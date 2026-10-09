//! A tiny in-memory stand-in for the Supabase functions, for fast, deterministic tests of the
//! client (the real server is covered by `tests/integration.rs`). Tokens look like `tok-<user>`.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use sha2::Digest;

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
    /// user id to (display name, username)
    pub profiles: HashMap<String, (String, Option<String>)>,
    /// How many requests have been made to this server (a test of "nothing leaves the device").
    pub calls: usize,
    /// Make every `send` fail with a 500 while true.
    pub fail_sends: bool,
    /// sender user to hashes of identified items that were deleted undelivered
    pub undelivered: HashMap<String, Vec<String>>,
    /// user to SHA-256(access_key) (hex): what `delivery-access-set` stored
    pub delivery_access: HashMap<String, String>,
    /// How many `send` requests carried an Authorization header, and how many did not (sealed).
    pub sends_with_token: usize,
    pub sends_without_token: usize,
    /// Storage objects by `<bucket>/<name>` (the stand-in for Supabase Storage behind signed URLs).
    pub objects: HashMap<String, Vec<u8>>,
    /// user to (public photo version); a photo exists only while it is here and visibility is `everyone`
    pub avatar_versions: HashMap<String, i64>,
    /// user to `everyone` or `contacts`
    pub avatar_visibility: HashMap<String, String>,
    /// blob id to (owner, committed version)
    pub blob_rows: HashMap<String, (String, Option<i64>)>,
    pub clock: i64,
    /// attachment id to (owner, chunks, recipients, committed, fetchers)
    pub attachments: HashMap<String, (String, usize, usize, bool, Vec<String>)>,
    /// Make the next chunk upload fail once (an interrupted upload).
    pub fail_chunk_after: Option<usize>,
    pub chunk_uploads: usize,
    /// Chunk downloads so far, and make the one after this many fail once (an interrupted download).
    pub chunk_downloads: usize,
    pub fail_download_after: Option<usize>,
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
        method: String,
        path: String,
        headers: Vec<HeaderPair>,
        body: Vec<u8>,
    ) -> Result<TransportResponse, TransportError> {
        // A signed Storage URL: no Authorization header, the token is in the URL.
        if path.starts_with("/storage/") {
            let clean = path.split('?').next().unwrap_or_default();
            let object = clean.split("/sign/").nth(1).unwrap_or_default().to_owned();
            let mut state = self.state.lock().unwrap();
            return if method == "PUT" && clean.contains("/upload/sign/") {
                state.chunk_uploads += 1;
                if state.fail_chunk_after.is_some_and(|n| state.chunk_uploads > n) {
                    state.fail_chunk_after = None;
                    return Err(TransportError::Failed);
                }
                state.objects.insert(object, body);
                Ok(TransportResponse { status: 200, body: b"{}".to_vec() })
            } else if method == "GET" && !clean.contains("/upload/") {
                state.chunk_downloads += 1;
                if state.fail_download_after.is_some_and(|n| state.chunk_downloads > n) {
                    state.fail_download_after = None;
                    return Err(TransportError::Failed);
                }
                match state.objects.get(&object) {
                    Some(bytes) => Ok(TransportResponse { status: 200, body: bytes.clone() }),
                    None => Ok(TransportResponse { status: 404, body: b"{}".to_vec() }),
                }
            } else {
                Ok(TransportResponse { status: 400, body: b"{}".to_vec() })
            };
        }
        let function = path.rsplit('/').next().unwrap_or_default().to_owned();
        let body: Value = serde_json::from_slice(&body).unwrap_or(Value::Null);
        let user = headers
            .iter()
            .find(|h| h.name == "authorization")
            .and_then(|h| h.value.strip_prefix("Bearer tok-"))
            .map(str::to_owned);
        // A sealed `send` carries no token (the server learns nothing about the sender).
        if user.is_none() && function != "send" {
            return respond(401, json!({ "error": "unauthorized" }));
        }
        let user = user.unwrap_or_default();
        let text = |key: &str| {
            body.get(key)
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_owned()
        };
        let mut state = self.state.lock().unwrap();
        state.calls += 1;

        match function.as_str() {
            "devices-register" => {
                let (device, identity, signing) =
                    (text("device_id"), text("identity_key"), text("signing_key"));
                // A different master key from a verified session replaces the account's keys: the old
                // devices go, with their waiting mail (identified senders are told by hash).
                if state.masters.get(&user).is_some_and(|m| *m != text("master_key")) {
                    let old: Vec<String> = state
                        .devices
                        .iter()
                        .filter(|(_, d)| d.0 == user)
                        .map(|(id, _)| id.clone())
                        .collect();
                    for id in &old {
                        let gone: Vec<_> = state.mailbox.iter().filter(|m| &m.1 == id).cloned().collect();
                        for item in gone {
                            if let (true, Some(sender)) = (item.3, item.4.clone()) {
                                let wire = vodozemac::base64_decode(&item.2).unwrap();
                                let hash = sha2::Sha256::digest(&wire).iter().map(|b| format!("{b:02x}")).collect();
                                state.undelivered.entry(sender).or_default().push(hash);
                            }
                        }
                        state.mailbox.retain(|m| &m.1 != id);
                        state.devices.remove(id);
                        state.one_time_keys.remove(id);
                    }
                }
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
                if state.fail_sends {
                    return respond(500, json!({ "error": "internal" }));
                }
                let ciphertext = text("ciphertext");
                let recipients = body
                    .get("recipients")
                    .and_then(Value::as_array)
                    .cloned()
                    .unwrap_or_default();
                if user.is_empty() { state.sends_without_token += 1 } else { state.sends_with_token += 1 }
                // All or nothing: check every recipient's access before storing anything.
                for r in &recipients {
                    let identified = r["access"]["identified"].as_bool() == Some(true);
                    if identified {
                        if user.is_empty() {
                            return respond(401, json!({ "error": "unauthorized" }));
                        }
                        continue;
                    }
                    let device = r["to_device"].as_str().unwrap_or_default();
                    let owner = state.devices.get(device).map(|d| d.0.clone());
                    let presented = r["access"]["sealed"].as_str().and_then(|k| vodozemac::base64_decode(k).ok());
                    let hash: Option<String> = presented
                        .filter(|k| k.len() == 16)
                        .map(|k| sha2::Sha256::digest(&k).iter().map(|b| format!("{b:02x}")).collect());
                    let stored = owner.and_then(|o| state.delivery_access.get(&o).cloned());
                    if hash.is_none() || hash != stored {
                        return respond(403, json!({ "error": "access_denied" }));
                    }
                }
                for r in recipients {
                    let device = r["to_device"].as_str().unwrap().to_owned();
                    let identified = r["access"]["identified"].as_bool() == Some(true);
                    state.next_cursor += 1;
                    let cursor = state.next_cursor;
                    state.mailbox.push((
                        cursor,
                        device,
                        ciphertext.clone(),
                        identified,
                        identified.then(|| user.clone()),
                    ));
                }
                respond(200, json!({ "stored": 1, "duplicates": 0 }))
            }
            "avatar" => {
                state.clock += 1;
                let version = state.clock;
                match body.get("action").and_then(Value::as_str).unwrap_or_default() {
                    "put" => respond(200, json!({ "url": format!("/storage/v1/object/upload/sign/public-avatars/{user}.jpg?token=t") })),
                    "commit" => {
                        if !state.objects.contains_key(&format!("public-avatars/{user}.jpg")) {
                            return respond(409, json!({ "error": "not_uploaded" }));
                        }
                        state.avatar_versions.insert(user.clone(), version);
                        state.avatar_visibility.insert(user.clone(), "everyone".into());
                        respond(200, json!({ "version": version }))
                    }
                    "get" => {
                        let who = text("user_id");
                        let visible = state.avatar_visibility.get(&who).is_none_or(|v| v == "everyone");
                        match state.avatar_versions.get(&who) {
                            Some(version) if visible => respond(200, json!({ "url": format!("/storage/v1/object/sign/public-avatars/{who}.jpg?token=t"), "version": version })),
                            _ => respond(404, json!({ "error": "not_found" })),
                        }
                    }
                    "visibility" => {
                        let visibility = text("visibility");
                        if visibility == "contacts" {
                            state.objects.remove(&format!("public-avatars/{user}.jpg"));
                            state.avatar_versions.remove(&user);
                        }
                        state.avatar_visibility.insert(user.clone(), visibility);
                        respond(200, json!({ "ok": true }))
                    }
                    "remove" => {
                        state.objects.remove(&format!("public-avatars/{user}.jpg"));
                        state.avatar_versions.remove(&user);
                        respond(200, json!({ "ok": true }))
                    }
                    _ => respond(400, json!({ "error": "bad_request" })),
                }
            }
            "attachment" => {
                let id = text("attachment_id");
                let chunks_declared = body.get("chunks").and_then(Value::as_u64).unwrap_or(0) as usize;
                match body.get("action").and_then(Value::as_str).unwrap_or_default() {
                    "put" => {
                        let recipients = body.get("recipients").and_then(Value::as_u64).unwrap_or(1) as usize;
                        let entry = state.attachments.entry(id.clone()).or_insert((user.clone(), chunks_declared, recipients, false, vec![]));
                        if entry.0 != user {
                            return respond(409, json!({ "error": "id_taken" }));
                        }
                        let chunks = entry.1;
                        let committed = entry.3;
                        let mut urls = serde_json::Map::new();
                        if !committed {
                            for n in 0..chunks {
                                if !state.objects.contains_key(&format!("blobs/a/{id}/{n}")) {
                                    urls.insert(n.to_string(), json!(format!("/storage/v1/object/upload/sign/blobs/a/{id}/{n}?token=t")));
                                }
                            }
                        }
                        respond(200, json!({ "urls": urls }))
                    }
                    "commit" => {
                        let Some(chunks) = state.attachments.get(&id).map(|a| a.1) else { return respond(404, json!({ "error": "not_found" })) };
                        if (0..chunks).any(|n| !state.objects.contains_key(&format!("blobs/a/{id}/{n}"))) {
                            return respond(409, json!({ "error": "not_uploaded" }));
                        }
                        state.attachments.get_mut(&id).unwrap().3 = true;
                        respond(200, json!({ "size": 1 }))
                    }
                    "share" => match state.attachments.get_mut(&id) {
                        Some(entry) if entry.3 => {
                            entry.2 += body.get("recipients").and_then(Value::as_u64).unwrap_or(1) as usize;
                            respond(200, json!({ "ok": true }))
                        }
                        _ => respond(404, json!({ "error": "not_found" })),
                    },
                    "get" => match state.attachments.get(&id).cloned() {
                        Some((owner, chunks, recipients, true, mut fetchers)) => {
                            if owner != user && !fetchers.contains(&user) {
                                fetchers.push(user.clone());
                                state.attachments.get_mut(&id).unwrap().4 = fetchers.clone();
                            }
                            // Everyone has it: the real server deletes it within the hour; the stand-in at once.
                            let urls: Vec<String> = (0..chunks).map(|n| format!("/storage/v1/object/sign/blobs/a/{id}/{n}?token=t")).collect();
                            let _ = recipients;
                            respond(200, json!({ "chunks": chunks, "urls": urls }))
                        }
                        _ => respond(404, json!({ "error": "not_found" })),
                    },
                    _ => respond(400, json!({ "error": "bad_request" })),
                }
            }
            "blob" => {
                state.clock += 1;
                let version = state.clock;
                let id = text("blob_id");
                match body.get("action").and_then(Value::as_str).unwrap_or_default() {
                    "put" => {
                        if state.blob_rows.get(&id).is_some_and(|(owner, _)| *owner != user) {
                            return respond(409, json!({ "error": "id_taken" }));
                        }
                        state.blob_rows.insert(id.clone(), (user.clone(), None));
                        respond(200, json!({ "url": format!("/storage/v1/object/upload/sign/blobs/{id}?token=t") }))
                    }
                    "commit" => {
                        if !state.objects.contains_key(&format!("blobs/{id}")) {
                            return respond(409, json!({ "error": "not_uploaded" }));
                        }
                        state.blob_rows.insert(id, (user.clone(), Some(version)));
                        respond(200, json!({ "size": 1 }))
                    }
                    "get" => match state.blob_rows.get(&id) {
                        Some((_, Some(version))) => respond(200, json!({ "url": format!("/storage/v1/object/sign/blobs/{id}?token=t"), "version": version })),
                        _ => respond(404, json!({ "error": "not_found" })),
                    },
                    "delete" => {
                        if state.blob_rows.get(&id).is_some_and(|(owner, _)| *owner != user) {
                            return respond(409, json!({ "error": "id_taken" }));
                        }
                        state.blob_rows.remove(&id);
                        state.objects.remove(&format!("blobs/{id}"));
                        respond(200, json!({ "ok": true }))
                    }
                    _ => respond(400, json!({ "error": "bad_request" })),
                }
            }
            "delivery-access-set" => {
                let hash = vodozemac::base64_decode(text("access_key_hash")).unwrap_or_default();
                if hash.len() != 32 {
                    return respond(400, json!({ "error": "bad_request" }));
                }
                state.delivery_access.insert(user.clone(), hash.iter().map(|b| format!("{b:02x}")).collect());
                respond(200, json!({ "ok": true }))
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
            "undelivered-take" => {
                let hashes = state.undelivered.remove(&user).unwrap_or_default();
                respond(200, json!({ "hashes": hashes }))
            }
            "users-find" => {
                let query = text("query").to_lowercase();
                let query = query.trim_start_matches('@');
                let found = if let Some(id) = state.emails.get(query) {
                    Some(id.clone())
                } else {
                    state
                        .profiles
                        .iter()
                        .find(|(_, p)| p.1.as_deref().map(str::to_lowercase).as_deref() == Some(query))
                        .map(|(id, _)| id.clone())
                };
                match found.and_then(|id| state.profiles.get(&id).map(|p| (id, p.clone()))) {
                    Some((id, (name, username))) => respond(
                        200,
                        json!({ "user_id": id, "display_name": name, "username": username, "school": null, "is_self": id == user }),
                    ),
                    None => respond(404, json!({ "error": "not_found" })),
                }
            }
            "profile-get" => match state.profiles.get(&text("user_id")) {
                Some((name, username)) => respond(
                    200,
                    json!({ "profile": { "user_id": text("user_id"), "display_name": name, "username": username, "school": null } }),
                ),
                None => respond(404, json!({ "error": "not_found" })),
            },
            _ => respond(404, json!({ "error": "unknown function" })),
        }
    }
}
