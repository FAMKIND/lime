//! Relay download (LIME-155): an OFFLINE phone asks a linked ONLINE lime phone to fetch its mail from the server and hand it over Bluetooth.
//!
//! The offline phone builds a request (its device id, where to start, what it already kept, a single-use nonce, an expiry of at most 10 minutes
//! and a one-time reply key), signs it with its own device key and seals it to the server's pinned mesh key (the routing header's construction, its
//! own HKDF label). The neighbour posts it to `mesh-fetch` with NO session and passes the answer back, which only the offline phone can open.
//! What each party learns is written in `docs/api-v2.md` §8 and `supabase/functions/mesh-fetch/index.ts`.
//!
//! Four link frames carry it (a phone that does not know them ignores them; they never reach the mesh node):
//! `5` request (the sealed bytes), `6` reply (the encrypted bytes), `7` fail (one code byte), `8` online (one byte: 1 = I can fetch for you).

use std::collections::HashMap;

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use hkdf::Hkdf;
use sha2::Sha256;
use vodozemac::{Curve25519PublicKey, Curve25519SecretKey};

use super::{current_server_key, now_ms, seal_to_server, MeshAction, MeshEngine, ServerKey};
use crate::store::pending::Fetched;
use crate::store::StoreError;
use crate::transport::{HeaderPair, Transport};
use std::sync::Arc;

pub(crate) const FETCH_LABEL: &[u8] = b"lime-mesh-fetch-v1";
const REPLY_LABEL: &[u8] = b"lime-mesh-fetch-reply-v1";
pub(crate) const CANONICAL_BYTES: usize = 91;
pub(crate) const MAX_REQUEST_LIFE_SECS: u64 = 600;

pub(crate) const FRAME_REQUEST: u8 = 5;
pub(crate) const FRAME_REPLY: u8 = 6;
pub(crate) const FRAME_FAIL: u8 = 7;
pub(crate) const FRAME_ONLINE: u8 = 8;

/// A request that has been waiting this long for its reply is given up on (the next neighbour is tried).
const REPLY_TIMEOUT_SECS: u64 = 20;
/// A neighbour relays at most this many requests a minute for one link.
const RELAYS_PER_MINUTE: usize = 10;
/// How many items one request asks for.
const ITEMS_PER_REQUEST: u16 = 50;

/// The fields of a request, in the order and width the server reads them.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct RequestFields {
    pub device_id: [u8; 16],
    pub after: i64,
    /// -1: nothing to acknowledge.
    pub ack_through: i64,
    pub limit: u16,
    pub nonce: [u8; 16],
    pub expires_at: u64,
    pub reply_key: [u8; 32],
}

impl RequestFields {
    /// `1 | device (16) | after (i64) | ack (i64) | limit (u16) | nonce (16) | expires (u64) | reply key (32)`, 91 bytes, big-endian.
    pub(crate) fn canonical(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(CANONICAL_BYTES);
        out.push(1);
        out.extend_from_slice(&self.device_id);
        out.extend_from_slice(&self.after.to_be_bytes());
        out.extend_from_slice(&self.ack_through.to_be_bytes());
        out.extend_from_slice(&self.limit.to_be_bytes());
        out.extend_from_slice(&self.nonce);
        out.extend_from_slice(&self.expires_at.to_be_bytes());
        out.extend_from_slice(&self.reply_key);
        debug_assert_eq!(out.len(), CANONICAL_BYTES);
        out
    }
}

/// The message the device signs: the label, then the canonical bytes.
pub(crate) fn signing_input(canonical: &[u8]) -> Vec<u8> {
    let mut out = FETCH_LABEL.to_vec();
    out.extend_from_slice(canonical);
    out
}

/// The sealed request: `canonical || signature(64)` sealed to the server with a given ephemeral key (tests pin it).
pub(crate) fn seal_request_with(ephemeral: &Curve25519SecretKey, server: &ServerKey, fields: &RequestFields, signature: &[u8; 64]) -> Result<Vec<u8>, StoreError> {
    let mut plain = fields.canonical();
    plain.extend_from_slice(signature);
    seal_to_server(ephemeral, server, FETCH_LABEL, &plain)
}

/// What the server said, once opened.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct ReplyBody {
    pub items: Vec<Fetched>,
    pub has_more: bool,
    /// The first waiting item does not fit one Bluetooth frame: it needs the internet (nothing was skipped or deleted).
    pub blocked: bool,
}

/// Opens a reply with the one-time reply secret: `ephemeral X25519 (32) || AES-256-GCM(4-byte length || JSON || zeros)`.
pub(crate) fn open_reply(secret: &Curve25519SecretKey, reply: &[u8]) -> Option<ReplyBody> {
    if reply.len() < 32 + 16 {
        return None;
    }
    let ephemeral: [u8; 32] = reply[..32].try_into().ok()?;
    let shared = secret.diffie_hellman(&Curve25519PublicKey::from_bytes(ephemeral))?;
    let mut info = REPLY_LABEL.to_vec();
    info.extend_from_slice(&ephemeral);
    let mut okm = [0u8; 44];
    Hkdf::<Sha256>::new(None, shared.as_bytes()).expand(&info, &mut okm).ok()?;
    let cipher = Aes256Gcm::new_from_slice(&okm[..32]).ok()?;
    let plain = cipher.decrypt(Nonce::from_slice(&okm[32..]), Payload { msg: &reply[32..], aad: &ephemeral }).ok()?;
    let length = u32::from_be_bytes(plain.get(..4)?.try_into().ok()?) as usize;
    let json: serde_json::Value = serde_json::from_slice(plain.get(4..4 + length)?).ok()?;
    let items = json.get("items")?.as_array()?;
    let mut out = Vec::with_capacity(items.len());
    for item in items {
        out.push(Fetched {
            cursor: item.get("cursor")?.as_i64()?,
            sender_user: item.get("sender_user").and_then(serde_json::Value::as_str).map(str::to_owned),
            identified: item.get("identified").and_then(serde_json::Value::as_bool) == Some(true),
            ciphertext: item.get("ciphertext")?.as_str()?.to_owned(),
            received_at: item.get("received_at").and_then(serde_json::Value::as_str).map(str::to_owned),
        });
    }
    Some(ReplyBody { items: out, has_more: json.get("has_more").and_then(serde_json::Value::as_bool) == Some(true), blocked: json.get("blocked").and_then(serde_json::Value::as_bool) == Some(true) })
}

fn frame(kind: u8, body: &[u8]) -> Vec<u8> {
    let mut out = vec![kind];
    out.extend_from_slice(body);
    out
}

struct Pending {
    secret: Curve25519SecretKey,
    link: u64,
    sent_secs: u64,
}

/// What the engine keeps for relay download.
#[derive(Default)]
pub(crate) struct FetchState {
    /// This phone can fetch for others (online and signed in).
    online: bool,
    /// The neighbours' "I can fetch for you" bits, by link.
    neighbours: HashMap<u64, bool>,
    /// My own request that waits for its reply.
    pending: Option<PendingBox>,
    /// Requests from neighbours that the app has yet to post.
    jobs: Vec<(u64, Vec<u8>)>,
    /// When each link last asked me to relay (seconds), for the per-minute limit.
    relayed: HashMap<u64, Vec<u64>>,
    /// The highest server cursor ingested through relay download, and acknowledged by the next request.
    after: i64,
    blocked: bool,
}

struct PendingBox(Pending);
impl Default for PendingBox {
    fn default() -> Self {
        PendingBox(Pending { secret: Curve25519SecretKey::new(), link: 0, sent_secs: 0 })
    }
}

/// A request a neighbour asked this phone to post (the app posts it with `relay_fetch`).
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct MeshFetchJob {
    pub link: u64,
    pub request: Vec<u8>,
}

impl MeshEngine {
    pub(crate) fn refresh_offline_neighbours(&self) {
        let offline = self.fetch_state().neighbours.values().filter(|online| !**online).count();
        self.store.set_mesh_offline_neighbours(offline);
    }

    fn fetch_state(&self) -> std::sync::MutexGuard<'_, FetchState> {
        self.fetch.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// The frames that are not the mesh's own (5 to 8): handled here, never by the node. `None` when `bytes` is not one of them.
    pub(super) fn app_frame(&self, link: u64, bytes: &[u8]) -> Option<Vec<MeshAction>> {
        let kind = *bytes.first()?;
        if !(FRAME_REQUEST..=FRAME_ONLINE).contains(&kind) {
            return None;
        }
        let body = &bytes[1..];
        let now = (now_ms().max(0) / 1000) as u64;
        let mut actions = Vec::new();
        match kind {
            FRAME_ONLINE => {
                let online = body.first() == Some(&1);
                self.fetch_state().neighbours.insert(link, online);
                // The node offers copies of mail already on the server to a neighbour that says it is offline (LIME-156).
                let offered = self.node().set_link_online(super::LinkId(link), online);
                if offered {
                    self.note(format!("copy_offered link_offline={:04x}", link & 0xffff));
                }
                self.refresh_offline_neighbours();
            }
            FRAME_REQUEST => {
                let mut state = self.fetch_state();
                let window = state.relayed.entry(link).or_default();
                window.retain(|t| now.saturating_sub(*t) < 60);
                let refused = if !state.online { Some(1u8) } else if state.relayed.get(&link).map(|w| w.len()).unwrap_or(0) >= RELAYS_PER_MINUTE { Some(2) } else if state.jobs.len() >= 4 || body.is_empty() || body.len() > 1024 { Some(3) } else { None };
                match refused {
                    Some(code) => {
                        drop(state);
                        self.note(format!("fetch_refused link_busy={code}"));
                        actions.push(MeshAction { link, bytes: frame(FRAME_FAIL, &[code]), delay_ms: 0 });
                    }
                    None => {
                        state.relayed.entry(link).or_default().push(now);
                        state.jobs.push((link, body.to_vec()));
                    }
                }
            }
            FRAME_REPLY | FRAME_FAIL => {
                if let Some(next) = self.handle_answer(link, kind, body, now) {
                    actions.push(next);
                }
            }
            _ => {}
        }
        Some(actions)
    }

    /// My request's answer arrived (a reply, or a fail from the neighbour).
    fn handle_answer(&self, link: u64, kind: u8, body: &[u8], now: u64) -> Option<MeshAction> {
        let secret = {
            let mut state = self.fetch_state();
            match state.pending.as_ref() {
                Some(p) if p.0.link == link => {}
                _ => return None, // nothing was asked of this link
            }
            let taken = state.pending.take()?;
            taken.0.secret
        };
        if kind == FRAME_FAIL {
            self.note(format!("fetch_fail why=neighbour code={}", body.first().copied().unwrap_or(0)));
            return None;
        }
        let Some(reply) = open_reply(&secret, body) else {
            self.note("fetch_fail why=unreadable_reply".into());
            return None;
        };
        let bytes: usize = reply.items.iter().map(|i| i.ciphertext.len()).sum();
        self.note(format!("fetch_reply items={} bytes={} has_more={}", reply.items.len(), bytes, reply.has_more));
        if reply.blocked {
            self.note("fetch_fail why=item_too_big_for_bluetooth".into());
            self.fetch_state().blocked = true;
        }
        let highest = reply.items.iter().map(|i| i.cursor).max();
        if !reply.items.is_empty() {
            match self.store.ingest_fetched(reply.items) {
                // What became messages, and what stayed pending and why (LIME-156b: group items fetched offline must show at once).
                Ok(shown) => {
                    let pending = self.store.pending_summary().unwrap_or_default();
                    self.note(format!("fetch_ingested messages={shown} pending=[{}]", if pending.is_empty() { "none" } else { pending.as_str() }));
                }
                Err(_) => {
                    self.note("fetch_fail why=ingest".into());
                    return None;
                }
            }
        }
        if let Some(highest) = highest {
            let mut state = self.fetch_state();
            state.after = state.after.max(highest);
        }
        if reply.has_more && highest.is_some() {
            return self.build_request(link, now).ok().flatten().map(|bytes| MeshAction { link, bytes, delay_ms: 0 });
        }
        None
    }

    /// Tests only: the same, at a chosen time (the 20 s timeout).
    #[cfg(test)]
    pub(crate) fn fetch_frame_at(&self, link: u64, now: u64) -> Result<Option<Vec<u8>>, StoreError> {
        if self.fetch_state().neighbours.get(&link) != Some(&true) {
            return Ok(None);
        }
        self.build_request(link, now)
    }

    /// A signed, sealed request frame for `link`, remembered as the one outstanding. `None`: not allowed now (one in flight, or blocked).
    fn build_request(&self, link: u64, now: u64) -> Result<Option<Vec<u8>>, StoreError> {
        let server = self.server_key.or_else(current_server_key).ok_or(StoreError::Unavailable)?;
        let (after, ack) = {
            let mut state = self.fetch_state();
            if let Some(p) = state.pending.as_ref() {
                if now.saturating_sub(p.0.sent_secs) < REPLY_TIMEOUT_SECS {
                    return Ok(None);
                }
                state.pending = None;
                drop(state);
                self.note("fetch_timeout".into());
                return self.build_request(link, now);
            }
            if state.blocked {
                return Ok(None);
            }
            (state.after, if state.after > 0 { state.after } else { -1 })
        };
        let account = self.store.load_or_create_account()?;
        let device_id = uuid::Uuid::parse_str(&account.device_id).map_err(|_| StoreError::BadMessage)?;
        let reply_secret = Curve25519SecretKey::new();
        let mut nonce = [0u8; 16];
        nonce.copy_from_slice(&Curve25519SecretKey::new().to_bytes()[..16]);
        let fields = RequestFields {
            device_id: *device_id.as_bytes(),
            after,
            ack_through: ack,
            limit: ITEMS_PER_REQUEST,
            nonce,
            expires_at: now + MAX_REQUEST_LIFE_SECS - 60,
            reply_key: *Curve25519PublicKey::from(&reply_secret).as_bytes(),
        };
        let signature = account.account.sign(signing_input(&fields.canonical()));
        let sealed = seal_request_with(&Curve25519SecretKey::new(), &server, &fields, &signature.to_bytes())?;
        self.fetch_state().pending = Some(PendingBox(Pending { secret: reply_secret, link, sent_secs: now }));
        self.note(format!("fetch_request_sent after={after}"));
        Ok(Some(frame(FRAME_REQUEST, &sealed)))
    }
}

#[uniffi::export]
impl MeshEngine {
    /// This phone can fetch for others (online with a signed-in session) or not. The app calls it when connectivity or the session changes.
    pub fn set_relay_online(&self, online: bool) {
        self.fetch_state().online = online;
    }

    /// The frame that tells a neighbour whether this phone can fetch for it: sent at link-up and whenever `set_relay_online` changes.
    pub fn online_frame(&self) -> Vec<u8> {
        frame(FRAME_ONLINE, &[u8::from(self.fetch_state().online)])
    }

    /// The links whose phones said they can fetch for me.
    pub fn fetch_neighbours(&self) -> Vec<u64> {
        let mut links: Vec<u64> = self.fetch_state().neighbours.iter().filter(|(_, online)| **online).map(|(link, _)| *link).collect();
        links.sort_unstable();
        links
    }

    /// A link went away: forget what it said.
    pub fn fetch_link_down(&self, link: u64) {
        let mut state = self.fetch_state();
        state.neighbours.remove(&link);
        state.relayed.remove(&link);
        if state.pending.as_ref().map(|p| p.0.link) == Some(link) {
            state.pending = None;
        }
        drop(state);
        self.refresh_offline_neighbours();
    }

    /// The request frame to put on `link` (a neighbour that can fetch for me), or nothing when one is already waiting for its reply, a reply said
    /// an item needs the internet, or the link is not an online neighbour.
    pub fn fetch_frame_for(&self, link: u64) -> Result<Option<Vec<u8>>, StoreError> {
        if self.fetch_state().neighbours.get(&link) != Some(&true) {
            return Ok(None);
        }
        self.build_request(link, (now_ms().max(0) / 1000) as u64)
    }

    /// Forget a "blocked" state and start over (the internet came back, or the person asked): the next request is allowed again.
    pub fn fetch_reset(&self) {
        let mut state = self.fetch_state();
        state.blocked = false;
        state.pending = None;
    }

    /// The requests neighbours asked this phone to post (the app posts each with [`MeshEngine::relay_fetch`] and sends the answer back).
    pub fn take_fetch_jobs(&self) -> Vec<MeshFetchJob> {
        std::mem::take(&mut self.fetch_state().jobs).into_iter().map(|(link, request)| MeshFetchJob { link, request }).collect()
    }

    /// Posts a neighbour's request to `mesh-fetch` with no session (only the anon key the transport adds) and returns the frame to send back:
    /// the reply (opaque to this phone) or a one-byte fail.
    pub fn relay_fetch(&self, transport: Arc<dyn Transport>, request: Vec<u8>) -> Vec<u8> {
        let body = serde_json::json!({ "request": vodozemac::base64_encode(&request) });
        let headers = vec![HeaderPair { name: "content-type".into(), value: "application/json".into() }];
        let response = body
            .to_string()
            .into_bytes()
            .pipe(|bytes| transport.request("POST".into(), "/functions/v1/mesh-fetch".into(), headers, bytes));
        match response {
            Ok(r) if r.status == 200 => {
                let reply = serde_json::from_slice::<serde_json::Value>(&r.body).ok().and_then(|v| v["reply"].as_str().and_then(|s| vodozemac::base64_decode(s).ok()));
                match reply {
                    Some(reply) => {
                        self.note(format!("fetch_relayed status=200 bytes={}", reply.len()));
                        frame(FRAME_REPLY, &reply)
                    }
                    None => {
                        self.note("fetch_relayed status=200 unreadable".into());
                        frame(FRAME_FAIL, &[5])
                    }
                }
            }
            Ok(r) => {
                self.note(format!("fetch_relayed status={}", r.status));
                frame(FRAME_FAIL, &[if r.status == 403 { 4 } else { 6 }])
            }
            Err(_) => {
                self.note("fetch_relayed status=network".into());
                frame(FRAME_FAIL, &[7])
            }
        }
    }
}

trait Pipe: Sized {
    fn pipe<R>(self, f: impl FnOnce(Self) -> R) -> R {
        f(self)
    }
}
impl<T> Pipe for T {}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use vodozemac::Ed25519SecretKey;

    /// The local test key pair of the Supabase stack (`supabase/functions/.env`): the secret there, the public half here. Never used on staging.
    const LOCAL_TEST_SECRET: &str = "KILKJyNyeB2broEOGIiyuqZcUVWs9jZM9XtAjY/ZiWA=";
    const LOCAL_TEST_PUBLIC: &str = "GyNOPj7N/ovXno/OznB9bEtKB2PTAsuRK1XzXrzX7lY=";

    fn local_server() -> ServerKey {
        ServerKey { id: 1, public: Curve25519PublicKey::from_base64(LOCAL_TEST_PUBLIC).unwrap().to_bytes() }
    }

    /// What the server does: opens `key_id || ephemeral || AES-GCM` with its secret and a label.
    pub(crate) fn open_sealed(secret: &Curve25519SecretKey, label: &[u8], sealed: &[u8]) -> Option<Vec<u8>> {
        if sealed.len() < 1 + 32 + 16 {
            return None;
        }
        let key_id = sealed[0];
        let ephemeral: [u8; 32] = sealed[1..33].try_into().ok()?;
        let shared = secret.diffie_hellman(&Curve25519PublicKey::from_bytes(ephemeral))?;
        let mut info = label.to_vec();
        info.push(key_id);
        info.extend_from_slice(&ephemeral);
        let mut okm = [0u8; 44];
        Hkdf::<Sha256>::new(None, shared.as_bytes()).expand(&info, &mut okm).ok()?;
        let cipher = Aes256Gcm::new_from_slice(&okm[..32]).ok()?;
        cipher.decrypt(Nonce::from_slice(&okm[32..]), Payload { msg: &sealed[33..], aad: &sealed[..33] }).ok()
    }

    /// What the server does with a reply: ephemeral X25519, HKDF, AES-256-GCM, padded to 4 KiB steps (the same as `_shared/mesh.ts`).
    pub(crate) fn seal_reply(reply_key: &[u8; 32], json: &[u8]) -> Vec<u8> {
        let ephemeral = Curve25519SecretKey::new();
        let ephemeral_public = *Curve25519PublicKey::from(&ephemeral).as_bytes();
        let shared = ephemeral.diffie_hellman(&Curve25519PublicKey::from_bytes(*reply_key)).unwrap();
        let mut info = REPLY_LABEL.to_vec();
        info.extend_from_slice(&ephemeral_public);
        let mut okm = [0u8; 44];
        Hkdf::<Sha256>::new(None, shared.as_bytes()).expand(&info, &mut okm).unwrap();
        let total = ((4 + json.len()).div_ceil(4096)) * 4096;
        let mut padded = vec![0u8; total];
        padded[..4].copy_from_slice(&(json.len() as u32).to_be_bytes());
        padded[4..4 + json.len()].copy_from_slice(json);
        let sealed = Aes256Gcm::new_from_slice(&okm[..32]).unwrap().encrypt(Nonce::from_slice(&okm[32..]), Payload { msg: &padded, aad: &ephemeral_public }).unwrap();
        let mut out = ephemeral_public.to_vec();
        out.extend_from_slice(&sealed);
        out
    }

    fn fields() -> RequestFields {
        RequestFields {
            device_id: *uuid::Uuid::parse_str("0a0b0c0d-0e0f-4a1b-8c2d-3e4f5a6b7c8d").unwrap().as_bytes(),
            after: 7,
            ack_through: 5,
            limit: 50,
            nonce: [0x11; 16],
            expires_at: 1_900_000_300,
            reply_key: [0x22; 32],
        }
    }

    #[test]
    fn the_canonical_request_is_91_bytes_in_the_order_the_server_reads() {
        let canonical = fields().canonical();
        assert_eq!(canonical.len(), CANONICAL_BYTES);
        assert_eq!(canonical[0], 1);
        assert_eq!(&canonical[1..17], uuid::Uuid::parse_str("0a0b0c0d-0e0f-4a1b-8c2d-3e4f5a6b7c8d").unwrap().as_bytes());
        assert_eq!(i64::from_be_bytes(canonical[17..25].try_into().unwrap()), 7);
        assert_eq!(i64::from_be_bytes(canonical[25..33].try_into().unwrap()), 5);
        assert_eq!(u16::from_be_bytes(canonical[33..35].try_into().unwrap()), 50);
        assert_eq!(&canonical[35..51], &[0x11; 16]);
        assert_eq!(u64::from_be_bytes(canonical[51..59].try_into().unwrap()), 1_900_000_300);
        assert_eq!(&canonical[59..91], &[0x22; 32]);
    }

    #[test]
    fn a_request_round_trips_to_the_server_and_the_signature_checks_with_the_device_key() {
        let secret = Curve25519SecretKey::from_slice(&vodozemac::base64_decode(LOCAL_TEST_SECRET).unwrap().try_into().unwrap());
        let signer = Ed25519SecretKey::from_slice(&[9u8; 32]);
        let f = fields();
        let signature = signer.sign(&signing_input(&f.canonical()));
        let sealed = seal_request_with(&Curve25519SecretKey::from_slice(&[7u8; 32]), &local_server(), &f, &signature.to_bytes()).unwrap();
        let opened = open_sealed(&secret, FETCH_LABEL, &sealed).expect("the server opens it");
        assert_eq!(&opened[..CANONICAL_BYTES], f.canonical().as_slice());
        let sig = vodozemac::Ed25519Signature::from_slice(&opened[CANONICAL_BYTES..]).unwrap();
        signer.public_key().verify(&signing_input(&opened[..CANONICAL_BYTES]), &sig).expect("the device's signature verifies");
        assert!(open_sealed(&secret, b"lime-mesh-header-v1", &sealed).is_none(), "a fetch request does not open as a routing header (separate labels)");
        let mut changed = sealed.clone();
        changed[40] ^= 1;
        assert!(open_sealed(&secret, FETCH_LABEL, &changed).is_none(), "a changed byte");
    }

    /// Shared with `supabase/tests/mesh_fetch_test.ts`: the server opens exactly this, the signature verifies, the fields read back.
    #[test]
    fn the_sealed_request_vector_is_pinned() {
        let signer = Ed25519SecretKey::from_slice(&[9u8; 32]);
        let f = fields();
        let signature = signer.sign(&signing_input(&f.canonical()));
        let sealed = seal_request_with(&Curve25519SecretKey::from_slice(&[7u8; 32]), &local_server(), &f, &signature.to_bytes()).unwrap();
        let hex: String = sealed.iter().map(|b| format!("{b:02x}")).collect();
        assert_eq!(hex, PINNED_REQUEST_HEX, "the pinned request (the Deno test opens this one)");
        assert_eq!(signer.public_key().to_base64(), PINNED_DEVICE_PUBLIC);
    }

    const PINNED_REQUEST_HEX: &str = "0113be4feaeaf204c7fd3358fc9c00721881d174278128227ec674f37f7fe97b6d66a8844fbbc8ebf1e812f62be7de27a30795f69bd025d3797a57eba7acf24713ad8e037e1e0e3c033152ce87ee11aacbab90b935ed4db81110e079f4ef1c8dade9f7028d66c2e05a407aa2ced7b1c36dad884a316d506901405abc8462fa5e2ee2ee2158211daa2586ad40053d1a9ee1efe1486005cffb2aeb0f3cb1d6fe3851c727fddef1f36f7fe2f919ae624c2d05c4fcb8ddbdbbeb71601235c9e33dd89b0b037a8667581a42fb2edd";
    const PINNED_DEVICE_PUBLIC: &str = "/RckOFqgx1tk+3jNYC+h2ZH96/drE8WO1wLqyDXp9hg";

    #[test]
    fn a_reply_opens_with_the_reply_secret_only_and_is_padded() {
        let reply_secret = Curve25519SecretKey::new();
        let reply_public = *Curve25519PublicKey::from(&reply_secret).as_bytes();
        let json = serde_json::json!({ "items": [{ "cursor": 3, "ciphertext": "AAAA", "size": 3, "received_at": "2026-10-16T00:00:00Z" },
                                                  { "cursor": 4, "ciphertext": "BBBB", "size": 3, "identified": true, "sender_user": "u" }], "has_more": true });
        let sealed = seal_reply(&reply_public, json.to_string().as_bytes());
        assert_eq!((sealed.len() - 32 - 16) % 4096, 0, "padded to 4 KiB steps");
        let opened = open_reply(&reply_secret, &sealed).expect("the owner opens it");
        assert_eq!(opened.items.iter().map(|i| i.cursor).collect::<Vec<_>>(), vec![3, 4]);
        assert!(opened.has_more && !opened.blocked);
        assert_eq!(opened.items[1].sender_user.as_deref(), Some("u"));
        assert!(open_reply(&Curve25519SecretKey::new(), &sealed).is_none(), "nobody else can");
        assert!(open_reply(&reply_secret, &sealed[..100]).is_none(), "cut short");
        // blocked
        let blocked = seal_reply(&reply_public, br#"{"items":[],"has_more":true,"blocked":true}"#);
        assert!(open_reply(&reply_secret, &blocked).unwrap().blocked);
    }
}
