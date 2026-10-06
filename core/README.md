# LimeCore

Lime's shared core, written in Rust. The iOS app links it through [UniFFI](https://mozilla.github.io/uniffi-rs/); Android and desktop follow later (see [`docs/architecture.md`](../docs/architecture.md), section 3).

This is the skeleton (LIME-89). It wraps [vodozemac](https://github.com/matrix-org/vodozemac) (Olm and Megolm) and proves the whole toolchain with a real encryption round trip. There is **no networking, no storage and no persisted keys yet**.

## FFI surface

Exactly two functions, and nothing else is exported. No secret material crosses the FFI or is logged.

- `core_version() -> String`: the crate version.
- `encryption_self_test() -> SelfTestReport { olm_ok, megolm_ok, detail }`: two in-memory Olm accounts and a session round-tripping a message both ways, then a Megolm group session round-tripping a message. `detail` is a short line with no key material.

In Swift these are `coreVersion()` and `encryptionSelfTest()`. In the app, long-press the logo on Messages to see "About Lime" run the test.

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
