//! lime's mesh engine (LIME-140): carries lime's already-sealed envelopes from phone to phone (store, carry, forward), with privacy on the
//! air, budgets, dedupe and expiry, so a phone that reaches the internet can upload what it carries without learning who it is for.
//!
//! **This crate depends on nothing of lime's** (no account, store, server or crypto types): it moves opaque bytes, which keeps a future mesh
//! SDK possible. The platform supplies three things: a [`MeshLink`] (how to put a frame on a link; links going up and down and frames
//! arriving are reported to the node), a [`MeshStore`] (persistence for the packets being carried) and a [`Clock`] (time is passed in: there are
//! **no timers in the core**). The node answers every event with a list of [`Action`]s for the platform to carry out.
//!
//! Modules: [`packet`] (the versioned, padded wire packet and its digest), [`frame`] (what two phones say to each other when they meet),
//! [`config`] (every parameter, in one place), [`node`] (the engine: forwarding rules, meetings, budgets).

pub mod config;
pub mod frame;
pub mod node;
pub mod packet;

pub use config::MeshConfig;
pub use frame::Frame;
pub use node::{Action, CopyEvent, Delivered, MeshNode, NodeStats, Uploadable};
pub use packet::{bucket_size, Digest, Packet, PacketError, Short, Tag};

/// A radio link to one other phone, named by the platform (one per pair at a time is the platform's job; the core tolerates duplicates).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct LinkId(pub u64);

/// How much a packet is worth keeping when the store is full: strangers' mail is evicted first, my own mail last.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Tier {
    Stranger = 0,
    Contact = 1,
    Own = 2,
}

/// Time, in seconds since the Unix epoch, supplied by the platform (the simulator makes its own).
pub trait Clock {
    fn now_secs(&self) -> u64;
}

/// Puts frames on links for the platform. A platform that prefers callbacks to a list of actions implements this and calls [`apply`].
pub trait MeshLink {
    /// Send `bytes` on `link` after about `delay_ms` (relay jitter: a hint, never slept in the core).
    fn send(&mut self, link: LinkId, bytes: &[u8], delay_ms: u32);
}

/// Carries out a list of actions on a [`MeshLink`].
pub fn apply(actions: Vec<Action>, link: &mut impl MeshLink) {
    for action in actions {
        match action {
            Action::SendFrame { link: id, bytes, delay_ms } => link.send(id, &bytes, delay_ms),
        }
    }
}

/// A packet the node carries, as the platform persists it. `bytes` is the encoded packet as it is now (its `hops_left` included).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StoredPacket {
    pub bytes: Vec<u8>,
    pub copies: u8,
    pub tier: Tier,
    pub received_at: u64,
}

/// Persistence for the packets being carried and the short-lived seen-set. `lime_core` implements it on its encrypted database; the
/// simulator keeps it in memory. A store that fails simply loses a packet: the mesh is best effort by design.
pub trait MeshStore {
    /// Everything carried, read once when the node starts.
    fn load(&mut self) -> Vec<StoredPacket>;
    fn save(&mut self, packet: &StoredPacket);
    fn remove(&mut self, digest: &Digest);
    /// The seen digests with the time they were seen, read once when the node starts.
    fn load_seen(&mut self) -> Vec<(Digest, u64)>;
    fn save_seen(&mut self, digest: &Digest, at: u64);
    /// The digests this phone uploaded to the server, with when (kept 48 hours so a neighbour's copy is not taken and uploaded again).
    fn load_uploaded(&mut self) -> Vec<(Digest, u64)> {
        Vec::new()
    }
    fn save_uploaded(&mut self, _digest: &Digest, _at: u64) {}
}

/// A [`MeshStore`] that keeps everything in memory (tests, the simulator, a platform that does not persist).
#[derive(Default, Clone)]
pub struct MemoryStore {
    pub packets: Vec<StoredPacket>,
    pub seen: Vec<(Digest, u64)>,
    pub uploaded: Vec<(Digest, u64)>,
}

impl MeshStore for MemoryStore {
    fn load(&mut self) -> Vec<StoredPacket> {
        self.packets.clone()
    }
    fn save(&mut self, packet: &StoredPacket) {
        if let Ok(decoded) = Packet::decode(&packet.bytes) {
            let digest = decoded.digest();
            self.packets.retain(|p| Packet::decode(&p.bytes).map(|d| d.digest()) != Ok(digest));
        }
        self.packets.push(packet.clone());
    }
    fn remove(&mut self, digest: &Digest) {
        self.packets.retain(|p| Packet::decode(&p.bytes).map(|d| d.digest()).as_ref() != Ok(digest));
    }
    fn load_seen(&mut self) -> Vec<(Digest, u64)> {
        self.seen.clone()
    }
    fn save_seen(&mut self, digest: &Digest, at: u64) {
        self.seen.push((*digest, at));
        if self.seen.len() > 4096 {
            self.seen.drain(..2048);
        }
    }
    fn load_uploaded(&mut self) -> Vec<(Digest, u64)> {
        self.uploaded.clone()
    }
    fn save_uploaded(&mut self, digest: &Digest, at: u64) {
        self.uploaded.push((*digest, at));
    }
}
