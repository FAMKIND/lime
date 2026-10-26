//! A draft written with others (LIME-233b, DESIGN-22 §2): who may write it, how a change reaches them instantly, and how nothing is lost.
//!
//! **Two paths for one draft.**
//! - **Instant.** Each shared draft has a random 128-bit *channel id* and a 32-byte *draft key*. Keystrokes and cursors are one message each, `[nonce |
//!   AES-256-GCM(key derived from the draft key, aad = the channel id)]` over a signed [`SealedInner`] (the author's device certificate and signature,
//!   exactly as a chat message), sent on a public Realtime broadcast topic `draft:<channel id>` joined with the public API key only (the iOS adapter).
//!   Anything that does not decrypt, verify, name a current author or chain to the pinned master key is dropped. Nothing is stored by the relay.
//! - **Durable.** The same changes go as `draft.change` ops over the ordinary encrypted mailbox (one per author, sealed like any control op, with 232's
//!   save-before-send), at most one batch every 5 seconds per draft; `draft.hello {heads}` (every minute while open) makes a phone that missed
//!   something ask for it; `draft.invite` carries the draft id, channel, key and a snapshot to an accepted co-author.
//!
//! With at most five authors the durable path is pairwise (one sealed op per author) rather than a Megolm group: the same encryption and signing, no
//! second group machinery, and the rate (12 batches a minute) is the same.
//!
//! What each party learns: the Realtime relay sees that some addresses are connected to channel X at the same time and the sizes and times of encrypted
//! messages (not accounts, not text); lime's mailbox sees the ordinary sealed traffic among the authors. Subscribers see only published versions.

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use hkdf::Hkdf;
use sha2::Sha256;

use super::*;
use crate::drafts::DraftPatch;

pub(super) const MAX_AUTHORS: usize = 5;
const FLUSH_EVERY_MS: i64 = 5_000;
const HELLO_EVERY_MS: i64 = 60_000;
const LIVE_OP: &str = "draft.live";

/// Who writes a draft and in what state.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct DraftAuthor {
    pub user_id: String,
    /// `active`, `removed` or `left`.
    pub status: String,
    pub is_writer: bool,
}

/// A shared draft's instant channel, for the adapter to join.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct DraftChannel {
    pub draft_id: String,
    pub channel_id: String,
}

/// Where an author's caret and selection are (positions in characters within their blocks).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct DraftPresence {
    /// Where the caret is: `title`, `subtitle` or `body` (empty means body). In the title and subtitle `offset` counts characters of that text.
    pub field: String,
    pub block_id: String,
    pub offset: u32,
    /// The other end of a selection (empty: no selection).
    pub end_block_id: String,
    pub end_offset: u32,
    pub typing: bool,
    /// They left the editor.
    pub away: bool,
}

/// What a message on the instant channel was.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct DraftInstantEvent {
    pub draft_id: String,
    pub from_user: String,
    pub patches: Vec<DraftPatch>,
    pub presence: Option<DraftPresence>,
}

fn b64(bytes: &[u8]) -> String {
    vodozemac::base64_encode(bytes)
}

fn unb64(text: &str) -> Option<Vec<u8>> {
    vodozemac::base64_decode(text).ok()
}

fn instant_key(draft_key: &[u8]) -> Option<Aes256Gcm> {
    let mut okm = [0u8; 32];
    Hkdf::<Sha256>::new(None, draft_key).expand(b"lime-draft-instant-v1", &mut okm).ok()?;
    Aes256Gcm::new_from_slice(&okm).ok()
}

fn heads_json(heads: &[String]) -> String {
    json!(heads).to_string()
}

fn heads_of(text: &str) -> Vec<String> {
    serde_json::from_str(text).unwrap_or_default()
}

pub(crate) fn active_authors(conn: &Connection, draft_id: &str) -> Result<Vec<String>, StoreError> {
    let mut st = conn.prepare("SELECT user_id FROM draft_authors WHERE draft_id = ?1 AND status = 'active' ORDER BY user_id").map_err(db_err)?;
    let rows = st.query_map(params![draft_id], |r| r.get::<_, String>(0)).map_err(db_err)?;
    rows.collect::<Result<_, _>>().map_err(db_err)
}

pub(super) fn enqueue(conn: &Connection, draft_id: &str, to: &str, op_type: &str, payload: Value, now: i64) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO draft_outbox (draft_id, to_user, op_type, payload, created_at) VALUES (?1, ?2, ?3, ?4, ?5)",
        params![draft_id, to, op_type, payload.to_string(), now],
    )
    .map_err(db_err)?;
    Ok(())
}

pub(super) fn row_keys(conn: &Connection, draft_id: &str) -> Result<Option<(String, Vec<u8>, String)>, StoreError> {
    conn.query_row("SELECT channel_id, draft_key, writer FROM drafts WHERE draft_id = ?1 AND channel_id IS NOT NULL AND draft_key IS NOT NULL", params![draft_id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))
        .optional()
        .map_err(db_err)
}

impl LimeStore {
    fn me_registered(&self) -> Result<String, StoreError> {
        let state = self.load_or_create_account()?;
        state.user_id.clone().filter(|_| state.registered).ok_or(StoreError::NotRegistered)
    }
}

#[uniffi::export]
impl LimeStore {
    /// The writer adds co-authors to a draft (accepted contacts, at most four besides the writer). A new author is sent an invitation with the draft's
    /// channel, key and a snapshot. Calling it again with more people adds them; people already in stay.
    pub fn share_draft(&self, draft_id: String, authors: Vec<String>) -> Result<(), StoreError> {
        let me = self.me_registered()?;
        let now = now_ms();
        let mut wanted: Vec<String> = authors.into_iter().filter(|a| *a != me).collect();
        wanted.sort();
        wanted.dedup();
        self.with_conn(|conn| {
            let row: Option<Option<String>> = conn.query_row("SELECT writer FROM drafts WHERE draft_id = ?1", params![draft_id], |r| r.get(0)).optional().map_err(db_err)?;
            match row {
                None => return Err(StoreError::NotFound),
                Some(Some(writer)) if writer != me => return Err(StoreError::Rejected),
                _ => {}
            }
            for who in &wanted {
                let accepted: bool = conn.query_row("SELECT EXISTS (SELECT 1 FROM conversations WHERE id = ?1 AND request_state = 'accepted')", params![format!("dm:{who}")], |r| r.get(0)).map_err(db_err)?;
                if !accepted {
                    return Err(StoreError::Rejected);
                }
            }
            let existing = active_authors(conn, &draft_id)?;
            let total: std::collections::BTreeSet<String> = existing.iter().cloned().chain(wanted.iter().cloned()).chain(std::iter::once(me.clone())).collect();
            if total.len() > MAX_AUTHORS {
                return Err(StoreError::Rejected);
            }
            if row_keys(conn, &draft_id)?.is_none() {
                let channel: String = crate::store::delivery::random_key()[..16].iter().map(|b| format!("{b:02x}")).collect();
                conn.execute("UPDATE drafts SET channel_id = ?2, draft_key = ?3, writer = ?4 WHERE draft_id = ?1", params![draft_id, channel, crate::store::delivery::random_key(), me]).map_err(db_err)?;
            }
            conn.execute("INSERT OR IGNORE INTO draft_authors (draft_id, user_id, status) VALUES (?1, ?2, 'active')", params![draft_id, me]).map_err(db_err)?;
            let (channel, key, _) = row_keys(conn, &draft_id)?.ok_or(StoreError::NotFound)?;
            let (snapshot, heads) = self.with_draft_conn(conn, &draft_id, false, |d| Ok((d.save(), d.heads())))?;
            let mut invited = Vec::new();
            for who in &wanted {
                if existing.contains(who) {
                    continue;
                }
                conn.execute("INSERT OR REPLACE INTO draft_authors (draft_id, user_id, status) VALUES (?1, ?2, 'active')", params![draft_id, who]).map_err(db_err)?;
                invited.push(who.clone());
            }
            if !invited.is_empty() {
                conn.execute("UPDATE drafts SET durable_heads = ?2, instant_heads = ?2 WHERE draft_id = ?1", params![draft_id, heads_json(&heads)]).map_err(db_err)?;
            }
            let all = active_authors(conn, &draft_id)?;
            for who in existing.iter().filter(|u| **u != me && !invited.contains(u)) {
                if !invited.is_empty() {
                    enqueue(conn, &draft_id, who, "draft.authors", json!({ "draft_id": draft_id, "authors": all }), now)?;
                }
            }
            for who in &invited {
                enqueue(conn, &draft_id, who, "draft.invite", json!({ "draft_id": draft_id, "channel_id": channel, "key": b64(&key), "writer": me, "authors": all, "snapshot": b64(&snapshot) }), now)?;
            }
            Ok(())
        })
    }

    /// The writer takes a co-author out. They are sent nothing more; the key changes and the others are given the new one.
    pub fn remove_draft_author(&self, draft_id: String, user_id: String) -> Result<(), StoreError> {
        let me = self.me_registered()?;
        let now = now_ms();
        self.with_conn(|conn| {
            let (channel, _, writer) = row_keys(conn, &draft_id)?.ok_or(StoreError::NotFound)?;
            if writer != me || user_id == me {
                return Err(StoreError::Rejected);
            }
            conn.execute("UPDATE draft_authors SET status = 'removed' WHERE draft_id = ?1 AND user_id = ?2", params![draft_id, user_id]).map_err(db_err)?;
            conn.execute("DELETE FROM draft_outbox WHERE draft_id = ?1 AND to_user = ?2", params![draft_id, user_id]).map_err(db_err)?;
            let new_key = crate::store::delivery::random_key();
            conn.execute("UPDATE drafts SET draft_key = ?2 WHERE draft_id = ?1", params![draft_id, new_key]).map_err(db_err)?;
            let remaining = active_authors(conn, &draft_id)?;
            for who in remaining.iter().filter(|u| **u != me) {
                enqueue(conn, &draft_id, who, "draft.key", json!({ "draft_id": draft_id, "channel_id": channel, "key": b64(&new_key), "authors": remaining }), now)?;
            }
            enqueue(conn, &draft_id, &user_id, "draft.removed", json!({ "draft_id": draft_id }), now)?;
            Ok(())
        })
    }

    /// A co-author leaves a draft: the others are told, and this phone stops syncing it (the text stays here).
    pub fn leave_draft(&self, draft_id: String) -> Result<(), StoreError> {
        let me = self.me_registered()?;
        let now = now_ms();
        self.with_conn(|conn| {
            let (_, _, writer) = row_keys(conn, &draft_id)?.ok_or(StoreError::NotFound)?;
            if writer == me {
                return Err(StoreError::Rejected);
            }
            let others: Vec<String> = active_authors(conn, &draft_id)?.into_iter().filter(|u| *u != me).collect();
            conn.execute("UPDATE draft_authors SET status = 'left' WHERE draft_id = ?1 AND user_id = ?2", params![draft_id, me]).map_err(db_err)?;
            conn.execute("UPDATE drafts SET draft_key = NULL WHERE draft_id = ?1", params![draft_id]).map_err(db_err)?;
            conn.execute("DELETE FROM draft_outbox WHERE draft_id = ?1", params![draft_id]).map_err(db_err)?;
            for who in others {
                enqueue(conn, &draft_id, &who, "draft.leave", json!({ "draft_id": draft_id }), now)?;
            }
            Ok(())
        })
    }

    pub fn draft_authors(&self, draft_id: String) -> Result<Vec<DraftAuthor>, StoreError> {
        self.with_conn(|conn| {
            let writer: Option<String> = conn.query_row("SELECT writer FROM drafts WHERE draft_id = ?1", params![draft_id], |r| r.get(0)).optional().map_err(db_err)?.flatten();
            let mut st = conn.prepare("SELECT user_id, status FROM draft_authors WHERE draft_id = ?1 ORDER BY user_id").map_err(db_err)?;
            let rows = st.query_map(params![draft_id], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))).map_err(db_err)?;
            let rows: Vec<(String, String)> = rows.collect::<Result<_, _>>().map_err(db_err)?;
            Ok(rows.into_iter().map(|(user_id, status)| DraftAuthor { is_writer: writer.as_deref() == Some(user_id.as_str()), user_id, status }).collect())
        })
    }

    /// Drafts that arrived by invitation and have not been opened yet (for "Shem invited you to write …").
    pub fn unseen_draft_invites(&self) -> Result<Vec<String>, StoreError> {
        self.with_conn(|conn| {
            let mut st = conn.prepare("SELECT draft_id FROM drafts WHERE seen = 0 ORDER BY invited_at").map_err(db_err)?;
            let rows = st.query_map([], |r| r.get::<_, String>(0)).map_err(db_err)?;
            rows.collect::<Result<_, _>>().map_err(db_err)
        })
    }

    pub fn mark_draft_seen(&self, draft_id: String) -> Result<(), StoreError> {
        self.with_conn(|conn| conn.execute("UPDATE drafts SET seen = 1 WHERE draft_id = ?1", params![draft_id]).map(|_| ()).map_err(db_err))
    }

    /// The instant channels of the drafts I am writing in, for the adapter to join.
    pub fn draft_channels(&self) -> Result<Vec<DraftChannel>, StoreError> {
        let me = self.me_registered()?;
        self.with_conn(|conn| {
            let mut st = conn
                .prepare("SELECT d.draft_id, d.channel_id FROM drafts d JOIN draft_authors a ON a.draft_id = d.draft_id AND a.user_id = ?1 AND a.status = 'active' WHERE d.channel_id IS NOT NULL AND d.draft_key IS NOT NULL")
                .map_err(db_err)?;
            let rows = st.query_map(params![me], |r| Ok(DraftChannel { draft_id: r.get(0)?, channel_id: r.get(1)? })).map_err(db_err)?;
            rows.collect::<Result<_, _>>().map_err(db_err)
        })
    }

    /// Sends what is due on the durable path now (batches at most every 5 seconds per draft, hellos, invitations, key changes). The app calls it on a
    /// timer while a draft is open; a normal sync does it too.
    pub fn flush_drafts(&self, transport: Arc<dyn Transport>, auth_token: String) -> Result<u32, StoreError> {
        let _guard = self.lock_protocol();
        let mut state = self.load_or_create_account()?;
        let me = state.user_id.clone().filter(|_| state.registered).ok_or(StoreError::NotRegistered)?;
        Ok(self.deliver_drafts(&transport, &auth_token, &mut state, &me, now_ms()))
    }

    /// Asks the other authors for what I may have missed (the app calls it when a draft is opened; a minute-by-minute hello does it otherwise).
    pub fn draft_hello(&self, draft_id: String) -> Result<(), StoreError> {
        let me = self.me_registered()?;
        let now = now_ms();
        self.with_conn(|conn| self.queue_hello(conn, &draft_id, &me, now))
    }

    // ------------------------------------------------------------------------------------------- the instant path

    /// The changes made since the last instant message, as one wire message to broadcast; `None` when there are none.
    pub fn draft_instant_change(&self, draft_id: String) -> Result<Option<Vec<u8>>, StoreError> {
        let state = self.load_or_create_account()?;
        self.with_conn(|conn| {
            let Some((channel, key, _)) = row_keys(conn, &draft_id)? else { return Ok(None) };
            let last: String = conn.query_row("SELECT instant_heads FROM drafts WHERE draft_id = ?1", params![draft_id], |r| r.get(0)).map_err(db_err)?;
            let (bytes, heads) = self.with_draft_conn(conn, &draft_id, false, |d| {
                let now = d.heads();
                if now == heads_of(&last) {
                    return Ok((Vec::new(), now));
                }
                Ok((d.changes_since(&heads_of(&last)), now))
            })?;
            if bytes.is_empty() {
                return Ok(None);
            }
            conn.execute("UPDATE drafts SET instant_heads = ?2 WHERE draft_id = ?1", params![draft_id, heads_json(&heads)]).map_err(db_err)?;
            Ok(Some(self.make_instant(&state, &draft_id, &channel, &key, json!({ "k": "c", "b": b64(&bytes) }))?))
        })
    }

    /// My caret and selection, as one wire message to broadcast.
    pub fn draft_instant_presence(&self, draft_id: String, presence: DraftPresence) -> Result<Option<Vec<u8>>, StoreError> {
        let state = self.load_or_create_account()?;
        self.with_conn(|conn| {
            let Some((channel, key, _)) = row_keys(conn, &draft_id)? else { return Ok(None) };
            let payload = json!({ "k": "p", "fld": presence.field, "blk": presence.block_id, "off": presence.offset, "eblk": presence.end_block_id, "eoff": presence.end_offset, "typing": presence.typing, "away": presence.away });
            Ok(Some(self.make_instant(&state, &draft_id, &channel, &key, payload)?))
        })
    }

    /// A message that arrived on `channel_id`. `None` when it is dropped (not decryptable, not signed by a current author, not for a draft I write in).
    pub fn draft_instant_receive(&self, channel_id: String, wire: Vec<u8>) -> Result<Option<DraftInstantEvent>, StoreError> {
        let me = self.me_registered()?;
        self.with_conn(|conn| {
            let row: Option<(String, Vec<u8>)> = conn
                .query_row("SELECT draft_id, draft_key FROM drafts WHERE channel_id = ?1 AND draft_key IS NOT NULL", params![channel_id], |r| Ok((r.get(0)?, r.get(1)?)))
                .optional()
                .map_err(db_err)?;
            let Some((draft_id, key)) = row else { return Ok(None) };
            if wire.len() < 12 + 16 {
                return Ok(None);
            }
            let Some(cipher) = instant_key(&key) else { return Ok(None) };
            let Ok(plain) = cipher.decrypt(Nonce::from_slice(&wire[..12]), Payload { msg: &wire[12..], aad: channel_id.as_bytes() }) else { return Ok(None) };
            let Some(inner) = SealedInner::from_bytes(&plain) else { return Ok(None) };
            let cert = &inner.sender_cert;
            let from = inner.sender_user.clone();
            let pinned: Option<String> = conn.query_row("SELECT master_key FROM peers WHERE user_id = ?1", params![from], |r| r.get(0)).optional().map_err(db_err)?;
            let author = active_authors(conn, &draft_id)?.contains(&from);
            let valid = from != me
                && author
                && inner.sender_device == cert.device_id
                && inner.op.op_type == LIVE_OP
                && inner.op.conversation_id == draft_id
                && cert.verify()
                && inner.op.verify(&cert.signing_key)
                && pinned.as_deref() == Some(cert.master_key.as_str());
            if !valid {
                return Ok(None);
            }
            match inner.op.payload.get("k").and_then(Value::as_str) {
                Some("c") => {
                    let Some(bytes) = inner.op.payload.get("b").and_then(Value::as_str).and_then(unb64) else { return Ok(None) };
                    let patches = self.with_draft_conn(conn, &draft_id, false, |d| {
                        d.apply_changes(&bytes)?;
                        Ok(d.take_patches())
                    })?;
                    Ok(Some(DraftInstantEvent { draft_id, from_user: from, patches, presence: None }))
                }
                Some("p") => {
                    let p = &inner.op.payload;
                    let text = |k: &str| p.get(k).and_then(Value::as_str).unwrap_or_default().to_owned();
                    let num = |k: &str| p.get(k).and_then(Value::as_u64).unwrap_or(0) as u32;
                    let flag = |k: &str| p.get(k).and_then(Value::as_bool).unwrap_or(false);
                    let presence = DraftPresence { field: text("fld"), block_id: text("blk"), offset: num("off"), end_block_id: text("eblk"), end_offset: num("eoff"), typing: flag("typing"), away: flag("away") };
                    Ok(Some(DraftInstantEvent { draft_id, from_user: from, patches: Vec::new(), presence: Some(presence) }))
                }
                _ => Ok(None),
            }
        })
    }
}

impl LimeStore {
    /// One signed, encrypted instant message.
    pub(crate) fn make_instant(&self, state: &AccountState, draft_id: &str, channel: &str, key: &[u8], payload: Value) -> Result<Vec<u8>, StoreError> {
        let me = state.user_id.clone().filter(|_| state.registered).ok_or(StoreError::NotRegistered)?;
        let mut op = Op {
            op_id: new_id(),
            op_type: LIVE_OP.into(),
            conversation_id: draft_id.to_owned(),
            hlc: Hlc { wall: now_ms(), counter: 0 }.render(),
            parents: Vec::new(),
            payload,
            sig: String::new(),
        };
        op.sig = state.account.sign(op.signing_bytes()).to_base64();
        let inner = SealedInner { sender_user: me, sender_device: state.device_id.clone(), sender_cert: state.cert(), op }.to_bytes();
        let cipher = instant_key(key).ok_or(StoreError::BadMessage)?;
        let mut nonce = [0u8; 12];
        getrandom::getrandom(&mut nonce).map_err(|_| StoreError::BadMessage)?;
        let sealed = cipher.encrypt(Nonce::from_slice(&nonce), Payload { msg: &inner, aad: channel.as_bytes() }).map_err(|_| StoreError::BadMessage)?;
        let mut out = nonce.to_vec();
        out.extend_from_slice(&sealed);
        Ok(out)
    }

    fn queue_hello(&self, conn: &Connection, draft_id: &str, me: &str, now: i64) -> Result<(), StoreError> {
        if row_keys(conn, draft_id)?.is_none() {
            return Ok(());
        }
        let heads = self.with_draft_conn(conn, draft_id, false, |d| Ok(d.heads()))?;
        for who in active_authors(conn, draft_id)?.into_iter().filter(|u| u != me) {
            enqueue(conn, draft_id, &who, "draft.hello", json!({ "draft_id": draft_id, "heads": heads }), now)?;
        }
        conn.execute("UPDATE drafts SET last_hello_at = ?2 WHERE draft_id = ?1", params![draft_id, now]).map_err(db_err)?;
        Ok(())
    }

    /// Batches due changes and hellos into the outbox (at most one batch every 5 seconds per draft), then sends what is in it. Returns how many went.
    pub(crate) fn deliver_drafts(&self, transport: &Arc<dyn Transport>, token: &str, state: &mut AccountState, me: &str, now: i64) -> u32 {
        let _ = self.with_conn(|conn| self.flush_drafts_at(conn, me, now));
        self.upload_draft_files(transport, token, me, now);
        let Ok(rows) = self.with_conn(|conn| {
            let mut st = conn.prepare("SELECT id, draft_id, to_user, op_type, payload FROM draft_outbox ORDER BY id LIMIT 200").map_err(db_err)?;
            let rows = st.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?, r.get::<_, String>(2)?, r.get::<_, String>(3)?, r.get::<_, String>(4)?))).map_err(db_err)?;
            rows.collect::<Result<Vec<_>, _>>().map_err(db_err)
        }) else {
            return 0;
        };
        let mut sent = 0;
        for (id, draft_id, to, op_type, payload) in rows {
            // A change or hello to someone who is no longer an author is not sent.
            let still_author = self.with_conn(|conn| Ok(active_authors(conn, &draft_id)?.contains(&to))).unwrap_or(false);
            if matches!(op_type.as_str(), "draft.change" | "draft.hello") && !still_author {
                let _ = self.with_conn(|conn| conn.execute("DELETE FROM draft_outbox WHERE id = ?1", params![id]).map(|_| ()).map_err(db_err));
                continue;
            }
            let Ok(payload) = serde_json::from_str::<Value>(&payload) else {
                let _ = self.with_conn(|conn| conn.execute("DELETE FROM draft_outbox WHERE id = ?1", params![id]).map(|_| ()).map_err(db_err));
                continue;
            };
            match self.send_control_op(transport, token, state, me, &to, &op_type, payload) {
                Ok(()) => {
                    let _ = self.with_conn(|conn| conn.execute("DELETE FROM draft_outbox WHERE id = ?1", params![id]).map(|_| ()).map_err(db_err));
                    sent += 1;
                }
                Err(StoreError::Network | StoreError::RateLimited | StoreError::Unavailable) => break,
                Err(_) => continue,
            }
        }
        sent
    }

    /// The batching rule, with the clock passed in so a test can type for a virtual minute.
    pub(crate) fn flush_drafts_at(&self, conn: &Connection, me: &str, now: i64) -> Result<(), StoreError> {
        let due: Vec<(String, String, i64, i64)> = {
            let mut st = conn
                .prepare("SELECT d.draft_id, d.durable_heads, d.last_flush_at, d.last_hello_at FROM drafts d JOIN draft_authors a ON a.draft_id = d.draft_id AND a.user_id = ?1 AND a.status = 'active' WHERE d.channel_id IS NOT NULL AND d.draft_key IS NOT NULL")
                .map_err(db_err)?;
            let rows = st.query_map(params![me], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?))).map_err(db_err)?;
            rows.collect::<Result<_, _>>().map_err(db_err)?
        };
        for (draft_id, durable_heads, last_flush, last_hello) in due {
            if now - last_flush >= FLUSH_EVERY_MS {
                let last = heads_of(&durable_heads);
                let (bytes, heads) = self.with_draft_conn(conn, &draft_id, false, |d| {
                    let now_heads = d.heads();
                    if now_heads == last {
                        return Ok((Vec::new(), now_heads));
                    }
                    Ok((d.changes_since(&last), now_heads))
                })?;
                if !bytes.is_empty() {
                    for who in active_authors(conn, &draft_id)?.into_iter().filter(|u| u != me) {
                        enqueue(conn, &draft_id, &who, "draft.change", json!({ "draft_id": draft_id, "bytes": b64(&bytes) }), now)?;
                    }
                    conn.execute("UPDATE drafts SET durable_heads = ?2, last_flush_at = ?3 WHERE draft_id = ?1", params![draft_id, heads_json(&heads), now]).map_err(db_err)?;
                }
            }
            if now - last_hello >= HELLO_EVERY_MS {
                self.queue_hello(conn, &draft_id, me, now)?;
            }
        }
        Ok(())
    }

    /// A `draft.*` op from `sender` (verified like any control op). Runs inside the receive transaction.
    pub(crate) fn apply_draft_op(&self, conn: &Connection, me: &str, sender: &str, op_type: &str, payload: &Value, now: i64) -> Result<(), StoreError> {
        let text = |k: &str| payload.get(k).and_then(Value::as_str).map(str::to_owned);
        let Some(draft_id) = text("draft_id").filter(|d| !d.is_empty() && d.len() <= 64) else { return Ok(()) };
        let is_author = |conn: &Connection| -> Result<bool, StoreError> { Ok(active_authors(conn, &draft_id)?.iter().any(|u| u == sender)) };
        match op_type {
            "draft.invite" => {
                // Only from an accepted contact, who must be the writer, for a draft I do not have.
                let accepted: bool = conn.query_row("SELECT EXISTS (SELECT 1 FROM conversations WHERE id = ?1 AND request_state = 'accepted')", params![format!("dm:{sender}")], |r| r.get(0)).map_err(db_err)?;
                let exists: bool = conn.query_row("SELECT EXISTS (SELECT 1 FROM drafts WHERE draft_id = ?1)", params![draft_id], |r| r.get(0)).map_err(db_err)?;
                if !accepted || exists || text("writer").as_deref() != Some(sender) {
                    return Ok(());
                }
                let (Some(channel), Some(key), Some(snapshot)) = (text("channel_id"), text("key").and_then(|k| unb64(&k)), text("snapshot").and_then(|s| unb64(&s))) else { return Ok(()) };
                if channel.len() != 32 || key.len() != 32 {
                    return Ok(());
                }
                let mut doc = crate::drafts::DraftDoc::load(&snapshot)?;
                let heads = doc.heads();
                doc.mark_seen();
                conn.execute(
                    "INSERT INTO drafts (draft_id, snapshot, post_id, changes, created_at, updated_at, channel_id, draft_key, writer, durable_heads, instant_heads, invited_at, seen)
                     VALUES (?1, ?2, NULL, 0, ?3, ?3, ?4, ?5, ?6, ?7, ?7, ?3, 0)",
                    params![draft_id, snapshot, now, channel, key, sender, heads_json(&heads)],
                )
                .map_err(db_err)?;
                self.draft_cache.lock().unwrap_or_else(|e| e.into_inner()).insert(draft_id.clone(), doc);
                let authors: Vec<String> = payload.get("authors").and_then(Value::as_array).map(|a| a.iter().filter_map(|u| u.as_str().map(str::to_owned)).collect()).unwrap_or_default();
                for who in authors.iter().take(MAX_AUTHORS).chain(std::iter::once(&sender.to_owned())).chain(std::iter::once(&me.to_owned())) {
                    conn.execute("INSERT OR REPLACE INTO draft_authors (draft_id, user_id, status) VALUES (?1, ?2, 'active')", params![draft_id, who]).map_err(db_err)?;
                }
            }
            "draft.change" => {
                if !is_author(conn)? {
                    return Ok(());
                }
                let Some(bytes) = text("bytes").and_then(|b| unb64(&b)) else { return Ok(()) };
                self.with_draft_conn(conn, &draft_id, false, |d| d.apply_changes(&bytes).map(|_| ()))?;
            }
            "draft.hello" => {
                if !is_author(conn)? {
                    return Ok(());
                }
                let theirs: Vec<String> = payload.get("heads").and_then(Value::as_array).map(|a| a.iter().filter_map(|h| h.as_str().map(str::to_owned)).collect()).unwrap_or_default();
                let (missing_for_them, i_lack_some, my_heads) = self.with_draft_conn(conn, &draft_id, false, |d| {
                    let mine = d.heads();
                    let lack = theirs.iter().any(|h| !mine.contains(h));
                    let bytes = if mine.iter().all(|h| theirs.contains(h)) { Vec::new() } else { d.changes_since(&theirs) };
                    Ok((bytes, lack, mine))
                })?;
                if !missing_for_them.is_empty() {
                    enqueue(conn, &draft_id, sender, "draft.change", json!({ "draft_id": draft_id, "bytes": b64(&missing_for_them) }), now)?;
                }
                if i_lack_some {
                    enqueue(conn, &draft_id, sender, "draft.hello", json!({ "draft_id": draft_id, "heads": my_heads }), now)?;
                }
            }
            "draft.key" => {
                let writer: Option<String> = conn.query_row("SELECT writer FROM drafts WHERE draft_id = ?1", params![draft_id], |r| r.get(0)).optional().map_err(db_err)?.flatten();
                if writer.as_deref() != Some(sender) {
                    return Ok(());
                }
                let Some(key) = text("key").and_then(|k| unb64(&k)).filter(|k| k.len() == 32) else { return Ok(()) };
                conn.execute("UPDATE drafts SET draft_key = ?2 WHERE draft_id = ?1", params![draft_id, key]).map_err(db_err)?;
                if let Some(list) = payload.get("authors").and_then(Value::as_array) {
                    let keep: Vec<String> = list.iter().filter_map(|u| u.as_str().map(str::to_owned)).collect();
                    for who in active_authors(conn, &draft_id)? {
                        if !keep.contains(&who) {
                            conn.execute("UPDATE draft_authors SET status = 'removed' WHERE draft_id = ?1 AND user_id = ?2", params![draft_id, who]).map_err(db_err)?;
                        }
                    }
                }
            }
            "draft.authors" => {
                let writer: Option<String> = conn.query_row("SELECT writer FROM drafts WHERE draft_id = ?1", params![draft_id], |r| r.get(0)).optional().map_err(db_err)?.flatten();
                if writer.as_deref() == Some(sender) {
                    for who in payload.get("authors").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str).take(MAX_AUTHORS) {
                        conn.execute("INSERT OR IGNORE INTO draft_authors (draft_id, user_id, status) VALUES (?1, ?2, 'active')", params![draft_id, who]).map_err(db_err)?;
                    }
                }
            }
            "draft.leave" => {
                if is_author(conn)? {
                    conn.execute("UPDATE draft_authors SET status = 'left' WHERE draft_id = ?1 AND user_id = ?2", params![draft_id, sender]).map_err(db_err)?;
                }
            }
            "draft.removed" => {
                let writer: Option<String> = conn.query_row("SELECT writer FROM drafts WHERE draft_id = ?1", params![draft_id], |r| r.get(0)).optional().map_err(db_err)?.flatten();
                if writer.as_deref() == Some(sender) {
                    conn.execute("UPDATE draft_authors SET status = 'removed' WHERE draft_id = ?1 AND user_id = ?2", params![draft_id, me]).map_err(db_err)?;
                    conn.execute("UPDATE drafts SET draft_key = NULL WHERE draft_id = ?1", params![draft_id]).map_err(db_err)?;
                    conn.execute("DELETE FROM draft_outbox WHERE draft_id = ?1", params![draft_id]).map_err(db_err)?;
                }
            }
            _ => return self.apply_draft_publish_op(conn, me, sender, op_type, payload),
        }
        Ok(())
    }
}
