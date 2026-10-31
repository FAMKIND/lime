//! Handing a band's publishing to another owner (LIME-275b). A band is bound to its writer's account, not to a key of its own, so a hand-over moves the
//! writer from one teacher to another:
//!
//! 1. **Offer.** The band's writer offers it to one of the band's owners (the server also checks: never the writer's own profile space) and sends a small
//!    `jam.handover.offer` over Olm. Nothing moves yet.
//! 2. **Accept.** The owner's phone says yes (`jam.handover.accept`). Only then does the old publisher's phone build the **bundle** and send it over Olm,
//!    in pieces of a size one item may have: the jam's state (title, about, topics, tiers, series), the subscriber list, the archive's index (each post's blob
//!    and the key that opens it), the community requests that wait, and the old publisher's **signed `jam.handover`**.
//! 3. **Take over.** When everything is in, the new publisher's phone asks the server to move the band (`handover_accept`), and only then becomes the writer:
//!    the band is `mine`, its creation time is now (so it never turns into their own profile space), the old publisher is a members-tier reader, the
//!    subscribers are told (`jam.handover`, with the old publisher's signed proof), and fresh tier sessions are made and handed out. The old sessions do not
//!    move, and old posts keep their credit (they are blobs with their own keys).
//! 4. **Let go.** The old publisher's phone is told (`jam.handover.done`), tells its own subscribers, then forgets the subscriber list and its sessions, and
//!    keeps reading and editing as an owner.
//!
//! A subscriber follows a hand-over only when the **current** writer sends it, or when the **new** writer sends it with the current writer's signed proof
//! (so the new writer's keys can arrive first without being refused); a proof is checked against the master key pinned for the writer, and never replayed
//! (`jams.handover_hlc`). Handing it back is the same in reverse.

use super::jam::{queue_op, signed_op};
use super::*;
use crate::store::jam as jam_store;

/// Subscribers per bundle item (an item may not exceed 64 KB).
const SUBS_PER_OP: usize = 200;
/// Posts per bundle item (the archive's index, as `jam.index`).
const POSTS_PER_OP: usize = 100;
const JOINS_PER_OP: usize = 200;

/// One hand-over this phone is part of.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct HandoverInfo {
    pub jam_id: String,
    pub title: String,
    /// The other person: who I offered it to, or who offered it to me.
    pub peer: String,
    /// `true` when I am handing it over.
    pub outgoing: bool,
    /// Outgoing: `offered` (waiting for them), `accepted` (they said yes; the bundle goes next), `sent` (waiting for them to take over).
    /// Incoming: `offered` (my answer is needed), `accepted` (waiting for the bundle), `ready` (everything is here; the take-over is next).
    pub state: String,
}

struct Handover {
    dir: String,
    peer: String,
    state: String,
    proof: Option<String>,
    need_subs: Option<i64>,
    need_posts: Option<i64>,
}

fn handover(conn: &Connection, jam_id: &str) -> Result<Option<Handover>, StoreError> {
    conn.query_row("SELECT dir, peer, state, proof, need_subs, need_posts FROM jam_handovers WHERE jam_id = ?1", params![jam_id], |r| {
        Ok(Handover { dir: r.get(0)?, peer: r.get(1)?, state: r.get(2)?, proof: r.get(3)?, need_subs: r.get(4)?, need_posts: r.get(5)? })
    })
    .optional()
    .map_err(db_err)
}

fn put_handover(conn: &Connection, jam_id: &str, dir: &str, peer: &str, state: &str, now: i64) -> Result<(), StoreError> {
    conn.execute("INSERT OR REPLACE INTO jam_handovers (jam_id, dir, peer, state, at) VALUES (?1, ?2, ?3, ?4, ?5)", params![jam_id, dir, peer, state, now]).map_err(db_err)?;
    Ok(())
}

fn set_state(conn: &Connection, jam_id: &str, state: &str) -> Result<(), StoreError> {
    conn.execute("UPDATE jam_handovers SET state = ?2 WHERE jam_id = ?1", params![jam_id, state]).map_err(db_err)?;
    Ok(())
}

fn drop_handover(conn: &Connection, jam_id: &str) -> Result<(), StoreError> {
    conn.execute("DELETE FROM jam_handovers WHERE jam_id = ?1", params![jam_id]).map_err(db_err)?;
    Ok(())
}

/// What a half-received bundle left behind on a phone that is not the publisher: the subscriber list must not stay.
fn forget_received_list(conn: &Connection, jam_id: &str) -> Result<(), StoreError> {
    conn.execute("DELETE FROM jam_subscribers WHERE jam_id = ?1 AND EXISTS (SELECT 1 FROM jams WHERE jam_id = ?1 AND mine = 0)", params![jam_id]).map_err(db_err)?;
    Ok(())
}

#[uniffi::export]
impl LimeStore {
    /// Offers MY band's publishing to one of its owners. The server refuses a profile space (`own_space`) and a teacher with no space of their own
    /// (`no_space`); nothing moves until they accept.
    pub fn offer_handover(&self, transport: Arc<dyn Transport>, auth_token: String, jam_id: String, to_user: String) -> Result<(), StoreError> {
        let state = self.load_or_create_account()?;
        let me = self.registered_user(&state)?;
        let now = now_ms();
        let title = self.with_conn(|conn| {
            let jam = jam_store::get(conn, &jam_id)?.filter(|j| j.mine && j.writer == me && !j.ended).ok_or(StoreError::Rejected)?;
            // Never my own profile space; only to another owner of the band; not while a bundle is already on its way.
            if to_user == me || jam_store::own_space(conn)?.as_deref() == Some(jam_id.as_str()) || !self.is_org_owner(conn, &jam_id, &to_user) {
                return Err(StoreError::Rejected);
            }
            if handover(conn, &jam_id)?.is_some_and(|h| h.dir == "out" && h.state == "sent") {
                return Err(StoreError::Rejected);
            }
            Ok(jam.title)
        })?;
        let (status, _) = call(&transport, Some(&auth_token), "jam-page", &json!({ "action": "handover_offer", "jam_id": jam_id, "new_writer_id": to_user }))?;
        if status == 409 {
            return Err(StoreError::Rejected);
        }
        check(status)?;
        self.with_conn(|conn| {
            put_handover(conn, &jam_id, "out", &to_user, "offered", now)?;
            let op = signed_op(conn, &state, "jam.handover.offer", &jam_id, None, json!({ "jam_id": jam_id, "title": title }), now)?;
            queue_op(conn, &jam_id, &to_user, &op)
        })
    }

    /// Takes MY offer back, as long as the bundle has not gone.
    pub fn cancel_handover(&self, transport: Arc<dyn Transport>, auth_token: String, jam_id: String) -> Result<(), StoreError> {
        let state = self.load_or_create_account()?;
        let now = now_ms();
        let peer = self.with_conn(|conn| match handover(conn, &jam_id)? {
            Some(h) if h.dir == "out" && matches!(h.state.as_str(), "offered" | "accepted") => Ok(h.peer),
            _ => Err(StoreError::Rejected),
        })?;
        let (status, _) = call(&transport, Some(&auth_token), "jam-page", &json!({ "action": "handover_cancel", "jam_id": jam_id }))?;
        if status != 404 {
            check(status)?;
        }
        self.with_conn(|conn| {
            drop_handover(conn, &jam_id)?;
            let op = signed_op(conn, &state, "jam.handover.cancel", &jam_id, None, json!({ "jam_id": jam_id }), now)?;
            queue_op(conn, &jam_id, &peer, &op)
        })
    }

    /// I say yes to an offer made to me. The bundle comes next; I become the publisher when it is all here.
    pub fn accept_handover(&self, jam_id: String) -> Result<(), StoreError> {
        let state = self.load_or_create_account()?;
        let now = now_ms();
        self.with_conn(|conn| {
            let Some(h) = handover(conn, &jam_id)?.filter(|h| h.dir == "in" && h.state == "offered") else { return Err(StoreError::Rejected) };
            set_state(conn, &jam_id, "accepted")?;
            let op = signed_op(conn, &state, "jam.handover.accept", &jam_id, None, json!({ "jam_id": jam_id }), now)?;
            queue_op(conn, &jam_id, &h.peer, &op)
        })
    }

    /// I say no to an offer made to me (before I said yes, or while the bundle is arriving: what arrived is forgotten).
    pub fn decline_handover(&self, transport: Arc<dyn Transport>, auth_token: String, jam_id: String) -> Result<(), StoreError> {
        let state = self.load_or_create_account()?;
        let now = now_ms();
        let peer = self.with_conn(|conn| match handover(conn, &jam_id)? {
            Some(h) if h.dir == "in" && matches!(h.state.as_str(), "offered" | "accepted") => Ok(h.peer),
            _ => Err(StoreError::Rejected),
        })?;
        let (status, _) = call(&transport, Some(&auth_token), "jam-page", &json!({ "action": "handover_decline", "jam_id": jam_id }))?;
        if status != 404 {
            check(status)?;
        }
        self.with_conn(|conn| {
            drop_handover(conn, &jam_id)?;
            forget_received_list(conn, &jam_id)?;
            let op = signed_op(conn, &state, "jam.handover.decline", &jam_id, None, json!({ "jam_id": jam_id }), now)?;
            queue_op(conn, &jam_id, &peer, &op)
        })
    }

    /// The hand-overs this phone is part of right now (waiting for an answer, or on their way).
    pub fn list_handovers(&self) -> Result<Vec<HandoverInfo>, StoreError> {
        self.with_conn(|conn| {
            let mut statement = conn
                .prepare(
                    "SELECT h.jam_id, COALESCE(j.title, ''), h.peer, h.dir, h.state FROM jam_handovers h LEFT JOIN jams j ON j.jam_id = h.jam_id
                     WHERE h.state <> 'live' ORDER BY h.at, h.jam_id",
                )
                .map_err(db_err)?;
            let rows = statement
                .query_map([], |r| Ok(HandoverInfo { jam_id: r.get(0)?, title: r.get(1)?, peer: r.get(2)?, outgoing: r.get::<_, String>(3)? == "out", state: r.get(4)? }))
                .map_err(db_err)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(db_err)?;
            Ok(rows)
        })
    }
}

// ---------------------------------------------------------------- receiving

impl LimeStore {
    /// The signed hand-over the new publisher of this band carries (set when they took over), for their first keys.
    pub(super) fn live_handover_proof(conn: &Connection, jam_id: &str) -> Result<Option<Value>, StoreError> {
        let proof: Option<Option<String>> = conn
            .query_row("SELECT proof FROM jam_handovers WHERE jam_id = ?1 AND dir = 'in' AND state = 'live'", params![jam_id], |r| r.get(0))
            .optional()
            .map_err(db_err)?;
        Ok(proof.flatten().and_then(|p| serde_json::from_str(&p).ok()))
    }

    /// Whether `proof` is the band's current writer's own signed hand-over of this band to `new_writer`: genuine, for this band, newer than any hand-over
    /// accepted before, and from the master key pinned for the writer. Gives the proof's clock.
    fn handover_proof_clock(conn: &Connection, jam: &jam_store::JamRow, new_writer: &str, proof: &Value) -> Result<Option<String>, StoreError> {
        let (Some(op), Some(cert)) = (proof.get("op").and_then(Op::from_json), proof.get("cert").and_then(SenderCert::from_json)) else { return Ok(None) };
        let held: String = conn.query_row("SELECT handover_hlc FROM jams WHERE jam_id = ?1", params![jam.jam_id], |r| r.get(0)).map_err(db_err)?;
        let text = |k: &str| op.payload.get(k).and_then(Value::as_str);
        if op.op_type != "jam.handover"
            || op.conversation_id != jam_store::conversation_id(&jam.jam_id)
            || text("jam_id") != Some(jam.jam_id.as_str())
            || text("new_writer") != Some(new_writer)
            || op.hlc.as_str() <= held.as_str()
            || !cert.verify()
            || !op.verify(&cert.signing_key)
        {
            return Ok(None);
        }
        let pinned: Option<String> = conn.query_row("SELECT master_key FROM peers WHERE user_id = ?1", params![jam.writer], |r| r.get(0)).optional().map_err(db_err)?;
        Ok(pinned.filter(|key| *key == cert.master_key).map(|_| op.hlc.clone()))
    }

    /// An op of the new publisher that carries the old publisher's signed hand-over (their first keys): the hand-over is followed first, so the op is
    /// judged as the writer's.
    pub(super) fn adopt_handover_proof(&self, conn: &Connection, jam: Option<jam_store::JamRow>, sender: &str, op: &Op) -> Result<Option<jam_store::JamRow>, StoreError> {
        let Some(row) = jam.as_ref().filter(|j| !j.mine && j.writer != sender && op.op_type == "jam.session") else { return Ok(jam) };
        let Some(proof) = op.payload.get("proof").filter(|p| p.is_object()) else { return Ok(jam) };
        let Some(clock) = Self::handover_proof_clock(conn, row, sender, proof)? else { return Ok(jam) };
        conn.execute("UPDATE jams SET writer = ?2, handover_hlc = ?3 WHERE jam_id = ?1", params![row.jam_id, sender, clock]).map_err(db_err)?;
        jam_store::get(conn, &row.jam_id)
    }

    #[allow(clippy::too_many_arguments)] // the context of one item
    pub(super) fn apply_handover_op(&self, conn: &Connection, state: &AccountState, me: &str, sender: &str, op: &Op, jam: Option<jam_store::JamRow>, now: i64) -> Result<(), StoreError> {
        let Some(jam) = jam else { return Ok(()) };
        let jam_id = jam.jam_id.clone();
        let text = |k: &str| op.payload.get(k).and_then(Value::as_str);
        let row = handover(conn, &jam_id)?;
        match op.op_type.as_str() {
            // A band's writer offers it to me (I must be one of its owners): kept to answer.
            "jam.handover.offer" => {
                if jam.mine || jam.writer != sender || sender == me || !self.is_org_owner(conn, &jam_id, me) || row.as_ref().is_some_and(|h| h.dir == "in" && matches!(h.state.as_str(), "accepted" | "ready")) {
                    return Ok(());
                }
                put_handover(conn, &jam_id, "in", sender, "offered", now)
            }
            // The owner I offered it to says yes: the bundle goes at the next pass.
            "jam.handover.accept" => {
                if row.is_some_and(|h| h.dir == "out" && h.peer == sender && h.state == "offered") {
                    set_state(conn, &jam_id, "accepted")?;
                }
                Ok(())
            }
            "jam.handover.decline" => {
                if row.is_some_and(|h| h.dir == "out" && h.peer == sender && matches!(h.state.as_str(), "offered" | "accepted")) {
                    drop_handover(conn, &jam_id)?;
                }
                Ok(())
            }
            "jam.handover.cancel" => {
                if row.is_some_and(|h| h.dir == "in" && h.peer == sender && matches!(h.state.as_str(), "offered" | "accepted")) {
                    drop_handover(conn, &jam_id)?;
                    forget_received_list(conn, &jam_id)?;
                }
                Ok(())
            }
            "jam.handover.bundle" => {
                if !row.is_some_and(|h| h.dir == "in" && h.peer == sender && h.state == "accepted") {
                    return Ok(());
                }
                if jam.mine || jam.writer != sender {
                    return Ok(());
                }
                self.import_bundle_part(conn, me, sender, op, &jam)?;
                Self::note_bundle_ready(conn, &jam_id)
            }
            // The new publisher has taken over: I tell my subscribers (they follow the writer's word), then let go.
            "jam.handover.done" => {
                if !row.is_some_and(|h| h.dir == "out" && h.peer == sender && h.state == "sent") || !jam.mine || jam.writer != me {
                    return Ok(());
                }
                self.let_go(conn, state, &jam, sender, now)
            }
            // A subscriber follows the new writer: from the current writer, or from the new writer with the current writer's signed proof.
            _ => {
                if jam.mine {
                    return Ok(());
                }
                let Some(new_writer) = text("new_writer").filter(|w| !w.is_empty() && w.len() <= 64) else { return Ok(()) };
                let held: String = conn.query_row("SELECT handover_hlc FROM jams WHERE jam_id = ?1", params![jam_id], |r| r.get(0)).map_err(db_err)?;
                let clock = if sender == jam.writer && new_writer != sender {
                    (op.hlc.as_str() > held.as_str()).then(|| op.hlc.clone())
                } else if sender == new_writer {
                    match op.payload.get("proof").filter(|p| p.is_object()) {
                        Some(proof) => Self::handover_proof_clock(conn, &jam, new_writer, proof)?,
                        None => None,
                    }
                } else {
                    None
                };
                if let Some(clock) = clock {
                    conn.execute("UPDATE jams SET writer = ?2, handover_hlc = ?3 WHERE jam_id = ?1", params![jam_id, new_writer, clock]).map_err(db_err)?;
                }
                Ok(())
            }
        }
    }

    fn import_bundle_part(&self, conn: &Connection, me: &str, sender: &str, op: &Op, jam: &jam_store::JamRow) -> Result<(), StoreError> {
        let jam_id = jam.jam_id.as_str();
        let payload = &op.payload;
        match payload.get("part").and_then(Value::as_str) {
            Some("state") => {
                // The signed hand-over must really be the old publisher's, to me, before anything of the bundle counts.
                let Some(proof) = payload.get("proof").filter(|p| p.is_object()) else { return Ok(()) };
                if Self::handover_proof_clock(conn, jam, me, proof)?.is_none() {
                    return Ok(());
                }
                if let Some(state_value) = payload.get("state") {
                    self.apply_jam_state(conn, jam, state_value, &op.hlc, true)?;
                }
                let num = |k: &str| payload.get(k).and_then(Value::as_i64).filter(|n| (0..=100_000).contains(n));
                conn.execute(
                    "UPDATE jam_handovers SET proof = ?2, need_subs = ?3, need_posts = ?4 WHERE jam_id = ?1",
                    params![jam_id, proof.to_string(), num("subscribers"), num("posts")],
                )
                .map_err(db_err)?;
                Ok(())
            }
            Some("subscribers") => {
                for entry in payload.get("list").and_then(Value::as_array).into_iter().flatten().take(SUBS_PER_OP) {
                    let text = |k: &str| entry.get(k).and_then(Value::as_str);
                    let (Some(user), Some(tier), Some(status), Some(since)) =
                        (text("user").filter(|u| !u.is_empty() && u.len() <= 64), text("tier").filter(|t| jam_store::valid_tier(t)), text("status").filter(|s| matches!(*s, "active" | "removed")), entry.get("since").and_then(Value::as_i64))
                    else {
                        continue;
                    };
                    if user == me {
                        continue;
                    }
                    conn.execute(
                        "INSERT INTO jam_subscribers (jam_id, user_id, since, tier, status) VALUES (?1, ?2, ?3, ?4, ?5)
                         ON CONFLICT (jam_id, user_id) DO UPDATE SET since = ?3, tier = ?4, status = ?5",
                        params![jam_id, user, since, tier, status],
                    )
                    .map_err(db_err)?;
                }
                Ok(())
            }
            Some("posts") => self.store_jam_index(conn, jam_id, sender, payload),
            Some("joins") => {
                for entry in payload.get("list").and_then(Value::as_array).into_iter().flatten().take(JOINS_PER_OP) {
                    if let Some(user) = entry.get("user").and_then(Value::as_str).filter(|u| !u.is_empty() && u.len() <= 64 && *u != me) {
                        conn.execute("INSERT OR IGNORE INTO community_joins (jam_id, user_id, state, at) VALUES (?1, ?2, 'pending', ?3)", params![jam_id, user, now_ms()]).map_err(db_err)?;
                    }
                }
                Ok(())
            }
            _ => Ok(()),
        }
    }

    /// Everything the bundle named is here: the take-over can follow.
    fn note_bundle_ready(conn: &Connection, jam_id: &str) -> Result<(), StoreError> {
        let Some(h) = handover(conn, jam_id)?.filter(|h| h.dir == "in" && h.state == "accepted") else { return Ok(()) };
        let (Some(need_subs), Some(need_posts), Some(_)) = (h.need_subs, h.need_posts, h.proof.as_ref()) else { return Ok(()) };
        let subs: i64 = conn.query_row("SELECT COUNT(*) FROM jam_subscribers WHERE jam_id = ?1", params![jam_id], |r| r.get(0)).map_err(db_err)?;
        let posts = jam_store::index_for(conn, jam_id, jam_store::TIER_MEMBERS)?.len() as i64;
        if subs >= need_subs && posts >= need_posts {
            set_state(conn, jam_id, "ready")?;
        }
        Ok(())
    }

    /// The old publisher, told the new one has taken over: my subscribers hear it from me, then the list and the sessions go.
    fn let_go(&self, conn: &Connection, state: &AccountState, jam: &jam_store::JamRow, new_writer: &str, now: i64) -> Result<(), StoreError> {
        let jam_id = jam.jam_id.as_str();
        let announce = signed_op(conn, state, "jam.handover", jam_id, None, json!({ "jam_id": jam_id, "new_writer": new_writer }), now)?;
        let mut statement = conn.prepare("SELECT user_id FROM jam_subscribers WHERE jam_id = ?1 AND status = 'active' AND user_id <> ?2").map_err(db_err)?;
        let people = statement.query_map(params![jam_id, new_writer], |r| r.get::<_, String>(0)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
        for user in people {
            queue_op(conn, jam_id, &user, &announce)?;
        }
        conn.execute("UPDATE jams SET mine = 0, writer = ?2, handover_hlc = ?3, status = 'active' WHERE jam_id = ?1", params![jam_id, new_writer, announce.hlc]).map_err(db_err)?;
        conn.execute("DELETE FROM jam_subscribers WHERE jam_id = ?1", params![jam_id]).map_err(db_err)?;
        conn.execute("DELETE FROM jam_wire_outbox WHERE jam_id = ?1", params![jam_id]).map_err(db_err)?;
        jam_store::delete_outbound(conn, jam_id)?;
        drop_handover(conn, jam_id)
    }
}

// ---------------------------------------------------------------- the pass

impl LimeStore {
    /// Once per delivery pass: the bundle goes when the other owner said yes and nothing of mine is still on its way to the subscribers; the take-over
    /// happens when the bundle is all here and the server has moved the band.
    pub(super) fn process_handovers(&self, transport: &Arc<dyn Transport>, token: &str, state: &AccountState, me: &str) {
        let Ok(rows) = self.with_conn(|conn| {
            let mut statement = conn.prepare("SELECT jam_id, dir, state, peer FROM jam_handovers WHERE state IN ('accepted', 'ready')").map_err(db_err)?;
            let rows = statement.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, String>(2)?, r.get::<_, String>(3)?))).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
            Ok(rows)
        }) else {
            return;
        };
        let now = now_ms();
        for (jam_id, dir, row_state, peer) in rows {
            if dir == "out" && row_state == "accepted" {
                let _ = self.with_conn(|conn| self.send_bundle(conn, state, me, &jam_id, &peer, now));
            } else if dir == "in" && row_state == "ready" {
                match call(transport, Some(token), "jam-page", &json!({ "action": "handover_accept", "jam_id": jam_id })) {
                    Ok((status, _)) if (200..300).contains(&status) => {
                        if self.with_conn(|conn| self.take_over(conn, state, me, &jam_id, &peer, now)).is_ok() {
                            // The colour, cover and picture are on the page: the new publisher's phone keeps them too.
                            let _ = self.refresh_jam_style(transport.clone(), token.to_owned(), jam_id.clone());
                            let _ = self.refresh_jam_picture(transport.clone(), token.to_owned(), jam_id.clone());
                        }
                    }
                    // The offer is gone (taken back, or the band moved on): what arrived is forgotten.
                    Ok((404 | 409, _)) => {
                        let _ = self.with_conn(|conn| {
                            drop_handover(conn, &jam_id)?;
                            forget_received_list(conn, &jam_id)
                        });
                    }
                    _ => {}
                }
            }
        }
    }

    /// The old publisher: the bundle, once nothing of the band's is still on its way out.
    fn send_bundle(&self, conn: &Connection, state: &AccountState, me: &str, jam_id: &str, peer: &str, now: i64) -> Result<(), StoreError> {
        let Some(jam) = jam_store::get(conn, jam_id)?.filter(|j| j.mine && j.writer == me) else { return Ok(()) };
        let waiting: i64 = conn
            .query_row(
                "SELECT (SELECT COUNT(*) FROM jam_wire_outbox WHERE jam_id = ?1) + (SELECT COUNT(*) FROM jam_posts WHERE jam_id = ?1 AND uploaded = 0 AND deleted_at IS NULL)",
                params![jam_id],
                |r| r.get(0),
            )
            .map_err(db_err)?;
        if waiting > 0 {
            return Ok(());
        }
        let proof_op = signed_op(conn, state, "jam.handover", jam_id, None, json!({ "jam_id": jam_id, "new_writer": peer }), now)?;
        let proof = json!({ "op": proof_op.to_json(), "cert": state.cert().to_json() });

        let mut statement = conn.prepare("SELECT user_id, since, tier, status FROM jam_subscribers WHERE jam_id = ?1 AND status IN ('active', 'removed') AND user_id <> ?2 ORDER BY since, user_id").map_err(db_err)?;
        let subscribers = statement
            .query_map(params![jam_id, peer], |r| Ok(json!({ "user": r.get::<_, String>(0)?, "since": r.get::<_, i64>(1)?, "tier": r.get::<_, String>(2)?, "status": r.get::<_, String>(3)? })))
            .map_err(db_err)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(db_err)?;
        let index = jam_store::index_for(conn, jam_id, jam_store::TIER_MEMBERS)?;
        let part = |conn: &Connection, body: Value| -> Result<(), StoreError> {
            let op = signed_op(conn, state, "jam.handover.bundle", jam_id, None, body, now)?;
            queue_op(conn, jam_id, peer, &op)
        };
        part(
            conn,
            json!({
                "jam_id": jam_id,
                "part": "state",
                "proof": proof,
                "subscribers": subscribers.len(),
                "posts": index.len(),
                "state": { "writer": jam.writer, "title": jam.title, "about": jam.about, "topics": jam.topics, "tiers": jam.tiers, "state_hlc": jam.state_hlc, "community": jam.community, "series": super::series::metas_json(conn, jam_id)? },
            }),
        )?;
        for chunk in subscribers.chunks(SUBS_PER_OP) {
            part(conn, json!({ "jam_id": jam_id, "part": "subscribers", "list": chunk }))?;
        }
        for chunk in index.chunks(POSTS_PER_OP) {
            let posts: Vec<Value> = chunk
                .iter()
                .map(|(post_id, post_tier, title, created, blob, kind, subtitle)| {
                    json!({ "post_id": post_id, "tier": post_tier, "kind": kind, "subtitle": subtitle, "title": title, "created": created,
                            "blob_id": blob.blob_id, "key": blob.key, "sha256": blob.sha256, "size": blob.size })
                })
                .collect();
            part(conn, json!({ "jam_id": jam_id, "part": "posts", "posts": posts }))?;
        }
        // The people waiting to join the community chat.
        let mut statement = conn.prepare("SELECT user_id FROM community_joins WHERE jam_id = ?1 AND state = 'pending' AND user_id <> ''").map_err(db_err)?;
        let waiting_joins = statement.query_map(params![jam_id], |r| Ok(json!({ "user": r.get::<_, String>(0)? }))).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
        for chunk in waiting_joins.chunks(JOINS_PER_OP) {
            part(conn, json!({ "jam_id": jam_id, "part": "joins", "list": chunk }))?;
        }
        set_state(conn, jam_id, "sent")
    }

    /// The new publisher, the server having moved the band: this phone is its writer now.
    fn take_over(&self, conn: &Connection, state: &AccountState, me: &str, jam_id: &str, old_writer: &str, now: i64) -> Result<(), StoreError> {
        let h = handover(conn, jam_id)?.ok_or(StoreError::Rejected)?;
        let proof: Value = h.proof.as_deref().and_then(|p| serde_json::from_str(p).ok()).ok_or(StoreError::BadMessage)?;
        let proof_hlc = proof.get("op").and_then(Op::from_json).map(|o| o.hlc).unwrap_or_default();
        conn.execute("UPDATE jams SET writer = ?2, mine = 1, created = ?3, status = 'active', handover_hlc = ?4 WHERE jam_id = ?1", params![jam_id, me, now, proof_hlc]).map_err(db_err)?;
        conn.execute("DELETE FROM jam_subscribers WHERE jam_id = ?1 AND user_id = ?2", params![jam_id, me]).map_err(db_err)?;
        // The old publisher keeps reading what the band publishes, as one of its members.
        conn.execute(
            "INSERT INTO jam_subscribers (jam_id, user_id, since, tier, status) VALUES (?1, ?2, ?3, 'members', 'active')
             ON CONFLICT (jam_id, user_id) DO UPDATE SET tier = 'members', status = 'active'",
            params![jam_id, old_writer, now],
        )
        .map_err(db_err)?;
        jam_store::mark_page_dirty(conn, jam_id)?;
        conn.execute("UPDATE jam_handovers SET state = 'live' WHERE jam_id = ?1", params![jam_id]).map_err(db_err)?;

        // The subscribers hear it from me with the old publisher's signed word, then get my fresh keys (which carry the same proof).
        let announce = signed_op(conn, state, "jam.handover", jam_id, None, json!({ "jam_id": jam_id, "new_writer": me, "proof": proof }), now)?;
        let mut statement = conn.prepare("SELECT user_id FROM jam_subscribers WHERE jam_id = ?1 AND status = 'active'").map_err(db_err)?;
        let people = statement.query_map(params![jam_id], |r| r.get::<_, String>(0)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
        for user in people {
            queue_op(conn, jam_id, &user, &announce)?;
        }
        let done = signed_op(conn, state, "jam.handover.done", jam_id, None, json!({ "jam_id": jam_id }), now)?;
        queue_op(conn, jam_id, old_writer, &done)?;
        let jam = jam_store::get(conn, jam_id)?.ok_or(StoreError::Rejected)?;
        let mut tiers = jam.tiers.clone();
        if !tiers.iter().any(|t| t == jam_store::TIER_MEMBERS) {
            tiers.push(jam_store::TIER_MEMBERS.to_owned());
        }
        for tier in tiers {
            self.ensure_jam_session(conn, state, jam_id, &tier, now)?;
        }
        Ok(())
    }
}
