//! Status (LIME-108): Available, Away or Do not disturb, shared only with accepted contacts as a small encrypted control op
//! (`status.changed`). There is no live presence and no "last seen", and the server never learns a status: a phone only
//! remembers what each contact last told it, and works out what is true now from the `until` times they sent.

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{json, Value};

use super::{db_err, LimeStore, StoreError};

pub(crate) const STATUS_CHANGED: &str = "status.changed";

const STATES: [&str; 3] = ["available", "away", "dnd"];

/// A status and when it ends, with what follows it (so a schedule such as work hours keeps working while the phone is off).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct StatusInfo {
    pub state: String,
    /// Milliseconds since the Unix epoch when it ends; `None` means until changed.
    pub until: Option<i64>,
    pub then_state: Option<String>,
    pub then_until: Option<i64>,
}

/// What a contact's phone shows for them right now.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ContactStatus {
    pub user_id: String,
    pub state: String,
    /// When this period ends (milliseconds), if it does: "Quiet hours until 7:00".
    pub until: Option<i64>,
}

fn valid(state: &str) -> bool {
    STATES.contains(&state)
}

/// The state that is true at `now` and when it ends: the first period, else the one after it, else nothing (unknown).
pub fn effective_period(status: &StatusInfo, now: i64) -> Option<(String, Option<i64>)> {
    if status.until.is_none_or(|u| now < u) {
        return Some((status.state.clone(), status.until));
    }
    match (&status.then_state, status.then_until) {
        (Some(state), until) if until.is_none_or(|u| now < u) => Some((state.clone(), until)),
        _ => None,
    }
}

/// Just the state (see [`effective_period`]).
#[cfg(test)]
fn effective(status: &StatusInfo, now: i64) -> Option<String> {
    effective_period(status, now).map(|(state, _)| state)
}

fn payload(status: &StatusInfo) -> Value {
    let mut value = json!({ "state": status.state });
    if let Some(until) = status.until { value["until"] = json!(until); }
    if let (Some(state), until) = (&status.then_state, status.then_until) {
        value["then"] = json!({ "state": state });
        if let Some(until) = until { value["then"]["until"] = json!(until); }
    }
    value
}

pub(crate) fn parse(payload: &Value) -> Option<StatusInfo> {
    let state = payload.get("state").and_then(Value::as_str).filter(|s| valid(s))?.to_owned();
    let until = payload.get("until").and_then(Value::as_i64);
    let then = payload.get("then");
    let then_state = then.and_then(|t| t.get("state")).and_then(Value::as_str).filter(|s| valid(s)).map(str::to_owned);
    let then_until = then.and_then(|t| t.get("until")).and_then(Value::as_i64);
    Some(StatusInfo { state, until, then_state, then_until })
}

fn read_row(r: &rusqlite::Row<'_>) -> rusqlite::Result<StatusInfo> {
    Ok(StatusInfo { state: r.get(0)?, until: r.get(1)?, then_state: r.get(2)?, then_until: r.get(3)? })
}

pub(crate) fn mine(conn: &Connection) -> Option<StatusInfo> {
    conn.query_row("SELECT state, until, then_state, then_until FROM my_status WHERE id = 1", [], read_row).optional().ok().flatten()
}

/// Keeps a contact's status, if it is newer than the one held.
pub(crate) fn store_contact(conn: &Connection, user: &str, status: &StatusInfo, sent_at: i64) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO contact_status (user_id, state, until, then_state, then_until, sent_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
         ON CONFLICT (user_id) DO UPDATE SET state = ?2, until = ?3, then_state = ?4, then_until = ?5, sent_at = ?6 WHERE ?6 >= sent_at",
        params![user, status.state, status.until, status.then_state, status.then_until, sent_at],
    )
    .map_err(db_err)?;
    Ok(())
}

pub(crate) fn queue_notices(conn: &Connection, peers: &[String], now: i64) -> Result<(), StoreError> {
    for peer in peers {
        conn.execute("INSERT OR IGNORE INTO status_notices (peer_user_id, queued_at) VALUES (?1, ?2)", params![peer, now]).map_err(db_err)?;
    }
    Ok(())
}

pub(crate) fn queued(conn: &Connection) -> Result<Vec<String>, StoreError> {
    let mut statement = conn.prepare("SELECT peer_user_id FROM status_notices ORDER BY queued_at, peer_user_id").map_err(db_err)?;
    let rows = statement.query_map([], |r| r.get::<_, String>(0)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(rows)
}

pub(crate) fn dequeue(conn: &Connection, peer: &str) -> Result<(), StoreError> {
    conn.execute("DELETE FROM status_notices WHERE peer_user_id = ?1", params![peer]).map_err(db_err)?;
    Ok(())
}

pub(crate) fn current_payload(conn: &Connection) -> Option<Value> {
    mine(conn).map(|s| payload(&s))
}

#[uniffi::export]
impl LimeStore {
    /// Sets my status and tells every accepted contact (and only them). Setting the same status again tells nobody twice.
    pub fn set_my_status(&self, status: StatusInfo) -> Result<(), StoreError> {
        if !valid(&status.state) || status.then_state.as_deref().is_some_and(|s| !valid(s)) {
            return Err(StoreError::Rejected);
        }
        let conn = self.lock();
        if mine(&conn).as_ref() == Some(&status) {
            return Ok(());
        }
        let now = super::now_ms();
        conn.execute(
            "INSERT INTO my_status (id, state, until, then_state, then_until, updated_at) VALUES (1, ?1, ?2, ?3, ?4, ?5)
             ON CONFLICT (id) DO UPDATE SET state = ?1, until = ?2, then_state = ?3, then_until = ?4, updated_at = ?5",
            params![status.state, status.until, status.then_state, status.then_until, now],
        )
        .map_err(db_err)?;
        let peers = super::delivery::accepted_peers(&conn)?;
        queue_notices(&conn, &peers, now)
    }

    /// The status I last set, if any.
    pub fn my_status(&self) -> Result<Option<StatusInfo>, StoreError> {
        Ok(mine(&self.lock()))
    }

    /// What each contact's status is at `now_ms` (a contact with none, or whose has ended, is left out: no badge for "unknown").
    pub fn contact_statuses(&self, now_ms: i64) -> Result<Vec<ContactStatus>, StoreError> {
        let conn = self.lock();
        let mut statement = conn.prepare("SELECT user_id, state, until, then_state, then_until FROM contact_status ORDER BY user_id").map_err(db_err)?;
        let rows = statement
            .query_map([], |r| Ok((r.get::<_, String>(0)?, StatusInfo { state: r.get(1)?, until: r.get(2)?, then_state: r.get(3)?, then_until: r.get(4)? })))
            .map_err(db_err)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(db_err)?;
        Ok(rows.into_iter().filter_map(|(user_id, s)| effective_period(&s, now_ms).map(|(state, until)| ContactStatus { user_id, state, until })).collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn status(state: &str, until: Option<i64>) -> StatusInfo {
        StatusInfo { state: state.into(), until, then_state: None, then_until: None }
    }

    #[test]
    fn a_status_holds_until_it_ends_then_the_next_one_then_nothing() {
        let quiet = StatusInfo { state: "dnd".into(), until: Some(100), then_state: Some("available".into()), then_until: Some(200) };
        assert_eq!(effective(&quiet, 50).as_deref(), Some("dnd"));
        assert_eq!(effective(&quiet, 100).as_deref(), Some("available"), "the next period starts when the first ends");
        assert_eq!(effective(&quiet, 199).as_deref(), Some("available"));
        assert_eq!(effective(&quiet, 200), None, "ended, and nothing follows: unknown, so no badge");
        assert_eq!(effective(&status("away", None), i64::MAX).as_deref(), Some("away"), "until changed");
    }

    #[test]
    fn only_the_three_states_are_accepted_and_they_survive_a_round_trip() {
        assert!(parse(&json!({ "state": "busy" })).is_none());
        assert!(parse(&json!({})).is_none());
        let s = StatusInfo { state: "dnd".into(), until: Some(5), then_state: Some("away".into()), then_until: None };
        assert_eq!(parse(&payload(&s)), Some(s));
    }
}
