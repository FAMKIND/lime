//! LimeCore's on-device store: SQLite encrypted at rest with SQLCipher.
//!
//! This is the *local view* only (people, conversations, members, messages). It has no networking
//! and no Olm or Megolm key storage; those arrive with the backend brief. The file is opened with
//! a raw 32-byte key supplied by the app (the iOS Keychain). No key material appears in any error
//! or log.
//!
//! Placeholders for the API v2 fields, deliberately not columns yet so nothing here pre-bakes that
//! design: the envelope signature (`sig`), a hybrid logical clock for ordering, and message
//! parents. See `docs/architecture.md` section 6.

pub(crate) mod account;
mod migrations;
pub(crate) mod pending;
mod sample;
#[cfg(test)]
mod tests;

use std::sync::Mutex;

use rusqlite::{params, Connection, OptionalExtension};
use uuid::Uuid;

/// The id of the person who owns this device. Messages with this sender are "mine".
pub(crate) const ME_ID: &str = "me";

/// Messages made on this device and not sent anywhere yet.
pub(crate) const LOCAL_STATE_SENT_LOCAL: &str = "sent_local";

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Error)]
pub enum StoreError {
    /// The key is not 32 bytes.
    InvalidKey,
    /// The file could not be opened or is not an encrypted Lime database for this key.
    WrongKeyOrNotADatabase,
    /// The linked SQLite is not SQLCipher, so the file would not be encrypted.
    EncryptionUnavailable,
    /// The database was written by a newer version of Lime, or a migration failed.
    Migration,
    /// The conversation does not exist.
    NotFound,
    /// The message text is empty.
    EmptyMessage,
    /// Any other database failure (the message carries no key material).
    Database,
    /// The network request could not be made (no response).
    Network,
    /// The server refused the request (a 4xx: bad request, not allowed, rate limited, conflict).
    Rejected,
    /// The server could not handle the request (a 5xx).
    Unavailable,
    /// A message or a response was malformed, failed verification, or stored state is unreadable.
    BadMessage,
    /// This device has not been registered with the server yet.
    NotRegistered,
    /// The recipient has no devices to send to, or no keys to start a session with.
    NoRecipientKeys,
    /// A person's master key differs from the one remembered for them.
    KeyMismatch,
}

impl std::fmt::Display for StoreError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let text = match self {
            StoreError::InvalidKey => "the storage key must be 32 bytes",
            StoreError::WrongKeyOrNotADatabase => "the database could not be opened with this key",
            StoreError::EncryptionUnavailable => "SQLCipher is not available",
            StoreError::Migration => "the database schema could not be brought up to date",
            StoreError::NotFound => "no such conversation",
            StoreError::EmptyMessage => "a message cannot be empty",
            StoreError::Database => "a database error occurred",
            StoreError::Network => "the network request failed",
            StoreError::Rejected => "the server refused the request",
            StoreError::Unavailable => "the server could not handle the request",
            StoreError::BadMessage => "a message or response could not be verified",
            StoreError::NotRegistered => "this device is not registered yet",
            StoreError::NoRecipientKeys => "the recipient has no keys to send to",
            StoreError::KeyMismatch => "a person's master key changed",
        };
        f.write_str(text)
    }
}

impl std::error::Error for StoreError {}

/// A person as shown next to a conversation (the initials and colour are derived from these).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct MemberInfo {
    pub id: String,
    pub name: String,
    pub initials: String,
    /// An index into the app's avatar palette (0 to 7).
    pub tone: u32,
}

/// One message. `sender_id` is `None` when the message is mine.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct MessageItem {
    pub id: String,
    pub conversation_id: String,
    pub sender_id: Option<String>,
    pub text: String,
    /// The display time, in milliseconds since the Unix epoch.
    pub sent_at: i64,
    pub local_state: String,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ConversationSummary {
    pub id: String,
    pub title: String,
    pub is_group: bool,
    pub is_pinned: bool,
    pub unread: u32,
    pub last_message: Option<MessageItem>,
    /// The other people (never me), in a stable order.
    pub members: Vec<MemberInfo>,
}

/// The encrypted local store. Thread-safe: one connection behind a mutex.
#[derive(uniffi::Object)]
pub struct LimeStore {
    conn: Mutex<Connection>,
    /// Encrypts the Olm pickles: derived from the store key (HKDF). Never logged.
    pub(crate) pickle_key: [u8; 32],
    /// Serialises register, send and sync, so two of them never interleave their network calls.
    pub(crate) protocol_lock: Mutex<()>,
}

pub(crate) fn db_err(_: rusqlite::Error) -> StoreError {
    StoreError::Database
}

pub(crate) fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

pub(crate) fn new_id() -> String {
    Uuid::now_v7().to_string()
}

pub(crate) fn initials_of(name: &str) -> String {
    name.split_whitespace()
        .take(2)
        .filter_map(|word| word.chars().next())
        .flat_map(|c| c.to_uppercase())
        .collect()
}

#[uniffi::export]
impl LimeStore {
    /// Opens (creating if needed) the encrypted database at `path` with a raw 32-byte `key`, and
    /// brings the schema up to date. A wrong key fails here.
    #[uniffi::constructor]
    pub fn open(path: String, key: Vec<u8>) -> Result<std::sync::Arc<Self>, StoreError> {
        Ok(std::sync::Arc::new(Self::open_inner(&path, &key)?))
    }

    /// Inserts the made-up people, conversations and messages the app shows before there is a
    /// backend, but only into an empty store. Safe to call on every launch.
    pub fn seed_sample_data_if_empty(&self) -> Result<(), StoreError> {
        let mut conn = self.lock();
        let tx = conn.transaction().map_err(db_err)?;
        let empty: bool = tx
            .query_row("SELECT NOT EXISTS (SELECT 1 FROM conversations)", [], |r| {
                r.get(0)
            })
            .map_err(db_err)?;
        if empty {
            sample::insert(&tx, now_ms()).map_err(db_err)?;
        }
        tx.commit().map_err(db_err)
    }

    /// Conversations, pinned first and then newest message first.
    pub fn list_conversations(&self) -> Result<Vec<ConversationSummary>, StoreError> {
        let conn = self.lock();
        let mut statement = conn
            .prepare(
                "SELECT c.id, c.title, c.is_group, c.is_pinned, c.unread
                 FROM conversations c
                 ORDER BY c.is_pinned DESC,
                          COALESCE((SELECT MAX(m.sent_at) FROM messages m
                                    WHERE m.conversation_id = c.id), 0) DESC,
                          c.id",
            )
            .map_err(db_err)?;
        let rows = statement
            .query_map([], |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, bool>(2)?,
                    r.get::<_, bool>(3)?,
                    r.get::<_, u32>(4)?,
                ))
            })
            .map_err(db_err)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(db_err)?;

        let mut summaries = Vec::with_capacity(rows.len());
        for (id, title, is_group, is_pinned, unread) in rows {
            summaries.push(ConversationSummary {
                last_message: last_message(&conn, &id)?,
                members: members_of(&conn, &id)?,
                id,
                title,
                is_group,
                is_pinned,
                unread,
            });
        }
        Ok(summaries)
    }

    /// A conversation's messages, oldest first.
    pub fn list_messages(&self, conversation_id: String) -> Result<Vec<MessageItem>, StoreError> {
        let conn = self.lock();
        let mut statement = conn
            .prepare(
                "SELECT id, conversation_id, sender_id, body, sent_at, local_state
                 FROM messages WHERE conversation_id = ?1 ORDER BY sent_at, id",
            )
            .map_err(db_err)?;
        let items = statement
            .query_map(params![conversation_id], message_from_row)
            .map_err(db_err)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(db_err)?;
        Ok(items)
    }

    /// Writes a message from this device into the conversation and returns it. It is stored
    /// locally only (`local_state` is `sent_local`).
    pub fn send_local_message(
        &self,
        conversation_id: String,
        text: String,
    ) -> Result<MessageItem, StoreError> {
        let body = text.trim();
        if body.is_empty() {
            return Err(StoreError::EmptyMessage);
        }
        let conn = self.lock();
        let exists: bool = conn
            .query_row(
                "SELECT EXISTS (SELECT 1 FROM conversations WHERE id = ?1)",
                params![conversation_id],
                |r| r.get(0),
            )
            .map_err(db_err)?;
        if !exists {
            return Err(StoreError::NotFound);
        }
        let item = MessageItem {
            id: new_id(),
            conversation_id,
            sender_id: None,
            text: body.to_string(),
            sent_at: now_ms(),
            local_state: LOCAL_STATE_SENT_LOCAL.to_string(),
        };
        conn.execute(
            "INSERT INTO messages (id, conversation_id, sender_id, body, sent_at, local_state)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![
                item.id,
                item.conversation_id,
                ME_ID,
                item.text,
                item.sent_at,
                item.local_state
            ],
        )
        .map_err(db_err)?;
        Ok(item)
    }
}

impl LimeStore {
    pub(crate) fn lock(&self) -> std::sync::MutexGuard<'_, Connection> {
        // A poisoned lock only means another call panicked; the database itself is intact.
        self.conn.lock().unwrap_or_else(|e| e.into_inner())
    }

    pub(crate) fn open_inner(path: &str, key: &[u8]) -> Result<Self, StoreError> {
        if key.len() != 32 {
            return Err(StoreError::InvalidKey);
        }
        let conn = Connection::open(path).map_err(|_| StoreError::WrongKeyOrNotADatabase)?;

        // The raw key as a hex blob literal, so SQLCipher skips its password key derivation.
        let mut pragma = String::with_capacity(32 + 64);
        pragma.push_str("PRAGMA key = \"x'");
        for byte in key {
            pragma.push_str(&format!("{byte:02x}"));
        }
        pragma.push_str("'\";");
        let keyed = conn.execute_batch(&pragma);
        // Do not keep the key text around.
        drop(pragma);
        keyed.map_err(|_| StoreError::WrongKeyOrNotADatabase)?;

        // This also fails with a wrong key (or a file that is not a database), which is the point.
        conn.query_row("SELECT count(*) FROM sqlite_master", [], |r| {
            r.get::<_, i64>(0)
        })
        .map_err(|_| StoreError::WrongKeyOrNotADatabase)?;

        // Plain SQLite silently ignores PRAGMA key. Refuse to run unencrypted.
        let cipher: Option<String> = conn
            .query_row("PRAGMA cipher_version", [], |r| r.get(0))
            .optional()
            .map_err(db_err)?;
        if cipher.as_deref().unwrap_or("").is_empty() {
            return Err(StoreError::EncryptionUnavailable);
        }

        conn.execute_batch("PRAGMA foreign_keys = ON;")
            .map_err(db_err)?;
        migrations::run(&conn)?;
        Ok(Self {
            conn: Mutex::new(conn),
            pickle_key: crate::keys::derive_pickle_key(key),
            protocol_lock: Mutex::new(()),
        })
    }
}

fn message_from_row(r: &rusqlite::Row<'_>) -> rusqlite::Result<MessageItem> {
    let sender: String = r.get(2)?;
    Ok(MessageItem {
        id: r.get(0)?,
        conversation_id: r.get(1)?,
        sender_id: if sender == ME_ID { None } else { Some(sender) },
        text: r.get(3)?,
        sent_at: r.get(4)?,
        local_state: r.get(5)?,
    })
}

fn last_message(
    conn: &Connection,
    conversation_id: &str,
) -> Result<Option<MessageItem>, StoreError> {
    conn.query_row(
        "SELECT id, conversation_id, sender_id, body, sent_at, local_state
         FROM messages WHERE conversation_id = ?1 ORDER BY sent_at DESC, id DESC LIMIT 1",
        params![conversation_id],
        message_from_row,
    )
    .optional()
    .map_err(db_err)
}

fn members_of(conn: &Connection, conversation_id: &str) -> Result<Vec<MemberInfo>, StoreError> {
    let mut statement = conn
        .prepare(
            "SELECT p.id, p.name, p.tone FROM members m JOIN people p ON p.id = m.person_id
             WHERE m.conversation_id = ?1 AND p.id != ?2 ORDER BY m.position",
        )
        .map_err(db_err)?;
    let members = statement
        .query_map(params![conversation_id, ME_ID], |r| {
            let name: String = r.get(1)?;
            Ok(MemberInfo {
                id: r.get(0)?,
                initials: initials_of(&name),
                name,
                tone: r.get(2)?,
            })
        })
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    Ok(members)
}
