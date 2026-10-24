//! jam (LIME-186, `docs/jam.md`): a one-author encrypted channel. A teacher (the writer) makes a jam; anyone signed in can subscribe; the writer's
//! phone publishes posts under a Megolm session per tier and hands each subscriber the keys, including the whole archive's. Nothing here is on the
//! server: it carries ciphertext only.
//!
//! This file is the data and the rules (tables, sessions, the queue). The sending and receiving are in `client::jam`.

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::Value;
use vodozemac::megolm::{GroupSession, GroupSessionPickle, InboundGroupSession, InboundGroupSessionPickle};

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
/// How many people one pass sends an Olm op to (a key, a welcome). Each costs a request per device and may claim a one-time key, which the server
/// limits (60 claims and 120 items a minute), so a pass stays inside that and the rest waits for the next.
pub(crate) const OPS_PER_PASS: usize = 60;
/// How many posts one pass uploads or downloads.
pub(crate) const BLOBS_PER_PASS: usize = 20;

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

/// The kinds of post: a quick post (no title), an article (title, subtitle, body), a recording (a video or voice clip).
pub(crate) const KINDS: [&str; 3] = ["quick", "article", "record"];

pub(crate) fn valid_kind(kind: &str) -> bool {
    KINDS.contains(&kind)
}

pub(crate) const MAX_SUBTITLE_CHARS: usize = 160;

/// A title that may be empty (a quick post has none).
pub(crate) fn clean_optional_line(text: &str, max: usize) -> Option<String> {
    let text: String = text.split_whitespace().collect::<Vec<_>>().join(" ");
    (text.chars().count() <= max).then_some(text)
}

pub(crate) fn valid_tier(tier: &str) -> bool {
    tier == TIER_FREE || tier == TIER_SUBSCRIBERS
}

/// The tiers a subscriber of a tier may read: a free subscriber only the free posts, a paying one both.
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
    pub kind: String,
    pub subtitle: String,
    /// 0 not downloaded yet, 1 ready, 2 gone from the server.
    pub fetched: i64,
    /// `person` or `jam`: who the post is shown as written by (LIME-188q).
    pub display_as: String,
    /// When it was last edited (milliseconds), 0 if never (LIME-195).
    pub edited_at: i64,
}

const POST: &str = "SELECT post_id, jam_id, author, tier, title, markdown, plain, attachments, created, deleted_at IS NOT NULL, fetched, kind, subtitle, display_as, COALESCE(edited_at, 0) FROM jam_posts";

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
        fetched: r.get(10)?,
        kind: r.get(11)?,
        subtitle: r.get(12)?,
        display_as: r.get(13)?,
        edited_at: r.get(14)?,
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

/// A post's blob on the server: where it is, the key that opens it and what it must hash to.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct BlobRef {
    pub blob_id: String,
    pub key: String,
    pub sha256: String,
    pub size: i64,
}

/// What a subscriber learns of a post from a notice or from the welcome's index: its title and where the content is. The content itself is fetched
/// later, from the server, without a session. `false` if the post was already known.
#[allow(clippy::too_many_arguments)] // one column each
pub(crate) fn insert_notice(
    conn: &Connection,
    post_id: &str,
    jam_id: &str,
    author: &str,
    session_id: &str,
    index: u32,
    tier: &str,
    title: &str,
    kind: &str,
    subtitle: &str,
    created: i64,
    blob: &BlobRef,
) -> Result<bool, StoreError> {
    let n = conn
        .execute(
            "INSERT OR IGNORE INTO jam_posts (post_id, jam_id, author, session_id, idx, tier, title, markdown, plain, attachments, created, blob_id, blob_key, blob_sha, blob_size, uploaded, fetched, kind, subtitle)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, '', '', '[]', ?8, ?9, ?10, ?11, ?12, 1, 0, ?13, ?14)",
            params![post_id, jam_id, author, session_id, index, tier, title, created, blob.blob_id, blob.key, blob.sha256, blob.size, kind, subtitle],
        )
        .map_err(db_err)?;
    Ok(n > 0)
}

/// The posts whose content a subscriber has not downloaded yet, oldest first.
pub(crate) fn to_fetch(conn: &Connection, limit: usize) -> Result<Vec<(String, BlobRef)>, StoreError> {
    let mut statement = conn
        .prepare("SELECT post_id, blob_id, blob_key, blob_sha, blob_size FROM jam_posts WHERE fetched = 0 AND blob_id IS NOT NULL ORDER BY created, post_id LIMIT ?1")
        .map_err(db_err)?;
    let rows = statement
        .query_map(params![limit as i64], |r| Ok((r.get::<_, String>(0)?, BlobRef { blob_id: r.get(1)?, key: r.get(2)?, sha256: r.get(3)?, size: r.get(4)? })))
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    Ok(rows)
}

/// A downloaded post's content (`fetched = 1`), or that it is gone from the server (`fetched = 2`).
pub(crate) fn set_fetched(conn: &Connection, post_id: &str, content: Option<(&str, &str, &Value, &str)>) -> Result<(), StoreError> {
    match content {
        Some((markdown, plain, attachments, display_as)) => conn
            .execute("UPDATE jam_posts SET markdown = ?2, plain = ?3, attachments = ?4, display_as = ?5, fetched = 1 WHERE post_id = ?1", params![post_id, markdown, plain, attachments.to_string(), display_as])
            .map_err(db_err)?,
        None => conn.execute("UPDATE jam_posts SET fetched = 2 WHERE post_id = ?1", params![post_id]).map_err(db_err)?,
    };
    Ok(())
}

/// The writer's posts whose blob is not on the server yet, oldest first, with what is needed to make it again.
pub(crate) struct Unuploaded {
    pub post_id: String,
    pub jam_id: String,
    pub tier: String,
    pub title: String,
    pub kind: String,
    pub subtitle: String,
    pub markdown: String,
    pub attachments: String,
    pub created: i64,
    pub blob: BlobRef,
    pub display_as: String,
}

pub(crate) fn to_upload(conn: &Connection, limit: usize) -> Result<Vec<Unuploaded>, StoreError> {
    let mut statement = conn
        .prepare(
            "SELECT post_id, jam_id, tier, title, markdown, attachments, created, blob_id, blob_key, blob_sha, blob_size, kind, subtitle, display_as FROM jam_posts
             WHERE uploaded = 0 AND wire IS NOT NULL AND deleted_at IS NULL
             AND NOT EXISTS (SELECT 1 FROM jam_attachments a WHERE a.post_id = jam_posts.post_id AND a.uploaded = 0) ORDER BY created, post_id LIMIT ?1",
        )
        .map_err(db_err)?;
    let rows = statement
        .query_map(params![limit as i64], |r| {
            Ok(Unuploaded {
                post_id: r.get(0)?,
                jam_id: r.get(1)?,
                tier: r.get(2)?,
                title: r.get(3)?,
                markdown: r.get(4)?,
                attachments: r.get(5)?,
                created: r.get(6)?,
                blob: BlobRef { blob_id: r.get(7)?, key: r.get(8)?, sha256: r.get(9)?, size: r.get(10)? },
                kind: r.get(11)?,
                subtitle: r.get(12)?,
                display_as: r.get(13)?,
            })
        })
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    Ok(rows)
}

pub(crate) fn set_uploaded(conn: &Connection, post_id: &str, jam_id: &str) -> Result<(), StoreError> {
    conn.execute("UPDATE jam_posts SET uploaded = 1 WHERE post_id = ?1", params![post_id]).map_err(db_err)?;
    conn.execute("UPDATE jams SET page_state = 'dirty' WHERE jam_id = ?1 AND page_state <> 'end'", params![jam_id]).map_err(db_err)?;
    Ok(())
}

/// The index a new subscriber is handed: every uploaded post it may read, oldest first.
/// (post id, tier, title, created, blob, kind, subtitle)
pub(crate) type IndexEntry = (String, String, String, i64, BlobRef, String, String);

pub(crate) fn index_for(conn: &Connection, jam_id: &str, subscriber_tier: &str) -> Result<Vec<IndexEntry>, StoreError> {
    let mut statement = conn
        .prepare(
            "SELECT post_id, tier, title, created, blob_id, blob_key, blob_sha, blob_size, kind, subtitle FROM jam_posts
             WHERE jam_id = ?1 AND uploaded = 1 AND deleted_at IS NULL AND blob_id IS NOT NULL AND (?2 = 'subscribers' OR tier = 'free') ORDER BY created, post_id",
        )
        .map_err(db_err)?;
    let rows = statement
        .query_map(params![jam_id, subscriber_tier], |r| {
            Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, BlobRef { blob_id: r.get(4)?, key: r.get(5)?, sha256: r.get(6)?, size: r.get(7)? }, r.get(8)?, r.get(9)?))
        })
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    Ok(rows)
}

/// Posts of a jam still waiting for their blob to go up (a new subscriber is queued their notice, as the index cannot name them yet).
pub(crate) fn not_uploaded_ids(conn: &Connection, jam_id: &str, subscriber_tier: &str) -> Result<Vec<String>, StoreError> {
    let mut statement = conn
        .prepare("SELECT post_id FROM jam_posts WHERE jam_id = ?1 AND uploaded = 0 AND wire IS NOT NULL AND deleted_at IS NULL AND (?2 = 'subscribers' OR tier = 'free') ORDER BY created, post_id")
        .map_err(db_err)?;
    let rows = statement.query_map(params![jam_id, subscriber_tier], |r| r.get(0)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(rows)
}

// ---------------------------------------------------------------- the files of a post

pub(crate) struct AttachmentRow {
    pub post_id: String,
    pub att_id: String,
    pub jam_id: String,
    pub blob_sha: String,
    pub blob_size: i64,
    pub data: Vec<u8>,
}

/// A file the writer attached: kept in plain (to show, and to seal again for the upload) until it is up.
pub(crate) fn insert_attachment(conn: &Connection, post_id: &str, att_id: &str, jam_id: &str, blob_sha: &str, blob_size: i64, data: &[u8]) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO jam_attachments (post_id, att_id, jam_id, blob_sha, blob_size, data, uploaded) VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0)",
        params![post_id, att_id, jam_id, blob_sha, blob_size, data],
    )
    .map_err(db_err)?;
    Ok(())
}

pub(crate) fn attachments_to_upload(conn: &Connection, limit: usize) -> Result<Vec<AttachmentRow>, StoreError> {
    let mut statement = conn
        .prepare("SELECT post_id, att_id, jam_id, blob_sha, blob_size, data FROM jam_attachments WHERE uploaded = 0 AND data IS NOT NULL ORDER BY rowid LIMIT ?1")
        .map_err(db_err)?;
    let rows = statement
        .query_map(params![limit as i64], |r| Ok(AttachmentRow { post_id: r.get(0)?, att_id: r.get(1)?, jam_id: r.get(2)?, blob_sha: r.get(3)?, blob_size: r.get(4)?, data: r.get(5)? }))
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    Ok(rows)
}

pub(crate) fn set_attachment_uploaded(conn: &Connection, post_id: &str, att_id: &str) -> Result<(), StoreError> {
    conn.execute("UPDATE jam_attachments SET uploaded = 1 WHERE post_id = ?1 AND att_id = ?2", params![post_id, att_id]).map_err(db_err)?;
    Ok(())
}

/// The plain bytes of a file, if this phone has them (the writer's own, or downloaded before).
pub(crate) fn attachment_data(conn: &Connection, post_id: &str, att_id: &str) -> Result<Option<Vec<u8>>, StoreError> {
    Ok(conn
        .query_row("SELECT data FROM jam_attachments WHERE post_id = ?1 AND att_id = ?2", params![post_id, att_id], |r| r.get::<_, Option<Vec<u8>>>(0))
        .optional()
        .map_err(db_err)?
        .flatten())
}

pub(crate) fn cache_attachment(conn: &Connection, post_id: &str, att_id: &str, jam_id: &str, blob_sha: &str, blob_size: i64, data: &[u8]) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO jam_attachments (post_id, att_id, jam_id, blob_sha, blob_size, data, uploaded) VALUES (?1, ?2, ?3, ?4, ?5, ?6, 1)
         ON CONFLICT (post_id, att_id) DO UPDATE SET data = ?6",
        params![post_id, att_id, jam_id, blob_sha, blob_size, data],
    )
    .map_err(db_err)?;
    Ok(())
}

// ---------------------------------------------------------------- co-authors

/// A co-author the writer asked (`pending`: not sent yet, waiting for the post's blob; `requested`: sent).
pub(crate) fn add_credit(conn: &Connection, post_id: &str, user: &str) -> Result<(), StoreError> {
    conn.execute("INSERT OR IGNORE INTO jam_credits (post_id, user_id, state) VALUES (?1, ?2, 'pending')", params![post_id, user]).map_err(db_err)?;
    Ok(())
}

pub(crate) fn credits_in_state(conn: &Connection, post_id: &str, state: &str) -> Result<Vec<String>, StoreError> {
    let mut statement = conn.prepare("SELECT user_id FROM jam_credits WHERE post_id = ?1 AND state = ?2 ORDER BY user_id").map_err(db_err)?;
    let rows = statement.query_map(params![post_id, state], |r| r.get::<_, String>(0)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(rows)
}

pub(crate) fn set_credit(conn: &Connection, post_id: &str, user: &str, state: &str) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO jam_credits (post_id, user_id, state) VALUES (?1, ?2, ?3) ON CONFLICT (post_id, user_id) DO UPDATE SET state = ?3",
        params![post_id, user, state],
    )
    .map_err(db_err)?;
    Ok(())
}

pub(crate) fn credit_state(conn: &Connection, post_id: &str, user: &str) -> Result<Option<String>, StoreError> {
    conn.query_row("SELECT state FROM jam_credits WHERE post_id = ?1 AND user_id = ?2", params![post_id, user], |r| r.get(0)).optional().map_err(db_err)
}

/// The posts whose co-authors have been asked but not yet sent the request (the blob had to be up first).
pub(crate) fn credits_to_send(conn: &Connection) -> Result<Vec<(String, String)>, StoreError> {
    let mut statement = conn
        .prepare("SELECT c.post_id, c.user_id FROM jam_credits c JOIN jam_posts p ON p.post_id = c.post_id WHERE c.state = 'pending' AND p.uploaded = 1")
        .map_err(db_err)?;
    let rows = statement.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(rows)
}

// ---------------------------------------------------------------- the public page on the server

pub(crate) fn pages_to_publish(conn: &Connection) -> Result<Vec<JamRow>, StoreError> {
    let mut statement = conn.prepare(&format!("{ROW} WHERE mine = 1 AND ended = 0 AND page_state = 'dirty'")).map_err(db_err)?;
    let rows = statement.query_map([], read_row).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(rows)
}

pub(crate) fn pages_to_end(conn: &Connection) -> Result<Vec<JamRow>, StoreError> {
    let mut statement = conn.prepare(&format!("{ROW} WHERE mine = 1 AND ended = 1 AND page_state = 'end'")).map_err(db_err)?;
    let rows = statement.query_map([], read_row).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(rows)
}

pub(crate) fn uploaded_count(conn: &Connection, jam_id: &str) -> Result<i64, StoreError> {
    conn.query_row("SELECT COUNT(*) FROM jam_posts WHERE jam_id = ?1 AND uploaded = 1 AND deleted_at IS NULL", params![jam_id], |r| r.get(0)).map_err(db_err)
}

/// The page on the server is out of date (a new post, a new subscriber, an edit): publish it again at the next pass.
pub(crate) fn mark_page_dirty(conn: &Connection, jam_id: &str) -> Result<(), StoreError> {
    conn.execute("UPDATE jams SET page_state = 'dirty' WHERE jam_id = ?1 AND page_state <> 'end' AND page_state <> 'done'", params![jam_id]).map_err(db_err)?;
    Ok(())
}

pub(crate) fn set_page_state(conn: &Connection, jam_id: &str, state: &str) -> Result<(), StoreError> {
    conn.execute("UPDATE jams SET page_state = ?2 WHERE jam_id = ?1", params![jam_id, state]).map_err(db_err)?;
    Ok(())
}

// ---------------------------------------------------------------- the send queue

/// One row per (post, subscriber) still to be sent: persistent, so it survives a restart and resumes; ordered by id. (Each counts toward the
/// jam's progress.)
pub(crate) fn queue_wire(conn: &Connection, jam_id: &str, post_id: &str, recipients: &[String]) -> Result<(), StoreError> {
    for recipient in recipients {
        conn.execute("INSERT INTO jam_wire_outbox (jam_id, post_id, recipient) VALUES (?1, ?2, ?3)", params![jam_id, post_id, recipient]).map_err(db_err)?;
    }
    bump_total(conn, jam_id, recipients.len() as i64)
}

/// An Olm op (a key, a welcome, the jam's news) for one person, in the jam's own queue: paced, and counted in the progress.
pub(crate) fn queue_op(conn: &Connection, jam_id: &str, recipient: &str, op_json: &str) -> Result<(), StoreError> {
    conn.execute("INSERT INTO jam_op_outbox (jam_id, recipient, op_json) VALUES (?1, ?2, ?3)", params![jam_id, recipient, op_json]).map_err(db_err)?;
    bump_total(conn, jam_id, 1)
}

fn bump_total(conn: &Connection, jam_id: &str, n: i64) -> Result<(), StoreError> {
    conn.execute("UPDATE jams SET queued_total = queued_total + ?2 WHERE jam_id = ?1", params![jam_id, n]).map_err(db_err)?;
    Ok(())
}

pub(crate) struct DueWire {
    pub wire: String,
    /// (row id, recipient, attempts)
    pub rows: Vec<(i64, String, i64)>,
}

/// The next ciphertext with recipients due, up to `limit` of them. A post whose blob is not up yet is not due (the notice would name nothing); a
/// credit announcement is always due.
pub(crate) fn next_due(conn: &Connection, now: i64, limit: usize) -> Result<Option<DueWire>, StoreError> {
    let first: Option<String> = conn
        .query_row(
            "SELECT o.post_id FROM jam_wire_outbox o WHERE o.next_at <= ?1
               AND (EXISTS (SELECT 1 FROM jam_posts p WHERE p.post_id = o.post_id AND p.uploaded = 1) OR EXISTS (SELECT 1 FROM jam_credit_wires w WHERE w.wire_id = o.post_id))
             ORDER BY o.id LIMIT 1",
            params![now],
            |r| r.get(0),
        )
        .optional()
        .map_err(db_err)?;
    let Some(post_id) = first else { return Ok(None) };
    let wire: Option<String> = conn.query_row("SELECT wire FROM jam_posts WHERE post_id = ?1", params![post_id], |r| r.get(0)).optional().map_err(db_err)?.flatten();
    let wire = match wire {
        Some(wire) => Some(wire),
        None => conn.query_row("SELECT wire FROM jam_credit_wires WHERE wire_id = ?1", params![post_id], |r| r.get(0)).optional().map_err(db_err)?,
    };
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

fn wait_after(attempts: i64) -> i64 {
    (30_000_i64 << attempts.clamp(0, 7)).min(3_600_000)
}

/// A failed try: wait longer each time (30 s, 1 min, 2 min... up to an hour).
pub(crate) fn back_off(conn: &Connection, rows: &[(i64, String, i64)], now: i64) -> Result<(), StoreError> {
    for (id, _, attempts) in rows {
        conn.execute("UPDATE jam_wire_outbox SET attempts = attempts + 1, next_at = ?2 WHERE id = ?1", params![id, now + wait_after(*attempts)]).map_err(db_err)?;
    }
    Ok(())
}

/// The next ops due, oldest first: (row id, jam id, recipient, op json, attempts).
/// (row id, jam id, recipient, op json, attempts)
pub(crate) type DueOp = (i64, String, String, String, i64);

pub(crate) fn next_ops(conn: &Connection, now: i64, limit: usize) -> Result<Vec<DueOp>, StoreError> {
    let mut statement = conn
        .prepare("SELECT id, jam_id, recipient, op_json, attempts FROM jam_op_outbox WHERE next_at <= ?1 ORDER BY id LIMIT ?2")
        .map_err(db_err)?;
    let rows = statement
        .query_map(params![now, limit as i64], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?)))
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    Ok(rows)
}

pub(crate) fn done_op(conn: &Connection, id: i64) -> Result<(), StoreError> {
    conn.execute("DELETE FROM jam_op_outbox WHERE id = ?1", params![id]).map_err(db_err)?;
    Ok(())
}

pub(crate) fn back_off_op(conn: &Connection, id: i64, attempts: i64, now: i64) -> Result<(), StoreError> {
    conn.execute("UPDATE jam_op_outbox SET attempts = attempts + 1, next_at = ?2 WHERE id = ?1", params![id, now + wait_after(attempts)]).map_err(db_err)?;
    Ok(())
}

/// How much of what is queued for a jam has gone: (still waiting, the total queued since the queue was last empty).
pub(crate) fn progress(conn: &Connection, jam_id: &str) -> Result<(i64, i64), StoreError> {
    let wires: i64 = conn.query_row("SELECT COUNT(*) FROM jam_wire_outbox WHERE jam_id = ?1", params![jam_id], |r| r.get(0)).map_err(db_err)?;
    let ops: i64 = conn.query_row("SELECT COUNT(*) FROM jam_op_outbox WHERE jam_id = ?1", params![jam_id], |r| r.get(0)).map_err(db_err)?;
    let pending = wires + ops;
    if pending == 0 {
        conn.execute("UPDATE jams SET queued_total = 0 WHERE jam_id = ?1", params![jam_id]).map_err(db_err)?;
        return Ok((0, 0));
    }
    let total: i64 = conn.query_row("SELECT queued_total FROM jams WHERE jam_id = ?1", params![jam_id], |r| r.get(0)).map_err(db_err)?;
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

// ---------------------------------------------------------------- edit and delete (LIME-195)

/// A post's edit counter (1 for one never edited).
pub(crate) fn version(conn: &Connection, post_id: &str) -> Result<i64, StoreError> {
    Ok(conn.query_row("SELECT version FROM jam_posts WHERE post_id = ?1", params![post_id], |r| r.get(0)).optional().map_err(db_err)?.unwrap_or(0))
}

/// A subscriber takes a newer version of a post: its words are fetched again from the new blob. Only the post's own writer, in its own jam and tier,
/// and only a higher version than the one held. `false` if it was not applied.
#[allow(clippy::too_many_arguments)] // one column each
pub(crate) fn apply_edit(conn: &Connection, post_id: &str, jam_id: &str, author: &str, tier: Option<&str>, version: i64, title: &str, subtitle: &str, blob: &BlobRef, edited_at: i64) -> Result<bool, StoreError> {
    let n = conn
        .execute(
            "UPDATE jam_posts SET title = ?6, subtitle = ?7, blob_id = ?8, blob_key = ?9, blob_sha = ?10, blob_size = ?11, fetched = 0, version = ?5, edited_at = ?12
             WHERE post_id = ?1 AND jam_id = ?2 AND author = ?3 AND (?4 IS NULL OR tier = ?4) AND version < ?5 AND deleted_at IS NULL",
            params![post_id, jam_id, author, tier, version, title, subtitle, blob.blob_id, blob.key, blob.sha256, blob.size, edited_at],
        )
        .map_err(db_err)?;
    Ok(n > 0)
}

/// A subscriber drops a post its writer deleted, with its downloaded files. `false` if there was no such post of that writer.
pub(crate) fn apply_delete(conn: &Connection, post_id: &str, jam_id: &str, author: &str, now: i64) -> Result<bool, StoreError> {
    let n = conn
        .execute("UPDATE jam_posts SET deleted_at = ?4, markdown = '', plain = '', attachments = '[]' WHERE post_id = ?1 AND jam_id = ?2 AND author = ?3 AND deleted_at IS NULL", params![post_id, jam_id, author, now])
        .map_err(db_err)?;
    if n > 0 {
        conn.execute("DELETE FROM jam_attachments WHERE post_id = ?1", params![post_id]).map_err(db_err)?;
        drop_engagement(conn, post_id)?;
    }
    Ok(n > 0)
}

/// Blobs the writer no longer needs on the server, to be told to it.
pub(crate) fn queue_blob_delete(conn: &Connection, blob_id: &str) -> Result<(), StoreError> {
    conn.execute("INSERT OR IGNORE INTO jam_blob_deletes (blob_id) VALUES (?1)", params![blob_id]).map_err(db_err)?;
    Ok(())
}

pub(crate) fn blobs_to_delete(conn: &Connection, limit: usize) -> Result<Vec<String>, StoreError> {
    let mut statement = conn.prepare("SELECT blob_id FROM jam_blob_deletes LIMIT ?1").map_err(db_err)?;
    let rows = statement.query_map(params![limit as i64], |r| r.get(0)).map_err(db_err)?.collect::<Result<Vec<String>, _>>().map_err(db_err)?;
    Ok(rows)
}

pub(crate) fn blob_deleted(conn: &Connection, blob_id: &str) -> Result<(), StoreError> {
    conn.execute("DELETE FROM jam_blob_deletes WHERE blob_id = ?1", params![blob_id]).map_err(db_err)?;
    Ok(())
}

/// The edits whose new blob is up and are not yet announced: (post id, jam id, tier).
pub(crate) fn edits_to_announce(conn: &Connection) -> Result<Vec<(String, String, String)>, StoreError> {
    let mut statement = conn.prepare("SELECT post_id, jam_id, tier FROM jam_posts WHERE edit_pending = 1 AND uploaded = 1 AND deleted_at IS NULL").map_err(db_err)?;
    let rows = statement.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(rows)
}

// ---------------------------------------------------------------- likes, comments and counts (LIME-189)

pub(crate) const MAX_COMMENT_CHARS: usize = 2000;
/// A writer takes at most this many comments a minute from one author.
pub(crate) const COMMENTS_PER_MINUTE: i64 = 20;
/// A post's tally goes out at most this often.
pub(crate) const COUNTS_EVERY_MS: i64 = 60_000;
pub(crate) const MAX_LIKERS: usize = 1000;

/// A deleted post takes its reactions, comments and counts with it.
pub(crate) fn drop_engagement(conn: &Connection, post_id: &str) -> Result<(), StoreError> {
    for table in ["jam_reactions", "jam_my_reactions", "jam_comments", "jam_counts", "jam_counts_out"] {
        conn.execute(&format!("DELETE FROM {table} WHERE post_id = ?1"), params![post_id]).map_err(db_err)?;
    }
    Ok(())
}

/// The writer's tally of a post changed: it goes out with the next pass that is due.
pub(crate) fn mark_counts_dirty(conn: &Connection, post_id: &str) -> Result<(), StoreError> {
    conn.execute("INSERT INTO jam_counts_out (post_id, dirty) VALUES (?1, 1) ON CONFLICT(post_id) DO UPDATE SET dirty = 1", params![post_id]).map_err(db_err)?;
    Ok(())
}

/// Posts whose tally is waiting and due (never sent, or last sent a minute ago): (post id, jam id, tier, next version).
pub(crate) fn counts_due(conn: &Connection, now: i64) -> Result<Vec<(String, String, String, i64)>, StoreError> {
    let mut statement = conn
        .prepare(
            "SELECT o.post_id, p.jam_id, p.tier, o.version + 1 FROM jam_counts_out o JOIN jam_posts p ON p.post_id = o.post_id
             WHERE o.dirty = 1 AND p.deleted_at IS NULL AND (o.sent_at = 0 OR ?1 - o.sent_at >= ?2)",
        )
        .map_err(db_err)?;
    let rows = statement.query_map(params![now, COUNTS_EVERY_MS], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?))).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(rows)
}

pub(crate) fn counts_sent(conn: &Connection, post_id: &str, version: i64, now: i64) -> Result<(), StoreError> {
    conn.execute("UPDATE jam_counts_out SET dirty = 0, version = ?2, sent_at = ?3 WHERE post_id = ?1", params![post_id, version, now]).map_err(db_err)?;
    Ok(())
}

/// The writer's own numbers for a post: likers (newest first) and published comments.
pub(crate) fn tally(conn: &Connection, post_id: &str) -> Result<(Vec<String>, i64), StoreError> {
    let mut statement = conn.prepare("SELECT user_id FROM jam_reactions WHERE post_id = ?1 ORDER BY at DESC, user_id").map_err(db_err)?;
    let likers = statement.query_map(params![post_id], |r| r.get::<_, String>(0)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    let comments: i64 = conn.query_row("SELECT COUNT(*) FROM jam_comments WHERE post_id = ?1 AND state = 'published'", params![post_id], |r| r.get(0)).map_err(db_err)?;
    Ok((likers, comments))
}

/// A subscriber keeps the newest tally the writer sent (by version).
pub(crate) fn apply_counts(conn: &Connection, post_id: &str, version: i64, likes: i64, comments: i64, remixes: i64, likers: &[String]) -> Result<bool, StoreError> {
    let n = conn
        .execute(
            "INSERT INTO jam_counts (post_id, version, likes, comments, remixes, likers) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
             ON CONFLICT(post_id) DO UPDATE SET version = ?2, likes = ?3, comments = ?4, remixes = ?5, likers = ?6 WHERE version < ?2",
            params![post_id, version, likes, comments, remixes, serde_json::to_string(likers).unwrap_or_else(|_| "[]".into())],
        )
        .map_err(db_err)?;
    Ok(n > 0)
}

pub(crate) fn comment_row(conn: &Connection, comment_id: &str) -> Result<Option<(String, String, Option<String>, String, String)>, StoreError> {
    // (post id, jam id, parent id, author, state)
    conn.query_row("SELECT post_id, jam_id, parent_id, author, state FROM jam_comments WHERE comment_id = ?1", params![comment_id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?)))
        .optional()
        .map_err(db_err)
}

/// Removes a comment and, for a top-level one, its replies.
pub(crate) fn remove_comment(conn: &Connection, comment_id: &str) -> Result<(), StoreError> {
    conn.execute("DELETE FROM jam_comments WHERE comment_id = ?1 OR parent_id = ?1", params![comment_id]).map_err(db_err)?;
    Ok(())
}

pub(crate) fn comments_by_author_since(conn: &Connection, author: &str, since: i64) -> Result<i64, StoreError> {
    conn.query_row("SELECT COUNT(*) FROM jam_comments WHERE author = ?1 AND created >= ?2", params![author, since], |r| r.get(0)).map_err(db_err)
}
