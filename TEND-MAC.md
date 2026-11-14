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
