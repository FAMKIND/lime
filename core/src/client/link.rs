//! Linking a new device to my account by QR (LIME-341b, DESIGN-M1 D6 = K2). Core only; how the bytes travel is the app's (like Move, LIME-272b).
//!
//! **Pairing = Move's** (`transfer.rs`): the new device shows a QR with a one-time X25519 key, a random 128-bit secret and when it was made; the phone
//! answers with a `hello` only a holder of the secret can make; both derive a session key (HKDF, the secret as salt, over the whole exchange) and show a 6-digit
//! check code; **nothing is sent before the person confirms**. A different QR prefix (`lime-link-v1:`) and a different cipher label keep a Move QR and a Link QR
//! from being taken for each other. A QR works **once** (the phone keeps the hash of every secret it scanned) and for **10 minutes**.
//!
//! **The package** is built inside core on the phone and sealed in the same chunk format as Move (AES-256-GCM, counter nonces, manifest + SHA-256): the delivery
//! key; the master secret **only for a phone or tablet** (a computer gets the phone's certificate for the keys in its QR instead); and plain rows of a short
//! list of tables (`TABLES`): the profile, contacts with pinned master keys, delivery keys and verified marks, one-to-one chats (no messages: LIME-341c),
//! groups with members and their signed ops, blocks (a chat's state), pins, marks, status, emergency settings, and the jams I follow (re-subscribed on arrival,
//! so each writer welcomes the new device itself: no tier keys travel). **Never:** Olm or Megolm sessions, this phone's pickled account or device keys, drafts,
//! contact labels, list or look choices (those live in the app), Bluetooth state. The master secret and the delivery key are never handed to Swift or Kotlin:
//! core reads them itself while building the package.
//!
//! **Applying** (the new device): the whole stream verified first, then ONE transaction: the account (`from_master` for a phone/tablet, or this device's own keys with
//! the phone's certificate for a computer), the delivery key, the rows, the jam subscriptions. Anything wrong rolls it all back: the store stays empty.
//! The app then calls `register_device` and, on **both** devices, `link_refresh_devices`.
//!
//! What each party learns: the server sees nothing of this (no request is made here); the two devices share a QR, a short code and the package over whatever the
//! app uses. Afterwards the server sees one more device row (`register_device`, LIME-341a) and the writers of the jams I follow get a subscribe request.

use std::sync::{Arc, Mutex};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use vodozemac::{base64_decode, base64_encode, Curve25519PublicKey, Curve25519SecretKey};

use super::transfer::{derive, mac, mac_matches, open_chunk, random, seal_chunk, Session, CHUNK, KIND_DATA, KIND_FINAL, KIND_MANIFEST, SECRET_LEN};
use super::*;
use crate::keys::DeviceRequest;
use crate::store::account::{load_account, save_account};

const VERSION: u8 = 1;
const QR_PREFIX: &str = "lime-link-v1:";
const LABEL: &[u8] = b"lime-link-v1";
/// A QR is good for 10 minutes.
const TTL_MS: i64 = 10 * 60 * 1000;
/// The largest package taken (a photo and a few hundred contacts are far below).
const MAX_PACKAGE: u64 = 16 * 1024 * 1024;

/// The history pointer (LIME-341c): sealed in the same session after the package, so the blob id and key never travel in the clear or to the server.
const KIND_HISTORY: u8 = 4;
const KIND_FULL: u8 = 1;

pub(crate) mod history;
const KIND_COMPUTER: u8 = 0;

/// The tables a package fills, in the order they are filled, with the rows taken. Nothing else is ever in it.
pub(crate) const TABLES: &[&str] = &[
    "people",
    "peers",
    "contact_delivery_keys",
    "contact_profile_keys",
    "contact_profile_masters",
    "profile_key",
    "my_photo",
    "my_username",
    "my_status",
    "deleted_peers",
    "conversations",
    "members",
    "group_members",
    "group_ops",
    "emergency_settings",
    "jam_follow_off",
    // The names and kinds of my devices (LIME-342a): a new device knows them from the start.
    "own_device_info",
];

#[derive(Serialize, Deserialize, Default)]
struct Package {
    v: u8,
    user_id: String,
    /// 1: a phone or tablet (has the master secret), 0: a computer.
    kind: u8,
    delivery_key: String,
    master_secret: Option<String>,
    certificate: Option<crate::keys::DeviceCertificate>,
    tables: std::collections::BTreeMap<String, Vec<serde_json::Map<String, Value>>>,
    /// The jams I follow: (jam id, writer). Re-subscribed on the new device.
    jams: Vec<(String, String)>,
}

/// What a finished link says (the app then registers the device and refreshes both devices' lists).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct LinkApplied {
    pub user_id: String,
    /// A computer (no master secret) rather than a phone or tablet.
    pub is_computer: bool,
}

/// How far a link has got, in bytes of the package.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct LinkProgress {
    pub done: u64,
    pub total: u64,
}

#[derive(Serialize, Deserialize)]
struct Manifest {
    v: u8,
    user_id: String,
    kind: u8,
    size: u64,
    chunks: u64,
}

#[derive(Serialize, Deserialize, Default)]
struct QrExtra {
    #[serde(skip_serializing_if = "Option::is_none")]
    user_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    request: Option<DeviceRequest>,
}

struct QrParts {
    kind: u8,
    new_pub: [u8; 32],
    secret: [u8; SECRET_LEN],
    created: i64,
    extra_bytes: Vec<u8>,
    extra: QrExtra,
}

fn encode_qr(kind: u8, new_pub: &[u8; 32], secret: &[u8; SECRET_LEN], created: i64, extra: &QrExtra) -> Result<String, StoreError> {
    let mut payload = vec![VERSION, kind];
    payload.extend_from_slice(new_pub);
    payload.extend_from_slice(secret);
    payload.extend_from_slice(&created.to_be_bytes());
    payload.extend_from_slice(&serde_json::to_vec(extra).map_err(|_| StoreError::BadMessage)?);
    Ok(format!("{QR_PREFIX}{}", base64_encode(payload)))
}

fn decode_qr(qr: &str) -> Result<QrParts, StoreError> {
    let body = qr.strip_prefix(QR_PREFIX).ok_or(StoreError::BadMessage)?;
    let bytes = base64_decode(body).map_err(|_| StoreError::BadMessage)?;
    let fixed = 2 + 32 + SECRET_LEN + 8;
    if bytes.len() < fixed || bytes[0] != VERSION || bytes[1] > KIND_FULL || bytes.len() > 4096 {
        return Err(StoreError::BadMessage);
    }
    let extra_bytes = bytes[fixed..].to_vec();
    Ok(QrParts {
        kind: bytes[1],
        new_pub: bytes[2..34].try_into().map_err(|_| StoreError::BadMessage)?,
        secret: bytes[34..34 + SECRET_LEN].try_into().map_err(|_| StoreError::BadMessage)?,
        created: i64::from_be_bytes(bytes[34 + SECRET_LEN..fixed].try_into().map_err(|_| StoreError::BadMessage)?),
        extra: serde_json::from_slice(&extra_bytes).map_err(|_| StoreError::BadMessage)?,
        extra_bytes,
    })
}

/// What both sides bind into the session: the kind and everything else the QR said (so a changed request or user changes the code).
fn binding(kind: u8, extra_bytes: &[u8]) -> Vec<u8> {
    let mut h = Sha256::new();
    h.update([kind]);
    h.update(extra_bytes);
    h.finalize().to_vec()
}

// ---------------------------------------------------------------------------------------------------- building and applying the package

fn json_of(value: rusqlite::types::ValueRef<'_>) -> Value {
    use rusqlite::types::ValueRef;
    match value {
        ValueRef::Null => Value::Null,
        ValueRef::Integer(i) => json!(i),
        ValueRef::Real(f) => json!(f),
        ValueRef::Text(t) => Value::String(String::from_utf8_lossy(t).into_owned()),
        ValueRef::Blob(b) => json!({ "$b": base64_encode(b) }),
    }
}

fn sql_of(value: &Value) -> rusqlite::types::Value {
    use rusqlite::types::Value as V;
    match value {
        Value::Null => V::Null,
        Value::Bool(b) => V::Integer(i64::from(*b)),
        Value::Number(n) => n.as_i64().map(V::Integer).unwrap_or_else(|| V::Real(n.as_f64().unwrap_or(0.0))),
        Value::String(s) => V::Text(s.clone()),
        Value::Object(o) => o.get("$b").and_then(Value::as_str).and_then(|b| base64_decode(b).ok()).map(V::Blob).unwrap_or(V::Null),
        Value::Array(_) => V::Null,
    }
}

fn columns(conn: &Connection, table: &str) -> Result<Vec<String>, StoreError> {
    let mut stmt = conn.prepare(&format!("PRAGMA table_info({table})")).map_err(db_err)?;
    let names = stmt.query_map([], |r| r.get::<_, String>(1)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(names)
}

fn dump(conn: &Connection, table: &str) -> Result<Vec<serde_json::Map<String, Value>>, StoreError> {
    let cols = columns(conn, table)?;
    let mut stmt = conn.prepare(&format!("SELECT {} FROM {table}", cols.join(", "))).map_err(db_err)?;
    let mut rows = stmt.query([]).map_err(db_err)?;
    let mut out = Vec::new();
    while let Some(row) = rows.next().map_err(db_err)? {
        let mut map = serde_json::Map::new();
        for (i, name) in cols.iter().enumerate() {
            map.insert(name.clone(), json_of(row.get_ref(i).map_err(db_err)?));
        }
        out.push(map);
    }
    Ok(out)
}

fn text_of<'a>(row: &'a serde_json::Map<String, Value>, key: &str) -> &'a str {
    row.get(key).and_then(Value::as_str).unwrap_or("")
}

/// The package, built on the phone. `request` is the computer's keys (for a computer), `full` whether the new device is a phone or tablet.
pub(crate) fn build_package(conn: &Connection, pickle_key: &[u8; 32], full: bool, request: Option<&DeviceRequest>) -> Result<Vec<u8>, StoreError> {
    let state = load_account(conn, pickle_key)?.ok_or(StoreError::NotRegistered)?;
    let user_id = state.user_id.clone().ok_or(StoreError::NotRegistered)?;
    // Only a device that holds the master secret can link another (a computer answers `MasterKeyNotOnDevice`).
    let master = state.master.as_ref().ok_or(StoreError::MasterKeyNotOnDevice)?;
    let (delivery_key, _) = delivery::current(conn, now_ms())?;
    let mut package = Package { v: VERSION, user_id, kind: if full { KIND_FULL } else { KIND_COMPUTER }, delivery_key: base64_encode(&delivery_key), ..Package::default() };
    if full {
        package.master_secret = Some(base64_encode(*master.to_bytes()));
    } else {
        package.certificate = Some(state.certify(request.ok_or(StoreError::BadMessage)?)?);
    }
    for table in TABLES {
        package.tables.insert((*table).to_owned(), dump(conn, table)?);
    }
    // Chats and groups only: not the jams' own conversations, and what belongs to a chat only for the chats that go.
    let keep = |id: &str| id.starts_with("dm:") || crate::store::groups::group_id_of(id).is_some();
    let kept: std::collections::HashSet<String> = package.tables["conversations"].iter().map(|r| text_of(r, "id")).filter(|id| keep(id)).map(str::to_owned).collect();
    package.tables.get_mut("conversations").map(|rows| rows.retain(|r| kept.contains(text_of(r, "id"))));
    package.tables.get_mut("members").map(|rows| rows.retain(|r| kept.contains(text_of(r, "conversation_id"))));
    let groups: std::collections::HashSet<&str> = kept.iter().filter_map(|id| crate::store::groups::group_id_of(id)).collect();
    package.tables.get_mut("group_members").map(|rows| rows.retain(|r| groups.contains(text_of(r, "group_id"))));
    package.tables.get_mut("group_ops").map(|rows| rows.retain(|r| groups.contains(text_of(r, "group_id"))));
    let mut stmt = conn.prepare("SELECT jam_id, writer FROM jams WHERE mine = 0 AND status IN ('active', 'requested')").map_err(db_err)?;
    package.jams = stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    serde_json::to_vec(&package).map_err(|_| StoreError::BadMessage)
}

/// Fills the store from a verified package: all or nothing.
fn apply_package(store: &LimeStore, bytes: &[u8], pending: Option<AccountState>) -> Result<LinkApplied, StoreError> {
    let package: Package = serde_json::from_slice(bytes).map_err(|_| StoreError::BadMessage)?;
    if package.v != VERSION || package.user_id.is_empty() || package.user_id.len() > 80 || package.tables.keys().any(|t| !TABLES.contains(&t.as_str())) {
        return Err(StoreError::BadMessage);
    }
    let delivery_key = base64_decode(&package.delivery_key).map_err(|_| StoreError::BadMessage)?;
    let mut state = match (package.kind, &package.master_secret, &package.certificate, pending) {
        (KIND_FULL, Some(secret), None, None) => AccountState::from_master(&base64_decode(secret).map_err(|_| StoreError::BadMessage)?, &package.user_id)?,
        (KIND_COMPUTER, None, Some(certificate), Some(mut state)) => {
            state.accept_certificate(certificate)?;
            state.user_id = Some(package.user_id.clone());
            state
        }
        _ => return Err(StoreError::BadMessage),
    };
    let now = now_ms();
    let conn = store.lock();
    if load_account(&conn, &store.pickle_key)?.is_some() {
        return Err(StoreError::Rejected);
    }
    conn.execute_batch("BEGIN IMMEDIATE").map_err(db_err)?;
    let result = (|| -> Result<(), StoreError> {
        delivery::install_key(&conn, &delivery_key, now)?;
        for table in TABLES {
            let Some(rows) = package.tables.get(*table) else { continue };
            let known = columns(&conn, table)?;
            for row in rows {
                let cols: Vec<&String> = row.keys().filter(|k| known.contains(k)).collect();
                if cols.is_empty() {
                    continue;
                }
                let sql = format!("INSERT OR REPLACE INTO {table} ({}) VALUES ({})", cols.iter().map(|c| c.as_str()).collect::<Vec<_>>().join(", "), vec!["?"; cols.len()].join(", "));
                let values: Vec<rusqlite::types::Value> = cols.iter().map(|c| sql_of(&row[*c])).collect();
                conn.execute(&sql, rusqlite::params_from_iter(values)).map_err(db_err)?;
            }
        }
        // The chats arrive without their messages: nothing is unread here yet.
        conn.execute("UPDATE conversations SET unread = 0", []).map_err(db_err)?;
        // The account first: following a jam signs an op as this device.
        save_account(&conn, &store.pickle_key, &state)?;
        for (jam_id, writer) in &package.jams {
            if jam_id.is_empty() || jam_id.len() > 64 || writer.is_empty() || *writer == package.user_id {
                return Err(StoreError::BadMessage);
            }
            crate::client::jam::subscribe_in(&conn, &state, jam_id, writer, now)?;
        }
        Ok(())
    })();
    match result {
        Ok(()) => conn.execute_batch("COMMIT").map_err(db_err)?,
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK");
            return Err(e);
        }
    }
    state.registered = false;
    Ok(LinkApplied { user_id: package.user_id, is_computer: package.kind == KIND_COMPUTER })
}

// ---------------------------------------------------------------------------------------------------- the phone

#[derive(PartialEq, Clone, Copy)]
enum Stage {
    Manifest,
    Data,
    Final,
    Done,
}

struct OldState {
    session: Session,
    confirmed: bool,
    counter: u64,
    stage: Stage,
    package: Vec<u8>,
    sent: usize,
    hasher: Sha256,
    full: bool,
    request: Option<DeviceRequest>,
    user_id: String,
    /// The history step has been made (LIME-341c): once.
    history_sent: bool,
    history_progress: history::HistoryProgress,
}

/// The phone's (or tablet's) side of a link: it holds the master secret and gives the new device what it needs.
#[derive(uniffi::Object)]
pub struct LinkOld {
    store: Arc<LimeStore>,
    hello: Vec<u8>,
    state: Mutex<OldState>,
}

#[uniffi::export]
impl LinkOld {
    /// Scans the new device's QR. Refused: a QR that is not a link QR (a Move QR included), one older than 10 minutes, one already scanned, one for another
    /// account, and any device that does not hold the master secret (`MasterKeyNotOnDevice`). Nothing is read or sent yet.
    #[uniffi::constructor]
    pub fn accept(store: Arc<LimeStore>, qr: String) -> Result<Arc<Self>, StoreError> {
        Self::accept_at(store, &qr, now_ms())
    }

    /// The bytes for the new device (its answer to the QR).
    pub fn hello(&self) -> Vec<u8> {
        self.hello.clone()
    }

    /// The 6 digits both devices show; the person confirms they are the same.
    pub fn check_code(&self) -> String {
        self.state().session.code.clone()
    }

    /// The person saw the same code on both devices (and passed Face ID or the passcode: the app's part, LIME-343). Until now nothing is built or sent.
    pub fn confirm_code(&self) {
        self.state().confirmed = true;
    }

    /// The next sealed chunk, or `None` after the last. The first call after the confirmation builds the package.
    pub fn export_next_chunk(&self) -> Result<Option<Vec<u8>>, StoreError> {
        let mut st = self.state();
        if !st.confirmed {
            return Err(StoreError::Rejected);
        }
        let (counter, key) = (st.counter, st.session.data);
        let chunk = match st.stage {
            Stage::Manifest => {
                let package = {
                    let conn = self.store.lock();
                    build_package(&conn, &self.store.pickle_key, st.full, st.request.as_ref())?
                };
                let size = package.len() as u64;
                let manifest = Manifest { v: VERSION, user_id: st.user_id.clone(), kind: if st.full { KIND_FULL } else { KIND_COMPUTER }, size, chunks: size.div_ceil(CHUNK as u64) };
                st.package = package;
                st.stage = if size == 0 { Stage::Final } else { Stage::Data };
                seal_chunk(LABEL, &key, counter, KIND_MANIFEST, &serde_json::to_vec(&manifest).map_err(|_| StoreError::BadMessage)?)?
            }
            Stage::Data => {
                let end = (st.sent + CHUNK).min(st.package.len());
                let piece = st.package[st.sent..end].to_vec();
                st.hasher.update(&piece);
                st.sent = end;
                if end >= st.package.len() {
                    st.stage = Stage::Final;
                }
                seal_chunk(LABEL, &key, counter, KIND_DATA, &piece)?
            }
            Stage::Final => {
                let digest = st.hasher.clone().finalize();
                st.stage = Stage::Done;
                seal_chunk(LABEL, &key, counter, KIND_FINAL, &digest)?
            }
            Stage::Done => {
                st.package.clear();
                return Ok(None);
            }
        };
        st.counter += 1;
        Ok(Some(chunk))
    }

    pub fn progress(&self) -> LinkProgress {
        let st = self.state();
        LinkProgress { done: st.sent as u64, total: st.package.len() as u64 }
    }

    /// Stops the link; nothing was changed on this device.
    pub fn abort(&self) {
        let mut st = self.state();
        st.package.clear();
        st.stage = Stage::Done;
        st.confirmed = false;
    }
}

impl LinkOld {
    fn state(&self) -> std::sync::MutexGuard<'_, OldState> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    pub(crate) fn accept_at(store: Arc<LimeStore>, qr: &str, now: i64) -> Result<Arc<Self>, StoreError> {
        let parts = decode_qr(qr)?;
        if now - parts.created > TTL_MS || parts.created - now > 2 * 60 * 1000 {
            return Err(StoreError::Rejected);
        }
        let mine = store.with_conn(|conn| load_account(conn, &store.pickle_key))?.ok_or(StoreError::NotRegistered)?;
        let user_id = mine.user_id.clone().ok_or(StoreError::NotRegistered)?;
        if mine.master.is_none() {
            return Err(StoreError::MasterKeyNotOnDevice);
        }
        if parts.extra.user_id.as_ref().is_some_and(|id| *id != user_id) || (parts.kind == KIND_COMPUTER) != parts.extra.request.is_some() {
            return Err(StoreError::Rejected);
        }
        // One time: the secret's hash is kept (a second scan of the same QR fails).
        let hash = base64_encode(Sha256::digest(parts.secret));
        store.with_conn(|conn| {
            conn.execute("INSERT INTO link_used (secret_hash, used_at) VALUES (?1, ?2)", params![hash, now]).map(|_| ()).map_err(|_| StoreError::Rejected)
        })?;
        let ours = Curve25519SecretKey::new();
        let old_pub = Curve25519PublicKey::from(&ours).to_bytes();
        let (session, hello_key) = derive(LABEL, &ours, &parts.new_pub, &parts.secret, &parts.new_pub, &old_pub, &binding(parts.kind, &parts.extra_bytes))?;
        let mut hello = old_pub.to_vec();
        hello.extend_from_slice(&mac(&hello_key, &[&old_pub, &parts.new_pub])?);
        Ok(Arc::new(Self {
            store,
            hello,
            state: Mutex::new(OldState {
                session,
                confirmed: false,
                counter: 0,
                stage: Stage::Manifest,
                package: Vec::new(),
                sent: 0,
                hasher: Sha256::new(),
                full: parts.kind == KIND_FULL,
                request: parts.extra.request,
                user_id,
                history_sent: false,
                history_progress: history::HistoryProgress::idle(),
            }),
        }))
    }
}

// ---------------------------------------------------------------------------------------------------- the new device

struct NewState {
    secret: [u8; SECRET_LEN],
    ours: Curve25519SecretKey,
    session: Option<Session>,
    confirmed: bool,
    manifest: Option<Manifest>,
    counter: u64,
    data: Vec<u8>,
    data_chunks: u64,
    hasher: Sha256,
    digest: Option<[u8; 32]>,
    /// A computer's own keys, kept here (not in the store) until the package is applied.
    pending: Option<AccountState>,
    applied: bool,
    failed: bool,
    /// Where the last 45 days of history wait on the server and how to open them (LIME-341c); arrives after the package.
    history: Option<history::Pointer>,
    /// Progress of the history step (this device's side).
    history_progress: history::HistoryProgress,
}

/// The new device's side of a link: a computer, tablet or phone with an empty store.
#[derive(uniffi::Object)]
pub struct LinkNew {
    store: Arc<LimeStore>,
    user_id: Option<String>,
    kind: u8,
    created: i64,
    extra_bytes: Vec<u8>,
    qr: String,
    state: Mutex<NewState>,
}

#[uniffi::export]
impl LinkNew {
    /// Starts a link on a device whose store is empty: a computer (`is_computer`: it makes its own device keys and puts them in the QR for the phone to certify)
    /// or a phone or tablet. `user_id` is the account if the person already typed or knows it, else the phone's answer says.
    #[uniffi::constructor]
    pub fn offer(store: Arc<LimeStore>, is_computer: bool, user_id: Option<String>) -> Result<Arc<Self>, StoreError> {
        Self::offer_at(store, is_computer, user_id, now_ms())
    }

    /// The text for the QR code.
    pub fn qr(&self) -> String {
        self.qr.clone()
    }

    /// The phone's answer. Refused unless it was made with this QR's secret, once, and within 10 minutes of the QR.
    pub fn accept_hello(&self, hello: Vec<u8>) -> Result<(), StoreError> {
        let mut st = self.state();
        if st.session.is_some() || hello.len() != 64 || now_ms() - self.created > TTL_MS {
            return Err(StoreError::BadMessage);
        }
        let old_pub: [u8; 32] = hello[..32].try_into().map_err(|_| StoreError::BadMessage)?;
        let new_pub = Curve25519PublicKey::from(&st.ours).to_bytes();
        let (session, hello_key) = derive(LABEL, &st.ours, &old_pub, &st.secret, &new_pub, &old_pub, &binding(self.kind, &self.extra_bytes))?;
        if !mac_matches(&hello_key, &[&old_pub, &new_pub], &hello[32..])? {
            return Err(StoreError::BadMessage);
        }
        st.session = Some(session);
        Ok(())
    }

    /// The 6 digits both devices show (after the hello).
    pub fn check_code(&self) -> Result<String, StoreError> {
        self.state().session.as_ref().map(|s| s.code.clone()).ok_or(StoreError::Rejected)
    }

    /// The person saw the same code on both devices. Until now no chunk is accepted.
    pub fn confirm_code(&self) {
        self.state().confirmed = true;
    }

    /// Takes the next chunk, in order. Any failure discards everything received; start again from a new QR.
    pub fn import_chunk(&self, chunk: Vec<u8>) -> Result<(), StoreError> {
        let mut st = self.state();
        let result = self.take_chunk(&mut st, &chunk);
        if result.is_err() {
            st.failed = true;
            st.data.clear();
        }
        result
    }

    pub fn progress(&self) -> LinkProgress {
        let st = self.state();
        LinkProgress { done: st.data.len() as u64, total: st.manifest.as_ref().map(|m| m.size).unwrap_or(0) }
    }

    /// Checks the whole stream and applies the package in one transaction. On any failure the store is left empty. The app then calls `register_device` and, on
    /// both devices, `link_refresh_devices`.
    pub fn import_finish(&self) -> Result<LinkApplied, StoreError> {
        let mut st = self.state();
        if st.failed || st.applied || st.digest.is_none() {
            return Err(StoreError::BadMessage);
        }
        let pending = st.pending.take();
        let result = apply_package(&self.store, &st.data, pending).and_then(|applied| {
            if self.user_id.as_ref().is_some_and(|id| *id != applied.user_id) {
                Err(StoreError::BadMessage)
            } else {
                Ok(applied)
            }
        });
        match &result {
            Ok(_) => st.applied = true,
            Err(_) => st.failed = true,
        }
        result
    }

    /// Stops the link; nothing was kept.
    pub fn abort(&self) {
        let mut st = self.state();
        st.failed = true;
        st.data.clear();
    }
}

impl LinkNew {
    fn state(&self) -> std::sync::MutexGuard<'_, NewState> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    pub(crate) fn offer_at(store: Arc<LimeStore>, is_computer: bool, user_id: Option<String>, created: i64) -> Result<Arc<Self>, StoreError> {
        if store.with_conn(|conn| Ok(load_account(conn, &store.pickle_key)?.is_some()))? {
            return Err(StoreError::Rejected);
        }
        let kind = if is_computer { KIND_COMPUTER } else { KIND_FULL };
        let pending = is_computer.then(|| AccountState::device_only(user_id.as_deref().unwrap_or("")));
        let extra = QrExtra { user_id: user_id.clone(), request: pending.as_ref().map(AccountState::request) };
        let ours = Curve25519SecretKey::new();
        let secret = random::<SECRET_LEN>()?;
        let qr = encode_qr(kind, &Curve25519PublicKey::from(&ours).to_bytes(), &secret, created, &extra)?;
        let extra_bytes = serde_json::to_vec(&extra).map_err(|_| StoreError::BadMessage)?;
        Ok(Arc::new(Self {
            store,
            user_id,
            kind,
            created,
            extra_bytes,
            qr,
            state: Mutex::new(NewState { secret, ours, session: None, confirmed: false, manifest: None, counter: 0, data: Vec::new(), data_chunks: 0, hasher: Sha256::new(), digest: None, pending, applied: false, failed: false, history: None, history_progress: history::HistoryProgress::idle() }),
        }))
    }

    fn take_chunk(&self, st: &mut NewState, chunk: &[u8]) -> Result<(), StoreError> {
        if st.failed || !st.confirmed {
            return Err(StoreError::Rejected);
        }
        let key = st.session.as_ref().ok_or(StoreError::Rejected)?.data;
        let (kind, payload) = open_chunk(LABEL, &key, st.counter, chunk)?;
        // Once the package is applied only the history pointer may still come (LIME-341c).
        if st.applied && kind != KIND_HISTORY {
            return Err(StoreError::Rejected);
        }
        match (st.counter, kind) {
            (n, KIND_HISTORY) if n > 0 && st.digest.is_some() && st.history.is_none() => {
                st.history = Some(history::Pointer::from_bytes(&payload)?);
            }
            (0, KIND_MANIFEST) => {
                let manifest: Manifest = serde_json::from_slice(&payload).map_err(|_| StoreError::BadMessage)?;
                if manifest.v != VERSION || manifest.kind != self.kind || manifest.size > MAX_PACKAGE || manifest.chunks != manifest.size.div_ceil(CHUNK as u64) || self.user_id.as_ref().is_some_and(|id| *id != manifest.user_id) {
                    return Err(StoreError::BadMessage);
                }
                st.manifest = Some(manifest);
            }
            (n, KIND_DATA) if n > 0 => {
                let manifest = st.manifest.as_ref().ok_or(StoreError::BadMessage)?;
                if payload.len() > CHUNK || st.data.len() as u64 + payload.len() as u64 > manifest.size || st.data_chunks >= manifest.chunks {
                    return Err(StoreError::BadMessage);
                }
                st.hasher.update(&payload);
                st.data.extend_from_slice(&payload);
                st.data_chunks += 1;
            }
            (n, KIND_FINAL) if n > 0 => {
                let digest: [u8; 32] = payload.try_into().map_err(|_| StoreError::BadMessage)?;
                let manifest = st.manifest.as_ref().ok_or(StoreError::BadMessage)?;
                if st.data.len() as u64 != manifest.size || st.data_chunks != manifest.chunks || st.hasher.clone().finalize().as_slice() != digest {
                    return Err(StoreError::BadMessage);
                }
                st.digest = Some(digest);
            }
            _ => return Err(StoreError::BadMessage),
        }
        st.counter += 1;
        Ok(())
    }
}

#[uniffi::export]
impl LimeStore {
    /// After `register_device` (and on the phone too): asks the server for this account's devices and keeps those the master key vouches for, so my devices can
    /// send each other copies. Returns how many devices the account has.
    pub fn link_refresh_devices(&self, transport: Arc<dyn Transport>, auth_token: String) -> Result<u32, StoreError> {
        let state = self.with_conn(|conn| load_account(conn, &self.pickle_key))?.ok_or(StoreError::NotRegistered)?;
        let me = state.user_id.clone().ok_or(StoreError::NotRegistered)?;
        let _guard = self.protocol_lock.lock().unwrap_or_else(|e| e.into_inner());
        Ok(self.refresh_own_devices(&transport, &auth_token, &state, &me)? as u32)
    }
}
