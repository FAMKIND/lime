//! The mesh, lime_core's side (LIME-140): what only a phone that holds the keys can do. The engine itself (`lime_mesh`) moves opaque,
//! already-sealed bytes and knows nothing of this.
//!
//! - **The recipient tag (finding 2a).** `tag = HMAC-SHA256(tag_key, "lime-mesh-tag-v1" || UTC day || to_device)[..16]` with
//!   `tag_key = HKDF-SHA256(delivery_key, "lime-mesh-tag-v1")`. A contact already holds my delivery key, so a sender can tag mail for my
//!   device; I recompute today's and yesterday's tags for my own device to recognise mine. Bystanders and relays see 16 random-looking
//!   bytes that change every day.
//! - **The sealed routing header (finding 2b).** `{ to_device, access: { signed } }` (LIME-139's proof for this ciphertext and device)
//!   sealed to the SERVER's mesh public key: X25519 (an ephemeral key per packet) + HKDF-SHA256 + AES-256-GCM, a 1-byte key id for
//!   rotation. Only `mesh-drop` can open it, so a relay learns neither the recipient nor anything it could reuse. Layout and derivation are
//!   in `supabase/functions/_shared/mesh.ts`, which opens it.
//!
//! Crates: vodozemac's Curve25519 (already linked), `hkdf`, `aes-gcm` and `sha2` (already dependencies) and `hmac` (hkdf's own dependency).

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use hkdf::Hkdf;
use hmac::{Hmac, KeyInit as _, Mac};
use sha2::Sha256;
use vodozemac::{Curve25519PublicKey, Curve25519SecretKey};

use crate::store::StoreError;

const TAG_INFO: &[u8] = b"lime-mesh-tag-v1";
const HEADER_INFO: &[u8] = b"lime-mesh-header-v1";

/// The server's mesh public keys by id, pinned in the app. **Empty until the server's key pair exists** (the user generates it with
/// `supabase/mesh-keygen.sh`, which prints only the public key; it is added here with its id). With none pinned, nothing can be sealed.
pub(crate) const SERVER_KEYS: &[ServerKey] = &[];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct ServerKey {
    pub id: u8,
    pub public: [u8; 32],
}

/// The server key to seal to: the newest pinned one.
pub(crate) fn current_server_key() -> Option<ServerKey> {
    SERVER_KEYS.last().copied()
}

pub(crate) fn day_of(now_secs: u64) -> u64 {
    now_secs / 86_400
}

fn device_bytes(to_device: &str) -> Result<[u8; 16], StoreError> {
    uuid::Uuid::parse_str(to_device).map(|u| *u.as_bytes()).map_err(|_| StoreError::BadMessage)
}

/// The recipient tag for `to_device` on UTC `day`, made with the recipient's delivery key.
pub(crate) fn recipient_tag(delivery_key: &[u8], to_device: &str, day: u64) -> Result<[u8; 16], StoreError> {
    let mut tag_key = [0u8; 32];
    Hkdf::<Sha256>::new(None, delivery_key).expand(TAG_INFO, &mut tag_key).map_err(|_| StoreError::BadMessage)?;
    let mut mac = Hmac::<Sha256>::new_from_slice(&tag_key).map_err(|_| StoreError::BadMessage)?;
    mac.update(TAG_INFO);
    mac.update(&day.to_be_bytes());
    mac.update(&device_bytes(to_device)?);
    let full = mac.finalize().into_bytes();
    Ok(full[..16].try_into().expect("16 of 32 bytes"))
}

/// Today's and yesterday's tags for one device (what a recipient answers to, so mail made just before midnight still finds it).
pub(crate) fn recipient_tags(delivery_key: &[u8], to_device: &str, now_secs: u64) -> Result<Vec<[u8; 16]>, StoreError> {
    let day = day_of(now_secs);
    Ok(vec![recipient_tag(delivery_key, to_device, day)?, recipient_tag(delivery_key, to_device, day.saturating_sub(1))?])
}

/// Seals the routing header with a given ephemeral key (tests pin it; production uses a fresh random one through [`seal_header`]).
pub(crate) fn seal_header_with(ephemeral: &Curve25519SecretKey, server: &ServerKey, to_device: &str, signed: &str) -> Result<Vec<u8>, StoreError> {
    let plaintext = serde_json::to_vec(&serde_json::json!({ "to_device": to_device, "access": { "signed": signed } })).map_err(|_| StoreError::BadMessage)?;
    let ephemeral_public = Curve25519PublicKey::from(ephemeral);
    let shared = ephemeral.diffie_hellman(&Curve25519PublicKey::from_bytes(server.public)).ok_or(StoreError::BadMessage)?;
    let mut info = HEADER_INFO.to_vec();
    info.push(server.id);
    info.extend_from_slice(ephemeral_public.as_bytes());
    let mut okm = [0u8; 44];
    Hkdf::<Sha256>::new(None, shared.as_bytes()).expand(&info, &mut okm).map_err(|_| StoreError::BadMessage)?;
    let cipher = Aes256Gcm::new_from_slice(&okm[..32]).map_err(|_| StoreError::BadMessage)?;
    let mut aad = vec![server.id];
    aad.extend_from_slice(ephemeral_public.as_bytes());
    let sealed = cipher.encrypt(Nonce::from_slice(&okm[32..]), Payload { msg: &plaintext, aad: &aad }).map_err(|_| StoreError::BadMessage)?;
    let mut out = aad;
    out.extend_from_slice(&sealed);
    Ok(out)
}

/// Seals the routing header to the server with a fresh ephemeral key.
pub(crate) fn seal_header(server: &ServerKey, to_device: &str, signed: &str) -> Result<Vec<u8>, StoreError> {
    seal_header_with(&Curve25519SecretKey::new(), server, to_device, signed)
}

// ---------------------------------------------------------------------------------------------------------------- the engine

use std::collections::HashSet;
use std::sync::{Arc, Mutex};

use lime_mesh::{Action, Clock, Digest, LinkId, MeshConfig, MeshNode, MeshStore, Packet, StoredPacket, Tier};
use rusqlite::params;

use crate::store::{db_err, now_ms, LimeStore};
use crate::transport::{HeaderPair, Transport};

struct SystemClock;
impl Clock for SystemClock {
    fn now_secs(&self) -> u64 {
        (now_ms() / 1000).max(0) as u64
    }
}

/// The mesh's persistence on lime's encrypted database (migration 32).
pub(crate) struct SqlMeshStore {
    store: Arc<LimeStore>,
}

fn tier_of(value: i64) -> Tier {
    match value {
        2 => Tier::Own,
        1 => Tier::Contact,
        _ => Tier::Stranger,
    }
}

impl MeshStore for SqlMeshStore {
    fn load(&mut self) -> Vec<StoredPacket> {
        let conn = self.store.lock();
        let Ok(mut statement) = conn.prepare("SELECT bytes, copies, tier, received_at FROM mesh_packets") else { return Vec::new() };
        let rows = statement.query_map([], |r| {
            Ok(StoredPacket { bytes: r.get(0)?, copies: r.get::<_, i64>(1)? as u8, tier: tier_of(r.get(2)?), received_at: r.get::<_, i64>(3)?.max(0) as u64 })
        });
        rows.map(|rows| rows.filter_map(Result::ok).collect()).unwrap_or_default()
    }

    fn save(&mut self, packet: &StoredPacket) {
        let Ok(decoded) = Packet::decode(&packet.bytes) else { return };
        let conn = self.store.lock();
        let _ = conn.execute(
            "INSERT OR REPLACE INTO mesh_packets (digest, bytes, copies, tier, received_at) VALUES (?1, ?2, ?3, ?4, ?5)",
            params![decoded.digest().to_vec(), packet.bytes, packet.copies as i64, packet.tier as i64, packet.received_at as i64],
        );
    }

    fn remove(&mut self, digest: &Digest) {
        let conn = self.store.lock();
        let _ = conn.execute("DELETE FROM mesh_packets WHERE digest = ?1", params![digest.to_vec()]);
    }

    fn load_seen(&mut self) -> Vec<(Digest, u64)> {
        let conn = self.store.lock();
        let Ok(mut statement) = conn.prepare("SELECT digest, at FROM mesh_seen ORDER BY at") else { return Vec::new() };
        let rows = statement.query_map([], |r| Ok((r.get::<_, Vec<u8>>(0)?, r.get::<_, i64>(1)?)));
        rows.map(|rows| rows.filter_map(Result::ok).filter_map(|(d, at)| Some((<Digest>::try_from(d.as_slice()).ok()?, at.max(0) as u64))).collect()).unwrap_or_default()
    }

    fn save_seen(&mut self, digest: &Digest, at: u64) {
        let conn = self.store.lock();
        let _ = conn.execute("INSERT OR REPLACE INTO mesh_seen (digest, at) VALUES (?1, ?2)", params![digest.to_vec(), at as i64]);
        // The seen-set only matters for minutes: keep the table small.
        let _ = conn.execute("DELETE FROM mesh_seen WHERE at < ?1", params![at as i64 - 3600]);
    }
}

/// Something the platform must put on a link (the mesh engine's `Action`).
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct MeshAction {
    pub link: u64,
    pub bytes: Vec<u8>,
    pub delay_ms: u32,
}

/// A carried packet a phone with internet can hand to `mesh-drop`. `id` names it for `upload_done` / `upload_failed`.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct MeshUpload {
    pub id: Vec<u8>,
    pub header: Vec<u8>,
    pub payload: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct MeshStats {
    pub carried: u32,
    pub carried_bytes: u32,
    pub received: u64,
    pub duplicates: u64,
    pub rejected: u64,
    pub rate_limited: u64,
    pub evicted: u64,
    pub expired: u64,
}

fn actions(list: Vec<Action>) -> Vec<MeshAction> {
    list.into_iter().map(|Action::SendFrame { link, bytes, delay_ms }| MeshAction { link: link.0, bytes, delay_ms }).collect()
}

/// The mesh on this phone: carries sealed mail between phones and hands it to the server when one reaches the internet. The platform owns the
/// radio (Bluetooth, LIME-141); this is everything else. Radio-free: the platform reports links and frames and does what the actions say.
#[derive(uniffi::Object)]
pub struct MeshEngine {
    store: Arc<LimeStore>,
    node: Mutex<MeshNode<SqlMeshStore, SystemClock>>,
    server_key: Option<ServerKey>,
    my_tags: Mutex<Vec<[u8; 16]>>,
}

impl MeshEngine {
    fn build(store: Arc<LimeStore>, server_key: Option<ServerKey>) -> Arc<Self> {
        let node = MeshNode::new(MeshConfig { seed: now_ms() as u64, ..MeshConfig::default() }, SqlMeshStore { store: store.clone() }, SystemClock);
        Arc::new(MeshEngine { store, node: Mutex::new(node), server_key, my_tags: Mutex::new(Vec::new()) })
    }

    fn node(&self) -> std::sync::MutexGuard<'_, MeshNode<SqlMeshStore, SystemClock>> {
        self.node.lock().unwrap_or_else(|e| e.into_inner())
    }
}

#[uniffi::export]
impl MeshEngine {
    /// The mesh engine for this store, sealing to the server's pinned mesh key (none is pinned until the server's key pair exists: then
    /// `queue_for_send` says it cannot).
    #[uniffi::constructor]
    pub fn new(store: Arc<LimeStore>) -> Arc<Self> {
        Self::build(store, current_server_key())
    }

    /// Seals to the given server key (its id and 32-byte X25519 public key) instead of the one pinned in lime_core: for an environment whose
    /// key the platform knows (the local stack's test key, a staging key before it is pinned).
    #[uniffi::constructor]
    pub fn new_with_server_key(store: Arc<LimeStore>, key_id: u8, public_key: Vec<u8>) -> Result<Arc<Self>, StoreError> {
        let public: [u8; 32] = public_key.try_into().map_err(|_| StoreError::BadMessage)?;
        Ok(Self::build(store, Some(ServerKey { id: key_id, public })))
    }

    /// Makes the node's tags current: this phone's own (today's and yesterday's, for its device) and those of the accepted contacts' devices
    /// (mail for them is worth more than a stranger's). The platform calls it at start, when the day changes and after the contacts change.
    pub fn refresh_tags(&self) -> Result<(), StoreError> {
        let now = now_ms().max(0) as u64 / 1000;
        let state = self.store.load_or_create_account()?;
        let (mine, contacts) = {
            let conn = self.store.lock();
            let (own_key, _) = crate::store::delivery::current(&conn, now_ms())?;
            let mine = recipient_tags(&own_key, &state.device_id, now)?;
            let mut contacts: HashSet<[u8; 16]> = HashSet::new();
            let mut statement = conn
                .prepare("SELECT c.key, d.device_id FROM contact_delivery_keys c JOIN peer_devices d ON d.user_id = c.user_id WHERE c.denied = 0")
                .map_err(db_err)?;
            let rows = statement.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
            for (key, device) in rows {
                let Ok(key) = vodozemac::base64_decode(key) else { continue };
                for tag in recipient_tags(&key, &device, now).unwrap_or_default() {
                    contacts.insert(tag);
                }
            }
            (mine, contacts)
        };
        let mut node = self.node();
        node.set_my_tags(&mine);
        node.set_contact_tags(contacts);
        *self.my_tags.lock().unwrap_or_else(|e| e.into_inner()) = mine;
        Ok(())
    }

    /// Puts a message the server's `send` would store (`ciphertext` for `to_device`, a device of the accepted contact `to_user`) on the mesh:
    /// tagged for that device, with the routing header sealed to the server. Only mail to contacts who gave us their delivery key can travel
    /// (the proof is signed with it); anything else is refused, and the caller sends it the usual way. Returns whether it was queued.
    pub fn queue_for_send(&self, to_user: String, to_device: String, ciphertext: Vec<u8>) -> Result<bool, StoreError> {
        let server = self.server_key.ok_or(StoreError::Unavailable)?;
        let now = now_ms().max(0) as u64 / 1000;
        let key = {
            let conn = self.store.lock();
            match crate::store::delivery::contact_key(&conn, &to_user)? {
                Some((key, false)) => key,
                _ => return Ok(false),
            }
        };
        let signed = crate::store::delivery::access_signature_b64(&key, &ciphertext, &to_device)?;
        let header = seal_header(&server, &to_device, &signed)?;
        let packet = Packet { tag: recipient_tag(&key, &to_device, day_of(now))?, header, payload: ciphertext, hops_left: 0, expires_at: now + 48 * 3600 };
        Ok(self.node().enqueue(packet).is_ok())
    }

    /// A link to another phone is up: the frames to send.
    pub fn link_up(&self, link: u64) -> Vec<MeshAction> {
        actions(self.node().on_link_up(LinkId(link)))
    }

    /// A frame arrived on `link`: the frames to send in answer.
    pub fn frame(&self, link: u64, bytes: Vec<u8>) -> Vec<MeshAction> {
        actions(self.node().on_frame(LinkId(link), &bytes))
    }

    pub fn link_down(&self, link: u64) {
        self.node().on_link_down(LinkId(link));
    }

    /// Mail for this phone that arrived over the mesh goes through the normal inbound path (de-duplicated by op id as ever). Returns how many
    /// messages it turned into.
    pub fn take_mine(&self) -> Result<u32, StoreError> {
        let tags = self.my_tags.lock().unwrap_or_else(|e| e.into_inner()).clone();
        let mail = self.node().take_mine(&tags);
        if mail.is_empty() {
            return Ok(0);
        }
        self.store.receive_mesh_payloads(mail.into_iter().map(|m| m.payload).collect())
    }

    /// What this phone carries that the server could take, for `mesh-drop`.
    pub fn take_uploadable(&self) -> Vec<MeshUpload> {
        self.node().take_uploadable().into_iter().map(|u| MeshUpload { id: u.digest.to_vec(), header: u.header, payload: u.payload }).collect()
    }

    pub fn upload_done(&self, id: Vec<u8>) {
        if let Ok(digest) = <Digest>::try_from(id.as_slice()) {
            self.node().confirm_uploaded(&digest);
        }
    }

    pub fn upload_failed(&self, id: Vec<u8>) {
        if let Ok(digest) = <Digest>::try_from(id.as_slice()) {
            self.node().upload_failed(&digest);
        }
    }

    /// Hands everything carried to `mesh-drop` (a signed-in session). A packet the server takes, or refuses for good (403: a bad proof or a
    /// device that is gone), is dropped from the store; a network error, a 5xx or "not configured" keeps it for next time. Returns how many
    /// the server stored.
    pub fn upload_all(&self, transport: Arc<dyn Transport>, auth_token: String) -> Result<u32, StoreError> {
        let mut stored = 0;
        for item in self.take_uploadable() {
            let body = serde_json::json!({ "header": vodozemac::base64_encode(&item.header), "payload": vodozemac::base64_encode(&item.payload) });
            let headers = vec![
                HeaderPair { name: "content-type".into(), value: "application/json".into() },
                HeaderPair { name: "authorization".into(), value: format!("Bearer {auth_token}") },
            ];
            let response = transport.request("POST".into(), "/functions/v1/mesh-drop".into(), headers, serde_json::to_vec(&body).map_err(|_| StoreError::BadMessage)?);
            match response.map(|r| (r.status, r.body)) {
                Ok((200, body)) => {
                    stored += serde_json::from_slice::<serde_json::Value>(&body).ok().and_then(|v| v["stored"].as_u64()).unwrap_or(0) as u32;
                    self.upload_done(item.id);
                }
                Ok((403, _)) => self.upload_done(item.id),
                _ => self.upload_failed(item.id),
            }
        }
        Ok(stored)
    }

    pub fn stats(&self) -> MeshStats {
        let s = self.node().stats();
        MeshStats {
            carried: s.carried as u32,
            carried_bytes: s.carried_bytes as u32,
            received: s.received,
            duplicates: s.duplicates,
            rejected: s.rejected,
            rate_limited: s.rate_limited,
            evicted: s.evicted,
            expired: s.expired,
        }
    }
}

impl LimeStore {
    /// Mail that came over the mesh: the ciphertexts the server would have stored for this device. They join the inbound queue (sealed, no
    /// sender: exactly as a sealed mailbox item) and are processed at once. A packet that arrives by the mesh and by the mailbox is one message
    /// (the inbound path de-duplicates by op id).
    pub(crate) fn receive_mesh_payloads(&self, payloads: Vec<Vec<u8>>) -> Result<u32, StoreError> {
        use sha2::{Digest as _, Sha256};
        let _guard = self.lock_protocol();
        let mut state = self.load_or_create_account()?;
        let me = state.user_id.clone().filter(|_| state.registered).ok_or(StoreError::NotRegistered)?;
        let items: Vec<crate::store::pending::Fetched> = payloads
            .iter()
            .map(|payload| {
                let digest = Sha256::digest(payload);
                // Mesh items have no server cursor: a negative one, from the payload's own hash (the same ciphertext twice is one item).
                let cursor = -(((u64::from_be_bytes(digest[..8].try_into().expect("8 bytes")) >> 1) as i64) + 1);
                crate::store::pending::Fetched { cursor, sender_user: None, identified: false, ciphertext: vodozemac::base64_encode(payload), received_at: None }
            })
            .collect();
        {
            let mut conn = self.lock();
            crate::store::pending::insert_all(&mut conn, &items, now_ms())?;
        }
        self.retry_pending(&mut state, &me)
    }
}

/// Tests only: what `mesh-drop` does with a header (the server's secret opens it). The real one is `supabase/functions/_shared/mesh.ts`.
#[cfg(test)]
pub(crate) fn open_header(server_secret: &Curve25519SecretKey, header: &[u8]) -> Option<Vec<u8>> {
    if header.len() < 1 + 32 + 16 {
        return None;
    }
    let key_id = header[0];
    let ephemeral = Curve25519PublicKey::from_slice(&header[1..33]).ok()?;
    let shared = server_secret.diffie_hellman(&ephemeral)?;
    let mut info = HEADER_INFO.to_vec();
    info.push(key_id);
    info.extend_from_slice(ephemeral.as_bytes());
    let mut okm = [0u8; 44];
    Hkdf::<Sha256>::new(None, shared.as_bytes()).expand(&info, &mut okm).ok()?;
    let cipher = Aes256Gcm::new_from_slice(&okm[..32]).ok()?;
    cipher.decrypt(Nonce::from_slice(&okm[32..]), Payload { msg: &header[33..], aad: &header[..33] }).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    // The local test key pair of the Supabase stack (`supabase/config.toml`, never used on staging): the secret there, the public half here.
    const LOCAL_TEST_PUBLIC: &str = "GyNOPj7N/ovXno/OznB9bEtKB2PTAsuRK1XzXrzX7lY=";
    const DEVICE: &str = "0a0b0c0d-0e0f-4a1b-8c2d-3e4f5a6b7c8d";

    fn local_key() -> ServerKey {
        ServerKey { id: 1, public: Curve25519PublicKey::from_base64(LOCAL_TEST_PUBLIC).unwrap().to_bytes() }
    }

    #[test]
    fn the_recipient_tag_is_pinned_daily_per_device_and_made_from_the_delivery_key() {
        // Never change (another platform checks the same vector). The HMAC and HKDF were also computed independently with Python's hmac/hashlib.
        let key = [7u8; 32];
        let hex = |b: &[u8]| b.iter().map(|x| format!("{x:02x}")).collect::<String>();
        assert_eq!(hex(&recipient_tag(&key, DEVICE, 20_000).unwrap()), "0ff9a2814cff0bfb4f5a0780999de6d4");
        let today = recipient_tag(&key, DEVICE, 20_000).unwrap();
        assert_ne!(today, recipient_tag(&key, DEVICE, 20_001).unwrap(), "it changes every day");
        assert_ne!(today, recipient_tag(&key, "0a0b0c0d-0e0f-4a1b-8c2d-3e4f5a6b7c8e", 20_000).unwrap(), "per device");
        assert_ne!(today, recipient_tag(&[8u8; 32], DEVICE, 20_000).unwrap(), "only someone with the delivery key can make it");
        assert_eq!(recipient_tags(&key, DEVICE, 20_000 * 86_400 + 5).unwrap(), vec![today, recipient_tag(&key, DEVICE, 19_999).unwrap()], "today's and yesterday's");
        assert!(recipient_tag(&key, "not-a-uuid", 1).is_err());
    }

    #[test]
    fn a_sealed_header_has_the_documented_layout_and_hides_the_recipient() {
        let header = seal_header(&local_key(), DEVICE, "c2ln").unwrap();
        assert_eq!(header[0], 1, "the key id");
        assert!(header.len() > 1 + 32 + 16, "key id, ephemeral key, ciphertext and tag");
        let text = String::from_utf8_lossy(&header);
        assert!(!text.contains(DEVICE) && !text.contains("c2ln") && !text.contains("to_device"), "nothing readable");
        // A new ephemeral key every time: two seals of the same thing differ.
        assert_ne!(header, seal_header(&local_key(), DEVICE, "c2ln").unwrap());
    }

    #[test]
    fn the_server_opens_what_the_phone_seals_and_nothing_else() {
        let secret = Curve25519SecretKey::from_slice(&vodozemac::base64_decode("KILKJyNyeB2broEOGIiyuqZcUVWs9jZM9XtAjY/ZiWA=").unwrap().try_into().unwrap());
        let header = seal_header(&local_key(), DEVICE, "c2lnbmVk").unwrap();
        let opened: serde_json::Value = serde_json::from_slice(&open_header(&secret, &header).unwrap()).unwrap();
        assert_eq!(opened, serde_json::json!({ "to_device": DEVICE, "access": { "signed": "c2lnbmVk" } }));
        for i in [0usize, 1, 33, header.len() - 1] {
            let mut bad = header.clone();
            bad[i] ^= 1;
            assert!(open_header(&secret, &bad).is_none(), "byte {i} changed");
        }
        assert!(open_header(&Curve25519SecretKey::new(), &header).is_none(), "another server's key");
    }

    #[test]
    fn the_sealed_header_vector_is_pinned_so_the_server_opens_what_the_phone_seals() {
        // The Deno test (`supabase/tests/mesh_test.ts`) opens exactly these bytes with the local test secret.
        let header = seal_header_with(&Curve25519SecretKey::from_slice(&[0x42; 32]), &local_key(), DEVICE, "c2lnbmVk").unwrap();
        let hex: String = header.iter().map(|x| format!("{x:02x}")).collect();
        assert_eq!(hex, "01132c442be010fbd57e72603328aa76e71fccc1503aae219327d14d9c9993f472aee31ccaa5d57330a036e255668651f607457eb3c4d50adf5eb4f2d56bceab33eee96e43f6301e10630620522a76be501696669c3e6a6deb2e7f9cfb4ecb69710a6744f256dec44f6e45a58db8b0ea849a20b3ad00208d4b6cdb3dbb262ee0c328e852");
    }
}
