//! Profile photos on the device (LIME-98b): the profile key, my own photo, and other people's cached photos.
//!
//! A person's photo is either **public** (a plain JPEG any signed-in user can fetch, `api-v2.md` §6) or
//! **contacts-only**: encrypted with a key derived from my *profile key*, uploaded as an opaque blob whose
//! id is derived from the same key, so only someone I shared the key with can find or read it. The profile
//! key travels with the delivery key inside the encrypted chat and is rotated on a block.

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use hkdf::Hkdf;
use rusqlite::{params, Connection, OptionalExtension};
use sha2::Sha256;

use super::delivery::random_key;
use super::{db_err, StoreError};

const KEY_BYTES: usize = 32;
const NONCE_BYTES: usize = 12;
const ENC_INFO: &[u8] = b"lime-photo-enc-v1";
const ID_INFO: &[u8] = b"lime-photo-id-v1";
/// A photo is re-checked at most this often (milliseconds), unless a refresh is forced.
pub(crate) const RECHECK_MS: i64 = 60 * 60 * 1000;
/// Pull-to-refresh and opening a chat re-check a person at most this often (milliseconds).
pub(crate) const MIN_GAP_MS: i64 = 60 * 1000;

// ---------------------------------------------------------------- crypto (pure)

fn derive(key: &[u8], info: &[u8], out: &mut [u8]) {
    Hkdf::<Sha256>::new(None, key).expand(info, out).expect("a valid HKDF-SHA256 length");
}

/// The blob id for the contacts-only copy of a photo made with `key`: 16 derived bytes as a UUID, so nobody
/// who lacks the key can look it up.
pub(crate) fn blob_id(key: &[u8]) -> String {
    let mut bytes = [0u8; 16];
    derive(key, ID_INFO, &mut bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    let hex: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    format!("{}-{}-{}-{}-{}", &hex[0..8], &hex[8..12], &hex[12..16], &hex[16..20], &hex[20..32])
}

/// `nonce || AES-256-GCM(jpeg)`, bound to the blob id so a blob cannot be swapped for another.
pub(crate) fn seal(key: &[u8], jpeg: &[u8]) -> Vec<u8> {
    let mut enc = [0u8; 32];
    derive(key, ENC_INFO, &mut enc);
    let mut nonce = [0u8; NONCE_BYTES];
    nonce.copy_from_slice(&random_key()[..NONCE_BYTES]);
    let id = blob_id(key);
    let cipher = Aes256Gcm::new_from_slice(&enc).expect("a 32-byte key");
    let body = cipher
        .encrypt(Nonce::from_slice(&nonce), Payload { msg: jpeg, aad: id.as_bytes() })
        .expect("encrypting in memory cannot fail");
    [nonce.to_vec(), body].concat()
}

pub(crate) fn open(key: &[u8], blob: &[u8]) -> Option<Vec<u8>> {
    if blob.len() <= NONCE_BYTES + 16 {
        return None;
    }
    let mut enc = [0u8; 32];
    derive(key, ENC_INFO, &mut enc);
    let id = blob_id(key);
    let cipher = Aes256Gcm::new_from_slice(&enc).ok()?;
    cipher
        .decrypt(Nonce::from_slice(&blob[..NONCE_BYTES]), Payload { msg: &blob[NONCE_BYTES..], aad: id.as_bytes() })
        .ok()
}

// ---------------------------------------------------------------- my profile key

/// My profile key; makes one the first time.
pub(crate) fn current_key(conn: &Connection, now_ms: i64) -> Result<Vec<u8>, StoreError> {
    let existing: Option<String> =
        conn.query_row("SELECT key FROM profile_key WHERE id = 1", [], |r| r.get(0)).optional().map_err(db_err)?;
    if let Some(bytes) = existing.and_then(|k| vodozemac::base64_decode(k).ok()).filter(|k| k.len() == KEY_BYTES) {
        return Ok(bytes);
    }
    rotate_key(conn, now_ms)?;
    current_key_unchecked(conn)
}

fn current_key_unchecked(conn: &Connection) -> Result<Vec<u8>, StoreError> {
    let key: String = conn.query_row("SELECT key FROM profile_key WHERE id = 1", [], |r| r.get(0)).map_err(db_err)?;
    vodozemac::base64_decode(key).map_err(|_| StoreError::BadMessage)
}

/// A new profile key (a block). The contacts-only copy made with the old one is now stale.
pub(crate) fn rotate_key(conn: &Connection, now_ms: i64) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO profile_key (id, key, rotated_at) VALUES (1, ?1, ?2)
         ON CONFLICT (id) DO UPDATE SET key = ?1, rotated_at = ?2",
        params![vodozemac::base64_encode(random_key()), now_ms],
    )
    .map_err(db_err)?;
    Ok(())
}

// ---------------------------------------------------------------- contacts' profile keys

pub(crate) fn store_contact_key(conn: &Connection, user: &str, key: &[u8], now_ms: i64) -> Result<(), StoreError> {
    let same = contact_key(conn, user)?.is_some_and(|old| old == key);
    conn.execute(
        "INSERT INTO contact_profile_keys (user_id, key, received_at) VALUES (?1, ?2, ?3)
         ON CONFLICT (user_id) DO UPDATE SET key = ?2, received_at = ?3",
        params![user, vodozemac::base64_encode(key), now_ms],
    )
    .map_err(db_err)?;
    if !same {
        // A new key: whatever was cached from an encrypted copy, and the "checked recently" mark, are stale.
        conn.execute("DELETE FROM photos WHERE user_id = ?1 AND source = 'encrypted'", params![user]).map_err(db_err)?;
        conn.execute("UPDATE photos SET checked_at = 0 WHERE user_id = ?1", params![user]).map_err(db_err)?;
    }
    Ok(())
}

pub(crate) fn contact_key(conn: &Connection, user: &str) -> Result<Option<Vec<u8>>, StoreError> {
    let key: Option<String> = conn
        .query_row("SELECT key FROM contact_profile_keys WHERE user_id = ?1", params![user], |r| r.get(0))
        .optional()
        .map_err(db_err)?;
    Ok(key.and_then(|k| vodozemac::base64_decode(k).ok()).filter(|k| k.len() == KEY_BYTES))
}

// ---------------------------------------------------------------- my photo

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Mine {
    pub jpeg: Option<Vec<u8>>,
    pub visibility: String,
    pub uploaded_key: Option<String>,
}

pub(crate) fn mine(conn: &Connection) -> Result<Mine, StoreError> {
    let row = conn
        .query_row("SELECT jpeg, visibility, uploaded_key FROM my_photo WHERE id = 1", [], |r| {
            Ok(Mine { jpeg: r.get(0)?, visibility: r.get(1)?, uploaded_key: r.get(2)? })
        })
        .optional()
        .map_err(db_err)?;
    Ok(row.unwrap_or(Mine { jpeg: None, visibility: "everyone".into(), uploaded_key: None }))
}

pub(crate) fn mine_updated_at(conn: &Connection) -> Result<i64, StoreError> {
    Ok(conn.query_row("SELECT updated_at FROM my_photo WHERE id = 1", [], |r| r.get(0)).optional().map_err(db_err)?.unwrap_or(0))
}

pub(crate) fn save_mine(conn: &Connection, mine: &Mine, now_ms: i64) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO my_photo (id, jpeg, visibility, uploaded_key, updated_at) VALUES (1, ?1, ?2, ?3, ?4)
         ON CONFLICT (id) DO UPDATE SET jpeg = ?1, visibility = ?2, uploaded_key = ?3, updated_at = ?4",
        params![mine.jpeg, mine.visibility, mine.uploaded_key, now_ms],
    )
    .map_err(db_err)?;
    Ok(())
}

// ---------------------------------------------------------------- other people's cached photos

pub(crate) struct Cached {
    pub bytes: Vec<u8>,
    pub source: String,
    pub version: i64,
    pub checked_at: i64,
}

pub(crate) fn cached(conn: &Connection, user: &str) -> Result<Option<Cached>, StoreError> {
    conn.query_row("SELECT bytes, source, version, checked_at FROM photos WHERE user_id = ?1", params![user], |r| {
        Ok(Cached { bytes: r.get(0)?, source: r.get(1)?, version: r.get(2)?, checked_at: r.get(3)? })
    })
    .optional()
    .map_err(db_err)
}

pub(crate) fn save_cached(conn: &Connection, user: &str, bytes: &[u8], source: &str, version: i64, now_ms: i64) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO photos (user_id, bytes, source, version, checked_at) VALUES (?1, ?2, ?3, ?4, ?5)
         ON CONFLICT (user_id) DO UPDATE SET bytes = ?2, source = ?3, version = ?4, checked_at = ?5",
        params![user, bytes, source, version, now_ms],
    )
    .map_err(db_err)?;
    Ok(())
}

// ---------------------------------------------------------------- telling contacts my photo changed

/// Queues a "my photo changed" notice for each person (an accepted contact).
pub(crate) fn queue_notices(conn: &Connection, peers: &[String], now_ms: i64) -> Result<(), StoreError> {
    for peer in peers {
        conn.execute("INSERT OR IGNORE INTO photo_notices (peer_user_id, queued_at) VALUES (?1, ?2)", params![peer, now_ms])
            .map_err(db_err)?;
    }
    Ok(())
}

pub(crate) fn queued_notices(conn: &Connection) -> Result<Vec<String>, StoreError> {
    let mut statement = conn.prepare("SELECT peer_user_id FROM photo_notices ORDER BY queued_at, peer_user_id").map_err(db_err)?;
    let rows = statement.query_map([], |r| r.get::<_, String>(0)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(rows)
}

pub(crate) fn dequeue_notice(conn: &Connection, peer: &str) -> Result<(), StoreError> {
    conn.execute("DELETE FROM photo_notices WHERE peer_user_id = ?1", params![peer]).map_err(db_err)?;
    Ok(())
}

/// Someone told us their photo changed: it is due for a check at once.
pub(crate) fn mark_stale(conn: &Connection, user: &str) -> Result<(), StoreError> {
    conn.execute("UPDATE photos SET checked_at = 0 WHERE user_id = ?1", params![user]).map_err(db_err)?;
    Ok(())
}

/// Everyone whose photo could be shown: the people in my conversations (not me), a few hundred at most.
pub(crate) fn people_to_check(conn: &Connection, me: &str) -> Result<Vec<String>, StoreError> {
    let mut statement = conn
        .prepare("SELECT DISTINCT person_id FROM members WHERE person_id != ?1 AND person_id != 'me' LIMIT 300")
        .map_err(db_err)?;
    let rows = statement.query_map(params![me], |r| r.get::<_, String>(0)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(rows)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_photo_opens_only_with_its_own_key_and_the_ciphertext_hides_it() {
        let key = random_key();
        let jpeg = b"\xff\xd8\xff\xe0 a recognisable photo body".repeat(50);
        let sealed = seal(&key, &jpeg);
        assert!(!sealed.windows(24).any(|w| w == &jpeg[..24]), "no plaintext in the blob");
        assert_eq!(open(&key, &sealed).as_deref(), Some(&jpeg[..]));
        assert_eq!(open(&random_key(), &sealed), None, "a stranger's key opens nothing");
        let mut tampered = sealed.clone();
        *tampered.last_mut().unwrap() ^= 1;
        assert_eq!(open(&key, &tampered), None, "a changed byte is detected");
        assert_ne!(seal(&key, &jpeg), sealed, "a fresh nonce every time");
    }

    #[test]
    fn the_blob_id_is_a_uuid_only_the_key_holder_can_derive() {
        let key = random_key();
        let id = blob_id(&key);
        assert_eq!(id.len(), 36);
        assert_eq!(id, blob_id(&key));
        assert_ne!(id, blob_id(&random_key()));
        assert_eq!(id.as_bytes()[14], b'4');
    }
}
