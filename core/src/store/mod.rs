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
pub(crate) mod attachments;
pub(crate) mod delivery;
pub(crate) mod groups;
pub(crate) mod labels;
pub(crate) mod message_ops;
mod migrations;
pub(crate) mod order;
pub(crate) mod photos;
pub(crate) mod pending;
pub(crate) mod search;
pub(crate) mod threads;
pub(crate) mod link_preview;
pub(crate) mod storage;
mod sample;
#[cfg(test)]
mod search_tests;
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
    /// The server says too many requests (a 429): try again shortly.
    RateLimited,
    /// The server does not accept this session (a 401 or 403): it ended, was never fully verified,
    /// or this device was replaced. The person must sign in again.
    Unauthorized,
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
            StoreError::RateLimited => "too many requests; try again shortly",
            StoreError::Unauthorized => "the session ended; sign in again",
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
    /// My private label for this person (shown only to me), if I gave one.
    pub label: Option<String>,
}

/// One attachment of a message, as the app shows it (the key and digest stay in the core).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct AttachmentInfo {
    pub id: String,
    pub mime: String,
    pub name: String,
    /// Plaintext bytes.
    pub size: u64,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub duration_ms: Option<u32>,
    /// A tiny preview image (JPEG), empty when there is none.
    pub thumb: Vec<u8>,
    /// This phone holds the decrypted file.
    pub downloaded: bool,
    /// Removed from this phone on purpose (by hand or by "Keep media"): it cannot be downloaded again.
    pub removed: bool,
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
    pub attachments: Vec<AttachmentInfo>,
    /// The text was edited (only the latest text is kept).
    pub edited: bool,
    /// Deleted for everyone: only its place is kept ("This message was deleted").
    pub deleted: bool,
    /// The emoji reactions on it.
    pub reactions: Vec<message_ops::Reaction>,
    /// Forwarded from another chat (the original sender is never named).
    pub forwarded: bool,
    /// The link card it carries, if any.
    pub link_preview: Option<link_preview::LinkPreview>,
    /// For a reply: the message it answers (the root of its thread).
    pub thread_root: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ConversationSummary {
    /// When the newest thing happened (a message, a reply or a reaction), milliseconds: what the list shows and sorts by.
    pub activity_at: i64,
    /// Set when the newest thing is a reaction (newer than the last message).
    pub last_reaction: Option<message_ops::ReactionActivity>,
    pub id: String,
    pub title: String,
    pub is_group: bool,
    pub is_pinned: bool,
    pub unread: u32,
    /// `pending` (a stranger's first message, waiting in Requests) or `accepted`. Blocked
    /// conversations are not listed.
    pub request_state: String,
    /// The other person's security key changed since we pinned it: accept it to keep chatting.
    pub key_change_pending: bool,
    pub last_message: Option<MessageItem>,
    /// The other people (never me), in a stable order.
    pub members: Vec<MemberInfo>,
    /// A group's emoji avatar, if it has one.
    pub group_emoji: Option<String>,
    /// The other person's key was confirmed in person against their QR code (one-to-one chats).
    pub verified: bool,
    /// I marked the conversation unread by hand (it shows the unread dot until opened).
    pub marked_unread: bool,
    /// `last_message` is a reply in a thread (it is the newest thing in the conversation, replies included).
    pub last_is_reply: bool,
}

/// Someone you blocked: they can be unblocked, which brings their conversation back.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct BlockedPerson {
    pub conversation_id: String,
    pub name: String,
    pub tone: u32,
}

/// What Settings shows about this device's keys: when they were made, and a short fingerprint of the
/// account's master public key (read-only; comparing it is for a later brief).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct KeyInfo {
    /// Five groups of four hex digits, e.g. `A1B2 C3D4 E5F6 0718 293A`.
    pub fingerprint: String,
    /// Milliseconds since the Unix epoch.
    pub created_at: i64,
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
                "SELECT c.id, c.title, c.is_group, c.is_pinned, c.unread, c.request_state,
                        EXISTS (SELECT 1 FROM peers p WHERE 'dm:' || p.user_id = c.id AND p.new_master_key IS NOT NULL),
                        c.group_emoji,
                        EXISTS (SELECT 1 FROM peers p WHERE 'dm:' || p.user_id = c.id AND p.verified_at IS NOT NULL AND p.new_master_key IS NULL),
                        c.marked_unread
                 FROM conversations c
                 WHERE c.request_state NOT IN ('blocked', 'left') AND c.hidden = 0
                 ORDER BY c.is_pinned DESC,
                          max(COALESCE((SELECT MAX(m.sent_at) FROM messages m
                                        WHERE m.conversation_id = c.id), 0),
                              COALESCE((SELECT MAX(CAST(substr(r.hlc, 1, 13) AS INTEGER)) FROM reactions r JOIN messages m ON m.id = r.message_id
                                        WHERE m.conversation_id = c.id AND r.active = 1 AND m.hidden = 0 AND m.deleted = 0), 0)) DESC,
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
                    r.get::<_, String>(5)?,
                    r.get::<_, bool>(6)?,
                    r.get::<_, Option<String>>(7)?,
                    r.get::<_, bool>(8)?,
                    r.get::<_, bool>(9)?,
                ))
            })
            .map_err(db_err)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(db_err)?;

        let mut summaries = Vec::with_capacity(rows.len());
        for (id, title, is_group, is_pinned, unread, request_state, key_change_pending, group_emoji, verified, marked_unread) in rows {
            let (latest, last_is_reply) = latest_activity(&conn, &id)?;
            // A reaction newer than the last message is the newest thing (no unread, no notification: it only shows in the preview).
            let reaction = message_ops::latest_reaction(&conn, &id, &my_user_id(&conn)).filter(|r| latest.as_ref().is_none_or(|m| r.at > m.sent_at));
            let activity_at = reaction.as_ref().map(|r| r.at).or(latest.as_ref().map(|m| m.sent_at)).unwrap_or(0);
            summaries.push(ConversationSummary {
                activity_at,
                last_reaction: reaction,
                last_message: latest,
                last_is_reply,
                members: members_of(&conn, &id)?,
                id,
                title,
                is_group,
                is_pinned,
                unread,
                request_state,
                key_change_pending,
                group_emoji,
                verified,
                marked_unread,
            });
        }
        Ok(summaries)
    }

    /// A conversation's messages in display order (causal, ties by clock then op id).
    pub fn list_messages(&self, conversation_id: String) -> Result<Vec<MessageItem>, StoreError> {
        let conn = self.lock();
        let me = my_user_id(&conn);
        Ok(order::load_ordered(&conn, &conversation_id)?
            .into_iter()
            .map(|row| item_in(&conn, row, &me))
            .collect())
    }

    /// Starts (or finds) the 1:1 conversation with a person you chose to message: it is yours, so
    /// it is `accepted` and appears in Messages. The name is their profile's display name.
    pub fn start_dm(&self, user_id: String, display_name: String) -> Result<String, StoreError> {
        let mut conn = self.lock();
        let tx = conn.transaction().map_err(db_err)?;
        let id = crate::client::ensure_dm(&tx, &user_id, Some(&display_name))?;
        tx.execute(
            "UPDATE conversations SET request_state = 'accepted' WHERE id = ?1",
            params![id],
        )
        .map_err(db_err)?;
        // A chat you start is implicitly accepting them: they get your delivery key (once), so they can
        // send you sealed messages.
        if !delivery::is_shared(&tx, &user_id)? {
            delivery::queue_share(&tx, &user_id, now_ms())?;
        }
        tx.commit().map_err(db_err)?;
        Ok(id)
    }

    /// Accepts a request: the conversation moves into Messages, and they are sent your delivery key
    /// (so their later messages can be sealed). The key goes out with the next delivery.
    pub fn accept_request(&self, conversation_id: String) -> Result<(), StoreError> {
        self.set_request_state(&conversation_id, "accepted")?;
        if let Some(peer) = conversation_id.strip_prefix("dm:") {
            let conn = self.lock();
            if !delivery::is_shared(&conn, peer)? {
                delivery::queue_share(&conn, peer, now_ms())?;
            }
        }
        Ok(())
    }

    /// Blocks a sender: the conversation is hidden and their new messages are not stored here. If they
    /// had your delivery key, **it is rotated** (a new key; the server learns its hash with the next
    /// delivery) and the new key is queued for every accepted contact except them, so their sealed sends
    /// are refused by the server. Someone who never had the key needs no rotation.
    pub fn block_sender(&self, conversation_id: String) -> Result<(), StoreError> {
        self.set_request_state(&conversation_id, "blocked")?;
        let Some(peer) = conversation_id.strip_prefix("dm:") else { return Ok(()) };
        let conn = self.lock();
        delivery::dequeue_share(&conn, peer)?;
        if delivery::unshare(&conn, peer)? {
            let now = now_ms();
            delivery::rotate(&conn, now)?;
            // The photo key is rotated with it: the person just blocked can no longer open my contacts-only photo
            // (the next delivery re-uploads it under the new key).
            photos::rotate_key(&conn, now)?;
            delivery::forget_all_shared(&conn)?;
            for other in delivery::accepted_peers(&conn)? {
                if other != peer {
                    delivery::queue_share(&conn, &other, now)?;
                }
            }
        }
        Ok(())
    }

    /// How many contacts can be sent to sealed (they shared their delivery key and have not refused it).
    /// For a Debug-only row in About.
    pub fn sealed_contact_count(&self) -> Result<u32, StoreError> {
        let conn = self.lock();
        delivery::sealed_contact_count(&conn)
    }

    /// Accepts the other person's new security key (they signed in on a new phone): their messages
    /// that were held back are read, and messages to them can be sent again.
    pub fn trust_new_key(&self, conversation_id: String) -> Result<(), StoreError> {
        let peer = conversation_id.strip_prefix("dm:").ok_or(StoreError::NotFound)?;
        let conn = self.lock();
        conn.execute(
            "UPDATE peers SET master_key = new_master_key, new_master_key = NULL, verified_at = NULL
             WHERE user_id = ?1 AND new_master_key IS NOT NULL",
            params![peer],
        )
        .map_err(db_err)?;
        conn.execute(
            "UPDATE pending_inbound SET reason = 'new' WHERE sender_user = ?1 AND reason = 'key_mismatch'",
            params![peer],
        )
        .map_err(db_err)?;
        // Their new phone has none of what the old one held: give it my delivery key.
        delivery::queue_share(&conn, peer, now_ms())?;
        Ok(())
    }

    /// Queues a message that was not sent or not delivered to go out again (same message, same place).
    pub fn retry_message(&self, message_id: String) -> Result<(), StoreError> {
        let conn = self.lock();
        conn.execute(
            "UPDATE messages SET local_state = 'sending'
             WHERE id = ?1 AND sender_id = ?2 AND local_state IN ('failed', 'undelivered')",
            params![message_id, ME_ID],
        )
        .map_err(db_err)?;
        Ok(())
    }

    /// The people you blocked, by name.
    pub fn list_blocked(&self) -> Result<Vec<BlockedPerson>, StoreError> {
        let conn = self.lock();
        let mut statement = conn
            .prepare(
                "SELECT c.id, COALESCE(p.name, c.title), COALESCE(p.tone, 0)
                 FROM conversations c LEFT JOIN people p ON 'dm:' || p.id = c.id
                 WHERE c.request_state = 'blocked' ORDER BY c.title, c.id",
            )
            .map_err(db_err)?;
        let rows = statement
            .query_map([], |r| {
                Ok(BlockedPerson {
                    conversation_id: r.get(0)?,
                    name: r.get(1)?,
                    tone: r.get(2)?,
                })
            })
            .map_err(db_err)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(db_err)?;
        Ok(rows)
    }

    /// Unblocks someone: their conversation comes back (what was stored before the block shows
    /// again, and new messages are kept).
    pub fn unblock(&self, conversation_id: String) -> Result<(), StoreError> {
        let conn = self.lock();
        let changed = conn
            .execute(
                "UPDATE conversations SET request_state = 'accepted' WHERE id = ?1 AND request_state = 'blocked'",
                params![conversation_id],
            )
            .map_err(db_err)?;
        if changed == 0 {
            return Err(StoreError::NotFound);
        }
        // They no longer have to be shut out: give them the current key again.
        if let Some(peer) = conversation_id.strip_prefix("dm:") {
            delivery::queue_share(&conn, peer, now_ms())?;
        }
        Ok(())
    }

    /// When this device's keys were made, and a short fingerprint of the account's master key.
    pub fn key_info(&self) -> Result<Option<KeyInfo>, StoreError> {
        let conn = self.lock();
        let Some(state) = account::load_account(&conn, &self.pickle_key)? else {
            return Ok(None);
        };
        let created: Option<i64> = conn
            .query_row("SELECT created_at FROM account WHERE id = 1", [], |r| r.get(0))
            .map_err(db_err)?;
        let fingerprint = crate::keys::fingerprint_of(&state.master_key()).ok_or(StoreError::BadMessage)?;
        Ok(Some(KeyInfo {
            fingerprint,
            created_at: created.unwrap_or(0),
        }))
    }

    /// Pins or unpins a conversation (pinned ones sort first).
    pub fn set_pinned(&self, conversation_id: String, pinned: bool) -> Result<(), StoreError> {
        let conn = self.lock();
        let changed = conn.execute("UPDATE conversations SET is_pinned = ?2 WHERE id = ?1", params![conversation_id, pinned]).map_err(db_err)?;
        if changed == 0 { Err(StoreError::NotFound) } else { Ok(()) }
    }

    /// Marks a conversation unread by hand (or read again); opening it reads it.
    pub fn set_marked_unread(&self, conversation_id: String, unread: bool) -> Result<(), StoreError> {
        let conn = self.lock();
        let changed = conn.execute("UPDATE conversations SET marked_unread = ?2 WHERE id = ?1", params![conversation_id, unread]).map_err(db_err)?;
        if changed == 0 { Err(StoreError::NotFound) } else { Ok(()) }
    }

    /// Deletes a chat for me: its messages and files go from this phone and the chat leaves the list. A new message from the
    /// other person (or one I start) brings it back, empty. Nothing is told to anyone; for a group I am still in, leave it first.
    pub fn delete_chat(&self, conversation_id: String) -> Result<(), StoreError> {
        let mut conn = self.lock();
        let tx = conn.transaction().map_err(db_err)?;
        let exists: bool = tx.query_row("SELECT EXISTS (SELECT 1 FROM conversations WHERE id = ?1)", params![conversation_id], |r| r.get(0)).map_err(db_err)?;
        if !exists {
            return Err(StoreError::NotFound);
        }
        tx.execute(
            "DELETE FROM message_attachments WHERE message_id IN (SELECT id FROM messages WHERE conversation_id = ?1)",
            params![conversation_id],
        )
        .map_err(db_err)?;
        tx.execute("DELETE FROM message_deliveries WHERE message_id IN (SELECT id FROM messages WHERE conversation_id = ?1)", params![conversation_id]).map_err(db_err)?;
        tx.execute("DELETE FROM thread_state WHERE root_id IN (SELECT id FROM messages WHERE conversation_id = ?1)", params![conversation_id]).map_err(db_err)?;
        tx.execute("DELETE FROM messages WHERE conversation_id = ?1 AND id NOT LIKE 'sys:%'", params![conversation_id]).map_err(db_err)?;
        tx.execute("DELETE FROM messages WHERE conversation_id = ?1", params![conversation_id]).map_err(db_err)?;
        tx.execute("UPDATE conversations SET hidden = 1, unread = 0, marked_unread = 0, is_pinned = 0 WHERE id = ?1", params![conversation_id]).map_err(db_err)?;
        tx.commit().map_err(db_err)
    }

    /// Gives a person a private label (at most 30 characters), or removes it with `None` or an empty text. Only on this phone.
    pub fn set_contact_label(&self, user_id: String, label: Option<String>) -> Result<(), StoreError> {
        let conn = self.lock();
        labels::set(&conn, &user_id, label.as_deref())
    }

    /// My private label for a person.
    pub fn contact_label(&self, user_id: String) -> Result<Option<String>, StoreError> {
        let conn = self.lock();
        labels::get(&conn, &user_id)
    }

    /// Marks a conversation as read.
    pub fn mark_read(&self, conversation_id: String) -> Result<(), StoreError> {
        let conn = self.lock();
        conn.execute(
            "UPDATE conversations SET unread = 0, marked_unread = 0 WHERE id = ?1 AND (unread != 0 OR marked_unread != 0)",
            params![conversation_id],
        )
        .map_err(db_err)?;
        Ok(())
    }

    /// Writes a message from this device into the conversation and returns it. It is stored
    /// locally only (`local_state` is `sent_local`).
    pub fn send_local_message(
        &self,
        conversation_id: String,
        text: String,
    ) -> Result<MessageItem, StoreError> {
        let normalised = crate::format::normalise(&text);
        let body = normalised.as_str();
        if body.is_empty() {
            return Err(StoreError::EmptyMessage);
        }
        let plain = crate::format::plain_text(body);
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
            attachments: Vec::new(),
            edited: false,
            deleted: false,
            reactions: Vec::new(),
            forwarded: false,
            link_preview: None,
            thread_root: None,
        };
        conn.execute(
            "INSERT INTO messages (id, conversation_id, sender_id, body, sent_at, local_state, plain)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                item.id,
                item.conversation_id,
                ME_ID,
                item.text,
                item.sent_at,
                item.local_state,
                plain
            ],
        )
        .map_err(db_err)?;
        Ok(item)
    }
}

impl LimeStore {
    fn set_request_state(&self, conversation_id: &str, state: &str) -> Result<(), StoreError> {
        let conn = self.lock();
        let changed = conn
            .execute(
                "UPDATE conversations SET request_state = ?2, unread = CASE WHEN ?2 = 'blocked' THEN 0 ELSE unread END
                 WHERE id = ?1",
                params![conversation_id, state],
            )
            .map_err(db_err)?;
        if changed == 0 {
            return Err(StoreError::NotFound);
        }
        Ok(())
    }

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

        // Nothing, not even a temporary search table, is written to a file outside the encrypted database.
        conn.execute_batch("PRAGMA foreign_keys = ON; PRAGMA temp_store = MEMORY;")
            .map_err(db_err)?;
        migrations::run(&conn)?;
        Ok(Self {
            conn: Mutex::new(conn),
            pickle_key: crate::keys::derive_pickle_key(key),
            protocol_lock: Mutex::new(()),
        })
    }
}

/// This account's user id (empty before registration).
pub(crate) fn my_user_id(conn: &Connection) -> String {
    conn.query_row("SELECT user_id FROM account WHERE id = 1", [], |r| r.get::<_, Option<String>>(0)).ok().flatten().unwrap_or_default()
}

/// A message for the app: a group's system line ("Jean added Lee") is put into words here.
fn item_in(conn: &Connection, row: order::Row, me: &str) -> MessageItem {
    let mut item = item_from_row(row);
    if item.local_state == "system" {
        item.text = groups::render_system(conn, &item.text, me);
    }
    item.attachments = attachment_infos(conn, &item.id);
    item.reactions = message_ops::reactions_for(conn, &item.id, me);
    item.forwarded = link_preview::is_forwarded(conn, &item.id);
    item.link_preview = link_preview::info(conn, &item.id);
    item.thread_root = conn.query_row("SELECT thread_root FROM messages WHERE id = ?1", params![item.id], |r| r.get::<_, Option<String>>(0)).ok().flatten();
    item
}

pub(crate) fn item_from_row(row: order::Row) -> MessageItem {
    MessageItem {
        id: row.id,
        conversation_id: row.conversation_id,
        sender_id: if row.sender_id == ME_ID { None } else { Some(row.sender_id) },
        text: row.body,
        sent_at: row.sent_at,
        local_state: row.local_state,
        attachments: Vec::new(),
        edited: row.edited,
        deleted: row.deleted,
        reactions: Vec::new(),
        forwarded: false,
        link_preview: None,
        thread_root: None,
    }
}

/// What the app shows of a message's attachments.
pub(crate) fn attachment_infos(conn: &Connection, message_id: &str) -> Vec<AttachmentInfo> {
    attachments::for_message(conn, message_id)
        .unwrap_or_default()
        .into_iter()
        .map(|(d, downloaded)| {
            let removed = attachments::is_removed(conn, message_id, &d.id);
            AttachmentInfo {
                id: d.id, mime: d.mime, name: d.name, size: d.size, width: d.width, height: d.height, duration_ms: d.duration_ms,
                thumb: d.thumb, downloaded, removed,
            }
        })
        .collect()
}

/// The newest thing in a conversation: its last message or, if a reply is newer, that reply (and `true`).
fn latest_activity(conn: &Connection, conversation_id: &str) -> Result<(Option<MessageItem>, bool), StoreError> {
    let me = my_user_id(conn);
    let main = order::load_ordered(conn, conversation_id)?.pop();
    let reply = order::latest_reply(conn, conversation_id)?;
    Ok(match (main, reply) {
        (Some(main), Some(reply)) if reply.sent_at > main.sent_at => (Some(item_in(conn, reply, &me)), true),
        (Some(main), _) => (Some(item_in(conn, main, &me)), false),
        (None, Some(reply)) => (Some(item_in(conn, reply, &me)), true),
        (None, None) => (None, false),
    })
}

fn members_of(conn: &Connection, conversation_id: &str) -> Result<Vec<MemberInfo>, StoreError> {
    let mut statement = conn
        .prepare(
            "SELECT p.id, p.name, p.tone, l.label FROM members m JOIN people p ON p.id = m.person_id
             LEFT JOIN contact_labels l ON l.user_id = p.id
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
                label: r.get(3)?,
            })
        })
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    Ok(members)
}
