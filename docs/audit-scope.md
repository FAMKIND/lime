# lime: scope for an independent security audit

**Prepared for:** an external auditor (for example through a programme such as OTF's Red Team Lab). **Prepared by:** the lime team, 2026-10-18, from the in-house review (`docs/security-review-2026-10.md`, which lists what we already found and what we did not cover). **Applicant:** Lime Chat Inc (a 501(c)(3), once formed), which owns Lime Chat LLC.

**What lime is.** A free, end-to-end encrypted messenger for teachers: messages, files, one-to-one and group calls, and (the part that makes it different) **messaging over Bluetooth between nearby phones when there is no internet**, for emergencies and for schools with poor connectivity. No ads, no tracking, no data sales. The server is a blind mailbox: it holds ciphertext and the minimum routing data.

**How to receive the code.** **Always from a fresh `git clone` of the agreed commit, never from a working copy or a zip of one.** Our working copies hold local, ignored files (a prototype server's account store with real email addresses and password hashes under `data/`, generated configuration with the project's public key, local build output). The auditor should also expect that the repository is not yet public: licensing (open source) is being decided before the audit starts.

---

## 1. Architecture in two pages

### 1.1 Parts

```
 iPhone app (SwiftUI) ──── LimeCore (Rust, shared with Android later, via UniFFI)
   views, CallKit, Keychain,        all protocol and crypto glue: Olm/Megolm (vodozemac),
   Bluetooth radio, LiveKit,        the op log, SQLCipher store, delivery keys, mesh engine
   WebRTC                           bindings, group-call key rules
        │                                   │
        │ HTTPS (Supabase Edge Functions)   │ Bluetooth LE (Debug builds only today)
        ▼                                   ▼
 Supabase: Auth, Postgres (RLS, service-role only), Storage, 33 Edge Functions (Deno/TypeScript)
 LiveKit SFU (self-hosted) for group calls; TURN for one-to-one calls
```

- **LimeCore** (`core/`, Rust, about 21,000 lines plus about 1,900 for the mesh engine crate `core/mesh`) decides everything: who may start or join a call, when keys renew, how a message is sealed and verified, what the mesh does. The iOS app (`ios/Lime`, about 31,000 lines of Swift) only draws screens and adapts Apple APIs (Keychain, CallKit, Bluetooth, LiveKit, WebRTC). The Android app does not exist yet; the core already compiles for Android (`core/check-android.sh`).
- **The server** (`supabase/functions`, about 2,400 lines of TypeScript, 33 functions; `supabase/migrations`, about 650 lines of SQL; 15 tables, all with row-level security and privileges only for the service role). The app has no direct table access, only functions. Server tests: `supabase/tests` (about 2,650 lines, Deno).
- **Other code in the repository that is not part of the product:** `server/`, `public/` (a web prototype, the visual spec; frozen), `tests/` (its browser tests). Out of scope.

### 1.2 Identity, keys and messages

- Each **device** has an Olm account (Curve25519 identity key, Ed25519 signing key) and each **account** has a master Ed25519 key that signs its devices (`core/src/keys.rs`). Contacts verify the master key's fingerprint (safety number); a changed key warns and clears verification (`core/src/store/mod.rs`).
- **Messages** are Olm (one to one) and Megolm (groups; session keys travel over Olm). Every op is signed by a device certificate chained to the master key (`core/src/protocol/`).
- **Delivery.** The server keeps a mailbox per *device*. A sender posts ciphertext; the server stores `SHA-256(ciphertext)` for de-duplication and the ciphertext itself, and (for sealed sends) **no sender**. To post to a device the sender must present an **access proof**: an Ed25519 signature, by a key pair both sides derive from the recipient's *delivery key* (HKDF-SHA256), over `"lime-access-v2" ‖ SHA-256(ciphertext) ‖ device UUID` (`core/src/store/delivery.rs`, `supabase/functions/_shared/access.ts`). Blocking someone rotates the delivery key. A legacy shared-secret proof is still accepted during an overlap (finding F-02).
- **Storage on the phone:** SQLCipher database whose key is in the Keychain (`AfterFirstUnlockThisDeviceOnly`), file protection until first unlock, excluded from backup. Olm and Megolm pickles are additionally encrypted under an HKDF-derived key.
- **Files:** AES-256-GCM in chunks under a random per-file key that travels inside the encrypted message; ids are capabilities; the server holds ciphertext chunks (`core/src/store/attachments.rs`, `supabase/functions/attachment`).

### 1.3 Calls

- **One to one:** WebRTC; the offer/answer travel as signed ops carrying the DTLS fingerprint, so a relay cannot swap the media key; a four-emoji check from both sides (`core/src/store/calls.rs`, `call_emoji.rs`).
- **Group:** LiveKit with end-to-end media encryption: **one sender key per participant**, created by the core, sent only inside signed Olm-encrypted ops to the people in the call, **renewed whenever anyone leaves** (`core/src/store/group_calls.rs`). The app installs every key in LiveKit's key slot 0 (`ios/Lime/Core/Calls/GroupCallMedia.swift`). The SFU forwards ciphertext only; `livekit-token` mints short-lived join tokens.

### 1.4 The mesh (offline Bluetooth messaging)

- A phone that cannot send (no internet) seals the message as usual, wraps it as a **mesh packet** and hands it to any lime phone nearby. Carriers store and forward (spray-and-wait with a TTL and trust tiers: own, contact, stranger); they see only opaque bytes, a **recipient tag** (`HMAC-SHA256(HKDF(delivery_key), label ‖ UTC day ‖ device)[..16]`, changing daily) and a **sealed routing header** (the recipient device and the access proof, sealed to the server's pinned mesh public key with an ephemeral X25519 key, HKDF-SHA256 and AES-256-GCM) (`core/src/mesh.rs`, engine in `core/mesh/src`).
- A carrier that reaches the internet uploads the packet through **`mesh-drop`**, a function with **no session**: the sealed header is the authority, so the server does not learn who carried it. An offline phone can ask a nearby online phone to fetch its mail through **`mesh-fetch`**: a request signed by the offline device's own key, sealed to the server, single-use (nonce table), at most 10 minutes old, answered encrypted to a key in the request and padded (`supabase/functions/mesh-fetch`).
- Both functions rate-limit on a **keyed hash** of the caller's address (never stored in the clear).
- **Status:** Bluetooth and the mesh code exist in **Debug builds only** today; the first TestFlight waits for the mesh. The auditor should audit the protocol and engine as they will ship.

---

## 2. Components and sizes (lines, tests included where noted)

| Component | Path | Language | Lines (approx.) |
|---|---|---|---|
| LimeCore: store, protocol, client, tests | `core/src` | Rust | 21,500 (tests included; the largest file is `client_tests.rs`) |
| Mesh engine crate | `core/mesh/src` | Rust | 1,900 |
| iOS app | `ios/Lime` | Swift | 30,900 (generated bindings excluded) |
| iOS tests | `ios/LimeTests` | Swift | 8,400 |
| Edge Functions | `supabase/functions` | TypeScript (Deno) | 2,400 |
| Database | `supabase/migrations` | SQL | 650 |
| Server tests | `supabase/tests` | TypeScript | 2,650 |
| Docs (architecture, API, data model, mesh DPIA) | `docs/` | Markdown | 4,300 |

Key documents: `docs/architecture.md` (decisions and components), `docs/api-v2.md` (every endpoint), `docs/message-format.md`, `docs/data-model.md`, `docs/dpia-mesh.md` (what each party learns on the mesh).

Third-party code of note: `vodozemac 0.11.1` (Olm/Megolm; independently audited by Least Authority in 2022), `rusqlite 0.40.2` with SQLCipher, RustCrypto `aes-gcm`, `hkdf`, `hmac`, `sha2`, `ed25519-dalek`/`x25519-dalek`, UniFFI 0.32, WebRTC 152.0.0 (`stasel/WebRTC`), LiveKit client SDK for Swift 2.17.0, Supabase.

---

## 3. Threat model (summary; full version in the in-house review, section 1)

Assets: message and call content, keys, who talks to whom and when, files, account data, server secrets.
Adversaries: a curious or compromised server operator; a network attacker; a nearby Bluetooth attacker or a stranger's phone; a malicious group member; a former member or contact; a stolen unlocked phone; a stolen locked phone; a malicious relay phone.
Promises to test: only the two ends read content; the server learns the minimum (sealed sender, sessionless mesh upload, no account link for relays); a leaver or a blocked contact loses access; nearby strangers learn nothing readable; nothing leaves the phone unsent.

---

## 4. Focus areas (please spend most of the time here)

1. **Crypto glue in LimeCore.** Everything we wrote around vodozemac and RustCrypto: the sealed-to-server construction (`core/src/mesh.rs` `seal_to_server`: label, key id, ephemeral X25519, HKDF info, AES-GCM nonce derived from the same HKDF output, AAD), the access-proof signature input and its server check, the delivery-key derivations (access key, signing seed, tag key) and their labels, the pickle key derivation, chunked file encryption (nonce and AAD), the call-key rules. Known-answer vectors exist (`core/src/store/delivery.rs`, `core/src/mesh.rs` tests); please attack the design, not only the code.
2. **The mesh protocol.** Frame parsing and bounds (`core/mesh/src/frame.rs`), packet validation, the tag and what a link learns (we already know about F-04), spray-and-wait state, replay and duplicate handling (`received_ciphertexts`), resource exhaustion by a hostile carrier (storage caps, tiers, rate limits), the relay-fetch frames (5-8), and what an upload or a fetch lets a malicious relay do or learn.
3. **The sessionless endpoints.** `mesh-drop`, `mesh-fetch` and the sealed branch of `send`: any request that can be made without a session. Replay, nonce handling, the rate-limit buckets and their keyed hash, oracle behaviour (the single opaque 403), timing, the `clientIp` assumption (F-11), and the staging/production key handling (`mesh-keygen.sh`, `check-staging-mesh-key.sh`).
4. **Group-call E2EE.** Key delivery, renewal on leave, ownership of a participant id (first signed op claims it), behaviour after crashes and rejoins (recent fixes: LIME-163, LIME-165), the use of LiveKit key slot 0, the token endpoint (F-06). One item is explicitly **left open for you**: a direct proof that a participant who left (holding only the old key, still connected to the room) receives packets that it cannot decrypt (our device test saw 0 decoded frames for 90 s after leaving, and we infer, but did not directly show, that packets kept arriving).

Also welcome, if time allows: authentication flow (two-step sign-in, `auth_proofs`), row-level security and the service-role-only model, the iOS storage and Keychain choices (F-03), and the Edge Function inputs.

## 5. Out of scope

- The web prototype (`server/`, `public/`, `tests/`) and its data.
- The Android app (not written) and any desktop client.
- Apple's and LiveKit's own code (WebRTC, the SFU) beyond how lime uses them; vodozemac's internals (audited 2022).
- Denial of service against Supabase infrastructure; social engineering; physical attacks beyond the "stolen phone" cases in the threat model.
- Marketing site, store listing and legal text.

## 6. How to build and run

**Prerequisites:** macOS with Xcode (iOS 17 SDK or newer), Rust (stable) with the iOS targets, [XcodeGen](https://github.com/yonaskolb/XcodeGen), Docker (for the local Supabase stack), the Supabase CLI, and Deno.

```
git clone <the agreed repository and commit> lime && cd lime

# 1. LimeCore (Rust): tests, then the iOS xcframework and Swift bindings
cd core && cargo test                      # about 280 tests, all offline
./build-ios.sh                             # builds LimeCoreFFI.xcframework + Swift bindings
./check-android.sh                         # builds the Android libraries and Kotlin bindings (optional)
cargo audit                                # dependency advisories (rustls shows up: dev-dependency only)

# 2. The backend, locally
cd .. && ./supabase/test.sh                # starts the local stack (Postgres, Auth, Storage, Edge runtime in Docker),
                                           # restarts the Edge runtime and runs the server tests (about 80)
# the local mesh key is a public test key in supabase/functions/.env; it is NOT the staging key

# 3. The iPhone app (Debug build; the mesh and Bluetooth exist in Debug only)
cd ../ios && ./generate.sh                 # XcodeGen: creates Lime.xcodeproj from project.yml
open Lime.xcodeproj                        # run on a device (Bluetooth needs real phones)
# or: xcodebuild test -scheme Lime -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:LimeTests
./check-release-no-bluetooth.sh            # confirms a Release build has no Bluetooth/Nearby code

# 4. Core against the real local backend
cd ../core && ./run-integration.sh         # the integration test (needs the stack from step 2)
```

- **Backend URL and key for the app:** `ios/Config/BackendConfig.generated.swift` (generated; holds only the project's public anon key). A Debug build also accepts `-lime-api-url` and `-lime-api-key` launch arguments to point at the local stack.
- **Test accounts:** the integration tests create their own; there is no shared password in the repository.
- **Mesh on real phones** needs at least two physical iPhones with Bluetooth; `docs/spike-ble.md` and `docs/dpia-mesh.md` describe the behaviour. We can run a joint session on three phones on request, including the Debug-only tool that keeps a phone in a call after it leaves (`-lime-ghost-leave`).
- **Staging** exists but is not needed for the audit; we can give the auditor their own Supabase project from the migrations (`supabase/deploy-staging.sh` shows the order).

## 7. What we already know

See the in-house review's findings table (`docs/security-review-2026-10.md`, section 4): no critical or high findings; two medium (F-02 the legacy shared-secret proof in `send`, to be removed before TestFlight; F-04 the daily recipient tag visible to any linked phone), and a short list of lower items with recommended fixes. Please do not spend time re-finding those; do tell us if you disagree with a rating.
