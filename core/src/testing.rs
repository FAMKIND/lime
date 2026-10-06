//! A tiny in-memory stand-in for the Supabase functions, for fast, deterministic tests of the
//! client (the real server is covered by `tests/integration.rs`). Tokens look like `tok-<user>`.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use serde_json::{json, Value};

use crate::transport::{HeaderPair, Transport, TransportError, TransportResponse};

#[derive(Default)]
pub(crate) struct ServerState {
    /// device id to (user, identity key, signing key, master signature)
    pub devices: HashMap<String, (String, String, String, String)>,
    pub masters: HashMap<String, String>,
    pub one_time_keys: HashMap<String, Vec<(String, String)>>,
    /// (cursor, to_device, ciphertext, identified, sender)
    pub mailbox: Vec<(i64, String, String, bool, Option<String>)>,
    pub next_cursor: i64,
    /// Make the next `mailbox-ack` fail with a 500.
    pub fail_next_ack: bool,
    pub emails: HashMap<String, String>,
}

#[derive(Default)]
pub(crate) struct FakeServer {
    pub state: Mutex<ServerState>,
}

impl FakeServer {
    pub(crate) fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    pub(crate) fn token(user: &str) -> String {
        format!("tok-{user}")
    }

    pub(crate) fn mailbox_len(&self, device: &str) -> usize {
        self.state
            .lock()
            .unwrap()
            .mailbox
            .iter()
            .filter(|m| m.1 == device)
            .count()
    }

    /// Put an item in a device's mailbox as the server would.
    pub(crate) fn inject(
        &self,
        device: &str,
        ciphertext: &str,
        identified: bool,
        sender: Option<&str>,
    ) {
        let mut state = self.state.lock().unwrap();
        state.next_cursor += 1;
        let cursor = state.next_cursor;
        state.mailbox.push((
            cursor,
            device.to_owned(),
            ciphertext.to_owned(),
            identified,
            sender.map(str::to_owned),
        ));
    }
}

fn respond(status: u16, body: Value) -> Result<TransportResponse, TransportError> {
    Ok(TransportResponse {
        status,
        body: serde_json::to_vec(&body).unwrap(),
    })
}

impl Transport for FakeServer {
    fn request(
        &self,
        _method: String,
        path: String,
        headers: Vec<HeaderPair>,
        body: Vec<u8>,
    ) -> Result<TransportResponse, TransportError> {
        let function = path.rsplit('/').next().unwrap_or_default().to_owned();
        let body: Value = serde_json::from_slice(&body).unwrap_or(Value::Null);
        let user = headers
            .iter()
            .find(|h| h.name == "authorization")
            .and_then(|h| h.value.strip_prefix("Bearer tok-"))
            .map(str::to_owned);
        let Some(user) = user else {
            return respond(401, json!({ "error": "unauthorized" }));
        };
        let text = |key: &str| {
            body.get(key)
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_owned()
        };
        let mut state = self.state.lock().unwrap();

        match function.as_str() {
            "devices-register" => {
                let (device, identity, signing) =
                    (text("device_id"), text("identity_key"), text("signing_key"));
                state.masters.insert(user.clone(), text("master_key"));
                state.devices.insert(
                    device.clone(),
                    (user.clone(), identity, signing, text("master_signature")),
                );
                let remaining = state.one_time_keys.get(&device).map_or(0, Vec::len);
                respond(
                    201,
                    json!({ "device_id": device, "user_id": user, "remaining_one_time_keys": remaining }),
                )
            }
            "keys-upload" => {
                let device = text("device_id");
                let keys = body
                    .get("one_time_keys")
                    .and_then(Value::as_array)
                    .cloned()
                    .unwrap_or_default();
                let pool = state.one_time_keys.entry(device).or_default();
                for key in keys {
                    pool.push((
                        key["key_id"].as_str().unwrap().to_owned(),
                        key["key"].as_str().unwrap().to_owned(),
                    ));
                }
                respond(200, json!({ "remaining_one_time_keys": pool.len() }))
            }
            "users-devices" => {
                let target = text("user_id");
                let devices: Vec<Value> = state
                    .devices
                    .iter()
                    .filter(|(_, d)| d.0 == target)
                    .map(|(id, d)| json!({ "device_id": id, "identity_key": d.1, "signing_key": d.2, "master_signature": d.3 }))
                    .collect();
                respond(
                    200,
                    json!({ "user_id": target, "master_key": state.masters.get(&target), "devices": devices }),
                )
            }
            "keys-claim" => {
                let target = text("user_id");
                let ids: Vec<String> = state
                    .devices
                    .iter()
                    .filter(|(_, d)| d.0 == target)
                    .map(|(id, _)| id.clone())
                    .collect();
                let mut out = Vec::new();
                for id in ids {
                    let key = state.one_time_keys.get_mut(&id).and_then(|pool| {
                        if pool.is_empty() {
                            None
                        } else {
                            Some(pool.remove(0))
                        }
                    });
                    out.push(json!({ "device_id": id, "one_time_key": key.map(|(key_id, key)| json!({ "key_id": key_id, "key": key })) }));
                }
                respond(200, json!({ "user_id": target, "devices": out }))
            }
            "send" => {
                let ciphertext = text("ciphertext");
                let recipients = body
                    .get("recipients")
                    .and_then(Value::as_array)
                    .cloned()
                    .unwrap_or_default();
                for r in recipients {
                    let device = r["to_device"].as_str().unwrap().to_owned();
                    state.next_cursor += 1;
                    let cursor = state.next_cursor;
                    state.mailbox.push((
                        cursor,
                        device,
                        ciphertext.clone(),
                        true,
                        Some(user.clone()),
                    ));
                }
                respond(200, json!({ "stored": 1, "duplicates": 0 }))
            }
            "mailbox-fetch" => {
                let device = text("device_id");
                let after = body.get("after").and_then(Value::as_i64).unwrap_or(0);
                let items: Vec<Value> = state
                    .mailbox
                    .iter()
                    .filter(|m| m.1 == device && m.0 > after)
                    .map(|m| {
                        let mut item = json!({ "cursor": m.0, "ciphertext": m.2, "size": m.2.len(), "received_at": "2026-10-06T00:00:00Z" });
                        if m.3 {
                            item["identified"] = json!(true);
                            item["sender_user"] = json!(m.4);
                        }
                        item
                    })
                    .collect();
                respond(200, json!({ "items": items, "has_more": false }))
            }
            "mailbox-ack" => {
                if state.fail_next_ack {
                    state.fail_next_ack = false;
                    return respond(500, json!({ "error": "internal" }));
                }
                let device = text("device_id");
                let up_to = body
                    .get("up_to_cursor")
                    .and_then(Value::as_i64)
                    .unwrap_or(0);
                let before = state.mailbox.len();
                state.mailbox.retain(|m| !(m.1 == device && m.0 <= up_to));
                respond(200, json!({ "deleted": before - state.mailbox.len() }))
            }
            "users-lookup" => {
                let email = text("email").to_lowercase();
                match state.emails.get(&email) {
                    Some(id) => respond(200, json!({ "user_id": id })),
                    None => respond(404, json!({ "error": "not_found" })),
                }
            }
            _ => respond(404, json!({ "error": "unknown function" })),
        }
    }
}
