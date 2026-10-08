//! The API v2 client: register this device, look people up, send an identified Olm message, and
//! sync (fetch, decrypt, store, acknowledge). The protocol lives here; the network is the
//! platform's [`Transport`]. Auth tokens are passed in per call and never stored.
//!
//! Scope so far: 1:1 chats over Olm (no Megolm or groups yet), with message requests, key changes,
//! threads and, since LIME-96, **sealed sender** for contacts who shared their delivery key with us
//! (`store::delivery`). The op's `payload` is a plain `{ "text": ... }` inside the Olm ciphertext
//! until Megolm lands.

use std::sync::Arc;

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{json, Value};
use vodozemac::olm::{OlmMessage, SessionConfig};
use vodozemac::Curve25519PublicKey;

use crate::keys::AccountState;
use crate::protocol::{dm_conversation_id, Hlc, Op, SealedInner, SenderCert};
use crate::store::account::{
    load_account, load_all_sessions, load_sessions, observe_hlc, pin_master_key, save_account, save_session, tick_hlc,
};
use crate::store::delivery;
use crate::store::order;
use crate::store::pending::{self, Fetched, PendingRow};
use crate::store::{db_err, new_id, now_ms, LimeStore, MessageItem, StoreError, ME_ID};
use crate::transport::{HeaderPair, Transport, TransportError};

/// The upload size of the one-time-key pool, and when to top it up (`api-v2.md` section 11).
const POOL_SIZE: usize = 50;
const POOL_LOW: u32 = 20;
/// A text message must fit in a 64 KB mailbox item once wrapped and encrypted.
const MAX_TEXT_BYTES: usize = 30_000;
pub(crate) mod groups;

/// The control op that gives a contact my delivery key (`api-v2.md` section 4).
const DELIVERY_KEY_SHARE: &str = "delivery_key.share";

/// Why one send did not go through.
enum SendError {
    /// A sealed send was refused (403): the recipient's delivery key is not the one we hold.
    Denied,
    Store(StoreError),
}

impl From<StoreError> for SendError {
    fn from(error: StoreError) -> Self {
        SendError::Store(error)
    }
}

impl SendError {
    fn into_store(self) -> StoreError {
        match self {
            SendError::Denied => StoreError::Rejected,
            SendError::Store(error) => error,
        }
    }
}

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
        // The delivery key (made here the first time) and its hash on the server. If this fails now it is
        // tried again before the next send.
        let _ = self.ensure_delivery_access(&transport, &auth_token);
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
        self.queue(conversation_id, text, None)
    }

    /// Writes a reply in the thread of `root_id` (a message of this conversation). Replying to a reply
    /// answers the same root. Like [`LimeStore::queue_text`] it is `sending` until delivered.
    pub fn queue_reply(
        &self,
        conversation_id: String,
        root_id: String,
        text: String,
    ) -> Result<MessageItem, StoreError> {
        self.queue(conversation_id, text, Some(root_id))
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
        // My delivery key's hash has to be on the server before anyone is given the key: then the people
        // who hold it can send sealed. Both are best effort here; they are tried again next time.
        if self.ensure_delivery_access(&transport, &auth_token).is_ok() {
            self.deliver_shares(&transport, &auth_token, &mut state, &me);
        }
        // Group state ops (a new group, someone added or removed...) go out before the messages that follow them.
        self.deliver_group_outbox(&transport, &auth_token, &mut state, &me);
        let queued = self.with_conn(queued_messages)?;
        let mut sent = 0;
        for message in queued {
            if message.conversation_id.starts_with("grp:") {
                match self.deliver_group_message(&transport, &auth_token, &mut state, &me, &message) {
                    Ok(()) => {
                        self.with_conn(|conn| set_state(conn, &message.id, "sent"))?;
                        sent += 1;
                    }
                    Err(error) => {
                        self.with_conn(|conn| set_state(conn, &message.id, "failed"))?;
                        return Err(error);
                    }
                }
                continue;
            }
            // Sealed when the contact shared their key and has not refused it; identified otherwise.
            let contact = self.with_conn(|conn| delivery::contact_key(conn, &message.peer))?;
            let sealed_key = contact.and_then(|(key, denied)| (!denied).then_some(key));
            let mut outcome = self.deliver_one(&transport, &auth_token, &mut state, &me, &message, sealed_key);
            if matches!(outcome, Err(SendError::Denied)) {
                // The contact's delivery key is no longer the one we hold (they blocked us, or replaced their
                // keys). Like Signal, say nothing: stop using sealed for them until they share a new key, send
                // this message identified straight away (once), and show "Sent". A person who blocked us learns
                // nothing, and one who changed phones still gets it.
                self.with_conn(|conn| delivery::mark_denied(conn, &message.peer))?;
                outcome = self.deliver_one(&transport, &auth_token, &mut state, &me, &message, None);
            }
            match outcome {
                Ok(()) => {
                    self.with_conn(|conn| set_state(conn, &message.id, "sent"))?;
                    sent += 1;
                }
                Err(error) => {
                    self.with_conn(|conn| set_state(conn, &message.id, "failed"))?;
                    return Err(error.into_store());
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

        // The delivery key's hash may still be waiting to go up (a block rotated it): send it, then the shares.
        if self.ensure_delivery_access(&transport, &auth_token).is_ok() {
            self.deliver_shares(&transport, &auth_token, &mut state, &me);
        }
        // Turn what is waiting into messages (and retry what failed before). A new session can make
        // an earlier item readable, so go round again while anything makes progress.
        let received = self.retry_pending(&mut state, &me)?;
        if received > 0 {
            self.refresh_names(&transport, &auth_token);
        }
        self.take_undelivered(&transport, &auth_token);
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
    /// The About line: an optional leading emoji, then a few words.
    pub about_emoji: Option<String>,
    pub about_text: Option<String>,
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
        about_emoji: text("about_emoji"),
        about_text: text("about_text"),
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
    fn queue(
        &self,
        conversation_id: String,
        text: String,
        reply_to: Option<String>,
    ) -> Result<MessageItem, StoreError> {
        // What is stored and sent is the one written form: unknown syntax downgraded to text.
        let normalised = crate::format::normalise(&text);
        let body = normalised.as_str();
        if body.is_empty() {
            return Err(StoreError::EmptyMessage);
        }
        if body.len() > MAX_TEXT_BYTES {
            return Err(StoreError::Rejected);
        }
        let plain = crate::format::plain_text(body);
        if conversation_id.strip_prefix("dm:").is_none() && crate::store::groups::group_id_of(&conversation_id).is_none() {
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
                    "SELECT EXISTS (SELECT 1 FROM conversations WHERE id = ?1 AND request_state NOT IN ('blocked', 'left'))",
                    params![conversation_id],
                    |r| r.get(0),
                )
                .map_err(db_err)?;
            if !visible {
                return Err(StoreError::NotFound);
            }
            // A reply hangs from a message of this conversation that is not itself a reply.
            let root = match &reply_to {
                None => None,
                Some(id) => Some(resolve_root(conn, &conversation_id, id)?.ok_or(StoreError::NotFound)?),
            };
            let hlc = tick_hlc(conn, now)?;
            let parents = match &root {
                Some(root) => order::thread_heads(conn, root)?,
                None => order::heads(conn, &conversation_id)?,
            };
            let op_id = new_id();
            conn.execute(
                "INSERT INTO messages (id, conversation_id, sender_id, body, sent_at, local_state, op_id, hlc, parents, plain, thread_root)
                 VALUES (?1, ?2, ?3, ?4, ?5, 'sending', ?1, ?6, ?7, ?8, ?9)",
                params![op_id, conversation_id, ME_ID, body, now, hlc.render(), json!(parents).to_string(), plain, root],
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

    pub(crate) fn load_or_create_account(&self) -> Result<AccountState, StoreError> {
        if let Some(state) = self.with_conn(|conn| load_account(conn, &self.pickle_key))? {
            return Ok(state);
        }
        let state = AccountState::create();
        self.save(&state)?;
        Ok(state)
    }

    /// Sends one queued message to every device of its recipient: sealed when the recipient shared their
    /// delivery key with us (`contact_key`), identified otherwise.
    fn deliver_one(
        &self,
        transport: &Arc<dyn Transport>,
        token: &str,
        state: &mut AccountState,
        me: &str,
        message: &Queued,
        contact_key: Option<Vec<u8>>,
    ) -> Result<(), SendError> {
        let recipient = message.peer.as_str();
        let mut op = Op {
            op_id: message.id.clone(),
            op_type: "message.send".into(),
            conversation_id: dm_conversation_id(me, recipient),
            hlc: message.hlc.clone(),
            parents: message.parents.clone(),
            // `thread_root` is part of the encrypted payload: the server never sees which message a reply answers.
            payload: match &message.thread_root {
                Some(root) => json!({ "text": message.text, "thread_root": root }),
                None => json!({ "text": message.text }),
            },
            sig: String::new(),
        };
        op.sig = state.account.sign(op.signing_bytes()).to_base64();
        let hashes = self.send_op(transport, token, state, me, recipient, op, contact_key.as_deref())?;
        self.with_conn(|conn| {
            for hash in &hashes {
                conn.execute(
                    "INSERT OR REPLACE INTO message_deliveries (hash, message_id) VALUES (?1, ?2)",
                    params![hash, message.id],
                )
                .map_err(db_err)?;
            }
            Ok(())
        })?;
        Ok(())
    }

    /// Wraps a signed op with this device's certificate, encrypts it for each of the recipient's devices
    /// and sends it: **sealed** (no user token; `access` is the access key made from the recipient's
    /// delivery key) when `delivery_key` is given, **identified** otherwise. Returns the hashes of what was
    /// sent. A sealed send the server refuses (403) is `SendError::Denied`: the recipient rotated their key.
    #[allow(clippy::too_many_arguments)] // the call's context (network, caller, keys) and the op
    fn send_op(
        &self,
        transport: &Arc<dyn Transport>,
        token: &str,
        state: &mut AccountState,
        me: &str,
        recipient: &str,
        op: Op,
        delivery_key: Option<&[u8]>,
    ) -> Result<Vec<String>, SendError> {
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
            return Err(StoreError::NoRecipientKeys.into());
        }

        // 3. The signed op, wrapped with this device's certificate.
        let inner = SealedInner {
            sender_user: me.to_owned(),
            sender_device: state.device_id.clone(),
            sender_cert: state.cert(),
            op,
        }
        .to_bytes();

        // 4. One Olm ciphertext per recipient device.
        let mut updated = Vec::new();
        let mut hashes = Vec::new();
        for (device, mut session) in sessions {
            let encrypted = session
                .encrypt(&inner)
                .map_err(|_| StoreError::BadMessage)?;
            let (kind, bytes) = encrypted.to_parts();
            let mut wire = vec![kind as u8];
            wire.extend_from_slice(&bytes);
            hashes.push(hex_sha256(&wire));
            let (status, _) = match delivery_key {
                // Sealed: no Authorization header at all, so the request carries nothing about the sender.
                Some(key) => call(
                    transport,
                    None,
                    "send",
                    &json!({
                        "ciphertext": vodozemac::base64_encode(&wire),
                        "recipients": [{ "to_device": device.device_id, "access": { "sealed": delivery::access_key_b64(key) } }],
                    }),
                )?,
                None => call(
                    transport,
                    Some(token),
                    "send",
                    &json!({
                        "ciphertext": vodozemac::base64_encode(&wire),
                        "recipients": [{ "to_device": device.device_id, "access": { "identified": true } }],
                    }),
                )?,
            };
            if delivery_key.is_some() && status == 403 {
                return Err(SendError::Denied);
            }
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
        })?;
        Ok(hashes)
    }

    // ------------------------------------------------------------ the delivery key

    /// Puts the hash of my delivery key on the server if it is not there (the first time, or after a block
    /// rotated it).
    fn ensure_delivery_access(&self, transport: &Arc<dyn Transport>, token: &str) -> Result<(), StoreError> {
        let (key, uploaded) = self.with_conn(|conn| delivery::current(conn, now_ms()))?;
        if uploaded {
            return Ok(());
        }
        let (status, _) = call(
            transport,
            Some(token),
            "delivery-access-set",
            &json!({ "access_key_hash": delivery::access_hash_b64(&key) }),
        )?;
        check(status)?;
        self.with_conn(|conn| delivery::mark_uploaded(conn, &key))
    }

    /// Sends my current delivery key to everyone queued (Accept, a chat I started, Unblock, a rotation).
    /// Errors leave the person queued; a message is never held up by this.
    fn deliver_shares(&self, transport: &Arc<dyn Transport>, token: &str, state: &mut AccountState, me: &str) {
        let Ok(peers) = self.with_conn(delivery::queued_shares) else { return };
        for peer in peers {
            match self.share_key_with(transport, token, state, me, &peer) {
                Ok(()) => {
                    let _ = self.with_conn(|conn| {
                        delivery::dequeue_share(conn, &peer)?;
                        delivery::mark_shared(conn, &peer, now_ms())
                    });
                }
                // Their keys changed (a key change waits to be accepted), or they cannot be reached right
                // now: keep them queued and carry on with the next person.
                Err(_) => continue,
            }
        }
    }

    /// One `delivery_key.share` op to one person, an ordinary encrypted op over the same Olm sessions.
    /// Sealed when they gave us their key (and it was not refused), identified otherwise.
    fn share_key_with(
        &self,
        transport: &Arc<dyn Transport>,
        token: &str,
        state: &mut AccountState,
        me: &str,
        peer: &str,
    ) -> Result<(), StoreError> {
        let now = now_ms();
        let (key, _) = self.with_conn(|conn| delivery::current(conn, now))?;
        let contact = self.with_conn(|conn| delivery::contact_key(conn, peer))?;
        let sealed_with = contact.filter(|(_, denied)| !denied).map(|(k, _)| k);
        let (hlc, parents) = self.with_conn(|conn| Ok((tick_hlc(conn, now)?, Vec::<String>::new())))?;
        let mut op = Op {
            op_id: new_id(),
            op_type: DELIVERY_KEY_SHARE.into(),
            conversation_id: dm_conversation_id(me, peer),
            hlc: hlc.render(),
            parents,
            payload: json!({ "key": vodozemac::base64_encode(&key) }),
            sig: String::new(),
        };
        op.sig = state.account.sign(op.signing_bytes()).to_base64();
        match self.send_op(transport, token, state, me, peer, op.clone(), sealed_with.as_deref()) {
            Ok(_) => Ok(()),
            // Our sealed send was refused: they rotated. Tell them identified (the key is for them).
            Err(SendError::Denied) => {
                self.with_conn(|conn| delivery::mark_denied(conn, peer))?;
                self.send_op(transport, token, state, me, peer, op, None).map(|_| ()).map_err(SendError::into_store)
            }
            Err(SendError::Store(error)) => Err(error),
        }
    }

    /// Asks the server which identified messages of mine were never delivered (the recipient's
    /// devices were replaced, or they expired) and marks them. Best effort.
    fn take_undelivered(&self, transport: &Arc<dyn Transport>, token: &str) {
        let Ok((200, body)) = call(transport, Some(token), "undelivered-take", &json!({})) else {
            return;
        };
        let Some(hashes) = body.get("hashes").and_then(Value::as_array) else {
            return;
        };
        for hash in hashes.iter().filter_map(Value::as_str) {
            let _ = self.with_conn(|conn| {
                conn.execute(
                    "UPDATE messages SET local_state = 'undelivered'
                     WHERE local_state = 'sent' AND id = (SELECT message_id FROM message_deliveries WHERE hash = ?1)",
                    params![hash],
                )
                .map_err(db_err)?;
                conn.execute("DELETE FROM message_deliveries WHERE hash = ?1", params![hash])
                    .map_err(db_err)?;
                Ok(())
            });
        }
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
        self.with_conn(|conn| match pin_master_key(conn, user_id, master) {
            Err(StoreError::KeyMismatch) => {
                record_key_change(conn, user_id, master)?;
                Err(StoreError::KeyMismatch)
            }
            other => other,
        })?;
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
    ///
    /// An **identified** item names its sender (the server vouches for it). A **sealed** item does not: the
    /// sender is whoever the decrypted envelope says, and that is believed only when it can be checked: the
    /// envelope's device certificate must chain to the master key **already pinned** for that person (a
    /// sealed message from someone we have not exchanged messages with, or with a different master key, is
    /// kept as invalid and never shown). A person whose keys changed first writes identified, which goes
    /// through the key-change flow.
    fn process_item(
        &self,
        state: &mut AccountState,
        me: &str,
        row: &PendingRow,
    ) -> Result<Outcome, StoreError> {
        let sealed = !row.identified;
        // Identified: who the server says. Sealed: unknown until the envelope is decrypted.
        let known_sender: Option<String> = if sealed {
            None
        } else {
            match row.sender_user.clone() {
                Some(sender) if sender != me => Some(sender),
                _ => return Ok(Outcome::Keep(pending::INVALID)),
            }
        };
        let Ok(wire) = vodozemac::base64_decode(&row.ciphertext) else {
            return Ok(Outcome::Keep(pending::INVALID));
        };
        let Some((kind, rest)) = wire.split_first() else {
            return Ok(Outcome::Keep(pending::INVALID));
        };
        if *kind == groups::GROUP_WIRE {
            // A group message: one Megolm ciphertext shared by every member (the first byte tells it from Olm).
            return self.process_group_message(me, rest, now_ms());
        }
        let Ok(message) = OlmMessage::from_parts(*kind as usize, rest) else {
            return Ok(Outcome::Keep(pending::INVALID));
        };

        let now = now_ms();
        // The sessions that could have made this item: the sender's, or (sealed) everyone's.
        let sessions: Vec<(String, crate::store::account::StoredSession)> = match &known_sender {
            Some(sender) => self
                .with_conn(|conn| load_sessions(conn, &self.pickle_key, sender))?
                .into_iter()
                .map(|s| (sender.clone(), s))
                .collect(),
            None => self.with_conn(|conn| load_all_sessions(conn, &self.pickle_key))?,
        };

        // Decrypt with an existing session, or (for a pre-key message) start one.
        let mut session_owner: Option<String> = known_sender.clone();
        let decrypted = 'decrypt: {
            // Held back earlier for a changed key: it is already decrypted.
            if let (Some(plain), Some(identity)) = (&row.plaintext, &row.peer_identity) {
                break 'decrypt Some((plain.clone(), None, identity.clone()));
            }
            for (owner, mut stored) in sessions {
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
                    session_owner = Some(owner);
                    break 'decrypt Some((plaintext, Some(stored.session), stored.peer_identity_key));
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
                    Some((created.plaintext, Some(created.session), identity.to_base64()))
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
        // The sender: the server's word (identified), or the envelope's (sealed, checked below).
        let sender = known_sender.clone().unwrap_or_else(|| inner.sender_user.clone());
        let is_control = inner.op.op_type == DELIVERY_KEY_SHARE;
        let is_group_op = inner.op.op_type.starts_with("group.");
        let valid = sender != me
            && inner.sender_user == sender
            && inner.sender_device == cert.device_id
            && cert.identity_key == peer_identity
            && cert.verify()
            && inner.op.verify(&cert.signing_key)
            && (inner.op.op_type == "message.send" || is_control || is_group_op)
            && if is_group_op {
                // A group op belongs to a group conversation, whose id (a create op's own id) is the group's.
                crate::store::groups::group_id_of(&inner.op.conversation_id).is_some()
            } else {
                inner.op.conversation_id == dm_conversation_id(&sender, me)
            }
            // A sealed item decrypted by someone's existing session is that person's.
            && (!sealed || session_owner.as_ref().is_none_or(|owner| *owner == sender));
        let control_key = is_control
            .then(|| inner.op.payload.get("key").and_then(Value::as_str).and_then(|k| vodozemac::base64_decode(k).ok()))
            .flatten()
            .filter(|k| k.len() == 32);
        let text = inner
            .op
            .payload
            .get("text")
            .and_then(Value::as_str)
            .map(str::to_owned);
        let remote_hlc = Hlc::parse(&inner.op.hlc);
        let Some(remote_hlc) = remote_hlc.filter(|_| valid) else {
            return Ok(Outcome::Keep(pending::INVALID));
        };
        if is_control && control_key.is_none() {
            return Ok(Outcome::Keep(pending::INVALID));
        }
        if !is_control && !is_group_op && text.is_none() {
            return Ok(Outcome::Keep(pending::INVALID));
        }
        if sealed {
            // Only a person we already know, with the master key we pinned for them.
            let pinned: Option<String> = self.with_conn(|conn| {
                conn.query_row("SELECT master_key FROM peers WHERE user_id = ?1", params![sender], |r| r.get(0))
                    .optional()
                    .map_err(db_err)
            })?;
            if pinned.as_deref() != Some(cert.master_key.as_str()) {
                return Ok(Outcome::Keep(pending::INVALID));
            }
        }

        // Whatever the sender wrote, what is kept is the one written form (and its plain words).
        let text = crate::format::normalise(&text.unwrap_or_default());
        if !is_control && !is_group_op && text.is_empty() {
            return Ok(Outcome::Keep(pending::INVALID));
        }
        let plain = crate::format::plain_text(&text);
        // A reply names the message it answers, inside the encrypted payload.
        let claimed_root = inner
            .op
            .payload
            .get("thread_root")
            .and_then(Value::as_str)
            .filter(|id| !id.is_empty() && id.len() <= 64 && *id != inner.op.op_id)
            .map(str::to_owned);
        let parents = json!(inner.op.parents).to_string();
        let stored = self.with_conn(|conn| {
            // The session is kept even when the key is not trusted: a pre-key message cannot be read a
            // second time (its one-time key is spent), and it must be readable once the key is accepted.
            if let Some(session) = &session {
                save_session(conn, &self.pickle_key, &sender, &cert.device_id, &peer_identity, session, now)?;
            }
            if pin_master_key(conn, &sender, &cert.master_key) == Err(StoreError::KeyMismatch) {
                record_key_change(conn, &sender, &cert.master_key)?;
                return Ok(None);
            }
            if is_group_op {
                // A group state op, a group's history for someone just added, or a Megolm session key.
                self.apply_group_op(conn, me, &sender, &inner, cert, now)?;
                return Ok(Some(Stored::Control));
            }
            if let Some(key) = &control_key {
                // A contact's delivery key: kept for sealed sends to them. No conversation, nothing shown.
                delivery::store_contact_key(conn, &sender, key, now)?;
                return Ok(Some(Stored::Control));
            }
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
                return Ok(Some(Stored::Message(false)));
            }
            // A person we did not start a chat with is a request until accepted.
            ensure_dm_as(conn, &sender, None, "pending")?;
            let inserted = insert_received_message(
                conn, &conversation, &sender, &inner.op.op_id, &inner.op.hlc, &parents, &text, &plain, claimed_root.as_deref(), now,
                remote_hlc.wall,
            )?;
            Ok(Some(Stored::Message(inserted)))
        })?;
        let Some(stored) = stored else {
            self.with_conn(|conn| pending::stash_plaintext(conn, row.id, &plaintext, &peer_identity))?;
            return Ok(Outcome::Keep(pending::KEY_MISMATCH));
        };
        self.with_conn(|conn| observe_hlc(conn, remote_hlc, now).map(|_| ()))?;
        Ok(match stored {
            Stored::Message(true) => Outcome::Stored,
            Stored::Message(false) => Outcome::Duplicate,
            // A control op is done with and is not a message.
            Stored::Control => Outcome::Duplicate,
        })
    }
}

/// Stores a message that arrived (1:1 or group) into `conversation`, counting it as unread. A reply names the message
/// it answers; replying to a reply answers the same root, and a root that has not arrived yet is taken as named.
/// The display time is never in the future (`api-v2.md` section 5). `true` when it was new.
#[allow(clippy::too_many_arguments)]
fn insert_received_message(
    conn: &Connection,
    conversation: &str,
    sender: &str,
    op_id: &str,
    hlc: &str,
    parents: &str,
    text: &str,
    plain: &str,
    claimed_root: Option<&str>,
    now: i64,
    remote_wall: i64,
) -> Result<bool, StoreError> {
    let root = match claimed_root {
        None => None,
        Some(id) => Some(resolve_root(conn, conversation, id)?.unwrap_or_else(|| id.to_owned())),
    };
    let shown = remote_wall.min(now);
    let inserted = conn
        .execute(
            "INSERT OR IGNORE INTO messages (id, conversation_id, sender_id, body, sent_at, local_state, op_id, hlc, parents, plain, thread_root)
             VALUES (?1, ?2, ?3, ?4, ?5, 'received', ?1, ?6, ?7, ?8, ?9)",
            params![op_id, conversation, sender, text, shown, hlc, parents, plain, root],
        )
        .map_err(db_err)?;
    if inserted > 0 {
        conn.execute("UPDATE conversations SET unread = unread + 1 WHERE id = ?1", params![conversation]).map_err(db_err)?;
        if let Some(root) = &root {
            conn.execute(
                "INSERT INTO thread_state (root_id, unread) VALUES (?1, 1)
                 ON CONFLICT (root_id) DO UPDATE SET unread = unread + 1",
                params![root],
            )
            .map_err(db_err)?;
        }
    }
    Ok(inserted > 0)
}

/// What storing an item did.
enum Stored {
    Message(bool),
    Control,
}

#[cfg(test)]
impl LimeStore {
    /// Tests only: a sealed item made by this store for `to_user`'s existing session, with `mutate` applied to the
    /// envelope after it is signed (a tampered certificate, a false sender). Returns the base64 wire text.
    pub(crate) fn test_forge_sealed(
        &self,
        to_user: &str,
        text: &str,
        mutate: impl FnOnce(&mut SealedInner),
    ) -> String {
        let state = self.load_or_create_account().unwrap();
        let me = state.user_id.clone().unwrap();
        let hlc = self.with_conn(|conn| tick_hlc(conn, now_ms())).unwrap();
        let mut op = Op {
            op_id: new_id(),
            op_type: "message.send".into(),
            conversation_id: dm_conversation_id(&me, to_user),
            hlc: hlc.render(),
            parents: vec![],
            payload: json!({ "text": text }),
            sig: String::new(),
        };
        op.sig = state.account.sign(op.signing_bytes()).to_base64();
        let mut inner = SealedInner {
            sender_user: me,
            sender_device: state.device_id.clone(),
            sender_cert: state.cert(),
            op,
        };
        mutate(&mut inner);
        let mut stored = self
            .with_conn(|conn| load_sessions(conn, &self.pickle_key, to_user))
            .unwrap()
            .into_iter()
            .next()
            .expect("a session with the recipient");
        let (kind, bytes) = stored.session.encrypt(inner.to_bytes()).unwrap().to_parts();
        let mut wire = vec![kind as u8];
        wire.extend_from_slice(&bytes);
        vodozemac::base64_encode(&wire)
    }

    /// Tests only: this store's delivery key (to compute what the server should hold).
    pub(crate) fn test_delivery_key(&self) -> Vec<u8> {
        self.with_conn(|conn| delivery::current(conn, now_ms())).unwrap().0
    }

    /// Tests only: who is waiting to be sent my delivery key.
    pub(crate) fn test_queued_shares(&self) -> Vec<String> {
        self.with_conn(delivery::queued_shares).unwrap()
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

/// Remembers that `user_id` now presents a different master key than the one we pinned.
fn record_key_change(conn: &Connection, user_id: &str, new_master_key: &str) -> Result<(), StoreError> {
    conn.execute(
        "UPDATE peers SET new_master_key = ?2 WHERE user_id = ?1",
        params![user_id, new_master_key],
    )
    .map_err(db_err)?;
    Ok(())
}

/// Lower-case hex SHA-256, the way the server writes a ciphertext hash.
fn hex_sha256(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    Sha256::digest(bytes).iter().map(|b| format!("{b:02x}")).collect()
}

/// The root a reply to `id` hangs from: `id` itself when it is a message of this conversation that is
/// not a reply, else the root that reply hangs from. `None` when there is no such message here.
pub(crate) fn resolve_root(conn: &Connection, conversation_id: &str, id: &str) -> Result<Option<String>, StoreError> {
    let row: Option<Option<String>> = conn
        .query_row(
            "SELECT thread_root FROM messages WHERE id = ?1 AND conversation_id = ?2",
            params![id, conversation_id],
            |r| r.get(0),
        )
        .optional()
        .map_err(db_err)?;
    Ok(row.map(|root| root.unwrap_or_else(|| id.to_owned())))
}

/// A message of mine waiting to be sent.
struct Queued {
    id: String,
    /// The conversation it belongs to (`dm:<user>` or `grp:<group>`).
    conversation_id: String,
    /// The other person of a 1:1 chat (empty in a group).
    peer: String,
    text: String,
    hlc: String,
    parents: Vec<String>,
    thread_root: Option<String>,
}

fn queued_messages(conn: &Connection) -> Result<Vec<Queued>, StoreError> {
    let mut statement = conn
        .prepare(
            "SELECT id, conversation_id, body, hlc, parents, thread_root FROM messages
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
                conversation_id: conversation,
                text: r.get(2)?,
                hlc: r.get(3)?,
                parents: parents.and_then(|p| serde_json::from_str(&p).ok()).unwrap_or_default(),
                thread_root: r.get(5)?,
            })
        })
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    Ok(rows.into_iter().filter(|q| !q.peer.is_empty() || q.conversation_id.starts_with("grp:")).collect())
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
        401 | 403 => Err(StoreError::Unauthorized),
        429 => Err(StoreError::RateLimited),
        500..=599 => Err(StoreError::Unavailable),
        _ => Err(StoreError::Rejected),
    }
}
