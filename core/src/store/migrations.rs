//! Forward-only schema migrations, versioned with `PRAGMA user_version`.
//! Never edit a released migration; append a new one.

use rusqlite::Connection;

use super::StoreError;

const MIGRATIONS: &[&str] = &[
    // 1: the local view.
    "CREATE TABLE people (
         id   TEXT PRIMARY KEY NOT NULL,
         name TEXT NOT NULL,
         tone INTEGER NOT NULL
     );
     CREATE TABLE conversations (
         id        TEXT PRIMARY KEY NOT NULL,
         title     TEXT NOT NULL,
         is_group  INTEGER NOT NULL,
         is_pinned INTEGER NOT NULL DEFAULT 0,
         unread    INTEGER NOT NULL DEFAULT 0
     );
     CREATE TABLE members (
         conversation_id TEXT NOT NULL REFERENCES conversations(id),
         person_id       TEXT NOT NULL REFERENCES people(id),
         position        INTEGER NOT NULL,
         PRIMARY KEY (conversation_id, person_id)
     );
     CREATE TABLE messages (
         id              TEXT PRIMARY KEY NOT NULL,
         conversation_id TEXT NOT NULL REFERENCES conversations(id),
         sender_id       TEXT NOT NULL REFERENCES people(id),
         body            TEXT NOT NULL,
         sent_at         INTEGER NOT NULL,
         local_state     TEXT NOT NULL
     );
     CREATE INDEX messages_by_conversation ON messages (conversation_id, sent_at);",
    // 2: the protocol state (LIME-93): this device's keys, its Olm sessions, pinned master keys,
    // and the op id and hybrid logical clock of messages that came through the protocol.
    "CREATE TABLE account (
         id            INTEGER PRIMARY KEY CHECK (id = 1),
         olm_pickle    TEXT NOT NULL,      -- vodozemac pickle, encrypted with a key derived from the store key
         master_secret TEXT NOT NULL,      -- the master signing key (base64), inside the encrypted database
         device_id     TEXT NOT NULL,
         user_id       TEXT,
         registered    INTEGER NOT NULL DEFAULT 0,
         hlc_wall      INTEGER NOT NULL DEFAULT 0,
         hlc_counter   INTEGER NOT NULL DEFAULT 0
     );
     CREATE TABLE olm_sessions (
         peer_user_id      TEXT NOT NULL,
         peer_device_id    TEXT NOT NULL,
         peer_identity_key TEXT NOT NULL,
         session_pickle    TEXT NOT NULL,  -- vodozemac pickle, encrypted as above
         created_at        INTEGER NOT NULL,
         updated_at        INTEGER NOT NULL,
         PRIMARY KEY (peer_user_id, peer_identity_key)
     );
     CREATE TABLE peers (
         user_id    TEXT PRIMARY KEY NOT NULL,
         master_key TEXT NOT NULL          -- trust on first use
     );
     ALTER TABLE messages ADD COLUMN op_id TEXT;
     ALTER TABLE messages ADD COLUMN hlc TEXT;
     CREATE UNIQUE INDEX messages_by_op_id ON messages (op_id) WHERE op_id IS NOT NULL;",
    // 3: every fetched mailbox item is kept here BEFORE it is acknowledged, and removed only once it
    // has been turned into a message. Nothing the server delivered is ever dropped silently.
    "CREATE TABLE pending_inbound (
         id           INTEGER PRIMARY KEY AUTOINCREMENT,
         cursor       INTEGER NOT NULL UNIQUE,   -- the server's cursor for this device's mailbox
         sender_user  TEXT,                      -- only for an identified item
         identified   INTEGER NOT NULL,
         ciphertext   TEXT NOT NULL,             -- base64, exactly as fetched
         received_at  TEXT,
         reason       TEXT NOT NULL,             -- new, no_session, decrypt_failed, sealed_unsupported, invalid, key_mismatch
         attempts     INTEGER NOT NULL DEFAULT 0,
         first_seen   INTEGER NOT NULL,
         last_attempt INTEGER
     );",
    // 4: message requests and causal ordering (LIME-95). A conversation is `pending` (a stranger's
    // first message: it waits in Requests), `accepted`, or `blocked` (hidden; its new messages are
    // not stored). `parents` is the JSON list of op ids the sender had seen (api-v2.md section 5).
    "ALTER TABLE conversations ADD COLUMN request_state TEXT NOT NULL DEFAULT 'accepted';
     ALTER TABLE messages ADD COLUMN parents TEXT;",
    // 5: key changes and delivery notices (LIME-95-fix). `new_master_key` is a different master key
    // a person has been seen with since we pinned theirs: nothing from or to them moves until the
    // person accepts it. `message_deliveries` remembers the hash of each ciphertext we sent, so a
    // later \"not delivered\" notice from the server can be matched to the message.
    "ALTER TABLE peers ADD COLUMN new_master_key TEXT;
     -- An item held back for a changed key was already decrypted (a message cannot be decrypted
     -- twice), so its plaintext waits here, inside the encrypted database, until the key is accepted.
     ALTER TABLE pending_inbound ADD COLUMN plaintext BLOB;
     ALTER TABLE pending_inbound ADD COLUMN peer_identity TEXT;
     CREATE TABLE message_deliveries (
         hash       TEXT PRIMARY KEY NOT NULL,   -- hex SHA-256 of the outer ciphertext, as the server hashes it
         message_id TEXT NOT NULL
     );
     CREATE INDEX message_deliveries_by_message ON message_deliveries (message_id);",
    // 6: when this device's keys were made (Settings shows it). An account made before this version
    // gets the day it was upgraded: the exact earlier time was never recorded.
    "ALTER TABLE account ADD COLUMN created_at INTEGER;
     UPDATE account SET created_at = CAST(strftime('%s', 'now') AS INTEGER) * 1000;",
    // 7: on-device search (LIME-99). An FTS5 index over message text, inside this encrypted database
    // (so it is encrypted at rest like everything else), kept in step by triggers on insert, edit and
    // delete, and filled from the messages already here. unicode61 with remove_diacritics makes it
    // case- and diacritic-insensitive. The text is stored twice (here and in `messages`): a few
    // kilobytes per hundred messages, for a search that never leaves the phone.
    "CREATE VIRTUAL TABLE message_fts USING fts5(
         body,
         message_id UNINDEXED,
         conversation_id UNINDEXED,
         tokenize = 'unicode61 remove_diacritics 2'
     );
     INSERT INTO message_fts (body, message_id, conversation_id) SELECT body, id, conversation_id FROM messages;
     CREATE TRIGGER messages_fts_insert AFTER INSERT ON messages BEGIN
         INSERT INTO message_fts (body, message_id, conversation_id) VALUES (new.body, new.id, new.conversation_id);
     END;
     CREATE TRIGGER messages_fts_delete AFTER DELETE ON messages BEGIN
         DELETE FROM message_fts WHERE message_id = old.id;
     END;
     CREATE TRIGGER messages_fts_update AFTER UPDATE OF body, conversation_id ON messages BEGIN
         UPDATE message_fts SET body = new.body, conversation_id = new.conversation_id WHERE message_id = old.id;
     END;",
    // 8: formatted messages (LIME-100). `body` is the message as Markdown (what is shown and sent);
    // `plain` is the same words without the markup, which is what search indexes and previews show.
    // Messages from before have no `plain` and are indexed by their `body`, which was plain text.
    "ALTER TABLE messages ADD COLUMN plain TEXT;
     DROP TRIGGER messages_fts_insert;
     DROP TRIGGER messages_fts_update;
     CREATE TRIGGER messages_fts_insert AFTER INSERT ON messages BEGIN
         INSERT INTO message_fts (body, message_id, conversation_id) VALUES (COALESCE(new.plain, new.body), new.id, new.conversation_id);
     END;
     CREATE TRIGGER messages_fts_update AFTER UPDATE OF body, plain, conversation_id ON messages BEGIN
         UPDATE message_fts SET body = COALESCE(new.plain, new.body), conversation_id = new.conversation_id WHERE message_id = old.id;
     END;",
    // 9: reply threads (LIME-101). A reply carries `thread_root`, the id of the message it answers
    // (never itself a reply: replying to a reply answers the same root). Replies are kept out of the
    // main timeline. `thread_state` counts the replies in each thread not yet read.
    "ALTER TABLE messages ADD COLUMN thread_root TEXT;
     CREATE INDEX messages_by_thread ON messages (thread_root) WHERE thread_root IS NOT NULL;
     CREATE TABLE thread_state (
         root_id TEXT PRIMARY KEY NOT NULL,
         unread  INTEGER NOT NULL DEFAULT 0
     );",
    // 10: sealed sender (LIME-96). `delivery_state` is this account's own delivery key (kept inside the
    // encrypted database) and whether its hash is on the server; `contact_delivery_keys` are the keys
    // people shared with us (`denied`: a sealed send to them was refused, so none is tried until they
    // share a new key); `share_queue` is who still has to be sent my current key; `key_shared` is who
    // already has it. A message refused sealed becomes \"Not delivered\" (`sealed_denied`), and one tap
    // on it sends it identified once (`identified_once`).
    "CREATE TABLE delivery_state (
         id         INTEGER PRIMARY KEY CHECK (id = 1),
         key        TEXT NOT NULL,
         uploaded   INTEGER NOT NULL DEFAULT 0,
         rotated_at INTEGER NOT NULL
     );
     CREATE TABLE contact_delivery_keys (
         user_id     TEXT PRIMARY KEY NOT NULL,
         key         TEXT NOT NULL,
         denied      INTEGER NOT NULL DEFAULT 0,
         received_at INTEGER NOT NULL
     );
     CREATE TABLE share_queue (
         peer_user_id TEXT PRIMARY KEY NOT NULL,
         queued_at    INTEGER NOT NULL
     );
     CREATE TABLE key_shared (
         peer_user_id TEXT PRIMARY KEY NOT NULL,
         shared_at    INTEGER NOT NULL
     );
     ALTER TABLE messages ADD COLUMN sealed_denied INTEGER NOT NULL DEFAULT 0;
     ALTER TABLE messages ADD COLUMN identified_once INTEGER NOT NULL DEFAULT 0;
     -- Chats that were accepted before this version have not been given my delivery key: queue them all.
     INSERT OR IGNORE INTO share_queue (peer_user_id, queued_at)
         SELECT substr(id, 4), 0 FROM conversations WHERE id LIKE 'dm:%' AND request_state = 'accepted';",
    // 11: LIME-96-fix. A sealed send the server refuses is now sent identified at once, silently (and shows
    // \"Sent\"), so the two columns migration 10 added for a one-tap resend are not needed.
    "ALTER TABLE messages DROP COLUMN sealed_denied;
     ALTER TABLE messages DROP COLUMN identified_once;",
    // 12: group chats (LIME-97). `group_ops` is the log of signed group state ops (with the whole signed envelope,
    // so the log can be handed to someone newly added); a group's members, name and roles are worked out by
    // replaying it. `group_members` is that result, kept for quick reads. `group_outbox` is what still has to be
    // sent to each person. A group message is encrypted with a Megolm session: one outbound session per group
    // for this device (`group_outbound_sessions`, with who already has its key), and the inbound sessions other
    // members' devices shared with us (`group_inbound_sessions`, each tied to the device that made it).
    "CREATE TABLE group_ops (
         op_id       TEXT PRIMARY KEY NOT NULL,
         group_id    TEXT NOT NULL,
         op_type     TEXT NOT NULL,
         sender_user TEXT NOT NULL,
         hlc         TEXT NOT NULL,
         parents     TEXT NOT NULL,
         payload     TEXT NOT NULL,
         inner       TEXT NOT NULL,
         received_at INTEGER NOT NULL
     );
     CREATE INDEX group_ops_by_group ON group_ops (group_id);
     CREATE TABLE group_members (
         group_id TEXT NOT NULL,
         user_id  TEXT NOT NULL,
         role     TEXT NOT NULL,
         seq      INTEGER NOT NULL,
         PRIMARY KEY (group_id, user_id)
     );
     CREATE TABLE group_outbox (
         id             INTEGER PRIMARY KEY AUTOINCREMENT,
         group_id       TEXT NOT NULL,
         recipient_user TEXT NOT NULL,
         op_json        TEXT NOT NULL
     );
     CREATE TABLE group_outbound_sessions (
         group_id    TEXT PRIMARY KEY NOT NULL,
         pickle      TEXT NOT NULL,
         session_id  TEXT NOT NULL,
         created_at  INTEGER NOT NULL,
         messages    INTEGER NOT NULL DEFAULT 0,
         fingerprint TEXT NOT NULL,
         rotate      INTEGER NOT NULL DEFAULT 0,
         shared_with TEXT NOT NULL DEFAULT '[]'
     );
     CREATE TABLE group_inbound_sessions (
         session_id   TEXT PRIMARY KEY NOT NULL,
         group_id     TEXT NOT NULL,
         owner_user   TEXT NOT NULL,
         owner_device TEXT NOT NULL,
         pickle       TEXT NOT NULL
     );
     ALTER TABLE conversations ADD COLUMN group_emoji TEXT;",
];

/// The schema version this build writes.
pub(crate) const LATEST: u32 = MIGRATIONS.len() as u32;

pub(crate) fn run(conn: &Connection) -> Result<(), StoreError> {
    let current: u32 = conn
        .query_row("PRAGMA user_version", [], |r| r.get(0))
        .map_err(|_| StoreError::Migration)?;
    if current > LATEST {
        // Written by a newer Lime: never downgrade or guess.
        return Err(StoreError::Migration);
    }
    for (index, sql) in MIGRATIONS.iter().enumerate().skip(current as usize) {
        let version = index as u32 + 1;
        conn.execute_batch(&format!(
            "BEGIN; {sql} PRAGMA user_version = {version}; COMMIT;"
        ))
        .map_err(|_| {
            let _ = conn.execute_batch("ROLLBACK;");
            StoreError::Migration
        })?;
    }
    Ok(())
}
