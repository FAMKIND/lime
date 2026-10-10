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

pub(crate) const OPS: [&str; 6] = ["call.offer", "call.answer", "call.ice", "call.end", "call.busy", "call.decline"];

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
            payload.get("candidate").and_then(Value::as_str).filter(|c| c.len() <= 2_000)?;
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
    /// `call.offer`, `call.answer`, `call.ice`, `call.end`, `call.busy` or `call.decline`.
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

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    const SDP: &str = "v=0\r\na=fingerprint:sha-256 ab:cd:ef\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n";

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
