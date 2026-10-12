//! Call signalling (LIME-111): `call.offer`, `call.answer`, `call.ice`, `call.end`, `call.busy` and `call.decline` are small
//! encrypted, signed control ops between two accepted contacts, sent like any other op (sealed where possible). They are not
//! messages: nothing is shown or stored beyond a short queue for the app to take. The media itself (WebRTC, DTLS-SRTP) goes
//! directly between the phones or through the TURN relay as ciphertext; the server never learns that a call happened beyond
//! normal mailbox traffic.
//!
//! An offer or answer carries the DTLS **fingerprint** of the sender's media key next to the SDP that contains it; both are inside
//! the signed op, so a relay or an attacker in the middle cannot swap the key. A phone refuses an op whose fingerprint field is not the
//! one in its SDP.

use rusqlite::{params, Connection};
use serde_json::Value;

use super::{db_err, LimeStore, StoreError};

pub(crate) const OPS: [&str; 8] = ["call.offer", "call.answer", "call.ice", "call.end", "call.busy", "call.decline", "call.ringing", "call.unavailable"];

/// An offer older than this is not rung.
pub(crate) const OFFER_MAX_AGE_MS: i64 = 90_000;
const KEEP: i64 = 200;

pub(crate) fn is_call_op(op_type: &str) -> bool {
    OPS.contains(&op_type)
}

/// The fingerprint line of an SDP (`a=fingerprint:sha-256 AB:CD:...`), normalised to upper-case hex pairs.
pub(crate) fn sdp_fingerprint(sdp: &str) -> Option<String> {
    sdp.lines().find_map(|line| {
        let rest = line.trim().strip_prefix("a=fingerprint:")?;
        let (_, value) = rest.split_once(' ')?;
        Some(normalise(value))
    })
}

fn normalise(fingerprint: &str) -> String {
    fingerprint.trim().to_ascii_uppercase()
}

/// Whether a call op is well formed. An offer or answer must carry an SDP whose fingerprint is the one named in the op.
pub(crate) fn validate(op_type: &str, payload: &Value) -> Option<String> {
    let call_id = payload.get("call_id").and_then(Value::as_str).filter(|id| !id.is_empty() && id.len() <= 64 && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-'))?;
    match op_type {
        "call.offer" | "call.answer" => {
            let sdp = payload.get("sdp").and_then(Value::as_str).filter(|s| !s.is_empty() && s.len() <= 30_000)?;
            let claimed = payload.get("fingerprint").and_then(Value::as_str).map(normalise)?;
            (sdp_fingerprint(sdp).as_deref() == Some(claimed.as_str())).then_some(())?;
        }
        "call.ice" => {
            // One candidate (`candidate`) or a batch (`candidates`: a list of `{candidate, sdpMid, sdpMLineIndex}`).
            let single = payload.get("candidate").and_then(Value::as_str).is_some_and(|c| c.len() <= 2_000);
            let batch = payload.get("candidates").and_then(Value::as_array).is_some_and(|list| {
                !list.is_empty() && list.len() <= 64 && list.iter().all(|c| c.get("candidate").and_then(Value::as_str).is_some_and(|c| c.len() <= 2_000))
            });
            (single || batch).then_some(())?;
        }
        // The callee will not ring (Do Not Disturb or outside work hours) and says which (LIME-128).
        "call.unavailable" => {
            payload.get("reason").and_then(Value::as_str).filter(|r| matches!(*r, "dnd" | "work_hours"))?;
        }
        _ => {}
    }
    Some(call_id.to_owned())
}

pub(crate) fn push(conn: &Connection, peer: &str, op_type: &str, call_id: &str, payload: &Value, now: i64) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO call_events (peer, op, call_id, payload, at) VALUES (?1, ?2, ?3, ?4, ?5)",
        params![peer, op_type, call_id, payload.to_string(), now],
    )
    .map_err(db_err)?;
    conn.execute("DELETE FROM call_events WHERE id <= (SELECT COALESCE(MAX(id), 0) FROM call_events) - ?1", params![KEEP]).map_err(db_err)?;
    Ok(())
}

/// One incoming call op, for the app.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct CallEvent {
    pub peer: String,
    /// `call.offer`, `call.answer`, `call.ice`, `call.end`, `call.busy`, `call.decline`, `call.ringing` (the callee's phone is ringing) or `call.unavailable` (the callee is in Do Not Disturb or outside work hours: `reason` is `dnd` or `work_hours`).
    pub op: String,
    pub call_id: String,
    /// The op's payload as JSON (the SDP, the candidate...).
    pub payload: String,
}

#[uniffi::export]
impl LimeStore {
    /// The call ops that have arrived since the last call to this, oldest first; they are removed as they are returned.
    pub fn take_call_events(&self) -> Result<Vec<CallEvent>, StoreError> {
        let conn = self.lock();
        let mut statement = conn.prepare("SELECT id, peer, op, call_id, payload FROM call_events ORDER BY id").map_err(db_err)?;
        let rows = statement
            .query_map([], |r| Ok((r.get::<_, i64>(0)?, CallEvent { peer: r.get(1)?, op: r.get(2)?, call_id: r.get(3)?, payload: r.get(4)? })))
            .map_err(db_err)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(db_err)?;
        drop(statement);
        if let Some((last, _)) = rows.last() {
            conn.execute("DELETE FROM call_events WHERE id <= ?1", params![last]).map_err(db_err)?;
        }
        Ok(rows.into_iter().map(|(_, e)| e).collect())
    }
}

/// One call on this phone, as the Calls tab lists it (LIME-116b).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct CallHistoryRecord {
    pub id: String,
    pub peer: String,
    pub peer_name: String,
    pub video: bool,
    pub outgoing: bool,
    pub at_ms: i64,
    pub duration_ms: i64,
    /// `completed`, `missed`, `missed_dnd`, `missed_hours`, `declined`, `noAnswer`, `busy`, `unavailable` or `failed`.
    pub outcome: String,
}

/// The most calls kept.
const HISTORY_KEEP: i64 = 500;

/// The id of the chat message a call becomes: the same on both phones, because both have the call's id.
pub(crate) fn call_message_id(call_id: &str) -> String {
    format!("call:{call_id}")
}

/// A call as a message in the DM (LIME-123): a local message with the id `call:<call_id>`, sent by the caller. It is made on each phone
/// from the call itself and **never sent**, so reactions and replies (ordinary ops that name a message id) work on it unchanged.
/// Idempotent: the first record wins and later ones leave it (and its reactions, replies and "deleted for me") alone.
#[allow(clippy::too_many_arguments)]
pub(crate) fn insert_call_message(conn: &Connection, call_id: &str, peer: &str, video: bool, outgoing: bool, at_ms: i64, duration_ms: i64, outcome: &str) -> Result<(), StoreError> {
    let conversation = format!("dm:{peer}");
    let exists: bool = conn.query_row("SELECT EXISTS(SELECT 1 FROM conversations WHERE id = ?1)", params![conversation], |r| r.get(0)).map_err(db_err)?;
    if !exists {
        return Ok(());
    }
    let body = serde_json::json!({ "video": video, "duration_ms": duration_ms, "outcome": outcome, "outgoing": outgoing }).to_string();
    conn.execute(
        "INSERT OR IGNORE INTO messages (id, conversation_id, sender_id, body, sent_at, local_state) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![call_message_id(call_id), conversation, if outgoing { super::ME_ID } else { peer }, body, at_ms, if outgoing { "sent" } else { "received" }],
    )
    .map_err(db_err)?;
    Ok(())
}

/// Calls recorded before they were messages (and any whose chat did not exist yet) become messages: run when the store opens.
pub(crate) fn backfill_call_messages(conn: &Connection) -> Result<(), StoreError> {
    let mut statement = conn.prepare("SELECT id, peer, video, outgoing, at_ms, duration_ms, outcome FROM call_history").map_err(db_err)?;
    let rows = statement
        .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, bool>(2)?, r.get::<_, bool>(3)?, r.get::<_, i64>(4)?, r.get::<_, i64>(5)?, r.get::<_, String>(6)?)))
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    drop(statement);
    for (id, peer, video, outgoing, at, duration, outcome) in rows {
        insert_call_message(conn, &id, &peer, video, outgoing, at, duration, &outcome)?;
    }
    Ok(())
}

#[uniffi::export]
impl LimeStore {
    /// Adds a call (or replaces the one with that id). A missed incoming call starts unseen.
    pub fn call_history_add(&self, record: CallHistoryRecord) -> Result<(), StoreError> {
        let conn = self.lock();
        conn.execute(
            "INSERT OR REPLACE INTO call_history (id, peer, peer_name, video, outgoing, at_ms, duration_ms, outcome, seen)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, COALESCE((SELECT seen FROM call_history WHERE id = ?1), 0))",
            params![record.id, record.peer, record.peer_name, record.video, record.outgoing, record.at_ms, record.duration_ms, record.outcome],
        )
        .map_err(db_err)?;
        conn.execute("DELETE FROM call_history WHERE id NOT IN (SELECT id FROM call_history ORDER BY at_ms DESC LIMIT ?1)", params![HISTORY_KEEP]).map_err(db_err)?;
        insert_call_message(&conn, &record.id, &record.peer, record.video, record.outgoing, record.at_ms, record.duration_ms, &record.outcome)?;
        Ok(())
    }

    /// Every call, newest first.
    pub fn call_history_list(&self) -> Result<Vec<CallHistoryRecord>, StoreError> {
        let conn = self.lock();
        let mut statement = conn
            .prepare("SELECT id, peer, peer_name, video, outgoing, at_ms, duration_ms, outcome FROM call_history ORDER BY at_ms DESC, id")
            .map_err(db_err)?;
        let rows = statement
            .query_map([], |r| {
                Ok(CallHistoryRecord { id: r.get(0)?, peer: r.get(1)?, peer_name: r.get(2)?, video: r.get(3)?, outgoing: r.get(4)?, at_ms: r.get(5)?, duration_ms: r.get(6)?, outcome: r.get(7)? })
            })
            .map_err(db_err)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(db_err)?;
        Ok(rows)
    }

    /// Removes these calls.
    pub fn call_history_delete(&self, ids: Vec<String>) -> Result<(), StoreError> {
        let conn = self.lock();
        for id in ids {
            conn.execute("DELETE FROM call_history WHERE id = ?1", params![id]).map_err(db_err)?;
        }
        Ok(())
    }

    /// Removes every call (Settings → Privacy → Clear call history).
    pub fn call_history_clear(&self) -> Result<(), StoreError> {
        self.lock().execute("DELETE FROM call_history", []).map_err(db_err)?;
        Ok(())
    }

    /// The call tab was opened: the missed calls so far are seen.
    pub fn call_history_mark_missed_seen(&self) -> Result<(), StoreError> {
        self.lock().execute("UPDATE call_history SET seen = 1 WHERE seen = 0", []).map_err(db_err)?;
        Ok(())
    }

    /// Missed incoming calls not yet seen (the call tab's badge).
    pub fn call_history_missed_unseen_count(&self) -> Result<u32, StoreError> {
        let count: i64 = self
            .lock()
            .query_row("SELECT COUNT(*) FROM call_history WHERE outgoing = 0 AND outcome IN ('missed', 'missed_dnd', 'missed_hours') AND seen = 0", [], |r| r.get(0))
            .map_err(db_err)?;
        Ok(count as u32)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    const SDP: &str = "v=0\r\na=fingerprint:sha-256 ab:cd:ef\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n";

    fn record(id: &str, at: i64, outgoing: bool, outcome: &str) -> CallHistoryRecord {
        CallHistoryRecord { id: id.into(), peer: "jean".into(), peer_name: "Jean".into(), video: false, outgoing, at_ms: at, duration_ms: 0, outcome: outcome.into() }
    }

    #[test]
    fn call_history_adds_lists_newest_first_deletes_clears_and_counts_unseen_missed() {
        let dir = tempfile::tempdir().unwrap();
        let store = LimeStore::open(dir.path().join("calls.db").to_string_lossy().into_owned(), vec![7u8; 32]).unwrap();
        assert!(store.call_history_list().unwrap().is_empty());
        store.call_history_add(record("a", 100, false, "missed")).unwrap();
        store.call_history_add(record("b", 300, true, "completed")).unwrap();
        store.call_history_add(record("c", 200, false, "missed")).unwrap();
        store.call_history_add(record("d", 250, false, "completed")).unwrap();
        assert_eq!(store.call_history_list().unwrap().iter().map(|r| r.id.as_str()).collect::<Vec<_>>(), ["b", "d", "c", "a"]);
        assert_eq!(store.call_history_missed_unseen_count().unwrap(), 2, "two missed incoming calls; outgoing and answered ones do not count");
        store.call_history_mark_missed_seen().unwrap();
        assert_eq!(store.call_history_missed_unseen_count().unwrap(), 0);
        store.call_history_add(record("e", 400, false, "missed")).unwrap();
        assert_eq!(store.call_history_missed_unseen_count().unwrap(), 1, "a new missed call is unseen again");
        // replacing a call keeps its seen state
        store.call_history_add(record("a", 100, false, "missed")).unwrap();
        assert_eq!(store.call_history_missed_unseen_count().unwrap(), 1);
        store.call_history_delete(vec!["b".into(), "nope".into()]).unwrap();
        assert_eq!(store.call_history_list().unwrap().len(), 4);
        store.call_history_clear().unwrap();
        assert!(store.call_history_list().unwrap().is_empty());
    }

    fn store_with_chat(dir: &tempfile::TempDir) -> std::sync::Arc<LimeStore> {
        let store = LimeStore::open(dir.path().join("c.db").to_string_lossy().into_owned(), vec![7u8; 32]).unwrap();
        store.start_dm("jean".into(), "Jean".into()).unwrap();
        store
    }

    #[test]
    fn a_call_becomes_one_message_in_the_dm_sent_by_the_caller_and_never_twice() {
        let dir = tempfile::tempdir().unwrap();
        let store = store_with_chat(&dir);
        store.call_history_add(CallHistoryRecord { video: true, duration_ms: 23_000, ..record("c1", 1_000, true, "completed") }).unwrap();
        store.call_history_add(record("c2", 2_000, false, "missed")).unwrap();
        store.call_history_add(record("c1", 1_000, true, "completed")).unwrap(); // the same call again
        let messages = store.list_messages("dm:jean".into()).unwrap();
        assert_eq!(messages.iter().map(|m| m.id.as_str()).collect::<Vec<_>>(), ["call:c1", "call:c2"]);
        assert_eq!(messages[0].sender_id, None, "I called: mine");
        assert_eq!(messages[1].sender_id.as_deref(), Some("jean"), "they called: theirs");
        let body: serde_json::Value = serde_json::from_str(&messages[0].text).unwrap();
        assert_eq!((body["video"].as_bool(), body["duration_ms"].as_i64(), body["outcome"].as_str()), (Some(true), Some(23_000), Some("completed")));
        // deleting the history row (the Calls tab) leaves the chat's message; no chat, no message
        store.call_history_delete(vec!["c1".into()]).unwrap();
        assert_eq!(store.list_messages("dm:jean".into()).unwrap().len(), 2);
        store.call_history_add(CallHistoryRecord { peer: "nobody".into(), ..record("c9", 3_000, true, "completed") }).unwrap();
        assert!(store.list_messages("dm:nobody".into()).unwrap().is_empty());
    }

    #[test]
    fn calls_recorded_before_they_were_messages_are_backfilled_and_a_reaction_and_reply_name_a_call() {
        let dir = tempfile::tempdir().unwrap();
        let store = store_with_chat(&dir);
        // an older build's history row, with no message yet
        store.lock().execute("INSERT INTO call_history (id, peer, peer_name, video, outgoing, at_ms, duration_ms, outcome) VALUES ('old', 'jean', 'Jean', 0, 0, 500, 0, 'missed')", []).unwrap();
        assert!(store.list_messages("dm:jean".into()).unwrap().is_empty());
        backfill_call_messages(&store.lock()).unwrap();
        backfill_call_messages(&store.lock()).unwrap(); // once is enough; twice changes nothing
        assert_eq!(store.list_messages("dm:jean".into()).unwrap().iter().map(|m| m.id.as_str()).collect::<Vec<_>>(), ["call:old"]);
        // a reply to the call message resolves its root like any message's
        assert_eq!(crate::client::resolve_root(&store.lock(), "dm:jean", "call:old").unwrap().as_deref(), Some("call:old"));
        assert_eq!(crate::client::resolve_root(&store.lock(), "dm:jean", "call:nope").unwrap(), None);
    }

    #[test]
    fn unavailable_names_why_the_callee_will_not_ring() {
        assert_eq!(validate("call.unavailable", &json!({ "call_id": "c-1", "reason": "dnd" })).as_deref(), Some("c-1"));
        assert!(validate("call.unavailable", &json!({ "call_id": "c-1", "reason": "work_hours" })).is_some());
        assert!(validate("call.unavailable", &json!({ "call_id": "c-1", "reason": "bored" })).is_none());
        assert!(validate("call.unavailable", &json!({ "call_id": "c-1" })).is_none());
        assert!(is_call_op("call.unavailable"));
    }

    #[test]
    fn silenced_calls_count_as_missed_and_unavailable_does_not() {
        let dir = tempfile::tempdir().unwrap();
        let store = LimeStore::open(dir.path().join("calls.db").to_string_lossy().into_owned(), vec![7u8; 32]).unwrap();
        store.call_history_add(record("a", 100, false, "missed_dnd")).unwrap();
        store.call_history_add(record("b", 200, false, "missed_hours")).unwrap();
        store.call_history_add(record("c", 300, true, "unavailable")).unwrap();
        assert_eq!(store.call_history_missed_unseen_count().unwrap(), 2);
    }

    #[test]
    fn ringing_needs_only_a_call_id() {
        assert_eq!(validate("call.ringing", &json!({ "call_id": "c-1" })).as_deref(), Some("c-1"));
        assert!(validate("call.ringing", &json!({})).is_none());
        assert!(is_call_op("call.ringing"));
    }

    #[test]
    fn a_batch_of_candidates_validates_and_the_single_form_still_does() {
        let one = json!({ "call_id": "c-1", "candidate": "candidate:1 1 udp 2 1.2.3.4 5 typ host" });
        assert!(validate("call.ice", &one).is_some());
        let batch = json!({ "call_id": "c-1", "candidates": [{ "candidate": "candidate:1 1 udp 2 1.2.3.4 5 typ host", "sdpMid": "0", "sdpMLineIndex": 0 }, { "candidate": "candidate:2 1 udp 2 1.2.3.5 5 typ relay" }] });
        assert!(validate("call.ice", &batch).is_some());
        assert!(validate("call.ice", &json!({ "call_id": "c-1", "candidates": [] })).is_none());
        assert!(validate("call.ice", &json!({ "call_id": "c-1", "candidates": [{ "nope": 1 }] })).is_none());
        assert!(validate("call.ice", &json!({ "call_id": "c-1" })).is_none());
    }

    #[test]
    fn candidates_inside_the_sdp_do_not_change_the_fingerprint_check() {
        let sdp = format!("{SDP}a=candidate:1 1 udp 2 1.2.3.4 5 typ host\r\na=candidate:2 1 udp 2 1.2.3.5 6 typ relay\r\n");
        assert!(validate("call.offer", &json!({ "call_id": "c-1", "sdp": sdp, "fingerprint": "AB:CD:EF" })).is_some());
        assert!(validate("call.offer", &json!({ "call_id": "c-1", "sdp": sdp, "fingerprint": "00:00:00" })).is_none());
    }

    #[test]
    fn the_fingerprint_is_read_from_the_sdp_and_must_match_the_one_the_op_names() {
        assert_eq!(sdp_fingerprint(SDP).as_deref(), Some("AB:CD:EF"));
        let ok = json!({ "call_id": "c-1", "sdp": SDP, "fingerprint": "ab:cd:ef" });
        assert_eq!(validate("call.offer", &ok).as_deref(), Some("c-1"));
        let swapped = json!({ "call_id": "c-1", "sdp": SDP, "fingerprint": "00:11:22" });
        assert!(validate("call.offer", &swapped).is_none(), "a swapped key is refused");
        assert!(validate("call.answer", &json!({ "call_id": "c-1", "sdp": "v=0\r\n", "fingerprint": "AB:CD:EF" })).is_none(), "an SDP with no fingerprint");
        assert!(validate("call.offer", &json!({ "sdp": SDP, "fingerprint": "AB:CD:EF" })).is_none(), "a call id is required");
        assert!(validate("call.ice", &json!({ "call_id": "c-1", "candidate": "candidate:1 1 udp 1 1.2.3.4 5 typ host" })).is_some());
        assert!(validate("call.end", &json!({ "call_id": "c-1" })).is_some());
        assert!(validate("call.end", &json!({ "call_id": "bad id!" })).is_none());
        assert!(is_call_op("call.busy") && !is_call_op("call.other") && !is_call_op("message.send"));
    }
}
