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
