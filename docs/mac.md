# lime for Mac

The Mac app: lime's chat list and conversation side by side, with a Mac menu bar.

Status: not started.

Build entry points: `mac/build-core.sh` (done, below); to come: `mac/generate.sh`, `mac/run.sh`.

## Building the core

```
mac/build-core.sh              # builds LimeCore for the Mac
mac/tools/selftest/build.sh    # builds and runs the self-test on this Mac
```

Outputs (all gitignored): `mac/Frameworks/LimeCoreFFI.xcframework` with two slices, `macos-arm64` (deployment target macOS 14.0) and `ios-arm64-maccatalyst` (iOS 17.0 equivalent); the Swift bindings in `mac/Lime/Generated/`. The module is `LimeCoreFFI`, as on iOS. Apple silicon only. The script adds the two Rust targets locally with `rustup target add` (the pinned `core/rust-toolchain.toml` is not edited). The self-test prints `lime core <version>` and `Encryption self-test: passed`, and exits 0 (1 on failure).

Linking to your phone: waiting for DESIGN-M1; until then the Mac app signs in only as the Mac staging test accounts.
