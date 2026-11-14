# lime for Mac

The Mac app: lime's chat list and conversation side by side, with a Mac menu bar.

Status: LIME-603: one window with the Messages list on the left and the selected chat on the right, a Mac menu bar, signed in as Ada Mac (Debug test account only).

Build entry points: `mac/build-core.sh` (LimeCore), `mac/generate.sh` (project), `mac/run.sh` (build + sign in as Ada Mac + open), `mac/test.sh` (UI test).

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

## The app (LIME-603)

Mac Catalyst, "Optimize Interface for Mac" (macOS 14+, Apple silicon, App Sandbox on), compiling `ios/Lime` by reference plus `mac/Lime/` (Mac-only Swift).

```
mac/run.sh     # build Debug, hand Ada Mac's tokens to the app, open it  (then, in a second tab: mac/tools/partner/build/partner --as b echo)
mac/test.sh    # the UI test (LimeMacUITests) against staging, as Ada Mac, with the partner answering as Ben Mac
```

- **No real sign-in.** Signed out, the window says "lime on your Mac links to your phone. Coming soon." A Debug build also has "Use a test account"; `mac/run.sh` hands Ada Mac's tokens (no password) over in a file in the app's container, and the app signs in through the same session code iOS uses and deletes the file. Any account that is not one of the three Mac test accounts is refused. Each `run.sh` makes fresh sessions for the test accounts, so start the partner after it.
- **Idiom.** `Config/Info.plist` sets `UIUserInterfaceIdiomMac` and `UIGlobalUserInterfaceIdiomMac`; `TARGETED_DEVICE_FAMILY "2,6"` alone gave the scaled iPad idiom (the window drew at 77%).
- **Signing.** Automatic, with the team from the gitignored `mac/Local.xcconfig` (a copy of `ios/Local.xcconfig`). The Keychain under the sandbox needs `keychain-access-groups` (without it: error -34018).
- **Generate-time patches.** `mac/generate.sh` writes patched copies of two `ios/` files (see TEND-MAC.md "Stand-ins") into the gitignored `mac/Lime/Generated/`.
- **Menu bar.** lime (About, Hide, Hide Others, Show All, Quit; no Settings), File (Close), Edit (system), View (Hide Sidebar ⌃⌘S, Enter Full Screen), Chat (Next Chat ⌘], Previous Chat ⌘[), Window (system), Help (system).
- **Shown:** the Messages list (pinned and unread numbers, as on the phone), a Requests entry when there are requests, the chat beside it, threads, group details and profiles pushed in the chat pane. **Hidden for now:** new message, search, filters, swipe actions, Calls, Jam, bands, Settings and Lock lime, calls UI, the mesh.
- Screenshots: `docs/design/mac/first-window-light.png`, `first-window-dark.png`.
