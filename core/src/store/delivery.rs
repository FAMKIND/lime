//! The delivery key and the contacts' delivery keys (`api-v2.md` sections 4 and 11).
//!
//! Each user has one random 32-byte delivery key, shared only inside their encrypted chats. A sender who
//! holds a contact's key sends **sealed**: the request carries `access_key = HKDF-SHA256(delivery_key,
//! "lime-access-v1")` (16 bytes) and no user token, so the server learns the recipient but not the sender.
//! The server stores only `SHA-256(access_key)`. Blocking someone rotates the key, which makes their sealed
//! sends fail. Keys never leave the encrypted database and never appear in an error or a log.
//!
//! **Signed access (LIME-139).** The access key is a reusable capability: anyone who sees one request (a future mesh relay) could message
//! that person. So a sealed send now carries a **signature** instead: both sides derive an Ed25519 key pair from the delivery key
//! (`seed = HKDF-SHA256(delivery_key, "lime-access-sign-v1")`, 32 bytes), the owner uploads the PUBLIC key, and a sender signs
//! `"lime-access-v2" || SHA-256(ciphertext) || to_device (16 raw UUID bytes)`, valid for that message to that device only. The older
//! access-key hash is still uploaded during the overlap (remove it before TestFlight).

use hkdf::Hkdf;
use rusqlite::{params, Connection, OptionalExtension};
use sha2::{Digest, Sha256};
use vodozemac::Ed25519SecretKey;

use super::{db_err, StoreError};

const KEY_BYTES: usize = 32;
pub(crate) const ACCESS_INFO: &[u8] = b"lime-access-v1";
pub(crate) const SIGN_INFO: &[u8] = b"lime-access-sign-v1";
pub(crate) const SIGNED_LABEL: &[u8] = b"lime-access-v2";

/// A new random delivery key.
pub(crate) fn random_key() -> Vec<u8> {
    Ed25519SecretKey::new().to_bytes().to_vec()
}

/// The 16-byte access key a sender presents for a recipient with this delivery key.
pub(crate) fn access_key(delivery_key: &[u8]) -> [u8; 16] {
    let mut out = [0u8; 16];
    Hkdf::<Sha256>::new(None, delivery_key)
        .expand(ACCESS_INFO, &mut out)
        .expect("16 bytes is a valid HKDF-SHA256 length");
    out
}

/// What the server stores: the base64 of `SHA-256(access_key)`.
pub(crate) fn access_hash_b64(delivery_key: &[u8]) -> String {
    vodozemac::base64_encode(Sha256::digest(access_key(delivery_key)))
}

/// The Ed25519 key pair both sides derive from a delivery key.
fn signing_key(delivery_key: &[u8]) -> Ed25519SecretKey {
    let mut seed = [0u8; 32];
    Hkdf::<Sha256>::new(None, delivery_key).expand(SIGN_INFO, &mut seed).expect("32 bytes is a valid HKDF-SHA256 length");
    Ed25519SecretKey::from_slice(&seed)
}

/// What the owner uploads beside the hash: the base64 of the public key of the pair derived from the delivery key.
pub(crate) fn access_public_key_b64(delivery_key: &[u8]) -> String {
    signing_key(delivery_key).public_key().to_base64()
}

/// The bytes a sender signs for one message to one device: the label, SHA-256 of the ciphertext and the device's 16 raw UUID bytes.
pub(crate) fn signed_message(ciphertext: &[u8], to_device: &str) -> Result<Vec<u8>, StoreError> {
    let device = uuid::Uuid::parse_str(to_device).map_err(|_| StoreError::BadMessage)?;
    let mut message = SIGNED_LABEL.to_vec();
    message.extend_from_slice(&Sha256::digest(ciphertext));
    message.extend_from_slice(device.as_bytes());
    Ok(message)
}

/// What a sealed send presents, base64: the signature for this ciphertext and this recipient device (see the module notes).
pub(crate) fn access_signature_b64(delivery_key: &[u8], ciphertext: &[u8], to_device: &str) -> Result<String, StoreError> {
    Ok(signing_key(delivery_key).sign(&signed_message(ciphertext, to_device)?).to_base64())
}

// ---------------------------------------------------------------- my own key

/// My delivery key and whether its hash is on the server; makes one the first time.
pub(crate) fn current(conn: &Connection, now_ms: i64) -> Result<(Vec<u8>, bool), StoreError> {
    let existing: Option<(String, bool)> = conn
        .query_row("SELECT key, uploaded FROM delivery_state WHERE id = 1", [], |r| Ok((r.get(0)?, r.get(1)?)))
        .optional()
        .map_err(db_err)?;
    if let Some((key, uploaded)) = existing {
        let bytes = vodozemac::base64_decode(key).map_err(|_| StoreError::BadMessage)?;
        if bytes.len() == KEY_BYTES {
            return Ok((bytes, uploaded));
        }
    }
    let key = random_key();
    conn.execute(
        "INSERT INTO delivery_state (id, key, uploaded, rotated_at) VALUES (1, ?1, 0, ?2)
         ON CONFLICT (id) DO UPDATE SET key = ?1, uploaded = 0, rotated_at = ?2",
        params![vodozemac::base64_encode(&key), now_ms],
    )
    .map_err(db_err)?;
    Ok((key, false))
}

/// A new key (a block): nobody has it yet, and the server has not seen its hash.
pub(crate) fn rotate(conn: &Connection, now_ms: i64) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO delivery_state (id, key, uploaded, rotated_at) VALUES (1, ?1, 0, ?2)
         ON CONFLICT (id) DO UPDATE SET key = ?1, uploaded = 0, rotated_at = ?2",
        params![vodozemac::base64_encode(random_key()), now_ms],
    )
    .map_err(db_err)?;
    Ok(())
}

pub(crate) fn mark_uploaded(conn: &Connection, key: &[u8]) -> Result<(), StoreError> {
    // Only if it is still the key that was uploaded (a rotation in between must be uploaded again).
    conn.execute(
        "UPDATE delivery_state SET uploaded = 1 WHERE id = 1 AND key = ?1",
        params![vodozemac::base64_encode(key)],
    )
    .map_err(db_err)?;
    Ok(())
}

// ---------------------------------------------------------------- contacts' keys

/// A contact's delivery key, and whether a sealed send to them was refused (they rotated it: they blocked
/// us, or replaced their keys) so no more sealed sends are tried until they share a new one.
pub(crate) fn contact_key(conn: &Connection, user: &str) -> Result<Option<(Vec<u8>, bool)>, StoreError> {
    let row: Option<(String, bool)> = conn
        .query_row(
            "SELECT key, denied FROM contact_delivery_keys WHERE user_id = ?1",
            params![user],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .optional()
        .map_err(db_err)?;
    Ok(row.and_then(|(key, denied)| vodozemac::base64_decode(key).ok().filter(|k| k.len() == KEY_BYTES).map(|k| (k, denied))))
}

pub(crate) fn store_contact_key(conn: &Connection, user: &str, key: &[u8], now_ms: i64) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO contact_delivery_keys (user_id, key, denied, received_at) VALUES (?1, ?2, 0, ?3)
         ON CONFLICT (user_id) DO UPDATE SET key = ?2, denied = 0, received_at = ?3",
        params![user, vodozemac::base64_encode(key), now_ms],
    )
    .map_err(db_err)?;
    Ok(())
}

pub(crate) fn mark_denied(conn: &Connection, user: &str) -> Result<(), StoreError> {
    conn.execute("UPDATE contact_delivery_keys SET denied = 1 WHERE user_id = ?1", params![user])
        .map_err(db_err)?;
    Ok(())
}

/// How many contacts messages can be sent to sealed (for the Debug-only About row).
pub(crate) fn sealed_contact_count(conn: &Connection) -> Result<u32, StoreError> {
    conn.query_row("SELECT count(*) FROM contact_delivery_keys WHERE denied = 0", [], |r| r.get(0))
        .map_err(db_err)
}

// ---------------------------------------------------------------- sharing my key

/// Queues "send my current delivery key to this person" (an Accept, a chat you start, an Unblock, a rotation).
pub(crate) fn queue_share(conn: &Connection, peer: &str, now_ms: i64) -> Result<(), StoreError> {
    conn.execute(
        "INSERT OR IGNORE INTO share_queue (peer_user_id, queued_at) VALUES (?1, ?2)",
        params![peer, now_ms],
    )
    .map_err(db_err)?;
    Ok(())
}

pub(crate) fn dequeue_share(conn: &Connection, peer: &str) -> Result<(), StoreError> {
    conn.execute("DELETE FROM share_queue WHERE peer_user_id = ?1", params![peer]).map_err(db_err)?;
    Ok(())
}

pub(crate) fn queued_shares(conn: &Connection) -> Result<Vec<String>, StoreError> {
    let mut statement = conn
        .prepare("SELECT peer_user_id FROM share_queue ORDER BY queued_at, peer_user_id")
        .map_err(db_err)?;
    let rows = statement.query_map([], |r| r.get::<_, String>(0)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(rows)
}

/// Remembers that this person has my current key (so a block of them needs a rotation, and Accept does
/// not send it twice).
pub(crate) fn mark_shared(conn: &Connection, peer: &str, now_ms: i64) -> Result<(), StoreError> {
    conn.execute(
        "INSERT OR REPLACE INTO key_shared (peer_user_id, shared_at) VALUES (?1, ?2)",
        params![peer, now_ms],
    )
    .map_err(db_err)?;
    Ok(())
}

pub(crate) fn unshare(conn: &Connection, peer: &str) -> Result<bool, StoreError> {
    let had = conn
        .execute("DELETE FROM key_shared WHERE peer_user_id = ?1", params![peer])
        .map_err(db_err)?;
    Ok(had > 0)
}

pub(crate) fn is_shared(conn: &Connection, peer: &str) -> Result<bool, StoreError> {
    conn.query_row("SELECT EXISTS (SELECT 1 FROM key_shared WHERE peer_user_id = ?1)", params![peer], |r| r.get(0))
        .map_err(db_err)
}

/// A key rotation: everyone must be given the new key. Forgets who had the old one.
pub(crate) fn forget_all_shared(conn: &Connection) -> Result<(), StoreError> {
    conn.execute("DELETE FROM key_shared", []).map_err(db_err)?;
    Ok(())
}

/// The accepted one-to-one chats: the people to re-share a new key with after a block.
pub(crate) fn accepted_peers(conn: &Connection) -> Result<Vec<String>, StoreError> {
    let mut statement = conn
        .prepare("SELECT substr(id, 4) FROM conversations WHERE id LIKE 'dm:%' AND request_state = 'accepted' AND id != 'dm:' || COALESCE((SELECT user_id FROM account WHERE id = 1), '') AND substr(id, 4) NOT IN (SELECT user_id FROM deleted_peers)")
        .map_err(db_err)?;
    let rows = statement.query_map([], |r| r.get::<_, String>(0)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(rows)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_access_key_is_sixteen_bytes_derived_from_the_delivery_key() {
        let a = access_key(&[1u8; 32]);
        assert_eq!(a.len(), 16);
        assert_eq!(a, access_key(&[1u8; 32]), "the same key gives the same access key");
        assert_ne!(a, access_key(&[2u8; 32]));
        // The hash the server stores is of the access key, not of the delivery key.
        assert_ne!(access_hash_b64(&[1u8; 32]), vodozemac::base64_encode(Sha256::digest([1u8; 32])));
    }

    const VECTOR_KEY: [u8; 32] = [7u8; 32];
    const VECTOR_DEVICE: &str = "0a0b0c0d-0e0f-4a1b-8c2d-3e4f5a6b7c8d";

    #[test]
    fn signed_access_fixed_test_vector_so_every_platform_derives_the_same_pair_and_signature() {
        // Must never change: another platform checks the same vector. Computed independently: HKDF-SHA256 with Python's hmac, the Ed25519
        // public key and signature with OpenSSL 3.6 (`openssl pkey` / `openssl pkeyutl -sign -rawin`), not with this code.
        let public = vodozemac::Ed25519PublicKey::from_base64(&access_public_key_b64(&VECTOR_KEY)).unwrap();
        assert_eq!(
            public.as_bytes().iter().map(|b| format!("{b:02x}")).collect::<String>(),
            "48f64e6a9932b684a073c9b47cf913871345f5b2dc9bd3123227d611589493cc"
        );
        let signature = vodozemac::Ed25519Signature::from_base64(&access_signature_b64(&VECTOR_KEY, b"hello lime", VECTOR_DEVICE).unwrap()).unwrap();
        assert_eq!(
            vodozemac::base64_encode(signature.to_bytes()).trim_end_matches('='),
            "lGF3ieAzmxRpRrgVd7Lzb9e7scE4/uIoNcrC0iK5qC0Am3PzXUcVooFUb5VY4ngPIcKEoQy+bWYirSproxhHAQ"
        );
        let message = signed_message(b"hello lime", VECTOR_DEVICE).unwrap();
        assert_eq!(message.len(), 14 + 32 + 16);
        assert!(message.starts_with(b"lime-access-v2"));
        assert!(public.verify(&message, &signature).is_ok());
    }

    #[test]
    fn a_signature_is_good_for_one_ciphertext_and_one_device_only() {
        let public = vodozemac::Ed25519PublicKey::from_base64(&access_public_key_b64(&VECTOR_KEY)).unwrap();
        let verify = |ciphertext: &[u8], device: &str, signature: &str| {
            let signature = vodozemac::Ed25519Signature::from_base64(signature).unwrap();
            public.verify(&signed_message(ciphertext, device).unwrap(), &signature).is_ok()
        };
        let signature = access_signature_b64(&VECTOR_KEY, b"hello lime", VECTOR_DEVICE).unwrap();
        assert!(verify(b"hello lime", VECTOR_DEVICE, &signature));
        assert!(!verify(b"hello lime!", VECTOR_DEVICE, &signature), "a changed byte of the ciphertext");
        assert!(!verify(b"hello lime", "0a0b0c0d-0e0f-4a1b-8c2d-3e4f5a6b7c8e", &signature), "another device");
        assert!(access_signature_b64(&VECTOR_KEY, b"hello lime", "not-a-uuid").is_err());
    }

    #[test]
    fn a_new_delivery_key_has_a_new_pair_and_the_old_signature_fails_against_it() {
        let old = random_key();
        let new = random_key();
        assert_ne!(access_public_key_b64(&old), access_public_key_b64(&new));
        let signature = vodozemac::Ed25519Signature::from_base64(&access_signature_b64(&old, b"ct", VECTOR_DEVICE).unwrap()).unwrap();
        let new_public = vodozemac::Ed25519PublicKey::from_base64(&access_public_key_b64(&new)).unwrap();
        assert!(new_public.verify(&signed_message(b"ct", VECTOR_DEVICE).unwrap(), &signature).is_err(), "a blocked sender's old key proves nothing");
        // The pair is not the delivery key itself, and the same key always gives the same pair.
        assert_ne!(access_public_key_b64(&VECTOR_KEY), vodozemac::Ed25519SecretKey::from_slice(&VECTOR_KEY).public_key().to_base64());
        assert_eq!(access_public_key_b64(&VECTOR_KEY), access_public_key_b64(&VECTOR_KEY));
    }
}
