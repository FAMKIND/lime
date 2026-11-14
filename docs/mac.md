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

## Test accounts and the partner

Three throwaway staging accounts: `mac-a/b/c@example.invalid` = Ada Mac (`ada_mac`), Ben Mac (`ben_mac`), Cleo Mac (`cleo_mac`). Never the real account, never Android's.

```
mac/tools/staging-test-accounts.sh            # create/reuse all three; fresh sessions in ~/.lime/mac-test-accounts.json (chmod 600)
mac/tools/staging-test-accounts.sh --delete   # delete them and the file
mac/tools/partner/build.sh                    # build the partner (needs mac/build-core.sh first)

P=mac/tools/partner/build/partner
$P --as c send --to ben_mac "hello from Cleo"   # --as b|c
$P --as b echo                                  # until stopped: accepts requests, replies: Ben here: got "<first 40 chars>"
$P --as c inbox --from ben_mac                  # sync once, accept requests, print what arrived
$P --as b status                                # short device-id prefix: the same each run = no new registration
$P --as b reset                                 # forget the store (when Ada's app signs in on a new Mac)
```

The partner's encrypted store and its key live in `~/.lime/mac-partner/<a|b|c>/` (outside the repo, key chmod 600; test tooling only). The first message to someone is a chat request on their side: `echo` and `inbox` accept it. Mind the staging limit of 10 device registrations per account per hour.
