//! Storage management (LIME-107): how much room media take, per chat; removing media by hand or by age ("Keep media") while the
//! messages stay; and the rules about a nearly full phone. Received files are kept decrypted in this encrypted store; the server's
//! copy goes about an hour after everyone fetched it, so this phone's copy may be the only one.

use rusqlite::params;

use super::{db_err, LimeStore, StoreError};

/// Below this much free space Lime stops downloading by itself and says so.
pub const LOW_STORAGE_BYTES: u64 = 500 * 1024 * 1024;
/// What an explicit download or send must leave free.
const KEEP_FREE_BYTES: u64 = 50 * 1024 * 1024;

/// Whether the phone is so full that automatic downloads pause.
#[uniffi::export]
pub fn storage_is_low(free_bytes: u64) -> bool {
    free_bytes < LOW_STORAGE_BYTES
}

/// Whether a download or an attachment of `needed_bytes` can be stored and still leave the phone usable.
#[uniffi::export]
pub fn storage_allows(free_bytes: u64, needed_bytes: u64) -> bool {
    free_bytes >= needed_bytes.saturating_add(KEEP_FREE_BYTES)
}

/// What one chat's media take on this phone.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ChatUsage {
    pub conversation_id: String,
    pub bytes: u64,
    pub files: u32,
}

/// What Lime uses on this phone.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct StorageUsage {
    /// The encrypted database file (messages, keys, search index and the files below).
    pub database_bytes: u64,
    /// The files received or sent (inside the database), all chats.
    pub media_bytes: u64,
    /// Per chat, the largest first.
    pub chats: Vec<ChatUsage>,
}

/// One file held for a chat.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct MediaEntry {
    pub message_id: String,
    pub attachment_id: String,
    pub name: String,
    pub mime: String,
    pub size: u64,
    pub sent_at: i64,
}

/// Names one file of one message (a file can be in several messages after a forward).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct MediaRef {
    pub message_id: String,
    pub attachment_id: String,
}

#[uniffi::export]
impl LimeStore {
    pub fn storage_usage(&self) -> Result<StorageUsage, StoreError> {
        let conn = self.lock();
        let pages: i64 = conn.query_row("PRAGMA page_count", [], |r| r.get(0)).map_err(db_err)?;
        // SQLCipher answers `page_size` in its own way (text on some builds), so read it loosely.
        let page_size: i64 = conn
            .query_row("PRAGMA page_size", [], |r| r.get::<_, rusqlite::types::Value>(0))
            .ok()
            .and_then(|v| match v {
                rusqlite::types::Value::Integer(n) => Some(n),
                rusqlite::types::Value::Text(t) => t.trim().parse().ok(),
                _ => None,
            })
            .unwrap_or(4096);
        let mut statement = conn
            .prepare(
                "SELECT m.conversation_id, SUM(length(a.bytes)), COUNT(*)
                 FROM message_attachments a JOIN messages m ON m.id = a.message_id
                 WHERE a.bytes IS NOT NULL AND m.hidden = 0
                 GROUP BY m.conversation_id ORDER BY SUM(length(a.bytes)) DESC, m.conversation_id",
            )
            .map_err(db_err)?;
        let chats = statement
            .query_map([], |r| Ok(ChatUsage { conversation_id: r.get(0)?, bytes: r.get::<_, i64>(1)? as u64, files: r.get::<_, i64>(2)? as u32 }))
            .map_err(db_err)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(db_err)?;
        let media_bytes = chats.iter().map(|c| c.bytes).sum();
        Ok(StorageUsage { database_bytes: (pages * page_size).max(0) as u64, media_bytes, chats })
    }

    /// The files held for a chat, largest first.
    pub fn list_media(&self, conversation_id: String) -> Result<Vec<MediaEntry>, StoreError> {
        let conn = self.lock();
        let mut statement = conn
            .prepare(
                "SELECT m.id, a.attachment_id, a.name, a.mime, length(a.bytes), m.sent_at
                 FROM message_attachments a JOIN messages m ON m.id = a.message_id
                 WHERE m.conversation_id = ?1 AND a.bytes IS NOT NULL AND m.hidden = 0
                 ORDER BY length(a.bytes) DESC, m.sent_at DESC",
            )
            .map_err(db_err)?;
        let rows = statement
            .query_map(params![conversation_id], |r| {
                Ok(MediaEntry { message_id: r.get(0)?, attachment_id: r.get(1)?, name: r.get(2)?, mime: r.get(3)?, size: r.get::<_, i64>(4)? as u64, sent_at: r.get(5)? })
            })
            .map_err(db_err)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(db_err)?;
        Ok(rows)
    }

    /// Removes files from this phone; the messages stay and show "Media removed". Returns how many were removed.
    pub fn remove_media(&self, items: Vec<MediaRef>) -> Result<u32, StoreError> {
        let mut conn = self.lock();
        let tx = conn.transaction().map_err(db_err)?;
        let mut removed = 0;
        for item in &items {
            removed += tx
                .execute(
                    "UPDATE message_attachments SET bytes = NULL, removed = 1 WHERE message_id = ?1 AND attachment_id = ?2 AND bytes IS NOT NULL",
                    params![item.message_id, item.attachment_id],
                )
                .map_err(db_err)? as u32;
        }
        tx.commit().map_err(db_err)?;
        Ok(removed)
    }

    /// "Keep media": removes the files of messages older than `days` days. Messages and any thumbnail stay; returns how many files went.
    pub fn remove_media_older_than(&self, days: u32) -> Result<u32, StoreError> {
        let cutoff = super::now_ms() - i64::from(days) * 86_400_000;
        let conn = self.lock();
        let n = conn
            .execute(
                "UPDATE message_attachments SET bytes = NULL, removed = 1
                 WHERE bytes IS NOT NULL AND message_id IN (SELECT id FROM messages WHERE sent_at < ?1)",
                params![cutoff],
            )
            .map_err(db_err)?;
        Ok(n as u32)
    }

    /// Gives the freed space back to the phone (the database file shrinks). Needs about the database's size free while it runs.
    pub fn compact_storage(&self) -> Result<(), StoreError> {
        let conn = self.lock();
        conn.execute_batch("VACUUM;").map_err(db_err)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_free_space_rules() {
        assert!(storage_is_low(100 * 1024 * 1024));
        assert!(!storage_is_low(LOW_STORAGE_BYTES));
        assert!(storage_allows(200 * 1024 * 1024, 100 * 1024 * 1024), "room for it and some to spare");
        assert!(!storage_allows(120 * 1024 * 1024, 100 * 1024 * 1024), "it would leave the phone too full");
        assert!(!storage_allows(10, u64::MAX), "no overflow");
    }
}
