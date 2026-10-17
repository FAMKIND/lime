//! Mailbox items that have been fetched but are not (yet) messages. They are written here before the
//! server is told to delete them, so nothing the server delivered is lost: an item stays until it
//! has been turned into a message, and is retried on each sync.

use rusqlite::{params, Connection};

use super::{db_err, StoreError};

/// Reasons an item is waiting.
pub(crate) const NEW: &str = "new";
pub(crate) const NO_SESSION: &str = "no_session";
pub(crate) const DECRYPT_FAILED: &str = "decrypt_failed";
/// Terminal: it will never become a message (a bad signature, a malformed op), but it is kept.
pub(crate) const INVALID: &str = "invalid";
pub(crate) const KEY_MISMATCH: &str = "key_mismatch";
/// A group message whose group (its create op) has not arrived yet.
pub(crate) const NO_GROUP: &str = "no_group";

#[derive(Debug, Clone)]
pub(crate) struct PendingRow {
    pub id: i64,
    pub sender_user: Option<String>,
    pub identified: bool,
    pub ciphertext: String,
    /// Set when the item was decrypted but held back for a changed key.
    pub plaintext: Option<Vec<u8>>,
    pub peer_identity: Option<String>,
}

pub(crate) struct Fetched {
    pub cursor: i64,
    pub sender_user: Option<String>,
    pub identified: bool,
    pub ciphertext: String,
    pub received_at: Option<String>,
}

/// Saves fetched items (one transaction). An item that is already here (the same cursor, fetched
/// again because an acknowledgement did not get through) is left as it is.
pub(crate) fn insert_all(
    conn: &mut Connection,
    items: &[Fetched],
    now_ms: i64,
) -> Result<(), StoreError> {
    let tx = conn.transaction().map_err(db_err)?;
    for item in items {
        tx.execute(
            "INSERT OR IGNORE INTO pending_inbound
               (cursor, sender_user, identified, ciphertext, received_at, reason, attempts, first_seen)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0, ?7)",
            params![item.cursor, item.sender_user, item.identified, item.ciphertext, item.received_at, NEW, now_ms],
        )
        .map_err(db_err)?;
    }
    tx.commit().map_err(db_err)
}

/// The items worth trying again, oldest first.
pub(crate) fn retryable(conn: &Connection) -> Result<Vec<PendingRow>, StoreError> {
    let mut statement = conn
        .prepare(
            "SELECT id, sender_user, identified, ciphertext, plaintext, peer_identity FROM pending_inbound
             WHERE reason NOT IN (?1, ?2) ORDER BY cursor",
        )
        .map_err(db_err)?;
    let rows = statement
        .query_map(params![INVALID, KEY_MISMATCH], |r| {
            Ok(PendingRow {
                id: r.get(0)?,
                sender_user: r.get(1)?,
                identified: r.get(2)?,
                ciphertext: r.get(3)?,
                plaintext: r.get(4)?,
                peer_identity: r.get(5)?,
            })
        })
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    Ok(rows)
}

pub(crate) fn remove(conn: &Connection, id: i64) -> Result<(), StoreError> {
    conn.execute("DELETE FROM pending_inbound WHERE id = ?1", params![id])
        .map_err(db_err)?;
    Ok(())
}

/// The item is still not a message: remember why, and that it was tried.
pub(crate) fn keep(
    conn: &Connection,
    id: i64,
    reason: &str,
    now_ms: i64,
) -> Result<(), StoreError> {
    conn.execute(
        "UPDATE pending_inbound SET reason = ?2, attempts = attempts + 1, last_attempt = ?3 WHERE id = ?1",
        params![id, reason, now_ms],
    )
    .map_err(db_err)?;
    Ok(())
}

/// Keeps what an item decrypted to, so it can be read once its sender's key is accepted.
pub(crate) fn stash_plaintext(
    conn: &Connection,
    id: i64,
    plaintext: &[u8],
    peer_identity: &str,
) -> Result<(), StoreError> {
    conn.execute(
        "UPDATE pending_inbound SET plaintext = ?2, peer_identity = ?3 WHERE id = ?1",
        params![id, plaintext, peer_identity],
    )
    .map_err(db_err)?;
    Ok(())
}

pub(crate) fn count(conn: &Connection) -> Result<u32, StoreError> {
    conn.query_row("SELECT count(*) FROM pending_inbound", [], |r| {
        r.get::<_, u32>(0)
    })
    .map_err(db_err)
}

/// The SHA-256 of an item's ciphertext (the wire bytes): the same message by the mesh and by the server has the same one.
pub(crate) fn ciphertext_hash(ciphertext_base64: &str) -> Option<Vec<u8>> {
    use sha2::{Digest, Sha256};
    let wire = vodozemac::base64_decode(ciphertext_base64).ok()?;
    Some(Sha256::digest(wire).to_vec())
}

/// Whether this ciphertext has already become a message (or was recognised as one we had).
pub(crate) fn already_received(conn: &Connection, hash: &[u8]) -> bool {
    conn.query_row("SELECT 1 FROM received_ciphertexts WHERE hash = ?1", params![hash], |_| Ok(())).is_ok()
}

/// Remembers a ciphertext that has been dealt with; forgets the ones older than 60 days.
pub(crate) fn remember_received(conn: &Connection, hash: &[u8], now_ms: i64) -> Result<(), StoreError> {
    conn.execute("INSERT OR IGNORE INTO received_ciphertexts (hash, at) VALUES (?1, ?2)", params![hash, now_ms]).map_err(db_err)?;
    conn.execute("DELETE FROM received_ciphertexts WHERE at < ?1", params![now_ms - 60 * 24 * 3600 * 1000]).map_err(db_err)?;
    Ok(())
}

/// Whether a waiting item came by the mesh (its cursor is negative: the mesh has no server cursor).
pub(crate) fn came_by_mesh(conn: &Connection, id: i64) -> bool {
    conn.query_row("SELECT cursor < 0 FROM pending_inbound WHERE id = ?1", params![id], |r| r.get::<_, bool>(0)).unwrap_or(false)
}
