# Lime native architecture (v2)

## 1. Purpose and status

This document is the design for Lime's native apps (iOS first, then Android): end-to-end encryption, devices and keys, a blind-mailbox server, the offline Bluetooth mesh, discovery and safety, and calls. It is the one place later briefs and agents read, so they do not have to dig through planning notes.

**Status: decided 2026-10-05.** The decisions below were made by the user on that date. This document records them and adds none.

**What is frozen.** The web app and the HTTP API v1 ([`api.md`](./api.md)) are frozen as a reference: the web app is the visual spec for the native screens and the future web and desktop client, and API v1 is the contract the dev server implements. They get real-bug fixes only. Where this document and `api.md` disagree for the native apps, this document wins.

**What is not decided here.** Endpoint specifications, the database schema and wire formats belong to later briefs (section 6 only describes the shape of the changes). The software licence (MIT or AGPL) is still open (section 11).

## 2. Decisions

| Id | Decision | Why |
|---|---|---|
| D1 | Minimum iOS 17. Real Liquid Glass (`glassEffect`) on iOS 26 and newer, behind an availability check; a thin material below it. | Wide device reach, with the newest look where the OS has it. |
| D2 | One shared core in Rust, **LimeCore**, used by the iOS app now and by Android and desktop later, exposed to Swift and Kotlin through UniFFI. | Signal's pattern: native UIs, one shared core for the protocol, signing, sync and crypto. |
| D3 | One repository: the app lives in `ios/` at the repo root, beside the frozen web app. | One place for the specs, the core and the apps. |
| D4 | Supabase for the backend, with separate staging and production projects. | Auth, Postgres, Storage and Edge Functions without running servers from day one. |
| D5 | **A.** An optional encrypted backup of history, unlocked by a recovery key the person writes down (Matrix-style). Without the backup, losing every device loses history. | Teachers lose phones; an opt-in backup keeps history recoverable without the server being able to read it. |
| D6 | **A.** Any Lime phone relays encrypted messages offline. Relays see only scrambled data and routing hints. | The most reach in an emergency. |
| D7 | **A.** Sign-up is open to any teacher. A "verified teacher" badge may come later (for example with a school email). Message requests protect inboxes. | "Connect all teachers" without excluding teachers who have no school address or tying identity to an employer. |
| D8 | **B.** The server is a **blind mailbox**, built that way from v1: sealed sender, client-managed encrypted group state, delivery to per-device mailboxes. The library stays vodozemac (permissively licensed). | Metadata privacy comes mostly from server architecture, and the offline mesh already forces client-managed group state. Retrofitting it later would be a painful migration. |
| E1 | **Full end-to-end encryption, no organisation key.** The audience is teachers (the mission is "connect all teachers"), not districts. Keeping records is the teacher's responsibility, which belongs in the terms of service later. | The server stores ciphertext and cannot search, preview or validate message content. Push previews are generated on the device. |
| E2 | **The encryption library is vodozemac** (Matrix's Olm and Megolm; Rust; Apache-2.0; code-audited by Least Authority in 2022). Lime does not write its own cryptography. | It is permissive, audited and battle-tested, it is Rust (so one shared core works), and Megolm tolerates offline and out-of-order delivery. It gives up post-quantum protection and Signal's metadata tools for now. |
| E3 | **Offline messaging works with the app open and closed**, so the apps are native (Swift, then Kotlin). Closed-app Bluetooth on iOS is the project's biggest technical risk and gets a real-device spike before anything is built on it. | A web view cannot relay in the background on iOS. |
| E4 | **Calls:** open source and secure. The self-hosted LiveKit server is used for group calls; 1:1 calls are peer-to-peer WebRTC with a TURN fallback. Group calls target 50 to 100 people. No recording in v1. | See section 9. |
| E5 | The first TestFlight waits until offline mesh relaying is included. | The offline promise is the product. |

## 3. Components

**The iOS app** (SwiftUI, iOS 17 and newer) talks only to **LimeCore**.

**LimeCore** is a Rust library, shared later with Android and desktop, exposed to Swift and Kotlin through UniFFI (Mozilla's binding generator, as matrix-rust-sdk does). It holds:

- vodozemac (the encryption);
- the local database: SQLite, encrypted at rest with SQLCipher, with the key in the Keychain;
- the op log and the outbox;
- the sync engine;
- the mesh protocol;
- local search (SQLite full-text search).

**Transports** plug into the core:

- HTTPS plus a realtime socket to the backend;
- Bluetooth LE mesh (section 7);
- later, local Wi-Fi.

**Backend** (a blind mailbox, section 5):

- **Supabase**: authentication, the **key directory**, the per-device **mailbox**, and Storage for encrypted blobs. Edge Functions implement the endpoints. Staging and production are separate projects.
- **LiveKit**, self-hosted, for group calls (section 9). A TURN fallback serves 1:1 calls.
- **APNs** for push, plus PushKit for calls. FCM later for Android.

The current dev server and API v1 stay as the frozen web app's backend and as the reference contract.

## 4. Identity, devices and keys

Each device has its own keys, in the Matrix style.

- **Per-device keys.** Each device has a vodozemac **Olm account**: a Curve25519 identity key and an Ed25519 signing key. It uploads its public keys and a pool of one-time keys to the key directory on the server.
- **Op signing.** Every op envelope carries `sig`, the device's Ed25519 signature over the canonical envelope. Recipients and relays reject an unsigned op or a bad signature. This is what makes an op relayed by a stranger's phone trustworthy, and it answers the first open question in `api.md` §9.
- **Cross-signing.** A per-user **master key** signs each of the user's device keys, so other people can trust a teacher's new phone without verifying again.
- **Adding a device** (what Linked Devices becomes): the new device shows a **QR code**; an existing device scans it, signs the new device's key, and hands over the history keys directly, encrypted.
- **Verify in person** (optional): two people scan each other's QR codes and get a verified badge.
- **If every device is lost (D5):** history comes back only from the optional encrypted backup, unlocked by the **recovery key** the person wrote down. Without a backup, history is gone. The server never holds a key that can open either.

## 5. What is encrypted, and what the server can still see

**The server is a blind mailbox (D8).** It does not run conversations; it delivers sealed envelopes to device mailboxes.

- **Sealed sender.** The sender's identity travels inside the encrypted envelope, so the server does not learn who sent a message. **This is live for 1:1 chats with people who have accepted you** (LIME-96): once someone accepts, or you start a chat with them, you exchange delivery keys and later messages are sealed. The exception is a stranger's first message, which is sent identified so that it can land in Requests; and **when the server refuses a sealed send** (the contact blocked you or changed phones) the app silently sends that message identified instead and shows "Sent", so a blocked person learns nothing: **that fallback message does name its sender to the server, once**, like a stranger's first message ([`api-v2.md`](./api-v2.md) section 4).
- **Client-managed encrypted group state.** Who is in a group, its name and its avatar are state that member devices keep and change themselves, as encrypted group-state ops. The server holds no list of groups and does not know their names.
- **Per-device mailboxes.** A message is delivered to each recipient device's mailbox and removed after delivery. Because the server does not track groups, it does not check membership: clients and delivery tokens, not database row-level rules, take over what those checks did.

**What is encrypted** (everything the server could otherwise read):

- message text and formatting, edits, the content of replies, and reactions;
- the conversation name and avatar;
- attachment names, types and sizes.

**Conversations use Megolm** (vodozemac). Each sending device has an outbound session per conversation and shares its key with every member device over Olm. The session rotates on any membership change, every 100 messages, or every 7 days. **Built in LIME-97 for groups** (up to 100 people): the group's state is a log of signed ops each phone replays, so the server never learns a group, its name or its members; the exact ops and rules are in [`api-v2.md`](./api-v2.md) section 11.

**Files** (built in LIME-98c and LIME-98d: photos, documents, voice messages and video) are encrypted on the device in chunks with a fresh AES-256-GCM key, which travels with the SHA-256, size, type, name and a tiny thumbnail inside the encrypted message. Storage only ever holds ciphertext, deleted an hour after the last recipient fetched it or after 30 days; recipients keep their own decrypted copy in the encrypted store. Photos are shrunk to 2048 px and stripped of EXIF and GPS on the sender's phone. Details: [`api-v2.md`](./api-v2.md) section 6.

**Profile photos** (LIME-98b) are the one place Lime stores a picture on the server, and the person chooses how: **Everyone on Lime** (the default) keeps a plain 512 px JPEG that any *signed-in* user can fetch (never anonymously; the server can see it too), or **Only my contacts (encrypted)** keeps AES-256-GCM ciphertext that only people holding the sender's photo key can open, and **deletes the public copy**. The photo key is shared with accepted contacts inside their encrypted chat, together with the delivery key, and rotates on a block ([`api-v2.md`](./api-v2.md) section 6).

**Status and work hours** (LIME-108): Available, Away or Do not disturb is shared only with accepted contacts as an encrypted control op that carries its own end time (and what follows), so schedules need no presence service; outside work hours the phone is in Do not disturb and holds notifications, with a summary when the quiet ends. Nothing is stored on the server, and there is no "last seen".

**Forward, link cards and messaging yourself** (LIME-106): a forward is a new message that shares the same encrypted file by reference (the server only extends that file's life); a link card is built on the sender's phone and its picture is an encrypted attachment, so a reader never visits the link and the server never fetches a URL; a chat with yourself never leaves the phone.

**Message actions** (LIME-105): reactions, edits and deletes are small signed, encrypted ops inside the conversation like any message; the server never sees them or who reacted. Delete for everyone and edit work for the author for 24 hours and cannot unsee a message someone already read or saved. Delete for me is local and sends nothing.

**Link previews** are made by the sender's device. The server never fetches URLs.

**Search** happens on the device only.

**Notifications** carry only ids. An iOS Notification Service Extension decrypts on the device to show a preview, sharing the core and the keys through an App Group.

**Reporting abuse:** a Report sends the reported messages, decrypted, by the reporter's choice. Nothing else is readable.

**What the server can still see** (the honest limit): the **recipient devices** a message is for, **timing**, **sizes**, and **IP addresses**. Even Signal's server sees these. It never sees message content or who belongs to which group, and it does not see the sender of a sealed message (a stranger's first message is the exception, as above).

The server also holds two things by design, because finding people and starting conversations needs them: the **key directory** (public keys) and the **user directory** (the public profile fields people choose to publish, section 8).

## 6. API v2 deltas from v1

This section describes the shape of the changes. Endpoint specifications are a later brief; the v1 contract is [`api.md`](./api.md). The decided protocol is in [`api-v2.md`](./api-v2.md).

- **A signed envelope.** Every op envelope gains `sig` (section 4). Anything unsigned or badly signed is dropped.
- **Encrypted payloads.** A message op's `payload` becomes `{ algorithm, session_id, ciphertext }`. The server can no longer validate, search or preview content.
- **Group-state ops.** The v1 membership and conversation ops become encrypted group-state ops that member devices apply themselves. The server no longer holds memberships, so the v1 row-level rules that depend on them (`api.md` §8, Visibility) do not carry over to the native apps.
- **Mailbox delivery.** Ops are delivered to per-device mailboxes (section 5) instead of being read from one op log per user. A device fetches its mailbox, applies the ops locally, and the server deletes what has been delivered.
- **Ordering.** The server's mailbox `cursor` is for sync only; the order of a conversation comes from the devices (a hybrid logical clock plus `parents[]`). This answers the question that was open here (section 11, item 5; [`api-v2.md`](./api-v2.md) section 5).
- **De-duplication.** The server cannot see the inner `op_id`, so it de-duplicates by a hash of the outer ciphertext per recipient device, and recipients de-duplicate by `op_id`: sending an op twice has the same effect as once, which lets a relay and the server both carry the same op ([`api-v2.md`](./api-v2.md) section 8).
- **Call signalling** moves into encrypted call ops (`call.invite`, `call.answer`, `call.end`) in the conversation (section 9).
- **Everything else in v1 that does not touch content** (client-made ids, the outbox, idempotent ops, local-first reads) carries over unchanged.

## 7. Offline mesh (D6 = A)

- **The unit is the signed, encrypted op envelope**, already unreadable to relays.
- **Any Lime phone relays** (D6). A relay sees only scrambled data and routing hints.
- **Store and forward:** at most 7 hops and 72 hours. Relays carry the outer envelope unchanged. Devices exchange "what I have" summaries and swap the missing items. There are per-device-key rate limits, and anything unsigned is dropped. Whoever reaches the internet first uploads; the server de-duplicates by a hash of the outer ciphertext per recipient device, and recipients de-duplicate by `op_id` ([`api-v2.md`](./api-v2.md) section 8; how a relay recognises an envelope it already carries is open item 5 in its section 11).
- **Transport:**
  - iOS: CoreBluetooth with background modes and state restoration;
  - Android: a foreground service;
  - wire format: borrowed from **bitchat** (public domain).
- **Client-managed group state fits here:** groups can change while offline, with no server to ask.
- **The key limit:** starting a new encrypted conversation needs the other person's keys. Offline, a person can message anyone they have already talked to, anyone whose keys the phone cached (the core caches members' keys while online), or someone they meet and scan in person. A stranger they have never connected with needs the internet once.
- **Open question for the spike:** how well iPhones relay with the app closed (section 11).

**As built so far (LIME-140: the engine, no radio yet).** `core/mesh` (`lime_mesh`) is a separate crate that depends on nothing of lime's (only `sha2`): it moves opaque sealed bytes. It has the versioned packet padded to buckets, the meeting frames (`Hello` summary, `Want`, `Packet`, `Ack`; resumable, a packet is only counted as handed over when acked), and the node: TTL 7 (5 when a node has 6 or more links), an LRU seen-set (1000 digests, 5 minutes), **spray and wait** (4 copies, cap 8, half handed to each courier met; the holder of the last copy waits for the recipient, recognised by its daily tag, or for the internet), budgets (5 MB, 100 packets per recipient tag, strangers at most 40%) with trust tiers (Stranger < Contact < Own) and eviction (lowest tier, then oldest), **48 hour** expiry (not 72), relay jitter hints, per-link rate limits. A simulator of up to 50 virtual phones (`core/mesh/tests/sim.rs`) proves it; the one structural finding is that spray and wait with 4 copies reaches the recipient through **at most two relays on a pure chain** (three need 8 copies), while a crowd delivers everything. `lime_core` adds what needs the keys: the **recipient tag** (made from the recipient's delivery key and the day), the **routing header sealed to the server's mesh key**, the `MeshStore` on the encrypted database, `MeshEngine` over UniFFI, and the server's **`mesh-drop`** that opens the header and stores through the same access check as `send` ([`api-v2.md`](./api-v2.md) section 8). **The iPhone Bluetooth link (LIME-141; Debug builds only until the mesh is offered to people).** `ios/Lime/Core/Mesh/`: every phone is a **central and a peripheral at once**, advertising **one service** and scanning for it (the advertisement is the service UUID and nothing else: no name, no account, no device id). **Meeting is GATT**: connect, read the other phone's **link id** (a random 64-bit id, new every launch and every 15 minutes, never in an advertisement, only in the hello read after connecting), write mine; **the lower id initiates**, so of the two links two phones make exactly one is kept. **Frames move over L2CAP** (unencrypted and unpaired: everything of value is already sealed) from the PSM the peripheral publishes, with **GATT write and notify** (about 470 byte fragments, reassembled with caps and a 30 second timeout) carrying frames meanwhile and whenever the channel fails. Weak links (below -92 dBm) are not connected to; foreground scanning is continuous and, idle for two minutes, 10 seconds on and 20 off; in the background iOS runs its own service-filtered scan, which the app cannot tune. Every wake event (a discovery, a connection, the app opening, a state restoration) tells the engine to announce every live link again, so it flushes what it holds. The pure parts (framing, fragments and their caps, link policy, running the engine's actions) are unit-tested without a radio; the CoreBluetooth adapter is proven on devices (see `TEND.md`, LIME-141). **Real messages over the mesh (LIME-142; still Debug-only).** *The flow.* With "Help pass on nearby messages" on (the default), a **sealed** send that cannot reach the server (a network error, to an accepted contact whose delivery key this phone holds, and only a message, its edit, delete or reaction, group state and its keys, or a delivery-key share; **never a call or group call**) is **kept, as made**, in the encrypted store's `mesh_outbox` (migration 33): one row per recipient device with that device's ciphertext, and the sender's ratchet is saved as for any send. **The retry never re-encrypts**: when the internet returns, `flush_mesh_outbox` sends exactly those bytes (a new ciphertext would burn another ratchet step and the recipient would see two for one message); the server de-duplicates by the hash of the outer ciphertext per device and recipients by op id, so a copy a relay already uploaded is a duplicate and the recipient has one message. `MeshEngine.pump_outbox` puts the kept ciphertexts on the mesh (sealed header, recipient tag, 8 copies) and notices when another phone acknowledges a copy. A group message is one Megolm ciphertext, parked once per member device; if any member would need an identified send (a stranger) the whole send waits for the internet. Offline, a group's member devices come from the cache. With internet, the phone uploads everything it carries through `mesh-drop` (on app active, on a connectivity change and after each sync). Mail for this phone that arrives over the mesh goes through the normal inbound path. *The statuses* (words and an icon, never colour alone; grey, not red): **Waiting for signal** (kept, no phone has it yet), **Passed to a nearby phone** (another phone acknowledged a copy), **Sent** (the server has it, by this phone or a relay: we learn of a relay's upload when our own retry finds it a duplicate), then Delivered as before; **Waiting for internet** for what cannot travel (pictures and files, someone who has not accepted you, or the switch off), with a one-line reason on tap; **Not sent** (red) only for a real failure, or **48 hours** with no route. None of these needs a tap to retry: sending resumes with any link or connection. *Switch off* means no relaying for others and no sending through the mesh. Honest limits: a message moves when phones meet and at least one is awake, and not after lime is swiped away.

**Not built yet:** Nearby / emergency mode (LIME-143) and shipping any of this in Release.

**Attachments and the mesh.** Mesh v1 carries text only: attachments need the server's Storage and sync when online. A short voice message is about 60 KB, so it could ride the mesh later (the same encrypted chunk format); flagged for the mesh brief.

## 8. Discovery and safety (D7 = A)

Lime is for connecting all teachers, so discovery has to work at scale without exposing people.

- **The directory carries over from today:** searchable by name and school; **exact match only** on username, email or phone; email and phone are never shown in results.
- **Open sign-up (D7).** A "verified teacher" badge may come later.
- **Message requests.** A first message from someone you share no conversation with lands in Requests, where you can Accept, Block or Report.
- **Block.**
- **Hide me from search.** People can still reach you by your exact username.
- **Rate-limited search.**
- **18 and older only**, with an age confirmation at sign-up.
- **No contact-book upload** in v1.

## 9. Calls

Calls are open source and secure, and a major part of how teachers connect.

- **1:1 calls are peer-to-peer WebRTC**, with a TURN fallback.
- **Group calls use a self-hosted LiveKit SFU** (Apache-2.0 server and SDKs; its TURN is built in). LiveKit Cloud is a proprietary hosting service running the same open code; it is only an emergency fallback, if ever.
- **Signalling** is encrypted call ops in the conversation (`call.invite`, `call.answer`, `call.end`).
- **Room tokens.** A Supabase Edge Function issues a LiveKit room token after checking a **per-call capability** (not server-side membership, section 5).
- **The media key is per call.** It is shared in the encrypted invite, over Lime's own vodozemac channel, and rotated when people join or leave. The server and the SFU never see the media.
- **iOS:** CallKit for the native incoming-call screen, plus a PushKit VoIP push that carries only ids. Android later: ConnectionService with high-priority FCM.
- **Group size:** 50 to 100 people (large PD sessions). Use simulcast, show only active speakers' video, and default to a speaker view above about 12 people. Load-test at 100 before launch.
- **No recording** in v1.
- **Verifying a call (LIME-119).** Both people see four emoji, computed in the core from the call id and the two DTLS fingerprints (each signed into its own offer or answer): the first four bytes of `SHA-256("lime-call-emoji-v1" || call_id || fp_caller || fp_callee)` index a fixed list of 256 emoji. The same four on both screens mean the media keys are the ones the two phones signed, so nobody is in between. The list never changes, and other platforms must pass the same test vectors.
- **Relaying (LIME-119).** A 1:1 call between contacts goes peer to peer with the relay as a fallback; **Settings → Privacy → "Always relay calls"** makes a phone gather and send only relay candidates, so the other person never sees its IP address (each side decides for itself; with no relay credentials the call fails instead of falling back to direct). **The rule for later: calls from a call link (LIME-117) or from someone who is not a contact relay by default**, because a stranger must not learn an address. Nothing to build until those exist: 1:1 calls are contacts only.
- **Audio before video.**
- **Phases:** v1 1:1 voice and video; v2 group calls (grid, speaker view, mute controls); v3 screen share, raise hand, larger sessions.
- **Offline:** calls need a network, because Bluetooth is too slow for audio or video. Local-network calls (the same Wi-Fi with no internet) are a later option.
- **Security review:** the call key exchange goes into the pre-launch external security review; no published audit of LiveKit's end-to-end encryption was found.

## 10. Build order

DESIGN-01's order, **as amended by the user on 2026-10-05: mesh v1 comes before TestFlight.** One brief each, with the user's check between:

1. LIME-87: the iOS skeleton (done).
2. LIME-88: this design in `docs/`.
3. LIME-89: the Rust core skeleton (`core/`, UniFFI, a vodozemac Olm round trip, linked into the iOS app).
4. LIME-90: the core's encrypted local store, and the iOS screens reading sample data from the core.
5. The Bluetooth spike (two iPhones; it may need the paid Apple account for background modes).
6. Supabase staging, schema v2, auth and the key directory.
7. Sync and end-to-end encrypted messaging (two simulators, then two phones).
8. Push and the notification extension.
9. **Mesh v1.**
10. **TestFlight** (the paid Apple account).
11. 1:1 calls (peer-to-peer).
12. Group calls (LiveKit).
13. Android.

**Cost principles** (principles, not hard numbers; Lime starts with no budget, out of pocket, and scales):

- the mailbox deletes after delivery;
- attachments expire (for example, 30 days after every recipient has fetched them);
- audio before video;
- group video comes only when funded;
- the TURN relays and the SFU bandwidth are the main recurring infrastructure cost, and self-hosting LiveKit keeps it bounded.

## 11. Open questions

1. **The licence.** MIT or AGPL for Lime's own code is undecided. vodozemac (Apache-2.0) works under either, so nothing is blocked. Moving MIT to AGPL stays easy while FAM owns all the code. The decision is needed before outside contributors arrive or the repository goes public.
2. **The Bluetooth spike's results.** How well iPhones relay with the app closed, on real devices. Everything in section 7 depends on the answer.
3. **Metadata hiding beyond the mailbox** (zkgroup-style private group credentials), to be revisited later.
4. **The web and desktop client's end-to-end encryption** (vodozemac compiled to WebAssembly), later.
5. **Message ordering under the mailbox** (raised while writing this document). v1 makes the server's `seq` the one order of events. DESIGN-01 kept `seq` as the server's ordering online, and then D8 made the server blind to conversations. How a per-mailbox delivery order relates to the order messages appear in a conversation is not specified, and the API v2 brief has to answer it.
   **Answered in `docs/api-v2.md` §5 (2026-10-06).**


### Calls: as built (LIME-111)

1:1 voice and video over WebRTC (stasel/WebRTC), DTLS-SRTP between the phones; media goes peer to peer, or through a self-hosted coturn at `turn.limechat.org` (`infra/turn/`) which only sees ciphertext. Signalling is Lime's own encrypted control ops (`core/src/client/calls.rs`); the app's `CallManager` is a small state machine over injectable signalling, system (CallKit) and media. History is local to the phone (`CallLog`). Calls ring only while Lime is open or recently open (no PushKit yet).


### Group calls: as built (LIME-112b)

Calls in a lime group go through one self-hosted LiveKit server (`infra/sfu/`, `sfu.limechat.org`, today on the same CPX11 as coturn, Caddy in front). It is an SFU: each phone sends its audio and video once, the server forwards it. **The media is end-to-end encrypted by the phones** using LiveKit's per-participant frame encryption, with **a key per sender**: each phone makes a random 32-byte key when it joins, and the key travels only to the people in the call, inside Olm-encrypted group ops (`group.call.key`, `docs/api-v2.md` §12.2). When anyone leaves, every phone still in the call makes a new key (next index) and sends it only to those still in the call, so someone who left cannot read on. **Each phone starts encrypting with its new key at once:** the core hands the app a `my_key` event (my participant, the new key as raw bytes, the new index) and the app sets it for sending first, then sends it to the others (the others keep the old index for frames in flight; LiveKit's key ring holds 16). *Note, 2026-10-15 (LIME-112e): before this fix the rotation did not take effect. The core renewed the key and sent it to the others but never told the app, so every phone went on encrypting with its first key (index 0): a leaver could still decrypt, and a rejoiner, who gets only the newest keys, stayed on "Connecting securely". The four-emoji check (LIME-147) caught it.* A participant whose key has not arrived shows "Connecting securely…" and no picture. The rules (who may start, join and be sent a key, key renewal, when a call ends, the 10-person ring cut-off) are in LimeCore, so Android gets them for free; the iOS `GroupCallManager` is a thin adapter over the LiveKit SDK and CallKit. TURN for the phones is Lime's coturn, handed to the SDK by the app (with time-limited credentials); **Always relay calls** sets the relay-only transport policy, so the SFU never sees the phone's address. A short-lived join token comes from the `livekit-token` Edge Function (the room is the call's random 64-hex id; the identity is a random per-call id, never the user id).

**The four-emoji check (LIME-147, v2 in LIME-147b).** A 1:1 call's emoji (LIME-119) come from the two phones' DTLS fingerprints, which are end to end in a P2P call; in a group call each phone's DTLS ends at the SFU, so those prove nothing about the other people. The group's emoji come from the **media keys** instead, which travel only inside Olm: every phone computes the first four bytes of `SHA-256("lime-group-call-emoji-v2" || len32(call_id) || call_id || u32(count) || for each participant, sorted by participant id (byte order of the id as sent): len32(participant_id) || participant_id || SHA-256(that participant's current key))` (every length and the count a big-endian u32, so the input is unambiguous: v1 concatenated the fields bare and was replaced before any other platform shipped), each of the four bytes indexing the same fixed 256-emoji list as 1:1. Everyone in the call, me included, counts, each with their **current** key (the newest index). All phones see the same four exactly when every phone holds the same keys for the same people: a substituted key, or a participant only some phones know about, changes them on someone's screen. They change whenever someone joins or leaves, so people compare again. The core keeps only the **SHA-256 of each other person's current key and its index** (`group_call_participants.key_hash`/`key_index`, migration 29), never the key, and answers `group_call_emoji_state(call_id)`: no emoji, and `waiting` = how many people's keys are missing or **not yet renewed**, until they are all in. *No mismatched emoji during a rekey:* every phone renews its key once per person who leaves, so after a leave a person's key counts only once it has been renewed as many times as mine has since I first saw them (`rekeys_at_join`, migration 30); until then the chip says "Waiting for everyone's keys…" instead of showing four that other phones are not showing yet. That wait is bounded: 15 s after my own renewal (`last_rekey_at`) the emoji show whatever keys are held, so a phone that missed a leave cannot keep the chip waiting for ever. A join renews nobody's key: the newcomer's key is waited for like any missing key. The pure function `group_call_emoji` with a pinned test vector (cross-checked with Python's hashlib) is exported for other platforms. The app shows the same chip as a 1:1 call after the timer.

*What names a call on screen (LIME-147b).* The group's own name when a person chose it, otherwise the people in the call (first names, with the count): the core decides with `group_is_custom_named` (the group was renamed at some point, or was made with a name other than what the first-names rule `default_group_name` gives for the people it was made with; a member whose name is unknown counts as "chosen"), so every phone agrees. The header pill, the people sheet's title and the mini player use it.

**Honest limits.**

- The SFU (and anyone watching its network) sees **IP addresses** (unless Always relay is on), **timing, who connects when, the number of people in a room, and packet sizes**; never the media, and never names or the group's identity (the room is a random id). The Edge Function sees that a signed-in account asked for a token, not which group.
- Anyone who holds the current key of a participant could forge that participant's stream; per-sender keys limit that to people in the call, and a leaver is cut off at the next key. The **sender-key exchange is flagged for the pre-launch external security review**, like the rest of the call key handling.
- A member can share what they see and hear, as in any call: end-to-end encryption protects the media from the server, not from the people in the call.
- The four-emoji check in a group call (below) shows that the phones hold the same keys for the same people; it does **not** say who each person is (Verify in person does that), and it is only as good as people actually comparing.
- A person's phone sees the identities (random per-call ids) of the others in the room; names come from the signed `group.call.join` ops, which only group members can send.
- The SFU is a single small server today: availability and capacity are limited (`infra/sfu/README.md`: about 3-10 people per room comfortably; a dedicated server for 50-100).
