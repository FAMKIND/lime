//! Usernames shared inside the encryption (LIME-184). A phone tells the people it shares a chat with its own username as a small encrypted control op
//! (`profile.username`), the way a status travels: only to accepted contacts and to the people in its groups, never as a message, and the server
//! carries ciphertext only, so it learns nothing new and is never asked about anyone. `null` (also what "Hide me from search" sends) makes a receiver
//! forget it. A phone keeps the newest one per sender (by the sender's clock) and ignores it from anyone it shares no chat with.

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{json, Value};

use super::{db_err, LimeStore, StoreError};

pub(crate) const USERNAME_SET: &str = "profile.username";

/// A username as shared: 1 to 64 visible characters, no white space.
pub(crate) fn valid(username: &str) -> bool {
    !username.is_empty() && username.chars().count() <= 64 && !username.chars().any(|c| c.is_whitespace() || c.is_control())
}

pub(crate) fn payload(username: Option<&str>) -> Value {
    json!({ "username": username })
}

/// What a received payload says: `Some(None)` is "forget it", `Some(Some(name))` a username, `None` a payload to ignore.
pub(crate) fn parse(payload: &Value) -> Option<Option<String>> {
    match payload.get("username")? {
        Value::Null => Some(None),
        Value::String(name) if valid(name) => Some(Some(name.clone())),
        _ => None,
    }
}

fn mine(conn: &Connection) -> Result<(Option<String>, i64), StoreError> {
    let row = conn
        .query_row("SELECT username, version FROM my_username WHERE id = 1", [], |r| Ok((r.get::<_, Option<String>>(0)?, r.get::<_, i64>(1)?)))
        .optional()
        .map_err(db_err)?;
    Ok(row.unwrap_or((None, 0)))
}

/// Sets what I share (`None` to share nothing). Changing it makes everyone I share a chat with due a new notice; the same value again does not.
pub(crate) fn set_mine(conn: &Connection, username: Option<&str>) -> Result<(), StoreError> {
    let username = username.map(str::trim).filter(|u| valid(u));
    let (current, version) = mine(conn)?;
    if current.as_deref() == username {
        return Ok(());
    }
    conn.execute(
        "INSERT INTO my_username (id, username, version) VALUES (1, ?1, ?2)
         ON CONFLICT (id) DO UPDATE SET username = ?1, version = ?2",
        params![username, version + 1],
    )
    .map_err(db_err)?;
    Ok(())
}

/// Who I share a chat with: accepted contacts, and everyone in a group I am in.
fn recipients(conn: &Connection, me: &str) -> Result<Vec<String>, StoreError> {
    let mut people = super::delivery::accepted_peers(conn)?;
    let mut statement = conn
        .prepare("SELECT DISTINCT user_id FROM group_members WHERE user_id != ?1 AND group_id IN (SELECT group_id FROM group_members WHERE user_id = ?1)")
        .map_err(db_err)?;
    let members = statement.query_map(params![me], |r| r.get::<_, String>(0)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    people.extend(members);
    people.retain(|p| p != me);
    people.sort();
    people.dedup();
    Ok(people)
}

/// The people who are due a notice of what I share now, with the version that notice carries. Someone who was never told anything is not told
/// "nothing" (there is nothing for them to forget): they are only marked as up to date.
pub(crate) fn due(conn: &Connection, me: &str) -> Result<(Option<String>, i64, Vec<String>), StoreError> {
    let (username, version) = mine(conn)?;
    if version == 0 {
        return Ok((None, 0, Vec::new()));
    }
    let mut due = Vec::new();
    for peer in recipients(conn, me)? {
        let sent: Option<i64> = conn.query_row("SELECT version FROM username_sent WHERE peer_user_id = ?1", params![peer], |r| r.get(0)).optional().map_err(db_err)?;
        if sent.is_some_and(|v| v >= version) {
            continue;
        }
        if username.is_none() && sent.is_none() {
            mark_sent(conn, &peer, version)?;
        } else {
            due.push(peer);
        }
    }
    Ok((username, version, due))
}

pub(crate) fn mark_sent(conn: &Connection, peer: &str, version: i64) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO username_sent (peer_user_id, version) VALUES (?1, ?2) ON CONFLICT (peer_user_id) DO UPDATE SET version = ?2",
        params![peer, version],
    )
    .map_err(db_err)?;
    Ok(())
}

/// Whether I share a chat with `user`: an accepted contact, or a member of a group I am in.
pub(crate) fn shares_a_chat(conn: &Connection, me: &str, user: &str) -> Result<bool, StoreError> {
    let contact: bool = conn
        .query_row("SELECT COALESCE((SELECT request_state = 'accepted' FROM conversations WHERE id = ?1), 0)", params![format!("dm:{user}")], |r| r.get(0))
        .map_err(db_err)?;
    if contact {
        return Ok(true);
    }
    conn.query_row(
        "SELECT EXISTS (SELECT 1 FROM group_members a JOIN group_members b ON a.group_id = b.group_id WHERE a.user_id = ?1 AND b.user_id = ?2)",
        params![user, me],
        |r| r.get(0),
    )
    .map_err(db_err)
}

/// Keeps what a person told me, if it is newer than what I hold and I share a chat with them.
pub(crate) fn store_received(conn: &Connection, me: &str, sender: &str, username: Option<&str>, sent_at: i64) -> Result<(), StoreError> {
    if !shares_a_chat(conn, me, sender)? {
        return Ok(());
    }
    super::groups::ensure_person(conn, sender)?;
    conn.execute("UPDATE people SET username = ?2, username_at = ?3 WHERE id = ?1 AND username_at <= ?3", params![sender, username, sent_at]).map_err(db_err)?;
    Ok(())
}

/// A person's username as this phone was told, if any.
pub(crate) fn of(conn: &Connection, user: &str) -> Option<String> {
    conn.query_row("SELECT username FROM people WHERE id = ?1", params![user], |r| r.get::<_, Option<String>>(0)).ok().flatten()
}

#[uniffi::export]
impl LimeStore {
    /// Sets the username this phone shares with the people it chats with (`None`: share none; also what "Hide me from search" means). The app calls
    /// this whenever the account's username or that choice may have changed; the same value again tells nobody twice.
    pub fn set_my_shared_username(&self, username: Option<String>) -> Result<(), StoreError> {
        set_mine(&self.lock(), username.as_deref())
    }

    /// The username a person told this phone (inside the encryption), if they did and have not hidden it.
    pub fn shared_username(&self, user_id: String) -> Option<String> {
        of(&self.lock(), &user_id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_username_is_one_visible_word_and_null_is_forget() {
        assert!(valid("jean.c") && valid("j_c-1"));
        assert!(!valid("") && !valid("two words") && !valid("tab\t") && !valid(&"x".repeat(65)));
        assert_eq!(parse(&payload(Some("jean.c"))), Some(Some("jean.c".into())));
        assert_eq!(parse(&payload(None)), Some(None));
        assert_eq!(parse(&json!({})), None);
        assert_eq!(parse(&json!({ "username": 5 })), None);
        assert_eq!(parse(&json!({ "username": "has space" })), None);
    }

    #[test]
    fn the_same_value_is_not_news_and_a_change_is() {
        let conn = Connection::open_in_memory().unwrap();
        crate::store::migrations::run(&conn).unwrap();
        set_mine(&conn, None).unwrap();
        assert_eq!(mine(&conn).unwrap().1, 0, "nothing set, nothing to say");
        set_mine(&conn, Some("jean.c")).unwrap();
        set_mine(&conn, Some("jean.c")).unwrap();
        assert_eq!(mine(&conn).unwrap(), (Some("jean.c".into()), 1));
        set_mine(&conn, Some("jean.d")).unwrap();
        assert_eq!(mine(&conn).unwrap().1, 2);
        set_mine(&conn, None).unwrap();
        assert_eq!(mine(&conn).unwrap(), (None, 3), "hiding is a change too");
        set_mine(&conn, Some("has space")).unwrap();
        assert_eq!(mine(&conn).unwrap().1, 3, "an invalid username counts as none");
    }
}
