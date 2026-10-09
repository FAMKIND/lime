//! My private label for a contact (LIME-104), for example "Grade 4 · Lincoln". It lives only in this encrypted store: it is
//! never sent to the server or to the person, and it is searchable on this phone.

use rusqlite::{params, Connection, OptionalExtension};

use super::{db_err, StoreError};

/// The longest a label can be, in characters.
pub(crate) const MAX_CHARS: usize = 30;

pub(crate) fn get(conn: &Connection, user_id: &str) -> Result<Option<String>, StoreError> {
    conn.query_row("SELECT label FROM contact_labels WHERE user_id = ?1", params![user_id], |r| r.get(0)).optional().map_err(db_err)
}

/// Sets, changes or (when empty) removes a label.
pub(crate) fn set(conn: &Connection, user_id: &str, label: Option<&str>) -> Result<(), StoreError> {
    let cleaned: Option<String> = label
        .map(|l| l.split_whitespace().collect::<Vec<_>>().join(" "))
        .filter(|l| !l.is_empty())
        .map(|l| l.chars().filter(|c| !c.is_control()).take(MAX_CHARS).collect());
    match cleaned {
        Some(text) => conn
            .execute(
                "INSERT INTO contact_labels (user_id, label) VALUES (?1, ?2) ON CONFLICT (user_id) DO UPDATE SET label = ?2",
                params![user_id, text],
            )
            .map_err(db_err)?,
        None => conn.execute("DELETE FROM contact_labels WHERE user_id = ?1", params![user_id]).map_err(db_err)?,
    };
    Ok(())
}
