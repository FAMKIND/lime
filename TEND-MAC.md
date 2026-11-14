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
