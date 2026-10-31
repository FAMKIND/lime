//! Moving an account to a new phone (LIME-272a): the pairing, the encrypted export and the import. Core only; the bytes travel by
//! whatever the app uses (LIME-272b: a direct connection between the two phones). Nothing here talks to the server.
//!
//! The account lives in one SQLCipher file (identity and device keys, Olm and Megolm sessions, chats, attachments, profile, extras), so the
//! export is a consistent copy of that file plus the key that opens it, and the new phone ends up with the same keys and the same device.
//!
//! Pairing: the new phone shows a QR (`TransferNew::qr`) holding a one-time X25519 public key, a random 128-bit secret and the account's id.
//! The old phone (`TransferOld::accept`) checks the account is its own, makes its own one-time key and answers with a `hello` that only a
//! holder of the secret can make. Both derive the same session key (X25519, then HKDF with the secret as salt over the whole exchange) and
//! both show a 6-digit check code from it; the person confirms the codes match, which stops a swapped QR. The old phone sends nothing
//! before it is confirmed, and the new phone accepts nothing before it is.
//!
//! Stream: chunk 0 is a manifest (sizes and counts, for progress, and the store key), then the data, then a final chunk with the SHA-256 of
//! the data. Every chunk is AES-256-GCM with its counter as the nonce, so a changed, reordered, repeated or dropped chunk fails.
//! The new phone writes a temporary file and keeps nothing unless the whole stream verified and the file opens as this account's store.
//! It then returns a proof; only that proof, from the holder of the session key, lets the old phone remove its copy.

use std::fs::File;
use std::io::{Read, Write};
use std::sync::{Arc, Mutex};

use aes_gcm::aead::{Aead, Payload};
use aes_gcm::{Aes256Gcm, KeyInit as _, Nonce};
use hkdf::Hkdf;
use hmac::{Hmac, KeyInit as _, Mac};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use vodozemac::{base64_decode, base64_encode, Curve25519PublicKey, Curve25519SecretKey};

use crate::store::{db_err, LimeStore, StoreError};

const VERSION: u8 = 1;
/// What a QR starts with, so the app can tell a move from any other code.
const QR_PREFIX: &str = "lime-move1:";
const SECRET_LEN: usize = 16;
/// The plaintext size of a data chunk.
const CHUNK: usize = 256 * 1024;
const LABEL: &[u8] = b"lime-move-v1";

const KIND_MANIFEST: u8 = 0;
const KIND_DATA: u8 = 1;
const KIND_FINAL: u8 = 2;

/// How far a move has got, in bytes of the account's data (for a progress bar).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct MoveProgress {
    pub done: u64,
    pub total: u64,
}

/// What the manifest says about the account being moved (the new phone can show the counts while it waits).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct MoveSummary {
    pub conversations: u64,
    pub messages: u64,
    pub attachments: u64,
    pub total_bytes: u64,
}

#[derive(Serialize, Deserialize)]
struct Manifest {
    v: u8,
    user_id: String,
    device_id: String,
    /// The key that opens the store (base64), so the sessions keep their pickle key and nothing is re-keyed.
    store_key: String,
    db_size: u64,
    chunks: u64,
    conversations: u64,
    messages: u64,
    attachments: u64,
}

/// The keys both phones derive.
struct Session {
    data: [u8; 32],
    ack: [u8; 32],
    code: String,
}

fn hkdf_expand(salt: &[u8], ikm: &[u8], info: &[u8], out: &mut [u8]) -> Result<(), StoreError> {
    Hkdf::<Sha256>::new(Some(salt), ikm).expand(info, out).map_err(|_| StoreError::BadMessage)
}

fn transcript(new_pub: &[u8; 32], old_pub: &[u8; 32], user_id: &str) -> Vec<u8> {
    let mut t = LABEL.to_vec();
    t.extend_from_slice(new_pub);
    t.extend_from_slice(old_pub);
    t.extend_from_slice(user_id.as_bytes());
    t
}

fn with_label(label: &[u8], transcript: &[u8]) -> Vec<u8> {
    let mut info = label.to_vec();
    info.push(0);
    info.extend_from_slice(transcript);
    info
}

fn mac(key: &[u8], parts: &[&[u8]]) -> Result<Vec<u8>, StoreError> {
    let mut m = Hmac::<Sha256>::new_from_slice(key).map_err(|_| StoreError::BadMessage)?;
    for part in parts {
        m.update(part);
    }
    Ok(m.finalize().into_bytes().to_vec())
}

fn mac_matches(key: &[u8], parts: &[&[u8]], tag: &[u8]) -> Result<bool, StoreError> {
    let mut m = Hmac::<Sha256>::new_from_slice(key).map_err(|_| StoreError::BadMessage)?;
    for part in parts {
        m.update(part);
    }
    Ok(m.verify_slice(tag).is_ok())
}

/// Both phones' keys from the one-time keys, the secret and the account. `ours` is this phone's secret key, `theirs` the other's public key.
fn derive(ours: &Curve25519SecretKey, theirs: &[u8; 32], secret: &[u8; SECRET_LEN], new_pub: &[u8; 32], old_pub: &[u8; 32], user_id: &str) -> Result<(Session, [u8; 32]), StoreError> {
    let shared = ours.diffie_hellman(&Curve25519PublicKey::from_bytes(*theirs)).ok_or(StoreError::BadMessage)?;
    let t = transcript(new_pub, old_pub, user_id);
    let mut data = [0u8; 32];
    let mut ack = [0u8; 32];
    let mut hello = [0u8; 32];
    let mut code = [0u8; 4];
    hkdf_expand(secret, shared.as_bytes(), &with_label(b"data", &t), &mut data)?;
    hkdf_expand(secret, shared.as_bytes(), &with_label(b"ack", &t), &mut ack)?;
    hkdf_expand(secret, shared.as_bytes(), &with_label(b"hello", &t), &mut hello)?;
    hkdf_expand(secret, shared.as_bytes(), &with_label(b"code", &t), &mut code)?;
    let code = format!("{:06}", u32::from_be_bytes(code) % 1_000_000);
    Ok((Session { data, ack, code }, hello))
}

fn nonce_of(counter: u64) -> [u8; 12] {
    let mut nonce = [0u8; 12];
    nonce[4..].copy_from_slice(&counter.to_be_bytes());
    nonce
}

fn seal_chunk(key: &[u8; 32], counter: u64, kind: u8, payload: &[u8]) -> Result<Vec<u8>, StoreError> {
    let cipher = Aes256Gcm::new_from_slice(key).map_err(|_| StoreError::BadMessage)?;
    let mut plain = Vec::with_capacity(payload.len() + 1);
    plain.push(kind);
    plain.extend_from_slice(payload);
    cipher
        .encrypt(Nonce::from_slice(&nonce_of(counter)), Payload { msg: &plain, aad: &aad_of(counter) })
        .map_err(|_| StoreError::BadMessage)
}

fn open_chunk(key: &[u8; 32], counter: u64, sealed: &[u8]) -> Result<(u8, Vec<u8>), StoreError> {
    let cipher = Aes256Gcm::new_from_slice(key).map_err(|_| StoreError::BadMessage)?;
    let plain = cipher
        .decrypt(Nonce::from_slice(&nonce_of(counter)), Payload { msg: sealed, aad: &aad_of(counter) })
        .map_err(|_| StoreError::BadMessage)?;
    let (kind, payload) = plain.split_first().ok_or(StoreError::BadMessage)?;
    Ok((*kind, payload.to_vec()))
}

fn aad_of(counter: u64) -> Vec<u8> {
    let mut aad = LABEL.to_vec();
    aad.extend_from_slice(&counter.to_be_bytes());
    aad
}

fn random<const N: usize>() -> Result<[u8; N], StoreError> {
    let mut out = [0u8; N];
    getrandom::getrandom(&mut out).map_err(|_| StoreError::BadMessage)?;
    Ok(out)
}

fn io_err(_: std::io::Error) -> StoreError {
    StoreError::Database
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

// ---------------------------------------------------------------------------------------------------------------- the old phone

struct OldState {
    session: Session,
    confirmed: bool,
    /// The copy being sent, and where it is on disk.
    snapshot: Option<(File, std::path::PathBuf)>,
    counter: u64,
    hasher: Sha256,
    db_size: u64,
    sent: u64,
    stage: Stage,
    finished: bool,
}

#[derive(PartialEq, Clone, Copy)]
enum Stage {
    Manifest,
    Data,
    Final,
    Done,
}

/// The old phone's side of a move.
#[derive(uniffi::Object)]
pub struct TransferOld {
    store: Arc<LimeStore>,
    hello: Vec<u8>,
    state: Mutex<OldState>,
}

#[uniffi::export]
impl TransferOld {
    /// Scans the new phone's QR. Refused unless it is for this phone's own account. Nothing is read or sent yet.
    #[uniffi::constructor]
    pub fn accept(store: Arc<LimeStore>, qr: String) -> Result<Arc<Self>, StoreError> {
        let (new_pub, secret, user_id) = decode_qr(&qr)?;
        let mine = {
            let conn = store.lock();
            crate::store::account::load_account(&conn, &store.pickle_key)?
        };
        match mine.and_then(|m| m.user_id) {
            Some(id) if id == user_id => {}
            _ => return Err(StoreError::Rejected),
        }
        let ours = Curve25519SecretKey::new();
        let old_pub = Curve25519PublicKey::from(&ours).to_bytes();
        let (session, hello_key) = derive(&ours, &new_pub, &secret, &new_pub, &old_pub, &user_id)?;
        // The hello proves the secret was known: only a holder of it derives the key behind this tag.
        let mut hello = old_pub.to_vec();
        hello.extend_from_slice(&mac(&hello_key, &[&old_pub, &new_pub])?);
        Ok(Arc::new(Self {
            store,
            hello,
            state: Mutex::new(OldState { session, confirmed: false, snapshot: None, counter: 0, hasher: Sha256::new(), db_size: 0, sent: 0, stage: Stage::Manifest, finished: false }),
        }))
    }

    /// The bytes for the new phone (its answer to the QR).
    pub fn hello(&self) -> Vec<u8> {
        self.hello.clone()
    }

    /// The 6 digits both phones show; the person confirms they are the same.
    pub fn check_code(&self) -> String {
        self.state().session.code.clone()
    }

    /// The person saw the same code on both phones. Until now nothing is exported.
    pub fn confirm_code(&self) {
        self.state().confirmed = true;
    }

    /// The next sealed chunk for the new phone, or `None` after the last. The first call after the confirmation makes the copy of the store.
    pub fn export_next_chunk(&self) -> Result<Option<Vec<u8>>, StoreError> {
        let mut st = self.state();
        if !st.confirmed {
            return Err(StoreError::Rejected);
        }
        let counter = st.counter;
        let key = st.session.data;
        let chunk = match st.stage {
            Stage::Manifest => {
                let (file, path, manifest) = self.make_snapshot()?;
                st.db_size = manifest.db_size;
                st.snapshot = Some((file, path));
                st.stage = if manifest.db_size == 0 { Stage::Final } else { Stage::Data };
                seal_chunk(&key, counter, KIND_MANIFEST, &serde_json::to_vec(&manifest).map_err(|_| StoreError::BadMessage)?)?
            }
            Stage::Data => {
                let mut buf = vec![0u8; CHUNK];
                let (file, _) = st.snapshot.as_mut().ok_or(StoreError::BadMessage)?;
                let mut n = 0;
                while n < CHUNK {
                    let read = file.read(&mut buf[n..]).map_err(io_err)?;
                    if read == 0 {
                        break;
                    }
                    n += read;
                }
                buf.truncate(n);
                st.hasher.update(&buf);
                st.sent += n as u64;
                if n < CHUNK || st.sent >= st.db_size {
                    st.stage = Stage::Final;
                }
                seal_chunk(&key, counter, KIND_DATA, &buf)?
            }
            Stage::Final => {
                let digest = st.hasher.clone().finalize();
                st.stage = Stage::Done;
                seal_chunk(&key, counter, KIND_FINAL, &digest)?
            }
            Stage::Done => {
                st.remove_snapshot();
                st.finished = true;
                return Ok(None);
            }
        };
        st.counter += 1;
        Ok(Some(chunk))
    }

    /// How much of the account has been sent.
    pub fn progress(&self) -> MoveProgress {
        let st = self.state();
        MoveProgress { done: st.sent, total: st.db_size }
    }

    /// The new phone says it holds everything and the store opens as this account. Only its proof counts; then this phone's copy is removed
    /// from disk. The app then signs out and forgets the account's key in its Keychain.
    pub fn transfer_confirm(&self, proof: Vec<u8>) -> Result<(), StoreError> {
        let mut st = self.state();
        if !st.finished {
            return Err(StoreError::Rejected);
        }
        let digest = st.hasher.clone().finalize();
        if !mac_matches(&st.session.ack, &[b"ack", &digest], &proof)? {
            return Err(StoreError::BadMessage);
        }
        st.remove_snapshot();
        drop(st);
        let conn = self.store.lock();
        let path = conn.path().map(std::path::PathBuf::from).ok_or(StoreError::Database)?;
        drop(conn);
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let mut name = path.clone().into_os_string();
            name.push(suffix);
            let _ = std::fs::remove_file(std::path::PathBuf::from(name));
        }
        Ok(())
    }

    /// Stops the move; this phone keeps everything and the copy made for it is deleted.
    pub fn abort(&self) {
        self.state().remove_snapshot();
    }
}

impl TransferOld {
    fn state(&self) -> std::sync::MutexGuard<'_, OldState> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// A consistent, encrypted copy of the store (the same key), opened for reading, with the manifest that describes it.
    fn make_snapshot(&self) -> Result<(File, std::path::PathBuf, Manifest), StoreError> {
        let conn = self.store.lock();
        let main = conn.path().map(std::path::PathBuf::from).ok_or(StoreError::Database)?;
        let mut name = main.clone().into_os_string();
        name.push(".move");
        let snap = std::path::PathBuf::from(name);
        let _ = std::fs::remove_file(&snap);
        let version: i64 = conn.query_row("PRAGMA user_version", [], |r| r.get(0)).map_err(db_err)?;
        let quoted = snap.to_string_lossy().replace('\'', "''");
        let export = format!(
            "PRAGMA foreign_keys = OFF;
             ATTACH DATABASE '{quoted}' AS move KEY \"x'{}'\";
             SELECT sqlcipher_export('move');
             PRAGMA move.user_version = {version};
             DETACH DATABASE move;
             PRAGMA foreign_keys = ON;",
            hex(&self.store.store_key)
        );
        let result = conn.execute_batch(&export);
        let count = |sql: &str| conn.query_row(sql, [], |r| r.get::<_, i64>(0)).unwrap_or(0).max(0) as u64;
        let conversations = count("SELECT count(*) FROM conversations");
        let messages = count("SELECT count(*) FROM messages");
        let attachments = count("SELECT count(*) FROM message_attachments");
        let account = crate::store::account::load_account(&conn, &self.store.pickle_key)?.ok_or(StoreError::Rejected)?;
        let _ = conn.execute_batch("PRAGMA foreign_keys = ON;");
        drop(conn);
        if result.is_err() {
            let _ = std::fs::remove_file(&snap);
            return Err(StoreError::Database);
        }
        let file = File::open(&snap).map_err(io_err)?;
        let db_size = file.metadata().map_err(io_err)?.len();
        let manifest = Manifest {
            v: VERSION,
            user_id: account.user_id.clone().ok_or(StoreError::Rejected)?,
            device_id: account.device_id.clone(),
            store_key: base64_encode(self.store.store_key),
            db_size,
            chunks: db_size.div_ceil(CHUNK as u64),
            conversations,
            messages,
            attachments,
        };
        Ok((file, snap, manifest))
    }
}

impl OldState {
    fn remove_snapshot(&mut self) {
        if let Some((file, path)) = self.snapshot.take() {
            drop(file);
            let _ = std::fs::remove_file(path);
        }
    }
}

impl Drop for OldState {
    fn drop(&mut self) {
        self.remove_snapshot();
    }
}

// ---------------------------------------------------------------------------------------------------------------- the new phone

struct NewState {
    secret: [u8; SECRET_LEN],
    ours: Curve25519SecretKey,
    session: Option<Session>,
    confirmed: bool,
    part: Option<File>,
    manifest: Option<Manifest>,
    counter: u64,
    hasher: Sha256,
    received: u64,
    data_chunks: u64,
    digest: Option<[u8; 32]>,
    finished: bool,
    failed: bool,
}

/// The new phone's side of a move.
#[derive(uniffi::Object)]
pub struct TransferNew {
    user_id: String,
    dest: std::path::PathBuf,
    qr: String,
    state: Mutex<NewState>,
}

#[uniffi::export]
impl TransferNew {
    /// Starts a move for `user_id`'s account into a store file at `dest_path` (nothing is created there until it all verified).
    #[uniffi::constructor]
    pub fn offer(user_id: String, dest_path: String) -> Result<Arc<Self>, StoreError> {
        let ours = Curve25519SecretKey::new();
        let secret = random::<SECRET_LEN>()?;
        let mut payload = vec![VERSION];
        payload.extend_from_slice(&Curve25519PublicKey::from(&ours).to_bytes());
        payload.extend_from_slice(&secret);
        payload.extend_from_slice(user_id.as_bytes());
        let qr = format!("{QR_PREFIX}{}", base64_encode(payload));
        Ok(Arc::new(Self {
            user_id,
            dest: dest_path.into(),
            qr,
            state: Mutex::new(NewState { secret, ours, session: None, confirmed: false, part: None, manifest: None, counter: 0, hasher: Sha256::new(), received: 0, data_chunks: 0, digest: None, finished: false, failed: false }),
        }))
    }

    /// The text for the QR code.
    pub fn qr(&self) -> String {
        self.qr.clone()
    }

    /// The old phone's answer. Refused unless it was made with this QR's secret.
    pub fn accept_hello(&self, hello: Vec<u8>) -> Result<(), StoreError> {
        let mut st = self.state();
        if st.session.is_some() || hello.len() != 32 + 32 {
            return Err(StoreError::BadMessage);
        }
        let old_pub: [u8; 32] = hello[..32].try_into().map_err(|_| StoreError::BadMessage)?;
        let new_pub = Curve25519PublicKey::from(&st.ours).to_bytes();
        let (session, hello_key) = derive(&st.ours, &old_pub, &st.secret, &new_pub, &old_pub, &self.user_id)?;
        if !mac_matches(&hello_key, &[&old_pub, &new_pub], &hello[32..])? {
            return Err(StoreError::BadMessage);
        }
        st.session = Some(session);
        Ok(())
    }

    /// The 6 digits both phones show (after the hello).
    pub fn check_code(&self) -> Result<String, StoreError> {
        self.state().session.as_ref().map(|s| s.code.clone()).ok_or(StoreError::Rejected)
    }

    /// The person saw the same code on both phones. Until now no chunk is accepted.
    pub fn confirm_code(&self) {
        self.state().confirmed = true;
    }

    /// Takes the next chunk, in order. Any failure discards everything received; start again from a new QR.
    pub fn import_chunk(&self, chunk: Vec<u8>) -> Result<(), StoreError> {
        let mut st = self.state();
        let result = self.take_chunk(&mut st, &chunk);
        if result.is_err() {
            st.failed = true;
            st.part = None;
            let _ = std::fs::remove_file(self.part_path());
        }
        result
    }

    /// What the manifest says about the account (after its chunk arrived).
    pub fn summary(&self) -> Option<MoveSummary> {
        self.state().manifest.as_ref().map(|m| MoveSummary { conversations: m.conversations, messages: m.messages, attachments: m.attachments, total_bytes: m.db_size })
    }

    pub fn progress(&self) -> MoveProgress {
        let st = self.state();
        MoveProgress { done: st.received, total: st.manifest.as_ref().map(|m| m.db_size).unwrap_or(0) }
    }

    /// Checks the whole stream, that the file opens as this account's store with this device's keys, and only then puts it in place.
    /// Returns the key that opens it (for the new phone's Keychain). On any failure nothing is kept.
    pub fn import_finish(&self) -> Result<Vec<u8>, StoreError> {
        let mut st = self.state();
        let result = self.finish(&mut st);
        if result.is_err() {
            st.failed = true;
            st.part = None;
            let _ = std::fs::remove_file(self.part_path());
        }
        result
    }

    /// The proof for the old phone that this phone holds everything (after `import_finish`).
    pub fn confirm_proof(&self) -> Result<Vec<u8>, StoreError> {
        let st = self.state();
        match (&st.session, st.digest, st.finished) {
            (Some(session), Some(digest), true) => mac(&session.ack, &[b"ack", &digest]),
            _ => Err(StoreError::Rejected),
        }
    }

    /// Stops the move and deletes what was received.
    pub fn abort(&self) {
        let mut st = self.state();
        st.part = None;
        st.failed = true;
        let _ = std::fs::remove_file(self.part_path());
    }
}

impl TransferNew {
    fn state(&self) -> std::sync::MutexGuard<'_, NewState> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn part_path(&self) -> std::path::PathBuf {
        let mut name = self.dest.clone().into_os_string();
        name.push(".part");
        name.into()
    }

    fn take_chunk(&self, st: &mut NewState, chunk: &[u8]) -> Result<(), StoreError> {
        if st.failed || st.finished || !st.confirmed {
            return Err(StoreError::Rejected);
        }
        let key = st.session.as_ref().ok_or(StoreError::Rejected)?.data;
        let (kind, payload) = open_chunk(&key, st.counter, chunk)?;
        match (st.counter, kind) {
            (0, KIND_MANIFEST) => {
                let manifest: Manifest = serde_json::from_slice(&payload).map_err(|_| StoreError::BadMessage)?;
                if manifest.v != VERSION || manifest.user_id != self.user_id || manifest.chunks != manifest.db_size.div_ceil(CHUNK as u64) {
                    return Err(StoreError::BadMessage);
                }
                if let Some(dir) = self.dest.parent() {
                    std::fs::create_dir_all(dir).map_err(io_err)?;
                }
                st.part = Some(File::create(self.part_path()).map_err(io_err)?);
                st.manifest = Some(manifest);
            }
            (n, KIND_DATA) if n > 0 => {
                let manifest = st.manifest.as_ref().ok_or(StoreError::BadMessage)?;
                if payload.len() > CHUNK || st.received + payload.len() as u64 > manifest.db_size || st.data_chunks >= manifest.chunks {
                    return Err(StoreError::BadMessage);
                }
                st.part.as_mut().ok_or(StoreError::BadMessage)?.write_all(&payload).map_err(io_err)?;
                st.hasher.update(&payload);
                st.received += payload.len() as u64;
                st.data_chunks += 1;
            }
            (n, KIND_FINAL) if n > 0 => {
                let digest: [u8; 32] = payload.try_into().map_err(|_| StoreError::BadMessage)?;
                let manifest = st.manifest.as_ref().ok_or(StoreError::BadMessage)?;
                if st.received != manifest.db_size || st.data_chunks != manifest.chunks || st.hasher.clone().finalize().as_slice() != digest {
                    return Err(StoreError::BadMessage);
                }
                st.part.as_mut().ok_or(StoreError::BadMessage)?.flush().map_err(io_err)?;
                st.digest = Some(digest);
            }
            _ => return Err(StoreError::BadMessage),
        }
        st.counter += 1;
        Ok(())
    }

    fn finish(&self, st: &mut NewState) -> Result<Vec<u8>, StoreError> {
        if st.failed || st.digest.is_none() {
            return Err(StoreError::BadMessage);
        }
        let manifest = st.manifest.as_ref().ok_or(StoreError::BadMessage)?;
        let store_key = base64_decode(&manifest.store_key).map_err(|_| StoreError::BadMessage)?;
        st.part.take();
        let part = self.part_path();
        // The file must open with that key as this account's store, with the device it was moved from.
        {
            let opened = LimeStore::open_inner(&part.to_string_lossy(), &store_key)?;
            let conn = opened.lock();
            let account = crate::store::account::load_account(&conn, &opened.pickle_key)?.ok_or(StoreError::BadMessage)?;
            if account.user_id.as_deref() != Some(self.user_id.as_str()) || account.device_id != manifest.device_id {
                return Err(StoreError::BadMessage);
            }
        }
        for suffix in ["-wal", "-shm", "-journal"] {
            let mut name = part.clone().into_os_string();
            name.push(suffix);
            let _ = std::fs::remove_file(std::path::PathBuf::from(name));
        }
        std::fs::rename(&part, &self.dest).map_err(io_err)?;
        st.finished = true;
        Ok(store_key)
    }
}

fn decode_qr(qr: &str) -> Result<([u8; 32], [u8; SECRET_LEN], String), StoreError> {
    let body = qr.strip_prefix(QR_PREFIX).ok_or(StoreError::BadMessage)?;
    let bytes = base64_decode(body).map_err(|_| StoreError::BadMessage)?;
    if bytes.len() <= 1 + 32 + SECRET_LEN || bytes[0] != VERSION {
        return Err(StoreError::BadMessage);
    }
    let new_pub: [u8; 32] = bytes[1..33].try_into().map_err(|_| StoreError::BadMessage)?;
    let secret: [u8; SECRET_LEN] = bytes[33..33 + SECRET_LEN].try_into().map_err(|_| StoreError::BadMessage)?;
    let user_id = String::from_utf8(bytes[33 + SECRET_LEN..].to_vec()).map_err(|_| StoreError::BadMessage)?;
    Ok((new_pub, secret, user_id))
}
