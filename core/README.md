# LimeCore

Lime's shared core, written in Rust. The iOS app links it through [UniFFI](https://mozilla.github.io/uniffi-rs/); Android and desktop follow later (see [`docs/architecture.md`](../docs/architecture.md), section 3).

It speaks Lime's API v2 ([`docs/api-v2.md`](../docs/api-v2.md)) and wraps [vodozemac](https://github.com/matrix-org/vodozemac) (Olm and Megolm) and, since LIME-90, owns the app's **encrypted local store**: SQLite encrypted at rest with SQLCipher. The network is the platform's (see Transport below), and the Olm keys are persisted inside the store.

## FFI surface

Two functions and one object. No secret material crosses the FFI or is logged.

- `core_version() -> String`: the crate version.
- `encryption_self_test() -> SelfTestReport { olm_ok, megolm_ok, detail }`: two in-memory Olm accounts and a session round-tripping a message both ways, then a Megolm group session round-tripping a message. `detail` is a short line with no key material.

- `LimeStore`, the encrypted store (thread-safe):
  - `LimeStore.open(path, key)` opens (creating if needed) the database with a raw 32-byte key and migrates it. A wrong key fails with `StoreError::WrongKeyOrNotADatabase`.
  - `seed_sample_data_if_empty()` inserts the made-up teachers, groups and messages (`src/store/sample.rs`) into an empty store.
  - `list_conversations()`, `list_messages(conversation_id)`, `send_local_message(conversation_id, text)`.
  - `StoreError` is a small enum; no key material is ever in an error or a log.

In Swift these are `coreVersion()`, `encryptionSelfTest()` and `LimeStore`. In the app, long-press the logo on Messages to see "About Lime" run the test.

## The protocol (LIME-93)

Two LimeCore instances, as two different accounts, exchange an Olm-encrypted message through the server. Scope: **identified** 1:1 sends only. No Megolm, sealed sends, delivery keys, groups or Requests yet.

FFI additions (on `LimeStore`, plus one function):

- `register_device(transport, auth_token) -> DeviceInfo`: creates this device's keys on first use, registers the device (idempotent), and tops up its one-time keys (upload 50; top up below 20).
- `send_text_identified(transport, auth_token, recipient_user_id, text) -> MessageItem`: looks up the recipient's devices and verifies their cross-signatures (pinning their master key on first use), claims one-time keys, starts or reuses an Olm session per device, and sends the signed op.
- `sync(transport, auth_token) -> SyncReport { received }`: fetches the mailbox, decrypts and verifies, stores each message in a DM with the sender (titled with their user id for now), and acknowledges.
- `lookup_user_by_email(transport, auth_token, email) -> Option<String>`: an exact, case-insensitive email match; the user id only.

Modules: `keys` (the Olm account and master key), `protocol` (the signed op and sealed inner, canonical bytes, the hybrid logical clock), `client` (the calls above), `transport` (the callback), `store/account.rs` (the persisted state).

**Keys are persisted inside the SQLCipher store.** The Olm account and the Olm sessions are vodozemac pickles encrypted with a key derived from the store key (HKDF-SHA256, info `lime-pickle-v1`). The account's master signing key is stored in the same encrypted database as base64 (vodozemac has no pickle format for a bare Ed25519 key). Nothing is logged, and no key leaves the device.

**Transport.** The platform's network is a UniFFI callback interface, so the protocol (what to call, signing, encrypting, state) stays in Rust while Swift (`URLSession`) and later Kotlin (OkHttp) make the requests. `request(method, path, headers, body)` is blocking and returns a status and a body; a network failure is a `TransportError`. The platform adds the base URL and the public `apikey` header; the user's token is passed in by the platform per call and the core never stores passwords or tokens. See `ios/Lime/Core/Network/URLSessionTransport.swift`.

## Integration tests

`tests/integration.rs` runs against a real Supabase stack with two throwaway accounts (created and deleted through the admin API): register both, look up by email, send, check that the server's copy is ciphertext, sync, decrypt, reply, acknowledge, send again on the established sessions, and survive a restart; plus a test that a ciphertext tampered with on the server is not stored.

```bash
./core/run-integration.sh            # the local stack (starts it if needed)
./core/run-integration.sh staging    # the staging project (needs `supabase login` and ~/.lime/staging.env)
```

It uses the `integration` cargo feature and reads the URL and keys from the environment only; nothing secret is written down.

## The store

`src/store/` has the schema (`migrations.rs`, versioned with `PRAGMA user_version`, forward-only), the sample content and the tests. Tables are the local view only: `people`, `conversations`, `members`, `messages` (a UUIDv7 id made by the core, the display time, and `local_state`, `sent_local` for now). The v2 fields that come later (signature, hybrid logical clock, parents) are noted in a comment in `store/mod.rs` and are deliberately not columns yet. On iOS the app generates the key, keeps it in the Keychain and puts the file in Application Support; see `ios/README.md`.

SQLCipher is compiled in by `libsqlite3-sys` (feature `bundled-sqlcipher`), using Apple's CommonCrypto on Apple targets; leave `OPENSSL_DIR` unset.

## Prerequisites

Rust through rustup (user-level, no `sudo`):

```bash
brew install rustup
rustup-init -y --no-modify-path
```

The toolchain (1.99.0) and the iOS targets are pinned in `rust-toolchain.toml`; rustup installs them the first time `cargo` runs in this folder. Xcode is needed for the iOS build.

## Commands

```bash
cd core
cargo test                           # Olm, Megolm, the store, the protocol (signatures, canonical bytes, persistence)
cargo clippy --all-targets -- -D warnings
./build-ios.sh                       # static libs for iOS and the simulator, Swift bindings, xcframework
```

`build-ios.sh` writes `ios/Frameworks/LimeCoreFFI.xcframework` and `ios/Lime/Core/Generated/lime_core.swift`. Both, and `core/target/`, are gitignored and rebuilt from source. `ios/generate.sh` runs the script first, so normally you just run that. The project links the xcframework and compiles the generated Swift; there is no Xcode build-phase script.

The simulator build is Apple-silicon only (`aarch64-apple-ios-sim`); the iOS project excludes `x86_64` simulators.

## Licences

See [`THIRD_PARTY.md`](./THIRD_PARTY.md).
