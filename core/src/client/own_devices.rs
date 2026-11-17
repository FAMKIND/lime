//! Copies of what I do go to my own other devices (LIME-340, DESIGN-M1 section 4).
//!
//! An account can have several verified devices (the same master key signs them all). Everything I do on one reaches the others, end-to-end encrypted like any
//! message: a message I send (1:1, group, or a note to myself), an edit, a delete, a reaction, a chat marked read, a person blocked or unblocked. With **one
//! device nothing happens at all**: no copy is made, no request is sent, and nothing is stored (the outbox stays empty).
//!
//! **The envelope.** A copy is one op of type `own.copy`, signed by this device and sent over Olm (identified, with my token: the sessions between my own devices
//! live under my own user id) to each of my other devices. Inside the encryption its payload says what it is:
//! - `{"kind":"op","to":"dm:ana","op":{...}}` the op I made (`message.send`, `message.edit`, `message.delete`, `reaction.toggle`), already signed by this
//!   device, and the conversation it belongs to **as I name it** (`dm:ana`, `grp:...`, `dm:<me>` for notes to myself), so a copy of my message to Ana lands in
//!   `dm:ana` on the other device and never in a chat with myself;
//! - `{"kind":"read","conversation":"..."}`;
//! - `{"kind":"block","user":"...","on":true}`.
//!
//! **What is accepted.** `sender == me` is accepted only for `own.copy`, from an identified item, whose device certificate chains to **my own master key** (the
//! one this device holds), whose signature verifies, from a device that is not this one. Anything else claiming to be me is dropped as before. Applying a copy
//! never makes another copy (no echo).
//!
//! **Which devices.** Mine are known from a cache (`peer_devices` under my own user id), verified against my master key and never against what the server says
//! it is. The cache is filled by `refresh_own_devices` (the linking flow calls it; a stale send answered 409/410 refreshes it once). Until then the account is
//! treated as having one device.
//!
//! What each party learns: the server sees one more mailbox item per other device per action (it already knows how many devices an account has) and that they
//! were sent by me (identified, as every item between my own devices must be); never what is in them. My contacts see nothing.

use super::*;

pub(crate) const OWN_COPY: &str = "own.copy";

/// May a copy come from this device certificate? It must chain to **my** master key and not be this device.
pub(crate) fn certifies_my_other_device(cert: &SenderCert, my_master: &str, my_device: &str) -> bool {
    cert.master_key == my_master && cert.device_id != my_device && cert.verify()
}

/// Is this a conversation a copy may name? A one-to-one chat (`dm:<id>`, which includes my notes to myself) or a group.
fn conversation_ok(to: &str) -> bool {
    (to.starts_with("dm:") && to.len() > 3 && to.len() <= 80) || crate::store::groups::group_id_of(to).is_some()
}

/// Do I have other devices (as far as the cache says)? The cache holds all of them, this one included.
pub(crate) fn has_other_devices(conn: &Connection) -> bool {
    let me = crate::store::my_user_id(conn);
    if me.is_empty() {
        return false;
    }
    conn.query_row("SELECT COUNT(*) FROM peer_devices WHERE user_id = ?1", params![me], |r| r.get::<_, i64>(0)).unwrap_or(0) >= 2
}

/// Queues something for my other devices (a no-op with one device).
pub(crate) fn enqueue(conn: &Connection, payload: &Value) -> Result<(), StoreError> {
    if !has_other_devices(conn) {
        return Ok(());
    }
    conn.execute(
        "INSERT INTO own_copy_outbox (id, payload, created_at) VALUES (?1, ?2, ?3)",
        params![new_id(), payload.to_string(), now_ms()],
    )
    .map_err(db_err)?;
    Ok(())
}

/// What a copy of one of my ops says.
pub(crate) fn op_payload(to: &str, op: &Op) -> Value {
    json!({ "kind": "op", "to": to, "op": op.to_json() })
}

impl LimeStore {
    /// My account's devices from the cache, each checked against my master key.
    fn own_devices_all(&self, state: &AccountState, me: &str) -> Result<Vec<PeerDevice>, StoreError> {
        let master = state.master_key();
        self.with_conn(|conn| {
            let mut statement = conn
                .prepare("SELECT device_id, identity_key, signing_key, master_signature FROM peer_devices WHERE user_id = ?1 ORDER BY device_id")
                .map_err(db_err)?;
            let rows: Vec<PeerDevice> = statement
                .query_map(params![me], |r| Ok(PeerDevice { device_id: r.get(0)?, identity_key: r.get(1)?, signing_key: r.get(2)?, master_signature: r.get(3)? }))
                .map_err(db_err)?
                .collect::<Result<_, _>>()
                .map_err(db_err)?;
            Ok(rows
                .into_iter()
                .filter(|d| {
                    SenderCert {
                        device_id: d.device_id.clone(),
                        identity_key: d.identity_key.clone(),
                        signing_key: d.signing_key.clone(),
                        master_key: master.clone(),
                        master_signature: d.master_signature.clone(),
                    }
                    .verify()
                })
                .collect())
        })
    }

    /// Asks the server for my account's devices and keeps those my master key vouches for. A list under a different master key is never believed (it
    /// would be someone else's keys, or a reset: neither is for a device to accept silently). Returns how many devices the account has now.
    pub(crate) fn refresh_own_devices(&self, transport: &Arc<dyn Transport>, token: &str, state: &AccountState, me: &str) -> Result<usize, StoreError> {
        let (status, body) = call(transport, Some(token), "users-devices", &json!({ "user_id": me }))?;
        check(status)?;
        let master = body.get("master_key").and_then(Value::as_str).ok_or(StoreError::NoRecipientKeys)?;
        if master != state.master_key() {
            return Err(StoreError::KeyMismatch);
        }
        let mut devices = Vec::new();
        for entry in body.get("devices").and_then(Value::as_array).ok_or(StoreError::BadMessage)? {
            let text = |k: &str| entry.get(k).and_then(Value::as_str).map(str::to_owned);
            let (Some(device_id), Some(identity_key), Some(signing_key), Some(master_signature)) =
                (text("device_id"), text("identity_key"), text("signing_key"), text("master_signature"))
            else {
                continue;
            };
            let cert = SenderCert { device_id: device_id.clone(), identity_key: identity_key.clone(), signing_key: signing_key.clone(), master_key: master.to_owned(), master_signature: master_signature.clone() };
            if cert.verify() {
                devices.push(PeerDevice { device_id, identity_key, signing_key, master_signature });
            }
        }
        // One device: nothing is cached (the account behaves as it always did).
        let keep: &[PeerDevice] = if devices.len() >= 2 { &devices } else { &[] };
        self.with_conn(|conn| {
            store_peer_devices(conn, me, keep)?;
            if keep.is_empty() {
                conn.execute("DELETE FROM own_copy_outbox", []).map_err(db_err)?;
            }
            Ok(())
        })?;
        Ok(devices.len())
    }

    /// Queues a copy of a message I send (1:1, group or note to myself) for my other devices.
    pub(super) fn enqueue_own_message(&self, state: &AccountState, message: &Queued) {
        let mut op = Op {
            op_id: message.id.clone(),
            op_type: "message.send".into(),
            conversation_id: message.conversation_id.clone(),
            hlc: message.hlc.clone(),
            parents: message.parents.clone(),
            payload: message.payload(),
            sig: String::new(),
        };
        op.sig = state.account.sign(op.signing_bytes()).to_base64();
        let to = message.conversation_id.clone();
        let _ = self.with_conn(|conn| enqueue(conn, &op_payload(&to, &op)));
    }

    /// Queues a copy of an edit, delete or reaction I made (`id` is the op's id; the payload carries its clock).
    pub(super) fn enqueue_own_message_op(&self, state: &AccountState, id: &str, op_type: &str, conversation_id: &str, payload: &Value) {
        let hlc = payload.get("hlc").and_then(Value::as_str).unwrap_or_default().to_owned();
        let mut op = Op { op_id: id.to_owned(), op_type: op_type.to_owned(), conversation_id: conversation_id.to_owned(), hlc, parents: vec![], payload: payload.clone(), sig: String::new() };
        op.sig = state.account.sign(op.signing_bytes()).to_base64();
        let _ = self.with_conn(|conn| enqueue(conn, &op_payload(conversation_id, &op)));
    }

    /// Sends what is owed to my other devices, in order. Stops quietly when the network is down; with one device it clears whatever was left.
    pub(super) fn deliver_own_copies(&self, transport: &Arc<dyn Transport>, token: &str, state: &mut AccountState, me: &str) {
        let Ok(rows) = self.with_conn(|conn| {
            let mut statement = conn.prepare("SELECT id, payload FROM own_copy_outbox ORDER BY created_at, rowid").map_err(db_err)?;
            let rows = statement
                .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))
                .map_err(db_err)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(db_err)?;
            Ok(rows)
        }) else {
            return;
        };
        for (id, payload) in rows {
            let done = |conn: &Connection| conn.execute("DELETE FROM own_copy_outbox WHERE id = ?1", params![id]).map(|_| ()).map_err(db_err);
            if !self.with_conn(|conn| Ok(has_other_devices(conn))).unwrap_or(false) {
                let _ = self.with_conn(done);
                continue;
            }
            let Ok(payload) = serde_json::from_str::<Value>(&payload) else {
                let _ = self.with_conn(done);
                continue;
            };
            match self.send_own_copy(transport, token, state, me, &payload) {
                Ok(()) => {
                    let _ = self.with_conn(done);
                }
                // No internet: the rest waits, in order.
                Err(StoreError::Network | StoreError::Unavailable) => return,
                // Anything else would block the copies behind it for good: this one is given up.
                Err(_) => {
                    let _ = self.with_conn(done);
                }
            }
        }
    }

    /// One copy to each of my other devices (an Olm ciphertext per device, like a send to a contact's devices). A 409 or 410 means my cache of my own devices
    /// is stale: it is refreshed once and the copy goes again.
    fn send_own_copy(&self, transport: &Arc<dyn Transport>, token: &str, state: &mut AccountState, me: &str, payload: &Value) -> Result<(), StoreError> {
        let mut corrected = false;
        loop {
            let all = self.own_devices_all(state, me)?;
            let others: Vec<PeerDevice> = all.iter().filter(|d| d.device_id != state.device_id).cloned().collect();
            if others.is_empty() {
                return Ok(());
            }
            let mut existing = self.with_conn(|conn| load_sessions(conn, &self.pickle_key, me))?;
            let mut sessions = Vec::new();
            let mut needs_claim = Vec::new();
            for device in &others {
                match existing.iter().position(|s| s.peer_identity_key == device.identity_key) {
                    Some(at) => sessions.push((device.clone(), existing.remove(at).session)),
                    None => needs_claim.push(device.clone()),
                }
            }
            if !needs_claim.is_empty() {
                let wanted: Vec<String> = needs_claim.iter().map(|d| d.device_id.clone()).collect();
                let claimed = self.claim_keys(transport, token, me, &wanted)?;
                let now = now_ms();
                for device in needs_claim {
                    let Some(one_time_key) = claimed.get(&device.device_id) else { continue };
                    let identity = Curve25519PublicKey::from_base64(&device.identity_key).map_err(|_| StoreError::BadMessage)?;
                    let one_time = Curve25519PublicKey::from_base64(one_time_key).map_err(|_| StoreError::BadMessage)?;
                    let session = state.account.create_outbound_session(SessionConfig::version_1(), identity, one_time).map_err(|_| StoreError::BadMessage)?;
                    self.with_conn(|conn| save_session(conn, &self.pickle_key, me, &device.device_id, &device.identity_key, &session, false, now))?;
                    sessions.push((device, session));
                }
            }
            if sessions.is_empty() {
                return Err(StoreError::NoRecipientKeys);
            }
            let hlc = self.with_conn(|conn| Ok(tick_hlc(conn, now_ms())?.render()))?;
            let mut op = Op { op_id: new_id(), op_type: OWN_COPY.into(), conversation_id: format!("own:{me}"), hlc, parents: vec![], payload: payload.clone(), sig: String::new() };
            op.sig = state.account.sign(op.signing_bytes()).to_base64();
            let inner = SealedInner { sender_user: me.to_owned(), sender_device: state.device_id.clone(), sender_cert: state.cert(), op }.to_bytes();
            let mut ids: Vec<String> = all.iter().map(|d| d.device_id.clone()).collect();
            ids.sort();
            let expect = json!({ me: { "devices": ids, "master": hex_sha256(state.master_key().as_bytes()) } });
            let mut updated = Vec::new();
            let mut stale = false;
            for (device, mut session) in sessions {
                let encrypted = session.encrypt(&inner).map_err(|_| StoreError::BadMessage)?;
                // Written ahead, as for any send: the ratchet has moved.
                self.with_conn(|conn| save_session(conn, &self.pickle_key, me, &device.device_id, &device.identity_key, &session, false, now_ms()))?;
                let (kind, bytes) = encrypted.to_parts();
                let mut wire = vec![kind as u8];
                wire.extend_from_slice(&bytes);
                let request = json!({
                    "ciphertext": vodozemac::base64_encode(&wire),
                    "recipients": [{ "to_device": device.device_id, "access": { "identified": true } }],
                    "expect": expect,
                });
                let (status, _) = call(transport, Some(token), "send", &request)?;
                if status == 409 || status == 410 {
                    stale = true;
                    break;
                }
                check(status)?;
                updated.push((device, session));
            }
            if stale {
                if corrected {
                    return Err(StoreError::Unavailable);
                }
                corrected = true;
                self.refresh_own_devices(transport, token, state, me)?;
                continue;
            }
            let now = now_ms();
            self.with_conn(|conn| {
                for (device, session) in &updated {
                    save_session(conn, &self.pickle_key, me, &device.device_id, &device.identity_key, session, false, now)?;
                }
                Ok(())
            })?;
            return Ok(());
        }
    }
}

/// Applies a copy that arrived from one of my other devices (already checked: identified, my master key, not this device, signature good). Never makes a copy of
/// its own. `Ok(true)` when it changed something new (a message that was not here).
impl LimeStore {
    pub(crate) fn apply_own_copy(&self, conn: &Connection, state: &AccountState, me: &str, cert: &SenderCert, payload: &Value, now: i64) -> Result<bool, StoreError> {
        match payload.get("kind").and_then(Value::as_str) {
            // A group or band state op I made on my other device (create, add, remove, rename, photo, style, role, leave, delete, band marks...), signed there and
            // kept with its certificate like any group op: applied as if I had made it here. Only when it is from that very device and its signature holds.
            Some("group_op") => {
                let Some(inner) = payload.get("inner").and_then(Value::as_str).and_then(|text| SealedInner::from_bytes(text.as_bytes())) else { return Ok(false) };
                if inner.sender_user != me || inner.sender_device != cert.device_id || inner.sender_cert != *cert || !inner.op.verify(&cert.signing_key) {
                    return Ok(false);
                }
                self.apply_group_op(conn, me, me, &inner, cert, now)?;
                Ok(false)
            }
            // A jam I followed on my other device: followed here too (the writer welcomes this device with the keys), or left here too.
            Some("jam") => {
                let Some(jam_id) = payload.get("jam_id").and_then(Value::as_str).filter(|id| !id.is_empty() && id.len() <= 64) else { return Ok(false) };
                match payload.get("op").and_then(Value::as_str) {
                    Some("subscribe") => {
                        let Some(writer) = payload.get("writer").and_then(Value::as_str).filter(|w| !w.is_empty() && *w != me) else { return Ok(false) };
                        if crate::store::jam::jam_id_of(&crate::store::jam::conversation_id(jam_id)).is_none() {
                            return Ok(false);
                        }
                        crate::client::jam::subscribe_in(conn, state, jam_id, writer, now)?;
                    }
                    Some("unsubscribe") => {
                        let _ = crate::client::jam::unsubscribe_local(conn, jam_id);
                    }
                    _ => {}
                }
                Ok(false)
            }
            // The settings that follow me. (Themes, chat looks, drafts, my private labels and the like are never copied.)
            Some("setting") => {
                apply_setting(conn, payload, now)?;
                Ok(false)
            }
            _ => apply_basic_copy(conn, me, cert, payload, now),
        }
    }
}

fn apply_setting(conn: &Connection, payload: &Value, now: i64) -> Result<(), StoreError> {
    let conversation = payload.get("conversation").and_then(Value::as_str).filter(|c| conversation_ok(c));
    let on = payload.get("on").and_then(Value::as_bool);
    match payload.get("name").and_then(Value::as_str) {
        Some("pin") => {
            if let (Some(conversation), Some(on)) = (conversation, on) {
                conn.execute("UPDATE conversations SET is_pinned = ?2 WHERE id = ?1", params![conversation, on]).map_err(db_err)?;
            }
        }
        Some("marked_unread") => {
            if let (Some(conversation), Some(on)) = (conversation, on) {
                conn.execute("UPDATE conversations SET marked_unread = ?2 WHERE id = ?1", params![conversation, on]).map_err(db_err)?;
            }
        }
        Some("status") => {
            if let Some(status) = payload.get("status").and_then(crate::store::status::parse) {
                crate::store::status::store_mine(conn, &status, now)?;
            }
        }
        Some("emergency") => {
            let text = |k: &str| payload.get(k).and_then(Value::as_str).map(str::to_owned);
            let settings = crate::store::emergency::EmergencySettings {
                group_id: text("group_id").unwrap_or_default(),
                school_actions: payload.get("school_actions").and_then(Value::as_bool).unwrap_or(true),
                sound: payload.get("sound").and_then(Value::as_bool).unwrap_or(false),
                last_students: payload.get("last_students").and_then(Value::as_u64).unwrap_or(0).min(u64::from(u32::MAX)) as u32,
                last_place: text("last_place").unwrap_or_default(),
            };
            crate::store::emergency::save_settings(conn, &settings)?;
        }
        _ => {}
    }
    Ok(())
}

pub(crate) fn apply_basic_copy(conn: &Connection, me: &str, cert: &SenderCert, payload: &Value, now: i64) -> Result<bool, StoreError> {
    match payload.get("kind").and_then(Value::as_str) {
        Some("op") => {
            let (Some(to), Some(op)) = (payload.get("to").and_then(Value::as_str), payload.get("op").and_then(Op::from_json)) else { return Ok(false) };
            if !conversation_ok(to) || op.conversation_id != to || !op.verify(&cert.signing_key) {
                return Ok(false);
            }
            match op.op_type.as_str() {
                "message.send" => apply_message(conn, me, to, &op, now),
                t if crate::store::message_ops::is_message_op(t) => {
                    // The same rules as for anyone's: only the author edits or deletes (here: me), a reaction is mine.
                    crate::store::message_ops::apply(conn, me, to, &op)?;
                    Ok(false)
                }
                _ => Ok(false),
            }
        }
        Some("read") => {
            if let Some(conversation) = payload.get("conversation").and_then(Value::as_str) {
                conn.execute(
                    "UPDATE conversations SET unread = 0, marked_unread = 0 WHERE id = ?1 AND (unread != 0 OR marked_unread != 0)",
                    params![conversation],
                )
                .map_err(db_err)?;
                // The replies in its threads were read too.
                conn.execute("UPDATE thread_state SET unread = 0 WHERE root_id IN (SELECT id FROM messages WHERE conversation_id = ?1) AND unread != 0", params![conversation])
                    .map_err(db_err)?;
            }
            Ok(false)
        }
        Some("block") => {
            let (Some(user), Some(on)) = (payload.get("user").and_then(Value::as_str), payload.get("on").and_then(Value::as_bool)) else { return Ok(false) };
            if user.is_empty() || user == me {
                return Ok(false);
            }
            let conversation = format!("dm:{user}");
            if on {
                // Without a chat the person gets the hidden one a block makes (as `block_person` does); the key rotation a block on the first device caused is that
                // device's own business: this only records that the person is blocked.
                ensure_dm_as(conn, user, None, "blocked")?;
                conn.execute("UPDATE conversations SET hidden = 1 WHERE id = ?1 AND hidden = 0 AND NOT EXISTS (SELECT 1 FROM messages WHERE conversation_id = ?1)", params![conversation]).map_err(db_err)?;
                conn.execute("UPDATE conversations SET request_state = 'blocked', unread = 0 WHERE id = ?1", params![conversation]).map_err(db_err)?;
            } else {
                conn.execute("UPDATE conversations SET request_state = 'accepted' WHERE id = ?1 AND request_state = 'blocked'", params![conversation]).map_err(db_err)?;
            }
            Ok(false)
        }
        _ => Ok(false),
    }
}

/// Stores a message I sent from another device, as mine (sent, not unread), in the conversation named inside the encryption.
fn apply_message(conn: &Connection, me: &str, to: &str, op: &Op, now: i64) -> Result<bool, StoreError> {
    let Some(hlc) = Hlc::parse(&op.hlc) else { return Ok(false) };
    let Some(attachments) = crate::store::attachments::parse_payload(&op.payload) else { return Ok(false) };
    let text = crate::format::normalise(op.payload.get("text").and_then(Value::as_str).unwrap_or_default());
    if text.is_empty() && attachments.is_empty() {
        return Ok(false);
    }
    // The chat: a one-to-one I started on the other device is mine here too (accepted); a group must already be here.
    if let Some(peer) = to.strip_prefix("dm:") {
        let blocked = conn
            .query_row("SELECT request_state = 'blocked' FROM conversations WHERE id = ?1", params![to], |r| r.get::<_, bool>(0))
            .optional()
            .map_err(db_err)?
            .unwrap_or(false);
        if blocked {
            return Ok(false);
        }
        ensure_dm_as(conn, peer, None, "accepted")?;
    } else {
        let known: bool = conn.query_row("SELECT EXISTS (SELECT 1 FROM conversations WHERE id = ?1)", params![to], |r| r.get(0)).map_err(db_err)?;
        if !known {
            return Ok(false);
        }
    }
    let restricted = crate::store::message_ops::restrict_mentions(conn, to, me, &text);
    let plain = crate::format::plain_text(&restricted);
    let claimed_root = op.payload.get("thread_root").and_then(Value::as_str).filter(|id| !id.is_empty() && id.len() <= 64 && *id != op.op_id);
    let root = match claimed_root {
        None => None,
        Some(id) => Some(resolve_root(conn, to, id)?.unwrap_or_else(|| id.to_owned())),
    };
    let shown = hlc.wall.min(now);
    let inserted = conn
        .execute(
            "INSERT OR IGNORE INTO messages (id, conversation_id, sender_id, body, sent_at, local_state, op_id, hlc, parents, plain, thread_root)
             VALUES (?1, ?2, ?3, ?4, ?5, 'sent', ?1, ?6, ?7, ?8, ?9)",
            params![op.op_id, to, ME_ID, restricted, shown, op.hlc, json!(op.parents).to_string(), plain, root],
        )
        .map_err(db_err)?;
    if inserted > 0 {
        conn.execute("UPDATE conversations SET hidden = 0 WHERE id = ?1 AND hidden != 0", params![to]).map_err(db_err)?;
        for (position, descriptor) in attachments.iter().enumerate() {
            crate::store::attachments::insert(conn, &op.op_id, position, descriptor, None)?;
        }
        crate::store::link_preview::Extras::parse(&op.payload).apply(conn, &op.op_id)?;
        crate::store::message_ops::apply_waiting(conn, &op.op_id, to)?;
    }
    Ok(inserted > 0)
}
