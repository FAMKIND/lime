//! jam on the client (LIME-186, `docs/jam.md`): a teacher's one-author encrypted channel.
//!
//! - **The writer's phone** makes a jam, takes subscribers, and publishes each post once: encrypted under a Megolm session (one per tier, so a
//!   subscribers-only post is never readable with a free subscriber's key), stored here, and queued for every subscriber who may read it.
//! - **A subscriber** asks to join (`jam.subscribe`), is sent a `jam.welcome` with the jam's state and the first-index key of every session it may
//!   hold (so it can read the whole archive), then the old posts' ciphertexts again, then each new post.
//! - **Rotation:** on a removal, after 100 posts, after 7 days and when the jam ends; **never on a join** (the archive is handed over anyway).
//! - **The queue** is persistent (`jam_wire_outbox`, one row per post and subscriber), so a post to 1,000 people never blocks anything, survives a
//!   restart and resumes with a back-off; a delivery pass sends at most [`jam_store::RECIPIENTS_PER_PASS`] recipients.
//!
//! The server carries ciphertext only and is not changed. Until LIME-187 an old post is re-sent as the same ciphertext; then it is a blob.

use vodozemac::megolm::{ExportedSessionKey, GroupSession, InboundGroupSession, MegolmMessage, SessionConfig as MegolmConfig, SessionKey};

use super::groups::GROUP_WIRE;
use super::*;
use crate::store::groups;
use crate::store::jam as jam_store;
use crate::store::jam::{TIER_FREE, TIER_SUBSCRIBERS};

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct JamInfo {
    pub jam_id: String,
    pub conversation_id: String,
    pub writer: String,
    pub title: String,
    pub about: String,
    pub topics: Vec<String>,
    pub tiers: Vec<String>,
    /// I am the writer.
    pub mine: bool,
    /// Mine: `active`. A subscription: `requested`, `active`, `full`, `removed` or `left`.
    pub status: String,
    pub ended: bool,
    /// Mine: how many active subscribers.
    pub subscriber_count: u32,
    pub post_count: u32,
    pub created: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct JamPostInfo {
    pub post_id: String,
    pub jam_id: String,
    pub author: String,
    pub tier: String,
    pub title: String,
    pub markdown: String,
    pub plain: String,
    /// The post's attachment descriptors, as received (a JSON array).
    pub attachments_json: String,
    pub created: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct JamSubscriberInfo {
    pub user_id: String,
    pub name: String,
    pub since: i64,
    pub tier: String,
    /// `active`, `removed` or `left`.
    pub status: String,
}

/// How much of what is queued for a jam has gone out: "sending to 412 of 1,000".
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct JamSendProgress {
    pub pending: u32,
    pub total: u32,
}

fn info(conn: &Connection, row: jam_store::JamRow) -> Result<JamInfo, StoreError> {
    Ok(JamInfo {
        subscriber_count: if row.mine { jam_store::subscriber_count(conn, &row.jam_id)? as u32 } else { 0 },
        post_count: jam_store::post_count(conn, &row.jam_id)? as u32,
        conversation_id: jam_store::conversation_id(&row.jam_id),
        jam_id: row.jam_id,
        writer: row.writer,
        title: row.title,
        about: row.about,
        topics: row.topics,
        tiers: row.tiers,
        mine: row.mine,
        status: row.status,
        ended: row.ended,
        created: row.created,
    })
}

fn post_info(row: jam_store::PostRow) -> JamPostInfo {
    JamPostInfo {
        post_id: row.post_id,
        jam_id: row.jam_id,
        author: row.author,
        tier: row.tier,
        title: row.title,
        markdown: row.markdown,
        plain: row.plain,
        attachments_json: row.attachments,
        created: row.created,
    }
}

/// Signs an op of this jam (`op_id` given for a post: it is the post's id).
pub(crate) fn signed_op(conn: &Connection, state: &AccountState, op_type: &str, jam_id: &str, op_id: Option<String>, payload: Value, now: i64) -> Result<Op, StoreError> {
    let hlc = tick_hlc(conn, now)?;
    let mut op = Op {
        op_id: op_id.unwrap_or_else(new_id),
        op_type: op_type.into(),
        conversation_id: jam_store::conversation_id(jam_id),
        hlc: hlc.render(),
        parents: vec![],
        payload,
        sig: String::new(),
    };
    op.sig = state.account.sign(op.signing_bytes()).to_base64();
    Ok(op)
}

/// Queues an op for one person in the persistent outbox (sent over Olm by the next delivery).
fn queue_op(conn: &Connection, jam_id: &str, recipient: &str, op: &Op) -> Result<(), StoreError> {
    groups::enqueue(conn, jam_id, recipient, &op.to_json().to_string())
}

/// Runs `body` as one unit: all of it or none.
fn atomically<T>(conn: &Connection, body: impl FnOnce() -> Result<T, StoreError>) -> Result<T, StoreError> {
    conn.execute_batch("SAVEPOINT jam_unit").map_err(db_err)?;
    match body() {
        Ok(value) => {
            conn.execute_batch("RELEASE jam_unit").map_err(db_err)?;
            Ok(value)
        }
        Err(error) => {
            let _ = conn.execute_batch("ROLLBACK TO jam_unit; RELEASE jam_unit");
            Err(error)
        }
    }
}

const SESSIONS_PER_OP: usize = 40;

fn session_entries(sessions: &[(String, String, String)]) -> Vec<Value> {
    sessions.iter().map(|(session_id, tier, key)| json!({ "session_id": session_id, "tier": tier, "key": key })).collect()
}

#[uniffi::export]
impl LimeStore {
    /// Makes a jam with me as its writer. Returns its conversation id (`jam:<id>`). Every jam has a free tier.
    pub fn create_jam(&self, title: String, about: String, topics: Vec<String>) -> Result<String, StoreError> {
        let state = self.load_or_create_account()?;
        let me = state.user_id.clone().filter(|_| state.registered).ok_or(StoreError::NotRegistered)?;
        let title = jam_store::clean_line(&title, jam_store::MAX_TITLE_CHARS).ok_or(StoreError::Rejected)?;
        let about = jam_store::clean_about(&about).ok_or(StoreError::Rejected)?;
        let topics = jam_store::clean_topics(&topics).ok_or(StoreError::Rejected)?;
        let tiers = jam_store::clean_tiers(&[TIER_FREE.to_owned(), TIER_SUBSCRIBERS.to_owned()]).ok_or(StoreError::Rejected)?;
        let jam_id = new_id();
        let now = now_ms();
        self.with_conn(|conn| {
            let hlc = tick_hlc(conn, now)?;
            conn.execute(
                "INSERT INTO jams (jam_id, writer, title, about, topics, tiers, state_hlc, mine, status, ended, created)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 1, 'active', 0, ?8)",
                params![jam_id, me, title, about, json!(topics).to_string(), json!(tiers).to_string(), hlc.render(), now],
            )
            .map_err(db_err)?;
            Ok(())
        })?;
        Ok(jam_store::conversation_id(&jam_id))
    }

    /// Changes my jam's title, about or topics; its subscribers are told.
    pub fn update_jam(&self, jam_id: String, title: String, about: String, topics: Vec<String>) -> Result<(), StoreError> {
        let state = self.load_or_create_account()?;
        self.registered_user(&state)?;
        let title = jam_store::clean_line(&title, jam_store::MAX_TITLE_CHARS).ok_or(StoreError::Rejected)?;
        let about = jam_store::clean_about(&about).ok_or(StoreError::Rejected)?;
        let topics = jam_store::clean_topics(&topics).ok_or(StoreError::Rejected)?;
        let now = now_ms();
        self.with_conn(|conn| {
            let jam = jam_store::get(conn, &jam_id)?.filter(|j| j.mine && !j.ended).ok_or(StoreError::NotFound)?;
            let op = signed_op(conn, &state, "jam.update", &jam_id, None, json!({ "jam_id": jam_id, "title": title, "about": about, "topics": topics, "tiers": jam.tiers }), now)?;
            conn.execute(
                "UPDATE jams SET title = ?2, about = ?3, topics = ?4, state_hlc = ?5 WHERE jam_id = ?1",
                params![jam_id, title, about, json!(topics).to_string(), op.hlc],
            )
            .map_err(db_err)?;
            for user in jam_store::audience(conn, &jam_id, TIER_FREE)? {
                queue_op(conn, &jam_id, &user, &op)?;
            }
            Ok(())
        })
    }

    /// Ends my jam: no more posts, the sessions are retired, and the subscribers are told (they keep what they have).
    pub fn end_jam(&self, jam_id: String) -> Result<(), StoreError> {
        let state = self.load_or_create_account()?;
        self.registered_user(&state)?;
        let now = now_ms();
        self.with_conn(|conn| {
            atomically(conn, || {
                let jam = jam_store::get(conn, &jam_id)?.filter(|j| j.mine && !j.ended).ok_or(StoreError::NotFound)?;
                let op = signed_op(conn, &state, "jam.end", &jam_id, None, json!({ "jam_id": jam_id }), now)?;
                conn.execute("UPDATE jams SET ended = 1, state_hlc = ?2 WHERE jam_id = ?1", params![jam_id, op.hlc]).map_err(db_err)?;
                jam_store::delete_outbound(conn, &jam_id)?;
                conn.execute("DELETE FROM jam_wire_outbox WHERE jam_id = ?1", params![jam_id]).map_err(db_err)?;
                for user in jam_store::audience(conn, &jam_id, TIER_FREE)? {
                    queue_op(conn, &jam_id, &user, &op)?;
                }
                let _ = jam;
                Ok(())
            })
        })
    }

    /// The jams I write, newest first.
    pub fn list_my_jams(&self) -> Result<Vec<JamInfo>, StoreError> {
        self.with_conn(|conn| jam_store::list(conn, true)?.into_iter().map(|row| info(conn, row)).collect())
    }

    /// The jams I follow (or asked to), newest first.
    pub fn list_jam_subscriptions(&self) -> Result<Vec<JamInfo>, StoreError> {
        self.with_conn(|conn| jam_store::list(conn, false)?.into_iter().map(|row| info(conn, row)).collect())
    }

    /// One jam, mine or followed.
    pub fn jam(&self, jam_id: String) -> Result<Option<JamInfo>, StoreError> {
        self.with_conn(|conn| jam_store::get(conn, &jam_id)?.map(|row| info(conn, row)).transpose())
    }

    /// Asks the writer to let me follow their jam. The writer's phone accepts anyone signed in, unless they removed me or the jam is full.
    pub fn subscribe_to_jam(&self, jam_id: String, writer_user_id: String) -> Result<(), StoreError> {
        let state = self.load_or_create_account()?;
        let me = self.registered_user(&state)?;
        if writer_user_id == me || writer_user_id.is_empty() || jam_store::jam_id_of(&jam_store::conversation_id(&jam_id)).is_none() {
            return Err(StoreError::Rejected);
        }
        let now = now_ms();
        self.with_conn(|conn| {
            if let Some(existing) = jam_store::get(conn, &jam_id)? {
                if existing.mine || existing.writer != writer_user_id || matches!(existing.status.as_str(), "active" | "requested") {
                    return Ok(());
                }
                conn.execute("UPDATE jams SET status = 'requested' WHERE jam_id = ?1", params![jam_id]).map_err(db_err)?;
            } else {
                conn.execute(
                    "INSERT INTO jams (jam_id, writer, title, about, topics, tiers, state_hlc, mine, status, ended, created)
                     VALUES (?1, ?2, '', '', '[]', '[\"free\"]', '', 0, 'requested', 0, ?3)",
                    params![jam_id, writer_user_id, now],
                )
                .map_err(db_err)?;
            }
            let op = signed_op(conn, &state, "jam.subscribe", &jam_id, None, json!({ "jam_id": jam_id }), now)?;
            queue_op(conn, &jam_id, &writer_user_id, &op)
        })
    }

    /// Stops following a jam: the writer is told and stops sending; what I have stays on this phone.
    pub fn unsubscribe_from_jam(&self, jam_id: String) -> Result<(), StoreError> {
        let state = self.load_or_create_account()?;
        self.registered_user(&state)?;
        let now = now_ms();
        self.with_conn(|conn| {
            let jam = jam_store::get(conn, &jam_id)?.filter(|j| !j.mine).ok_or(StoreError::NotFound)?;
            conn.execute("UPDATE jams SET status = 'left' WHERE jam_id = ?1", params![jam_id]).map_err(db_err)?;
            let op = signed_op(conn, &state, "jam.unsubscribe", &jam_id, None, json!({ "jam_id": jam_id }), now)?;
            queue_op(conn, &jam_id, &jam.writer, &op)
        })
    }

    /// The posts of a jam I follow or write, oldest first (a subscriber's archive included).
    pub fn list_jam_posts(&self, jam_id: String) -> Result<Vec<JamPostInfo>, StoreError> {
        self.with_conn(|conn| Ok(jam_store::posts(conn, &jam_id)?.into_iter().map(post_info).collect()))
    }

    /// One post.
    pub fn read_jam_post(&self, post_id: String) -> Result<Option<JamPostInfo>, StoreError> {
        self.with_conn(|conn| Ok(jam_store::post(conn, &post_id)?.filter(|p| !p.deleted).map(post_info)))
    }

    /// Publishes a post to my jam's subscribers: encrypted here once, kept, and queued for everyone who may read it. `tier` is `free` or
    /// `subscribers`; `attachments_json` is a JSON array of attachment descriptors (`[]` for none). Returns the post's id. Nothing is sent
    /// yet: the delivery passes do that, in chunks.
    pub fn publish_jam_post(&self, jam_id: String, title: String, markdown: String, tier: String, attachments_json: String) -> Result<String, StoreError> {
        let state = self.load_or_create_account()?;
        let me = self.registered_user(&state)?;
        let title = jam_store::clean_line(&title, jam_store::MAX_POST_TITLE_CHARS).ok_or(StoreError::Rejected)?;
        let markdown = crate::format::normalise(&markdown);
        if markdown.len() > jam_store::MAX_POST_BYTES || !jam_store::valid_tier(&tier) {
            return Err(StoreError::Rejected);
        }
        let attachments: Value = serde_json::from_str(&attachments_json).map_err(|_| StoreError::Rejected)?;
        let parsed = crate::store::attachments::parse_payload(&json!({ "attachments": attachments })).ok_or(StoreError::Rejected)?;
        if markdown.is_empty() && parsed.is_empty() {
            return Err(StoreError::Rejected);
        }
        let plain = crate::format::plain_text(&markdown);
        let post_id = new_id();
        let now = now_ms();
        self.with_conn(|conn| {
            atomically(conn, || {
                let jam = jam_store::get(conn, &jam_id)?.filter(|j| j.mine).ok_or(StoreError::NotFound)?;
                if jam.ended || !jam.tiers.contains(&tier) {
                    return Err(StoreError::Rejected);
                }
                let mut outbound = self.ensure_jam_session(conn, &state, &jam_id, &tier, now)?;
                let op = signed_op(
                    conn,
                    &state,
                    "jam.post",
                    &jam_id,
                    Some(post_id.clone()),
                    json!({ "post_id": post_id, "tier": tier, "title": title, "markdown": markdown, "attachments": attachments }),
                    now,
                )?;
                let inner = SealedInner { sender_user: me.clone(), sender_device: state.device_id.clone(), sender_cert: state.cert(), op }.to_bytes();
                let encrypted = outbound.session.encrypt(&inner);
                let index = encrypted.message_index();
                outbound.posts += 1;
                jam_store::save_outbound(conn, &self.pickle_key, &jam_id, &tier, &outbound)?;
                let mut wire = vec![GROUP_WIRE];
                wire.extend_from_slice(json!({ "s": outbound.session.session_id(), "c": encrypted.to_base64() }).to_string().as_bytes());
                let wire_b64 = vodozemac::base64_encode(&wire);
                let audience = jam_store::audience(conn, &jam_id, &tier)?;
                conn.execute(
                    "INSERT INTO jam_posts (post_id, jam_id, author, session_id, idx, tier, title, markdown, plain, attachments, created, wire, fanout_total)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)",
                    params![post_id, jam_id, me, outbound.session.session_id(), index, tier, title, markdown, plain, attachments.to_string(), now, wire_b64, audience.len() as i64],
                )
                .map_err(db_err)?;
                jam_store::queue_wire(conn, &jam_id, &post_id, &audience)?;
                Ok(())
            })
        })?;
        Ok(post_id)
    }

    /// Removes a subscriber: they are told, they get nothing more, and the next post is under a new session they are not given.
    pub fn remove_jam_subscriber(&self, jam_id: String, user_id: String) -> Result<(), StoreError> {
        let state = self.load_or_create_account()?;
        self.registered_user(&state)?;
        let now = now_ms();
        self.with_conn(|conn| {
            atomically(conn, || {
                jam_store::get(conn, &jam_id)?.filter(|j| j.mine).ok_or(StoreError::NotFound)?;
                let known = jam_store::subscriber(conn, &jam_id, &user_id)?;
                if !known.is_some_and(|(status, _)| status == "active") {
                    return Err(StoreError::NotFound);
                }
                conn.execute("UPDATE jam_subscribers SET status = 'removed', removed_at = ?3 WHERE jam_id = ?1 AND user_id = ?2", params![jam_id, user_id, now]).map_err(db_err)?;
                conn.execute("DELETE FROM jam_wire_outbox WHERE jam_id = ?1 AND recipient = ?2", params![jam_id, user_id]).map_err(db_err)?;
                conn.execute("DELETE FROM group_outbox WHERE group_id = ?1 AND recipient_user = ?2", params![jam_id, user_id]).map_err(db_err)?;
                jam_store::mark_rotate(conn, &jam_id)?;
                let op = signed_op(conn, &state, "jam.remove", &jam_id, None, json!({ "jam_id": jam_id }), now)?;
                queue_op(conn, &jam_id, &user_id, &op)
            })
        })
    }

    /// The people following my jam (active, and those who left or were removed).
    pub fn list_jam_subscribers(&self, jam_id: String) -> Result<Vec<JamSubscriberInfo>, StoreError> {
        self.with_conn(|conn| {
            jam_store::get(conn, &jam_id)?.filter(|j| j.mine).ok_or(StoreError::NotFound)?;
            let mut statement = conn
                .prepare(
                    "SELECT s.user_id, COALESCE(p.name, s.user_id), s.since, s.tier, s.status FROM jam_subscribers s LEFT JOIN people p ON p.id = s.user_id
                     WHERE s.jam_id = ?1 ORDER BY s.since, s.user_id",
                )
                .map_err(db_err)?;
            let rows = statement
                .query_map(params![jam_id], |r| Ok(JamSubscriberInfo { user_id: r.get(0)?, name: r.get(1)?, since: r.get(2)?, tier: r.get(3)?, status: r.get(4)? }))
                .map_err(db_err)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(db_err)?;
            Ok(rows)
        })
    }

    /// How much of what is queued for this jam has gone ("sending to 412 of 1,000"). Both zero when nothing waits.
    pub fn jam_send_progress(&self, jam_id: String) -> Result<JamSendProgress, StoreError> {
        let (pending, total) = self.with_conn(|conn| jam_store::progress(conn, &jam_id))?;
        Ok(JamSendProgress { pending: pending as u32, total: total as u32 })
    }
}

// ---------------------------------------------------------------- sessions

impl LimeStore {
    fn registered_user(&self, state: &AccountState) -> Result<String, StoreError> {
        state.user_id.clone().filter(|_| state.registered).ok_or(StoreError::NotRegistered)
    }

    /// The current outbound session for a tier, replaced first when it is time (a removal marked it, 100 posts, 7 days), and its key given to
    /// everyone who may read that tier. A new subscriber does not cause a replacement: they are handed the older keys with their welcome.
    fn ensure_jam_session(&self, conn: &Connection, state: &AccountState, jam_id: &str, tier: &str, now: i64) -> Result<jam_store::Outbound, StoreError> {
        let existing = jam_store::load_outbound(conn, &self.pickle_key, jam_id, tier)?;
        if let Some(current) = existing.filter(|o| !o.rotate && o.posts < jam_store::ROTATE_AFTER_POSTS && now - o.created_at < jam_store::ROTATE_AFTER_MS) {
            return Ok(current);
        }
        let outbound = jam_store::Outbound { session: GroupSession::new(MegolmConfig::version_1()), created_at: now, posts: 0, rotate: false };
        jam_store::save_outbound(conn, &self.pickle_key, jam_id, tier, &outbound)?;
        jam_store::record_session(conn, &self.pickle_key, jam_id, tier, &outbound.session, now)?;
        let entry = json!({ "session_id": outbound.session.session_id(), "tier": tier, "key": outbound.session.session_key().to_base64() });
        let op = signed_op(conn, state, "jam.session", jam_id, None, json!({ "jam_id": jam_id, "sessions": [entry] }), now)?;
        for user in jam_store::audience(conn, jam_id, tier)? {
            queue_op(conn, jam_id, &user, &op)?;
        }
        Ok(outbound)
    }

    /// Takes a subscriber in (or says why not) and queues the welcome and the archive.
    fn accept_subscriber(&self, conn: &Connection, state: &AccountState, jam: &jam_store::JamRow, user: &str, now: i64) -> Result<(), StoreError> {
        let jam_id = jam.jam_id.as_str();
        let existing = jam_store::subscriber(conn, jam_id, user)?;
        let refuse = |reason: &str| -> Result<(), StoreError> {
            let op = signed_op(conn, state, "jam.refused", jam_id, None, json!({ "jam_id": jam_id, "reason": reason }), now)?;
            queue_op(conn, jam_id, user, &op)
        };
        if jam.ended {
            return refuse("ended");
        }
        match existing.as_ref().map(|(status, _)| status.as_str()) {
            Some("removed") => return refuse("removed"),
            Some("active") => {}
            _ => {
                if jam_store::subscriber_count(conn, jam_id)? >= jam_store::MAX_SUBSCRIBERS {
                    return refuse("full");
                }
                conn.execute(
                    "INSERT INTO jam_subscribers (jam_id, user_id, since, tier, status) VALUES (?1, ?2, ?3, 'free', 'active')
                     ON CONFLICT (jam_id, user_id) DO UPDATE SET status = 'active', removed_at = NULL, since = ?3",
                    params![jam_id, user, now],
                )
                .map_err(db_err)?;
            }
        }
        let tier = existing.map(|(_, tier)| tier).unwrap_or_else(|| TIER_FREE.to_owned());
        let sessions = jam_store::session_keys(conn, &self.pickle_key, jam_id, &tier)?;
        let entries = session_entries(&sessions);
        let (first, rest) = entries.split_at(entries.len().min(SESSIONS_PER_OP));
        let welcome = json!({
            "jam_id": jam_id,
            "state": { "writer": jam.writer, "title": jam.title, "about": jam.about, "topics": jam.topics, "tiers": jam.tiers, "state_hlc": jam.state_hlc },
            "sessions": first,
            "post_count": jam_store::post_count(conn, jam_id)?,
        });
        queue_op(conn, jam_id, user, &signed_op(conn, state, "jam.welcome", jam_id, None, welcome, now)?)?;
        for chunk in rest.chunks(SESSIONS_PER_OP) {
            queue_op(conn, jam_id, user, &signed_op(conn, state, "jam.session", jam_id, None, json!({ "jam_id": jam_id, "sessions": chunk }), now)?)?;
        }
        // The archive: every post this subscriber may read, as the same ciphertext it was first sent as (the keys above open it).
        let mut statement = conn
            .prepare("SELECT post_id FROM jam_posts WHERE jam_id = ?1 AND deleted_at IS NULL AND wire IS NOT NULL AND (?2 = 'subscribers' OR tier = 'free') ORDER BY created, post_id")
            .map_err(db_err)?;
        let old: Vec<String> = statement.query_map(params![jam_id, tier], |r| r.get(0)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
        for post_id in old {
            jam_store::queue_wire(conn, jam_id, &post_id, &[user.to_owned()])?;
            conn.execute("UPDATE jam_posts SET fanout_total = fanout_total + 1 WHERE post_id = ?1", params![post_id]).map_err(db_err)?;
        }
        Ok(())
    }
}

// ---------------------------------------------------------------- receiving an op over Olm

impl LimeStore {
    /// A jam op that came through a verified Olm item from `sender`. Who may do what: a subscribe or an unsubscribe is for the writer (from
    /// anyone); everything else must come from the jam's writer, as this phone knows them.
    #[allow(clippy::too_many_arguments)] // the context of one item
    pub(super) fn apply_jam_op(&self, conn: &Connection, state: &AccountState, me: &str, sender: &str, inner: &SealedInner, cert: &SenderCert, now: i64) -> Result<(), StoreError> {
        let op = &inner.op;
        let Some(jam_id) = jam_store::jam_id_of(&op.conversation_id) else { return Ok(()) };
        if op.payload.get("jam_id").and_then(Value::as_str) != Some(jam_id) {
            return Ok(());
        }
        let jam = jam_store::get(conn, jam_id)?;
        match op.op_type.as_str() {
            "jam.subscribe" => {
                let Some(jam) = jam.filter(|j| j.mine && j.writer == me) else { return Ok(()) };
                if sender == me {
                    return Ok(());
                }
                self.accept_subscriber(conn, state, &jam, sender, now)
            }
            "jam.unsubscribe" => {
                if jam.is_some_and(|j| j.mine) {
                    conn.execute(
                        "UPDATE jam_subscribers SET status = 'left', removed_at = ?3 WHERE jam_id = ?1 AND user_id = ?2 AND status = 'active'",
                        params![jam_id, sender, now],
                    )
                    .map_err(db_err)?;
                    conn.execute("DELETE FROM jam_wire_outbox WHERE jam_id = ?1 AND recipient = ?2", params![jam_id, sender]).map_err(db_err)?;
                }
                Ok(())
            }
            // Everything else is the writer's, to a subscriber or someone who asked to be one.
            other => {
                let Some(jam) = jam.filter(|j| !j.mine && j.writer == sender) else { return Ok(()) };
                match other {
                    "jam.welcome" => {
                        let Some(state_value) = op.payload.get("state") else { return Ok(()) };
                        self.apply_jam_state(conn, &jam, state_value, &op.hlc, true)?;
                        conn.execute("UPDATE jams SET status = 'active' WHERE jam_id = ?1 AND status IN ('requested', 'full', 'left')", params![jam_id]).map_err(db_err)?;
                        self.store_jam_sessions(conn, jam_id, sender, &cert.device_id, &op.payload)
                    }
                    "jam.session" => self.store_jam_sessions(conn, jam_id, sender, &cert.device_id, &op.payload),
                    "jam.update" => {
                        self.apply_jam_state(conn, &jam, &op.payload, &op.hlc, false)?;
                        Ok(())
                    }
                    "jam.end" => {
                        if op.hlc.as_str() > jam.state_hlc.as_str() {
                            conn.execute("UPDATE jams SET ended = 1, state_hlc = ?2 WHERE jam_id = ?1", params![jam_id, op.hlc]).map_err(db_err)?;
                        }
                        Ok(())
                    }
                    "jam.remove" => {
                        conn.execute("UPDATE jams SET status = 'removed' WHERE jam_id = ?1", params![jam_id]).map_err(db_err)?;
                        Ok(())
                    }
                    "jam.refused" => {
                        let reason = op.payload.get("reason").and_then(Value::as_str).unwrap_or("full");
                        let status = match reason {
                            "removed" => "removed",
                            "ended" => "left",
                            _ => "full",
                        };
                        conn.execute("UPDATE jams SET status = ?2 WHERE jam_id = ?1 AND status = 'requested'", params![jam_id, status]).map_err(db_err)?;
                        Ok(())
                    }
                    _ => Ok(()),
                }
            }
        }
    }

    /// The jam's title, about, topics and tiers from the writer, if newer than what is held (`force`: a welcome always sets them).
    fn apply_jam_state(&self, conn: &Connection, jam: &jam_store::JamRow, value: &Value, hlc: &str, force: bool) -> Result<(), StoreError> {
        if !force && hlc <= jam.state_hlc.as_str() {
            return Ok(());
        }
        let text = |k: &str| value.get(k).and_then(Value::as_str);
        let list = |k: &str| value.get(k).and_then(Value::as_array).map(|a| a.iter().filter_map(|v| v.as_str().map(str::to_owned)).collect::<Vec<_>>());
        let (Some(title), Some(about), Some(topics)) = (text("title").and_then(|t| jam_store::clean_line(t, jam_store::MAX_TITLE_CHARS)), text("about").and_then(jam_store::clean_about), list("topics").and_then(|t| jam_store::clean_topics(&t))) else {
            return Ok(());
        };
        let tiers = list("tiers").and_then(|t| jam_store::clean_tiers(&t)).unwrap_or_else(|| jam.tiers.clone());
        let state_hlc = if hlc > jam.state_hlc.as_str() { hlc } else { jam.state_hlc.as_str() };
        conn.execute(
            "UPDATE jams SET title = ?2, about = ?3, topics = ?4, tiers = ?5, state_hlc = ?6 WHERE jam_id = ?1",
            params![jam.jam_id, title, about, json!(topics).to_string(), json!(tiers).to_string(), state_hlc],
        )
        .map_err(db_err)?;
        Ok(())
    }

    /// Session keys from the writer's device: kept, tied to that device (a post in them counts as the writer's only).
    fn store_jam_sessions(&self, conn: &Connection, jam_id: &str, sender: &str, device: &str, payload: &Value) -> Result<(), StoreError> {
        let Some(entries) = payload.get("sessions").and_then(Value::as_array) else { return Ok(()) };
        for entry in entries.iter().take(SESSIONS_PER_OP) {
            let text = |k: &str| entry.get(k).and_then(Value::as_str);
            let (Some(session_id), Some(tier), Some(key)) = (text("session_id"), text("tier"), text("key")) else { continue };
            if !jam_store::valid_tier(tier) || jam_store::load_inbound(conn, &self.pickle_key, session_id)?.is_some() {
                continue; // never replace a session that has moved on
            }
            // A key made just now is a session key; the archive's keys (the first index of an older session) are exported keys.
            let session = match SessionKey::from_base64(key) {
                Ok(key) => InboundGroupSession::new(&key, MegolmConfig::version_1()),
                Err(_) => match ExportedSessionKey::from_base64(key) {
                    Ok(key) => InboundGroupSession::import(&key, MegolmConfig::version_1()),
                    Err(_) => continue,
                },
            };
            if session.session_id() != session_id {
                continue;
            }
            jam_store::save_inbound(
                conn,
                &self.pickle_key,
                session_id,
                &jam_store::Inbound { session, jam_id: jam_id.to_owned(), owner_user: sender.to_owned(), owner_device: device.to_owned(), tier: tier.to_owned() },
            )?;
        }
        Ok(())
    }

    /// Decrypts and keeps one post. `message` is the Megolm ciphertext of a session this phone holds (`inbound`). Whose post it is comes from the
    /// session (the writer's device that shared it, verified then), and the signed envelope inside must agree; a post whose tier is not its
    /// session's is refused.
    pub(super) fn process_jam_message(&self, me: &str, session_id: &str, message: &MegolmMessage, mut inbound: jam_store::Inbound, now: i64) -> Result<Outcome, StoreError> {
        let Ok(decrypted) = inbound.session.decrypt(message) else { return Ok(Outcome::Keep(pending::DECRYPT_FAILED)) };
        let Some(inner) = SealedInner::from_bytes(&decrypted.plaintext) else { return Ok(Outcome::Keep(pending::INVALID)) };
        let cert = &inner.sender_cert;
        let conversation = jam_store::conversation_id(&inbound.jam_id);
        let op = &inner.op;
        let valid = inner.sender_user == inbound.owner_user
            && inner.sender_device == inbound.owner_device
            && inner.sender_device == cert.device_id
            && inner.sender_user != me
            && cert.verify()
            && op.verify(&cert.signing_key)
            && op.op_type == "jam.post"
            && op.conversation_id == conversation;
        let payload = &op.payload;
        let text = |k: &str| payload.get(k).and_then(Value::as_str);
        let attachments = crate::store::attachments::parse_payload(payload);
        let (true, Some(title), Some(markdown), Some(attachments), Some(remote_hlc)) = (
            valid && text("post_id") == Some(op.op_id.as_str()) && text("tier") == Some(inbound.tier.as_str()),
            text("title").and_then(|t| jam_store::clean_line(t, jam_store::MAX_POST_TITLE_CHARS)),
            text("markdown").filter(|m| m.len() <= jam_store::MAX_POST_BYTES).map(crate::format::normalise),
            attachments,
            Hlc::parse(&op.hlc),
        ) else {
            return Ok(Outcome::Keep(pending::INVALID));
        };
        if markdown.is_empty() && attachments.is_empty() {
            return Ok(Outcome::Keep(pending::INVALID));
        }
        let author = inner.sender_user.clone();
        let outcome = self.with_conn(|conn| {
            // The writer's master key must be the one pinned when their session key arrived.
            let pinned: Option<String> = conn.query_row("SELECT master_key FROM peers WHERE user_id = ?1", params![author], |r| r.get(0)).optional().map_err(db_err)?;
            if pinned.as_deref() != Some(cert.master_key.as_str()) {
                return Ok(Outcome::Keep(pending::INVALID));
            }
            // Only the jam's own writer, and only while I follow it: a post from anyone else, or after I left, is not kept.
            let Some(jam) = jam_store::get(conn, &inbound.jam_id)? else { return Ok(Outcome::Keep(pending::INVALID)) };
            if jam.mine || jam.writer != author || matches!(jam.status.as_str(), "removed" | "left") {
                return Ok(Outcome::Keep(pending::INVALID));
            }
            jam_store::save_inbound(conn, &self.pickle_key, session_id, &inbound)?;
            let plain = crate::format::plain_text(&markdown);
            let attachments_value = crate::store::attachments::payload_value(&attachments);
            jam_store::insert_received_post(
                conn,
                &op.op_id,
                &inbound.jam_id,
                &author,
                session_id,
                decrypted.message_index,
                &inbound.tier,
                &title,
                &markdown,
                &plain,
                &attachments_value,
                remote_hlc.wall.min(now),
            )?;
            Ok(Outcome::Duplicate)
        })?;
        if matches!(outcome, Outcome::Duplicate) {
            self.with_conn(|conn| observe_hlc(conn, remote_hlc, now).map(|_| ()))?;
        }
        Ok(outcome)
    }
}

// ---------------------------------------------------------------- the send queue

/// A pass sends at most this many recipients; the rest wait for the next pass.
const _: () = assert!(jam_store::RECIPIENTS_PER_PASS <= 500, "the server takes 500 devices per request");

impl LimeStore {
    /// Sends what is due in the jam queue: each post's ciphertext to its waiting subscribers, a chunk at a time. A person whose key changed, or
    /// who has no devices, is dropped (nobody to give it to); a failed try waits longer each time; no internet stops the pass and keeps everything.
    /// Never holds up the messages.
    pub(super) fn deliver_jam_wires(&self, transport: &Arc<dyn Transport>, token: &str) {
        let mut budget = jam_store::RECIPIENTS_PER_PASS;
        while budget > 0 {
            let now = now_ms();
            let Ok(Some(due)) = self.with_conn(|conn| jam_store::next_due(conn, now, budget.min(jam_store::WIRE_CHUNK))) else { return };
            if due.rows.is_empty() {
                return;
            }
            let ids: Vec<i64> = due.rows.iter().map(|(id, _, _)| *id).collect();
            if due.wire.is_empty() {
                let _ = self.with_conn(|conn| jam_store::done(conn, &ids));
                continue;
            }
            budget = budget.saturating_sub(due.rows.len());
            // Everyone's devices (a person whose key changed, or with no devices, is left out of this send).
            let mut audience: Vec<(String, Vec<String>)> = Vec::new();
            let mut dropped: Vec<i64> = Vec::new();
            let mut failed: Vec<(i64, String, i64)> = Vec::new();
            for (id, user, attempts) in &due.rows {
                match self.recipient_devices(transport, token, user) {
                    Ok(devices) => audience.push((user.clone(), devices.into_iter().map(|d| d.device_id).collect())),
                    Err(StoreError::KeyMismatch | StoreError::NoRecipientKeys) => dropped.push(*id),
                    Err(StoreError::Network) => return,
                    Err(_) => failed.push((*id, user.clone(), *attempts)),
                }
            }
            let _ = self.with_conn(|conn| jam_store::done(conn, &dropped));
            if !failed.is_empty() {
                let _ = self.with_conn(|conn| jam_store::back_off(conn, &failed, now));
            }
            let sent: Vec<i64> = due.rows.iter().filter(|(id, _, _)| !dropped.contains(id) && !failed.iter().any(|f| f.0 == *id)).map(|r| r.0).collect();
            if audience.is_empty() {
                continue;
            }
            match self.send_group_wire(transport, token, &due.wire, audience, None) {
                Ok(()) => {
                    let _ = self.with_conn(|conn| jam_store::done(conn, &sent));
                }
                Err(StoreError::Network) => return,
                Err(_) => {
                    let rows: Vec<(i64, String, i64)> = due.rows.iter().filter(|r| sent.contains(&r.0)).cloned().collect();
                    let _ = self.with_conn(|conn| jam_store::back_off(conn, &rows, now));
                }
            }
        }
    }
}
