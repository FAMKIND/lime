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

`mac/build-core.sh` builds LimeCore into `mac/Frameworks/LimeCoreFFI.xcframework` (slices `macos-arm64` and `ios-arm64-maccatalyst`) and the bindings into `mac/Lime/Generated/lime_core.swift`. `mac/tools/selftest/build.sh` builds and runs the self-test on this Mac: prints `lime core 0.1.0` and `Encryption self-test: passed`, exit 0. `cargo test` in `core/`: 564 passed, 0 failed. Nothing generated is tracked; the lane diff (`ios/ android/ site/ supabase/ server/ core/`) vs `main` is empty. `docs/mac.md` has "Building the core".

Survey: Xcode 27.0 on macOS 26.6.2; 1.99.0 installs `aarch64-apple-darwin` and `aarch64-apple-ios-macabi` with a prebuilt standard library (`rustup target add` in `core/`), so no nightly or `build-std`: DECISION M-A's cost is unchanged.

Deviation: UniFFI's bindgen ran Xcode's `swift-format` on the generated file and it hung for an hour, so the script passes `--no-format`. The Swift is unformatted but compiles and the self-test passes. (iOS's `build-ios.sh` doesn't pass it; it may be slow there too.)

For plot: the first full clean build (`rm -rf core/target`) was killed during the bindings step, so there is no clean total time; both release `.a` files had finished by then, after roughly 10 minutes of compiling on a machine also running other builds. The re-run (bindings + xcframework) took 2.3 s. `.a` sizes: macOS 94,954,728 bytes, Catalyst 94,719,952 bytes (release, with `strip = true` that doesn't apply to `.a`). Warnings: only the Rust dead-code ones already in core (`captions::cue_at`, `verify_published_comment`); none from SQLCipher or the C build on either Mac target. The selftest links `Security`, `SystemConfiguration` and `CoreFoundation`.
