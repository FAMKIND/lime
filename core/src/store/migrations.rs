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
