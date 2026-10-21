//! jam (LIME-186, `docs/jam.md`): a one-author encrypted channel. A teacher (the writer) makes a jam; anyone signed in can subscribe; the writer's
//! phone publishes posts under a Megolm session per tier and hands each subscriber the keys, including the whole archive's. Nothing here is on the
//! server: it carries ciphertext only.
//!
//! This file is the data and the rules (tables, sessions, the queue). The sending and receiving are in `client::jam`.

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::Value;
use vodozemac::megolm::{GroupSession, GroupSessionPickle, InboundGroupSession, InboundGroupSessionPickle, SessionConfig};

use super::{db_err, StoreError};

/// A jam holds at most this many subscribers (a further subscribe gets a polite "full").
pub(crate) const MAX_SUBSCRIBERS: i64 = 1000;
/// A session is replaced after this many posts, or this long (and on a removal, and when the jam ends; never on a join).
pub(crate) const ROTATE_AFTER_POSTS: i64 = 100;
pub(crate) const ROTATE_AFTER_MS: i64 = 7 * 24 * 3_600 * 1000;
/// How many recipients one delivery pass sends to (the server takes 500 devices per request; the client sends in chunks inside that).
pub(crate) const RECIPIENTS_PER_PASS: usize = 500;
/// Recipients that share one ciphertext, per send round.
pub(crate) const WIRE_CHUNK: usize = 100;

pub(crate) const TIER_FREE: &str = "free";
pub(crate) const TIER_SUBSCRIBERS: &str = "subscribers";

pub(crate) fn conversation_id(jam_id: &str) -> String {
    format!("jam:{jam_id}")
}

/// The jam id of a `jam:` conversation id, if it is one.
pub(crate) fn jam_id_of(conversation_id: &str) -> Option<&str> {
    conversation_id.strip_prefix("jam:").filter(|id| !id.is_empty() && id.len() <= 64)
}

pub(crate) fn is_jam_op(op_type: &str) -> bool {
    op_type.starts_with("jam.")
}

pub(crate) fn valid_tier(tier: &str) -> bool {
    tier == TIER_FREE || tier == TIER_SUBSCRIBERS
}

/// The tiers whose keys a subscriber of `tier` may hold: a free subscriber only the free session, a paying one both.
pub(crate) fn tiers_for(subscriber_tier: &str) -> &'static [&'static str] {
    if subscriber_tier == TIER_SUBSCRIBERS {
        &[TIER_FREE, TIER_SUBSCRIBERS]
    } else {
        &[TIER_FREE]
    }
}

// ---------------------------------------------------------------- cleaning what a person typed

pub(crate) const MAX_TITLE_CHARS: usize = 60;
pub(crate) const MAX_ABOUT_CHARS: usize = 500;
pub(crate) const MAX_TOPICS: usize = 8;
pub(crate) const MAX_TOPIC_CHARS: usize = 30;
pub(crate) const MAX_POST_TITLE_CHARS: usize = 120;
pub(crate) const MAX_POST_BYTES: usize = 30_000;

pub(crate) fn clean_line(text: &str, max: usize) -> Option<String> {
    let text: String = text.split_whitespace().collect::<Vec<_>>().join(" ");
    (!text.is_empty() && text.chars().count() <= max).then_some(text)
}

pub(crate) fn clean_about(text: &str) -> Option<String> {
    let text = text.trim().to_owned();
    (text.chars().count() <= MAX_ABOUT_CHARS).then_some(text)
}

pub(crate) fn clean_topics(topics: &[String]) -> Option<Vec<String>> {
    let mut out: Vec<String> = Vec::new();
    for topic in topics {
        let Some(clean) = clean_line(topic, MAX_TOPIC_CHARS) else { continue };
        if !out.iter().any(|t| t.eq_ignore_ascii_case(&clean)) {
            out.push(clean);
        }
    }
    (out.len() <= MAX_TOPICS).then_some(out)
}

/// Every jam has a free tier: a writer cannot make a subscribers-only jam. `None` is a tier list without `free` (or with an unknown tier).
pub(crate) fn clean_tiers(tiers: &[String]) -> Option<Vec<String>> {
    if !tiers.iter().all(|t| valid_tier(t)) || !tiers.iter().any(|t| t == TIER_FREE) {
        return None;
    }
    let mut out: Vec<String> = Vec::new();
    for tier in tiers {
        if !out.contains(tier) {
            out.push(tier.clone());
        }
    }
    Some(out)
}

// ---------------------------------------------------------------- the jam row

#[derive(Debug, Clone)]
pub(crate) struct JamRow {
    pub jam_id: String,
    pub writer: String,
    pub title: String,
    pub about: String,
    pub topics: Vec<String>,
    pub tiers: Vec<String>,
    pub state_hlc: String,
    pub mine: bool,
    /// Mine: `active`. A subscription: `requested`, `active`, `full`, `removed` (by the writer) or `left`.
    pub status: String,
    pub ended: bool,
    pub created: i64,
}

fn read_row(r: &rusqlite::Row<'_>) -> rusqlite::Result<JamRow> {
    let list = |text: String| serde_json::from_str::<Vec<String>>(&text).unwrap_or_default();
    Ok(JamRow {
        jam_id: r.get(0)?,
        writer: r.get(1)?,
        title: r.get(2)?,
        about: r.get(3)?,
        topics: list(r.get(4)?),
        tiers: list(r.get(5)?),
        state_hlc: r.get(6)?,
        mine: r.get(7)?,
        status: r.get(8)?,
        ended: r.get(9)?,
        created: r.get(10)?,
    })
}

const ROW: &str = "SELECT jam_id, writer, title, about, topics, tiers, state_hlc, mine, status, ended, created FROM jams";

pub(crate) fn get(conn: &Connection, jam_id: &str) -> Result<Option<JamRow>, StoreError> {
    conn.query_row(&format!("{ROW} WHERE jam_id = ?1"), params![jam_id], read_row).optional().map_err(db_err)
}

pub(crate) fn list(conn: &Connection, mine: bool) -> Result<Vec<JamRow>, StoreError> {
    let mut statement = conn.prepare(&format!("{ROW} WHERE mine = ?1 ORDER BY created DESC, jam_id")).map_err(db_err)?;
    let rows = statement.query_map(params![mine], read_row).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(rows)
}

pub(crate) fn subscriber_count(conn: &Connection, jam_id: &str) -> Result<i64, StoreError> {
    conn.query_row("SELECT COUNT(*) FROM jam_subscribers WHERE jam_id = ?1 AND status = 'active'", params![jam_id], |r| r.get(0)).map_err(db_err)
}

pub(crate) fn post_count(conn: &Connection, jam_id: &str) -> Result<i64, StoreError> {
    conn.query_row("SELECT COUNT(*) FROM jam_posts WHERE jam_id = ?1 AND deleted_at IS NULL", params![jam_id], |r| r.get(0)).map_err(db_err)
}

/// The people a post of `tier` goes to: the active subscribers whose tier lets them read it.
pub(crate) fn audience(conn: &Connection, jam_id: &str, tier: &str) -> Result<Vec<String>, StoreError> {
    let mut statement = conn
        .prepare(
            "SELECT user_id FROM jam_subscribers WHERE jam_id = ?1 AND status = 'active' AND (?2 = 'free' OR tier = 'subscribers') ORDER BY since, user_id",
        )
        .map_err(db_err)?;
    let rows = statement.query_map(params![jam_id, tier], |r| r.get::<_, String>(0)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(rows)
}

pub(crate) fn subscriber(conn: &Connection, jam_id: &str, user: &str) -> Result<Option<(String, String)>, StoreError> {
    conn.query_row("SELECT status, tier FROM jam_subscribers WHERE jam_id = ?1 AND user_id = ?2", params![jam_id, user], |r| Ok((r.get(0)?, r.get(1)?)))
        .optional()
        .map_err(db_err)
}

// ---------------------------------------------------------------- the writer's sessions

/// This device's outbound session for one tier of one jam.
pub(crate) struct Outbound {
    pub session: GroupSession,
    pub created_at: i64,
    pub posts: i64,
    pub rotate: bool,
}

pub(crate) fn load_outbound(conn: &Connection, pickle_key: &[u8; 32], jam_id: &str, tier: &str) -> Result<Option<Outbound>, StoreError> {
    let row: Option<(String, i64, i64, bool)> = conn
        .query_row(
            "SELECT pickle, created_at, posts, rotate FROM jam_outbound WHERE jam_id = ?1 AND tier = ?2",
            params![jam_id, tier],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
        )
        .optional()
        .map_err(db_err)?;
    let Some((pickle, created_at, posts, rotate)) = row else { return Ok(None) };
    let session = GroupSession::from_pickle(GroupSessionPickle::from_encrypted(&pickle, pickle_key).map_err(|_| StoreError::BadMessage)?);
    Ok(Some(Outbound { session, created_at, posts, rotate }))
}

pub(crate) fn save_outbound(conn: &Connection, pickle_key: &[u8; 32], jam_id: &str, tier: &str, o: &Outbound) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO jam_outbound (jam_id, tier, pickle, session_id, created_at, posts, rotate) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
         ON CONFLICT (jam_id, tier) DO UPDATE SET pickle = ?3, session_id = ?4, created_at = ?5, posts = ?6, rotate = ?7",
        params![jam_id, tier, o.session.pickle().encrypt(pickle_key), o.session.session_id(), o.created_at, o.posts, o.rotate],
    )
    .map_err(db_err)?;
    Ok(())
}

pub(crate) fn mark_rotate(conn: &Connection, jam_id: &str) -> Result<(), StoreError> {
    conn.execute("UPDATE jam_outbound SET rotate = 1 WHERE jam_id = ?1", params![jam_id]).map_err(db_err)?;
    Ok(())
}

pub(crate) fn delete_outbound(conn: &Connection, jam_id: &str) -> Result<(), StoreError> {
    conn.execute("DELETE FROM jam_outbound WHERE jam_id = ?1", params![jam_id]).map_err(db_err)?;
    Ok(())
}

/// Remembers a session the writer made: its key at the first message index, kept for ever (encrypted), so any later subscriber can be handed
/// the whole archive of that session.
pub(crate) fn record_session(conn: &Connection, pickle_key: &[u8; 32], jam_id: &str, tier: &str, session: &GroupSession, now: i64) -> Result<(), StoreError> {
    let first = InboundGroupSession::new(&session.session_key(), SessionConfig::version_1());
    conn.execute(
        "INSERT OR IGNORE INTO jam_sessions (session_id, jam_id, tier, first_key, created) VALUES (?1, ?2, ?3, ?4, ?5)",
        params![session.session_id(), jam_id, tier, first.pickle().encrypt(pickle_key), now],
    )
    .map_err(db_err)?;
    conn.execute("UPDATE jam_sessions SET rotated_at = ?3 WHERE jam_id = ?1 AND tier = ?2 AND session_id != ?4 AND rotated_at IS NULL", params![jam_id, tier, now, session.session_id()])
        .map_err(db_err)?;
    Ok(())
}

/// The sessions a subscriber of `tier` may hold, oldest first, as (session id, tier, first-index key in base64).
pub(crate) fn session_keys(conn: &Connection, pickle_key: &[u8; 32], jam_id: &str, subscriber_tier: &str) -> Result<Vec<(String, String, String)>, StoreError> {
    let mut statement = conn.prepare("SELECT session_id, tier, first_key FROM jam_sessions WHERE jam_id = ?1 ORDER BY created, session_id").map_err(db_err)?;
    let rows = statement
        .query_map(params![jam_id], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, String>(2)?)))
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    let mut out = Vec::new();
    for (session_id, tier, first_key) in rows {
        if !tiers_for(subscriber_tier).contains(&tier.as_str()) {
            continue;
        }
        let pickle = InboundGroupSessionPickle::from_encrypted(&first_key, pickle_key).map_err(|_| StoreError::BadMessage)?;
        let session = InboundGroupSession::from_pickle(pickle);
        out.push((session_id, tier, session.export_at_first_known_index().to_base64()));
    }
    Ok(out)
}

// ---------------------------------------------------------------- the subscriber's sessions

pub(crate) struct Inbound {
    pub session: InboundGroupSession,
    pub jam_id: String,
    pub owner_user: String,
    pub owner_device: String,
    pub tier: String,
}

pub(crate) fn load_inbound(conn: &Connection, pickle_key: &[u8; 32], session_id: &str) -> Result<Option<Inbound>, StoreError> {
    let row: Option<(String, String, String, String, String)> = conn
        .query_row(
            "SELECT pickle, jam_id, owner_user, owner_device, tier FROM jam_inbound WHERE session_id = ?1",
            params![session_id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?)),
        )
        .optional()
        .map_err(db_err)?;
    let Some((pickle, jam_id, owner_user, owner_device, tier)) = row else { return Ok(None) };
    let session = InboundGroupSession::from_pickle(InboundGroupSessionPickle::from_encrypted(&pickle, pickle_key).map_err(|_| StoreError::BadMessage)?);
    Ok(Some(Inbound { session, jam_id, owner_user, owner_device, tier }))
}

pub(crate) fn save_inbound(conn: &Connection, pickle_key: &[u8; 32], session_id: &str, i: &Inbound) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO jam_inbound (session_id, jam_id, owner_user, owner_device, tier, pickle) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
         ON CONFLICT (session_id) DO UPDATE SET pickle = ?6",
        params![session_id, i.jam_id, i.owner_user, i.owner_device, i.tier, i.session.pickle().encrypt(pickle_key)],
    )
    .map_err(db_err)?;
    Ok(())
}

// ---------------------------------------------------------------- posts

#[derive(Debug, Clone)]
pub(crate) struct PostRow {
    pub post_id: String,
    pub jam_id: String,
    pub author: String,
    pub tier: String,
    pub title: String,
    pub markdown: String,
    pub plain: String,
    pub attachments: String,
    pub created: i64,
    pub deleted: bool,
}

const POST: &str = "SELECT post_id, jam_id, author, tier, title, markdown, plain, attachments, created, deleted_at IS NOT NULL FROM jam_posts";

fn read_post(r: &rusqlite::Row<'_>) -> rusqlite::Result<PostRow> {
    Ok(PostRow {
        post_id: r.get(0)?,
        jam_id: r.get(1)?,
        author: r.get(2)?,
        tier: r.get(3)?,
        title: r.get(4)?,
        markdown: r.get(5)?,
        plain: r.get(6)?,
        attachments: r.get(7)?,
        created: r.get(8)?,
        deleted: r.get(9)?,
    })
}

pub(crate) fn posts(conn: &Connection, jam_id: &str) -> Result<Vec<PostRow>, StoreError> {
    let mut statement = conn.prepare(&format!("{POST} WHERE jam_id = ?1 AND deleted_at IS NULL ORDER BY created, post_id")).map_err(db_err)?;
    let rows = statement.query_map(params![jam_id], read_post).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(rows)
}

pub(crate) fn post(conn: &Connection, post_id: &str) -> Result<Option<PostRow>, StoreError> {
    conn.query_row(&format!("{POST} WHERE post_id = ?1"), params![post_id], read_post).optional().map_err(db_err)
}

/// Keeps a post a subscriber received; `false` if it was already there.
#[allow(clippy::too_many_arguments)] // one column each
pub(crate) fn insert_received_post(
    conn: &Connection,
    post_id: &str,
    jam_id: &str,
    author: &str,
    session_id: &str,
    index: u32,
    tier: &str,
    title: &str,
    markdown: &str,
    plain: &str,
    attachments: &Value,
    created: i64,
) -> Result<bool, StoreError> {
    let n = conn
        .execute(
            "INSERT OR IGNORE INTO jam_posts (post_id, jam_id, author, session_id, idx, tier, title, markdown, plain, attachments, created)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
            params![post_id, jam_id, author, session_id, index, tier, title, markdown, plain, attachments.to_string(), created],
        )
        .map_err(db_err)?;
    Ok(n > 0)
}

// ---------------------------------------------------------------- the send queue

/// One row per (post, subscriber) still to be sent: persistent, so it survives a restart and resumes; ordered by id.
pub(crate) fn queue_wire(conn: &Connection, jam_id: &str, post_id: &str, recipients: &[String]) -> Result<(), StoreError> {
    for recipient in recipients {
        conn.execute("INSERT INTO jam_wire_outbox (jam_id, post_id, recipient) VALUES (?1, ?2, ?3)", params![jam_id, post_id, recipient]).map_err(db_err)?;
    }
    Ok(())
}

pub(crate) struct DueWire {
    pub wire: String,
    /// (row id, recipient, attempts)
    pub rows: Vec<(i64, String, i64)>,
}

/// The next ciphertext with recipients due, up to `limit` of them.
pub(crate) fn next_due(conn: &Connection, now: i64, limit: usize) -> Result<Option<DueWire>, StoreError> {
    let first: Option<String> = conn.query_row("SELECT post_id FROM jam_wire_outbox WHERE next_at <= ?1 ORDER BY id LIMIT 1", params![now], |r| r.get(0)).optional().map_err(db_err)?;
    let Some(post_id) = first else { return Ok(None) };
    let wire: Option<String> = conn.query_row("SELECT wire FROM jam_posts WHERE post_id = ?1", params![post_id], |r| r.get(0)).optional().map_err(db_err)?.flatten();
    let mut statement = conn
        .prepare("SELECT id, recipient, attempts FROM jam_wire_outbox WHERE post_id = ?1 AND next_at <= ?2 ORDER BY id LIMIT ?3")
        .map_err(db_err)?;
    let rows = statement
        .query_map(params![post_id, now, limit as i64], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?, r.get::<_, i64>(2)?)))
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    Ok(Some(DueWire { wire: wire.unwrap_or_default(), rows }))
}

pub(crate) fn done(conn: &Connection, ids: &[i64]) -> Result<(), StoreError> {
    for id in ids {
        conn.execute("DELETE FROM jam_wire_outbox WHERE id = ?1", params![id]).map_err(db_err)?;
    }
    Ok(())
}

/// A failed try: wait longer each time (30 s, 1 min, 2 min... up to an hour).
pub(crate) fn back_off(conn: &Connection, rows: &[(i64, String, i64)], now: i64) -> Result<(), StoreError> {
    for (id, _, attempts) in rows {
        let wait = (30_000_i64 << (*attempts).clamp(0, 7)).min(3_600_000);
        conn.execute("UPDATE jam_wire_outbox SET attempts = attempts + 1, next_at = ?2 WHERE id = ?1", params![id, now + wait]).map_err(db_err)?;
    }
    Ok(())
}

/// How much of what is queued for a jam has gone: (still waiting, the total those posts were queued for).
pub(crate) fn progress(conn: &Connection, jam_id: &str) -> Result<(i64, i64), StoreError> {
    let pending: i64 = conn.query_row("SELECT COUNT(*) FROM jam_wire_outbox WHERE jam_id = ?1", params![jam_id], |r| r.get(0)).map_err(db_err)?;
    if pending == 0 {
        return Ok((0, 0));
    }
    let total: i64 = conn
        .query_row(
            "SELECT COALESCE(SUM(fanout_total), 0) FROM jam_posts WHERE post_id IN (SELECT DISTINCT post_id FROM jam_wire_outbox WHERE jam_id = ?1)",
            params![jam_id],
            |r| r.get(0),
        )
        .map_err(db_err)?;
    Ok((pending, total.max(pending)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_jam_always_has_a_free_tier() {
        assert_eq!(clean_tiers(&["free".into()]), Some(vec!["free".into()]));
        assert_eq!(clean_tiers(&["subscribers".into(), "free".into(), "free".into()]), Some(vec!["subscribers".into(), "free".into()]));
        assert_eq!(clean_tiers(&["subscribers".into()]), None, "a writer cannot be paywall-only");
        assert_eq!(clean_tiers(&[]), None);
        assert_eq!(clean_tiers(&["free".into(), "vip".into()]), None, "an unknown tier");
    }

    #[test]
    fn what_is_typed_is_cleaned() {
        assert_eq!(clean_line("  Grade   4 \n maths ", 60).as_deref(), Some("Grade 4 maths"));
        assert_eq!(clean_line("   ", 60), None);
        assert_eq!(clean_topics(&["Maths".into(), "maths".into(), " ".into(), "Reading".into()]), Some(vec!["Maths".into(), "Reading".into()]));
        assert_eq!(clean_topics(&(0..9).map(|i| format!("t{i}")).collect::<Vec<_>>()), None, "at most eight");
        assert_eq!(jam_id_of("jam:abc"), Some("abc"));
        assert_eq!(jam_id_of("grp:abc"), None);
        assert!(tiers_for("free") == [TIER_FREE] && tiers_for("subscribers").len() == 2);
    }
}
