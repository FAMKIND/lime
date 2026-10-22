//! jam on the client (LIME-186, `docs/jam.md`): a teacher's one-author encrypted channel.
//!
//! - **The writer's phone** makes a jam, takes subscribers, and publishes each post once: encrypted under a Megolm session (one per tier, so a
//!   subscribers-only post is never readable with a free subscriber's key), stored here, and queued for every subscriber who may read it.
//! - **A post is a blob** (LIME-187): its content is sealed with a fresh key and uploaded once to the server as ciphertext it cannot read; the Megolm
//!   message every subscriber device receives is only a small notice (`post_id`, title, `blob_id`, key, hash, size). A subscriber downloads the blob
//!   from the server **without a session** (`jam-blob-get`), at its own pace.
//! - **A subscriber** asks to join (`jam.subscribe`), is sent a `jam.welcome` with the jam's state and the current session keys, then the **index** of
//!   the archive (`jam.index`: every post it may read, with its blob and key), and then each new post. No old ciphertext is re-sent.
//! - **Rotation:** on a removal, after 100 posts, after 7 days and when the jam ends; **never on a join** (the archive is handed over anyway).
//! - **The queue** is persistent (`jam_wire_outbox`, one row per post and subscriber), so a post to 1,000 people never blocks anything, survives a
//!   restart and resumes with a back-off; a delivery pass sends at most [`jam_store::RECIPIENTS_PER_PASS`] recipients.
//!
//! The server carries ciphertext only; the jam's public page (`jam-page`) is the one thing on it a person can read.

use vodozemac::megolm::{GroupSession, InboundGroupSession, MegolmMessage, SessionConfig as MegolmConfig, SessionKey};

use super::attachments::OutgoingAttachment;
use super::groups::GROUP_WIRE;
use super::photos::raw;
use super::*;
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
    /// `quick` (no title), `article` or `record`.
    pub kind: String,
    pub title: String,
    pub subtitle: String,
    pub markdown: String,
    pub plain: String,
    /// The post's attachment descriptors, as received (a JSON array).
    pub attachments_json: String,
    pub created: i64,
    /// Co-authors who accepted the credit (user ids): "with Jean Chung".
    pub coauthors: Vec<String>,
    /// `person` (shown as written by the writer) or `jam` (shown as the jam's, "by <writer>" under it) (LIME-188q).
    pub display_as: String,
    /// `ready` (the content is here), `fetching` (the title is known, the content is still to come from the server) or `gone` (removed from the
    /// server: the jam ended or the writer deleted it).
    pub state: String,
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

/// One file of a jam post, as the app shows it before it is downloaded.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct JamAttachmentInfo {
    pub attachment_id: String,
    pub name: String,
    pub mime: String,
    /// `image`, `video`, `audio` (a voice clip) or `file`.
    pub kind: String,
    pub size: u64,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub duration_ms: Option<u32>,
    /// A tiny preview (JPEG), or empty.
    pub thumb: Vec<u8>,
    /// A video's cover frame, or empty.
    pub poster: Vec<u8>,
    /// This phone already has the file.
    pub available: bool,
}

/// A jam's public page as the server shows it to any signed-in teacher.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct JamPageInfo {
    pub jam_id: String,
    pub writer_id: String,
    pub title: String,
    pub about: String,
    pub topics: Vec<String>,
    pub post_count: u32,
    /// How many teachers follow it (public, with the page: LIME-188b).
    pub subscriber_count: u32,
}

/// The largest file in a jam post (the server's blob cap is 25 MiB, and the sealed form is a little larger).
const MAX_ATTACHMENT_BYTES: usize = 24 * 1024 * 1024;

/// A request to be credited as a co-author of a post (LIME-188f): the writer, the post's title and kind.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct CoauthorRequest {
    pub post_id: String,
    pub jam_id: String,
    pub writer: String,
    pub title: String,
    pub kind: String,
    pub created: i64,
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

fn post_info(conn: &Connection, row: jam_store::PostRow) -> JamPostInfo {
    JamPostInfo {
        coauthors: jam_store::credits_in_state(conn, &row.post_id, "accepted").unwrap_or_default(),
        display_as: row.display_as,
        post_id: row.post_id,
        jam_id: row.jam_id,
        author: row.author,
        tier: row.tier,
        kind: row.kind,
        title: row.title,
        subtitle: row.subtitle,
        markdown: row.markdown,
        plain: row.plain,
        attachments_json: row.attachments,
        created: row.created,
        state: match row.fetched {
            1 => "ready",
            2 => "gone",
            _ => "fetching",
        }
        .to_owned(),
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

/// Queues an op for one person in the jam's own persistent queue (sent over Olm, paced, counted in the progress).
fn queue_op(conn: &Connection, jam_id: &str, recipient: &str, op: &Op) -> Result<(), StoreError> {
    jam_store::queue_op(conn, jam_id, recipient, &op.to_json().to_string())
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

/// Posts per `jam.index` op (an item may not exceed 64 KB).
const INDEX_PER_OP: usize = 100;

fn blob_json(blob: &jam_store::BlobRef) -> Value {
    json!({ "blob_id": blob.blob_id, "key": blob.key, "sha256": blob.sha256, "size": blob.size })
}

/// What a post's content is, as the bytes that are sealed into its blob.
#[allow(clippy::too_many_arguments)] // one field each
#[allow(clippy::too_many_arguments)] // one field each
fn post_plaintext(post_id: &str, jam_id: &str, tier: &str, kind: &str, title: &str, subtitle: &str, markdown: &str, attachments: &Value, created: i64, display_as: &str) -> Vec<u8> {
    json!({ "post_id": post_id, "jam_id": jam_id, "tier": tier, "kind": kind, "title": title, "subtitle": subtitle, "markdown": markdown, "attachments": attachments, "created": created, "display_as": display_as })
        .to_string()
        .into_bytes()
}

fn blob_text_to_ref(value: &Value) -> Option<jam_store::BlobRef> {
    let text = |k: &str| value.get(k).and_then(Value::as_str);
    let key = text("key").and_then(|k| vodozemac::base64_decode(k).ok()).filter(|k| k.len() == 32)?;
    let sha = text("sha256").filter(|h| h.len() == 64 && h.bytes().all(|b| b.is_ascii_hexdigit()))?;
    let id = text("blob_id").filter(|i| !i.is_empty() && i.len() <= 64 && i.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-'))?;
    let size = value.get("size").and_then(Value::as_i64).filter(|s| (1..=26 * 1024 * 1024).contains(s))?;
    Some(jam_store::BlobRef { blob_id: id.to_owned(), key: vodozemac::base64_encode(&key), sha256: sha.to_ascii_lowercase(), size })
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
                "UPDATE jams SET title = ?2, about = ?3, topics = ?4, state_hlc = ?5, page_state = 'dirty' WHERE jam_id = ?1",
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
                conn.execute("UPDATE jams SET ended = 1, state_hlc = ?2, page_state = 'end' WHERE jam_id = ?1", params![jam_id, op.hlc]).map_err(db_err)?;
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
        self.with_conn(|conn| Ok(jam_store::posts(conn, &jam_id)?.into_iter().map(|row| post_info(conn, row)).collect()))
    }

    /// One post.
    pub fn read_jam_post(&self, post_id: String) -> Result<Option<JamPostInfo>, StoreError> {
        self.with_conn(|conn| Ok(jam_store::post(conn, &post_id)?.filter(|p| !p.deleted).map(|row| post_info(conn, row))))
    }

    /// Publishes a post to my jam's subscribers: its content is sealed into a blob (uploaded by the next delivery pass), and a small notice is
    /// encrypted here once and queued for everyone who may read it. `tier` is `free` or `subscribers`; `attachments` are the files (already
    /// shrunk and stripped by the app; at most 10, each under 24 MiB): each becomes a jam-class blob of its own, uploaded before the post. Returns the post's id. Nothing is sent yet: the passes do that, in order and in chunks.
    #[allow(clippy::too_many_arguments)] // one field of a post each, for the app
    pub fn publish_jam_post(&self, jam_id: String, kind: String, title: String, subtitle: String, markdown: String, tier: String, attachments: Vec<OutgoingAttachment>, coauthors: Vec<String>) -> Result<String, StoreError> {
        self.publish_jam_post_as(jam_id, kind, title, subtitle, markdown, tier, attachments, coauthors, "person".into())
    }

    /// `publish_jam_post`, saying who the post is shown as written by: `person` (the writer) or `jam` (the jam's name, "by <writer>" under it).
    /// It travels inside the encrypted post; the server learns nothing new.
    #[allow(clippy::too_many_arguments)]
    pub fn publish_jam_post_as(&self, jam_id: String, kind: String, title: String, subtitle: String, markdown: String, tier: String, attachments: Vec<OutgoingAttachment>, coauthors: Vec<String>, display_as: String) -> Result<String, StoreError> {
        let display_as = if display_as == "jam" { "jam" } else { "person" };
        let state = self.load_or_create_account()?;
        let me = self.registered_user(&state)?;
        if !jam_store::valid_kind(&kind) {
            return Err(StoreError::Rejected);
        }
        // A quick post has no title; an article needs one (and may have a subtitle); a recording may have a title and a subtitle (LIME-188k) and needs a video or voice clip.
        let title = if kind == "quick" { String::new() } else { jam_store::clean_optional_line(&title, jam_store::MAX_POST_TITLE_CHARS).ok_or(StoreError::Rejected)? };
        let subtitle = if kind == "article" || kind == "record" { jam_store::clean_optional_line(&subtitle, jam_store::MAX_SUBTITLE_CHARS).ok_or(StoreError::Rejected)? } else { String::new() };
        if (kind == "article" && title.is_empty()) || (kind == "record" && !attachments.iter().any(|a| a.mime.starts_with("video/") || a.mime.starts_with("audio/"))) {
            return Err(StoreError::Rejected);
        }
        let markdown = crate::format::normalise_post(&markdown);
        if markdown.len() > jam_store::MAX_POST_BYTES || !jam_store::valid_tier(&tier) {
            return Err(StoreError::Rejected);
        }
        if attachments.len() > crate::store::attachments::MAX_PER_MESSAGE || attachments.iter().any(|a| a.bytes.is_empty() || a.bytes.len() > MAX_ATTACHMENT_BYTES || !a.mime.contains('/')) {
            return Err(StoreError::Rejected);
        }
        if markdown.is_empty() && attachments.is_empty() {
            return Err(StoreError::Rejected);
        }
        // An image block must name a file that is in this post.
        let file_count = attachments.len();
        if crate::format::parse_post(&markdown).iter().any(|b| matches!(b, crate::format::Block::Image { attachment, .. } if *attachment as usize >= file_count)) {
            return Err(StoreError::Rejected);
        }
        // Each file: a fresh key, sealed in chunks into one blob (named by the file's own id), its hash and size noted in the post.
        let mut files: Vec<(String, Vec<u8>, String, i64)> = Vec::new(); // (id, plain bytes, sealed hash, sealed size)
        let mut descriptors: Vec<Value> = Vec::new();
        for file in &attachments {
            let id = new_id();
            let key = crate::store::attachments::new_key();
            let sealed = crate::store::attachments::seal(&key, &id, &file.bytes).concat();
            let (hash, size) = (crate::store::attachments::digest_hex(&sealed), sealed.len() as i64);
            let descriptor = crate::store::attachments::Descriptor {
                id: id.clone(),
                key,
                digest: crate::store::attachments::digest_hex(&file.bytes),
                size: file.bytes.len() as u64,
                mime: file.mime.clone(),
                name: file.name.clone(),
                width: file.width,
                height: file.height,
                duration_ms: file.duration_ms,
                thumb: file.thumb.clone(),
                poster: file.poster.clone(),
            };
            let mut value = descriptor.to_json();
            value["blob_sha"] = json!(hash);
            value["blob_size"] = json!(size);
            // What a receiver would accept: refuse here what it would refuse there.
            crate::store::attachments::Descriptor::parse(&value).ok_or(StoreError::Rejected)?;
            descriptors.push(value);
            files.push((id, file.bytes.clone(), hash, size));
        }
        let attachments = Value::Array(descriptors);
        let plain = crate::format::plain_text_post(&markdown);
        let post_id = new_id();
        let now = now_ms();
        // The blob: a fresh key and id, the content sealed (one chunk: a post is under 1 MiB), its hash and size noted for the notice.
        let blob_id = new_id();
        let key = crate::store::attachments::new_key();
        let sealed = crate::store::attachments::seal(&key, &blob_id, &post_plaintext(&post_id, &jam_id, &tier, &kind, &title, &subtitle, &markdown, &attachments, now, &display_as));
        let [ciphertext] = <[Vec<u8>; 1]>::try_from(sealed).map_err(|_| StoreError::Rejected)?;
        let blob = jam_store::BlobRef { blob_id, key: vodozemac::base64_encode(&key), sha256: crate::store::attachments::digest_hex(&ciphertext), size: ciphertext.len() as i64 };
        self.with_conn(|conn| {
            atomically(conn, || {
                let jam = jam_store::get(conn, &jam_id)?.filter(|j| j.mine).ok_or(StoreError::NotFound)?;
                if jam.ended || !jam.tiers.contains(&tier) {
                    return Err(StoreError::Rejected);
                }
                let mut outbound = self.ensure_jam_session(conn, &state, &jam_id, &tier, now)?;
                let notice = json!({ "post_id": post_id, "tier": tier, "kind": kind, "title": title, "subtitle": subtitle, "created": now, "blob_id": blob.blob_id, "key": blob.key, "sha256": blob.sha256, "size": blob.size });
                let op = signed_op(conn, &state, "jam.post", &jam_id, Some(post_id.clone()), notice, now)?;
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
                    "INSERT INTO jam_posts (post_id, jam_id, author, session_id, idx, tier, title, markdown, plain, attachments, created, wire, blob_id, blob_key, blob_sha, blob_size, uploaded, fetched, kind, subtitle, display_as)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, 0, 1, ?17, ?18, ?19)",
                    params![post_id, jam_id, me, outbound.session.session_id(), index, tier, title, markdown, plain, attachments.to_string(), now, wire_b64, blob.blob_id, blob.key, blob.sha256, blob.size, kind, subtitle, display_as],
                )
                .map_err(db_err)?;
                for (id, plain, hash, size) in &files {
                    jam_store::insert_attachment(conn, &post_id, id, &jam_id, hash, *size, plain)?;
                }
                jam_store::queue_wire(conn, &jam_id, &post_id, &audience)?;
                // People asked to be credited (at most four, never me, once each): the request goes when the post's blob is up.
                let mut asked: Vec<&String> = Vec::new();
                for user in &coauthors {
                    if user != &me && !user.is_empty() && !asked.contains(&user) && asked.len() < 4 {
                        asked.push(user);
                        jam_store::add_credit(conn, &post_id, user)?;
                    }
                }
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
                jam_store::mark_page_dirty(conn, &jam_id)?;
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

    /// Requests to be credited that are waiting for an answer.
    pub fn list_coauthor_requests(&self) -> Result<Vec<CoauthorRequest>, StoreError> {
        self.with_conn(|conn| {
            let mut statement = conn.prepare("SELECT post_id, jam_id, writer, title, kind, created FROM jam_credit_requests WHERE state = 'pending' ORDER BY created DESC").map_err(db_err)?;
            let rows = statement
                .query_map([], |r| Ok(CoauthorRequest { post_id: r.get(0)?, jam_id: r.get(1)?, writer: r.get(2)?, title: r.get(3)?, kind: r.get(4)?, created: r.get(5)? }))
                .map_err(db_err)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(db_err)?;
            Ok(rows)
        })
    }

    /// Accepts or declines a credit. Accepting keeps the post on this phone (it is listed with the posts I am credited on); the writer is told either way.
    pub fn answer_coauthor_request(&self, post_id: String, accept: bool) -> Result<(), StoreError> {
        let state = self.load_or_create_account()?;
        self.registered_user(&state)?;
        let now = now_ms();
        self.with_conn(|conn| {
            atomically(conn, || {
                let (jam_id, writer, title, kind, created, blob): (String, String, String, String, i64, jam_store::BlobRef) = conn
                    .query_row(
                        "SELECT jam_id, writer, title, kind, created, blob_id, blob_key, blob_sha, blob_size FROM jam_credit_requests WHERE post_id = ?1 AND state = 'pending'",
                        params![post_id],
                        |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, jam_store::BlobRef { blob_id: r.get(5)?, key: r.get(6)?, sha256: r.get(7)?, size: r.get(8)? })),
                    )
                    .optional()
                    .map_err(db_err)?
                    .ok_or(StoreError::NotFound)?;
                conn.execute("UPDATE jam_credit_requests SET state = ?2 WHERE post_id = ?1", params![post_id, if accept { "accepted" } else { "declined" }]).map_err(db_err)?;
                if accept {
                    jam_store::insert_notice(conn, &post_id, &jam_id, &writer, "", 0, TIER_FREE, &title, &kind, "", created, &blob)?;
                    conn.execute("UPDATE jam_posts SET coauthored = 1 WHERE post_id = ?1", params![post_id]).map_err(db_err)?;
                }
                let reply = signed_op(conn, &state, "jam.coauthor.reply", &jam_id, None, json!({ "jam_id": jam_id, "post_id": post_id, "accept": accept }), now)?;
                queue_op(conn, &jam_id, &writer, &reply)
            })
        })
    }

    /// The posts I am credited on (accepted), newest first.
    pub fn list_coauthored_posts(&self) -> Result<Vec<JamPostInfo>, StoreError> {
        self.with_conn(|conn| {
            let mut statement = conn.prepare("SELECT post_id FROM jam_posts WHERE coauthored = 1 AND deleted_at IS NULL ORDER BY created DESC").map_err(db_err)?;
            let ids = statement.query_map([], |r| r.get::<_, String>(0)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
            let mut out = Vec::new();
            for id in ids {
                if let Some(row) = jam_store::post(conn, &id)? {
                    out.push(post_info(conn, row));
                }
            }
            Ok(out)
        })
    }

    /// The files of a post, as the app lists them before any is downloaded.
    pub fn list_jam_attachments(&self, post_id: String) -> Result<Vec<JamAttachmentInfo>, StoreError> {
        self.with_conn(|conn| {
            let Some(post) = jam_store::post(conn, &post_id)? else { return Ok(Vec::new()) };
            let list: Value = serde_json::from_str(&post.attachments).unwrap_or(Value::Array(vec![]));
            let mut out = Vec::new();
            for value in list.as_array().into_iter().flatten() {
                let Some(d) = crate::store::attachments::Descriptor::parse(value) else { continue };
                out.push(JamAttachmentInfo {
                    available: jam_store::attachment_data(conn, &post_id, &d.id)?.is_some(),
                    kind: if d.mime.starts_with("image/") { "image" } else if d.mime.starts_with("video/") { "video" } else if d.mime.starts_with("audio/") { "audio" } else { "file" }.to_owned(),
                    attachment_id: d.id,
                    name: d.name,
                    mime: d.mime,
                    size: d.size,
                    width: d.width,
                    height: d.height,
                    duration_ms: d.duration_ms,
                    thumb: d.thumb,
                    poster: d.poster,
                });
            }
            Ok(out)
        })
    }

    /// A file of a post: what this phone has, else downloaded now **with no session** (`jam-blob-get`), checked against the hash in the post, opened
    /// and kept. `Rejected` if the server no longer has it or it does not open as announced.
    pub fn jam_attachment_data(&self, transport: Arc<dyn Transport>, post_id: String, attachment_id: String) -> Result<Vec<u8>, StoreError> {
        if let Some(data) = self.with_conn(|conn| jam_store::attachment_data(conn, &post_id, &attachment_id))? {
            return Ok(data);
        }
        let (post, descriptor_json) = self.with_conn(|conn| {
            let post = jam_store::post(conn, &post_id)?.ok_or(StoreError::NotFound)?;
            let list: Value = serde_json::from_str(&post.attachments).unwrap_or(Value::Array(vec![]));
            let found = list.as_array().into_iter().flatten().find(|v| v.get("id").and_then(Value::as_str) == Some(attachment_id.as_str())).cloned();
            Ok((post, found.ok_or(StoreError::NotFound)?))
        })?;
        let descriptor = crate::store::attachments::Descriptor::parse(&descriptor_json).ok_or(StoreError::BadMessage)?;
        let blob_sha = descriptor_json.get("blob_sha").and_then(Value::as_str).unwrap_or_default().to_owned();
        let blob_size = descriptor_json.get("blob_size").and_then(Value::as_i64).unwrap_or(0);
        let (status, body) = call(&transport, None, "jam-blob-get", &json!({ "blob_id": descriptor.id }))?;
        if status == 404 {
            return Err(StoreError::Rejected);
        }
        check(status)?;
        let url = body.get("url").and_then(Value::as_str).ok_or(StoreError::BadMessage)?;
        let (status, sealed) = raw(&transport, "GET", url, None, Vec::new())?;
        check(status)?;
        if sealed.len() as i64 != blob_size || crate::store::attachments::digest_hex(&sealed) != blob_sha {
            return Err(StoreError::Rejected);
        }
        let chunk = crate::store::attachments::CHUNK + 16;
        let chunks: Vec<Vec<u8>> = sealed.chunks(chunk).map(<[u8]>::to_vec).collect();
        let plain = crate::store::attachments::open(&descriptor.key, &descriptor.id, &chunks).ok_or(StoreError::Rejected)?;
        if crate::store::attachments::digest_hex(&plain) != descriptor.digest {
            return Err(StoreError::Rejected);
        }
        self.with_conn(|conn| jam_store::cache_attachment(conn, &post_id, &descriptor.id, &post.jam_id, &blob_sha, blob_size, &plain))?;
        Ok(plain)
    }

    /// A teacher's live jam page, if they have one: any signed-in teacher can look (the same trust as reading their profile; the server learns that
    /// this account looked). `None` when they have no jam, or it ended.
    pub fn fetch_jam_page(&self, transport: Arc<dyn Transport>, auth_token: String, writer_user_id: String) -> Result<Option<JamPageInfo>, StoreError> {
        let (status, body) = call(&transport, Some(&auth_token), "jam-page", &json!({ "action": "by_writer", "writer_id": writer_user_id }))?;
        if status == 404 {
            return Ok(None);
        }
        check(status)?;
        let Some(jam) = body.get("jam").filter(|j| j.is_object()) else { return Ok(None) };
        let text = |k: &str| jam.get(k).and_then(Value::as_str).map(str::to_owned);
        let topics = jam.get("topics").and_then(Value::as_array).map(|a| a.iter().filter_map(|t| t.as_str().map(str::to_owned)).collect()).unwrap_or_default();
        Ok(Some(JamPageInfo {
            jam_id: text("jam_id").ok_or(StoreError::BadMessage)?,
            writer_id: text("writer_id").unwrap_or(writer_user_id),
            title: text("title").unwrap_or_default(),
            about: text("about").unwrap_or_default(),
            topics,
            post_count: jam.get("post_count").and_then(Value::as_u64).unwrap_or(0) as u32,
            subscriber_count: jam.get("subscriber_count").and_then(Value::as_u64).unwrap_or(0) as u32,
        }))
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
                jam_store::mark_page_dirty(conn, jam_id)?;
            }
        }
        let tier = existing.map(|(_, tier)| tier).unwrap_or_else(|| TIER_FREE.to_owned());
        // The keys for what comes next: the current session of each tier this subscriber may read. (The archive needs no old keys: each old post is
        // a blob with its own key, named in the index below.)
        let mut sessions: Vec<Value> = Vec::new();
        for readable in jam_store::tiers_for(&tier) {
            if let Some(outbound) = jam_store::load_outbound(conn, &self.pickle_key, jam_id, readable)? {
                sessions.push(json!({ "session_id": outbound.session.session_id(), "tier": readable, "key": outbound.session.session_key().to_base64() }));
            }
        }
        let welcome = json!({
            "jam_id": jam_id,
            "state": { "writer": jam.writer, "title": jam.title, "about": jam.about, "topics": jam.topics, "tiers": jam.tiers, "state_hlc": jam.state_hlc },
            "sessions": sessions,
            "post_count": jam_store::post_count(conn, jam_id)?,
        });
        queue_op(conn, jam_id, user, &signed_op(conn, state, "jam.welcome", jam_id, None, welcome, now)?)?;
        // The archive's index: every post this subscriber may read, with where its blob is and the key that opens it.
        let index = jam_store::index_for(conn, jam_id, &tier)?;
        for chunk in index.chunks(INDEX_PER_OP) {
            let posts: Vec<Value> = chunk
                .iter()
                .map(|(post_id, post_tier, title, created, blob, kind, subtitle)| {
                    let mut entry = blob_json(blob);
                    entry["post_id"] = json!(post_id);
                    entry["tier"] = json!(post_tier);
                    entry["kind"] = json!(kind);
                    entry["subtitle"] = json!(subtitle);
                    entry["title"] = json!(title);
                    entry["created"] = json!(created);
                    entry
                })
                .collect();
            queue_op(conn, jam_id, user, &signed_op(conn, state, "jam.index", jam_id, None, json!({ "jam_id": jam_id, "posts": posts }), now)?)?;
        }
        // A post still waiting for its blob to go up is not in the index: its notice will reach this subscriber instead.
        for post_id in jam_store::not_uploaded_ids(conn, jam_id, &tier)? {
            jam_store::queue_wire(conn, jam_id, &post_id, &[user.to_owned()])?;
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
                    jam_store::mark_page_dirty(conn, jam_id)?;
                }
                Ok(())
            }
            // Someone asks me to be credited on their post: kept to answer (anyone may ask; nothing is shown until I accept).
            "jam.coauthor" => {
                if sender == me {
                    return Ok(());
                }
                let text = |k: &str| op.payload.get(k).and_then(Value::as_str);
                let (Some(post_id), Some(title), Some(kind), Some(blob)) = (
                    text("post_id").filter(|p| !p.is_empty() && p.len() <= 64),
                    jam_store::clean_optional_line(text("title").unwrap_or_default(), jam_store::MAX_POST_TITLE_CHARS),
                    text("kind").filter(|k| jam_store::valid_kind(k)),
                    blob_text_to_ref(&op.payload),
                ) else {
                    return Ok(());
                };
                let created = op.payload.get("created").and_then(Value::as_i64).unwrap_or(now).min(now);
                conn.execute(
                    "INSERT OR IGNORE INTO jam_credit_requests (post_id, jam_id, writer, title, kind, created, blob_id, blob_key, blob_sha, blob_size) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
                    params![post_id, jam_id, sender, title, kind, created, blob.blob_id, blob.key, blob.sha256, blob.size],
                )
                .map_err(db_err)?;
                Ok(())
            }
            // The person I asked answers: an accepted credit is announced to my subscribers.
            "jam.coauthor.reply" => {
                let Some(_jam) = jam.filter(|j| j.mine) else { return Ok(()) };
                let Some(post_id) = op.payload.get("post_id").and_then(Value::as_str) else { return Ok(()) };
                if jam_store::credit_state(conn, post_id, sender)?.as_deref() != Some("requested") {
                    return Ok(());
                }
                if op.payload.get("accept").and_then(Value::as_bool) == Some(true) {
                    jam_store::set_credit(conn, post_id, sender, "accepted")?;
                    self.announce_credit(conn, state, me, jam_id, post_id, sender, now)?;
                } else {
                    jam_store::set_credit(conn, post_id, sender, "declined")?;
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
                    "jam.index" => self.store_jam_index(conn, jam_id, sender, &op.payload),
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
            let Ok(key) = SessionKey::from_base64(key) else { continue };
            let session = InboundGroupSession::new(&key, MegolmConfig::version_1());
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

    /// Tells my subscribers, in the post's own session, that `user` is credited on it (a small signed message through the same queue as the posts).
    #[allow(clippy::too_many_arguments)] // the context of one announcement
    fn announce_credit(&self, conn: &Connection, state: &AccountState, me: &str, jam_id: &str, post_id: &str, user: &str, now: i64) -> Result<(), StoreError> {
        let Some(post) = jam_store::post(conn, post_id)? else { return Ok(()) };
        let mut outbound = self.ensure_jam_session(conn, state, jam_id, &post.tier, now)?;
        let op = signed_op(conn, state, "jam.credit", jam_id, None, json!({ "post_id": post_id, "user": user }), now)?;
        let inner = SealedInner { sender_user: me.to_owned(), sender_device: state.device_id.clone(), sender_cert: state.cert(), op }.to_bytes();
        let encrypted = outbound.session.encrypt(&inner);
        outbound.posts += 1;
        jam_store::save_outbound(conn, &self.pickle_key, jam_id, &post.tier, &outbound)?;
        let mut wire = vec![GROUP_WIRE];
        wire.extend_from_slice(json!({ "s": outbound.session.session_id(), "c": encrypted.to_base64() }).to_string().as_bytes());
        let wire_id = new_id();
        conn.execute("INSERT INTO jam_credit_wires (wire_id, jam_id, wire) VALUES (?1, ?2, ?3)", params![wire_id, jam_id, vodozemac::base64_encode(&wire)]).map_err(db_err)?;
        jam_store::queue_wire(conn, jam_id, &wire_id, &jam_store::audience(conn, jam_id, &post.tier)?)
    }

    /// Sends the credit requests of posts whose blob is now up (the co-author must be able to download the post if she accepts).
    fn queue_credit_requests(&self, state: &AccountState) {
        let now = now_ms();
        let Ok(pending) = self.with_conn(jam_store::credits_to_send) else { return };
        for (post_id, user) in pending {
            let _ = self.with_conn(|conn| {
                let Some(post) = jam_store::post(conn, &post_id)? else { return Ok(()) };
                let blob: (Option<String>, Option<String>, Option<String>, i64) = conn
                    .query_row("SELECT blob_id, blob_key, blob_sha, blob_size FROM jam_posts WHERE post_id = ?1", params![post_id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))
                    .map_err(db_err)?;
                let (Some(blob_id), Some(key), Some(sha256)) = (blob.0, blob.1, blob.2) else { return Ok(()) };
                let payload = json!({ "jam_id": post.jam_id, "post_id": post_id, "title": post.title, "kind": post.kind, "created": post.created,
                                      "blob_id": blob_id, "key": key, "sha256": sha256, "size": blob.3 });
                let op = signed_op(conn, state, "jam.coauthor", &post.jam_id, None, payload, now)?;
                queue_op(conn, &post.jam_id, &user, &op)?;
                jam_store::set_credit(conn, &post_id, &user, "requested")
            });
        }
    }

    /// The archive's index from the writer: each post's title and where its content is. Entries are checked for shape; the content is fetched later.
    fn store_jam_index(&self, conn: &Connection, jam_id: &str, writer: &str, payload: &Value) -> Result<(), StoreError> {
        let Some(posts) = payload.get("posts").and_then(Value::as_array) else { return Ok(()) };
        for entry in posts.iter().take(INDEX_PER_OP) {
            let text = |k: &str| entry.get(k).and_then(Value::as_str);
            let kind = text("kind").filter(|k| jam_store::valid_kind(k)).unwrap_or("article");
            let (Some(post_id), Some(tier), Some(title), Some(subtitle), Some(created), Some(blob)) = (
                text("post_id").filter(|p| !p.is_empty() && p.len() <= 64),
                text("tier").filter(|t| jam_store::valid_tier(t)),
                jam_store::clean_optional_line(text("title").unwrap_or_default(), jam_store::MAX_POST_TITLE_CHARS),
                jam_store::clean_optional_line(text("subtitle").unwrap_or_default(), jam_store::MAX_SUBTITLE_CHARS),
                entry.get("created").and_then(Value::as_i64),
                blob_text_to_ref(entry),
            ) else {
                continue;
            };
            jam_store::insert_notice(conn, post_id, jam_id, writer, "", 0, tier, &title, kind, &subtitle, created, &blob)?;
        }
        Ok(())
    }

    /// Decrypts and keeps one post's notice. `message` is the Megolm ciphertext of a session this phone holds (`inbound`). Whose post it is comes from the
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
            && (op.op_type == "jam.post" || op.op_type == "jam.credit")
            && op.conversation_id == conversation;
        let payload = &op.payload;
        let text = |k: &str| payload.get(k).and_then(Value::as_str);
        // The writer says someone accepted a credit on a post (LIME-188f): kept for the byline.
        if valid && op.op_type == "jam.credit" {
            let (Some(post_id), Some(user), Some(remote_hlc)) = (text("post_id").filter(|p| !p.is_empty() && p.len() <= 64), text("user").filter(|u| !u.is_empty() && u.len() <= 64), Hlc::parse(&op.hlc)) else {
                return Ok(Outcome::Keep(pending::INVALID));
            };
            let author = inner.sender_user.clone();
            let outcome = self.with_conn(|conn| {
                let pinned: Option<String> = conn.query_row("SELECT master_key FROM peers WHERE user_id = ?1", params![author], |r| r.get(0)).optional().map_err(db_err)?;
                let jam = jam_store::get(conn, &inbound.jam_id)?;
                if pinned.as_deref() != Some(cert.master_key.as_str()) || jam.is_none_or(|j| j.mine || j.writer != author || matches!(j.status.as_str(), "removed" | "left")) {
                    return Ok(Outcome::Keep(pending::INVALID));
                }
                jam_store::save_inbound(conn, &self.pickle_key, session_id, &inbound)?;
                jam_store::set_credit(conn, post_id, user, "accepted")?;
                Ok(Outcome::Duplicate)
            })?;
            if matches!(outcome, Outcome::Duplicate) {
                self.with_conn(|conn| observe_hlc(conn, remote_hlc, now).map(|_| ()))?;
            }
            return Ok(outcome);
        }
        let kind = text("kind").filter(|k| jam_store::valid_kind(k)).unwrap_or("article");
        let (true, Some(title), Some(subtitle), Some(blob), Some(remote_hlc)) = (
            valid && op.op_type == "jam.post" && text("post_id") == Some(op.op_id.as_str()) && text("tier") == Some(inbound.tier.as_str()),
            jam_store::clean_optional_line(text("title").unwrap_or_default(), jam_store::MAX_POST_TITLE_CHARS),
            jam_store::clean_optional_line(text("subtitle").unwrap_or_default(), jam_store::MAX_SUBTITLE_CHARS),
            blob_text_to_ref(payload),
            Hlc::parse(&op.hlc),
        ) else {
            return Ok(Outcome::Keep(pending::INVALID));
        };
        if kind == "article" && title.is_empty() {
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
            let created = payload.get("created").and_then(Value::as_i64).unwrap_or(remote_hlc.wall).min(now);
            jam_store::insert_notice(conn, &op.op_id, &inbound.jam_id, &author, session_id, decrypted.message_index, &inbound.tier, &title, kind, &subtitle, created, &blob)?;
            Ok(Outcome::Duplicate)
        })?;
        if matches!(outcome, Outcome::Duplicate) {
            self.with_conn(|conn| observe_hlc(conn, remote_hlc, now).map(|_| ()))?;
        }
        Ok(outcome)
    }
}

// ---------------------------------------------------------------- the passes

impl LimeStore {
    /// Everything jam does in a delivery pass, in the order that keeps it sound: the Olm ops (keys, welcomes, the jam's news), then the posts'
    /// blobs up, then the public pages, then the notices, then the subscriber's own downloads. Each is paced, resumes by itself and stops quietly
    /// without internet. Never holds up the messages.
    pub(super) fn deliver_jam(&self, transport: &Arc<dyn Transport>, token: &str, state: &mut AccountState, me: &str) {
        self.queue_credit_requests(state);
        self.deliver_jam_ops(transport, token, state, me);
        self.upload_jam_posts(transport, token);
        self.publish_jam_pages(transport, token);
        self.deliver_jam_wires(transport, token);
        self.fetch_jam_posts(transport);
    }

    /// Sends the Olm ops waiting in the jam queue, at most [`jam_store::OPS_PER_PASS`] people a pass (the server limits claims and items a minute).
    /// A person whose key changed waits; one with no devices is dropped; a rate limit or no internet ends the pass with the rest kept.
    fn deliver_jam_ops(&self, transport: &Arc<dyn Transport>, token: &str, state: &mut AccountState, me: &str) {
        let now = now_ms();
        let Ok(rows) = self.with_conn(|conn| jam_store::next_ops(conn, now, jam_store::OPS_PER_PASS)) else { return };
        for (id, _jam, recipient, op_json, attempts) in rows {
            let Some(op) = serde_json::from_str::<Value>(&op_json).ok().and_then(|v| Op::from_json(&v)) else {
                let _ = self.with_conn(|conn| jam_store::done_op(conn, id));
                continue;
            };
            match self.send_to_user(transport, token, state, me, &recipient, op) {
                Ok(()) | Err(StoreError::NoRecipientKeys) => {
                    let _ = self.with_conn(|conn| jam_store::done_op(conn, id));
                }
                Err(StoreError::KeyMismatch) => {
                    let _ = self.with_conn(|conn| jam_store::back_off_op(conn, id, attempts, now));
                }
                Err(StoreError::RateLimited) => {
                    let _ = self.with_conn(|conn| jam_store::back_off_op(conn, id, attempts, now));
                    return;
                }
                Err(StoreError::Network) => return,
                Err(_) => {
                    let _ = self.with_conn(|conn| jam_store::back_off_op(conn, id, attempts, now));
                }
            }
        }
    }

    /// Uploads the writer's posts that are not on the server yet: each as one blob of ciphertext (the class `jam`: no expiry, fetched without a
    /// session). A post's notice is held back until its blob is up.
    fn upload_jam_posts(&self, transport: &Arc<dyn Transport>, token: &str) {
        self.upload_jam_attachments(transport, token);
        let Ok(posts) = self.with_conn(|conn| jam_store::to_upload(conn, jam_store::BLOBS_PER_PASS)) else { return };
        for post in posts {
            let Some(key) = vodozemac::base64_decode(&post.blob.key).ok().filter(|k| k.len() == 32) else { continue };
            let attachments: Value = serde_json::from_str(&post.attachments).unwrap_or(Value::Array(vec![]));
            let plaintext = post_plaintext(&post.post_id, &post.jam_id, &post.tier, &post.kind, &post.title, &post.subtitle, &post.markdown, &attachments, post.created, &post.display_as);
            let sealed = crate::store::attachments::seal(&key, &post.blob.blob_id, &plaintext);
            let [ciphertext] = <[Vec<u8>; 1]>::try_from(sealed).unwrap_or_default();
            if crate::store::attachments::digest_hex(&ciphertext) != post.blob.sha256 {
                continue; // cannot be made again as it was announced: leave it (never happens unless the row was changed)
            }
            let uploaded = (|| -> Result<(), StoreError> {
                let (status, body) = call(transport, Some(token), "blob", &json!({ "action": "put", "blob_id": post.blob.blob_id, "size": ciphertext.len(), "class": "jam", "jam_id": post.jam_id }))?;
                check(status)?;
                let url = body.get("url").and_then(Value::as_str).ok_or(StoreError::BadMessage)?;
                let (put, _) = raw(transport, "PUT", url, Some("application/octet-stream"), ciphertext)?;
                check(put)?;
                let (status, _) = call(transport, Some(token), "blob", &json!({ "action": "commit", "blob_id": post.blob.blob_id }))?;
                check(status)
            })();
            match uploaded {
                Ok(()) => {
                    let _ = self.with_conn(|conn| jam_store::set_uploaded(conn, &post.post_id, &post.jam_id));
                }
                Err(StoreError::Network) => return,
                Err(_) => continue,
            }
        }
    }

    /// Uploads the files of the writer's posts, each as a jam-class blob of its sealed chunks (before the post that names them goes up).
    fn upload_jam_attachments(&self, transport: &Arc<dyn Transport>, token: &str) {
        let Ok(rows) = self.with_conn(|conn| jam_store::attachments_to_upload(conn, jam_store::BLOBS_PER_PASS)) else { return };
        for row in rows {
            let key = self.with_conn(|conn| {
                let post = jam_store::post(conn, &row.post_id)?;
                let list: Value = post.and_then(|p| serde_json::from_str(&p.attachments).ok()).unwrap_or(Value::Array(vec![]));
                Ok(list.as_array().into_iter().flatten().filter(|v| v.get("id").and_then(Value::as_str) == Some(row.att_id.as_str())).find_map(crate::store::attachments::Descriptor::parse).map(|d| d.key))
            });
            let Ok(Some(key)) = key else { continue };
            let sealed = crate::store::attachments::seal(&key, &row.att_id, &row.data).concat();
            if sealed.len() as i64 != row.blob_size || crate::store::attachments::digest_hex(&sealed) != row.blob_sha {
                continue;
            }
            let uploaded = (|| -> Result<(), StoreError> {
                let (status, body) = call(transport, Some(token), "blob", &json!({ "action": "put", "blob_id": row.att_id, "size": sealed.len(), "class": "jam", "jam_id": row.jam_id }))?;
                check(status)?;
                let url = body.get("url").and_then(Value::as_str).ok_or(StoreError::BadMessage)?;
                let (put, _) = raw(transport, "PUT", url, Some("application/octet-stream"), sealed)?;
                check(put)?;
                let (status, _) = call(transport, Some(token), "blob", &json!({ "action": "commit", "blob_id": row.att_id }))?;
                check(status)
            })();
            match uploaded {
                Ok(()) => {
                    let _ = self.with_conn(|conn| jam_store::set_attachment_uploaded(conn, &row.post_id, &row.att_id));
                }
                Err(StoreError::Network) => return,
                Err(_) => continue,
            }
        }
    }

    /// Keeps the server's copy of each jam's public page (title, about, topics, how many posts) up to date, and tells it when a jam has ended so it
    /// removes the posts. The page is the only part of a jam the server can read.
    fn publish_jam_pages(&self, transport: &Arc<dyn Transport>, token: &str) {
        let Ok(dirty) = self.with_conn(jam_store::pages_to_publish) else { return };
        for jam in dirty {
            let count = self.with_conn(|conn| jam_store::uploaded_count(conn, &jam.jam_id)).unwrap_or(0);
            let subscribers = self.with_conn(|conn| jam_store::subscriber_count(conn, &jam.jam_id)).unwrap_or(0);
            let body = json!({ "action": "set", "jam_id": jam.jam_id, "title": jam.title, "about": jam.about, "topics": jam.topics, "post_count": count, "subscriber_count": subscribers });
            match call(transport, Some(token), "jam-page", &body) {
                Ok((status, _)) if (200..300).contains(&status) => {
                    let _ = self.with_conn(|conn| jam_store::set_page_state(conn, &jam.jam_id, "ok"));
                }
                Err(StoreError::Network) => return,
                _ => {}
            }
        }
        let Ok(ended) = self.with_conn(jam_store::pages_to_end) else { return };
        for jam in ended {
            match call(transport, Some(token), "jam-page", &json!({ "action": "end", "jam_id": jam.jam_id })) {
                // Done, or the server never had the page: either way there is nothing left to remove.
                Ok((status, _)) if (200..300).contains(&status) || status == 404 => {
                    let _ = self.with_conn(|conn| jam_store::set_page_state(conn, &jam.jam_id, "done"));
                }
                Err(StoreError::Network) => return,
                _ => {}
            }
        }
    }

    /// A subscriber's own downloads: the content of the posts it knows only by title. **No session and no token**: the request carries no account,
    /// only the post's unguessable id. A post the server no longer has is marked gone.
    fn fetch_jam_posts(&self, transport: &Arc<dyn Transport>) {
        let Ok(wanted) = self.with_conn(|conn| jam_store::to_fetch(conn, jam_store::BLOBS_PER_PASS)) else { return };
        for (post_id, blob) in wanted {
            let got = (|| -> Result<Option<Vec<u8>>, StoreError> {
                let (status, body) = call(transport, None, "jam-blob-get", &json!({ "blob_id": blob.blob_id }))?;
                if status == 404 {
                    return Ok(None);
                }
                check(status)?;
                let url = body.get("url").and_then(Value::as_str).ok_or(StoreError::BadMessage)?;
                let (status, bytes) = raw(transport, "GET", url, None, Vec::new())?;
                check(status)?;
                Ok(Some(bytes))
            })();
            let bytes = match got {
                Ok(Some(bytes)) => bytes,
                Ok(None) => {
                    let _ = self.with_conn(|conn| jam_store::set_fetched(conn, &post_id, None));
                    continue;
                }
                Err(StoreError::Network) => return,
                Err(_) => continue,
            };
            // What was announced, and nothing else: the size and hash from the notice, then the seal itself (which also binds the blob's id).
            let opened = (bytes.len() as i64 == blob.size && crate::store::attachments::digest_hex(&bytes) == blob.sha256)
                .then(|| vodozemac::base64_decode(&blob.key).ok())
                .flatten()
                .and_then(|key| crate::store::attachments::open(&key, &blob.blob_id, &[bytes]))
                .and_then(|plain| serde_json::from_slice::<Value>(&plain).ok());
            let kept = self.with_conn(|conn| {
                let Some(row) = jam_store::post(conn, &post_id)? else { return Ok(()) };
                let content = opened.as_ref().and_then(|value| {
                    let text = |k: &str| value.get(k).and_then(Value::as_str);
                    // The content must be this very post of this jam, in the tier it was announced in.
                    if text("post_id") != Some(post_id.as_str()) || text("jam_id") != Some(row.jam_id.as_str()) || text("tier") != Some(row.tier.as_str()) {
                        return None;
                    }
                    let attachments = value.get("attachments").cloned().unwrap_or(Value::Array(vec![]));
                    crate::store::attachments::parse_payload(&json!({ "attachments": attachments }))?;
                    let markdown = crate::format::normalise_post(text("markdown")?);
                    let display_as = if text("display_as") == Some("jam") { "jam" } else { "person" };
                    (markdown.len() <= jam_store::MAX_POST_BYTES).then_some((markdown, attachments, display_as))
                });
                match content {
                    Some((markdown, attachments, display_as)) => jam_store::set_fetched(conn, &post_id, Some((&markdown, &crate::format::plain_text_post(&markdown), &attachments, display_as))),
                    // Bytes that do not open as announced: gone for good (a retry would fetch the same).
                    None => jam_store::set_fetched(conn, &post_id, None),
                }
            });
            let _ = kept;
        }
    }

    /// A subscriber's device ids for a notice: from the cache when it is under a day old (so a post to a thousand people does not read a thousand
    /// device lists, which the server limits to 120 a minute), else live. A stale cache that names a gone device is caught by the send itself.
    fn jam_devices(&self, transport: &Arc<dyn Transport>, token: &str, user: &str, live: bool) -> Result<Vec<String>, StoreError> {
        if !live {
            let updated: Option<i64> = self.with_conn(|conn| {
                conn.query_row("SELECT MAX(updated_at) FROM peer_devices WHERE user_id = ?1", params![user], |r| r.get(0)).optional().map(Option::flatten).map_err(db_err)
            })?;
            if updated.is_some_and(|at| now_ms() - at < 24 * 3_600_000) {
                if let Some((_, devices)) = self.cached_devices(user)? {
                    return Ok(devices.into_iter().map(|d| d.device_id).collect());
                }
            }
        }
        Ok(self.recipient_devices(transport, token, user)?.into_iter().map(|d| d.device_id).collect())
    }

    /// Sends what is due in the jam queue: each post's notice to its waiting subscribers, a chunk at a time. A person whose key changed, or who has
    /// no devices, is dropped (nobody to give it to); a failed try waits longer each time; no internet stops the pass and keeps everything.
    fn deliver_jam_wires(&self, transport: &Arc<dyn Transport>, token: &str) {
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
                match self.jam_devices(transport, token, user, false) {
                    Ok(devices) => audience.push((user.clone(), devices)),
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
            let mut result = self.send_group_wire(transport, token, &due.wire, audience.clone(), None);
            // The server refused the whole chunk (a cached device list named a device that is gone): ask for these people's lists live, once.
            if matches!(result, Err(StoreError::Rejected | StoreError::NotFound | StoreError::KeyMismatch)) {
                let mut fresh: Vec<(String, Vec<String>)> = Vec::new();
                for (user, _) in &audience {
                    match self.jam_devices(transport, token, user, true) {
                        Ok(devices) => fresh.push((user.clone(), devices)),
                        Err(StoreError::Network) => return,
                        Err(_) => {}
                    }
                }
                if !fresh.is_empty() {
                    result = self.send_group_wire(transport, token, &due.wire, fresh, None);
                }
            }
            match result {
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
