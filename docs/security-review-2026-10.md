# lime: in-house security review, October 2026

**Brief:** LIME-158. **Reviewed:** the repository at the commit that carries this file (`main`, 2026-10-18), by `tend` with the user on the devices. **Not an audit.** This is a first, evidence-backed pass by the people who built it; an independent audit is planned once Lime Chat Inc and Lime Chat LLC exist (see `docs/audit-scope.md`).

**Result in one line: no critical and no high findings.** 2 medium, 9 low, 5 info (section 4). Every fix is its own brief; nothing in the product was changed by this review (two debug-only aids were added to the iOS app for the device test, section 3).

How to read this: section 1 is the threat model; section 2 is the checklist, one line per item with the evidence (file:line, a test, or a command); section 3 is the five known open items; section 4 is the findings table; section 5 is what was *not* covered.

Rating scale: **critical** (remote, no user action, reads or forges messages or keys), **high** (breaks a stated promise for a realistic attacker), **medium** (weakens a promise or leaks metadata to a realistic attacker, or must be fixed before release), **low** (needs an unusual position, or a small leak), **info** (hardening, a note, no loss today).

---

## 1. Threat model

### Assets

| Asset | Where it lives |
|---|---|
| Message and call content | encrypted on the phones; the server holds only ciphertext |
| Keys: the Olm account and sessions, Megolm group sessions, the account's master signing key, delivery keys, per-call sender keys | the phone's SQLCipher database (`core/src/store/account.rs`, `keys.rs`); the database key is in the iOS Keychain |
| Who talks to whom, and when | the contact graph is on the phones; the server sees device ids, mailbox timing and sizes, and which device fetched when (section 3, d) |
| Media and files | AES-256-GCM chunks under a random per-file key; the key travels inside the encrypted message (`core/src/store/attachments.rs:2-9`) |
| Account (email, password hash, sessions) | Supabase Auth plus lime's `auth_proofs` two-step sign-in |
| The server's own secrets | mesh routing secret, LiveKit API secret, service-role key, sweep secret: only in Supabase secrets |

### Adversaries

| # | Adversary | Position | What they can do |
|---|---|---|---|
| A1 | Curious or compromised server or staging operator | full read of the database, logs and function code; can ship a malicious function | read ciphertext, device lists, mailbox timing; try to insert keys |
| A2 | Network attacker | on the path between phone and server or LiveKit | watch sizes and timing; try to replay or tamper |
| A3 | Nearby Bluetooth attacker or a stranger's phone | physically close, runs a lime-speaking radio | become a carrier; see packets, tags and timing |
| A4 | Malicious group member | holds valid group keys | send junk, lie in ops, stay in a call |
| A5 | Former member or former contact | held keys in the past | try to keep reading or sending |
| A6 | Stolen phone, unlocked | full app access | read everything the app shows |
| A7 | Stolen phone, locked | physical access, forensic tools | extract keys or data at rest |
| A8 | Malicious relay phone | carries a stranger's mesh packets and may upload or fetch for them | drop, delay, replay, learn what it can |

### What lime promises (and what this review checked against)

1. **Content is end to end encrypted**: only the sender's and the recipient's phones can read messages, files and call media. The server never holds a content key.
2. **The server learns as little as possible**: sends are *sealed* (no sender recorded, the proof is a signature bound to one ciphertext and one device); mesh uploads and relay fetches carry no session, so the server does not learn which account relayed.
3. **A leaver or a blocked contact loses access**: blocking rotates the delivery key; a call leave renews every remaining key.
4. **Nearby Bluetooth strangers learn nothing readable**: packets are opaque, the recipient tag changes daily, the routing header is sealed to the server.
5. **Nothing leaves the phone that the person did not send**: no analytics, no ad identifiers, no data sales (always free).

---

## 2. Checklist with evidence

Legend: **OK** = checked, evidence given. **F-nn** = a finding (section 4). **n/v** = not verified here (section 5).

### 2.1 End-to-end encryption of messages

| Item | Result | Evidence |
|---|---|---|
| One-to-one messages use Olm (vodozemac 0.11.1), per-device sessions | OK | `core/src/client.rs:14` (`OlmMessage`, `SessionConfig`); `core/src/store/account.rs:4` (account and session pickles); `core/Cargo.toml` pins `vodozemac = "0.11.1"` |
| Group messages use Megolm sessions, keys shared over Olm | OK | `core/src/client/groups.rs:13`, `core/src/store/groups.rs:7`; group keys travel in `group.session` ops |
| Long-term keys and pickles encrypted at rest | OK | `core/src/keys.rs:17` `derive_pickle_key` (HKDF-SHA256, label `lime-pickle-v1`); database is SQLCipher: `core/src/store/mod.rs:701-720` (refuses to run unencrypted: `cipher_version` check) |
| Secrets never logged | OK | `core/src/keys.rs:3` ("never logged"); `grep -rn "println!\|eprintln!\|dbg!" core/src core/mesh/src` finds nothing outside tests |
| Key verification (safety numbers) and key-change warning | OK | master-key fingerprint `core/src/keys.rs:78` `fingerprint_of`; verified flag `peers.verified_at` (`store/migrations.rs:230`); a changed master key sets `new_master_key` and clears verification until re-verified (`store/mod.rs:308-312`, `:466`) |
| Sender authentication of ops (who sent this) | OK | each op is signed by a device certificate chained to the master key (`core/src/protocol/` `SenderCert`, `device_signing_text`); group call ops are rejected unless the sender is a current member (`store/group_calls.rs` `allowed()`, `apply()`; tests around `client_tests.rs:3995-4030` apply keys from a non-member, a stranger, a wrong device and an unknown call, and all are refused) |
| Sealed sender: the server does not record who sent | OK | `send` stores `sender_user` only for `identified` items (`supabase/functions/_shared/access.ts` `sealedRow`: `sender_user: identified ? senderUser : null`); sealed sends carry no session |
| Access proofs: only someone holding the recipient's delivery key can post to a device | OK | `core/src/store/delivery.rs:4-15,49,58-68` (Ed25519 key pair derived from the delivery key; signature over `"lime-access-v2" ‖ SHA-256(ciphertext) ‖ device UUID`); server check `_shared/access.ts` `verifySealed` (label, hash, device bytes; a wrong, short or missing proof is the same 403) |
| Blocking rotates the delivery key (cuts a blocked contact off) | OK | `delivery.rs:6` ("Blocking someone rotates the key") |
| Legacy bearer-style `{ sealed: access_key }` proof still accepted by `send` | **F-02** | `supabase/functions/send/index.ts:4,113`; the comment itself says "remove it once every device has updated, before TestFlight" |
| Replay of a captured ciphertext | OK | server de-duplicates by SHA-256 per device (`access.ts` `storeRows`, `onConflict: to_device,ciphertext_hash`); the phone checks `received_ciphertexts` before decrypting (LIME-141-fix6, migration 36) |
| Randomness | OK | keys come from vodozemac and `getrandom`; the group-call sender key and room id are two UUIDv4s (`store/group_calls.rs:48-51`) → **F-12** (info) |

### 2.2 Media and attachments

| Item | Result | Evidence |
|---|---|---|
| Files encrypted before upload; the server holds ciphertext only | OK | `core/src/store/attachments.rs:2-9`: AES-256-GCM chunks, random per-file key, nonce = chunk index, associated data = attachment id ‖ index ‖ chunk count (no reorder, drop or add); function header `supabase/functions/attachment/index.ts:1-14` |
| The file key never reaches the server | OK | key is inside the encrypted message; the `attachment` function takes ids and counts only (`index.ts:20-30`) |
| Thumbnails and video posters | OK | both are bytes inside the encrypted message (`attachments.rs:23,40-54`, poster capped in size); the server never sees an image |
| Blob and attachment access | OK, by design | the id is a capability: whoever knows a UUID can download that ciphertext (`blob/index.ts:5-7`, `attachment/index.ts:12`); only the owner can replace or delete; the ciphertext is useless without the key. Unguessable 122-bit ids |
| Expiry and cleanup | OK | `blob-sweep` every 15 min: expired and never-committed uploads are removed with their Storage objects (`blob-sweep/index.ts:1-40`); the sweep is gated by a secret (`x-sweep-secret`, constant-time compare) |
| Upload limits | OK | per file, per user and per minute (`blob/index.ts:17`, `_shared/storage.ts` `blobConfig`) |

### 2.3 Group calls (LiveKit end-to-end encryption)

| Item | Result | Evidence |
|---|---|---|
| Media is encrypted by the phones; the SFU forwards ciphertext | OK | `ios/Lime/Core/Calls/GroupCallMedia.swift:67,108`: `BaseKeyProvider(isSharedKey: false)`, `EncryptionOptions(keyProvider:, encryptionType: .gcm)` |
| One sender key per participant, delivered only inside Olm-encrypted signed ops | OK | `core/src/store/group_calls.rs:1-26` (`group.call.key` goes only to people in the call); a key is accepted only for a known call, from the participant's owner, and only while I am in the call (`apply`, `group.call.key`, tests "a refused key says why") |
| Keys renew when anyone leaves | OK | `rotate_my_key` (`store/group_calls.rs:239`) runs on a leave op, the SFU reporting someone gone, and a membership change; the new key goes only to people still in the call and the group |
| Slot-0 fix (LIME-163): every key in LiveKit slot 0 | OK | `GroupCallMedia.swift:75-90` (`slot = 0`, `setKey`, `setCurrentKeyIndex`); device check LIME-163 passed (1e201) |
| A leaver cannot read on | OK (inferred, see section 3a) | device test 3(a) |
| Call token | OK | `livekit-token`: signed-in session, 20 a minute, room = 64 hex (capability), identity = random per call, token allows join, publish, subscribe, data only, 10 min to join, no admin or recording (`livekit-token/index.ts:1-30`) |
| A non-member who learns the room id can join the room | **F-06** | `livekit-token/index.ts:14-20`: no membership check (the server does not know the group); they see random identities and cannot decrypt |
| One-to-one calls: DTLS fingerprint is inside the signed op | OK | `core/src/store/calls.rs:7-9` (a relay cannot swap the media key); four-emoji check for both kinds of call (`call_emoji.rs`) |
| Ghost / stale participants after a kill | OK (fixed, LIME-165) | `store/group_calls.rs` `recover_killed`, `drop_device_elsewhere`, `expire_stale`; tests in `client_tests.rs` |

### 2.4 The mesh (Bluetooth)

| Item | Result | Evidence |
|---|---|---|
| Carriers move opaque, already-sealed bytes and know nothing of keys | OK | `core/src/mesh.rs:1-3`; the engine crate `core/mesh` has no key code |
| Recipient tag: `HMAC-SHA256(HKDF(delivery_key, "lime-mesh-tag-v1"), label ‖ UTC day ‖ device)[..16]`, changes daily | OK | `core/src/mesh.rs:47-58`; only holders of the delivery key (contacts) can compute it |
| Hello sends this phone's own tags to every linked phone | **F-04** | `core/mesh/src/frame.rs:4,16`; see 3(c) |
| Sealed routing header: `{to_device, access.signed}` sealed to the server's mesh public key (X25519 ephemeral + HKDF-SHA256 + AES-256-GCM, 1-byte key id for rotation) | OK | `core/src/mesh.rs:64-93`; opened only in `mesh-drop` (`_shared/mesh.ts`); a carrier learns neither recipient nor anything reusable |
| Server mesh key pinned in the app; the staging key is not the local test key | OK | `core/src/mesh.rs:27-35` (id 1); `./supabase/check-staging-mesh-key.sh` run during this review: "ok: staging holds a key that is not the local test key" (digest `d87134f7a5371c6e`) |
| `mesh-drop` has no session (the server never learns who relayed) | OK | `supabase/functions/mesh-drop/index.ts:1-12,34-61`; `config.toml` `verify_jwt = false`; the sender's proof is the authority; the same access check as `send` |
| `mesh-fetch` is device-signed, single-use, short-lived | OK | `mesh-fetch/index.ts:44-85`: sealed request, Ed25519 over `FETCH_SIGN_LABEL ‖ canonical`, expiry ≤ 600 s, nonce table `mesh_fetch_nonces` (primary key, swept on expiry), per-device 6/min after signature check, reply encrypted to the request's `reply_key` and padded in 4 KiB steps |
| Nonces and replay | OK | `mesh-fetch/index.ts:75-83` (`23505` → `nonce_used`); migration `20261016130000_mesh_fetch_nonces.sql` (RLS, service role only) |
| Rate limits and the IP bucket | OK | both functions rate-limit on a keyed-hash IP bucket *before* any cryptography (`_shared/ipbucket.ts`: HMAC with the mesh secret, 12 bytes, never the address, swept after a day): 120/min drop, 30/min fetch; plus per recipient/device |
| IP source | **F-11** (info) | `_shared/auth.ts:34-39` trusts `cf-connecting-ip`, else the last `x-forwarded-for` entry; correct behind Supabase's proxy, spoofable if the function were ever exposed directly |
| Spray-and-wait with TTL, tiers (own, contact, stranger) and caps | OK | `core/mesh/src/node.rs` (`effective_ttl:587`, `MAX_REFUSALS:104`, `COPY_LIFETIME_SECS:101`, test `a_recipient_tag_and_the_strangers_share_are_budgeted:941`); copy rows capped at 600 (`core/src/mesh.rs` `MAX_COPY_ROWS`) |
| Mesh in a Release build | OK (none) | Bluetooth, its background modes and the Nearby code exist in Debug builds only (`ios/project.yml:67-70`, `ios/check-release-no-bluetooth.sh`): **the mesh is not in anything shippable yet**; the audit should treat the protocol, not the shipped app |

### 2.5 The server (Supabase Edge Functions, 33 functions)

Authentication of every function (read from each `index.ts`; `verify_jwt = false` is set for the 10 functions that cannot carry a user JWT: `send`, `identify`, `signin-password`, `signup-start`, `signup-verify`, `reset-start`, `reset-verify`, `blob-sweep`, `mesh-fetch`, `mesh-drop`; `supabase/config.toml`, around lines 440-460):

| Function | Auth | Rate limit | Note |
|---|---|---|---|
| `identify`, `signup-start`, `reset-start` | none (anonymous by nature) | yes | account enumeration → F-08 |
| `signup-verify`, `reset-verify` | email code | 5 wrong tries then locked (`take_code_attempt`) | |
| `signin-password` | password step of `auth_proofs`, then `requireUser` | yes | two-step sign-in |
| `code-verify`, `code-resend`, `signup-set-password` | `requireSession` + `auth_proofs` | attempts (5) / resend limits | |
| `send` | `requireUser` for identified sends; sealed proof for sealed sends | per user and per recipient | F-02 |
| `mesh-drop` | sealed header + access proof, no session | IP bucket + per recipient | |
| `mesh-fetch` | device Ed25519 signature + nonce, no session | IP bucket + per device | |
| `mailbox-fetch`, `mailbox-ack`, `keys-upload` | `requireDevice` (session bound to a registered device) | yes (`mailbox-ack`, `keys-upload` rely on the session) | |
| `keys-claim`, `users-find`, `users-lookup`, `users-devices`, `profile-get/-set`, `avatar`, `blob`, `attachment`, `livekit-token`, `turn-credentials`, `mesh-key`, `password-change-*`, `delivery-access-set`, `devices-register`, `undelivered-take` | `requireUser` (full session: both sign-in steps) | most yes; none in the function for `users-devices`, `profile-set`, `undelivered-take`, `delivery-access-set` (and `password-change-verify`, which counts wrong codes instead) | F-07 |
| `blob-sweep` | shared secret header | none, but it deletes only expired items | F-13 (info) |

| Item | Result | Evidence |
|---|---|---|
| Sessions are two-step: a token is not "full" until both password and email code succeeded | OK | `_shared/db.ts` `requireSession` / `requireUser` / `requireDevice`; `auth_proofs` table (password_ok + code_ok) |
| Row-level security on every table; privileges only to `service_role` | OK | 15 `create table public.*`, 15 `enable row level security` in `supabase/migrations/*.sql`; each followed by `revoke all … from public, anon, authenticated` and `grant … to service_role` (example: `20261016130000_mesh_fetch_nonces.sql:9-11`); the app has no direct table access, only functions |
| What is logged | OK | `_shared/http.ts:1` ("Nothing in here logs request bodies, keys, ciphertext or tokens"); the only `console.*` calls are error *codes* (`devices-register`, `mesh-fetch`, `_shared/db.ts:87`, `notify.ts`) and `access_denied` with a short reason (`_shared/access.ts:21`: no device, account, address or token); internal errors return `{error:"internal"}` without detail |
| Request size limits | OK | `readJson(req, maxBytes)` default 256 KiB, 8 KiB for `mesh-fetch`, 1 KiB for `livekit-token` (`http.ts:20-36`) |
| Secrets handling and 153's lesson | OK | the local test mesh key lives in `supabase/functions/.env` (public on purpose, tracked via a `.gitignore` exception), `config.toml` no longer carries `[edge_runtime.secrets]` (`grep MESH_ROUTING supabase/config.toml` finds nothing); `deploy-staging.sh` runs `check-staging-mesh-key.sh` and fails if staging holds the local key (LIME-153); the real key is made by `mesh-keygen.sh` straight into Supabase secrets |
| Third-party code on the server | **F-09** | `npm:@supabase/supabase-js@2` (an unpinned major) in the shared client |
| Device list is readable by any signed-in user | **F-07** | `users-devices/index.ts` (no rate limit; returns device ids and public keys for any user id; needed to send, and those keys are public) |

### 2.6 The phone (iOS)

| Item | Result | Evidence |
|---|---|---|
| Database key in the Keychain, this device only | OK | `ios/Lime/Core/Storage/StorageKeychain.swift:30`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (not synced to iCloud Keychain, not restored to another phone); session tokens the same (`SessionKeychain.swift:19`) |
| Files protected and excluded from backup | OK | `StorageBootstrap.swift:39` (`completeUntilFirstUserAuthentication`), `:135` `isExcludedFromBackup = true` |
| Locked-after-first-unlock phone | **F-03** | the choice above keeps the key available to the app (and so to a forensic tool that runs in that state) after the first unlock until reboot; the trade-off buys push, CallKit and the mesh in the background |
| Plain files and logs | **F-05** | `call-diagnostics.log` is a plain text file in Caches (`ios/Lime/Core/Calls/CallDiagnostics.swift:13-30`): timestamps, call state, candidate *kinds*, no addresses, SDP or keys; shared only through a Debug-build button (`AccountScreens.swift:400`). `NetworkLog` (method, path, status) is Debug-only (`Core/Network/NetworkLog.swift:4`) |
| Debug-only code is not in Release | OK | 33 launch-argument strings (`"-lime-…"`) in the app; all but one sit inside an `#if DEBUG` branch, the last is guarded by a constant that is `false` in Release (`StorageBootstrap.swift:182,186`); `BackendConfig.swift:12-18` honours `-lime-api-url` only in DEBUG; the repo's own gate `ios/check-release-no-bluetooth.sh` was run: exit 0 (section 6) |
| App Transport Security | OK | no `NSAppTransportSecurity` override anywhere in `ios/` |
| Permissions | OK | camera, microphone, photos, (Debug-only: Bluetooth) with specific usage strings (`ios/project.yml:60-70`); background modes `audio` and `voip` only in Release |
| Crash and diagnostic content | OK | no crash reporter or analytics SDK is linked (dependencies: LimeCore, WebRTC 152.0.0, LiveKit 2.17.0, `ios/project.yml:21-30`) |

### 2.7 Dependencies

| Item | Result | Evidence |
|---|---|---|
| Rust: known vulnerabilities | OK for the app, **F-10** (info) | `cargo audit` (cargo-audit 0.22.2, 1,338 advisories, 226 crates): 4 advisories, all `rustls 0.23.45` (RUSTSEC-2026-0346 medium 4.0, -0347 low, -0348 low, -0349 low), upgrade to ≥ 0.23.46. `cargo tree -i rustls` shows it enters only through `ureq`, a **dev-dependency** (the integration tests); it is not in the iOS or Android library. Nothing flagged in vodozemac, rusqlite/SQLCipher, aes-gcm, hkdf, sha2, hmac, ed25519-dalek, x25519-dalek, uniffi |
| Swift packages | OK, pinned | `ios/project.yml`: stasel/WebRTC `exactVersion 152.0.0`, livekit/client-sdk-swift `exactVersion 2.17.0`; no known-vulnerability tool was run for these (n/v) |
| Deno / npm on the server | **F-09** | `npm:@supabase/supabase-js@2` unpinned major; no other third-party imports |
| Web dev server (`server/`, `public/`) | out of scope | the old prototype; see F-14 |

### 2.8 Secrets in the repository and its history

| Item | Result | Evidence |
|---|---|---|
| Tree and history scan | OK | `gitleaks 8.30.1` (installed with the user's approval): `gitleaks git` over 541 commits, 8 hits, all triaged: the public local test mesh key (`supabase/functions/.env`, and `config.toml`, `core/src/mesh.rs`/tests fixtures, from before LIME-153), a throwaway test signing key in the Debug-only `NearbyTransport.swift:244`, a test password string in `tests/suites/auth.mjs`, the TURN test vector. **No real secret.** My own `git grep` for private-key blocks, `eyJ…` tokens, AWS/Slack/Stripe patterns found nothing |
| Working-copy scan | OK | `gitleaks dir`: 31 hits: the above, plus gitignored files: the anon-role key in `ios/Lime/Config/BackendConfig.generated.swift` and `supabase/.staging.public.env` (decoded: `"role":"anon"`, public by design), local Docker env under `supabase/.temp`, `data/auth.json`, and 11 `ed25519_dalek` build artefacts in `core/target` (compiled library code matching the private-key rule) |
| Tracked secrets files | OK | the only tracked `.env` is the public local test key (`supabase/functions/.env`); `git log --all -- data` is empty (never committed) |
| `data/auth.json` | **F-14** | the old web dev server's account store: real team email addresses, PBKDF2 hashes (600,000 iterations) for two accounts, session token hashes; gitignored, never committed, not served (`tests/suites/api.mjs:85` expects 404). Its risk is that it sits in a working copy next to `data/secret.key`: auditors get a fresh clone, never a working copy |

---

## 3. The five known open items, tested

### 3(a) A leaver cannot decrypt after a renewal (LIME-163): **passed, by inference**

**Test.** Three phones in a video group call; B leaves while A and C stay; a Debug-only tool on B (`-lime-ghost-leave`, `GroupCallManager.swift` `startGhost`, committed `4c5256c`, fixed `007e963`) keeps B connected to the LiveKit room with its old keys and takes no part in the key exchange, and logs every 5 s how many frames it decrypts per person.

| Phone | Role | Result |
|---|---|---|
| iPhone 13 mini ("Lime 13 mini") | B, the leaver, with `-lime-ghost-leave` | Before leaving (15:11, call-diagnostics): decoded A's video at about 5 fps and C's at about 10 fps, matching LiveKit's own decoded counts; cryptors `ok`. After leaving at 15:11:28: the ghost's totals stopped at 491 (C) and 413 (A) frames and **no new frame was decrypted for the next 90 s** (18 probe lines, 0 each) |
| Jean Chung's iPhone 12 mini | A, stayed in the call, sending video | stayed in, saw C (user) |
| iPad Pro 12.9" (5th gen) | C, stayed in the call, sending video | stayed in, saw A (user) |

An earlier run on the same ghost build (14:10-14:16) also showed 0 frames from both for 6 minutes; two earlier runs were invalid (the first ghost ended itself a second after starting: my bug, fixed; and the baseline of one call already read near 0 for reasons unrelated to the leaver: slow senders). The device runs also exposed a real bug in LIME-165's first draft (recovery ran during a normal leave), fixed.

**Why this counts as a pass, though it is not a direct proof.** The user records it as passed by inference: LIME-163's device check showed that a phone that *rejoins* holding only the renewed key decrypts everyone, so the media really is sent with the renewed key; a leaver holds only the old key; and the ghost decoded 0 frames for 90 s after leaving, which is what that predicts. **What is missing:** a direct proof that packets keep *arriving* at the ghost while frames stay undecodable (packets received rising, frames decoded frozen, ideally a frame-cryptor `decryptionFailed` state). The probe now logs packets and bytes received (`GroupCallMedia.swift` `trackDetails`), but the run that would have used it was not made. **Left for the independent audit.**

### 3(b) The copy's 6-hour expiry reveals "the sender was online" (156b)

- **What is visible.** A *copy* is a second packet for the same message, made when the sender has internet and an offline neighbour linked; it lives 6 h (`COPY_LIFETIME_SECS`, `core/mesh/src/node.rs:101`) where an ordinary packet lives 48 h. The expiry is part of the packet a carrier holds (`core/mesh/src/packet.rs:37`).
- **What an attacker learns.** A carrier (A3/A8) that holds a 6-hour packet learns one bit: the sender had a server connection when it was made (the message is already on the server). It cannot learn who, to whom, or what (the recipient tag is a daily pseudonym, the payload is sealed).
- **Practical?** Only for someone who is already a carrier of that packet; the bit has little value alone, but with timing of other packets from the same link it helps separate "online sender" from "offline sender".
- **Recommended fix and cost.** Give copies the ordinary life and let the existing caps bound them (600 copy rows). Cost: copies sit in carriers' stores up to 8 times longer (storage and a little air time); one constant plus the `mesh_delivered` delay estimate that reads "≤ 6 h left = a copy" (`core/src/mesh.rs`, 156b) must then use an explicit flag instead. Rating: low (F-04b).

### 3(c) Hello sends this phone's own daily tags to every linked phone (156c)

- **What is visible.** The Hello frame carries up to 16-byte tags for mail this phone is the recipient of: today's and yesterday's tag for each of its devices (`core/mesh/src/frame.rs:4`, `core/src/mesh.rs:62-66`). A tag is a pseudonym that changes at UTC midnight, but is identical on every link during the day.
- **What an attacker learns.** Any lime phone that links with this one (including a stranger; links are made automatically) receives a stable, readable-without-keys identifier valid 24-48 hours. A nearby stranger, or several cooperating ones, can recognise "the same phone" at different places and times in that window, even though Bluetooth addresses rotate: movement and presence tracking of a pseudonym, not of a name. Contacts can compute the tag and so know whose it is.
- **Practical?** Yes for anyone who runs the app as a scanner at a doorway, a school gate or a protest; no key or server access needed. It runs against the "nearby strangers learn nothing" promise and the privacy bar, so this is the one **medium** in the mesh.
- **Recommended fix and cost.** Send per-link blinded tags: each side adds a random nonce to its Hello and sends `H(tag ‖ link_nonce)`; the holder of a packet for tag T compares `H(T ‖ nonce)` for its own packets (it knows T), so matching still works and the value differs on every link (no cross-link correlation). Cost: one nonce in the Hello and a hash per held packet per Hello; a frame change plus a protocol version bump; about a day of work plus tests. Rating: medium (F-04).

### 3(d) The relay's IP reaches the server (155/157)

- **What the server learns.** For `mesh-drop`: a caller address, the time, and (after opening the header) the recipient *device* and the sealed payload. For `mesh-fetch`: device D's mail was fetched at time t from address X. Not which account relayed (no session), not the content. The rate-limit bucket holds only a keyed hash of the address (`_shared/ipbucket.ts`), swept after a day; the function code never logs it.
- **What an attacker learns.** A compromised server (A1) or the hosting platform's own request logs (outside our control) can link "device D was served at time t" to an address that belongs to the relay phone *next to D*: that places an offline phone near a network address (a school, a house). The bucket table alone does not allow that; platform logs do.
- **Practical?** Needs server or platform-log access (A1), not a bystander. It is the honest limit the function header already states.
- **Recommended fix and cost.** (1) Disclose it in the privacy text now. (2) Before wide launch, route these two calls through an oblivious relay (OHTTP style) so the server sees the relay operator's address, not the phone's. Cost: a third party or a small proxy we run, an extra hop (tens of ms), and the HPKE-style request wrapping; one to two weeks. Rating: low (F-04c); medium if the "emergency, offline" use becomes a headline promise.

### 3(e) Own packets leave without jitter (161)

- **What is visible.** The 10-220 ms relay jitter now applies only to packets a phone forwards for others; a phone's own new packets leave at once, in creation order (`core/mesh/src/node.rs:1314` test `only_what_this_phone_forwards_for_others_keeps_the_relay_jitter`).
- **What an attacker learns.** The exact moment a phone made a packet (when its owner pressed send), to every neighbour on a direct link: the packet arrives with no forwarding delay, so a receiver can tell "originated here" from "forwarded" by timing. A neighbour already knows it shares a link with that phone, so the new information is the originator bit and the send time, not identity.
- **Practical?** Only with a receiver in radio range at the moment, and it reveals when someone typed, not what.
- **Recommended fix and cost.** Add a small random delay (for example 0-150 ms) to the start of each *batch* of own packets, keeping their order by creation sequence (so a message and its reaction cannot swap). Cost: up to 150 ms latency for a first packet; a few lines in `node.rs` plus a test. Rating: low (F-04d).

---

## 4. Findings

No critical, no high. Ordered by severity.

| ID | Severity | Finding | Where | Reproduce | Recommended fix |
|---|---|---|---|---|---|
| F-04 | **medium** | Hello hands this phone's daily recipient tags to every linked phone, strangers included, so a nearby stranger can recognise one phone across places for 24-48 h | `core/mesh/src/frame.rs:4,16`; `core/src/mesh.rs:62-66` | Link two phones, read the Hello's tag bytes on each link; the same 16 bytes appear on every link that day | Per-link blinded tags (3c) |
| F-02 | **medium** | `send` still accepts the legacy bearer-style `{ sealed: access_key }` proof (a static secret derived from the delivery key, presented as is) next to the signature; its own comment says remove it before TestFlight | `supabase/functions/send/index.ts:4,113`; `_shared/access.ts` `verifySealed` (the `sealed` branch) | POST `send` with a `sealed` access key from an old device: accepted | Remove the overlap once every device signs (one brief); then `allowAccessKey` is always false |
| F-03 | low | Database key and files are available after the first unlock until reboot (`AfterFirstUnlockThisDeviceOnly`, `completeUntilFirstUserAuthentication`): a locked phone that was unlocked once since boot is easier for forensic tools than a freshly booted one | `StorageKeychain.swift:30`; `StorageBootstrap.swift:39` | n/a (design) | A decision, not a bug: keep (needed for background push, CallKit, mesh) and say so in the privacy text; offer an optional "protect when locked" setting later |
| F-04b | low | Copy packets live 6 h, ordinary 48 h: reveals "sender was online" | `core/mesh/src/node.rs:101`; `packet.rs:37` | Inspect a copy's `expires_at` | Same life as ordinary packets (3b) |
| F-04c | low | The relay's address reaches the server (and platform logs) on `mesh-drop` and `mesh-fetch` | `mesh-drop/index.ts`, `mesh-fetch/index.ts` | n/a (design) | Disclose now; oblivious relay before wide launch (3d) |
| F-04d | low | A phone's own packets leave with no jitter: send time and "originated here" are visible to a neighbour | `core/mesh/src/node.rs` (LIME-161) | Watch packet arrival at a neighbour after pressing send | Batch-start jitter keeping order (3e) |
| F-05 | low | `call-diagnostics.log` is plain text in Caches (call times, call state, ICE candidate kinds; no addresses, SDP or keys) and is written in Release too | `ios/Lime/Core/Calls/CallDiagnostics.swift:13-40` | Pull the file from the app container | Keep the log in memory only in Release, or cap it to the last call and give it file protection `complete` |
| F-06 | low | `livekit-token` mints a token for any room id to any signed-in user; the server cannot check group membership. A non-member who learns a call's room id can join the room (cannot decrypt; sees random identities and presence) | `supabase/functions/livekit-token/index.ts:14-20` | Sign in as any user, request a token for a known 64-hex room | Keep the room id out of anything but the encrypted ops (already so); optionally bind the token to a per-call secret in the op |
| F-07 | low | Several authenticated functions have no rate limit of their own: `users-devices`, `profile-set`, `undelivered-take`, `delivery-access-set`, and the device-bound `keys-upload` and `mailbox-ack` (they rely on the session; the code-checking functions count wrong codes instead). `users-devices` returns the device ids and public keys of any user id to any signed-in user | those `index.ts` files | Call `users-devices` in a loop | Add `rateLimit` (a one-line change each) |
| F-08 | low | Account enumeration: `identify` and `signup-start` say whether an email has an account (by design: the sign-in flow needs it) | `identify/index.ts`, `signup-start/index.ts` | Ask `identify` for a known and an unknown email | Per-address and per-IP limits exist; add a uniform response delay and a stricter anonymous limit |
| F-14 | low | `data/auth.json` (the old web dev server): real team emails, PBKDF2 hashes, session token hashes, next to `data/secret.key`; gitignored, never committed | `data/` (working copy only) | `ls data/` | Give auditors a fresh `git clone`, never a working copy (`docs/audit-scope.md`); delete or rotate if the prototype is retired |
| F-09 | info | `npm:@supabase/supabase-js@2` is an unpinned major in the Edge Functions' shared client | `supabase/functions/_shared/db.ts` | read | Pin an exact version |
| F-10 | info | `cargo audit`: 4 advisories on `rustls 0.23.45`, dev-dependency only (not shipped) | `core/Cargo.lock` via `ureq` | `cargo audit` | `cargo update -p rustls`; run `cargo audit` in CI |
| F-11 | info | `clientIp` trusts `cf-connecting-ip` then the last `x-forwarded-for` entry: correct behind Supabase's proxy, spoofable if a function were reachable directly | `_shared/auth.ts:34-39` | send the header to the local stack | Document the assumption; prefer the platform's own forwarded-for position |
| F-12 | info | The group-call sender key (and the room id and identity) are two UUIDv4s concatenated: 244 bits of entropy, with fixed version bits, not 256 uniform bits | `core/src/store/group_calls.rs:48-51` | read | Use 32 bytes from the OS random source |
| F-13 | info | `blob-sweep` is reachable without a JWT and does one database read before the secret check | `blob-sweep/index.ts:17-23` | POST without the header: 401 | Check the header first, then read |

Tally: critical 0, high 0, **medium 2** (F-02, F-04), **low 9** (F-03, F-04b, F-04c, F-04d, F-05, F-06, F-07, F-08, F-14), **info 5** (F-09 to F-13).

---

## 5. What this review did not cover

- **No fuzzing, no dynamic penetration test** of the Edge Functions or the Bluetooth framing.
- **Cryptographic construction of the glue** (HKDF labels, nonce use, signing inputs) was read and found consistent, with the known-answer vectors in the tests (`delivery.rs:237`), but not formally analysed: the auditor's first focus.
- **Swift package vulnerability data** for WebRTC and LiveKit was not checked against an advisory database.
- **Release binary** was checked by the repo's script and by source reading, not by a full string diff of Debug against Release.
- **Staging data**: no database queries were made beyond the read-only mesh-key digest check; no staging writes.
- **3(a)** is a pass by inference (section 3a); the direct packets-vs-frames proof is left to the independent audit.
- The Android app does not exist yet; only LimeCore compiles for Android (`core/check-android.sh`: OK).
- **Web prototype** (`server/`, `public/`) is out of scope.

## 6. Commands run (so the review can be repeated)

```
cargo audit                                  # in core/: 4 rustls advisories, dev-dependency only
cargo tree -i rustls                         # ureq, [dev-dependencies]
gitleaks git --redact                        # 541 commits, 8 hits, all test fixtures / public keys
gitleaks dir --redact .                      # 31 hits, triaged above
./supabase/check-staging-mesh-key.sh         # ok: staging holds a key that is not the local test key
cd core && cargo test                        # 278 pass
cd core && ./check-android.sh                # OK
ios/check-release-no-bluetooth.sh            # exit 0: "Release build: no Bluetooth background modes, no usage text, no CoreBluetooth, no Nearby test."
```
