# LimeCore

Lime's shared core, written in Rust. The iOS app links it through [UniFFI](https://mozilla.github.io/uniffi-rs/); Android and desktop follow later (see [`docs/architecture.md`](../docs/architecture.md), section 3).

It wraps [vodozemac](https://github.com/matrix-org/vodozemac) (Olm and Megolm) and, since LIME-90, owns the app's **encrypted local store**: SQLite encrypted at rest with SQLCipher. There is **no networking and no persisted Olm keys yet**.

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
cargo test                           # Olm, Megolm, tampered ciphertext, the self-test
cargo clippy --all-targets -- -D warnings
./build-ios.sh                       # static libs for iOS and the simulator, Swift bindings, xcframework
```

`build-ios.sh` writes `ios/Frameworks/LimeCoreFFI.xcframework` and `ios/Lime/Core/Generated/lime_core.swift`. Both, and `core/target/`, are gitignored and rebuilt from source. `ios/generate.sh` runs the script first, so normally you just run that. The project links the xcframework and compiles the generated Swift; there is no Xcode build-phase script.

The simulator build is Apple-silicon only (`aarch64-apple-ios-sim`); the iOS project excludes `x86_64` simulators.

## Licences

See [`THIRD_PARTY.md`](./THIRD_PARTY.md).
