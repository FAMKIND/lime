//! Encrypted attachments on the device (LIME-98c): the descriptor that travels inside the encrypted message, its
//! storage, and the chunked AES-256-GCM that protects the file. The server only ever holds the ciphertext chunks.
//!
//! A file is encrypted in chunks of [`CHUNK`] bytes under a random per-file key. Each chunk's nonce is its index, and its
//! associated data is the attachment id, its index and the chunk count, so chunks cannot be reordered, dropped, added or
//! moved to another attachment. The descriptor also carries a SHA-256 of the whole plaintext, checked after decrypting.

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use super::{db_err, StoreError};

/// Plaintext bytes per chunk.
pub(crate) const CHUNK: usize = 1024 * 1024;
/// The largest file (plaintext), per the cost guardrails.
pub(crate) const MAX_BYTES: usize = 50 * 1024 * 1024;
/// Attachments per message (an album of photos).
pub(crate) const MAX_PER_MESSAGE: usize = 10;
const MAX_THUMB: usize = 2048;

/// What a message says about one attachment (all inside the encrypted message).
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Descriptor {
    pub id: String,
    pub key: Vec<u8>,
    /// Lower-case hex SHA-256 of the plaintext.
    pub digest: String,
    pub size: u64,
    pub mime: String,
    pub name: String,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub duration_ms: Option<u32>,
    pub thumb: Vec<u8>,
}

impl Descriptor {
    pub(crate) fn to_json(&self) -> Value {
        let mut value = json!({
            "id": self.id, "key": vodozemac::base64_encode(&self.key), "digest": self.digest, "size": self.size,
            "mime": self.mime, "name": self.name,
        });
        if let Some(w) = self.width { value["w"] = json!(w); }
        if let Some(h) = self.height { value["h"] = json!(h); }
        if let Some(d) = self.duration_ms { value["duration_ms"] = json!(d); }
        if !self.thumb.is_empty() { value["thumb"] = json!(vodozemac::base64_encode(&self.thumb)); }
        value
    }

    /// Reads one descriptor from a received payload, refusing anything malformed or out of bounds.
    pub(crate) fn parse(value: &Value) -> Option<Descriptor> {
        let text = |k: &str| value.get(k).and_then(Value::as_str);
        let number = |k: &str| value.get(k).and_then(Value::as_u64).and_then(|n| u32::try_from(n).ok());
        let id = text("id").filter(|id| is_uuid(id))?.to_ascii_lowercase();
        let key = vodozemac::base64_decode(text("key")?).ok().filter(|k| k.len() == 32)?;
        let digest = text("digest").filter(|d| d.len() == 64 && d.bytes().all(|b| b.is_ascii_hexdigit()))?.to_ascii_lowercase();
        let size = value.get("size").and_then(Value::as_u64).filter(|s| *s >= 1 && *s <= MAX_BYTES as u64)?;
        let mime = text("mime").filter(|m| !m.is_empty() && m.len() <= 100 && m.contains('/'))?.to_owned();
        let name: String = text("name").unwrap_or("").chars().filter(|c| !c.is_control() && *c != '/' && *c != '\\').take(255).collect();
        let thumb = match text("thumb") {
            None => Vec::new(),
            Some(t) => vodozemac::base64_decode(t).ok().filter(|b| b.len() <= MAX_THUMB)?,
        };
        Some(Descriptor { id, key, digest, size, mime, name, width: number("w"), height: number("h"), duration_ms: number("duration_ms"), thumb })
    }
}

fn is_uuid(text: &str) -> bool {
    text.len() == 36
        && text.bytes().enumerate().all(|(i, b)| if [8, 13, 18, 23].contains(&i) { b == b'-' } else { b.is_ascii_hexdigit() })
}

/// The attachments of a received payload (at most [`MAX_PER_MESSAGE`]); one malformed entry makes the whole message invalid.
pub(crate) fn parse_payload(payload: &Value) -> Option<Vec<Descriptor>> {
    let Some(list) = payload.get("attachments") else { return Some(Vec::new()) };
    let list = list.as_array().filter(|l| l.len() <= MAX_PER_MESSAGE)?;
    list.iter().map(Descriptor::parse).collect()
}

pub(crate) fn payload_value(descriptors: &[Descriptor]) -> Value {
    Value::Array(descriptors.iter().map(Descriptor::to_json).collect())
}

// ---------------------------------------------------------------- crypto

pub(crate) fn chunk_count(plaintext_len: usize) -> usize {
    plaintext_len.div_ceil(CHUNK).max(1)
}

pub(crate) fn digest_hex(plaintext: &[u8]) -> String {
    Sha256::digest(plaintext).iter().map(|b| format!("{b:02x}")).collect()
}

fn cipher(key: &[u8]) -> Aes256Gcm {
    Aes256Gcm::new_from_slice(key).expect("a 32-byte key")
}

fn nonce(index: u32) -> [u8; 12] {
    let mut out = [0u8; 12];
    out[8..].copy_from_slice(&index.to_be_bytes());
    out
}

fn aad(id: &str, index: u32, total: u32) -> Vec<u8> {
    [id.as_bytes(), &index.to_be_bytes(), &total.to_be_bytes()].concat()
}

/// A new random per-file key.
pub(crate) fn new_key() -> Vec<u8> {
    super::delivery::random_key()
}

/// Encrypts `plaintext` into chunks. The same inputs give the same chunks, so an interrupted upload resumes by
/// computing them again.
pub(crate) fn seal(key: &[u8], id: &str, plaintext: &[u8]) -> Vec<Vec<u8>> {
    let total = chunk_count(plaintext.len()) as u32;
    let cipher = cipher(key);
    (0..total)
        .map(|index| {
            let start = index as usize * CHUNK;
            let part = &plaintext[start.min(plaintext.len())..(start + CHUNK).min(plaintext.len())];
            cipher
                .encrypt(Nonce::from_slice(&nonce(index)), Payload { msg: part, aad: &aad(id, index, total) })
                .expect("encrypting in memory cannot fail")
        })
        .collect()
}

/// Decrypts the chunks (in order), `None` if any is changed, missing, extra or reordered.
pub(crate) fn open(key: &[u8], id: &str, chunks: &[Vec<u8>]) -> Option<Vec<u8>> {
    let total = u32::try_from(chunks.len()).ok().filter(|t| *t >= 1)?;
    let cipher = cipher(key);
    let mut out = Vec::new();
    for (index, chunk) in chunks.iter().enumerate() {
        let index = index as u32;
        let part = cipher.decrypt(Nonce::from_slice(&nonce(index)), Payload { msg: chunk, aad: &aad(id, index, total) }).ok()?;
        out.extend_from_slice(&part);
        if out.len() > MAX_BYTES {
            return None;
        }
    }
    Some(out)
}

// ---------------------------------------------------------------- storage

/// Position of a link preview's picture among a message's attachments (after any files).
pub(crate) const PREVIEW_POSITION: i64 = 1000;

pub(crate) fn insert(conn: &Connection, message_id: &str, position: usize, d: &Descriptor, bytes: Option<&[u8]>) -> Result<(), StoreError> {
    insert_as(conn, message_id, position as i64, d, bytes, "file")
}

/// The picture of a message's link preview: an attachment like any other, but not shown in the album.
pub(crate) fn insert_preview(conn: &Connection, message_id: &str, d: &Descriptor, bytes: Option<&[u8]>) -> Result<(), StoreError> {
    insert_as(conn, message_id, PREVIEW_POSITION, d, bytes, "preview")
}

fn insert_as(conn: &Connection, message_id: &str, position: i64, d: &Descriptor, bytes: Option<&[u8]>, role: &str) -> Result<(), StoreError> {
    // The same file can already be here (a forward shares it): then the bytes are copied, so deleting the first message
    // never takes the file from the second.
    let copied: Option<Vec<u8>> = match bytes {
        Some(_) => None,
        None => data(conn, &d.id)?,
    };
    conn.execute(
        "INSERT OR IGNORE INTO message_attachments
           (attachment_id, message_id, position, key, digest, size, mime, name, width, height, duration_ms, thumb, bytes, role)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)",
        params![
            d.id, message_id, position, vodozemac::base64_encode(&d.key), d.digest, d.size as i64, d.mime, d.name,
            d.width, d.height, d.duration_ms, if d.thumb.is_empty() { None } else { Some(&d.thumb) }, bytes.map(<[u8]>::to_vec).or(copied), role
        ],
    )
    .map_err(db_err)?;
    Ok(())
}

fn from_row(r: &rusqlite::Row<'_>) -> rusqlite::Result<(Descriptor, bool)> {
    let key: String = r.get(1)?;
    Ok((
        Descriptor {
            id: r.get(0)?,
            key: vodozemac::base64_decode(key).unwrap_or_default(),
            digest: r.get(2)?,
            size: r.get::<_, i64>(3)? as u64,
            mime: r.get(4)?,
            name: r.get(5)?,
            width: r.get(6)?,
            height: r.get(7)?,
            duration_ms: r.get(8)?,
            thumb: r.get::<_, Option<Vec<u8>>>(9)?.unwrap_or_default(),
        },
        r.get::<_, bool>(10)?,
    ))
}

const COLUMNS: &str = "attachment_id, key, digest, size, mime, name, width, height, duration_ms, thumb, bytes IS NOT NULL";

/// A message's files in order (not its link preview's picture), with whether this phone holds each one's bytes.
pub(crate) fn for_message(conn: &Connection, message_id: &str) -> Result<Vec<(Descriptor, bool)>, StoreError> {
    let mut statement = conn
        .prepare(&format!("SELECT {COLUMNS} FROM message_attachments WHERE message_id = ?1 AND role = 'file' ORDER BY position"))
        .map_err(db_err)?;
    let rows = statement.query_map(params![message_id], from_row).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(rows)
}

/// The picture of a message's link preview, if it has one.
pub(crate) fn preview_of(conn: &Connection, message_id: &str) -> Result<Option<(Descriptor, bool)>, StoreError> {
    conn.query_row(&format!("SELECT {COLUMNS} FROM message_attachments WHERE message_id = ?1 AND role = 'preview'"), params![message_id], from_row)
        .optional()
        .map_err(db_err)
}

/// One attachment by id (it can be in several messages): the row that holds its bytes if any does.
pub(crate) fn get(conn: &Connection, attachment_id: &str) -> Result<Option<(Descriptor, bool)>, StoreError> {
    conn.query_row(
        &format!("SELECT {COLUMNS} FROM message_attachments WHERE attachment_id = ?1 ORDER BY bytes IS NOT NULL DESC LIMIT 1"),
        params![attachment_id],
        from_row,
    )
    .optional()
    .map_err(db_err)
}

pub(crate) fn data(conn: &Connection, attachment_id: &str) -> Result<Option<Vec<u8>>, StoreError> {
    let bytes: Option<Vec<u8>> = conn
        .query_row("SELECT bytes FROM message_attachments WHERE attachment_id = ?1 AND bytes IS NOT NULL LIMIT 1", params![attachment_id], |r| r.get(0))
        .optional()
        .map_err(db_err)?;
    Ok(bytes)
}

pub(crate) fn set_data(conn: &Connection, attachment_id: &str, bytes: &[u8]) -> Result<(), StoreError> {
    conn.execute("UPDATE message_attachments SET bytes = ?2 WHERE attachment_id = ?1", params![attachment_id, bytes]).map_err(db_err)?;
    Ok(())
}

// ---------------------------------------------------------------- resumable downloads and progress

pub(crate) fn save_part(conn: &Connection, attachment_id: &str, index: usize, bytes: &[u8]) -> Result<(), StoreError> {
    conn.execute(
        "INSERT OR REPLACE INTO attachment_parts (attachment_id, idx, bytes) VALUES (?1, ?2, ?3)",
        params![attachment_id, index as i64, bytes],
    )
    .map_err(db_err)?;
    Ok(())
}

/// The chunk indexes of a download already held.
pub(crate) fn held_parts(conn: &Connection, attachment_id: &str) -> Result<Vec<usize>, StoreError> {
    let mut statement = conn.prepare("SELECT idx FROM attachment_parts WHERE attachment_id = ?1").map_err(db_err)?;
    let rows = statement.query_map(params![attachment_id], |r| r.get::<_, i64>(0)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(rows.into_iter().map(|i| i as usize).collect())
}

pub(crate) fn parts(conn: &Connection, attachment_id: &str, total: usize) -> Result<Option<Vec<Vec<u8>>>, StoreError> {
    let mut out = Vec::with_capacity(total);
    for index in 0..total {
        let part: Option<Vec<u8>> = conn
            .query_row("SELECT bytes FROM attachment_parts WHERE attachment_id = ?1 AND idx = ?2", params![attachment_id, index as i64], |r| r.get(0))
            .optional()
            .map_err(db_err)?;
        match part {
            Some(bytes) => out.push(bytes),
            None => return Ok(None),
        }
    }
    Ok(Some(out))
}

pub(crate) fn drop_parts(conn: &Connection, attachment_id: &str) -> Result<(), StoreError> {
    conn.execute("DELETE FROM attachment_parts WHERE attachment_id = ?1", params![attachment_id]).map_err(db_err)?;
    Ok(())
}

/// How far an upload (`up`) or download (`down`) has got, in chunks.
pub(crate) fn set_progress(conn: &Connection, attachment_id: &str, direction: &str, done: usize, total: usize) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO transfers (attachment_id, direction, done, total) VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT (attachment_id) DO UPDATE SET direction = ?2, done = ?3, total = ?4",
        params![attachment_id, direction, done as i64, total as i64],
    )
    .map_err(db_err)?;
    Ok(())
}

pub(crate) fn clear_progress(conn: &Connection, attachment_id: &str) -> Result<(), StoreError> {
    conn.execute("DELETE FROM transfers WHERE attachment_id = ?1", params![attachment_id]).map_err(db_err)?;
    Ok(())
}

pub(crate) fn progress(conn: &Connection, attachment_id: &str) -> Result<Option<(String, usize, usize)>, StoreError> {
    conn.query_row("SELECT direction, done, total FROM transfers WHERE attachment_id = ?1", params![attachment_id], |r| {
        Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)? as usize, r.get::<_, i64>(2)? as usize))
    })
    .optional()
    .map_err(db_err)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn id() -> String {
        uuid::Uuid::new_v4().to_string()
    }

    #[test]
    fn chunks_round_trip_and_hide_the_plaintext() {
        let (key, id) = (new_key(), id());
        let plain: Vec<u8> = (0..(CHUNK * 2 + 777)).map(|i| (i % 251) as u8).collect();
        let sealed = seal(&key, &id, &plain);
        assert_eq!(sealed.len(), 3);
        assert_eq!(sealed[0].len(), CHUNK + 16);
        assert!(!sealed[0].windows(64).any(|w| w == &plain[..64]), "no plaintext run in the ciphertext");
        assert_eq!(open(&key, &id, &sealed), Some(plain.clone()));
        assert_eq!(seal(&key, &id, &plain), sealed, "deterministic, so an upload can resume");
        // Empty and tiny files are one chunk.
        assert_eq!(seal(&key, &id, b"").len(), 1);
        assert_eq!(open(&key, &id, &seal(&key, &id, b"hi")), Some(b"hi".to_vec()));
    }

    #[test]
    fn a_changed_missing_extra_swapped_or_moved_chunk_is_refused() {
        let (key, id) = (new_key(), id());
        let plain = vec![7u8; CHUNK * 2 + 5];
        let sealed = seal(&key, &id, &plain);
        let mut flipped = sealed.clone();
        flipped[1][10] ^= 1;
        assert_eq!(open(&key, &id, &flipped), None, "a flipped byte");
        assert_eq!(open(&key, &id, &sealed[..2]), None, "a missing chunk");
        let mut extra = sealed.clone();
        extra.push(sealed[0].clone());
        assert_eq!(open(&key, &id, &extra), None, "an extra chunk");
        let swapped = vec![sealed[1].clone(), sealed[0].clone(), sealed[2].clone()];
        assert_eq!(open(&key, &id, &swapped), None, "reordered chunks");
        assert_eq!(open(&key, &self::id(), &sealed), None, "moved to another attachment");
        assert_eq!(open(&new_key(), &id, &sealed), None, "the wrong key");
    }

    #[test]
    fn a_descriptor_survives_json_and_a_malformed_one_is_refused() {
        let d = Descriptor {
            id: id(), key: new_key(), digest: digest_hex(b"x"), size: 1, mime: "image/jpeg".into(), name: "a.jpg".into(),
            width: Some(10), height: Some(20), duration_ms: None, thumb: vec![1, 2, 3],
        };
        assert_eq!(Descriptor::parse(&d.to_json()), Some(d.clone()));
        let mut bad = d.to_json();
        bad["key"] = json!("AAAA");
        assert_eq!(Descriptor::parse(&bad), None, "a short key");
        let mut big = d.to_json();
        big["size"] = json!(MAX_BYTES as u64 + 1);
        assert_eq!(Descriptor::parse(&big), None, "over the size limit");
        let mut path = d.to_json();
        path["name"] = json!("../../etc/passwd");
        assert_eq!(Descriptor::parse(&path).unwrap().name, "....etcpasswd", "no path separators survive");
        let mut thumb = d.to_json();
        thumb["thumb"] = json!(vodozemac::base64_encode(vec![0u8; 3000]));
        assert_eq!(Descriptor::parse(&thumb), None, "an oversized thumbnail");
        assert_eq!(parse_payload(&json!({ "attachments": vec![d.to_json(); 11] })), None, "too many");
        assert_eq!(parse_payload(&json!({ "text": "x" })), Some(vec![]));
    }
}
