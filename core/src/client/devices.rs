//! The devices of my account (LIME-342a, DESIGN-M1 section 6): their names, the list, unlinking a computer, and what a removed device does.
//!
//! **Names live only inside encryption.** Each device holds a name ("Shem's MacBook Air": the app suggests one from the system) and a kind (phone, tablet or
//! computer) and tells my other devices by `own.copy` (`setting` / `device_name`); the server never sees a name or a kind (it stores only the device ids it
//! always stored). A new device learns the existing names from the link package (341b) and announces itself with `set_device_name`.
//!
//! **Unlinking** is for a computer only, and only from a device that holds the master secret (a phone or tablet): it signs a statement with the master key,
//! the server revokes the device (`devices-revoke`), and then everything the removed device might still use is rotated: the delivery key (it travels to my
//! other devices by `own.copy` and to my contacts by the usual share), the photo key, every group's outbound session and every jam's tier keys (a new one at the
//! next send, not shared with the removed device). My other devices are told by `own.copy` (`device_unlinked`) and rotate theirs. A phone or tablet is never
//! unlinked until DESIGN-M2: it holds the master secret, so removing it would change nothing.
//!
//! **A device that finds itself removed** (the server answers 401 `revoked`) remembers it; the next open wipes its store.
//!
//! What each party learns: the server learns which device was revoked and when (it already knows the ids and the count); my contacts see a new delivery key
//! like after a block; nobody learns a name or a kind.

use super::*;
use crate::store::{delivery, photos};

/// A device name: 1 to 60 characters, no control characters.
pub(crate) fn valid_name(name: &str) -> bool {
    let t = name.trim();
    !t.is_empty() && t.chars().count() <= 60 && !t.chars().any(char::is_control)
}

pub(crate) fn valid_kind(kind: &str) -> bool {
    matches!(kind, "phone" | "tablet" | "computer")
}

/// One of my devices, as the Linked Devices screen shows it.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct MyDevice {
    pub device_id: String,
    /// What the device calls itself; empty if it has not said yet.
    pub name: String,
    /// `phone`, `tablet`, `computer`, or `unknown` (a device that has not said yet).
    pub kind: String,
    /// When it was added (milliseconds).
    pub added_at: i64,
    pub is_this_device: bool,
}

/// Drops a device of mine from what this device holds (the list and its name).
pub(crate) fn forget_device(conn: &Connection, me: &str, device_id: &str) -> Result<(), StoreError> {
    conn.execute("DELETE FROM peer_devices WHERE user_id = ?1 AND device_id = ?2", params![me, device_id]).map_err(db_err)?;
    conn.execute("DELETE FROM own_device_info WHERE device_id = ?1", params![device_id]).map_err(db_err)?;
    Ok(())
}

/// Every group's outbound session and every jam's tier keys are replaced at the next send (and not shared with a device that was removed).
pub(crate) fn rotate_outbound(conn: &Connection) -> Result<(), StoreError> {
    conn.execute("UPDATE group_outbound_sessions SET rotate = 1", []).map_err(db_err)?;
    conn.execute("UPDATE jam_outbound SET rotate = 1", []).map_err(db_err)?;
    Ok(())
}

/// Empties every table of this store (a removed device keeps nothing of the account). The store stays a valid, empty database.
pub(crate) fn wipe_all(conn: &Connection) -> Result<(), StoreError> {
    conn.execute_batch("PRAGMA foreign_keys = OFF;").map_err(db_err)?;
    let tables: Vec<(String, String)> = {
        let mut stmt = conn.prepare("SELECT name, sql FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'").map_err(db_err)?;
        let rows = stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?.unwrap_or_default()))).map_err(db_err)?;
        rows.collect::<Result<_, _>>().map_err(db_err)?
    };
    let virtuals: Vec<&str> = tables.iter().filter(|(_, sql)| sql.to_ascii_uppercase().starts_with("CREATE VIRTUAL")).map(|(n, _)| n.as_str()).collect();
    for (name, _) in &tables {
        // A full-text index keeps its pieces in tables of its own: emptying the index table empties them.
        if virtuals.iter().any(|v| name.starts_with(&format!("{v}_"))) {
            continue;
        }
        conn.execute(&format!("DELETE FROM \"{}\"", name.replace('"', "")), []).map_err(db_err)?;
    }
    conn.execute_batch("PRAGMA foreign_keys = ON;").map_err(db_err)
}

#[uniffi::export]
impl LimeStore {
    /// This device's name and kind (`phone`, `tablet` or `computer`), sent to my other devices inside encryption. A device without the master secret is a
    /// computer; one that holds it is a phone or a tablet.
    pub fn set_device_name(&self, name: String, kind: String) -> Result<(), StoreError> {
        let name = name.trim().to_owned();
        if !valid_name(&name) || !valid_kind(&kind) {
            return Err(StoreError::Rejected);
        }
        let state = self.with_conn(|conn| load_account(conn, &self.pickle_key))?.ok_or(StoreError::NotRegistered)?;
        if state.master.is_some() == (kind == "computer") {
            return Err(StoreError::Rejected);
        }
        let now = now_ms();
        self.with_conn(|conn| {
            let added: i64 = conn.query_row("SELECT added_at FROM own_device_info WHERE device_id = ?1", params![state.device_id], |r| r.get(0)).optional().map_err(db_err)?.unwrap_or(now);
            conn.execute(
                "INSERT INTO own_device_info (device_id, name, kind, added_at) VALUES (?1, ?2, ?3, ?4)
                 ON CONFLICT (device_id) DO UPDATE SET name = ?2, kind = ?3",
                params![state.device_id, name, kind, added],
            )
            .map_err(db_err)?;
            own_devices_enqueue(
                conn,
                &json!({ "kind": "setting", "name": "device_name", "device_id": state.device_id, "device_name": name, "device_kind": kind, "added_at": added }),
            )
        })
    }

    /// My devices: this one first, then the others by when they were added, each with its name and kind (the list is what the server vouched for, checked against
    /// my master key; the names are what the devices told each other).
    pub fn my_devices(&self) -> Result<Vec<MyDevice>, StoreError> {
        let state = self.with_conn(|conn| load_account(conn, &self.pickle_key))?.ok_or(StoreError::NotRegistered)?;
        let me = state.user_id.clone().ok_or(StoreError::NotRegistered)?;
        self.with_conn(|conn| {
            let mut known: Vec<(String, i64)> = {
                let mut stmt = conn.prepare("SELECT device_id, updated_at FROM peer_devices WHERE user_id = ?1").map_err(db_err)?;
                let rows = stmt.query_map(params![me], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?))).map_err(db_err)?;
                rows.collect::<Result<_, _>>().map_err(db_err)?
            };
            if !known.iter().any(|(id, _)| *id == state.device_id) {
                known.push((state.device_id.clone(), 0));
            }
            let mut out = Vec::new();
            for (id, updated) in known {
                let info: Option<(String, String, i64)> = conn
                    .query_row("SELECT name, kind, added_at FROM own_device_info WHERE device_id = ?1", params![id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))
                    .optional()
                    .map_err(db_err)?;
                let (name, kind, added_at) = info.unwrap_or_else(|| (String::new(), "unknown".to_owned(), updated));
                out.push(MyDevice { is_this_device: id == state.device_id, device_id: id, name, kind, added_at });
            }
            out.sort_by_key(|d| (!d.is_this_device, d.added_at, d.device_id.clone()));
            Ok(out)
        })
    }

    /// Unlinks one of my computers (from a phone or tablet that holds the master secret): the server revokes it, then the delivery key, the photo key, every group's
    /// outbound session and every jam's tier keys are replaced and my other devices are told. Refused (`Rejected`) for a phone, a tablet, a device that has not said
    /// what it is, and this device itself; `MasterKeyNotOnDevice` on a computer.
    pub fn unlink_device(&self, transport: Arc<dyn Transport>, auth_token: String, device_id: String) -> Result<(), StoreError> {
        let _guard = self.protocol_lock.lock().unwrap_or_else(|e| e.into_inner());
        let state = self.with_conn(|conn| load_account(conn, &self.pickle_key))?.ok_or(StoreError::NotRegistered)?;
        let master = state.master.as_ref().ok_or(StoreError::MasterKeyNotOnDevice)?;
        let me = state.user_id.clone().ok_or(StoreError::NotRegistered)?;
        if device_id == state.device_id {
            return Err(StoreError::Rejected);
        }
        let (mine, kind): (bool, Option<String>) = self.with_conn(|conn| {
            let mine = conn.query_row("SELECT COUNT(*) FROM peer_devices WHERE user_id = ?1 AND device_id = ?2", params![me, device_id], |r| r.get::<_, i64>(0)).map_err(db_err)? > 0;
            let kind = conn.query_row("SELECT kind FROM own_device_info WHERE device_id = ?1", params![device_id], |r| r.get::<_, String>(0)).optional().map_err(db_err)?;
            Ok((mine, kind))
        })?;
        if !mine {
            return Err(StoreError::NotFound);
        }
        if kind.as_deref() != Some("computer") {
            return Err(StoreError::Rejected);
        }
        let at = now_ms();
        let signature = master.sign(format!("lime-revoke-v1\n{me}\n{device_id}\n{at}\ncomputer").as_bytes()).to_base64();
        let (status, _) = call(
            &transport,
            Some(&auth_token),
            "devices-revoke",
            &json!({ "device_id": device_id, "from_device": state.device_id, "at": at, "kind": "computer", "master_signature": signature }),
        )?;
        if status == 404 {
            // The server no longer has it as an active device of this account: forget it here too.
            self.with_conn(|conn| forget_device(conn, &me, &device_id))?;
            return Err(StoreError::NotFound);
        }
        check(status)?;
        self.with_conn(|conn| {
            let now = now_ms();
            forget_device(conn, &me, &device_id)?;
            rotate_outbound(conn)?;
            // A new delivery key, as after a block, for everyone: the removed computer held the old one. It reaches my other devices by `own.copy` (the removed one
            // is not in my list any more) and my contacts by the usual share.
            delivery::rotate(conn, now)?;
            let (key, _) = delivery::current(conn, now)?;
            own_devices_enqueue(conn, &json!({ "kind": "setting", "name": "delivery_key", "key": vodozemac::base64_encode(&key) }))?;
            photos::rotate_key(conn, now)?;
            delivery::forget_all_shared(conn)?;
            for other in delivery::accepted_peers(conn)? {
                delivery::queue_share(conn, &other, now)?;
            }
            own_devices_enqueue(conn, &json!({ "kind": "setting", "name": "device_unlinked", "device_id": device_id }))
        })
    }

    /// The server told this device it was removed from the account (and the next open will wipe the store): the app shows the signed-out state.
    pub fn was_revoked(&self) -> bool {
        self.with_conn(|conn| Ok(conn.query_row("SELECT COUNT(*) FROM device_state WHERE key = 'revoked'", [], |r| r.get::<_, i64>(0)).unwrap_or(0) > 0)).unwrap_or(false)
    }

    /// Wipes this store now (what the next open does for a removed device). The store stays a valid, empty database.
    pub fn wipe_removed_device(&self) -> Result<(), StoreError> {
        self.with_conn(wipe_all)
    }
}
