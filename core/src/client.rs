//! The API v2 client: register this device, look people up, send an identified Olm message, and
//! sync (fetch, decrypt, store, acknowledge). The protocol lives here; the network is the
//! platform's [`Transport`]. Auth tokens are passed in per call and never stored.
//!
//! Scope of LIME-93: identified 1:1 sends only, Olm only. No Megolm, sealed sends, delivery keys,
//! groups or Requests yet. The op's `payload` is a plain `{ "text": ... }` inside the Olm
//! ciphertext until Megolm lands.

use std::sync::Arc;

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{json, Value};
use vodozemac::olm::{OlmMessage, SessionConfig};
use vodozemac::Curve25519PublicKey;

use crate::keys::AccountState;
use crate::protocol::{dm_conversation_id, Hlc, Op, SealedInner, SenderCert};
use crate::store::account::{
    load_account, load_sessions, observe_hlc, pin_master_key, save_account, save_session, tick_hlc,
};
use crate::store::order;
use crate::store::pending::{self, Fetched, PendingRow};
use crate::store::{db_err, new_id, now_ms, LimeStore, MessageItem, StoreError, ME_ID};
use crate::transport::{HeaderPair, Transport, TransportError};

/// The upload size of the one-time-key pool, and when to top it up (`api-v2.md` section 11).
const POOL_SIZE: usize = 50;
const POOL_LOW: u32 = 20;
/// A text message must fit in a 64 KB mailbox item once wrapped and encrypted.
const MAX_TEXT_BYTES: usize = 30_000;

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct DeviceInfo {
    pub device_id: String,
    pub user_id: String,
    pub identity_key: String,
    pub signing_key: String,
    pub master_key: String,
    pub remaining_one_time_keys: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct SyncReport {
    /// Messages decrypted, verified and stored (including earlier items that were retried).
    pub received: u32,
    /// Fetched items that are still waiting (unreadable for now, unsupported, or invalid): kept,
    /// never dropped.
    pub pending: u32,
}

// ---------------------------------------------------------------- the FFI surface

#[uniffi::export]
impl LimeStore {
    /// Registers this device with the server (idempotent) and tops up its one-time keys. The first
    /// call creates the device's keys (and, being the account's first device, its master key).
    pub fn register_device(
        &self,
        transport: Arc<dyn Transport>,
        auth_token: String,
    ) -> Result<DeviceInfo, StoreError> {
        let _guard = self.protocol_lock.lock().unwrap_or_else(|e| e.into_inner());
        let mut state = self.load_or_create_account()?;
        let cert = state.cert();

        let (status, body) = call(
            &transport,
            Some(&auth_token),
            "devices-register",
            &json!({
                "device_id": cert.device_id,
                "identity_key": cert.identity_key,
                "signing_key": cert.signing_key,
                "master_key": cert.master_key,
                "master_signature": cert.master_signature,
            }),
        )?;
        check(status)?;
        let user_id = body
            .get("user_id")
            .and_then(Value::as_str)
            .ok_or(StoreError::BadMessage)?
            .to_owned();
        let mut remaining = body
            .get("remaining_one_time_keys")
            .and_then(Value::as_u64)
            .unwrap_or(0) as u32;
        state.user_id = Some(user_id.clone());
        state.registered = true;
        self.save(&state)?;

        if remaining < POOL_LOW {
            remaining =
                self.top_up_one_time_keys(&transport, &auth_token, &mut state, remaining)?;
        }
        Ok(DeviceInfo {
            device_id: state.device_id.clone(),
            user_id,
            identity_key: state.identity_key(),
            signing_key: state.signing_key(),
            master_key: state.master_key(),
            remaining_one_time_keys: remaining,
        })
    }

    /// Writes a text into a 1:1 conversation as `sending` and returns it at once (nothing is sent
    /// yet: [`LimeStore::deliver_queued`] does that). The op's id, clock and parents are fixed here,
    /// so the message keeps its place however long delivery takes.
    pub fn queue_text(
        &self,
        conversation_id: String,
        text: String,
    ) -> Result<MessageItem, StoreError> {
        let body = text.trim();
        if body.is_empty() {
            return Err(StoreError::EmptyMessage);
        }
        if body.len() > MAX_TEXT_BYTES {
            return Err(StoreError::Rejected);
        }
        if conversation_id.strip_prefix("dm:").is_none() {
            return Err(StoreError::NotFound);
        }
        let state = self.load_or_create_account()?;
        state
            .user_id
            .as_ref()
            .filter(|_| state.registered)
            .ok_or(StoreError::NotRegistered)?;
        let now = now_ms();
        self.with_conn(|conn| {
            let visible: bool = conn
                .query_row(
                    "SELECT EXISTS (SELECT 1 FROM conversations WHERE id = ?1 AND request_state != 'blocked')",
                    params![conversation_id],
                    |r| r.get(0),
                )
                .map_err(db_err)?;
            if !visible {
                return Err(StoreError::NotFound);
            }
            let hlc = tick_hlc(conn, now)?;
            let parents = order::heads(conn, &conversation_id)?;
            let op_id = new_id();
            conn.execute(
                "INSERT INTO messages (id, conversation_id, sender_id, body, sent_at, local_state, op_id, hlc, parents)
                 VALUES (?1, ?2, ?3, ?4, ?5, 'sending', ?1, ?6, ?7)",
                params![op_id, conversation_id, ME_ID, body, now, hlc.render(), json!(parents).to_string()],
            )
            .map_err(db_err)?;
            Ok(MessageItem {
                id: op_id,
                conversation_id: conversation_id.clone(),
                sender_id: None,
                text: body.to_owned(),
                sent_at: now,
                local_state: "sending".to_owned(),
            })
        })
    }

    /// Sends every queued message (`sending`, or `failed` earlier), oldest first, as **identified**
    /// Olm messages, marking each `sent` once the server accepted it. Stops at the first failure
    /// (that message becomes `failed`; the order is kept) and returns the error. Returns how many
    /// were sent. A recipient de-duplicates by op id, so a retry never shows twice.
    pub fn deliver_queued(
        &self,
        transport: Arc<dyn Transport>,
        auth_token: String,
    ) -> Result<u32, StoreError> {
        let _guard = self.protocol_lock.lock().unwrap_or_else(|e| e.into_inner());
        let mut state = self.load_or_create_account()?;
        let me = state
            .user_id
            .clone()
            .filter(|_| state.registered)
            .ok_or(StoreError::NotRegistered)?;
        let queued = self.with_conn(queued_messages)?;
        let mut sent = 0;
        for message in queued {
            match self.deliver_one(&transport, &auth_token, &mut state, &me, &message) {
                Ok(()) => {
                    self.with_conn(|conn| set_state(conn, &message.id, "sent"))?;
                    sent += 1;
                }
                Err(error) => {
                    self.with_conn(|conn| set_state(conn, &message.id, "failed"))?;
                    return Err(error);
                }
            }
        }
        Ok(sent)
    }

    /// Queues a text for `recipient_user_id` and delivers it now (the conversation is created if
    /// needed). Returns the message as `sent`.
    pub fn send_text_identified(
        &self,
        transport: Arc<dyn Transport>,
        auth_token: String,
        recipient_user_id: String,
        text: String,
    ) -> Result<MessageItem, StoreError> {
        self.with_conn(|conn| ensure_dm(conn, &recipient_user_id, None).map(|_| ()))?;
        let mut item = self.queue_text(format!("dm:{recipient_user_id}"), text)?;
        self.deliver_queued(transport, auth_token)?;
        item.local_state = "sent".to_owned();
        Ok(item)
    }

    /// Fetches this device's mailbox, decrypts and verifies what it can, stores it, and
    /// acknowledges everything it fetched.
    pub fn sync(
        &self,
        transport: Arc<dyn Transport>,
        auth_token: String,
    ) -> Result<SyncReport, StoreError> {
        let _guard = self.protocol_lock.lock().unwrap_or_else(|e| e.into_inner());
        let mut state = self.load_or_create_account()?;
        let me = state
            .user_id
            .clone()
            .filter(|_| state.registered)
            .ok_or(StoreError::NotRegistered)?;

        let mut after = 0i64;
        loop {
            let (status, body) = call(
                &transport,
                Some(&auth_token),
                "mailbox-fetch",
                &json!({ "device_id": state.device_id, "after": after }),
            )?;
            check(status)?;
            let items = body
                .get("items")
                .and_then(Value::as_array)
                .ok_or(StoreError::BadMessage)?;
            if items.is_empty() {
                break;
            }
            let mut fetched = Vec::with_capacity(items.len());
            let mut highest = after;
            for item in items {
                let cursor = item
                    .get("cursor")
                    .and_then(Value::as_i64)
                    .ok_or(StoreError::BadMessage)?;
                highest = highest.max(cursor);
                fetched.push(Fetched {
                    cursor,
                    sender_user: item
                        .get("sender_user")
                        .and_then(Value::as_str)
                        .map(str::to_owned),
                    identified: item.get("identified").and_then(Value::as_bool) == Some(true),
                    ciphertext: item
                        .get("ciphertext")
                        .and_then(Value::as_str)
                        .ok_or(StoreError::BadMessage)?
                        .to_owned(),
                    received_at: item
                        .get("received_at")
                        .and_then(Value::as_str)
                        .map(str::to_owned),
                });
            }
            // Keep every item BEFORE telling the server to delete it: if this fails nothing is
            // acknowledged, and if the acknowledgement fails the items are still safe here.
            {
                let now = now_ms();
                let mut conn = self.lock();
                pending::insert_all(&mut conn, &fetched, now)?;
            }
            let (status, _) = call(
                &transport,
                Some(&auth_token),
                "mailbox-ack",
                &json!({ "device_id": state.device_id, "up_to_cursor": highest }),
            )?;
            check(status)?;
            after = highest;
            if body.get("has_more").and_then(Value::as_bool) != Some(true) {
                break;
            }
        }

        // Turn what is waiting into messages (and retry what failed before). A new session can make
        // an earlier item readable, so go round again while anything makes progress.
        let received = self.retry_pending(&mut state, &me)?;
        if received > 0 {
            self.refresh_names(&transport, &auth_token);
        }
        let waiting = self.with_conn(pending::count)?;
        Ok(SyncReport {
            received,
            pending: waiting,
        })
    }
}

/// Exact, case-insensitive email to user id (no profile data), or `None` when nobody has it.
#[uniffi::export]
pub fn lookup_user_by_email(
    transport: Arc<dyn Transport>,
    auth_token: String,
    email: String,
) -> Result<Option<String>, StoreError> {
    let (status, body) = call(
        &transport,
        Some(&auth_token),
        "users-lookup",
        &json!({ "email": email }),
    )?;
    if status == 404 {
        return Ok(None);
    }
    check(status)?;
    Ok(Some(
        body.get("user_id")
            .and_then(Value::as_str)
            .ok_or(StoreError::BadMessage)?
            .to_owned(),
    ))
}

/// A person found by exact username or email: public profile fields only.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FoundUser {
    pub user_id: String,
    pub display_name: String,
    pub username: Option<String>,
    pub school: Option<String>,
    /// True when the search found yourself.
    pub is_self: bool,
}

/// Finds a person by their exact username or exact email (nothing partial, never a list). `None`
/// when nobody matches, or they chose not to be found.
#[uniffi::export]
pub fn find_user(
    transport: Arc<dyn Transport>,
    auth_token: String,
    query: String,
) -> Result<Option<FoundUser>, StoreError> {
    let (status, body) = call(
        &transport,
        Some(&auth_token),
        "users-find",
        &json!({ "query": query }),
    )?;
    match status {
        404 => return Ok(None),
        429 => return Err(StoreError::RateLimited),
        _ => check(status)?,
    }
    let text = |k: &str| body.get(k).and_then(Value::as_str).map(str::to_owned);
    Ok(Some(FoundUser {
        user_id: text("user_id").ok_or(StoreError::BadMessage)?,
        display_name: text("display_name").ok_or(StoreError::BadMessage)?,
        username: text("username"),
        school: text("school"),
        is_self: body.get("is_self").and_then(Value::as_bool) == Some(true),
    }))
}

// ---------------------------------------------------------------- internals

#[derive(Clone)]
struct PeerDevice {
    device_id: String,
    identity_key: String,
}

impl LimeStore {
    fn with_conn<T>(
        &self,
        f: impl FnOnce(&Connection) -> Result<T, StoreError>,
    ) -> Result<T, StoreError> {
        let conn = self.lock();
        f(&conn)
    }

    fn save(&self, state: &AccountState) -> Result<(), StoreError> {
        self.with_conn(|conn| save_account(conn, &self.pickle_key, state))
    }

    fn load_or_create_account(&self) -> Result<AccountState, StoreError> {
        if let Some(state) = self.with_conn(|conn| load_account(conn, &self.pickle_key))? {
            return Ok(state);
        }
        let state = AccountState::create();
        self.save(&state)?;
        Ok(state)
    }

    /// Sends one queued message to every device of its recipient.
    fn deliver_one(
        &self,
        transport: &Arc<dyn Transport>,
        token: &str,
        state: &mut AccountState,
        me: &str,
        message: &Queued,
    ) -> Result<(), StoreError> {
        let recipient = message.peer.as_str();
        // 1. The recipient's devices, each vouched for by their master key.
        let devices = self.recipient_devices(transport, token, recipient)?;

        // 2. A session per device; claim a one-time key for each device that has none.
        let mut sessions = Vec::new();
        let mut needs_claim = Vec::new();
        for device in &devices {
            let existing =
                self.with_conn(|conn| load_sessions(conn, &self.pickle_key, recipient))?;
            match existing
                .into_iter()
                .find(|s| s.peer_identity_key == device.identity_key)
            {
                Some(stored) => sessions.push((device.clone(), stored.session)),
                None => needs_claim.push(device.clone()),
            }
        }
        if !needs_claim.is_empty() {
            let claimed = self.claim_keys(transport, token, recipient)?;
            for device in needs_claim {
                let Some(one_time_key) = claimed.get(&device.device_id) else {
                    continue;
                };
                let identity = Curve25519PublicKey::from_base64(&device.identity_key)
                    .map_err(|_| StoreError::BadMessage)?;
                let one_time = Curve25519PublicKey::from_base64(one_time_key)
                    .map_err(|_| StoreError::BadMessage)?;
                let session = state
                    .account
                    .create_outbound_session(SessionConfig::version_1(), identity, one_time)
                    .map_err(|_| StoreError::BadMessage)?;
                sessions.push((device, session));
            }
        }
        if sessions.is_empty() {
            return Err(StoreError::NoRecipientKeys);
        }

        // 3. The signed op (the id, clock and parents were fixed when it was queued), wrapped with
        // this device's certificate.
        let mut op = Op {
            op_id: message.id.clone(),
            op_type: "message.send".into(),
            conversation_id: dm_conversation_id(me, recipient),
            hlc: message.hlc.clone(),
            parents: message.parents.clone(),
            payload: json!({ "text": message.text }),
            sig: String::new(),
        };
        op.sig = state.account.sign(op.signing_bytes()).to_base64();
        let inner = SealedInner {
            sender_user: me.to_owned(),
            sender_device: state.device_id.clone(),
            sender_cert: state.cert(),
            op,
        }
        .to_bytes();

        // 4. One Olm ciphertext per recipient device, each sent identified.
        let mut updated = Vec::new();
        for (device, mut session) in sessions {
            let encrypted = session
                .encrypt(&inner)
                .map_err(|_| StoreError::BadMessage)?;
            let (kind, bytes) = encrypted.to_parts();
            let mut wire = vec![kind as u8];
            wire.extend_from_slice(&bytes);
            let (status, _) = call(
                transport,
                Some(token),
                "send",
                &json!({
                    "ciphertext": vodozemac::base64_encode(&wire),
                    "recipients": [{ "to_device": device.device_id, "access": { "identified": true } }],
                }),
            )?;
            check(status)?;
            updated.push((device, session));
        }

        // 5. Remember the sessions: their ratchets moved.
        let now = now_ms();
        self.with_conn(|conn| {
            for (device, session) in &updated {
                save_session(
                    conn,
                    &self.pickle_key,
                    recipient,
                    &device.device_id,
                    &device.identity_key,
                    session,
                    now,
                )?;
            }
            save_account(conn, &self.pickle_key, state)
        })
    }

    /// Fills in the profile name of people we only know by id (best effort, a few per sync).
    fn refresh_names(&self, transport: &Arc<dyn Transport>, token: &str) {
        let unnamed: Vec<String> = self
            .with_conn(|conn| {
                let mut statement = conn
                    .prepare("SELECT id FROM people WHERE id != ?1 AND name = id LIMIT 10")
                    .map_err(db_err)?;
                let rows = statement
                    .query_map(params![ME_ID], |r| r.get::<_, String>(0))
                    .map_err(db_err)?
                    .collect::<Result<Vec<_>, _>>()
                    .map_err(db_err)?;
                Ok(rows)
            })
            .unwrap_or_default();
        for id in unnamed {
            let Ok((200, body)) = call(transport, Some(token), "profile-get", &json!({ "user_id": id }))
            else {
                continue;
            };
            if let Some(name) = body
                .pointer("/profile/display_name")
                .and_then(Value::as_str)
                .filter(|n| !n.trim().is_empty())
            {
                let _ = self.with_conn(|conn| set_person_name(conn, &id, name));
            }
        }
    }

    fn top_up_one_time_keys(
        &self,
        transport: &Arc<dyn Transport>,
        token: &str,
        state: &mut AccountState,
        remaining: u32,
    ) -> Result<u32, StoreError> {
        let wanted = POOL_SIZE.saturating_sub(remaining as usize).max(1);
        state.account.generate_one_time_keys(wanted);
        let keys: Vec<Value> = state
            .account
            .one_time_keys()
            .into_iter()
            .map(|(id, key)| json!({ "key_id": id.to_base64(), "key": key.to_base64() }))
            .collect();
        self.save(state)?;
        if keys.is_empty() {
            return Ok(remaining);
        }
        let (status, body) = call(
            transport,
            Some(token),
            "keys-upload",
            &json!({ "device_id": state.device_id, "one_time_keys": keys }),
        )?;
        check(status)?;
        state.account.mark_keys_as_published();
        self.save(state)?;
        Ok(body
            .get("remaining_one_time_keys")
            .and_then(Value::as_u64)
            .unwrap_or(0) as u32)
    }

    /// The recipient's devices whose cross-signature verifies, with their master key pinned.
    fn recipient_devices(
        &self,
        transport: &Arc<dyn Transport>,
        token: &str,
        user_id: &str,
    ) -> Result<Vec<PeerDevice>, StoreError> {
        let (status, body) = call(
            transport,
            Some(token),
            "users-devices",
            &json!({ "user_id": user_id }),
        )?;
        check(status)?;
        let master = body
            .get("master_key")
            .and_then(Value::as_str)
            .ok_or(StoreError::NoRecipientKeys)?;
        self.with_conn(|conn| pin_master_key(conn, user_id, master))?;
        let mut devices = Vec::new();
        for entry in body
            .get("devices")
            .and_then(Value::as_array)
            .ok_or(StoreError::BadMessage)?
        {
            let text = |k: &str| entry.get(k).and_then(Value::as_str).map(str::to_owned);
            let (Some(device_id), Some(identity_key), Some(signing_key), Some(master_signature)) = (
                text("device_id"),
                text("identity_key"),
                text("signing_key"),
                text("master_signature"),
            ) else {
                continue;
            };
            let cert = SenderCert {
                device_id: device_id.clone(),
                identity_key: identity_key.clone(),
                signing_key,
                master_key: master.to_owned(),
                master_signature,
            };
            if cert.verify() {
                devices.push(PeerDevice {
                    device_id,
                    identity_key,
                });
            }
        }
        if devices.is_empty() {
            return Err(StoreError::NoRecipientKeys);
        }
        Ok(devices)
    }

    /// One-time keys claimed for a user's devices: device id to key.
    fn claim_keys(
        &self,
        transport: &Arc<dyn Transport>,
        token: &str,
        user_id: &str,
    ) -> Result<std::collections::HashMap<String, String>, StoreError> {
        let (status, body) = call(
            transport,
            Some(token),
            "keys-claim",
            &json!({ "user_id": user_id }),
        )?;
        check(status)?;
        let mut claimed = std::collections::HashMap::new();
        for entry in body
            .get("devices")
            .and_then(Value::as_array)
            .ok_or(StoreError::BadMessage)?
        {
            let device = entry.get("device_id").and_then(Value::as_str);
            let key = entry
                .get("one_time_key")
                .and_then(|k| k.get("key"))
                .and_then(Value::as_str);
            if let (Some(device), Some(key)) = (device, key) {
                claimed.insert(device.to_owned(), key.to_owned());
            }
        }
        Ok(claimed)
    }

    /// Tries every waiting item that is worth trying; returns how many became messages.
    fn retry_pending(&self, state: &mut AccountState, me: &str) -> Result<u32, StoreError> {
        let mut received = 0;
        loop {
            let rows = self.with_conn(pending::retryable)?;
            let mut progress = false;
            for row in rows {
                let outcome = self.process_item(state, me, &row)?;
                let now = now_ms();
                match outcome {
                    Outcome::Stored => {
                        self.with_conn(|conn| pending::remove(conn, row.id))?;
                        received += 1;
                        progress = true;
                    }
                    Outcome::Duplicate => {
                        self.with_conn(|conn| pending::remove(conn, row.id))?;
                        progress = true;
                    }
                    Outcome::Keep(reason) => {
                        self.with_conn(|conn| pending::keep(conn, row.id, reason, now))?;
                    }
                }
            }
            if !progress {
                return Ok(received);
            }
        }
    }

    /// Decrypts, verifies and stores one waiting item, or says why it stays waiting.
    fn process_item(
        &self,
        state: &mut AccountState,
        me: &str,
        row: &PendingRow,
    ) -> Result<Outcome, StoreError> {
        // Only identified items are understood here (sealed sends are not built yet): keep them.
        if !row.identified {
            return Ok(Outcome::Keep(pending::SEALED_UNSUPPORTED));
        }
        let Some(sender) = row.sender_user.clone() else {
            return Ok(Outcome::Keep(pending::INVALID));
        };
        if sender == me {
            return Ok(Outcome::Keep(pending::INVALID));
        }
        let Ok(wire) = vodozemac::base64_decode(&row.ciphertext) else {
            return Ok(Outcome::Keep(pending::INVALID));
        };
        let Some((kind, rest)) = wire.split_first() else {
            return Ok(Outcome::Keep(pending::INVALID));
        };
        let Ok(message) = OlmMessage::from_parts(*kind as usize, rest) else {
            return Ok(Outcome::Keep(pending::INVALID));
        };

        let now = now_ms();
        let sessions = self.with_conn(|conn| load_sessions(conn, &self.pickle_key, &sender))?;

        // Decrypt with an existing session, or (for a pre-key message) start one.
        let decrypted = 'decrypt: {
            for mut stored in sessions {
                let fits = match &message {
                    OlmMessage::PreKey(pre_key) => {
                        stored.session.session_id() == pre_key.session_id()
                    }
                    OlmMessage::Normal(_) => true,
                };
                if !fits {
                    continue;
                }
                if let Ok(plaintext) = stored.session.decrypt(&message) {
                    break 'decrypt Some((plaintext, stored.session, stored.peer_identity_key));
                }
            }
            let OlmMessage::PreKey(pre_key) = &message else {
                break 'decrypt None; // a normal message with no session that can read it (yet)
            };
            let identity = pre_key.identity_key();
            match state.account.create_inbound_session(
                SessionConfig::version_1(),
                identity,
                pre_key,
            ) {
                Ok(created) => {
                    // The one-time key it used is gone from the account now: save that.
                    self.save(state)?;
                    Some((created.plaintext, created.session, identity.to_base64()))
                }
                Err(_) => {
                    return Ok(Outcome::Keep(pending::DECRYPT_FAILED));
                }
            }
        };
        let Some((plaintext, session, peer_identity)) = decrypted else {
            return Ok(Outcome::Keep(match &message {
                OlmMessage::Normal(_) => pending::NO_SESSION,
                OlmMessage::PreKey(_) => pending::DECRYPT_FAILED,
            }));
        };

        let Some(inner) = SealedInner::from_bytes(&plaintext) else {
            return Ok(Outcome::Keep(pending::INVALID));
        };
        let cert = &inner.sender_cert;
        let valid = inner.sender_user == sender
            && inner.sender_device == cert.device_id
            && cert.identity_key == peer_identity
            && cert.verify()
            && inner.op.verify(&cert.signing_key)
            && inner.op.op_type == "message.send"
            && inner.op.conversation_id == dm_conversation_id(&sender, me);
        let text = inner
            .op
            .payload
            .get("text")
            .and_then(Value::as_str)
            .map(str::to_owned);
        let remote_hlc = Hlc::parse(&inner.op.hlc);
        let (true, Some(text), Some(remote_hlc)) = (valid, text, remote_hlc) else {
            return Ok(Outcome::Keep(pending::INVALID));
        };

        let parents = json!(inner.op.parents).to_string();
        let stored = self.with_conn(|conn| {
            if pin_master_key(conn, &sender, &cert.master_key) == Err(StoreError::KeyMismatch) {
                return Ok(None);
            }
            save_session(conn, &self.pickle_key, &sender, &cert.device_id, &peer_identity, &session, now)?;
            let conversation = format!("dm:{sender}");
            let blocked = conn
                .query_row(
                    "SELECT request_state = 'blocked' FROM conversations WHERE id = ?1",
                    params![conversation],
                    |r| r.get::<_, bool>(0),
                )
                .optional()
                .map_err(db_err)?
                .unwrap_or(false);
            if blocked {
                // Read (so the session keeps in step) but never stored or shown.
                return Ok(Some(false));
            }
            // A person we did not start a chat with is a request until accepted.
            ensure_dm_as(conn, &sender, None, "pending")?;
            // The display time is never in the future (api-v2.md section 5).
            let shown = remote_hlc.wall.min(now);
            let inserted = conn
                .execute(
                    "INSERT OR IGNORE INTO messages (id, conversation_id, sender_id, body, sent_at, local_state, op_id, hlc, parents)
                     VALUES (?1, ?2, ?3, ?4, ?5, 'received', ?1, ?6, ?7)",
                    params![inner.op.op_id, conversation, sender, text, shown, inner.op.hlc, parents],
                )
                .map_err(db_err)?;
            if inserted > 0 {
                conn.execute(
                    "UPDATE conversations SET unread = unread + 1 WHERE id = ?1",
                    params![conversation],
                )
                .map_err(db_err)?;
            }
            Ok(Some(inserted > 0))
        })?;
        let Some(inserted) = stored else {
            return Ok(Outcome::Keep(pending::KEY_MISMATCH));
        };
        self.with_conn(|conn| observe_hlc(conn, remote_hlc, now).map(|_| ()))?;
        Ok(if inserted {
            Outcome::Stored
        } else {
            Outcome::Duplicate
        })
    }
}

/// What became of one waiting item.
enum Outcome {
    /// It is now a message.
    Stored,
    /// It was a message already (the same op arrived twice).
    Duplicate,
    /// It stays, for this reason.
    Keep(&'static str),
}

/// A message of mine waiting to be sent.
struct Queued {
    id: String,
    peer: String,
    text: String,
    hlc: String,
    parents: Vec<String>,
}

fn queued_messages(conn: &Connection) -> Result<Vec<Queued>, StoreError> {
    let mut statement = conn
        .prepare(
            "SELECT id, conversation_id, body, hlc, parents FROM messages
             WHERE sender_id = ?1 AND local_state IN ('sending', 'failed') AND op_id IS NOT NULL AND hlc IS NOT NULL
             ORDER BY hlc, id",
        )
        .map_err(db_err)?;
    let rows = statement
        .query_map(params![ME_ID], |r| {
            let conversation: String = r.get(1)?;
            let parents: Option<String> = r.get(4)?;
            Ok(Queued {
                id: r.get(0)?,
                peer: conversation.strip_prefix("dm:").unwrap_or_default().to_owned(),
                text: r.get(2)?,
                hlc: r.get(3)?,
                parents: parents.and_then(|p| serde_json::from_str(&p).ok()).unwrap_or_default(),
            })
        })
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    Ok(rows.into_iter().filter(|q| !q.peer.is_empty()).collect())
}

fn set_state(conn: &Connection, id: &str, state: &str) -> Result<(), StoreError> {
    conn.execute(
        "UPDATE messages SET local_state = ?2 WHERE id = ?1",
        params![id, state],
    )
    .map_err(db_err)?;
    Ok(())
}

/// Gives a person (and their 1:1 conversation) their profile name.
fn set_person_name(conn: &Connection, id: &str, name: &str) -> Result<(), StoreError> {
    conn.execute("UPDATE people SET name = ?2 WHERE id = ?1", params![id, name])
        .map_err(db_err)?;
    conn.execute(
        "UPDATE conversations SET title = ?2 WHERE id = ?1",
        params![format!("dm:{id}"), name],
    )
    .map_err(db_err)?;
    Ok(())
}

/// Makes sure there is an accepted DM conversation (and a person) for `peer`.
pub(crate) fn ensure_dm(
    conn: &Connection,
    peer: &str,
    name: Option<&str>,
) -> Result<String, StoreError> {
    ensure_dm_as(conn, peer, name, "accepted")
}

/// Makes sure there is a DM conversation (and a person) for `peer`; a new one starts in
/// `state_if_new`. Titled with their profile name when known, else their user id until it is.
pub(crate) fn ensure_dm_as(
    conn: &Connection,
    peer: &str,
    name: Option<&str>,
    state_if_new: &str,
) -> Result<String, StoreError> {
    let tone = peer.bytes().fold(0u32, |acc, b| {
        acc.wrapping_mul(31).wrapping_add(u32::from(b))
    }) % 8;
    let shown = name.map(str::trim).filter(|n| !n.is_empty()).unwrap_or(peer);
    conn.execute(
        "INSERT OR IGNORE INTO people (id, name, tone) VALUES (?1, ?2, ?3)",
        params![peer, shown, tone],
    )
    .map_err(db_err)?;
    conn.execute(
        "INSERT OR IGNORE INTO people (id, name, tone) VALUES (?1, 'Me', 4)",
        params![ME_ID],
    )
    .map_err(db_err)?;
    let id = format!("dm:{peer}");
    conn.execute(
        "INSERT OR IGNORE INTO conversations (id, title, is_group, is_pinned, unread, request_state)
         VALUES (?1, ?2, 0, 0, 0, ?3)",
        params![id, shown, state_if_new],
    )
    .map_err(db_err)?;
    if shown != peer {
        set_person_name(conn, peer, shown)?;
    }
    conn.execute(
        "INSERT OR IGNORE INTO members (conversation_id, person_id, position) VALUES (?1, ?2, 0)",
        params![id, peer],
    )
    .map_err(db_err)?;
    conn.execute(
        "INSERT OR IGNORE INTO members (conversation_id, person_id, position) VALUES (?1, ?2, 1)",
        params![id, ME_ID],
    )
    .map_err(db_err)?;
    Ok(id)
}

/// One call to an Edge Function. `token` is the user's access token (None for the sealed path).
fn call(
    transport: &Arc<dyn Transport>,
    token: Option<&str>,
    function: &str,
    body: &Value,
) -> Result<(u16, Value), StoreError> {
    let mut headers = vec![HeaderPair {
        name: "content-type".into(),
        value: "application/json".into(),
    }];
    if let Some(token) = token {
        headers.push(HeaderPair {
            name: "authorization".into(),
            value: format!("Bearer {token}"),
        });
    }
    let response = transport
        .request(
            "POST".into(),
            format!("/functions/v1/{function}"),
            headers,
            serde_json::to_vec(body).map_err(|_| StoreError::BadMessage)?,
        )
        .map_err(|_: TransportError| StoreError::Network)?;
    let value = if response.body.is_empty() {
        Value::Null
    } else {
        serde_json::from_slice(&response.body).unwrap_or(Value::Null)
    };
    Ok((response.status, value))
}

fn check(status: u16) -> Result<(), StoreError> {
    match status {
        200..=299 => Ok(()),
        500..=599 => Err(StoreError::Unavailable),
        _ => Err(StoreError::Rejected),
    }
}
