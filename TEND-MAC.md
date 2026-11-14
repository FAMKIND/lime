# TEND-MAC

The execution record for the Mac lane of lime. Written by tend-Mac, one `## LIME-6xx` section per brief, each ending "For plot:". Briefs are read from `~/Sites/lime/PLOT-MAC.md` (the main tree's copy, never one inside this worktree). This worktree is `~/Sites/lime-mac`, branch `mac`.

tend-Mac's lane (from `PLOT-MAC.md` `## MAC LANE RULES`):
- **May touch:** `mac/`, `docs/mac.md`, `docs/design/mac/` (screenshots), `TEND-MAC.md`, and NEW files under `core/` (a brief will say so).
- **Never:** `ios/`, `android/`, `site/`, `public/`, `supabase/`, `server/`, existing `core/` files (incl. `core/build-ios.sh`, `core/rust-toolchain.toml`, `Cargo.toml`), the root `.gitignore` (use `mac/.gitignore`), `PLOT*.md`, `TEND.md`, `TEND-ANDROID.md`.
- **Never merge into, rebase onto or push `main`**; push `mac` only. Syncs are plot-written `LIME-SYNC-M<n>` briefs.
- **Staging:** only the three Mac test accounts (`mac-a/b/c@example.invalid`); never the user's real account or Android's.

## Mac debt

Logic written in `mac/` that should live in core or shared Swift:

(none yet)

## Asks for plot-iOS

(none yet)

## Stand-ins

Mac files that stand in for an `ios/` file Catalyst can't compile, each paired with an ask:

(none yet)

## LIME-600

Opened the Mac lane. Created the worktree `~/Sites/lime-mac` on new branch `mac` from `main` (`67ae440a`), copied the gitignored `supabase/.staging.public.env` into it, and added `TEND-MAC.md` and `docs/mac.md`. Survey first: no `mac` branch locally or on `origin`, no `~/Sites/lime-mac`. No file in `~/Sites/lime` changed; nothing committed on `main`.

For plot: main's head at branch time was `67ae440a`; worktree path `~/Sites/lime-mac`; nothing unexpected.

## LIME-601

`mac/build-core.sh` builds LimeCore into `mac/Frameworks/LimeCoreFFI.xcframework` (slices `macos-arm64` and `ios-arm64-maccatalyst`) and the bindings into `mac/Lime/Generated/lime_core.swift`. `mac/tools/selftest/build.sh` builds and runs the self-test on this Mac: prints `lime core 0.1.0` and `Encryption self-test: passed`, exit 0. `cargo test` in `core/`: 564 passed, 0 failed. Nothing generated is tracked; the lane diff vs the branch point (`git merge-base main mac`) is empty (`main` itself has since moved by a commit that touches `ios/`, so a plain diff against its tip is not empty; that is main's change, not this branch's). `docs/mac.md` has "Building the core".

Survey: Xcode 27.0 on macOS 26.6.2; 1.99.0 installs `aarch64-apple-darwin` and `aarch64-apple-ios-macabi` with a prebuilt standard library (`rustup target add` in `core/`), so no nightly or `build-std`: DECISION M-A's cost is unchanged.

Deviation: UniFFI's bindgen ran Xcode's `swift-format` on the generated file and it hung for an hour, so the script passes `--no-format`. The Swift is unformatted but compiles and the self-test passes. (iOS's `build-ios.sh` doesn't pass it; it may be slow there too.)

For plot: the first full clean build (`rm -rf core/target`) was killed during the bindings step, so there is no clean total time; both release `.a` files had finished by then, after roughly 10 minutes of compiling on a machine also running other builds. The re-run (bindings + xcframework) took 2.3 s. `.a` sizes: macOS 94,954,728 bytes, Catalyst 94,719,952 bytes (release, with `strip = true` that doesn't apply to `.a`). Warnings: only the Rust dead-code ones already in core (`captions::cue_at`, `verify_published_comment`); none from SQLCipher or the C build on either Mac target. The selftest links `Security`, `SystemConfiguration` and `CoreFoundation`.

## LIME-602

Added `mac/tools/staging-test-accounts.sh` (Android's logic with `mac-a/b/c@example.invalid`, "Ada/Ben/Cleo Mac", `ada_mac`/`ben_mac`/`cleo_mac`, `~/.lime/mac-test-accounts.json` chmod 600, `--delete`, no `--push`), `mac/tools/partner/{main.swift,build.sh}` (a Swift partner built with `swiftc` against the macOS slice; `--as b|c`, commands `send --to <username>`, `echo`, `inbox [--from]`, `status`, `reset`), and a "Test accounts and the partner" section in `docs/mac.md`. Staging: only those three accounts and their profile rows. The Kotlin partner has `photo`; I did not port it (the brief says only if Kotlin has it, and it does, but no 602 check needs it; say if you want it, plus voice/file/jam).

Verified: the accounts script ran three times with identical user ids (so reuse, not recreate) and exit 0; its output has no `eyJ`. Round trip: `partner --as b echo` in the background, `partner --as c send --to ben_mac "hello from Cleo"`, then `partner --as c inbox --from ben_mac` showed `Ben Mac: Ben here: got "hello from Cleo"` after 9 s (send to reply seen). No second registration: `status` prints a device-id prefix and it was the same on every run (`registerDevice` is idempotent in core and returns the stored device). The transport is iOS's `URLSessionTransport.swift` compiled by reference; it compiled alone (its `NetworkLog` calls are `#if DEBUG` only), so no stand-in and no Mac-debt line.

For plot: first-message request: Cleo's send creates a chat request on Ben's side; Ben's `echo` (and `inbox`) accepts every pending request, then answers. Accounts: the first run's created/reused split isn't known (I only compared ids across runs 2 and 3; ids `6d58de16…`, `f6e49a6e…`, `dbde50c6…`). Note the partner's `echo` serves every non-group chat, not only one, and skips messages that look like another echo. The partner and `inbox` print message text (test accounts only, as the Kotlin partner does).

## LIME-603 (Phase 1 only; stopped for the user's decision)

Built so far (committed as WIP): `mac/project.yml` (XcodeGen: Catalyst, "Optimize for Mac", macOS 14, arm64, sandbox + network client entitlements, the two packages, `../ios/Lime` by reference), `mac/generate.sh`, `mac/Config/{Base.xcconfig,LimeMac.entitlements}`, a placeholder `mac/Lime/MacApp.swift` and `mac/LimeMacUITests/Placeholder.swift`; `mac/Local.xcconfig` (copy of `ios/Local.xcconfig`, gitignored). No app, no UI yet.

**Phase 1 step 1, the Catalyst compile of `ios/`:** `stasel/WebRTC` 152.0.0 and LiveKit 2.17.0 both resolve and build for Mac Catalyst. The whole of `ios/Lime` compiles except **two API uses** (found one file at a time: the compiler stops a batch at the first failing file, so I patched each in a scratch copy under `mac/Lime/Generated/` and rebuilt until it passed; Debug build then SUCCEEDED):
1. **AVFoundation, `AVCaptureSession.isMultitaskingCameraAccessSupported` / `isMultitaskingCameraAccessEnabled`**, `ios/Lime/Core/Calls/GroupCallManager.swift:921` (one diagnostic log line in `logCameraSupport()`). Patch tried: replace both with `false`.
2. **CoreText/UIKit, `UIFontDescriptor.withMatrix(_:)`**, `ios/Lime/Features/Chat/Composer/ComposerDocument.swift:85` (the fake-italic slant when a font has no italic). Patch tried: skip the slant (`return slanted`), so on the Mac that fallback would not slant.
No CallKit, PushKit, camera-picker, MessageUI or background-mode errors at all. Warnings in `mac/` sources: 0 (one in my scratch copy, unused variable); LiveKitWebRTC emits one duplicate-category warning (`RTCDevice` on `UIDevice`).

**Why I stopped:** both files are NOT "adapters to an Apple service" (the brief's stand-in rule): `GroupCallManager` is the group-call state machine (1,024 lines, a view model many views use) and `ComposerDocument` is the chat composer's text model. The brief says anything else is not stood in: stop and report. A hand-written stub of either would be large and would drift; the honest fix is a guard in `ios/` (`#if !targetEnvironment(macCatalyst)`, two lines), which is a plot-iOS ask. Options for the user: (a) **recommended**: `mac/generate.sh` writes a patched copy of each of the two files into `mac/Lime/Generated/` (gitignored; a `sed` of exactly those two expressions; the generator fails loudly if the line is no longer there), the originals are excluded from the Mac target, and two asks go to plot-iOS ("add the Catalyst guards; then the Mac drops the patch step"); no drift, nothing hand-copied; (b) wait for plot-iOS to add the guards and sync `main` first (blocks 603 until a `LIME-SYNC-M<n>`); (c) a hand-made stand-in of each file (not recommended).

**Not yet done (Phase 1 steps 3 to 5 and all of Phase 2):** the object wiring list, reuse of the Messages list and `ChatView`, Keychain under the sandbox, the app, menu bar, test sign-in, UI test, screenshots.

For plot: the Catalyst cost is far below DECISION M-A's worst case: 2 API uses in 2 files, 0 true stand-ins so far.
