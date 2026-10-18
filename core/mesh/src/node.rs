//! The mesh engine (LIME-140): what a phone does with packets it carries, and with the phones it meets.
//!
//! It is a state machine: the platform reports events (a link came up or went down, a frame arrived, the app has something to send) and the
//! node answers with [`Action`]s. Time comes from the [`Clock`]; nothing here sleeps or sets a timer, and nothing here reads a radio.
//!
//! **A meeting** (the platform says a link is up): both sides send a **Hello** (a summary of the packets they hold and have recently seen,
//! plus the recipient tags they answer to); each then asks, in a **Want**, for the packets it is missing; the other sends them as **Packet**
//! frames (one per packet, each with a small jitter hint), and the receiver **Ack**s each one. A packet whose Ack never came (the link
//! dropped) is simply asked for again at the next meeting: nothing is lost and nothing is counted as handed over until it is acked.
//!
//! **Forwarding** is spray and wait: a packet starts with `copies_initial` copies; handing a courier a copy hands over half of what the holder
//! has; a holder with one copy keeps it until it meets the packet's recipient (a peer whose Hello lists the packet's tag) or the internet
//! (`take_uploadable`). Each hop costs one of `hops_left`; a node with many links hands out a shorter TTL. A packet seen before is never
//! stored twice; budgets, trust tiers, expiry and per-link rate limits bound what a phone carries for others.

use std::collections::{HashMap, HashSet, VecDeque};

use crate::config::MeshConfig;
use crate::frame::Frame;
use crate::packet::{short, Digest, Packet, Short, Tag};
use crate::{Clock, LinkId, MeshStore, StoredPacket, Tier};

/// What the platform should do.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Action {
    /// Put these bytes on `link`, after about `delay_ms` (the relay jitter hint; the platform delays, the core never sleeps).
    SendFrame { link: LinkId, bytes: Vec<u8>, delay_ms: u32 },
}

/// Mail for this phone, taken out of the store: `payload` is exactly what the server's `send` would have stored.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Delivered {
    pub digest: Digest,
    pub payload: Vec<u8>,
    /// Hops the packet had left when it arrived here (the hops it took are `ttl - hops_left`, plus the last hand-over).
    pub hops_left: u8,
    /// When the packet expires: its author makes it expire 48 hours after creation, so `expires_at - 48 h` is when it was made.
    pub expires_at: u64,
}

/// A carried packet a phone with internet can hand to the server (`mesh-drop`): the sealed routing header and the payload.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Uploadable {
    pub digest: Digest,
    pub header: Vec<u8>,
    pub payload: Vec<u8>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EnqueueError {
    Expired,
    TooLarge,
    NoRoom,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct NodeStats {
    pub carried: usize,
    pub carried_bytes: usize,
    pub received: u64,
    pub duplicates: u64,
    pub rejected: u64,
    pub rate_limited: u64,
    pub evicted: u64,
    pub expired: u64,
    pub bad_frames: u64,
    pub sent_packets: u64,
}

struct Carried {
    packet: Packet,
    copies: u8,
    tier: Tier,
    received_at: u64,
    /// Order of arrival at this node (a counter: `received_at` is whole seconds, and two packets made in the same second must keep their order).
    seq: u64,
}

#[derive(Default)]
struct LinkState {
    peer_summary: HashSet<Short>,
    peer_tags: Vec<Tag>,
    /// Packets sent on this link and not acked yet: short digest → (digest, copies handed over, whether it went to its recipient).
    pending: HashMap<Short, (Digest, u8, bool)>,
    window_start: u64,
    accepted_in_window: u32,
}

/// What happened to a copy of mail already on the server (LIME-156c), for the platform's log.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CopyEvent {
    /// The copy went to this link.
    Handed { link: LinkId, digest: Digest },
    /// The copy cannot go to this link, and why: `online`, `unknown` (the neighbour has not said), `no_tag_match` (not its recipient).
    Held { link: LinkId, digest: Digest, why: &'static str },
}

/// How long a phone remembers it uploaded a packet.
pub const UPLOADED_MEMORY_SECS: u64 = 48 * 3600;
/// How long a copy of mail already on the server stays on the mesh.
pub const COPY_LIFETIME_SECS: u64 = 6 * 3600;

/// How many times the server may refuse a packet before the carrier gives up on it.
pub const MAX_REFUSALS: u32 = 3;

pub struct MeshNode<S: MeshStore, C: Clock> {
    config: MeshConfig,
    store: S,
    clock: C,
    carried: HashMap<Digest, Carried>,
    seen: VecDeque<(Digest, u64)>,
    seen_set: HashSet<Digest>,
    links: HashMap<LinkId, LinkState>,
    contact_tags: HashSet<Tag>,
    my_tags: Vec<Tag>,
    uploading: HashSet<Digest>,
    /// Packets the server refused (403): how many times, and not before when. A refusal may be fixed later (the recipient has not uploaded its
    /// access key yet), so it is retried a few times, later and later, and then dropped.
    refused: HashMap<Digest, (u32, u64)>,
    /// Packets this phone uploaded to the server, with when: never taken again from a neighbour that still holds a copy (LIME-156; the 5 minute
    /// seen window used to forget them, and a neighbour offered the same packet back).
    uploaded: HashMap<Digest, u64>,
    /// Copies of mail this phone already sent to the server (LIME-156): offered only to a neighbour whose online bit says it is offline, never
    /// uploaded by this phone. Local state only; nothing on the air marks them.
    /// (the value: handed only to its own recipient, never sprayed onward — group copies, LIME-156b)
    offline_only: HashMap<Digest, bool>,
    /// What each linked neighbour said about being online (`None`: not heard yet, which counts as online: no copy goes out unasked).
    link_online: HashMap<LinkId, bool>,
    /// Packets taken out of the upload list because they were uploaded before (the platform logs `upload_skip why=already_uploaded`).
    already_uploaded: u32,
    copy_events: Vec<CopyEvent>,
    copy_held_logged: HashSet<(Digest, &'static str)>,
    next_seq: u64,
    /// Packets another phone has acknowledged taking (a copy handed over): what "Passed to a nearby phone" is made from.
    handed: HashSet<Digest>,
    rng: u64,
    stats: NodeStats,
    /// Counts every change to what is carried or recently seen (what a Hello's summary is made of): the platform sends a new Hello only when it moved.
    version: u64,
}

impl<S: MeshStore, C: Clock> MeshNode<S, C> {
    pub fn new(config: MeshConfig, mut store: S, clock: C) -> Self {
        let now = clock.now_secs();
        let mut carried = HashMap::new();
        for stored in store.load() {
            if let Ok(packet) = Packet::decode(&stored.bytes) {
                if packet.expires_at > now {
                    carried.insert(packet.digest(), Carried { packet, copies: stored.copies.clamp(1, config.copies_cap), tier: stored.tier, received_at: stored.received_at, seq: 0 });
                }
            }
        }
        // What was carried before a restart keeps its order: by when it arrived, then by digest.
        let mut order: Vec<(u64, Digest)> = carried.iter().map(|(d, c): (&Digest, &Carried)| (c.received_at, *d)).collect();
        order.sort();
        for (seq, (_, digest)) in order.iter().enumerate() {
            if let Some(c) = carried.get_mut(digest) {
                c.seq = seq as u64;
            }
        }
        let next_seq = order.len() as u64;
        let mut seen: VecDeque<(Digest, u64)> = store.load_seen().into_iter().filter(|(_, at)| now.saturating_sub(*at) <= config.seen_window_secs).collect();
        while seen.len() > config.seen_capacity {
            seen.pop_front();
        }
        let seen_set = seen.iter().map(|(d, _)| *d).collect();
        let uploaded: HashMap<Digest, u64> = store.load_uploaded().into_iter().filter(|(_, at)| now.saturating_sub(*at) <= UPLOADED_MEMORY_SECS).collect();
        let rng = config.seed | 1;
        MeshNode { config, store, clock, carried, seen, seen_set, links: HashMap::new(), contact_tags: HashSet::new(), my_tags: Vec::new(), uploading: HashSet::new(), refused: HashMap::new(), handed: HashSet::new(), uploaded, offline_only: HashMap::new(), link_online: HashMap::new(), already_uploaded: 0, copy_events: Vec::new(), copy_held_logged: HashSet::new(), next_seq, rng, stats: NodeStats::default(), version: 0 }
    }

    pub fn config(&self) -> &MeshConfig {
        &self.config
    }

    pub fn stats(&self) -> NodeStats {
        let mut stats = self.stats.clone();
        stats.carried = self.carried.len();
        stats.carried_bytes = self.carried.values().map(|c| c.packet.wire_len()).sum();
        stats
    }

    /// A number that changes whenever the packets carried or the recently seen digests change (so does what a Hello would say). Idle meetings,
    /// duplicates and frames that change nothing leave it alone.
    pub fn summary_version(&self) -> u64 {
        self.version
    }

    /// Whether another phone has acknowledged taking a copy of this packet (or it reached its recipient) since this phone started.
    pub fn was_handed(&self, digest: &Digest) -> bool {
        self.handed.contains(digest)
    }

    pub fn link_count(&self) -> usize {
        self.links.len()
    }

    pub fn carried_digests(&self) -> Vec<Digest> {
        self.carried.keys().copied().collect()
    }

    /// The recipient tags this phone answers to (today's and yesterday's, for each of its devices). Announced in every Hello, so a phone that
    /// holds the last copy of mail for this phone can hand it over when they meet. The platform sets them at start and when the day changes.
    pub fn set_my_tags(&mut self, tags: &[Tag]) {
        // A Hello carries these tags: when they change, what a Hello would say changed, so the platform sends a new one.
        if self.my_tags != tags {
            self.version += 1;
        }
        self.my_tags = tags.to_vec();
    }

    /// The tags of accepted contacts' devices (today's and yesterday's): packets for them are worth more than a stranger's.
    pub fn set_contact_tags(&mut self, tags: HashSet<Tag>) {
        self.contact_tags = tags;
    }

    // ------------------------------------------------------------------ the app's side

    /// A packet this phone made: stored with the highest tier, `ttl` hops (shorter with many links), `copies_initial` copies.
    pub fn enqueue(&mut self, packet: Packet) -> Result<Digest, EnqueueError> {
        self.enqueue_as(packet, Tier::Own, self.config.max_lifetime_secs)
    }

    /// `enqueue` with the tier it is stored at and the longest it may live from now.
    fn enqueue_as(&mut self, mut packet: Packet, tier: Tier, lifetime: u64) -> Result<Digest, EnqueueError> {
        let now = self.clock.now_secs();
        self.housekeeping();
        if packet.expires_at <= now {
            return Err(EnqueueError::Expired);
        }
        packet.expires_at = packet.expires_at.min(now + lifetime.min(self.config.max_lifetime_secs));
        packet.hops_left = self.effective_ttl();
        if packet.wire_len() > self.config.max_packet_bytes {
            return Err(EnqueueError::TooLarge);
        }
        let digest = packet.digest();
        if self.carried.contains_key(&digest) {
            return Ok(digest);
        }
        self.remember_seen(digest);
        if self.admit(packet, self.config.copies_initial, tier, now) { Ok(digest) } else { Err(EnqueueError::NoRoom) }
    }

    /// A copy of mail this phone already sent to the server (LIME-156): like [`enqueue`](Self::enqueue), but it lives 6 hours, is offered only to
    /// neighbours that say they are offline, and is never uploaded by this phone.
    pub fn enqueue_copy(&mut self, packet: Packet, direct: bool) -> Result<Digest, EnqueueError> {
        let digest = self.enqueue_as(packet, Tier::Contact, COPY_LIFETIME_SECS)?;
        self.offline_only.insert(digest, direct);
        Ok(digest)
    }

    /// Takes a copy off the mesh (the platform dropped its outbox row: the oldest copies go first when there is no room for more).
    pub fn discard(&mut self, digest: &Digest) {
        self.offline_only.remove(digest);
        if self.carried.remove(digest).is_some() {
            self.store.remove(digest);
            self.version += 1;
        }
    }

    /// Marks a carried packet as a copy again after a restart (the platform remembers which ones are).
    pub fn mark_offline_only(&mut self, digest: &Digest, direct: bool) {
        if self.carried.contains_key(digest) {
            self.offline_only.insert(*digest, direct);
        }
    }

    /// A neighbour said whether it is online. Returns whether copies are now on offer to it (it is offline) and were not before.
    pub fn set_link_online(&mut self, link: LinkId, online: bool) -> bool {
        let before = self.link_online.insert(link, online);
        before != Some(false) && !online && self.carried.keys().any(|d| self.offline_only.contains_key(d))
    }

    /// What happened to copies since the last call (handed over, or held back and why), for the log.
    pub fn take_copy_events(&mut self) -> Vec<CopyEvent> {
        std::mem::take(&mut self.copy_events)
    }

    /// Whether this phone uploaded the packet before.
    pub fn was_uploaded(&self, digest: &Digest) -> bool {
        self.uploaded.contains_key(digest)
    }

    /// How many packets were left out of the upload list since the last call because they were uploaded before.
    pub fn take_already_uploaded(&mut self) -> u32 {
        std::mem::take(&mut self.already_uploaded)
    }

    /// Mail for this phone (any packet whose tag is one of `my_tags`), taken out of the store. Also remembers the tags for meetings.
    pub fn take_mine(&mut self, my_tags: &[Tag]) -> Vec<Delivered> {
        self.my_tags = my_tags.to_vec();
        self.housekeeping();
        let mine: Vec<Digest> = self.carried.iter().filter(|(_, c)| my_tags.contains(&c.packet.tag)).map(|(d, _)| *d).collect();
        let mut out = Vec::new();
        for digest in mine {
            if let Some(c) = self.carried.remove(&digest) {
                self.store.remove(&digest);
                self.version += 1;
                self.remember_seen(digest);
                out.push(Delivered { digest, payload: c.packet.payload, hops_left: c.packet.hops_left, expires_at: c.packet.expires_at });
            }
        }
        out.sort_by_key(|d| d.digest);
        out
    }

    /// What this phone carries that the server could take (everything but mail for this phone), for `mesh-drop`. Each stays carried until
    /// [`confirm_uploaded`](Self::confirm_uploaded) says the server has it; [`upload_failed`](Self::upload_failed) offers it again.
    pub fn take_uploadable(&mut self) -> Vec<Uploadable> {
        self.housekeeping();
        let now = self.clock.now_secs();
        let again: Vec<Digest> = self.carried.keys().filter(|d| self.uploaded.contains_key(*d)).copied().collect();
        for digest in again {
            self.carried.remove(&digest);
            self.store.remove(&digest);
            self.version += 1;
            self.already_uploaded += 1;
        }
        let mut out: Vec<Uploadable> = self
            .carried
            .iter()
            .filter(|(d, c)| !self.uploading.contains(*d) && !self.offline_only.contains_key(*d) && !self.my_tags.contains(&c.packet.tag) && self.refused.get(*d).map(|(_, after)| *after <= now).unwrap_or(true))
            .map(|(d, c)| Uploadable { digest: *d, header: c.packet.header.clone(), payload: c.packet.payload.clone() })
            .collect();
        out.sort_by_key(|u| u.digest);
        for u in &out {
            self.uploading.insert(u.digest);
        }
        out
    }

    pub fn confirm_uploaded(&mut self, digest: &Digest) {
        self.uploading.remove(digest);
        if self.carried.remove(digest).is_some() {
            self.store.remove(digest);
            self.version += 1;
        }
        self.remember_seen(*digest);
        let now = self.clock.now_secs();
        if self.uploaded.insert(*digest, now).is_none() {
            self.store.save_uploaded(digest, now);
        }
    }

    pub fn upload_failed(&mut self, digest: &Digest) {
        self.uploading.remove(digest);
    }

    /// The server refused the packet (403). Kept and tried again later (10 minutes, then 20), up to [`MAX_REFUSALS`] refusals, then dropped.
    /// Returns `(refusals so far, dropped)`.
    pub fn upload_refused(&mut self, digest: &Digest) -> (u32, bool) {
        let now = self.clock.now_secs();
        let count = self.refused.get(digest).map(|(n, _)| *n).unwrap_or(0) + 1;
        if count >= MAX_REFUSALS {
            self.refused.remove(digest);
            self.confirm_uploaded(digest);
            return (count, true);
        }
        self.refused.insert(*digest, (count, now + 600 * u64::from(count)));
        self.uploading.remove(digest);
        (count, false)
    }

    // ------------------------------------------------------------------ the radio's side

    /// A link to another phone is up: answers with this phone's Hello (the summary of what it holds).
    pub fn on_link_up(&mut self, link: LinkId) -> Vec<Action> {
        self.housekeeping();
        // A Hello sent again on a live link (a wake, a queued copy) must not forget what the neighbour said about itself (its tags).
        self.links.entry(link).or_default();
        let hello = Frame::Hello { summary: self.summary_for(link), tags: self.my_tags.iter().take(255).copied().collect() };
        vec![self.send(link, hello)]
    }

    pub fn on_link_down(&mut self, link: LinkId) {
        self.links.remove(&link);
        self.link_online.remove(&link);
    }

    /// A frame arrived on `link`.
    pub fn on_frame(&mut self, link: LinkId, bytes: &[u8]) -> Vec<Action> {
        self.housekeeping();
        if !self.links.contains_key(&link) {
            // A frame from a link the platform did not announce: tolerated (duplicates and late frames happen).
            self.links.insert(link, LinkState::default());
        }
        let Some(frame) = Frame::decode(bytes) else {
            self.stats.bad_frames += 1;
            return Vec::new();
        };
        match frame {
            Frame::Hello { summary, tags } => self.on_hello(link, summary, tags),
            Frame::Want { digests } => self.on_want(link, digests),
            Frame::Packet { copies, bytes } => self.on_packet(link, copies, bytes),
            Frame::Ack { digest } => {
                self.on_ack(link, digest);
                Vec::new()
            }
        }
    }

    fn on_hello(&mut self, link: LinkId, summary: Vec<Short>, tags: Vec<Tag>) -> Vec<Action> {
        let have: HashSet<Short> = self.carried.keys().map(short).collect();
        let want: Vec<Short> = summary
            .iter()
            .filter(|s| !have.contains(*s) && !self.seen_set.iter().any(|d| short(d) == **s) && !self.uploaded.keys().any(|d| short(d) == **s))
            .take(self.config.want_max)
            .copied()
            .collect();
        if let Some(state) = self.links.get_mut(&link) {
            state.peer_summary = summary.into_iter().collect();
            state.peer_tags = tags;
        }
        if want.is_empty() { Vec::new() } else { vec![self.send(link, Frame::Want { digests: want })] }
    }

    /// What this phone would hand `link` for one carried packet, under every rule: a copy of mail already on the server only to an offline
    /// neighbour (and a group copy only to its own recipient), nothing expired, the recipient gets it whatever the copies, anyone else half the
    /// copies and one hop less. `(copies handed, the packet to put on the wire, whether it goes to its recipient)`.
    fn plan_offer(&mut self, link: LinkId, digest: &Digest, peer_tags: &[Tag], now: u64, cap: u8) -> Option<(u8, Packet, bool)> {
        let carried = self.carried.get(digest)?;
        // A copy of mail already on the server goes only to a neighbour that said it is offline.
        if let Some(direct) = self.offline_only.get(digest).copied() {
            let why = match self.link_online.get(&link) {
                Some(true) => Some("online"),
                None => Some("unknown"),
                Some(false) if direct && !peer_tags.contains(&carried.packet.tag) => Some("no_tag_match"),
                Some(false) => None,
            };
            if let Some(why) = why {
                if self.copy_held_logged.insert((*digest, why)) {
                    self.copy_events.push(CopyEvent::Held { link, digest: *digest, why });
                }
                return None;
            }
        }
        if carried.packet.expires_at <= now {
            return None;
        }
        if peer_tags.contains(&carried.packet.tag) {
            // The recipient is here: hand it over, whatever the hops and copies.
            Some((1, carried.packet.clone(), true))
        } else if carried.copies > 1 && carried.packet.hops_left >= 1 {
            let give = carried.copies / 2;
            let mut out = carried.packet.clone();
            out.hops_left = (carried.packet.hops_left - 1).min(cap);
            Some((give, out, false))
        } else {
            None
        }
    }

    /// Whether this phone made the packet itself (or is leaving a copy of its own mail): such a packet goes out at once, in order; only what it
    /// forwards for others gets the relay jitter.
    fn is_authored(&self, digest: &Digest) -> bool {
        self.offline_only.contains_key(digest) || self.carried.get(digest).map(|c| c.tier == Tier::Own).unwrap_or(false)
    }

    fn on_want(&mut self, link: LinkId, wanted: Vec<Short>) -> Vec<Action> {
        let now = self.clock.now_secs();
        let by_short: HashMap<Short, Digest> = self.carried.keys().map(|d| (short(d), *d)).collect();
        let peer_tags = self.links.get(&link).map(|l| l.peer_tags.clone()).unwrap_or_default();
        let cap = self.effective_ttl();
        // Best first: higher tier, then in the order they arrived here (a message before the reaction made after it).
        let mut eligible: Vec<(Digest, u8, Packet, bool)> = Vec::new();
        for want in wanted.iter().take(self.config.want_max) {
            let Some(digest) = by_short.get(want) else { continue };
            if let Some((copies, packet, to_recipient)) = self.plan_offer(link, digest, &peer_tags, now, cap) {
                eligible.push((*digest, copies, packet, to_recipient));
            }
        }
        eligible.sort_by_key(|(d, _, _, _)| {
            let c = &self.carried[d];
            (std::cmp::Reverse(c.tier), c.seq, *d)
        });
        let mut actions = Vec::new();
        for (digest, copies, packet, to_recipient) in eligible {
            actions.push(self.packet_action(link, &digest, copies, packet, to_recipient));
        }
        actions
    }

    /// Records a packet as sent on `link` (waiting for its Ack) and makes the frame: at once for what this phone made, with the relay jitter for
    /// what it forwards.
    fn packet_action(&mut self, link: LinkId, digest: &Digest, copies: u8, packet: Packet, to_recipient: bool) -> Action {
        self.stats.sent_packets += 1;
        if self.offline_only.contains_key(digest) {
            self.copy_events.push(CopyEvent::Handed { link, digest: *digest });
        }
        let immediate = self.is_authored(digest);
        if let Some(state) = self.links.get_mut(&link) {
            state.pending.insert(short(digest), (*digest, copies, to_recipient));
            state.peer_summary.insert(short(digest));
        }
        let frame = Frame::Packet { copies, bytes: packet.encode() };
        let delay_ms = if immediate { 0 } else { self.jitter() };
        Action::SendFrame { link, bytes: frame.encode(), delay_ms }
    }

    /// New packets this phone just made (or copies it left): put on every live link that may have them, now, in the order they were made, without
    /// waiting for a Hello and a Want (LIME-161). A link that already lists the packet, or has it waiting for an Ack, is skipped; Hello and Want stay as
    /// the catch-up for links that come up later.
    pub fn push_new(&mut self, digests: &[Digest]) -> Vec<Action> {
        let now = self.clock.now_secs();
        let cap = self.effective_ttl();
        let mut links: Vec<LinkId> = self.links.keys().copied().collect();
        links.sort();
        let mut actions = Vec::new();
        for link in links {
            let peer_tags = self.links.get(&link).map(|l| l.peer_tags.clone()).unwrap_or_default();
            for digest in digests {
                let known = self.links.get(&link).map(|l| l.peer_summary.contains(&short(digest)) || l.pending.contains_key(&short(digest))).unwrap_or(true);
                if known {
                    continue;
                }
                if let Some((copies, packet, to_recipient)) = self.plan_offer(link, digest, &peer_tags, now, cap) {
                    actions.push(self.packet_action(link, digest, copies, packet, to_recipient));
                }
            }
        }
        actions
    }

    fn on_packet(&mut self, link: LinkId, copies: u8, bytes: Vec<u8>) -> Vec<Action> {
        let now = self.clock.now_secs();
        // The per-link rate limit: a neighbour that floods is ignored beyond its allowance.
        let limit = self.config.link_packets_per_minute;
        if let Some(state) = self.links.get_mut(&link) {
            if now.saturating_sub(state.window_start) >= 60 {
                state.window_start = now;
                state.accepted_in_window = 0;
            }
            if state.accepted_in_window >= limit {
                self.stats.rate_limited += 1;
                return Vec::new();
            }
            state.accepted_in_window += 1;
        }
        let Ok(packet) = Packet::decode(&bytes) else {
            self.stats.bad_frames += 1;
            return Vec::new();
        };
        if packet.expires_at <= now || packet.expires_at > now + self.config.max_lifetime_secs + 60 || packet.wire_len() > self.config.max_packet_bytes {
            self.stats.rejected += 1;
            return Vec::new();
        }
        let digest = packet.digest();
        let ack = vec![self.send(link, Frame::Ack { digest: short(&digest) })];
        if self.carried.contains_key(&digest) || self.seen_set.contains(&digest) || self.uploaded.contains_key(&digest) {
            self.stats.duplicates += 1;
            return ack;
        }
        let tier = if self.my_tags.contains(&packet.tag) { Tier::Own } else if self.contact_tags.contains(&packet.tag) { Tier::Contact } else { Tier::Stranger };
        self.remember_seen(digest);
        if self.admit(packet, copies.clamp(1, self.config.copies_cap), tier, now) {
            self.stats.received += 1;
            ack
        } else {
            // No room for it here: no Ack, so the sender still counts it as its own and may offer it elsewhere.
            self.stats.rejected += 1;
            Vec::new()
        }
    }

    fn on_ack(&mut self, link: LinkId, digest: Short) {
        let Some((full, given, to_recipient)) = self.links.get_mut(&link).and_then(|l| l.pending.remove(&digest)) else { return };
        if self.handed.len() < 10_000 {
            self.handed.insert(full);
        }
        if to_recipient {
            // Delivered to its recipient: no need to carry it on.
            if self.carried.remove(&full).is_some() {
                self.store.remove(&full);
                self.version += 1;
            }
            return;
        }
        if let Some(c) = self.carried.get_mut(&full) {
            c.copies = c.copies.saturating_sub(given).max(1);
            let stored = StoredPacket { bytes: c.packet.encode(), copies: c.copies, tier: c.tier, received_at: c.received_at };
            self.store.save(&stored);
        }
    }

    // ------------------------------------------------------------------ the store's rules

    fn effective_ttl(&self) -> u8 {
        if self.links.len() >= self.config.many_links { self.config.ttl.min(self.config.ttl_cap_many_links) } else { self.config.ttl }
    }

    /// The summary for one link: copies are left out unless that neighbour said it is offline.
    fn summary_for(&self, link: LinkId) -> Vec<Short> {
        let mut out = self.summary();
        if !self.offline_only.is_empty() && self.link_online.get(&link) != Some(&false) {
            let hidden: HashSet<Short> = self.offline_only.keys().map(short).collect();
            out.retain(|s| !hidden.contains(s));
        }
        out
    }

    /// The summary a Hello carries: what I hold (best first), then what I have recently seen, up to `summary_max`.
    fn summary(&self) -> Vec<Short> {
        let mut held: Vec<(&Digest, &Carried)> = self.carried.iter().collect();
        held.sort_by_key(|(d, c)| (std::cmp::Reverse(c.tier), std::cmp::Reverse(c.received_at), **d));
        let mut out: Vec<Short> = held.iter().map(|(d, _)| short(d)).collect();
        for (d, _) in self.seen.iter().rev() {
            if out.len() >= self.config.summary_max {
                break;
            }
            let s = short(d);
            if !out.contains(&s) {
                out.push(s);
            }
        }
        out.truncate(self.config.summary_max);
        out
    }

    /// Drops what has expired and forgets what has been seen too long ago.
    pub fn housekeeping(&mut self) {
        let now = self.clock.now_secs();
        let expired: Vec<Digest> = self.carried.iter().filter(|(_, c)| c.packet.expires_at <= now).map(|(d, _)| *d).collect();
        for digest in expired {
            self.carried.remove(&digest);
            self.store.remove(&digest);
            self.stats.expired += 1;
            self.version += 1;
        }
        self.offline_only.retain(|d, _| self.carried.contains_key(d));
        self.uploaded.retain(|_, at| now.saturating_sub(*at) <= UPLOADED_MEMORY_SECS);
        while let Some((digest, at)) = self.seen.front().copied() {
            if now.saturating_sub(at) > self.config.seen_window_secs {
                self.seen.pop_front();
                self.seen_set.remove(&digest);
            } else {
                break;
            }
        }
    }

    fn remember_seen(&mut self, digest: Digest) {
        let now = self.clock.now_secs();
        if self.seen_set.insert(digest) {
            self.seen.push_back((digest, now));
            self.store.save_seen(&digest, now);
            self.version += 1;
        }
        while self.seen.len() > self.config.seen_capacity {
            if let Some((old, _)) = self.seen.pop_front() {
                self.seen_set.remove(&old);
            }
        }
    }

    /// Stores a packet if the budgets allow it, evicting lower-value packets first (lowest tier, then oldest); never evicts something worth
    /// more than the newcomer. Returns whether it was stored.
    fn admit(&mut self, packet: Packet, copies: u8, tier: Tier, now: u64) -> bool {
        let size = packet.wire_len();
        let digest = packet.digest();
        // Per recipient tag.
        let same_tag: Vec<Digest> = self.carried.iter().filter(|(_, c)| c.packet.tag == packet.tag).map(|(d, _)| *d).collect();
        if same_tag.len() >= self.config.per_tag_cap {
            let victim = same_tag.iter().filter(|d| self.carried[*d].tier <= tier).min_by_key(|d| (self.carried[*d].tier, self.carried[*d].received_at, **d)).copied();
            match victim {
                Some(v) => self.evict(&v),
                None => return false,
            }
        }
        // The strangers' share of the store.
        if tier == Tier::Stranger {
            let share = self.config.store_cap_bytes * self.config.stranger_share_percent / 100;
            loop {
                let used: usize = self.carried.values().filter(|c| c.tier == Tier::Stranger).map(|c| c.packet.wire_len()).sum();
                if used + size <= share {
                    break;
                }
                let victim = self.carried.iter().filter(|(_, c)| c.tier == Tier::Stranger).min_by_key(|(d, c)| (c.received_at, **d)).map(|(d, _)| *d);
                match victim {
                    Some(v) => self.evict(&v),
                    None => return false,
                }
            }
        }
        // The whole store.
        loop {
            let used: usize = self.carried.values().map(|c| c.packet.wire_len()).sum();
            if used + size <= self.config.store_cap_bytes {
                break;
            }
            let victim = self.carried.iter().min_by_key(|(d, c)| (c.tier, c.received_at, **d)).map(|(d, c)| (*d, c.tier));
            match victim {
                Some((v, victim_tier)) if victim_tier <= tier => self.evict(&v),
                _ => return false,
            }
        }
        let stored = StoredPacket { bytes: packet.encode(), copies, tier, received_at: now };
        self.store.save(&stored);
        let seq = self.next_seq;
        self.next_seq += 1;
        self.carried.insert(digest, Carried { packet, copies, tier, received_at: now, seq });
        self.version += 1;
        true
    }

    fn evict(&mut self, digest: &Digest) {
        if self.carried.remove(digest).is_some() {
            self.store.remove(digest);
            self.stats.evicted += 1;
            self.version += 1;
        }
    }

    // ------------------------------------------------------------------ small things

    fn jitter(&mut self) -> u32 {
        // xorshift64: deterministic for a given seed.
        self.rng ^= self.rng << 13;
        self.rng ^= self.rng >> 7;
        self.rng ^= self.rng << 17;
        let span = self.config.jitter_max_ms.saturating_sub(self.config.jitter_min_ms) as u64 + 1;
        self.config.jitter_min_ms + (self.rng % span) as u32
    }

    /// Relay jitter (a delay hint) goes only on the packets a phone forwards, so two phones' relays do not line up in time; the small
    /// control frames (Hello, Want, Ack) go at once, which also keeps them in order on a link.
    fn send(&mut self, link: LinkId, frame: Frame) -> Action {
        let delay_ms = if matches!(frame, Frame::Packet { .. }) { self.jitter() } else { 0 };
        Action::SendFrame { link, bytes: frame.encode(), delay_ms }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::MemoryStore;
    use std::cell::Cell;
    use std::rc::Rc;

    #[derive(Clone)]
    struct TestClock(Rc<Cell<u64>>);
    impl Clock for TestClock {
        fn now_secs(&self) -> u64 {
            self.0.get()
        }
    }

    type Node = MeshNode<MemoryStore, TestClock>;

    fn node_with(config: MeshConfig, clock: &TestClock) -> Node {
        MeshNode::new(config, MemoryStore::default(), clock.clone())
    }

    fn clock() -> TestClock {
        TestClock(Rc::new(Cell::new(1_000_000)))
    }

    fn packet(tag: u8, n: u8, clock: &TestClock) -> Packet {
        Packet { tag: [tag; 16], header: vec![n; 40], payload: vec![n; 100], hops_left: 7, expires_at: clock.0.get() + 3600 }
    }

    /// Lets two nodes meet and trades frames until nothing more is sent.
    fn meet(a: &mut Node, b: &mut Node) {
        let (la, lb) = (LinkId(2), LinkId(1)); // each side names the link by the other's id
        let mut queue: Vec<(bool, Vec<u8>)> = Vec::new(); // (to_b, bytes)
        for action in a.on_link_up(la) {
            let Action::SendFrame { bytes, .. } = action;
            queue.push((true, bytes));
        }
        for action in b.on_link_up(lb) {
            let Action::SendFrame { bytes, .. } = action;
            queue.push((false, bytes));
        }
        let mut guard = 0;
        while let Some((to_b, bytes)) = (!queue.is_empty()).then(|| queue.remove(0)) {
            guard += 1;
            assert!(guard < 10_000, "a meeting must end");
            let actions = if to_b { b.on_frame(lb, &bytes) } else { a.on_frame(la, &bytes) };
            for action in actions {
                let Action::SendFrame { bytes, .. } = action;
                queue.push((!to_b, bytes));
            }
        }
        a.on_link_down(la);
        b.on_link_down(lb);
    }

    #[test]
    fn a_packet_hops_to_a_courier_with_half_the_copies_and_one_fewer_hop() {
        let c = clock();
        let four = MeshConfig { copies_initial: 4, ..MeshConfig::default() };
        let mut a = node_with(four.clone(), &c);
        let mut b = node_with(four, &c);
        let digest = a.enqueue(packet(1, 1, &c)).unwrap();
        meet(&mut a, &mut b);
        assert_eq!(a.carried[&digest].copies, 2, "4 copies: half handed over and acked, the holder keeps 2");
        assert_eq!(b.carried[&digest].copies, 2);
        assert_eq!(a.carried[&digest].packet.hops_left, 7);
        assert_eq!(b.carried[&digest].packet.hops_left, 6);
        assert_eq!(b.carried[&digest].tier, Tier::Stranger);
        // A third phone meets B: B hands over half of ITS copies (1), and keeps 1.
        let mut third = node_with(MeshConfig::default(), &c);
        meet(&mut b, &mut third);
        assert_eq!(b.carried[&digest].copies, 1);
        assert_eq!(third.carried[&digest].copies, 1);
        assert_eq!(third.carried[&digest].packet.hops_left, 5);
    }

    #[test]
    fn with_one_copy_left_a_holder_waits_for_the_recipient_and_hands_it_over_when_they_meet() {
        let c = clock();
        let mut config = MeshConfig::default();
        config.copies_initial = 2;
        let mut a = node_with(config.clone(), &c);
        let mut b = node_with(config.clone(), &c);
        let digest = a.enqueue(packet(7, 1, &c)).unwrap();
        meet(&mut a, &mut b); // both now hold 1 copy
        assert_eq!((a.carried[&digest].copies, b.carried[&digest].copies), (1, 1));
        // A stranger who is not the recipient gets nothing more.
        let mut stranger = node_with(config.clone(), &c);
        meet(&mut b, &mut stranger);
        assert!(stranger.carried.is_empty(), "the wait phase: the last copy is not handed to just anyone");
        // The recipient (it answers to tag 7) meets B: it gets the packet, and B drops its copy.
        let mut recipient = node_with(config, &c);
        assert!(recipient.take_mine(&[[7; 16]]).is_empty());
        meet(&mut b, &mut recipient);
        let mine = recipient.take_mine(&[[7; 16]]);
        assert_eq!(mine.len(), 1);
        assert_eq!(mine[0].payload, vec![1; 100]);
        assert!(!b.carried.contains_key(&digest), "delivered: nothing left to carry");
    }

    #[test]
    fn a_packet_seen_before_is_not_stored_or_counted_twice() {
        let c = clock();
        let mut a = node_with(MeshConfig::default(), &c);
        let mut b = node_with(MeshConfig::default(), &c);
        let digest = a.enqueue(packet(1, 1, &c)).unwrap();
        meet(&mut a, &mut b);
        let before = b.stats().received;
        meet(&mut a, &mut b);
        assert_eq!(b.stats().received, before, "the summary says B has it: nothing is sent again");
        assert_eq!(b.carried.len(), 1);
        // A packet B forwarded and evicted is still remembered for a while, so it does not come back at once.
        b.evict(&digest);
        assert!(b.seen_set.contains(&digest));
        meet(&mut a, &mut b);
        assert!(!b.carried.contains_key(&digest), "seen within the window: not taken again");
        // After the window it may be taken again.
        c.0.set(c.0.get() + 301);
        meet(&mut a, &mut b);
        assert!(b.carried.contains_key(&digest));
    }

    #[test]
    fn hops_run_out_and_a_busy_node_hands_out_a_shorter_ttl() {
        let c = clock();
        let mut config = MeshConfig::default();
        config.ttl = 2;
        config.copies_initial = 8;
        let mut a = node_with(config.clone(), &c);
        let mut b = node_with(config.clone(), &c);
        let mut d = node_with(config.clone(), &c);
        let digest = a.enqueue(packet(1, 1, &c)).unwrap();
        meet(&mut a, &mut b); // b: hops 1
        meet(&mut b, &mut d); // d: hops 0
        assert_eq!(d.carried[&digest].packet.hops_left, 0);
        let mut e = node_with(config, &c);
        meet(&mut d, &mut e);
        assert!(e.carried.is_empty(), "TTL exhausted: no more forwarding to non-recipients");
        // A node with many links caps what it hands out.
        let mut busy = node_with(MeshConfig::default(), &c);
        for i in 0..6 {
            busy.on_link_up(LinkId(100 + i));
        }
        let own = busy.enqueue(packet(2, 2, &c)).unwrap();
        assert_eq!(busy.carried[&own].packet.hops_left, 5, "7 capped to 5 with 6 links");
        let mut calm = node_with(MeshConfig::default(), &c);
        let calm_digest = calm.enqueue(packet(3, 3, &c)).unwrap();
        assert_eq!(calm.carried[&calm_digest].packet.hops_left, 7);
    }

    #[test]
    fn expired_packets_are_dropped_and_never_taken() {
        let c = clock();
        let mut a = node_with(MeshConfig::default(), &c);
        let mut b = node_with(MeshConfig::default(), &c);
        let digest = a.enqueue(packet(1, 1, &c)).unwrap();
        assert_eq!(a.enqueue(Packet { expires_at: c.0.get() - 1, ..packet(1, 2, &c) }), Err(EnqueueError::Expired));
        // A lifetime beyond 48 h is cut to 48 h.
        let long = a.enqueue(Packet { expires_at: c.0.get() + 10 * 24 * 3600, ..packet(1, 3, &c) }).unwrap();
        assert_eq!(a.carried[&long].packet.expires_at, c.0.get() + 48 * 3600);
        c.0.set(c.0.get() + 3601);
        meet(&mut a, &mut b);
        assert!(!a.carried.contains_key(&digest), "gone after its hour");
        assert!(a.carried.contains_key(&long) && b.carried.contains_key(&long), "the long one is still carried");
        c.0.set(c.0.get() + 48 * 3600);
        a.housekeeping();
        assert!(a.carried.is_empty());
    }

    #[test]
    fn the_store_cap_evicts_the_lowest_tier_then_the_oldest_and_never_something_worth_more() {
        let c = clock();
        let mut config = MeshConfig::default();
        config.store_cap_bytes = 4 * 256; // four small packets
        config.stranger_share_percent = 100;
        let mut node = node_with(config, &c);
        node.set_contact_tags([[9; 16]].into_iter().collect());
        let mut digests = Vec::new();
        // Two strangers' packets, then a contact's, then my own.
        for (n, tag) in [(1u8, 1u8), (2, 1), (3, 9), (4, 2)] {
            c.0.set(c.0.get() + 1);
            let p = packet(tag, n, &c);
            let digest = p.digest();
            digests.push(digest);
            let tier = if tag == 9 { Tier::Contact } else if n == 4 { Tier::Own } else { Tier::Stranger };
            assert!(node.admit(p, 4, tier, c.0.get()));
        }
        assert_eq!(node.carried.len(), 4);
        // Another stranger's packet: the OLDEST stranger's packet goes.
        c.0.set(c.0.get() + 1);
        let p5 = packet(5, 5, &c);
        assert!(node.admit(p5.clone(), 4, Tier::Stranger, c.0.get()));
        assert!(!node.carried.contains_key(&digests[0]) && node.carried.contains_key(&digests[1]));
        // A contact's packet next: the remaining strangers go before the contact's or my own.
        c.0.set(c.0.get() + 1);
        assert!(node.admit(packet(9, 6, &c), 4, Tier::Contact, c.0.get()));
        assert!(!node.carried.contains_key(&digests[1]));
        assert!(node.carried.contains_key(&digests[2]) && node.carried.contains_key(&digests[3]));
        // Fill with higher tiers: a stranger can no longer get in, and my own packets are the last to go.
        for n in 7..10u8 {
            c.0.set(c.0.get() + 1);
            node.admit(packet(9, n, &c), 4, Tier::Contact, c.0.get());
        }
        assert!(!node.admit(packet(5, 77, &c), 4, Tier::Stranger, c.0.get()), "nothing lower to evict: refused");
        assert!(node.carried.contains_key(&digests[3]), "my own packet survived");
        assert!(node.stats().evicted >= 3);
    }

    #[test]
    fn a_recipient_tag_and_the_strangers_share_are_budgeted() {
        let c = clock();
        let mut config = MeshConfig::default();
        config.per_tag_cap = 3;
        let mut node = node_with(config, &c);
        for n in 0..5u8 {
            c.0.set(c.0.get() + 1);
            assert!(node.admit(packet(1, n, &c), 4, Tier::Stranger, c.0.get()));
        }
        assert_eq!(node.carried.values().filter(|p| p.packet.tag == [1; 16]).count(), 3, "at most 3 per recipient tag: the oldest went");
        assert!(node.carried.values().all(|p| p.packet.payload[0] >= 2));
        // The strangers' share: 40% of the store.
        let mut config = MeshConfig::default();
        config.store_cap_bytes = 10 * 256;
        let mut node = node_with(config, &c);
        for n in 0..10u8 {
            c.0.set(c.0.get() + 1);
            node.admit(packet(n + 20, n, &c), 4, Tier::Stranger, c.0.get());
        }
        assert_eq!(node.carried.len(), 4, "strangers hold at most 40% of the store");
        assert!(node.admit(packet(99, 99, &c), 4, Tier::Contact, c.0.get()), "contacts still have room");
    }

    #[test]
    fn a_flooding_neighbour_is_ignored_beyond_its_allowance() {
        let c = clock();
        let mut config = MeshConfig::default();
        config.link_packets_per_minute = 5;
        let mut victim = node_with(config.clone(), &c);
        let mut flooder = node_with(MeshConfig::default(), &c);
        for n in 0..30u8 {
            flooder.enqueue(packet(n, n, &c)).unwrap();
        }
        meet(&mut flooder, &mut victim);
        assert_eq!(victim.stats().received, 5, "only the allowance was taken");
        assert!(victim.stats().rate_limited > 0);
        // A minute later the next batch is welcome.
        c.0.set(c.0.get() + 61);
        meet(&mut flooder, &mut victim);
        assert_eq!(victim.stats().received, 10);
    }

    #[test]
    fn a_dropped_link_loses_nothing_the_packet_is_asked_for_again_at_the_next_meeting() {
        let c = clock();
        let mut a = node_with(MeshConfig::default(), &c);
        let mut b = node_with(MeshConfig::default(), &c);
        let digest = a.enqueue(packet(1, 1, &c)).unwrap();
        // A meeting that dies after the Packet frame is sent but before B's Ack comes back.
        let (la, lb) = (LinkId(2), LinkId(1));
        let hello_a = a.on_link_up(la);
        let hello_b = b.on_link_up(lb);
        let Action::SendFrame { bytes: ha, .. } = hello_a[0].clone();
        let Action::SendFrame { bytes: hb, .. } = hello_b[0].clone();
        let want = b.on_frame(lb, &ha);
        a.on_frame(la, &hb);
        let Action::SendFrame { bytes: want_bytes, .. } = want[0].clone();
        let packets = a.on_frame(la, &want_bytes);
        assert_eq!(packets.len(), 1);
        let Action::SendFrame { bytes: packet_bytes, .. } = packets[0].clone();
        let _lost_ack = b.on_frame(lb, &packet_bytes); // B stored it, the Ack never reaches A
        a.on_link_down(la);
        b.on_link_down(lb);
        assert_eq!(a.carried[&digest].copies, 8, "A did not count it as handed over (no Ack)");
        assert!(b.carried.contains_key(&digest));
        // Next meeting: B says it has it; nothing is re-sent, and the copy count stays honest (it was never acked).
        meet(&mut a, &mut b);
        assert_eq!(b.carried.len(), 1);
    }

    #[test]
    fn mail_is_recognised_by_tag_taken_once_and_uploadable_mail_is_everything_else() {
        let c = clock();
        let mut node = node_with(MeshConfig::default(), &c);
        let mine = node.enqueue(packet(1, 1, &c)).unwrap();
        let other = node.enqueue(packet(2, 2, &c)).unwrap();
        let up = node.take_uploadable();
        assert_eq!(up.len(), 2, "before it knows its tags, everything it carries is uploadable");
        for u in &up {
            node.upload_failed(&u.digest);
        }
        let delivered = node.take_mine(&[[1; 16]]);
        assert_eq!((delivered.len(), delivered[0].digest), (1, mine));
        assert!(node.take_mine(&[[1; 16]]).is_empty(), "taken once");
        let up = node.take_uploadable();
        assert_eq!(up.iter().map(|u| u.digest).collect::<Vec<_>>(), vec![other], "mail for this phone is not uploaded");
        assert!(node.take_uploadable().is_empty(), "offered once until it fails");
        node.upload_failed(&other);
        assert_eq!(node.take_uploadable().len(), 1);
        node.confirm_uploaded(&other);
        assert!(node.carried.is_empty());
    }

    #[test]
    fn a_refused_upload_is_retried_later_and_dropped_on_the_third_refusal() {
        let c = clock();
        let mut node = node_with(MeshConfig::default(), &c);
        let digest = node.enqueue(packet(2, 2, &c)).unwrap();
        assert_eq!(node.take_uploadable().len(), 1);
        assert_eq!(node.upload_refused(&digest), (1, false));
        assert!(node.take_uploadable().is_empty(), "not again at once");
        c.0.set(c.0.get() + 599);
        assert!(node.take_uploadable().is_empty(), "not before 10 minutes");
        c.0.set(c.0.get() + 2);
        assert_eq!(node.take_uploadable().len(), 1, "after 10 minutes it is offered again");
        assert_eq!(node.upload_refused(&digest), (2, false));
        c.0.set(c.0.get() + 1201);
        assert_eq!(node.take_uploadable().len(), 1, "after 20 minutes more");
        assert_eq!(node.upload_refused(&digest), (3, true), "the third refusal drops it");
        assert!(node.carried.is_empty());
    }

    #[test]
    fn jitter_stays_inside_the_configured_range_and_is_deterministic_for_a_seed() {
        let c = clock();
        let mut a = node_with(MeshConfig { seed: 42, ..MeshConfig::default() }, &c);
        let mut b = node_with(MeshConfig { seed: 42, ..MeshConfig::default() }, &c);
        let mut seen = HashSet::new();
        for _ in 0..200 {
            let (x, y) = (a.jitter(), b.jitter());
            assert_eq!(x, y);
            assert!((10..=220).contains(&x));
            seen.insert(x);
        }
        assert!(seen.len() > 50, "it actually varies");
    }

    #[test]
    fn a_node_that_restarts_keeps_what_it_carried_and_what_it_had_seen() {
        let c = clock();
        let mut a = node_with(MeshConfig::default(), &c);
        let digest = a.enqueue(packet(1, 1, &c)).unwrap();
        c.0.set(c.0.get() + 10);
        let store = a.store.clone();
        let again: Node = MeshNode::new(MeshConfig::default(), store, c.clone());
        assert!(again.carried.contains_key(&digest));
        assert_eq!(again.carried[&digest].tier, Tier::Own);
        assert!(again.seen_set.contains(&digest));
    }

    #[test]
    fn garbage_frames_and_packets_are_counted_and_ignored() {
        let c = clock();
        let mut node = node_with(MeshConfig::default(), &c);
        assert!(node.on_frame(LinkId(1), &[9, 9, 9]).is_empty());
        assert!(node.on_frame(LinkId(1), &Frame::Packet { copies: 1, bytes: vec![1; 300] }.encode()).is_empty());
        assert_eq!(node.stats().bad_frames, 2);
        // A packet that claims to outlive the lifetime limit is refused.
        let far = Packet { expires_at: c.0.get() + 30 * 24 * 3600, ..packet(1, 1, &c) };
        assert!(node.on_frame(LinkId(1), &Frame::Packet { copies: 1, bytes: far.encode() }.encode()).is_empty());
        assert_eq!(node.stats().rejected, 1);
        assert!(node.carried.is_empty());
    }

    #[test]
    fn the_summary_version_moves_only_when_what_a_hello_would_say_moves() {
        let c = clock();
        let mut a = node_with(MeshConfig::default(), &c);
        let mut b = node_with(MeshConfig::default(), &c);
        let start = a.summary_version();
        a.enqueue(packet(1, 1, &c)).unwrap();
        let after_enqueue = a.summary_version();
        assert!(after_enqueue > start, "a new packet");
        meet(&mut a, &mut b);
        assert!(b.summary_version() > 0, "the receiver's summary moved too");
        let (va, vb) = (a.summary_version(), b.summary_version());
        meet(&mut a, &mut b);
        meet(&mut a, &mut b);
        assert_eq!((a.summary_version(), b.summary_version()), (va, vb), "idle meetings change nothing");
        // A duplicate frame changes nothing either.
        let digest = a.carried_digests()[0];
        let bytes = a.carried[&digest].packet.encode();
        b.on_link_up(LinkId(7));
        b.on_frame(LinkId(7), &Frame::Packet { copies: 1, bytes }.encode());
        assert_eq!(b.summary_version(), vb);
        // Expiry and delivery move it.
        c.0.set(c.0.get() + 3601);
        a.housekeeping();
        assert!(a.summary_version() > va);
    }

    /// A meeting where `a` has heard `b`'s online bit (`bit`) and says its Hello again afterwards, as the platform does.
    fn meet_with_bit(a: &mut Node, b: &mut Node, bit: Option<bool>) {
        let (la, lb) = (LinkId(2), LinkId(1));
        let mut queue: Vec<(bool, Vec<u8>)> = Vec::new();
        for action in b.on_link_up(lb) {
            let Action::SendFrame { bytes, .. } = action;
            queue.push((false, bytes));
        }
        a.on_link_up(la);
        if let Some(on) = bit {
            a.set_link_online(la, on);
        }
        for action in a.on_link_up(la) {
            let Action::SendFrame { bytes, .. } = action;
            queue.push((true, bytes));
        }
        let mut guard = 0;
        while let Some((to_b, bytes)) = (!queue.is_empty()).then(|| queue.remove(0)) {
            guard += 1;
            assert!(guard < 10_000);
            let actions = if to_b { b.on_frame(lb, &bytes) } else { a.on_frame(la, &bytes) };
            for action in actions {
                let Action::SendFrame { bytes, .. } = action;
                queue.push((!to_b, bytes));
            }
        }
        a.on_link_down(la);
        b.on_link_down(lb);
    }

    #[test]
    fn a_copy_of_mail_already_on_the_server_goes_only_to_a_neighbour_that_says_it_is_offline_and_is_never_uploaded_by_its_sender() {
        let c = clock();
        let mut sender = node_with(MeshConfig::default(), &c);
        let copy = sender.enqueue_copy(Packet { expires_at: c.0.get() + 48 * 3600, ..packet(5, 5, &c) }, false).unwrap();
        assert!(sender.take_uploadable().is_empty(), "its sender never uploads a copy");
        let mut online = node_with(MeshConfig::default(), &c);
        meet_with_bit(&mut sender, &mut online, Some(true));
        assert_eq!(online.stats().received, 0, "an online neighbour is not offered it");
        let mut unknown = node_with(MeshConfig::default(), &c);
        meet_with_bit(&mut sender, &mut unknown, None);
        assert_eq!(unknown.stats().received, 0, "nor one that has not said");
        let mut offline = node_with(MeshConfig::default(), &c);
        meet_with_bit(&mut sender, &mut offline, Some(false));
        assert_eq!(offline.stats().received, 1, "an offline neighbour gets it");
        assert!(sender.was_handed(&copy));
        // The copy lives 6 hours, not 48.
        c.0.set(c.0.get() + 6 * 3600 + 1);
        let mut late = node_with(MeshConfig::default(), &c);
        meet_with_bit(&mut sender, &mut late, Some(false));
        assert_eq!(late.stats().received, 0, "after 6 hours it is gone");
    }

    #[test]
    fn a_carrier_does_not_take_back_or_upload_a_packet_it_uploaded_even_after_the_seen_window() {
        let c = clock();
        let mut carrier = node_with(MeshConfig::default(), &c);
        let original = packet(6, 6, &c);
        let digest = carrier.enqueue(original.clone()).unwrap();
        let up = carrier.take_uploadable();
        assert_eq!(up.len(), 1);
        carrier.confirm_uploaded(&digest);
        assert!(carrier.was_uploaded(&digest));
        // Past the 5 minute seen window, a neighbour that still holds it offers it again: it is not taken.
        c.0.set(c.0.get() + 400);
        let mut neighbour = node_with(MeshConfig::default(), &c);
        neighbour.enqueue(original).unwrap();
        meet(&mut neighbour, &mut carrier);
        assert!(carrier.take_uploadable().is_empty(), "not offered for upload again");
        // A restart keeps the memory.
        let store = MemoryStore { uploaded: vec![(digest, c.0.get())], ..MemoryStore::default() };
        let restarted = MeshNode::new(MeshConfig::default(), store, c.clone());
        assert!(restarted.was_uploaded(&digest));
        // 48 hours later it is forgotten.
        c.0.set(c.0.get() + 48 * 3600 + 1);
        let mut later = node_with(MeshConfig::default(), &c);
        later.uploaded.insert(digest, 0);
        later.housekeeping();
        assert!(!later.was_uploaded(&digest));
    }

    #[test]
    fn a_hello_sent_again_on_a_live_link_keeps_the_neighbours_tags_so_a_direct_copy_still_reaches_it() {
        let c = clock();
        let mut sender = node_with(MeshConfig::default(), &c);
        let mut receiver = node_with(MeshConfig::default(), &c);
        receiver.set_my_tags(&[[7; 16]]);
        let (ls, lr) = (LinkId(2), LinkId(1));
        // The receiver (just restarted) says its Hello with its tags; the sender hears it, then hears the receiver is offline.
        let hello = receiver.on_link_up(lr);
        let Action::SendFrame { bytes, .. } = hello[0].clone();
        sender.on_link_up(ls);
        sender.on_frame(ls, &bytes);
        sender.set_link_online(ls, false);
        // A copy is queued after the link is up; the platform says its Hello again on that link.
        sender.enqueue_copy(Packet { tag: [7; 16], expires_at: c.0.get() + 3600, ..packet(7, 7, &c) }, true).unwrap();
        let again = sender.on_link_up(ls);
        let Action::SendFrame { bytes, .. } = again[0].clone();
        let want = receiver.on_frame(lr, &bytes);
        let Action::SendFrame { bytes, .. } = want[0].clone();
        let packets = sender.on_frame(ls, &bytes);
        assert_eq!(packets.len(), 1, "the copy is handed over in one Hello round, whatever re-announced in between");
        let events = sender.take_copy_events();
        assert!(events.iter().any(|e| matches!(e, CopyEvent::Handed { .. })));
    }

    #[test]
    fn a_copy_that_cannot_go_says_why_once() {
        let c = clock();
        let mut sender = node_with(MeshConfig::default(), &c);
        sender.enqueue_copy(Packet { tag: [7; 16], expires_at: c.0.get() + 3600, ..packet(7, 7, &c) }, true).unwrap();
        let digest = sender.carried.keys().next().copied().unwrap();
        let want = vec![short(&digest)];
        let l = LinkId(2);
        sender.on_link_up(l);
        sender.on_frame(l, &Frame::Want { digests: want.clone() }.encode());
        sender.set_link_online(l, true);
        sender.on_frame(l, &Frame::Want { digests: want.clone() }.encode());
        sender.on_frame(l, &Frame::Want { digests: want.clone() }.encode());
        sender.set_link_online(l, false);
        sender.on_frame(l, &Frame::Want { digests: want }.encode());
        let whys: Vec<&str> = sender.take_copy_events().iter().filter_map(|e| if let CopyEvent::Held { why, .. } = e { Some(*why) } else { None }).collect();
        assert_eq!(whys, vec!["unknown", "online", "no_tag_match"], "each reason once");
    }

    #[test]
    fn changing_this_phones_tags_moves_the_summary_version_so_a_new_hello_goes() {
        let c = clock();
        let mut node = node_with(MeshConfig::default(), &c);
        let before = node.summary_version();
        node.set_my_tags(&[[1; 16]]);
        let after = node.summary_version();
        assert!(after > before);
        node.set_my_tags(&[[1; 16]]);
        assert_eq!(node.summary_version(), after, "the same tags change nothing");
    }

    /// A link that is up and whose Hello has been heard (`tags` its owner's).
    fn linked(node: &mut Node, link: u64, tags: Vec<Tag>) {
        node.on_link_up(LinkId(link));
        node.on_frame(LinkId(link), &Frame::Hello { summary: Vec::new(), tags }.encode());
    }

    #[test]
    fn a_new_packet_goes_to_a_linked_neighbour_at_once_in_the_order_it_was_made_without_a_hello_round() {
        let c = clock();
        let mut sender = node_with(MeshConfig::default(), &c);
        linked(&mut sender, 1, vec![[9; 16]]);
        // A message and, 100 ms later, a reaction to it (the same second: `received_at` alone could not tell them apart).
        let message = sender.enqueue(packet(1, 1, &c)).unwrap();
        let reaction = sender.enqueue(packet(1, 2, &c)).unwrap();
        let actions = sender.push_new(&[message, reaction]);
        assert_eq!(actions.len(), 2, "both frames leave now, with no Hello and no Want");
        let order: Vec<Digest> = actions
            .iter()
            .map(|a| {
                let Action::SendFrame { bytes, delay_ms, .. } = a;
                assert_eq!(*delay_ms, 0, "what this phone made goes out at once: no relay jitter");
                match Frame::decode(bytes) {
                    Some(Frame::Packet { bytes, .. }) => Packet::decode(&bytes).unwrap().digest(),
                    other => panic!("not a packet: {other:?}"),
                }
            })
            .collect();
        assert_eq!(order, vec![message, reaction], "a message always leaves before the reaction made after it");
        // Pushed once: a second push (or a Hello round) does not send them again.
        assert!(sender.push_new(&[message, reaction]).is_empty());
    }

    #[test]
    fn packets_wanted_in_one_round_keep_the_order_they_were_made_whatever_their_digests() {
        let c = clock();
        let mut sender = node_with(MeshConfig::default(), &c);
        let made: Vec<Digest> = (1..=12).map(|n| sender.enqueue(packet(1, n, &c)).unwrap()).collect();
        let l = LinkId(1);
        sender.on_link_up(l);
        let wanted: Vec<Short> = made.iter().rev().map(short).collect();
        let sent: Vec<Digest> = sender
            .on_frame(l, &Frame::Want { digests: wanted }.encode())
            .iter()
            .map(|a| {
                let Action::SendFrame { bytes, .. } = a;
                match Frame::decode(bytes) {
                    Some(Frame::Packet { bytes, .. }) => Packet::decode(&bytes).unwrap().digest(),
                    other => panic!("not a packet: {other:?}"),
                }
            })
            .collect();
        assert_eq!(sent, made, "creation order, not the order asked for and not the digests' order");
    }

    #[test]
    fn only_what_this_phone_forwards_for_others_keeps_the_relay_jitter() {
        let c = clock();
        let mut relay = node_with(MeshConfig::default(), &c);
        let mut author = node_with(MeshConfig::default(), &c);
        let l = LinkId(1);
        // Someone else's packet, handed to the relay.
        let theirs = packet(4, 4, &c);
        author.enqueue(theirs.clone()).unwrap();
        author.on_link_up(l);
        let digest = theirs.digest();
        let Action::SendFrame { bytes, .. } = author.on_frame(l, &Frame::Want { digests: vec![short(&digest)] }.encode())[0].clone();
        relay.on_link_up(l);
        relay.on_frame(l, &bytes);
        // The relay forwards it on: jitter applies (10 to 220 ms).
        relay.on_link_up(LinkId(2));
        let forwarded = relay.on_frame(LinkId(2), &Frame::Want { digests: vec![short(&digest)] }.encode());
        let Action::SendFrame { delay_ms, .. } = forwarded[0].clone();
        assert!((10..=220).contains(&delay_ms), "a forwarded packet keeps its jitter: {delay_ms}");
    }

    #[test]
    fn a_pushed_copy_still_follows_the_copy_rules() {
        let c = clock();
        let mut sender = node_with(MeshConfig::default(), &c);
        linked(&mut sender, 1, vec![[7; 16]]);
        linked(&mut sender, 2, vec![[7; 16]]);
        linked(&mut sender, 3, vec![[8; 16]]);
        sender.set_link_online(LinkId(1), true);
        sender.set_link_online(LinkId(2), false);
        sender.set_link_online(LinkId(3), false);
        let copy = sender.enqueue_copy(Packet { tag: [7; 16], expires_at: c.0.get() + 3600, ..packet(7, 7, &c) }, true).unwrap();
        let pushed = sender.push_new(&[copy]);
        let links: Vec<u64> = pushed.iter().map(|a| { let Action::SendFrame { link, .. } = a; link.0 }).collect();
        assert_eq!(links, vec![2], "an online neighbour and a phone that is not its recipient get nothing");
    }
}
