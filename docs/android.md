# Android

Lime's Android app is not started yet. This page records the plan, how to check that the shared core still builds for Android, and what is owed before the app can start.

## The plan

Kotlin and Jetpack Compose on top of **LimeCore** (the Rust core, `core/`), reached through UniFFI-generated Kotlin bindings. The core owns the protocol, encryption, the encrypted store and, increasingly, the app's non-UI logic; Compose is views only. The platform adapters, written in Kotlin:

- calls: ConnectionService / Telecom;
- push: FCM;
- mesh messaging: Android BLE;
- media: CameraX and WebRTC;
- keys: the Android Keystore;
- the minimised call window: the system Picture in Picture.

## Checking the core builds for Android

```sh
./core/check-android.sh
```

It builds `liblime_core.so` for arm64-v8a and x86_64 (via `cargo-ndk`, requesting a `cdylib` so `Cargo.toml`'s `crate-type` and the iOS build are unchanged), prints their sizes, generates the Kotlin bindings with `uniffi-bindgen`, and **compiles** them with `kotlinc` against JNA plus a tiny harness (`core/android-check/Main.kt`). It does not run anything: that needs a device or emulator. It exits non-zero on any failure and stops early with a message if the NDK or JDK is missing. Outputs are under `core/target/`.

Tooling it needs: the rustup Android targets (pinned in `core/rust-toolchain.toml`), `cargo-ndk`, `kotlin` (Homebrew), a JDK (Temurin), and the Android NDK with `ANDROID_NDK_HOME` set (command-line tools from `brew install --cask android-commandlinetools`, then `sdkmanager "ndk;<version>"`). Last verified with cargo-ndk 4.1.2, Kotlin 2.4.21, NDK 30.0.16248370.

How it builds on Android:

- **SQLCipher** needs a crypto library. Apple builds use CommonCrypto; Android has none, so `core/Cargo.toml` turns on `rusqlite`'s `bundled-sqlcipher-vendored-openssl` for `target_os = "android"` only, which builds OpenSSL from source. The Apple features are unchanged.
- **vodozemac** and the other crates needed nothing special.
- The Kotlin is generated from a **non-stripped** host build, because the release profile's `strip = true` can drop the metadata UniFFI reads.
- Sizes at the time of writing (release, arm64-v8a / x86_64): about 6.8 MB / 7.5 MB.

## Rule: names exposed through UniFFI

**No UniFFI-exposed type, enum or enum variant may be named `List`, `Map`, `Set`, `String`, `Int` or `Unit` (or `Result`).** A variant named like that becomes a Kotlin nested class that shadows the standard type inside its sealed class, and the generated Kotlin stops compiling (this happened with `Block::List`, renamed `ItemList` in LIME-136). `check-android.sh` catches it.

## Android debt

Logic that lives in Swift today and must move into the core before (or as) Android needs it (LIME-133):

- `CallManager`'s signalling (phases, timeouts, busy/unavailable/glare, the breakthrough rule, renegotiation decisions, `lime-ctl` handling); media, CallKit and PiP stay platform code;
- status and work hours (`StatusSettings` / `StatusPlan`);
- call history rules (grouping, outcome keys, missed counting);
- the list filters;
- the profile context rule (where a profile was opened from decides which chat and sender);
- unread counts, including marked-unread = 1.

## Lesson carried over from iOS: system windows take explicit data

On iOS, a SwiftUI view inside the system-hosted Picture in Picture window crashed because it read the app's environment, which that window does not have (LIME-135-fix). The Android twin: the views shown in the system PiP window (and any other system-hosted surface, such as a notification or widget) must take explicit data and read nothing from the app's dependency graph, `CompositionLocal`s, view models or singletons that the system window does not provide.
