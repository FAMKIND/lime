//! The mesh simulator (LIME-140): many virtual phones, virtual time, scripted meetings, partings and sleeps, deterministic seeds. Every
//! scenario of the brief runs here and reports its delivery rate, hops and median delay (run `cargo test -p lime_mesh --test sim -- --nocapture`
//! to see the table). The radio is not simulated, only what it decides: who can talk to whom, and when.

use std::cell::Cell;
use std::cmp::Reverse;
use std::collections::{BinaryHeap, HashMap, HashSet};
use std::rc::Rc;

use lime_mesh::{Action, Clock, Digest, LinkId, MemoryStore, MeshConfig, MeshNode, Packet, Tag};
use sha2::{Digest as _, Sha256};

const START: u64 = 1_800_000_000;
/// Link latency on top of the jitter hint, milliseconds.
const LATENCY_MS: u64 = 20;

#[derive(Clone)]
struct SimClock(Rc<Cell<u64>>); // virtual milliseconds since START

impl Clock for SimClock {
    fn now_secs(&self) -> u64 {
        START + self.0.get() / 1000
    }
}

/// The simulator's stand-in for the platform's tags: a day-scoped pseudonym per phone (lime_core makes the real ones from the delivery key).
fn tag_of(phone: usize, day: u64) -> Tag {
    let digest = Sha256::digest([b"sim-tag".as_slice(), &(phone as u64).to_be_bytes(), &day.to_be_bytes()].concat());
    digest[..16].try_into().unwrap()
}

fn day_of(now_ms: u64) -> u64 {
    (START + now_ms / 1000) / 86_400
}

struct Phone {
    node: MeshNode<MemoryStore, SimClock>,
    awake: bool,
    internet: bool,
    inbox: Vec<(Digest, Vec<u8>, u8, u64)>, // digest, payload, hops_left, time (ms)
}

struct Event {
    at: u64,
    seq: u64,
    to: usize,
    link: LinkId,
    bytes: Vec<u8>,
    from: usize,
}

impl PartialEq for Event {
    fn eq(&self, other: &Self) -> bool {
        (self.at, self.seq) == (other.at, other.seq)
    }
}
impl Eq for Event {}
impl PartialOrd for Event {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}
impl Ord for Event {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        (self.at, self.seq).cmp(&(other.at, other.seq))
    }
}

struct World {
    now: Rc<Cell<u64>>,
    phones: Vec<Phone>,
    links: HashMap<(usize, usize), u64>, // (low, high) -> link id, present while up
    next_link: u64,
    queue: BinaryHeap<Reverse<Event>>,
    seq: u64,
    /// The server's mailbox for the internet scenarios: payloads that `mesh-drop` accepted.
    server: HashMap<Digest, Vec<u8>>,
    /// Every packet size seen on the wire.
    wire_sizes: HashSet<usize>,
    frames: u64,
}

impl World {
    fn new(count: usize, config: MeshConfig) -> World {
        let now = Rc::new(Cell::new(0u64));
        let phones = (0..count)
            .map(|i| Phone {
                node: MeshNode::new(MeshConfig { seed: config.seed + i as u64 * 7919, ..config.clone() }, MemoryStore::default(), SimClock(now.clone())),
                awake: true,
                internet: false,
                inbox: Vec::new(),
            })
            .collect();
        World { now, phones, links: HashMap::new(), next_link: 1, queue: BinaryHeap::new(), seq: 0, server: HashMap::new(), wire_sizes: HashSet::new(), frames: 0 }
    }

    fn now_ms(&self) -> u64 {
        self.now.get()
    }

    fn schedule(&mut self, from: usize, to: usize, link: LinkId, actions: Vec<Action>) {
        for action in actions {
            let Action::SendFrame { bytes, delay_ms, .. } = action;
            if bytes.first() == Some(&3) {
                // A Packet frame: [3, copies, len u32, packet...]: the packet is a bucket size on the wire.
                self.wire_sizes.insert(bytes.len() - 6);
            }
            self.frames += 1;
            self.seq += 1;
            let at = self.now_ms() + delay_ms as u64 + LATENCY_MS;
            self.queue.push(Reverse(Event { at, seq: self.seq, to, link, bytes, from }));
        }
    }

    /// The platform keeps each node's tags current (today's and yesterday's): done whenever a phone is about to meet someone.
    fn refresh_tags(&mut self, phone: usize) {
        let day = day_of(self.now_ms());
        self.phones[phone].node.set_my_tags(&[tag_of(phone, day), tag_of(phone, day - 1)]);
    }

    /// Two awake phones come into range: a link comes up on both.
    fn meet(&mut self, a: usize, b: usize) {
        if !self.phones[a].awake || !self.phones[b].awake || self.links.contains_key(&(a.min(b), a.max(b))) {
            return;
        }
        self.refresh_tags(a);
        self.refresh_tags(b);
        let id = self.next_link;
        self.next_link += 1;
        self.links.insert((a.min(b), a.max(b)), id);
        let link = LinkId(id);
        let actions = self.phones[a].node.on_link_up(link);
        self.schedule(a, b, link, actions);
        let actions = self.phones[b].node.on_link_up(link);
        self.schedule(b, a, link, actions);
    }

    /// They move apart: the link goes down on both, and frames still in flight on it are lost.
    fn part(&mut self, a: usize, b: usize) {
        if let Some(id) = self.links.remove(&(a.min(b), a.max(b))) {
            self.phones[a].node.on_link_down(LinkId(id));
            self.phones[b].node.on_link_down(LinkId(id));
        }
    }

    fn sleep(&mut self, phone: usize) {
        let linked: Vec<usize> = self.links.keys().filter(|(x, y)| *x == phone || *y == phone).map(|(x, y)| if *x == phone { *y } else { *x }).collect();
        for other in linked {
            self.part(phone, other);
        }
        self.phones[phone].awake = false;
    }

    fn wake(&mut self, phone: usize) {
        self.phones[phone].awake = true;
    }

    /// Runs the virtual clock forward to `until_ms`, delivering frames in order (a frame on a link that has gone down is lost).
    fn run_until(&mut self, until_ms: u64) {
        while let Some(Reverse(next)) = self.queue.peek() {
            if next.at > until_ms {
                break;
            }
            let Reverse(event) = self.queue.pop().unwrap();
            self.now.set(event.at);
            let up = self.links.get(&(event.from.min(event.to), event.from.max(event.to))) == Some(&event.link.0);
            if !up || !self.phones[event.to].awake {
                continue;
            }
            let actions = self.phones[event.to].node.on_frame(event.link, &event.bytes);
            self.schedule(event.to, event.from, event.link, actions);
        }
        self.now.set(until_ms.max(self.now.get()));
    }

    fn advance(&mut self, ms: u64) {
        let target = self.now_ms() + ms;
        self.run_until(target);
    }

    /// A meeting that lasts `ms` (long enough for everything to flow), then they part.
    fn meet_for(&mut self, a: usize, b: usize, ms: u64) {
        self.meet(a, b);
        self.advance(ms);
        self.part(a, b);
    }

    /// Phone `from` writes a message for phone `to`: a packet tagged for `to`'s tag of the day, a made-up sealed header, a unique payload.
    fn send_mail(&mut self, from: usize, to: usize, n: u32) -> Digest {
        let now = self.now_ms();
        let mut payload = format!("mail {from}->{to} #{n}").into_bytes();
        payload.resize(120, 7);
        let packet = Packet { tag: tag_of(to, day_of(now)), header: vec![n as u8; 60], payload, hops_left: 0, expires_at: START + now / 1000 + 48 * 3600 };
        self.phones[from].node.enqueue(packet).expect("room to enqueue")
    }

    /// The phone collects its own mail (today's and yesterday's tags): the application's side of the platform.
    fn collect(&mut self, phone: usize) {
        let now = self.now_ms();
        let day = day_of(now);
        let tags = [tag_of(phone, day), tag_of(phone, day - 1)];
        for d in self.phones[phone].node.take_mine(&tags) {
            self.phones[phone].inbox.push((d.digest, d.payload, d.hops_left, now));
        }
    }

    /// A phone with internet hands everything it carries to the server (the sim's `mesh-drop`).
    fn upload(&mut self, phone: usize) -> usize {
        let items = self.phones[phone].node.take_uploadable();
        let n = items.len();
        for item in items {
            self.server.insert(item.digest, item.payload);
            self.phones[phone].node.confirm_uploaded(&item.digest);
        }
        n
    }

    fn got(&self, phone: usize, digest: &Digest) -> bool {
        self.phones[phone].inbox.iter().any(|(d, _, _, _)| d == digest)
    }
}

const SEC: u64 = 1000;
const MIN: u64 = 60 * SEC;
const HOUR: u64 = 60 * MIN;

#[derive(Debug, Default)]
struct Report {
    name: String,
    sent: usize,
    delivered: usize,
    median_delay_s: f64,
    mean_hops: f64,
}

fn report(name: &str, sent: usize, delays_ms: &[u64], hops: &[f64]) -> Report {
    let mut sorted = delays_ms.to_vec();
    sorted.sort();
    let median = if sorted.is_empty() { f64::NAN } else { sorted[sorted.len() / 2] as f64 / 1000.0 };
    let mean_hops = if hops.is_empty() { f64::NAN } else { hops.iter().sum::<f64>() / hops.len() as f64 };
    Report { name: name.to_owned(), sent, delivered: delays_ms.len(), median_delay_s: median, mean_hops }
}

/// A chain: phone 0 is the author, the last phone the recipient, `relays` couriers between; each pair meets once, in order, for a minute.
fn chain(relays: usize, config: MeshConfig) -> (World, Digest) {
    let mut world = World::new(relays + 2, config);
    let to = relays + 1;
    let digest = world.send_mail(0, to, 1);
    for i in 0..=relays {
        world.advance(10 * MIN);
        world.meet_for(i, i + 1, MIN);
    }
    world.collect(to);
    (world, digest)
}

fn scenario_direct() -> Report {
    let (world, digest) = chain(0, MeshConfig::default());
    assert!(world.got(1, &digest));
    let (_, _, hops_left, at) = world.phones[1].inbox[0];
    report("A -> B direct", 1, &[at], &[(7 - hops_left) as f64 + 1.0])
}

fn scenario_relays(relays: usize, config: MeshConfig, label: &str) -> Report {
    let (world, digest) = chain(relays, config.clone());
    let to = relays + 1;
    if world.got(to, &digest) {
        let (_, _, hops_left, at) = world.phones[to].inbox[0];
        report(label, 1, &[at], &[(config.ttl - hops_left) as f64 + 1.0])
    } else {
        report(label, 1, &[], &[])
    }
}

fn scenario_asleep_then_wake() -> Report {
    let mut world = World::new(2, MeshConfig::default());
    let digest = world.send_mail(0, 1, 1);
    world.sleep(0);
    world.sleep(1);
    world.meet(0, 1); // in range, but both asleep: nothing happens
    world.advance(3 * HOUR);
    world.collect(1);
    assert!(!world.got(1, &digest), "asleep, nothing was exchanged");
    world.wake(0);
    world.wake(1);
    world.meet_for(0, 1, 5 * SEC);
    world.collect(1);
    assert!(world.got(1, &digest), "on the wake the whole backlog flushes in one meeting");
    let at = world.phones[1].inbox[0].3;
    report("both asleep 3 h, then a wake", 1, &[at], &[1.0])
}

fn scenario_relay_to_internet() -> Report {
    // 0 writes for 3; 1 is a courier that later reaches the internet; the server holds the payload for 3's mailbox.
    let mut world = World::new(4, MeshConfig::default());
    let digest = world.send_mail(0, 3, 1);
    world.advance(5 * MIN);
    world.meet_for(0, 1, 10 * SEC);
    assert!(world.phones[1].node.carried_digests().contains(&digest));
    world.advance(40 * MIN);
    world.phones[1].internet = true;
    let uploaded = world.upload(1);
    assert_eq!(uploaded, 1);
    assert!(world.server.contains_key(&digest), "the server has it for 3's mailbox");
    assert!(world.phones[1].node.carried_digests().is_empty(), "uploaded: no longer carried");
    // 3 reads it from its mailbox (the normal inbound path); the relay learned nothing about who it was for.
    let at = world.now_ms();
    report("relay reaches the internet (upload)", 1, &[at], &[1.0])
}

fn scenario_ttl_exhaustion() -> (Report, usize) {
    let mut config = MeshConfig::default();
    config.ttl = 2;
    config.copies_initial = 8;
    let (world, digest) = chain(4, config);
    let carriers = world.phones.iter().filter(|p| p.node.carried_digests().contains(&digest)).count();
    (report("TTL 2 across 4 relays", 1, if world.got(5, &digest) { &[1] } else { &[] }, &[]), carriers)
}

fn scenario_expiry() -> Report {
    let mut world = World::new(2, MeshConfig::default());
    let digest = world.send_mail(0, 1, 1);
    world.advance(49 * HOUR);
    world.meet_for(0, 1, 10 * SEC);
    world.collect(1);
    assert!(!world.got(1, &digest), "expired after 48 h: not delivered");
    world.phones[0].node.housekeeping();
    assert!(world.phones[0].node.carried_digests().is_empty(), "and no longer carried");
    report("expiry (b appears after 49 h)", 1, &[], &[])
}

fn scenario_duplicates() -> (Report, usize) {
    // 0 writes for 11; ten couriers each meet 0 (then 11): every path leads to 11, which must deliver it once.
    let mut world = World::new(12, MeshConfig { copies_initial: 8, ..MeshConfig::default() });
    let digest = world.send_mail(0, 11, 1);
    for courier in 1..=10 {
        world.advance(MIN);
        world.meet_for(0, courier, 10 * SEC);
    }
    for courier in 1..=10 {
        world.advance(MIN);
        world.meet_for(courier, 11, 10 * SEC);
    }
    world.collect(11);
    let n = world.phones[11].inbox.iter().filter(|(d, _, _, _)| *d == digest).count();
    (report("duplicates via many paths", 1, &[world.phones[11].inbox[0].3], &[]), n)
}

/// A crowd: `count` phones, `messages` random sender/recipient pairs, random meetings over `hours`.
fn scenario_crowd(count: usize, messages: usize, hours: u64, label: &str) -> Report {
    let mut world = World::new(count, MeshConfig::default());
    let mut state: u64 = 0x2545F4914F6CDD1D;
    let mut random = move |n: usize| -> usize {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        (state % n as u64) as usize
    };
    let mut mails: Vec<(usize, usize, Digest, u64)> = Vec::new();
    for n in 0..messages {
        let from = random(count);
        let mut to = random(count);
        if to == from {
            to = (to + 1) % count;
        }
        let digest = world.send_mail(from, to, n as u32);
        mails.push((from, to, digest, world.now_ms()));
    }
    let end = hours * HOUR;
    while world.now_ms() < end {
        // Every minute a handful of random pairs come into range for a few seconds.
        for _ in 0..count / 3 {
            let a = random(count);
            let b = random(count);
            if a != b {
                world.meet(a, b);
            }
        }
        world.advance(8 * SEC);
        let linked: Vec<(usize, usize)> = world.links.keys().copied().collect();
        for (a, b) in linked {
            world.part(a, b);
        }
        world.advance(52 * SEC);
        for p in 0..count {
            world.collect(p);
        }
    }
    let mut delays = Vec::new();
    let mut hops = Vec::new();
    for (_, to, digest, sent_at) in &mails {
        if let Some((_, _, hops_left, at)) = world.phones[*to].inbox.iter().find(|(d, _, _, _)| d == digest) {
            delays.push(at - sent_at);
            hops.push((7 - *hops_left) as f64 + 1.0);
        }
    }
    report(label, messages, &delays, &hops)
}

// ------------------------------------------------------------------------------------------------------------------------------ the tests

#[test]
fn a_to_b_direct_is_delivered_in_one_meeting() {
    let r = scenario_direct();
    assert_eq!(r.delivered, 1);
    assert!(r.median_delay_s < 700.0, "delivered in the first meeting: {r:?}");
}

#[test]
fn one_and_two_relays_deliver_with_the_default_copies_three_need_more_copies() {
    let one = scenario_relays(1, MeshConfig::default(), "A -> B via 1 relay");
    let two = scenario_relays(2, MeshConfig::default(), "A -> B via 2 relays");
    assert_eq!((one.delivered, two.delivered), (1, 1));
    // The honest limit of spray and wait on a pure chain: 4 copies halve at each courier, so the third courier holds the last copy and
    // only waits. With 8 copies a chain of three works.
    let three = scenario_relays(3, MeshConfig::default(), "A -> B via 3 relays (4 copies)");
    assert_eq!(three.delivered, 0, "a pure chain of three relays does not deliver with 4 copies");
    let three_more = scenario_relays(3, MeshConfig { copies_initial: 8, ..MeshConfig::default() }, "A -> B via 3 relays (8 copies)");
    assert_eq!(three_more.delivered, 1);
}

#[test]
fn both_asleep_then_a_wake_flushes_everything_in_one_meeting() {
    let r = scenario_asleep_then_wake();
    assert_eq!(r.delivered, 1);
    assert!(r.median_delay_s >= 3.0 * 3600.0, "it waited for the wake: {r:?}");
}

#[test]
fn a_relay_that_reaches_the_internet_uploads_what_it_carries() {
    assert_eq!(scenario_relay_to_internet().delivered, 1);
}

#[test]
fn the_ttl_runs_out_and_the_packet_stops_travelling() {
    let (r, carriers) = scenario_ttl_exhaustion();
    assert_eq!(r.delivered, 0, "4 relays with a TTL of 2");
    assert!(carriers <= 3, "it reached at most the author and two hops: {carriers}");
}

#[test]
fn a_packet_expires_after_48_hours() {
    assert_eq!(scenario_expiry().delivered, 0);
}

#[test]
fn many_paths_to_the_recipient_deliver_once() {
    let (r, copies) = scenario_duplicates();
    assert_eq!(r.delivered, 1);
    assert_eq!(copies, 1, "ten couriers offered it; the recipient took it once");
}

#[test]
fn only_the_recipient_recognises_its_tag() {
    let mut world = World::new(3, MeshConfig::default());
    let digest = world.send_mail(0, 2, 1);
    world.meet_for(0, 1, 10 * SEC);
    world.collect(1);
    assert!(world.phones[1].inbox.is_empty(), "a courier cannot tell whose mail it carries, and does not receive it as its own");
    assert!(world.phones[1].node.carried_digests().contains(&digest));
    world.meet_for(1, 2, 10 * SEC);
    world.collect(2);
    assert!(world.got(2, &digest));
    // Tags change every day: yesterday's tag and today's differ, and one phone's never equal another's.
    assert_ne!(tag_of(2, 1), tag_of(2, 2));
    assert_ne!(tag_of(1, 5), tag_of(2, 5));
}

#[test]
fn every_packet_on_the_wire_is_a_bucket_size() {
    let mut world = World::new(6, MeshConfig::default());
    // Messages of very different sizes.
    for (n, size) in [10usize, 150, 400, 900, 1800, 3000, 9000].iter().enumerate() {
        let now = world.now_ms();
        let packet = Packet { tag: tag_of(5, 20_000), header: vec![1; 60], payload: vec![n as u8; *size], hops_left: 0, expires_at: START + now / 1000 + 3600 };
        world.phones[0].node.enqueue(packet).unwrap();
    }
    for i in 0..5 {
        world.meet_for(i, i + 1, 30 * SEC);
    }
    assert!(world.frames > 20);
    assert!(world.wire_sizes.len() >= 4, "sizes were mixed: {:?}", world.wire_sizes);
    for size in &world.wire_sizes {
        assert!([256usize, 512, 1024, 2048].contains(size) || size % 4096 == 0, "{size} is not a bucket");
    }
}

#[test]
fn storage_pressure_evicts_strangers_first_and_keeps_mail_for_contacts_and_my_own() {
    let mut config = MeshConfig::default();
    config.store_cap_bytes = 20 * 256;
    config.stranger_share_percent = 100;
    let mut world = World::new(3, config);
    // Phone 2 is a courier with a small store; phone 1 knows phone 0's contacts (tag of phone 0's friend is a contact tag).
    let friend_tag = tag_of(9, day_of(0));
    world.phones[2].node.set_contact_tags([friend_tag].into_iter().collect());
    let mut strangers = Vec::new();
    for n in 0..30u32 {
        strangers.push(world.send_mail(1, 1000 + n as usize % 7, n));
    }
    world.meet_for(1, 2, 30 * SEC);
    let before = world.phones[2].node.stats();
    assert!(before.carried_bytes <= 20 * 256, "the cap holds: {before:?}");
    // A contact's packet arrives later and must get in, evicting a stranger's.
    let now = world.now_ms();
    let contact_packet = Packet { tag: friend_tag, header: vec![3; 60], payload: vec![3; 120], hops_left: 0, expires_at: START + now / 1000 + 3600 };
    let contact_digest = world.phones[0].node.enqueue(contact_packet).unwrap();
    world.meet_for(0, 2, 30 * SEC);
    assert!(world.phones[2].node.carried_digests().contains(&contact_digest), "a contact's mail took a stranger's place");
    assert!(world.phones[2].node.stats().evicted > 0);
}

#[test]
fn a_flood_from_one_node_is_held_by_the_rate_limit_and_honest_mail_still_flows() {
    let mut config = MeshConfig::default();
    config.link_packets_per_minute = 30;
    let mut world = World::new(3, config);
    let honest = world.send_mail(2, 1, 1);
    for n in 0..2000u32 {
        world.send_mail(0, 1000 + n as usize, n); // 0 floods
    }
    // Phone 2 (honest) meets 1 first, then the flooder keeps meeting 1 for ten minutes.
    world.meet_for(2, 1, 20 * SEC);
    for _ in 0..10 {
        world.meet_for(0, 1, 50 * SEC);
        world.advance(10 * SEC);
    }
    world.collect(1);
    assert!(world.got(1, &honest), "the honest packet arrived");
    let stats = world.phones[1].node.stats();
    assert!(stats.rate_limited > 0, "the flooder was held back: {stats:?}");
    assert!(stats.received <= 30 * 10 + 5, "at most the allowance per minute was taken: {stats:?}");
    assert!(stats.carried_bytes <= 5 * 1024 * 1024);
}

#[test]
fn the_simulation_report() {
    let (ttl, _) = scenario_ttl_exhaustion();
    let reports = vec![
        scenario_direct(),
        scenario_relays(1, MeshConfig::default(), "A -> B via 1 relay"),
        scenario_relays(2, MeshConfig::default(), "A -> B via 2 relays"),
        scenario_relays(3, MeshConfig::default(), "A -> B via 3 relays (4 copies)"),
        scenario_relays(3, MeshConfig { copies_initial: 8, ..MeshConfig::default() }, "A -> B via 3 relays (8 copies)"),
        scenario_asleep_then_wake(),
        scenario_relay_to_internet(),
        ttl,
        scenario_expiry(),
        scenario_crowd(50, 40, 6, "crowd of 50, 6 h, 40 messages"),
        scenario_crowd(50, 40, 24, "crowd of 50, 24 h, 40 messages"),
        scenario_crowd(20, 20, 6, "crowd of 20, 6 h, 20 messages"),
    ];
    println!("\n{:<44} {:>5} {:>9} {:>12} {:>10}", "scenario", "sent", "delivered", "median delay", "mean hops");
    for r in &reports {
        println!("{:<44} {:>5} {:>9} {:>11.0}s {:>10.1}", r.name, r.sent, r.delivered, r.median_delay_s, r.mean_hops);
    }
    let crowd = reports.iter().find(|r| r.name.starts_with("crowd of 50, 24 h")).unwrap();
    assert!(crowd.delivered as f64 / crowd.sent as f64 >= 0.7, "a day in a crowd of 50 should deliver most mail: {crowd:?}");
}
