# lime_mesh

lime's mesh engine (LIME-140): carries lime's **already-sealed** envelopes from phone to phone (store, carry, forward) with privacy on the air, budgets, dedupe and expiry, so a phone that reaches the internet can upload what it carries without learning who it is for.

**It depends on nothing of lime's** (only `sha2`): no accounts, store, server, vodozemac. It moves opaque bytes; `lime_core` does the cryptography (the recipient tag, the sealed routing header) and persists the carried packets. No radio, no timers: the platform tells the node what happened and does what the node says. `cargo test --workspace` (from `core/`) runs its unit tests and the simulator.

## The API (proposed for LIME-141/142)

```rust
let mut node = MeshNode::new(config, store /* impl MeshStore */, clock /* impl Clock */);

node.set_my_tags(&tags);                  // the recipient tags this phone answers to (today's and yesterday's, per device); announced in every Hello
node.set_contact_tags(tags_of_contacts);  // packets for accepted contacts are worth more than a stranger's

node.enqueue(packet)?;                    // a packet this phone made (tier Own, ttl hops, copies_initial copies)
let actions = node.on_link_up(link);      // -> [SendFrame{link, bytes, delay_ms}]: the Hello; the platform sends it
let actions = node.on_frame(link, bytes); // the answer to whatever the other phone sent
node.on_link_down(link);

let mail  = node.take_mine(&my_tags);     // Vec<Delivered{digest, payload, hops_left}>: payload is exactly what the server's `send` would store
let drops = node.take_uploadable();       // Vec<Uploadable{digest, header, payload}> for `mesh-drop`
node.confirm_uploaded(&digest);           // the server has it: stop carrying it  (node.upload_failed(&digest) offers it again)
```

`Action::SendFrame { link, bytes, delay_ms }`: the platform sends `bytes` on `link` after about `delay_ms` (relay jitter, 10-220 ms, on forwarded packets only; the control frames go at once and stay in order). `apply(actions, &mut impl MeshLink)` does it for a platform that prefers a callback.

Platform hooks: `MeshLink` (put a frame on a link), `MeshStore` (`load`/`save`/`remove` for carried packets, `load_seen`/`save_seen`), `Clock` (seconds since the epoch). `MemoryStore` is the in-memory store of the tests.

## The wire

**Packet** (versioned, length-prefixed, padded to a bucket: 256, 512, 1024, 2048, then 4 KiB steps; pinned by a test vector): `version(1) | tag(16) | hops_left(1) | expires_at(8, BE secs) | header_len(2) | header | payload_len(4) | payload | zero padding`. The **digest** (SHA-256 over everything that does not change on the way, each variable field with its length) names a packet; summaries carry its first 8 bytes.

**Frames** between two phones that meet: `Hello` (a summary of what I hold and have recently seen, plus the tags I answer to) -> `Want` (what I am missing) -> `Packet` (copies handed over + the packet) -> `Ack`. A packet whose Ack never came is simply asked for again at the next meeting: nothing is lost, nothing counted as handed over until acked.

## The rules (all in `MeshConfig`)

TTL 7 hops, **5 when a node has 6 or more links**; an LRU seen-set (1000 digests, 5 minutes); **spray and wait** (4 copies, cap 8, half handed to each courier met; a holder with one copy waits for the recipient, who is recognised by a tag in its Hello, or for the internet); a 5 MB store, 100 packets per recipient tag, strangers limited to 40% of the store; **eviction** lowest tier first (Stranger < Contact < Own), then oldest, never something worth more than the newcomer; expiry at 48 h; per-link rate limit (120 packets a minute).

## What the simulator found (`tests/sim.rs`, `cargo test -p lime_mesh --test sim -- --nocapture`)

See `TEND.md` (LIME-140) for the table. The one structural finding: **spray and wait is built for crowds, not chains.** In a pure chain of couriers 4 copies halve at each hand-over, so the author reaches the recipient through at most **two relays**; three relays need `copies_initial = 8` (the cap). In a crowd (random meetings) the delivery rate was 100% with a median of about 16 minutes.
