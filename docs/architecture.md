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
