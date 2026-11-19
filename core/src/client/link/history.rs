//! The last 45 days of history to a new device (LIME-341c, DESIGN-M1 D3 and D4). Part of linking (`link.rs`); core only.
//!
//! After the package (`link.rs`) the phone builds a **filtered copy** of what its chats held in the last 45 days: the messages (decrypted bodies, edits,
//! deletions as tombstones), their attachments' descriptors (the **keys and metadata, never the files**: the new device downloads them like any message, while
//! they are still on the server), the reactions and the unread counts. It never holds a session of any kind (Olm or Megolm), the pickled account, drafts,
//! private labels or anything local to this phone. The copy is compressed, sealed in 256 KiB chunks with a fresh key (AES-256-GCM, counter nonces, like Move),
//! and uploaded as **one blob** through the server's `blob` function **with a 24-hour expiry**. The blob's id and key travel only **inside the link session**
//! (a `KIND_HISTORY` chunk after the package: never in the clear, never to the server). The new device downloads it, checks it, imports it in one transaction
//! and then deletes the blob (the same account may delete its own blob); if that never happens the server drops it after 24 hours.
//!
//! **Nothing older than 45 days, ever:** the cut-off is by message time on the phone, and the new device refuses a message older than that again.
//! **All or nothing:** a bad or tampered file imports nothing (the package already landed, so the device works, just without the history). Imported messages
//! appear as already received (mine as mine), fire no notification (nothing here is an arrival) and the unread counts are the phone's.
//!
//! What each party learns: the server sees the size of one ciphertext, its uploader (the account) and that it was fetched and deleted; nothing of its content.
//! It already knew how many devices the account has. The blob has no connection to any message.

use std::collections::HashSet;
use std::io::{Read, Write};

use flate2::read::DeflateDecoder;
use flate2::write::DeflateEncoder;
use flate2::Compression;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use super::super::transfer::{open_chunk, random, seal_chunk, CHUNK, KIND_DATA};
use super::super::*;
use super::{LinkNew, LinkOld, Stage, KIND_HISTORY, LABEL as LINK_LABEL};

const HLABEL: &[u8] = b"lime-link-history-v1";
const VERSION: u8 = 1;
/// How far back (D3): 45 days.
pub(crate) const DAYS: i64 = 45;
const DAY_MS: i64 = 86_400_000;
/// The server's blob limit is 25 MiB; stay under it (the sealed size is a little more than the compressed).
const MAX_SEALED: usize = 24 * 1024 * 1024;
/// The most a history may inflate to (a guard against a hostile file).
const MAX_PLAIN: u64 = 256 * 1024 * 1024;
/// What an imported message may be (the phone's unsent ones stay on the phone).
const STATES: [&str; 3] = ["received", "sent", "system"];

/// How far a history step has got (the app shows it, LIME-343): `step` is `idle`, `building`, `uploading`, `downloading`, `importing` or `done`; the
/// bytes are of the sealed file (a download or upload is one request, so `done` moves from 0 to the size when it finishes).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct HistoryProgress {
    pub step: String,
    pub done: u64,
    pub total: u64,
}

impl HistoryProgress {
    pub(super) fn idle() -> Self {
        Self { step: "idle".into(), done: 0, total: 0 }
    }
    fn at(step: &str, done: u64, total: u64) -> Self {
        Self { step: step.into(), done, total }
    }
}

/// What the new device reports after importing.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct HistoryImported {
    pub messages: u64,
    /// Messages in the file that were not imported (a chat or a sender this device does not have, too old, or already here).
    pub skipped: u64,
    pub conversations: u64,
    /// The oldest time the file reaches back to (milliseconds).
    pub cutoff_ms: i64,
    /// The phone had more than fits in one file and kept the newest days only.
    pub truncated: bool,
}

/// Where the history is and how to open it: sealed inside the link session.
#[derive(Serialize, Deserialize, Clone)]
pub(super) struct Pointer {
    v: u8,
    blob_id: String,
    /// The file's key (base64).
    key: String,
    chunks: u32,
    sealed_size: u64,
    /// SHA-256 (hex) of the compressed history, before it was sealed.
    digest: String,
    messages: u64,
    cutoff_ms: i64,
    truncated: bool,
}

impl Pointer {
    pub(super) fn from_bytes(bytes: &[u8]) -> Result<Self, StoreError> {
        let p: Pointer = serde_json::from_slice(bytes).map_err(|_| StoreError::BadMessage)?;
        let uuid_ok = uuid::Uuid::parse_str(&p.blob_id).is_ok();
        if p.v != VERSION || !uuid_ok || p.chunks == 0 || p.chunks > 200 || p.sealed_size as usize > MAX_SEALED + 64 * 1024 || vodozemac::base64_decode(&p.key).map(|k| k.len()) != Ok(32) {
            return Err(StoreError::BadMessage);
        }
        Ok(p)
    }
}

#[derive(Serialize, Deserialize, Default)]
struct History {
    v: u8,
    cutoff_ms: i64,
    truncated: bool,
    /// `[conversation id, unread, marked unread]`
    conversations: Vec<(String, i64, i64)>,
    messages: Vec<serde_json::Map<String, Value>>,
    attachments: Vec<serde_json::Map<String, Value>>,
    reactions: Vec<serde_json::Map<String, Value>>,
    threads: Vec<serde_json::Map<String, Value>>,
}

fn json_of(value: rusqlite::types::ValueRef<'_>) -> Value {
    use rusqlite::types::ValueRef;
    match value {
        ValueRef::Null => Value::Null,
        ValueRef::Integer(i) => json!(i),
        ValueRef::Real(f) => json!(f),
        ValueRef::Text(t) => Value::String(String::from_utf8_lossy(t).into_owned()),
        ValueRef::Blob(b) => json!({ "$b": vodozemac::base64_encode(b) }),
    }
}

fn sql_of(value: &Value) -> rusqlite::types::Value {
    use rusqlite::types::Value as V;
    match value {
        Value::Null => V::Null,
        Value::Bool(b) => V::Integer(i64::from(*b)),
        Value::Number(n) => n.as_i64().map(V::Integer).unwrap_or_else(|| V::Real(n.as_f64().unwrap_or(0.0))),
        Value::String(s) => V::Text(s.clone()),
        Value::Object(o) => o.get("$b").and_then(Value::as_str).and_then(|b| vodozemac::base64_decode(b).ok()).map(V::Blob).unwrap_or(V::Null),
        Value::Array(_) => V::Null,
    }
}

fn columns(conn: &Connection, table: &str) -> Result<Vec<String>, StoreError> {
    let mut stmt = conn.prepare(&format!("PRAGMA table_info({table})")).map_err(db_err)?;
    let names = stmt.query_map([], |r| r.get::<_, String>(1)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(names)
}

/// Rows of `table` as maps, for the columns in `take`, with the given `WHERE` (and its one text-list parameter handled by the caller).
fn dump(conn: &Connection, table: &str, take: &[&str], filter: &str, params: &[rusqlite::types::Value]) -> Result<Vec<serde_json::Map<String, Value>>, StoreError> {
    let known = columns(conn, table)?;
    let cols: Vec<&str> = take.iter().copied().filter(|c| known.iter().any(|k| k == c)).collect();
    let mut stmt = conn.prepare(&format!("SELECT {} FROM {table} {filter}", cols.join(", "))).map_err(db_err)?;
    let mut rows = stmt.query(rusqlite::params_from_iter(params.iter())).map_err(db_err)?;
    let mut out = Vec::new();
    while let Some(row) = rows.next().map_err(db_err)? {
        let mut map = serde_json::Map::new();
        for (i, name) in cols.iter().enumerate() {
            map.insert((*name).to_owned(), json_of(row.get_ref(i).map_err(db_err)?));
        }
        out.push(map);
    }
    Ok(out)
}

fn text<'a>(row: &'a serde_json::Map<String, Value>, key: &str) -> &'a str {
    row.get(key).and_then(Value::as_str).unwrap_or("")
}

/// The filtered copy of the last 45 days (the history as JSON), and how many messages it holds. `cutoff` is the oldest time it reaches back to.
pub(crate) fn build(conn: &Connection, cutoff: i64, truncated: bool) -> Result<(Vec<u8>, u64), StoreError> {
    // The chats that went with the package: one-to-one and group chats, never a jam's.
    let messages = dump(
        conn,
        "messages",
        &["id", "conversation_id", "sender_id", "body", "sent_at", "local_state", "op_id", "hlc", "parents", "plain", "thread_root", "edited", "edit_hlc", "deleted", "forwarded", "link_preview"],
        "WHERE sent_at >= ?1 AND hidden = 0 AND local_state IN ('received', 'sent', 'system') AND (conversation_id LIKE 'dm:%' OR conversation_id LIKE 'grp:%') ORDER BY sent_at, id",
        &[rusqlite::types::Value::Integer(cutoff)],
    )?;
    let ids: HashSet<&str> = messages.iter().map(|m| text(m, "id")).collect();
    // Attachments: everything about the file except the file itself.
    let attachments: Vec<_> = dump(
        conn,
        "message_attachments",
        &["attachment_id", "message_id", "position", "key", "digest", "size", "mime", "name", "width", "height", "duration_ms", "thumb", "poster", "role", "alt", "removed"],
        "",
        &[],
    )?
    .into_iter()
    .filter(|a| ids.contains(text(a, "message_id")))
    .collect();
    let reactions: Vec<_> = dump(conn, "reactions", &["message_id", "user_id", "emoji", "hlc", "active"], "", &[])?.into_iter().filter(|r| ids.contains(text(r, "message_id"))).collect();
    let threads: Vec<_> = dump(conn, "thread_state", &["root_id", "unread"], "", &[])?.into_iter().filter(|t| ids.contains(text(t, "root_id"))).collect();
    let chats: HashSet<&str> = messages.iter().map(|m| text(m, "conversation_id")).collect();
    let mut conversations = Vec::new();
    let mut stmt = conn.prepare("SELECT id, unread, marked_unread FROM conversations").map_err(db_err)?;
    let rows = stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?, r.get::<_, i64>(2)?))).map_err(db_err)?;
    for row in rows {
        let row = row.map_err(db_err)?;
        if row.0.starts_with("dm:") || crate::store::groups::group_id_of(&row.0).is_some() || chats.contains(row.0.as_str()) {
            conversations.push(row);
        }
    }
    let count = messages.len() as u64;
    let history = History { v: VERSION, cutoff_ms: cutoff, truncated, conversations, messages, attachments, reactions, threads };
    Ok((serde_json::to_vec(&history).map_err(|_| StoreError::BadMessage)?, count))
}

fn deflate(bytes: &[u8]) -> Result<Vec<u8>, StoreError> {
    let mut encoder = DeflateEncoder::new(Vec::new(), Compression::new(6));
    encoder.write_all(bytes).map_err(|_| StoreError::BadMessage)?;
    encoder.finish().map_err(|_| StoreError::BadMessage)
}

fn inflate(bytes: &[u8]) -> Result<Vec<u8>, StoreError> {
    let mut out = Vec::new();
    DeflateDecoder::new(bytes).take(MAX_PLAIN + 1).read_to_end(&mut out).map_err(|_| StoreError::BadMessage)?;
    if out.len() as u64 > MAX_PLAIN {
        return Err(StoreError::BadMessage);
    }
    Ok(out)
}

/// The compressed history sealed in 256 KiB chunks, each `u32 length | sealed chunk`.
fn seal_all(key: &[u8; 32], compressed: &[u8]) -> Result<(Vec<u8>, u32), StoreError> {
    let mut out = Vec::with_capacity(compressed.len() + 64);
    let mut n = 0u32;
    for (i, piece) in compressed.chunks(CHUNK).enumerate() {
        let sealed = seal_chunk(HLABEL, key, i as u64, KIND_DATA, piece)?;
        out.extend_from_slice(&(sealed.len() as u32).to_be_bytes());
        out.extend_from_slice(&sealed);
        n += 1;
    }
    if n == 0 {
        let sealed = seal_chunk(HLABEL, key, 0, KIND_DATA, &[])?;
        out.extend_from_slice(&(sealed.len() as u32).to_be_bytes());
        out.extend_from_slice(&sealed);
        n = 1;
    }
    Ok((out, n))
}

fn open_all(key: &[u8; 32], sealed: &[u8], chunks: u32) -> Result<Vec<u8>, StoreError> {
    let mut out = Vec::new();
    let mut at = 0usize;
    for i in 0..chunks {
        let len_bytes: [u8; 4] = sealed.get(at..at + 4).ok_or(StoreError::BadMessage)?.try_into().map_err(|_| StoreError::BadMessage)?;
        let len = u32::from_be_bytes(len_bytes) as usize;
        at += 4;
        let piece = sealed.get(at..at.checked_add(len).ok_or(StoreError::BadMessage)?).ok_or(StoreError::BadMessage)?;
        at += len;
        let (kind, payload) = open_chunk(HLABEL, key, u64::from(i), piece)?;
        if kind != KIND_DATA {
            return Err(StoreError::BadMessage);
        }
        out.extend_from_slice(&payload);
    }
    if at != sealed.len() {
        return Err(StoreError::BadMessage);
    }
    Ok(out)
}

#[uniffi::export]
impl LinkOld {
    /// **The phone's history step**, after the package has all gone (`export_next_chunk` returned `None`): builds the last 45 days, seals and uploads them
    /// (24-hour expiry) and returns **one more sealed chunk** for the new device (the file's id and key, inside the session). Once only.
    pub fn history_chunk(&self, transport: Arc<dyn Transport>, auth_token: String) -> Result<Vec<u8>, StoreError> {
        let (key, counter) = {
            let st = self.state();
            if !st.confirmed || st.stage != Stage::Done || st.history_sent {
                return Err(StoreError::Rejected);
            }
            (st.session.data, st.counter)
        };
        self.set_history(HistoryProgress::at("building", 0, 1));
        let now = now_ms();
        let mut cutoff = now - DAYS * DAY_MS;
        let mut truncated = false;
        let (compressed, count, file_key, sealed, chunks) = loop {
            let (json, count) = {
                let conn = self.store.lock();
                build(&conn, cutoff, truncated)?
            };
            let compressed = deflate(&json)?;
            let file_key = random::<32>()?;
            let (sealed, chunks) = seal_all(&file_key, &compressed)?;
            if sealed.len() <= MAX_SEALED || cutoff >= now - DAY_MS {
                break (compressed, count, file_key, sealed, chunks);
            }
            // More than one file holds: the newest days only (the oldest day goes, and again).
            cutoff += DAY_MS;
            truncated = true;
        };
        let digest = hex_of(&Sha256::digest(&compressed));
        let blob_id = uuid::Uuid::new_v4().to_string();
        self.set_history(HistoryProgress::at("uploading", 0, sealed.len() as u64));
        let uploaded = upload(&transport, &auth_token, &blob_id, sealed.clone());
        if let Err(e) = uploaded {
            let _ = call(&transport, Some(&auth_token), "blob", &json!({ "action": "delete", "blob_id": blob_id }));
            self.set_history(HistoryProgress::idle());
            return Err(e);
        }
        self.set_history(HistoryProgress::at("done", sealed.len() as u64, sealed.len() as u64));
        let pointer = Pointer {
            v: VERSION,
            blob_id,
            key: vodozemac::base64_encode(file_key),
            chunks,
            sealed_size: sealed.len() as u64,
            digest,
            messages: count,
            cutoff_ms: cutoff,
            truncated,
        };
        let chunk = seal_chunk(LINK_LABEL, &key, counter, KIND_HISTORY, &serde_json::to_vec(&pointer).map_err(|_| StoreError::BadMessage)?)?;
        let mut st = self.state();
        st.counter += 1;
        st.history_sent = true;
        Ok(chunk)
    }

    /// How far the history step has got on the phone.
    pub fn history_progress(&self) -> HistoryProgress {
        self.state().history_progress.clone()
    }
}

impl LinkOld {
    fn set_history(&self, progress: HistoryProgress) {
        self.state().history_progress = progress;
    }
}

fn hex_of(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn upload(transport: &Arc<dyn Transport>, token: &str, blob_id: &str, sealed: Vec<u8>) -> Result<(), StoreError> {
    // One blob with a 24-hour expiry: the generic `blob` function (the attachment path keeps a file for 30 days if nobody fetches it).
    let (status, body) = call(transport, Some(token), "blob", &json!({ "action": "put", "blob_id": blob_id, "size": sealed.len(), "expires_in_days": 1 }))?;
    check(status)?;
    let url = body.get("url").and_then(Value::as_str).ok_or(StoreError::BadMessage)?;
    let (put, _) = super::super::photos::raw(transport, "PUT", url, Some("application/octet-stream"), sealed)?;
    check(put)?;
    let (status, _) = call(transport, Some(token), "blob", &json!({ "action": "commit", "blob_id": blob_id }))?;
    check(status)
}

#[uniffi::export]
impl LinkNew {
    /// Whether the phone has said where the history is (after the package; `import_chunk` took its chunk).
    pub fn history_pending(&self) -> bool {
        self.state().history.is_some()
    }

    /// How far the history step has got on this device.
    pub fn history_progress(&self) -> HistoryProgress {
        self.state().history_progress.clone()
    }

    /// **The new device's history step**, after `import_finish` and `register_device` (it needs this account's session): downloads the file, checks it, imports it
    /// all at once and deletes it from the server. A failure imports nothing and leaves the device as it was (the package stays); the file is left to expire.
    pub fn import_history(&self, transport: Arc<dyn Transport>, auth_token: String) -> Result<HistoryImported, StoreError> {
        let pointer = {
            let st = self.state();
            if !st.applied {
                return Err(StoreError::Rejected);
            }
            st.history.clone().ok_or(StoreError::Rejected)?
        };
        let result = self.fetch_and_import(&transport, &auth_token, &pointer);
        let mut st = self.state();
        match &result {
            Ok(_) => {
                st.history = None;
                st.history_progress = HistoryProgress::at("done", pointer.sealed_size, pointer.sealed_size);
                drop(st);
                // The file has done its work: remove it now rather than wait for the expiry (the same account may delete its own blob).
                let _ = call(&transport, Some(&auth_token), "blob", &json!({ "action": "delete", "blob_id": pointer.blob_id }));
            }
            Err(_) => st.history_progress = HistoryProgress::idle(),
        }
        result
    }
}

impl LinkNew {
    fn set_history(&self, progress: HistoryProgress) {
        self.state().history_progress = progress;
    }

    fn fetch_and_import(&self, transport: &Arc<dyn Transport>, token: &str, pointer: &Pointer) -> Result<HistoryImported, StoreError> {
        self.set_history(HistoryProgress::at("downloading", 0, pointer.sealed_size));
        let (status, body) = call(transport, Some(token), "blob", &json!({ "action": "get", "blob_id": pointer.blob_id }))?;
        if status == 404 {
            return Err(StoreError::NotFound);
        }
        check(status)?;
        let url = body.get("url").and_then(Value::as_str).ok_or(StoreError::BadMessage)?;
        let (status, sealed) = super::super::photos::raw(transport, "GET", url, None, Vec::new())?;
        check(status)?;
        if sealed.len() as u64 != pointer.sealed_size {
            return Err(StoreError::BadMessage);
        }
        self.set_history(HistoryProgress::at("importing", pointer.sealed_size, pointer.sealed_size));
        let key: [u8; 32] = vodozemac::base64_decode(&pointer.key).map_err(|_| StoreError::BadMessage)?.try_into().map_err(|_| StoreError::BadMessage)?;
        let compressed = open_all(&key, &sealed, pointer.chunks)?;
        if hex_of(&Sha256::digest(&compressed)) != pointer.digest {
            return Err(StoreError::BadMessage);
        }
        let history: History = serde_json::from_slice(&inflate(&compressed)?).map_err(|_| StoreError::BadMessage)?;
        apply(&self.store, history)
    }
}

/// Fills the store from a verified history: all or nothing.
fn apply(store: &LimeStore, history: History) -> Result<HistoryImported, StoreError> {
    if history.v != VERSION {
        return Err(StoreError::BadMessage);
    }
    let now = now_ms();
    // Nothing older than 45 days, ever: the new device holds the line too (an hour of slack for clocks).
    let oldest = now - DAYS * DAY_MS - 3_600_000;
    let conn = store.lock();
    let chats: HashSet<String> = {
        let mut stmt = conn.prepare("SELECT id FROM conversations").map_err(db_err)?;
        let ids = stmt.query_map([], |r| r.get::<_, String>(0)).map_err(db_err)?.collect::<Result<_, _>>().map_err(db_err)?;
        ids
    };
    let people: HashSet<String> = {
        let mut stmt = conn.prepare("SELECT id FROM people").map_err(db_err)?;
        let ids = stmt.query_map([], |r| r.get::<_, String>(0)).map_err(db_err)?.collect::<Result<_, _>>().map_err(db_err)?;
        ids
    };
    let known = columns(&conn, "messages")?;
    conn.execute_batch("BEGIN IMMEDIATE").map_err(db_err)?;
    let result = (|| -> Result<(u64, u64), StoreError> {
        let (mut imported, mut skipped) = (0u64, 0u64);
        let mut taken: HashSet<String> = HashSet::new();
        for row in &history.messages {
            let id = text(row, "id");
            let chat = text(row, "conversation_id");
            let sender = text(row, "sender_id");
            let sent_at = row.get("sent_at").and_then(Value::as_i64).unwrap_or(0);
            let ok = !id.is_empty()
                && id.len() <= 200
                && chats.contains(chat)
                && (chat.starts_with("dm:") || crate::store::groups::group_id_of(chat).is_some())
                && (sender == ME_ID || people.contains(sender))
                && sent_at >= oldest
                && sent_at <= now + 600_000
                && STATES.contains(&text(row, "local_state"));
            if !ok {
                skipped += 1;
                continue;
            }
            let cols: Vec<&String> = row.keys().filter(|k| known.contains(k) && k.as_str() != "hidden").collect();
            let sql = format!("INSERT OR IGNORE INTO messages ({}) VALUES ({})", cols.iter().map(|c| c.as_str()).collect::<Vec<_>>().join(", "), vec!["?"; cols.len()].join(", "));
            let values: Vec<rusqlite::types::Value> = cols.iter().map(|c| sql_of(&row[c.as_str()])).collect();
            let changed = conn.execute(&sql, rusqlite::params_from_iter(values)).map_err(db_err)?;
            if changed == 1 {
                imported += 1;
                taken.insert(id.to_owned());
            } else {
                skipped += 1;
            }
        }
        let attachment_cols = columns(&conn, "message_attachments")?;
        for row in history.attachments.iter().filter(|a| taken.contains(text(a, "message_id"))) {
            let cols: Vec<&String> = row.keys().filter(|k| attachment_cols.contains(k) && k.as_str() != "bytes").collect();
            let sql = format!("INSERT OR IGNORE INTO message_attachments ({}) VALUES ({})", cols.iter().map(|c| c.as_str()).collect::<Vec<_>>().join(", "), vec!["?"; cols.len()].join(", "));
            let values: Vec<rusqlite::types::Value> = cols.iter().map(|c| sql_of(&row[c.as_str()])).collect();
            conn.execute(&sql, rusqlite::params_from_iter(values)).map_err(db_err)?;
        }
        for row in history.reactions.iter().filter(|r| taken.contains(text(r, "message_id"))) {
            conn.execute(
                "INSERT OR IGNORE INTO reactions (message_id, user_id, emoji, hlc, active) VALUES (?1, ?2, ?3, ?4, ?5)",
                params![text(row, "message_id"), text(row, "user_id"), text(row, "emoji"), text(row, "hlc"), row.get("active").and_then(Value::as_i64).unwrap_or(0)],
            )
            .map_err(db_err)?;
        }
        for row in history.threads.iter().filter(|t| taken.contains(text(t, "root_id"))) {
            conn.execute("INSERT OR REPLACE INTO thread_state (root_id, unread) VALUES (?1, ?2)", params![text(row, "root_id"), row.get("unread").and_then(Value::as_i64).unwrap_or(0)]).map_err(db_err)?;
        }
        // The unread counts are the phone's (the package left them at zero: there were no messages).
        for (id, unread, marked) in &history.conversations {
            if chats.contains(id) {
                conn.execute("UPDATE conversations SET unread = ?2, marked_unread = ?3 WHERE id = ?1", params![id, unread.max(&0), marked.clamp(&0, &1)]).map_err(db_err)?;
            }
        }
        Ok((imported, skipped))
    })();
    match result {
        Ok((imported, skipped)) => {
            conn.execute_batch("COMMIT").map_err(db_err)?;
            Ok(HistoryImported { messages: imported, skipped, conversations: history.conversations.len() as u64, cutoff_ms: history.cutoff_ms, truncated: history.truncated })
        }
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK");
            Err(e)
        }
    }
}

/// How big the last 45 days are for this store: (plain JSON bytes, compressed bytes, sealed bytes, messages). For the size estimates in the record and the tests.
#[cfg(test)]
pub(crate) fn sizes(conn: &Connection, cutoff: i64) -> Result<(usize, usize, usize, u64), StoreError> {
    let (json, count) = build(conn, cutoff, false)?;
    let compressed = deflate(&json)?;
    let (sealed, _) = seal_all(&random::<32>()?, &compressed)?;
    Ok((json.len(), compressed.len(), sealed.len(), count))
}
