//! The persisted protocol state: the account, the Olm sessions, and pinned master keys.

use rusqlite::{params, Connection, OptionalExtension};
use vodozemac::olm::{Account, AccountPickle, Session, SessionPickle};
use vodozemac::Ed25519SecretKey;

use super::{db_err, StoreError};
use crate::keys::AccountState;
use crate::protocol::Hlc;

pub(crate) fn load_account(
    conn: &Connection,
    pickle_key: &[u8; 32],
) -> Result<Option<AccountState>, StoreError> {
    let row = conn
        .query_row(
            "SELECT olm_pickle, master_secret, device_id, user_id, registered, hlc_wall, hlc_counter
             FROM account WHERE id = 1",
            [],
            |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, String>(2)?,
                    r.get::<_, Option<String>>(3)?,
                    r.get::<_, bool>(4)?,
                    r.get::<_, i64>(5)?,
                    r.get::<_, i64>(6)?,
                ))
            },
        )
        .optional()
        .map_err(db_err)?;
    let Some((olm, master, device_id, user_id, registered, wall, counter)) = row else {
        return Ok(None);
    };
    let account = Account::from_pickle(
        AccountPickle::from_encrypted(&olm, pickle_key).map_err(|_| StoreError::BadMessage)?,
    );
    let secret = vodozemac::base64_decode(&master).map_err(|_| StoreError::BadMessage)?;
    let secret: [u8; 32] = secret.try_into().map_err(|_| StoreError::BadMessage)?;
    Ok(Some(AccountState {
        account,
        master: Ed25519SecretKey::from_slice(&secret),
        device_id,
        user_id,
        registered,
        hlc: Hlc { wall, counter },
    }))
}

pub(crate) fn save_account(
    conn: &Connection,
    pickle_key: &[u8; 32],
    state: &AccountState,
) -> Result<(), StoreError> {
    let olm = state.account.pickle().encrypt(pickle_key);
    let master = vodozemac::base64_encode(state.master.to_bytes().as_slice());
    conn.execute(
        "INSERT INTO account (id, olm_pickle, master_secret, device_id, user_id, registered, hlc_wall, hlc_counter, created_at)
         VALUES (1, ?1, ?2, ?3, ?4, ?5, ?6, ?7, CAST(strftime('%s', 'now') AS INTEGER) * 1000)
         ON CONFLICT (id) DO UPDATE SET olm_pickle = ?1, master_secret = ?2, device_id = ?3,
           user_id = ?4, registered = ?5",
        // The clock is moved only by tick_hlc / observe_hlc (atomically), never from a stale copy.
        params![olm, master, state.device_id, state.user_id, state.registered, state.hlc.wall, state.hlc.counter],
    )
    .map_err(db_err)?;
    Ok(())
}

/// The next clock value for an op made now. Atomic in the database, so a send and a sync running
/// side by side never move the clock backwards.
pub(crate) fn tick_hlc(conn: &Connection, now_ms: i64) -> Result<Hlc, StoreError> {
    move_hlc(conn, |hlc| hlc.tick(now_ms))
}

/// Folds in the clock of an op received from another device.
pub(crate) fn observe_hlc(conn: &Connection, remote: Hlc, now_ms: i64) -> Result<Hlc, StoreError> {
    move_hlc(conn, |hlc| hlc.observe(remote, now_ms))
}

fn move_hlc(conn: &Connection, next: impl FnOnce(Hlc) -> Hlc) -> Result<Hlc, StoreError> {
    conn.execute_batch("SAVEPOINT hlc").map_err(db_err)?;
    let result = (|| {
        let (wall, counter): (i64, i64) = conn
            .query_row(
                "SELECT hlc_wall, hlc_counter FROM account WHERE id = 1",
                [],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .map_err(db_err)?;
        let moved = next(Hlc { wall, counter });
        conn.execute(
            "UPDATE account SET hlc_wall = ?1, hlc_counter = ?2 WHERE id = 1",
            params![moved.wall, moved.counter],
        )
        .map_err(db_err)?;
        Ok(moved)
    })();
    conn.execute_batch(if result.is_ok() { "RELEASE hlc" } else { "ROLLBACK TO hlc; RELEASE hlc" })
        .map_err(db_err)?;
    result
}

pub(crate) struct StoredSession {
    pub peer_identity_key: String,
    pub session: Session,
}

/// The most sessions kept per peer device; the least recently used go first.
const MAX_SESSIONS_PER_PEER: i64 = 5;

/// One row of `olm_sessions`, read: its columns, and the session unpickled.
fn read_session(
    conn: &Connection,
    pickle_key: &[u8; 32],
    user: &str,
    peer_identity_key: String,
    stored_id: String,
    pickle: String,
) -> Result<StoredSession, StoreError> {
    let session = Session::from_pickle(SessionPickle::from_encrypted(&pickle, pickle_key).map_err(|_| StoreError::BadMessage)?);
    if stored_id.is_empty() {
        // A row from before sessions were kept one each: its id could not be known until now. Fill it in (the row goes if that id is already there).
        let id = session.session_id();
        let moved = conn
            .execute(
                "UPDATE OR IGNORE olm_sessions SET session_id = ?3 WHERE peer_user_id = ?1 AND peer_identity_key = ?2 AND session_id = ''",
                params![user, peer_identity_key, id],
            )
            .map_err(db_err)?;
        if moved == 0 {
            conn.execute("DELETE FROM olm_sessions WHERE peer_user_id = ?1 AND peer_identity_key = ?2 AND session_id = ''", params![user, peer_identity_key]).map_err(db_err)?;
        }
    }
    Ok(StoredSession { peer_identity_key, session })
}

/// A person's sessions, the one a send should use first: the one that most recently decrypted something, else the newest.
pub(crate) fn load_sessions(
    conn: &Connection,
    pickle_key: &[u8; 32],
    peer_user: &str,
) -> Result<Vec<StoredSession>, StoreError> {
    let mut statement = conn
        .prepare(
            "SELECT peer_identity_key, session_id, session_pickle FROM olm_sessions
             WHERE peer_user_id = ?1 ORDER BY last_received DESC, created_at DESC",
        )
        .map_err(db_err)?;
    let rows = statement
        .query_map(params![peer_user], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, String>(2)?)))
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    drop(statement);
    rows.into_iter().map(|(identity, id, pickle)| read_session(conn, pickle_key, peer_user, identity, id, pickle)).collect()
}

/// Every Olm session with the person it belongs to (a sealed item does not say who sent it).
pub(crate) fn load_all_sessions(
    conn: &Connection,
    pickle_key: &[u8; 32],
) -> Result<Vec<(String, StoredSession)>, StoreError> {
    let mut statement = conn
        .prepare("SELECT peer_user_id, peer_identity_key, session_id, session_pickle FROM olm_sessions ORDER BY last_received DESC, created_at DESC")
        .map_err(db_err)?;
    let rows = statement
        .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, String>(2)?, r.get::<_, String>(3)?)))
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    drop(statement);
    rows.into_iter()
        .map(|(user, identity, id, pickle)| Ok((user.clone(), read_session(conn, pickle_key, &user, identity, id, pickle)?)))
        .collect()
}

/// Saves a session **by its own id**: it never replaces a different session with the same person. `received`: this session has just
/// decrypted a message (what a later send prefers). Keeps at most `MAX_SESSIONS_PER_PEER` per peer device, dropping the least recently
/// used, never the one just saved.
#[allow(clippy::too_many_arguments)]
pub(crate) fn save_session(
    conn: &Connection,
    pickle_key: &[u8; 32],
    peer_user: &str,
    peer_device: &str,
    peer_identity_key: &str,
    session: &Session,
    received: bool,
    now_ms: i64,
) -> Result<(), StoreError> {
    let id = session.session_id();
    conn.execute(
        "INSERT INTO olm_sessions (peer_user_id, peer_device_id, peer_identity_key, session_id, session_pickle, created_at, updated_at, last_received)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6, ?7)
         ON CONFLICT (peer_user_id, peer_identity_key, session_id) DO UPDATE SET
           peer_device_id = ?2, session_pickle = ?5, updated_at = ?6,
           last_received = CASE WHEN ?8 THEN ?6 ELSE last_received END",
        params![peer_user, peer_device, peer_identity_key, id, session.pickle().encrypt(pickle_key), now_ms, if received { now_ms } else { 0 }, received],
    )
    .map_err(db_err)?;
    conn.execute(
        "DELETE FROM olm_sessions WHERE peer_user_id = ?1 AND peer_identity_key = ?2 AND session_id <> ?3 AND session_id NOT IN (
             SELECT session_id FROM olm_sessions WHERE peer_user_id = ?1 AND peer_identity_key = ?2 AND session_id <> ?3 ORDER BY last_received DESC, updated_at DESC LIMIT ?4)",
        params![peer_user, peer_identity_key, id, MAX_SESSIONS_PER_PEER - 1],
    )
    .map_err(db_err)?;
    Ok(())
}

/// Trust on first use: remember a user's master key the first time it is seen, and refuse a
/// different one later.
pub(crate) fn pin_master_key(
    conn: &Connection,
    user_id: &str,
    master_key: &str,
) -> Result<(), StoreError> {
    conn.execute(
        "INSERT OR IGNORE INTO peers (user_id, master_key) VALUES (?1, ?2)",
        params![user_id, master_key],
    )
    .map_err(db_err)?;
    let pinned: String = conn
        .query_row(
            "SELECT master_key FROM peers WHERE user_id = ?1",
            params![user_id],
            |r| r.get(0),
        )
        .map_err(db_err)?;
    if pinned == master_key {
        Ok(())
    } else {
        Err(StoreError::KeyMismatch)
    }
}
