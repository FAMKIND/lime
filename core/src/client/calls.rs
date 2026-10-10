//! Sending call signalling (LIME-111, see `store::calls`).

use super::*;
use crate::store::calls;

#[uniffi::export]
impl LimeStore {
    /// Sends one call op (`call.offer`, `call.answer`, `call.ice`, `call.end`, `call.busy` or `call.decline`) to an accepted contact,
    /// now (signalling is not queued: a ring that arrives late is no ring). `payload` is a JSON object with a `call_id`; an offer or answer
    /// must carry an SDP and the fingerprint inside it.
    pub fn send_call_signal(
        &self,
        transport: Arc<dyn Transport>,
        auth_token: String,
        peer_user_id: String,
        op_type: String,
        payload: String,
    ) -> Result<(), StoreError> {
        if !calls::is_call_op(&op_type) {
            return Err(StoreError::Rejected);
        }
        let payload: Value = serde_json::from_str(&payload).map_err(|_| StoreError::Rejected)?;
        calls::validate(&op_type, &payload).ok_or(StoreError::Rejected)?;
        let accepted = self.with_conn(|conn| {
            conn.query_row("SELECT request_state = 'accepted' FROM conversations WHERE id = ?1", params![format!("dm:{peer_user_id}")], |r| r.get::<_, bool>(0))
                .optional()
                .map_err(db_err)
                .map(|v| v.unwrap_or(false))
        })?;
        if !accepted {
            return Err(StoreError::Rejected);
        }
        let _guard = self.lock_protocol();
        let mut state = self.load_or_create_account()?;
        let me = state.user_id.clone().filter(|_| state.registered).ok_or(StoreError::NotRegistered)?;
        self.send_control_op(&transport, &auth_token, &mut state, &me, &peer_user_id, &op_type, payload)
    }
}

/// Time-limited credentials for the TURN relay (see `supabase/functions/turn-credentials`).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct TurnServers {
    pub urls: Vec<String>,
    pub username: String,
    pub credential: String,
    pub ttl_seconds: u32,
}

#[uniffi::export]
impl LimeStore {
    /// Asks the server for TURN credentials (a signed-in session only). `None` when calls' relay is not set up there yet; a call can
    /// still connect directly.
    pub fn fetch_turn_servers(&self, transport: Arc<dyn Transport>, auth_token: String) -> Result<Option<TurnServers>, StoreError> {
        let (status, body) = call(&transport, Some(&auth_token), "turn-credentials", &json!({}))?;
        if status == 503 {
            return Ok(None);
        }
        check(status)?;
        let text = |k: &str| body.get(k).and_then(Value::as_str).map(str::to_owned);
        let urls: Vec<String> = body.get("urls").and_then(Value::as_array).map(|a| a.iter().filter_map(Value::as_str).map(str::to_owned).collect()).unwrap_or_default();
        let (Some(username), Some(credential)) = (text("username"), text("credential")) else { return Err(StoreError::BadMessage) };
        if urls.is_empty() {
            return Err(StoreError::BadMessage);
        }
        Ok(Some(TurnServers { urls, username, credential, ttl_seconds: body.get("ttl").and_then(Value::as_u64).unwrap_or(3600) as u32 }))
    }
}
