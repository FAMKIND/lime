//! The parts of a profile that, like the photo, are Everyone's or contacts-only (LIME-214 links, LIME-217 background image).
//!
//! The same scheme as the photo (`photos.rs`): a contacts-only copy is `nonce || AES-256-GCM(data)` under a key derived from my profile key for the
//! slot, stored as a blob whose id is derived from the same key; an Everyone copy is a public object the server serves (the `avatar` function with a
//! `slot`). Each slot has its own derived key and id, so a links blob can never be read as a background.

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use hkdf::Hkdf;
use rusqlite::{params, Connection, OptionalExtension};
use sha2::Sha256;

use super::delivery::random_key;
use super::{db_err, StoreError};

pub(crate) const LINKS: &str = "links";
pub(crate) const BACKGROUND: &str = "background";
const NONCE_BYTES: usize = 12;

pub(crate) fn is_slot(slot: &str) -> bool {
    slot == LINKS || slot == BACKGROUND
}

/// The most a slot may hold: a short list of links, or a 1 MiB image.
pub(crate) fn max_bytes(slot: &str) -> usize {
    if slot == LINKS { 8 * 1024 } else { 1024 * 1024 }
}

fn derive(key: &[u8], info: &str, out: &mut [u8]) {
    Hkdf::<Sha256>::new(None, key).expand(info.as_bytes(), out).expect("a valid HKDF-SHA256 length");
}

/// The blob id of the contacts-only copy of `slot` made with `key`: derived, so only a key holder can find it.
pub(crate) fn blob_id(slot: &str, key: &[u8]) -> String {
    let mut bytes = [0u8; 16];
    derive(key, &format!("lime-{slot}-id-v1"), &mut bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    let hex: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    format!("{}-{}-{}-{}-{}", &hex[0..8], &hex[8..12], &hex[12..16], &hex[16..20], &hex[20..32])
}

pub(crate) fn seal(slot: &str, key: &[u8], data: &[u8]) -> Vec<u8> {
    let mut enc = [0u8; 32];
    derive(key, &format!("lime-{slot}-enc-v1"), &mut enc);
    let mut nonce = [0u8; NONCE_BYTES];
    nonce.copy_from_slice(&random_key()[..NONCE_BYTES]);
    let id = blob_id(slot, key);
    let cipher = Aes256Gcm::new_from_slice(&enc).expect("a 32-byte key");
    let body = cipher.encrypt(Nonce::from_slice(&nonce), Payload { msg: data, aad: id.as_bytes() }).expect("encrypting in memory cannot fail");
    [nonce.to_vec(), body].concat()
}

pub(crate) fn open(slot: &str, key: &[u8], blob: &[u8]) -> Option<Vec<u8>> {
    if blob.len() <= NONCE_BYTES + 16 {
        return None;
    }
    let mut enc = [0u8; 32];
    derive(key, &format!("lime-{slot}-enc-v1"), &mut enc);
    let id = blob_id(slot, key);
    let cipher = Aes256Gcm::new_from_slice(&enc).ok()?;
    cipher.decrypt(Nonce::from_slice(&blob[..NONCE_BYTES]), Payload { msg: &blob[NONCE_BYTES..], aad: id.as_bytes() }).ok()
}

// ---------------------------------------------------------------- mine

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Mine {
    pub data: Option<Vec<u8>>,
    pub visibility: String,
    pub uploaded_key: Option<String>,
}

pub(crate) fn mine(conn: &Connection, slot: &str) -> Result<Mine, StoreError> {
    let row = conn
        .query_row("SELECT data, visibility, uploaded_key FROM my_extra WHERE slot = ?1", params![slot], |r| {
            Ok(Mine { data: r.get(0)?, visibility: r.get(1)?, uploaded_key: r.get(2)? })
        })
        .optional()
        .map_err(db_err)?;
    Ok(row.unwrap_or(Mine { data: None, visibility: "contacts".into(), uploaded_key: None }))
}

pub(crate) fn save_mine(conn: &Connection, slot: &str, mine: &Mine, now_ms: i64) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO my_extra (slot, data, visibility, uploaded_key, updated_at) VALUES (?1, ?2, ?3, ?4, ?5)
         ON CONFLICT (slot) DO UPDATE SET data = ?2, visibility = ?3, uploaded_key = ?4, updated_at = ?5",
        params![slot, mine.data, mine.visibility, mine.uploaded_key, now_ms],
    )
    .map_err(db_err)?;
    Ok(())
}

// ---------------------------------------------------------------- others, cached

pub(crate) struct Cached {
    pub bytes: Vec<u8>,
    pub source: String,
    pub version: i64,
}

pub(crate) fn cached(conn: &Connection, user: &str, slot: &str) -> Result<Option<Cached>, StoreError> {
    conn.query_row("SELECT bytes, source, version FROM extras WHERE user_id = ?1 AND slot = ?2", params![user, slot], |r| {
        Ok(Cached { bytes: r.get(0)?, source: r.get(1)?, version: r.get(2)? })
    })
    .optional()
    .map_err(db_err)
}

pub(crate) fn save_cached(conn: &Connection, user: &str, slot: &str, bytes: &[u8], source: &str, version: i64, now_ms: i64) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO extras (user_id, slot, bytes, source, version, checked_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
         ON CONFLICT (user_id, slot) DO UPDATE SET bytes = ?3, source = ?4, version = ?5, checked_at = ?6",
        params![user, slot, bytes, source, version, now_ms],
    )
    .map_err(db_err)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn each_slot_has_its_own_id_and_key_and_a_stranger_opens_nothing() {
        let key = random_key();
        assert_ne!(blob_id(LINKS, &key), blob_id(BACKGROUND, &key), "a links blob is not a background's");
        assert_ne!(blob_id(LINKS, &key), super::super::photos::blob_id(&key), "nor the photo's");
        let links = br#"[{"title":"My site","url":"https://example.com"}]"#.repeat(3);
        let sealed = seal(LINKS, &key, &links);
        assert!(!sealed.windows(16).any(|w| w == &links[..16]), "no plaintext in the blob");
        assert_eq!(open(LINKS, &key, &sealed).as_deref(), Some(&links[..]));
        assert_eq!(open(BACKGROUND, &key, &sealed), None, "another slot's key does not open it");
        assert_eq!(open(LINKS, &random_key(), &sealed), None, "a stranger's key opens nothing");
        let mut tampered = sealed.clone();
        *tampered.last_mut().unwrap() ^= 1;
        assert_eq!(open(LINKS, &key, &tampered), None);
    }
}
