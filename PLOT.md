# PLOT.md

Planning state for Lime. Written only by `plot` sessions. `TEND.md` is the execution record.

## ▶ START HERE: session-end note (plot, 2026-10-10, context handoff)

**Read this first. It supersedes the 2026-10-05 note below.** Details live in the sections below; search for the IDs.

### Where things stand
- **The product direction:** native iOS app (SwiftUI) + a shared Rust core (`core/`, vodozemac E2EE, SQLCipher) + a Supabase blind-mailbox backend (`supabase/`). **The web app (`public/`) is frozen.**
- **The docs:** `docs/architecture.md`, `docs/api-v2.md`, `docs/spike-ble.md`, `docs/release-checklist.md`.
- **The org:** a teacher-co-op 501(c)(3) foundation owning Lime Messenger LLC; **always free**; the audience is teachers; **US first**.
- **origin/main = `096123b`** (LIME-102b-fix). The landed chain this session, all pushed:
  - 87-fix2 … fix5, 88–98d;
  - 103/103b/103c (BLE spikes done: a locked receiver works for hours; both asleep = bursty);
  - 104, 104-fix, 105, 106, 106-fix, 106-fix2, 107, 107-qa, 107-qa2, 108, 102b, 102b-fix.
- **Two real iPhones** (Shem 13 mini, Jean 12 mini) + an iPad (a test account) run Debug builds via free provisioning (7-day expiry). **Staging Supabase = `lime-staging`.**
- **Domains:**
  - `limechat.org` (NameSilo; **deSEC DNS + DNSSEC**; Resend on `send.limechat.org` for sign-in codes; **Migadu mail active**: the shem@ mailbox exists; **Jean's mailbox + aliases are pending the user's card**);
  - famkind.com is on KnownHost (its NS-record fix was suggested to the user).

### LIME-115 → `tend` (lime-aa) (**running NOW, before 111**: the user runs it while away; then the Hetzner server for 111): group row actions, owner-only Delete group, default group names
**The user (2026-10-10).**

**Phase 0:** `git add PLOT.md` only. Time-box ~60 min.

**Phase 2:**
1. **Swipe left on a GROUP row: Mute · Leave · Delete** (right swipe unchanged: Unread · Pin).
   - **Leave:** confirms "Leave <group>?"; sends `group.leave`; the group stays in the list as "You left", read-only, deletable locally.
   - **Delete:**
     - **owner only:** "Delete <group> for everyone?". A new signed, encrypted **`group.delete`** op (owner authority enforced by every client) ends the group for all: members see "<Owner> deleted this group" and the group becomes read-only, and each member can remove it locally. Rotate/retire the Megolm session.
     - **Non-owners** see **"Clear messages"** instead of Delete: removes the messages from this phone **and stays in the group** (the gap the user found).
   - **DM rows:** Mute · Delete (unchanged: local clear; a new message brings it back empty).
2. **Group details:** add a red **"Delete group"** (owner only, same op) below Leave; non-owners see "Clear messages".
3. **The default group name:**
   - New Group pre-fills the name from the **selected members' first names**: "Jean & Lee", "Jean, Lee & Sam", 4+ = "Jean, Lee, Sam +2";
   - editable, max 50; **Create is enabled immediately** (no required naming step);
   - it updates as members are added/removed **until the user edits it**;
   - rename is still available later.

4. **Unread count badges are round** (the user, 2026-10-10): a **perfect circle** for 1–9 (width = height); for 10+ a capsule that keeps fully round ends; for 99+ show "99+". The same on Messages rows and the dock badge. Centred digits.

**Docs:** `api-v2.md` (`group.delete`; authority = owner only).

**Verification:**
- core (only the owner's `group.delete` is honoured; a forged one is ignored; members end up read-only);
- the integration e2e (3 accounts);
- UI tests (swipe actions per row type; owner vs non-owner; default name + Create without editing);
- tiered; 0 warnings.

**Gate:**
- swipe a group: Mute/Leave/Delete;
- as owner, Delete group → Jean sees "deleted this group";
- as non-owner, Clear messages keeps you in the group;
- New Group: pick 2 people → the name pre-filled → Create right away.

**Record:** `## LIME-115`. Commit: `feat: group row actions (mute/leave/delete), owner-only delete group, clear messages, default group names`, trailer `Brief: LIME-115`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

### The authoritative order (the user, 2026-10-09/10)
0. **LIME-115 landed as `7f17df5`** (group swipe Mute/Leave/Delete-or-Clear, owner-only `group.delete`, Leave now keeps a read-only "You left" row, Clear messages, default first-name group names, round badges). Awaiting the user's gate. Then:
1. **LIME-111: 1:1 calls** (P2P WebRTC + **self-hosted coturn on Hetzner CPX11, Ashburn**).
   - **The Hetzner server is CREATED (2026-10-10):** `lime-turn-1`, CPX11, Ashburn VA, Ubuntu 26.04, **IPv4 178.156.199.1**, the user's ed25519 key (shem@MBP.local), project `lime`; the account is under FAMKIND LLC, login accounts@limechat.org; **$21.09/mo excl. VAT** (US plans cost more than EU).
     - **DNS:** the user adds `turn.limechat.org` A → 178.156.199.1 in deSEC (guided).
     - Tend then SSHes in as root (key auth) for `infra/turn/setup.sh`.
   - **(History) The user is mid-way through buying the Hetzner server** (settings + SSH key steps given). Next: give tend the IPv4; tend runs `infra/turn/setup.sh`; the user adds `turn.limechat.org` A in deSEC; the TURN secret is set via Terminal `read -s`.
   - Prompt: "implement LIME-111 (re-read from PLOT.md), commit, push, and stop for my check. In Phase 0 commit PLOT.md only (git add PLOT.md). Stop at the TURN server step and give me the Hetzner setup steps. Keep to the ~60 min soft cap. No /loop wakeups."
2. **LIME-115:** group row actions, owner-only Delete group, Clear messages, default group names (drafted, above).
3. **LIME-112:** group calls (LiveKit, self-hosted; **not yet drafted**; cost principles under LIME-111).
3. **LIME-113:** account deletion + Report (drafted).
4. **Offline messaging (mesh v1) + emergency mode:** **plot's design pass is needed first** (inputs: DESIGN-01 §4, DESIGN-06 bitchat notes, `docs/spike-ble.md` §5b; rules: Nearby mode, emergency turns it on, flush on wake, no timers in a suspended app, an honest promise, 48 h carry).
5. **LIME-110:** Jam MVP (drafted; J1 = A, J2 = B, J3 required, J4 ok).
6. **LIME-109:** Spanish (drafted; needs a native review).
7. **Push/APNs** (needs the paid Apple account, which **the user enrols in November**).
8. **limechat.org site** (marketing, waitlist, invite pages, privacy/terms/support) + **the compliance pack (LIME-114b: 18+ gate, data export, policies, security.txt)**.
9. **TestFlight.**

### Open with the user
- Is the avatar→status sheet→Settings change OK? (LIME-108)
- Gate checks pending on recent briefs (102b-fix: chime without touching Settings on iPhone + iPad).
- Apple enrolment: individual vs FAMKIND (D-U-N-S); use shem@limechat.org.
- **Migadu DONE (2026-10-10):**
  - the Micro plan paid (renews 2027-10-10);
  - mailboxes shem@ (active), jean@ (pending invite), admin@ (default);
  - aliases: postmaster→admin; accounts/dmarc/privacy/security/abuse→shem; hello/support/safety→jean+shem.
  - postmaster→shem (done; the forwarding page is external-only, so it isn't used).
  - **Remaining:** connect Nextcloud Mail (IMAP `imap.migadu.com:993`, SMTP `smtp.migadu.com:465`); move service accounts to accounts@; use shem@limechat.org for Apple enrolment.
- DPAs to sign; a lawyer review (licences, trademark "LimeChat", policies).

### BRAND RULE (the user, 2026-10-10): **"lime" is always lowercase**, like the logo
- It applies everywhere in UI, notifications, permission strings, the App Store display name, the website, emails, docs prose, and project names (Hetzner project `lime`).
- **Even at the start of a sentence** ("lime uses the camera…").
- **Exceptions:**
  - **legal entity names** keep their registered form (e.g. FAMKIND LLC; the future foundation/LLC as filed);
  - **code identifiers** don't change (`Lime.xcodeproj`, `LimeCore`, the bundle id stay).
- **Implementation:** fold a full user-facing string sweep "Lime" → "lime" into **LIME-109** (which already moves every string into String Catalogs). Until then, new briefs use lowercase.
- The App Store name, e.g. "lime: teacher messaging" (lowercase is allowed).

### Standing rules (also in the sections below)
- Tend Phase 0: `git add PLOT.md` only.
- Tiered iOS tests (full on the 13 mini, changed tests on SE/18 Pro); **~15 min per failing test, ~60 min per brief**.
- Never suggest sign-out to refresh (it wipes keys).
- Secrets only via the Terminal app (`read -s`), never in chats.
- Green = only the primary action; no dividers/arrows on lists (Settings keeps its chevrons).
- The QA intake: small items go into the next QA brief; features get their own brief.
- Tend is the session **lime-aa**; relay prompts there.

### Gather
**Tend: commit this file as written; do not edit it** (it happens as Phase 0 of the next brief).

---

## (Previous) session-end note (plot, 2026-10-05, written at "end")

**The next plot session (`rtb`) reads this section first.** Everything below it is history and reference. Where they conflict, this note wins.

### Where things stand (2026-10-05)
- **`origin/main` = `bfb70de`** (`PLOT.md` committed by tend at the start of LIME-86). **Tend was mid-LIME-86** at session end (uncommitted `lime.css`, `index.html`, `app.js`, `TEND.md`, `tests/suites/mobile.mjs`, plus `tests/*.tmp.mjs` scratch files tend should delete). **Check `git log` and `TEND.md` first.**
- **Done this session (all pushed):**
  - the sync and server stack: LIME-69 (live tabs), 71 (`docs/api.md` contract), 72 (the `tests/` harness, puppeteer-core), 73 (`server/dev-server.mjs`), 74 (`ApiAdapter`), 74-redact (history rewrite), 75 (@famkind.com demo emails; the test accounts merged into the seed's Shem and Jean), 76 (ids without `crypto.randomUUID` on the insecure LAN);
  - **mobile v2:** LIME-78/79 + fix … fix6, 82 (Messages and chat header v2, glass toasts), 83 (composer and Aa), 84 (Settings/Profile, **usernames**, **Linked Devices**, Donate link);
  - earlier: toasts 67/68, the auth redesign 48 (+ fixes), New message 29, Share 27, dew icons 66, lime avatars and status icons 57-*, primary buttons 58/61.
- **Running it:** `cd ~/Sites/lime && node server/dev-server.mjs`. The phone uses the printed "On your network" URL (e.g. `http://192.168.0.127:8000/public/auth.html`). The test accounts are `shem@famkind.com` and `jean@famkind.com` (password in the gitignored `seed-data/test-accounts.local.json`); seed teachers use the demo password in `public/js/demo-config.local.js`. To reset: stop, `rm -rf data`, start.
- **The design source of truth:** the user's Penpot exports in **`docs/design/mobile/` (01–06)**. **Desktop frames go in `docs/design/desktop/`.** The user shared one desktop frame in chat (two panes; described under "Open decision: desktop v2"), but it **isn't saved there yet**.

### Update after the end note (2026-10-05): LIME-86 landed as `c9712c9` and was pushed
- The full matrix passed (mobile 551); desktop pixel-identical. **No iOS test:** the header-with-keyboard behaviour is the one part tend couldn't test.
- **Decisions for the user:**
  - (a) **dark mode: the own bubble (`--lime-primary-bg`) is barely distinct from the dark canvas (ΔE 2.1).** Options: a darker-green dark variant, or a hairline border. Ask;
  - (b) **Lemon:** ΔE 4.5 against the canvas (borderline);
  - (c) desktop has no own-bubble styling yet (all neutral), so it goes in desktop v2.
- The 360px header was tightened; header tool buttons are now 40px circles.
- **The next action:** the user's iPhone review of 86 (plus answering (a)), then LIME-85.

### Update: LIME-86-fix landed as `8ba1989` (local; push pending the user's word; `7557554` = the PLOT.md commit, pushed)
- The full matrix is at 0 failures (mobile 621); desktop has 0 pixels changed.
- **Tend deviated on item 3 without asking:**
  - light mode: white-ish others' bubbles plus a **hairline edge** (ΔE ≥ 6 is impossible on near-white canvases; Warm ≈ 2, Pure white = the canvas);
  - dark mode: ΔE ≥ 6 is kept.

  Plot thinks it is reasonable; **the user judges it at the gate.**
- Untested on iOS: the keyboard, the callout clearance, real dictation (over the LAN expect the fallback toast) and Safari's fixed-menu correction.
- **Lesson:** the handoff prompt said "commit and stop", which overrode the brief's push. Future prompts say "commit, push, and stop".

### DIRECTION SET (user, 2026-10-05): all effort goes to the native iOS app (infrastructure + app)
- **The web app is frozen** (fix real bugs only). **LIME-85, 80 and 81 are paused indefinitely**; their ideas carry into the iOS app. The dark "+"/own-bubble question is dropped for the web; the iOS theme decides it.
- **`8ba1989` is pushed** (verified: `origin/main` = `8ba1989`). **The tend session is `lime-aa`**; `lime-04` is not tend. Relay to `lime-aa` only from now on.
- **Machine survey (2026-10-05):**
  - macOS 26.6.2;
  - **CORRECTION: Xcode is NOT installed.** `/Applications` holds `Xcode.appdownload`, an unfinished App Store download. Plot misread it as `Xcode.app` at first.
  - `xcode-select -p` = CommandLineTools;
  - Homebrew is present;
  - **Rust is not installed**.
- **Xcode 27.0 (27A266a) installed 2026-10-05 but crashes on launch.**
  - The cause, from running the binary: `dlopen libIDEApplicationLoader: Symbol not found _XPCTypeBool`. The system-wide `/Library/Developer/PrivateFrameworks/CoreDevice.framework` is **stale** (397.28, Dec 2024), left over from an old Xcode, and Xcode 27's first-launch packages haven't been installed.
  - **The fix given to the user:** `sudo xcode-select -s …` then `sudo xcodebuild -runFirstLaunch`; the fallback is to install the 4 `.pkg`s in `Xcode.app/Contents/Resources/Packages/` by hand.
  - The "Command Line Tools for Xcode 27.0" update is also pending.
  - **Resolved:** Xcode 27.0 now opens (user screenshot, 2026-10-05). The iOS 27.0 Simulator (24A434, 8 GB) is downloading. No iOS 17 runtime is installed, so LIME-87 builds against iOS 17 but tests on iOS 27 (the brief allows this; tend reports it).
- **D1–D4 = all A (user, 2026-10-05):** iOS 17+, a shared Rust core, one repo (`ios/` at the root), Supabase. **LIME-87 is drafted** and waits on the user finishing the Xcode install.
- **The iOS foundation decision surface was put to the user** (see the reply of 2026-10-05). Decisions:
  - **D1** the minimum iOS version;
  - **D2** the shared Rust core vs Swift-only;
  - **D3** the repo layout;
  - **D4** the backend (re-confirm Supabase now that E2EE is in).

  After the answers: the first brief is **LIME-87, the iOS skeleton** (Xcode project, SwiftUI, builds and runs in the Simulator, CI-free, no networking).

### Update: LIME-87 landed as `dbe7f2e` (pushed; `dc26286` = the PLOT.md commit)
- 7 tests pass (6 unit, 1 UI) on the iPhone 18 Pro simulator, iOS 27.0. The runtimes installed are 18.3 and 27.0; there is no iOS 17.
- **No Simulator.app on the Mac:** tend ran the app headless via simctl. `mdfind` finds no `com.apple.iphonesimulator`; it was probably not installed with the Xcode 27 components. The user is told to open `ios/Lime.xcodeproj` in Xcode and press Run.
- **Plot's review of tend's screenshots, for a likely LIME-87-fix after the user looks:**
  1. **Dark own bubble / "+" / unread badge** (#0D2016 on #131B17) are nearly invisible. This is the same dark-green question as on the web. Lean: a native dark primary that clearly reads green, with text ≥ 4.5:1.
  2. **The chat header has no scroll fade:** the sender name "Grace…" shows cut under the header pills.
  3. **The edge-swipe back is disabled** (the nav bar is hidden). Restore it; it's core iOS behaviour.
  4. A sample message repeats oddly ("Best breakfast in town breakfast in town").
- The bundle id `com.famkind.lime` is awaiting the user's confirmation.
- **Running on the user's own iPhone (asked 2026-10-05):**
  - TestFlight needs the paid account (next month). For now: **free provisioning** (a personal Apple ID team in Xcode, USB, Developer Mode on the phone; the build expires after 7 days).
  - **Follow-up for a future brief:** persist signing in a **gitignored `ios/Local.xcconfig`** (`DEVELOPMENT_TEAM`), included by `project.yml`, so `./generate.sh` doesn't wipe the user's team choice. The team id is personal, so keep it out of git.
- **The user reviewed LIME-87: "looks great".** They approved the visible dark green; **LIME-87-fix is drafted** (items 1–4).
- **Bundle id:** there is no Lime domain yet; everything is under famkind.com.
  - Plot's advice: **keep `com.famkind.lime`**. Bundle ids needn't match a domain you own later. Signal's iOS app still uses `org.whispersystems.signal`, from its old company. The app can later be *transferred* to the foundation's Apple account with the bundle id unchanged.
  - **The bigger choice is the Apple account type:** individual (the seller shows the user's personal name) vs organisation (needs a legal entity + a D-U-N-S number, free but it can take days to weeks).
  - The user is to decide before enrolling next month.

**Incident (2026-10-06): famkind.com is down. Not caused by Lime work.**
- Plot diagnosed it read-only:
  - The domain's DNS is **self-hosted on the web server** (`ns1/ns2.famkind.com` → `108.160.153.182/.183`, PrivateSystems Networks; registrar NameSilo).
  - The server accepts TCP on 80/443 but **never answers HTTP**, and **its DNS times out intermittently**, so public resolvers return SERVFAIL.
  - The MX is Google Workspace (unchanged).
  - **No `send.famkind.com` records exist**, so no Resend DNS change has been made yet.
  - No Lime brief has ever touched famkind.com.
- The user is working with the host.
- **Re-verified 2026-10-06:** HTTPS 200 and resolvers NOERROR.
- **A latent fault was found:** the zone's own NS records say `ns1/ns2.risefam.com`, which **doesn't exist (NXDOMAIN)**, while the registry delegates to `ns1/ns2.famkind.com`. That NS mismatch can cause intermittent lookup failures. The user is to ask the host to correct the zone NS records (or to move DNS to NameSilo/Cloudflare).
- **Plot's recommendation after the fix:** move DNS to NameSilo's or Cloudflare's nameservers, so a web-server outage can't break email or the later Resend records. **Hold the Resend DNS step until the site and DNS are stable.**

**Open thread: a Lime domain (raised 2026-10-06).**
- The user asked whether to send Lime's emails from a Lime domain rather than famkind.com.
- **Plot's advice:** use `send.famkind.com` for staging now (a subdomain, so the existing famkind.com mail is untouched). **Pick and buy a Lime domain before TestFlight.** It will also be needed for the privacy policy/terms URLs, universal links/deep links, the App Store support URL and the eventual foundation.
- Switching the email sender later is a dashboard change (a new Resend domain + the SMTP sender), with no code change.
- **Update (user, 2026-10-06):** famkind.com's site and DNS are on **KnownHost** (moving DNS is too big a job). The user may **buy a Lime domain now**.
  - **Correction:** the user has **never used NameSilo directly**. famkind.com was bought through **KnownHost**, which resells registrations through NameSilo (that's why WHOIS shows NameSilo).
  - **Plot's advice:** register it where the **DNS is not on the web server** (any reputable registrar: Porkbun, Cloudflare Registrar, NameSilo; open-source nonprofit DNS: deSEC), and host the policy pages on free static hosting (Cloudflare Pages / GitHub Pages).
  - **If it's bought now, skip `send.famkind.com` and set Resend up directly on the Lime domain** (once, not twice).
  - The user should still ask KnownHost to fix the `risefam` NS records.
- **The name check (USPTO, the user, 2026-10-06):**
  - **"LimeChat": no marks, live or dead.**
  - **"Lime" in classes 9/38/42 is crowded with live marks, e.g. NEUTRON HOLDINGS (the Lime scooters) "LIME VISION" (class 42, software) and LIME CELLULAR LLC (class 38, telecom).** The user's search for "chat" covered page 1 of 7 only.
  - **Plot's advice:** prefer **"LimeChat" as the distinctive brand/App Store name** over bare "Lime", **register limechat.org**, and **add a trademark review (Neutron Holdings' LIME portfolio; Lime Cellular) to `docs/release-checklist.md`** for the lawyer before launch.
- **DONE (user, 2026-10-06): `limechat.org` registered at NameSilo**, for 1 year with WHOIS privacy.
  - Registrant email verified; auto-renew ON.
  - **Nameservers = deSEC (`ns1.desec.io`, `ns2.desec.org`).**
  - **The DS record was added at NameSilo** (key tag 14658, alg 13, digest type 2; it matches deSEC's CDS). Resolvers answered NOERROR right after, without the AD flag yet (propagating); check with the DNSSEC Analyzer.
  - **`limechat.com`** has been owned by a third party since 2002 and is listed for sale on Atom (a brand marketplace). Not needed.
  - **Resend DNS added in deSEC (2026-10-06), verified by plot via dig:** the DKIM TXT at `resend._domainkey.send` (ends `…QIDAQAB`), the CNAMEs `rsend.send` / `send.send` → `*.forge.rmta.net.`, and `_dmarc` "v=DMARC1; p=none;". **Public resolvers already see them, so the delegation to deSEC is live.**
  - **The Resend domain `send.limechat.org` is VERIFIED** (2026-10-06 15:53; DKIM + both CNAMEs). Receiving is off.
  - **The user reports (2026-10-06):** the Resend API key was created; **Supabase custom SMTP is on** (`no-reply@send.limechat.org`, smtp.resend.com:465, 30s minimum interval); the Confirm signup + Magic Link/OTP templates are the code template; password min 10. **Unblocks the LIME-94 gate and tend's staging e2e.**
  - **(History) Next:** an API key (Sending access) → the Supabase SMTP settings (sender `no-reply@send.limechat.org`), the templates, password min 10, email interval ≤ 30s → `./generate.sh` → the LIME-94 gate.
  - Plot gave the deSEC (DNS + DNSSEC) and Resend-on-`send.limechat.org` steps; **this supersedes `send.famkind.com`**.
  - The Supabase SMTP sender becomes `no-reply@send.limechat.org`.
  - **Still open:** whether "LimeChat" is the official brand/App Store name (plot's lean).
- **(Superseded) DECIDED (user, 2026-10-06):** `send.famkind.com` for now; **switch to a Lime domain later, before TestFlight**. Add "choose and register a Lime domain; move the email sender" to `docs/release-checklist.md` in the next brief that touches it.

**Update: LIME-103 analysis landed as `010d040`** (`docs/spike-ble.md`; `ios/analyze-ble-logs.py`; raw logs in the user's `~/Downloads/ble-logs/`). **Field test 2026-10-07/08: Shem's 13 mini + Jean's 12 mini, 8 scenarios, ~85 min.**
- **Proven:**
  - discovery in ~1 s; no pairing prompt; delivery both ways with no internet;
  - delivery to a backgrounded/locked phone **10–30 s after it left the app**, with the link held 4–8 min;
  - L2CAP is ~4–5× faster than GATT (32 KB ≈ 1.3 s);
  - it works through a wall at about −83 dBm;
  - free provisioning is enough;
  - a force-quit app is unreachable;
  - links drop ~every 20 min with ~1 s reconnects;
  - 81/81 signatures were valid.
- **Unproven:**
  - delivery to a **long-idle** backgrounded phone (iOS suspension);
  - iOS relaunching via state restoration;
  - battery with screens off.
- **Plot's decisions on tend's §8 flags:**
  1. **Mesh v1 transport = GATT to meet + L2CAP to move data** (GATT fallback), one link per pair, resumable per-envelope acks. Accepted.
  2. **No bitchat wire compatibility.** Lime's mesh only carries Lime's sealed envelopes to Lime users, so interop has no user value. "Borrow from bitchat" means *ideas* (public-domain code patterns), not its wire format. Update `architecture.md` §7 in the next docs touch.
  3. **Split `architecture.md` §7's open question into "force-quit (a hard no)" and "long-idle background (unproven)".** **The product must not promise "works with the app closed" until LIME-103b proves the long-idle case.** The user's D3 requirement ("open AND closed") stands as the goal.
  4. **UX for mesh v1:** a Bluetooth permission explainer, a visible "Nearby" status, and a gentle "swiping Lime away stops nearby delivery" note.
- **LIME-103b (the follow-up spike), proposed by tend:**
  - queued sends without taps;
  - long-idle receivers (15/30/60 min);
  - a system-terminated app;
  - scenario 8 redone;
  - a screens-off battery hour.
  - **Fix first:** the log `ms` key collision and the blank "Share all" sheet.
  - **Scheduling:** needs Jean's phone again for ~2 h; **the free builds expire ~2026-10-14** (installed 10-07).
- **The user (2026-10-08): a 2-hour test isn't realistic (3 kids).** Plot reshaped LIME-103b into an **unattended overnight "leave it on the table" test** (~5 minutes of the user's time).
- **The order agreed:**
  1. **LIME-103b build** (quick, so it's ready);
  2. **LIME-96 sealed;**
  3. **LIME-97 groups** ("complete the app experience");
  4. the user runs the overnight test the next night;
  5. then mesh v1.
- **(Superseded) Order proposed to the user:**
  - LIME-96 (sealed sends; no hardware needed) now;
  - **LIME-103b** whenever Jean is available (before mesh v1);
  - then LIME-97 groups, then mesh v1.

**Update: LIME-103 (the build stage) landed as `be3633a`** (pushed and verified).
- **The Debug-only Nearby test** (GATT + L2CAP, state restoration, signed random blobs, JSONL logs, share).
- **Free provisioning works** for the Bluetooth background modes (Info.plist keys, not entitlements).
- `ios/check-release-no-bluetooth.sh` proves Release has none of it.
- Installed on **Shem's 13 mini and Jean's 12 mini**.
- **Deviation (accepted):** a throwaway Ed25519 key, not the device key (avoids adding a general sign-anything FFI to the shipped core).
- **Waiting on the user's ~90-minute field test** (`docs/spike-ble-test-plan.md`), then Phase 4 analysis → `docs/spike-ble.md`.

**Update: LIME-102 landed as `e81933d`** (pushed and verified).
- In-app glass banner + system sound; local notifications for the short background window; previews (N2 = A; requests never show text; "Replied in a thread"); Settings → Notifications; per-chat mute; a permission explainer.
- **No chime** (Default/None; the hook is in `ios/Lime/Resources/Sounds/README.md`).
- 158 unit + 52 UI tests pass; 0 warnings.
- **Real-device-only checks are pending with the user.**
- **LIME-103 (the Bluetooth spike) is drafted.**

**ROADMAP CONFIRMED (user, 2026-10-07, "wonderful"):**
1. LIME-102 notifications (in progress; no chime yet);
2. **LIME-103: the Bluetooth spike** (two real iPhones: Shem's 13 mini + Jean's; free provisioning; open, backgrounded and locked; Wi-Fi/cellular off);
3. LIME-96 sealed sends;
4. LIME-97 groups + New Message invite/QR;
5. **mesh v1** (sealed envelopes, 7 hops / 72 h, QR offline first contact);
6. APNs push (paid account);
7. TestFlight (with mesh).

**Plot drafts LIME-103 next** (after LIME-102's report).

**Update: LIME-101b landed as `6c49400`** (pushed and verified).
- System-blue selection, a warm-neutral pressed state (3.4:1), word-level find highlights, New Message v2 (A–Z, index rail, bottom search, exact lookup, Find by Username/Email screens).
- 136 unit + 47 UI tests pass; 0 warnings.
- **Open small asks for the user:**
  - an @ badge on list rows (needs usernames stored locally; core);
  - the unread dot green vs neutral (plot's lean: keep green; it's status and small);
  - the ↗ on own-bubble links (from the 101 review, still unanswered).
- **Tend kept answering timed-out background wait loops:** harmless noise.
- **LIME-102 is blocked on the user's chime file** (`ios/Lime/Resources/Sounds/` doesn't exist yet).

**Update: LIME-101 landed as `9193306`** (pushed and verified).
- Threads: `thread_root` is encrypted in the payload, one level deep; a summary row with avatars + an accent unread dot; a thread screen with a shared composer; live.
- Link green vs underline: every pair is ≥ 4.5:1.
- 87 Rust tests pass + iOS on 3 simulators; 0 warnings.
- **Plot's review:** good. **On the own bubble (dark mode `#8ECF73`), the deep-green link is hard to tell from the black text** (hue only). Offered the ↗ glyph there; the user decides (would go into 101b).
- The thread screen uses the system nav bar rather than the glass header (minor; could align later).

**MILESTONE (2026-10-07): Shem's and Jean's real iPhones exchanged E2EE messages through staging** (the user's screenshots: "Hey love" / "it works" / "True it does work!"). **The LIME-95-fix gate has passed.**
- **A design principle the user set:** **the accent green only for the single primary action per screen;** secondary/active states use a warm neutral; the text selection is the system blue.
- **LIME-101b is drafted** (that polish + New Message v2 for 1:1). Tend is mid-LIME-101 (uncommitted work in core).

**Update: LIME-100 landed as `376b7d0`** (pushed and verified).
- The Markdown subset with **one grammar in LimeCore** (parse/write/normalise/plain); normalised on send and on receive; a 30,000-byte limit on the written form.
- The keyboard-docked capsule toolbar.
- 81 Rust / 114 iOS tests pass; fuzzed with 4,000 hostile inputs; 0 warnings.
- **Plot's review of the screenshots:** good. **One issue:** **links and underlined text look identical** (both just underlined in the text colour; e.g. "the policy" link vs "Almost" underline). **Proposed polish:** links in the accent ink with a subtle tint/underline style distinct from `__underline__`; ask the user.
- **Known limits:**
  - no indent key for nested lists;
  - Return twice doesn't leave a code block;
  - **an old literal `*` may render as italics** (old plain messages); acceptable pre-launch.
- Next: LIME-101.

**Update: LIME-99 landed as `5050a5c`** (pushed and verified).
- FTS5 inside SQLCipher (already compiled in; no size impact). Prefix, accent-insensitive.
- Messages search + in-chat find ("N of M").
- Tests prove no plaintext in the DB file and no network calls. 63 Rust / 90 iOS tests pass; 0 warnings.
- **Plot's review of the screenshots:** good. **Polish candidates (only if the user minds):**
  - the find bar floats over the messages, so text shows through behind it (busy);
  - the whole bubble is outlined rather than the matched words highlighted.
- Next: LIME-100.

**Update: LIME-98 landed as `aa1c6b7`** (pushed and verified; no project ref).
- Settings per design 05, the Signal-style ✕/✓ editors, About (emoji + 140 + presets), Account/password change, Privacy (Blocked, safety numbers), Customize, About + generated acknowledgements (105 libs; the SQLCipher notice closes that checklist item).
- 36 server / 51 Rust / 85 iOS tests pass; 0 warnings. Plot reviewed the screenshots: good.
- **Watch:** a one-off transient `register_device` failure on staging (it passed on retry). If it recurs, open a brief.
- **Deviations accepted:** Linked Devices is top-level (as in design 05); no chat details yet; the key date shows the upgrade day for older accounts.
- Next: LIME-99 (drafted).

**⚠ Incident (2026-10-07):** the user pasted the `lime-notify` Resend key into **tend's chat** (inside the `read -s` command line), so the key is in tend's transcript. Tend set it as the staging secret anyway.
- **The user is told to rotate it:** create a new Resend key, delete the old one, and set it from the **Terminal app** (not a chat). **Done (2026-10-07):** the new key was set via the Terminal ("Finished supabase secrets set"). The user confirms the old key was deleted in Resend.
- **Lesson for plot:**
  - Secret-entry commands must say **"run in the Terminal app, not tend"**, and use the simplest form: `read -s KEY`, then paste on the next line.
  - Never embed a prompt string that the user might replace with the secret.
  - Tend should refuse to act on secrets pasted into its chat and tell the user to rotate them.

**Update: LIME-95-fix landed as `3c42366`** (pushed and verified).
- **The real root cause:** **sign-out wipes the keys**, so every re-sign-in brought a new master key, the server refused it (409 `master_key_mismatch`), and the app swallowed the error.
- **The fix:** option 1 + (a)(b)(c). Also truthful errors, single-flight token refresh, and avatar colours from the user id (the old code used a per-launch random `hashValue`).
- 30 server / 49 Rust / 71 iOS tests pass; 0 warnings; staging smoke passes.
- **(a) needs a function secret** `LIME_NOTIFY_RESEND_API_KEY` (the user sets it; plot advised a **separate** Resend key `lime-notify`, entered via `read -s` so it stays out of shell history).
- **⚠ Tend's own product decisions to revisit (flagged to the user):**
  1. **one active phone per account** (registering a second revokes the first), which conflicts with Linked Devices / multi-device (DESIGN-01 §2). It's acceptable as interim policy until QR device linking; **record it in `api-v2.md` as interim**.
  2. **sign-out wipes the keys**, so every sign-out/in shows contacts "security key changed". **Candidate:** a Signal-like distinction between "sign out (keep keys on this phone, re-verify to resume)" and "delete account data from this phone". Decide with the device-linking brief.

**Update: LIME-95 landed as `d2686f3`** (pushed and verified; no project ref).
- **New message** (exact username/email), the identified-Olm DM, live receive via a **private** Realtime channel (tend found and fixed a public-channel metadata leak), Requests (Accept/Block, local), atomic HLC, `check-warnings.sh` (clean builds for a device + simulator).
- 27 server / 46 Rust / 64+13 iOS tests pass; local + staging e2e pass.
- **Tend's decisions, accepted:**
  - Accept is local until LIME-96;
  - hidden-from-search users still show their name on a request;
  - messaging a requester or a blocked person marks them accepted;
  - no unblock UI yet (**a follow-up: Settings → Blocked**);
  - no push.
- **Awaiting the user's two-device gate**, then LIME-96 (sealed sends).

**Update: LIME-94-fix landed as `8d21e18`** (pushed and verified; no project ref).
- **Root cause:** staging sent 8-digit OTPs while the app and `code-verify` took exactly 6. The user set staging to 6; the code now accepts 6–8.
- **Also fixed:** the sign-up resend for unconfirmed accounts (a migration; local `enable_confirmations` on); send failures and rate limits are surfaced; stale errors are cleared.
- **The visuals:** Next in the accent green; the welcome screen with the new `lime-logo.svg` (committed), no grey circle, "Connect All Teachers" / "A secure messenger made for teachers." Plot reviewed the screenshots: good.
- `supabase/check-staging-settings.sh` compares `otp_length` and `enable_confirmations` (read-only).
- **Remaining: the user's real-email gate on the phone** (tend can't read the inbox).
- **After it passes:** LIME-95 (New message + the first phone↔simulator chat).
- **Xcode GUI shows 2 warnings** in `OnboardingScreens` that tend's `xcodebuild` runs missed: "Cannot use generic class 'Autoconnect'" and "Cannot use enum 'Publishers' in a property declaration member of a type not marked…" (probably availability/`@MainActor`/Sendable around `Timer.publish(...).autoconnect()` for the resend countdown).
  - They're warnings only and don't block running.
  - **Fold into the next brief:** fix them (e.g. replace the `Timer` publisher with a `.task` loop or `TimelineView`). Also, the "no warnings" check must match what Xcode shows (build for a device destination too, or parse all warnings, not just the Lime target's compile).

**Update: LIME-94 landed as `461110e`** (pushed and verified; no project ref in HEAD).
- **2FA is enforced by the Edge Functions** with per-session records of both checks, since Supabase Auth can't require both.
- `identify` replaces `username-resolve`.
- `pending_inbound` is built (this fixes LIME-93's ack-everything).
- 21 server + 36 Rust + 60 iOS tests pass; a local e2e script is in place; the app is 5640 KB.
- Plot reviewed all 12 onboarding screenshots: they match DESIGN-03, with no Google/Apple.
- **The staging end-to-end test and the user's gate are BLOCKED on the user's Resend + Supabase SMTP setup.** Plot gave the user the step-by-step (use a `send.famkind.com` subdomain; the API key is entered only in the Supabase dashboard).

**Update: LIME-94w landed as `e15afb6`** (pushed and verified). The web sign-in now shows only email. Plot checked the 390px screenshot: it's tidy. **Next: LIME-94.**

**Update: LIME-93 landed as `7f411a0`** (pushed and verified; no project ref in HEAD).
- **The first E2EE exchange between two accounts passes locally and on staging**; staging was left clean.
- 30 Rust + 13 server + 36 iOS tests pass; the app size is +848 KB.
- **Tend's gap-fills, reviewed by plot:**
  - **Accepted:** canonical JSON signing; a sender cert chaining to the master key; recipients **pin the master key on first use**. This later needs a "safety number changed" UX (with device linking).
  - **Accepted for now:** one Olm ciphertext and one request per recipient device. Megolm fan-out will use the shared-ciphertext batch.
  - **⚠ Must change before sealed sends or real users:** "sync acks everything it fetches, **including unreadable items; sealed items are acked unread**". That silently loses messages.
    - **Fix (fold into LIME-94 or the sealed-send brief):** store unreadable/unsupported items in a local **`pending_inbound`** table (ciphertext + reason + attempts), ack them on the server only after they are safely stored locally, and retry decryption when sessions/keys change.
    - Never drop sealed items: LIME-94 or 95 must handle sealed sends before anyone sends them.
  - `StoreError.Protocol` was renamed `BadMessage`: fine.

**Update: LIME-92 landed as `a046a66`** (pushed and verified).
- **Plot's own check:** `git grep` finds no project ref in HEAD and no `.env` files tracked.
- The staging smoke test passed; RLS is on; anon/authenticated have no grants; the expiry cron is scheduled.
- A concurrency bug (master-key creation race) was found and fixed.
- **Tend's guards** (accepted): ≤ 500 recipients per send, ≤ 100 keys per upload, ≤ 100 items per fetch; functions at `/functions/v1/<name>`, with the `/v2` paths logical.
- The local stack and Colima are left running (the user can stop them).
- **LIME-93 is drafted.**

**(History) LIME-92 in progress (2026-10-06):** the local half passes 11/11, with tools installed without sudo. The staging deploy is waiting on the user running `supabase login` in tend's window.
- **Tend's two gap-fills (recorded in `api-v2.md` §11), accepted by plot:**
  - the cross-signature message format, `lime-device-v1\n<device_id>\n<identity_key>\n<signing_key>`, with the **master public key fixed at the account's first registration** (trust on first use). **Later needed:** a master-key reset/recovery flow, tied to D5 recovery. Add it to the device-linking/backup brief.
  - all-or-nothing sealed sends (403 for a wrong key, an unknown device or a revoked device alike; nothing is stored), which avoids a device-existence oracle.

**Update: LIME-91 landed as `9f74780`** (pushed and verified).
- `architecture.md` was corrected to match DESIGN-02 (identified first messages from strangers; de-dupe by the outer ciphertext hash).
- **Accepted:** tend's §9 inference (the server sees which account looks up whose keys), an honest limit.
- **For the mesh brief:** relays de-dupe by a hash of the outer envelope.
- **LIME-92 is drafted** (the Supabase v2 core).
- **Machine (2026-10-06):** no Docker, no Supabase CLI, no Deno. LIME-92 installs them via brew + **Colima** (open source).
- **User prerequisites given:**
  - create the `lime-staging` project (East US, free);
  - write `~/.lime/staging.env` with a one-line Terminal command;
  - approve `supabase login` in the browser when tend asks.

**Update: LIME-90-fix landed as `9d18cad`** (pushed and verified). 33 iOS tests pass. Tend set `xcodeVersion: "2700"` + `STRING_CATALOG_GENERATE_SYMBOLS`; the user is to report whether the Xcode "recommended settings" warning is gone.

### DESIGN-04 (noted, plot, 2026-10-07): New Message / New Group, adapted from Signal's pattern
**The user loves Signal's pattern** (5 screenshots, 2026-10-07). **Privacy note:** the screenshots contain the user's phone number; never copy it into files.

**Signal's pattern:**
- a sheet titled "New Message" with a close ✕;
- a card of actions: **New Group**, **Find by Username**, **Find by Phone Number**;
- an **A–Z list of people with an index rail**;
- a floating glass **search field** at the bottom ("Name, username, or number");
- **New Group** = multi-select (checkmarks) with **removable chips** at the top, "N Members", and **Next**;
- Find by Phone shows "Searching…", then "**Invite to Signal**" if they're not a user.

**Lime's adaptation (no contact-book upload, per DESIGN-01 §5):**
- **The list = teachers you already have a conversation with or accepted** (from the local store), A–Z with an index rail. It's empty-state friendly ("Find teachers by username or email").
- **Actions:**
  - **New Group** (needs Megolm/groups; that brief);
  - **Find by Username**;
  - **Find by Email**;
  - **Find by Phone** appears only once phone sign-in is funded (S1 = A).
- **Bottom search:** filters the local list as you type, and on submit does an **exact** server match on username/email (no partial directory search yet).
- **Not found → "Invite a teacher":** the iOS share sheet with an invite link (`joinlime.org`/`limechat.org`, later). The server never sends SMS or email invites itself.
- **New Group:** multi-select + chips → Next → the group name (+ optional photo) → Create.

**Added (the user, 2026-10-07): invite + QR code** ("they make bringing teachers into our community seamless"). From 6 more Signal screenshots, which contain **third parties' names and phone numbers: never copy them anywhere**.
- **Invite a teacher:** a "More → Invite teachers to Lime" row at the end of the list, and the "Invite a teacher" empty-state card.
  - **Plot's privacy choice:** use Apple's **system contact picker** (`CNContactPickerViewController`). The user picks one or more people in Apple's own UI, and **Lime receives only the chosen entries, with no Contacts permission prompt and no access to the whole address book.** Signal asks for full Contacts access; Lime doesn't need it.
  - The choice of **Messages / Mail / Share…** opens the iOS composer **from the teacher's own phone** (`MFMessageComposeViewController` / `MFMailComposeViewController`), prefilled: "Join me on Lime, a private messenger made for teachers: <link>". **Lime's servers never send invites and never see who was invited.**
  - **The invite link** = a personal link to the inviter (e.g. `limechat.org/u/<username>`). On install, it can open straight to "Message <inviter>".
  - **Universal links need the paid Apple account** (Associated Domains) + a small file on limechat.org. Before then, the link opens a web page with App Store/TestFlight instructions.
- **QR code:**
  - **"My QR code"** in Profile/Settings, plus a **"Scan QR Code"** button on Find by Username (as in Signal).
  - **The QR encodes the personal link plus the person's identity key fingerprint.** Scanning opens their profile → **Message**, and **marks them verified in person** (the optional verification in DESIGN-01 §2).
  - **A mesh bonus:** because the QR carries the keys, **two teachers who scan each other can start an encrypted conversation offline**, which is exactly the DESIGN-01 §4 path ("someone you meet and scan in person").
  - The camera permission text: "Lime uses the camera to scan a teacher's QR code." (Photos/video for chat later.)
- **Usernames:** Lime keeps unique usernames, with **no Signal-style ".123" discriminator** (it already enforces uniqueness).
- **"Note to Self"** (seen in Signal) was not requested; it's a candidate for later.

**Where it goes:**
- **New Message v2** (the list, the search, the find-by screens, invite, QR) is folded into the **groups brief (LIME-97)**, because it shares the multi-select.
- **QR-based offline first contact** lands with mesh v1.
- A small interim polish may come earlier if the user asks.

### DESIGN-03 (draft, plot, 2026-10-06): native sign-up and sign-in (for LIME-94), adapted from Signal
**The user's ask:** "remove the coming-soon Google and Apple sign-in; keep sign-in by phone number, username or email; take the best of Signal's sign-in". They shared 11 screenshots of Signal's onboarding.
- **Privacy note for plot:** those screenshots contain the user's real phone number. **Never copy it into any file.**

**What we take from Signal:**
- a splash;
- a welcome with one primary "Continue";
- **one question per screen**, with a glass "Next" top right, disabled until valid;
- **a confirmation sheet** ("Is this correct? Yes / Edit") before sending a code;
- **one-time codes instead of passwords**;
- a short permissions explainer *before* the system prompt;
- an empty state with "Get started" cards.

**What we don't take:**
- **Contacts upload:** Lime has no private contact discovery (Signal uses secure enclaves; hashed phone numbers are reversible). This matches DESIGN-01 §5 "no contact-book upload in v1".
- **A short PIN for backups:** without Signal's enclave, a 4–6-digit PIN can be brute-forced offline. **Lime uses the long recovery key (D5)** instead.
- **"Restore or Transfer" options before they exist:** show them only once device linking and the recovery backup are built.

**The proposed flow (native iOS):**
1. **Splash:** the lime logo on the canvas.
2. **Welcome:**
   - an illustration of teachers (to be designed);
   - "Connect with every teacher. Privately.";
   - "Built by teachers, for teachers" (**not** "a 501(c)(3)": Lime isn't one yet);
   - Terms & Privacy;
   - **Continue**.
3. **"Your phone, email or username"**: **one field**. It detects the type: digits/`+` show a country-code picker (Signal's style); `@…` is an email; otherwise a username. **No Google or Apple buttons.**
4. **The confirmation sheet:** "We'll send a code to: … Is this correct?" (Yes / Edit).
   - For a **username**, the code goes to the email or phone on that account, shown masked ("s•••@famkind.com").
   - An unknown username gets "No account with that username" plus "Use your phone or email instead".
5. **The code screen:** 6 digits, with autofill (`oneTimeCode`), Resend after 30s, and Edit.
6. **A new account only:**
   - "Your name" (display name);
   - optional **username** (unique, as on the web);
   - optional **school**;
   - then go to Messages.
7. **Messages, empty state:** "No chats yet" plus Get started cards (**New message**, **Invite a teacher**).
- **Later briefs (not 94):**
  - a permissions explainer: Notifications, with the push brief; Bluetooth "Nearby messaging", with the mesh brief;
  - "Save your recovery key", with the backup brief;
  - Restore/Transfer, with the linking/backup briefs.

**DECIDED (user, 2026-10-06):**
- **S1 = A:** email + username at launch; phone sign-in when funded.
- **S2 = B: password + code.** Plot's interpretation, written into LIME-94:
  - **Sign-up:** email → emailed 6-digit code (verifies the email) → create a password → name, optional username and school.
  - **Sign-in:** email **or** username → password → **a 6-digit code emailed every time a device signs in** (two-step).
  - **Forgot password:** emailed code → new password.
  - The server must **enforce** that a device registers only after both the password and the code were verified for that sign-in.
- **Remove "Continue with Google/Apple · Soon" from the web sign-in page too:** yes (LIME-94w).

**(History) Decisions for the user (asked 2026-10-06):**
- **S1, phone numbers at launch:**
  - **A.** Email + username now; **phone sign-in switched on when funded**. SMS costs money per message (around a cent in the US, more abroad) and attracts SMS-fraud attacks; email codes are nearly free. **Lean A.**
  - **B.** Phone too from day one: needs a paid SMS provider + fraud protection.
- **S2, codes or passwords:**
  - **A.** Codes only, no passwords, like Signal: nothing to forget or leak. Stolen-email risk is mitigated later by the recovery key and device verification. **Lean A.**
  - **B.** Password + code.
- **Note:** email codes in production need a proper email sender (Supabase's built-in one is for testing and heavily rate-limited; e.g. Resend's free tier). Staging can use the built-in one.
- **The web app** keeps its old auth (frozen). The native app never had Google/Apple buttons, so "remove" means "never add". The user may still ask to remove them from the web.

### DESIGN-02 (draft, plot, 2026-10-06): API v2, the blind mailbox protocol
**Status:**
- **The user's decision needed: R1 only** (below). Everything else follows from D1–D8.
- Once decided, **LIME-91** writes it into `docs/api-v2.md` (docs only); then come the Supabase briefs.
- **Grounded in:** `docs/architecture.md` §§3–7 and 11.5; `docs/api.md` v1 §§2–8 (the op envelope, idempotency, auth).
- **Not verified:** Supabase Realtime/Edge Function limits at scale; the first Supabase brief will survey them.

**1. What the server stores (Supabase Postgres + Storage):**
- `profiles`: the public directory fields only (display name, username, school, avatar file id, `hide_from_search`). This is the one cleartext social data (D7).
- `devices`: the device id, the user id, the Curve25519 identity key, the Ed25519 signing key, **a signature by the user's master key** (cross-signing), and the revoked time.
- `master_keys`: the user's public master signing key.
- `one_time_keys`: a pool per device, each **claimed once**.
- `mailbox_items`: the recipient device, a `cursor` (bigserial), the outer ciphertext bytes, the size and the received time. **Deleted when acknowledged**; **undelivered items expire after R1 days**.
- `blobs`: encrypted attachments (the id, the size, the uploader for quota, the expiry).
- `delivery_keys`: per user, **a hash** of the current delivery-key material (see 3). Never the key itself.
- `backups`: opaque recovery-key-encrypted backup blobs (D5).
- **The server never stores:** conversations, group names, membership, senders of sealed messages, message text, or reactions.

**2. Envelopes (two layers):**
- **Outer (the server sees it):** `{ to_device, access, ciphertext, size }`. **No sender.** `access` is either a delivery-token proof (sealed) or the sender's auth (identified; see 3).
- **Sealed inner (after the recipient's Olm decrypt):** `{ sender_user, sender_device, sender_cert, op }`, where `sender_cert` is the sender device key signed by its master key.
- **`op` (signed, as `architecture.md` §4):** `{ op_id (UUIDv7), type, conversation_id, hlc, parents[], payload, sig }`.
  - `payload` is a **Megolm ciphertext** for messages/reactions/edits, or an encrypted group-state op.
  - `sig` is the Ed25519 signature of the sender device over the canonical op.
- **Fan-out:** one request carries a shared Megolm ciphertext plus a list of `(to_device, access)`. The server stores one item per recipient device. **Honest limit (already in `architecture.md` §5):** the server sees the recipient set of each request, and so could infer group membership statistically.
- **Megolm session keys** travel as Olm-encrypted to-device ops through the same mailbox.

**3. Sealed sender and message requests (D7 + D8):**
- Each user has a **delivery key**, shared only inside their encrypted conversations (so contacts have it).
- A sealed send proves knowledge of the recipient's delivery key (an HMAC over the request); the server checks it against the stored hash and **learns nothing about the sender**.
- **Strangers don't have the key**, so their first message is sent **identified** (the server sees the sender) and lands in the recipient's **Requests**.
- **Accept** shares your delivery key.
- **Block rotates your delivery key** and shares the new one with everyone except the blocked person, so their sealed sends fail.
- Rate limits apply per access token and per IP.

**4. Ordering (the answer to `architecture.md` §11.5; told to the user 2026-10-06, no objection):**
- The server's `cursor` is **per mailbox, for sync only**.
- The conversation order comes from the devices: **HLC + `parents[]`** (the latest op ids the sender had seen). Display order is causal, tie-broken by HLC, then `op_id`. It is identical online and over the mesh.
- The display time keeps v1's "never in the future" rule.

**5. Group state (client-managed):**
- The ops are `group.create`, `group.add`, `group.remove`, `group.leave`, `group.rename`, `group.set_avatar`, `group.set_role`. All are encrypted and signed, and ordered by rule 4.
- **The authority rules are checked by every client:** only the owner and admins add, remove or rename; a member may leave.
- **Conflict rules:** a concurrent remove beats an add; a rename/avatar is last-writer-wins by `(hlc, op_id)`; the owner can't be removed except by leaving (then the oldest admin, else the oldest member, becomes owner).
- **Rotate the Megolm session on any membership change** (`architecture.md` §3).

**6. Endpoints (`/v2`, Supabase Edge Functions):**
- **Auth:** Supabase Auth email + password, plus device registration that binds a token to a `device_id`.
- **Keys:**
  - upload the device keys + a one-time-key batch;
  - `GET /v2/users/:id/devices` (the identity keys + cross-signatures);
  - `POST /v2/keys/claim` (one-time keys);
  - publish the master key.
- **Mailbox:** `POST /v2/send` (the fan-out batch); `GET /v2/mailbox?after=cursor`; `POST /v2/mailbox/ack` (deletes up to the cursor).
- **Realtime:** one Supabase Realtime channel per device, carrying a **"new items" nudge only** (no content).
- **Push:** APNs with **no content**; the notification extension fetches and decrypts on the device.
- **Blobs:** upload/download of encrypted files via signed URLs, with the expiry rule from cost principles.
- **Directory:** search with exact username/email/phone match, as v1; respects `hide_from_search`.
- **Backup:** `PUT/GET /v2/backup` (opaque).
- **Calls:** `POST /v2/turn` (time-limited TURN credentials, rate-limited); `POST /v2/calls/token` (a LiveKit token in exchange for a **per-call capability** from the encrypted invite, so no server membership check is needed).

**7. Mesh:** relays carry the **outer** envelope unchanged (`to_device` + ciphertext + access). Whoever gets online first posts it to `/v2/send`.
- **The server de-dupes by a hash of the outer ciphertext per recipient device**; it can't see the inner `op_id`.
- **Recipients de-dupe by `op_id`.**

**Decision for the user:**
- **R1: how long an undelivered message waits on the server** for a phone that's been offline (e.g. lost, or off for the summer):
  - **A. 30 days** (lean);
  - **B. 90 days** (more forgiving, more storage);
  - **C. 7 days** (Signal-like strictness).

  After that, the sender's message is gone for that device. Its other devices and the recovery backup are unaffected.

**R1 DECIDED (user, 2026-10-06, after the correction): 30 days.** Undelivered mailbox items expire 30 days after they are received. DESIGN-02 is final for LIME-91.

**(History) R1: the user first chose C (7 days) on 2026-10-06, but plot had mislabelled C as "Signal-like".** Signal actually drops queued messages after about **30 days** (support.signal.org, "Troubleshoot receiving messages"). Plot corrected this and asked the user to confirm 7 or switch to 30. **Pending the user's confirmation; don't write LIME-91 until it's confirmed.**

**Briefs this unlocks (after R1):**
1. **LIME-91:** `docs/api-v2.md` (docs only).
2. **LIME-92:** a Supabase **staging** project + the schema + the key/mailbox Edge Functions + tests. Needs **the user to create a free Supabase account and a project**; the credentials go in a gitignored file.
3. **LIME-93:** the core: persisted Olm/Megolm keys (in the SQLCipher store), device registration, send and fetch. **Two simulators exchange an encrypted message through staging.**

### DESIGN-01 (draft, plot, 2026-10-05): native Lime architecture: E2EE, devices, mesh, discovery, calls
**Status:**
- **A draft for the user's decisions D5–D8 (below).** Once they're decided, LIME-88 (docs only) moves it into `docs/architecture.md`, and `docs/api.md` gets a "v2: E2EE" section.
- **Grounded in:** `docs/api.md` §§1–3, 8, 9 and 12 (the op envelope, the auth/devices endpoints, visibility, mesh notes), `docs/data-model.md`, and the decisions D1–D4, vodozemac, teachers-as-audience and calls recorded above.
- **Assumed:** the paid Apple account in November 2026; Supabase as decided; LiveKit self-hosted.

**1. Components.**
- **The iOS app** (SwiftUI, iOS 17+) talks only to **LimeCore**.
- **LimeCore** is a Rust library shared later with Android and desktop, exposed to Swift and Kotlin through **UniFFI** (Mozilla's binding generator, as matrix-rust-sdk does). It holds:
  - vodozemac;
  - the local database (SQLite encrypted at rest with **SQLCipher**; the key in the Keychain);
  - the op log and outbox;
  - the sync engine;
  - the mesh protocol;
  - local search (SQLite FTS).
- **Transports** plug into the core:
  - HTTPS + a realtime socket to the backend;
  - Bluetooth LE mesh;
  - later, local Wi-Fi.
- **Backend:**
  - **Supabase:** Postgres for routing metadata and ciphertext, Auth, Storage for encrypted blobs, and Edge Functions implementing the op endpoints (separate staging and production projects);
  - **LiveKit** (self-hosted) for calls;
  - **APNs** (+ PushKit for calls); FCM later.
- The current dev server and API v1 stay as the frozen web app's backend and the reference contract.

**2. Identity and keys (per device, Matrix-style).**
- Each device has a vodozemac **Olm account**: Curve25519 identity + Ed25519 signing keys. It uploads its public keys and a pool of one-time keys to a **key directory** on the server.
- **Op signing (closes `api.md` §9 Q1):** every op envelope carries `sig`, the device's Ed25519 signature over the canonical envelope. Server and peers reject an unsigned op or a bad signature. This is what makes a relayed op from a stranger's phone trustworthy.
- **Cross-signing:** a per-user **master key** signs each device key, so other people trust a teacher's new phone without re-verifying.
- **Adding a device** (Linked Devices becomes this): the new device shows a QR code; an existing device scans it, signs the new key and hands over the history keys directly (encrypted).
- **Optional "verify in person"** (scan each other's QR) gives a verified badge.

**3. What is encrypted.**
- **Every conversation uses Megolm** (vodozemac). Each sending device has an outbound session per conversation and shares its key with every member device over Olm. **Rotation:** on any membership change, every 100 messages, or every 7 days.
- **Encrypted:**
  - message text and formatting, edits, replies' content, reactions;
  - the conversation name and avatar;
  - attachment names, types and sizes.
- **Files** are encrypted on the device with a fresh AES key, which travels inside the encrypted message. Storage only ever holds ciphertext.
- **Link previews** are made by the sender's device; the server never fetches URLs.
- **Search** happens on the device only. **Notifications** carry only ids; an iOS Notification Service Extension decrypts on the device to show a preview, sharing the core and keys through an App Group.
- **The server still sees (honest limit, v1):**
  - who is in which conversation;
  - when messages are sent, and their sizes;
  - the profile fields in the directory.

  It sees **content, never**. Signal-grade metadata hiding (sealed sender, private groups) is a later version.
- **API v2:**
  - a message op's `payload` becomes `{ algorithm, session_id, ciphertext }`;
  - membership ops stay readable, so the server can route and enforce membership;
  - `seq` stays the server's ordering online.
- **Reporting abuse:** a "Report" sends the reported messages, decrypted, by the reporter's choice; nothing else is readable.

**4. Offline mesh (Bluetooth).**
- **The unit is the signed, encrypted op envelope**, already unreadable to relays.
- **Store-and-forward:** at most 7 hops and 72 hours, de-duplicated by `op_id`. Devices exchange "what I have" summaries and swap the missing ops. Rate limits per device key; anything unsigned is dropped. Whoever reaches the internet first uploads; the server de-dupes by `op_id`.
- **Transport:**
  - iOS: CoreBluetooth with background modes + state restoration;
  - Android: a foreground service;
  - wire format: borrow from **bitchat** (public domain).
- **The key limit:** starting a *new* encrypted conversation needs the other person's keys. So offline, you can message **anyone you've already talked to or whose keys your phone cached** (the core caches members' keys while online), or someone you meet and scan in person. Strangers you've never connected with need the internet once.
- **The open question for the spike:** how well iPhones relay with the app closed.

**5. Discovery: "connect all teachers" vs privacy.**
- Today: a directory searchable by name and school; exact match only on username, email or phone; email and phone are never shown. This carries over.
- **New for v1:**
  - **Message requests:** a first message from someone you share no conversation with lands in Requests (Accept / Block / Report).
  - **Block.**
  - **"Hide me from search"** (people can still reach you by exact username).
  - Rate-limited search.
  - **18+ only** (an age confirmation at sign-up).
- No contact-book upload in v1.

**6. Calls.**
- Signalling is encrypted call ops in the conversation (`call.invite` / `answer` / `end`).
- The server's Edge Function issues a LiveKit room token after checking membership.
- **The media key is per call**, shared in the encrypted invite and rotated when people join or leave.
- iOS: CallKit + a PushKit VoIP push that carries only ids.
- Group: 50–100 people, active-speaker video, speaker view above ~12. No recording.

**7. Build order (one brief each; the user's gate between):**
1. LIME-87, the iOS skeleton (in progress).
2. LIME-88: this design into `docs/`.
3. LIME-89: the Rust core skeleton (`core/`, UniFFI, a vodozemac Olm round-trip test, linked into the iOS app; needs `rustup`).
4. LIME-90: the core's encrypted local store + the iOS screens reading sample data from the core.
5. **The Bluetooth spike** (2 iPhones; may need the paid account for background modes).
6. Supabase staging + schema v2 + auth + the key directory.
7. Sync + E2EE messaging end to end (two simulators, then two phones).
8. Push + the notification extension.
9. TestFlight (the paid account).
10. Mesh v1.
11. Calls v1 (1:1).
12. Group calls.
13. Android.

**ALL DECIDED (user, 2026-10-05): D5 A (optional encrypted backup + recovery key), D6 A (any Lime phone relays), D7 A (open sign-up, verified badge later), D8 B (blind mailbox).** DESIGN-01 is final for LIME-88.

**Decisions put to the user (2026-10-05):**
- **D5 history if you lose every device:**
  - **A.** An optional encrypted backup unlocked by a recovery key you write down (Matrix-style). **Lean A.**
  - **B.** No backup: history is gone (Signal's strict default).
- **D6 who relays offline messages:**
  - **A.** Any Lime phone relays encrypted messages (the most reach in an emergency; relays see only scrambled data and routing hints). **Lean A.**
  - **B.** Only people you're connected to.
- **D7 joining and verification:**
  - **A.** Open to any teacher who signs up, with a "verified teacher" badge later (e.g. school email) and message requests protecting inboxes. **Lean A.**
  - **B.** School-email verification required up front (more trust, but it excludes teachers without a school address and ties identity to employers).
- **D8 metadata in v1 (REVISED after the user asked whether libsignal/AGPL is worth it for this):**
  - **Plot's finding:**
    - Signal's metadata privacy comes mostly from **server architecture**: the server is a blind mailbox per device, the sender is hidden inside the envelope ("sealed sender"), and groups are managed by the clients.
    - Only **private group credentials (zkgroup)** need libsignal (AGPL) code; rebuilding those ourselves would be rolling our own crypto.
    - **The offline mesh already forces client-managed group state** (groups must change while offline, with no server to ask), so a mailbox server fits Lime anyway.
  - **The options:**
    - **A.** v1 as drafted (a conversation-aware server sees who/when/which group), with metadata hiding later. Later means a painful migration.
    - **B.** Stay on vodozemac and **build v1 as a blind mailbox:**
      - sealed sender (the server doesn't learn who sent a message);
      - client-managed encrypted group state (the server has no list of groups or names);
      - delivery to per-device mailboxes.

      The server still sees recipients' devices, timing, sizes and IP addresses; even Signal's does. It is moderately more v1 work, and Supabase RLS can no longer enforce membership (clients and delivery tokens do). **Lean B.**
    - **C.** Switch to libsignal (AGPL) for zkgroup + sealed-sender certificates: Signal's full model, but AGPL, a library "unsupported outside Signal", and a Signal-style server to build.
  - **DECIDED: B (user, 2026-10-05).** Blind-mailbox server from v1, vodozemac, MIT. D5–D7 are still awaiting the user.
  - **DESIGN-01 changes accordingly (they apply; LIME-88 must write the design this way):**
    - §1: Supabase becomes auth + key directory + mailbox + blob storage;
    - §3: membership ops become encrypted group-state ops;
    - §6: the call token check uses a per-call capability instead of server membership.

### Open thread: market and bootstrapping (user, 2026-10-05: "no budget, out of pocket; start small, then scale")
- **Market (researched):**
  - US: ~3.8M public-school teachers (NCES/Pew) + ~0.48M private (NCES FTE, 2021).
  - Worldwide: tens of millions of teachers (UNESCO 2024 Global Report; the world still needs 44M more by 2030).
  - The parent/school communication market is ~$2.8–3.2B (2025, analyst reports of low reliability), dominated by ParentSquare/Remind and ClassDojo (school- and parent-facing, not E2EE).
  - **Cautionary tale:** Edmodo (100M users, free) shut down in 2022 as "no longer viable".
- **The 2x2 given to the user:** privacy (readable by company or school ↔ E2EE) × audience (general ↔ built for teachers). Lime sits almost alone in **E2EE + built for teachers + across schools + offline**. The nearest are the German state school messengers on Matrix (E2EE but walled per state or district).
- **Users, not dollars (a nonprofit):**
  - TAM ≈ the world's teachers;
  - SAM ≈ English-speaking smartphone teachers, US first (~4.3M);
  - SOM (3 years, $0 budget) ≈ **10k–50k active teachers**;
  - year 1 ≈ **500–2,000**.
- **The plan given to the user:**
  - Phase 0: $0–25/month.
  - Pilot: ~$50–100/month.
  - Grants: NLnet NGI Zero €5k–50k; OTF $10k–900k (check its current status); education foundations.
  - Teachers' unions as distribution partners.
  - Fiscal sponsor or Form 1023-EZ ($275, under $50k/yr receipts).
- **Design implications to fold into DESIGN-01 later (leans, not yet decided):**
  - **1:1 calls go peer-to-peer WebRTC** with a TURN fallback, and LiveKit only for group calls (LiveKit is SFU-only, so every 1:1 call would otherwise cost server bandwidth);
  - **audio before video**;
  - the mailbox deletes after delivery;
  - attachments expire (e.g. 30 days after every recipient has fetched them);
  - group video comes only when funded.

  Raise these with the user before LIME-88 if possible, or as a DESIGN-01 amendment.
- **DECIDED (user, 2026-10-05):**
  1. **1:1 calls go peer-to-peer WebRTC** (with a TURN fallback); **the self-hosted LiveKit SFU only for group calls**. LIME-88 must write DESIGN-01 §6 this way.
  2. **The first TestFlight waits until offline mesh relaying is included.** So the build order moves "Mesh v1" **before** "TestFlight":
     1. … 7. sync + E2EE messaging;
     2. 8. push;
     3. 9. **mesh v1**;
     4. 10. **TestFlight**;
     5. 11. 1:1 calls (P2P);
     6. 12. group calls (LiveKit);
     7. 13. Android.

     LIME-88 writes the amended order.
- **The cost-design leans** (the mailbox deletes after delivery, attachments expire, audio before video, group video only when funded) are carried into LIME-88 as **principles**, not hard numbers.

### Open thread: voice and video calls (raised by the user 2026-10-05: "a major part of teachers connecting")
- **Plot's plan:**
  - WebRTC media on **LiveKit** (an open-source SFU, Apache-2.0; Swift, Kotlin, web and Rust SDKs; E2EE through frame encryption; self-hostable or LiveKit Cloud).
  - **The precedent is Element Call**: Matrix + vodozemac + LiveKit, E2EE group calls of up to ~100 people. **The call keys are distributed over Lime's own E2EE channel (vodozemac)**, so the server and the SFU never see the media.
- **The native iOS pieces:**
  - **CallKit** (the native incoming-call screen, the lock screen, Recents, Bluetooth headsets);
  - **PushKit VoIP pushes** to ring a closed app (needs the **paid Apple account**; every VoIP push must report a call to CallKit at once);
  - the background-audio and VoIP modes.
  - Android later: ConnectionService + high-priority FCM.
- **Rejected options:**
  - Signal's RingRTC + calling server (AGPL, and "unsupported outside Signal");
  - Twilio/Agora/Daily (the vendor can see the media, and recurring costs);
  - Jitsi (Apache, but weaker native mobile polish).
- **Cost note:** the TURN relays and the SFU bandwidth are Lime's main recurring infrastructure cost (video the most). Self-hosting LiveKit keeps it bounded; budget for it in the nonprofit plan.
- **Offline:** calls need a network. Bluetooth is too slow for audio or video. A later option is **local-network calls** (the same Wi-Fi with no internet, or peer-to-peer Wi-Fi). Messages are mesh; calls are online-first.
- **The phases** (after the messaging core, the backend and the paid Apple account):
  1. **Calls v1:** 1:1 voice + video, E2EE, CallKit, ringing via PushKit.
  2. **v2:** group calls (staff meetings: grid, speaker view, mute controls).
  3. **v3:** screen share, raise hand, larger PD sessions, and maybe a "jam" tie-in.
  - The architecture choice (LiveKit) goes into the design pass, so the backend reserves call signalling (call-invite ops through the existing op channel) and token issuance.
- **Requirement (user, 2026-10-05): calls must be open source and secure.**
  - LiveKit fits: the server and every SDK are Apache-2.0, and its TURN is built in.
  - **So: self-host LiveKit** (LiveKit Cloud is a proprietary hosting service, though it runs the same open code; keep it only as an emergency fallback, if ever).
  - Media is E2EE, with keys from vodozemac sessions.
  - Include the call key exchange in the pre-launch external security review; plot found no published audit of LiveKit's E2EE.
- **DECIDED (user, 2026-10-05):**
  1. **Group calls target 50–100 participants** (large PD sessions). LiveKit's SFU is in range; use simulcast, show only active speakers' video, and a speaker view by default above about 12. Load-test at 100 before launch.
  2. **No recording in v1.**
  3. **Self-host LiveKit from launch.**

### Queue override (2026-10-05, later)
1. **LIME-86-fix** (drafted under "Drafted briefs"): the user's 14 QA notes on 86; commits `PLOT.md` first.
2. **Then the web phone layout goes into maintenance.** LIME-85, 80 and 81 are **paused** (plot's lean, option A; the user said "close out this round of QA, save it on git and then switch to this direction"; confirm with the user).
3. **Plot's next work:** the E2EE / keys / devices / mesh / discovery design pass toward the native iOS app (see "Open thread: the road to the iPhone app").
4. **Pending with the user:** the dark own bubble and the dark "+" button (screenshot 1 shows the "+" nearly invisible in dark; lean C: lift the dark `--lime-primary-bg`); Xcode and two iPhones for the Bluetooth spike; the Apple Developer account comes next month.

### The authoritative queue (in order; see the override above)
1. ~~LIME-86~~ **landed as `c9712c9`** (review pending): mobile QA round 3 (toasts at the top right, the scroll lock, the chat sliding sideways, landscape margins, thread and details headers, "⋯" with no ring and a slimmer menu, the add-reaction smiley only with reactions, a single ✓ until read receipts, lighter chips, a compact "N replies", composer fixes plus the Aa / list / align menus, **the selection → inline B/I/U/S toolbar**, true circles, dock strokes, **own bubble = the "+" FAB green**).
2. **LIME-85:** the shared component set, **no visual change** (component CSS with container queries, shared render functions, `docs/components.md`).
3. **LIME-80** (amended): Pin replaces Star, Customize, native share / timezone, find-in-chat, the calls toast, **instant sign-out of a revoked device**.
4. **LIME-81:** live "typing…" (ephemeral) plus **read receipts** (✓ / ✓✓; members can see each other's `last_read_at`).
5. **Desktop v2** (approach **A**, "same app, wider"): **brief it after the user saves their frames** to `docs/design/desktop/` and LIME-85 lands. The desktop UI for usernames and Linked Devices goes in here.
6. **Later:** the backend planning pass (**option C**: Supabase + local-first sync; **separate staging and production projects**), Communities (deferred), swipe actions, voice messages (the mic → recording with sound waves), calls (planned "soon"), the cleanup brief (see Unbriefed).

### Waiting on the user
- The LIME-86 review on the iPhone (then LIME-85).
- Save the desktop frame(s) to `docs/design/desktop/` (also Settings on desktop, hover / right-click, and the details/thread pane behaviour).
- Unanswered: commit `public/assets/Logomark-outline.svg` as a brand asset? DND grey or red (assumed grey)? Leading zero in times (assumed none)?
- The `LIME_DONATE_URL` when ready (`public/js/config.js`).
- Optional: `safaridriver --enable` (so tend can test Safari).

### Steward: the assumption to question next session
**We're polishing a mobile *web* app to native-app fidelity** (liquid glass emulated with `backdrop-filter`, gestures, the iOS selection callout, Safari's password prompt, the status bar). The stated goal is **native iOS and Android apps** with offline Bluetooth. Much of this web-only work may be throwaway, depending on the client technology (**native / React Native / Capacitor**, `docs/api.md` §12). **Before the desktop v2 build, put a decision surface to the user on the mobile client technology,** since it decides how much of today's web UI carries over (Capacitor keeps it; native or RN rebuilds it) and how much more polish the web phone layout deserves.

### Open thread: the road to the iPhone app, then Android (raised by the user 2026-10-05 during the 86 review)
The user's view was "we're closer than I imagined". Plot's assessment (it was surveyed):
- **What is closer than expected:** the **data layer**, which is the hardest part to retrofit. `docs/api.md` is op-based, local-first, uses client-made ids, has an outbox and idempotent ops, and §9 already names the op as the unit a phone relays over Bluetooth. The phone UI exists and follows the Penpot design (01–06).
- **What is further than it looks:**
  1. **No real backend.** `server/dev-server.mjs` keeps JSON files in `data/` on the user's laptop. The Supabase pass (option C, separate staging and production) has to come before TestFlight.
  2. **On-device storage** is `localStorage`: the cache and outbox in `api-adapter.js`. iOS can evict web storage, so an app needs SQLite or another durable store.
  3. **Push** (APNs/FCM, §10) isn't built.
  4. **The mesh is unscoped.** On iOS, Bluetooth between two phones that both have the app in the background is very limited. This is the deciding unknown.
  5. **Store overhead:** Apple developer account ($99/yr), Play ($25), privacy policy, review.
- **The decision surface given to the user:**
  - **A.** Capacitor wrap, with the mesh as a native Swift/Kotlin plugin.
  - **B.** React Native: rebuild the UI, keep the contract.
  - **C.** Fully native, Swift then Kotlin.
- **Lean: A**, plus a **Bluetooth feasibility spike first**. The question for the user that unlocks it: must offline messaging work with the app **closed** (backgrounded), or only while it is **open**? Open-only favours A strongly; closed, phone-to-phone on iOS, pushes toward native for the mesh part, whatever the UI is.
- **Update (same day): the user's gut is C, modelled on Signal.**
  - **Signal's approach (researched):** one app per platform. iOS is Swift and Android is Kotlin, both native. Desktop is TypeScript/Electron. The hard core (the encryption protocol and crypto) is one shared Rust library, `libsignal`, wrapped for Swift, Java and TypeScript.
  - Signal has **no offline or Bluetooth mode**; it needs the internet. "Signal Offline Messenger" is an unrelated app.
  - The closest model for the mesh is **bitchat**: native Swift on iOS, and a protocol-compatible native Kotlin port on Android (which uses a foreground service to keep the mesh alive).
  - **Plot's revised view:**
    - C is defensible *if* privacy is a product promise. In that case, mirror Signal: native UIs, plus one shared core for the op protocol, signing and crypto.
    - The current web app becomes the web/desktop client and the spec for the native screens.
    - **The bigger decision that C surfaces is end-to-end encryption.** Signal is private because of E2EE, not because it is native. E2EE changes the backend (the server can't read, search or validate message content; `docs/api.md` §9 Q2) and so has to be decided *before* the Supabase pass.
    - `libsignal` is AGPL-3.0; Lime is MIT. Using it would mean open-sourcing under AGPL or picking another library: a decision for the user.
- **DECIDED (user, 2026-10-05): end-to-end encryption.** It shapes the backend pass: the server stores ciphertext and can't search, preview or validate message content. Push previews must be generated on the device. Server-side search is gone.
- **Open: which E2EE library.** The user asked about MIT vs AGPL and about "studying theirs and making our own". Plot's answer:
  - **Don't write our own cryptography.** Reading published specs is fine, since copyright covers code, not ideas. A home-made implementation needs a paid audit and is the classic way secure apps fail.
  - **The candidates:**
    - `libsignal` (AGPL-3.0: Lime would have to be open-sourced under AGPL);
    - **vodozemac** (Matrix's Olm/Megolm, i.e. Signal's Double Ratchet plus group sessions; Rust, Apache-2.0, audited by Least Authority);
    - **OpenMLS** (the IETF MLS standard, RFC 9420; Rust, MIT; built for large groups and multi-device, but group changes need a consistent order, which fits poorly with the offline mesh).
  - **Plot's lean: vodozemac.** It is permissive, so Lime can stay MIT; it has been audited; it is battle-tested in Matrix/Element; it is Rust, so the Signal pattern of one shared core works; and Megolm tolerates offline and out-of-order delivery.
  - **Chosen: vodozemac (see DECIDED below).**
  - **Follow-up facts given to the user:**
    - **Neither library does Bluetooth.** Encryption doesn't care how bytes travel. The Bluetooth transport is built separately either way; **bitchat** (Unlicense / public domain, Swift + Kotlin) is a free-to-borrow reference for it.
    - **1:1 chats:** Olm ≈ Signal (both Double Ratchet).
    - **Groups:** Signal's Sender Keys recover better after a compromised device; with Megolm, whoever holds a session can read its later messages until the session rotates (mitigation: rotate often and on membership change).
    - **Signal's protocol is the most formally analysed** (2016 analysis; PQXDH formally verified in 2024) and has post-quantum key exchange. I found no published third-party *code* audit of libsignal itself. vodozemac has a code audit (Least Authority, 2022) and Matrix has formal analyses.
    - **AGPL for schools:**
      - Teachers and schools *using* Lime take on no obligations.
      - Friction falls on (a) blanket corporate/legal bans (e.g. Google's), (b) procurement questionnaires that flag copyleft, and (c) edtech partners who'd embed Lime's code; integrating over an API is fine.
      - A district self-hosting a modified copy would have to publish its changes.
      - Schools' real procurement concern is student-data privacy (FERPA/COPPA, GDPR), where E2EE helps.
    - **Matrix in education and government (researched):**
      - Schleswig-Holstein and Hamburg (Element, 500k seats including schools), SchulchatRLP (a FluffyChat fork for about half a million pupils), ByCS-Messenger (Bavaria), LOGINEO NRW Messenger;
      - Tchap (France), BwMessenger (the Bundeswehr), TI-Messenger (German healthcare), NATO's NI2CE experiment.
      - vodozemac is Matrix's reference E2EE (libolm is deprecated). Which version each deployment runs was not verified.
    - **What MIT/vodozemac gives up vs libsignal:**
      - **post-quantum protection**, i.e. "harvest now, decrypt later" (Signal has PQXDH and a PQ ratchet; vodozemac doesn't yet);
      - **metadata privacy tools** in libsignal (zkgroup private groups, sealed-sender certificates), which also need a Signal-style server design;
      - **performance:** no meaningful difference.
      - **Correction to an earlier answer:** the difference in group recovery between Megolm and Signal's Sender Keys is subtle, not a clear Signal win.
      - Matrix's published vulnerabilities (2022 Royal Holloway; libolm timing) were in protocol/client logic or the old libolm, not vodozemac.
    - **libsignal facts:**
      - Signal gets no ownership of FAM's code.
      - A released version's AGPL grant can't be revoked; future versions could change.
      - Its README says "Use outside of Signal is unsupported" and that APIs "are subject to change without notice", so we'd pin a version and absorb breaking upgrades. A community fork exists (mollyim/libsignal).
    - **US school messaging (ParentSquare/Remind, ClassDojo):** I found no E2EE or Signal Protocol, only encryption in transit and at rest. E2EE would set Lime apart.
    - **NEW OPEN THREAD (important): E2EE vs school record-keeping.** US public-school communications can be public records or FERPA records, and districts may require archiving, e-discovery or safeguarding review. With E2EE, a district can't do that server-side.
      - This needs a product answer before the backend: who Lime sells to (teachers directly vs districts), plus possible designs such as an opt-in org archive key or user-initiated export.
      - The question was raised with the user.
    - **The AGPL trade-offs were explained** (the licence is per repo; FAM owns its code so it can still ship to the App Store; outside contributors need a CLA; it is hard to go back to MIT later).
- **DECIDED (user, 2026-10-05):**
  1. **The audience is teachers** (mission: "connect all teachers"), not districts. So: **full E2EE, no organisation archive key.** Record-keeping is the teacher's responsibility, which belongs in the terms of service later.
  2. **E2EE library: vodozemac.** **The licence (MIT vs AGPL) is still open; the user is "still deciding".**
     - vodozemac (Apache-2.0) works under either, so the licence doesn't block anything.
     - MIT→AGPL stays easy while FAM owns all the code.
     - The decision is needed before outside contributors arrive or the repo goes public.
  3. **Offline messaging must work with the app open AND closed.** So: **C (native Swift, then Kotlin) is confirmed.** Closed-app Bluetooth on iOS is the project's biggest technical risk and gets a real-device spike before anything is built on it.
  4. (Earlier) **C: native apps, on Signal's pattern** (native UIs, one shared Rust core).
- **Organisational context (user, 2026-10-05):** Lime plans to be a **501(c)(3)**, eventually a foundation, with **Lime Messenger LLC (a teacher cooperative)** as the core product. This mirrors Signal (Signal Technology Foundation, a 501(c)(3), owns Signal Messenger LLC).
  - Plot's thought-exercise answer:
    - Borrow Signal's *model* and proven crypto; be trailblazers in the mission (offline mesh, teachers, cooperative governance), not in cryptography.
    - **The nonprofit status weakens AGPL's downsides** (no closed licences to sell), so **AGPL + vodozemac** is now a strong option.
    - ~~Flagged for a lawyer: LLC vs co-op~~ **Clarified by the user:**
      - **a cooperative nonprofit** (a teacher-member-governed 501(c)(3) foundation) **wholly owns a for-profit subsidiary, Lime Messenger LLC**, which runs the product. The co-op is at the foundation level, as in Signal's LLC-under-foundation shape.
      - Still for a lawyer: how member governance and the subsidiary's profits are set up.
- **Consequences plot is carrying:**
  - **The web app's new role** is the web/desktop client (like Signal Desktop) and the visual spec for the native apps. More mobile-web polish has diminishing value: fix real bugs only.
    - ~~Trim LIME-80's phone-native items~~ **Withdrawn after re-reading the brief:**
      - The glass menus already moved into 79-fix.
      - What remains is useful on web and desktop too (Pin, Customize, `navigator.share`, input types, find-in-chat, which is local-only search and so exactly the E2EE model, the calls toast, revoked-device sign-out).
      - **LIME-80 stays as written.**
    - **The Apple Developer account comes next month (user, 2026-10-05).**
      - A free Apple ID in Xcode can likely install a test build on the user's own iPhones (it expires after 7 days), which may be enough for the Bluetooth spike. Unconfirmed.
      - Still unknown: whether the user has Xcode and two iPhones.
      - Meanwhile, plot's E2EE/keys/mesh design pass needs no account.
  - **E2EE rewrites parts of `docs/api.md`:**
    - op payloads for messages become ciphertext;
    - the server can't validate content or search;
    - every device needs its own keys (Linked Devices becomes key verification);
    - push previews are decrypted on the device.

    This needs a plot design pass **before** the Supabase backend.
  - **"Connect all teachers"** means discovery at scale (usernames, directory, large groups). Megolm suits large groups. The directory and E2EE pull against each other (who can find whom); decide in the design pass.
- **Revised order:**
  1. The 86 review, then LIME-85.
  2. Plot design pass: E2EE + keys + devices + mesh, written into `docs/`.
  3. Bluetooth spike on 2 real iPhones (needs Xcode, an Apple developer account, 2 iPhones; open, backgrounded and locked).
  4. Supabase backend with E2EE.
  5. The shared Rust core (vodozemac + op/sync).
  6. The iOS app, to TestFlight.
  7. The Android app.

  Desktop/web v2 runs alongside.
- **Superseded proposed order (kept for history):**
  1. Answer the open/closed question.
  2. Bluetooth spike (2 iPhones, foreground and background).
  3. Supabase backend.
  4. Capacitor iOS shell plus durable storage and push, to TestFlight.
  5. Android from the same shell.

  Desktop v2 can run alongside.

### Session lessons (2026-10-05; also in Patterns learned)
- **Never write personal data into `PLOT.md`.** Plot did it once (test-account phones and emails), which forced a history rewrite. The emails are now intentionally public demo emails; **phones and passwords** stay in gitignored files only.
- **Tiered verification** (the user's decision): quick checks per brief, the full matrix once per chain.
- **"Visible" means hit-testable** in UI tests (`elementFromPoint`), not just bounds.
- **Insecure LAN origins** lack `crypto.randomUUID` and `crypto.subtle`; test on the LAN IP (`LIME_TEST_ORIGIN=lan`).
- **The user designs in Penpot and exports to `docs/design/`:** use these as the spec; mock-first beats the build-and-QA loop.
- **The user pastes tend prompts here by mistake sometimes:** say so plainly and point to tend's window.

---

## (Previous) session-end note (plot, 2026-09-29, SUPERSEDED by the note above)

**History only.** The history below it is kept for reference. Anything above the "Continuation note (2026-09-27)" heading supersedes older queue lines.

### Where things stand
- **HEAD is `378c82c`** (LIME-52-fix2). The tree is clean apart from `PLOT.md` (plot's own) and untracked assets that are **deliberately uncommitted**: `public/assets/teacher.{mp4,ogg,webm}` (for LIME-48) and `public/assets/patterns/` (the user's 6 samples, committed by LIME-52-fix4).
- **Tend was sent LIME-52-fix3, then 52-fix4, then LIME-49** as one instruction at session end. **Check `git log` first** to see how far it got. Don't assume.
- **Gate checks the user may still owe** (ask briefly, then move on): LIME-50, 51, 50-fix, 52, 52-fix and 52-fix2. The user said "everything else looks good" after 52-fix2, apart from the uploads.
- **LIME-50's two open questions are answered:** keep the header palette shortcut, and the darker muted text is fine (the user approved both in the prompt plot drafted).

### The authoritative queue
1. ~~**LIME-52-fix3**~~ **landed as `c646917`.** Root cause: the upload input was re-rendered away while the OS file dialog was open. The gate check is pending.
2. ~~LIME-52-fix4~~ **SUPERSEDED (never sent), the user, 2026-09-30:** "get rid of the subtle patterns and the credit and let's just refine the ones we have now instead and the upload." Drop the 6 samples in `public/assets/patterns/` (untracked; delete them) and every credit line. Keep the 4 generated SVG presets (dots, grid, diagonal, noise) and refine them and the upload. **LIME-52-fix5 was investigated with no code change** (`4ad3566`, 2026-09-30; `PLOT.md` committed as `cc910fd`). Tend drove the **real installed Firefox (157.0)** through the real file dialog: both surfaces, `file://` and localhost, strict privacy settings, and chat attachments. **Everything passed; it couldn't reproduce the failure.** The likely cause is something in the user's own Firefox profile (an extension, broken site storage, or stale cached code). **Waiting on the user:** the console errors (⌥⌘K) during an upload, and a retry in Firefox's Troubleshoot Mode (extensions off). If it works in Troubleshoot Mode, it's an extension and no brief is needed. If the console shows an error, draft **LIME-52-fix6** from it. **→ PARKED by the user 2026-09-30** (see "PARKED: pattern upload fails" above). **LIME-53 DROPPED 2026-09-30; next is LIME-54 (delete the samples and the probing code), then LIME-49.** (Old plan, for history: then LIME-53 (a pattern lab of 12 in-house SVG candidates outside the repo; the user picks by number; drafted) **→ LIME-53b** (integrate the picks, remove the file-name probing, delete the samples, strip the credit mentions; drafted after the picks).)
3. ~~LIME-54~~ **landed as `5c138b0`** (samples and tile probing removed; `PLOT.md` committed as `c254323`). ~~LIME-49~~ **landed as `912240a`** (2026-09-30): the modal body moved to normal flow so it grows to its content; one shared avatar helper everywhere; photo upload verified in the real Firefox 157 and Chrome, and it does **not** hit the parked Firefox bug. **The user's gate check on 49 found a bug:** replying to your own message stacks copies of your photo on its avatar. **LIME-49-fix is drafted and runs next.** (LIME-33 ran first, because the user sent its prompt before 49-fix was drafted.)
4. ~~LIME-33~~ **landed as `a398ca3`** (2026-09-30; `PLOT.md` committed as `ac77bd1`): PBKDF2 local accounts, the `lime-auth-v1` store, `createProfile` with a synchronous flush (a 100ms debounced save could lose a new account on redirect), and `seedVersion` now keeps snapshots that hold local profiles. Verified in the real Firefox 157 and Chrome 154. **The user's gate check FAILED (2026-09-30):** in their Firefox, sign-up bounces straight back to sign-in and the account is gone. Probably the same root cause as the parked upload bug (their Firefox profile won't keep local storage). **LIME-33-fix landed as `769c268`; LIME-49-fix landed as `9cd68d2`** (2026-09-30). **Cause:** Firefox's default `security.fileuri.strict_origin_policy` gives **every `file://` page its own separate `localStorage`**, so `signup.html`, `login.html` and `index.html` can't share accounts or the session. It can't be fixed in the app, so there's now a plain message plus the seed-password hint. It works over `http://localhost` (a server from the repo root) and in Chrome. Tend also found that `puppeteer-core` silently writes a `user.js` into any Firefox profile it launches (turning that pref **off**), which hides this bug. **It does NOT explain the parked upload bug** (that's within one page). **PREVIEW CHANGE:** from now on, every gate uses `http://localhost:8000/public/…` with `python3 -m http.server 8000` started in the repo root, **not** `file://` (this supersedes the older Patterns-learned note). The demo password for seed teachers is in the gitignored `public/js/demo-config.local.js`. **The user's gate checks on both are pending.**
5. ~~LIME-48~~ **landed as `3ac4b6d`** (2026-09-30; `PLOT.md` committed as `d9d2fc5`): one `auth.html` (email-first), `login.html`/`signup.html` redirect with the query string kept, the video as `auth-hero.webm` plus a 360×640 `auth-hero.mp4` (2.5 MB) and a poster. The 18.9 MB original and the `.ogg` are deleted. The page is fixed at 100vh (the portrait video had stretched it to 1396px). **The user's gate check:** they refined the page in the Inspector (bigger logo, smaller bold headline with a full stop, tighter spacing) and said to use plot's judgement from their screenshot. **LIME-48-fix landed as `8890a6b`** (the user signed in on it successfully, 2026-09-30). **LIME-29 was in progress in tend** at that point (uncommitted `lime.css`, `index.html`, `app.js`, `store.js`). **Don't touch the tree until tend reports.** **LIME-29 landed as `629bcff`** (2026-09-30): the picker, plus two fixes: blank picker avatars, and a **data-loss race** (a 100ms debounced save lost to sign-out's navigation; `LimeStore.flush()` now runs before `signOut`). It only showed in the real Firefox and Chrome. **The milestone (sign up → sign in → find a teacher → message them) is built; the user's gate check is pending.** **LIME-55 landed as `0f504fb`**; the user's check led to **LIME-55-fix** (Add goes lime, nav states neutral, split-button hover). **LIME-27 was in progress in tend** at that point (uncommitted `store.js`). **LIME-27 landed as `a843683`** (Share popover, deep links, toasts; **the user's gate check is pending**). **LIME-55-fix landed as `18170d9`** (shared `--lime-primary-*` tokens for Send and Add; neutral nav). **Open:** on the Lemon tone, primary-button hover text is 4.43:1 (it predates this: Send has always had it). Plot's lean: switch the primary buttons' icon and text to full ink, as a one-line follow-up, or fold it into the cleanup brief. Asked the user. Next: the user's checks of 27 and 55-fix, then the **Communities decision surface** (plot's own work, no tend). (Old queue line: LIME-27 → LIME-55-fix → then the **Communities decision surface** (LIME-28).
6. **LIME-29**: New message (search by name, email, phone or school; "Invite (Soon)"; the documented invites design)
7. **LIME-27 (revised)**: the Share header button and a Claude-style popover (add people by email for groups; who has access; Copy link), deep links, toasts
8. **LIME-28 Communities: DEFERRED (the user, 2026-10-02) until direct and group messaging land on mobile.** Previously: BLOCKED on a planning pass. Present a **decision surface** from the user's mockups (the discovery cards, the feed of posts with likes, community pages with channels) before briefing.

Items 4–6 complete the user's milestone: sign up → sign in → find a teacher → message them.

### Waiting on the user
- ~~The pattern credit source~~ **Answered 2026-09-29: Subtle Patterns, credit it.** Folded into LIME-52-fix4.
- **The LIME-52-fix3 gate check** (landed as `c646917`, 2026-09-29). Tend couldn't test 16-bit, palette or interlaced PNGs, or a real private window (it simulated one by forcing IndexedDB to fail).
- Optionally, the failing PNGs that tend should test (a Desktop folder path).
- Communities planning answers, when LIME-28 comes up.

### PARKED: pattern upload fails in the user's Firefox (the user, 2026-09-30)
"upload pattern still not fully working on firefox, but is on chrome, let's make note and move on we can come back to it after all the major parts are done."
- **Where it stands:** LIME-52-fix3 (`c646917`) fixed the input being re-rendered away. LIME-52-fix5 (`4ad3566`, investigation only) **couldn't reproduce** the failure in the real installed Firefox 157 (both surfaces, `file://` and localhost, strict privacy, chat attachments all passed). It works in the user's Chrome.
- **New clue (plot, 2026-09-30):** the user's LIME-49 gate screenshot shows a **round blue icon button inside the Reply composer** that isn't Lime's. It's almost certainly a Firefox add-on injecting into text fields (a writing, translation or accessibility tool). That makes an add-on the leading suspect. **When this resumes, first retry with that add-on disabled** (or in Troubleshoot Mode).
- **Unchecked:** the user hasn't yet reported the console errors (⌥⌘K) or a Troubleshoot Mode (add-ons off) retry. **Start there when this comes back.** An add-on or a broken site-storage area in the user's profile is the leading suspect.
- **When to return:** after the major parts are done (the milestone: LIME-49, 33, 48, 29, 27 and Communities). Don't re-raise it before then.

### Open decision: brand palette vs the 8 canvas tones, and lime-shaped avatars (raised 2026-09-30, decision surface sent)
- **The user's brand palette:** ink `#131b17` (= `--seed-soil-925`/`--seed-lime-950`, Lime's ink), green `#09a950` (= `--seed-lime-500`, primary buttons), light green `#a3e18a` (= `--seed-lime-300`, the pressed step), pale lime `#e4f9be` (= `--seed-lime-100`, `--lime-primary-bg`), warm light `#f0eee6` (**not used anywhere yet**; the warm ramp's step 100 is `#E8E4DB`), and off-white `#f9f8f4` (= Warm's canvas). **The brand is already wired in, apart from `#f0eee6`.**
- **Plot's read of the 8 tones** (from hex values, not measured):
  - **Warm** is the brand's off-white; keep it as the default.
  - **Warm cream** `#FDF8F0` is a near-duplicate of Warm.
  - **Pure white** and **Cool gray** are neutral and fine.
  - **Blue tint** `#F0F4F8` is cool and clinical next to a warm green brand.
  - **Lemon** `#FBF3D0` is citrus and on-brand.
  - **Sage** `#D8E6D0` is green on green: the pale-lime Add/Send button likely blends in. Measure it.
  - **Lilac** `#F1ECF6` is the complement of green, so it makes the lime pop, even though it isn't in the brand family.
- **Options sent:**
  - **A.** Keep all 8; align Warm's surface layer to `#f0eee6`.
  - **B (plot's lean).** A curated "citrus" set of 7: Warm (default, surfaces aligned to `#f0eee6`), Pure white, Cool gray, Lemon, Lilac; retune Sage greyer so lime stands out; replace Blue tint with a pale grapefruit/peach (~`#FBEEE6`); drop Warm cream. Each tone is verified so the primary lime reads as distinct and all text contrast holds.
  - **C.** Cut to 4 (Warm, Pure white, Lemon, Lilac).
- **Lime-shaped shapes (`public/assets/Logomark-outline.svg`, untracked):** a hand-drawn, slightly wobbly circle with a small nub at the lower left, which works as a CSS `mask-image` at any size. **Options sent:**
  - **A (plot's lean).** Avatars **≥ 28px** use the lime silhouette; smaller avatars (clusters, reply rows, the rail) stay circles, because the nub is only 1–2px there and reads as a glitch. Icon hovers stay as they are. The presence dot sits bottom-right, so it doesn't conflict with the nub.
  - **B.** Everything round becomes a lime: noisy, with small-size artefacts and stacked-avatar rings needing mask-based borders.
  - **C.** Signature moments only (profile and details avatars, empty states, a lime-slice loading spinner); list avatars unchanged.
  - Either way, prototype at 20/24/32/40/64px in light and dark before calling it done.
- **DECIDED (the user, 2026-09-30): palette "B", then revised to "keep all 8"**, so: **no tones dropped or replaced**, only B's refinements to existing tones (Warm's surfaces → `#f0eee6`, Sage retuned so lime stands out, and every tone verified). **Shape "A":** lime-silhouette avatars at ≥ 28px. Briefs: **LIME-56** (palette) and **LIME-57** (lime avatars, a preview stop first).
- **Landed (2026-09-30):** LIME-48-fix2 `c88bcfc` (the new video); **LIME-56 `c7f5009`** (Warm surface `#f0eee6`, Sage greyer, Add/Send ink now a theme-aware token; a dark-mode 1.03:1 regression was caught and fixed). **LIME-57 Phase 1:** the preview is done and `lime-silhouette.svg` is extracted (untracked). Plot looked at it: the nub reads as a **speech-bubble tail** at 40px and up (a nice fit for a messaging app), and it's barely visible at 28–32px, where it's harmless. Plot's lean is to keep 28px. **The user confirmed 28px. Landed (2026-09-30):** LIME-57 `5a17cbb` (no 28–31px avatars exist, so in practice md/lg/xl = 32/40/56px are shaped and sm/xs stay round; `border-radius: 0` is needed, or the circle clip eats the nub; the unread ring is now a `.lime-avatar-ring` wrapper, because box-shadow on a masked element is invisible), LIME-58 `f578558`, LIME-59 `6db2847` (a hand-drawn Share SVG; bubbles = list hover through one token). **The user's gate checks on 56–59 are pending.** `Logomark-outline.svg` and `signin-teachers.mp4` are still untracked. Ask whether to commit the logomark as a brand asset. **The user's check found the Recent row's presence dots clipped** (the ring wrapper is an always-masked ancestor), so LIME-57-fix was drafted. The user then asked for Slack-style status icons in a cut-out notch, so **LIME-57-fixb (which supersedes it) runs next.** **LIME-57-fixb landed as `81a759d`** (2026-09-30): a `mask-composite` notch, SVG states, and the ring as a layer behind the avatar, verified in the real Firefox and Chrome plus the fallback. Tend's lesson: element-clipped screenshots in Firefox can hide mask effects; confirm with a full-page shot. **The user's gate check FAILED:** the icons shrank (LIME-59 normalised down; the left toggle is the right size), and the status icons have a halo and are too small. **LIME-59-fix and LIME-57-fixc are drafted and run next.** **Landed (2026-09-30):** LIME-59-fix `2db344f` (icons match the left toggle) and **LIME-57-fixc `d50d85a`** (four pre-composited notched SVG masks; `mask-composite` now appears only in comments, which plot verified; the path Z). **The user's check ("closer")** asked for a bigger Z and a tighter notch (**LIME-57-fixd**), the ↵ smaller again, a split mic button like Add, and the reply composer's clipped mic hover fixed (**LIME-60**). Both are drafted. **Landed:** LIME-57-fixd `167f3ee` and LIME-60 `9d09dd4` (2026-09-30). The user's check of 60 asked for the container outline → **LIME-60-fix drafted → landed as `55baa1b`**; then LIME-60-fix2 (outline on hover only) **landed as `fec746e`** (2026-09-30; the user's check is pending). **LIME-61 landed as `c045fca`** (all 12 primary CTAs use pale lime; on elevated surfaces in Lemon and Sage they get a thin lime-300 border; the user's check is pending). **Next: LIME-57-fixe** (the Montserrat Bold z). **LIME-57-fixe landed as `44e9db1`** (the real Montserrat Bold "z" outline, extracted from the font with fontTools; Montserrat is OFL, so artwork use is fine; lg ≈ 6.0px; the user's check is pending). **LIME-57-fixf landed as `f82d402`** (the z is smaller and clear of the circle). **The user's QA round (2026-09-30) → LIME-62** (the media viewer) **and LIME-63** (list radius, Share as a dropdown, composer fade, reply mic) **are drafted and run next.** **Landed (2026-10-01):** LIME-62 `23a7c5d`, LIME-63 `5d93386`, and LIME-64 `4e7b942` (the back arrow in the panel header row). **The user's gate checks on 57-fixf and 61–64 are pending.** Then: the Communities decision surface. Then: the Communities decision surface.
- **New finding (tend, LIME-56): white text on the solid green `#09a950` buttons** (e.g. "Continue with email", Seed's `seed-button--primary`) is **under 4.5:1 on every tone** (white on `#09a950` ≈ 3.1:1, computed). It's a brand-level decision. Options put to the user: **A.** ink text `#131b17` on `#09a950` (≈ 5.7:1, computed; keeps the brand green); **B.** darker green `#078040` (`--seed-lime-600`) with white text (≈ 5.0:1, computed); **C.** leave it (large or bold text only needs 3:1, and a 16px semibold button label doesn't qualify). Plot's lean: **A.** Upstream candidate for Seed too. **DECIDED: A (the user, 2026-09-30) → LIME-58 drafted.** Its hover and press go lighter (lime-400/300), because ink on the darker lime-600 is only ≈ 3.5:1.

### Open decision: real two-person testing (raised 2026-10-01, decision surface sent)
- **The user (screenshot: two Firefox windows, one a private window, signed in as Shem and Jean):** each sees only their own changes. "Before Communities, how do we make this function so we can actually test Link (communicate), from the messages to the profile changes?"
- **Why (plot's survey):**
  - all data lives in **one browser's storage** (`lime-state-v1` snapshot in `localStorage`, attachments in IndexedDB), so a private window or another browser is a separate world;
  - **the session is in `localStorage` too** (`lime-demo-session`, `auth.js` ~13), so two tabs in the same browser are always the **same** user;
  - there's **no cross-tab sync** (no `storage` listener or BroadcastChannel);
  - saves write the **whole snapshot** (`store.js` `scheduleSave`), so two writers would overwrite each other (last write wins: lost messages).
- **Options sent:**
  - **A. Two tabs, one browser, live (plot's lean for now):**
    - the session moves to `sessionStorage` (per tab), so each tab can be a different user;
    - a `storage` event / BroadcastChannel makes every other tab reload state and re-render live (messages, lists, unread, profile, members);
    - saves become **merge-by-id** (re-read, then merge; messages append-only), so nothing gets overwritten.
    - *Pro:* about one brief, no server, testable today; it also stress-tests the store's change events. *Con:* the same browser profile on one computer only (not a private window, another browser, or a phone).
  - **B. A small local dev server** (Node, no dependencies) holding shared state, plus a `ServerAdapter` behind the existing store seam, with live updates (SSE).
    - *Pro:* works across browsers, private windows and phones on the same Wi-Fi; it rehearses a real network seam. *Con:* 2–3 briefs, and a stepping stone that the real backend later replaces.
  - **C. The real backend (Supabase, per `docs/schema.sql` and the switch checklist):** real auth, Postgres, RLS, realtime and storage.
    - *Pro:* the actual path to launch. *Con:* needs a Supabase project and keys, network, RLS testing, and **a sync-architecture decision first**, because the offline Bluetooth differentiator ([[lime-offline-differentiator]]) argues for local-first sync, so choosing it deserves its own planning pass.
  - **LIME-71 landed as `46dffb8`; plot reviewed it and APPROVED it with amendments** (see "Plot's review of LIME-71" in Drafted briefs). The user decided: **show the written time** (with "delivered" when it's more than 5 minutes later); **email visible to chat-mates only, phone never displayed, exact-match search only.** Next: **LIME-72** (a committed test harness) → **LIME-73** (the dev server plus contract amendments) → **LIME-74** (the web `ApiAdapter`; drafted after 73). **Landed 2026-10-01: LIME-72 `8b2e33b`** (`tests/`, puppeteer-core; run with `cd tests && npm install && npm test`) **and LIME-73 `fc16919`** (the dev server; 86 API checks; minimal presence; a single-page snapshot; no password endpoint yet). Tend's security note: the server exposes `demo-config.local.js` on the LAN; **LIME-74 Phase 0 fixes it with an allow-list.** **LIME-74 is drafted.** **LIME-74 landed as `b3f0803`** (2026-10-01): the `ApiAdapter`, outbox, SSE, the allow-list, `POST /auth/password`, and the test accounts in a gitignored file; tend also added a dev-only `POST /auth/lookup`; 46 e2e checks across three browsers. **The user's gate check is pending** (phone and a true private window). **LIME-74-redact DONE (2026-10-01, recorded in `af064f3`):** history rewritten (`filter-branch` over `PLOT.md` only; hashes changed: the old `34cf2a9` → `7450e93`, the old `d6b1785` → `b3f0803`; references in this file updated). 0/4 strings anywhere in history, backup refs and reflog pruned, nothing pushed. **Pushing is now safe from this issue; when to push is the user's call.**
  - **LIME-69 landed as `3bb437b`** (2026-10-01): per-tab sessions, merge-on-save, `storage`-event live sync (~130–150ms), reactions with a `removed_at` tombstone, memberships with `updated_at`, and read-on-visible. Limits: a simultaneous duplicate DM (now required in LIME-71's rules), a Reset racing an unsaved write (not hand-reachable), and a pre-existing Firefox `SecurityError` on sign-out with two tabs (cleanup candidate). **Tend's jsdom suites lived in a scratchpad and are gone** (cleanup candidate: commit a test harness). **The user's gate check is pending.**
  - **DECIDED (the user, 2026-10-01): "A, then B".** LIME-69 (A) and LIME-70 (B) are drafted. **Then the user added: plan the infrastructure for iOS and Android apps soon**, so B became **LIME-71** (the API and sync contract: an op log, token auth, a changes feed, files by id, realtime, push and mesh notes; docs only, plot reviews it) **then LIME-72** (the dev server plus web `ApiAdapter` implementing it). LIME-70 is superseded. C (the real backend plus local-first sync) stays a later planning pass.
  - **Plot's recommendation:** **A now** (test two-person messaging today), then a **planning pass for C** (backend plus local-first sync) as the next milestone, before or alongside Communities.

### Open thread: environments and release stages (raised by the user 2026-10-01; plot's proposal sent)
- **The user:** treat the current setup as "staging" while we're in alpha; Supabase would be "production" (beta); sharing with real teachers would be "early access"; "then we can try without fear of breaking things that would impact real teachers."
- **Plot's view:** the instinct is right (protect real teachers), but it mixes two separate ideas. **Keep them separate:**
  - **Environments (where the code runs):**
    - **Local:** the Mac, today's setup plus the LIME-73 dev server; demo data; reset anytime; break freely.
    - **Staging:** a hosted copy built **exactly like production** (its own Supabase project); fake or test data; every change is tried here first; trusted testers.
    - **Production:** its own Supabase project; real teachers' data; only changes that passed staging.
    - **Key point:** the local dev server is *not* staging. Staging must mirror production's real infrastructure, or it can't catch production problems. **When we move to Supabase, create two projects (staging and production) from day one.**
  - **Release stages (who is using production):**
    - **Alpha** (now): the user and close collaborators, local or staging only, no real data.
    - **Early access / beta** (one public label is enough): invited real teachers on production.
    - **Launch:** open sign-up.
- **What it implies (to plan, not build yet):**
  - an environment config (API URL and keys per environment, in gitignored `*.local.js`; the contract already allows it);
  - a small **environment badge** in non-production builds ("Local" / "Staging") so nobody confuses them;
  - **Reset demo data and seed data in local and staging only** (already dev-only in `docs/api.md`);
  - **versioned database migrations and backups** from the first real teacher onward;
  - **before early access:** a privacy policy and terms, and a review of student-data rules (FERPA, COPPA), since teachers may mention students (the app already warns them);
  - feature flags for early-access features (later).
- **DECIDED (the user, 2026-10-01): the framework is agreed. The environment badge is CUT.** The URL is the distinction (e.g. `localhost` for local, a `staging.` subdomain, and the production domain). Don't propose a badge again. Environment config (the API URL and keys per environment) still applies when the app talks to a hosted backend. The Supabase staging/production split belongs in the backend planning pass (option C).

### Open decision: the mobile shell (raised by the user 2026-10-01; plot's proposal sent)
- **The user's mobile QA (iPhone, LAN URL):**
  - you can't get **back from a chat to the messages list**;
  - the **breadcrumbs are illegible** ("M… / Sh…");
  - **bubbles and the location card overflow** on the right;
  - the **composer gets cut off**;
  - the **paint-brush** button should move into the "⋯" menu on mobile.
- **The user's questions:**
  - (1) on mobile, should the nav become a **bottom dock** (like WhatsApp: Updates, Calls, Communities, Chats, You), freeing the top left and right for navigation, like Messages and WhatsApp?
  - (2) can we use **native device elements** (dropdowns etc.)?
- **Plot's proposal:**
  - **(1) Yes, a bottom dock on phones** (≤ 767px). The current hamburger/push drawer was designed in LIME-12; this **supersedes the mobile drawer decision** recorded in the README ("Decisions 2026-09-23"). Plot needs the user's explicit OK, since it reverses a logged decision.
    - **Dock items:** Link (chats), Communities, Notifications (with a badge), and You (profile and settings). **Jam isn't in it until it exists.**
    - **The "+ Add" action** goes to the **top right** of the Chats screen, like WhatsApp's "+".
    - **Screens stack like native apps:** the chat list is a full screen; tapping a chat pushes the chat screen, with **"‹" back at the top left** and the **title** (avatar, name, a member count you can tap for details) in the centre, plus Share and "⋯" at the top right. The **paint brush moves into "⋯"**.
    - **No breadcrumbs on phones:** the back button plus the title replace them. That fixes "illegible breadcrumbs" by design.
    - The thread and details panels push as full screens with "‹" back.
  - **(2) Native where the web allows it:**
    - **`navigator.share`** (the native share sheet) for Share / Copy link on phones;
    - a **native `<select>`** for simple pickers (the microphone list, timezone);
    - **native input types** (email, tel and search keyboards; `enterkeyhint="send"` on the composer, so the keyboard's return key says "Send");
    - native file and photo pickers (already).
    - **Action menus** ("⋯", the title menu) have no native web equivalent, so on phones they become **bottom sheets** in Lime's style (like the iOS action sheet).
    - **Haptics** (`navigator.vibrate`) work on Android only. Skip them.
  - **The layout bugs** (overflowing bubbles, the composer, the toast covering the header, the toolbar expanding when the keyboard opens) are fixed inside the same pass, measured at 390×844.
  - **Steward point:** this is a big visual change, so plot proposes **one design brief first**: a static mock page of the 3 phone screens (the chat list with the dock, a chat, a bottom sheet) for the user to approve, then two or three build briefs. That avoids the build-and-QA loop.
- **DECIDED (the user, 2026-10-01):**
  - **(1) "ok with dock"**: the bottom dock on phones; **this supersedes the README's 2026-09-23 mobile drawer decision** (the build brief updates the README);
  - **(2) "native when allowed"**;
  - **(3) mock first: "sounds good"** → **LIME-77** (a static mock) is drafted.
  - The test accounts' password works.

### Open decision: desktop v2 from the mobile design (raised by the user 2026-10-04; plot's brainstorm sent)
- **The user:** "I made some significant changes on mobile that I think desktop can benefit from greatly. All the primary components could be shareable (chat bubbles, searching, reply, avatars, menu icon buttons, etc.). Let's brainstorm how we could simplify and level up the desktop based on the updates I made on mobile."
- **Plot's brainstorm (sent):**
  - **Approach options:**
    - **A. "Same app, wider" (plot's lean):** desktop = the mobile screens arranged as panes (**list | chat | details/thread**), built from **one shared component set**; components respond to their **container** (container queries), not the viewport. One rendering path means fewer desktop/mobile divergence bugs (many recent bugs were exactly that).
    - **B.** Keep today's desktop structure and only reskin it with the shared components (incremental; leaves two layouts to maintain).
    - **C.** A minimal desktop; focus on the native apps.
  - **Proposals under A:**
    - (1) **The left sidebar becomes a slim vertical "dock" rail:** link · jam · call, with your avatar at the bottom (Settings) and the logo at the top. The Notifications bell, the Add split button, the Communities tab and the nav Search go away, since their jobs move into the list.
    - (2) **The list pane = the mobile Messages screen:** search plus All/Unread chips and filter, pinned-first rows, badges, pastel avatars, and a "+" in the pane's header (or a FAB at the pane's bottom). No Recent row, sections or breadcrumbs.
    - (3) **The chat pane = the mobile chat:**
      - floating glass header pills (members pill; search · call · ⋯);
      - own-right green bubbles; the under-bubble row;
      - **a readable centred column (~720px max)**;
      - the v2 glass composer floating at the bottom.
    - (4) **The details and thread pane:** the same Members, Person and Thread screens, as a docked third pane (wide screens) or a glass side sheet (medium).
    - (5) **Desktop-native interactions on the shared menus:** **hover shows a small glass action bar** (quick reactions, reply, ⋯), **right-click opens the same context menu as long-press**, plus keyboard shortcuts (⌘K search, ↑/↓ chats, Esc closes panes, ⌘Enter, …), drag-and-drop files, and hover states.
    - (6) **Settings** = the mobile Settings and Profile (a centred glass sheet, the same rows: Account, Linked Devices, Donate, Customize, Username, About). The old modal is retired.
    - (7) **One responsive set of breakpoints:** phone (one pane), tablet (list plus chat, details as a sheet), desktop (three panes).
  - **The recommended sequence:**
    - (a) **The user designs 2–3 desktop frames in Penpot** with the mobile components (the three-pane chat, Settings, hover/right-click), exported to `docs/design/desktop/`;
    - (b) **meanwhile tend does the invisible groundwork:** a **shared-component refactor** (component CSS keyed to container queries, with shared render functions for row, bubble, composer, header pills, menu, sheet, avatar, badge and toast), with **no visual change on either size** (proved by the tests and screenshot diffs);
    - (c) then desktop v2 build briefs against the designs.
- **Waiting for:** the user's pick (A, B or C), whether they'll design the desktop frames, and an OK for the groundwork refactor brief.
- **DECIDED (the user, 2026-10-04):**
  - **A** ("same app, wider");
  - **the user designs the desktop frames** in Penpot → `docs/design/desktop/`;
  - **the groundwork refactor is OK**, after LIME-82 to 84 → **LIME-85** is drafted.
  - **The user's first desktop frame (2026-10-04, shared in chat; not yet saved to `docs/design/desktop/`).** Plot's reading:
    - **Two panes, no separate nav rail.**
    - **The left pane is the mobile Messages screen exactly:** the logo top left; the search + avatar pill; All/Unread chips plus filter; the rows; **the FAB "+" and the 3-item dock (link · jam · call) at the bottom of the list pane**.
      - **This replaces plot's "vertical rail" idea:** the dock stays a horizontal pill inside the list pane.
    - **The right pane is the mobile chat, wide:**
      - **a members pill at the top left showing more names** ("Jean, Rise, Journey, Autumn, Sage, Ember, Mary…") plus "13 members", with **no back button**;
      - the right glass pill: search · call · ⋯;
      - **others' messages at the pane's left edge, your own at its right edge** (full pane width; **not** the centred 720px column plot proposed);
      - the composer spans the pane (shown expanded with the v2 toolbar).
    - **The details/thread pane isn't shown yet** (presumably it slides in). The user is to add frames for Settings, hover and right-click, and details/thread.
  - **The user's feedback on LIME-82 and 83 (2026-10-04): "looking good, I tried it out and it works smoothly."** LIME-82 `1d131e1` and LIME-83 `96b7372` landed; LIME-84 was in progress (uncommitted).
  - **LIME-84 landed as `4057474`** (2026-10-05, pushed; the full matrix passed before the push: mobile 504, api 117). Open items:
    - (a) the desktop UI for usernames and Linked Devices (unbriefed; it goes into desktop v2);
    - (b) **design 06 shows a first name on the Name row; ours shows the full display name.** Ask the user;
    - (c) a revoked device only notices on its next request. Candidate: the server sends a `{type:'revoked'}` realtime message before closing, and the client signs out at once (fold it into LIME-80).
    - **The user's iPhone review of LIME-84 is pending.**
  - **The order (updated 2026-10-05):** LIME-82, 83, 84 → **LIME-86 (QA round 3)** → **LIME-85 (the shared components; no visual change)** → LIME-80, 81 (built on the shared parts) → the desktop v2 briefs (after the user's frames).

### Unbriefed candidates (offer when the queue thins)
- **Swipe actions** (the user, 2026-10-05, "we can add these later"): on list rows, **swipe left for read/unread** and **swipe right for pin or delete** (the native mail/messaging pattern). Horizontal gestures are otherwise disabled (LIME-86 item 2).
- **A mobile layout pass** (seen in the user's iPhone screenshots of the LAN URL, 2026-10-01):
  - the top-centre toast covers the header and list;
  - the composer box is narrower than the screen and offset, and the bubble or location card is cut off on the right;
  - the header is crowded (truncated crumbs plus four icons);
  - the composer toolbar is expanded when the keyboard opens.
  Offer it after LIME-74 as a focused mobile QA brief (measured at 390×844).
- **A committed test harness** (2026-10-01: tend's jsdom and Playwright suites lived in session scratchpads and were lost between sessions, so LIME-69 couldn't re-run them). Add `tests/` with a `package.json` (devDependencies: jsdom, playwright), the smoke test (the real `index.html` and `auth.html` load with zero errors), and the key regression suites (auth, live sync / no lost writes, toasts), runnable with one command. Fold it into the cleanup brief, or make it its own brief before LIME-72.
- **Firefox `SecurityError` on sign-out with a second tab open** (pre-existing; seen in LIME-69). Investigate in the cleanup brief.
- **A CSS guard script** (the `*/`-inside-a-comment truncation hit a **second** time in LIME-61, 2026-09-30): a small Node script in the repo (e.g. `scripts/check-css.mjs`, no dependencies) that parses every `public/css/*.css` file, fails if any comment body contains `*/` or a `/*` nesting, and prints each file's rule count against an expected minimum. Tend runs it before every CSS commit. Fold it into the cleanup brief.
- **Accessibility: `aria-expanded` is never updated by `wireDropdownToggle`** (found by tend in LIME-60-fix2, 2026-09-30). Every dropdown trigger's `aria-expanded` stays at its markup value, so screen readers never hear "expanded". Fix it centrally in `wireDropdownToggle` (set it on open and close, including outside-click and Escape), then audit the triggers. Fold it into the cleanup brief.
- **"Forgot password?" on `auth.html`** (raised 2026-09-30: the user got confused between their own password and the seed demo password, and between `file://` and localhost accounts). Locally: reset a local account's password after confirming the email (demo-grade). Production: Supabase `resetPasswordForEmail`. Also consider showing on the password step which kind of account it is ("Demo teacher: use the shared demo password").
- **Real notifications** (the bell is a mockup; the user wants these instead of ✓/✓✓).
- **A cleanup brief:** a global border-box reset, `[hidden] { display: none !important }`, the dead `.lime-message__file` block, the unused Seed `dropdown.css` link, and the placeholder "Jean Chung" HTML.
- **The right panel is unreachable at 768–1024px.**
- The mobile duplicate "Thread" heading.
- "Leave group" for non-owners.
- A `STATUS.md` refresh.
- **Mobile/offline Bluetooth planning:** the product differentiator, which needs its own decision surface.

### Steward: one assumption to question next session
**Plot has been drafting one brief per QA screenshot, and the appearance work alone took 8 briefs (45 → 52-fix4).** Before the next visual feature, propose a short **design pass first** (a decision surface with 2–3 options and mock descriptions) rather than build, QA, rebuild. That's cheaper in the user's usage limits, which the user mentions often.

### Session lessons (also in Patterns learned)
- **Prompt wording:** "implement …, commit, and stop for my check" (never "re-read it, then stop").
- **Plot must `assert` anchors when editing `PLOT.md` with scripts.** A silent no-op lost two notes this session (since restored).
- **Tend runs `/loop` wakeups** that re-report the same result. Tell the user to stop them, and include "stop any /loop wakeups" in prompts.
- **Measure with Playwright + Firefox;** CSS changes report the browser-parsed rule counts; JS changes load the real app in jsdom.
- **The user pastes tend's output here.** Tend only acts on text typed into *its* window. Say so plainly when the user re-pastes an old message.
- **UPDATED AGAIN (the user, 2026-09-30, LIME-61): every primary button uses the pale lime of Add/↵ (`--lime-primary-*`, lime-100/200/300, ink text).** Solid brand green `#09a950` remains only for the presence "active" dot, the voice/audio play buttons, and the unread ring.
- **UPDATED (the user, 2026-10-05):** **own chat bubbles use `--lime-primary-bg`, the same green as the "+" FAB** (LIME-86 item 18), replacing `--seed-lime-300`.
- **UPDATED AGAIN (the user, 2026-10-03, the mobile design):** **the user's own chat bubbles are light green (`--seed-lime-300`).** Bubble and wallpaper customisation come later.
- **The lime rule (UPDATED by the user, 2026-09-30, LIME-55-fix): lime is for primary actions only** (the "+ Add" button, Send, primary buttons). **Nav items are neutral now** (they match menus and the selected list row). The unread ring and the voice play button stay lime by the user's earlier choice. Everything else stays neutral, and neutral layers derive from the canvas tone (LIME-50-fix).

## Continuation note (2026-09-27)

- **LIME-13 landed as `cd39519`. Gate passed (2026-09-27):** the user checked it at the file:// URL and it looks fine.
- **LIME-14 landed as `c82a2d8`** (with the text/icon contrast amendment). The user's QA raised two older mobile-drawer bugs but said nothing against the colours. Confirm the colour gate explicitly.
- **Landed (2026-09-27):**
  - LIME-15 `b069188`, then LIME-15-fix `fef0c00`, which moved the drawer logo inset to desktop's 24px at the user's request, **reversing LIME-12-fix6's 12px**. Don't re-propose 12px.
  - LIME-16 `77bb100`
  - LIME-17 `573ac40`, then 17-fix `714eaec`
  - LIME-18 `f33f5b8`. It shipped a load-order crash that froze the whole app; 18-fix `759a392` fixed it.
  - 18-fix2 `d7d76bc`, then 18-fix3 `0ad6b26` (the reply composer toolbar is always collapsed; the reply disclaimer reads "Secure & encrypted"). 18-fix3's gate passed, with feedback. 18-fix4 `1334859` fixed the reply composer overflow and clamped dropdowns to the viewport. 18-fix5 `cb6b4bc` was built on a wrong premise: it made the reply composer flush-right and 16px lower. The user likes the lower height, so fix7 is drafted to lower the main composer to match and restore the reply composer's right gap. **Update 2026-09-27:** fix6 `c374d01` and fix7 `462f4ab` landed, and the user confirmed "looks good". Fix7 was measured with headless Chrome. It lowered the main composer by giving `.seed-layout__center` a desktop-only `margin-bottom: -16px` (reset to 0 on mobile); the reply composer's padding is now 12/16/8/16. **Queue now: LIME-20, then LIME-21 (menus).** LIME-19 is still held for the tab-merge answers.
- **Update later on 2026-09-27:**
  - LIME-20 `e9d3783` and 20-fix `71e0bac` passed.
  - **The old LIME-21 *was* executed** (`2db5912`, Seed dropdown styles) before the user redirected. **Plot's LIME-21b note wrongly said it wasn't**, and tend corrected that in `TEND.md`. Lesson: check `git log` before labelling a brief "never executed".
  - LIME-21b `505e0e3` then replaced it with the search-modal pattern. **The user's gate check on 21b is pending**, plus three lime questions tend raised: the Jam "Soon" badge, the unread ring on Recent avatars (`--selected-border-bold-default`), and the voice-message play button (`--selected-bg-bold-default`).
  - Leftover from LIME-21: `index.html` still links Seed's `dropdown.css` (~line 20), but nothing uses `seed-dropdown` any more. Fold its removal into the next cleanup.
  - **Next queue:** the user checks 21b and answers the lime questions → LIME-22 (search close ×) → the LIME-19 redraft (needs the tab-merge answers) → the backlog (disabled/focus states, 768px breakpoint, border-box reset, `STATUS.md`, upstreaming to Seed).
  - `PLOT.md` is still untracked. Gather it at the next clean pause.
- **Update, end of 2026-09-27:**
  - `PLOT.md` committed (`724c6ee`).
  - LIME-22 `e69cf50` (search close ×) landed.
  - LIME-23 `e4c647b` (neutral "Soon" pill) landed; its gate check is pending.
  - The user chose to keep lime on the unread ring and the voice play button.
  - **The queue is empty.** Next: LIME-19 (needs the tab-merge answers), then the backlog.
- **LIME-19b committed as `0b5b3c7`** (and PLOT.md as `5e38b3d`). The user's check raised header and list-count issues, so LIME-19b-fix is drafted. **LIME-19c is ON HOLD, don't send it.** It's superseded by LIME-25 (real starring) in the lifecycle sequence. Queue: 19b-fix → LIME-24a `9e5506f` (reviewed) → LIME-24a-fix `30563a8` (re-reviewed, passed) → LIME-24b `a870c1e` (landed: `data.js` retired, `store.js` + `local-adapter.js`, sender check applied; the reload test used snapshot inspection instead of a real reload because headless `--user-data-dir` hung; the user's gate check is pending) → **LIME-25 drafted (next).** Then, **as the user prioritised: LIME-30 (settings shell, blurred backdrops) → LIME-31 (editable settings)**, then back to lifecycle 26–29. Later settings sections: Notifications and Preferences, plus a dark-mode design pass.
  - **Update (2026-09-28):**
    - LIME-25 `da1dea4`, LIME-30 `b7612b2` and LIME-31 `c6bbbeb` landed.
    - 31 found that Seed's `button.css` was never linked, so every `seed-button` had been rendering unstyled. Fixed.
    - The contract gained `findProfileByEmail` and `setProfileEmail`; `createModal` gained `onBeforeClose`.
    - **LIME-31-fix drafted and runs FIRST** (settings layout feedback). **Then LIME-26 (drafted), then LIME-32 (drafted: the composer toolbar collapses by its own width).** Then 27 (share and toast; **now drafted**)
    - **Update:** LIME-31-fix `1bfb4bb` passed (Profile still scrolls ~106px; plot offered pairing short fields side by side as an optional follow-up, no answer yet). LIME-26 `e90bfd1` landed and its gate check is pending. It also fixed a LIME-31 bug where "Discard changes?" appeared on a clean form. Open product question from the 26 gate: **DMs have Archive but no Delete.** Next: LIME-32 → LIME-27.
    - **Update (2026-09-28 evening):** LIME-32 `8e31b72` landed (a container query at 374px; the reply composer keeps its unconditional collapse); its gate check is pending.
      - Tend found that **the right panel is unreachable at window widths of 768–1024px** (Seed's mobile-reveal was never wired). This is a new open item, not yet briefed.
      - **The user reprioritised:** the milestone "sign up → sign in → find a teacher → message them", with local accounts. **Queue now: LIME-33 (local accounts) → LIME-29 (New message picker) → then LIME-27 (share), LIME-28 (Communities).**
      - **Superseded by the user's "solid place" QA (2026-09-28, later).** **Queue: LIME-34 → 35 → 36 → 37 → 38 (QA fixes), then LIME-33 → 29 (milestone), then 27 (share), 28 (Communities).** The right panel being unreachable at 768–1024px is still an unbriefed open item.
      - LIME-34 `e888cb3` landed: `canReason`, `deleteForMe`, `cleared_at` in the schema, rename in place. Its gate check is pending. Next: LIME-35.
      - LIME-35 `80d36f6` landed: person details, the Members panel, `renderCrumbs`. The title crumb now *closes* the panel (inverted from before). Its gate check is pending. Next: LIME-36.
        - **Still mockups (backlog):** the notifications dropdown (static Jean/Mary/Valene), and the global search modal's "Recent searches". On mobile there's a duplicate "Thread" heading (pre-existing, flagged by tend). The initial breadcrumb and header HTML still say "Jean Chung" as placeholders, overwritten on render. Harmless, but they could be emptied.
      - LIME-36 `60ef871` landed: a dynamic Recent row, unread via `markRead` on select. Its gate check is pending. Next: LIME-37.
        - **Uncommitted drift** (not tend's; very likely the user's own hand edits, their usual pattern):
          - `lime.css` ~2495: `.lime-message__actions` background changed from `--soil-bg-surface` to `--soil-bg-elevated` (the hover action bar becomes white);
          - `store.js` ~230: `canReason` delete text shortened to "Only the group owner can delete." (the Archive hint dropped).
        - Plot asked the user to confirm. If they're theirs, commit them as the user's edits, with a `TEND.md` note.
      - **The user's edits were committed as `3ed7352`.** LIME-37 `f43ee40` landed (the WYSIWYG composer, and a sanitiser plot reviewed and found sound: a `<template>`-inert allow-list, attributes stripped, `javascript:` blocked, applied on send and on render; `<strike>` normalised to `<s>`). There's no `--seed-font-mono` token, so it uses a system monospace stack. **LIME-39 is drafted** for the composer covering the last message (pre-existing). **Queue: LIME-38 → LIME-39 → LIME-33 → LIME-29 → 27 → 28.**
      - LIME-39 `4c824b7` landed: `--composer-clearance` via `ResizeObserver`, pinned-to-bottom on reload and image load, and it no longer yanks the view on every keystroke. The reply panel needs no clearance (it flows). **The padding rule is now in both `lime.css` and `gradients.css`.** LIME-46 should leave it in exactly one place. Its gate check is pending.
      - LIME-47 `d081912` landed: `overflow-wrap`, code blocks scroll inside the bubble, the composer-radius token, reply-quote thumbnails (ready for "+N"), the DM "Profile" crumb, and the duplicate padding rule removed. Its gate check is pending. Next: LIME-40, then 41. The three `teacher.*` video files in `public/assets/` are deliberately **untracked** until LIME-48.
      - LIME-41-fix `a67d834` and LIME-43 `c1516a6` landed: receipts are derived from `last_read_at`, with native-`title` tooltips, in-place patching, and a z-index fix so the tick is hoverable under the action bar. Both gate checks are pending. **Tend thought the queue was finished. It isn't.** Remaining: **LIME-43-revert (the user dropped receipts; landed as `6cb8e4e`, `public/` is identical to `a67d834` as plot verified, and `PLOT.md` was committed as `d12c283`)** → LIME-44 (landed as `8bd114a`: `getLinkPreview` with 3 fixtures and a minimal fallback, no network, `link_previews` and `unfurl` documented; its gate check is pending) → 45 → **49 (settings profile and real photos)** → 33 → 48 → 29 → 27 (Share, **revised**: a header Share button and popover) → **28 (Communities: needs a planning pass first, see Open threads)**.
      - LIME-40-fix `90c5672` and LIME-42 `e8430e3` landed: the lightbox bar outside the image, real audio playback, typed file cards with badges ≥ 6.4:1, and PDFs opening via a real `<a target=_blank>`. Both gate checks are pending. **Next: LIME-41-fix** (the user's QA: captions, viewer controls, the photo wall), then LIME-43.
        - **Cleanup backlog:** a dead `.lime-message__file` block in `lime.css` (from LIME-38) overrides the Download button's size by class collision. Remove it in a cleanup brief, with the border-box and `[hidden]` global resets.
      - LIME-41 `848f271` landed: the `message_attachments` table, albums and gallery, **and the user removed LIME-38's 5-file cap** (tend asked mid-brief). The gallery-plus-lightbox double-Escape was fixed by a hand-off. Its gate check is pending. **LIME-40-fix is drafted and runs next,** before 42: the close button sits in a bar outside the image.
      - LIME-40 `5476097` landed: the lightbox × inset at the image's corner, arrows and keys, a counter, no wrap-around. Its gate check is pending. Next: LIME-41.
      - **Queue (2026-09-29): LIME-39 (amended) → LIME-46 (the fade system; landed as `aba5855`: pinned frames, `--surface-bg`, `color-mix` fades; 11/12 pixel samples within ±3, with one edge pixel ±4 from anti-aliasing, which is acceptable) → LIME-47 (bubbles, reply-quote media) → 40 → 41 → 42 → 43 → 44 → 45, then LIME-33 → **LIME-48 (auth redesign; needs the user's copy and photo first)** → 29 → 27 → 28.**
      - LIME-38 `9c9742d` landed: attachments through IndexedDB, `uploadAttachment`/`getAttachmentUrl` in the store, `'file'` in the schema, and `reset()` now chains the async adapter reset. Its gate check is pending. Next: LIME-39.
      - **Prompt wording lesson:** "re-read it, then stop for my check" made tend stop *before* implementing. Always write "implement, commit, then stop for my check"., 28 (live Communities), 29 (Create).
    - **The border-box bug has now hit 5 times** (18-fix4, 20, 21b, the composer, settings). Plot should weigh the global `*, *::before, *::after { box-sizing: border-box }` reset soon, as its own brief with a full visual regression pass (headless screenshots of key views before and after).
    - Later candidate: "Leave group" for non-owners. → (25–29 drafted as each lands).
  - **Update:** 19b-fix `d4a7810` passed with the user's feedback. The follow-up `67a4107` unified the DM header with the group header at the user's direct request (the brief had scoped DMs as unchanged). That commit has **no `Brief:` trailer**. It's left as is, not rewritten; its `TEND.md` entry explains it. **Tend proposed LIME-19c next, which is wrong: it's on hold.** Next is LIME-24.
- **(Resolved) Paused mid-LIME-19b (2026-09-27, tend hit its usage limit):**
  - All of 19b is implemented and verified but **uncommitted**, and `TEND.md` has no 19b entry yet. Uncommitted files: `lime.css`, `index.html`, `app.js`, `data.js`, `seed-data.js`, and `seed-data/conversations.json` + `messages.json`.
  - Plot sanity-checked the tree: no diagnostic script left in `index.html`, `node --check` passes on both JS files, `lime.css` braces balance (434/434), and conv-011 is present in the JSON and the embedded copy.
  - **`PLOT.md` is also modified (plot's edits). It must NOT go into the 19b commit.** Commit it separately as `chore: update PLOT.md`.
  - **Resume:** a fresh tend session writes the `TEND.md` entry, commits 19b (excluding `PLOT.md`), then runs the gate. **No `git checkout` or `git stash`**: the only copy of this work is the working tree. Its gate feedback led to 18-fix5: vertical alignment of the two composers and the right-panel gutter.
- **Minor, not urgent:** 18-fix3 swaps the reply disclaimer text in JS at load instead of just changing the words in `index.html`. It works but is roundabout. Fold it into a later cleanup.
- LIME-17, 18 and 19 were drafted from the user's thread and chat-list QA. **LIME-19 is ON HOLD, don't send it:** it will be redrafted to be conversation-based once the tab-merge decision below lands.

## Open thread: merge the Teachers and Group Chat tabs (raised 2026-09-27)

- **The user's proposal:** two tabs instead of three. Teachers (1:1 and group chats together) and Community.
- **Plot agrees.** Proposed rule: first tab = "conversations I'm in" (private, invite-only, small: DMs, ad-hoc groups, named teams); Community = "spaces I've joined" (open or joinable, topic-based, many members).
- **DECIDED 2026-09-27:** the tabs are "Messages" and "Communities". Briefs LIME-19b (merged live list) and 19c (Starred) are drafted. **Later briefs:** make Communities live from the seed data (it's a static mockup today), make the Recent row data-driven, and make the profile panel group-aware.
- **Leans for the redraft:**
  - group rows get a stacked two-avatar mark, the group name (or "Jean, Mary & Jimin" if unnamed), and a sender-prefixed preview ("Jean: …");
  - sections become Recent / Starred / All, and groups can be starred.
- **Survey facts:**
  - The seed data has 5 group conversations (3 include teacher-002), e.g. "PS 113 7th Grade Team", "Math Teachers NYC", and "Jean, Mary, Jimin & Me" (ad-hoc). It also has 9 community conversations (3 include teacher-002).
  - `index.html`'s Group Chat panel (~332) and Community panel (~390) are **static mockups** whose names ("Grade Three", "Staff Lounge", "FAM Wide"…) don't match the seed data.
  - Tabs: `data-scope="teachers|groups|communities"` (~182–184). The scope filter lives in app.js ~1003.
- **Redrafted LIME-19** (conversation-based rows, not teacher-based) should cover: DMs and groups in one live, recency-sorted list; a data-driven Starred section; and removing the Group Chat tab. Community going live is a separate later brief.

## Open thread: conversation lifecycle (create, star, edit, share, archive/delete), raised 2026-09-27

- **The user's ask:** "we need a way to 'create' either a DM, group chat or community, then a way to star them, edit them, share them and delete/archive them."
  - References: Claude's title caret menu (Pin / Rename / Share / Copy link / Delete, with keyboard hints), inline rename (the title turns into a selected text field), and Notion's header (a breadcrumb sibling switcher, plus Share, link and star icons, and a member avatar stack with "+10").
- **Constraints plot found:**
  1. **All data is in-memory.** A reload discards anything created, sent or renamed. A create and archive feature needs a decision on persistence.
  2. **Rows can't be added today.** The list's load-time click bindings (`app.js` ~1245 and ~1310) only attach to rows that exist at load. That has to become delegated listeners before new conversations can appear.
  3. The Communities tab is a static mockup, so "create community" needs a live Communities list first.
  4. LIME-19c's hard-coded starred list would be thrown away once real starring exists. **19c is on hold, to be replaced by a real star feature.**
- **Proposed sequence** (each one brief, one commit; after LIME-19b-fix):
  - **LIME-24:** delegated list listeners, plus a conversation state layer in `data.js`: create, rename, star, archive, delete; a change event; and persistence per decision 1.
  - **LIME-25:** real starring (a star toggle, and a Starred section driven by state). This replaces 19c.
  - **LIME-26:** a conversation actions menu on the title caret **and** on a hover "…" on list rows, sharing one menu: Star, Rename (inline, groups and communities only; a DM's title is the person), Copy link, Archive, Delete (with a confirm dialog).
  - **LIME-27:** Share. Copy a deep link (`#c=<conversation id>`) that opens that conversation on load, with a toast (Seed has a toast component).
  - **LIME-28:** live Communities list, the same pattern as Messages.
  - **LIME-29:** Create. A "New" button by the tabs opens a modal in the search-modal style. Pick 1 person for a DM, 2 or more for a group (optional title), or switch to Community (title required).
- **Decisions put to the user:** persistence; archive and/or delete; red for destructive actions; where the actions live.
- **DECIDED (2026-09-27):**
  1. **Remember changes** in the browser across reloads, with a "Reset demo data" item in the profile menu.
  2. **Archive and Delete.** Archive hides a conversation into a restorable "Archived" section; Delete removes it for good, after a confirm dialog.
  3. **Delete is red** (Seed's `bad` colour); only Delete. Everything else stays neutral.
  4. **Actions live only in the title caret menu,** Claude-style. There's no row hover "…" and no header icons. The caret (`.lime-topbar__crumb-caret`, currently a dead "Switch conversation" button) becomes the actions menu.
- **Revised sequence:** LIME-24 (foundation, drafted) → LIME-25 (the title actions menu with Star; Starred driven by state, replacing 19c) → LIME-26 (inline rename, archive with the Archived section, delete with confirm) → LIME-27 (share: copy link plus deep link, and a toast) → LIME-28 (live Communities) → LIME-29 (Create modal). 25 onward are drafted once 24 lands.

## Open threads

- **Product context (user, 2026-09-29):** Lime's key differentiator is planned native **iOS and Android apps with offline, Bluetooth (mesh-style) messaging** for when networks are down: natural disasters, strikes, and so on. It isn't scoped yet. When it is, it affects the data layer (local-first sync, conflict handling, message ids and ordering without a server). The store/adapter seam and UUID ids from LIME-24 already point the right way. It needs its own planning pass (a decision surface) before any mobile work. The sign-in page's under-card area is reserved for future app-download links (LIME-48).
- **Real notifications (user, 2026-09-29):** "we can use notifications for that [read status] to start." The notifications dropdown is still a **static mockup** (Jean/Mary/Valene). Candidate brief: data-driven notifications (new messages, replies to you, reactions, mentions), derived from messages and `last_read_at`, with the bell's count real. Production: a `notifications` table, or derived views, plus push later. Receipts (LIME-43) can return later by reverting LIME-43-revert (`6cb8e4e`).
- **Communities need a planning pass before LIME-28 is briefed (user, 2026-09-29, earlier mobile mockups):**
  - **A discovery row of community cards:** a cover image, the name, stacked member avatars with a count ("12.3k"), and "✓ Member".
  - **A feed/wall of posts:** image cards with a caption and @mentions, a heart/like with a count, and the source community with its member count, in a two-column masonry.
  - **A community page:** a cover banner, a square community avatar, the name with ⌄, a description, member avatars with "12.3k members", "✓ Member", then **channels inside the community** ("Bulletin Board" with an unread badge, a "Starred" section, and a "Groups" section: "NYC Teachers", "Bookclub", "Announcements").
  - A bottom tab bar, Link and Jam, on mobile.
  - **Implications:** communities **contain channels** (sub-conversations: `conversations.parent_id`), **posts with likes** (a new content type, maybe Jam-adjacent), **cover and avatar images**, and **large member counts** (the seed's `member_count` question from LIME-24a).
  - **This is a decision surface, not a brief.** Present the options (e.g. channels-only first, versus channels plus a feed) before drafting LIME-28. The old LIME-28 draft ("a live Communities list, the same as Messages") is **superseded** by this.
- **Pattern tiles need a manifest (plot, reviewing LIME-52-fix):** over `file://`, the app can't list a folder, so `appearance.js` ~228 only probes **12 fixed names** (`paper`, `linen`, `dots`, `grid`, `diagonal`, `topography`, `texture`, `noise`, `wave`, `grain`, `weave`, `stripes`), in `.svg`/`.png`. Any other file name is silently ignored.
  - **Follow-up when the user adds SVGs:** a small `public/assets/patterns/patterns.js` manifest (`window.LIME_PATTERN_TILES = [{ file, label, credit }]`, loaded by a script tag and `file://`-safe) replaces the probing. The credit line in Settings is generated from its `credit` fields.
  - Until then, the user must name files from that list.
- **Cleanup brief candidates (not yet drafted):**
  - a global `*, *::before, *::after { box-sizing: border-box }` reset (the bug has hit 5+ times), with a visual regression pass;
  - `[hidden] { display: none !important }`;
  - remove the dead `.lime-message__file` block (LIME-42) and the unused Seed `dropdown.css` link;
  - empty the "Jean Chung" placeholder HTML in the breadcrumb and header.
  - Also open: **the right panel is unreachable at 768–1024px** (LIME-32 finding), and the mobile duplicate "Thread" heading (LIME-35 finding).
- **Plot process lesson:** a Python `str.replace` on a heading that doesn't exist silently does nothing. That's how the notifications and product-context notes were lost for a while. Always `assert` the anchor exists before replacing.

- **State-colour system: DECIDED 2026-09-27, option A, stepped.** LIME-14 is drafted below. Follow-up briefs in order: disabled (one consistent look instead of opacity 0.4 vs `--soil-text-disabled`), focus (restore visible outlines, e.g. `.lime-search-field` where LIME-03b removed Seed's focus glow), then a hover/default tidy-up. Error needs no brief until Lime has something that can fail. Candidate later: upstream the lime `selected` scale into Seed (option C). Original notes: The user wants the nav's active colour (`--lime-nav-hover` = `--seed-lime-100`, #E4F9BE) promoted to a reusable system colour with Seed-style default/hover/active/disabled states. Error is Seed's `bad-*` family, not a state.
  - Survey findings:
    - `--lime-nav-hover` has 7 uses (nav hover and active, divider hover, user trigger, the button at ~1355, and Send active and active-hover).
    - Raw `--seed-lime-300` is used directly at lines 90 and 1360, which breaks Seed's rule of not using Tier 1 colours in components.
    - Seed's own `selected-*` family (meaning "chosen, this one") is mint (`lime-25`/`40`/`75`), not the user's lime-100. Lime uses it about 12 times (lines ~634, 1550, 2003–2008, 2071), and about 10 Seed components use it.
    - `lime-100` is the same in both themes. Only the light theme is used today.
  - Options put to the user:
    - **A.** Retune Seed's `selected-*` inside Lime (my lean).
    - **B.** Create a new `--lime-*` family.
    - **C.** Change Seed upstream.
  - Also still open: the actual hover and pressed steps. The nav currently uses the same colour for hover and active.
  - Next brief (LIME-14) waits on this answer. LIME-13 doesn't depend on it.

- **Lime is reserved for nav and primary actions (user, 2026-09-27).** This narrows LIME-14's option A. Menus, reactions and dividers go neutral in LIME-21b. `--selected-*` is still lime-retuned globally, so any *other* consumer of `--selected-*` (Seed components, avatar rings) is lime by accident. Future cleanup: give nav and primary actions their own lime tokens (e.g. `--lime-accent-*`) and return `--selected-*` to neutral or stock. Decide after LIME-21b's gate answers.
- **Existing Supabase signup code:**
  - `public/signup.html` + `public/js/supabase.js` (commit `8066506`) already use Supabase auth via CDN, with **placeholder** URL and key constants in the file.
  - When the switch happens, consolidate: one Supabase client and config (from a gitignored `*.local.js`, per the switch checklist), shared by signup, login and the future `SupabaseAdapter`. Don't leave placeholder constants in committed code.
  - LIME-24b left `supabase.js` untouched.
- **Toasts landed (2026-10-01):** LIME-67 `65e40d2` (`toast.js`, `LimeToast.show`/`queue`, bottom-right, a neutral card) and LIME-68 `1191243` (the event table in `TEND.md`). Tend's flags:
  - **(a) An out-of-scope one-liner in `local-adapter.js`** (dispatching `lime:storage-failed` inside `save()`'s catch, needed for the storage warning). Plot reviewed it: tiny and correct. **Plot's recommendation is to keep it**; the user decides.
  - **(b)** The 10MB attachment limit is now a toast; `showAttachmentError` is dead code (cleanup brief).
  - **(c)** dew has no proper error icon (`dew-negative` reads as a red minus). A **dew request: an alert-circle icon.**
  - **(d) A possible bug: inline rename drops spaces** ("Planning crew" became "Planningcrew"). The breadcrumb rename input may sit inside a button that treats Space as a click. **Ask the user to try it by hand; if confirmed, it's a fix brief.**
  - **(e)** LIME-67's behaviour suite was only run in Chrome. LIME-68's events ran in both browsers.
  - The user's gate checks on 67 and 68 are pending.
- **LIME-66 landed as `0e7b014`** (2026-10-01): Seed bumped to `2c911c2`; the paint brush, link-simple and code icons are in. Share keeps LIME-59's hand-drawn SVG (`dew-share` is the same icon whose sizing didn't match). **The user's checks of 62–66 are pending.**
- **2026-10-01 update:** dew and Seed were pushed (Seed `2c911c2`, a clean diff: `icons/dew` plus Seed's `TEND.md`). LIME-65 landed as `bd5ee3e`. **LIME-66's submodule checkout was blocked by tend's sandbox**, so plot gave the user the commands to run. **Careful:** a `git submodule update --init --recursive` from Lime's **root** would reset `vendor/seed` back to the recorded `2bc0868`. Run it **inside** `vendor/seed` (`git -C vendor/seed submodule update --init --recursive`).
- **Cross-project, open 2026-10-01: the new dew icons** (code, link-simple, paint-brush-broad, palette) are built in `~/Sites/dew` but uncommitted and unpushed (DEW-01, dew's own `PLOT.md`). LIME-66 is blocked until dew commits and pushes, then Seed bumps `icons/dew` and pushes. The user must run those in the dew and Seed sessions; pushing is their call.
- **Upstream to Seed, added 2026-09-30:** the light theme's `seed-button--primary` should use ink text on lime-500, with lighter hover and press (LIME-58).
- **Upstream to Seed (Seed's owner is FAM, the same person as the user):** `.seed-dropdown__item` is `width: 100%` plus padding with no `box-sizing: border-box`, so it overflows its menu. Lime works around it in LIME-21. Also candidates: the lime `selected` scale (LIME-14), and whether Seed should ship a global border-box reset.
- **The 768px breakpoint doesn't match.** Seed's layout.css mobile rules use `max-width: 768px` and Lime's use `max-width: 767px`. At exactly 768px wide, Seed hides the left panel (`display: none`) and Lime's hamburger isn't shown, so there's probably no way to reach the nav at that single width. It isn't reported yet. Candidate small brief: align Lime's queries to 768px, or override Seed's. Verify live first.
- **Briefs keep re-proposing overlays.** An overlay/backdrop version of the mobile nav was proposed three times against the settled push model (LIME-12-fix2/3/4/6). The decision is now logged in `README.md` → "Decisions (2026-09-23)". Any brief touching the mobile nav must be checked against it.
- **`STATUS.md` is stale.** It still says only "Link screen renders". It needs a refresh brief at some point. Low priority.
- **Unverified live:** the 20px sidebar width gap (LIME-12-fix2) and the ≤480px placeholder trigger (LIME-12-fix4). Both are minor.

## Patterns learned

- **Previewing (UPDATED 2026-09-30, LIME-33-fix): use `http://localhost:8000/public/login.html`, with `python3 -m http.server 8000` started in the repo root.** `file://` no longer works in Firefox now that there are several pages sharing accounts (each `file://` page gets its own storage by default). Accounts made under `file://` don't carry over to localhost. The older note follows. **Previewing (old):** `index.html` loads Seed via `../vendor/...`, so it must be served from the repo root or opened as a `file://` URL. A server started inside `public/` (as the LIME-13 tend session did, with `python -m http.server 8756`) returns 404 for all Seed CSS, and the page renders unstyled. Every brief's gate should give the preview URL as `file:///Users/shem/Sites/lime/public/index.html`, or as `localhost:<port>/public/index.html` with the server started from the repo root.
- **Pixel alignment must be measured, not computed.** LIME-18-fix2 and fix5 both computed positions from CSS "by arithmetic" and got the premise wrong (fix5 assumed Seed's panel padding, which `lime.css` zeroes). Without the Chrome extension, use headless Chrome (`/Applications/Google Chrome.app`, `--headless=new --dump-dom` plus a temporary diagnostic script that's removed afterwards). Every alignment brief must require this.
- **What actually worked in LIME-31-fix (`1bfb4bb`): Playwright-driven Firefox.** It's installed outside the repo; `node_modules` is gitignored. `TEND.md`'s LIME-31-fix entry records two headless-Firefox timing gotchas. **Future briefs should say "measure with Playwright + Firefox per `TEND.md` LIME-31-fix".**
  - Also a lesson: a leftover diagnostic script in `index.html` auto-ran a click cascade on every load. **Every measurement brief must end with `git diff public/index.html` showing only intended changes,** checked before commit.
- **The measurement tool is now headless Firefox (decided 2026-09-28, during LIME-31-fix).**
  - Headless Chrome is blocked on this machine: Chrome's own GoogleUpdater/Keystone side process stalls on the system resolver when offline, which tend diagnosed from stderr. The only workaround needs `--no-sandbox`, which was declined.
  - **Use Firefox 156** (`/Applications/Firefox.app`). It's the user's target browser, so it's also the more faithful measurement.
  - **Recipe:**
    - `firefox --headless -no-remote -profile "$(mktemp -d)" --window-size=W,H --screenshot out.png "file://…/index.html"`;
    - a temporary diagnostic script prints the measurement JSON in a large fixed `<pre>` overlay, which tend reads from the PNG;
    - **or** drive it over WebDriver BiDi (`--remote-debugging-port`, Node's WebSocket, `script.evaluate`);
    - a 45s alarm per run;
    - always a throwaway profile, never the user's.
  - The Chrome notes below are historical.
- **Headless Chrome hangs (seen in LIME-24b and LIME-31-fix).**
  - A `--dump-dom --virtual-time-budget` run can sit for many minutes.
  - **Plot's likely cause:** the page's external requests (Google Fonts, the unpkg lucide CSS) never settle in the sandbox, so virtual time never advances.
  - **Standard recipe for every brief:**
    - add `--host-resolver-rules="MAP * ~NOTFOUND"`, so external hosts fail fast (`file://` is unaffected);
    - wrap each run in a hard timeout (macOS has no `timeout`; use `perl -e 'alarm 45; exec @ARGV' -- "…/Google Chrome" …`);
    - use a throwaway `--user-data-dir` per run;
    - clean up with `pkill -f -- '--headless=new'` if a run is killed. **Never `pkill -f "Google Chrome"`**, which quits the user's real Chrome windows (tend did this during LIME-31-fix).
    - The user's rule is "preview to the user in Firefox only". Headless Chrome as an internal measuring tool is allowed and isn't the cause of the hangs.
  - Never wait on a monitor for more than ~2 minutes.
- **"Visible" means hit-testable** (LIME-79-fix): a menu that opened as a 0×0 box passed LIME-78's "inside the screen" check. UI tests must assert a non-zero rect **and** that `document.elementFromPoint` at its centre lands inside the element.
- **Avoid multi-layer `mask-composite`** (LIME-57-fixc): it painted the notch's overflow solid in Firefox and Chrome, and the operator semantics are easy to get backwards. For a fixed-ratio cut-out, **pre-composite it inside one SVG** and use a single `mask-image`.
- **Screenshot artefact (LIME-57-fixb):** a Playwright screenshot clipped tightly to one element can render masks as if uncut in Firefox. Confirm mask work with a full-page (or padded) screenshot before chasing a "browser bug".
- **CSS masks clip every descendant** (LIME-57): a masked wrapper hides child badges and dots, and box-shadows on masked elements vanish. Any mask brief must verify that no indicator sits inside a masked **ancestor**, with element screenshots of each indicator.
- **Debounced saves lose data on navigation** (LIME-33, LIME-29): `scheduleSave()` waits 100ms, and a sign-out, redirect or reload inside that window drops the write. Only the real Firefox and Chrome caught it. Any brief that writes and then navigates must flush first (`LimeStore.flush()`); a `pagehide` flush is the general fix (folded into LIME-27).
- **Plot crossed a line (2026-10-01): never write personal data into `PLOT.md`.** Plot copied the user's test-account emails and phone numbers into the LIME-74 brief while that same brief said they must never be committed. Tend committed `PLOT.md` unedited (`7450e93`), as instructed. It was caught before any push (origin was 129 commits behind) and redacted. **Rule:** real emails, phone numbers, passwords and keys go **only** into the prompt the user pastes, pointing at a gitignored file. **Updated 2026-10-01 (the user's decision, LIME-75): the two test **emails** (`shem@` and `jean@famkind.com`) are now intentionally public demo emails and may appear in `PLOT.md` and the seed. The phone numbers and password remain private, local file only.** `PLOT.md` refers to them abstractly ("test account 1"). The history rewrite is LIME-74-redact.
- **Tiered verification (DECIDED by the user 2026-10-03: "yes"), applies to every brief from LIME-79-fix6 on:**
  - **CSS-only or visual polish:** the `mobile` suite plus `smoke` on **one** origin (the dev server, LAN), and screenshots of the changed screens only; no desktop pixel diffs unless desktop CSS was touched.
  - **JS, behaviour, data or server changes:** the relevant suites on the dev server (LAN), plus smoke.
  - **The full matrix** (every suite × localhost/dev/LAN × Firefox and Chrome) runs **once at the end of a chained run**, before the last push.
  - Measurements (ΔE, contrast, icon tables) only where the brief asks for them.
- **The test harness lives in `tests/`** (LIME-72): it uses **puppeteer-core** driving the installed Firefox (BiDi, with real-default prefs) and Chrome. Run `cd tests && npm test` (the Python server) and `LIME_TEST_SERVER=dev npm test` (the dev server). Every brief touching `public/` must run it and report the result.
- **Playwright's Firefox is not the user's Firefox (found 2026-09-30, LIME-52-fix3).** Uploads passed tend's whole matrix in Playwright's patched Firefox build but did nothing in the user's installed Firefox 156, while working in Chrome. **Any brief touching browser APIs with per-browser behaviour (files, IndexedDB, blobs, canvas, clipboard, `file://` origin rules) must verify in `/Applications/Firefox.app` itself** (BiDi, or Playwright with `executablePath`), and state which binary it used. Layout-only measurements can keep using Playwright's Firefox.
- **`[hidden]` is unreliable here:** any class that sets `display` (e.g. `.lime-icon-btn { display: flex }`) beats the browser's default `[hidden]` rule (found in LIME-40). Candidate for the global-reset brief: `[hidden] { display: none !important; }` alongside the border-box reset.
- **CSS verification must check what the browser parsed** (found in LIME-50-fix): a `*/` inside a comment (e.g. writing `--calm-bg-*/…`) closes it early and silently drops the rest of the stylesheet. Brace counts and `node --check` can't catch it. Every CSS-touching brief should report `document.styleSheets[i].cssRules.length` for `lime.css` (≈ 660) and `gradients.css` in the real browser, and never write `*/` inside comment text.
- **JS verification must load the real app.** `node --check` and testing extracted functions missed LIME-18's load-order crash, which froze every click in the app. Every brief that touches JS must require that `seed-data.js`, `data.js` and `app.js` are loaded as real scripts against the real `index.html` (jsdom in the session scratchpad, not the repo, when Chrome isn't connected), with zero errors reported. Tend adopted this from LIME-18-fix onward.
- **Handoff:** every brief handoff ends with a copy-paste prompt for tend, e.g. `tend LIME-14`. Tend reads the full brief from this file, so the brief must be saved here before handing off.
- The user isn't technical. Explain decisions in plain terms: what the user will see, not selector mechanics.
- The user makes visual CSS edits by hand, then asks plot to review them and tend to QA them. Treat those edits as design intent. Fix only what breaks behaviour or consistency, and don't restyle.
- The `seed-layout--collapsed-left` class can persist into mobile views through `localStorage`. Any change to a sidebar row's base styling must also be checked in (a) the desktop collapsed rail and (b) the `.seed-layout--mobile-open.seed-layout--collapsed-left` `!important` overrides in `lime.css`'s mobile media query.

---

## Drafted briefs

### LIME-87-fix → `tend` (lime-aa) (next): a visible dark green, the chat header fade, swipe-back, sample text
**What it does:** the user reviewed LIME-87 ("looks great") and approved these fixes. The iOS app only.

**Capabilities assumed:** edit files, XcodeGen, `xcodebuild`, `xcrun simctl`, commit, push.

**Phase 0:** commit `PLOT.md` as on disk, unedited (`chore: update PLOT.md`, plus the attribution trailer).

**Phase 1: survey (read only):** `ios/Lime/Theme/`, the colour sets, the Chat and Messages headers, how the nav bar is hidden, and `SampleData.swift`. If anything contradicts this brief, stop and ask the user.

**Phase 2: the change.**
1. **A visible dark green** (the user: "the chat bubble in dark mode disappears"):
   - In dark mode, the **primary** colour (the own bubble, the "+" button, unread badges, the dock badge) becomes a green that clearly reads as green on the dark canvas: **OKLab distance from the canvas ≥ 8**, and its ink colour **≥ 4.5:1** on it. The own bubble's text and links use that ink.
   - Keep one token: the bubble and "+" stay identical.
   - Light mode is unchanged.
   - Document the chosen hex values in `ios/README.md` (Theme). Note that the web's dark `--lime-primary-bg` is intentionally different, since the web is frozen.
2. **The chat header fade:** messages scroll under a soft fade behind the back, title and tool pills (canvas colour → clear, about the header's height plus 24pt), so no text shows hard-cut under the pills. The Messages screen gets the same fade if it lacks one. Light and dark.
3. **Swipe back:** the left-edge swipe pops Chat back to Messages, as in any iOS app, while keeping the custom glass header (e.g. re-enable the navigation controller's interactive pop gesture despite the hidden bar). The glass back button still works.
4. **Sample data:** replace the repeated "Best breakfast in town breakfast in town…" texts with natural, distinct teacher messages. Made-up people only; no personal data.

**Out of scope:** `public/`, `server/`, `tests/`, networking, the bundle id (it stays `com.famkind.lime`; the user is deciding), new screens.

**Phase 3: verification.**
- `./generate.sh`, then `xcodebuild build` and `xcodebuild test` on the iPhone 18 Pro (iOS 27.0) simulator: 0 failures, no warnings in Lime sources.
- **New unit tests:** the dark primary vs the dark canvas OKLab distance ≥ 8; the dark ink on the dark primary ≥ 4.5:1; the light values are unchanged from LIME-87.
- **New UI test:** open a chat, swipe from the left edge, and Messages is shown.
- Screenshots: Messages and Chat in **light and dark** (including a chat with the own bubble visible, and a scrolled chat showing the fade) into the scratchpad. Report the paths.
- Also try the iOS 18.3 runtime (installed) and report whether build + tests pass there.
- `git status` shows only `ios/`, `TEND.md` (and `PLOT.md` from Phase 0) changed.

**Gate (the user, in Xcode → Run):**
- in dark mode your bubble and "+" are clearly green;
- messages fade under the header;
- swiping from the left edge goes back;
- the sample messages read naturally.

**Record:** a `## LIME-87-fix` entry in `TEND.md`. Commit: `fix(ios): visible dark green, header fade, swipe back, sample text`, trailer `Brief: LIME-87-fix`, plus the attribution trailer. **Push.** Stop for the user's check. No /loop wakeups.

---

**Update: LIME-90 landed as `2fcf708`** (pushed and verified).
- SQLCipher via CommonCrypto (BSD-style; the Zetetic notice is needed in acknowledgements). 19 Rust + 25 iOS tests pass; the app size is now +1528 KB.
- **Plot's findings:** the DB is **not excluded from iCloud backup** while its key is `ThisDeviceOnly`, so a restore onto a new phone would fail. And `-lime-reset-store` isn't Debug-gated. **LIME-90-fix is drafted** (a plot decision consistent with D5: the DB is never backed up; recovery comes via the recovery key).
- **Next-step plan:**
  - The Bluetooth spike needs a **second iPhone**. Plot believes the free provisioning covers the `UIBackgroundModes` bluetooth keys (no paid entitlement), but this is unverified, so the spike may not need the paid account.
  - While the hardware is pending, plot drafts **DESIGN-02: API v2** (mailbox, key directory, signed envelopes, group-state ops, HLC + parents ordering, delivery tokens), ahead of the Supabase brief.

**Update: LIME-89 landed as `fa8fd3c`** (pushed and verified; no generated or binary artefacts tracked).
- vodozemac 0.11.1 (Apache-2.0), UniFFI 0.32.2 (MPL-2.0, file-level; tend's reading: fine for MIT, and a lawyer's glance before public release). No GPL/AGPL linked.
- Rust 1.99.0 pinned (installed via brew rustup, no sudo, no profile edits). 6 Rust tests + 21 iOS tests pass.
- **+896 KB** app size; a cold `./generate.sh` takes 1m36s.
- Tend added `EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64` (no Intel simulator slice); fine on Apple-silicon Macs.
- **LIME-90 is drafted** (the SQLCipher store; iOS reads from the core). It waits on the user's phone check of 89.

**Update: LIME-88 landed as `65b3755`** (pushed and verified): `docs/architecture.md` (187 lines, 11 sections).
- **Tend's judgement calls:** all three accepted by plot.
  - The key/user directories were added to "the server can see"; correct, and more honest.
  - It **flagged a real gap: ordering under the blind mailbox** (`architecture.md` §11 item 5).
- **Plot's proposed answer** (put to the user 2026-10-06 as a lean; it goes into the API v2 brief, not LIME-89):
  - The server's `seq` becomes a **per-mailbox delivery cursor only** ("what have I fetched").
  - **The conversation order is decided on the devices:** each message carries a **hybrid logical clock** timestamp plus **references to the latest messages its sender had seen**. Devices show messages in causal order (a reply never appears before what it answers), tie-broken by the clock, then the message id.
  - **The same rule works online and over the mesh.**
  - The displayed time keeps v1's rule (never in the future).
  - Group-state changes are ordered the same way, with deterministic conflict rules (e.g. a concurrent remove beats an add); detailed later.
- **Next:** LIME-89 (drafted) once the user confirms the doc.

**Update: LIME-87-fix5 landed as `630c79e`** (pushed and verified).
- The dark own bubble and send arrow = `#8ECF73` (tend chose it over `#8fd473` to meet the brief's 6–8% lightness drop; justified).
- The title is reverted to the fix3 side-by-side style (it truncates even at 402pt; the user accepted truncation).
- **Next:** the user's phone check → LIME-88 (docs) → **LIME-89 (drafted: the Rust core skeleton)**.

**Update: LIME-87-fix4 landed as `360aabb`** (pushed and verified).
- 18 tests pass on 4 simulators, including 375pt ones; the build for the user's iPhone succeeded.
- Plot reviewed the screenshots: the dark accent bubble reads well; full names show at 375pt.
- **A minor observation:** the stacked title sits left of centre (next to the back button) because the trailing 3-button group is wide; Apple centres it. Offer it as a polish item only if the user minds.
- Next: the user's on-phone check, then LIME-88.

**Update: LIME-87-fix3 landed as `6131d50`** (pushed and verified).
- `ios/Local.xcconfig` is gitignored and not tracked; it holds the team `CZH2QUHB3Y`.
- 16 tests pass.
- The accent comparison (`acc/accent-compare.png`): **plot's lean is to keep `#a3e18a`**. It reads well on both canvases; `#b8e8a3` is faint in light; `#8fd473` is fine but heavier.
- DM sender names stay groups-only (tend's call, matches Apple).
- Awaiting the user's pick and phone check, then LIME-88.

**Update: the user ran Lime on their own iPhone 13 mini** (free Personal Team signing; Developer Mode on; trusted). "Looks good." **LIME-87-fix3 is drafted:** DM avatars, the accent `#a3e18a` for the badges and "+", and persistent local signing. The plain title (no capsule) was accepted implicitly.

**Update: LIME-87-fix2 landed as `4f1db1e`** (pushed and verified).
- Only `ios/` and `TEND.md` are in the commit; `TmpShots.swift` was not committed.
- 11 tests pass on iOS 27.0 and 18.3. The dark green now clearly reads (plot checked `ios27-chat-dark.png`).
- **The iOS 26 centre title has no capsule** (plain avatars + name). Plot's lean: **keep it plain**, since Apple Messages' own title is plain. The user decides at the gate.
- Next: the user's on-phone check, then LIME-88.

**Status (2026-10-05, 22:06; superseded):**
- LIME-87-fix landed as `726c378`.
- LIME-87-fix2 is in progress (its PLOT.md commit is `98f43f9`).
- **Watch:** an untracked scratch file `ios/LimeUITests/TmpShots.swift` must not be committed.

### LIME-87-fix2 → `tend` (lime-aa) (after LIME-87-fix lands): Apple's own scroll edge effect and toolbar
**What it does:** the user compared Lime's header fade with Apple Messages on iOS 26 (screenshots, 2026-10-05): "the fade needs to be higher up and more subtle; look at the Apple Messages example; we should copy that".
- In Apple Messages, the content **blurs and softly fades starting at the very top of the screen (behind the status bar)** and is clear just below the glass buttons.
- Lime's fade sits lower, with a heavier wash.

The faithful way to match it is to **use the system's own toolbar and scroll edge effect** instead of hand-drawn fades. That also gives the system swipe-back and back button for free.

**Capabilities assumed:** edit files, XcodeGen, `xcodebuild`, `simctl`, commit, push.

**Phase 0:** commit `PLOT.md` as on disk, unedited (`chore: update PLOT.md`, plus the attribution trailer).

**Phase 1: survey (read only):** how the Messages and Chat headers, the fades and the swipe-back are built after LIME-87-fix. Check that the installed SDK has `scrollEdgeEffectStyle` and toolbar glass for iOS 26+. If anything contradicts this brief, or the native toolbar can't hold the title pill (avatars + name + "N members"), **stop and ask the user**.

**Phase 2: the change.**
1. **iOS 26 and newer: native toolbar plus the system scroll edge effect.**
   - **Messages:** `NavigationStack` toolbar items: leading, the logo button; trailing, **one group** with search + avatar (the system draws one shared glass capsule). The custom header and fade are removed. The scroll view uses the system **soft** top edge effect (`.scrollEdgeEffectStyle(.soft, for: .top)` or the SDK's equivalent), so the list blurs and fades under the status bar and buttons exactly as Apple Messages does.
   - **Chat:**
     - leading, the **system back button** (system glass and the system swipe-back; remove LIME-87-fix's custom swipe workaround if it becomes redundant);
     - principal, the title pill (the avatar stack, the name, "N members");
     - trailing, one group with search, call and "⋯".
     - The same soft top edge effect.
   - **Bottom:** the soft bottom edge effect behind the composer (Chat) and the dock (Messages), so content softens under them instead of cutting.
2. **iOS 17–25 fallback:** keep visually close, with a **subtle** top treatment: a progressive blur/material plus a canvas-colour gradient that starts **at the top of the screen (behind the status bar)** and fades out about 8–12pt below the header buttons. The maximum opacity is low enough that rows read as softly veiled, not washed out. Custom glass pills stay as they are below 26.
3. Keep the LIME-87-fix dark green, the sample text and the button sizes. Don't change the colours.

**Out of scope:** anything outside `ios/`; networking; new screens; the bundle id.

**Phase 3: verification.**
- `./generate.sh`; build + test on the iPhone 18 Pro (iOS 27.0): 0 failures, no warnings in Lime sources. Also on the iOS 18.3 runtime (the fallback path).
- The UI tests still pass:
  - launch → open chat → send → back via the back button;
  - **and** via an edge swipe.
- **Screenshots** (light and dark, iOS 27, plus one on 18.3) with the list **scrolled** so a row sits under the header: Messages, and Chat scrolled. Report the paths, and describe in one line each how the top edge compares with Apple Messages (where the fade starts and ends).

**Gate (the user, on the iPhone via Xcode → Run):** scroll the list and a chat. The top looks like Apple Messages: a soft blur that starts behind the clock and clears just under the buttons. The back swipe still works.

**Record:** a `## LIME-87-fix2` entry in `TEND.md`. Commit: `fix(ios): system toolbar and scroll edge effect (Apple Messages-style fade)`, trailer `Brief: LIME-87-fix2`, plus the attribution trailer. **Push.** Stop for the user's check. No /loop wakeups.

---

### LIME-87-fix3 → `tend` (lime-aa) (next): DM avatars, the accent green #a3e18a, signing that survives regeneration
**What it does:** the user ran LIME-87-fix2 on their iPhone 13 mini ("looks good") and asked for two changes. It also persists their on-device signing.

**Capabilities assumed:** edit files, XcodeGen, `xcodebuild`, commit, push.

**Phase 0:** commit `PLOT.md` as on disk, unedited (`chore: update PLOT.md`, plus the attribution trailer).

**Phase 1: survey (read only):**
- how Chat decides whether to show a sender avatar (it seems to be groups only);
- the theme tokens used by the unread badges (the Messages rows and the dock's "link" badge) and the "+" button vs the own bubble;
- how `project.yml` sets signing.

If anything contradicts this brief, stop and ask the user.

**Phase 2: the change.**
1. **Avatars in 1:1 chats:** in a DM (e.g. Journey Park, Autumn Reyes), the other person's messages show their avatar beside the bubble, exactly as group chats do (same size, same position, and the same grouping rule for consecutive messages if one exists).
2. **The accent green `#a3e18a`:**
   - Add a separate **accent** token = `#a3e18a`, used for **the unread number badges** (the Messages rows and the dock badge) and **the "+" button** on Messages, in **light and dark**.
   - The badge numbers and the "+" glyph use a dark ink with **≥ 4.5:1** on `#a3e18a`.
   - **The chat's own bubble keeps its current colours** (the light primary, and the LIME-87-fix dark green); only these three uses move to the accent.
   - Update the theme unit tests: the accent equals `#a3e18a`; ink contrast ≥ 4.5:1; the own bubble is unchanged from LIME-87-fix2.
   - **The user wants to *see* it in both modes before settling** ("#a3e18a, or something in this family that fits our system").
     - Ship `#a3e18a` in both modes, **and** capture a comparison: Messages in light and dark with `#a3e18a`, plus **two family alternatives** rendered the same way (e.g. a slightly deeper `#8fd473`-ish and a softer `#b8e8a3`-ish; pick values that keep the ink at ≥ 4.5:1).
     - Put the six screenshots side by side in one image (`accent-compare.png`) with the hex labelled under each. Report its path.
     - Don't switch away from `#a3e18a` yourself; the user chooses from the comparison.
3. **Signing survives `./generate.sh`:**
   - `project.yml` includes an optional, **gitignored `ios/Local.xcconfig`**, and the app target reads `DEVELOPMENT_TEAM` (and `CODE_SIGN_STYLE = Automatic`) from it.
   - Commit an `ios/Local.xcconfig.example` with a placeholder and a comment.
   - Create the user's real `ios/Local.xcconfig` locally with their Personal Team id, taken from the existing signing state or the keychain certificate (it appears as `SCV29U533Y` in the certificate name; verify it is the **team** id, not just a certificate id). **Never commit it.**
   - Builds without the file still work (simulator).
   - `ios/README.md`: a short "Run on your iPhone" section (Personal Team, Developer Mode, the trust step, the 7-day expiry, `Local.xcconfig`).

**Out of scope:** anything outside `ios/`; other colour changes; networking; the bundle id (it stays `com.famkind.lime`).

**Phase 3: verification.**
- `./generate.sh`; build + test on the iPhone 18 Pro (iOS 27.0) and iOS 18.3: 0 failures, no warnings in Lime sources.
- A UI or unit check that a DM's incoming message has an avatar.
- After `./generate.sh`, the generated project still carries the user's team (`xcodebuild -showBuildSettings | grep DEVELOPMENT_TEAM` shows it). `git status` shows `Local.xcconfig` **ignored**.
- If the iPhone ("iPhone", the 13 mini) is connected and unlocked, also run `xcodebuild -destination 'platform=iOS,name=iPhone' build`; report the result. If it isn't connected, say so.
- Screenshots: Messages (light and dark: the badges and "+") and a DM chat with avatars.

**Gate (the user, on the iPhone via ▶ Run):**
- Journey and Autumn have avatars in their chats;
- the badges and "+" are `#a3e18a` in light and dark;
- your chat bubble is unchanged;
- ▶ Run works without re-picking the team.

**Record:** a `## LIME-87-fix3` entry in `TEND.md`. Commit: `fix(ios): DM avatars, accent green badges and +, persistent local signing`, trailer `Brief: LIME-87-fix3`, plus the attribution trailer. **Push.** Stop for the user's check. No /loop wakeups.

---

### LIME-87-fix4 → `tend` (lime-aa) (next): the dark own bubble in the accent green; a chat title that fits on small iPhones
**What it does:** the user approved `#a3e18a` ("looks good in light and dark") and asked for **the dark-mode own bubble to be `#a3e18a`** too. Their iPhone 13 mini screenshot also shows the chat title cut to "Autu…" (375pt wide).

**Capabilities assumed:** edit files, XcodeGen, `xcodebuild`, commit, push.

**Phase 0:** commit `PLOT.md` as on disk, unedited (`chore: update PLOT.md`, plus the attribution trailer).

**Phase 1: survey (read only):** the theme tokens for the own bubble, the bubble ink, the send button and the accent; the iOS 26 toolbar title (principal) and the iOS 17–25 title pill. If anything contradicts this brief, stop and ask the user.

**Phase 2: the change.**
1. **Dark mode only:**
   - the **own bubble** = the accent `#a3e18a`, with the accent ink for its text, links and timestamps inside it (≥ 4.5:1);
   - the **send button** (the up arrow) = the same accent + ink, so the composer matches.
   - **Light mode is unchanged** (the own bubble keeps its light primary).
   - Update the tests: in dark, the own bubble equals the accent and the ink contrast is ≥ 4.5:1; in light, the own bubble is unchanged.
   - Remove the now-unused dark primary from LIME-87-fix **only if nothing else uses it**; otherwise leave it.
2. **The chat title on narrow phones, Apple Messages-style:**
   - On iOS 26+, the principal title shows the **avatar (or avatar stack) above the name**, small, centred (Apple Messages' layout). The name gets the full width between the back button and the trailing group; "N members" is dropped from the title on phones narrower than 390pt if needed.
   - On iOS 17–25, keep the pill but let the name take priority: shrink the avatar stack first, then truncate.
   - **Acceptance:** at 375pt wide (the iPhone 13 mini / SE size), "Autumn Reyes", "Journey Park" and "Grade 4 Team" show **in full**. Longer names may still truncate.

**Out of scope:** light-mode colours; anything outside `ios/`.

**Phase 3: verification.**
- `./generate.sh`; build + test on the iPhone 18 Pro (iOS 27.0) **and the smallest available iPhone simulator** (create an iPhone SE / 13 mini-class simulator with `simctl` if one exists for iOS 27; otherwise use the narrowest one available and say which). 0 failures, no warnings.
- **A UI test:** in the Autumn Reyes chat, the title's full name is visible (not truncated) at the narrow size.
- Screenshots: a dark DM chat with own bubbles and the send button; light DM unchanged; a narrow-width chat header. Report the paths.
- If the iPhone ("iPhone") is connected, also build for it and report the result.

**Gate (the user, on the iPhone):**
- in dark mode your bubbles and the send arrow are the bright `#a3e18a` with dark text;
- light mode is unchanged;
- chat titles show full names on your iPhone 13 mini.

**Record:** a `## LIME-87-fix4` entry in `TEND.md`. Commit: `fix(ios): accent-green dark own bubble and send; Apple-style chat title on narrow phones`, trailer `Brief: LIME-87-fix4`, plus the attribution trailer. **Push.** Stop for the user's check. No /loop wakeups.

---

### DESIGN-05 (plot, 2026-10-07): "the basics": settings, search, formatting, threads, notifications
**The user's ask (2026-10-07), while the two-phone gate of LIME-95-fix waits for Jean's phone:** "fill out the basics of the app: search, settings, chat formatting, chat reply threads, notifications (including a notification chime)".

**The execution order:**
1. **LIME-98** Settings;
2. **LIME-99** Search;
3. **LIME-100** Formatting;
4. **LIME-101** Reply threads;
5. **LIME-102** Notifications;
6. then LIME-96 (sealed), LIME-97 (groups + New Message v2 + invite/QR).

**The design sources:** `docs/design/mobile/` 04 (format menu; thread summary "3 replies · Last reply …"), 05 (Settings), 06 (Profile); plus the frozen web app's behaviour for threads/formatting.

**Plot's technical decisions (made here, no user input needed):**
- **The wire format for formatted text = a Markdown subset** inside the encrypted payload (CommonMark: `**bold**`, `*italic*`, `~~strike~~`, `__underline__` (a Lime extension), inline `` `code` ``, fenced code blocks, `-`/`1.` lists, links). It's portable to Android and the web; the renderer allow-lists only these. There is **no HTML on the wire**, and **no alignment/indent in messages** (the web's align menu is not carried over).
- **Threads = Slack-style, as in design 04:**
  - a reply carries `thread_root` (the root message id) inside the encrypted payload;
  - the root shows "N replies · Last reply <time>" with replier avatars;
  - tapping it opens a Thread screen with its own composer.
  - Ordering per `api-v2.md` §5. A quote-reply (swipe-to-reply) is later.
- **Search is on-device only** (E2EE): SQLCipher FTS5 over decrypted message text, in the encrypted DB. Nothing is sent to the server.
- **Notifications in two stages:**
  - **now (LIME-102):** local notifications when a message arrives while the app is backgrounded but still running, the in-app chime + banner while it's open, the notification settings, and the chime sound;
  - **later (with the paid Apple account):** APNs remote push with a Notification Service Extension that decrypts on the device (content-free push, per `api-v2.md`).

**Decisions put to the user (2026-10-07):**
- **N1 the chime sound:**
  - **A.** The user/a designer supplies a short sound (≤ 2 s; WAV/AIFF/CAF), placed at `ios/Lime/Resources/Sounds/`;
  - **B.** Tend synthesises a gentle 2-note placeholder chime (CC0, generated in code), replaceable later.
  - **Lean B now, A later.**
- **N2 the notification preview default:**
  - **A.** Name + message text (decrypted on the device only; Apple never sees it);
  - **B.** Name only;
  - **C.** "New message" only.

  Every option is user-changeable in Settings. **Lean A**, with the toggle.

### LIME-98 → `tend` (lime-aa) (next): Settings (design 05/06): profile, account, privacy, blocked, customize, about/acknowledgements
**What it does:** the iOS Settings screen, per `docs/design/mobile/05-settings.png` and `06-profile.png`, replacing the Debug-only About sheet as the main place for account things.

**Capabilities assumed:** edit files, `cargo`, the Supabase CLI (deploy functions without `config push`), XcodeGen, `xcodebuild`, commit, push.

**Phase 0:** commit `PLOT.md` as on disk, unedited (`chore: update PLOT.md`, plus the attribution trailer).

**Phase 1: survey (read only):** designs 05/06; `AboutView`, `AccountSession`, the profile functions, `ConversationStore` (blocked state); `docs/release-checklist.md`. If anything contradicts this brief, stop and ask the user.

**Phase 2: the change.**
1. **The entry:** tapping the **avatar pill** (top right of Messages) opens Settings as a sheet (the glass ✕), as in design 05. Long-press-logo About stays for Debug only.
2. **Settings rows** (glass grouped cards):
   1. **Profile card** (avatar, display name, `@username`) → **Profile** (design 06): edit the name, username (the same uniqueness rules), school, and a "Hide me from search" toggle. Saved via the profile functions.
   2. **Account:** the email (masked display); **Change password** (current + new, min 10, then an emailed code); **Sign out**.
   3. **Privacy:**
      - **Blocked** (list; **Unblock**);
      - **Safety numbers / keys** (shows "Your key was set on <date>" + a short fingerprint; read-only for now);
      - **Linked Devices** (design 05): shows **"This iPhone"** only, with a note: "Using Lime on more than one device is coming soon." (One active phone per account is the interim policy, LIME-95-fix.)
   4. **Notifications:** a placeholder row "Coming next" (LIME-102 fills it).
   5. **Customize** (design 05): **Appearance** (System / Light / Dark), stored locally and applied app-wide.
   6. **Donate to lime** (design 05): opens the donate URL **if configured**; otherwise the row is hidden. (The web's `LIME_DONATE_URL` is not set yet.)
   7. **About:**
      - the versions (app + core);
      - **Acknowledgements** (the open-source licences from `core/THIRD_PARTY.md`, **including the SQLCipher/Zetetic notice**, which closes that `release-checklist.md` item);
      - Terms and Privacy links (placeholders to `https://limechat.org/terms` / `/privacy`).
3. **Amendment (the user, 2026-10-07; Signal screenshots of "About"): the Profile edit screens follow Signal's editor pattern.**
   - **One field per sheet:** a glass ✕ at top left; the title centred; a round **✓ save** at top right in the **accent `#a3e18a`** with the dark ink, shown as dimmed glass until there's a valid change (Lime's version of Signal's blue ✓).
   - The field sits in a large glass pill with a clear (ⓧ) button; **the keyboard's return key is ✓ (save)**.
   - **Edit Name:** the display name (required, 1–40 characters).
   - **About** (a new profile field): a short status line with an **optional leading emoji**:
     - the emoji button at the left of the field opens the emoji picker;
     - **max 140 characters**, and the title shows the remaining count when ≤ 140, as in Signal ("About (128)");
     - placeholder: "Write a few words about yourself…";
     - **below the field, a list of tap-to-fill presets** (teacher-flavoured): 👋 Happy to help · 📚 Planning lessons · 🍎 In class · ☕ Coffee lover · 📝 Grading · 🔕 Taking a break · 🔒 Encrypted.
     - The About line shows on the Profile card in Settings, in New message results, and in the chat details.
   - **Server:** add `about_emoji` + `about_text` to `profiles`, readable through the same public-profile rules as the display name and school. **Note in `api-v2.md`:** it's a public profile field and the server can see it (like the name).
   - Apply the same ✕/✓ editor pattern to **Username** and **School**.
4. **Sign-out semantics stay as LIME-95-fix for now,** with the confirmation copy: "Signing out removes your messages and keys from this iPhone. Your contacts will see that your security key changed."

**Out of scope:** notification settings (LIME-102), real multi-device linking, recovery key, profile photos (later), account deletion (later; note it in `release-checklist.md`: the App Store requires in-app account deletion before release).

**Phase 3: verification.**
- Server, Rust and iOS tests pass on the three simulators; `ios/check-warnings.sh` reports 0 warnings.
- **New tests:** the About editor (the emoji, the 140 limit and counter, a preset fills it, ✓ is disabled until changed, saves, shows on the Profile card and in New message results); edit the profile (the name and username uniqueness errors); hide-from-search is honoured by `users-find`; block → unblock restores message display; the appearance persists across a relaunch; the change-password flow (local stack); the Donate row is hidden when the URL is unset.
- Screenshots (light and dark, 375pt): Settings, Profile, Account, Privacy/Blocked, Customize, Acknowledgements.

**Gate (the user, on the iPhone):**
- tap your avatar → Settings looks like design 05;
- edit your name and school;
- switch to Dark;
- see Acknowledgements;
- the Blocked list is empty, or shows anyone you blocked.

**Record:** a `## LIME-98` entry in `TEND.md`; update `docs/release-checklist.md` (acknowledgements done; account deletion required before release). Commit: `feat(ios): Settings (profile, account, privacy, blocked, customize, about)`, trailer `Brief: LIME-98`, plus the attribution trailer. **Push.** Stop for the user's check. No /loop wakeups.

---

### LIME-99 → `tend` (lime-aa) (after LIME-98): on-device search (Messages list + in-chat find)
**What it does:** private search that runs entirely on the phone.

**Capabilities assumed / Phase 0:** as in LIME-98.

**Phase 1: survey (read only):** the core store schema and migrations; the Messages header search button; the Chat header search icon; SQLCipher's FTS5 availability in the current build. If FTS5 isn't compiled in, report how to enable it and its size impact before proceeding.

**Phase 2: the change.**
1. **Core:**
   - an FTS5 index over decrypted message text (inside the SQLCipher DB, so it is encrypted at rest), maintained on insert/edit/delete;
   - a migration that back-fills existing messages;
   - the FFI `search_messages(query, conversation_id: Option, limit) -> Vec<SearchHit { conversation_id, message_id, snippet, time }>`, prefix-matching, case- and diacritic-insensitive;
   - `search_conversations(query)` over titles and participant names.
2. **Messages search** (the search button in the header): an iOS search field. The results show **Chats** (title/name matches) then **Messages** (snippets with the match highlighted). Tapping a message opens the chat **scrolled to that message**, highlighted briefly.
3. **In-chat find** (the chat header 🔍): the field in the header plus **"3 of 12"** with up/down to step through matches in this chat.
4. **Nothing leaves the device** (assert in a test that `search_*` makes no transport calls).

**Out of scope:** server/directory search (remains exact username/email in New message), searching attachments.

**Phase 3: verification.**
- `cargo test` (FTS ranking, prefix, diacritics, back-fill, delete removes it from the index, **the encrypted DB file contains no plaintext of an indexed word**);
- the iOS tests + UI tests (search → open at the message; in-chat stepping);
- 0 warnings;
- screenshots.

**Gate (the user):**
- search a word from a chat → it finds it → opens at the message;
- inside a chat, 🔍 steps through matches.

**Record:** a `## LIME-99` entry in `TEND.md`. Commit: `feat: on-device encrypted search (chats, messages, find in chat)`, trailer `Brief: LIME-99`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

---

### LIME-100 → `tend` (lime-aa) (after LIME-99): message formatting (design 04), Markdown subset on the wire
**What it does:** rich text in messages, per `docs/design/mobile/04-format-menu.png`, carried as the DESIGN-05 Markdown subset inside the encrypted payload.

**Capabilities assumed / Phase 0:** as in LIME-98.

**Phase 1: survey (read only):** `Model/MessageFormat.swift` (it may already partially exist), the composer in `ChatView`, design 04, and the frozen web composer's toolbar for behaviour cues. If anything contradicts this brief, stop and ask the user.

**Phase 2: the change.**
1. **The format** (`docs/api-v2.md` §11 + a short `docs/message-format.md`):
   - the subset is exactly: bold, italic, underline (`__x__`, a Lime extension), strikethrough, inline code, fenced code block, bulleted and numbered lists (one nesting level), links (http/https/mailto only).
   - **Everything else renders as plain text.** Max 64 KB per message.
2. **The core:** a parser/renderer-neutral validator (it rejects nothing; it downgrades unknown syntax to text) and a plain-text fallback for search and notification previews (strip the markup).
3. **The iOS composer, matching design 04:**
   - a toolbar of `+`, emoji, **Aa** (a menu: Bold, Italic, Underline, Strikethrough), bulleted list, numbered list, link, code;
   - mic and send on the right.
   - **Selecting text** shows a small glass B/I/U/S pill above the system edit menu (the web LIME-86-fix lesson).
   - Live (WYSIWYG) editing: the user sees formatting, not asterisks.
   - **Return = a new line;** send = the arrow.
   - **Link:** a sheet with a URL (+ text when there's no selection).
3b. **Amendment (the user, 2026-10-07): the formatting toolbar docks above the keyboard,** modelled on the user's examples (Notion's and Gmail's iOS editors). **The screenshots contain personal emails and names; never copy them.**
   - **This replaces** the "pill above the system edit menu" in item 3 and the toolbar's Aa popover.
   - **A floating glass capsule sits directly above the keyboard** (a keyboard accessory; it moves with the keyboard and is never covered by the system Cut/Copy/Paste callout). It is **horizontally scrollable** when the items don't fit (Notion style).
   - **The items, in order:** **B**, *I*, U, ~~S~~, link, code `</>`, bulleted list, numbered list.
     - Each shows its **pressed state** for the current selection/caret (like Gmail's).
     - Unavailable items are dimmed (e.g. link with no selection still opens the link sheet).
   - **At the right end, a separate round glass button:** **✕** (Gmail style) closes the toolbar and returns to the normal composer row (`+`, emoji, **Aa**, mic, send).
   - **When it appears:**
     1. automatically **whenever text is selected** in the composer;
     2. when the user taps **Aa** in the composer row (it stays until ✕ or send).
   - **Text colour and highlight (seen in Gmail) are NOT included.** The Markdown subset has no colour, and they'd break cross-platform rendering and the plain-text previews. The user may ask for them later as a separate decision.
   - The UI tests must cover:
     - selecting text shows the toolbar;
     - B toggles the pressed state and bold;
     - the toolbar scrolls at 375pt;
     - ✕ restores the composer row;
     - Aa opens it with no selection.
4. **The bubble rendering:** a native attributed text. Code blocks are monospaced with horizontal scroll. Links are tappable, with a confirmation for non-https URLs. Own and other bubbles keep their colours and contrast.

**Out of scope:** mentions, emoji reactions (later), attachments.

**Phase 3: verification.**
- `cargo test` (round-trips, unknown syntax downgraded, link scheme allow-list, the size limit);
- the iOS unit tests (Markdown ↔ attributed string both ways for every feature);
- UI tests (bold via the Aa menu; the selection pill; a list; a code block mid-message; a link);
- the local e2e: a formatted message renders identically on the receiver;
- 0 warnings;
- screenshots vs design 04.

**Gate (the user):**
- format a message with bold, a list and a code block → send → it looks right;
- select text → **the formatting capsule appears above the keyboard** (Notion/Gmail style), scrolls if needed, and ✕ closes it.

**Record:** a `## LIME-100` entry in `TEND.md`. Commit: `feat: message formatting (Markdown subset, encrypted), composer per design 04`, trailer `Brief: LIME-100`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

---

### LIME-101 → `tend` (lime-aa) (after LIME-100): reply threads (Slack-style, design 04)
**What it does:** reply in a thread to any message, per design 04's "N replies · Last reply …" summary.

**Capabilities assumed / Phase 0:** as in LIME-98.

**Phase 1: survey (read only):** the core message model and ordering (HLC + parents); `ChatView`; the frozen web thread behaviour (`TEND.md` LIME-17/18 entries) for cues. If anything contradicts this brief, stop and ask the user.

**Phase 2: the change.**
1. **Protocol:**
   - `thread_root: message_id | null` inside the encrypted message payload (not visible to the server);
   - replies inherit the root's conversation.
   - Document it in `api-v2.md` (the payload fields).
2. **Core:** the thread queries (`list_thread(root_id)`, the root's reply count, the last-reply time, the replier ids); unread-in-thread counts; search hits inside threads (LIME-99) open the thread.
3. **iOS:**
   - **long-press a message → "Reply in thread";**
   - the root bubble shows "N replies · Last reply <time>" with up to 3 replier avatars (design 04);
   - tapping opens the **Thread screen** (the system nav push: the root at the top, then the replies, then its own composer with formatting);
   - new replies arrive live.
   - Replies don't appear in the main chat timeline (Slack-style).

4. **Folded in from the LIME-100 review (the user, 2026-10-07): links must look different from underlined text.** Today both render as text-colour underline.
   - **Links:**
     - a dedicated **link colour token per bubble surface** (neutral bubble, own bubble; light and dark), from Lime's green family: a **deep green** that keeps **≥ 4.5:1** contrast on that surface (compute it; on the dark-mode own bubble `#8ECF73`, pick whatever green or ink-plus-style passes);
     - plus an underline;
     - **tapping shows the pressed state.**
   - **`__underline__`** keeps the **text colour** with a plain underline.
   - If a surface can't fit a distinct ≥ 4.5:1 green, use the ink colour with a **link glyph (↗) after the link text** instead, and say which surfaces needed it.
   - The same token applies in the composer while editing.
   - Unit-test every contrast pair. Add a screenshot showing a link and an underline side by side in each bubble type, light and dark.

**Out of scope:** "also send to chat", quote-reply, thread notifications (LIME-102 adds those).

**Phase 3: verification.**
- `cargo test` (thread queries, ordering, counts);
- the iOS tests + UI tests (reply → the summary updates → open the thread → reply live);
- the local two-account e2e;
- 0 warnings;
- screenshots.

**Gate (the user):**
- reply in a thread from one phone; the other phone shows "1 reply", opens the thread, replies back;
- **links are green and clearly different from underlined text** in both bubble types, light and dark.

**Record:** a `## LIME-101` entry in `TEND.md`. Commit: `feat: reply threads (encrypted thread_root, summary, thread screen)`, trailer `Brief: LIME-101`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

---

**Update: LIME-97 landed as `54c0a43`** (pushed and verified; no server change).
- Client-managed signed group-op log replayed in HLC order; Megolm with one shared ciphertext; rotation on membership change / 100 messages / 7 days; late joiners can't read history; removed members can't read what follows.
- **An admin query confirms no server table holds groups, members, group names or message text.**
- New Group (chips → name + emoji → Create); Group details (rename/remove/add/leave); system lines; groups from non-contacts go to Requests.
- 117 Rust / 6+6 integration / 176+60 iOS tests pass; 0 warnings.
- **Known limits, documented:**
  - a replaced phone must be removed and re-added;
  - stale sessions persist until a member hears of a removal;
  - unaccepted key-change members are skipped;
  - no admin-promotion UI;
  - emoji-only group photo.
- **Follow-ups to queue later:** a "make admin" UI; auto-rejoin after a phone replacement (with device linking).
- Awaiting the user's gate (two phones + the simulator or a third device with a plus-address account).

**STANDING RULE (the user, 2026-10-08): iOS verification is tiered, to save time.**
- **Each brief:** the full unit + UI suite on **one** simulator (the iPhone 13 mini, 375pt), plus **only the new or changed UI tests** on the SE (iOS 18.3) and the 18 Pro; `check-warnings.sh`; `check-release-no-bluetooth.sh`; the server/core/e2e tests as relevant.
- **The full three-simulator matrix only:** before TestFlight, at the end of a chain, or when a brief changes layout broadly.
- This applies to every brief from LIME-98b on; the briefs' "three simulators" wording is overridden by this rule.
- **Addition (2026-10-09; the user asked "why so long?" during LIME-107, at 1 h+):**
  - **when a test fails, fix it and re-run ONLY that test (`-only-testing`) until it passes; run the full 13 mini suite once, at the end.**
  - Don't re-run whole suites to check a single fix.
  - Prefer briefs that are small enough to finish in ~30–45 min.
- **Addition 2 (2026-10-09, the user asked again during LIME-107-qa2, at 1 h 22 m):**
  - **time-box test debugging to about 15 minutes per failing test.** If a layout/pixel assertion still fails on one device after that, loosen its tolerance, or skip it on that device with a comment + a `TEND.md` note, and move on.
  - **Never spend longer debugging a test than building the feature.**
  - **The brief soft-caps at about 60 min:** at that point, commit what's verified and report the rest as follow-ups.

**The user's gate on LIME-97: "groups look great".**

**Update: LIME-97b landed as `f7a0dc2`** (pushed and verified).
- Invite via the system contact picker → Messages/Mail/Share from the teacher's phone; My QR Code; Scan QR (verified in person / mismatch warning / key-change accept).
- 119 Rust tests pass; iOS UI tests pass on the 18 Pro/13 mini; **the SE full suite was not re-run after the invite-row fix** (re-run it in the next brief).
- **`invite-site/` (static) is committed but not hosted.**
- **Plot's call on hosting: DEFER until just before TestFlight.** Nobody can install Lime from a link yet, so the page only says "coming soon".
  - Note: Cloudflare Pages can't serve the **apex** `limechat.org` while DNS is on deSEC (apex custom domains need a Cloudflare zone; deSEC has no ALIAS/CNAME flattening). `www` via CNAME works.
  - **Decide at TestFlight time:**
    - (a) Cloudflare Pages on `www.limechat.org`, and switch `InviteLink.host` to `www`; or
    - (b) GitHub/Codeberg Pages for the apex via A/AAAA records in deSEC (a `404.html` fallback for `/u/*`).

    Either way, the same site should also host `/privacy` and `/terms` (the release checklist). **Never delete the `send.limechat.org` email records.**
- The user's gate is pending: invite text, QR verified in person, foreign-code warning.

**Update: LIME-98b landed as `08261a8`** (pushed and verified).
- Public avatars + ciphertext blobs; a profile key shared alongside the delivery key; contacts-only encrypted photos; edit/crop/remove; visibility setting; EXIF stripped.
- 41 server / 125 Rust / 7+7 integration tests pass; tiered iOS passed; the SE 97b suite passed (66).
- **Plot found a UX bug in tend's gate advice:** photos refresh **at most hourly**, and tend suggested Jean "sign out and in, or reinstall" to see changes. **That would wipe Jean's keys** (the LIME-95-fix semantics) and trigger "security key changed" for her contacts.
  - **LIME-98b-fix is drafted:** a live photo-change notice + pull-to-refresh.
  - **Also:** the blob expiry cron isn't scheduled yet (fold it into 98c); the CDN cache is ≤ 60 s (unmeasured).

**LIME-98b-fix landed as `c63e2d1`** (pushed and verified): a `profile.changed` notice to accepted contacts; pull-to-refresh and chat-open refresh photos (≤ 1/min each); the bad sign-out advice was removed. 128 Rust tests pass; integration 7/7; tiered iOS passed. Awaiting the user's two-phone photo gate. **Next: LIME-98c (attachments + voice).**

**Update: LIME-98c (photos + files) landed as `888e5c7`** (pushed and verified). Voice + video were split out to **LIME-98d**.
- 1 MiB-chunk AES-GCM encryption with a resumable upload; the key/digest/2 KB thumbnail live only in the encrypted message; album/viewer/Quick Look.
- **Blob sweep:** delete 1 h after the last recipient fetches, after 30 days, or after 1 day if the upload never finished; pg_cron every 15 min (`supabase/schedule-sweep.sh`).
- 47 server / 136 Rust / 8+8 integration tests pass; tiered iOS passed; 0 warnings.
- **Gaps → fold into LIME-98d:**
  - **the Replies (thread) composer has no "+"**;
  - no resumable download;
  - no progress %.

**LIME-98d landed as `73b5be0`** (pushed and verified).
- Voice (hold/cancel/lock, AAC ~24 kbps, a speed cycle, auto-play of the next), video (720p, ≤ 3 min/50 MB, metadata dropped, a full-screen player), "+" and mic in Replies, chunk-resumable downloads, progress rings.
- 139 Rust / 9+9 integration tests pass; tiered iOS passed (75 UI); 0 warnings.
- **The user's gate (2026-10-09): "audio and video works great for v1".** Next: LIME-104.

### LIME-98d → `tend` (lime-aa) (landed as `73b5be0`): voice messages + video (split from 98c), plus the 98c gaps
- **Build the voice and video parts of the LIME-98c brief exactly as specified there:**
  - voice: hold the mic to record, slide to cancel/lock, a waveform bubble, 1×/1.5×/2× speed, auto-play the next;
  - video: record/pick, 720p, max 3 min / ~50 MB, poster + duration, a full-screen player.

  Both use the 98c pipeline.
- **Also:**
  1. **add "+" (attachments) to the Replies/thread composer;**
  2. **resumable downloads** (by chunk);
  3. **a progress indicator** (a percentage ring) for uploads and downloads.
- **Phase 0:** commit `PLOT.md` unedited. Survey 98c's pipeline first.
- **Verification:**
  - the tiered iOS rule;
  - the integration e2e (a voice note + a short video through staging; ciphertext only);
  - UI tests for the record/cancel/lock gestures;
  - 0 warnings.
- **Gate:** send Jean a voice message (try 2× speed) and a 30-second video; attach a photo inside a Replies thread.
- **Record:** `## LIME-98d`. Commit: `feat: voice messages and video; attachments in threads; resumable downloads with progress`, trailer `Brief: LIME-98d`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

**The user's gate on LIME-98c (2026-10-08): "all media files look good"** (several image sets + files).

### Open thread: positioning (the user asked 2026-10-09: "what makes us stand out vs Signal, bitchat, Telegram, WhatsApp, Messenger?")
**Plot's answer:**
- **No single feature is unique;** Lime's edge is the **combination** + **who it's for** + **who owns it**:
  1. built for and **owned by teachers** (a co-op nonprofit, no ads, never sold);
  2. **connects teachers across schools/districts** (school apps are walled; general apps have no teacher layer);
  3. **works when networks fail** (the proven BLE receive while locked; mesh coming);
  4. **private by design**, Signal-grade (E2EE + a blind mailbox + sealed sender) but with teacher-friendly features (threads, formatting, PD calls);
  5. **safety for a profession around kids** (no public stranger channels; Requests; block; verified teachers later).
- **Honest risks:**
  - the network effect (WhatsApp/Messenger are where people already are);
  - **Signal could add mesh**;
  - the edge must deepen through teacher-specific value.
- **The user (2026-10-09): "love all 1–6; prioritise them."** Plot's proposed priority (awaiting confirmation):
  - **before TestFlight:**
    - **(2) work-hours boundaries** (local-only, cheap);
    - **(1) emergency "I'm safe" mode** (built with or right after mesh v1);
    - **(6) multilingual-ready** (all strings in String Catalogs now; the first translation, likely Spanish, later);
  - **around launch:** **(3) verified teacher** (needs a verification method + a process);
  - **after launch:**
    - **(5) PD sessions** = group calls (LiveKit, the paid account, CallKit);
    - **(4) communities** (needs a design pass: discoverability vs the blind server; scale beyond Megolm's comfort → MLS?).
- **The user's answers (2026-10-09):**
  1. **Bring back the web prototype's status icons** (LIME-57 series: Slack-style status badges in a cut-out notch at the avatar's bottom right: active, away, busy/DND "z" in Montserrat Bold, offline).
     - **Plot's privacy design (to confirm):** **a manual status + work-hours status shared only with contacts** via an encrypted control op (like `profile.changed`).
     - **No live "online now"/"last seen" by default**, since the server would learn activity patterns and contacts could track when teachers are on their phones. **An opt-in later at most.**
  2. **Work-hours boundaries: yes.**
     - **Where:** Settings → **Work hours** (a weekly schedule + "after school" quiet hours; notifications held, a gentle auto-reply option later);
     - a **quick toggle** by tapping your own avatar (set status: Available / Away / Do not disturb / quiet hours until …);
     - **contacts see the "z" badge** + "Quiet hours until 7:00" in the chat header;
     - **emergency messages break through** (ties to emergency mode).
  3. **Languages: the user will choose the first ones** (asked).
  4. **Verified teacher: start now, while small.** The method is to be chosen (a decision surface was given).
  5. **PD sessions = the large-session mode on top of calls** (1:1 voice/video + group calls are already planned): 50–100 people, hosts, mute-all, raise hand, screen share, speaker view.
  6. **Communities (the user's concept):** a **community = a collection of groups**, with:
     - a **bulletin board for announcements** (admins post; members read/react);
     - **groups inside it you can browse, join and pin**, each with its own chats and threads.

     It needs a design pass (discoverability vs the blind server; scale).
- **Follow-ups (the user, 2026-10-09):**
  1. Status icons: **yes**, as plot designed (manual + work-hours status, contacts only, encrypted; no live presence by default).
  2. Work hours: **yes**. Also **make Sign Out more discoverable** (a red "Sign out" row at the bottom of Settings, keeping the honest confirmation about keys).
  3. **Spanish first.**
  4. **Instead of formal verification now: a private custom label/nickname per contact**, shown next to their name, visible **only to you** (it's local, encrypted, syncs to your own devices later). **A formal "official teacher" label is deferred** until the team grows.
  5. Understood (PD = the large mode on calls).
  6. The user said "example of an early prototype" for communities, **but no image was attached**. Ask for it.
- **NEW IDEA from the user: JAM reimagined** (it replaces the old Miro-like whiteboard idea). **"Lime's imagination of Substack/Patreon with our values"**: teachers write daily, encourage each other, build community around their expertise, publish as writing + media or podcast (video too), and **optionally monetise**. The user's insight (they were an early designer at Teachers Pay Teachers): **"teachers learn best by watching teachers teach: modeling is pd."**
  - **Plot's view (given to the user):** strong mission fit and a real differentiator; **sequence it after messaging + communities** (the community bulletin board is a proto-Jam).
  - **Flags:**
    - (a) **"Always free" (memory):** Lime takes **0%**; monetisation is teacher-to-teacher only, opt-in; prefer **tips/support** over paywalls (avoid recreating TpT's teachers-charging-teachers dynamic). The user decides.
    - (b) **Apple IAP rules** for digital subscriptions in an iOS app (research the current US external-link rules) + payouts/taxes (Stripe Connect, 1099-K) → the LLC.
    - (c) **Student privacy:** teaching videos show students, so consent/blur tooling + FERPA/COPPA guidance are required before video "modeling" posts.
    - (d) **Public publishing ≠ E2EE:** a separate privacy model (public by design), with moderation (App Store 1.2).
    - (e) **It's a second product:** validate with a small cohort first.
- **The communities mock (received 2026-10-09; a wireframe; the user prefers the current design system, but it has good takeaways):**
  - **Home/discover:**
    - a "lime ⌃" switcher;
    - "Search anything" + mic + filters;
    - a horizontal row of **joined community cards** (image, name, member avatars + count, "✓ Member");
    - a **masonry feed of posts** from communities (image, caption with @mentions, likes, the community chip);
  - **A community page:**
    - a banner + a logo, name, description, members, ✓ Member;
    - **Bulletin Board** (unread count);
    - **Starred** groups;
    - **Groups** list (Announcements, NYC Teachers, Bookclub…) with last-message previews/times/unreads;
  - **The bottom nav: Link · Jam** (this predates the current link/jam/call dock).
  - **Takeaways for the communities design pass:** joined cards; a bulletin board pinned at the top; Starred (pinned) groups; the community feed as the bridge into Jam.
- **Communities vs groups (explained to the user):**
  - groups are invite-only, ≤ 100, everyone sees everything, and the server knows nothing;
  - communities are larger (hundreds to thousands), **joinable** (open or by approval), contain **several channels** (announcements-only + topics), and have moderation roles.
  - **The tension:** being discoverable means *something* about the community (at least its name) must be findable, unlike the blind groups. It needs a design decision later.
- **Moat candidates (the user loves all 1–6):**
  - **"Verified teacher"** badges;
  - **work-hours boundaries** (scheduled quiet hours / "after school" mode; teacher burnout is real);
  - school/district/subject **communities**;
  - **PD sessions** (50–100-person calls);
  - **emergency mode** (a school lockdown or disaster: one-tap "I'm safe" broadcast over the mesh to your staff group);
  - **multilingual** (teachers worldwide).

### DESIGN-06 notes (plot, 2026-10-08): learnings from the bitchat whitepaper for mesh v1
**Source:** the bitchat `WHITEPAPER.md` (the user asked how Lime compares). Feed this into the mesh v1 design brief.

**Adopt (adapted to Lime):**
1. **Store-and-forward budgets** (bitchat's courier):
   - a bounded relay pool with **trust tiers** (accepted contacts get more slots than "any Lime phone", per D6 = A);
   - **spray-and-wait copy budgets** (start at 4, cap 8, hand half to each courier met);
   - a per-recipient outbox cap (~100 per peer), a resend cap (~8 tries);
   - **DECIDED (the user, 2026-10-08): the mesh carry time is 1–2 days** (it replaces DESIGN-01's 72 h). **Implement it as a 48 h maximum,** with relays allowed to drop earlier under storage/battery pressure (oldest/lowest-trust first).
2. **The TTL policy:** start at 7 hops, **cap to ~5 in dense graphs** (≥ 6 links); relay with **random 10–220 ms jitter**; **dedupe with an LRU seen-set** (~1000 entries, 5 min) keyed on the envelope digest.
3. **A rotating recipient tag on the air:**
   - Lime's outer envelope carries `to_device` in the clear (fine for the server, **a leak over BLE**, since anyone nearby could map who's receiving);
   - **over the mesh, replace it with a daily rotating tag = HMAC(recipient key, UTC day)**, computable only by people who already know the recipient's key.
4. **Pad every mesh envelope to buckets** (256/512/1024/2048 B, then 4 KiB steps); bitchat pads only some types and admits the size leak.
5. **Battery:**
   - RSSI-gated connections;
   - duty-cycled scanning;
   - announce backoff (fast when isolated ~4 s, then ~15–30 s jittered when connected);
   - combine with the LIME-103b evidence (~1.4%/h as a receiver).
6. **Fragmentation** for the GATT fallback (~470 B fragments, reassembly limits: concurrent assemblies, a 30 s timeout, a size cap). **L2CAP remains the primary path** (our spike: 4–5× faster).
7. **Media over the mesh:** text-only couriers in v1 (already decided); later small media with an explicit accept and a ≤ 1 MiB cap.

**Avoid (bitchat's own admitted weaknesses):**
- a **static on-air sender ID** (trackable across places) → **Lime uses rotating ephemeral BLE identities**;
- **cleartext announcements with nicknames and neighbour lists** (they reveal participants and the local graph) → **Lime announces nothing human-readable and no neighbour lists**;
- **no forward secrecy for sealed courier mail** → Lime's envelopes are Olm/Megolm ratchet ops, so FS holds over the mesh too. **Offline first contact still needs QR** (DESIGN-04).

**Not for Lime:**
- **anonymous public/geohash location channels** (a safety risk around schools and minors; it conflicts with the teacher identity model);
- **a Nostr fallback** (Lime has its own mailbox);
- a **panic wipe** exists in spirit as the planned "Erase Lime from this phone" (separate from sign-out); keep it on the list.

**Range:**
- the BLE single-hop range indoors is roughly a room to ~30 m; our test delivered **through a wall at −83 dBm**;
- **range grows by hops, not by radio power**;
- iOS doesn't let apps choose BLE Long Range (Coded PHY), so multi-hop density is the lever. Unverified beyond our tests.

### LIME-107 → `tend` (lime-aa) (queued after 106; the user asked "where are files saved? what if they're low on memory?")
**Facts given to the user:**
- received files are decrypted, checked and **kept in each phone's encrypted Lime store**;
- the **server copy is deleted ~1 h after every recipient has downloaded it** (or after 30 days);
- **so the phones hold the only copies.** If a phone is lost before the recovery backup (D5) exists, its media is gone; the other person's copy remains.

**Brief contents (draft):**
- **Settings → Storage:**
  - the total Lime usage, and per-chat usage (largest first);
  - review and delete media per chat (multi-select);
  - **"Keep media": Forever / 1 year / 30 days** (auto-delete older local media; the messages stay with a "Media removed" placeholder).
- **Auto-download:** Photos (Wi-Fi + mobile / Wi-Fi only / never); Video & files (Wi-Fi only by default); voice always.
  - **When not auto-downloaded:** a tap-to-download placeholder with the size; **"Available until <date>"** because the server deletes it after 30 days (or 1 h after everyone else fetched it, which only counts devices that downloaded).
- **Low storage:**
  - check the free space before each download/attachment send;
  - **below ~500 MB free:** pause auto-downloads, show a gentle banner ("Your iPhone is almost full. Lime paused downloads."), and **never crash or corrupt the DB**: fail the single download cleanly and keep it retryable while the server copy exists.
  - Test with a simulated full disk.
- **Never** let iOS purge chat media silently (it's not in Caches); it **is** excluded from iCloud backup (encrypted; recovery comes via D5).

### BUG (the user, 2026-10-09): notifications only appear when the app is open on Jean's phone and the iPad (no badge, banner or lock screen); sometimes on Shem's
**Plot's diagnosis (expected behaviour, not a regression):**
- **There is no push yet** (APNs needs the paid Apple account).
- LIME-102 only shows notifications while Lime is open or **in the short window after leaving it**; after that iOS suspends Lime, and nothing arrives until it's opened.
- **Shem's phone "sometimes" works because its Auto-Lock is set to Never**, and/or Lime was recently used.

**Fix = APNs (stage 2)** once the paid account exists (**the user's November enrolment**): content-free pushes + a Notification Service Extension that decrypts on the device.
- **Make it the first brief after enrolment.**
- **Interim:** QA item 13 (an honest note in Settings → Notifications).

**LIME-104 landed (pushed):**
- **The code is in `cef2bf3` (mis-titled "chore: update PLOT.md"); `8f23116` is an empty commit carrying the proper message + `Brief: LIME-104`.**
- **Plot's call: keep the history** (no force-push). It's documented here and in `TEND.md`. Lesson for tend: commit `PLOT.md` with `git add PLOT.md` only (never `-A`/`.`) in Phase 0.
- All 13 items are built (the honest notification note = item 13; tend's report said twelve, so plot to verify at the gate).
- 145 Rust / 10+10 integration tests pass; tiered iOS passed (84 UI); 0 warnings.
- **Known:** a removed member keeps the key to the current group photo until it changes; Delete is local only.
- **The user's concept image `docs/design/concepts/communities-early-concept.png` is untracked**: commit it in the next Phase 0 (a design asset).
- **Also LIME-103c (both asleep, offline) results were relayed to the user:**
  - sender delivered 46/68 eventually; the receiver had 23 on time;
  - gaps up to ~3 h 20 m; bursty delivery.
  - **Design implications for mesh v1:** a "Nearby mode" (keeps Lime awake); emergency mode enables it; catch-up on wake; honest copy.
  - **The 103c analysis landed as `65236c5`** (`docs/spike-ble.md` §5b + a script; logs in `~/Downloads/ble-logs-103c/`).
    - **Both asleep:** the sender suspended for 3 h 14 m, until a BLE discovery woke it (05:24), when 44 queued blobs flushed; then again only at the unlock.
    - **All 69 delivered, none lost; only 3 on time; median 1 h 10 m late, max 3 h 08 m.**
    - **The first sighting of an iOS relaunch for Bluetooth:** B's process ended and was relaunched, then received 16 while locked (one observation).
    - B's log had a 4 h 57 m gap (writer issue; fixes listed for any rerun).
    - **Both phones were actually unplugged** (per the logs).
  - **MESH v1 DESIGN RULES (plot, final; for the mesh brief + `architecture.md` §7 update):**
    1. **Nearby mode** (keeps Lime awake, clearly labelled, with a battery note);
    2. **emergency mode turns it on**;
    3. **flush the whole queue on every wake/discovery**;
    4. **no timers that depend on a suspended app**;
    5. **the product promise:** "delivered when phones meet and at least one is awake", **never prompt delivery between two locked phones**.
  - The spike series is complete. Next for the mesh: the v1 design brief after 105–109.

**LIME-106-fix landed as `89ef075`** (pushed and verified).
- Reactions under the bubble in the footer row (chips leading, time trailing; soft grey; 5 + "+N"); a 16 pt row gap; a horizontal emoji row in the viewer; Messages list breathing room + an unread gutter; **no dividers/arrows** (also New Message action rows and Group details members); a chat side margin of 20; the Replies context card + a "Reply to" strip.
- **⚠ Item 0 (the forward status bug) was NOT addressed:** the report and commit don't mention it (iOS-only, no core change). Tend started before item 0 was added and apparently didn't get the relay. **→ LIME-106-fix2.**
- **Tend's questions:**
  - the Messages-list reply rows (the user to confirm (a) or (b));
  - the **Settings chevrons are still present** (the exception in the brief): ask the user.

### LIME-110 → `tend` (lime-aa) (after 108 + the chime): the Jam MVP (public-by-design teacher publishing)
**Per DESIGN-07 + the decisions J1 = A, J2 = B, J3 = required, J4 = ok.** It may be split (110a feed/composer/posts/articles; 110b record/comments/moderation) at a clean boundary; say so.

**Phase 0:** `git add PLOT.md` only. **Phase 1:** survey the dock's jam tab, the 98c/98d media pipeline, the Markdown subset, the profiles, and the Supabase patterns. Note that **Jam is NOT E2EE**: a separate, readable-by-server model, with RLS-enforced visibility. If anything conflicts, **stop and ask the user**.

**Phase 2:**
1. **Server (new tables + functions; RLS: readable only by signed-in, verified-session users per J1 = A; writable by the owner):**
   - `jam_posts` (author, kind = post|article|recording, title?, body (the Markdown subset), media refs, created/edited, hidden flag, a student-privacy attestation timestamp);
   - `jam_follows`, `jam_likes`, `jam_comments` (one level of replies);
   - `jam_reports` (target post/comment, reporter, reason);
   - **media in a separate public-to-signed-in bucket `jam-media`**, not the E2EE `blobs` bucket; EXIF stripped on the device.
   - **Auto-hide** a post/comment after **3 distinct reports** (config).
   - **A small admin review page** (an Edge Function + a static page, protected by an allow-list of admin user ids: the user and Jean) to list reports and hide/unhide/delete content.
   - Rate limits.
2. **iOS:**
   - **Jam tab = a feed:** "Following" and "Discover" (recent), with cards: author, time, title/excerpt, a media preview, ♥ count, the comment count.
   - **The composer** (the user's reference, in Lime's style):
     - Cancel / ⋯ / **Drafts** (local);
     - "What's on your mind?" + photo / camera / formatting;
     - CTA cards **Write an article** (a title + cover image + the long-form editor), **Record** (video or audio ≤ 3 min via the 98d pipeline), **Go Live** (a "coming soon" sheet).
   - **The required student-privacy check** before any media post: "No students can be identified (faces, names or voices)" + a link to guidance (a short in-app page).
   - **Post detail:** the full article/post, ♥ like, **comments** (newest first, one level of replies), Report on posts and comments.
   - **Profiles:** a teacher's Jam page (bio = the About, posts, Follow).
   - **Report:** reasons (student privacy, harassment, spam, other).
3. **Docs:**
   - `docs/jam.md` (the privacy model: public to signed-in teachers; not E2EE; moderation);
   - `architecture.md` (a section on Jam's separate model);
   - `release-checklist.md` (the moderation process documented; a content policy page on limechat.org).

**Out of scope:** money, live streaming, web visibility, podcasts as feeds, notifications for Jam (later).

**Verification:**
- server tests (RLS: anon can't read; signed-in can; owner-only edits; auto-hide at 3 reports; the admin allow-list);
- core/integration (2 accounts: post, follow, like, comment, report, hide);
- UI tests (composer flows, the privacy check blocks a media post until ticked, Drafts persist);
- tiered iOS; 0 warnings.

**Gate:**
- write an article with a cover image → Jean sees it in Following;
- Jean likes and comments;
- post a recording (the privacy check is required);
- report a test post 3 times (3 accounts) → it's hidden → it appears in the admin page.

**Record:** `## LIME-110`. Commit: `feat: Jam MVP (posts, articles, recordings, follows, likes, comments, moderation)`, trailer `Brief: LIME-110`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

**LIME-107 landed as `3a5ec16`** (pushed and verified).
- **Item 0:** the Kakao-style reply rows (the core now carries the replied-to id); Forward is disabled for gone, never-opened files (a new cheap `info` action, deployed to staging).
- **Storage:** usage per chat; remove media; Keep media (forever / 1 y / 30 d); auto-download defaults; placeholders with "Available until"; low storage (< 500 MB pauses downloads; < 50 MB refuses before writing).
- 48 server / 13+13 integration tests pass; tiered iOS passed; 0 warnings.
- **One UI check was dropped** (the Forward-enabled long-press on the SE/18 Pro is flaky; covered by core tests). Took 1 h 28 m.
- **Next: LIME-107-qa.**

**LIME-107-qa landed** (iOS only; 46 min).
- Unread = dot + bold + count; manual unread = dot only; **the dock badge now counts unread chats** (it used to sum messages: the root of the mismatch).
- A 16 pt page margin with the dot hanging; **the avatar is at x = 16 vs the logo glyph at x = 21: the user should check by eye**.
- The landscape list stops before the "+".
- The message-group alignment test was added (tend couldn't see the screenshots: plot to remind the user to report if anything still looks detached).
- The reply summary is "1 reply · 6:35 PM", regular weight.
- **Next: LIME-108.**

### LIME-107-qa → `tend` (lime-aa) (landed): (right after LIME-107; tend was mid-107 when these arrived): the unread system, row alignment, the message-group footer, the reply summary
**The user's QA (2026-10-09; screenshots of both phones; portrait + landscape):**
1. **One coherent unread system** (today the dot and the count badge disagree: e.g. Jean's phone shows a dot on one chat and a count on another).
   - **Any unread chat shows BOTH:** the left dot **and** the trailing count badge.
   - **"Marked unread" manually:** the dot only (no number).
   - **The dock "link" badge = the number of unread chats** and always matches.
   - The dot, the badge, and bold name/preview text change together when a chat becomes read.
2. **Row alignment:**
   - **the avatar's left edge aligns with the logo button's left edge** (the page margin);
   - **the unread dot hangs in the margin to the left of the avatar** (not a reserved gutter that indents every row);
   - read rows therefore use the full width.
   - Check 375 / 402 pt and landscape.
3. **Landscape:** the "+" button **overlaps the row timestamps** (the user's landscape shot). Keep the floating buttons clear of content (inset the list's trailing edge, or move the FAB), and keep rows a readable width in landscape.
4. **Each message is one visual unit**, so reactions and the reply summary never look detached, **especially after media**:
   - **media + caption + footer (reactions … time) + reply summary** are grouped and **aligned to the same edge** (trailing for own, leading for others; after the avatar column in groups);
   - tight spacing **inside** a message (~4 pt); the larger 16 pt gap only **between** messages.
   - The footer aligns to the message group's own edges, never wider than the widest element, and the chips start at the group's leading edge.
   - The same rules for left and right bubbles.
5. **The reply summary is lighter and shorter:**
   - **regular weight (not bold)**: "**1 reply · 6:35 PM**" (drop "Last reply"; a date instead of the time if it isn't today);
   - the replier avatars stay;
   - **it hugs its content** so it isn't wider than a short bubble, aligned like the footer;
   - both sides.

**Phase 0:** `git add PLOT.md` only. **Verification:**
- UI tests (dot + count together and in sync with the dock badge; avatar x == logo x in portrait; the FAB doesn't intersect any row text in landscape; footer/reply aligned to the message group edge after a video; reply summary text regular weight and format);
- the tiered iOS rule; 0 warnings.

**Gate:**
- unread chats show a dot + a number, matching the dock badge;
- read rows align with the logo;
- landscape has no overlap;
- reactions/replies look attached to their message (incl. after a video);
- "1 reply · 6:35 PM" in regular weight.

**Record:** `## LIME-107-qa`. Commit: `fix(ios): coherent unread indicators, row alignment, landscape FAB, message-group footer, lighter reply summary`, trailer `Brief: LIME-107-qa`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

### LIME-106-fix2 → `tend` (lime-aa) (landed as `edd1071`): the forward status bug (item 0 of 106-fix, not yet done)
**Do exactly item 0 of LIME-106-fix above** (BUG FIRST + UPDATE + UPDATE 2):
- forwards with attachments **arrive**, but the **sender stays on "Sending…" or shows a false "Not sent · Tap to retry"**; find out why they never become "Sent" locally, and fix it;
- **retry on a falsely-failed forward must not send a duplicate** (the user may have a duplicate PDF);
- verify the swept-blob case (forwarding an attachment older than ~1 h after everyone fetched it) as secondary;
- **strengthen the real-server integration test** so it checks the **sender's local status = Sent** after a forward with an attachment, and the receiver gets it once.

**Also (the user, 2026-10-09; it replaces the "↩ Jean: …" row preview): the Messages-list row for reply activity uses the Kakao-style reply context, with no ↩ glyph.**
- The row's preview area shows:
  - **line 1:** a small quote, with a thin vertical quote bar on the left (secondary colour): "**Reply to <root author>** · <root text, or its attachment label>", one line, truncated;
  - **line 2:** the reply itself: "<Name>: <reply text>" (in DMs, just the reply text; "You: …" for your own).
- **Reuse the LIME-106-fix reply-context component** (the same visual language as the Replies header card and the composer strip), scaled for a list row.
- The row height stays consistent with other rows (2 preview lines).

**Phase 0:** `git add PLOT.md` only. **Verification:** core + integration (local + staging) + the tiered iOS rule (+ a UI test: a reply-activity row shows "Reply to …" with no ↩); 0 warnings.

**Gate:**
- forward a photo, an album and a PDF to Jean → each shows "Sent" on your phone within seconds and arrives once;
- a chat with a new reply shows the Kakao-style "Reply to …" quote in the Messages list.

**Record:** `## LIME-106-fix2`. Commit: `fix: forwarded attachments show Sent; no duplicate on retry`, trailer `Brief: LIME-106-fix2`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

### ROADMAP TO APP STORE (the user, 2026-10-09)
"After status and the major QA bugs, incl. chimes, we'll have a complete app. Then a Jam placeholder ('coming soon', a Substack-like teacher pd community), then calls (audio, video, open source, free), then in-app account deletion, report, limechat.org, then TestFlight. **Core app + a marketing experience to capture interest and build community around the App Store release.**"

**The proposed sequence:**
1. **LIME-106-fix** (in progress);
2. **107** storage;
3. **108** status + work hours;
4. **the chime** (when the user's sound file arrives);
5. **LIME-110 Jam placeholder:** the dock's "jam" opens a **coming-soon** screen explaining Jam (a teacher pd community: writing, media, podcasts; "teachers learn by watching teachers") + **"Notify me" / "I want to write on Jam"** interest capture (local opt-in + a mailbox to FAM; **privacy-light**);
6. **calls:**
   - **LIME-111:** 1:1 voice + video, **peer-to-peer WebRTC + TURN** (decided), with CallKit UI;
   - **LIME-112:** group calls on **self-hosted LiveKit** (decided);
   - **Ringing a closed app needs PushKit = the paid Apple account** → full ringing lands with APNs;
7. **LIME-113:** **in-app account deletion** (App Store rule 5.1.1(v)) + **Report user/message** (rule 1.2) + an abuse contact/moderation process;
8. **LIME-114: limechat.org** = the **marketing site** (landing: the mission, the teacher co-op, privacy, offline; a **waitlist/interest form**; the invite pages `/u/<username>`; **/privacy, /terms, /support**). Hosting per the earlier note (www via Cloudflare Pages with a CNAME in deSEC, or GitHub/Codeberg Pages for the apex). **The waitlist store is a privacy decision**: plot's lean is a Supabase table with explicit consent (or Resend Audiences), with a double opt-in;
9. **APNs push** (the paid account);
10. **TestFlight.**

**Change (the user, 2026-10-09): no Jam placeholder; build a small Jam MVP instead.** The user shared a composer reference:
- Cancel / ⋯ / Drafts;
- "What's on your mind?" with photo/camera/formatting/more;
- CTA cards **Write an article · Go Live · Record**.

**→ DESIGN-07 (plot, 2026-10-09): Jam MVP decision surface, awaiting the user.**
- **What Jam is technically:** **public-by-design publishing**, a separate privacy model from E2EE chat. The server stores posts readably so others can read them; **moderation and App Store 1.2 apply in full**.
- **The proposed MVP** (the reference's look in Lime's design system):
  - **the Jam tab = a feed** (posts + articles from teachers you follow, plus a "Discover" tab of recent posts);
  - **the composer**:
    - "What's on your mind?" + photo/camera/formatting;
    - Drafts (local);
    - CTA cards: **Write an article** (long-form editor: title, cover image, the Markdown subset), **Record** (a short video/audio post using the 98d pipeline, ≤ 3 min, the podcast seed), **Go Live** (**"coming soon"** in the MVP: live streaming needs heavy infra; it can piggyback on the LiveKit group calls later);
  - **a profile page** (posts/articles, follow);
  - **likes**;
  - **Report**.
  - **No money in the MVP.**
- **DECIDED (the user, 2026-10-09):**
  - **J1 = A** (signed-in Lime teachers only);
  - **J2 = B (comments now)**;
  - **J3 = required** (a student-privacy check on media posts);
  - **J4 = ok** (report → auto-hide → a FAM admin review queue; the user + Jean are the moderators).
  - Also: **keep the Settings chevrons**. **The Messages-list reply rows get the Kakao-style "Reply to …" quote, with no ↩** (the user changed their mind; in LIME-106-fix2).
  - **Mesh v1 stays before TestFlight.** The user thought it was already done: plot clarified that the spikes were throwaway tests; **mesh v1 itself must still be built** (with emergency mode).
  - **Spanish:** not answered. It stays in the queue (109) before TestFlight unless the user says otherwise.
- **(History) Decisions for the user:**
  - **J1 visibility:**
    - **A.** Readable by **signed-in Lime teachers only** (lean: safer for teachers; no web scraping);
    - **B.** Public on the web too (limechat.org/@user; better for growth/SEO, more exposure).
  - **J2 comments:**
    - **A.** Likes only in the MVP; comments later (lean: moderation load);
    - **B.** Comments now.
  - **J3 student privacy** (lean: required) for any photo/video/audio post: a mandatory check "No students can be identified (faces, names, voices)", plus a guidance link; a posting removes metadata; reported student-privacy posts are hidden pending review.
  - **J4 moderation:** Report → auto-hide after N reports → a FAM admin review queue (a small admin web page); the user agrees to be the first moderator(s).
  - **Where it sits in the order:** after 108 + the chime, before calls (as the user listed).

**ORDER REVISED (the user, 2026-10-09, later), authoritative:**
1. 107-qa;
2. 108 status + work hours;
3. **the chime**;
4. **calls** (111 1:1, then 112 group);
5. **account deletion + Report (113)**;
6. **offline messaging + emergency mode** (the mesh v1 design pass → briefs);
7. **Jam MVP (110)**;
8. **Spanish (109)**;
9. **push (APNs; the paid account)**;
10. limechat.org (marketing/waitlist/privacy/terms; it must precede TestFlight because App Store Connect needs privacy/support URLs);
11. TestFlight.

**LIME-107-qa2 landed as `0e77002`** (pushed and verified; 1 h 53 m).
- The duplicate preview was **an app bug** (line 2 drew text that already held both lines).
- **Reactions in the row:** a core change (`last_reaction`, `activity_at`).
- **The unread bug had three causes, all fixed:**
  - a manual mark wasn't cleared on open (an early return);
  - Replies-only reading left the chat count;
  - a stale reload overwrote "read" after a fast Back.

  The notification badge = the dock count.
- **Landscape:** full width, aligned to the header (38/34 pt on notch phones), "+" beside the dock.
- **Accepted exceptions:** the landscape assertion is loosened to 12 pt; the reaction-row UI test is skipped on the SE.
- 163 Rust tests pass; tiered iOS; 0 warnings.
- **Next: LIME-108.**

### LIME-107-qa2 → `tend` (lime-aa) (landed as `0e77002`): reply duplication, reactions in previews, landscape width
**The user's QA (2026-10-09, screenshots).**

**Phase 0:** `git add PLOT.md` only.

**Phase 2:**
1. **Replies screen:** remove the **"Reply to <Name>" strip above the composer** (too repetitive). Keep only the **header card** ("Replies · <Name>" + quote) at the top.
2. **Messages-row reply preview: a duplicate bug.**
   - Today both lines show "Reply to FAM · <root>"; **line 2 must be the reply itself** ("<Name>: <reply>", "You: …", or the bare text in a DM).
   - Layout:
     - **line 1** = the small quote with a bar ("Reply to <author> · <root>");
     - **line 2** = the reply text;
     - when the reply is short and both fit, they may share a line; **never repeat the same text**.
   - Use "Reply to you" (lowercase) when the root is yours.
3. **Reactions in the Messages preview** (Apple-style):
   - when the latest activity in a chat is a reaction, the row shows "**Jean reacted ❤️ to "True that"**" (or "You reacted 👍 to …"), and the row's time and sort order follow it;
   - **no unread count and no notification for reactions** (per LIME-105); the dot doesn't change.
4. **Landscape layout:**
   - the list must use the **full content width, aligned to the header elements**: the row's leading edge matches the logo, the trailing time/badge **aligns with the right edge of the search/avatar pill**; the scroll indicator sits at the screen edge, not mid-screen (today the 107-qa fix narrowed the list).
   - **Resolve the "+" overlap differently:** in landscape (compact height), **move the "+" into the bottom bar beside the dock** (or into the top pill), and give the list a bottom content inset so the last rows scroll clear of the dock.
   - Portrait is unchanged.

5. **BUG (the user, 2026-10-09): reading a chat sometimes doesn't clear its unread state.** The user opens an unread chat, goes Back, and the Messages row still shows unread (the dot/count/bold), and so does the dock badge.
   - **Reproduce first:**
     - a new message arrives **while the chat is open**;
     - opening via a notification/banner, via search or via a pinned row;
     - reading only the Replies (thread unread vs chat unread);
     - fast Back;
     - an unread mark set manually, then the chat opened.
   - **Report the cause.**
   - **Rule:** opening a chat marks every message visible in it as read **at once**; **returning to Messages always shows the updated state**, with no stale row. The row must refresh on appear, and the dock badge recomputes.
   - Thread replies read inside Replies clear the thread's unread too.
   - A manual "mark unread" is cleared by opening the chat.

**Verification:**
- UI tests:
  - **the unread clears after open → Back in each repro path above** (the row + dock badge);
  - no composer strip in Replies;
  - the row's line 1 ≠ line 2, and line 2 contains the reply text;
  - a reaction preview string;
  - landscape: the row trailing edge ≈ the pill's trailing edge (±4 pt), the "+" doesn't intersect rows, the scroll indicator is at the trailing screen edge;
- the tiered iOS rule; 0 warnings.

**Gate:**
- Replies shows only the header card;
- the reply row shows a quote line + the reply text (no duplicate);
- a reaction shows in the preview;
- landscape rows span to the avatar pill, with nothing under the "+";
- **open an unread chat → Back → the row and the dock badge show it as read, every time.**

**Record:** `## LIME-107-qa2`. Commit: `fix(ios): reply preview duplicate, reactions in previews, Replies strip removed, landscape width, unread clears on read`, trailer `Brief: LIME-107-qa2`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

### limechat.org email (the user, 2026-10-10: "start using limechat.org emails, for the app dev account and others")
**Plot's recommendation:**
- **add limechat.org as a secondary domain to FAM's existing Google Workspace** (famkind.com already uses Workspace MX), at no extra licence cost:
  - **personal addresses as aliases** on existing users;
  - **role addresses as Google Groups** (free).
- **The privacy-brand alternative:** Proton Mail for Business (paid per user); it can migrate later.
- **The DNS goes in deSEC:** Google's verification TXT + MX `smtp.google.com` + the apex SPF `v=spf1 include:_spf.google.com ~all` + Google DKIM `google._domainkey` + update the existing `_dmarc` with `rua=mailto:dmarc@limechat.org`.
  - **This doesn't affect `send.limechat.org`** (Resend uses its own subdomain records).
- **Addresses:**
  - **people:** shem@, jean@;
  - **groups:** hello@ (general/waitlist), support@ (the App Store support URL), privacy@ (the privacy policy, data requests), security@ (`security.txt`, disclosures), safety@ (abuse/reports/moderation; App Store 1.2), accounts@ (**the owner email for service accounts**: Hetzner, Supabase, Resend, deSEC, NameSilo; continuity), dmarc@ (reports).
- **The Apple Developer Account Holder must be a person:** use **shem@limechat.org** as that Apple ID (or the user's own).
- **Later:** move the service-account logins from shem@famkind.com to accounts@limechat.org.
- **UPDATE (2026-10-10):** FAM is **moving off Google Workspace to Nextcloud on a home server** ("email pulling from there").
  - **Plot's advice:** **don't run the limechat.org mail *server* at home**: residential IPs are blocklisted, port 25 is often blocked, it's down when the home server is, and **accounts@/support@/security@ must be reliable** (they're the recovery inboxes for Apple, Hetzner and Supabase). It's the same lesson as the famkind.com DNS-on-web-server outage.
  - **Use a hosted, privacy-respecting IMAP provider and read it in Nextcloud Mail:**
    - **Migadu** (Swiss; priced per domain, not per mailbox; cheap, with unlimited aliases);
    - or **mailbox.org** (German; per user);
    - **Proton is a poor fit** with Nextcloud: it needs the Bridge app for IMAP.
  - **Lean: Migadu.** The same address list; the DNS records come from the provider.
  - Asked the user what "email pulling" means today (IMAP fetch from a provider vs a self-hosted MTA).
  - **The answer:** FAM's mail is **cPanel mail on the KnownHost VPS** (the same server that had the 2026-10-06 outage), sent on via Gmail; they're re-pointing it to Nextcloud.
  - **Plot's advice stands for limechat.org:** host it with a **dedicated mail provider (Migadu)**, separate from the KnownHost web server, so a web-server outage can't take Lime's recovery inboxes down; read it in Nextcloud Mail.
  - KnownHost cPanel mail for limechat.org is an acceptable no-cost fallback, but it **ties limechat.org mail to that VPS**.
  - (Note: plot's 2026-10-06 dig showed famkind.com's MX at Google; the setup may be mid-migration.)
  - **DECIDED (the user, 2026-10-10): Migadu.**
    - **Plot's plan pick: Micro ($19/year:** unlimited mailboxes/aliases, **20 outgoing/day, 200 incoming/day**, 5 GB; no multi-admin**)** to start; **upgrade to Mini ($90/year:** 100 out/day, 1,000 in, 30 GB, multi-admin**) at TestFlight/launch**, when support@/safety@/hello@ traffic grows or Jean needs admin access.
    - **Lime's app emails (sign-in codes) don't count:** they go through Resend on `send.limechat.org`.
    - There's a free trial (no card). **Added to Migadu 2026-10-10** (external nameservers = deSEC; default addresses created; trial until 2026-10-24).
    - **The DNS to add in deSEC (plot's guidance):**
      - apex TXT RRset with **two values**: `hosted-email-verify=…` + `v=spf1 include:spf.migadu.com -all`;
      - apex MX `10 aspmx1.migadu.com.` / `20 aspmx2.migadu.com.`;
      - CNAMEs `key1/2/3._domainkey` → `keyN.limechat.org._domainkey.migadu.com.`;
      - **edit** `_dmarc` to `v=DMARC1; p=quarantine; rua=mailto:dmarc@limechat.org` (Resend's mail is DKIM-aligned via `send.limechat.org`);
      - the optional `autoconfig` CNAME;
      - **skip** the wildcard MX/SRV.
      - **⚠ FOUND (2026-10-10):** Migadu reported "Nameservers missing". **Plot confirmed the deSEC zone serves NO apex NS RRset** (NS queries to ns1/ns2 return NODATA), although .org delegates to deSEC correctly.
        - **Fix:** add NS (subname empty) `ns1.desec.io.` + `ns2.desec.org.` in deSEC.
        - Resolution still worked (the delegation is fine), but checkers that ask for NS fail, and DNSSEC chains want it too.
        - **Fixed 2026-10-10** (the user added NS; plot verified that ns1/ns2 now answer).
        - **shem@limechat.org mailbox created** (2026-10-10). **Jean's mailbox + the aliases are paused:** Migadu requires a card to add more addresses; the user will add it tomorrow.
        - **Migadu domain ACTIVE (2026-10-10 05:33 UTC): "Happy Mailing!"** Next: create the mailboxes (shem@, jean@) + aliases, then connect Nextcloud Mail; then move the service accounts to accounts@.
      - **Done in deSEC 2026-10-10 (plot verified via 1.1.1.1):** MX, TXT verify + SPF, key1–3 CNAMEs, Resend intact. The DMARC still showed the old `p=none` publicly (resolver cache, ~1 h TTL). key4/key5 were added by mistake and then removed.

### Open thread: compliance posture (GDPR, COPPA, FERPA, SOC 2), asked by the user 2026-10-09
**Plot's assessment (not legal advice):**
- **Strengths by design:**
  - E2EE + the blind mailbox (FAM can't read messages or see groups/senders);
  - data minimisation (the server holds ciphertext, delete-after-fetch, 30-day expiry);
  - no ads/tracking/analytics;
  - no contact upload;
  - MFA on the admin accounts;
  - secrets handling;
  - acknowledgements;
  - a planned external security review.
- **COPPA:** applies to services directed at under-13s or knowingly collecting their data. **Lime is adults-only (18+, DESIGN-03), but NO age gate is built yet** → add an 18+ confirmation at sign-up + "not for students" in the terms.
  - **Student data inside messages/Jam:** E2EE means FAM can't access message content; Jam (public) has the required student-privacy check.
- **FERPA/state student-privacy laws (e.g. SOPIPA):** Lime is a teacher's personal tool, not a school-contracted service, so FERPA's school-official model mostly doesn't attach. Still publish **teacher guidance** ("don't share identifiable student info") + Jam safeguards.
  - **If districts ever contract with Lime,** a DPA + student-privacy pledge becomes necessary.
- **GDPR (if EU teachers join):**
  - a privacy policy with the lawful bases;
  - **DPAs with processors** (Supabase, Resend, Hetzner, Apple);
  - EU→US transfer terms (SCCs/DPF; Supabase staging is East US);
  - a records-of-processing doc;
  - **data subject rights:** access/**export** (missing; deletion = LIME-113);
  - a breach-notification process;
  - possibly an EU representative (Art. 27) if EU users are targeted.
  - **CCPA:** nonprofits are generally exempt; revenue thresholds are not met.
- **SOC 2:** an expensive third-party audit (~$20k–80k+/yr incl. tooling) that enterprise buyers ask for. **Not needed for a teacher-direct nonprofit launch;** revisit if districts/partners require it.
  - Meanwhile adopt the practices: a security policy, an incident response plan, access reviews, vulnerability disclosure (`security@limechat.org` + `/.well-known/security.txt`), dependency updates, logging without content.
- **The App Store:** privacy nutrition labels; the account deletion (113); report (113).

**→ Proposed LIME-114b "compliance pack"** (docs + small app items, before TestFlight; with limechat.org):
- **18+ age confirmation at sign-up**;
- **data export** (Settings → Account → "Export my data": the profile + your own local messages as JSON/HTML, generated on the device);
- `docs/privacy-policy.md` + `terms.md` drafts (published on limechat.org; **lawyer review**);
- `docs/compliance.md` (processors + DPAs to sign; records of processing; the breach/incident runbook; the security policy; the student-data guidance);
- `security.txt`;
- the App Store privacy-label answers.
- **The user's actions:**
  - sign the DPAs (Supabase/Resend/Hetzner dashboards);
  - a lawyer review;
  - decide whether EU users are targeted at launch. **DECIDED (2026-10-10): US first.** Stay GDPR-ready (DPAs, export, a policy), but no EU representative or EU-specific work at launch; the App Store availability is the US at first.

**LIME-108 landed as `c58b4cb`** (pushed and verified).
- **Status:** contacts-only encrypted control op (nothing on the server; a test checks it); badges (green / moon / red "z") in a notch everywhere; header text "Do not disturb / Quiet hours until … / Away".
- **The own-avatar sheet** now sets status. **Settings moved into that sheet** (it's a row; the avatar no longer opens Settings directly).
- **Work hours:** off by default; outside hours = DND; notifications are held silently, with one summary at the end.
- **Limits:**
  - holding only works while Lime runs (until APNs + the notification extension);
  - no urgent flag (the mesh/emergency brief);
  - **the badge is SF Symbols + the rounded-black "z", not the web prototype's SVGs/Montserrat** (the user to judge);
  - in the header, a private label and a status share one line (only one shows).
- 166 Rust tests pass; integration passes; tiered iOS; 0 warnings.
- **Ask the user:** is the avatar→sheet→Settings change OK? Does the badge look right?
- **Next: 102b.** (Tend's report said "LIME-109" by mistake; the user's order is 102b → 111.)

**LIME-102b landed as `42400c3`** (pushed and verified; the original m4a files are not in git; over the soft cap, mostly test fixes).
- Sounds: chime (+4.3 dB) / steelpan (quieter; it was already peaking); Lime chime is the default; custom sounds (trim, up to 10, `Library/Sounds`, not uploaded).
- **CallKit can't use custom call sounds** (bundle-only, per the docs; LIME-111 confirms on a device): a custom call sound plays in Lime's own ringing UI, and the system call screen uses the steelpan.
- Per-chat sounds are a follow-up.
- **QA:**
  - (a) chips ≈ 1.1:1 (the root cause was the format-button grey);
  - (b) the Replies heading = avatar + "Replies · Name";
  - (c) the composer no longer hides the newest message (on appear + rotation);
  - (d) Away is a solid amber disc, and the "z" is bigger.
- **Next: LIME-111 (calls); the user needs the Hetzner VPS** (blocked on the user's Hetzner setup; Phase 1 stops for it anyway).

**LIME-102b-fix landed as `096123b`** (pushed and verified).
- **Sound root cause:** no default was stored, and old builds stored "Default". Now there's a registered Lime-chime default, plus a one-time migration of the old "Default".
- The iPad isn't tested by tend.
- The seal is inline after the name, tappable with a date (a core change).
- The emoji-field state deferred.
- Bare URLs are auto-linked.
- **The runtime-warning console check is a follow-up** (needs `log stream`).
- **Next: LIME-111 (calls).**

### LIME-102b-fix → `tend` (lime-aa) (landed as `096123b`): sound default not applied, the iPad seal under the name, a SwiftUI state warning, bare links
**The user's report (2026-10-10, iPhone + iPad + Xcode screenshot).**

**Phase 0:** `git add PLOT.md` only. **Time-box: ~45 min.**

**Phase 2:**
1. **The Lime chime isn't used until the user re-selects it.**
   - On the phone, sounds only worked after Settings → Notifications → tapping a sound and going back; **on the iPad no chime plays on incoming messages**.
   - **The likely cause:** the default is only written when the picker is touched, so the code reading the preference gets nil (= none/default) on upgraded installs.
   - **Fix:** a single source of truth with a **registered default** (`UserDefaults.register` or equivalent) = Lime chime, read by both the in-app banner and the local-notification paths. **A test:** a fresh install and an upgraded install with no stored key both play the Lime chime.
   - **Also confirm the iPad** receives local notifications/banners at all (permission state on iPad), and **report** the iPad specifics.
2. **The iPad shows a seal/check badge under "Shem Rajoon"** in a chat header (the user doesn't know why).
   - **Identify it** (likely the LIME-97b "Verified in person" seal, or the status/label line) and report it.
   - **Design fix:** the verified seal sits **inline after the name** (a small seal icon, with accessibility label "Verified in person"), **not on its own line**.
   - **Tapping it** shows a short explanation ("You scanned Shem's QR code in person on <date>").
   - **The user's note (2026-10-10):** they imagined labels might later carry verification (e.g. the official "teacher" label). **For now, keep them separate:**
     - **the seal = a security fact on this device** ("in-person verified keys"), always an icon;
     - **the label = the user's private text tag.**
   - **Build them as two independent pieces in one name-adornment row** (name · seal · label capsule), so a future official "Verified teacher" label can sit in the same row without redesign. Revisit after the user sees it.
   - If it is **not** verification, fix whatever it is.
3. **The Xcode runtime warning:** "Modifying state during view update, this will cause undefined behavior" at `ProfileScreens.swift` `EmojiKeyboardField.Coordinator.textFieldDidEndEditing` (`parent.isActive = false`).
   - Defer the state change (e.g. `DispatchQueue.main.async` / a `Task { @MainActor in … }`), and fix the same pattern anywhere else.
   - **Add runtime-warning checking to the UI test run if feasible** (fail on "Modifying state during view update" in the logs).
4. **Bare URLs aren't linked:** typed "https://famkind.com" / "HTTPS://famkind.com" render as plain text.
   - **Auto-link bare http(s) URLs** (case-insensitive scheme) in bubbles with the link style (green, underline, tappable, the same confirmation);
   - it works in your own chat too;
   - the link-card generation also triggers for bare URLs when the setting is on (not for your own chat, which is local).

**Verification:**
- unit/UI tests for each;
- the Xcode console shows no "Modifying state during view update" during the UI suite;
- tiered; 0 warnings.

**Gate:**
- on the iPhone **and the iPad**, the chime plays for incoming messages without touching Settings;
- the iPad header shows the seal inline (or the badge is explained/fixed);
- typed links are green and tappable.

**Record:** `## LIME-102b-fix`. Commit: `fix(ios): default sound applied, verified seal inline, state warning, auto-linked URLs`, trailer `Brief: LIME-102b-fix`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

### LIME-102b → `tend` (lime-aa) (landed as `42400c3`): Lime's own sounds: the message chime + the call ringtone
**The user provided (2026-10-09), on their Desktop:**
- `~/Desktop/lime-message-chime.m4a`: **1.2 s**, stereo AAC 44.1 kHz, 18 KB;
- `~/Desktop/lime-call-steelpan.m4a`: **25.9 s**, stereo AAC 44.1 kHz, 410 KB (a steelpan ringtone, for calls).
- **Rights confirmed by the user (2026-10-10): "chimes are good".** A more produced version will come later (it will drop in by replacing the CAFs).

**Phase 0:** `git add PLOT.md` only.

**Phase 2:**
1. **Convert** with `afconvert` to Apple-friendly CAF (linear PCM or IMA4, mono is fine), **keeping the originals out of git** (only the converted CAFs are committed):
   - `ios/Lime/Resources/Sounds/lime-chime.caf` (≤ 2 s);
   - `lime-ring.caf` (**< 30 s**, which iOS requires for notification sounds; this one is 25.9 s, so OK).
   - Normalise loudness so neither is jarring (about −16 LUFS integrated; a brief peak check).
   - Record the conversion commands in `ios/Lime/Resources/Sounds/README.md`.
2. **The message chime:**
   - **"Lime chime" becomes the default Sound** in Settings → Notifications (options: Lime chime / Default / None);
   - used for local notifications (`UNNotificationSound(named:)`) and the in-app banner sound;
   - **the silent switch is respected.**
3. **The call ringtone:** set as the **CallKit `ringtoneSound`** for incoming calls once LIME-111 lands (wire the constant now; LIME-111 uses it); it loops while ringing.
4. **Remove the "honest note" wording** about the missing chime if any.
5. **Custom sounds (the user, 2026-10-09: "be able to add their own custom message and call chimes"):**
   - **Settings → Notifications → Message sound / Call sound:** a list of built-ins (Lime chime, Default, None; for calls: Lime steelpan, Default) + **"Add your own…"**.
   - **Add your own:**
     - pick an audio file (the document picker: Files, Voice Memos exports, music the user owns; no Apple Music DRM files);
     - **trim it** (a simple start/end trimmer with a preview; **max 2 s for messages, < 30 s for calls**);
     - name it;
     - Lime converts it to CAF and saves it in the app's **`Library/Sounds`** directory (where iOS looks for custom notification sounds).
   - **Custom sounds stay on this phone** (not uploaded, not synced; excluded from backup like other media).
   - Delete or rename a custom sound; the max is 10.
   - **Verify in Phase 1** whether CallKit's `ringtoneSound` can play a file from `Library/Sounds` (Apple documents it as an app-bundle sound). **If not:** the custom call sound applies to the in-app ringing UI only, and CallKit uses the Lime steelpan. **Say which in the report.**
   - **Per-chat sounds are optional** (a chat's ⋯ → Notification sound), if cheap; otherwise list it as a follow-up.

**Verification:**
- a unit test that the bundle contains both CAFs with durations < 30 s / ≤ 2 s;
- a UI test that Settings shows "Lime chime" selected by default;
- tiered; 0 warnings.

**Also folded into 102b (the user's QA, 2026-10-10; tend was mid-108):**
- **(a) Reaction chips lighter still:** the grey behind the emoji is still too dark. Make the fill **very subtle** (about 1.1–1.2:1 against the canvas, a warm neutral; yours a touch deeper), so **the emoji itself is the clear element**. Light and dark. Update the token test bounds.
- **(b) The Replies header = the context:**
  - **remove the separate "Replies · Name + quote" card**;
  - **put the context in the nav title area instead**, replacing the plain word "Replies": **the root author's avatar + "Replies · <Name>"** (like the chat header's avatar + name), with "N replies" as a small subtitle;
  - **no quote** (the first bubble already shows the root message).
- **(c) Landscape in Replies (and chats):** the floating composer **covers the messages** (the user's landscape shot shows the composer over "2 replies"). Give the message list a bottom content inset equal to the composer height + its margin, so the content scrolls clear; the same in portrait if it ever overlaps.

- **(d) Status badge polish (the user, 2026-10-10, after LIME-108):**
  - ~~the status badge slightly smaller~~ **(withdrawn by the user: keep the current badge size)**;
  - **on your own avatar in the Messages header, the "Away" badge has a transparent background**: make it **solid**, matching the badges on other avatars (the notch/ring colour = the surface behind);
  - **the "z" in Do not disturb a tiny bit bigger** within its badge.
  - Check light and dark, at all avatar sizes.

**Gate:**
- **(QA)** your own Away badge is solid (the badge size is unchanged); the DND "z" is a touch bigger;
- **(QA)** emoji chips are subtle with the emoji prominent;
- **(QA)** Replies' heading shows the avatar + "Replies · Name", with no card;
- **(QA)** in landscape nothing hides under the composer;
- a message arrives while Lime is in the background → the Lime chime plays; Settings → Notifications → Sound shows Lime chime;
- **add your own message sound** from a file, trim it to 2 s, select it → the next message plays it.

**Record:** `## LIME-102b`. Commit: `feat(ios): Lime message chime and call ringtone, plus custom sounds`, trailer `Brief: LIME-102b`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

### LIME-111 → `tend` (lime-aa) (after the chime): 1:1 voice and video calls (peer-to-peer WebRTC, E2EE, CallKit)
**Decisions already made:**
- 1:1 = **peer-to-peer WebRTC with a TURN fallback**; group = self-hosted LiveKit (LIME-112);
- **open source and free**; no recording.

**Phase 0:** `git add PLOT.md` only.

**Phase 1: survey + one stop.**
- Survey: the WebRTC for iOS options (Google's BSD-licensed WebRTC via a maintained prebuilt Swift package); CallKit; AVAudioSession; and how call signalling can ride Lime's existing encrypted control ops.
- **TURN hosting is a user decision. STOP and present it:**
  - (a) **coturn self-hosted on a small VPS** (open source; ~€4–6/month; the user creates the VPS account);
  - (b) a free-tier managed TURN (cheaper to start, but a third party sees IPs and timing; still no media access);
  - (c) STUN-only for now (works on most home Wi-Fi; **fails on many school/mobile networks**).
  - Give the cost/privacy trade-offs and a lean (**plot's lean: (a)**, shared later with LiveKit's server).
- **Don't create accounts.**

**DECIDED (the user, 2026-10-09): (a) Lime's own relay (coturn on a small VPS).**
- **Plot's provider lean: Hetzner Cloud.**
  - **CORRECTION (2026-10-10):** the cheap CX line is **EU-only**, and plot's "€4–5/month" was an EU price.
  - **In the US (Ashburn), use CPX11** (2 vCPU / 2 GB / 40 GB). Hetzner's price-adjustment doc lists about **$6.99/month**, but third-party sites quote ~$21 including IPv4, so the **user confirms the price in the console at order time**.
  - It needs a **primary IPv4** (TURN requires it).
  - Upgrade to CPX21+ when LiveKit is added.
- **The user creates the Hetzner account + adds the Mac's SSH public key; tend never creates accounts.**
- **The Phase 1 stop becomes:**
  - give the user step-by-step VPS creation (Ubuntu LTS, Ashburn, the SSH key, the firewall ports for TURN: 3478 UDP/TCP, 5349 TLS, the relay port range);
  - then tend provisions coturn over SSH with a **committed, idempotent setup script** (`infra/turn/setup.sh`):
    - a TLS certificate for `turn.limechat.org` (**the user adds an A record in deSEC**);
    - `use-auth-secret` with the REST-API shared secret **stored only on the server and as a Supabase function secret (set by the user via Terminal `read -s`)**.
  - Document it in `infra/turn/README.md`.

**Phase 2 (after the user's TURN choice):**
1. **Signalling over Lime's E2EE channel:** encrypted, signed control ops `call.offer` / `call.answer` / `call.ice` / `call.end` / `call.busy` / `call.decline`, sealed where possible. **The server never learns a call happened beyond normal mailbox traffic.**
   - **TURN credentials** come from a new Edge Function `turn-credentials` (time-limited HMAC credentials per the coturn REST API; rate-limited; verified sessions only).
2. **Media:** WebRTC **DTLS-SRTP** (end-to-end between the two phones; TURN only relays ciphertext).
   - **Verify the DTLS fingerprint** inside the signed `call.offer`/`call.answer` (it binds the media to the Lime identity, so a TURN/MITM can't swap keys).
   - Audio: Opus; video: VP8/H.264, adaptive.
3. **iOS UI:**
   - **the phone icon** in the chat header (voice), plus a **video** option;
   - **CallKit** for the system call UI (incoming while Lime is open/recent; outgoing; it shows in Recents as "Lime");
   - an in-call screen: mute, speaker, video on/off, flip camera, end; a picture-in-picture self view;
   - a **calls timeline line** in the chat ("Voice call · 4:12", "Missed call");
   - **the dock "call" tab:** a call history (local).
   - **Respect work hours/DND** (LIME-108): calls outside hours are silenced, shown as missed.
4. **The honest limit (until APNs/PushKit, the paid account):** an incoming call **rings only if Lime is open or recently used**. Show the note in Settings → Notifications (the existing note, extended to calls).

**Out of scope:** group calls (112), PushKit ringing (with APNs), screen share, recording.

**Verification:**
- core (call ops sign/verify; the fingerprint mismatch is rejected);
- server (`turn-credentials` auth + rate limit);
- an integration test of the signalling exchange through the real mailbox;
- **a real two-device call** cannot be automated: **simulator ↔ simulator audio is limited**, so the user tests on 2 phones;
- the tiered iOS rule; 0 warnings.

**Gate (two phones):**
- a voice call Shem→Jean while Jean has Lime open: it rings, connects, audio both ways, mute works;
- a video call; flip the camera;
- a missed call shows in the chat and the call tab;
- **a call on mobile data (Wi-Fi off on one phone)** connects (via TURN).

**Record:** `## LIME-111`. Commit: `feat: 1:1 voice and video calls (P2P WebRTC, E2EE signalling, CallKit)`, trailer `Brief: LIME-111`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

*(LIME-112, group calls on self-hosted LiveKit: to be drafted after 111; same VPS family, likely a larger instance.)*

**Call scaling and cost principles (plot, 2026-10-10; the user wants low cost + open source):**
- **1:1:** P2P first (most calls use no server). TURN only relays the fallback. ~1.5–2 GB of egress per relayed video-hour, so 1 TB ≈ 500+ relayed video-hours/month on CPX11.
- **Group (LiveKit, Apache-2.0):**
  - egress ≈ the receivers × the forwarded video;
  - **simulcast + active-speaker-only video + 360p thumbnails + video off by default in sessions > 12** → a 50-person PD hour ≈ 20–35 GB.
- **Levers:**
  - **separate the always-on small TURN box from the LiveKit box**;
  - **resize LiveKit up for scheduled PD sessions and back down** (Hetzner bills hourly);
  - audio-first defaults;
  - a 720p cap (480p default on mobile data);
  - LiveKit Cloud is never used (open-source requirement).
- **Rough monthly at the pilot scale:** TURN ~$7–21 + LiveKit (CPX21–CPX31) only when group calls launch; overage traffic ~€1/TB (US, verify).

### LIME-113 → `tend` (lime-aa) (after the calls): in-app account deletion + Report (App Store rules 5.1.1(v) and 1.2)
**Phase 0:** `git add PLOT.md` only. **Phase 1:** survey the auth, profiles, devices, mailbox, blobs/attachments, the Jam tables if present, Block, and the Settings → Account screen. Stop and ask the user on any conflict.

**Phase 2:**
1. **Delete account** (Settings → Account → red "Delete account"):
   - an explanation screen: what is deleted, and that **messages already on others' phones stay there** (E2EE);
   - type "DELETE" + **re-verify (password + an emailed code)**;
   - **the server deletes:** the auth user, profile, devices, keys, delivery-access hashes, mailbox items, attachments/blobs owned, the avatar, Jam content (when it exists), reports filed **by** them (keep reports **about** others);
   - **contacts receive a final encrypted `account.deleted` notice:** the chat shows "This account was deleted", and sending is disabled;
   - **the phone wipes the local store + keys**, returning to the welcome screen;
   - **a server deletion log row** (the user id hash + the time only) for compliance.
2. **Report:**
   - long-press menu **Report** on a message, plus **Report <name>** in the chat ⋯ (with Block);
   - reasons (harassment, spam, impersonation, inappropriate content, child safety, other) + optional notes;
   - **with E2EE the server can't see messages:** the report **includes the reported message(s) decrypted, by the reporter's choice** (a checkbox "Include this message", default on), sent to a FAM moderation mailbox (an Edge Function → the `moderation_reports` table; admin-only access; the same admin allow-list as the Jam review page);
   - an option "**Also block**";
   - **child-safety reports** are flagged as urgent; document the escalation process in `docs/moderation.md`.
3. **Docs:** `docs/moderation.md` (process, response times, the admin allow-list, data retention for reports); `release-checklist.md` (tick the account deletion + report items; the remaining items: the content policy page, the abuse contact email on limechat.org).

**Verification:**
- server tests (deletion removes every row/object for the user, and nothing of others; the report endpoint auth; the admin allow-list);
- the integration e2e (2 accounts: A deletes → B sees "account deleted", sends disabled; A's server data gone);
- UI tests;
- tiered iOS; 0 warnings.

**Gate:**
- report a message from Jean (it arrives in the admin view with the included message);
- delete a **throwaway** account (the iPad's FAM test account) end to end.

**Record:** `## LIME-113`. Commit: `feat: in-app account deletion and reporting (with moderation queue)`, trailer `Brief: LIME-113`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

**(History) Open questions put to the user (2026-10-09):**
- **(a) Mesh v1:** the user decided earlier that **TestFlight waits until offline relaying is included**; the new list omits it. Keep mesh v1 before TestFlight, or move it to after?
- **(b) Spanish (109):** before TestFlight, or after?

### LIME-106-fix → `tend` (lime-aa) (NEXT, before 107): reaction layout back to the bottom, the horizontal emoji picker, breathing room, a reply-context header
**The user's QA (2026-10-09) with screenshots (Lime; Apple Messages list; KakaoTalk reply). The screenshots contain other people's names/messages: never copy them.**

**Phase 0:** `git add PLOT.md` only. **Phase 1:** survey the iOS bubble/footer/reaction code from 104-fix, the image viewer's reaction menu, the Messages list row and the Replies screen. **Reference the web prototype's mobile footer** in `public/css/lime.css` ~7930–7975 (`.lime-message__foot`: one row under the bubble with **reaction chips on the leading side and the time/status stamp pushed to the trailing side** (`margin-left: auto`), wrapping if needed; then the reply summary) and `.lime-reaction` ~5017.

**Phase 2:**
0. **BUG FIRST (the user, 2026-10-09): a forwarded message never arrived on the receiver's phone.**
   - **Reproduce with a real two-account test** (the local stack, then staging):
     - forward a **text** message and a **photo** to (a) a DM and (b) a group, and to a mix of 2 chats in one forward;
     - assert that each receiver gets a "Forwarded" message.
   - **Diagnose and report the cause.** Candidates:
     - the forward written only to the local store (e.g. treated like the self-chat path);
     - not queued for delivery;
     - the wrong conversation/recipient set;
     - the attachment `share` call failing silently so the message is held;
     - a sealed/identified mismatch.
   - Fix it.
   - **The sender must never show "Sent" for something not accepted by the server:** a failed forward shows "Not sent · Tap to retry".
   - **UPDATE (the user's screenshot, 2:30 PM):**
     - forwarded **text arrived** (slowly);
     - a forwarded **album shows "Not sent. Tap to retry"**;
     - **two forwarded PDFs have been stuck on "Sending…" with a spinner for 17+ minutes** (2:13 → 2:30).
   - **Plot's leading hypothesis:** **forward-by-reference fails when the original attachment's server copy has already been swept.** LIME-98c deletes it ~1 h after the last recipient fetched it, so `share` on an old attachment hits a missing blob, and the forward stalls or fails.
   - **The fix to apply if confirmed:** when `share` reports the blob is gone (or near expiry), **re-upload from the sender's local decrypted copy** (a fresh key + upload, the 98c pipeline) and then send.
     - Never wait indefinitely: a time-boxed attempt, then "Not sent · Tap to retry".
     - Retry must work.
     - Also check that a **double forward** (the screenshot shows the same PDF forwarded twice) isn't a duplicate-send bug from a retry.
   - **UPDATE 2 (the user): everything actually arrived and opens on the receiver's phone.** **The bug is the SENDER's status**, which stays "Sending…" with a spinner, or shows a false "Not sent. Tap to retry", although delivery succeeded.
     - **So:** find why forwarded messages (with attachments) never transition to "Sent" locally (e.g. the forward path not recording the server's acceptance, a status keyed on the wrong message id after the attachment re-link (migration 20), or the share/upload completion not updating the message), and fix it.
     - **The swept-blob hypothesis above is now secondary:** verify it anyway with an old attachment, but don't redesign if delivery already works.
     - **Also make sure "Tap to retry" on a falsely-failed forward doesn't send a duplicate** (the double PDF may be exactly that).
   - The real-server integration test from LIME-106 apparently didn't cover the receiver side of forward (or passed for the wrong reason). **Strengthen it so it fails on today's bug.**
1. **Reactions back under the bubble (the user prefers it: "cleaner and more aligned"). This reverses 104-fix item 9's top-corner pill.** The layout, following the web prototype:
   1. the bubble;
   2. **one footer row**: reaction chips (leading) … time · Sent/Edited (trailing), aligned to the bubble's edge;
   3. the reply summary below.
   - **Chips:** **no outline**, a **soft grey fill only** (a light warm-neutral token, subtle); yours slightly deeper. Emoji + count.
   - **Too many:** the chip row **scrolls horizontally** within the bubble's width, or shows the first 5 + "+N" opening the who-reacted sheet.
   - **Spacing:** enough vertical space **between message groups** (≈ 12–16 pt) that a footer clearly belongs to the bubble above it, never crowding the next bubble.
2. **The reaction picker is a horizontal, scrollable emoji bar** (the Apple/macOS tapback style) everywhere: chat, Replies, **and the photo/album/video viewer** (today the viewer shows a vertical menu list). The 6 quick emoji + "+" (the full picker), in a glass capsule above the long-pressed item. The other actions stay in the menu below it.
3. **Breathing room, Apple-Messages style, on the Messages list:**
   - wider side margins;
   - **a dedicated left gutter column for the unread dot** (aligned, not touching the avatar);
   - consistent avatar size and spacing;
   - taller rows with comfortable vertical padding;
   - **NO divider lines and NO trailing chevrons/arrows** (the user, 2026-10-09: "I don't like the divider lines or the right arrows"). Separate rows by spacing only. This also applies to New Message lists, Group details member lists and Settings-style lists where Lime uses its own rows (keep the system grouped-card style only where already used, without chevrons unless a row pushes a new screen and has no other affordance).
   - Apply the same margin rhythm to the chat screen (bubble side margins, avatar gutter).
4. **The reply-context component (inspired by KakaoTalk's "Reply to …" quote):**
   - **in the Replies screen header area**, under the nav, a compact glass card: the root author's avatar + **"Replies · <Name>"** + **a one-line quote of the root message** (or its attachment label), like the chat header shows a person;
   - the full root bubble below can then be removed or kept (plot's choice: **keep the root bubble**, and the card is the header summary);
   - **the same component appears above the composer while replying in a thread**: "Reply to <Name> · <quote>" with an ✕ to leave Replies;
   - **also used in the Messages list** for reply-activity rows (see the note: **the user to confirm what "messages page" means**; if unclear, build only the Replies-header + composer uses and ask).

**Verification:**
- the tiered iOS rule;
- UI tests (chips under the bubble with no outline (a token check); the footer order bubble→reactions/time→replies; a horizontal picker in the viewer; the unread gutter alignment; the reply-context card in Replies);
- 0 warnings.

**Gate:**
- **forward a text and a photo to Jean (and to a group): they arrive, labelled "Forwarded"**;
- **forward an OLD photo/album/PDF** (sent more than an hour ago, already downloaded by everyone): it re-uploads and arrives, with nothing stuck on "Sending…";
- reactions sit under the bubble on the same line as the time, with a soft grey and no outline, and clearly belong to their message;
- long-press a photo/video → a horizontal emoji bar;
- the Messages list has more breathing room, with no divider lines and no arrows;
- Replies shows the "Replies · Name + quote" header and a "Reply to …" strip above the composer.

**Record:** `## LIME-106-fix`. Commit: `fix(ios): reactions under the bubble, horizontal emoji bar, list breathing room, reply-context header`, trailer `Brief: LIME-106-fix`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

**LIME-106-fix2 landed as `edd1071`** (pushed and verified).
- **The real cause:** forwarding a file whose server copy was swept failed, and **the delivery loop stopped at the first failure**, stalling everything queued behind it ("Sending…").
- **Fix:** re-upload from the local copy (same id/key); unforwardable items fail alone; retry never duplicates. 158 Rust / 13+13 integration tests pass.
- **The Kakao-style Messages-row item was NOT built** (no iOS change in the commit). **→ folded into LIME-107 as item 0.**
- **Remaining limit:** a swept file the forwarder never opened can't be forwarded. **Plot's call: fine**; show Forward disabled for it with "This file is no longer available" (fold into 107).

**LIME-107 run instructions (finalising the draft above):**
- **Item 0 first (carried over from 106-fix2; not built there):**
  - **(a)** the Kakao-style "Reply to <author> · <root quote>" line with a quote bar + "<Name>: <reply>" on Messages rows for reply activity (no ↩); spec in LIME-106-fix2;
  - **(b)** Forward disabled with "This file is no longer available" for swept attachments the user never downloaded.
- **Phase 0:** `git add PLOT.md` only.
- **Phase 1:** survey the attachment store, download paths, Settings and core migrations; stop and ask the user on any conflict.
- **Phase 2:** build the draft's four bullets (Settings → Storage; Keep media; Auto-download incl. "Available until <date>"; low-storage handling incl. a free-space check, the < 500 MB pause banner, clean failures).
- **Verification:**
  - core tests (the keep-media sweep keeps messages, removes media; the free-space guard);
  - a UI test with a simulated full disk (an injected free-space provider);
  - the tiered iOS rule; 0 warnings.
- **Gate:** Settings → Storage shows usage per chat; delete one chat's media; set Keep media to 30 days; switch video auto-download to Wi-Fi only and see a tap-to-download placeholder.
- **Record:** `## LIME-107`. Commit: `feat(ios): storage management, keep-media, auto-download settings, low-storage safety`, trailer `Brief: LIME-107`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

### LIME-108 → `tend` (lime-aa) (after 107): status badges + work hours
**What it does:** the user approved (2026-10-09) status icons from the web prototype (LIME-57 series) + work-hours boundaries, with plot's privacy design.

**Phase 0:** `git add PLOT.md` only. **Phase 1:** survey the avatar component, the LIME-102 notification settings/holding, the `profile.changed` control op (98b-fix), and the web prototype's status SVGs in `public/` (the cut-out notch + the Montserrat "z"). Stop and ask the user on any conflict.

**Phase 2:**
1. **The status model:**
   - **Available / Away / Do not disturb**, set manually or **automatically by work hours**;
   - **shared only with accepted contacts** via an encrypted control op `status.changed { state, until }` (sealed where possible);
   - **no live presence, no "last seen", nothing on the server.**
2. **The badge:** a small status icon **in a cut-out notch at the avatar's bottom-right**, ported from the web prototype: green dot = available, yellow moon = away, a DND badge with the Montserrat-Bold "z" = do not disturb.
   - Shown in Messages rows, chat headers, New Message, member lists and Settings.
   - **No badge for "unknown"** (a contact who hasn't shared one).
3. **Set your status:** tap **your own avatar** (top right of Messages) → a sheet: Available · Away · Do not disturb · **Quiet until…** (1 h / until tomorrow 7:00 / custom); plus a link to Work hours.
4. **Settings → Work hours:** a weekly schedule (days + start/end, default Mon–Fri 7:00–15:30).
   - **Outside work hours:** you're automatically DND; **notifications are held** (delivered silently, with a summary at the start of the next work period).
   - **Exception:** messages marked **urgent/emergency always break through** (reserve the flag for emergency mode; not sendable by users until the mesh/emergency brief).
5. **Chat header:** under a contact's name, "Quiet hours until 7:00", or "Do not disturb", when applicable.
6. **Docs:** `api-v2.md` (the control op; the privacy note: contacts-only, no presence).

**Verification:**
- core (status op sent only to accepted contacts; expiry of "until");
- notification holding outside hours (unit, with an injected clock);
- UI tests (set status; the badge appears on the other account in the integration e2e; the work-hours editor);
- tiered iOS; 0 warnings.

**Gate:**
- set DND on your phone → Jean sees the "z" badge and "Do not disturb";
- set work hours ending in 5 minutes → after that, Jean's message arrives silently, and you get the summary when hours resume (or when you switch to Available).

**Record:** `## LIME-108`. Commit: `feat: status badges (contacts-only) and work hours with held notifications`, trailer `Brief: LIME-108`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

### LIME-109 → `tend` (lime-aa) (after 108): localization groundwork + Spanish
**Phase 0:** `git add PLOT.md` only. **Phase 1:** inventory every user-facing string (SwiftUI `Text`, alerts, notifications, the permission strings in Info.plist, the core error messages surfaced to UI).

**Phase 2:**
1. **Move all strings into Apple String Catalogs** (`Localizable.xcstrings`, `InfoPlist.xcstrings`), with plural rules ("1 reply" / "N replies"), and dates/times via locale formatters.
2. **Spanish (es) translation** of every string.
   - **Tend drafts it**, writing **neutral Latin-American Spanish**, teacher-appropriate and using "tú";
   - **marks each string "needs review"**;
   - and lists in `docs/localization.md` the strings it's least sure of.
   - **The user/a native speaker reviews before release** (add this to `docs/release-checklist.md`).
3. The app follows the iPhone language; no in-app switch in v1.
4. **The no-hardcoded-strings rule** added to `ios/README.md` + a check script that flags new literal UI strings.

**Verification:**
- run the app in Spanish (a scheme argument) on the 13 mini: **no English left on the main screens**, no truncation at 375pt (UI tests in `es`), plurals correct;
- 0 warnings.

**Gate:** set the iPhone language to Español → Lime is in Spanish; skim for anything odd.

**Record:** `## LIME-109`. Commit: `feat(ios): String Catalogs + Spanish translation (draft, needs native review)`, trailer `Brief: LIME-109`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

### THE QA INTAKE RULE (the user, 2026-10-08): "I'll keep adding them as I see; you prioritise."**
- **Plot appends** small UI/QA items to the **current open QA brief (LIME-104)** until it's sent.
- **Protocol/feature-sized items** go to a feature brief (105/106 or new).
- **The order now:**
  1. 98d;
  2. **104 (QA, now 12 items incl. Sign Out + private labels)**;
  3. 105;
  4. 106;
  5. **107 (storage)**;
  6. **108 (status badges + work hours)**;
  7. **109 (localization groundwork + Spanish)**;
  8. **mesh v1 + emergency "I'm safe" mode**;
  9. TestFlight prep;
  10. later: calls → PD sessions, communities, verified-teacher process, Jam.

### LIME-104 → `tend` (lime-aa) (after LIME-98d): QA round (formatting state, group avatar, Reply wording, Replies screen, search in replies)
**The user's QA notes (2026-10-08), while tend is on LIME-98c.**

**Phase 0:** commit `PLOT.md` unedited. **Phase 1:** survey the theme pressed tokens, the format toolbar, the New Group/Group details, the message long-press menu, the thread screen, and the search (Messages search + in-chat find + the thread screen). If anything is ambiguous, **stop and ask the user**, in particular item 1's scope.

**Phase 2:**
1. **The formatting selected/pressed state is too dark → more subtle.**
   - Lighten the warm-neutral pressed fill on the format toolbar (Aa and B/I/U/S/link/code/lists): a lighter tint, **still distinguishable** (≥ 1.5:1 against the bar, so it's visible) while the ink stays ≥ 4.5:1. Light and dark.
   - **Confirmed by the user:** it's the grey active circles behind Aa, B, I… in the format toolbar. Nothing else changes.
2. **Group avatar = an emoji OR a photo, editable after creation:**
   - in **New Group** and in **Group details → Edit**, choose **Emoji** or **Photo** (library/camera + circular crop, as for the profile);
   - **change or remove it any time** (owner/admins, the same rule as rename);
   - **a group photo is encrypted** (a random key; the blob is in the `blobs` bucket; the key + blob id ride in a signed `group.set_avatar` op inside the group's encrypted state), so the server never sees it;
   - a system line: "Rae changed the group photo".
3. **The message long-press menu says "Reply"** (not "Reply in thread").
4. **The thread screen is titled "Replies"** (with the root message's sender as a subtitle if it fits).
5. **Search replies:**
   - **in-chat find** (🔍 in a chat) also matches replies in that chat's threads; a hit in a reply opens the Replies screen with the word highlighted;
   - **the Replies screen gets its own 🔍 find**;
   - **Messages search** already indexes replies (LIME-101); verify it and label those results "in Replies".

6. **The chat header tool group** (search, phone, ⋯; top right in chats and Replies): **tighter spacing between the three icons** (the hit targets stay ≥ 44pt; reduce the visual gaps/padding so the glass pill is more compact). Check 375pt.
7. **The ⋯ menu: "Mute Notifications" → "Mute".**

8. **(Added 2026-10-08) The Messages list preview shows the latest activity, including replies.** Today a new reply only bumps the unread counter, and the row keeps showing the last main-timeline message.
   - The row shows the **most recent message or reply**;
   - for a reply, prefix it: "↩ Jean: sounds good" (or "Jean replied: …"); in groups, "Name: …";
   - **the row's time and sort order follow the latest activity**, replies included.
9. **(Added) Attachment previews in the Messages list:**
   - the row shows a small type icon + label for attachments: 📷 Photo / 📷 3 Photos, 🎬 Video, 🎤 Voice message (0:12), 📄 File name.pdf; **with the caption if there is one**;
   - **a tiny thumbnail** at the trailing edge for photos/videos (from the encrypted 2 KB thumbnail; nothing extra is fetched).
10. **(Added) Swipe actions on Messages rows** (iOS-native `swipeActions`):
   - **swipe left: Mute** (opens the mute durations) **and Delete** (red; confirms "Delete chat? This removes it from this phone.");
   - **swipe right: Unread/Read** (toggles; the unread dot) **and Pin/Unpin**.
   - **Pinned chats sort to the top** with a pin glyph.
   - **The core needs:** a manual "mark unread" flag, `pinned` (exists: check), delete-chat-for-me (a local clear, like the web's `cleared_at`).
   - **Groups:** Delete = "Leave and delete" (confirm), or just delete locally if you've already left.
11. **(Added 2026-10-09) Sign Out more discoverable:** a **red "Sign out" row at the bottom of Settings** (as well as in Account), keeping the confirmation text about keys.
12. **(Added 2026-10-09) A private nickname/label per contact:**
   - in the chat details or the profile sheet: "Add a label" (≤ 30 characters, e.g. "Grade 4 · Lincoln");
   - **it shows next to their name** in Messages, chat headers, New Message and group member lists;
   - **visible only to you**: stored in the encrypted local store, never sent to the server or to them (it syncs to your own devices once device linking exists);
   - searchable locally.
13. **(Added 2026-10-09) The honest notification note** in Settings → Notifications: "Until Lime's push service is ready, alerts arrive while Lime is open or recently used." (Remove it when APNs lands.)

**Verification (the tiered rule):**
- unit + UI tests for each item (the pressed-state contrast token test; the group photo set/change/remove across 2 accounts in the integration test, with the server holding only ciphertext; menu wording; the title; find hits in replies);
- 0 warnings.

**Gate (the user):**
- the formatting buttons look subtler;
- set, then change, a group photo, and switch to an emoji;
- long-press shows "Reply";
- the thread is titled "Replies";
- find a word that's only in a reply.

**Record:** `## LIME-104`. Commit: `fix(ios): QA round: subtler format state, group photo/emoji editing, Reply wording, Replies title, search in replies`, trailer `Brief: LIME-104`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

---

### LIME-105/106 amendment (the user, 2026-10-08): the full long-press menu, multi-select, Note to Self
**The long-press menu on a bubble, in this order:**
1. **an emoji reaction row** (6 quick + "+" for any emoji);
2. **Reply**;
3. **Forward**;
4. **Edit** (own messages only);
5. **Copy**;
6. **Select**;
7. **Delete** (red).

**The split** (keeps each brief reviewable):
- **LIME-105 = reactions, Reply (already exists; verify the wording), Copy, Edit, Delete, Select (multi-select).**
- **LIME-106 = Forward, Note to Self, link preview cards** (moved out of 105).

**Edit (plot's decision):**
- **your own messages, within 24 hours** (the same window as Delete for everyone);
- an encrypted, signed `message.edit` op;
- the bubble shows "Edited" (tap to see the previous versions **on your own phone only**? No: **keep only the latest text**; simpler and more private);
- the search index updates;
- works in threads.

**Copy:** copies the plain text (the formatting is kept as rich text where the paste target supports it).

**Select (multi-select mode):**
- every bubble shows a **round selection circle** (left of incoming, right of own);
- **a bottom bar: 🗑 trash (left) · "N Selected" (centre) · Forward (right)**;
- a header with **Cancel**.
- **Trash** asks: **Delete for me**, or **Delete for everyone** (offered only if *all* the selected messages are yours and within 24 h);
- **Forward** opens the Forward picker (LIME-106; in 105 the button is present but routes to a "Coming next" toast until 106 lands).

### LIME-106 → `tend` (lime-aa) (after LIME-105): Forward, Note to Self, link preview cards
- **Forward:**
  - pick one or more **teachers or groups** (the New Message list UI with checkmarks + chips, like New Group) → Send.
  - Each forward is a **new encrypted message** labelled "Forwarded" (no original sender name, for privacy).
  - Attachments are re-shared by reference (the same encrypted blob + key travel in the new message; the blob's lifetime extends to the new recipients).
  - Formatting is preserved.
  - Up to 5 chats per forward (anti-spam, like WhatsApp).
- **Messaging yourself** (the user, 2026-10-08: **don't call it "Note to Self"; it's just your own name**, like messaging anyone else):
  - **you appear in New Message as yourself** (your name, your avatar, your @username; no special badge or label), in the normal A–Z list and in search;
  - the chat's title is your name, and it sits in Messages like any other chat;
  - searchable;
  - **stored on your phone only for now** (encrypted at rest; nothing is sent to the server); it syncs to your other devices once device linking exists;
  - supports everything a chat does (formatting, attachments, threads, edit, delete, search).
- **Link preview cards:** as specified in LIME-105 below (moved here).

**Gate:**
- forward a message to two chats;
- find **yourself** in New Message, send yourself a message with a photo, and find it via search;
- send a link → card.

**Record:** `## LIME-106`. Commit: `feat: forward, Note to Self, link preview cards`, trailer `Brief: LIME-106`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

---

**LIME-105 landed as `55c1f96`** (pushed and verified).
- The long-press menu (reaction row incl. "+"; Reply / Forward / Edit / Copy / Select / Delete); reactions with chips; Edit for 24 h ("Edited"); Delete for me/everyone (24 h); Copy; Select mode. Forward is a toast until 106.
- 151 Rust / 11+11 integration tests pass; tiered iOS passed; 0 warnings.
- **Tend ran 105 before 104-fix** (the order was swapped); 104-fix (7 items) is next.

**LIME-106 landed as `e11542b`** (pushed and verified).
- **Forward:** a picker (≤ 5 chats); "Forwarded" with no author; attachments re-shared by reference (a new `share` call extends the server lifetime; local migration 20).
- **Messaging yourself:** local-only, never uploaded; no "Note to Self" label (only the commit title says it).
- **Link cards:** LinkPresentation on the sender; card + image encrypted; recipients never fetch; Settings → Privacy toggle (on). The subheading = the site (LinkPresentation has no description).
- 157 Rust / 48 server / 12+12 integration tests pass; tiered iOS passed (one transient link-card stall); 0 warnings.
- Tend deployed the attachment function to staging (needed for integration; fine).
- **Next:** LIME-107 (storage) → 108 (status + work hours) → 109 (Spanish) → the mesh v1 design brief.

**LIME-104-fix landed as `d0b9884`** (pushed and verified).
- **The bug's cause:** the find task re-ran on the chat's reappear and re-pushed Replies; now the answered query is remembered.
- **All 11 items are done.** Notes:
  - Mute is still a bottom sheet (titled "Mute <name>" + a row highlight), since iPhone has no row-anchored popover;
  - the reaction pill sits at the bubble's top corner, with the time directly under it;
  - media long-press works.
- 152 Rust tests pass; integration + tiered iOS passed; 0 warnings.
- Awaiting the user's gate. **Next: LIME-106.**

### LIME-104-fix → `tend` (lime-aa) (landed as `d0b9884`): in-chat find → reply hit traps navigation
**The user's bug (2026-10-09, iPhone):**
- in the Shem↔Jean chat, 🔍 find "FAM" (a word only in a reply) → it opens the Replies screen;
- **pressing Back keeps re-opening Replies**, and the chat can't be reached again **until the app is force-quit**.

**Likely cause (plot's guess; tend must verify):** the find state (the current match = a reply hit) stays active, so re-showing the chat re-triggers "open Replies for the current match", or the navigation path is rebuilt from the find state on appear.

**Phase 0:** commit `PLOT.md` only (`git add PLOT.md`). **Phase 1:** reproduce in a UI test first (the chat with a reply-only word → find → hit → Back), confirm the cause, and report it.

**Phase 2: the fix.**
- Opening a reply hit **pushes Replies once**. **Back returns to the chat** with the find bar still open at the same "N of M", and stepping ↑/↓ continues; stepping onto another reply hit pushes Replies again (once).
- **Done** closes find with no navigation side effects.
- The same check for Messages search → a reply result → Back → Back (returns to the results, then to Messages).
- **Never** derive navigation from a persistent find/match state on appear.

**Also folded in (the user's LIME-104 QA, 2026-10-09):**
1. **The unread dot moves to the LEFT side of the Messages row** (before the avatar, like Apple Mail/Messages), not the right.
2. **A smaller photo/video thumbnail** in the Messages row preview (about 32–36 pt, the same corner radius family, vertically centred with the preview text).
3. **Swipe-left → Mute shows its durations in context:** the mute options must clearly belong to the swiped chat.
   - Present them as a **confirmation dialog/menu anchored to that row** (a popover from the row on iOS 26 / a context menu), **titled with the chat's name**: "Mute **Jean Chung**", with 1 hour / 8 hours / 1 week / Always / Cancel.
   - Keep the swiped row highlighted until a choice is made.
   - Never a centred, unlabelled sheet.

4. **Private labels must never wrap the name** (the user's screenshot: "Jean 👑 Queen" pushed "Chung" to a second line in Messages and in Group details).
   - The **name has priority and stays on one line**; the label is a **small capsule after the name that truncates first** (…), down to just its emoji, or hidden if there's no room.
   - In tight places (member lists) the label may move under the name as the secondary line.
   - Never wrap the name because of a label.
5. **Group details edit affordances:** the photo badge and the name pencil both become **matching light-grey circles with an icon** (photo badge: a camera or pencil icon in a light-grey circle at the avatar's bottom-right; name: a small light-grey circle with a pencil next to the name). **Not green:** green is reserved for the primary action.
6. **The format toolbar's active/pressed circles must be lighter still** (the user: Aa and B/I/U still compete with the send button). Use roughly **half the current contrast**: a very light warm tint (about 1.2–1.4:1 against the bar). The **pressed state is also indicated by the icon weight/ink** (e.g. the icon in full ink + a faint fill), so it stays perceivable without a heavy fill. Light and dark. Update the token test bounds accordingly.

7. **Pin/Unpin reorders smoothly** (the user's screenshots: two rows briefly drawn on top of each other, cross-fading, before the list settles). Fix:
   - **Stable row identity:** `ForEach` keyed by the conversation id; never by index or a recomputed struct identity.
   - **Let the swipe close first,** then apply the reorder **in one `withAnimation(.snappy)`**, so rows **slide** into their new places (a move, not a fade/overlap).
   - **No opacity transitions** on rows during a reorder.
   - Pinned rows and the pinned section move as a unit.
   - **A UI test** captures frames mid-animation and asserts no two rows' frames overlap by more than a few points.

8. **Deleted replies disappear from the reply summary** (the user: a thread whose only reply was deleted still shows "1 reply" with an avatar under the bubble).
   - The summary's count, last-reply time and replier avatars **ignore deleted replies**;
   - **if no live replies remain, no summary is shown** under the bubble.
   - Inside Replies, a deleted reply may keep its "This message was deleted" line (for context), but the header count excludes it.
9. **Reactions move to the bubble's top corner, Apple Messages style** (the user asked "what do you think?"; **plot decided yes**: cleaner, and it solves the "time pushed under reactions" confusion and "too many reactions"). **The per-message layout becomes:**
   1. **the reaction cluster overlapping the bubble's top corner** (the top-left for own bubbles; the top-right for others'): a small rounded glass/cream pill with **up to 3 distinct emoji + a count if more** (e.g. "👍❤️😂 5"); your own reaction is subtly outlined;
   2. **the bubble**;
   3. **the time line** (time · Sent/Edited), directly under the bubble, **always immediately below it**;
   4. **the reply summary** under that.
   - **Tap the cluster** → a sheet listing every reaction with who reacted (tap your own to remove it).
   - The bubble gets a little top margin when it has reactions, so the cluster never overlaps the bubble above.
   - **This replaces the chips under the bubble** (and the "lighter chip background" ask is then moot: the cluster is a light glass/cream pill, not a grey fill).
11. **Reactions (and the full long-press menu) on media messages** (the user, 2026-10-09):
   - **long-press works on photos, albums, video, voice messages and file cards** exactly as on text bubbles (the reaction row + "+", Reply, Forward, Copy where it makes sense (e.g. a caption or a single image), Select, Delete; Edit applies to the caption only).
   - **The reaction cluster sits on the media's top corner** the same way.
   - **In the full-screen viewer:** a react button (or a long-press) for the photo/video shown.
   - **Album reactions apply to the message** (the album), not to individual photos, in v1.
10. **(Note)** consecutive "This message was deleted" placeholders are visually heavy (the user's screenshot shows 4 in a row). **Collapse runs of ≥ 2 consecutive deleted placeholders into one line**: "3 messages deleted".

**Verification:**
- the new UI tests for both paths (in-chat find and Messages search), including a double Back and the swipe-back gesture;
- the reply summary hides when all replies are deleted; the reaction cluster sits at the top corner (frame check); the time line sits directly under the bubble; the tap-cluster sheet lists who; deleted runs collapse;
- a label never wraps the name (a long-label UI test at 375pt); the pressed fill is within the new bounds;
- the dot is on the left; the thumbnail size is ≤ 36 pt; the mute dialog title contains the chat name;
- the tiered iOS rule; 0 warnings.

**Gate:**
- find "FAM" in the Jean chat → Replies → Back → you're in the chat; Back again → Messages;
- the unread dot is on the left;
- a smaller thumbnail;
- swipe → Mute shows "Mute <name>" next to that chat;
- a long label truncates without wrapping the name;
- the group photo/name edit icons are light-grey circles;
- the format active state is lighter, and send is the only strong colour;
- pinning/unpinning slides the row smoothly to its new place, with no overlap;
- reactions sit on the bubble's top corner, Apple-style, and the time stays right under the bubble;
- a deleted-only thread shows no "1 reply";
- runs of deleted messages collapse;
- long-press a photo, an album, a video and a voice message → react; the cluster shows on the media.

**Record:** `## LIME-104-fix`. Commit: `fix(ios): find in replies no longer traps navigation; QA polish (unread dot, thumbnails, mute in context, labels, edit icons, lighter format state)`, trailer `Brief: LIME-104-fix`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

### LIME-105 → `tend` (lime-aa) (after LIME-104-fix): message actions (see the amendment above: reactions, Reply, Copy, Edit, Delete, Select; Forward + link cards move to 106)
**The user's QA notes (2026-10-08):** "in addition to reply, we need ability to delete a message in a chat, thread or reply and give emoji reactions, with the plus to pick any emoji"; "link cards are missing (thumbnails, heading and subheading)". Split from LIME-104 because these need protocol work.

**Plot's decisions:**
- **Delete:**
  - **Delete for me** works on any message;
  - **Delete for everyone** works on **your own** messages **within 24 hours** of sending (a signed, encrypted `message.delete` op to the conversation's members; their phones replace it with "This message was deleted"; the search index and attachments are purged locally).
  - **Honest limit, shown in the confirm text:** "Lime can't guarantee it's gone if someone already saw or saved it."
  - Works in chats, groups and Replies.
  - For a thread root: the replies stay, under "This message was deleted".
- **Reactions:**
  - long-press shows a **quick row of 6 emoji + a "+"** that opens the **full emoji picker** (any emoji, with search);
  - an encrypted `reaction.toggle` op (one reaction per emoji per person; toggling removes it);
  - **chips under the bubble** with counts, highlighted if yours; tap a chip to toggle it; long-press a chip to see who reacted.
  - Works in groups and Replies.
  - **No notification for reactions** in v1 (only a badge-free update).
- **Link preview cards:**
  - **the sender's phone** builds the preview (Apple's LinkPresentation: title, description/subheading, the site name, a thumbnail) **before sending**;
  - the preview text plus a **thumbnail as an encrypted blob** (the 98c pipeline) travel inside the encrypted message;
  - **recipients never fetch the URL** (no tracking of readers; DESIGN-01 §3);
  - the card shows the thumbnail, the title (heading), the description (subheading) and the domain; tap opens the link (the existing https/non-https confirmation).
  - **The composer shows the card before sending** (removable with ✕).
  - **Settings → Privacy → "Generate link previews"** (default **on**), with a note: "Creating a preview visits the site from your phone."

**Phase 0:** commit `PLOT.md` unedited. **Phase 1:** survey `api-v2.md` §§3, 11 (the payload/control ops), the 98c attachment pipeline, the message long-press menu, the composer. Stop and ask the user on any conflict.

**Phase 2:** build the above. Document the ops in `api-v2.md` and the privacy notes in `architecture.md` §5.

**Verification (the tiered rule):**
- core tests (delete-for-everyone within/after 24 h; non-senders can't delete others' messages for everyone; reactions toggle and converge across devices; a preview thumbnail stored as ciphertext);
- the integration e2e (2 accounts);
- UI tests (the quick row + full picker; chip toggle; delete for me/everyone; the link card in the composer and in the bubble);
- 0 warnings.

**Gate (the user, two phones):**
- react with a quick emoji and with one picked via "+"; Jean sees the chips;
- delete for everyone → "This message was deleted" on Jean's phone;
- paste a link → a card with a thumbnail, title and subheading appears before sending and on Jean's phone.

**Record:** `## LIME-105`. Commit: `feat: delete messages, emoji reactions, link preview cards (sender-generated, encrypted)`, trailer `Brief: LIME-105`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

---

### LIME-98b-fix → `tend` (lime-aa) (landed as `c63e2d1`): photo changes show up at once
**Problem:** contacts see a new/removed photo or a visibility change only after a re-check (at most hourly). Tend's workaround (sign out / reinstall) destroys keys. **Never suggest signing out to refresh data.**

**Phase 0:** commit `PLOT.md` unedited. **Phase 1:** survey `refresh_photos`, the delivery-key control op and the pull-to-refresh paths.

**Phase 2:**
1. When you **set, remove or change the visibility** of your photo, send your accepted contacts a small encrypted control op, `profile.changed { photo_version }` (over the existing channel; sealed where possible). **Receivers refresh that person's photo immediately** (bypassing the hourly limit for that person).
2. **Pull-to-refresh** on Messages, and opening a chat or profile, forces a photo refresh for the people shown (rate-limited to once per minute per person).
3. Remove the "sign out/reinstall to see it" advice from `TEND.md`/the docs; add to `core/README.md`: *"Never sign out to refresh data: sign-out deletes keys."*

**Verification:**
- core + integration (a photo change reaches a contact within one sync);
- the tiered iOS rule;
- 0 warnings.

**Gate:** Shem changes his photo → it appears on Jean's phone within seconds (or after a pull-to-refresh).

**Record:** `## LIME-98b-fix`. Commit: `fix: photo changes reach contacts immediately (profile.changed op, pull-to-refresh)`, trailer `Brief: LIME-98b-fix`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

---

### Open decision: profile photos on native (raised 2026-10-08: "why can't we edit our avatar anymore?")
- **Why it's missing:**
  - the web app had photo upload (LIME-49);
  - the native LIME-98 deliberately left photos out;
  - **the native app has no encrypted blob storage yet** (no attachments either).
- **The decision put to the user:**
  - **P-A. Public photo:** like the name/school/About; the server stores it and anyone who finds you sees it. *Simple.* *Con:* teachers' faces are visible to strangers and the server, which fits poorly with E2EE and child-safety norms.
  - **P-B. Contacts-only, encrypted (Signal's model):** the photo is encrypted with a **profile key** shared with your accepted contacts (reusing the LIME-96 delivery-key sharing channel); the server stores only ciphertext; **strangers and search results see initials.** *Con:* a bit more work; strangers can't recognise you by face.
  - **Lean: P-B.**
- **Either way it needs the encrypted blob store** (`api-v2.md` §6 Blobs). **Plan:** one brief, **LIME-98b**, "encrypted blob store + profile photo (crop, camera/library)", after LIME-97. **Chat photo/file attachments** reuse it next (a separate brief).
- **DECIDED (the user, 2026-10-08): A by default, plus a setting for contacts-only, encrypted.**
  - **Default:** a public photo (any signed-in Lime user who sees your profile, and the server).
  - **Setting:** Profile → "Who can see my photo": **Everyone on Lime** (default) / **Only my contacts (encrypted)**.
    - Switching to contacts-only **deletes the public copy from the server** and shares an encrypted copy via the profile key; strangers see initials.
    - Switching back re-uploads the public copy.

### LIME-98b → `tend` (lime-aa) (after LIME-97/97b): encrypted blob store + profile photos (public by default, contacts-only option)
**What it does:** builds `api-v2.md` §6 Blobs and native profile photos, per the user's decision above.

**Capabilities assumed:** edit files, `cargo`, the Supabase CLI (migrations, storage buckets and functions **without `config push`**), XcodeGen, `xcodebuild`, commit, push. Stop and ask the user before anything that needs a dashboard change or a paid plan.

**Phase 0:** commit `PLOT.md` unedited. **Phase 1:** survey `api-v2.md` §§2, 6, 11 (blobs, the expiry rules); the LIME-96 key sharing; the profile functions; Supabase Storage limits on the free plan. Stop and ask the user on any conflict.

**Phase 2: the change.**
1. **The blob store (server):** two Supabase Storage buckets, **private**, reached only through Edge Functions with short-lived signed URLs:
   - `public-avatars`: plaintext images, readable by any **signed-in** user (never anonymously), writable only by the owner; max 1 MB, JPEG/HEIC re-encoded to JPEG 512 px on the device (strip EXIF/GPS).
   - `blobs`: **ciphertext only** (AES-256-GCM, a random key per blob; the key travels inside encrypted messages/control ops). It's the general store for later chat attachments.
   - Quotas per user; tests; deploy.
2. **The profile key (core):** a random key per account, shared with accepted contacts over the LIME-96 control-op channel (same triggers); it rotates on block, like the delivery key.
3. **Photos (iOS):**
   - **Profile → Photo:** take a photo / choose from the library (`PHPicker`; no full library permission) → a circular crop → save. Remove photo.
   - **"Who can see my photo":** **Everyone on Lime** (the default) / **Only my contacts (encrypted)**, with a one-line explanation of each.
   - **Where avatars appear:** Messages, chat headers, bubbles, New Message, Requests, Settings. They're cached on the device (in the encrypted store); initials remain the fallback.
4. **Docs:**
   - `api-v2.md` (the buckets, the profile key, the visibility rules; **the public photo is visible to the server and to signed-in users**);
   - `architecture.md` §5;
   - `docs/release-checklist.md`: **App Store guideline 1.2 (user-generated content) requires a way to report objectionable content/users, plus block, before release.** Public photos make this concrete. Add an item: "Report user/photo" + the moderation process.

**Out of scope:** chat photo/file attachments (the next brief, reusing `blobs`), group photos (could reuse it later), the web.

**Phase 3: verification.**
- Server tests:
  - an anonymous user can't read either bucket;
  - a signed-in user can read a public avatar;
  - the `blobs` bucket holds only ciphertext (a test uploads a known image through the app path and asserts the stored bytes don't match);
  - quotas.
- Core: profile-key sharing/rotation; contacts-only decryption; a stranger can't decrypt.
- iOS:
  - pick → crop → save; it shows on the other phone;
  - switching to contacts-only removes the public copy (a server check) and strangers see initials;
  - EXIF stripped.
- 0 warnings; screenshots.

**Gate (the user, both phones):**
- set a photo → Jean sees it;
- switch to "Only my contacts" → Jean still sees it; a new stranger account sees initials;
- remove it → initials.

**Record:** `## LIME-98b`. Commit: `feat: blob store (public avatars + encrypted blobs), profile photos with contacts-only option`, trailer `Brief: LIME-98b`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

---

### LIME-98c → `tend` (lime-aa) (after LIME-98b): encrypted attachments: photos, videos, files, and voice messages
**The user's ask (2026-10-08):** "also audio voice recordings and videos sending". It builds on LIME-98b's `blobs` bucket (ciphertext only).

**Plot's decisions (no user input needed; flag anything that hits limits):**
- **One encrypted attachment pipeline:**
  - each file is encrypted on the device (AES-256-GCM, a random key + digest per file) and uploaded **chunked and resumable**;
  - **the key, digest, size, type, duration and a tiny blurred thumbnail travel inside the encrypted message.**
  - The server sees only ciphertext size and timing.
- **Cost guardrails (the free plan; the cost principles):**
  - **compressed on the device:** photos → JPEG/HEIC ≤ 2048 px; **video → H.264/HEVC 720p, max 3 minutes / ~50 MB**; voice → AAC/Opus mono ~24 kbps; files ≤ 50 MB.
  - **The blob is deleted once every recipient device has downloaded it, or after 30 days**, whichever is first (mailbox-like). Recipients keep their own decrypted copy locally.
  - Supabase free-plan storage/egress limits go into `docs/release-checklist.md` as a funding trigger.
- **Voice messages (Signal/WhatsApp style):**
  - **hold the mic to record** (slide left to cancel, slide up to lock hands-free); release to send;
  - a waveform bubble with play/pause, a scrubber, the duration and a playback speed (1×/1.5×/2×);
  - the next voice message auto-plays.
  - **Dictation stays available via the keyboard's own mic.** The composer mic becomes voice messages (it replaces LIME-86's web-era dictation idea on native).
- **Videos:** record or pick (`PHPicker`; no full library permission); compressed with progress; inline poster + duration; full-screen player.
- **Photos:** pick or take; an album grid for multiple photos (up to 10); a full-screen viewer with swipe between photos; save-to-Photos on request.
- **Files:** the document picker; a file card (name, size, type icon); open with Quick Look / share.
- **The offline mesh (mesh v1) carries text only at first.** Attachments sync when online. *(A short voice message is ~60 KB; it could ride the mesh later, so flag it in `architecture.md` §7.)*
- **Privacy:** strip EXIF/GPS from photos/videos by default; the camera/microphone permission texts explain why.

**Capabilities / Phase 0 / Phase 1:** as in LIME-98b. In Phase 1, survey the composer `+` and mic, the `blobs` bucket and the message payload format. Stop and ask the user on any conflict.

**Phase 2: the change.** Build the above in this order:
1. the pipeline + the server (chunked signed-URL upload/download, delete-after-fetch, 30-day sweep, quotas, tests);
2. photos;
3. files;
4. voice;
5. video.

**If it grows too large, split it at a clean boundary** (e.g. 98c photos+files, 98d voice+video) and say so.

**Phase 3: verification.**
- **Encryption:** the stored bytes ≠ the plaintext; a tampered blob fails its digest.
- **Lifecycle:** delete-after-all-fetched; the 30-day sweep; resume after interrupting an upload.
- **Compression limits:** a 4-minute video is refused/trimmed with a clear message.
- **Voice:** the record/cancel/lock gestures (UI tests), playback, and the speed control.
- **The two-phone e2e** for each type (local + staging).
- 0 warnings; screenshots.

**Gate (the user, both phones):** send each type to Jean (a photo, an album, a short video, a PDF, a voice message); all arrive and play/open; voice speed works.

**Record:** `## LIME-98c` (+ 98d if split). Commit: `feat: encrypted attachments (photos, video, files, voice messages)`, trailer `Brief: LIME-98c`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

---

### LIME-96-fix → `tend` (lime-aa) (landed as `703b6eb`): Signal-style silent fallback, so a blocked sender gets no hint
**The user's decision (2026-10-08): B.** On a **sealed send refused with 403**:
- **automatically retry once as identified, silently**;
- **show "Sent"** (never "Not delivered" for this case);
- **stop using sealed for that contact** until they share a new key.

The result: a blocked person learns nothing, and a contact who changed phones still gets the message (landing normally, as an accepted contact).

**Capabilities / Phase 0:** as in LIME-96. Commit `PLOT.md` first, unedited.

**Phase 1:** survey the LIME-96 send/403 path, the bubble states and the tests.

**Phase 2:**
- **Add a way to block an existing contact.** The user asked "how do you block someone?", and plot found that Block **only exists on the Requests bar** (`ChatView` request bar); an accepted chat has no Block.
  - Add **"Block <Name>"** (destructive, red) at the bottom of the chat's **⋯ menu**, with the same confirmation ("Block <Name>? Their new messages won't be shown on this phone.").
  - After blocking, return to Messages; the person appears in **Settings → Privacy → Blocked** (with Unblock).
  - Add a UI test.
- Implement the above. **Remove the one-tap identified resend UI for this case.**
- "Not delivered" remains only for genuine failures (the identified retry itself failing, network errors after the retries).
- Docs: `api-v2.md` §4 (the 403 rule as built); `architecture.md` §5 (the note: the fallback message reveals the sender to the server, once).

**Verification:**
- `cargo test` + the local and staging e2e: block → the blocked person's next message reads **"Sent"**, is stored identified, and **is not shown** on the blocker's phone;
- **a re-keyed (new phone) contact receives the fallback normally;**
- unblock → sealed resumes after the key share;
- the iOS tests; 0 warnings.

**Gate:** Jean blocks Shem → Shem's message reads "Sent", and Jean doesn't see it; unblock → normal.

**Record:** `## LIME-96-fix`. Commit: `fix: silent identified fallback on sealed refusal (no block hint)`, trailer `Brief: LIME-96-fix`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

---

### LIME-97 → `tend` (lime-aa) (after LIME-96-fix): group chats (Megolm, client-managed group state) + New Group
**What it does:** real end-to-end encrypted group chats per `docs/api-v2.md` §§3, 5–6 and `architecture.md` §3: Megolm sessions, encrypted client-managed group state (the server never learns groups, names or members), New Group creation from the New Message sheet (DESIGN-04), and group details.

**Capabilities assumed:** edit files, `cargo`, the Supabase CLI (deploy without `config push`), XcodeGen, `xcodebuild`, commit, push.

**Phase 0:** commit `PLOT.md` as on disk, unedited (`chore: update PLOT.md`, plus the attribution trailer).

**Phase 1: survey (read only):**
- `api-v2.md` §§3, 5–6 (the group ops; the authority + conflict rules; Megolm rotation);
- vodozemac's Megolm API;
- the core (sessions, ordering, sealed sends from LIME-96, threads, search);
- the iOS New Message sheet + chat header;
- DESIGN-04.

If anything contradicts `api-v2.md`, stop and ask the user.

**Phase 2: the change.**
1. **Group state (core):**
   - the encrypted, signed ops `group.create / add / remove / leave / rename / set_role`, sent to every member device over Olm (sealed where a delivery key is held);
   - ordered by HLC + parents;
   - **every client enforces the authority rules** (the owner/admins add, remove and rename; a member may leave);
   - the deterministic conflict rules from `api-v2.md` §5 (a concurrent remove beats an add; rename by `(hlc, op_id)`; owner succession).
2. **Messages:**
   - **one Megolm outbound session per sending device per group**, its key shared to each member device via Olm;
   - **rotate on any membership change, every 100 messages, or every 7 days**;
   - receivers hold inbound sessions;
   - a message arriving before its session key waits in `pending_inbound` and decrypts when the key arrives.
   - **The fan-out send uses one shared ciphertext + per-device recipients** (the server's batch shape).
   - Threads and formatting work in groups too.
3. **iOS:**
   - **New Group** (the row in New Message, now enabled): a multi-select of known teachers with **removable chips** + "N Members" + **Next** (accent) → **group name** (required, ≤ 50) + an optional emoji/initials avatar → **Create**.
   - **The group chat:** the avatar stack + "N members" header; sender names + avatars on bubbles (existing).
   - **Group details** (tap the header): the name (rename if allowed), the member list with roles, **Add members** (owner/admin), **Remove** (owner/admin), **Leave group**.
   - **System lines in the timeline:** "Jean added Lee", "Rae renamed the group…".
   - **Requests:** an invite from a non-contact creates the group in Requests until accepted.
4. **Limits:** max 100 members (the PD-call target; document it).
5. **Docs:** `api-v2.md` §11 (the group op payloads, Megolm rotation as built), `architecture.md` §3.

**Out of scope:** invite links/QR (LIME-97b), group calls, admin transfer UI beyond the succession rule, group photos (emoji/initials only), push.

**Phase 3: verification.**
- `cargo test` + integration (local and staging), clippy, iOS tests on the three simulators; 0 warnings.
- **New tests:**
  - create a group of 3 and all receive it;
  - Megolm decrypts for all members;
  - **a removed member can't decrypt messages after removal** (rotation);
  - a late joiner can't read history from before joining;
  - concurrent add/remove resolves the same on every device;
  - only admins can rename (a non-admin rename is ignored by others);
  - leave;
  - a message before its key → pending → it decrypts when the key arrives;
  - **a server-side check: no table holds group names or member lists** (an admin query in the test only).
- **A 3-account local e2e:** create, chat, add, remove, rename, leave.
- **Staging e2e** with throwaway accounts.

**Gate (the user, two phones + simulator):**
- Shem creates "Grade 4 Team" with Jean (+ the simulator account if handy);
- both see it; chat; rename; remove/add;
- Jean leaves and sees no new messages.

**Record:** a `## LIME-97` entry in `TEND.md`. Commit: `feat: E2EE group chats (Megolm, client-managed group state), New Group, group details`, trailer `Brief: LIME-97`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

---

### LIME-97b → `tend` (lime-aa) (after LIME-97): invite teachers + QR codes (DESIGN-04)
**What it does:** DESIGN-04's invite and QR features.

**Phase 0:** commit `PLOT.md` unedited. **Phase 1:** survey DESIGN-04, the profile/key code, and the New Message sheet; stop and ask the user on any conflict.

**Phase 2:**
1. **Invite:** a "More → Invite teachers to Lime" row and the empty-state card.
   - Apple's **system contact picker** (no Contacts permission; only the picked entries are seen).
   - Then Messages / Mail / Share sheet from the teacher's own phone, prefilled: "Join me on Lime, a private messenger made for teachers: https://limechat.org/u/<username>".
   - **Lime's servers never send invites or learn who was invited.**
2. **The invite link page:** a minimal static page for `limechat.org/u/<username>` explaining how to get Lime (TestFlight/App Store "coming soon"), hosted for free (Cloudflare Pages / Codeberg Pages). **Tend gives the user the steps to point the DNS (in deSEC) and doesn't create accounts for them.**
   - Universal links come later (the paid account).
3. **QR:**
   - **My QR code** in Settings/Profile, encoding the invite link **plus the identity-key fingerprint**;
   - **Scan QR Code** on Find by Username (the camera permission text: "Lime uses the camera to scan a teacher's QR code.");
   - scanning opens their profile → Message;
   - **if the fingerprint matches the server's key, mark them "Verified in person"** (a badge in their profile/chat);
   - a mismatch shows a warning.
4. **Note:** QR-based *offline* first contact comes with mesh v1.

**Verification:**
- the tests (the QR encode/decode round-trip, the fingerprint match/mismatch, the invite text);
- 0 warnings;
- screenshots.

**Gate:** invite someone from Messages (check the prefilled text); show your QR; Jean scans it → "Verified in person".

**Record:** `## LIME-97b`. Commit: `feat: invite teachers (system picker, own-device sending), QR codes with in-person verification`, trailer `Brief: LIME-97b`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

---

### LIME-103b → `tend` (lime-aa) (build now, field test tomorrow): the "leave it on the table" Bluetooth test (≈ 5 minutes of the user's time)
**Why it's shaped this way:** the user (3 kids) can't do a 2-hour hands-on session. **The test must run unattended:** two phones on a table, set up in ~2 minutes, read back the next morning. **That's actually the best way to answer the open question** (long-idle background delivery and screens-off battery), because an overnight run covers 15 min, 1 h and many hours at once.

**Capabilities / Phase 0:** as in LIME-103. Commit `PLOT.md` first, unedited.

**Phase 1: survey (read only):** the LIME-103 spike code and `docs/spike-ble.md` §5.

**Phase 2: the change (Debug only, in the Nearby test).**
1. **Fix the two LIME-103 bugs:**
   - the `ms` key collision (separate `duration_ms` from the timestamp);
   - **the blank "Share all" sheet** (pass the log files as file URLs / an activity item provider; verify on a real device during the field test).
   - **Also add a fallback:** the logs are readable via `xcrun devicectl` from the app container, documented in `ios/README.md`.
2. **"Auto test" mode: one big button per phone, two roles:**
   - **Sender (phone A):** after Start, **queues and sends automatically**, with no taps. One signed 4 KB blob **every 5 minutes**, plus one 32 KB blob every 30 minutes, for up to 12 hours.
     - It keeps trying while backgrounded/locked, and holds a queue of unsent blobs that it delivers when a link exists (a real store-and-forward behaviour).
     - It logs each attempt and result.
   - **Receiver (phone B):** Start, then the user locks it and leaves it. It logs each arrival with the time since the screen locked, and the battery every 15 minutes (the screen is off).
   - **A morning summary card** on both phones: "Sent 96 · delivered 94 · longest gap 11 min · first miss after 2 h 10 m · battery 100 → 81%". It's readable at a glance, with no log reading needed.
3. **A 2-minute force-quit check** (to redo scenario 8 properly): a "Force-quit check" role. B starts it, **then** the user swipes Lime away, and A keeps sending for 2 minutes. When B is reopened, it reports whether anything arrived while it was quit (expected: no) and whether A saw B's Lime service disappear.
4. **`docs/spike-ble-test-plan-2.md`, at most 10 lines, plain words:**
   1. charge both phones; plug both in, or note it: **unplugged is better for the battery reading; plugged is fine if needed**;
   2. Nearby test → Auto test → Sender on A, Receiver on B;
   3. lock both phones, put them ≤ 2 m apart, go to bed;
   4. in the morning: read the summary cards (screenshot both);
   5. optional 2-minute force-quit check.

5. **Amendment (the user, 2026-10-08): running TONIGHT, not tomorrow.**
   - **Jean will pick up phone B now and then (the flashlight, maybe other apps), leaving Lime in the background, not force-quit.**
   - The receiver must **log the phase changes** (unlock/lock, foreground/background, other app in front) so the summary separates "delivered while locked and idle" from "delivered during a pickup".
   - The summary card adds: **"longest idle stretch with no pickups: X h Y m, delivered N of M in it"**.
   - **Pickups are not failures.**
   - **Tend installs on both phones in Phase 3** (the user plugs each in when asked) and ends with a 6-step setup the user can follow at bedtime.

- **LIME-96 landed as `55062b3`** (pushed and verified; no server change).
  - Delivery keys (hash only on the server), encrypted control-op sharing (on accept / start chat / unblock / key-change accept / after rotation; the migration queues it for already-accepted chats);
  - sealed sends for contacts, verified by an admin query that the server stores no sender;
  - a sealed 403 → "Not delivered" + a one-tap identified resend;
  - block = rotate + re-share to the others.
  - 96 Rust / 36 server / 175+55 iOS tests pass; 0 warnings.
  - **Accepted trade-off:** sealed messages to a replaced phone still read "Sent" (the server can't notify an anonymous sender); the next send shows "Not delivered".
  - **Plot's flag to the user (a privacy nuance):** "Not delivered" after a block **hints to the blocked person that they were blocked** (or that the contact changed phones). Signal shows blocked messages as sent.
    - **Lean:** on a sealed 403, **silently retry identified once** and show "Sent" (no hint; still no loss for a genuine phone change).
    - The cost: that one message reveals the sender to the server.
    - **DECIDED: B (the user, 2026-10-08). LIME-96-fix landed as `703b6eb`.**
      - Silent identified fallback → "Sent"; a new migration drops the resend columns; **Block <Name> in the chat ⋯ menu**.
      - 96 Rust / 175+56 iOS tests pass; 0 warnings.
      - A changed-phone contact receives the fallback as a Request (fresh store), not in the old chat: acceptable.
      - **The user's gate: "looks good" (2026-10-08). Tend is on LIME-97.**
  - **The phones still have the spike builds.** The LIME-96 build must be installed; **the Debug build still includes the Nearby/Auto test**, so tonight's 103c works with it, and reinstalling resets the 7-day expiry.
- **LIME-103c STARTED ~02:10, 2026-10-09** (the first attempt showed delivered 0 because Jean's receiver wasn't started; fixed).
  - **Setup lesson for the briefs/plan:** the receiver must show "Receiving" and the sender must show delivered ≥ 1 **before** locking either phone.
- **LIME-103c runs night 2026-10-09:**
  - **both phones asleep AND fully offline** (Airplane Mode + Bluetooth on, Wi-Fi off);
  - Shem's Auto-Lock set to 30 s;
  - the sender's "Keep the screen on" unticked;
  - Jean's phone is the receiver (pickups allowed);
  - the build stays at 98d `73b5be0`.
  - Morning: both summary cards → tend's Phase 4 for 103c.
- **(Superseded) LIME-103c is scheduled for tonight (2026-10-08)**, the user's choice: the same setup, with the sender's "Keep the screen on" unticked and both phones locked. **Tend is on LIME-96 meanwhile.**
- **The analysis landed as `aa6f5d1`.**
  - 87/89 were delivered first try (median 0.5 s); 2 were re-sent by the queue after link drops (~95 s late).
  - **39 link drops in 6.3 h (~6/h)**; iOS reconnected each time. The resumable/ack design is confirmed as necessary.
  - **What Lime can say:**
    - **it receives while locked/backgrounded if not swiped away;**
    - **swiping away stops nearby delivery;**
    - **it must NOT yet claim** sleeping-to-sleeping relay.
  - B's own raw log wasn't copied (optional: plug in Jean's phone).
  - **Next spike, LIME-103c (no new build):** the same overnight run with "Keep the screen on" **off** on the sender (both asleep). It can run any night before the builds expire (~10-15).
- **OVERNIGHT RESULT (2026-10-08 07:16): the long-idle question is answered: YES.**
  - **Sender A** (awake, plugged in): 88 created/sent/delivered, longest gap 6 min, no misses.
  - **Receiver B** (Jean's, locked, unplugged):
    - **received 89/89**, no misses, longest gap 5 min;
    - **longest untouched idle stretch 4 h 7 m, with 57/57 delivered in it**;
    - all idle time 6.3 h, with 88/88 delivered; 4 pickups;
    - **87 arrivals while locked**, 2 with another app in front, 0 with Lime in front;
    - **battery 85% → 75% over ~7.4 h (≈ 1.4%/h)**.
  - **Implication:** a locked, long-idle receiver with Lime backgrounded (not force-quit) keeps receiving over BLE for hours at a modest battery cost.
  - **Still open:** both phones asleep/locked (sender also suspended), which the real mesh needs; force-quit (not run); state restoration after a system kill.
  - Phase 4 has been sent to tend.
- **The overnight run STARTED (the user, 2026-10-08, ~01:00).** The user will send both morning summary screenshots; then send tend Phase 4.
- **Status (2026-10-08 00:48):** the build is installed on both phones. **Tend's deviation (accepted): A (the sender) stays awake + plugged in all night**, so the test isolates **B's long-idle receive** (a locked A would suspend and confound it). The setup is in `docs/spike-ble-test-plan-2.md`. The overnight run starts tonight; tend commits once its simulator suites finish.

**Out of scope:** the mesh protocol, multi-hop, Release builds.

**Phase 3: verification.**
- Unit tests for the queue, the summary maths and the log keys;
- the simulators don't crash; 0 warnings;
- Release still has no Bluetooth (`ios/check-release-no-bluetooth.sh`);
- build to both phones if connected (**reinstalling also resets the 7-day expiry**).

**Phase 4 (after the user's screenshots and/or logs):** update `docs/spike-ble.md` with:
- the long-idle results (delivery over time while locked; the first miss; the gaps);
- screens-off battery per hour;
- the force-quit result;
- a final recommendation on what the product can promise for "app closed".

**Gate (the user):**
- tomorrow night: start the Auto test on both phones (~2 minutes);
- in the morning: screenshot both summary cards and send them.

**Record:** `## LIME-103b` in `TEND.md`. Commits: `spike(ios): unattended Bluetooth auto test, share fix`, later `docs: Bluetooth long-idle results`. Trailer `Brief: LIME-103b` plus the attribution trailer. **Push.** Stop after each. No /loop wakeups.

---

### LIME-96 → `tend` (lime-aa) (next): sealed sender for accepted contacts; server-side block via delivery-key rotation
**What it does:** turns on the blind mailbox's main privacy property (`docs/api-v2.md` §§3–4; D8 = B).
- **Messages to people who have accepted you are sent sealed**, so the server learns the recipient device but **not the sender**.
- **Strangers' first messages stay identified** (Requests).
- **Block now works on the server too**, by rotating your delivery key.

The server's sealed path already exists (LIME-92: `send` with `{ sealed: access_key }`, `delivery-access-set`, all-or-nothing 403).

**Capabilities assumed:** edit files, `cargo`, the Supabase CLI (deploy functions/migrations **without `config push`**), XcodeGen, `xcodebuild`, commit, push.

**Phase 0:** commit `PLOT.md` as on disk, unedited (`chore: update PLOT.md`, plus the attribution trailer).

**Phase 1: survey (read only):**
- `docs/api-v2.md` §§3–4, 11 (the delivery key, `access_key = HKDF-SHA256(delivery_key, "lime-access-v1")`, 16 B; the server stores SHA-256);
- `core/` (client, store, `pending_inbound`, the sealed-item handling, request state, block);
- `supabase/functions/send` + `delivery-access-set`;
- the LIME-95/95-fix accept/block flows.

If anything contradicts `api-v2.md`, **stop and ask the user**.

**Phase 2: the change.**
1. **Delivery key lifecycle (core):**
   - On registration, create a random 32-byte delivery key (in the SQLCipher store) and upload its access hash via `delivery-access-set`.
   - **Re-key after a master-key replacement** (LIME-95-fix): a new device means a new delivery key.
2. **Sharing it (an encrypted control op over the existing Olm channel):**
   - when you **Accept** a request, and when **you** start a chat with someone (you're implicitly accepting them), send them a `delivery_key.share { key }` control op;
   - store contacts' delivery keys locally;
   - **never display or log keys.**
3. **Sending:**
   - **with a contact's delivery key:** use **sealed** (no JWT on the request; `access = { sealed: access_key }`). The inner envelope carries `sender_user`, `sender_device` and a `sender_cert` (the device key signed by the master key) per `api-v2.md` §3.
   - **without one:** use identified (as today).
   - **If a sealed send gets 403** (the recipient rotated the key: blocked you, or re-keyed): don't retry identified automatically. **Mark the message "Not delivered"**; fall back to identified only if the recipient is not blocking (unknown to the sender, so: one identified retry, which lands in their Requests if they re-keyed for a new device, or is dropped server-side if blocked). **Plot's call:** one identified retry, no more. Document it.
4. **Receiving sealed:**
   - process the sealed items held in `pending_inbound` (from LIME-94);
   - decrypt with Olm;
   - **verify `sender_cert` against the sender's pinned master key** (the key-changed flow from LIME-95-fix applies);
   - only then attribute the sender.
   - A sealed item that fails verification stays in `pending_inbound` with its reason. It is never shown.
5. **Block = rotate:**
   - **Block** creates a new delivery key, uploads its hash and **re-shares it with every accepted, non-blocked contact.**
   - The blocked person's sealed sends now fail with 403. Their identified sends still reach the server but are hidden locally (as today).
   - **Unblock** shares the current key with them again.
6. **App:** no visible change, except a Debug-only About row "Sealed contacts: N".
   - Message bubbles are unchanged.
   - Not delivered uses the existing state.
7. **Docs:** `api-v2.md` §§3–4 + §11 (the control-op format, the 403 retry rule, re-key triggers); `architecture.md` §5 (sealed is now live for contacts).

**Out of scope:** groups/Megolm (LIME-97), hiding recipient sets, padding/timing defences, push.

**Phase 3: verification.**
- `./supabase/test.sh`, `cargo test` (+ integration local and staging), clippy, iOS tests on the three simulators; `ios/check-warnings.sh` reports 0 warnings.
- **New tests:**
  - after Accept, both sides hold each other's delivery keys and **subsequent sends are sealed**;
  - **a server-side check that a sealed item stored has no sender user id** (an admin query in the test only);
  - a tampered `sender_cert` → rejected, not shown;
  - Block → the blocked person's sealed send gets 403 → "Not delivered";
  - non-blocked contacts still deliver sealed after the rotation;
  - Unblock restores;
  - a master-key replacement re-keys and re-shares;
  - a stranger's first message stays identified and lands in Requests.
- **Staging e2e** with two throwaway accounts (create/delete via the admin API).

**Gate (the user, both phones):**
- Shem ↔ Jean keep chatting normally (now sealed; nothing looks different);
- **Jean blocks Shem → Shem's next message shows "Not delivered";**
- Jean unblocks → messages flow again.

**Record:** a `## LIME-96` entry in `TEND.md`. Commit: `feat: sealed sender for accepted contacts; block rotates the delivery key`, trailer `Brief: LIME-96`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

---

### LIME-103 → `tend` (lime-aa) (landed: build `be3633a`, analysis `010d040`): the Bluetooth spike: can two iPhones find each other and pass encrypted blobs with no internet?
**What it does:** a **throwaway, Debug-only experiment** that measures what iOS really allows for Bluetooth LE between two Lime phones, open, backgrounded and locked, **before** the mesh is designed in detail (`architecture.md` §7, DESIGN-01 §4).
- **The output is evidence**: `docs/spike-ble.md` with measured numbers and a recommendation. **The spike code is not the product**; it lives behind `#if DEBUG` and is deleted or replaced by mesh v1.

**Capabilities assumed:** edit files, XcodeGen, `xcodebuild`, commit, push. Tend **can't** hold the phones, so the user runs the field test with **two real iPhones**: Shem's 13 mini + Jean's, both installed from the user's Mac (free provisioning). Tend prepares the build, the test script and the log export, then analyses the logs the user sends back.

**Phase 0:** commit `PLOT.md` as on disk, unedited (`chore: update PLOT.md`, plus the attribution trailer).

**Phase 1: survey (read only):**
- `docs/architecture.md` §§4, 7; `docs/api-v2.md` §8 (the mesh relay unit = the outer envelope);
- Apple's current CoreBluetooth docs: the background execution modes (`bluetooth-central`, `bluetooth-peripheral`), state preservation and restoration, the background advertising limits (service UUIDs moved to the "overflow area"; discoverable only by devices explicitly scanning for that UUID), background scanning (must name service UUIDs; no duplicates; slower), L2CAP channels (`CBL2CAPChannel`) vs GATT.
- **Confirm that `UIBackgroundModes` Bluetooth works with free (Personal Team) provisioning.** If it needs the paid account, **stop and tell the user**.

**Phase 2: the change (Debug only).**
1. **A "Nearby test" screen**, reachable only in Debug from About (long-press the logo):
   - **Start/Stop**, a role display (each phone is both central and peripheral);
   - a live log: discovered / connected / sent / received, each with timestamps, RSSI and sizes;
   - **Send test blobs:** random bytes of **200 B, 4 KB, 32 KB** each, signed with the device's Ed25519 key from LimeCore (so the receiver verifies them). **No real messages, no user data, no keys in the payload.**
2. **The transport:**
   - one custom service UUID; the peripheral advertises it; the central scans for it (with the service filter, as required in the background);
   - **GATT** write-with-response + notify as the baseline;
   - **an L2CAP channel** attempt for throughput (report both).
   - De-dupe by blob hash.
   - **State restoration** enabled, with the identifiers recorded.
3. **Background modes:** add `bluetooth-central` + `bluetooth-peripheral` to `UIBackgroundModes` **in Debug builds only** (via `project.yml` per-configuration Info.plist keys). Add `NSBluetoothAlwaysUsageDescription`: "Lime uses Bluetooth to pass messages between nearby teachers when there's no internet."
4. **The log export:** a "Share log" button (the iOS share sheet), with a JSON lines file per run: the device model, the iOS version, the scenario label, the events. **No personal data.**
5. **`docs/spike-ble-test-plan.md`: a step-by-step field script for the user** (plain language) covering these scenarios, each run ~5 minutes, with the label typed into the app before starting:
   1. both open, 1 m apart;
   2. A open, B **backgrounded** (Home);
   3. **both backgrounded**;
   4. A open, B **locked, screen off**;
   5. **both locked**;
   6. distance: 10 m same room, and through one wall (both open);
   7. **Airplane mode with Bluetooth re-enabled** (no internet at all), both open;
   8. B **force-quit** (swiped away), to confirm it does nothing, as expected.

   For each: time to first discovery, the connection success, the throughput per size, the reconnects, and the delivery while backgrounded/locked. Also note the battery % at the start and end of the whole session.

**Out of scope:** the mesh protocol, multi-hop, the store-and-forward database, real message delivery, Android, anything in Release builds.

**Phase 3: verification (tend's part).**
- Build + the existing tests pass on the three simulators (the Bluetooth features are guarded so the simulators don't crash); `ios/check-warnings.sh` reports 0 warnings.
- **A Release-configuration build contains no Bluetooth background modes and no Nearby screen** (check the built Info.plist and the symbols).
- **Build to both iPhones if connected**; otherwise give the user the exact steps.
- Write `docs/spike-ble-test-plan.md`. **Stop and hand over to the user for the field test.**

**Phase 4 (after the user returns the logs): the analysis.**
- Tend parses the logs into **`docs/spike-ble.md`**: a results table per scenario (discovery time, success, throughput, background/locked behaviour), what iOS allowed vs blocked, the battery note.
- **A recommendation for mesh v1:** GATT vs L2CAP; the realistic expectations ("works when at least one phone has Lime open"…); UX implications (e.g. a "Nearby mode" the teacher turns on); whether any of DESIGN-01 §4 / `architecture.md` §7 needs changing (**flag it, don't decide**).

**Gate (the user):**
- run the field test with Jean using the plan;
- send tend the exported logs (AirDrop them to the Mac, then tell tend the folder);
- read `docs/spike-ble.md`.

**Record:** a `## LIME-103` entry in `TEND.md` (the build) and an update after the analysis. Commits:
- `spike(ios): Debug-only Bluetooth LE field test (Nearby test screen, logs, test plan)`;
- later `docs: Bluetooth spike results`.

Both get the trailer `Brief: LIME-103` plus the attribution trailer. **Push.** Stop after each. No /loop wakeups.

---

### LIME-101b → `tend` (lime-aa) (landed as `6c49400`): colour hierarchy polish, word-level find highlight, New Message v2 (1:1)
**What it does:** the user's review of LIME-99/100 on real phones (2026-10-07).
- **Milestone:** the screenshots show **Shem's and Jean's iPhones chatting end to end** ("it works" / "True it does work!"), so **the LIME-95-fix two-phone gate has passed.**
- **The principle the user set:** **the accent green is reserved for the one primary action on a screen** (send, Find, Next, Continue). Secondary/active states use a **warm neutral**.

**Capabilities assumed:** edit files, XcodeGen, `xcodebuild`, commit, push.

**Phase 0:** commit `PLOT.md` as on disk, unedited (`chore: update PLOT.md`, plus the attribution trailer).

**Phase 1: survey (read only):**
- the theme tokens;
- the composer (the Aa active state, the selection);
- the in-chat find (the highlight);
- `NewMessageSheet`;
- `ConversationStore` (known people);
- DESIGN-04 in `PLOT.md`.

If anything contradicts this brief, stop and ask the user.

**Phase 2: the change.**
1. **Text selection = the system default blue.** Remove any app-wide tint that makes the selection, the caret and the selection handles green (in the composer, the editors and the search fields). The accent stays on buttons only.
2. **The format toolbar's active states → a warm neutral:**
   - **Aa** while the toolbar is open, and the pressed B/I/U/S/etc., use a **warm neutral fill** (a token, e.g. `surface.pressed`; ≥ 3:1 against the bar, ink ≥ 4.5:1), not green;
   - **only the send button is green.**
3. **Find highlights the matched words, not the bubble:**
   - in-chat find draws a highlight behind **each matched word** in the bubbles (a soft warm-yellow/neutral background, readable in both bubble colours, light and dark);
   - **the current match** is stronger than the others;
   - **remove the bubble outline.**
   - Messages-search results keep the bold words; opening one highlights the words in the chat the same way.
4. **New Message v2, 1:1 only** (DESIGN-04; groups/invite/QR stay in LIME-97):
   - **A sheet titled "New Message"** with a glass ✕.
   - **A card of actions:** **Find by Username**, **Find by Email**. **New Group** is shown dimmed with "Coming soon"; Find by Phone is hidden (S1 = A).
   - **An A–Z list of known teachers** (anyone you have a conversation with, accepted), with avatars, names and an `@` badge, plus **an index rail** on the right. Tap → open or start the DM.
   - **A floating glass search field at the bottom** ("Name, username or email"):
     - filters the list live;
     - on submit, does the **exact** server lookup for a username/email;
     - a match appears as a **row** (avatar, name, `@username · school`), and tapping the row starts the chat;
     - **there is no separate "Message" button**, so nothing competes with the primary action.
   - **Find by Username / Find by Email** are pushed screens: ‹ back, a centred title, a **Next** button top right (accent, dimmed until valid), and one field. Next → the result row → tap to message. "No teacher found" otherwise.
   - **The empty state** (no known teachers yet): "Find teachers by their username or email."
   - Remove the old sheet (the big Find button plus the Message card).

**Out of scope:** groups, invite, QR, the phone lookup, partial directory search.

**Phase 3: verification.**
- iOS unit + UI tests on the three simulators; `ios/check-warnings.sh` reports 0 warnings.
- **New tests:**
  - the selection tint is the system default;
  - the Aa active and pressed states aren't the accent colour (a token check);
  - find highlights ranges inside a bubble with no outline;
  - New Message: the list sorted A–Z with the index jump; live filter; an exact lookup by username and by email; the empty state; Find by Username's Next is disabled until input.
- Screenshots (light and dark, 375pt): the composer with selected text and the toolbar; find with a word highlight; New Message (list); Find by Username.

**Gate (the user, on the iPhone):**
- selected text is blue;
- the Aa and pressed format buttons are warm grey, and only send is green;
- find highlights just the word;
- New Message shows your teachers A–Z with search at the bottom, and Find by Username works.

**Record:** a `## LIME-101b` entry in `TEND.md`. Commit: `polish(ios): accent only for primary actions, word-level find highlight, New Message v2`, trailer `Brief: LIME-101b`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

---

### LIME-102 → `tend` (lime-aa) (after LIME-101b): notifications, stage 1 (local + in-app chime; APNs later)
**DECIDED (user, 2026-10-07):**
- **N1 = A:** the user/a designer supplies the chime sound.
- **N2 = A:** name + message text by default (decrypted on the device), changeable in Settings.

**Amendment (the user, 2026-10-07): go ahead WITHOUT the chime file.**
- Build everything except the custom sound.
- **The Sound setting offers "Default" (the iOS system sound) and "None" for now.** The in-app arrival sound uses the system default.
- **Leave a single, documented hook** (`ios/Lime/Resources/Sounds/`, a README note naming `lime-chime.caf` and the conversion command) so adding the user's file later is a 1-line change that adds "Lime chime" as an option and makes it the default.
- **Don't synthesise or bundle any placeholder sound.**

**(Superseded) Prerequisite for LIME-102:**
- the user provides the chime file (≤ 2 s; WAV/AIFF/CAF; mono is fine; they must own the rights).
- **If it isn't provided when LIME-102 starts, tend stops and asks.** It must not synthesise a placeholder (the user chose A).
- Tend converts it to `lime-chime.caf` (linear PCM or IMA4, ≤ 30 s as Apple requires) at `ios/Lime/Resources/Sounds/`.

**Drafted as an outline; finalise before sending.**
- **The chime:** the user's sound file (N1 = A), converted to `lime-chime.caf`.
- **While the app is open:**
  - a new message in another chat shows an in-app glass banner + the chime (respecting the silent switch via the system sound APIs);
  - nothing plays in the chat you're viewing (a subtle tick instead).
- **While backgrounded but alive:** a local notification (`UNUserNotificationCenter`) with the preview per **N2 = A (name + message; the stripped plain text from LIME-100)**, the custom sound, grouped by conversation (`threadIdentifier`), a tap opening the chat/thread; the badge count = unread chats.
- **Permissions:** a pre-prompt screen explaining why (DESIGN-03's later "permissions explainer"), then the system prompt; and respect "Not now".
- **Settings → Notifications:** On/Off, Preview (name + message / name only / "New message"), Sound (Lime chime / Default / None), per-chat **Mute** (1 h / 8 h / 1 week / Always).
- **Stage 2 (a later brief; needs the paid Apple account):** APNs + the Notification Service Extension that decrypts on the device; the server sends content-free pushes; push tokens per device.

### LIME-95-fix → `tend` (lime-aa) (landed as `3c42366`): the user's phone can't search or receive; inconsistent avatar colours
**What the user saw (2026-10-07, two real iPhones on staging):**
- **Jean's iPhone (newly installed, signed up fresh):** finds `@shem` and sends "Hi Shem" → "Sent".
- **Shem's iPhone (13 mini; account created during the 8-digit-OTP period; signed in earlier):**
  - every search (`jean`, `jean@famkind.com`) fails with **"Couldn't search. Check your connection and try again."** while the phone is online;
  - **Jean's message never appears** (no Request).
- **Avatar colours differ:** "SR" is purple in Jean's search result but yellow in Jean's chat header.

**Tend's diagnosis (relayed 2026-10-07):** Shem's phone has **fresh keys whose master key differs from the one fixed at the account's first registration** (trust on first use; `api-v2.md` §11). So the device can't register, and every verified call fails.
- **Tend asked the user how a phone with fresh keys regains an existing account.**
- **Plot recommended option 1, with three additions:**
  - **"Verified sign-in resets keys"**, Signal-style re-registration: password + emailed code may replace the master key; the old devices are revoked; contacts who pinned the old key see **"Shem's security key changed"** and must tap Accept before messages flow.
  - **Additions:**
    - (a) **email the account** whenever its master key is replaced ("A new phone signed in and replaced your Lime keys. If this wasn't you, reset your password.");
    - (b) messages waiting for the old devices are discarded, and **the sender sees them as "Not delivered"** where possible;
    - (c) **this is temporary policy**: once the recovery key (D5) exists, a **registration lock** requires the recovery key to replace the master key (Signal's model).
- **Pending the user's answer.**

**Plot's hypothesis (superseded by the diagnosis above):**
- Shem's phone's session is in a bad server-side state, e.g. a session never marked verified in `auth_proofs`, a device registered under an older schema/flow, or a session/token rejected after refresh.
- So **every authenticated function returns 401/403**, and the app maps it to a "connection" message.
- `sync` fails the same way, so nothing is fetched.

**Capabilities assumed:** edit files, the Supabase CLI/admin access to **staging (read-only queries for diagnosis)**, deploy functions **without `config push`**, Xcode, commit, push.

**Phase 0:** commit `PLOT.md` as on disk, unedited (`chore: update PLOT.md`, plus the attribution trailer).

**Phase 1: diagnose. Report the root cause before changing anything. Read-only on staging.**
- **Don't ask the user to sign out yet:** signing out wipes the evidence (and the local keys, so Jean's first message would become unreadable).
- For `shem@famkind.com` on staging, inspect:
  - the Auth sessions;
  - `auth_proofs` rows (`password_ok` / `code_ok`, per `session_id`);
  - `devices` (registered? revoked? which keys);
  - `profiles`;
  - **`mailbox_items` addressed to Shem's device(s)** (is Jean's message waiting there, and for which `to_device`?);
  - the Edge Function logs for Shem's recent `identify`/`users-lookup`/`mailbox-fetch` calls (the status codes).
- Read only metadata; **never decrypt or print ciphertext or tokens**.
- Also check: did Jean's send target **all of Shem's current devices**? Is there a stale device for Shem from an earlier sign-up?

**Phase 2: the fix** (from the diagnosed cause):
- **The server or core fix** for the root cause, with a test reproducing it. Typical candidates:
  - the session-proof lookup across token refresh;
  - devices registered before LIME-94-fix;
  - sends that fan out only to stale devices.
- **The app must tell the truth:**
  - map 401/403 (session not verified/expired) to **"Your session has ended. Please sign in again."** with a Sign in button;
  - map rate limits and server errors distinctly;
  - keep "Check your connection" for real network failures only.
  - Log the HTTP status (no secrets) in Debug builds.
- **Recovery path for this user without losing data, if possible:** e.g. re-verify the existing session (password + code) instead of a full sign-out that wipes the store. If a full reset is unavoidable, say so plainly in the report.
- **Consistent avatars:** one function derives the avatar colour (and the initials) **from the user id** everywhere (Messages, chat header, New message results, Requests), the same on every device. Unit-test it.

**Out of scope:** LIME-96 (sealed sends), new features.

**Verification:**
- tests pass (server, Rust, iOS) and `ios/check-warnings.sh` reports 0 warnings;
- **a new e2e:** an account whose session was created, then refreshed after the 1h access-token expiry (simulate it), can still search and sync;
- the staging e2e passes;
- report **exactly what was wrong with Shem's account** and what the user must do on the phone, if anything.

**Gate (the user):**
- Shem's phone can find Jean and **receives Jean's messages** (Requests → Accept);
- both directions work;
- "SR"/"JC" avatars are the same colour everywhere on both phones.

**Record:** a `## LIME-95-fix` entry in `TEND.md`. Commit: `fix: <root cause>; truthful auth errors; consistent avatars`, trailer `Brief: LIME-95-fix`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

---

### LIME-95 → `tend` (lime-aa) (after the user's LIME-94-fix phone gate): New message and the first real 1:1 encrypted chat (iPhone ↔ simulator)
**What it does:** makes Lime useful between two real accounts:
- **New message** finds a teacher by **exact username or email**, opens a DM, and sends **end-to-end encrypted** messages.
- The other device receives them **live while the app is open**.
- Replies flow back. Both sides persist across restarts.

**The gate:** the user's iPhone (`shem@`) and the simulator (`jean@`) chat with each other through staging. It also cleans up the Xcode warnings that tend's checks missed.

**Plot's scope decisions (no new decisions for the user):**
- **Identified Olm sends only**, as in LIME-93/94; **sealed sends and delivery keys are LIME-96**.
- Because of that, **every first message from a new person lands in Requests**, per `api-v2.md` §4 + D7. The minimum UI for this brief:
  - a **"Requests" row** at the top of Messages when any exist;
  - opening one shows the messages plus **Accept** / **Block**;
  - **Accept** moves it into Messages;
  - **Block** hides it and stops showing that sender's messages locally.
  - The server-side block (delivery-key rotation) comes with LIME-96.
- **Live delivery while open:** subscribe to the device's Realtime channel (`device:<id>`, the "new items" nudge only), then sync. **Also sync on app foreground and on pull-to-refresh.** There is no push yet.
- **Message ordering:** use `hlc` + `parents[]` per `api-v2.md` §5 for display order.
- **DM display names:** the other person's profile display name via an authenticated `profile-get` for other users, which returns **public fields only** (display name, username, school, `hide_from_search` respected); never email or phone.
- **Search** (in New message): exact username **or** exact email (reuse `identify`/`users-lookup` rules; never list or partial-match yet). "No teacher found with that username or email" otherwise.
- **Delivery states in the bubble:** "Sending…" → "Sent" (server accepted). No read receipts yet.

**Capabilities assumed:** edit files, `cargo`, the Supabase CLI, deploy functions/migrations to staging **without `config push`**, XcodeGen, `xcodebuild`, commit, push. Stop and ask the user if anything needs a dashboard change or a paid plan.

**Phase 0:** commit `PLOT.md` as on disk, unedited (`chore: update PLOT.md`, plus the attribution trailer).

**Phase 1: survey (read only):** `docs/api-v2.md` (§§3–5, 7, 11), `core/` (the client, the store, `pending_inbound`), `supabase/functions/` (`send`, the mailbox, `profile-get`, `identify`, `users-lookup`), `ios/` (Messages, Chat, the empty-state cards, the onboarding timer). Find the two Xcode warnings in `OnboardingScreens` ("Cannot use generic class 'Autoconnect'…", "Cannot use enum 'Publishers'…") and **why tend's previous "no warnings" checks missed them**. If anything contradicts `api-v2.md`, stop and ask the user.

**Phase 2: the change.**
1. **Server:**
   - a public-profile read for other users (public fields only; rate-limited);
   - **confirm Realtime nudges work on staging** for a device channel, and the client may only subscribe to **its own** channel (Realtime authorisation);
   - tests; deploy.
2. **Core:**
   - `start_dm(...)` / `send_text(...)` reuse the identified Olm path;
   - `sync` assigns received messages to the DM with the sender, and marks **new senders as requests** (a `request_state` on the conversation: `pending` / `accepted` / `blocked`);
   - `accept_request` / `block_sender` (local);
   - HLC + parents ordering;
   - tests for ordering, requests, blocking (a blocked sender's new messages stay hidden) and `pending_inbound` interplay.
3. **iOS:**
   - the **New message** card and the "+" button open a sheet: one field (username or email) → Find → the person's name and school → **Message**.
   - **Chat** sends real messages; the bubble state goes Sending… → Sent.
   - **Live receive** via Realtime while in the foreground; sync on foreground and on pull-to-refresh.
   - **Requests** row and screen (Accept / Block).
   - The "Invite a teacher" card stays "Coming next".
   - **Fix the two warnings** (e.g. replace the `Timer` publisher with a `.task` countdown loop).
4. **Warnings check:** the verification must catch what the Xcode GUI shows. Build **for a device destination and a simulator**, and fail on **any** warning in Lime's own sources (excluding the generated UniFFI code), including Swift 6 concurrency/availability diagnostics.

**Out of scope:** sealed sends/delivery keys (LIME-96), groups/Megolm, push/APNs, attachments, typing/read receipts, partial-name directory search, contacts, Android, `public/`, `server/`.

**Phase 3: verification.**
- `./supabase/test.sh`, `cargo test` (+ integration local and staging), clippy, iOS tests on the three simulators: all pass; **0 warnings** by the stricter check.
- **The two-simulator e2e** (local stack): A finds B by username → sends → B sees it **in Requests** live → Accept → B replies → A receives it live → restart both → the history persists in order. Block test: B blocks A; A's next message is not shown to B.
- **Staging e2e** with two throwaway accounts (create/delete via the admin API; respect the 30s email interval; never read real inboxes).
- Screenshots: New message sheet, Requests, a chat with Sending/Sent, light and dark at 375pt.
- No secrets in git.

**Gate (the user):**
- Sign in on the **iPhone as shem@** and on the **simulator as jean@**. Tend explains how to sign the simulator in, since Jean's codes go to the jean@ inbox.
- From the iPhone, **New message → Jean's username → send "hello"**: it appears on the simulator **within a few seconds** under Requests → Accept → reply → the reply appears on the iPhone.
- Close and reopen both: the chat is still there.

**Record:** a `## LIME-95` entry in `TEND.md`. Commit: `feat: New message, requests, live encrypted 1:1 chat (identified Olm), warning-clean build`, trailer `Brief: LIME-95`, plus the attribution trailer. **Push.** Stop for the user's check. No /loop wakeups.

---

### LIME-94-fix → `tend` (lime-aa) (landed as `8d21e18`): emailed codes are rejected on staging; stale error messages
**What it does:** fixes the LIME-94 gate failure (the user's iPhone, 2026-10-06).
- **Sign-up works.**
- **But entering the emailed code fails** with "That code is not right. N tries left" during **sign-in** and **forgot password**.
- **The same red error also stays visible on later screens** (the password screens).

**Capabilities assumed:** edit files, the Supabase CLI (logged in), deploy to staging, Xcode tests, commit, push.

**Phase 0:** commit `PLOT.md` as on disk, unedited (`chore: update PLOT.md`, plus the attribution trailer).

**ROOT CAUSE CONFIRMED by the user (2026-10-06): the staging emails contain 8-digit codes**, while the app and `code-verify` accept 6.
- **The user was told to set Authentication → Sign In / Providers → Email → "Email OTP Length" = 6 in the dashboard.**
- Tend should still:
  - **verify** the staging OTP length reads 6 (read-only);
  - make the app and functions **tolerant of either 6 or 8 digits** (`^\d{6,8}$`; the app adapts its boxes to the configured length, or accepts paste of up to 8), so a future settings drift can't lock users out;
  - **add `otp_length` to a "staging settings that must match config.toml" check** in `supabase/test.sh` or `smoke-staging.sh` (read-only);
  - plus the stale-error and send-failure items below.

**Added visual changes (the user, 2026-10-06), iOS onboarding only:**
1. **The top-right "Next" glass button uses the brand primary**, like the main CTA ("Continue"): the accent `#a3e18a` fill with the dark accent ink (the same tokens as the welcome screen's Continue).
   - **The disabled state** stays clearly distinct: the neutral glass with a dimmed label.
   - Applies to every onboarding screen.
2. **The welcome screen logo:**
   - **remove the grey circle/backdrop** behind it;
   - **use the user's new asset `public/assets/lime-logo.svg`** (Penpot export, 288×349, about 44 KB; currently **untracked**, so commit it as part of this brief).
   - Bring it into the iOS asset catalog as a vector (preserve vector data; if the SVG has unsupported features for the asset catalog, convert it faithfully and say how).
   - Keep the app icon unchanged unless the user asks.
3. **The welcome copy:**
   - heading: **"Connect All Teachers"**;
   - subtext: **"A secure messenger made for teachers."** The user wrote "A secure, messenger…"; **drop the stray comma** as a typo. Show it to the user at the gate.
   - The rest of the welcome screen (Terms & Privacy, Continue) is unchanged.
- **The verification adds:** onboarding screenshots (light and dark, 375pt) of the welcome screen and one screen with the enabled + disabled Next; UI tests updated for the new copy.

**Phase 1: diagnose (read only first). Report the root cause before changing anything.**
1. **The staging Auth settings vs `supabase/config.toml`:** the hosted **Email OTP length** (local = 6; `code-verify` accepts only `^\d{6}$`, and the app has 6 boxes), the OTP expiry, and the per-user send interval (**the user set 30s minimum interval** in the SMTP settings). Read them via the Management API or the CLI **without changing them**.
2. **The staging Auth logs** (the Management API / the dashboard log query) for `shem@famkind.com`'s recent `/otp` and `/verify` calls: was each sign-in actually *sent* a new code, or was the `/otp` call rate-limited (so the user typed an older, already-used code)? What error does `/verify` return (expired, invalid, …)?
3. Whether `signin-password` / `code-resend` / `reset-start` **surface a failed `/otp` send** to the app (they must not show "We sent a code" if the send failed).

**Plausible causes to check:** an OTP-length mismatch (staging sending 8 digits); a code not re-sent because of the 30s interval or Supabase's own email rate limit; the wrong `type` for `/verify`; codes invalidated by a later resend.

**Phase 2: the fix** (the smallest change that addresses the diagnosed cause):
- **If it's a staging setting** (e.g. the OTP length), **tell the user exactly which dashboard field to change.**
  - **Do NOT run `supabase config push`**, or anything that writes Auth config to staging: it could wipe the user's custom SMTP (Resend) settings.
- **If it's code:** fix the function(s), plus a test reproducing it; deploy only the affected functions.
- **Always:**
  - a failed or rate-limited code *send* returns a clear error the app shows ("Please wait 30 seconds before asking for another code");
  - **error messages are cleared when moving to a new screen** and when the user edits the field;
  - the password screens never show a code error.

**Out of scope:** new features; changing the Auth settings on staging yourself.

**Verification:**
- the server tests (a new test for the diagnosed case) + the iOS tests pass;
- `./ios/run-e2e-local.sh` passes;
- **the staging e2e: sign-up → sign-out → sign-in by username → the code accepted**, with `jean@famkind.com` (clean up the account after; mind the 30s interval);
- no secrets in git.

**Gate (the user, on the iPhone):** sign in with your username + password, the emailed code is accepted, and you reach Messages; forgot password works; no stale red errors.

**Record:** a `## LIME-94-fix` entry in `TEND.md` (the root cause stated plainly). Commit: `fix(auth): <root cause>; clear stale errors`, trailer `Brief: LIME-94-fix`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

---

### LIME-94w → `tend` (lime-aa) (next; tiny, web): remove the Google/Apple "Soon" buttons from the web sign-in
**What it does:** the user asked (2026-10-06) to remove "Continue with Google" and "Continue with Apple" (both disabled, "Soon") from `public/auth.html`. This is the only change to the frozen web app.

**Capabilities assumed:** edit files, run the `tests/` suites, commit, push.

**Phase 0:** commit `PLOT.md` as on disk, unedited (`chore: update PLOT.md`, plus the attribution trailer).

**Phase 1: survey:**
- `public/auth.html` around lines 51–55 (the two `lime-auth__oauth` buttons);
- any wrapper, divider ("or") or CSS that exists only for them (`public/css/auth.css`), and the `.lime-badge--soon` usage elsewhere (**keep it if it's used elsewhere**);
- the tests that reference them.

**Phase 2:**
- Remove both buttons, plus any divider/wrapper that would be left empty or orphaned, and CSS used **only** by them.
- Don't change anything else on the page.
- Update any test that asserted them.

**Verification:**
- `cd tests && node run.mjs smoke css auth auth-phone`: 0 failures.
- `grep -n -i "Continue with Google\|Continue with Apple" public/` → no matches.
- Screenshots of `auth.html` at 1280 and 390 wide: the card has no gap where the buttons were.

**Gate:** the user opens the web sign-in page: no Google/Apple buttons, and the layout is tidy.

**Record:** a `## LIME-94w` entry in `TEND.md`. Commit: `chore(web): remove Google/Apple sign-in placeholders`, trailer `Brief: LIME-94w`, plus the attribution trailer. **Push.** Stop. No /loop wakeups.

---

### LIME-94 → `tend` (lime-aa) (after LIME-94w; needs the user's email-delivery answer): native sign-up and sign-in (email/username + password + emailed code), profiles, and safe inbound handling
**What it does:** builds DESIGN-03 (as decided: S1 = A, S2 = B) on iOS and the server.
- New users sign up, existing users sign in, and the device registers with the v2 server.
- **The Messages screen shows the account's real (empty) store** instead of the sample data.
- It also fixes LIME-93's **unsafe ack-everything sync**.
- The visible phone↔simulator chat is **LIME-95**.

**Capabilities assumed:** edit files, `cargo`, the Supabase CLI (logged in), the local stack via Colima, XcodeGen, `xcodebuild`, commit, push. **Stop and ask the user** if anything needs a paid plan, DNS changes, a password, or a new third-party account.

**Phase 0:** commit `PLOT.md` as on disk, unedited (`chore: update PLOT.md`, plus the attribution trailer).

**Phase 1: survey (read only):**
- `PLOT.md` "DESIGN-03" (the flow; the DECIDED block);
- `docs/api-v2.md` (§2 profiles/directory, §11);
- `supabase/`, `core/`, `ios/`;
- Supabase Auth's capabilities: email + password, email OTP, the JWT `amr` claim, MFA options. **Find out how to make the server *require both* the password and the email code before `devices-register` accepts a device.** If Supabase can't express it natively, design a small Edge Function challenge, e.g. a server-issued sign-in challenge marked complete only after both steps; describe it in the report.
- **Email delivery:**
  - Supabase's built-in email is for testing and heavily rate-limited (and may only send to the organisation's team members). **Confirm the current rules.**
  - **If the built-in sender can't deliver codes to the two test addresses the user will provide, stop and ask the user** (the likely fix is a free Resend account plus DNS records on famkind.com, which only the user can do).

If anything contradicts DESIGN-03 or `api-v2.md`, stop and ask the user.

**The test addresses (the user, 2026-10-06):**
- `shem@famkind.com` (the iPhone) and `jean@famkind.com` (the simulator). These are the intentionally public demo emails (see the session lessons).
- **Tend found** that the built-in sender allows 2 emails per hour for the whole project. **The user is advised to pick option 1:** build and test locally with the mail catcher, give the user the Resend steps, and run the staging end-to-end test after SMTP is set up in the dashboard (tend never sees the key).
- **The second test phone for the Bluetooth spike = Jean's iPhone** (the user, 2026-10-06), installed from the user's Mac (free provisioning, 7-day expiry) or via TestFlight later.
- **The Supabase org FAM now has 2 members** (2026-10-06): `shem@` (Owner) and `jean@` (Administrator; accepted). **MFA is enabled on both.** So the built-in sender's team-member restriction, if it applies, is satisfied for both test addresses.
- **The user can edit famkind.com's DNS** (confirmed 2026-10-06).
  - If the built-in sender can't reach both addresses, try the simplest fix first: invite `jean@famkind.com` to the Supabase organisation.
  - Otherwise, propose Resend (a free tier) with the exact DNS records for the user to add. **Stop and give the user the records and the steps; don't create accounts for them.**

**Phase 2: the change.**
1. **Server:**
   - a `profiles` table (the user id, display name, username (unique, case-insensitive, the same rules as on the web), school, `hide_from_search`), with RLS deny-all and Edge Functions only;
   - functions: profile set/get-own; **`username-resolve`** (username → a masked email hint for the sign-in confirmation sheet; exact match only; rate-limited; reveals nothing for unknown usernames beyond "not found");
   - the **two-factor enforcement** for `devices-register` from the survey;
   - tests in `supabase/test.sh`; deploy to staging.
2. **Core:**
   - **`pending_inbound`**: store every fetched item that can't be processed yet (unreadable, unsupported, sealed) **before** acking, with the reason and the attempts.
   - Retry it on each `sync` and after key or session changes. Never drop silently.
   - Tests: an unreadable item survives the sync and is retried successfully once the session exists; sealed items are kept, not lost.
3. **iOS onboarding (DESIGN-03 steps 1–7; the Lime look; glass Next; one question per screen):**
   - the splash;
   - the welcome (a **placeholder illustration** using the logo until the art exists; the copy from DESIGN-03; Terms & Privacy linking to `https://famkind.com` placeholders);
   - **"Your email or username"**: one field; phone numbers show "Phone sign-in is coming later. Use your email for now." (S1 = A);
   - the confirmation sheet (Yes / Edit; a masked hint for usernames);
   - the **6-digit code** (`oneTimeCode` autofill, resend after 30s);
   - **password** (sign-up: create + confirm, min 10 characters, a strength hint; sign-in: enter; "Forgot password?" → code → new password);
   - new account → name / optional username / optional school;
   - then Messages.
   - **Tokens go in the Keychain** (this device only). The core registers the device once both factors pass.
   - Sign out lives in the About sheet for now: it clears the tokens and the local store **after a confirmation**.
4. **Messages after sign-in** reads the account's real store: **empty for a new account**, with the empty state ("No chats yet" + cards **New message** and **Invite a teacher**; both show "Coming next" for now). **The sample conversations appear only in Debug builds**, behind a "Load sample chats" developer row in About.
5. **About (Debug):** "Developer: staging · Signed in as <masked email> · device registered ✓".
6. **Docs:** `docs/api-v2.md` §11 (the 2FA enforcement design, `username-resolve`, `pending_inbound`); `ios/README.md` (how to sign up on staging).

**Out of scope:** phone/SMS, Google/Apple, New message/compose and real chats (LIME-95), push, contacts, recovery key, device linking, Android, `public/` (LIME-94w handles the web).

**Phase 3: verification.**
- `./supabase/test.sh`; `cargo test` (+ integration); clippy; iOS tests on the three simulators. 0 failures; no warnings in Lime's sources.
- **New tests:**
  - sign-up → code → password → profile → device registered;
  - sign-in by email and by username;
  - **a password-only session cannot register a device**;
  - **a code-only session cannot register a device**;
  - a wrong code is limited after 5 tries;
  - forgot password;
  - sign out clears the Keychain and the store;
  - `pending_inbound` retention and retry.
- Staging: deploy, then run one sign-up end to end with a test address the user provides. Report it, and delete the test account after.
- **Secrets:** the `git grep` checks as in LIME-92/93.
- Screenshots of every onboarding screen (light and dark, 375pt).

**Gate (the user, on the iPhone via ▶ Run):**
1. **Sign up** with your email: a code arrives, you set a password, and enter your name.
2. Messages shows "No chats yet".
3. Sign out, then **sign in with your username** + password + a new code.
4. Never any Google/Apple buttons.

**Record:** a `## LIME-94` entry in `TEND.md`. Commit: `feat: native sign-up/sign-in (email or username, password + emailed code), profiles, safe pending inbound`, trailer `Brief: LIME-94`, plus the attribution trailer. **Push.** Stop for the user's check. No /loop wakeups.

---

### LIME-93 → `tend` (lime-aa) (landed as `7f411a0`): LimeCore speaks API v2: persisted keys, device registration, the first encrypted 1:1 message (core + tests)
**What it does:** teaches LimeCore the protocol from `docs/api-v2.md`, so that **two LimeCore instances, as two different accounts, exchange an Olm-encrypted message through the server**.
- This is proven by automated tests against the **local** Supabase stack, then once against **staging**.
- The iOS UI change is only a status line. The visible phone-to-phone chat is LIME-94.

**Plot's decisions for this brief:**
- **Networking lives in the platform; the protocol lives in the core.** LimeCore defines a UniFFI **callback interface** `Transport` (`request(method, path, headers, body) -> response`), which Swift implements with `URLSession` (and Kotlin later with OkHttp).
  - It keeps the binary small, and it uses iOS networking (proxies, background sessions later).
  - All protocol logic (what to call, signing, encrypting, state) stays in Rust.
- **Key persistence:** the Olm account, the sessions and the master signing key are stored **inside the SQLCipher store** (vodozemac pickles encrypted with a key derived from the store key via HKDF). They never leave the device and are never logged.
- **The master key:** an Ed25519 keypair per account, created on the first device, used to sign each device per `api-v2.md` §11 (`lime-device-v1\n…`). Multi-device linking is out of scope.
- **Scope of messaging here:**
  - **identified** 1:1 sends only (the sender is known to the server, which is what a first message is anyway, per `api-v2.md` §4);
  - Olm encryption (claim a one-time key → an outbound session);
  - fetch → decrypt → store → ack.
  - **Not here:** Megolm, sealed sends, delivery-key exchange, groups, Requests UI (LIME-94/95).
- **Finding the other person:** a minimal **`users-lookup`** Edge Function: **exact email match only**, authenticated, rate-limited, returning the user id only (no profile data). This is the smallest slice of `api-v2.md` §6 Directory.

**Capabilities assumed:** edit files, `cargo`, the Supabase CLI (logged in), the local stack via Colima, XcodeGen, `xcodebuild`, commit, push. If anything needs the user (a browser login, a password, a paid plan), **stop and ask**.

**Phase 0:** commit `PLOT.md` as on disk, unedited (`chore: update PLOT.md`, plus the attribution trailer).

**Phase 1: survey (read only):** `docs/api-v2.md` (all), `docs/architecture.md` §4, `core/` (the store, the FFI), `supabase/` (the functions, the tests), and the vodozemac pickling APIs. If anything contradicts `api-v2.md`, stop and ask the user.

**Phase 2: the change.**
1. **Core modules:** `keys` (master + device, pickled in the store), `protocol` (the signed op envelope `api-v2.md` §3 with `hlc`, `parents[]`, `sig`; canonical bytes; verification), `client` (register, upload/top-up of one-time keys, claim, identified send, fetch/decrypt/ack), and `Transport` (the callback).
   - **Auth tokens are passed in by the platform**; the core never stores passwords.
2. **The FFI additions (exactly):**
   - `LimeStore::register_device(transport, auth_token) -> DeviceInfo` (idempotent);
   - `LimeStore::send_text_identified(transport, auth_token, recipient_user_id, text) -> MessageItem`;
   - `LimeStore::sync(transport, auth_token) -> SyncReport { received: u32 }`;
   - `lookup_user_by_email(transport, auth_token, email) -> Option<String>`.

   Received messages land in the store as a DM conversation with the sender (the title = their user id for now; profiles come later).
3. **`supabase/functions/users-lookup`:** exact, case-insensitive email → user id; 404 otherwise; never lists; rate-limited (30/min per user). Tests are added to `supabase/test.sh`; deploy to staging.
4. **Tests:**
   - **Rust unit tests:** the envelope's canonical bytes and signature verification (tampered → rejected); the pickles survive a store reopen; a wrong store key can't read the pickles.
   - **The Rust integration test** (`cargo test --features integration`, against the local stack): two throwaway accounts → register both → A looks up B by email → A sends "hello from A" → B syncs and decrypts it → B replies → A decrypts it → items are acked and the mailboxes are empty. Also: **the ciphertext on the server ≠ the plaintext** (fetch the raw item with an admin client in the test only).
   - **Once against staging** with two throwaway accounts (created and deleted by the test using the CLI or admin API **without committing any secret**). Report the result.
5. **iOS (minimal):** implement `Transport` with `URLSession`. In **Debug builds only**, the About sheet gets a "Developer: staging" row that shows "Not connected" (no UI to sign in yet; LIME-94). No other UI changes.
6. **Docs:** `core/README.md` (the protocol modules, the Transport design, how to run the integration tests); `docs/api-v2.md` §11 (record the Transport decision and `users-lookup`).

**Out of scope:** Megolm, sealed sends, delivery keys, groups, Requests, profiles, push, blobs, sign-in UI, multi-device linking, recovery backup, Android, `public/`, `server/`.

**Phase 3: verification.**
- `cargo test`, `cargo test --features integration` (local) and `cargo clippy -D warnings`: all pass.
- `./supabase/test.sh` passes (with the `users-lookup` tests).
- The staging run of the integration test passes, with its accounts cleaned up.
- iOS build + test on the iPhone 18 Pro, the 13 mini (27.0) and the SE (18.3): 0 failures, no warnings; the phone build if it is connected.
- **Secrets:** `git grep` for the project ref, `sb_secret_`, the JWT prefix and the DB password → no matches outside docs describing the check. No tokens in logs (grep the test output).
- Report the app size change.

**Gate (the user):** tend's report shows the two-account encrypted exchange passing locally **and on staging**. Nothing changes on the phone yet; the visible chat between your iPhone and the simulator is LIME-94.

**Record:** a `## LIME-93` entry in `TEND.md`. Commit: `feat(core): API v2 client in LimeCore (persisted keys, registration, identified Olm send/sync) + users-lookup`, trailer `Brief: LIME-93`, plus the attribution trailer. **Push.** Stop for the user's check. No /loop wakeups.

---

### LIME-92 → `tend` (lime-aa) (landed as `a046a66`): the v2 server core on Supabase: keys, devices, mailbox
**What it does:** builds the first half of `docs/api-v2.md` on Supabase and deploys it to a **staging** project:
- the schema;
- device registration;
- the key directory;
- one-time keys;
- delivery-key access;
- the fan-out send;
- mailbox fetch/ack;
- the 30-day expiry.

It is tested on a local Supabase stack first. **The iOS app is untouched** (LIME-93 connects it).

**Plot's decisions filling `api-v2.md` §11's open items (record them in `api-v2.md` §11 as "decided in LIME-92"):**
- **Sealed access:**
  - Each user has a random 32-byte **delivery key** (shared with contacts in encrypted messages).
  - The sender presents `access_key = HKDF-SHA256(delivery_key, info="lime-access-v1")` (16 bytes) per recipient user.
  - The server stores **only SHA-256(access_key)** per user and compares in constant time. This is Signal's unidentified-access model.
  - Rotation (block) = the user uploads a new hash.
- **The one-time-key pool:** upload 50 per device; the client tops up when the server reports fewer than 20 left.
- **Rate limits (config, not constants):**
  - sends: 120 recipient-items/min per authenticated user, or per access key for sealed sends;
  - key claims: 60/min per user;
  - registration: 10/hour per user.
- **Undelivered expiry: 30 days**, via `pg_cron` (daily).

**Capabilities assumed:** edit files, Homebrew installs without sudo, run the Supabase CLI, Docker via **Colima** (open source), Deno, commit, push.
- If anything needs `sudo`, a password, or a paid plan, **stop and ask the user**.
- **Prerequisites (the user's, done before this brief):**
  - a free Supabase project **`lime-staging`** (region East US);
  - `~/.lime/staging.env` (outside the repo, `chmod 600`) holding `SUPABASE_PROJECT_REF` and `SUPABASE_DB_PASSWORD`.
- **Tend runs `supabase login`**, which opens the user's browser to approve; tell the user when to click.

**Phase 0:** commit `PLOT.md` as on disk, unedited (`chore: update PLOT.md`, plus the attribution trailer).

**Phase 1: survey (read only):**
- `docs/api-v2.md` (all) and `docs/architecture.md` §§4–5;
- the current Supabase CLI docs: local dev, migrations, Edge Functions (Deno), `pg_cron`, the secrets handling;
- the Free plan's limits. **Note:** free projects pause after inactivity; record it in the docs.

If anything contradicts `api-v2.md`, stop and ask the user.

**Phase 2: the change.** Use the Supabase CLI's standard layout, at **`supabase/`** in the repo root.
1. **Tooling:** `brew install supabase/tap/supabase deno colima docker`; `colima start`. **No Docker Desktop** (its licence terms vary).
2. **Migrations** (`supabase/migrations/`):
   - the tables of `api-v2.md` §2 needed now: `devices`, `master_keys`, `one_time_keys`, `mailbox_items`, `delivery_access` (the user id + `access_key_hash`), plus a rate-limit table;
   - **RLS on every table, denying all access to `anon` and `authenticated`.** Only the Edge Functions (service role, server-side) touch them.
   - **The staging project was created with "Automatically expose new tables" OFF and "Enable automatic RLS" ON** (the user, 2026-10-06; the Data API stays enabled). So the migrations must **explicitly `GRANT` the needed privileges to `service_role` only**, and must work identically on the local stack. A test asserts `anon`/`authenticated` have no grants.
   - **No tables for** conversations, membership, profiles' social data, blobs, backup or calls in this brief.
3. **Edge Functions** (`supabase/functions/`, TypeScript/Deno), each authenticated with a Supabase Auth JWT **except the sealed path of `send`**:
   - `devices-register`: binds `device_id` to the user; stores the identity + signing keys and the master-key signature; verifies the signature.
   - `keys-upload`: one-time keys; returns the remaining count.
   - `users-devices`: a user's devices + cross-signatures.
   - `keys-claim`: atomically claims one one-time key per device.
   - `delivery-access-set`: stores SHA-256(access_key).
   - `send`: a fan-out batch `{ ciphertext, recipients: [{ to_device, access }] }`.
     - `access` is either `{ sealed: access_key }` (no JWT required) or `{ identified: true }` (JWT required; the item is marked as identified, with the sender user id).
     - **De-dupe by SHA-256(ciphertext) per recipient device.** Enforce the size limit (64 KB per item; blobs come later) and the rate limits.
   - `mailbox-fetch`: items after a cursor for the caller's own device, oldest first, at most 100 per call.
   - `mailbox-ack`: deletes the caller's items up to a cursor.
   - **Realtime nudge:** after storing items, broadcast `{ type: "new" }` on the channel `device:<device_id>`. No content.
   - **Never log** ciphertext, keys, access keys or tokens.
4. **Expiry:** a `pg_cron` job deletes `mailbox_items` older than 30 days (daily); a test proves it.
5. **Tests** (`supabase/tests/`, Deno; one command: `./supabase/test.sh`), against the **local** stack (`supabase start`), creating throwaway users through the local admin API. They must cover:
   - register → upload keys → claim (a key is claimed only once; the count drops);
   - a sealed send with the right `access_key` succeeds **with no JWT**, and with a wrong one fails (`403`); an identified send records the sender;
   - fan-out to 3 devices → each fetches only its own items;
   - ack deletes;
   - **the de-dupe:** sending the same ciphertext twice → one item;
   - the size limit; a rate limit trips;
   - RLS: `anon` and `authenticated` clients can't select any table directly;
   - expiry deletes a back-dated item;
   - a revoked device can't fetch.
6. **Staging deploy** (`./supabase/deploy-staging.sh`): it reads `~/.lime/staging.env`, links, pushes migrations, deploys functions and sets function secrets. **Never echo secrets.**
   - The **anon (publishable) key and URL** go into a gitignored `supabase/.staging.public.env` for the later iOS brief.
   - **The service-role key never leaves Supabase.**
7. **Docs:** `supabase/README.md` (what's here, the prerequisites, `test.sh`, `deploy-staging.sh`, the free-plan pause note). `docs/api-v2.md` §11: mark the four items as decided, with the values above.

**Out of scope:** the iOS app, `core/`, directory/profiles, blobs, backup, push/APNs, calls/TURN/LiveKit, production, `public/`, `server/` (v1 stays as it is), `tests/`.

**Phase 3: verification.**
- `./supabase/test.sh`: all pass; report the count.
- `./supabase/deploy-staging.sh` succeeds. Then a **smoke test against staging:** two throwaway users, one sealed send, one fetch, one ack. Then delete the throwaway users.
- `git status`: no secrets, no `.env` files with values, no `~/.lime` content, no Colima/Docker state tracked. Run `git grep` for the project ref, the password and `service_role` → no matches.
- Report the tool versions, the Supabase plan limits noted, and anything that needed the user (the browser login).

**Gate (the user):** in the Supabase dashboard, **Table Editor** shows the new tables (empty after the smoke test). Tend's report shows the staging smoke test passing. No secrets on GitHub.

**Record:** a `## LIME-92` entry in `TEND.md`. Commit: `feat(server): API v2 core on Supabase (keys, devices, sealed mailbox, 30-day expiry) with local tests and staging deploy`, trailer `Brief: LIME-92`, plus the attribution trailer. **Push.** Stop for the user's check. No /loop wakeups.

---

### LIME-91 → `tend` (lime-aa) (landed as `9f74780`): DESIGN-02 into `docs/api-v2.md` (docs only)
**What it does:** writes the decided API v2 (the blind-mailbox protocol) into the repo, so the Supabase and core briefs work from one document.

**Capabilities assumed:** edit files, commit, push.

**Phase 0:** commit `PLOT.md` as on disk, unedited (`chore: update PLOT.md`, plus the attribution trailer).

**Phase 1: survey (read only):**
- In `PLOT.md`, the "DESIGN-02" section: §§1–7, **R1 = 30 days**. Ignore the "(History)" R1 lines except as context.
- `docs/architecture.md` (especially §§4–7 and §11.5);
- `docs/api.md` §§2–8 (v1's envelope, idempotency and auth, for the "changes from v1" notes).

**If anything in DESIGN-02 conflicts with `architecture.md`, stop and ask the user. Don't resolve it yourself.**

**Phase 2: the change.**
1. **Create `docs/api-v2.md`, "Lime API v2: the blind mailbox"**, with exactly these sections:
   1. Status and scope: decided 2026-10-06; the native apps only; v1 is frozen for the web;
   2. What the server stores, and never stores (DESIGN-02 §1, with **30-day expiry** for undelivered items);
   3. Envelopes (outer, sealed inner, the signed op; fan-out; Megolm key distribution) (§2);
   4. Sealed sender, delivery keys, message requests and blocking (§3);
   5. Ordering: the per-mailbox cursor; HLC + `parents[]`; the display time (§4). **Mark it as the answer to `architecture.md` §11 item 5**;
   6. Group state ops, authority and conflict rules (§5);
   7. Endpoints: the **shape only**, request and response fields at the level DESIGN-02 gives, no full JSON schemas (§6);
   8. The mesh relay and de-duplication (§7);
   9. Honest limits: what the server can still infer (recipient sets, timing, sizes, IP, the directory, the key directory);
   10. Changes from v1 (a short table);
   11. Open items for the Supabase briefs: Realtime/Edge Function limits; the delivery-key HMAC construction details; the one-time-key pool size; the rate-limit numbers.

   Copy decisions faithfully; **add no new decisions**. Where DESIGN-02 is silent, list the point under §11 rather than filling it in.
2. **`docs/architecture.md`:**
   - §11 item 5: append "Answered in `docs/api-v2.md` §5 (2026-10-06)".
   - §6: add a one-line pointer to `docs/api-v2.md`.
3. **`README.md`:** add a link line beside the architecture link.

**Amendment (plot, 2026-10-06, after tend raised two conflicts):** DESIGN-02 deliberately refines `architecture.md` in two places:
- a stranger's first message is sent **identified** (the D7 message requests);
- **the server de-dupes by a hash of the outer ciphertext**, not by `op_id`.

**Correct `architecture.md` §5 and §6/§7 to match DESIGN-02** (a few lines). This is the user's choice "option 1".

**Out of scope:** code, `ios/`, `core/`, `public/`, `server/`, `tests/`, schema SQL.

**Verification:**
- `git diff --stat` touches only `docs/api-v2.md`, `docs/architecture.md`, `README.md` and `TEND.md` (plus `PLOT.md` from Phase 0);
- `docs/api-v2.md` has the 11 numbered sections;
- it contains "30 days", "delivery key", "HLC", "parents" and "sealed";
- it contains **no** statement that the server stores conversations, membership, group names or senders of sealed messages;
- no personal data.

**Gate:** the user skims `docs/api-v2.md` on GitHub.

**Record:** a `## LIME-91` entry in `TEND.md`. Commit: `docs: API v2, the blind mailbox protocol`, trailer `Brief: LIME-91`, plus the attribution trailer. **Push.** Stop for the user's check. No /loop wakeups.

---

### LIME-90-fix → `tend` (lime-aa) (landed as `9d18cad`): a lost-key and backup-restore path for the local store; a debug-only reset flag
**What it does:** closes the gap tend flagged in LIME-90 ("if the Keychain key is lost while the DB file survives, the store can't open").
- **The likely real-world trigger:** restoring a new iPhone from an iCloud backup. The DB file in Application Support is backed up, but the Keychain key is `ThisDeviceOnly`, so it is not.
- **Plot's decision (consistent with D5):** the local DB is **never backed up**. History comes back through Lime's own recovery-key backup and device linking (later briefs), not through iCloud.
- Also gates LIME-90's `-lime-reset-store` flag to Debug builds.

**Capabilities assumed:** edit files, XcodeGen, `xcodebuild`, commit, push.

**Phase 0:** commit `PLOT.md` as on disk, unedited (`chore: update PLOT.md`, plus the attribution trailer).

**Phase 1: survey (read only):** the iOS store bootstrap (`LimeApp.swift`, the store wrapper), where the DB path is created, and how the open errors surface. If anything contradicts this brief, stop and ask the user.

**Phase 2: the change.**
1. **Exclude the DB from backups:** set `isExcludedFromBackup` on the database file (and any `-wal`/`-shm` siblings or its containing folder) every launch, since the attribute can be lost when files are replaced.
2. **The unopenable-store path:** if the Keychain key is missing **or** the store fails to open with the key (wrong key or corrupted):
   - **move the old file aside** (rename it to `lime-<ISO timestamp>.unreadable.db` in the same folder; keep at most the 2 newest, delete older ones);
   - generate a new key, create a fresh store, seed it (sample data, for now);
   - show a one-time, non-blocking notice on Messages: **"Lime couldn't open the data saved on this phone, so it started fresh. Your chats will come back when you restore from your recovery key."** (for now there is no restore; the wording stands for the later feature);
   - **never log the key**, and log no plaintext.
   - **A missing key with no DB** (a first launch) is not an error: no notice.
3. **`-lime-reset-store`** works only in Debug builds (`#if DEBUG`); Release ignores it.
5. **Silence Xcode's "Update to recommended settings" warning at the source:** set Xcode 27's recommended project settings in `project.yml` (the dialog offered *Enable String Catalog Symbol Generation*; apply whatever `xcodebuild` / Xcode lists as recommended for this project). There must be no behaviour change, and the warning must be gone after `./generate.sh`. If a recommended setting would change behaviour, leave it off and say which. (The user was told not to click the dialog, because `./generate.sh` would overwrite it.)
4. **Pre-release checklist note:** add `docs/release-checklist.md` with two items: the acknowledgements screen (the Zetetic/SQLCipher notice, plus `core/THIRD_PARTY.md`), and a lawyer's glance at UniFFI's MPL-2.0 use. Keep it short; later briefs append to it.

**Out of scope:** the recovery-key backup itself; anything outside `ios/`, `core/` (only if a small error-type change is needed), `docs/release-checklist.md` and `TEND.md`.

**Phase 3: verification.**
- Build + test on the iPhone 18 Pro, the 13 mini (iOS 27.0) and the SE (18.3): 0 failures, no warnings.
- **New tests:**
  - the DB file reports `isExcludedFromBackup == true` after launch;
  - **wrong-key simulation:** replace the Keychain key with random bytes (a test hook, Debug only), relaunch → the old file is moved aside, a fresh store opens, the notice shows once and doesn't show on the next launch;
  - a missing key with an existing DB → the same path;
  - a first launch (no key, no DB) → no notice;
  - in Release configuration, `-lime-reset-store` has no effect (a unit test of the gating function).
- If the iPhone is connected, build for it and report.

**Gate (the user, on the iPhone):** nothing visible changes in normal use. Sending, closing and reopening still keeps your messages. (The lost-key path is proven by the tests.)

**Record:** a `## LIME-90-fix` entry in `TEND.md`. Commit: `fix(ios): keep the local store out of backups; recover from an unopenable store; debug-only reset`, trailer `Brief: LIME-90-fix`, plus the attribution trailer. **Push.** Stop for the user's check. No /loop wakeups.

---

### LIME-90 → `tend` (lime-aa) (landed as `2fcf708`): the encrypted local store in LimeCore; the iOS screens read from it
**What it does:** gives LimeCore its on-device database, **SQLite encrypted at rest with SQLCipher**, and moves the iOS app off `SampleData.swift` onto the core.
- Messages you send **persist across app restarts**.
- Still **no networking and no persisted Olm keys** (those come with the backend brief).
- Follows `docs/architecture.md` §3 (Components) and §4.

**Capabilities assumed:** edit files, `cargo`, XcodeGen, `xcodebuild`, commit, push.

**Phase 0:** commit `PLOT.md` as on disk, unedited (`chore: update PLOT.md`, plus the attribution trailer).

**Phase 1: survey (read only):**
- `core/` (lib layout, UniFFI setup), `ios/Lime/Model/` and the views using `SampleData`;
- `docs/architecture.md` §§3–5;
- the rusqlite SQLCipher options for iOS: **prefer a build that uses Apple's CommonCrypto** over vendoring OpenSSL. Report the choice, the licence (SQLCipher Community is BSD-style) and the size impact.

If anything contradicts this brief, or a dependency is GPL/AGPL, **stop and ask the user**.

**Phase 2: the change.**
1. **The core store** (`core/src/store/`):
   - opened with `(path, key: 32 bytes)`; SQLCipher with that raw key; schema versioned with `PRAGMA user_version` and forward-only migrations.
   - **Tables, the local view only:** `people`, `conversations` (DM or group, title, pinned), `members`, `messages` (id = a UUIDv7 made by the core, conversation, sender, body text, the display time, `local_state` = `sent_local` for now).
   - Leave clearly marked placeholders in a comment (not columns) for the v2 fields that come later (signature, HLC, parents), so nothing pre-bakes the API v2 design.
2. **The FFI surface** (a UniFFI object `LimeStore`, thread-safe; nothing else is exported beyond LIME-89's two functions):
   - `LimeStore::open(path: String, key: Vec<u8>) -> Result<LimeStore, StoreError>`
   - `seed_sample_data_if_empty()`: inserts **the same made-up people, conversations and messages as `SampleData.swift`** (move that content into Rust; no personal data);
   - `list_conversations() -> Vec<ConversationSummary>` (with the last message, unread count, pinned, member initials and colours as today);
   - `list_messages(conversation_id) -> Vec<MessageItem>`;
   - `send_local_message(conversation_id, text) -> MessageItem`;
   - `StoreError` is a small enum. **No key material in any error or log.**
3. **The iOS key and the file:**
   - On first launch, Swift generates a 32-byte random key and stores it in the **Keychain** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, which a later background mesh relay needs; this-device-only, so it never goes to iCloud backup).
   - The DB lives in Application Support with file protection `completeUntilFirstUserAuthentication`.
   - All store calls run off the main thread; the UI updates on the main actor.
4. **The iOS screens read from the core:**
   - Messages and Chat use `LimeStore`; sending writes through `send_local_message`.
   - Delete `SampleData.swift` (or reduce it to previews only).
   - The look is unchanged.
5. **The About sheet** gains the line **"Storage: encrypted ✓"**. It is shown when the store opened with a key and the core's own check passes: a reopen with a wrong key fails.

**Out of scope:** networking, Olm/Megolm key persistence, search/FTS, attachments, Android, anything outside `core/`, `ios/`, `.gitignore` and `TEND.md`.

**Phase 3: verification.**
- `cargo test`:
  - open/seed/list/send round-trip;
  - **reopening with the wrong key fails**;
  - the DB file contains no plaintext sample strings (scan its bytes for a known message);
  - migrations from an empty DB.

  `cargo clippy -D warnings` is clean.
- iOS build + test on the iPhone 18 Pro, the 13 mini (iOS 27.0) and the SE (iOS 18.3): 0 failures, no warnings in Lime's sources.
- **A UI test:** send "persist me", terminate the app, relaunch, and the message is still in the chat.
- Report the size change and any CommonCrypto vs OpenSSL details.
- If the iPhone is connected, build for it and report.
- `git status`: no DB files, binaries or generated code tracked.

**Gate (the user, on the iPhone via ▶ Run):**
- send a message, **swipe the app away, reopen it**, and the message is still there;
- the About sheet shows "Encryption self-test: passed ✓" and "Storage: encrypted ✓".

**Record:** a `## LIME-90` entry in `TEND.md`. Commit: `feat(core): SQLCipher-encrypted local store; iOS reads and writes through LimeCore`, trailer `Brief: LIME-90`, plus the attribution trailer. **Push.** Stop for the user's check. No /loop wakeups.

---

### LIME-89 → `tend` (lime-aa) (landed as `fa8fd3c`): the shared Rust core skeleton (LimeCore + vodozemac, linked into iOS)
**What it does:** starts DESIGN-01's shared core (`docs/architecture.md` once LIME-88 lands): a Rust library **LimeCore** that wraps **vodozemac**, exposed to Swift with **UniFFI** and linked into the iOS app. It proves the whole toolchain end to end with a real encryption round-trip. **No networking, no storage, no persisted keys yet.**

**Capabilities assumed:** edit files, install developer tools via Homebrew/rustup (user-level, no sudo), `cargo`, XcodeGen, `xcodebuild`, commit, push. If any install needs `sudo` or a password, **stop and ask the user**.

**Phase 0:** commit `PLOT.md` as on disk, unedited (`chore: update PLOT.md`, plus the attribution trailer).

**Phase 1: survey (read only):**
- `docs/architecture.md` (Components; Identity, devices and keys; What is encrypted);
- `ios/project.yml` (note `ENABLE_USER_SCRIPT_SANDBOXING: YES` and Swift 6 strict concurrency);
- `ios/generate.sh`;
- the current vodozemac and UniFFI versions on crates.io, with their licences (vodozemac Apache-2.0; UniFFI MPL-2.0, used as a build tool and runtime: confirm it is compatible with an MIT app and record it).

If anything contradicts this brief, stop and ask the user.

**Phase 2: the change.**
1. **Toolchain:**
   - `brew install rustup`, then `rustup-init -y` (or `rustup default stable` if rustup is already set up);
   - `rustup target add aarch64-apple-ios aarch64-apple-ios-sim`;
   - pin the toolchain in `core/rust-toolchain.toml`.
2. **The crate `core/`** (crate name `lime_core`, `crate-type = ["staticlib", "lib"]`), UniFFI in **proc-macro** mode. Its **public FFI surface is exactly:**
   - `core_version() -> String` (the crate version);
   - `encryption_self_test() -> SelfTestReport`, where `SelfTestReport { olm_ok: bool, megolm_ok: bool, detail: String }`.
     - It creates **two in-memory Olm accounts**, establishes an Olm session and round-trips a message both ways (`olm_ok`).
     - Then it creates a Megolm outbound group session, shares its key into an inbound session and round-trips a message (`megolm_ok`).
     - `detail` is a short human-readable line with **no key material**.
   - Nothing else is exported. Internal modules may be laid out freely, but **no secret material crosses the FFI or is logged**.
3. **Rust tests** (`cargo test`): the Olm round-trip, the Megolm round-trip, a tampered ciphertext failing to decrypt, and `encryption_self_test()` returning both ok.
4. **The iOS build glue (no Xcode build-phase scripts, because of the sandboxing):**
   - `core/build-ios.sh` builds the static lib for both targets in release, makes `ios/Frameworks/LimeCoreFFI.xcframework`, and generates the Swift bindings into `ios/Lime/Core/Generated/`.
   - `ios/generate.sh` runs it first (it fails with a clear message if Rust is missing).
   - The **xcframework and the generated Swift are gitignored** (rebuilt from source).
   - `project.yml` links the xcframework and compiles the generated sources. Warnings inside generated code are acceptable; Lime's own sources stay warning-free under Swift 6.
5. **App surface (tiny):** **long-press the logo button** on Messages opens an "About Lime" sheet showing "Lime 0.1.0 · Core x.y.z", plus "Encryption self-test: passed ✓" (or "failed" with the detail line), run off the main thread. No other UI changes.
6. **Licences:** `core/THIRD_PARTY.md` lists vodozemac, UniFFI and their licences (and any notable transitive crates with non-permissive licences; if one is GPL/AGPL, **stop and ask**).
7. **Docs:** `core/README.md` (what LimeCore is, the prerequisites, `cargo test`, `build-ios.sh`); `ios/README.md` notes that `./generate.sh` now needs Rust.

**Out of scope:** networking, storage/SQLCipher, persisted keys, the Keychain, Android/Kotlin bindings, `public/`, `server/`, `tests/`.

**Phase 3: verification.**
- `cd core && cargo test` (all pass) and `cargo clippy -- -D warnings` (clean).
- `cd ios && ./generate.sh`, then build + test on the iPhone 18 Pro and the iPhone 13 mini (iOS 27.0) and the SE (iOS 18.3): 0 failures; no warnings in Lime's own sources.
- **A new unit test** calls `encryption_self_test()` through the Swift bindings and asserts both ok.
- **A UI test:** long-press the logo, and the About sheet shows "passed".
- Report the **app size change** (the Release .app size before and after) and the cold `./generate.sh` time.
- If the iPhone is connected, build for it and report the result.
- `git status`: only `core/`, `ios/`, `.gitignore`, `README.md` (if touched) and `TEND.md` changed; **no generated or binary artefacts tracked**.

**Gate (the user, on the iPhone via ▶ Run):** long-press the Lime logo, and the About sheet says **"Encryption self-test: passed ✓"**. That is real vodozemac encryption running on your phone.

**Record:** a `## LIME-89` entry in `TEND.md` (the versions, the licences, the size change). Commit: `feat(core): LimeCore Rust skeleton with vodozemac, UniFFI-linked into iOS`, trailer `Brief: LIME-89`, plus the attribution trailer. **Push.** Stop for the user's check. No /loop wakeups.

---

### LIME-87-fix5 → `tend` (lime-aa) (landed as `630c79e`): a slightly dimmer dark bubble; revert the stacked chat title
**What it does:** the user reviewed LIME-87-fix4 on the phone:
- "I like the green in light more, and agree in dark mode it can be slightly dimmer";
- "I like the previous title treatment better, so we should go back even if it's truncated".

**Plot's reading:** light mode stays as it is; only the dark own bubble (and its matching send arrow) gets slightly dimmer. If the user meant something else, they'll say so at the gate.

**Capabilities assumed:** edit files, XcodeGen, `xcodebuild`, commit, push.

**Phase 0:** commit `PLOT.md` as on disk, unedited (`chore: update PLOT.md`, plus the attribution trailer).

**Phase 1: survey (read only):** the dark own-bubble and send tokens from fix4; the title code before fix4 (`git show 6131d50:` the Chat files) and after it. If anything contradicts this brief, stop and ask the user.

**Phase 2: the change.**
1. **The dark own bubble + send arrow, slightly dimmer:**
   - Use a new dark-only token for them: the same green family as `#a3e18a`, about **6–8% lower OKLCH lightness**, same hue, similar chroma. **Start from `#8fd473`** (the "deeper" swatch the user saw) unless it fails the checks below.
   - The ink on it ≥ 4.5:1.
   - **The badges and the Messages "+" stay `#a3e18a`** in both modes (small areas; no glare).
   - **Light mode is fully unchanged.**
   - Tests: the dark own bubble = the new value, ink ≥ 4.5:1, and the dark own bubble ≠ the accent; light unchanged; the accent unchanged.
   - README Theme table updated.
2. **Revert the chat title to the LIME-87-fix3 treatment** on both the iOS 26+ and the iOS 17–25 paths: the avatar (or stack) **beside** the name, with "N members" under the name for groups, exactly as in `6131d50`. Truncation is acceptable (the user's words).
   - Remove the fix4 narrow-width title logic and its full-name UI test (or change it to assert the side-by-side layout).
   - Keep the 375pt simulators in the test matrix.

**Out of scope:** light-mode colours, the accent, anything outside `ios/`.

**Phase 3: verification.**
- Build + test on the iPhone 18 Pro and the iPhone 13 mini (iOS 27.0), plus the SE (iOS 18.3): 0 failures, no warnings.
- Screenshots: a dark DM with own bubbles and the send arrow; a light DM (unchanged); a group chat header at 375pt showing the side-by-side title.
- If the iPhone is connected, build for it and report.

**Gate (the user, on the iPhone):**
- in dark mode, your bubbles are a slightly calmer green;
- light mode is the same as now;
- the chat title is back to the avatar-beside-name style.

**Record:** a `## LIME-87-fix5` entry in `TEND.md`. Commit: `fix(ios): dimmer dark own bubble; restore side-by-side chat title`, trailer `Brief: LIME-87-fix5`, plus the attribution trailer. **Push.** Stop for the user's check. No /loop wakeups.

---

### LIME-88 → `tend` (lime-aa) (after LIME-87-fix5 is reviewed): DESIGN-01 into `docs/` (docs only)
**What it does:** writes the decided native architecture into the repo, so every later brief and agent works from one document instead of `PLOT.md`.

**Capabilities assumed:** edit files, commit, push. No builds needed.

**Phase 0:** commit `PLOT.md` exactly as on disk, unedited (`chore: update PLOT.md`, plus the attribution trailer).

**Phase 1: survey (read only):**
- In `PLOT.md`: the "DESIGN-01" section (§§1–7 and the decisions D5–D8, **including the D8 = B changes**), the "Open thread: voice and video calls" section (with its decisions), and the "Open thread: the road to the iPhone app" section (the decisions D1–D4, vodozemac, audience = teachers, nonprofit context).
- In `docs/api.md`: §§1, 2, 8, 9 and 12.

If anything in them conflicts, **stop and ask the user**; don't resolve it yourself.

**Phase 2: the change.**
1. **Create `docs/architecture.md`, "Lime native architecture (v2)"**, with exactly these sections:
   1. Purpose and status: decided 2026-10-05; the web app and API v1 are frozen as reference;
   2. Decisions (a table: id, decision, why), covering D1–D8, the vodozemac + MIT licence note (the licence is still open), audience = teachers, full E2EE with no organisation key, offline open and closed, and calls (LiveKit self-hosted, 50–100, no recording);
   3. Components;
   4. Identity, devices and keys (including the D5 recovery-key backup and QR device linking);
   5. What is encrypted, and what the server can still see: **written for the blind mailbox (D8 = B)**: sealed sender, client-managed encrypted group state, per-device mailboxes. The server sees recipient devices, timing, sizes and IP addresses only;
   6. API v2 deltas from v1 (the signed envelope `sig`, encrypted payloads, group-state ops, mailbox delivery). Describe the shape; **don't write endpoint specs** (that's a later brief);
   7. Offline mesh (D6 = A);
   8. Discovery and safety (D7 = A, message requests, block, report, "hide me from search", 18+);
   9. Calls (**1:1 = peer-to-peer WebRTC + TURN; group = self-hosted LiveKit**);
   10. Build order (DESIGN-01 §7 **as amended by the user on 2026-10-05: mesh v1 before TestFlight**; see "Open thread: market and bootstrapping"), plus a short "Cost principles" note from that thread;
   11. Open questions: the licence; the Bluetooth spike's results; metadata hiding beyond the mailbox (zkgroup-style), revisited later; the web/desktop client's E2EE (vodozemac WASM), later.

   Plain, precise prose. **Copy decisions faithfully; add no new decisions.**
2. **`docs/api.md`:**
   - A note at the top of §9 and §12: "Superseded for the native apps by `docs/architecture.md` (2026-10-05); kept as v1 reference."
   - In §9's open questions, mark Q1 (op signing) and Q2 (E2EE) as **answered in architecture.md**.
3. **`README.md`:** one line under the iOS pointer linking `docs/architecture.md`.

**Out of scope:** any code, `ios/`, `public/`, `server/`, `tests/`, schema changes.

**Verification:**
- `git diff --stat` touches only `docs/architecture.md`, `docs/api.md`, `README.md` and `TEND.md`;
- `docs/architecture.md` has the 11 numbered sections;
- it contains "sealed sender", "recovery key", "LiveKit" and "vodozemac";
- it contains **no** wording that says the server enforces membership or reads group names;
- it contains no personal data.

**Gate:** the user skims `docs/architecture.md` on GitHub and confirms it matches what we decided.

**Record:** a `## LIME-88` entry in `TEND.md`. Commit: `docs: native architecture v2 (E2EE, mailbox server, mesh, discovery, calls)`, trailer `Brief: LIME-88`, plus the attribution trailer. **Push.** Stop for the user's check. No /loop wakeups.

---

### LIME-87 → `tend` (lime-aa) (next; needs Xcode installed first): the native iOS app skeleton
**What it does:** adds `ios/`, a SwiftUI iPhone app called Lime that builds and runs in the iOS Simulator. It shows a static Messages list, a chat screen and the dock, styled from Lime's tokens. There is no networking, no accounts and no encryption yet. It is the foundation every later iOS brief builds on.

**Decisions this brief carries (the user, 2026-10-05, "all A"):**
- **D1** minimum **iOS 17**: real Liquid Glass (`glassEffect`) on iOS 26 behind `if #available(iOS 26, *)`, `.ultraThinMaterial` below it;
- **D2** a shared Rust core *later* (not in this brief);
- **D3** **one repository**: the app lives in `ios/` at the repo root, beside the frozen web app;
- **D4** a Supabase backend *later*.

**Placeholder the user confirms at the gate:** the bundle identifier **`com.famkind.lime`**. It is free to change until it is registered with Apple next month, and permanent after that.

**Capabilities assumed:** edit files, run shell commands including `brew`, `xcodebuild` and `xcrun simctl`, commit and push. **Prerequisites (the user's, before tend starts):**
1. Xcode fully installed. On 2026-10-05 `/Applications` only held an unfinished `Xcode.appdownload`.
2. Xcode opened once, with the licence accepted and the iOS platform/simulator installed.
3. `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

**If `xcodebuild -version` fails, or no iOS Simulator runtime exists, stop and tell the user what's missing. Don't work around it.**

**Phase 0: save plot's state.** Commit `PLOT.md` exactly as on disk, unedited: `chore: update PLOT.md`, plus the attribution trailer. Leave `public/assets/Logomark-outline.svg` and `public/assets/signin-teachers.mp4` untracked.

**Phase 1: survey (read only).** Read:
- `docs/design/mobile/01-messages.png` and `02-chat.png`;
- the token section of `public/css/lime.css`: the canvas tones, `--lime-primary-bg`/`-ink`, the neutral bubble, radii, the fonts in use and the dock icons;
- `public/assets/` for the logo.

List the available simulators (`xcrun simctl list devices available`). If anything here contradicts the brief, or you spot related issues, stop and ask the user.

**Phase 2: the change.**
1. **Tooling:**
   - Install **XcodeGen** (`brew install xcodegen`).
   - The project is defined in **`ios/project.yml`**. The generated `ios/Lime.xcodeproj` is **gitignored**, and **`ios/generate.sh`** regenerates it.
   - One app target `Lime` (Swift 6 language mode, iOS 17.0, iPhone only, portrait and landscape), one unit-test target `LimeTests`, and one UI-test target `LimeUITests`.
2. **Structure** (exactly these folders under `ios/Lime/`):
   - `App/` (the `@main` app, the root view);
   - `Theme/` (colours, typography, the glass modifier);
   - `Features/Messages/`, `Features/Chat/`, `Features/Dock/`;
   - `Model/` (plain Swift structs `Conversation`, `Message`, `Person`, plus `SampleData.swift`);
   - `Resources/` (the asset catalog: AppIcon from the lime logo, the logo image, and colour sets).
3. **Theme:**
   - Port the **default light tone and dark** from `lime.css` into colour sets plus a `Theme` type: the canvas, the surface, the neutral bubble (brighter than the canvas, as in LIME-86-fix), the own bubble = `lime-primary-bg` with `lime-primary-ink`, text and secondary text.
   - One `limeGlass()` view modifier: `glassEffect` on iOS 26+, `.ultraThinMaterial` plus a hairline below that.
   - The app follows the system light/dark setting.
   - Use the system font (SF) for now; note the web font in a code comment for a later decision.
4. **Screens (static, matching 01 and 02 in layout, not pixel-perfect):**
   - **Messages:** the floating glass logo button at the top left; a glass pill at the top right with search and the avatar; a list of 5 sample conversations (DMs and groups, initials avatars, last message, time, a pinned glyph on one); a round "+" button; and the **dock** (link, jam, call) as a floating glass bar. The list scrolls under the top controls.
   - **Chat:** pushed from a row with a `NavigationStack`. A glass back button, a title pill (avatar and name, "N members" for groups), and glass search/call/"⋯" (they do nothing yet). Sample messages with others' bubbles on the left and own bubbles on the right; date separators; and a glass composer pill ("+", "Send message…", mic).
   - Typing and tapping send appends an own bubble **in memory only**. Return makes a new line; the send button is an up arrow and only appears with text.
   - **Search, call, "⋯", "+", jam and call:** no-ops, or a small "Coming soon" banner. No other screens.
5. **Sample data:** made-up teachers and groups only. **No real names, emails or phone numbers** (the seed's public demo names are fine).
6. **Accessibility:** every button has an accessibility label, and Dynamic Type grows the list and the bubbles without clipping.
7. **Docs:**
   - `ios/README.md`: what this is, the prerequisites, `./generate.sh`, how to open it in Xcode and run it in the Simulator, and how to run the tests.
   - A short "iOS app" pointer in the root `README.md`.
   - Add the Xcode/XcodeGen ignores to `.gitignore` (`ios/Lime.xcodeproj`, `DerivedData`, `xcuserdata`, `*.xcresult`).

**Out of scope:**
- any networking, Supabase, auth, Rust, vodozemac, Bluetooth or push;
- Android;
- any change to `public/`, `server/` or `tests/` (the web app is frozen);
- signing for a real device.

**Phase 3: verification.**
- `cd ios && ./generate.sh && xcodebuild -scheme Lime -destination 'platform=iOS Simulator,name=<an available iPhone>' build` → **BUILD SUCCEEDED, zero warnings in Lime sources**.
- `xcodebuild test` (same destination) → the unit and UI tests pass:
  - **unit tests:** `SampleData` is non-empty; every conversation has a name and at least one message; the theme's own bubble equals the primary colour; text on both bubbles is **≥ 4.5:1** in light and dark;
  - **UI tests:** the app launches into Messages; tap the first row → the chat appears; type "hello" and tap send → a new own bubble with "hello" appears; back → Messages.
- If an **iOS 17 simulator runtime** is installed, also build and run the tests there. If not, say so (don't install one unasked).
- Screenshots via `xcrun simctl io booted screenshot` (Messages and Chat, light and dark) into the scratchpad. Report their paths.
- `git status` shows only `ios/`, `README.md`, `.gitignore` and `TEND.md` changed. **No `public/`, `server/` or `tests/` changes.**
- Report the simulator model and iOS version used, and the test count.

**Gate (the user):** tend leaves the app running in the Simulator on the Mac.
- It opens to a Messages list that looks like Lime, with glass controls and the dock.
- Tapping a chat opens it; you can type, a new line works, and send adds your green bubble.
- It switches correctly between light and dark (Settings → Developer → Dark Appearance, or the Simulator's Features menu).
- Confirm or change the bundle id `com.famkind.lime`.

**Record:** add a `## LIME-87` entry to `TEND.md` (what landed, the simulator used, the test count, the screenshot paths, anything skipped). Commit: `feat(ios): native SwiftUI app skeleton (Messages, Chat, dock; static data)`, trailer `Brief: LIME-87`, plus the attribution trailer. **Push.** Stop for the user's review. No /loop wakeups.

---

### LIME-86-fix → `tend` (landed as `8ba1989`, pushed): close out mobile QA round 3; the last web-phone polish before the native direction
**What it does:** fixes the user's 14 QA notes on `c9712c9` (iPhone screenshots, 2026-10-05). Then this round is closed, saved to git, and the web phone layout goes into maintenance (real bugs only) while plot designs the native apps.

**Capabilities assumed:** edit files, run the `tests/` suites (Chrome and Firefox), commit and push. No iPhone; the user checks on the phone at the gate.

**Phase 0: save plot's state first.** Commit `PLOT.md` exactly as it is on disk, **without editing it**: `chore: update PLOT.md`, plus the attribution trailer. (It holds the new native/E2EE direction.) Leave `public/assets/Logomark-outline.svg` and `public/assets/signin-teachers.mp4` untracked.

**Phase 1: survey (read only).** Find the code for:
- the Messages screen header (logo, search and avatar pill) and the chat header's fade;
- the bubble tokens in each tone, light and dark;
- the header pill icons;
- the "⋯" menu's reason text;
- the avatar-stack ring;
- the thread view's composer and keyboard handling (`--vv-top`, `visualViewport`);
- the composer's link popover (`openLinkPopover`, `public/js/app.js` ~988: it is placed at `rect.bottom + 8`, i.e. *below* the toolbar, so on a phone it lands under the keyboard or off-screen; that is the likely cause of item 8);
- the Enter handler (~1277: plain Enter sends);
- the Aa / list / align menus;
- `syncSelecting` (~1210, the LIME-86 selection toolbar);
- the reaction row;
- the code-block (`pre`) handling in the composer, the sanitiser and message rendering.

If the survey turns up anything that contradicts this brief, or related bugs, **stop and ask the user** before going on.

**Phase 2: the changes.** These apply on phones (≤ 767px and touch landscape) unless stated. **Desktop must stay pixel-identical** in the committed 1280×800 baseline (chat, composer with text, thread). The exceptions are items 8 and 14, which fix shared composer logic and may change desktop *behaviour*, never its look in those three states.

1. **Logo:** the Messages header's lime logo is slightly larger inside its round button, about 15% (the glyph, not the button), in light and dark.
2. **Messages-screen fade:** the list scrolls *under* a soft fade behind the logo, search and avatar pill, exactly like the chat header's fade (same mechanism, same height, coloured by the canvas tone). No hard cut on a row's title, which screenshot 1 shows.
3. **Other people's bubbles are brighter, like Apple Messages, in every tone:**
   - **light:** a surface clearly lighter than the canvas (towards white);
   - **dark:** a lifted surface clearly lighter than the canvas.

   Derive them from the tone's canvas (keep the appearance system's method; no fixed hex). Text on them meets **4.5:1**. In the suite, assert for all 8 tones plus dark that the bubble is lighter than the canvas and that the OKLab distance from the canvas is **≥ 6**. Don't touch the own bubble.
4. **Header icons are smaller, with breathing room inside the glass pills,** following Apple's toolbar convention: about a **20px glyph** in each **44px** hit target.
   - This covers search, call, "⋯", the Messages search, and the back chevron to match.
   - The pills keep their height; the icons sit centred with even space around them; one stroke weight throughout.
   - Update the LIME-86 icon-size checks to the new values.
5. **Menu reason text contrast:** the grey explanation lines in the "⋯" menu ("Only the group owner can rename", "…can delete.") meet **WCAG AA 4.5:1** against the menu's background in every tone, light and dark. Measure it in the suite for every tone. The disabled item's *label* may stay dimmed, but the reason must be readable.
6. **Avatar-stack ring = the surface behind it:**
   - the canvas in the list;
   - the row's highlight colour when a row is pressed or selected;
   - the header pill's colour in the chat header;
   - correct in light and dark (screenshot 1 shows black rings in dark).

   Use one variable that each context sets.
7. **The thread with the keyboard open:**
   - The reply composer and its whole toolbar sit **fully above the keyboard** (screenshot 6: the toolbar is hidden under it), and the Thread header stays pinned.
   - **All composer menus** (emoji, Aa, list, align, link, selection pill) open **inside the visible viewport** (`visualViewport`), above the composer and *below the header layer's bottom edge*. If there isn't room they scroll internally; they are never clipped by the header or the screen (screenshot 10: Align is cut off at both ends).
   - The same applies in the main chat.
8. **The link tool works on a phone.** Tapping link opens the link popover **above the composer, within the visible viewport**, with:
   - a URL field (and a "Text" field when nothing is selected);
   - "Add";
   - when the caret is in a link: "Edit" and "Remove link".

   Enter in the URL field adds it. It works with the keyboard open. (Fix the placement for desktop too; it must not change the desktop baseline states.)
9. **Return makes a new line on phones.**
   - On phones, Enter **never sends**: it inserts a line break (a new item in lists, a new line in code). Sending is the send button only, as in Apple Messages.
   - Set `enterkeyhint="enter"` on the composers on phones.
   - **The send button gets an up-arrow icon**, not the ↵ return glyph (screenshots 7 and 17 show ↵, which reads as "new line").
   - **Desktop keeps Enter to send** and Shift+Enter for a new line, unchanged.
10. **Mic = dictation.**
    - Tapping the mic starts speech-to-text **into the composer at the caret** using the browser's speech recognition (`SpeechRecognition` / `webkitSpeechRecognition`), showing interim text live.
    - While listening, the mic shows an active state (a pulsing ring); tap again to stop. Stop on send, on blur and after silence.
    - Where it's unsupported or blocked (e.g. the insecure LAN origin, Firefox), show the toast **"Dictation isn't available here. Use the mic on your keyboard."**
    - Voice *messages* are not built here; later they'll take the long-press.
11. **Split indent from alignment:**
    - **List menu:** Bulleted list · Numbered list · divider · **Indent** · **Outdent**.
    - **Align menu:** **one row of four icon buttons** (left, centre, right, justify), each with an accessible name. The current option shows as pressed. No text rows, no indent.
    - Both composers.
12. **Revert the LIME-86 selection toolbar** (item 15: the toolbar turning into B/I/U/S + Done). Remove `is-selecting` and the Done button.
    - **Instead,** while text is selected in a composer, show a small **floating glass pill with B, I, U and S** positioned **above iOS's own Cut / Copy / Paste callout**. Place it above the selection rectangle with enough clearance for the system callout (about 52px). If there's no room above inside the visible viewport, place it below the selection with the same clearance. Always clamp it inside `visualViewport`.
    - The buttons show pressed state; the pill goes away when the selection collapses. The normal toolbar stays as it is throughout.
    - Phones only. Desktop unchanged.
13. **Reactions:**
    - The chips and the add-reaction smiley stay on **one row** under the bubble, even under a short bubble (screenshot 14 puts the smiley on a second line). The row aligns to the bubble's edge and may be wider than the bubble, up to the message column; it wraps only when the chips genuinely don't fit the column.
    - Chips get **less space left and right of the emoji**: about 5px horizontal padding and a 3px gap before the count.
14. **Code blocks inside a formatted message:**
    - The code tool inserts a code block **at the caret** (or turns the selected lines into one). The text before and after stays normal, keeping its bold, italic and lists.
    - Inside the block, Enter adds a line. **Enter on an empty last line, or ArrowDown on the last line, leaves the block** into a normal paragraph below.
    - A message mixing paragraphs, formatting, a list and a code block **sends and renders as composed** (the sanitiser keeps `pre`/`code` alongside the other allowed tags; the code block keeps its own horizontal scroll).
    - Applies to both composers, on all sizes.

**Out of scope:**
- the own-bubble colour and the dark "+" button (decision pending with the user);
- Pin/Star (LIME-80);
- receipts (LIME-81);
- desktop visuals;
- any new feature not listed.

**Phase 3: verification** (full matrix, since this closes the chain: `cd tests && npm test`, then `LIME_TEST_SERVER=dev npm test` and `LIME_TEST_SERVER=dev LIME_TEST_ORIGIN=lan npm test`; Chrome and Firefox; **0 failures** expected).
- **Add mobile checks for:**
  - the logo size;
  - the Messages fade present (a row under the header is visibly faded, not cut);
  - other bubbles lighter than the canvas, at ΔE ≥ 6 in 8 tones and dark, with text ≥ 4.5:1;
  - header glyphs at about 20px in 44px targets;
  - reason text ≥ 4.5:1 in every tone and dark;
  - the ring colour equal to its surface (list, pressed row, header);
  - with `--vv-top` and a reduced `visualViewport` height simulated, the thread composer's toolbar fully visible and every composer menu inside the viewport and below the header;
  - the link popover opening above the composer and inserting a link (with and without a selection, plus Remove);
  - Enter inserting a line break on phones (not sending) while Ctrl/Cmd+Enter still sends, and Enter still sending on desktop;
  - the send icon being the up arrow;
  - the dictation fallback toast when speech recognition is absent;
  - the list menu holding indent/outdent and the align menu holding four icon buttons;
  - no `is-selecting` toolbar, and the selection pill appearing above the selection, clamped;
  - the add-reaction smiley on the same row as the chips under a one-word bubble, and the chip padding;
  - a message with bold text, a list and a code block round-tripping through send and render.
- Remove or update the LIME-86 checks this brief supersedes (the selection toolbar, the align menu contents, the icon sizes).
- **Desktop pixel comparison:** 0 pixels differ in the three baseline states.
- Report the new check count, and any check you couldn't make meaningful in Chrome (dictation and the real iOS callout position will be among them).

**Gate (the user, on the iPhone):**
- the logo is a bit bigger and the list fades under the header;
- other people's bubbles are brighter in every theme;
- the header icons have room inside their glass;
- the menu's grey text is readable;
- the avatar rings match what's behind them;
- in a thread with the keyboard up, the toolbar and every menu are fully visible;
- link opens a box you can use;
- Return makes a new line, and the send button has an up arrow;
- the mic dictates (or explains why not over the LAN; real dictation may need the HTTPS/TestFlight build);
- align is a row of icons, and indent lives in the list menu;
- selecting text shows a B/I/U/S pill above Copy/Paste;
- the smiley sits beside small reactions;
- a code block can sit in the middle of a formatted message.

**Record:** add a `## LIME-86-fix` entry to `TEND.md`. Commit: `fix(mobile): QA round 3 close-out: fades, brighter bubbles, header icons, keyboard-safe menus, link, newline, dictation, selection pill, code blocks`, trailer `Brief: LIME-86-fix`, plus the attribution trailer. Push. **Stop for the user's review. No /loop wakeups.**

---

### LIME-86 → `tend` (landed as `c9712c9`): the mobile QA round on LIME-82 to 84

**The user's iPhone QA (2026-10-05, 9 screenshots) plus decisions.** Tiered verification (mostly CSS and UI JS: the `mobile` and `smoke` suites on the dev LAN, and the full matrix once before the push). ≤ 767px and touch landscape. **Then LIME-85** (the refactor must start from the corrected visuals).

**Toasts**
1. **Move the phone toasts to the top right, under the avatar pill**, right-aligned with it, glass, about 75% wide. The browser's own "Save username?" password prompt occupies the bottom, so toasts must never sit there.

**Chat and thread layout and scrolling**
2. **No horizontal scrolling anywhere in the chat** (the user can currently drag the chat sideways and the bubbles move). Clamp the width (`overflow-x: hidden` on the scroller, `overscroll-behavior: contain`, `touch-action: pan-y` on the message list; find the element that overflows and fix its width). Horizontal gestures are reserved for **future swipe actions** (swipe a row left for read, right for pin or delete; listed in Unbriefed).
3. **The header must never move or break while scrolling** ("sometimes everything scrolls and the header moves"): a fixed app shell (`height: 100dvh`, the body doesn't scroll, **only the list or messages container scrolls**), `overscroll-behavior: none` on the shell, and the floating header pinned. Test a fast fling, rubber-band at the top and bottom, and the keyboard open and closed.
4. **Landscape needs breathing room:** horizontal padding including `env(safe-area-inset-left/right)`, so nothing touches or hides behind the notch or edges (screenshot 844×390, notch on each side).
5. **Thread and teacher-details screens use the same header treatment as the chat:** floating glass round "‹" plus a glass title pill, the fade under it, **no plain "Thread" bar with a line**.

**The chat header**
6. **"⋯" is plain three dots with no circle** (as in the mockup; the current glyph has its own ring). Use the same glyph and stroke as search and call.
7. **The header icons are a little smaller inside their glass pill** (a ~22px glyph) with **equal stroke weight** across back, search, call and "⋯". Measure them.
8. **The "⋯" menu is narrower:** content-width with a sensible max (~260px), wrapping the "Rename" reason onto two lines inside it. (The "Unstar" label becomes "Pin"/"Unpin" in LIME-80; don't change it here.)

**Bubbles and the under-bubble row**
9. **Hide the add-reaction button unless the message already has reactions** (then it sits after the chips). New reactions come from press-and-hold. This cuts visual noise.
10. **Receipts:**
    - give the two ticks of ✓✓ a little space so they read as two;
    - **semantics until LIME-81:** show **one ✓ when the server has it**;
    - **✓✓ only means "read"**, so don't show ✓✓ until read receipts exist (the user saw ✓✓ on a message the other person hadn't read).
11. **Reaction chips are lighter still:** a very faint fill and no dark outline, with less horizontal padding.
12. **A compact reply summary on short bubbles:** when the bubble is narrower than the full "N replies · Last reply …" text, show just **"N replies"** (or "1 reply"), aligned to the bubble. The full text when there's room.

**The composer** (main and thread)
13. **Fix the responsive glitches** (the toolbar wrapping or overflowing at 360 and 390, the text area jumping when expanding). Screenshot each width collapsed, expanded and typing.
14. **The toolbar:** **left: +, emoji, Aa, list, align, link, code**; **right: mic, ↵.**
    - **Aa → a glass menu with only Bold, Italic, Underline, Strikethrough** (as in the mockup);
    - **list → a glass menu with Bulleted list and Numbered list**;
    - **align → a glass menu with Align left, centre, right, justify, plus Indent and Outdent**;
    - link and code as today.
15. **Selecting text** (the user's choice): **while text is selected in the composer, the toolbar row itself switches to inline Bold / Italic / Underline / Strikethrough buttons** (plus a "done" to return), **with no popup**, so iOS's Cut/Copy/Paste bubble never stacks with a Lime menu. Deselect and the normal toolbar returns. The Aa menu is still available when nothing is selected.
16. **Round buttons:** every circular hover or press state (toolbar icons, ↵, the header icons) is a **true circle** (equal width and height, `border-radius: 50%`). **The ↵ glyph shrinks to the standard inline size.**

**The dock**
17. **The dock icons share one stroke weight** (link, jam's book, call). Redraw any outlier at the shared stroke. Measure it.

**Own-bubble colour (added by the user, 2026-10-05)**
18. **Your own chat bubbles use the same green as the "+" FAB** at the bottom right of Messages: **`--lime-primary-bg`** (the FAB's fill, `.m-fab::before`, `lime.css` ~9657; currently pale lime) instead of `--seed-lime-300`, with `--lime-primary-ink` text. **Point both at the shared token** so they can never drift. Apply it on phones and **in the desktop chat too**, where own bubbles exist. Check:
    - the own bubble stays clearly distinct from the neutral bubble and the canvas **in all 8 tones and dark** (ΔE against both; flag Sage);
    - link colour and inline code stay readable on it (≥ 4.5:1).
    - **Update the lime-rule note** in `TEND.md`: own bubble = `--lime-primary-bg`.

**The user's answers recorded here:** horizontal gestures come later (item 2); selection → an inline B/I/U/S toolbar (item 15); **the Profile Name row shows the full display name** (keep it as is).

**Gate (iPhone):**
- toasts appear at the top right, clear of the password prompt;
- the chat no longer slides sideways, and the header never jumps;
- landscape has margins;
- thread and details headers match the chat;
- "⋯" has no ring, and its menu is slimmer;
- the smiley only shows on messages with reactions;
- ticks are clear (one ✓ until read receipts);
- lighter chips;
- "1 reply" on short bubbles;
- the chat box behaves at every width;
- selecting text turns the toolbar into B/I/U/S;
- all round buttons are round and the send arrow is smaller;
- dock icons match;
- **your bubbles are the same green as the "+" button.**

**Record:** add a `## LIME-86` entry to `TEND.md`. Commit: `fix(mobile): QA round 3: toasts, scroll lock, headers, receipts, composer menus, selection toolbar`, trailer `Brief: LIME-86`, plus the attribution trailer. Push. **Stop for the user's review.**

---

### LIME-85 → `tend` (after LIME-84's review): one shared component set; NO visual change on any size

**The user (2026-10-04):** chose desktop approach **A** ("same app, wider": desktop = the mobile screens as panes, from one shared component set) and approved this **invisible groundwork** before LIME-80/81 and desktop v2. **Nothing may look or behave differently after this brief.** It changes structure, not design.

**Assumptions:** the agent can refactor CSS and JS, run the full test matrix, take screenshot diffs, and commit. No build step exists (plain files served statically). Keep it that way unless the user agrees otherwise.

**Phase 1: an inventory (read-only; record it in `TEND.md`, then continue):** list every primary UI part and **where it's duplicated or diverges** between the phone and desktop paths (CSS selectors and JS render code):
- the conversation row;
- the message (bubble, under-bubble row, reply summary, reactions);
- the avatar, the stack and the presence icon;
- the badge;
- the chips;
- the composer (main and thread);
- the header controls (glass buttons and pills);
- the glass menu (all menus, including the long-press and reactions ones);
- the sheet and screen container (Settings, New message, Members, Thread);
- the toast;
- the icon button;
- the search field.

**If a divergence is a genuine design difference** (not accidental duplication), **list it and keep both looks as variants. Don't pick one.**

**Phase 2: the refactor:**
1. **CSS by component:** split the component styles out of `public/css/lime.css` into **`public/css/components/<name>.css`** (one per part above), loaded by `<link>` tags in a fixed order. Tokens and theme stay in `lime.css` (or a `tokens.css`).
   - **Each component styles itself from its own container:** a pane or screen sets `container-type: inline-size`, and the component uses **`@container`** queries for its narrow and wide variants.
   - **Viewport media queries remain only for the shell** (one screen vs panes, dock vs rail).
   - Keep `vendor/` untouched.
2. **JS by component:** one render function per part (e.g. `renderConversationRow`, `renderMessage`, `renderAvatar`, `renderComposer`, `openGlassMenu`, `openScreen`/`openSheet`, `showToast`), in `public/js/components/` or clearly grouped modules. **The phone and desktop paths both call the same functions** (variant options where Phase 1 found real differences). Remove the dead duplicates.
3. **A component catalogue:** **`docs/components.md`**, with each part's name, variants, states, the screens that use it, and its CSS file. **Use the same names the user can use in Penpot**, so designs and code share a vocabulary. This is the reference for the desktop design.
4. **The CSS guard** (the `css` suite) covers every new file (no `*/` in comments, rule counts).

**Verification (the full matrix: this touches JS):**
- **Screenshot diffs, before and after, must be zero** (allow only documented sub-pixel anti-aliasing) at **390×844, 360×780, 844×390 (touch), 1280×800, 1024×768 and 800×600**, for: Messages, a DM, a group, the thread, Members, a person, Settings and Profile, New message, each menu open, a toast, the composer collapsed and expanded, light and dark, and 2 tones.
- **All suites pass** on localhost, dev and LAN in Firefox and Chrome.
- Report the inventory, the files created, the lines removed by de-duplication, and the diff results.

**Scope:** `public/css/` (the split), `public/js/` (the component extraction), `public/index.html` and `auth.html` (link and script tags), `docs/components.md` (new), `tests/` (the css guard covering new files; screenshot-diff helper), and `TEND.md`. **No design changes, no new features.** If something can't be shared without a visible change, **stop and ask the user.**

**Gate:** you shouldn't notice anything. Lime looks and works exactly the same on phone and desktop. Read `docs/components.md`: those are the names to use when you design the desktop in Penpot.

**Record:** add a `## LIME-85` entry to `TEND.md`. Commits may be split into parts (each with the trailer `Brief: LIME-85`), e.g. `refactor: component CSS and container queries`, `refactor: shared render functions`, `docs: component catalogue`. Push. **Stop for the user's check.**

---

> **Shared context for LIME-82 to 84 (mobile v2).**
> - **The source of truth is the user's PNGs in `docs/design/mobile/` (01–06). Open and compare against them; screenshot your result next to each.**
> - **Commit the PNGs in LIME-82** (`.DS_Store` stays ignored).
> - Everything floating (header buttons and pills, menus, the composer, the dock, toasts, the Settings sheet) uses **Lime's liquid-glass style** (translucent, blurred, a hairline outline, a soft shadow, a large radius; solid when the system asks for reduced transparency).
> - ≤ 767px (and touch landscape) only; **desktop unchanged.**
> - **Tiered verification;** push each brief; stop after LIME-84.
> - **No personal data in commits** (the design PNGs use a fake phone number).

### LIME-82 → `tend` (next): the v2 Messages screen and chat header, glass toasts, the photo viewer on the back stack
1. **Messages (`01-messages.png`):**
   - **top left:** the **logo in a round glass button** (it scrolls the list to the top);
   - **top right:** a **glass pill with search and the user's avatar** (search opens a search field over the list; **the avatar opens Settings**, LIME-84);
   - **filter chips "All" and "Unread"** plus the **filter icon** (a glass menu: Pinned, Groups, Archived);
   - **no "Messages" title** (keep an accessible heading);
   - rows as designed: **times in ink** (not green), the green unread badges, the pin icon, the pastel avatars, group stacks;
   - a **floating lime-shaped pale-lime "+" (FAB) at the bottom right** above the dock (New message);
   - **the dock has 3 items: link · jam (book icon; use dew's closest book or notebook glyph, or a hand-drawn SVG in dew's style) · call.** **Account leaves the dock.**
2. **The chat header (`02-chat.png`):** floating glass at the top, over the messages:
   - **"‹" in a round glass button;**
   - a **glass pill with the 2-avatar stack + "+N", the truncated name, and "N members"** (a DM shows the person and their status). Tapping it opens **Members**;
   - **at the right, one glass pill with search, call and "⋯"** (search arrives in LIME-80; call shows the toast);
   - the messages scroll **under** the floating controls with the fade;
   - the "‹ 13" unread count is dropped in this design (only "‹"). **Confirm by matching the PNG.**
3. **Toasts on phones:** **liquid glass**, about **75% of the screen width**, centred, **just above the dock** (or the composer in a chat), never covering the header or list. **Confirm the position with the user at the gate** (they said "that position works").
4. **The photo wall and viewer join the back stack** (LIME-79-fix6's gap): back closes the viewer, then the wall, then returns to the chat.

**Gate:** Messages and the chat top look like your designs 01 and 02, side by side with the screenshots; toasts are glass, not full width, and sit above the dock.

**Record:** add a `## LIME-82` entry to `TEND.md`. Commit: `feat(mobile): v2 Messages and chat header, glass toasts, viewer back stack (+ design PNGs)`, trailer `Brief: LIME-82`, plus the attribution trailer. Push.

### LIME-83 → `tend` (after 82): the v2 composer and the "Aa" formatting menu
1. **The composer (`02`, `03`):**
   - **collapsed:** a glass pill, "+ · Send message… · mic";
   - **expanded on focus:** a glass card with the text area, then a toolbar: **left: +, emoji, Aa, bulleted list, numbered list, link, code**; **right: mic, ↵** (↵ disabled until text);
   - the same in the thread reply composer.
2. **"Aa" opens a glass menu (`04`)** in context, above the composer:
   - **Bold, Italic, Underline, Strikethrough**;
   - plus **Bulleted list, Numbered list, Indent, Outdent**;
   - **Align left, centre, right, justify.**
   - It applies to the selection (or the current paragraph for lists, indent and alignment), with the active states shown.
3. **The sanitiser (LIME-37's allow-list) must allow the new formatting safely:**
   - lists (`ul`, `ol`, `li`, already allowed?);
   - **indentation** as nested lists or `blockquote`;
   - **alignment** as a **single whitelisted attribute or class** (e.g. `data-align="center"` on `p`/`div`/`li`), **never free `style`**.
   - Rendered bubbles respect it.
   - **Update `docs/data-model.md`**: message content is sanitised HTML with this allow-list, which native clients must render too.
   - Add tests that a hostile `style`, `on*` or `javascript:` is still stripped.

**Gate:** tap the chat box: it opens as in your design; "Aa" offers bold, italic, underline, strikethrough, lists, indent and alignment, and they show correctly in the sent bubble.

**Record:** add a `## LIME-83` entry to `TEND.md`. Commit: `feat(mobile): v2 composer, Aa formatting (lists, indent, align) with safe sanitiser`, trailer `Brief: LIME-83`, plus the attribution trailer. Push.

### LIME-84 → `tend` (after 83): v2 Settings and Profile, Linked Devices, usernames, Donate
1. **Settings (`05-settings.png`):** a **glass sheet** opened from the top-right avatar, with a "×" to close:
   - a **profile card** (avatar, name, and **your own** phone or email; it's shown only to you; tap → Profile);
   - a group of **Account** (email, password, sign out; today's Login & security content) · **Linked Devices** · **Donate to lime**;
   - a group of **Customize** (today's Appearance).
   - Each row pushes its screen, with "‹" back (the LIME-79-fix6 back rule).
2. **Profile (`06-profile.png`):**
   - a large avatar plus **Edit Photo**;
   - a group of **Name** (→ an edit screen) · **About** (→ an edit screen for the bio);
   - the note **"Your profile and changes to it are visible to teachers you message and your groups."** (fix the PNG's typos; Lime has no "contacts" concept, so the word is dropped);
   - a group of **Username** (→ an edit screen), with the note **"Teachers can find you by your optional username, so you don't have to share your phone number."**
   - The other profile fields (pronouns, role, school, grades, subjects, timezone) stay reachable: **put them under About's screen.** Report it.
3. **Usernames (new):**
   - an optional, **unique**, case-insensitive `@username`: 3–20 characters, letters, numbers, `.` and `_`, not starting or ending with a dot;
   - **reserved words blocked** (admin, lime, support, …);
   - shown on profiles and member lists **instead of** an email or phone;
   - **New message search matches an exact `@username`** (or the username without the @).
   - **Contract and server:**
     - add `username` to `profiles` (`docs/api.md`, `docs/schema.sql`: a unique index on `lower(username)`);
     - `profile.update` accepts it, with the server rejecting duplicates as `conflict` and showing a clear inline message;
     - `GET /profiles?q=` matches it;
     - the visibility rule: username is a **public** field.
   - The local adapter mirrors the rules.
   - Seed: give the two test accounts usernames, e.g. `@shem` and `@jean`; others none.
4. **Linked Devices (new):**
   - **the contract and server:** `GET /auth/devices` (the caller's devices: `device_id`, a friendly label derived from the user agent, e.g. "iPhone · Safari", the last active time, "This device") and `DELETE /auth/devices/:device_id` (revokes that device's refresh token and ends its realtime connection; you can't remove the current device here; use Sign out);
   - **the screen:** the list, plus "Sign out" per device, with a confirm;
   - add api-suite checks.
5. **Donate to lime:**
   - opens an **external donation URL** from a config value (`LIME_DONATE_URL` in a committed, non-secret `public/js/config.js`, empty by default);
   - **when it's empty, tapping shows "Coming soon"**;
   - it opens in a new tab or the system browser.
6. **Desktop** keeps today's Settings modal. **Note** that usernames and Linked Devices need desktop UI later (list it in Unbriefed).

**Gate:** tap your avatar at the top right: Settings opens as in design 05; Profile matches 06; set a username and find yourself from the other phone by typing it in New message; Linked Devices shows both of your devices and can sign one out.

**Record:** add a `## LIME-84` entry to `TEND.md`. Commit: `feat(mobile): v2 Settings/Profile; usernames; linked devices; donate link`, trailer `Brief: LIME-84`, plus the attribution trailer. Push. **Stop for the user's review.**

---

> **Shared context for LIME-78 to 81: the mobile build (the user's Penpot design, 2026-10-03).** Applies at **≤ 767px only**; desktop is refined later. Read this before each brief.
>
> **The design, in words:**
> - **The Messages screen:**
>   - the logo mark plus a large "Messages" title, with a pale-lime **lime-shaped "+"** at the top right (New message);
>   - search plus a **filter** icon;
>   - **one list** (no Recent row, no sections, no tabs). **Pinned chats sit at the top with a pin icon after the name.**
>   - **Row:**
>     - a large lime-shaped avatar;
>     - a bold name;
>     - a 1–2 line preview, which can be **"typing…"**;
>     - the time at the right: **green plus a pale-lime count badge when unread**, grey when read ("Yesterday", dates);
>     - groups show **2, 3, or 3 + "+N"** stacked avatars, with names like "Jean, Rise & Me" and previews like "Jean: …";
>     - the selected or pressed row gets a soft neutral fill.
> - **The dock** (floating, rounded, neutral): **link** (chat bubble, unread total badge) · **jam** (pencil) · **calls** (phone) · **account** (your avatar). Labels in **lowercase**. The active item sits in a grey pill. **No Communities, no notifications bell on mobile.**
> - **The chat screen** (pushed; no dock):
>   - **the top bar:** "‹" plus the **unread count of other chats** (back to Messages); the truncated title; a **stacked-avatar group with "+N"** (tap → opens the right panel's details/members as a pushed screen); **search** (find in this chat); **phone** (calls); **"⋯"**.
>   - **Messages:**
>     - **others on the left**, with avatar and name, in a **neutral** bubble;
>     - **your own on the right**, in a **light-green** bubble (brand `#a3e18a`, `--seed-lime-300`, with ink text), no avatar;
>     - under each: **reaction chips plus an "add reaction" button**, then **the time and receipts (✓ / ✓✓)** at the right;
>     - the reply summary ("3 replies · Last reply Jul 7");
>     - rich text (bold, lists);
>     - media within the width.
> - **The composer:**
>   - **collapsed:** one pill ("+", "Send message…", mic);
>   - **on focus it grows:** the text area above a toolbar ("+", emoji/add reaction, B, I, U, "⋯", mic, ↵). **↵ is disabled until there's text, then it uses the existing pale-lime send pattern.** The keyboard's return key says Send.
> - **Menus:** Apple's newer pattern. **No bottom sheets.** A **"liquid glass" popover opens in context** from its trigger (translucent, `backdrop-filter` blur, rounded, a soft outline).
>   - **The chat "⋯" menu:** Rename · **Pin chat** · Customize (paint brush = Appearance) · Share · Archive · (divider) · Delete (red).
>
> **The user's decisions (2026-10-02/03):**
> - Communities is deferred.
> - Notifications are baked into link (badges plus live previews).
> - "typing…": yes.
> - Avatars stay lime-shaped.
> - Lowercase times ("06:32 am"; confirm the leading zero at the gate).
> - **Read receipts return:** ✓ sent (accepted by the server) / ✓✓ read (groups: read by everyone).
> - **Calls: leave the calls tab and phone icon in place, with no "Soon" badge** ("we will prioritize soon"). Tapping shows a gentle toast, "Calls are coming soon".
> - **Pin replaces Star:** the same per-user field, relabelled "Pin chat" / "Unpin chat", and pinned chats sort first.
> - **Default avatars use a few brand tints:** light green `#a3e18a`, pale lime `#e4f9be`, warm grey `#f0eee6`, plus a soft ink tint for variety, picked deterministically by name, with ink initials ≥ 4.5:1.
> - **The lime rule changes:** the **user's own bubble is light green** by the user's choice; bubble and wallpaper customisation come later.
> - **The bottom dock supersedes the README's 2026-09-23 push-drawer decision** (on phones).
>
> **Standing rules for all four:**
> - measure at **390×844** (plus 360×780);
> - run `tests/` on localhost **and** `LIME_TEST_ORIGIN=lan`;
> - check the real Firefox and Chrome with mobile emulation, **and Safari** (if `safaridriver` is enabled; otherwise say so);
> - desktop (≥ 768px) must look **unchanged**: compare screenshots;
> - **no personal data** in any committed file;
> - commit, push, and stop at each gate.

> **Shared context for LIME-79-fix2 to fix5 (the user's iPhone QA, 2026-10-03, 15 screenshots).** The same standing rules as LIME-78 to 81:
> - 390×844 and 360×780;
> - tests on localhost and LAN;
> - the real Firefox and Chrome, plus Safari if enabled;
> - desktop unchanged unless stated;
> - push, then stop at the end for review.
>
> **The user's design references are their Penpot screens** (Messages list, chat, the "⋯" menu, the expanded composer, recorded in the shared context above LIME-78). Where this list says "as designed", follow those. **Times:** no leading zero ("7:32 am"; the user didn't object when shown it).

### LIME-79-fix2 → `tend` (next): the Messages screen and shell polish, a new avatar palette, badges, landscape
1. **Background under the iPhone status bar:** the app's canvas must extend under the time, signal and battery area and behind Safari's bars (no white band at the top). Use `viewport-fit=cover`, `<meta name="theme-color">` matching the canvas (light and dark, updated when the tone or theme changes), the canvas on `html`/`body`, and safe-area padding (`env(safe-area-inset-*)`).
2. **Search field:** soften its outline (focus included; use the subtle neutral border, no heavy dark ring).
3. **The filter button's hover and press use warm neutrals** (the same tokens as the desktop nav and menu hovers), **not** the primary green.
4. **A new avatar palette, replacing LIME-79-fix's tints:**
   - **no brand greens** (no lime or dark green, so avatars never compete with the brand or the primary actions);
   - **no warm neutrals** (e.g. the grey "AD" avatar);
   - **soft pastels in hues complementary to the brand greens:** rose, coral/peach, apricot, butter, sky, periwinkle, lilac, and a cool aqua-blue (not mint);
   - 8 hues, distinct (OKLab ΔE ≥ 6 between every pair), ink initials ≥ 4.5:1, dark-mode variants;
   - **the account (dock) avatar follows the same palette** (or the photo), never brand green.
   - Report the table.
5. **Pressed and selected list rows have rounded corners** and an inset from the screen edges (as in the user's original screens), not an edge-to-edge band.
6. **Group avatar stacks: every stacked avatar gets the same ring** in the background colour (the 4-avatar stack currently shows darker outlines than the 2- and 3-avatar stacks). Use one token.
7. **Badges, one style:** the dock's link badge and each row's unread badge match: **lime green fill (`--seed-lime-300`) with ink numbers**, the same size, radius and font, and no outline. Report the sizes.
8. **The dock's native press effect:** pressing and holding on the dock shows a **liquid-glass highlight** (a translucent, slightly magnified pill) under the finger that **follows horizontally while held** and snaps to the item on release, like the iOS tab bar. Reduced motion: a simple highlight.
9. **Landscape on phones = the phone layout, not desktop:** use the mobile layout when `(max-width: 767px)` **or** `(pointer: coarse) and (max-height: 500px)`, so a phone turned sideways shows a responsive version of the vertical design (the list and chat full-width, the dock, safe areas). Tablets and desktop are unchanged. Screenshot it at 844×390.

**Gate:** no white band at the top; a soft search field; the filter hover is warm grey; avatars come in soft non-green colours; pressed rows have rounded corners; group stacks look even; badges match; the dock has a glassy press; turning the phone sideways keeps the phone layout.

**Record:** add a `## LIME-79-fix2` entry to `TEND.md`. Commit: `fix(mobile): status-bar canvas, palette, rows, badges, dock press, landscape`, trailer `Brief: LIME-79-fix2`, plus the attribution trailer. Push.

### LIME-79-fix3 → `tend` (after fix2): the chat view: header, reactions, receipts, alignment
1. **The header for large groups:** show **at most 2 avatars plus a count** ("+11"), and **truncate the names**, so the avatar stack, names and icons fit **on one line**, as in the user's screen. **No cramming.**
2. **Header icons:** search, phone and "⋯" use **the same stroke weight, height and width** (draw them in one icon set at one size; measure them).
3. **Header fade:** the chat header, the **thread header** and the **details header** use the **same fade effect as the Messages screen** (content fades under a glass bar), **not** a hard horizontal line with blur.
4. **Under each bubble, as designed:**
   - **reaction chips plus the add-reaction button aligned to the bubble's left edge**;
   - **the time plus ticks aligned to the bubble's right edge**;
   - **the reply summary aligned to the bubble's left edge**;
   - for others' messages, the same rule relative to their bubble.
   - Compare against the Penpot screens and report the alignments.
5. **The add-reaction button is subtler:** a lighter, muted icon (secondary text colour), the inline 20px size.
6. **Reaction chips:** a lighter background and outline, so the emoji stands out (a faint fill, a hairline or no border). Your own reaction is marked subtly.
7. **The add-reaction button opens the same glass reactions menu as press-and-hold** (the user loves that one), **anchored to the button**. Remove the detached floating emoji strip that can appear away from the button.
8. **Receipts:**
   - **remove the words** "Sent … · delivered …";
   - show **only the time plus ticks** (✓ or ✓✓);
   - **tapping the ticks or time opens a small glass popover:** Sent 2:07 pm · Delivered 2:22 pm · Read 2:30 pm (read details arrive with LIME-81; until then show sent and delivered).
9. **The thread screen** uses the same bubble, reaction and alignment rules as the chat screen.

**Gate:** big groups fit on one line at the top; the three header icons match; headers fade like the Messages screen; under each bubble, things sit where your design puts them; the smiley is subtle and opens the same reactions menu right beside it; tap a time to see sent and delivered.

**Record:** add a `## LIME-79-fix3` entry to `TEND.md`. Commit: `fix(mobile): chat header, reactions, receipts popover, alignment`, trailer `Brief: LIME-79-fix3`, plus the attribution trailer. Push.

### LIME-79-fix4 → `tend` (after fix3): one composer for the chat and thread, "Aa" formatting
1. **One composer component** for the main chat **and** the thread reply (today the thread's is the older design, with B I U S ⋯ and the "Secure & encrypted" row). Identical look and behaviour: collapsed pill → expanded on focus; ↵ disabled until text.
2. **Brighter:** the composer surface is **near off-white** (e.g. the elevated layer), so it stands out from the canvas, with the soft outline. Check it in every tone and in dark.
3. **The expanded toolbar:** **left: "+", emoji, "Aa"**; **right: mic, ↵**.
   - **"Aa" opens a glass formatting menu** in context (Bold, Italic, Underline, Strikethrough, Bulleted list, Numbered list, Quote, Code, Link). This replaces B I U and "⋯".
   - The web can't open the iOS system formatting menu, so this is Lime's glass menu in the native style; note it.
4. **↵ send:** a **perfect circle**, the glyph at the **standard inline icon size** (matching the other toolbar icons), and the states disabled, enabled (pale lime) and pressed. Measure it.
5. **Desktop:** leave the desktop composer as it is, unless sharing the component forces changes. Report any.

**Gate:** the chat box and the reply box are the same: brighter, with "+", emoji and "Aa" on the left and mic and send on the right. "Aa" opens the formatting options, and the send circle is round.

**Record:** add a `## LIME-79-fix4` entry to `TEND.md`. Commit: `fix(mobile): unified composer, Aa formatting menu, round send`, trailer `Brief: LIME-79-fix4`, plus the attribution trailer. Push.

### LIME-79-fix5 → `tend` (after fix4): signing in on a phone with the keyboard open
1. **The keyboard never hides the action:** on the email step and the password and create steps, the **Continue / Sign in / Create account** button stays visible above the keyboard. Use the `visualViewport` resize, scroll it into view, and a layout that fits the reduced height.
2. **The keyboard's Return says and does the next thing:**
   - the email field gets `enterkeyhint="next"` (Return = Continue);
   - the password field gets `enterkeyhint="go"` (Return = Sign in);
   - on create, the name field gets `next` to the password, and the password gets `done`/`go` (Return = Create account, if the terms box is ticked; otherwise it focuses the checkbox with a hint);
   - correct `autocomplete` (`email`, `current-password`, `new-password`, `name`) so iOS offers saved passwords.

**Gate:** on your phone, type your email and press the keyboard's button: you move to the password, and the Sign in button is visible the whole time.

**Record:** add a `## LIME-79-fix5` entry to `TEND.md`. Commit: `fix(mobile): auth with the keyboard open; Return goes to the next step`, trailer `Brief: LIME-79-fix5`, plus the attribution trailer. Push. **Stop for the user's review of fix2 to fix5.**

---

### Landed (2026-10-03): LIME-79-fix2 `3935a07`, fix3 `4f8b591`, fix4 `21dfddf`, fix5 `7a029d2` (all pushed; about 58 minutes for the four)
- The palette has 8 non-green pastels (ΔE ≥ 7.10). The 20px lime badges match. Dock press glass. Landscape on touch phones uses the phone layout. The header shows 2 avatars plus a count. One 24px header icon set. Fades. Under-bubble alignment. Receipts popover. A unified composer with "Aa". A 40px round send. Auth handles the keyboard and `enterkeyhint`. Desktop is 0 px different. **No real iPhone or Safari test yet.**
- **Tend's notes:**
  - (a) it **can't open the Penpot files**, so "as designed" was inferred. **Ask the user to export the Penpot screens as PNGs into `docs/design/mobile/`** so tend can compare directly;
  - (b) **a behaviour change:** Create account now refuses an unticked terms box (it used to create the account anyway). That's correct;
  - (c) **a bug found, not fixed:** a `#c=` deep link to a chat that arrived after the cached copy opens the list instead (unbriefed candidate);
  - (d) plot's uncommitted `PLOT.md` lines were correctly left out.
- **The user asked "why did this take an hour?"** Plot's answer: 4 briefs and about 35 items, each with full verification (the whole suite across localhost, dev and LAN in Firefox and Chrome; desktop pixel diffs; ΔE and contrast computation; screenshot sweeps), and re-runs after each fix. **Proposed tiered verification** (waiting for the user's choice): CSS-only polish runs the mobile suite plus smoke on one origin; JS, data or server changes run the full matrix; the full matrix runs once at the end of a chain rather than per brief.

### The user's updated Penpot designs, v2 (2026-10-04): to be exported into `docs/design/mobile/`
- **The user:** "my updates. Where can I add them for tend to reference? All the menus and chat boxes are liquid glass, Apple native aesthetic." **Plot's answer:** export them as PNGs into **`docs/design/mobile/`** in the repo, named in order (e.g. `01-messages.png`, `02-chat.png`, `03-chat-composer-open.png`, `04-format-menu.png`, `05-settings.png`, `06-profile.png`). **Warn: the Settings design shows a real phone number** (the test account's); replace it with a fake one (`+1 555-0100`) **before** exporting, because `docs/` gets pushed to GitHub.
- **The changes in v2 (plot's reading; confirm when briefing):**
  - **Messages:**
    - no "Messages" title;
    - the **logo in a round button at the top left**;
    - a **glass pill at the top right with search plus the user's avatar** (the avatar opens Settings);
    - **filter chips "All" and "Unread"** plus a filter icon;
    - the list as before (pastel non-green avatars; pin icon; green unread badges; times now in **ink**, not green);
    - a **floating pale-lime lime-shaped "+" button at the bottom right** (FAB);
    - **the dock: 3 items, link · jam (now a book icon) · call.** **Account leaves the dock** (it's now the top-right avatar).
  - **The chat header: floating glass circles:**
    - "‹";
    - a **glass pill with the avatar stack, the truncated name and "13 members"**;
    - **call**;
    - "⋯".
    - **No search icon in the chat header.**
  - **The composer:**
    - a glass bar; collapsed it's "+ Send message… mic";
    - expanded it shows **+, emoji, Aa, bulleted list, numbered list, link, code** on the left and **mic, ↵** on the right;
    - **"Aa" opens a glass menu with Bold, Italic, Underline and Strikethrough** (shown applied to selected text).
  - **Settings** (a glass sheet with "×"):
    - a **profile card** (avatar, name, phone);
    - a group of **Account · Linked Devices · Donate to lime**;
    - a group of **Customize**.
  - **Profile** ("‹"):
    - a large avatar and **Edit Photo**;
    - a group of **name** and **About**;
    - the note "visible to teachers you message, contacts and groups";
    - **Username** (optional, "so you don't have to give out your phone number").
  - **New features implied** (to plan, not build blind): **usernames**, **About** (the bio), **Linked Devices**, **Donate**, and the filter chips. Settings/Profile restructure the LIME-79-fix6 Account screen.
- **Next:** once the PNGs are in, plot drafts the v2 briefs. **Hold LIME-80 and 81** until then; their scope overlaps (menus, composer, search placement).
- **2026-10-04: the PNGs are in `docs/design/mobile/` (01–06, untracked until tend commits them; plot confirmed the Settings design now shows the fake `+1 555-0100`).** Corrections to the reading above:
  - **the chat header's right side is one glass pill with search, call and "⋯"** (so search *is* in the chat header);
  - **"Aa" also covers** bulleted and numbered lists, **indent and outdent**, and **alignment** (left, centre, right, justified) (the user, 2026-10-04).
- **The user's decisions (2026-10-04):**
  - **Donate:** opens an external donation link (a configurable URL the user supplies later; until then, "Coming soon");
  - **Linked Devices:** build it now (list devices, sign any of them out);
  - **Usernames:** build them now;
  - **Toasts:** "that position works" (read as **just above the dock**, plot's recommended option; confirm at the gate), restyled in **liquid glass** and about **75% of the screen width**, not full width.
- **Briefs LIME-82, 83 and 84 are drafted.** LIME-80 and 81 follow them.

### LIME-79-fix6 landed as `c0a0b50` (pushed, 2026-10-04; about 25 minutes under tiered verification)
- History entries cover every layered screen; Account (with Login & security and Preferences rows); New message full screen (Start → the chat over Messages); the back audit table is in `TEND.md`.
- Also fixed: a stale "Discard changes?" when reopening Settings (desktop too), and a New message pick opening details behind it (desktop too).
- **Open, waiting on the user:**
  - (a) the dock exists only on Messages, so a chat has no account button. Does the user want one? Plot's lean: **no** (keep chats focused; the WhatsApp pattern);
  - (b) the **photo wall and viewer aren't on the back stack** (a browser back there leaves the chat). An unbriefed candidate; small;
  - (c) **toasts can cover the first list rows.** Candidate: on phones, show toasts above the dock (bottom) instead of at the top. Ask the user.
- **The user's iPhone review is pending.** Then LIME-80 and 81.

### LIME-79-fix6 → `tend` (after fix5): back always returns to where you came from; the Account screen; New message full screen

**The user (2026-10-03), answering tend's LIME-79-fix questions:**
- (1) "back should always take you back to where you started. For profile, back to settings is confusing. Also profile could be changed to account."
- (2) "new messages should go fullscreen, agree."

1. **One navigation rule on phones: "‹" (and the browser or swipe back) always returns to the screen you came from.**
   - Keep a single navigation stack (built on the `history` work from LIME-78). Every pushed screen (chat, thread, members, person details, Account, the sub-screens, New message) pops back to **exactly** the screen and scroll position it was opened from.
   - **No "‹" ever jumps sideways** to a parent you didn't come through.
   - Audit every pushed screen and list each one's back target in `TEND.md`.
2. **The Account screen, replacing "Profile" on phones:**
   - the dock's **account** opens **Account** (title "Account"), with the profile fields **and**, below them, rows for **Login & security** and **Preferences** (each pushing its own screen, with "‹" back to Account);
   - **Account's "‹" returns to wherever you were** (e.g. Messages or a chat);
   - Save and Cancel as today.
   - **Desktop's Settings modal is unchanged for now** (desktop is refined later); note the label difference.
3. **New message on phones is a full pushed screen:**
   - the top bar has "‹", the title "New message", and **Start** at the right (enabled when someone's picked);
   - a search field;
   - chips for the picked people;
   - the results list (lime avatars, name and school);
   - the group-name field when 2 or more are picked;
   - the empty and no-match states as today;
   - "‹" returns to Messages.
   - Desktop keeps the centred dialog.

**Gate:**
- from a chat, tap account, then "‹": you're back in that chat;
- in Account, open Login & security, then "‹" twice: you're back where you started;
- "+" opens New message full screen.

**Verification:** **tiered** (see Patterns learned): the `mobile` and `smoke` suites on the dev server (LAN), screenshots of the changed screens, and the full matrix once before the push.

**Record:** add a `## LIME-79-fix6` entry to `TEND.md`. Commit: `fix(mobile): back returns to origin; Account screen; full-screen New message`, trailer `Brief: LIME-79-fix6`, plus the attribution trailer. Push. **Stop for the user's review.**

---

### LIME-79-fix landed as `9b69bf4` (pushed, 2026-10-03); the user's iPhone review is pending
- **All 14 items are done;** 262 mobile checks. Tend also fixed:
  - the chat "⋯" menu, invisible on phones since LIME-78 (it opened as a 0×0 box);
  - a stray 16px left gap;
  - presence updates blanking the open chat's header;
  - the thread back arrow.
- **Presence is live** (~0.6s), and live presence overrides the seed's static status with the API on.
- Icons: 24px in ≥ 44px targets; inline 20px; the pin is 17px. Eight tints (ΔE ≥ 6.26 light, 5.95 dark).
- **Not tested on a real iPhone or in Safari.** The user's iPhone check is the real test.
- **ANSWERED by the user 2026-10-03:** (1) back always returns to the origin, and Profile becomes **Account**; (2) New message goes full screen. Both are in **LIME-79-fix6.**
- **Tend's questions, with plot's leans sent:**
  - (1) Profile's "‹" goes to the Settings list (which keeps Login & security and Preferences reachable): **keep.**
  - (2) The New message picker on phones: **make it a full pushed "New message" screen** (the native pattern, like WhatsApp's new chat), not a glass menu or a centred dialog. A small follow-up if the user agrees.
- **Lesson:** LIME-78's test passed a 0×0 menu as "on screen". Visibility checks must assert a **non-zero size and `elementFromPoint` hitting the element**, not just bounds (added to Patterns learned).

### LIME-79-fix → `tend` (next): the mobile QA round on LIME-78 and 79 (the user reviews before LIME-80)

**The user's QA on an iPhone (2026-10-03, 9 screenshots):** "make these QA updates for me to review before we move on." Applies at ≤ 767px unless stated. **This brief absorbs LIME-80 item 1 (glass menus)**; LIME-80 keeps Pin, Customize, native share and pickers, and find-in-chat.

1. **Avatar tints: more pastel variety, within the brand palette.** LIME-79's 4 tints (`PALETTE_SIZE = 4`, `app.js` ~1968; `lime.css` ~399) make too many people look alike.
   - Build **8–10 soft pastel tints** derived only from Seed's brand ramps (the `--seed-lime-*` steps such as 50/75/100/150/200/300, `--seed-meadow-*`, and warm `--seed-soil-*` tints such as 0/100/200), so they're **distinct from each other**: measure OKLab ΔE ≥ ~6 between every pair and report it.
   - Ink initials ≥ 4.5:1 on each; dark-mode variants.
   - The deterministic pick by name is unchanged.
2. **The Messages header is a fixed top bar** with only the **logo, "Messages" and "+"**. **Search and filter scroll with the list** and **fade under the header bar** as you scroll (a mask fade, like the bottom fade).
3. **One menu style everywhere, the "native" look.** The user likes the "+" (attach) menu because it's **iOS's own native menu** (Photo Library / Take Photo or Video / Choose Files): frosted liquid glass, large ~17px text, icons at the left, a large radius, in context. **Every other menu on phones must look like it:** the filter, the chat "⋯", the title menu, the New message picker's result list styling where it's a menu, and any other popover.
   - Implement it as Lime's **glass menu**: translucent with `backdrop-filter: blur(…) saturate(…)`, a solid fallback, a large radius, a hairline outline, 44px rows, icons left, opening in context from the trigger with a short scale and fade.
   - **Screenshot it next to the native "+" menu** for comparison.
4. **The pin icon is too small:** make it match the name's cap height (≈ the 16–18px visual size of the name text). Measure it.
5. **The dock in liquid glass,** like the menus: translucent and blurred, so the list shows through it while scrolling.
6. **Icon sizes, one standard on phones:**
   - **header and dock icons:** a ~24px visible glyph in ≥ 44px tap targets;
   - **inline action icons** (under bubbles): ~20px.
   - **The call icon is too small; the search icon is too big.** Measure every header, composer, row and dock icon's rendered box and report a before/after table.
7. **The chat header feels native** (an iOS-style navigation bar):
   - **"‹" then a plain number** (the other-chats unread count as **text**, not a pill badge, e.g. "‹ 13");
   - the title and avatar stack centred;
   - the icons at the right (search, call, "⋯") at the standard size;
   - a **glass bar** that the messages scroll under (a fade or blur).
8. **Tapping the names or avatars in the header** opens the right panel **showing everyone in the chat (Members)**, for groups **and** DMs (a DM shows both people). Tapping a member then shows their details, with "‹" back to Members (the LIME-64 pattern).
9. **Remove the inline reply button** (from LIME-79). Keep the add-reaction button under the bubble, as in the user's design.
   - **Press and hold** (a ~400ms long-press) on a message opens a **context menu in the same glass style**, anchored to the message:
     - a **row of quick reactions** (6 common emoji plus "more");
     - **Reply in thread**;
     - **Copy text**.
   - Also add a light haptic where available (`navigator.vibrate(10)`, Android only).
   - Long-press must not trigger text selection or the browser's own callout on the bubble (`-webkit-touch-callout: none` and `user-select` on the bubble during press). Text stays selectable via Copy.
10. **The return (↵) icon is broken in the expanded composer:** fix the glyph and size, and check every state (disabled, enabled pale-lime, pressed).
11. **The composer gets a scroll fade:** messages fade out **under** the composer area, like the dock area does on the Messages screen.
12. **Remove the mic-selection caret and dropdown** (on mobile **and** desktop: the user said "remove mic selection"). The mic is a single button. Pressing it shows the toast "Voice messages are coming soon". The future feature records with a live sound-wave view (note it in the README's roadmap line).
13. **Settings on phones** (the Account → Profile screen; screenshot: a grey pill with "‹" plus a separate "×"): use the **same native-style header** as item 7 (a "‹" back to the previous screen, the title "Profile", no "×"), with the Save and Cancel footer above the safe area.
14. **Presence check (the user asked "are the status icons working?"):** verify live presence on the dev server with two clients. When one signs in or out, the other's status icon updates within a few seconds, in the list, the chat header area and the members list. Report what works; **fix it if it isn't live.** Note: the seed's static `status` values (e.g. Jean "busy") must be **overridden by live presence** when connected; say how they combine.

**Scope:** `public/css/lime.css`, `public/js/app.js`, `public/index.html` (removing the mic caret and dropdown markup), `server/` only if presence needs a fix, `README.md` (the roadmap line), `tests/`, and `TEND.md`. **Desktop is unchanged** except item 12 (the mic caret removed) and item 1 (the tints).

**Verification:**
- Screenshots at 390 and 360: Messages (scrolled, so search fades under the header and the list shows through the dock), every menu next to the native "+" menu, a chat (scrolled under the header and composer), a long-press menu, the composer states, the Members panel from the header, and Settings Profile.
- The icon table, the tint ΔE and contrast table, and the presence results (two clients, timings).
- Tests pass on localhost and LAN.
- Desktop screenshots unchanged apart from items 1 and 12.
- Push.

**Gate (on the iPhone):** the header stays put while search scrolls away under it; the dock and every menu look frosted like the "+" menu; icons are even; "‹ 13" is a plain number; tapping the names shows everyone in the chat; press and hold a message for reactions and reply; the mic is a single button; the send arrow looks right; avatars come in more soft colours.

**Record:** add a `## LIME-79-fix` entry to `TEND.md`. Commit: `fix(mobile): QA round: glass header/dock/menus, icons, long-press, composer, tints`, trailer `Brief: LIME-79-fix`, plus the attribution trailer. Push. **Stop for the user's review.**

### Landed (2026-10-03): LIME-78 `d57298f` and LIME-79 `1048c45`, both pushed
- 159 mobile checks; desktop pixel-identical apart from the avatar tints; Safari not run (`safaridriver --enable` still pending); **no real-phone test yet** (the user's gate).
- **Tend's additions beyond the briefs** (reasonable, but the user should OK them):
  - a **reply button** next to add-reaction (phones have no hover toolbar for starting a thread);
  - a **12-emoji popover** for the composer's emoji button;
  - Shift+Enter still gives a newline (on keyboards that have it).
- **Open: the leading zero in times** ("06:32 am" as in Penpot vs "7:32 am" today). Asked the user.
- **The user's gate check on 78 and 79 is pending.** LIME-80 and 81 wait for it.

### LIME-78 → `tend` (next): the mobile shell: dock, Messages screen, pushed chat with back, header
**The change (≤ 767px):**
1. **The dock** as designed. It replaces the hamburger drawer on phones (remove the drawer and its toggle at this width). The link badge = total unread.
   - **jam** opens the existing Jam placeholder;
   - **calls** shows the toast;
   - **account** opens Settings → Profile (full screen on phones), where sign-out also lives.
2. **The Messages screen** as designed:
   - logo, title, "+" (New message), search (filters the list as you type), and **filter** (an in-context menu with **All · Unread · Pinned · Groups · Archived**; the in-context menu style comes in LIME-80, so here a plain menu is fine);
   - **pinned first**, then by recency;
   - the row design (time and badge rules, group stacks with "+N", 2-line preview);
   - **remove on mobile:** the Recent row, the section headers, the Messages/Communities tabs, the bell, the breadcrumbs.
3. **Stacked navigation:** tapping a row **pushes the chat screen**. "‹" with the other-chats unread count goes back to Messages. **The browser and Android back button also go back** (`history.pushState` / `popstate`), and the deep links `#c=` still work. The thread panel and details also push as full screens with "‹".
4. **The chat top bar** as designed. Tapping the avatar stack or title opens **details/members** (the existing right-panel content) as a pushed screen. Search and the phone are placeholders here (search arrives in LIME-80; the phone shows the calls toast).
5. **The README:** replace the 2026-09-23 mobile drawer decision with the dock decision (date it 2026-10-03, the user's choice).

**Scope:** `public/index.html`, `public/js/app.js`, `public/css/lime.css` (mobile media queries), `README.md`, `tests/`, and `TEND.md`. **Not:** desktop layout, message rendering (LIME-79), menus (LIME-80), or live typing and receipts (LIME-81).

**Verification:** screenshots at 390 and 360 of Messages (plain, with the filter open, empty search), a chat, details, the thread, and the back flow (including the browser back button). Desktop screenshots unchanged. Tests pass on both origins.

**Gate (on your phone):** the Messages screen looks like your design, with the dock at the bottom. Tap a chat and it opens full screen; "‹" (or swiping back) returns to the list. Tap the avatars at the top for details.

**Record:** add a `## LIME-78` entry to `TEND.md`. Commit: `feat(mobile): dock, Messages screen, stacked navigation`, trailer `Brief: LIME-78`, plus the attribution trailer. Push.

### LIME-79 → `tend` (after LIME-78): the mobile chat view: bubbles, reactions row, time and receipts slot, the composer, brand avatars
**The change:**
1. **Bubbles (≤ 767px):** others left (avatar + name on the first of a run; consecutive messages from the same sender group without repeating them), neutral bubble (the current bubble token). **Own messages right, in `--seed-lime-300` with ink text**, with no avatar or name. A max width of ~78%. **Nothing overflows:** long URLs wrap, and albums, location cards, link previews and code blocks fit.
2. **Under each bubble:** the reaction chips plus an **add-reaction** button (opens the existing picker), and at the right the **time (lowercase, e.g. "7:32 am") plus a receipt slot** (render "✓" for now; LIME-81 makes it live). Then the reply summary as designed.
3. **The composer** as designed: collapsed pill → expanded on focus (the toolbar slides in); ↵ disabled until text, then pale-lime; it collapses again when empty and blurred; `enterkeyhint="send"`: on phones the keyboard's Return **sends** (the common messaging pattern; document it). There's no newline from the keyboard on phones, which is accepted. Mic and "+" as today. **The toolbar never expands just because the keyboard opened.**
4. **Brand default avatars (all widths):** replace the 12-pastel `hashName` palette with the **brand tints** listed in the shared context (deterministic by name), with ink initials, contrast ≥ 4.5:1, and dark-mode variants computed and measured.
5. **Times in lowercase** everywhere on mobile (list and chat). **Ask the user at the gate whether "06:32" keeps the leading zero.**

**Scope:** message, composer and avatar rendering and CSS, `tests/`, and `TEND.md`. **Not:** receipt logic (LIME-81) or menus (LIME-80).

**Verification:** 390 and 360 screenshots: a DM, a group with runs, own and others' messages, every message type, reactions, a reply summary, and the composer collapsed, expanded, typing and sending. The avatar contrast table. Desktop unchanged (apart from the avatar tints, which apply everywhere). Tests pass on both origins.

**Gate:** your messages are on the right in light green and others' on the left; nothing is cut off; the message box starts as one line and grows when you tap it; the send button wakes up when you type.

**Record:** add a `## LIME-79` entry to `TEND.md`. Commit: `feat(mobile): chat bubbles, reactions row, composer; brand avatar tints`, trailer `Brief: LIME-79`, plus the attribution trailer. Push. **Stop for the user's check** (LIME-78 and 79 are checked together).

### LIME-80 → `tend` (after the user checks 78 and 79): in-context "liquid glass" menus, Pin, native share and pickers, find-in-chat
**Amendment (2026-10-03):** the glass-menu styling (item 1) and the removal of the mic list (item 3's mic `<select>`) **moved into LIME-79-fix**. LIME-80 keeps items 2, 3 (share and timezone only), 4 and 5.
1. **Menus on phones** (the chat "⋯", the filter, the title menu, the mic list, the list row's long-press if any): **an in-context popover** anchored to its trigger. Translucent (`backdrop-filter: blur(…) saturate(…)`) with a solid fallback where unsupported, a rounded large radius, a soft outline, items with icons, and Delete red. It opens from the trigger with a short scale and fade (reduced motion: fade). It stays inside the viewport. Closes on outside-tap or Escape. **No bottom sheets.**
2. **The chat "⋯" items:** Rename · **Pin chat / Unpin chat** · **Customize** (opens Appearance) · Share · Archive · Delete. **Pin replaces Star app-wide** (labels, toasts: "Pinned" / "Unpinned", the pin icon in rows, pinned-first sorting). **Keep the stored field and op** (`starred`, `membership.setStarred`) **for compatibility**, and document "Pin = starred" in `docs/api.md`.
3. **Native where allowed:**
   - Share uses **`navigator.share({ title, url })`** when available (phones), falling back to the existing popover;
   - the **mic list and timezone** become native `<select>` on phones;
   - inputs get the right `type` / `inputmode` / `autocomplete`.
4. **Find in chat** (the search icon): a search field in the top bar that highlights matches in the loaded messages, with up and down to step between them and a "3 of 12" count. **Local only.**
5. **Calls** (the dock and the phone icon): the toast "Calls are coming soon".
6. **(Added 2026-10-05) Instant sign-out of a revoked device:** when Linked Devices signs a device out, the server sends `{ type: 'revoked' }` on that device's realtime stream before closing it. The client signs out at once, with the toast "You were signed out from another device". Add an api-suite check.

**Gate:** "⋯" opens a frosted menu right where you tapped; Pin keeps a chat at the top; Share opens your phone's share sheet; search finds words in the chat.

**Record:** add a `## LIME-80` entry to `TEND.md`. Commit: `feat(mobile): in-context glass menus, pin, native share/pickers, find in chat`, trailer `Brief: LIME-80`, plus the attribution trailer. Push.

### LIME-81 → `tend` (after LIME-80): live "typing…" and read receipts
1. **Contract** (`docs/api.md`):
   - **typing** is an ephemeral realtime message, `{ type: 'typing', conversation_id, user_id, state: 'start'|'stop' }`, sent by `POST /typing` (rate-limited, ≤ 1 per 3s per conversation) and fanned out over `/events` to the **other members only**, never logged as an op. It auto-expires after 6s without a refresh.
   - **Receipts:** **members can now see each other's `last_read_at`** (the user's decision 2026-10-03; update the visibility section and the privacy notes). `membership.markRead` feed entries go to **all members** of that conversation, not only the actor.
2. **The server:** implement both, with api-suite checks (fan-out, rate limit, expiry, visibility).
3. **The client:**
   - **typing:** send while the composer has text and focus (throttled; stop on send, blur or empty).
   - **Show it:**
     - in the **list preview** as "typing…" (green italic or muted; tend proposes, matching the design);
     - in the chat as an **animated three-dot bubble** on the left, with the typer's lime avatar, just above the composer. In groups, show stacked avatars when several people type, plus "Jean is typing…" or "2 people are typing…".
     - **Reduced motion:** static dots.
4. **Receipts:**
   - own messages show **a clock icon while still in the outbox**, **✓ once the server accepts them**, and **✓✓ once every other member's `last_read_at` ≥ the message's `server_ts`**;
   - grey ticks, with the ✓✓ in brand green;
   - tapping a group message's ticks shows who has read it (a small popover). Optional: if large, report it and skip.

**Gate:** on two phones, start typing on one; the other sees "typing…" in the list and dots in the chat. Send it; the ticks go ✓ then ✓✓ when the other opens it.

**Record:** add a `## LIME-81` entry to `TEND.md`. Commit: `feat: live typing indicator and read receipts`, trailer `Brief: LIME-81`, plus the attribution trailer. Push. **Stop for the user's check.**

---

### The user's own mobile design (Penpot), direction set 2026-10-02: supersedes the LIME-77 mock
- **The user:** "I am using Penpot to create my own as I have the vision… It needs to be simplified greatly for people of all ages to use. Let's use this direction." They're adding **the chat screen and the reply thread** next. **Don't brief the mobile build until those arrive.** LIME-77's mock was "helpful to start" and is superseded.
- **Screen 1, Messages (plot's reading of the user's design):**
  - **Header:** the **lime logo mark** next to a large **"Messages"** title, and at the top right a **pale-lime "+"** button that appears **lime-shaped** (the silhouette).
  - **A search field**, with a **filter icon** (sliders) to its right.
  - **A row of large round avatars** with names (Recent / favourites).
  - **One simple list, with no Starred/All sections and no Messages/Communities tabs.**
  - **Row:**
    - a large round avatar;
    - a **bold name**;
    - a preview line that can show **"typing…"** live;
    - a **time** at the right: **green when unread**, with a **pale-lime round unread-count badge** (ink number); **grey when read**, with "Yesterday" for older days;
    - **groups show two overlapping avatars** and "Jean, Rise & Me" style names with a "Jean: …" preview.
  - **Dock:** a floating rounded bar with **three items only, labelled in lowercase**:
    - **link** (chat bubble, unread badge "2"; the active item in a grey pill);
    - **jam** (pencil);
    - **account** (the user's avatar).
  - **Communities and Notifications aren't in the dock.**
- **ANSWERED (the user, 2026-10-02):**
  1. **Communities is scoped back** until direct and group messages are landed. LIME-28 / the Communities decision surface is deferred; hide the Communities entry points on mobile. **Notifications are baked into link:** badge counts plus live, dynamic preview text. There's no separate notifications screen on mobile (the bell mockup goes away there).
  2. **Desktop is refined after mobile** (a later pass follows the same simplification).
  3. **"typing…": yes** (an ephemeral realtime event; add it to `docs/api.md` alongside presence).
  4. **Avatars stay lime-shaped** (the user's round placeholders are just placeholders).
  5. **Time format in lowercase:** "06:32 am" (the user's design shows a two-digit hour; confirm "6:32 am" vs "06:32 am" at the build gate if unclear).
  - Still open: where Starred and Archived live (plot's assumption: the filter button).
- **Implications to settle when briefing (ask the user then, not now):**
  - (1) Where do Communities, Notifications, Starred and Archived live? (Likely: the **filter** for Unread, Starred, Groups and Archived; Notifications and Communities later.)
  - (2) **"typing…"** is a new live feature: an ephemeral realtime event (a contract addition, not an op).
  - (3) Is this simplification **mobile-only, or the direction for desktop too**?
  - (4) The time format ("06:32 am") versus the current "6:32 AM".
  - (5) The avatars in the user's design are **round**; confirm whether the lime silhouette stays for avatars ≥ 32px.

### LIME-76 landed as `b1cd522` and LIME-77 as `3932666` (both pushed, 2026-10-01)
- **LIME-76:** `ids.js` (`getRandomValues`), per-browser device ids, the server rejects non-UUID device ids, a "Couldn't save that" toast, and `LIME_TEST_ORIGIN=lan` suites asserting an insecure context. The mutation check proved the test catches the original bug. **Safari wasn't run:** the user must run `safaridriver --enable` (it asks for their password), then `cd tests && LIME_TEST_ORIGIN=lan node run.mjs safari`. **The user's phone gate is pending.**
- **Plot's review of the LIME-77 mock (from tend's Chrome screenshot):**
  - **(a) Frame 1 renders incompletely in Chrome:** the **Recent row is blank and the floating dock and toast are missing** (they do render in the dark frame 5). A mock bug to fix before judging it.
  - **(b) Frame 2 introduces an unrequested design change:** **the user's own messages are right-aligned in pale-lime bubbles** (the WhatsApp/iMessage convention), whereas the app lays every message out left with names. That's a product decision for the user. It also conflicts with the lime rule (lime is for primary actions).
  - **(c) The dock's Link item uses a chain-link icon,** while the app's Link nav uses the chat bubble (`dew-chat`). It should match.
  - The rest (the top bar with "‹", centred avatar and name, Share and "⋯"; the sheet with a title and Cancel; the classic bar alternative; the native list) matches the proposal.
  - Asked the user: their verdict, own messages left or right (and the colour), and floating vs classic.

### LIME-77 → `tend` (after LIME-76): a static mock of the phone shell, for the user to approve before building

**The user (2026-10-01):** OK to a **bottom dock** on phones (superseding the push-drawer decision), **native elements where allowed**, and **a mock first**. See the open decision "the mobile shell" for the full proposal. **This brief builds no app behaviour.** It's a picture made of real CSS, so the user can say yes or no.

**Assumptions:** the agent can write HTML/CSS, take screenshots with the installed browsers, and commit.

**The change:** create **`public/mockups/mobile-shell.html`** (served by the dev server's allow-list; it isn't linked from the app). It's static HTML using **Lime's real tokens and CSS** (`vendor/seed` tokens, `public/css/lime.css`: the lime avatars, status icons, pale-lime primary, canvas tones, Montserrat). It shows **phone frames at 390×844** side by side, each labelled:
1. **Chats (the list screen):**
   - a large title "Messages", with a **"+"** at the top right (pale-lime primary; it opens New message);
   - a search field;
   - the Recent row, Starred and All (real-looking seed names);
   - **the dock** at the bottom: **Link (selected), Communities, Notifications (badge "3"), You (your avatar)**. Styled as a **floating, rounded, translucent pill** (like the user's WhatsApp reference), clearing the iPhone home indicator (safe area).
   - **A toast** shown at its phone position (just under the top bar, not covering the title).
2. **A chat (the pushed screen):**
   - the top bar has **"‹"** (back to Chats) at the left, the **avatar plus name plus status/member line** centred (tappable for details), and **Share and "⋯"** at the right;
   - **no breadcrumbs, no dock** inside a chat (like WhatsApp and Messages);
   - messages: text bubbles, a long URL wrapping, a photo album, a location card, a reply-count line, and the "Sent · delivered" note. **Everything fits the 390px width.**
   - the composer pinned above the safe area: "+", the input with the keyboard's return labelled **Send** (note it), and mic ⌄.
3. **The "⋯" bottom sheet:** a grab handle; items **Star, Rename, Appearance (paint brush), Share, Archive, and Delete (red)** in Lime's menu style, over a dimmed backdrop; the native look of an iOS action sheet, in Lime's style.
4. **For comparison: the dock as a classic full-width tab bar** (a small frame, Chats only), so the user can choose between floating and classic.
5. **One dark-mode frame** of screen 1.

**Under the frames, short notes** listing what will be **native** in the build:
- `navigator.share` for Share;
- a native `<select>` for the microphone and timezone pickers;
- `inputmode` / `type` keyboards for email, phone and search;
- `enterkeyhint="send"`;
- native file and photo pickers.

Also note what **can't** be native on the web (action menus become bottom sheets; no haptics on iOS).

**Scope:** `public/mockups/mobile-shell.html` (new), its own small CSS block inside it (mock-only, no changes to `lime.css`), and `TEND.md`.

**Verification:** screenshots of the page in the real Firefox and Safari (Safari as the iOS proxy), with the paths given; text contrast holds; nothing overflows 390px. **There's no app regression risk** (no app files change); confirm with `git diff --stat` (only the new file plus `TEND.md`).

**Gate:** open `http://localhost:8000/public/mockups/mobile-shell.html` (or the network link on your phone) and say yes, or what to change: the dock items, floating or classic, the top bar, the sheet.

**Record:** add a `## LIME-77` entry to `TEND.md`. Commit: `docs: static mobile shell mock (dock, chat, sheet)`, trailer `Brief: LIME-77`, plus the attribution trailer. Push. **Stop for the user's verdict.** Plot then drafts the build briefs (the shell and navigation, the layout fixes, and the native elements and sheets).

---

### LIME-76 → `tend` (next, urgent): phones can't send. `crypto.randomUUID` doesn't exist on the LAN address

**The user's QA (2026-10-01):** signed in as Jean and Shem on two phone browsers via `http://192.168.0.127:8000`. **No messages showed from either end, not even a profile change.**

**Plot's diagnosis (from the dev server's own `data/oplog.jsonl` and the code):**
- The phones **did** reach the server: 13 ops arrived (`markRead`, a `profile.update` by teacher-002 to "Shem Rajoon" with an audience of 15, and a `reaction.toggle`). **But there's not a single `message.send`.**
- **Every op has `device_id: "web-volatile"`.** That's the fallback in `api-adapter.js` ~82–84, taken when `'web-' + crypto.randomUUID()` throws.
- **`crypto.randomUUID()` (and `crypto.subtle`) exist only in secure contexts.** `http://localhost` is secure; **`http://192.168.x.x` isn't.** So on phones:
  - (a) **`sendMessage` throws** at `store.js` ~632 (`crypto.randomUUID()` for the message id), and so do the attachment ids (~637) and new conversations (~749, ~760). **That's why no message was ever sent.**
  - (b) every phone shares the **same** `device_id`, `"web-volatile"`, which can collide in per-device sessions and refresh tokens. That's a likely reason the other phone didn't receive the profile change (its session or feed may have been revoked or confused). Confirm it.
- Tend's suites all ran on `localhost` (secure), so they never saw it.

**The change:**
1. **A shared id helper**, `public/js/ids.js` (loaded before everything that needs it): `newId()` returns a UUIDv4 using **`crypto.getRandomValues`** (available in insecure contexts), and `newOpId()` returns a **UUIDv7** the same way (the contract asks for v7 op ids; check what the adapter does today). **Replace every `crypto.randomUUID()`** in `public/js/` with it (the full list is the grep above: `auth.js` ~143, `api-adapter.js` ~82, `store.js` ~632/637/647/660/749/760, `local-adapter.js` ~58, and any others found).
2. **`device_id`:** generated with the helper and stored per browser. **Never a shared constant:** if storage is unavailable, generate a random id per page load. Remove `"web-volatile"`.
3. **`crypto.subtle`** (`auth.js` ~76, the `LocalAdapter`'s browser-side PBKDF2): with the `ApiAdapter`, passwords are verified by the server, so this path isn't used. Make sure it's **never reached in `ApiAdapter` mode**. In `LocalAdapter` mode on an insecure origin, show a clear message instead of a crash.
4. **Never fail silently:** wrap op creation so any exception in a write shows the error toast and logs it, rather than leaving the UI looking sent while nothing was queued.
5. **The server side of the collision:** confirm what `"web-volatile"` did to sessions and refresh tokens (e.g. signing in as Jean revoking Shem's session on the "same device"). The server should **reject an obviously invalid `device_id`** (not a UUID) with `bad_request`, so this can't recur silently.
6. **Tests over an insecure origin:**
   - add a `LIME_TEST_ORIGIN` option so the browser suites (and `e2e-server`) run against the **LAN IP** (`http://<this Mac's LAN IP>:8000`), not `localhost`;
   - confirm in the test that `window.isSecureContext === false` there;
   - run the whole `e2e-server` suite that way in Firefox and Chrome;
   - **also drive Safari on the Mac** (`safaridriver`, WebDriver; the same WebKit engine as iOS Safari) for at least: sign in, send a DM, receive a DM live, and a profile change propagating. If `safaridriver` needs enabling (`safaridriver --enable` asks for the user's password), **stop and give the user the one command.**

**Scope:** `public/js/` (the new `ids.js`, the replacements, error handling), `public/index.html` and `auth.html` (script tag), `server/` (`device_id` validation), `tests/` (the origin option, the Safari run), and `TEND.md`.

**Verification:**
- `grep crypto.randomUUID public/js` finds 0.
- The full suites pass on localhost **and** on the LAN IP (insecure).
- Safari passes its checks.
- A fresh `data/` log after the e2e run shows `message.send` ops with **distinct** `device_id`s.
- **Manual phone steps for the user,** listed exactly.

**Gate:** restart the server (`rm -rf data` first, so the test accounts are fresh). On two phones (or two phone browsers), sign in as Shem and Jean and message each other: messages, a name change, a photo, all live.

**Record:** add a `## LIME-76` entry to `TEND.md`, including the root cause. Commit: `fix: ids without crypto.randomUUID (insecure LAN origin); unique device ids`, trailer `Brief: LIME-76`, plus the attribution trailer. **Push** (the user approved pushing backups). **Stop for the user's check.**

---

### LIME-75 → LANDED as `e56fbf5` and **pushed** (2026-10-01; the first push in a long while, `origin/main` = `e56fbf5`; `PLOT.md` pushed as `c63a4bf`). Plot verified: 0 old-style emails in the seed, and 0 phone matches in history. **The user's gate check is pending** (delete `data/` or reset, then sign in as Shem and Jean). Original brief: every demo email becomes @famkind.com; the two test accounts ARE the demo Shem and Jean

**The user (2026-10-01):** "any emails, make them @famkind.com, because Lime is a FAM project, so that would be jean@famkind.com."

**Survey (plot):**
- **25 seed teachers** have made-up school-style emails (e.g. `grace.o@libertyprep.edu`, `shem.robinson@ps113.edu`), plus one real-looking one (`jean@chungrajoon.com`). They're in `seed-data/teachers.json` and the embedded `public/js/seed-data.js`, and referenced in tests and docs.
- **Collisions:** the LIME-74 test accounts already use `shem@` and `jean@famkind.com` as **separate, extra** profiles. Meanwhile the seed's **Jean Chung** (teacher-001) and **Shem Robinson** (teacher-002, whom the user already renamed "Shem Rajoon" in the app) are clearly the same people.
- **So: merge them.** The test accounts **become** teacher-001 and teacher-002, keeping all their demo history (DMs, groups, threads).

**The change:**
1. **Email scheme:** every seed teacher's email becomes **`<first name, lowercase>@famkind.com`** (e.g. `grace@famkind.com`, `eun@famkind.com`, `jean@famkind.com`, `shem@famkind.com`). Plot checked that the 25 first names are unique; confirm it. Update `seed-data/teachers.json` **and** the embedded seed (regenerated the way it's normally generated, not hand-edited, if a generator exists), the tests, and the **current** docs. **Old `TEND.md` entries stay as history.**
2. **Merge the test accounts into the seed profiles:**
   - **teacher-002:** display name **Shem Rajoon**, `shem@famkind.com`;
   - **teacher-001:** **Jean Chung**, `jean@famkind.com`;
   - keep their existing history and memberships;
   - fill in LIME-74's made-up profile details where the seed is blank.
   - **Remove** the separate test profiles and their extra DM from the dev server's seeding (the seed's own Jean↔Shem DM, conv-001, serves instead).
   - **The gitignored `seed-data/test-accounts.local.json` keeps only what must stay private** (the **phone numbers** and the **password**) and is applied server-side as overrides keyed by email. The committed example file is updated to match (fake values).
3. **The demo password:** **every** seed teacher can sign in with the shared demo password from the local config (unchanged). The two test accounts use their own password from the local file.
4. **Rule (record in `docs/api.md` and `README`):** demo emails are `@famkind.com`, which **could be real mailboxes**. **Local and staging must never send real email or SMS.** Any future invite or notification feature must stub delivery outside production.
5. **Data reset:** after this, `data/` must be re-seeded. The server does it on `/dev/reset` or with a fresh `data/`; tell the user which.

**Scope:** `seed-data/` (`teachers.json`, the example file, the README), `public/js/seed-data.js` (embedded), `server/lib/seed.mjs` (the merge and overrides), `tests/` (email references), current docs (`docs/api.md`, `docs/data-model.md`, `README.md`), and `TEND.md`. **Don't commit any phone number or password**: check `git diff --cached` for the phone digits and the password (read from the local file) before committing, and report "0 matches".

**Verification:** no `.edu`, `.org` or `chungrajoon` emails remain in the seed, tests or current docs (`grep`). Both suites pass (`npm test` and `LIME_TEST_SERVER=dev npm test`). Signing in on the dev server as `shem@famkind.com` (own password) lands as Shem Rajoon **with the demo history**, and the same for Jean. A seed teacher such as `grace@famkind.com` signs in with the demo password.

**Gate:** restart the server (re-seeded). Sign in as `shem@famkind.com` and `jean@famkind.com`: you're the familiar Shem and Jean, with all the existing chats, and every teacher's email ends in @famkind.com.

**Record:** add a `## LIME-75` entry to `TEND.md`. Commit: `chore: demo emails @famkind.com; test accounts merged into seed Shem and Jean`, trailer `Brief: LIME-75`, plus the attribution trailer. **Stop for the user's check.**

---

### LIME-74-redact → `tend` (next, BEFORE any push): rewrite history to remove the test-account details from `7450e93`

**What happened:** plot wrote the two test accounts' **real emails and phone numbers** into `PLOT.md`. Tend committed it unedited as `7450e93` ("chore: update PLOT.md"), followed by `b3f0803` (LIME-74). **Neither is pushed** (`origin/main` = `a7a7fab`, 129 commits behind), so a local rewrite is safe. Plot has already redacted the working-tree `PLOT.md`. `git log -S` found the strings **only in `7450e93`**. The password was never in `PLOT.md`.

**Assumptions:** the agent can run git (including `filter-branch`, or an equivalent non-interactive rewrite) and has the user's approval (given in the prompt). **No push.** Don't use interactive commands (`rebase -i` isn't available).

**The change:**
1. **Commit the current redacted `PLOT.md` first** (`chore: update PLOT.md`), so the working tree is clean.
2. **Rewrite the commits from `7450e93` through `HEAD`** so that **no version of `PLOT.md` in that range** contains the two test emails or the two phone numbers. Tend knows them from the local accounts file (`seed-data/test-accounts.local.json`). **Read them from that file inside the rewrite command; don't type them into any committed file, `TEND.md`, or the report.** Replace each with a neutral placeholder (e.g. `[test account 1 email]`). A tree filter limited to `PLOT.md`, or `git filter-branch --tree-filter` over `7450e93^..HEAD`, is fine. **Keep every commit message, author, date and trailer unchanged.** Only `PLOT.md` content changes.
3. **Verify:** for each of the four strings, `git log --all -S '<string>'` finds **no commit** (search with the values read from the local file; report only "0 matches for 4/4 strings"). `git diff <old HEAD> <new HEAD> -- . ':!PLOT.md'` is **empty** (no other file changed). The commit count is unchanged.
4. **Clean up the backup refs** that `filter-branch` leaves (`refs/original/…`), and expire the reflog for those entries and `gc --prune=now`, so the old objects don't linger. **Report each command run.**

**Scope:** git history only (`PLOT.md` content in that range) plus the new `PLOT.md` commit. **No push.**

**Gate:** none. Tend reports "0 matches" and an empty non-`PLOT.md` diff. **The user decides when to push.**

**Record:** add a `## LIME-74-redact` entry to `TEND.md` (without the strings).

---

### Plot's review of LIME-71 (`docs/api.md`, `46dffb8`), 2026-10-01: APPROVED with amendments

A strong contract: an op log, idempotency, `seq` authority, per-field last-writer-wins, tombstones, `dm_key` dedup with aliases, backfill, transport-neutral realtime, and per-device tokens. Rulings on its open points:
1. **Attachments inside `message.send`: agreed.**
2. **Message time: DECIDED by the user: show the WRITTEN time.**
   - Store **both** `client_ts` (written) and `server_ts` (delivered).
   - **Displayed time = `min(client_ts, server_ts)`** (a wrong clock can never show a future time).
   - **Thread order stays `seq`** (arrival).
   - When written and delivered differ by **more than 5 minutes**, show "Sent 10:05 · delivered 10:35" (the exact copy is tend's call, kept short).
   - Amend section 6 rule 8 and section 3 (`message.send`'s effect) accordingly. **Reason:** in the offline and emergency use case, *when it was written* is the important fact.
3. **Appearance device-local: agreed** (revisit if the user asks).
4. **`POST /events/ticket`: agreed.**
5. **Privacy: DECIDED by the user:**
   - **email** is visible only to people who **share a conversation** with you;
   - **phone is never displayed** to others (unless a later "show my phone" setting is added; not now);
   - **finding people:** the directory matches name and school by partial text, and email or phone **only by exact match**, and **doesn't reveal** the email or phone in results.
   - Read receipts (5b): deferred, since LIME-43 receipts were removed. Note it in the doc.
6. **The directory endpoint is required now:** add `GET /profiles?q=` (q ≥ 2 characters; partial match on display name and school; exact match on email or digits-only phone; returns the public fields under rule 5; capped at 50).
7. Line drift: noted.

**Gaps plot found:**
- **(a) Presence/status** (active, busy, away; `profiles.status` and the presence icons) isn't covered. **Presence is ephemeral**, so it isn't an op: it goes over realtime (`{ type: 'presence', user_id, status }`), with "away" inferred from no connection. Add a short section; LIME-73 may implement a minimal version or defer it (say which).
- **(b) Link previews:** add `GET /link-preview?url=` (a read; the server unfurls; the dev server may return LIME-44's fixtures).
- **(c) Web sign-in persistence:** per-tab `sessionStorage` is right for the dev phase (two-person testing). Note that production web will want an optional persistent sign-in ("keep me signed in") as a later decision.

These amendments go into `docs/api.md` as **Phase 0 of LIME-73**.

### LIME-72 → `tend` (next): commit a test harness into the repo

**Why:** tend's jsdom and Playwright suites lived in session scratchpads and were lost (LIME-69 couldn't re-run them). The coming server work (LIME-73/74) needs regression tests that persist.

**The change:**
1. A `tests/` folder with a `package.json` (devDependencies: `jsdom`, `playwright`) and a README. `node_modules/` is already gitignored. **If installing isn't possible (the network is blocked in the sandbox), use the Playwright and jsdom installs tend already has on this machine (via `NODE_PATH` or a documented path), and report it.** Don't vendor `node_modules`.
2. Suites, each runnable by one command (`npm test` in `tests/`, or `node tests/run.mjs`):
   - **smoke:** the real `index.html` and `auth.html` load in jsdom with zero errors;
   - **css:** the CSS guard (fail on `*/` inside a comment, and report each stylesheet's browser-parsed rule count against a minimum; the cleanup-list item);
   - **auth:** sign up, sign in, wrong password, the seed-teacher hint, sign out (rebuilt from LIME-33's checks);
   - **sync:** two pages in one Playwright context: a live message, and **no lost writes (20 + 20)** (from LIME-69);
   - **toasts:** queue across navigation, max 3, an error stays (from LIME-67).
   Playwright suites use the **installed Firefox** where the browser matters (with the real-default prefs) and start their own `python3 -m http.server` from the repo root.
3. `TEND.md` gets a standing rule: **run `tests/` before every commit that touches `public/`**, and report pass/fail.

**Scope:** `tests/` (new), `.gitignore` if needed, `README.md` (a "Running tests" section), and `TEND.md`. **No app code changes.** If a test exposes a real bug, report it; don't fix it here.

**Verification:** all suites pass on the current `HEAD`. Report the commands and the time each takes.

**Gate:** none for the user (plot reviews the report).

**Record:** add a `## LIME-72` entry to `TEND.md`. Commit: `test: committed regression harness (smoke, css, auth, sync, toasts)`, trailer `Brief: LIME-72`, plus the attribution trailer.

---

### LIME-73 → `tend` (after LIME-72): the dev server implementing `docs/api.md` (plus contract amendments)

**Assumptions:** Node v23, **built-ins only** (`http`, `fs`, `crypto`, `path`, `os`, `url`); no npm runtime dependencies. A dev tool on the local network: **not for the internet.**

**Phase 0: amend `docs/api.md`** per plot's review above (message time, privacy, the directory, presence, link previews, web sign-in persistence). Commit it with this brief.

**Phase 1: the server**, `server/dev-server.mjs`:
- **Static files:** serves the **repo root** (so `/public/…` and `/vendor/…` keep working), no-cache for html/js/css, correct MIME types, and `Range` for media.
- **Binds `0.0.0.0:8000`** and prints the localhost and **LAN** URLs (`…/public/index.html`). If port 8000 is busy, say so clearly.
- **The `/api/v1` endpoints from the amended contract:** auth (signup, signin, refresh, signout; PBKDF2 ≥ 600k; rotating refresh tokens; per-device sessions), `POST /ops` (validation and permission per op, idempotency by `op_id`, `dm_key` dedup with aliases, backfill on `membership.add`), `GET /changes`, `GET /snapshot` (paging may be simple), `POST /files` and `GET /files/:id` (10 MB; authorisation per the contract), `POST /events/ticket` and `GET /events` (SSE), `GET /profiles?q=`, `GET /link-preview` (fixtures), `GET /health`, and dev-only `POST /dev/reset`.
- **Persistence:** under a **gitignored `data/`**: the op log (append-only JSONL), derived state (rebuildable from the log), sessions and files. Atomic writes. Survives restarts. **First run seeds** from `seed-data/` (seed teachers get credentials from the local demo password file if it exists, matching today's demo sign-in; otherwise they can't sign in until reset; document this).
- **Presence:** a minimal version (connected → active; disconnected → away; a `presence` realtime message) **or** defer it, and say which.
- **Server tests** added to `tests/` (an `api` suite): each endpoint, permissions (403s), idempotency (replays), DM dedup and alias, backfill, the changes-feed visibility filter (no per-user rows leaking; email and phone rules), files authorisation, and restart persistence.

**Scope:** `server/` (new), `docs/api.md` (Phase 0), `tests/` (the api suite), `.gitignore` (`data/`), `README.md` (how to run the server and open it on a phone), and `TEND.md`. **The web app is unchanged in this brief** (it still uses `LocalAdapter`). LIME-74 connects it.

**Verification:** the api suite passes; `curl` walk-throughs are recorded in `TEND.md`; the server serves the current app at localhost and the LAN URL unchanged; it restarts with its data intact.

**Gate:** start it with `node server/dev-server.mjs` instead of the Python server. Lime opens and works exactly as before at the printed link. (It doesn't share data yet; that's LIME-74.)

**Record:** add a `## LIME-73` entry to `TEND.md`. Commit: `feat: dev server implementing the v1 API (ops, feed, files, events)`, trailer `Brief: LIME-73`, plus the attribution trailer.

### LIME-74 → `tend` (next): the web app talks to the dev server: everyone shares one Lime, live

**Context:** LIME-72 (`8b2e33b`, tests; **puppeteer-core** driving the installed Firefox and Chrome instead of Playwright, accepted) and LIME-73 (`fc16919`, `server/dev-server.mjs` implementing the amended `docs/api.md`; 86 API checks) landed on 2026-10-01. The web app still uses `LocalAdapter`. This brief connects it.

**Assumptions:** the agent can edit files, run Node, run `tests/` (`npm test`, and `LIME_TEST_SERVER=dev npm test`), drive the real Firefox and Chrome, and commit. Read `docs/api.md` in full first.

**Phase 0: contract and server fixes**
1. **Password change:** add `POST /auth/password` `{ current_password, new_password }` to `docs/api.md` and the server (it verifies, re-hashes, and **revokes the user's other devices' refresh tokens**; the calling device stays signed in). Add api-suite checks.
2. **Security: serve only what the app needs.** The dev server currently serves the whole repo root, so **`public/js/demo-config.local.js` (the demo password) is readable by anyone on the same Wi-Fi** (tend's note). Change static serving to an **allow-list**: `public/**` and `vendor/**` only, **never** `*.local.js`, dotfiles, `data/`, `server/`, `tests/`, `.git/`. The demo password is read **server-side** only (for seeding). Add api-suite checks that those paths return 404.

3. **Two dedicated test accounts (the user, 2026-10-01: "create two test accounts so there is no confusion"):**
   - **Test account 1** ("Shem Rajoon") and **test account 2** ("Jean Chung"): emails, phone numbers and password **only in the gitignored `seed-data/test-accounts.local.json`** (the user gave them in chat on 2026-10-01; plot wrongly copied them here at first, and redacted them on 2026-10-01);
   - **both with the password the user gave** (plot wrote it into the prompt the user pastes, not into this file).
   - **They're real people's emails and phones, and a real password, and the repo has a GitHub remote (`FAMKIND/lime`), so NONE of it goes into committed files.** Put them in a **gitignored** `seed-data/test-accounts.local.json` (**add `*.local.json` to `.gitignore`**, and confirm with `git check-ignore`). The dev server reads it **server-side** on first run and on `/dev/reset`, creating both profiles with server-hashed credentials. Commit only a **`seed-data/test-accounts.example.json`** with obviously fake values and a README line.
   - Make up the rest of their profiles, plausible and teacher-like:
     - Shem Rajoon: Math teacher, PS 113, grades 7–8, he/him, a short bio;
     - Jean Chung: Head of FAM, PS 113, life skills, she/her, a short bio;
     - timezone `America/New_York`.
   - Give them a **ready DM with each other** (no messages yet) and make both members of **PS 113 Staff Room**, so group testing works immediately.
   - The existing seed teachers (including the older "Jean Chung" and "Shem Robinson" demo profiles) stay. **To avoid confusion, the server log line prints the two test emails at startup.**
   - Phone numbers follow the privacy rule: **stored and searchable by exact match, never displayed.**

**Phase 1: the `ApiAdapter`** (`public/js/api-adapter.js`, the same contract `LimeStore` already uses):
1. **Selection:** `store.js` uses the `ApiAdapter` when `GET /api/v1/health` answers on the same origin; otherwise `LocalAdapter` (the Python server and `file://` keep working as the local-only version). Log which one is active in the console.
2. **Auth:** `auth.js`'s signUp, signInWithPassword, signOut, changePassword and changeEmail go through the API (the email change is the `profile.setEmail` op).
   - Access and refresh tokens are kept in **`sessionStorage`** (per tab, as LIME-69 decided); a `device_id` in `localStorage`.
   - Silent refresh when the access token expires.
   - Every existing UX stays: inline errors, the seed-teacher hint, `?from=auth`, toasts and the storage messages (adapted to the server's error codes).
3. **The local store and outbox:** reads stay synchronous from the in-memory cache, persisted per user (IndexedDB or `localStorage`) together with the **cursor** and the **outbox**, so a reload is instant and works offline.
   - **Every `LimeStore` write becomes an op** (the mapping table in `docs/api.md` section 11): apply it optimistically, queue it, flush it to `POST /ops` in order, and retry with the same `op_id`s.
   - **A permanent rejection rolls back and shows an error toast.**
   - Apply feed entries in `seq` order: confirm your own ops, and handle **backfill** and **alias** entries.
4. **Realtime:** `POST /events/ticket`, then `EventSource('/api/v1/events?ticket=…')`. On `changed`, fetch `/changes`. Reconnect with backoff; poll every 30s as a fallback. **Presence:** update the presence icons from realtime `presence` messages.
5. **Files:** uploads go to `POST /files`. **Images can't send a bearer header**, so `getAttachmentUrl` fetches `GET /files/:id` with the token, turns it into a `blob:` URL, and caches it per session. Note signed URLs as the production alternative in `docs/api.md`. This covers attachments, avatars and the photo wall alike.
6. **Product rules from plot's review:**
   - **message time:** show the **written** time (`min(client_ts, server_ts)`); when delivered more than 5 minutes later, show a compact "Sent 10:05 · delivered 10:35" (tend's exact copy, kept short);
   - **privacy:** the UI handles **missing email** (not a chat-mate) and **never shows phone numbers**;
   - **the New message picker** uses `GET /profiles?q=` once 2 characters are typed (partial name or school; exact email or phone, never revealing them), and shows the people you already chat with when empty;
   - **link previews** come from `GET /link-preview`.
7. **Reset demo data** (local dev only) calls `POST /dev/reset`. **Every** connected client gets `410 cursor_expired` and goes to sign-in with the "Demo data was reset" toast.
8. **LIME-69's cross-tab `storage` sync** stays only for `LocalAdapter`. With the `ApiAdapter`, tabs sync through the server.
9. **Remove `demo-config.local.js` from the HTML** when the `ApiAdapter` is active (the server verifies demo passwords), keeping it for the `LocalAdapter` fallback.

**Scope:**
- **May touch:** `public/js/` (new `api-adapter.js`; `store.js`, `auth.js`, `app.js` where needed), `public/index.html` and `auth.html` (script tags), `server/` (Phase 0), `docs/api.md` and `docs/data-model.md`, `tests/` (new suites), and `TEND.md`.
- **May not touch:** the visual design, Communities, and `vendor/`.
- If a decision isn't covered by the contract or this brief, **stop and ask the user.**

**Verification:**
- **All existing suites** pass under both `npm test` (the Python / `LocalAdapter` fallback) **and** `LIME_TEST_SERVER=dev npm test`.
- **A new `e2e-server` suite** against the dev server, in the **real Firefox (a normal and a private window) and Chrome**, as three different users:
  - a DM and a group message live;
  - a thread reply;
  - a reaction;
  - rename, add member and delete;
  - a name and photo change propagating;
  - an attachment visible to members and **403 for a non-member**;
  - per-user star and archive not leaking;
  - DM dedup when two users create the same DM at once (one conversation);
  - **offline:** stop the server, send messages in one client, restart → they deliver in order, and a gap over 5 minutes shows "delivered" (simulate the clock);
  - no lost writes (20 + 20 across two browsers);
  - Reset → everyone goes to sign-in.
- The demo password file returns 404 over the LAN URL.
- **Manual phone check, for the user:** give the exact LAN URL and steps.
- Zero console errors.

**Gate:** start `node server/dev-server.mjs`. Open the printed link in Firefox, a **private window** and Chrome, and the network link **on your phone**. Sign in as the **two test accounts** (their emails print at server startup) and chat: everyone sees everything live, including photos and name changes. Stop the server for a minute, send a message, start it again: it arrives.

**Record:** add a `## LIME-74` entry to `TEND.md`. Commit (Phase 0 may be a separate commit, each with the trailer): `feat: web ApiAdapter: shared live Lime via the dev server`, trailer `Brief: LIME-74`, plus the attribution trailer. **Stop for the user's check.**

---

### LIME-69 → `tend` (next): two people in two tabs, live

**The user (2026-10-01): chose "A, then B"** for real two-person testing (see the open decision "real two-person testing"). This is A.

**Goal:** in **one normal browser window**, tab 1 is signed in as one person and tab 2 as another. Everything one does (messages, replies, reactions, reads/unread, star/rename/archive/delete, new chats and groups, members added, profile and photo changes) **appears in the other tab within ~1s, without a reload**, and **nothing is ever lost** when both write.

**Survey (plot, 2026-10-01):**
- The session is `localStorage['lime-demo-session']` (`auth.js` ~13), shared by every tab.
- State is one snapshot, `localStorage['lime-state-v1']` (`local-adapter.js` ~9), written whole by `store.js` `scheduleSave()` (~64, a 100ms debounce) plus `flush()`.
- Attachments are in IndexedDB (shared by tabs already).
- There's no `storage` listener or BroadcastChannel.
- The UI already re-renders on store events (e.g. `lime:conversations-changed`, `lime:profile-changed`).

**Assumptions:** the agent can edit files, run jsdom and Playwright, drive the real Firefox and Chrome with **two tabs in one context** (a shared storage partition), and commit. Preview: `http://localhost:8000/public/…`.

**The change:**
1. **A session per tab:** move the session to **`sessionStorage`** (per tab). New tabs and windows start signed out (the gate sends them to `auth.html`). A **duplicated** tab keeps its session (the browser copies `sessionStorage`; that's fine). Sign-out clears only that tab. Keep `?from=auth`, the gate reasons and the toasts working. **Reset demo data** still wipes the shared data and signs out the current tab; other tabs notice (item 3) and go to `auth.html`, with a toast queued for them ("Demo data was reset").
2. **No lost writes: merge-by-id on save.** Before writing the snapshot, **re-read** the latest stored snapshot and **merge** it with this tab's changes:
   - rows by `id`, newer `updated_at`/`created_at` wins per row;
   - messages, attachments, memberships and reactions are **union by id** (append-only; deletes as tombstones or `deleted_at` where the model already has them; **don't** resurrect a row another tab deleted);
   - per-user fields (`last_read_at`, `starred`, `cleared_at`) only ever change for that membership's own user.
   - Document the merge rules in `docs/data-model.md` as **the local stand-in for server-side writes**. Keep `flush()` semantics.
3. **Live updates:** listen for the **`storage` event** on `lime-state-v1` (it fires in *other* tabs) and/or a `BroadcastChannel('lime')` ping after every save. On a change: reload the snapshot into the store, then **emit the existing change events**, so every view updates (the list, the open thread and reply panel, Recent and unread, headers and members, the details panel, avatars and profile names). **Keep the user's place:** scroll position, the open conversation, the composer draft, open menus and modals untouched. If the open conversation was deleted or the user was removed from it, go to the default view and show a toast ("This chat is no longer available").
4. **New-message cues for the other person:** an incoming message in another conversation bumps it to the top with unread (as on load). In the open conversation it appears at the bottom, using the existing stick-to-bottom behaviour. **No sound and no system notification** (that's the separate "real notifications" item).
5. **Profile changes propagate:** a display name or photo change in tab 1 updates tab 2's avatars and names everywhere (the existing `repaintAvatar` / `updateProfileEverywhere`).

**Scope:**
- **May touch:** `public/js/auth.js` (session storage), `public/js/store.js` (reload, merge-on-save, events), `public/js/local-adapter.js` (snapshot read and write helpers), `public/js/app.js` (listening, re-render, keeping the user's place), `auth.html`/`index.html` gate bits if needed, `docs/data-model.md`, and `TEND.md`.
- **May not touch:** the visual design, Communities, and the adapter seam's public contract (additions are OK, documented).
- If a decision isn't covered here, stop and ask the user.

**Verification (two tabs, one context, in the real Firefox **and** Chrome):**
- Tab A = Shem, tab B = Jean (a seed or a new account). Script: A sends a DM to B → B sees it live in the list and in the thread. B replies in a thread → A sees the reply count and the panel live. Reactions both ways. A renames a shared group → B's header and list update. A adds B to a group → it appears for B. B changes their name and photo → A's avatars and names update. Star and archive are per-user (not mirrored to the other person). Read state: B opening the chat clears B's unread only.
- **The no-lost-writes test:** both tabs send 20 messages each, interleaved as fast as possible. All 40 exist in both tabs afterwards, in order.
- Reset demo data in A → B goes to sign-in with a toast.
- A new tab starts signed out. Sign-out in A doesn't sign out B.
- Report the measured live-update latency. Zero console errors. jsdom suites still pass.

**Gate:** open Lime in **two tabs of the same normal window** (not a private window). Sign in as yourself in one and as another teacher in the other. Message back and forth: each message appears in the other tab within a second. Change your name or photo, and the other tab updates.

**Record:** add a `## LIME-69` entry to `TEND.md`, including the merge rules. Commit: `feat: per-tab sessions, live cross-tab sync, merge-on-save`, trailer `Brief: LIME-69`, plus the attribution trailer. **Stop for the user's check.**

---

### LIME-71 → `tend` (after LIME-69's check; docs only, no code): the client API and sync contract (web, iOS, Android, offline)

**The user (2026-10-01):** "when we get to the small test server, keep in mind that we want this to be an iOS and Android app in the near future, so let's plan our infrastructure with that in mind." **This supersedes LIME-70's snapshot design** (LIME-70 below is kept for history, never sent). Same pattern as LIME-24a: **write the contract first, review it, then build.**

**Why the design changes (plot):** LIME-70 synced the **whole snapshot** over `/api/state`. That's web-specific and doesn't scale to mobile clients that work **offline** and later relay over **Bluetooth** ([[lime-offline-differentiator]]). Mobile and offline-first clients need:
- an **operation log**: each change is a small, self-contained, idempotent operation with a **client-generated id**;
- an **incremental changes feed** (everything since a cursor);
- **token auth**, not browser session storage;
- **files by id**;
- **realtime** that also works on phones;
- **a hook for push notifications** later.

Designed this way, the same protocol serves the web app now, native apps next, and the mesh later: ops can be carried peer-to-peer and merged by id. It also maps onto a production backend (an `ops` table + RLS + realtime on Supabase, or a custom server) without choosing one yet.

**Assumptions:** docs only. The agent reads `public/js/store.js` (the write functions: `sendMessage` ~521, `toggleReaction` ~591, `createConversation` ~610, `addMembers` ~653, `renameConversation` ~680, `setStarred` ~690, `setArchived` ~699, `deleteConversation` ~708, `deleteForMe` ~721, `markRead` ~730, `updateProfile` ~746, `setAppearance` ~769, `setProfileEmail` ~780, `createProfile` ~800, and attachments), `docs/data-model.md`, `docs/schema.sql`, and **LIME-69's merge rules** (`TEND.md`).

**Write `docs/api.md` (new), covering:**
1. **Principles:**
   - one versioned HTTP+JSON API (`/api/v1`) for every client;
   - the server is the authority for ordering;
   - clients are **local-first** (a local store plus an **outbox** of ops);
   - **every write is an op**;
   - reads come from the local store, kept current by the changes feed.
2. **The op envelope:** `op_id` (UUIDv7, client-made, the idempotency key), `type`, `actor_id`, `device_id`, `client_ts`, `payload`; the server adds `seq` (a monotonic integer) and `server_ts`. Replaying the same `op_id` is a no-op.
3. **The op catalogue:** one op per store write listed above (e.g. `message.send`, `reaction.toggle`, `conversation.create`, `conversation.rename`, `membership.add`, `membership.setStarred`, `membership.setArchived`, `membership.markRead`, `conversation.delete`, `conversation.deleteForMe`, `profile.update`, `profile.setEmail`, `attachment.attach`), with payload fields and **who may perform it** (mirroring `canReason` / the RLS draft).
   - **Per-user ops** (star, archive, read, `deleteForMe`, appearance) affect only the actor.
   - **Appearance stays device-local** (not synced) unless the user decides otherwise. Flag it.
4. **Conflict rules (they must cover what LIME-69 `3bb437b` found):** **DMs are deduplicated by `dm_key`** (two clients creating the same DM at once must converge on one conversation: the server keeps the first and maps the second's later ops onto it; LIME-69's local merge can create two). Reactions use a `removed_at` tombstone, and memberships carry `updated_at` (as LIME-69 introduced). Messages, attachments and reactions are append-only/union; deletes are **tombstones** (never resurrected); scalar fields are **last-writer-wins by server `seq`**; membership rows are per user. This must match LIME-69's local merge rules exactly. List any differences.
5. **Endpoints:**
   - `POST /auth/signup`, `POST /auth/signin` (the server verifies; it returns an **access token** and a **refresh token**), `POST /auth/refresh`, `POST /auth/signout`;
   - `POST /ops` (a batch, idempotent; returns the assigned `seq`s or per-op errors);
   - `GET /changes?since=<seq>&limit=` (ops the caller is allowed to see, in order, plus `next` and `has_more`);
   - `GET /snapshot` (a cold-start bootstrap scoped to the caller, plus its `seq`);
   - `POST /files` (multipart → `file_id`, `size`, `mime`) and `GET /files/:id` (an authorised download);
   - `GET /events` (realtime: **Server-Sent Events** for web; note that native clients may prefer WebSocket, so define the message format to be transport-neutral, `{ type: 'changed', seq }`);
   - `GET /health`.
6. **Auth model:** bearer tokens (short-lived access + a refresh); per-device sessions (`device_id`). Passwords are verified **on the server** (PBKDF2 or better; production uses the backend's auth). Web stores tokens in `sessionStorage` (per tab, matching LIME-69); **iOS uses the Keychain, Android the Keystore** (note only).
7. **Visibility:** which ops a user receives through `/changes` (conversations they're a member of; their own profile and per-user rows; others' **public** profile fields), matching the RLS draft.
8. **Offline and mesh notes (forward-looking, no design commitment):** the outbox and retry, ordering by `seq` after sync, and **ops as the unit for Bluetooth relay** later. Note the open questions: op signing (authenticity when relayed by a peer), end-to-end encryption, and dedup by `op_id`. **Flag these as a future planning pass.**
9. **Push notifications (later):** where APNs/FCM hook in (the server emits on `message.send` to members not currently connected). Note only.
10. **Mapping table:** each op → today's `store.js` function → `docs/schema.sql` tables touched → the RLS policy.
11. **Errors:** `{ error: { code, message } }`, standard codes, and per-op errors in a batch.

**Also:** a short **"Mobile client options"** note listing the choices the user will face later (fully native Swift/Kotlin; React Native/Expo; Capacitor wrapping the web app), with one line each on how Bluetooth mesh affects them (all need native Bluetooth modules). **Don't recommend one.** That's a future decision surface.

**Scope:** `docs/api.md` (new), a pointer from `docs/data-model.md`, and `TEND.md`. **No code.**

**Verification:** every store write function is mapped to an op (report the table); every op has a permission rule; the conflict rules match LIME-69's (diff them); there are no undefined terms. Plot reviews the doc before LIME-72 is drafted.

**Gate:** none needed from the user beyond "ok". **Plot reviews it** (as with LIME-24a).

**Record:** add a `## LIME-71` entry to `TEND.md`. Commit: `docs: client API and sync contract (web, mobile, offline)`, trailer `Brief: LIME-71`, plus the attribution trailer. **Stop.**

**Next (drafted after plot's review): LIME-72**, the dev server implementing `docs/api.md` (Node built-ins only, binding `0.0.0.0`, a LAN URL for phones, the op log persisted under a gitignored `data/`, files, SSE), plus a web `ApiAdapter` that turns store writes into ops with an outbox, with the local adapter kept as a fallback. It reuses LIME-70's practical details (serving the repo root, the printed URLs, the README, the reset endpoint), with the snapshot API replaced by the op log.

---

### LIME-70 → SUPERSEDED (never sent) by LIME-71/72 (the user's mobile-first direction, 2026-10-01). Kept for history: a local dev server so phones and other browsers share the same Lime

**The user (2026-10-01): "A, then B".** This is B: shared state across **any** browser, private windows and **phones on the same Wi-Fi**.

**Assumptions:** Node **v23** is installed (plot checked); there's **no npm dependency** (Node built-ins only: `http`, `fs`, `crypto`, `path`, `os`). The agent can run Node, edit files, drive the real browsers, and commit. **This is a dev tool: no internet exposure, and no production security claims.**

**Plot's design (the user can overrule at the gate):**
1. **`server/dev-server.mjs`** (new, run with `node server/dev-server.mjs`) replaces `python3 -m http.server`:
   - serves the **repo root** statically (so `/public/…` and `../vendor/…` keep working), with correct MIME types and no caching for `.js`/`.css`/`.html`;
   - **binds `0.0.0.0:8000`** and prints both `http://localhost:8000/public/index.html` and the **LAN URL** (`http://<Mac's IP>:8000/public/index.html`) for the phone;
   - **a shared state API:** `GET /api/state` returns the snapshot plus a version. `POST /api/ops` applies a batch of **operations** (or a snapshot diff) using **the same merge-by-id rules as LIME-69**, server-side, then bumps the version;
   - **live updates:** `GET /api/events` (Server-Sent Events) sends a `changed` event with the new version after every write;
   - **files:** `POST /api/files` stores uploads under `data/uploads/` and `GET /api/files/<path>` serves them (the attachment, avatar and pattern blobs);
   - **persistence:** `data/lime-dev.json`, written atomically (a temp file, then rename). **`data/` is gitignored.** It's seeded from `seed-data/` on first run. `POST /api/reset` restores the seed (the Reset demo data item calls it);
   - **credentials** live in the shared state like today (hashes only; verification can stay in the browser for this dev tool; document that **production verifies on the server**, per the switch checklist).
2. **`ServerAdapter`** (`public/js/server-adapter.js`) implements the **same contract** as `LocalAdapter` (state load and save through `/api/…`, attachments through `/api/files`, link previews as local fixtures). `store.js` picks it **automatically when `/api/health` answers** (served by the dev server); otherwise it falls back to `LocalAdapter` (`python3 -m http.server` or `file://` keep working as before). Show a small dev-only indicator? **No:** keep the UI unchanged; log which adapter is active in the console.
3. **Sessions:** per tab (`sessionStorage`, from LIME-69), on each device.
4. **Live updates** go through the SSE `changed` event → refetch → the same reload-and-emit path LIME-69 built, so the UI work is shared.
5. **A README section:** how to start it, how to open it on a phone, and how to reset the data. Update the `lime-preview-url` guidance in `TEND.md`: **the dev server is the default preview from now on.**

**Scope:**
- **May touch:** `server/` (new), `public/js/server-adapter.js` (new), `public/js/store.js` (adapter selection), `public/index.html`/`auth.html` (script tags), `.gitignore` (`data/`), `README.md`, `docs/data-model.md`, and `TEND.md`.
- **May not touch:** the UI, `LocalAdapter`'s behaviour, and anything in `vendor/`.

**Verification:**
- Start the server; both URLs print.
- The real Firefox (normal **and** private window) and Chrome: three sessions as three users. A message, reply, reaction, rename, member add and profile/photo change made in any one appears live in the others. Attachments uploaded in one display in the others.
- **The phone check is manual:** give the user the LAN URL and the steps.
- The concurrent-write test (as in LIME-69, across two browsers): nothing is lost.
- Restart the server: the data persists. Reset demo data restores the seed for everyone.
- Opened via `python3 -m http.server` instead, the app still works as the local-only version.
- Zero console errors. jsdom suites pass.

**Gate:** stop the old Python server and start the new one with `node server/dev-server.mjs`. Open the localhost link in Firefox, a private window and Chrome (and the network link on your phone), sign in as different teachers, and chat. Everyone sees everything live.

**Record:** add a `## LIME-70` entry to `TEND.md`. Commit: `feat: local dev server with shared state, files and live updates`, trailer `Brief: LIME-70`, plus the attribution trailer. **Stop for the user's check.**

---

### LIME-67 → `tend` (next): toasts redesigned for Lime: title, body, an action, and cross-page messages

**The user (2026-10-01, a Claude toast as reference):** "our toast notifications like this one. We have some toasts in Seed, but they will need to be refined to fit Lime's aesthetic. Then we can apply toasts to changes we make: when you sign in, sign out, make a change, etc., areas where communication will help with recognition of system status."

**The reference:** a white card with a soft shadow, a thin outline and large rounded corners. It has an **info icon** at the left, a **bold title** ("Your Max plan is active"), a **body line**, and an **outlined action button** ("View billing") under the text. A **×** sits at the top right. Neutral colours throughout.

**Survey:**
- LIME-27's `showToast(message, { tone, duration })` (`app.js` ~281–303) renders Seed's `seed-toast` markup (title only) into `#toast-container` (`index.html` ~903, `bottom-center`, the container itself `role="status"`).
- Hover pauses it, but mouseleave restarts the timer at only **1s**.
- `auth.html` has **no** toast container.
- There are 4 call sites (2× "Link copied", "That chat isn't available to you.", and one other).
- Seed's `toast.css` provides the container positions and base styles.

**Plot's design decisions (the user can overrule at the gate):**
- **Position:** **bottom-right** on desktop (24px from the edges, so it never covers the composer or Send, which bottom-centre risks). On ≤ 767px, **top-centre** under the header.
- **Look, matching the menus (LIME-21b/63):**
  - `--soil-bg-elevated`, `1px solid --soil-border-subtle`, `--seed-radius-lg`, `--seed-shadow-md`;
  - width `min(380px, 100vw − 32px)`, padding ~16px 20px;
  - a 20px leading icon. **Only the icon carries the tone colour** (info is muted ink; success, warning and error use the good/warn/bad icon tokens). The card stays neutral, per the lime rule;
  - **title:** semibold, ink, ~15px. **Body:** regular, ink (or muted if contrast allows ≥ 4.5:1), ~14px, wrapping;
  - **an optional action:** Seed's **secondary outline small** button under the body (not pale lime: toasts are never the primary action);
  - **×:** a neutral icon button at the top right.
- **Behaviour:**
  - default **5s**; **8s** with an action; **error toasts stay until dismissed**;
  - **hover or keyboard focus inside pauses**, and leaving **resumes the remaining time** (not 1s);
  - at most **3** visible, with the newest nearest the corner; older ones leave first;
  - entry and exit: a short slide and fade (~150ms), **fade only under reduced motion**.
- **Accessibility:**
  - the container is `role="region"` `aria-label="Notifications"`;
  - each toast is `role="status"` (polite), or `role="alert"` for errors;
  - toasts never steal focus. With focus inside one, Escape dismisses it. The action and × are keyboard-reachable.

**The change:**
1. Move the toast system into **`public/js/toast.js`** (loaded by `index.html` **and** `auth.html`, each with its own container), exposing:
   - `LimeToast.show({ title, body, tone: 'info'|'success'|'warning'|'error', action: { label, onClick }, duration })`;
   - **keep `showToast(message, options)` working** as a thin wrapper, so existing calls don't break.
2. **Cross-page messages:** `LimeToast.queue({...})` stores a toast in `sessionStorage` (`lime-flash-toasts`) **before a navigation**. Every page shows and clears queued toasts on load. (This lets "Signed out" appear on the auth page and "Welcome back" on the app.)
3. Restyle in **`public/css/lime.css`** (auth loads it; confirm), building on Seed's `toast.css`. Don't edit `vendor/`.
4. Migrate the 4 existing calls: "Link copied" becomes a success with a title only; "That chat isn't available to you" becomes a warning with the title "Chat not available" and the body "You're not a member of that chat."
5. Write a short **usage note** in `docs/` (or the top of `toast.js`): when to toast and when not to (the rules in LIME-68).

**Scope:** `public/js/toast.js` (new), `public/js/app.js` (wrapper and migration), `public/index.html` and `public/auth.html` (container and script tag), `public/css/lime.css`, `docs/` (the note), and `TEND.md`.

**Verification:**
- A **demo sheet** (in the scratchpad, using the real CSS and JS) of: info, success, warning and error; title only; title + body; with an action; a long body wrapping; 3 stacked. In light and dark, at desktop and mobile.
- Timing: pause on hover and focus, resume with the remaining time, errors persist, max 3.
- A queued toast survives a navigation (index → auth and auth → index).
- Screen-reader roles in the DOM. Reduced motion.
- In the real Firefox and Chrome. The real app and `auth.html` load in jsdom with zero errors. Report the CSS rule counts.

**Gate:** copy a chat link: a clean white card at the bottom-right says "Link copied", with a check icon and a ×, and it fades after a few seconds (it stays while you hover over it).

**Record:** add a `## LIME-67` entry to `TEND.md`. Commit: `feat: Lime toasts (title, body, action, cross-page)`, trailer `Brief: LIME-67`, plus the attribution trailer.

---

### LIME-68 → `tend` (after LIME-67): toasts for system status across the app

**The user (2026-10-01):** apply toasts "when you sign in, sign out, make a change, etc., areas where communication will help with recognition of system status."

**The rules (also go in LIME-67's usage note):**
- **Toast** when an outcome **happened somewhere you're not looking**, **can't otherwise be seen**, is **irreversible**, **can be undone**, or **failed**.
- **Don't toast** what the screen already shows clearly: sending a message, reactions, opening panels, live appearance changes, typing, selecting chats.
- **Form validation errors stay inline**, not as toasts.
- Keep copy short. Plain words. No exclamation marks.

**Where (find each call site; `app.js` lines are from plot's survey):**

| Event | Toast |
|---|---|
| **Sign up** → app | success, "Welcome to Lime, {first name}", body "Your account is ready." Action: **"Edit profile"** (opens Settings → Profile). Queued across the redirect. |
| **Sign in** → app | info, "Signed in as {display name}". Queued. |
| **Sign out** → auth | info, "You've signed out". Queued. |
| **Reset demo data** → auth | info, "Demo data reset", body "All accounts and changes were cleared." Queued. |
| **Profile saved** (~5439) | success, "Profile updated" |
| **Email changed** (~5499) | success, "Email updated" |
| **Password changed** (~5523) | success, "Password changed" |
| **Star / unstar** (~3464) | success, "Starred" / "Removed from Starred" (3s) |
| **Rename** (~2481) | success, "Renamed to “{name}”" |
| **Archive** | success, "Chat archived". Action: **"Undo"** (restores it through the existing unarchive path, then shows "Chat restored"). |
| **Unarchive / restore** | success, "Chat restored" |
| **Delete** (~3523) | success, "Chat deleted" |
| **Delete for me (DM)** (~3511) | success, "Chat removed for you" |
| **Add members** (Share, ~3378) | success, "Added {name} to {group}" |
| **New group created** (New message) | success, "Group created" (only for groups; a DM opening is visible on its own) |
| **Attachment upload fails** | error, "Couldn't attach {file name}", with the existing reason as the body |
| **Saving fails / session-only storage** (any `LimeStore` write rejecting, or the private-browsing fallback) | warning, "Changes may not be saved", body "Lime couldn't save to this browser." **Once per session.** |
| **Link copied / chat not available** | from LIME-67 |

If an event above doesn't exist in the app (e.g. there's no unarchive path or no leave-group), **skip it and list it.** **Don't add features.** If the survey finds other clearly status-worthy outcomes, **list them in `TEND.md` without implementing them**, for the user to choose.

**Scope:** call sites in `public/js/app.js`, `public/auth.html`'s inline script (queueing on sign-out and showing queued toasts), `public/js/auth.js` only if the queueing belongs there, and `TEND.md`.

**Verification:**
- Trigger each event in the real app (jsdom for the logic; Playwright for screenshots of a representative half). Report a table of event → toast seen (yes/no), with title and tone.
- **Archive → Undo** restores the chat to its previous section.
- The cross-page toasts appear after the navigations.
- No toast fires for the "don't toast" list (spot-check sending, reacting, and an appearance change).
- In the real Firefox and Chrome. Zero console errors.

**Gate:** sign out and back in, change your profile, star, rename, archive (try Undo) and delete a chat: each gives a short, calm confirmation at the bottom-right. Sending messages doesn't.

**Record:** add a `## LIME-68` entry to `TEND.md`, including the event table. Commit: `feat: toasts for system status (auth, settings, chat actions, failures)`, trailer `Brief: LIME-68`, plus the attribution trailer. **Stop for the user's check.**

---

### LIME-65 → `tend` (next): the slideshow's "all photos" grid button sits next to the counter

**The user (2026-10-01):** "the gallery grid icon should be moved next to the slideshow number 4/6."

**Survey:** the grid button is `#lightbox-back` ("Back to all photos", added by LIME-62), and the counter is `#lightbox-counter` (`index.html` ~860–872).

**The change:**
- Place the grid button **immediately beside the counter**, to its right, in one small pill-shaped group: the same height, centred under the photo as the counter is today, with a ~6px gap.
- The grid icon size matches the counter's text cap height optically. It's a neutral, round hover target ≥ 24px, keeping its label and keyboard access.
- It shows **only when the slides were opened from (or can open) the wall** (albums with a wall), as today. When it's hidden, the counter stays centred alone.
- Both still follow the photo's position (LIME-62's rect-based placement) if the counter does.

**Scope:** the lightbox markup and CSS (and positioning JS if the counter is positioned in JS), and `TEND.md`.

**Verification:** screenshots of the slides from the wall (counter + grid) and from a single photo (counter alone), at 1567px and on mobile. Clicking the grid button opens the wall. Run in the real Firefox and Chrome; the real app loads in jsdom with zero errors; report the CSS rule counts.

**Gate:** in a slideshow opened from an album, the small grid button sits right beside "4/6".

**Record:** add a `## LIME-65` entry to `TEND.md`. Commit: `fix: gallery grid button beside the slide counter`, trailer `Brief: LIME-65`, plus the attribution trailer.

---

### LIME-66 → `tend` (BLOCKED until the new dew icons reach Seed): new dew icons: paint brush for Appearance; link-simple and code in both composers

**The user (2026-10-01):** "I added a few [icons] to dew. Let's pull them and update the palette icon to the paint as well. Also update the link to simple link and code icons in the chat box main and reply."

**Where the icons actually are (plot's survey, 2026-10-01):**
- `~/Sites/dew` has `code`, `link-simple`, `paint-brush-broad` and `palette` built into `dist/dew.css` and `src/icons/`. That's dew's brief **DEW-01**, done in the working tree but **uncommitted and unpushed** (dew `HEAD` = `origin/main` = `b71327e`).
- **Lime gets dew through two submodules:** `lime/vendor/seed` (→ `FAMKIND/seed`), which itself has `icons/dew` (→ `FAMKIND/dew`, pinned at `b71327e`). Lime's vendored `dew.css` has none of the new classes.
- **The chain:**
  1. dew commits and pushes;
  2. Seed bumps its `icons/dew` submodule, then commits and pushes;
  3. Lime bumps `vendor/seed`.

  Steps 1–2 belong to the dew and Seed sessions, not Lime's.

**Precondition (Phase 1 checks it first; if any fails, STOP and tell the user):**
1. `git -C vendor/seed fetch` shows a Seed commit whose `icons/dew` includes `dew-paint-brush-broad`, `dew-link-simple` and `dew-code`.
2. **The diff between Lime's current Seed commit (`2bc0868`) and that commit contains only the dew bump** (or only changes the user knows about). List anything else and stop if it's more than the dew bump.

**The change:**
1. Bump `vendor/seed` to that commit and run `git submodule update --init --recursive`. Confirm the three classes exist in `vendor/seed/icons/dew/dist/dew.css`.
2. **Appearance button** (thread header, `#appearance-toggle`, `index.html` ~281): replace the hand-drawn palette `<svg class="lime-appearance-icon">` with `<span class="dew dew-paint-brush-broad">`. Remove the now-unused `.lime-appearance-icon` CSS. The size matches the header standard (LIME-59-fix: the left toggle's visible size). Measure it.
3. **Both composers** (main ~518/526 and reply ~679/687, the toolbar buttons **and** their overflow-menu items):
   - the **link** buttons → `dew-link-simple`;
   - the **code** buttons (currently a text `</>`) → `dew-code`.
   - Sizes match the neighbouring formatting buttons (B, I, U, S). Measure them.
   - Leave other `dew-link` uses (e.g. Share's Copy link) as they are, unless the user says otherwise.
4. Check the Share icon (LIME-59's hand-drawn SVG) against dew. If dew now ships a share icon, **report it; don't swap.**

**Scope:** `vendor/seed` (the submodule pointer only), `public/index.html` (those icons), `public/css/lime.css` (removing `.lime-appearance-icon` and any size tweaks), and `TEND.md`. **Don't edit anything inside `vendor/`.**

**Verification:**
- The submodule commits before and after, and the Seed diff summary.
- Screenshots of the header (paint brush beside Share and "…") and both composers' toolbars (expanded and overflow), with the measured icon sizes.
- Run in the real Firefox and Chrome. The real app loads in jsdom with zero errors. Report the CSS rule counts.

**Gate:** the Appearance button shows the paint brush, and both chat boxes use the new simple link and code icons.

**Record:** add a `## LIME-66` entry to `TEND.md`. Commit: `chore: bump seed (new dew icons); paint brush, link-simple, code icons`, trailer `Brief: LIME-66`, plus the attribution trailer. **Stop for the user's check.**

---

### LIME-64 → `tend` (after LIME-63): the person panel's back arrow moves up into the panel header row

**The user (2026-10-01, screenshot):** in a group chat, clicking the member avatars opens the right panel (Members). Clicking a member shows their details, **but the back arrow sits on its own line below the header**. "The back arrow needs to be on the same line as the close toggle," i.e. **in the right panel's header row**, at the panel's left side, with the panel toggle staying at the right.

**Survey:**
- The back button is `.lime-profile__back` (rendered in the details HTML, `app.js` ~3778, "Back to Members").
- The right panel's header row holds the toggle `#right-panel-toggle` (`.lime-panel-close`, absolutely positioned top-right, `lime.css`).
- The Thread and Members views show a title ("Thread", the group name) in that same row.

**The change:**
1. When the details view is reached **from Members**, the back arrow renders **in the header row**, left-aligned with the panel's content padding and vertically centred with the toggle and the other panels' titles (the same row height as the Thread/Members header). There's no extra row, and the details content moves up accordingly.
2. Keep its behaviour, label and keyboard focus ("Back to Members"). When details are opened **directly** (e.g. a DM's profile, or from a message sender), there's **no back arrow**, as today.
3. Check the mobile layout (the panel as a full-screen view) too: the arrow stays in the header row there.

**Scope:** the details-panel header markup in `app.js`, its CSS in `lime.css`, and `TEND.md`. Nothing else.

**Verification:** screenshots of Members → a member's details at 1567px and on mobile. The measured vertical centres of the back arrow and toggle (±1px), and the back arrow's left edge against the content's left edge. Back returns to Members; the direct-open view has no arrow. The real app loads in jsdom with zero errors. Report the CSS rule counts.

**Gate:** from a group's Members panel, open someone's details. The back arrow sits at the top-left of the panel, on the same line as the panel toggle, and the details move up.

**Record:** add a `## LIME-64` entry to `TEND.md`. Commit: `fix: details back arrow in the panel header row`, trailer `Brief: LIME-64`, plus the attribution trailer. **Stop for the user's check.**

---

### LIME-62 → `tend` (after LIME-57-fixf): the media viewer: × at the photo's corner, a 3-column wall, and slides that replace the wall

**The user's QA (2026-09-30, screenshots):**
1. "The close button on the image slideshow needs to be aligned to the top-right corner of the photo." In their reference, the round white × sits **just outside the photo's top-right corner, diagonally**: its centre is ~28px right of and ~30px above the corner. (This supersedes LIME-40-fix's "close in a bar outside the image".)
2. "The media gallery: make it 3 columns, with more spacing around the wall."
3. "When someone clicks an image you shouldn't see the wall any more; it should be the regular slides with the arrows on the left and right. You should only see the grid when you click the +N tile or the 'N photos' link in the chat."

**Survey:**
- The lightbox is `openLightbox(images, index, options)` (`app.js` ~4773), with `.lime-lightbox__close` (~2734–2790 in `lime.css`).
- The wall is `openPhotoWall(messageId)` (~4786), a CSS-columns masonry (`.lime-photo-wall__masonry`: `column-count` 2 / 3 at a breakpoint / 5 wide, `column-gap: --seed-space-2`, padding `space-8 space-6`).
- A wall tile click calls `openLightbox(..., { fromWall: true })` (~4845–4850), which currently shows the slides **over** the still-visible wall.

**The change:**
1. **The ×:** positioned **relative to the displayed image's actual rect** (recomputed on open, on slide change and on resize), with its centre at the image's top-right corner + (≈ 28px, −30px). It's **clamped inside the viewport** (≥ 12px from any edge) when the image is near an edge. It stays a round, high-contrast button, keyboard-focusable, with Escape still closing.
2. **The wall:** **3 columns** at desktop widths (2 below 768px, 1 below 480px), with **`column-gap` and tile spacing ≈ `--seed-space-4` (16px)** and **more padding around the wall** (≈ `--seed-space-12` on desktop, scaled down on mobile). Keep the masonry (natural aspect ratios).
3. **Slides replace the wall:** clicking a wall tile **hides the wall completely** and shows the regular slides (arrows left and right, the counter, ×) on the normal lightbox backdrop. **Closing the slides (× or Escape) returns to the wall** at the same scroll position, since that's where the user came from. Closing the wall returns to the chat.
4. **Entry points:** the wall opens **only** from the album's "+N" tile and the "N photos" link. Clicking any other album tile opens the slides directly at that photo (it does today; confirm). Report each entry point's behaviour.

**Scope:** the lightbox and photo-wall code in `public/js/app.js`, their CSS in `public/css/lime.css`, and `TEND.md`. Not attachments, uploads, or the album grid in the chat.

**Verification:**
- The × position measured against the image rect at 3 viewport sizes and for a portrait, a landscape and a small image.
- Screenshots: the wall at 1567px (3 columns, spacing), slides opened from the wall (no wall visible), × → back to the wall at the same scroll, and each entry point.
- Escape order: slides → wall → chat.
- Run in the real Firefox and Chrome. The real app loads in jsdom with zero errors. Report the browser-parsed CSS rule counts.

**Gate:** open an album's "+N": a roomy 3-column wall. Click a photo: just that photo, with arrows and the × at its top-right corner. Close it and you're back on the wall.

**Record:** add a `## LIME-62` entry to `TEND.md`. Commit: `fix: media viewer: corner close, 3-column wall, slides replace wall`, trailer `Brief: LIME-62`, plus the attribution trailer.

---

### LIME-63 → `tend` (after LIME-62): QA polish: list corners, the Share popover as a dropdown, the composer fade, the reply mic clipping

**The user's QA (2026-09-30, screenshots):**
1. "The rounded corners of the message list should be consistent with the chat bubbles." Hovered and selected list rows look less rounded than the bubbles.
2. "The Share dropdown needs to follow the same pattern as the dropdowns: outlines, no close button in the top right, etc."
3. "The bottom fade could move up a little so that the + and mic icons are still readable." In the screenshot, a photo in the thread shows through behind the main composer's footer row (+, mic ⌄).
4. "The icons (mic) under the reply chat box are still getting a little cut off" (the split mic's outline or hover at the reply panel's right edge, after LIME-60, 60-fix and 60-fix2).

**Survey:**
- Bubbles use `--seed-radius-lg` (16px, `.lime-message__content`, `lime.css` ~4125). Find the list row radius.
- Menus: `.lime-menu` (~1954): `--soil-bg-elevated`, **`1px solid --soil-border-subtle`**, `--seed-radius-lg`, `--seed-shadow-md`, padding `--seed-space-2`, z 1000, closed by outside-click and Escape through `wireDropdownToggle`.
- The Share popover (`.lime-share-popover`, ~1120) has **no border**, `--seed-shadow-xl`, padding `--seed-space-5`, and a **close ×** (`#share-popover-close`, `index.html` ~250).

**The change:**
1. **List corners:** conversation rows (hover and selected, in every section: Starred, All, Archived) and any other row-style list in the centre panel use **`--seed-radius-lg`**, the bubbles' token. Point both at one shared token so they can't drift.
2. **The Share popover follows the menu pattern:** a `1px solid --soil-border-subtle` border, `--seed-shadow-md`, the same radius as `.lime-menu`, and padding consistent with menus (it holds a form, so use padding ≥ `--seed-space-3` where the content needs it; report the value). **Remove the close ×** (and its JS). The popover closes by **outside-click, Escape, or clicking Share again**, through the same registry as the other dropdowns (one open at a time). Its contents and Copy link stay as they are. Keep focus management: focus moves into the popover on open and returns to the Share button on close.
3. **The composer fade moves up:** the thread's bottom fade (the mask that fades content under the composer) must reach **full transparency above the top of the composer's footer row** (+, mic ⌄, disclaimer), so nothing in the thread shows behind those icons. Measure the footer row's top and the mask's 0%-opacity point, at 1567px and in the collapsed composer state. Apply the same to the reply panel if it has a fade. **Don't** reintroduce colour-matched overlays (fades are masks since LIME-50).
4. **Reply mic clipping, measured this time:** find what still clips the split mic in the reply composer: its outline (on hover and focus) and hover fill at the reply panel's real widths (default, narrowest and widest). Fix it so the whole outline and hover fill are visible. **Give a padded screenshot of the hover and focus states at each width as proof.** (LIME-60 claimed this was fixed. Report why it wasn't.)

**Scope:** `public/css/lime.css`, the Share popover markup and JS (`index.html` ~232–260, its handlers in `app.js`), the fade rules, and `TEND.md`. Not the Share contents' behaviour, the list's data, or other menus.

**Verification:**
- Measured radii (list row vs bubble).
- Screenshots of the Share popover beside an open "…" menu (the same pattern), plus open/close via outside-click, Escape and the Share toggle, and focus return.
- The fade measurements and screenshots with a photo scrolled behind the composer (the icons are readable).
- The reply mic at three widths (hover and focus, padded).
- Run in the real Firefox and Chrome. The real app loads in jsdom with zero errors. Report the browser-parsed CSS rule counts. `git diff public/index.html` shows only intended changes.

**Gate:**
- List rows have the same rounded corners as chat bubbles.
- Share opens like the other menus: a thin outline, and no ×; click outside or press Escape to close.
- The + and mic under the chat box stay clear even with a photo scrolled behind them.
- The reply box's mic is never cut off.

**Record:** add a `## LIME-63` entry to `TEND.md`. Commit: `fix: QA polish: list radius, share as dropdown, composer fade, reply mic`, trailer `Brief: LIME-63`, plus the attribution trailer. **Stop for the user's check.**

---

### LIME-57-fixf → `tend` (next): the z a touch smaller and higher, never touching the circle

**The user (2026-09-30, zoomed screenshot of `44e9db1`):** "z needs to be a tiny bit smaller and come up a tiny bit as well so that it doesn't touch the status circle." In the screenshot, the z's lower-left corner meets the green circle's bite edge on Jean's busy icon (Recent and Starred).

**The change (`presenceIconSvg` in `app.js`, the `-z` notched SVGs, and CSS if needed):**
1. **Smaller:** visible z height **~15% smaller**: lg 6.0 → **~5.2px**, md ~5 → **~4.3px**, xl ~8 → **~6.8px**.
2. **Higher (and, if needed, slightly further right):** move it up until there's a **clear gap of ≥ 0.75px at lg** (scaled for md and xl) between every painted pixel of the z and every painted pixel of the status circle, including its bite edge. Measure it from pixels in a padded or full-page screenshot, not from path coordinates.
3. **The z's own cut-out in the avatar and ring masks** moves and shrinks with it (the same ~4% gap rule). The z must still never overlap the avatar.
4. Busy (green) and DND (muted) both; md, lg and xl only, as before.

**Scope:** as LIME-57-fixe. **Verification:** zoomed full-page crops of busy and DND at md, lg and xl on the canvas, hovered and selected rows, and Recent with an unread ring, in light and dark. The measured z height and the minimum z-to-circle and z-to-avatar gaps. The real Firefox and Chrome.

**Gate:** the "z" is a hair smaller and sits just above the green circle, with a little space between them.

**Record:** add a `## LIME-57-fixf` entry to `TEND.md`. Commit: `fix: status z slightly smaller and clear of the circle`, trailer `Brief: LIME-57-fixf`, plus the attribution trailer. **Stop for the user's check.**

---

### LIME-57-fixe → `tend` (after LIME-61): the status "z" as Montserrat Bold, big enough to read

**The user (2026-09-30, screenshot of the Recent row and the Starred list, plus the mockup again):** "the status 'z' is still too small. In my mockup I used a small Montserrat Bold z."

**Plot's measurements:**
- **In the mockup**, the busy icon is 128px wide and its "z" is ~38×40px, i.e. ~31% of the icon's diameter, or **~10% of the avatar's width**.
- **At the app's real size** (a 40px avatar, a ~12px icon), that proportion gives a **~4px z**, which is unreadable. That's why following the mockup's ratio still looks too small. **At real size the z must be larger than the mockup's ratio** to read the way it does in the mockup.
- **The mockup's glyph is a lowercase "z" in Montserrat Bold** (flat top and bottom bars, a heavy diagonal). Today's is a hand-drawn stroked path.

**The change:**
1. **The glyph:** a **lowercase "z" in Montserrat Bold (700)**, the app's own brand font (`--seed-font-brand`, already loaded). Either use SVG `<text>` with that font (it's loaded on every page that shows avatars; confirm), or convert the glyph's outline to a path (if the font file is available locally) so it renders before the font loads. Report which. **No hand-drawn stroke path.**
2. **Size by visible glyph height** (the rendered bounding box, not the font size): **md 32 → ~5px, lg 40 → ~6px, xl 56 → ~8px** (≈ 15% of the avatar width, ≈ 50% of the icon's diameter). Hidden at sm/xs, as before.
3. **Position:** as in the mockup, in the icon's top-right bite, overlapping slightly outside the icon's bounds. **Colour:** green for Busy, muted for DND.
4. **The Z cut-out grows with it:** regenerate the `-z` notched masks (LIME-57-fixd) so the avatar (and the unread ring layer) is cut around the new glyph's box, plus the same ~4% gap. Active and away masks are unchanged.
5. **Legibility check:** at lg (40px), a zoomed screenshot must show a clearly recognisable "z" in the brand font.

**Scope:** `presenceIconSvg` in `public/js/app.js`, the `-z` notched SVGs in `public/assets/`, the related CSS in `public/css/lime.css`, and `TEND.md`.

**Verification:** as for LIME-57-fixd (busy and DND × md, lg and xl, Recent with an unread ring, the list rows hovered and selected, light/dark/Sage, full-page or padded screenshots, the real Firefox and Chrome), plus the measured z heights. Show a zoomed side-by-side of the app's lg busy icon next to the mockup's busy icon scaled to the same size.

**Gate:** the little "z" on busy and do-not-disturb is clearly readable, in the same bold Montserrat as your mockup.

**Record:** add a `## LIME-57-fixe` entry to `TEND.md`. Commit: `fix: status z in Montserrat Bold, readable size`, trailer `Brief: LIME-57-fixe`, plus the attribution trailer. **Stop for the user's check.**

---

### LIME-61 → `tend` (next): every primary button uses the Add/Send pale-lime style

**The user (2026-09-30, screenshots of the Share popover's "Copy link" and Settings' "Save changes"):** "want to make sure all the primary CTAs are the same color as the Add and return buttons." So the **solid brand-green** `seed-button--primary` (lime-500 `#09a950`, ink text since LIME-58) becomes the **pale lime** of `--lime-primary-*` (lime-100 rest → lime-200 hover → lime-300 pressed, `--lime-primary-ink` text): the same tokens Add and ↵ already share (`lime.css` ~31–48).

**Survey:**
- `seed-button--primary` has **12 call sites**: `auth.html` ×3 (Continue with email, Sign in, Create account), `index.html` ×5 (e.g. Copy link, Settings Save changes, the picker's Start), and `app.js` ×4 (dynamic dialogs, e.g. confirm actions).
- Seed's rule reads `--selected-bg-bold-*`/`--selected-text-bold-default`. Lime retuned those in LIME-58 (`lime.css` ~138–151). **Other consumers of `--selected-bg-bold-*`** (the voice/audio play buttons, ~4521 and ~4778) are **not CTAs**; leave them solid green.
- **Destructive buttons** (red, e.g. Delete confirm) are a different class. Leave them alone.

**Assumptions:** the agent can edit CSS, run Playwright and jsdom, drive the real Firefox and Chrome, and commit. `lime.css` is loaded on `auth.html` too (confirm).

**The change (in `public/css/lime.css` only):**
1. **Override `.seed-button--primary` in Lime** to read `--lime-primary-bg`, `-bg-hover`, `-bg-active` and `--lime-primary-ink` (text and icon), with the border colour matching the fill. **Don't change `--selected-bg-bold-*`**, so the play buttons stay as they are. Scope it so the override wins over Seed's `button.css` regardless of load order (the same specificity approach Lime uses elsewhere).
2. **Disabled primary buttons:** a clearly disabled look on the pale fill (e.g. the surface layer with `--soil-text-disabled`, no hover). Report what Seed did before and what it looks like now.
3. **Focus-visible:** the neutral focus ring Lime uses elsewhere (LIME-31-fix), visible on the pale fill.
4. **Verify the pale fill reads as a button on every surface it sits on:** the white elevated popover/modal (Share, Settings, the picker), the auth card, and the canvas in all 8 tones plus dark. Measure `--lime-primary-bg` against each background (ΔE, as in LIME-56). **If any falls below Warm's canvas distinctness, add a 1px border in `--lime-primary-bg-active` for primary buttons on elevated surfaces only, and report it.**

**Scope:** `public/css/lime.css` and `TEND.md`. **Not:** Seed files, the play buttons, destructive buttons, secondary or outline buttons, Add, or ↵.

**Verification:**
- Screenshots of every primary-button site found (all 12, including the auth page's three and any dynamic dialog), at rest, hovered, pressed, focus-visible, and disabled where it applies. In light and dark.
- The ΔE table from item 4. Ink contrast ≥ 4.5:1 on every state.
- The real app loads in jsdom with zero errors. Report the browser-parsed CSS rule counts.

**Gate:** "Copy link", "Save changes", the sign-in page's buttons and New message's "Start" are all the same pale lime as Add and the ↵ send button, with dark text, and they still clearly look like the main button wherever they appear.

**Record:** add a `## LIME-61` entry to `TEND.md`, and update the lime-rule note there: **primary buttons = pale lime (`--lime-primary-*`); solid brand green is now only for status and play accents.** Commit: `fix: primary buttons use the Add/Send pale-lime style`, trailer `Brief: LIME-61`, plus the attribution trailer. **Stop for the user's check.**

---

### LIME-60-fix2 → `tend` (next): the mic split's outline shows only on hover

**The user (2026-09-30, screenshot of `55baa1b`):** "only show the outline on hover."

**The change (in `public/css/lime.css`, `.lime-voice-split`):**
- At rest the border is **`transparent`** (keep the 1px border so nothing shifts).
- The outline colour (`--calm-border-normal-default`) appears when the pointer is over **either half** (`.lime-voice-split:hover`), when either half has **keyboard focus** (`:focus-within`, so keyboard users still see the grouping), and **while its microphone menu is open** (the ⌄ half's `aria-expanded="true"`; use `:has([aria-expanded="true"])` if verified in both browsers, otherwise a class toggled where the dropdown opens and closes).
- A short colour transition (~80ms, matching the halves' hover), so it fades rather than pops. The halves' own inset hover is unchanged.

**Scope:** `.lime-voice-split` rules in `lime.css` (plus a one-line class toggle in `app.js` only if `:has()` isn't usable), and `TEND.md`.

**Verification:** both composers: at rest (no outline, and no layout shift compared with hovered: measure the positions), mic hovered, ⌄ hovered, keyboard focus, and the menu open, in light and dark. In the real Firefox and Chrome. Report the browser-parsed CSS rule counts.

**Gate:** the mic and ⌄ look plain at rest, and the outline appears when you hover over either one, or while the microphone list is open.

**Record:** add a `## LIME-60-fix2` entry to `TEND.md`. Commit: `fix: mic split outline on hover only`, trailer `Brief: LIME-60-fix2`, plus the attribution trailer. **Stop for the user's check.**

---

### LIME-60-fix → `tend` (next): the mic split button gets its container outline

**The user (2026-09-30, screenshot of LIME-60 `9d09dd4` plus a reference crop):** "they currently function separately but without the container outline that holds them together, like in this example." **The reference:**
- **one rounded-rectangle container with a visible light-grey outline at rest** (radius ≈ 20–25% of its height, so not a full pill);
- inside it, the **mic half** (wider, square-ish) and the **⌄ half**;
- hovering the mic fills **just the mic half** with an inset rounded grey fill, inset ~3px from the outline;
- there's no divider line between the halves.

**Survey (`lime.css` ~5859–5905):**
- `.lime-voice-split` is a 28px-tall flex row with **no border**.
- The halves are full pills (`--seed-radius-full`) with a 2px margin and a hover of `--calm-bg-subtle-hover`.
- The composer box's own border uses `--calm-border-normal-default`.

**The change (in `public/css/lime.css` only, both composers via the shared classes):**
1. **The container:** `.lime-voice-split` gets a **1px border in `--calm-border-normal-default`** (the same token as the chat box's outline, so they read as a family), radius **`--seed-radius-md` (8px)**, a transparent background, and `box-sizing: border-box`. Raise the height to **~32px** if needed, so the inset hover fits comfortably. Keep it vertically centred with the + icon and the disclaimer.
2. **The halves:** inset ~3px inside the outline (the margins), radius = container radius − inset (≈ 5–6px), **not** pills. The mic half is roughly square (its width ≈ its height); the ⌄ half is narrower (~20–22px). The hover, pressed and focus-visible states stay as LIME-60 built them.
3. **Glyph sizes are unchanged** (the mic keeps LIME-59-fix's size; ⌄ as it is).

**Scope:** `.lime-voice-split*` rules in `public/css/lime.css`, and `TEND.md`. Nothing else.

**Verification:** screenshots of both composers at rest (the outline is visible), mic hovered, ⌄ hovered, and focus-visible, in light, dark and Warm. Use padded screenshots (nothing clipped). Report the measured container height, radius and inset, and the browser-parsed CSS rule counts.

**Gate:** in both chat boxes, the mic and ⌄ sit inside one thin rounded outline, like your example, and hovering either one fills just that half.

**Record:** add a `## LIME-60-fix` entry to `TEND.md`. Commit: `fix: outline container for the split mic button`, trailer `Brief: LIME-60-fix`, plus the attribution trailer. **Stop for the user's check.**

---

### LIME-57-fixd → `tend` (next): a slightly bigger Z, and a notch that hugs the icon

**The user (2026-09-30, screenshot after `d50d85a`):** "closer. The z needs to be a little bigger, also the cut out behind the status icon needs to be slightly smaller, closer around the status icon."

**Survey (`TEND.md` LIME-57-fixc):**
- The notch is one circle, `--notch-r` = **24% of the avatar width**, sized so it also clears the Z (whose farthest point is 23.56% out).
- The icon is 31% wide (radius 15.5%), so the gap around a plain icon is **≈ 8.5% of the avatar**, much more than the mockup's ~5.5%. That's why it looks loose.
- The notch is baked into four single-layer SVGs in `public/assets/` (`lime-silhouette-notched`, `lime-silhouette-ring-notched`, `circle-notched`, `circle-ring-notched`).

**The change:**
1. **The Z is ~25% bigger:** height ≈ **38% of the icon's diameter** (was ~30%), same position logic (in the bite, top-right) and the same 4.4:1 bar-to-stroke ratio, so it stays crisp.
2. **The notch hugs the icon:** the gap around the icon circle ≈ **4% of the avatar width** (≈ 1.6px at 40px). The notch circle's radius is therefore ≈ **15.5% + 4% = 19.5%**.
3. **The Z gets its own small cut-out** instead of inflating the whole circle: busy and DND icons need the Z area clear of the avatar too. Bake a **second, separate cut** for the Z region into **status-specific** notched SVGs (e.g. `*-notched-z.svg`): the Z's bounding area, dilated by the same 4% gap, with rounded corners. Avatars whose presence is busy or DND use the `-z` variant; active and away use the plain tight notch. The unread ring layer gets matching variants. Report the file list.
4. Regenerate the masks from the same source geometry (record the generator or the exact numbers in `TEND.md`).

**Scope:** the notched SVGs in `public/assets/`, the mask selection CSS in `public/css/lime.css` (and the presence-class hook in `app.js` if busy/DND need a class on the frame), the Z path in `presenceIconSvg`, and `TEND.md`.

**Verification:** as for LIME-57-fixc (the state × size grid, the Recent row with unread rings, hovered/selected, light/dark/Sage, full-page screenshots, the real Firefox and Chrome), plus the measured gap around the icon (≈ 4% ±0.5px at 40px) and the Z height (≈ 38% of the icon).

**Gate:** the Z is easier to see, and the cut around each status icon is tighter, just a thin gap like your mockup.

**Record:** add a `## LIME-57-fixd` entry to `TEND.md`. Commit: `fix: bigger Z, tighter notch with a separate Z cut`, trailer `Brief: LIME-57-fixd`, plus the attribution trailer.

---

### LIME-60 → `tend` (after LIME-57-fixd): composer polish: ↵ back to its old size, a split mic button, no clipped hover

**The user (2026-09-30, same screenshot):**
- "the return icon buttons in the chat and reply boxes were changed and now look too big";
- "the mic icon at the bottom of the reply chat box: the background hover is cut off";
- "this also needs to be more like the Add button, with a hover over the mic to record your voice and the caret to pick a mic to record from."

**Survey:**
- LIME-59-fix set `.lime-composer__return`'s glyph to **32px** (from LIME-59's 23px). **Before LIME-59 it was 18px** (`lime.css`, LIME-10 era; confirm with `git show 6db2847^:public/css/lime.css`).
- The mic is **one button** containing both glyphs: `#voice-mode-toggle` / `#replies-voice-mode-toggle`, `.lime-composer__aux.lime-composer__voice` with `dew-microphone` + `dew-chevron-down` (`index.html` ~549 and ~685), opening a decorative device menu (`#voice-mode-dropdown` / `#replies-voice-mode-dropdown`). The mic itself doesn't record (still a placeholder, per LIME-10).
- The Add split button's inset-hover pattern is in `lime.css` (`.lime-nav-add`, LIME-55-fix).

**The change:**
1. **↵ return, both composers:** back to its **pre-LIME-59 visible size** (the 18px glyph, or whatever measured size it had at `6db2847^`), identical in the main and reply composers. **↵ is excluded** from the "match the left toggle" rule; the other composer icons keep LIME-59-fix's size.
2. **The mic becomes a split button, like Add but neutral** (it's not a primary action):
   - **One rounded container**, no fill at rest, no divider. Two halves: **mic** (left) and **⌄** (right, narrow).
   - Each half gets **its own inset rounded hover** (the LIME-55-fix technique) in the **neutral** hover token (`--calm-bg-subtle-hover`), with a pressed step and a focus-visible ring on that half only.
   - **Mic half:** `title`/`aria-label` "Record a voice message". Clicking it does what the mic does today (nothing real yet; keep it a placeholder, or show the existing "Soon" pattern if there is one). **Don't build recording.**
   - **⌄ half:** `title`/`aria-label` "Choose microphone", opening the existing device menu. Escape and outside-click close it, as today.
   - **Both composers**, with identical markup and CSS.
3. **No clipped hover:** the reply composer's footer (or an ancestor) clips the mic's hover background. Find the clipping (overflow, height, or a negative margin) and fix it so the full inset hover shows, in **both** composers at all widths, including the reply composer's always-collapsed toolbar and the main composer's collapsed state (LIME-32's container query).

**Scope:** composer markup in `public/index.html` (splitting the voice button into two buttons inside one container), its wiring in `public/js/app.js` (the dropdown trigger moves to the ⌄ half), `public/css/lime.css`, and `TEND.md`. **Not** recording, the device list's contents, or the other composer icons' sizes.

**Verification:**
- The measured ↵ glyph size, before and after, in both composers.
- Screenshots of both composers: at rest, mic half hovered, ⌄ half hovered, focus-visible, and with the menu open, at 1567px and the reply panel's narrow width, in light and dark. **No hover is clipped** (padded or full-page screenshots).
- The menu opens from ⌄ only; Escape and outside-click close it; one menu at a time.
- The real app loads in jsdom with zero errors. Report the browser-parsed CSS rule counts. `git diff public/index.html` shows only intended changes.

**Gate:** the ↵ buttons are back to their smaller size. In both chat boxes, the mic and its ⌄ form one button with two halves: hovering the mic highlights just the mic ("Record a voice message"), and hovering ⌄ highlights just the arrow ("Choose microphone"). Nothing is cut off.

**Record:** add a `## LIME-60` entry to `TEND.md`. Commit: `fix: composer: return size, split mic button, unclipped hover`, trailer `Brief: LIME-60`, plus the attribution trailer. **Stop for the user's check.**

---

### LIME-59-fix → `tend` (next): icons back up to the left toggle's size

**The user (2026-09-30, screenshot after LIME-59 `6db2847` and 57-fixb):** "the right toggle button: if you look at the left toggle size (which is correct), the right toggle and palette icon, the mic icon, the + icon all look smaller than they were." LIME-59 normalised the header and composer icons to a ~18px visible bounding box, **which shrank them.** **The reference size is the left sidebar toggle** (`#left-panel-toggle`, `index.html` ~84).

**The change:** measure the **left toggle's rendered glyph bounding box and stroke weight** (in the real Firefox). Then make **every header icon** (Share, Appearance palette, "…", `#right-panel-toggle`) and **every composer icon** (+ attach, mic, ⌄, ↵ return) render at **that same visible size (±1px) and stroke weight**. Keep LIME-59's goal: all of them equal to each other. Hit areas are unchanged. The hand-drawn SVGs (Share, palette) scale accordingly. **Don't change the left toggle.**

**Scope:** icon sizing in `public/css/lime.css` (and the inline SVGs' size attributes in `public/index.html` if needed), and `TEND.md`. Nothing else.

**Verification:** a table of each icon's measured bounding box before and after, against the left toggle's; a screenshot of the header and composer next to the left toggle; the real app in jsdom with zero errors; and the browser-parsed CSS rule counts.

**Gate:** the right-panel toggle, the palette, Share, "…", and the chat box's +, mic and ⌄ are all the same size as the left sidebar toggle.

**Record:** add a `## LIME-59-fix` entry to `TEND.md`. Commit: `fix: header and composer icons match the left toggle's size`, trailer `Brief: LIME-59-fix`, plus the attribution trailer.

---

### LIME-57-fixc → `tend` (after LIME-59-fix; REVISED before sending, 2026-09-30, to follow the user's Penpot mockup): status icons drawn exactly like the mockup

**The user (2026-09-30), on LIME-57-fixb `81a759d`:** "the status icon is also broken: the outline should be around the status only [on] the profile. There should be no background around the status icons." **Then the user made a Penpot mockup** "of how I want it executed". **The mockup is the spec. If the user exports it as an SVG into `public/assets/` (e.g. `status-mockup.svg`), use its exact geometry and override the numbers below. Otherwise use plot's measurements:**

**The mockup (plot's description and measurements; the avatar silhouette is drawn as a white outline on purple only to show its shape):**
- **The avatar is the lime silhouette** (nub at the lower left). **The status icon sits on the avatar's lower-right edge,** and the avatar is **cut away around it**: the silhouette's outline simply stops on either side of the icon, leaving a clean gap. **Nothing is drawn around the icon:** no disc, no ring, no halo. Inside the cut, you see the true background.
- **Proportions (measured on the ~400px mockup avatar):**
  - icon diameter ≈ **31% of the avatar width** (≈ 12.5px at 40, 10px at 32, 17.5px at 56);
  - icon centre ≈ **(90%, 86%)** of the avatar's box (x, y);
  - **the cut-away circle's radius ≈ icon radius + 5.5% of the avatar width** (≈ +2.2px at 40). **This replaces plot's earlier "thin 1–1.5px" guess, which was wrong.**
- **The four states:**
  - **Active:** a solid **green** filled circle (brand green `--good-bg-bold-default`).
  - **Busy:** the solid green circle with a **round bite taken out of its top-right** (a bite circle of radius ≈ 30% of the icon's diameter, centred ≈ (+34%, −26%) of the icon diameter from the icon's centre). Plus a **green geometric "Z"** (a flat top bar, a diagonal, a flat bottom bar, drawn as a path, **not** a font glyph), height ≈ 30% of the icon's diameter, sitting **in that bite and slightly outside the icon's top-right bounds** (its left edge ≈ the icon centre + 18%, its top ≈ the icon top − 12%).
  - **Away:** a **hollow ring**, stroke ≈ 10% of the icon's diameter, **in the muted colour** (`--soil-text-muted`; the mockup's white is its stand-in on purple). The inside is empty: the background shows through (the avatar is cut away there too).
  - **Do not disturb:** the same muted ring **with the same top-right bite** (an open gap in the ring), plus the **muted "Z"** in the same position as Busy's.
- The "Z" extends beyond the icon's box, so **the icon element must allow overflow** (or be sized to include the Z), and the avatar's cut-away must also clear the Z's area, so the Z never overlaps the avatar. **The Z is shown on md and larger only**; at sm/xs, keep the bite or gap so the state still differs.

**What was wrong in `81a759d` (plot's survey; fix all of it):**
- the icons' SVGs use a 24-unit viewBox with the circle at `r=10` (or a ring at `r=9`, stroke 3), so the visible icon is ~25% of the avatar, smaller than before and than the mockup. **Draw shapes that fill their box;**
- the "Z" is an 8-unit **text** glyph (≈ 4px): unreadable and font-dependent. **Draw it as a path;**
- a visible band shows around icons, most clearly in the Recent row (the unread ring layer showing through). **Cut the unread ring layer with the same cut-away circle (and the Z area),** confirm the fallback `box-shadow` is off where `mask-composite` works, and remove any background, border or shadow on `.lime-presence` and its SVG. **Report what caused the band.**

**AMENDMENT (plot, 2026-09-30, answering tend's mid-brief blocker): the notch technique changes. No `mask-composite` at all.**
- **Tend's report:** the two-layer `mask-composite: add, subtract` notch paints the part of the notch circle that lies **outside** the base shape **solid** (in Firefox and Chrome), which causes the band/square. Two compensating attempts failed. Tend correctly stopped. **Keep tend's verified Z-path fix** (wider bars, stroke 5, uncommitted in `app.js`).
- **Plot's suspicion, for the record:** with `mask-image: A, B; mask-composite: add, subtract`, the operator that applies is the **top layer's** ("add", a union). The bottom layer's operator is ignored. That would explain the circle's overflow being painted. Either way, **don't keep debugging composite order.**
- **Decision: bake the notch into single-layer SVG masks.** The notch is a fixed **ratio** of the avatar (centre ≈ 90%/86%, radius = tend's measured `--notch-r` ratio, now 24% of the width), so **one pre-composited SVG per shape works at every size:**
  - `public/assets/lime-silhouette-notched.svg`: the silhouette **minus** the notch circle, done **inside the SVG** (an SVG `<mask>`, or the silhouette path plus the circle with `fill-rule="evenodd"`, or a clip). The viewBox equals the silhouette's. Any part of the circle outside the viewBox is irrelevant.
  - `public/assets/circle-notched.svg`: the same for the round avatars (xs/sm).
  - **The unread ring layer** (`::after`, which is bigger than the avatar by the ring width): give it its **own** notched SVG (`lime-silhouette-ring-notched.svg`), with the notch placed so it lines up with the avatar's notch once scaled to the ring's box (compute it from the ring-to-avatar size ratio). Or confirm that a single SVG lines up within ±0.5px at md, lg and xl, and report which.
  - Each element then uses **one** `mask-image` layer with `mask-size: 100% 100%`. **Remove every `mask-composite` and the radial-gradient layers.**
  - **Only avatars that actually show a presence icon get the notched mask.** Others (e.g. avatars without status) keep the plain `lime-silhouette.svg` or circle. Use a class the markup already has, or add `lime-avatar-frame--has-presence` where the icon is rendered, or `:has(.lime-presence)` if verified in both browsers. Report which.
  - Delete the per-size `--notch-cx/-cy` overrides if the single ratio makes them unnecessary.
  - The no-mask fallback (`@supports not (mask-image…)`) keeps the round avatar plus the `box-shadow` separation.
- **Everything else in this brief stands:** the mockup geometry, the four states, the path Z, the size ratios, verification (now with explicit **"the circle's overflow outside the shape is never painted"** checks at md, lg and xl), and the gate.

**Scope:** the presence and cut-away CSS in `public/css/lime.css`, `presenceIconSvg` in `public/js/app.js`, the new notched SVGs in `public/assets/`, and `TEND.md`. Not the plain silhouette, the avatar sizes, or presence data.

**Verification:**
- **A side-by-side sheet: the mockup's 4 states re-created at 400px in the real app's CSS** (a scratch page using the real classes, on the purple `#451a49`-ish background so it's directly comparable with the mockup), **plus** every state × md, lg and xl on the canvas, a hovered row, a selected row, and a Recent item with an unread ring. In light, dark and Warm. **Use full-page or padded screenshots, not element-clipped ones** (see Patterns learned).
- Measured icon diameters, centre positions, cut-away radii and Z sizes, against the mockup's ratios (±1px at 40px).
- In the real Firefox and Chrome. The real app loads in jsdom with zero errors. Report the CSS rule counts.

**Gate:** status icons look like your Penpot mockup: a bigger icon on the lower-right edge, the avatar cut away around it with nothing around the icon; solid green for active, a bitten green circle with a green Z for busy, a grey ring for away, and an open grey ring with a Z for do-not-disturb.

**Record:** add a `## LIME-57-fixc` entry to `TEND.md`. Commit: `fix: status icons match the mockup (cut-away, sizes, path Z)`, trailer `Brief: LIME-57-fixc`, plus the attribution trailer. **Stop for the user's check.**

---

### LIME-57-fixb → `tend` (next; SUPERSEDES LIME-57-fix, which was never sent): polished status icons in a cut-out notch, never clipped

**The user (2026-09-30), after LIME-57-fix was drafted:** "we need to refine those to make them more polished, the status icons. I like how it is done in this example" (a Slack-style reference). What the reference does:
- **the avatar has a cut-out "bite"** where the status icon sits, so there's a clean gap of whatever is behind it, **not a painted border ring**;
- the icon is fairly large (~28% of the avatar width), at the bottom-right, overlapping the edge;
- the four states:
  - **Active:** a solid green circle;
  - **Busy:** a solid green circle with a small notch at the top-right, and a tiny **"z"** sitting in that notch;
  - **Away:** a hollow ring (outline only);
  - **Do not disturb:** a hollow ring with a gap at the top-right, and a tiny **"z"**.

**Everything in LIME-57-fix below still applies** (the root cause and the rule "no masked ancestor around a presence icon; rebuild the unread ring as a masked layer behind the avatar"). **This brief adds the new design on top.**

**Survey (plot, 2026-09-30, `lime.css` ~500–547):**
- `.lime-presence` is an absolutely positioned dot with a **`box-shadow` ring in `--soil-bg-canvas`** (so on hovered or selected rows, and in other tones, the ring is the wrong colour).
- Sizes: xs 6, sm 7, md 9, lg 11px.
- States: `active` (green), `busy` (green with a knocked-out "z" inside), `away` (a canvas fill with a 1.5px grey border), `dnd` (red with a knocked-out dash).
- `app.js` maps data statuses `online → active`, `busy → busy`, `offline → away` (~108). `dnd` is styled but has no data status yet.
- There's also an inline variant, `.lime-presence--inline` (~705), used in profile text.

**The change (on top of LIME-57-fix's items 1–3):**
1. **The cut-out notch:** every avatar that shows a presence icon is masked with **its shape minus a circle** centred on the icon: the lime silhouette for ≥ 32px, a circle for smaller ones. Use two mask layers with `mask-composite: subtract` (and `-webkit-mask-composite: source-out`). The circle's radius = icon radius + gap (gap ≈ 2px at 40px, scaled by size). **Remove the `box-shadow` canvas ring:** the gap is truly transparent, so it's right on any tone, hover, selected row, or dark. **The unread ring layer (from LIME-57-fix) gets the same bite,** so the ring never runs into the icon. If `mask-composite` is unsupported, `@supports` falls back to today's `box-shadow` ring.
2. **Icon sizes:** about 28% of the avatar: xs 20 → **7px**, sm 24 → **8px**, md 32 → **10px**, lg 40 → **12px**, xl 56 → **16px**. Placement: the icon's centre sits on the avatar's edge at the bottom-right, at roughly 45°. On the lime silhouette, place it where the edge actually is (the silhouette isn't a perfect circle), and report the offsets.
3. **The four states, drawn as small inline SVGs** (crisp at small sizes, `currentColor`, one shared definition):
   - **Active:** a solid circle in the brand green (`--good-bg-bold-default`, `#09a950`).
   - **Busy:** a solid green circle with a top-right notch, plus a tiny "z" in the notch.
   - **Away:** a hollow ring, stroke ≈ 1.5–2px (scaled), in `--soil-text-muted`.
   - **Do not disturb:** a hollow muted ring with a top-right gap, plus a "z" (as in the reference). **This replaces today's red DND**; the user can ask for red back at the gate.
   - **At xs and sm (7–8px), drop the "z"** (it can't be read); keep the notch or gap so the state still differs.
   - Colour never carries the meaning alone: keep `role="img"` and `aria-label` on every icon.
4. **The inline variant** (`.lime-presence--inline`, e.g. next to "Active" in profiles) uses the same SVGs at text size, with no cut-out.
5. **The "z" colour** matches its state (green for Busy, muted for DND). The "z" sits in the notch, so it's inside the cut-out gap. Make sure it isn't clipped by the avatar's mask; it lives in the icon element, outside any mask.

**Scope:** as in LIME-57-fix, plus the presence markup/SVG (in `app.js`, wherever presence icons are rendered) and `lime.css`'s presence styles. **May not touch:** the presence data logic (the `online/busy/offline` mapping), the avatar colours, and the silhouette itself.

**Verification (on top of LIME-57-fix's):**
- A **zoomed sheet** of all 4 states × the 5 avatar sizes (shaped and round), on the canvas, on a **hovered** list row and on a **selected** row, in light, dark, Warm and Sage. The gap always shows the true background, and no icon or "z" is clipped.
- The measured icon sizes and offsets.
- In the real Firefox and Chrome (confirm `mask-composite` works in both; report the versions).
- The fallback works when masks are disabled (force it by removing the `@supports` match in a test).
- Report the browser-parsed CSS rule counts. The real app loads in jsdom with zero errors.

**Gate:** status icons look like your example: a clean notch cut into the avatar, green for active, green with a little "z" for busy, a ring for away, and a broken ring with a "z" for do-not-disturb. Nothing is cut off, including in the Recent row, and it looks right on hovered and selected chats.

**Record:** add a `## LIME-57-fixb` entry to `TEND.md`. Commit: `feat: polished status icons in a cut-out notch; never clipped`, trailer `Brief: LIME-57-fixb`, plus the attribution trailer. **Stop for the user's check.**

---

### LIME-57-fix → SUPERSEDED (never sent) by LIME-57-fixb above; its root cause and items 1–3 still apply through 57-fixb. Kept for reference:

**The user (2026-09-30, screenshot of the Recent row):** "recent section, the status icons are cut off." Every Recent avatar's presence dot (green online, grey away) is **clipped to the lime silhouette**, whether or not the item has an unread ring.

**Root cause (plot's survey of LIME-57 `5a17cbb`):** `.lime-avatar-ring` (`lime.css` ~595–616) is **always** present in the Recent markup (`app.js` ~2615–2619), wraps `.lime-avatar-frame`, and **always carries the silhouette mask**. The presence dot is a child of the frame, so it's inside a masked ancestor and gets clipped. Tend's LIME-57 check confirmed the dot is a sibling of the avatar, but not that no masked **ancestor** wraps it, and it didn't screenshot the Recent row's dots.

**Assumptions:** the agent can edit CSS and JS, run Playwright and jsdom, drive the real Firefox and Chrome, and commit.

**The change:**
1. **No masked element may be an ancestor of a presence dot, anywhere.** Rebuild the unread ring so it's a **masked layer behind the avatar**, not a wrapper around the frame: for example, `.lime-avatar-frame::before` (or a sibling span placed before the avatar) absolutely positioned at `inset: -2px`, carrying the silhouette mask and the ring fill, and shown only for `.lime-recent__item--unread`. The avatar sits above it and the presence dot above both, **outside any mask**. Remove the always-present `.lime-avatar-ring` wrapper if it's no longer needed.
2. **Keep the ring's look** from LIME-57: 2px, `--selected-border-bold-default`, following the nub. **Read items: zero layout shift**, as before.
3. **Audit every masked avatar in the app** (md/lg/xl): confirm that no presence dot, badge (e.g. the "z" away/DND mark), or focus outline sits inside a masked ancestor. List each place checked.

**Scope:**
- **May touch:** the ring styles in `public/css/lime.css`, the Recent row markup in `public/js/app.js`, and `TEND.md`.
- **May not touch:** the silhouette, avatar sizes or cutoff, presence logic, and anything else.

**Verification:**
- **Element screenshots of every Recent avatar,** read and unread, online, away and offline: the full round dot with its canvas-coloured border is visible.
- The same for a thread-header avatar, the details panel and Settings Profile.
- The unread ring still follows the nub (a zoomed crop).
- In the real Firefox and Chrome, plus Playwright. The real app loads in jsdom with zero errors. Report the browser-parsed CSS rule counts.

**Gate:** in the Recent row, every green or grey status dot is a complete circle again, and the green unread rings still follow the lime shape.

**Record:** add a `## LIME-57-fix` entry to `TEND.md`. Commit: `fix: presence dots never clipped by the lime mask`, trailer `Brief: LIME-57-fix`, plus the attribution trailer. **Stop for the user's check.**

---

### LIME-59 → `tend` (after LIME-58): softer hovers and selected rows; header and composer icons at one consistent size

**The user (2026-09-30, screenshot):** "soften the hovers in the center panel hovers of the messages list and the top icons. Also the share icons and the theme icons need to be consistent in size, I feel the same way about the chat box link button." In the screenshot:
- the **selected list row** (a strong grey) and hovered rows read heavy;
- in the header, the **Share** glyph (`dew-share`, an upload arrow) looks visibly **larger and heavier** than the **Appearance** palette (a hand-drawn SVG) and the "…";
- the chat box's bottom icons (+ attach, mic, ⌄) and the ↵ return button don't follow one size.

**Plot's interpretation of "chat box link button"** (the user can correct it at the gate): **every icon in the composer**, i.e. + attach, mic, ⌄ and ↵ return, follows the same icon-size standard as the header.

**Survey (plot, 2026-09-30, `lime.css`):**
- The layer tokens are `--lime-layer-hover` (canvas + 8% ink) and `--lime-layer-active` (+12% ink) at ~80–81. Warm's overrides are at ~159–160 (based on `#F0EEE6` from LIME-56), and dark's at ~174–175 (+10% / +14% white).
- They feed `--calm-bg-subtle-hover/-active`, used by list rows, menus, icon buttons and (since LIME-55-fix) the nav's active item, **which must keep matching the selected list row**.
- `.lime-icon-btn` is 36px with `.dew` at 18px (~621–649). The palette SVG is sized to 18px (~651).

**Assumptions:** the agent can edit CSS (and markup only to swap a glyph), run Playwright and jsdom, and commit.

**The change:**
1. **Softer hover and selected, app-wide and in step:** lower the light-theme mix from **8% → ~5%** (hover) and **12% → ~8%** (active/selected), for the default and Warm overrides alike; dark from **10% → ~7%** and **14% → ~10%**. **The order must hold:** surface < hover < selected, each **still clearly distinguishable** in all 8 tones and dark. Measure OKLab ΔE between neighbours and pick the lowest percentages that keep ΔE ≥ a threshold you state (for example, the value at which hover is still obvious on Warm). Report the final percentages and the table. The nav's active item still equals the selected list row.
2. **One icon standard for header and composer:** every icon button in the **thread header** (Share, Appearance, "…", and the right-panel toggle) and the **composer** (+ attach, mic, ⌄, and ↵ return) renders at the **same visible glyph size** (target: a visible bounding box of ~18px for 24-grid icons, ±1px), the same stroke weight, and the same hit-area size within each group (header 36px; composer at its current size unless a mismatch is found). **Measure each glyph's rendered bounding box** (not just `font-size`: dew glyphs vary optically) and adjust per icon where needed. **If `dew-share` can't be matched in weight, draw it as an inline SVG in dew's stroke style** (as LIME-50 did for the palette), and report it.
3. **Header icon hovers soften too** (they use the same tokens, via item 1). Their hover shape and size must match each other.
4. **Chat bubbles match the list's hover colour (the user, 2026-09-30):** "I'd like the colour of the chat bubbles to be the same as the messages list hover or similar (currently it's slightly darker)." Bubbles are `.lime-message__content { background: var(--soil-bg-surface) }` (`lime.css` ~4125), i.e. `--lime-layer-surface` (on Warm, `#F0EEE6` since LIME-56). List hover is `--lime-layer-hover`. **Point the bubble background at the same colour as the list-row hover (after item 1's softening)**, through one shared token, so they stay identical in every tone and in dark. Apply it to the reply panel's bubbles too, if they're styled separately. Leave the composer box and other surface users alone. **Measure and report** the bubble and list-hover colours before and after on Warm, Sage and dark (the user perceived the bubbles as darker; confirm what was actually true). Ink text on the bubble stays ≥ 4.5:1, and a bubble on a **hovered message row** (the message hover state, if any) must still be distinguishable. Report it.

**Scope:**
- **May touch:** `public/css/lime.css` (the layer percentages and icon sizing), `public/index.html` (only to swap a glyph for an inline SVG), and `TEND.md`.
- **May not touch:** colours other than the layer mix and the bubble token (item 4), the primary buttons, layout, and behaviour.

**Verification:**
- The ΔE table (surface/hover/selected, 8 tones + dark), before and after.
- The measured glyph bounding boxes for every header and composer icon, before and after.
- Screenshots: the list with a hovered and a selected row, the header icons (at rest, hovered), and the composer icons. In light and dark.
- Report the browser-parsed CSS rule counts. The real app loads in jsdom with zero errors.

**Gate:** hovering and selecting chats in the list feels lighter. Chat bubbles are the same soft shade as a hovered chat in the list. The Share, palette and "…" icons at the top look the same size, and the chat box icons match each other. **If "chat box link button" meant something else, say which button.**

**Record:** add a `## LIME-59` entry to `TEND.md`. Commit: `fix: softer hover/selected layers; consistent icon sizes`, trailer `Brief: LIME-59`, plus the attribution trailer.

---

### LIME-58 → `tend` (after LIME-57 Phase 2): dark ink text on the solid green buttons

**The user (2026-09-30): chose "A"**: text on the solid brand-green buttons becomes ink `#131b17` instead of white. White on `#09a950` is ≈ 3.1:1, which fails 4.5:1 (found by tend in LIME-56).

**Survey (plot, 2026-09-30):**
- `seed-button--primary` (`vendor/seed/components/button/button.css` ~75–88) reads `--selected-bg-bold-default/-hover/-active` and `--selected-text-bold-default`.
- **Light theme** (`tokens.css` ~241–250): bg lime-500 `#09A950` → hover **lime-600 `#078040`** → active **lime-700** (darker), text `--seed-soil-0` (white).
- **Dark theme** (~370–379): already ink-style text (`--seed-soil-950`) on lime-500, with **lighter** hover and active (lime-400, lime-300).
- **Plot computed:** ink on lime-500 ≈ **5.7:1** ✓; ink on lime-600 ≈ **3.5:1** ✗. So the light theme's darker hover/press steps don't work with ink. **Hover and press must go lighter instead** (ink on lime-400 `#5DC870` ≈ 8.4:1 ✓; on lime-300 `#A3E18A` higher), which is **exactly Seed's own dark-theme pattern**.
- Other Lime consumers of `--selected-bg-bold-*`/`--selected-text-bold-default`: `lime.css` ~4521 and ~4778 (e.g. the voice-note play button). They inherit the change. Check that they still look right.

**Assumptions:** the agent can edit CSS, run Playwright and jsdom, and commit. **Don't edit `vendor/seed/`.** Override in Lime's own theme block in `lime.css`, where Lime already retunes `--selected-*`.

**The change (in `public/css/lime.css`, light theme only):**
1. `--selected-text-bold-default` → Lime's pinned ink (`#131b17`, the existing ink token).
2. `--selected-bg-bold-hover` → `--seed-lime-400`; `--selected-bg-bold-active` → `--seed-lime-300` (mirroring dark mode).
3. Any icon token paired with these on solid green (e.g. `--selected-icon-bold-default`, currently `--seed-soil-0` in light) → ink as well, so icons match text.
4. **Leave dark mode as it is** (it's already correct); just re-verify it.

**Scope:**
- **May touch:** `public/css/lime.css` (the token overrides) and `TEND.md`.
- **May not touch:** `vendor/seed/`, `auth.css` beyond what the tokens already drive, and the pale `--lime-primary-*` (Add and Send) buttons.

**Verification:**
- A contrast table: text and icon on rest, hover and press, in light and dark, for every solid-green consumer (the auth "Continue with email", "Sign in", "Create account", Settings Save, the picker's "Start", the Share popover's "Copy link", the voice-note play button, and any others found). All ≥ 4.5:1.
- Screenshots of each, at rest and hovered.
- Report the browser-parsed CSS rule counts. The real app loads in jsdom with zero errors.

**Gate:** the green buttons (sign-in page, Settings Save, New message Start, Copy link) now have dark text that's easy to read, and hovering makes them lighter, not darker.

**Record:** add a `## LIME-58` entry to `TEND.md`, and note it as an **upstream candidate for Seed** (the same change in Seed's light theme). Commit: `fix: ink text on solid green buttons (contrast)`, trailer `Brief: LIME-58`, plus the attribution trailer.

---

### LIME-56 → `tend` (after LIME-48-fix2): the 8 canvas tones tuned to the brand palette (keep all 8)

**The user (2026-09-30):** shared Lime's brand palette and asked whether the 8 canvas tones complement it. They chose to **keep all 8** tones and refine them.

**Brand palette → existing tokens (plot's survey):** ink `#131b17` = `--seed-soil-925` / Lime's pinned ink; green `#09a950` = `--seed-lime-500` (primary buttons); `#a3e18a` = `--seed-lime-300` (the pressed step of `--lime-primary-*`); `#e4f9be` = `--seed-lime-100` (`--lime-primary-bg`: Add and Send); `#f9f8f4` = Warm's canvas. **`#f0eee6` is unused.** Canvas presets: `CANVAS_P` in `public/js/appearance.js` (~77–86). The surface layers are tone-relative mixes in `lime.css` ~63–66 (`--lime-layer-surface` = canvas 97% + ink 3%; hover 8%; active 12%; raised = canvas 30% + white 70%).

**Assumptions:** the agent can edit files, run Playwright (Firefox) and jsdom, and commit. Preview at `http://localhost:8000/public/index.html`.

**The change:**
1. **Warm's surface layer becomes the brand's `#f0eee6`:** on the Warm tone, the surface (bubbles, the composer box, the segmented toggle, the selected list row and the nav active item) renders **`#f0eee6` (±2 per channel)**. Choose the cleanest mechanism (a Warm-only override of `--lime-layer-surface`, or a Warm ramp adjustment) and report why. Hover and active must stay progressively darker than surface on Warm. **Other tones' layers don't change** unless a contrast check forces it (report any).
2. **Sage is retuned so lime stands out:** move Sage's base `#D8E6D0` greyer (lower chroma, same lightness family) until `--lime-primary-bg` (`#e4f9be`) is **at least as distinguishable** from Sage's canvas **and** surface as it is on Warm (measure OKLab ΔE for both pairs on Warm, then require Sage ≥ that). Keep all Sage text-contrast targets from LIME-50/50-fix (≥ 4.5:1 ink and muted on canvas and surface).
3. **Every tone is verified against the brand:** for all 8 tones, measure and report (a table):
   - ink and muted text on canvas and surface (≥ 4.5:1);
   - `--lime-primary-bg` vs canvas and vs surface (ΔE; flag any tone below Warm's);
   - the primary green `#09a950` button text contrast (unchanged tokens, re-confirmed);
   - **primary-button icon/text on rest, hover and pressed lime** (≥ 4.5:1).
   **Known gap:** on Lemon, the hover text is 4.43:1 (from LIME-55-fix). **If any primary-button state is below 4.5:1, switch `--lime-primary-*`'s icon/text colour to full ink (`--seed-soil-900`/the pinned ink)** for both Add and Send, and report it. The user may veto this at the gate.
   Any other tone that falls below a target: adjust that tone's base minimally, report before/after, and **stop and ask the user if the fix would visibly change a tone's character**.
4. **Labels, order and ids are unchanged** (stored preferences keep working).

**Scope:**
- **May touch:** `CANVAS_P` in `public/js/appearance.js`, the layer tokens in `public/css/lime.css` (Warm-only if possible), the `--lime-primary-*` text colour (only under item 3's condition), and `TEND.md`.
- **May not touch:** dark mode, patterns, the swatch UI, and anything else.

**Verification:**
- The full table from item 3 (before and after), and the measured Warm surface colour.
- Screenshots of the app in all 8 tones (the list with a selected row, a chat with bubbles, the composer, the Add button).
- Report the browser-parsed CSS rule counts for `lime.css` and `gradients.css`. The real app loads in jsdom with zero errors.

**Gate:** open the palette menu and click through all 8 tones. On **Warm**, the panels and bubbles now use the brand's warm grey. On **Sage**, the green Add and Send buttons stand out clearly. Everything stays easy to read.

**Record:** add a `## LIME-56` entry to `TEND.md`, including the tables. Commit: `fix: canvas tones tuned to the brand palette`, trailer `Brief: LIME-56`, plus the attribution trailer.

---

### LIME-57 → `tend` (after LIME-56; TWO stops): lime-shaped avatars at 28px and up

**The user (2026-09-30):** added `public/assets/Logomark-outline.svg` (untracked) and asked about making circles lime-shaped. **They chose option A: avatars ≥ 28px use the lime silhouette; smaller avatars stay round; icon hovers are unchanged.**

**Survey (plot, 2026-09-30):**
- The SVG is a 245.37×245.54 export with lots of wrapper cruft. **The outer silhouette is its first `<path>`**: a hand-drawn, slightly wobbly circle with a **small nub at the lower left** (~x 30–62, y 210–225). The segment paths inside are the logo's slices, not needed here.
- Seed avatar sizes (`vendor/seed/components/avatar/avatar.css`): xs 20, sm 24, **md 32, lg 40, xl 56**. Lime also has custom-sized avatars (profile/details, the Recent row, Settings 64px). Find them all.
- **Masks clip borders and box-shadows.** The Recent row's unread ring is a `box-shadow` (`lime.css` ~3745), and focus rings on avatar buttons would be clipped too.

**Phase 1: a preview, then STOP for the user.**
1. Extract the outer path into a clean, minimal SVG: `public/assets/lime-silhouette.svg` (a single path, a `viewBox` normalised to a square so it's centred, `fill="#000"`, no ids or cruft; ≤ 3 KB). **Don't edit or commit `Logomark-outline.svg`; ask the user in the report whether to commit it as a brand asset.**
2. Make a **scratch preview page (outside the repo)** showing the silhouette applied via `mask-image` (with `-webkit-mask-image`, `mask-size: 100% 100%`) to initials avatars and photo avatars at **20, 24, 28, 32, 40, 56 and 64px**, in light and dark, with the presence dot, and with the unread ring (built the way item 3 below proposes). Put circles side by side for comparison.
3. **Stop and show the user the screenshot** (a path to the PNG). Ask: is 28px the right cut-off, and does the nub read well?

**Phase 2 (only after the user approves, with any cut-off change they give):**
1. Apply the silhouette to **every avatar ≥ the cut-off** app-wide (a size-based class or selectors covering md, lg, xl and the custom sizes). Smaller ones stay circles. **Group avatar clusters stay as they are.**
2. **Presence dots** stay outside the mask (they already sit in a separate frame wrapper); confirm none is clipped.
3. **Rings:** rebuild the Recent row's unread ring and any avatar focus ring so they follow the lime shape. For example, a wrapper that carries the same mask, filled with the ring colour and padded by the ring width, with the avatar inside. **No clipped rings anywhere.**
4. Photos are masked the same way. The avatar's `border-radius` stays as a fallback where masks are unsupported.

**Scope:**
- **May touch:** `public/css/lime.css`, `public/assets/lime-silhouette.svg` (new), avatar markup in `public/js/app.js` only if a wrapper is needed for rings, and `TEND.md`.
- **May not touch:** icon-button hovers, avatar colours, presence logic, and anything else.

**Verification (Phase 2, `http://localhost:8000/public/index.html`, Playwright Firefox, plus a check in the real Firefox and Chrome):**
- Screenshots: the list, the Recent row (with an unread ring), the thread, details and members panels, Settings Profile, and the picker. In light and dark.
- List every avatar size found and whether it's shaped or round.
- No ring or presence dot is clipped (element screenshots).
- Report the browser-parsed CSS rule counts. The real app loads in jsdom with zero errors.

**Gate:** Phase 1: look at the preview and approve (or change the cut-off). Phase 2: avatars across Lime are little limes, the tiny ones stay round, and the unread rings and green online dots still look right.

**Record:** add a `## LIME-57` entry to `TEND.md`. Commit (Phase 2): `feat: lime-shaped avatars`, trailer `Brief: LIME-57`, plus the attribution trailer. If Phase 1 creates files in the repo (the silhouette SVG), commit them with the Phase 2 commit, not before.

---

### LIME-48-fix2 → `tend` (next): swap the sign-in video for the user's `signin-teachers.mp4`

**The user (2026-09-30):** "update the auth video to this one instead signin-teachers.mp4". The file is at `public/assets/signin-teachers.mp4` (untracked). **Plot inspected it:** H.264 + AAC audio, **4096×2160 landscape**, 12s, **11.5 MB**. That's far too heavy for a sign-in page, and it's landscape, while the current hero (`auth-hero.*`, Pexels 12896417) is portrait. **Source/licence:** unknown to plot. If the user's prompt names it, record it; otherwise record "supplied by the user, source not recorded" and flag it in the report. Don't block on it.

**Assumptions:** the agent can run macOS tools (`avconvert`, `sips`, `mdls`), Playwright, and the real Firefox and Chrome, edit files and commit. `ffmpeg` isn't installed (per LIME-48). Firefox on macOS plays H.264 MP4, so **an MP4-only source is acceptable** if a WebM can't be made; report which.

**The change:**
1. **Re-encode** with `avconvert` to a web size: try `Preset1920x1080` and `Preset1280x720`, and pick the smallest that still looks sharp in the panel at 1567×905 (the panel is roughly 740×880 CSS px, so ~1280 px wide source is plenty). **Target ≤ 3 MB** (report the size and dimensions of each attempt). **Drop the audio track if the preset allows** (the video is always muted); if it can't, report it. Output: `public/assets/auth-hero.mp4` (replacing the old one).
2. **Poster:** capture a new frame (as LIME-48 did) as `public/assets/auth-hero-poster.jpg`, ≤ 200 KB.
3. **Framing:** the panel is portrait-ish and the video is landscape, so `object-fit: cover` crops the sides heavily. **Look at the frames** (e.g. at 0s, 4s, 8s, 11s) and set `object-position` so the people stay in view throughout. Report the value chosen and screenshots at 1567×905 and a narrower desktop (e.g. 1024×768).
4. **Sources:** remove the `auth-hero.webm` source (it's the old Pexels video) and delete that file. The `<video>` keeps one MP4 source. Update the source comment in `auth.html` (~119–130) to describe the new file and its provenance.
5. **The original:** **don't delete or commit `signin-teachers.mp4`.** Leave it untracked and untouched, and tell the user they can remove it.
6. Everything else is unchanged: autoplay muted loop, the pause button, reduced-motion (poster only), hidden at ≤ 767px with no download there.

**Scope:**
- **May touch:** `public/auth.html` (the video sources, the comment, and `object-position` if set inline), `public/css/auth.css` (`object-position`), `public/assets/auth-hero.mp4`, `auth-hero-poster.jpg`, deleting `auth-hero.webm`, and `TEND.md`.
- **May not touch:** `signin-teachers.mp4`, the form, and anything else.

**Verification (at `http://localhost:8000/public/auth.html`):**
- In the **real Firefox and Chrome**, the video autoplays, loops, is muted, and pause/play works.
- Reduced motion shows the poster. At 767px, no video or poster request is made (check the network log).
- The new file sizes and dimensions, and whether the MP4 has an audio track.
- Framing screenshots.
- `git status` shows `signin-teachers.mp4` still untracked, and the old webm deleted.

**Gate:** open the sign-in page. The new teachers video plays on the right, the people stay in frame, and the page loads quickly.

**Record:** add a `## LIME-48-fix2` entry to `TEND.md`, including the encode attempts. Commit: `feat: new sign-in video`, trailer `Brief: LIME-48-fix2`, plus the attribution trailer. **Stop for the user's check.**

---

### LIME-55-fix → `tend` (after LIME-27): Add becomes the lime primary action; nav states go neutral; a proper split-button look

**The user (2026-09-30, screenshot of LIME-55 `0f504fb`, plus two reference crops of a split mic ⌄ button):** "make the New button the color of the active nav item and then make the nav items follow the same pattern as the other dropdowns etc. that way the lime green can be on the primary action." The references show a **split button inside one rounded container**: at rest the two halves read as one control with **no visible divider**; hovering a half fills **just that half** with an **inset, rounded** highlight (a few px in from the container's edge), so each half feels like its own button.

**The user, follow-up (2026-09-30): "make sure you use the same green pattern as the chat box return button."** So the Add button (both halves and the rail "+") must use **exactly the same three states as `.lime-composer__return.is-active`** (`lime.css` ~5175–5189): rest `--selected-bg-subtle-default` (lime-100), hover `--selected-bg-subtle-hover` (lime-200), pressed `--selected-bg-subtle-active` (lime-300). **Match the icon and text colour to the return button's active state too.** To keep the two from drifting, define **one set of primary-action custom properties** in `lime.css` (e.g. `--lime-primary-bg`, `--lime-primary-bg-hover`, `--lime-primary-bg-active`, mapped to those three `--selected-*` tokens) and point **both** the return button and the Add button at them. The return button's look must not change: its computed colours before and after are identical (report them). This overrides any other colour wording in item 2 below.

**This changes the lime rule (the user's decision, 2026-09-30):** lime is now for **primary actions only**. **Nav items no longer use lime** for hover or active. Record this in `TEND.md`; plot updates Patterns learned.

**Assumptions:** the agent can edit CSS, run Playwright and jsdom, and commit. Survey facts (`lime.css`, 2026-09-30): `.lime-nav__btn:hover` and `--active` use `--selected-bg-subtle-default/-hover/-active` (~1231–1247), which Lime retunes to lime; menus use `--calm-bg-subtle-hover` (`.lime-menu__item:hover`, ~1349); the split button is `.lime-nav-add` (`__main`, `__toggle`, ~1054–1100).

**The change (in `public/css/lime.css` only, plus markup only if strictly needed):**
1. **Nav items go neutral, matching the rest of the app:** `.lime-nav__btn` hover uses the **same token as menu-item hover** (`--calm-bg-subtle-hover`). **Active** ("Link") uses the **same neutral selected state as the selected conversation row** in the list (find the token that row uses; it's tone-relative since LIME-50-fix), with active-hover one step darker in the same family. Apply the same in the collapsed rail and in the mobile drawer's `!important` overrides. **Also check the notifications button and the user trigger at the bottom** (`PLOT.md` lists `--lime-nav-hover` users: nav hover and active, divider hover, user trigger). Make them neutral too, and **list every remaining lime consumer you find in `TEND.md`** without changing them (e.g. Send, the unread ring and the voice play button stay lime by the user's earlier choice).
2. **"+ Add | ⌄" becomes the lime primary action, styled like the references:**
   - **Container:** one rounded shape (keep the current height and radius, matching Search), filled with **the colour the active nav item has today** (`--selected-bg-subtle-default`, the lime), ink text and icons, **no border, no visible divider at rest**.
   - **Each half on hover:** an **inset rounded fill** (inset ~3–4px from the container edge; radius = container radius − inset) one step darker (`--selected-bg-subtle-hover`), filling only that half. On press, `--selected-bg-subtle-active`. **Focus-visible:** a 2px neutral focus ring on the focused half only.
   - The chevron half is narrow (~32px) and the label half takes the rest, like today.
   - **The collapsed rail "+"** gets the same lime fill as a single 40px rounded button, with the same hover and press steps.
3. **Contrast:** ink on each lime step is ≥ 4.5:1, and the lime fill is visibly distinct from the canvas in **every canvas tone and dark mode** (report the ratios; if dark mode's lime needs its own step, use Seed's dark ramp and report it).

**Scope:**
- **May touch:** `public/css/lime.css`, `public/index.html` (only if the split button needs an extra wrapper for the inset hover), and `TEND.md`.
- **May not touch:** behaviour (Add, the menu, the picker), the return/Send button's appearance (it only switches to the shared custom properties), the Recent unread ring, the voice play button, the list rows, and anything else.
- If a decision isn't covered here, stop and ask the user.

**Verification (Playwright Firefox at `http://localhost:8000/public/index.html`):**
- Screenshots at rest, with the **main half hovered**, with the **chevron half hovered**, and focus-visible. Compare against the references: no divider at rest; an inset fill on one half only.
- The nav's Link (active), hover on Notifications, the collapsed rail (Add "+" and the active item) and the 767px drawer, all in light, dark, and 2 canvas tones.
- The measured nav active background equals the selected list row's background (same computed colour).
- The contrast table.
- Report the browser-parsed CSS rule counts for `lime.css` and `gradients.css`.

**Gate:** the **+ Add** button is now the green one, and hovering either half highlights just that half, like your mic examples. **Link** and the other nav items use the same soft grey as the rest of the app (like the selected chat in your list).

**Record:** add a `## LIME-55-fix` entry to `TEND.md`, including the lime-consumer list and the contrast table. Commit: `fix: Add is the lime primary action; neutral nav states; split-button hover`, trailer `Brief: LIME-55-fix`, plus the attribution trailer. **Stop for the user's check.**

---

### LIME-55 → `tend` (next, before LIME-27): a split "+ Add | ⌄" button in the left nav replaces the + beside the tabs

**The user (2026-09-30, screenshot of the app after LIME-29):** "I would like to move the add button to the nav with a multi action [ + Add | v ]. When you press Add it adds a new chat; if you press the arrow it should open a dropdown for Link, Jam (soon). When the menu is toggled to collapsed you only see the plus sign."

**Plot's decisions (the user can overrule at the gate):**
- **Placement:** the **first item in `.lime-nav`**, directly **above the Search field** (`index.html` ~87–88), full nav width, the way Claude puts "New chat" at the top.
- **Style:** neutral, matching the Search field's height, radius and fill (`.lime-nav-search`). **Not lime** (the lime rule keeps lime for the *active* nav item and primary buttons; a lime block above a lime active "Link" row would compete). Two halves in one pill: the left half "+ Add" (`dew-plus` + label) and the right half a narrow ⌄ (`dew-chevron-down`), with a 1px neutral divider between. Each half has its own hover and focus.
- **"+ Add"** opens LIME-29's New message picker (the same code path as `#new-message-btn`/`[data-open-picker]`).
- **⌄** opens a menu in the LIME-21b menu pattern (the search-modal style, one menu open at a time via the dropdown registry, Escape and outside-click close, arrow keys):
  - **"New message"**, with `dew-chat` and a muted "Link" hint, opening the picker;
  - **"New jam"**, with `dew-pencil`, **disabled** with the LIME-23 "Soon" pill and an accessible label "New jam (coming soon)".
- **The collapsed rail** (`seed-layout--collapsed-left`): only a **"+" icon button** (the rail's icon-button style, tooltip and `aria-label` "New message"), opening the picker. No chevron.
- **The mobile drawer** shows the full split button, the same as desktop.
- **Remove** the `+` beside the Messages/Communities tabs (`#new-message-btn`, `index.html` ~249) and let the tabs take the row's width back. **Keep** LIME-29's empty-state "New message" text button in the list.

**Assumptions:** the agent can edit files, run jsdom and Playwright, drive the real Firefox and Chrome, and commit. Preview at `http://localhost:8000/public/index.html` (server from the repo root).

**Scope:**
- **May touch:** `public/index.html` (the nav markup; removing `#new-message-btn`), `public/js/app.js` (wiring; reuse the picker opener and `wireDropdownToggle`), `public/css/lime.css`, and `TEND.md`.
- **May not touch:** the picker itself, the Jam page, and anything else.
- **Check the `PLOT.md` pattern note:** any change to a sidebar row's styling must also be checked in (a) the desktop collapsed rail and (b) the `.seed-layout--mobile-open.seed-layout--collapsed-left` `!important` overrides in `lime.css`'s mobile media query.
- If a decision isn't covered here, stop and ask the user.

**Verification:**
- The real app loads in jsdom with zero errors. "+ Add" opens the picker; ⌄ opens the menu; "New message" opens the picker; "New jam" is disabled and does nothing; Escape and outside-click close the menu; opening it closes any other open menu.
- **Playwright Firefox, measured at 1567×905, in the collapsed rail, and at 767px (drawer open):** the split button's height and radius equal the Search field's (±1px); it fits the nav width with no overflow; the rail shows only "+", centred like the other rail icons; the tabs row no longer has the +.
- Screenshots in light and dark.
- Report the browser-parsed CSS rule counts for `lime.css` and `gradients.css`.
- `git diff public/index.html` shows only intended changes.

**Gate:** at `http://localhost:8000/public/index.html`: the new **+ Add | ⌄** button sits at the top of the left nav. **Add** starts a new message; the **arrow** shows New message and New jam (Soon). Collapse the sidebar and you only see **+**. The + beside the tabs is gone.

**Record:** add a `## LIME-55` entry to `TEND.md`. Commit: `feat: split Add button in the nav (new message, new jam soon)`, trailer `Brief: LIME-55`, plus the attribution trailer.

---

### LIME-48-fix → `tend` (next, before LIME-29): the user's Inspector refinements to the sign-in page (bigger logo, smaller bold headline, spacing)

**The user (2026-09-30):** refined `auth.html` live in Firefox's Inspector (not saved to disk; the tree is clean) and shared a screenshot: "note the logo font size, spacing etc." Asked for exact values, they said: "no need, just use your best judgement based on the screen capture." **So these values are plot's estimates from the screenshot. Match the look; don't treat the numbers as sacred.**

**How plot measured:** the screenshot's scale is ≈ 0.93 of CSS pixels. Calibrated against things the user didn't change: the card is 372px wide in the screenshot versus its 400px `max-width`; the inputs and buttons are ~41px versus 44px; the video panel's margin is ~22px versus 24px. All targets below are already converted to CSS px.

**Assumptions:** the agent can edit files, run Playwright, drive the real Firefox, and commit. Current values are from `public/css/auth.css` (2026-09-30).

**The change (in `public/css/auth.css` and `public/auth.html` only):**
1. **Logo, bigger:** mark `32px` → **`40px`**; wordmark image height `16px` → **about `28px`** (target: rendered wordmark ≈ 69px wide; check the SVG's aspect ratio and adjust the height to hit it). The gap stays `--seed-space-2`. Keep `margin-bottom: --seed-space-8`; target ≈ 32–36px of clear space between the logo's bottom and the headline's glyph tops.
2. **Headline, smaller and bolder:** `--seed-text-3xl` (48px) semibold → **`28px`, `--seed-weight-bold`**, line-height ~1.2. Target: "Where teachers connect." renders ≈ 335px wide (±10). **Add the full stop** to the headline text (the subline has none, as in the screenshot).
3. **Subline:** `--seed-text-lg` (20px) → **`22px`**, line-height ~1.4, same muted colour. It should wrap as "Messages, groups and communities / for educators" inside the 400px column. Headline-to-subline margin `--seed-space-3` → **`--seed-space-2`**. Keep the subline-to-card gap at `--seed-space-8`.
4. **Everything else is unchanged:** the card, buttons, inputs, divider, legal text, video panel, vertical centring, and the other steps (password and create).

**Scope:**
- **May touch:** `public/css/auth.css`, the headline text in `public/auth.html`, and `TEND.md`.
- **May not touch:** anything else. If a value doesn't match a Seed token, a raw px value is fine here, scoped to `auth.css`, with a one-line comment "user's refinement, 2026-09-30".

**Verification (at `http://localhost:8000/public/auth.html`, 1567×905 and 767px, Playwright Firefox is fine for this layout-only change):**
- Report the measured mark size, the wordmark width, the headline width and font size, the subline's line breaks, and the gaps logo→headline, headline→subline and subline→card.
- The form column still fits at 1567×905 with no scroll, on the email, password and create steps alike.
- Screenshots at desktop, mobile and dark.
- Report the browser-parsed CSS rule counts for `auth.css` (and `lime.css`, unchanged).

**Gate:** open `http://localhost:8000/public/auth.html`. It should look like your Inspector version: the bigger logo, the smaller bold "Where teachers connect.", and the tighter spacing under it.

**Record:** add a `## LIME-48-fix` entry to `TEND.md`. Commit: `fix: sign-in page refinements (logo size, headline, spacing)`, trailer `Brief: LIME-48-fix`, plus the attribution trailer.

---

### LIME-33-fix → `tend` (next, before LIME-49-fix): accounts don't survive a page change in the user's Firefox

**The user's gate check on LIME-33 (`a398ca3`, 2026-09-30, screenshot + answers):**
- Created a new account **twice** with the same email in **Firefox**. **Right after "Sign up" it went straight back to the sign-in page** (not into Lime), and signing in then says "Incorrect email or password."
- The second sign-up with the same email **wasn't** refused as "already in use", so **the first account wasn't there even on `signup.html` itself.**
- They also tried `shem.robinson@ps113.edu` with a password they made up. **That's expected to fail:** seed teachers sign in with the shared demo password unless they've changed it in Settings. The fix is to explain it, not to change the rule (see 4 below).

**Plot's reading (survey of `auth.js` ~80–147 and ~225–238, `login.html` and `signup.html`, 2026-09-30):** the sign-up and sign-in logic is correct. **The data written to `localStorage` on one page isn't visible on the next page load in the user's Firefox,** so the session is missing on `index.html` (bounce to login) and the credential is missing on `login.html` and `signup.html`. **This very likely has the same root cause as the parked pattern upload bug** (IndexedDB, also working in Chrome and in tend's clean Firefox). Suspects: a user preference (cookies or site data blocked or cleared for local files; Enhanced Tracking Protection "strict"/custom), `file://` origin handling for this profile, or an add-on (the user's screenshot of LIME-49 shows an injected blue button in the Reply composer).

**The user APPROVED (2026-09-30) testing on a private copy of their Firefox profile:**
- Copy their default profile (from `~/Library/Application Support/Firefox/Profiles/`; `profiles.ini` names the default) **to a temporary folder**, excluding `lock`/`.parentlock`. **Never launch or modify the real profile.**
- Launch the real `/Applications/Firefox.app` with `-profile <copy> -no-remote`.
- **Don't read, print or record personal data** (history, cookies, saved logins, form data). Only read **preferences and the add-on list** (`prefs.js`, `user.js`, `extensions.json` names/ids), and only what's relevant.
- **Delete the copy afterwards** and say so in `TEND.md`.

**Assumptions:** the agent can copy files, drive the real Firefox (as in LIME-52-fix5), edit files and commit.

**Phase 1: reproduce and find the cause (read-only for the repo).**
1. With the profile copy, over `file://`: sign up → does `index.html` see the session? Record `localStorage` keys on each page (`signup.html`, `index.html`, `login.html`), and whether `localStorage.setItem` throws or silently doesn't persist.
2. **Find the exact cause:** bisect by disabling add-ons (all, then one at a time) and by comparing relevant prefs with the clean profile (e.g. `privacy.file_unique_origin`, `network.cookie.cookieBehavior`, `dom.storage.enabled`, `browser.privatebrowsing.autostart`, any "delete cookies and site data on close", cookie exceptions). **Name the exact add-on or preference.**
3. **Also run the pattern upload** with the profile copy (both surfaces). Record whether it fails and whether the same cause explains it. **Don't fix the upload in this brief;** just record it for the parked item.
4. Repeat 1 over `http://localhost` (a server from the repo root) to see if it's `file://`-only.

**Phase 2: the change (only after Phase 1 names a cause).**
1. **Never fail confusingly:** on `signup.html`, `login.html` and the session gate in `index.html`, run a **storage check** (write a probe key, read it back; and on `index.html` right after sign-up, detect "I was just sent here from sign-up but there's no session"). If storage doesn't work or doesn't persist, show one clear message in plain words instead of bouncing to sign-in or saying "Incorrect": e.g. "Your browser isn't letting Lime save your account on this computer. [one-line cause-specific fix]". **The wording of the fix comes from Phase 1's finding.**
2. **If the cause is a Firefox setting or add-on the app can't work around:** don't try to bypass it. Write the exact steps for the user to change it in `TEND.md` and in the gate below. **If it can be worked around safely** (e.g. something about `file://` handling), propose the workaround in `TEND.md` and **stop and ask the user** before building it.
3. **Seed-teacher sign-in hint:** when a seed email fails with the wrong password, the message says: "Incorrect password. Demo teachers use the shared demo password unless you've changed it in Settings."

**Scope:**
- **May touch:** `public/js/auth.js`, `public/login.html`, `public/signup.html`, the session gate in `public/index.html`/`app.js`/`store.js`, `docs/data-model.md` (a note), and `TEND.md`.
- **May not touch:** the pattern upload code (parked), the password hashing, and anything else.
- If the survey turns up related issues, raise them before fixing. If a decision isn't covered here, stop and ask the user.

**Verification:**
- Phase 1's findings table: each page × `file://`/localhost × profile copy/clean profile, and the named cause. Also the upload result with the profile copy.
- With the cause present: the new storage message appears (screenshot) instead of the bounce or "Incorrect".
- With the cause removed (add-on off or pref restored in the **copy**): sign up → land in Lime → sign out → sign back in works, in the real Firefox and in Chrome.
- The real app loads in jsdom with zero errors. Report browser-parsed CSS rule counts if CSS is touched.
- The profile copy is deleted (say so).

**Gate:** follow the fix steps tend gives for your Firefox (if any), then sign up again. You should land in Lime as the new teacher, and signing out and back in should work. If anything still blocks it, Lime should now tell you plainly why.

**Record:** add a `## LIME-33-fix` entry to `TEND.md` with the findings table and the named cause (plot reads it from there; tend doesn't edit `PLOT.md`). Commit: `fix: clear message when the browser won't save accounts; seed sign-in hint`, trailer `Brief: LIME-33-fix`, plus the attribution trailer. **Stop for the user's check.**

---

### LIME-49-fix → `tend` (next, before LIME-33): replying stacks copies of your photo on the original message's avatar

**The user's gate check on LIME-49 (`912240a`, 2026-09-30, screenshot):** "everytime i reply the main chat avatar breaks and duplicates my photo. this only happens if I reply my own messages." In the screenshot, the parent message (a voice note with "4 replies") has an avatar showing **4 side-by-side copies** of the user's photo. Other messages' avatars are fine.

**Root cause (plot's survey, 2026-09-30):**
- `paintAvatar` (`app.js` ~1637) **isn't idempotent for photos.** The photo branch **appends** a new `<img>` every call, while the initials branch sets `textContent` (which replaces). Before LIME-49 every avatar was initials, so repainting was harmless.
- `refreshReplyIndicator` (`app.js` ~1583–1591) runs after each reply, replaces the footer, then repaints **every** `.lime-avatar[data-name]` in the whole message, **including the sender's own avatar**, which was already painted. With a photo, each reply adds one more `<img>`, so 4 replies make 4 copies. "Only on my own messages" = only the user has a photo so far.
- Other bulk sweeps (`app.js` ~1912, 2105, 2315, 2506, 2559, 2828, 3132, 3449, 4614) could repaint already-painted avatars in the same way.

**Assumptions:** the agent can edit files, run jsdom and Playwright (and the real Firefox), and commit.

**The change:**
1. **Make `paintAvatar` idempotent:** before painting, clear the element's own content (`el.textContent = ''`) and remove any `lime-avatar--p<N>` palette class (as `repaintAvatar` ~2713 already does). **First confirm `.lime-avatar` never holds other children that must survive** (e.g. the presence badge sits in a separate frame wrapper per the `lime.css` ~390 comment). If something does, stop and ask. `repaintAvatar` can then drop its own duplicate clearing.
2. **Scope `refreshReplyIndicator`'s repaint to the new footer only** (`.lime-message__footer .lime-avatar[data-name]`), so it doesn't touch the sender avatar at all.
3. **Photos added later still update:** the photo in an already-rendered message changes live when the user changes or removes their photo (the existing `lime:profile-changed` path via `repaintAvatar`).

**Scope:**
- **May touch:** `paintAvatar`, `repaintAvatar` and `refreshReplyIndicator` in `public/js/app.js`, and `TEND.md`.
- **May not touch:** anything else. **If other sweeps need scoping too, list them in `TEND.md` rather than changing them,** since idempotency already fixes them.

**Verification:**
- **jsdom (real app, zero errors):** with the current user given a photo, reply 5 times to their own message. The parent's avatar contains **exactly 1 `<img>`** afterwards, and every avatar in the app has at most 1 `<img>` (report the max found). The footer's reply avatars have 1 each. An initials avatar repainted 3 times still shows its initials once, with exactly one palette class.
- **Real Firefox and Chrome:** the same, by hand-driven replies from the thread panel. Screenshot the parent message after 4 replies.
- Changing and then removing the photo updates the parent message's avatar live.

**Gate:** reply to your own message a few times. Its avatar stays a single, normal photo. Also reply to someone else's message, and check that the little avatars in "N replies" look right.

**Record:** add a `## LIME-49-fix` entry to `TEND.md`. Commit: `fix: avatars never stack duplicate photos on repaint`, trailer `Brief: LIME-49-fix`, plus the attribution trailer. **Stop for the user's check.**

---

### LIME-54 → `tend` (next, then LIME-49): delete the Subtle Patterns samples and the tile-probing code

**The user (2026-09-30):** "I want to dial back the pattern lab, delete the subtle patterns so we can get back to the major parts." **LIME-53 (the pattern lab) is DROPPED, never sent.** The 4 current presets stay exactly as they are.

**Assumptions:** the agent can edit files, delete files, run Node/jsdom and Playwright, and commit. Plot surveyed (`grep`, 2026-09-30) every reference: `appearance.js` ~162–167 (comment), ~218–268 (`USER_TILE_CANDIDATES`, `USER_TILE_EXTENSIONS`, `probeImage`, `detectUserPatternTiles`), ~574 (the `'user-tile'` branch in `applyPattern`), ~616 (export); `app.js` ~114–118 (`patternUserTileThumbHtml`), ~157, ~207–213 (`cachedUserPatternTiles`), ~366–370 (the tile click branch), ~2056 and ~4641 (callers passing `cachedUserPatternTiles`); `docs/data-model.md` ~1027–1036 and ~1096–1118.

**Phase 1: survey (read-only).** Confirm the references above, and find any others (`probeImage` may have other users; keep it if so). Confirm `public/assets/patterns/` holds only the 6 untracked samples (`bananas.png`, `cork-board.png`, `ep_naturalwhite.png`, `geometry2.png`, `leaves.png`, `ripples.png`) and is untracked in git. **If anything else is in that folder, stop and ask the user.**

**Phase 2: the change.**
1. **Delete** `public/assets/patterns/` and its 6 files (untracked, so they won't appear in the commit; the user asked for this explicitly).
2. **Remove the user-tile feature:** everything named above in `appearance.js` and `app.js`. `patternGridHtml` loses its `userTiles` parameter; the grid shows None, the 4 presets, and the Upload tile, exactly as it did otherwise.
3. **Stored appearance with `kind: 'user-tile'`** (the feature existed but the folder never held a matching file name, so this should be rare) is treated as None, without errors.
4. **Comments and docs:** rewrite `appearance.js` ~162–167 to one line: the presets are drawn in-house as inline SVG, with no third-party assets and no credit owed. In `docs/data-model.md`, replace the Subtle Patterns and user-tile notes with the same fact in 2–3 lines. Don't touch `PLOT.md` or old `TEND.md` entries.

**Scope:**
- **May touch:** `public/js/appearance.js`, `public/js/app.js`, `docs/data-model.md`, `TEND.md`, and the deletion of `public/assets/patterns/`.
- **May not touch:** the 4 presets, the upload pipeline (**parked**: see "PARKED: pattern upload fails"), CSS beyond removing a rule used only by user tiles (report it if so), and anything else.

**Verification:**
- `grep -rniE "subtle ?patterns|USER_TILE|detectUserPatternTiles|cachedUserPatternTiles|user-tile|assets/patterns" public docs` → **no matches**.
- `ls public/assets/patterns` → no such directory.
- The real app loads in jsdom with zero errors. In Playwright Firefox, the palette popover and Settings show None + 4 presets + Upload; picking each preset still works; a stored `{ kind: 'user-tile' }` loads as None with no console errors.
- If CSS is touched, report the browser-parsed rule counts for `lime.css` and `gradients.css`.

**Gate:** none needed from the user beyond a glance. The palette menu looks the same as before, with the four patterns plus Upload.

**Record:** add a `## LIME-54` entry to `TEND.md`. Commit: `chore: remove sample patterns and tile-probing code`, trailer `Brief: LIME-54`, plus the attribution trailer. **Then continue straight to LIME-49** (the user wants to get back to the major parts), and stop after LIME-49 for the user's check.

---

### LIME-53 → DROPPED (never sent), the user, 2026-09-30: "dial back the pattern lab." Kept for history.

### LIME-52-fix5 → `tend` (next, before LIME-53): uploads still do nothing, in both surfaces

**The user (2026-09-30, after LIME-52-fix3 `c646917`):** the upload is "still buggy and want to try it working." Asked what happens: **"Nothing happens"** (no change, no message), from **both the palette menu and Settings**. Tend's own fix3 matrix passed in headless Firefox, so **the failure only shows in the user's real, headed Firefox.** Treat tend's earlier green matrix as not proving anything about this.

**Update from the user (2026-09-30): "certainly happening in firefox because chrome it works."** The same files work in Chrome and fail in Firefox. So:
- **This is a Firefox-specific bug.** Hypothesis 1 (applied but invisible) is **much less likely**, because the processing is identical in both browsers. Keep it only as a quick check.
- **Why tend's tests passed:** Playwright's `firefox` is **Playwright's own patched Firefox build** with its own default preferences, **not** the user's installed Firefox 156 (`/Applications/Firefox.app`). A pass there doesn't prove the real browser works.
- **New Firefox-specific hypotheses, tested first:**
  - (5) **`file://` origin rules.** Firefox gives each `file://` page an opaque/unique origin (`security.fileuri.strict_origin_policy`). Test whether IndexedDB opens and a **Blob** write succeeds there, whether a `blob:` object URL made from that page loads as an `<img>`/`mask-image`/`background-image` in CSS, and whether `canvas.toBlob` works on a canvas drawn from that blob image. A thrown `SecurityError` or `InvalidStateError` that's caught and swallowed, or an IndexedDB request that never fires any event, would look exactly like "nothing happens".
  - (6) **The hidden input's `change` event in stock Firefox:** whether `.click()` on an `<input hidden>` opens the picker and delivers `change`. Also test with the input visually hidden (off-screen, `opacity: 0`) instead of `hidden`.
  - Also check: **does attaching a photo in a chat (the + button, LIME-38, also IndexedDB) work in the real Firefox?** If it fails too, the cause is shared storage, not the pattern code.
- **The required test browser is the real Firefox app:** drive `/Applications/Firefox.app` over **WebDriver BiDi** (`--remote-debugging-port`, a throwaway `-profile "$(mktemp -d)"`, the recipe in Patterns learned) or Playwright's `firefox.launch({ executablePath: '/Applications/Firefox.app/Contents/MacOS/firefox' })` if that works. **Use Chrome as a control:** the same steps must pass there. Read the real Firefox's **browser console** errors for each attempt and report them. **Also run the same test over `http://localhost`** (a server started from the **repo root**, opening `/public/index.html`) to find out whether the failure is `file://`-only. The real product will be served over https, but the user previews over `file://`, so **both must work**. Report the result for each. If the real Firefox can't be automated, say so and hand the user an exact 3-step manual test that includes opening the console (⌥⌘K) and reading back any red errors.

**Assumptions:** the agent can edit files, run Node + Playwright (Firefox, headed and headless), and commit. **Plot's assumption:** the user most likely tested with their own sample files in `public/assets/patterns/` (very light, near-white images; two are WebP named `.png`). Use all 6 as test files. **Copy them to the scratchpad first,** because LIME-53b will delete them from the repo.

**Hypotheses (plot's reading of `app.js` ~216–378, `appearance.js` ~296–470 and `local-adapter.js`). Test each one; don't assume any:**
1. **Applied but invisible.** A near-white source (ripples, natural white, geometry) defaults to **Texture**. After auto-levelling, it may still produce a mask so faint that at Low (6%) it looks like nothing changed. "Nothing happens" might really be "it worked, invisibly." Check whether the selected state and the upload preview tile change.
2. **The pipeline hangs.** `processUploadFile` waits on `isStorageAvailable()` (`checkStorageAvailable` in `local-adapter.js`) before doing anything. If `openFilesDb()` never settles (a `blocked` open because another Lime tab holds an older DB version; a transaction that **aborts** rather than errors, since there's no `onabort` handler), the promise never resolves. The job stays busy forever and the only sign is a 28px spinner the user might not notice. The result is also **cached for the session**, so one hang blocks every later upload.
3. **The file dialog never opens,** or `change` never reaches the listener in headed Firefox (a programmatic `.click()` on a `hidden` input after user activation was consumed or lost; `uploadActiveSurface` being null when `change` fires).
4. **Stale code:** the user's Firefox may be running cached pre-fix3 JS. Rule this out by loading with a cache bypass, and **tell the user to hard-reload (⌘⇧R) in the gate**.

**The change:**
1. **Reproduce in headed Firefox** (Playwright `headless: false`, a throwaway profile), from both surfaces, with each of the user's 6 files plus one ordinary mid-tone photo. Add a **temporary** trace (`console.log` at: tile click → input click → `change` → storage check resolved → decoded → processed → stored → applied → re-rendered) to find exactly where each attempt stops. Also run it **with a second Lime tab open**. Record in `TEND.md` which hypothesis (or which new cause) it was.
2. **Fix every root cause found.** At minimum:
   - **No stage can hang silently:** add a timeout (~10s) around the storage check and the store writes. On timeout, fall back to the session-only path with its note. Handle `onabort` and `onblocked` everywhere `checkStorageAvailable` and `openFilesDb` wait. Don't cache a failed or timed-out check.
   - **A visible result, every time:** after a successful upload, the new upload tile is selected and shows the image, and the background visibly changes. If a Texture comes out too faint to see (measure: the processed mask's mean alpha under a threshold you choose and report), default that upload to **Photo** instead, or say "This image is very light, so we're showing it as a photo."
   - **Busy state that can't be missed:** while processing, the upload tile shows the spinner **and** the surface's message line says "Processing…".
3. **Remove the temporary trace** before committing. `git diff public/index.html` shows only intended changes.

**Scope:**
- **May touch:** the upload code in `public/js/app.js` and `public/js/appearance.js`, `public/js/local-adapter.js` (timeouts and handlers only), related CSS in `public/css/lime.css`, and `TEND.md`.
- **May not touch:** the preset patterns (LIME-53 owns them), the sample files in `public/assets/patterns/` (don't delete or commit them), and everything else.
- If the survey turns up related issues, **raise them before fixing**. If a decision isn't covered here, **stop and ask the user**.

**Verification:**
- **In the real Firefox 156 app (not Playwright's bundled Firefox), with Chrome as a control:** every one of the 7 files, from both surfaces, visibly changes the background and selects the upload tile. Report a pass/fail table with the stage each failure stopped at **before** the fix and pass **after**.
- With a second Lime tab open: an upload either works or shows a clear message within ~10s. It never hangs.
- The same file twice in a row, and a new file right after, both work.
- Report the browser-parsed CSS rule counts for `lime.css` and `gradients.css`. The real app loads in jsdom with zero errors.

**Gate:** in Firefox, **hard-reload first (⌘⇧R)**. Then upload one of your images from the palette menu, and another from Settings. Each time, the background should visibly change and the upload tile should show your image. If it can't, a message should say why. Nothing should ever just silently do nothing.

**Record:** add a `## LIME-52-fix5` entry to `TEND.md`, including the stage-by-stage table and which cause it was. Commit: `fix: uploads never hang or apply invisibly (timeouts, visible result, busy message)`, trailer `Brief: LIME-52-fix5`, plus the attribution trailer. **Stop for the user's check.**

---

### LIME-53 → `tend` (after LIME-52-fix5): a pattern lab to choose new designs (no app changes)

**The user (2026-09-30):** get rid of the Subtle Patterns samples and credit, and **refine the patterns we have now.** On the current four (Dots, Grid, Diagonal, Noise): they **"look plain or cheap"** and the user **"wants different designs"**.

**Why a lab first (plot's steward lesson):** the appearance work took 8 build-and-QA rounds. Choosing designs from a single page of candidates costs one round instead.

**Assumptions:** the agent can write files and run Playwright (Firefox). **Every pattern is drawn by us as an inline SVG** (no third-party assets, so no credit is owed). Each renders as a **tinted mask**, exactly like today's presets (`appearance.js` `patternMaskSvg`, ~193): white shapes on transparent, recoloured by `--lime-pattern-tint`.

**The change:**
1. Create **`/Users/shem/Sites/lime-pattern-lab/index.html`, outside the repo** (not committed). It's a standalone page that opens by `file://`.
2. Include **12 candidates** as SVG mask tiles, with care for polish (fine strokes of 0.75–1px, generous spacing, tiles of 32–80px, seamless edges, and no visible repeat seams):
   - refined versions of the current 4: **soft dots** (sparser, offset rows), **fine grid** (hairline, larger cells), **pinstripe diagonal**, and **paper grain** (subtler noise);
   - 8 new: **waves**, **topography** (contour lines), **crosses/plus**, **circles** (overlapping rings), **hexagons**, **scales** (overlapping arcs), **chevron**, and **confetti** (small scattered strokes).
3. Show each candidate as a **labelled card at a realistic size** (~320×200) with a fake message bubble and a date divider on top, at **Low and Medium intensity** (today's 6% and 9% tint). Show it in **3 canvas tones** (Warm, Sage, Lemon: use the real `CANVAS_P` canvas colours from `appearance.js`) **and dark mode**. Number every card (1–12) so the user can answer "3, 7, 9, 11".
4. Screenshot the page with Playwright Firefox to check it renders, and that every candidate is visible but calm (text contrast is still ≥ 4.5:1 at Medium; reuse the method from LIME-52).

**Scope:**
- **May touch:** only the new folder `/Users/shem/Sites/lime-pattern-lab/`, plus a short note in `TEND.md`.
- **May not touch:** anything in the repo's `public/`. **No commit of project code;** commit only the `TEND.md` note.

**Verification:** the page opens over `file://` with no console errors; all 12 × (3 tones + dark) × 2 intensities render; contrast is ≥ 4.5:1 for every card at Medium (report any failure, don't hide it).

**Gate:** open `file:///Users/shem/Sites/lime-pattern-lab/index.html` in Firefox and pick your favourites by number (4 to 8). Say if any are close but need a tweak (bigger, finer, fewer).

**Record:** add a `## LIME-53` entry to `TEND.md` with the path and the candidate list. Commit only `TEND.md`: `docs: pattern lab for choosing preset designs`, trailer `Brief: LIME-53`, plus the attribution trailer. **Stop for the user's picks.** Plot then drafts **LIME-53b**, which (a) replaces the presets with the user's picks, (b) removes `USER_TILE_CANDIDATES`/`detectUserPatternTiles` (the file-name probing) and every Subtle Patterns/credit mention in code comments and `docs/`, and (c) deletes the 6 untracked samples in `public/assets/patterns/`. Stored appearance pointing at a removed preset falls back to None.

---

### LIME-52-fix4 → SUPERSEDED (never sent), 2026-09-30: the user dropped the Subtle Patterns samples and the credit. Replaced by LIME-52-fix5, LIME-53 and 53b. Kept for history.

### (old) LIME-52-fix4 → `tend` (after LIME-52-fix3, before LIME-49): the user's samples become the preset patterns

**The user (2026-09-29):** "can we use the samples I give as our starting patterns, instead of the ones we have now?" **Yes. They replace the 4 generated presets (dots, grid, diagonal, noise).**

**The samples (plot inspected them in `public/assets/patterns/`; all 400×400, none has an alpha channel):**
- `ripples.png`: 8-bit greyscale, subtle white-on-white waves.
- `geometry2.png`: **actually WebP**; faint grey scattered shapes (circles, triangles, squiggles).
- `ep_naturalwhite.png`: **actually WebP**; off-white paper with flecks.
- `leaves.png`: RGB; pale green leaf outlines on white.
- `bananas.png`: RGB; **full-colour** yellow bananas on teal.
- `cork-board.png`: RGB; **full-colour** cork texture.
- **The source is Subtle Patterns (CONFIRMED by the user, 2026-09-29: "they're from subtle pattern so please credit").** Toptal, licensed **CC BY-SA 3.0: attribution required, and adaptations (e.g. our tinted versions) are shared alike.** Credit: "Patterns from Subtle Patterns by Toptal (CC BY-SA 3.0)". The credit is required, not optional.

**The design:** one model for presets **and** uploads. Each has two looks, **Texture** and **Original** (this renames LIME-52-fix's "Photo" for clarity; **update the UI and docs**):
- **Texture** (the default for every preset): the tile turned into a **tone-tinted mask** (grayscale, then luminance inverted to alpha, then auto-levelled), repeating at Low/Medium intensity. It follows the canvas tone and light/dark mode, and is calm and on-brand.
- **Original:** the tile **as designed, in its real colours,** repeating (or, for large uploaded photos, covering) under the computed scrim that guarantees ≥ 4.5:1 for on-canvas text. Bananas and cork are loud, so the scrim does real work there.
- The Texture/Original toggle shows whenever a pattern (preset or upload) is active.

**Why a one-time build step:** Firefox treats every `file://` page as its own origin, so drawing a local asset into a `<canvas>` **taints** it (`getImageData` throws). Converting presets at runtime therefore won't work over `file://`. Uploaded files aren't affected, because they're same-origin blobs. So:
1. **Normalise the source files:** convert the two disguised WebPs to real PNGs with macOS `sips -s format png` (rename them so the extension matches the content), or keep them as `.webp` with the correct extension. Choose one and report.
2. **Generate the Texture masks once:**
   - use a small **Node + Playwright (Firefox)** script in the scratchpad (not the repo): read each file as bytes, pass it into a blank page as a **data URL** (not tainted), run the same luminance-to-alpha plus auto-level function the upload path uses (**share the function**; don't duplicate the maths), and write out `public/assets/patterns/texture/<name>.png` (alpha PNGs, ≤ 50 KB each ideally);
   - commit the generated files;
   - record the exact command in `TEND.md`, so adding a new preset later means dropping in a file and re-running it.
3. **A manifest replaces the name probing:** `public/assets/patterns/patterns.js`, loaded by a script tag and `file://`-safe, sets `window.LIME_PATTERNS = [{ id, label, original: 'ripples.png', texture: 'texture/ripples.png', credit: 'subtle-patterns' }, …]`. Labels: Ripples, Geometry, Natural white, Leaves, Bananas, Cork board. **Delete** LIME-52-fix's `USER_TILE_CANDIDATES` probing and the 4 generated SVG presets.
4. **The credit line** in Settings → Appearance (and a docs note) is generated from the manifest's `credit` values: "Patterns from Subtle Patterns by Toptal (CC BY-SA 3.0)".
5. **Stored appearance** referencing a removed preset (dots, grid, diagonal or noise) falls back to None without errors.

**Scope:**
- **May touch:** `public/assets/patterns/` (the normalised originals, the generated `texture/`, and `patterns.js`), `public/js/appearance.js` + `app.js`, `public/index.html` (the manifest script tag), `public/css/lime.css`, `docs/data-model.md` (credits, the manifest and the build step), and `TEND.md`.
- **May not touch:** the upload pipeline's behaviour from LIME-52-fix3, except sharing the conversion function and renaming Photo to Original.

**Verification (Playwright + Firefox):**
- The palette popover and Settings show exactly the 6 presets plus None and Upload, **4 per row**.
- **For each preset:** its Texture looks right in 2 tones and in dark; its Original shows the real colours; on-canvas text contrast is ≥ 4.5:1 in both looks (report the table); there are no fade bands.
- The old stored preset ids fall back cleanly.
- The generated textures exist and are committed, with their sizes reported.
- The credit line is visible.
- Report the browser-parsed CSS rule counts. The real app loads in jsdom with zero errors.

**Gate:** open the palette menu. Your six patterns are the presets. Each one is quiet and tinted by default (**Texture**), and **Original** shows it in its true colours with text still readable. The credit line shows in Settings.

**Record:** add a `## LIME-52-fix4` entry to `TEND.md`, including the build command. Commit: `feat: user's sample patterns as presets (Texture/Original), manifest, credits`, trailer `Brief: LIME-52-fix4`, plus the attribution trailer.

---

### LIME-52-fix3 → `tend` (next, before LIME-49): intermittent pattern-upload failures

**The user (2026-09-29):** "the pattern upload is still not functioning properly. Sometimes I upload a .png and it works, sometimes not. I tried in a private window as well. Everything else looks good."

**Plot's read of the code** (app.js ~295–311 `handleAppearanceUploadChange`; appearance.js ~395–420 `processUploadFile`): the flow is validate → decode (`new Image` plus an object URL) → build **both** the Texture and Photo canvases → two `toBlob` calls → two `uploadAttachment` writes → `applyPattern` → `setAppearance` → re-render, with `input.value` reset in `finally`.

**Hypotheses, to test (not to assume), most likely first:**
1. **Popover lifecycle:** the file picker opens *from inside the palette popover*. If opening the OS dialog (focus loss, or an outside-click or Escape path, or a re-render) closes or re-renders the popover, the `<input>` is **detached** before `change` fires. The delegated `change` listener on the menu then never sees it, **silently**. That would explain "sometimes" (it depends on timing) and it working from Settings but not the popover, or the reverse.
2. **Silent errors:** if `setError` isn't wired for a given surface, or the error element isn't visible, failures show nothing.
3. **Overlapping jobs:** a second pick while the first is still processing (large PNGs take a moment) causes a race in which a stale job's result overwrites the new one, or `rerender` replaces the input mid-flight.
4. **Heavy output:** the Photo form is saved as **PNG** at up to 1600px, which can be several MB for photos (slow `toBlob`, a large IndexedDB write). Consider JPEG at ~0.85 for the Photo form. Old uploads are never deleted, so IndexedDB grows with each try.
5. **Mislabelled files (plot found this in the user's own samples):** `public/assets/patterns/ep_naturalwhite.png` and `geometry2.png` are **WebP files with a `.png` name** (`file` reports "Web/P image"). If the user's failing uploads were files like these, check whether any extension- or MIME-based branch mishandles them (the browser reports `image/png` from the name while the bytes are WebP). Sniff the magic bytes, or rely only on a successful decode.
6. **Decode edge cases:** 16-bit, palette or interlaced PNGs, very large dimensions (over 8000px), and colour profiles. Check `naturalWidth`/`Height` of 0, and canvas size limits.
7. **Private windows:** IndexedDB in Firefox private browsing behaves differently (in-memory, some versions restricted). Detect a failed open or write and show a clear message instead of failing silently.

**The change:**
1. **Reproduce first, with a matrix:** from **both** the popover and Settings, and in a normal **and** a private (ephemeral) context, upload:
   - a small transparent PNG, a large opaque PNG photo (~4000px), a 16-bit PNG, a palette PNG and an interlaced PNG;
   - a JPG, a WebP, an SVG, and a 9.5 MB file;
   - **the same file twice in a row**, **two files quickly one after another**, and **an upload followed immediately by closing the popover.**
   Record pass or fail for each cell **and the failure reason** in `TEND.md`. **If the user has provided failing files** (see below), include them.
2. **Fix every root cause found.** At minimum, whatever the matrix shows:
   - **The file input must survive the picker:** keep a **single persistent hidden `<input type=file>`** outside the popover (at the document level), triggered by the Upload tiles, with its `change` handled directly, not by delegation from a container that can re-render or close. The popover must not close or re-render while the picker is open.
   - **One job at a time, latest wins:** a job token; stale results are discarded. Show a processing state on the Upload tile (a spinner or "Processing…"), and prevent a double pick while busy.
   - **Never fail silently:** every failure path shows an inline message in whichever surface started it, with a generic fallback: "Couldn't use that image. Try a different PNG or JPG." Log the technical error to the console.
   - **Lighter output:** the Photo form as JPEG at ~0.85; the Texture form as PNG (alpha needed). Cap canvases at safe sizes. Delete the **previous** upload's blobs from IndexedDB when a new upload replaces them (and on "None").
   - **Private windows:** detect IndexedDB unavailability or failure up front and show "Uploads need normal browsing (not private)". Or, if feasible, keep the processed result **in memory for the session** so it still works, with a note that it won't persist. Report which.
3. Keep everything that works (the treatments, the scrim maths, the toggle, the popover size).

**Scope:** the upload and processing code in `public/js/appearance.js` and `app.js`, the related markup and CSS, `public/js/local-adapter.js` (only for blob deletion if needed), and `TEND.md`.

**Verification:** the full matrix above re-run, **every cell passing** (or showing its intended friendly message), the report of what the original failure(s) actually were, IndexedDB blob count stable after 5 successive uploads, browser-parsed CSS rule counts, and the real app loading in jsdom with zero errors.

**Gate:** in Firefox, upload PNGs repeatedly from the palette menu and from Settings, including the same file twice and a big photo. It works every time or tells you clearly why not. In a private window, it either works for the session or clearly says it needs normal browsing.

**Record:** add a `## LIME-52-fix3` entry to `TEND.md`, including the matrix. Commit: `fix: reliable pattern uploads (persistent input, single job, no silent failures)`, trailer `Brief: LIME-52-fix3`, plus the attribution trailer.

---

### LIME-52-fix2 → `tend` (next, before LIME-49): a narrower palette menu, the upload tile preview and its ×, and a band under the composer

**The user's QA of LIME-52-fix (`345d749`, 2026-09-29, screenshots):**
1. **"Can we make the min width smaller?"** The palette popover is wide: 4-column grids of large (~76px) swatch circles and pattern tiles.
2. **The upload works, but its tile preview is broken:** it shows a solid dark square instead of the texture or photo. **The tile's delete × is cut off** (clipped at the tile's corner).
3. **"I still see a broken gradient or background under the main chat box."** With a pattern active, a **flat, pattern-less band** fills the bottom of the thread behind and around the composer.

**Root causes (plot read `lime.css` ~643–749 and ~4295–4311):**
- **The band:** `.lime-composer` (the full-width absolute bar) still has `background: var(--soil-bg-canvas)`, a solid canvas-coloured block that hides the pattern layer. Since LIME-50, the thread's own content is masked before it reaches the bar, so **the bar doesn't need a background at all.** Only `.lime-composer__box` (the input) and its controls need their surface.
- **The ×:** `.lime-pattern-tile__delete` sits at `top: -6px; right: -6px`, outside a tile that (plot suspects) has `overflow: hidden` or a clipping mask. The mask used for the Texture preview clips **all** its children, including the ×.
- **The preview:** likely the async `paintAttachments()` fill for `data-attachment-style="mask"`/`photo-bg` isn't running for pattern tiles, or it applies the mask to the wrong element. **Reproduce and report.**

**The change:**
1. **The composer bar is transparent:** `.lime-composer { background: transparent; }`, and update its comment. Verify the masked thread content still fades out **above** the composer box, and that the area around the box shows the canvas plus the pattern with **no band**, in light, dark, and with a Photo upload. If content would now show *through* the gap between the bar's edges and the box, extend the thread's bottom mask to cover the composer zone. Report which.
2. **Upload tile:**
   - **Structure:** the tile becomes a wrapper (`position: relative`, **no** clipping) containing (a) a preview element that carries the mask or background image and the radius, and (b) the × button as a **sibling** of the preview, not a child. The × can then sit on the corner without being clipped.
   - **The × style:** a 18px circle on `--lime-layer-raised`, with a `--soil-text` ×, a soft shadow, hover and focus styles, and `aria-label="Remove upload"`.
   - **Fix the preview fill** so Texture shows the tinted mask and Photo shows the image (cover), matching what's applied to the app.
3. **A narrower popover:**
   - swatches and pattern tiles become **28px** (circles for Canvas, rounded squares for Pattern) with an 8px gap, 4 per row, so the grid is 136px wide;
   - the popover takes padding plus the grid, **≈ 168–184px** wide;
   - Mode's segmented control and the Low/Medium and Texture/Photo toggles fit that width (smaller text, or full-width segments);
   - "More in Settings" stays;
   - **the Settings → Appearance grids keep their larger size** (the shared component takes a size variant);
   - hit targets stay ≥ 24px (WCAG 2.2 target size);
   - the selected ring stays visible at the smaller size.

**Scope:** the related rules in `public/css/lime.css`, the shared picker and pattern-tile markup and `paintAttachments` in `public/js/app.js`/`appearance.js`, and `TEND.md`.

**Verification (Playwright + Firefox):**
- The popover's width is reported (target ≤ 184px) and it's fully on-screen.
- The swatch and tile rects are 28px with 8px gaps; the Appearance grids are unchanged.
- The upload tile shows the correct preview for Texture **and** Photo (report computed `mask-image`/`background-image` non-empty), and the × is fully visible (its rect is not clipped: `elementFromPoint` at its centre hits the ×).
- **No band:** sample pixels across the bottom 120px of the thread with the dots pattern active. The pattern's dots appear right up to the composer box's edges; report the sample positions.
- Report the browser-parsed CSS rule counts. The real app loads in jsdom with zero errors.

**Gate:** in Firefox:
- **Palette menu:** it's compact, with small swatches in rows of 4.
- **Your upload:** its tile shows a preview, and its × is fully visible.
- **Around the message box:** with a pattern on, the pattern runs right up to the message box, with no flat band.

**Record:** add a `## LIME-52-fix2` entry to `TEND.md`. Commit: `fix: compact palette popover, upload tile preview and delete, no band under composer`, trailer `Brief: LIME-52-fix2`, plus the attribution trailer.

---

### LIME-52-fix → `tend` (next, before LIME-49): patterns in the palette popover with live preview; 4-per-row swatches; a tidy Pattern row; user-supplied pattern tiles

**The user's QA of LIME-52 (`c2964be`, 2026-09-29, screenshots):**
1. "The patterns need to come into the palette dropdown so that you can preview the changes in real time." The header palette popover currently has only Mode, Canvas and "More in Settings".
2. "We can make the palette dropdown 4 colours per line, so the dropdown takes up less width." It's currently 8 swatches in one row.
3. **(Plot's observation)** In Settings → Preferences, the Pattern row is untidy: the thumbnails and "+" wrap onto their own line, with the Low/Medium toggle and a free-floating "Remove" text button beneath. The Canvas swatches crowd the right edge.
4. **The user will provide example patterns.** Plot told the user the format: **SVG (preferred) or PNG with a transparent background**, one colour on transparency, **a seamless tile**, 100–400px square (PNG at 2×), ideally ≤ 50 KB, saved in `public/assets/patterns/`. Presets render as **tinted masks** (alpha only), so the file's colour doesn't matter. Suggested source: **Hero Patterns** (transparent SVG tiles, **CC BY 4.0, attribution required**). Subtle Patterns tiles are opaque textures and need converting.

**The change:**
1. **The popover gains Pattern:** the header palette popover shows **Mode**, **Canvas** (a **4-column** swatch grid), **Pattern** (a 4-column thumbnail grid: None, the presets, and an "Upload" tile; with the Low/Medium intensity toggle shown only when a pattern is active) and "More in Settings". **Every choice applies live** (that's already the case; confirm for patterns). The popover width shrinks to fit 4 columns (≈ 4 × 40px swatches plus gaps plus padding). Measure it and make sure it stays fully on-screen (the LIME-20 clamp).
2. **One shared picker component** renders Canvas and Pattern in both the popover and Settings → Appearance. **Don't keep two copies.**
3. **The Settings → Appearance layout:** use the same 4-column grids for Canvas and Pattern, left-aligned under each row's label (the label above the grid, as a stacked row), with intensity as a small segmented control beside the "Pattern" label. **"Remove" is replaced by the "None" tile** (delete the separate button). An uploaded pattern appears as its own tile, with a small × to delete it. It fits without scrolling (it'll be shared with LIME-49's modal sizing).
4. **User-supplied tiles:**
   - **if** files exist in `public/assets/patterns/` when this runs, add them as presets **after** the 4 built-ins: SVGs used directly as masks; transparent PNGs as masks; opaque PNGs **converted** (luminance to alpha, on a canvas, at load, cached) with a note in `TEND.md`;
   - show the file names as tooltips;
   - add the credit line for their source (ask the user in `TEND.md` if it's unknown; e.g. "Patterns from Hero Patterns (CC BY 4.0)") in Settings → Appearance and in the docs;
   - if the folder is still empty, skip this and note it.

5. **Uploads that work tastefully with any everyday image** (user, 2026-09-29: "I tried uploading a .png pattern and it didn't show. I imagine everyday teachers would upload PNG, JPG, whatever, so how do we make that work tastefully, not only with SVGs?"; the user will also supply some SVGs for presets):
   - **Diagnose first:** reproduce the user's PNG upload failure and report the **root cause** (a size-limit rejection, an opaque image blending away under `mix-blend-mode`, a MIME check, a storage error, …) before redesigning.
   - **Accept** PNG, JPG/JPEG, WebP, GIF (first frame) and SVG. Show a friendly inline message for unsupported ones (e.g. HEIC: "Please export as JPG or PNG"). Take files **up to 10 MB**.
   - **Process once, at upload, on a canvas** (never live on every paint). Store only the processed result, via `uploadAttachment`, in IndexedDB.
   - **Two treatments, auto-chosen with a user toggle ("Texture" / "Photo")** in the Pattern area once an upload is selected:
     - **Texture** (the default for small or square-ish images ≤ 600px, or anything the user marks as Texture): convert to **grayscale, then luminance to alpha**, auto-levelled (stretch the contrast so faint textures still register, and cap density so busy images don't turn noisy), then downscale to a ≤ 400px tile. It's then used **exactly like the presets:** a tinted mask coloured by the tone and mode, repeating, at Low/Medium intensity. This makes *any* photo or texture look on-brand and calm.
     - **Photo** (the default for larger images): a full-bleed, fixed layer behind all panels (`background-size: cover`), **softened** (downscaled to ≤ 1600px, plus a slight blur of ~8–12px baked in at processing time) under a **tone-coloured scrim** (the canvas colour at high opacity; dark-mode aware). **The scrim opacity is computed to guarantee ≥ 4.5:1 for on-canvas text** (date dividers, names, times) against the photo's darkest and lightest regions: measure the processed image's luminance range and set the scrim accordingly, with a floor of ~75%. Panels and surfaces stay tone layers (LIME-50-fix), so reading areas are never over busy imagery.
   - **The fades** (LIME-50 masks) need no change. Verify with a Photo upload.
   - **Accessibility:** `prefers-contrast: more` hides uploads, as it does presets. `prefers-reduced-transparency`, where supported, raises the scrim.
   - **Production note for the docs:** uploads become objects in a user-scoped storage path (`appearance/<userId>/pattern`). The processing stays client-side.

**Scope:** the palette popover and Appearance markup and JS, the shared picker, the upload processing (canvas), the related `lime.css` rules, the `public/assets/patterns/` reading, `docs/data-model.md` (only for credits and the tile format), and `TEND.md`.

**Verification (Playwright + Firefox):**
- The popover shows a 4-column grid for Canvas and Pattern (report the width, and that it's on-screen at 1567 and 767px).
- Picking a pattern in the popover updates the app immediately without closing it.
- The Settings Appearance grids match the popover.
- There's no separate "Remove" button; "None" clears the pattern.
- Any user tiles load, and recolour across 2 tones and dark.
- **Uploads:** the user's failing-PNG root cause is reported and fixed. Upload a real JPG photo, a real opaque PNG texture and a transparent PNG from the scratchpad. Each renders **visibly but subtly** in the right treatment (Texture or Photo), the toggle switches it, it persists across reload, and the on-canvas text contrast is ≥ 4.5:1 in light and dark (report the measured values). HEIC gets the friendly message; an 11 MB file is rejected clearly.
- Report the browser-parsed CSS rule counts. The real app loads in jsdom with zero errors.

**Gate:** click the palette icon. Canvas and Pattern both sit in tidy rows of 4, and trying a pattern changes the app live behind the menu. Settings → Appearance looks the same and tidy. **Upload an everyday PNG or JPG:** it shows up tastefully, as a soft texture or a softened photo behind the app, and you can switch between Texture and Photo.

**Record:** add a `## LIME-52-fix` entry to `TEND.md`. Commit: `fix: patterns in palette popover with live preview, 4-column grids, tidy Appearance`, trailer `Brief: LIME-52-fix`, plus the attribution trailer.

---

### LIME-50-fix → `tend` (before LIME-51): every neutral layer derives from the chosen tone (surfaces, hovers, selected states, toggles, bubbles)

> **Amended 2026-09-29: LIME-51 (dark mode) landed FIRST, as `d44b4be`.** This brief never ran before it. So this brief now defines the layer tokens for **both** themes: the light values as below, **and the dark values** (mixing toward white) under `[data-theme="dark"]`, replacing whatever per-token dark values LIME-51 relied on for these same fills (surface, hovers, selected states, borders). Verify **both** modes: the 8 tones in light, plus dark. Don't regress LIME-51's fixes (the body text colour, the dark avatar pastels, the scrollbar thumb).

**The user's QA of LIME-50 (2026-09-29, screenshots on the lemon and sage tones):**
- "the toggle, chat bubbles, the chatbox mic with chevron (no background by default, like the plus), and the hover and active states in the Messages section of the center panel all need to be dynamic and relate to the chosen background colour, or they look visually broken. They need balance, contrast, and a minimal aesthetic, but modern and timeless."
- **In the screenshots:** on lemon and sage canvases, the segmented toggle track and its active pill, the chat bubbles, the composer box, the selected and hovered list rows, and the mic pill all stay **warm beige/grey** (the old Warm tone's values), so they clash with the tinted canvas.

**Root cause (plot read `lime.css` ~20–50):**
- **LIME-50 routed only `--soil-bg-canvas` through the ramp.** `--soil-bg-surface` is still hard-coded `#f0eee6`.
- **Seed's `--calm-bg-subtle-*`/`--calm-bg-normal-*` map to ramp stops *between* the ones `CANVAS_P` retunes** (soil-25, 30, 40, 50 and 75 aren't in `SOIL_K`), so hover, active and subtle fills never follow the tone.
- The mic pill has a permanent `--calm-bg-subtle-default` fill (~4447).

**The design:** one **relative layer system,** derived from the canvas with `color-mix(in oklab, …)`, so **any** tone (and dark mode in LIME-51) stays in balance by construction. Defined once on `:root` (and adjusted under `[data-theme="dark"]` in 51), **then Seed's semantic tokens are remapped to it**, so every component follows without per-component edits.
- **Canvas:** `--soil-bg-canvas` (the tone).
- **Raised**, for things that should lift (the segmented active pill, menus, modals, popovers): light mode mixes the canvas with white (~70% white); dark mixes it with white at ~8%.
- **Surface**, for resting filled elements (chat bubbles, the composer box, the segmented track, input fields, the search field): the canvas mixed ~4% toward the ink (black) in light, ~6% toward white in dark.
- **Hover:** ~6% toward the ink (light), ~9% toward white (dark).
- **Active/selected** (the selected list row, a pressed state): ~9% toward the ink, ~12% toward white.
- **Border-subtle:** ~10% toward the ink, ~14% toward white.
- The exact percentages are **tuned by measurement**, not guessed. Targets across **all 8 tones**:
  - body text on surface, and on active, ≥ 4.5:1;
  - muted text on surface ≥ 4.5:1;
  - **surface vs canvas, hover vs surface, and active vs hover each clearly distinguishable** (ΔL in OKLab ≥ ~0.02–0.03, tuned by eye on screenshots and reported);
  - the raised pill vs the track is distinguishable.
  Pick one set of percentages that works for all 8 tones. Report the table.

**The change:**
1. **Define the layer tokens:** `--lime-layer-raised`, `--lime-layer-surface`, `--lime-layer-hover`, `--lime-layer-active` and `--lime-border-subtle`.
2. **Remap** `--soil-bg-surface`, `--soil-bg-elevated`, `--calm-bg-subtle-default/-hover/-active`, `--calm-bg-normal-default/-hover`, `--soil-border-subtle` and `--calm-border-normal-default` to them in Lime's theme block. List every remapped token, and **grep for components using hard-coded fills** that bypass the tokens (the segmented pill, list-row selected and hover, bubbles, the composer box, the search fields, the mic pill, the avatar-trigger hover, menus, the settings nav, the lightbox bar). Route each through a token.
3. **The mic and chevron button** has **no background at rest,** like the + button; hover and active use the layer tokens.
4. **The lime accent** (the nav active, the primary Send, the unread ring) is unchanged. Check that it still reads on every tone (≥ 3:1 for the non-text fills against the canvas); report it.
5. **Timeless and minimal:** no new shadows or gradients. Rely on the tonal layering, and keep radii as they are.

**Scope:** the theme and token block and any bypassing component fills in `public/css/lime.css` (and `gradients.css` if touched), and `TEND.md`. **No JS**, except removing any inline style colours if found.

**Verification (Playwright + Firefox, all 8 tones, 1567×905):** screenshots of the Messages view with a row hovered and one selected, the segmented toggle, bubbles and the composer (paths in `TEND.md`); the contrast and ΔL table; no hard-coded fill left on the listed components (grep); the mic pill transparent at rest; the real app in jsdom with zero errors.

**Gate:** in Firefox, switch between tones (Warm, lemon, sage, lilac, blue). The toggle, bubbles, message box, hovered and selected chats, and the mic button all shift with the tone, staying balanced, clear and quiet on each one.

**Record:** add a `## LIME-50-fix` entry to `TEND.md`. Commit: `fix: tone-relative layer system for surfaces, hovers and selected states`, trailer `Brief: LIME-50-fix`, plus the attribution trailer.

---

> **Shared context for LIME-50, 51 and 52: app-wide appearance, replacing per-chat backgrounds.** User, 2026-09-29, with screenshots:
> - "The chat feature needs to be simplified: think two modes, light/dark, and patterns (preselected, or upload your own)" (source: <https://www.toptal.com/designers/subtlepatterns/>).
> - "It should change the entire body, not just the chat area."
> - "Reference Seed's customise background colours, thinking about colour theory and accessibility."
>
> **The screenshots:** LIME-45's per-chat colour paints only the chat card (a saturated green block beside cream panels), which looks broken. The user's example tints **every panel** with one pale tone, which looks right.
>
> **Plot's survey of Seed's brand customiser** (`vendor/seed/components/layout/layout.html` ~60–100): it retunes the **entire neutral (soil) ramp** from one canvas choice.
> - Presets are in `CANVAS_P`: `warm` (today's default), `cool-gray`, `warm-cream`, `blue-tint` and `pure-white`, each 11 stops.
> - `makeCanvasRamp(hex)` builds a ramp from any colour **with saturation heavily attenuated** (≤ 8%) and lightness clamped, "so dark stops stay warm-grey, never golden". That's the colour-theory safeguard: canvases stay pale, and every semantic token derived from the ramp keeps its contrast.
> - **The canvas applies in light mode only.** Dark mode comes from Seed's `[data-theme="dark"]` tokens (tokens.css ~264).
>
> **Plot's decisions (flag at the gates; the user declined further questions for now):**
> - **App-wide, not per chat.** The per-chat background feature from LIME-45 is **removed** (code reverted; the docs keep a note).
> - **Where it lives:** Settings → Preferences → **Appearance**. The header palette button stays as a **shortcut** that opens the same Appearance controls (the user's example still shows it); remove it at the gate if unwanted.
> - **Stored per user** in `user_settings` (`theme`, `canvas`, `pattern`). Local: the store snapshot, with pattern uploads in IndexedDB.
> - **Colours come from Seed's method,** never raw saturated swatches.
>
> **Order:** LIME-50 → 51 → 52, then LIME-49 and the rest of the queue.

### LIME-50 → `tend`: the appearance foundation: one app-wide canvas tone (Seed's method), background-agnostic fades, and per-chat backgrounds removed

**The change:**
1. **Remove per-chat backgrounds:**
   - revert LIME-45's per-chat code: `setChatBackground` per conversation, the per-chat `--surface-bg` override on `.lime-chat-body`, and the popover's per-chat UI;
   - keep `TEND.md` and add a note to `data-model.md`: "per-chat backgrounds removed on 2026-09-29 in favour of app-wide appearance";
   - in the schema, drop `conversation_members.background` from the docs and keep `user_settings` with `theme`, `canvas` and `pattern`;
   - **store:** `getAppearance()` and `setAppearance(patch)`, emitting `lime:appearance-changed`.
2. **Canvas tone, applied app-wide:**
   - **port Seed's approach:** the `CANVAS_P` presets plus `makeCanvasRamp` (copied into Lime with attribution to Seed, since `vendor/` can't be edited), applying the 11 soil stops on `:root` so **every** surface, panel, text, border and fade updates together;
   - **presets:** Seed's 5 (Warm is the default, today's look), plus **2–3 extra pale tints generated through `makeCanvasRamp`** (e.g. a soft lemon like the user's example, a soft sage, a soft lilac). **Every preset must pass:** body text on canvas ≥ 4.5:1, muted text ≥ 4.5:1, bubble surface vs canvas ≥ 1.1:1 luminance difference (so bubbles remain distinguishable), and borders ≥ 1.5:1. Report a table and drop any preset that fails;
   - **unify the panels:** the list column, the center and the right panel all show the **same canvas** (the user's example). Replace the right panel's distinct flush colour and any other panel-specific backgrounds with the canvas ladder (canvas, then surface for cards and bubbles, then elevated for menus and modals). Report which rules changed.
3. **Fades become background-agnostic,** because patterns (LIME-52) and tones must never show bands:
   - convert the LIME-46 overlay fades to **CSS masks on the scroll content** (`mask-image: linear-gradient(to bottom, transparent, #000 32px, #000 calc(100% - 48px), transparent)`, per side, toggled by the existing scroll-state classes), so content fades into **whatever** is behind it: tone, pattern or photo;
   - keep the pinned-frame structure only where still needed;
   - the composer fade becomes a mask on the thread above the composer;
   - verify with a **checkerboard test background** (a temporary diagnostic): there's no band at any fade, and the pixel samples in the fade zone show the background unchanged where content is absent.
4. **The Appearance UI:**
   - Settings → Preferences (a new nav item) → **Appearance**: a "Canvas" row with round tone swatches (name tooltips, the current one marked). **Mode** and **Pattern** rows are added in 51 and 52.
   - The header shortcut (the palette icon: an inline SVG matching the dew stroke style; replace the sun) opens a compact popover with the same controls plus "More in Settings".
   - Changes apply live and persist.

**Scope:** `public/js/store.js` + `local-adapter.js`, `public/js/app.js`, `public/css/lime.css` + `gradients.css`, `public/index.html`, `docs/data-model.md` + `docs/schema.sql`, and `TEND.md`.

**Verification (Playwright + Firefox):**
- Per-chat background code is gone (grep for it).
- Each preset retunes every panel identically: sample the list column, the thread and the right panel background (all equal).
- The contrast table is reported.
- The checkerboard fade test passes.
- It persists across reload.
- The real app loads in jsdom with zero errors.

**Gate:** in Firefox:
- **Tones:** Settings → Preferences → Appearance (or the palette shortcut). Pick a tone, and the **whole app** changes together, staying pale and readable like your example.
- **Fades:** they still blend, with no bands.
- **Shortcut:** tell tend whether to keep the header palette shortcut.

**Record:** add a `## LIME-50` entry to `TEND.md`. Commit: `feat: app-wide canvas tones (Seed method), masked fades; per-chat backgrounds removed`, trailer `Brief: LIME-50`, plus the attribution trailer.

---

### LIME-51 → `tend` (after LIME-50): dark mode: an app-wide design pass

**Why it's its own brief:** Lime was built light-only. `lime.css` has light-only overrides (`[data-theme="light"]` canvas and surface), literal `rgba(...)` values, and theme-invariant avatar pastels. A switch alone would expose unfinished screens (the reason for the "light only" call on 2026-09-27; now the user wants two modes).

**The change:**
1. **The mode control:** Appearance gets **Mode: Light / Dark / System** (System follows `prefers-color-scheme`, live). It sets `data-theme` on `<html>`, stored in `user_settings.theme`, and **replaces** the old `lime-theme` `localStorage` read at app.js ~4. **Apply it before the first paint** (a tiny inline script in `<head>`) so there's no flash of light theme. It also applies on `login.html` and `signup.html`.
2. **The canvas tone** applies in light mode only (as in Seed). In dark mode, the tone swatches show as disabled, with "Tones apply in light mode".
3. **Audit and fix:**
   - list every hard-coded colour in `lime.css`, `gradients.css` and the inline styles (`#hex`, `rgb()`, `rgba()`), and replace each with a Seed token or a Lime token defined for **both** themes;
   - add Lime's `[data-theme="dark"]` values where light-only overrides exist (canvas and surface);
   - **the avatar pastels** stay recognisable but get dark-mode variants with ≥ 4.5:1 initials contrast;
   - **the lime accent** in the nav and primary buttons: pick the dark-mode lime step from Seed's ramp that passes 4.5:1 for text on it, or 3:1 for the non-text fill.
4. **Every view** in dark mode: lists, the thread (bubbles, reactions, the reply summary, link cards, file cards, albums), the composer and toolbar, menus, the settings modal, the lightbox and wall, the search modal, dialogs, toasts, the details and members panels, and login/signup.

**Verification (Playwright + Firefox):** screenshots of each of those views in dark **and** light (as file paths in `TEND.md`), a contrast table for the text and UI tokens in dark, grep proof that no raw colour literals remain outside token definitions (list any justified exceptions), no flash on reload in dark, and System mode following a simulated `prefers-color-scheme` change.

**Gate:** switch to Dark. Every screen looks finished and readable, and switching back to Light (and each tone) still looks right.

**Record:** add a `## LIME-51` entry to `TEND.md`. Commit: `feat: dark mode (app-wide design pass)`, trailer `Brief: LIME-51`, plus the attribution trailer.

---

### LIME-52 → `tend` (after LIME-51): background patterns: curated presets or upload your own, across the whole app

**Sources:**
- the user suggested **Subtle Patterns** (<https://www.toptal.com/designers/subtlepatterns/>);
- **licensing:** Subtle Patterns are free to use under **CC BY-SA 3.0, which requires attribution.** Tend: confirm the current terms on the site's license page if you can reach it; otherwise record it as "to verify". Add a visible credit (Settings → Appearance → a small "Patterns from Subtle Patterns (CC BY-SA)" line) and a note in `docs/`;
- **tend's sandbox can't download,** so the user saves **4–6 chosen patterns** (seamless PNG tiles) into `public/assets/patterns/` (e.g. `paper.png`, `linen.png`, `dots.png`, `grid.png`). If the folder is empty when this runs, **generate 4 subtle patterns as inline SVG/CSS** (dots, grid, diagonal lines, noise) as the built-in set, and flag it.

**The change:**
1. **The Pattern row** in Appearance: None (the default), the preset thumbnails, and "Upload your own…". An upload is an image tile (≤ 1 MB, stored in IndexedDB via `uploadAttachment`, path `appearance/pattern`), repeated.
2. **Applied to the whole app canvas:** one fixed background layer behind all panels (`body` or a dedicated `.lime-app-bg` layer), repeating, at a **user-invisible-by-default intensity**. Panels are transparent over it (after LIME-50's unification), while bubbles, cards, menus and modals stay opaque surfaces.
3. **Works in both modes and every tone:**
   - presets render as **tinted masks** (the pattern as `mask-image` over a layer coloured from the soil ramp at low alpha), so they recolour with the tone and mode automatically;
   - uploaded images use `background-blend-mode`/`mix-blend-mode` with an intensity cap (`multiply` in light, `screen` in dark), plus a scrim if needed;
   - **accessibility:** measure the text directly on the canvas (date dividers, names, times) against the **darkest and lightest** pattern pixels, which must be ≥ 4.5:1. Provide an **"Intensity" slider** (Low / Medium) if needed to guarantee it. Also check `prefers-contrast: more`: patterns are hidden, or at minimum intensity.
4. The fades (LIME-50 masks) need no change. Verify.

**Verification (Playwright + Firefox):**
- every preset in light (2 tones) and dark: screenshots, the min and max contrast of on-canvas text, and no fade bands;
- an upload works and persists across reload;
- None restores the plain canvas;
- `prefers-contrast` behaves as specified.

**Gate:** Settings → Appearance → Pattern. Pick a preset or upload your own. It sits subtly behind the **whole** app, in light and dark, and everything stays readable.

**Record:** add a `## LIME-52` entry to `TEND.md`. Commit: `feat: app-wide background patterns (presets and upload)`, trailer `Brief: LIME-52`, plus the attribution trailer.

---

### LIME-45-fix → SUPERSEDED (never executed) by LIME-50/51/52 (app-wide appearance). Kept for history.

### LIME-45-fix → `tend` (next, before LIME-49): simpler backgrounds: per chat in the popover, the global default in Settings → Preferences; a palette icon

**LIME-45 landed as `a07b204`.** Plot reviewed it:
- Using `--surface-bg` instead of the brief's `--chat-bg` is **correct**; it's what the brief's "builds on LIME-46" meant.
- "Apply to all chats" silently overwrote existing per-chat picks.

**The user's decisions (2026-09-29):**
- "This feature needs to be simplified: think manual, one per chat. Then in Preferences you can do global changes."
- **Replace the sun icon with a custom palette icon.**

**The change:**
1. **The popover is per chat only.** Remove the "Apply to all chats" checkbox and its logic from the popover. The popover's "Reset" becomes **"Use default"**: it clears this chat's override, so the chat shows your default.
2. **A new Settings section, "Preferences"** (a nav item under Account, after Login & security, with a sliders-style icon from dew or neutral inline SVG):
   - for now it holds one row, **"Default chat background"**, with a compact preview swatch and a "Change" control. It opens the **same picker component** as the header popover (factor it into one reusable picker; don't duplicate it), but it writes the **default** (`setChatBackground(null, …)`);
   - add the muted description "Used in every chat where you haven't picked a background";
   - the Preferences layout follows the LIME-31-fix row style, and the modal still fits without scrolling (LIME-49 targets the same).
3. **Precedence stays:** a chat's own pick, then your default, then the app default. No destructive bulk overwrite anywhere.
4. **Palette icon:** an inline SVG paint palette drawn to **match the dew icon style** (the same stroke width, rounded caps and joins, 24px viewBox, `currentColor`), used for the header button. Add it where the other inline SVGs live (or as a small icon helper), with `aria-label="Chat background"`.
5. **Docs:** update the background section of `data-model.md` (the popover is per chat; the default is set in Preferences; no apply-to-all). The schema is unchanged.

**Scope:** the background popover and picker code in `app.js`, the settings markup and JS (the Preferences section), the related `lime.css` rules, `index.html` (the icon and settings nav), `docs/data-model.md`, and `TEND.md`. The store API is unchanged.

**Verification (Playwright + Firefox):**
- The popover has no apply-to-all.
- Setting a default in Preferences changes every chat without an override, and a chat with its own pick keeps it.
- "Use default" on that chat switches it to the default.
- Everything persists across reload.
- The icon renders at the same visual weight as its neighbours (screenshot).
- The Settings modal with Preferences fits without scrolling.
- The real app loads in jsdom with zero errors.

**Gate:** in Firefox:
- **Header:** the palette icon changes only this chat's background.
- **Default:** Settings → Preferences → Default chat background changes every chat you haven't customised.
- **"Use default"** puts a customised chat back to your default.

**Record:** add a `## LIME-45-fix` entry to `TEND.md`. Commit: `fix: per-chat backgrounds; default in Settings → Preferences; palette icon`, trailer `Brief: LIME-45-fix`, plus the attribution trailer.

---

### LIME-49 → `tend` (after LIME-54; amended 2026-09-30): Settings Profile fits without scrolling; real profile photo upload

**The user's QA (2026-09-29, screenshot):** "the profile section still needs tightening up. I'd rather the modal expand than have a scroll for one field. Also the profile picture alignment, and remove the Soon badge etc., can be cleaned up."
- **In the screenshot:** the Profile pane scrolls just to reach Bio (LIME-31-fix measured ~106px of overflow). The avatar and "Upload photo" + "Soon" are stacked awkwardly in a narrow column to the left of Display name, misaligned with it.

**The change:**
1. **The modal grows to its content:**
   - the settings modal's height becomes `min(content height, 100vh - 64px)` instead of a fixed `min(720px, …)`;
   - **Profile must not scroll at 1567×905.** Only on genuinely short viewports does the body scroll (with the footer still fixed);
   - keep the width;
   - Login & security can simply be shorter.
2. **The photo row** (Notion-style, cleaned up):
   - **a 64px avatar on the left, vertically centred with the Display name field** on the right, which takes the remaining width;
   - under the avatar, or as a text button beside the name label, a neutral **"Change photo"** link. **Remove the "Upload photo" button and the "Soon" badge.**
3. **Real profile photos,** since LIME-38 gave us the storage:
   - "Change photo" (or clicking the avatar, with a hover overlay reading "Change") opens an image picker (`image/*`, ≤ 5 MB);
   - the image is **center-cropped to a square** and resized to 256px on a canvas, then uploaded via `LimeStore.uploadAttachment` into a `profile-photos/<profileId>` path;
   - set `profiles.avatar_url` (the column already exists in the schema) through `updateProfile` (**allow `avatar_url`** in its field allow-list, and document it);
   - "Remove photo" appears when one is set.
   - **Production:** a Supabase Storage bucket `avatars`, publicly readable, writable only by the owner. Document it.
   - **This is part of the form:** it saves with "Save changes" and reverts with Cancel.
4. **Avatars everywhere show the photo:** `paintAvatar` (app.js ~1285) renders an `<img>` (`object-fit: cover`, rounded) when the profile has `avatar_url`, and falls back to initials otherwise. It updates live on `lime:profile-changed`. It covers every avatar: lists, the Recent row, the thread, replies, headers, clusters, members, details, and the sidebar.

**Amendment (plot, 2026-09-30, before sending): lessons from the pattern upload (LIME-52-fix3/fix5).**
- **The photo picker's `<input type=file>` must not live inside markup that re-renders** (the settings pane's `innerHTML`). Reuse fix3's pattern: one persistent, document-level input with its own `change` listener, and a record of which caller opened it. **Share it with the pattern upload if that's clean; otherwise add a second one.** Report which.
- **Never fail silently:** a busy state while processing, a friendly inline error on every failure path, and a timeout on storage writes (fall back to a clear message).
- **Verify the photo upload in the real installed Firefox** (`/Applications/Firefox.app`, driven as in LIME-52-fix5), not Playwright's bundled Firefox, **and** in Chrome. Report which binaries were used.
- **The pattern upload is parked** because it fails in the user's own Firefox but not in tend's. If the profile photo fails the same way at the user's gate, **don't fix it inside LIME-49.** Note it in `TEND.md` as evidence for the parked bug.
- The Settings modal has changed since this brief was drafted (Preferences → Appearance, from LIME-50 to 52-fix5). Survey the current markup first; the line numbers above are stale.

**Scope:** the settings markup and CSS, `paintAvatar`, the store's `updateProfile` allow-list, `local-adapter.js` (only if needed for the photo path), `docs/data-model.md` + `docs/schema.sql` (the avatars bucket note), and `TEND.md`.

**Verification (Playwright + Firefox):**
- At 1567×905 the Profile body doesn't scroll (report its `scrollHeight` against `clientHeight`) and the modal fits the viewport.
- The avatar's vertical centre equals the Display name field's (±2px).
- There's no "Soon" badge and no "Upload photo" button.
- Upload a photo from the scratchpad: after Save, the avatar shows it in 5 different places (report which); Cancel reverts; Remove restores the initials.
- It persists across reload. A group avatar cluster shows the photo for that member.
- The real app loads in jsdom with zero errors.

**Gate:** open Settings → Profile. Everything fits with no scrolling, and your picture sits neatly beside your name. Click "Change photo", pick a picture and Save. Your photo appears across Lime.

**Record:** add a `## LIME-49` entry to `TEND.md`. Commit: `feat: settings profile fits; real profile photos across the app`, trailer `Brief: LIME-49`, plus the attribution trailer.

---

### LIME-43-revert → `tend` (next, before LIME-44): remove the ✓/✓✓ receipts

**The user (2026-09-29):** "the check feature doesn't read, remove it. We can use notifications for that to start, and bring it back later if needed."

**Plot checked:** LIME-43 (`c1516a6`) is **the latest commit and purely additive** (TEND.md +21, data-model.md +67, lime.css +38, app.js +73, store.js +39; no deletions). So a clean revert of the code is safe, and reinstating it later is just "revert the revert".

**The change:**
1. `git revert --no-commit c1516a6`
2. **Keep the history and the design:** restore `TEND.md` and `docs/data-model.md` to their current versions (`git checkout HEAD -- TEND.md docs/data-model.md`), so the LIME-43 record and the receipts design stay documented.
3. In `docs/data-model.md`'s receipts section, add at the top: "**Removed from the UI on 2026-09-29 (user decision).** The derivation from `last_read_at` stays valid. To reinstate, revert the LIME-43-revert commit."
4. **Keep everything `last_read_at` powers:** unread rings (LIME-36) and `markRead` must be untouched. The revert only removes LIME-43's additions. Confirm nothing from LIME-36 changes.
5. The z-index stacking fix that LIME-43 added for the tick goes too, since it only existed for the tick. Confirm the message action bar still behaves as before LIME-43.

**Verification:**
- `git diff a67d834 -- public/` shows **no differences** (the code is identical to before LIME-43).
- `TEND.md` and `data-model.md` keep their LIME-43 content, plus the note.
- The real app loads in jsdom with zero errors. The Recent unread ring still clears when a chat is opened.

**Gate:** in Firefox, your messages no longer show ✓ or ✓✓. Unread rings in Recent still work.

**Record:** add a `## LIME-43-revert` entry to `TEND.md`. Commit: `revert: remove delivered/viewed receipts from the UI (design kept in docs)`, trailer `Brief: LIME-43-revert`, plus the attribution trailer.

---

### LIME-48 → `tend` (next, after the user's checks of 33-fix and 49-fix; amended 2026-09-30): redesigned sign in and sign up, Claude-style

**The user's direction (2026-09-29):** "prioritise for the future. I want to update our sign in and sign up flows to have more of a feeling like this", referencing Claude's login page:
- a **two-column** layout: on the left, the logo top-left, a large serif-feel headline, a one-line subline, a soft rounded card containing "Continue with Google", "Continue with Apple", "OR", an email field, a primary "Continue with email" button and small legal text, and a secondary button under the card;
- on the right, a **large rounded photo** filling most of the height.

**It depends on LIME-33** (local accounts: `LimeAuth.signUp`/`signInWithPassword`). This brief is the **UI and flow** on top of it.

**Plot's design decisions, flagged for the user:**
- **One email-first flow replaces separate login and signup pages:** enter your email, then Continue.
  - **An existing account** (local credential or seed teacher) goes to a password step ("Welcome back, <first name>").
  - **A new email** goes to a create-account step (display name and password, plus the terms checkbox).
  - "Use a different email" goes back.
  - `login.html` and `signup.html` both render this flow, and `signup.html` opens at the create step when given an email. Or consolidate into one `auth.html` and redirect the other two; tend chooses and reports.
- **Google and Apple buttons** are shown with a small "Soon" tag and disabled, until Supabase OAuth exists. **Production:** `supabase.auth.signInWithOAuth({ provider })`. Add it to the switch checklist.
- **Visual:**
  - **Colours:** Lime's canvas background; the card on `--soil-bg-elevated` with a soft shadow; **the primary button is lime** (a primary action, per the lime rule); the social buttons are neutral outlined.
  - **Type:** the headline at the largest Seed display size. Lime has no serif token, so use Montserrat semibold at display size, **unless the user supplies a serif.** Ask.
  - **At 767px and below,** the photo is hidden (or shown as a short banner on top) and the card is full width.
  - **Accessibility:** labelled inputs, visible focus (the neutral focus style from LIME-31-fix, no green glow), errors inline with `role="alert"`, and ≥ 4.5:1 contrast.
- **The user's answers (2026-09-29):**
  1. **Copy:** use plot's placeholder: headline "Where teachers connect", subline "Messages, groups and communities for educators".
  2. **The photo:** a free-licence photo from **Unsplash or Pexels** (both allow free commercial use without permission; attribution is appreciated, not required). **Tend's sandbox can't reliably download** (network is blocked), so the user saves the chosen photo as `public/assets/auth-hero.jpg`. Tend then optimises it (≤ 1600px wide, JPEG ≈ 80%, ideally ≤ 300 KB) and records the source URL and photographer credit in a comment and in `TEND.md` (plus an optional small credit line under the photo; tend proposes). If the file isn't there when this runs, ship the placeholder block and flag it.
  2b. **Update (2026-09-29): the hero is a VIDEO, already in the repo (uncommitted):** Pexels video 12896417, <https://www.pexels.com/video/businesswoman-doing-a-presentation-in-an-office-12896417/> (Pexels licence: free use, no attribution required; record the URL in `TEND.md` and in a code comment, and credit is optional). Plot inspected the files in `public/assets/`:
     - `teacher.mp4`: H.264, **2160×3840 portrait, 10s, 18.9 MB. Too heavy** for a sign-in page and for git.
     - `teacher.webm`: 0.87 MB.
     - `teacher.ogg`: Theora, 0.57 MB (obsolete format).
     - `ffmpeg` isn't installed.
   - **Plan:**
     - **Serve `teacher.webm` first,** then a **re-encoded small MP4** fallback for Safari. Make it with macOS's built-in `avconvert` (e.g. `avconvert --preset Preset1280x720 …`). **Check that the output keeps the portrait orientation** and isn't letterboxed; if a preset can't, try another preset or report back. Target ≤ 3 MB.
     - **Don't ship or commit the 18.9 MB original or the `.ogg`.** Delete them after the re-encode succeeds, or leave the original untracked and add it to `.gitignore`. Ask the user which, if unsure.
     - **Poster image:** capture a frame via Playwright + Firefox (`video.currentTime = 1`, drawn to a canvas, saved as `auth-hero-poster.jpg`, ≤ 200 KB). It's shown before playback and for reduced motion.
     - **Behaviour:**
       - `<video autoplay muted loop playsinline preload="metadata" poster=…>` with `object-fit: cover` in the rounded right-hand panel;
       - `aria-hidden="true"` (decorative) and no audio;
       - **a small pause/play button** in the panel corner (WCAG 2.2.2: moving content longer than 5s needs a pause control), with `aria-label` and keyboard access;
       - under `prefers-reduced-motion: reduce`, **don't autoplay**: show the poster, with the button available to play;
       - at ≤ 767px it's hidden (the poster isn't downloaded either: use `media` on the sources, or set the source via JS only when visible).
  3. **Font:** keep Montserrat for now.
  4. **Under the card:** leave it blank for now. **Future:** links to the iOS and Android apps. The key product differentiator is **offline Bluetooth messaging during natural disasters, strikes, etc.** (see the product-context note in Open threads).
- **Originally needed from the user before execution (now answered above):**
  1. **Headline and subline copy.** Plot's placeholder is "Where teachers connect" / "Messages, groups and communities for educators".
  2. **The hero photo:** a licensed image of teachers or a classroom that the user provides, in `public/assets/`. Otherwise a neutral placeholder block ships with the exact dimensions.
  3. What the button under the card should be, if anything. Claude's is "Download desktop app"; plot proposes none for now.

**Amendment (plot, 2026-09-30, before sending; supersedes anything above that conflicts):**
- **Preview and verify over `http://localhost:8000/public/…`** (`python3 -m http.server 8000` from the repo root), **not** `file://`. Firefox isolates every `file://` page's storage (LIME-33-fix). **Verify in the real installed Firefox and in Chrome** (LIME-52-fix5 rule). If driving Firefox with `puppeteer-core`, **pass `extraPrefsFirefox` restoring Firefox's real defaults** (`security.fileuri.strict_origin_policy: true`, `privacy.trackingprotection.enabled: true`), per `TEND.md` LIME-33-fix.
- **Keep everything LIME-33 and 33-fix built working** through the redesign: the storage probe and its message, the `?from=auth` marker on post-auth redirects, `login.html?reason=storage|fileorigin` messages, the seed-teacher wrong-password hint, the terms checkbox, and `signUp`'s synchronous save. If you consolidate into `auth.html`, carry the `reason` messages over, and keep `login.html`/`signup.html` as redirects that preserve the query string.
- **Remove "Use phone number instead"** (it's dead; phone sign-in isn't planned yet). The current tagline "Connect families and teachers, effortlessly" is replaced by the user's chosen copy above.
- **The video files, decided by plot (the user may overrule at the gate):** once the small MP4 is verified, **delete `teacher.ogg` and the 18.9 MB `teacher.mp4` original** (re-downloadable from the Pexels URL above). Commit only `teacher.webm` (renamed `auth-hero.webm`), the small MP4 (`auth-hero.mp4`) and the poster.
- **Email-first reveals whether an email has an account.** That's fine for the local demo. In `docs/data-model.md`'s switch checklist, note that production should avoid account enumeration (e.g. Supabase magic link / OTP, or a uniform "Continue" response).
- The line references above predate LIME-49 to 33-fix. Survey first.

**Scope, when it runs:** `public/login.html`, `public/signup.html` (or a new `auth.html` plus redirects), a CSS file for auth (`auth.css` already exists), `public/assets/` for the photo, `public/js/auth.js` (only an `accountExists(email)` read, if needed), `docs/data-model.md` (OAuth in the switch checklist), and `TEND.md`.

**Verification:** jsdom and Playwright + Firefox for the full email-first flow: an existing seed email reaches the password step, a new email reaches create and then the app, wrong-password errors appear, and both layouts (1567×905 and 767px) are screenshotted. The OAuth buttons are disabled, with an accessible "Coming soon" label.

**Gate:** the user opens `http://localhost:8000/public/login.html` in Firefox. It feels like the reference: headline, a clean card, and the teacher video with a pause button. The email-first flow works for both an existing and a new account.

**Record:** add a `## LIME-48` entry to `TEND.md`. Commit: `feat: redesigned email-first sign in / sign up`, trailer `Brief: LIME-48`, plus the attribution trailer.

---

> **Shared context for LIME-40 to 45: the media, receipts, link previews and chat backgrounds round** (the user's QA of LIME-38, 2026-09-29, with Apple Messages and WhatsApp as references).
>
> **Decisions:**
> - Receipts are **✓ delivered and ✓✓ viewed, both neutral grey,** with who and when on hover.
> - **Link previews are built the real way,** demoed with sample data.
> - **Chat backgrounds, not a fixed pattern:** a header icon (between the header avatars and "…") opens customisation: accessible colours, a few patterns, or upload your own photo. **The fades and gradients must follow whatever background is chosen.**
>
> **Order:** LIME-39 (amended: open at the latest message) → 40 → 41 → 42 → 43 → 44 → 45, then the milestone (LIME-33 → 29). **The user can reprioritise.** Capability, measurement and production-ready rules are as for LIME-34 to 38.

### LIME-46 → `tend` (right after LIME-39, before LIME-40): one fade system: pinned to every panel's edges, coloured by that panel's background

**The user's QA (2026-09-29), with a background colour applied via devtools to expose it:**
1. **The fades are a single fixed colour** (`--soil-bg-canvas`), so on any other background they show as off-colour bands: the top of the list column, above the composer, the composer's own bar, and the Recent row's edges.
2. **Some fades scroll with the content** instead of staying at the panel's edges ("it sometimes scrolls with the component when it should be at the bottom, top and sides of each panel, as a system"). In the screenshot, the list column's fades and the Recent row's right fade have moved with the scrolled content.

**Root causes (plot read `gradients.css`, all 74 lines, and the fade markup in `index.html` ~185, ~212, ~339 and ~456):**
- **Everything is hard-coded to `--soil-bg-canvas`** (gradients.css ~35–38 and ~62) and fades to the bare `transparent` keyword (which interpolates through transparent black, giving grey halos on coloured backgrounds). The composer bar's own background is also canvas.
- **The fade divs are `position: absolute` children of `.has-fade-y`/`.has-fade-x`.** Where that element **is itself the scroll container** (e.g. `#list-col`), absolutely positioned children scroll along with the content. `wireScrollFades(scrollEl, fadeHost)` (app.js ~3597) already supports a separate, non-scrolling host, but not every usage is structured that way.
- Panels don't share one background: the center is canvas, the right panel in flush mode is `--calm-bg-subtle-default`, and the settings nav differs. So one colour can never be right everywhere.
- `gradients.css` ~64–74 still sets `.lime-messages { padding-bottom: 200px }`, which conflicts with `lime.css`'s 80px and LIME-39's dynamic clearance. LIME-39 should already own this; if it's still there, remove it here.

**Goal:**
- Every scrollable area (the conversation list, the Recent row, the main thread, the reply list, the profile/members panel, and the settings pane) uses **one** fade system.
- The fades are **fixed to the scroll area's visible edges** (they never move with content), appear only when there's hidden content in that direction (today's behaviour), and are **coloured by the actual background behind them,** with no bands or grey halos on any background.

**Scope:**
- **May touch:** `public/css/gradients.css`, the fade markup in `public/index.html` (wrapping scrollers where needed), `wireScrollFades` and its call sites in `public/js/app.js`, background declarations in `public/css/lime.css` (to set the panel variable), and `TEND.md`.
- **May not touch:** panel layout or sizes, and scroll behaviour itself (LIME-39's pinning).

**The change:**
1. **One background variable per surface.**
   - Every panel or surface that hosts fades declares `--surface-bg` equal to its real background (the center/thread: canvas; the right panel: its flush colour; the settings pane and nav: theirs; the composer: the thread's).
   - Its `background` **uses** `var(--surface-bg)`, so the two can't drift apart.
   - Children inherit it. LIME-45 will later override `--surface-bg` on the thread with the chosen chat background, so **the fades follow automatically.**
2. **Fade colours:** every fade gradient goes from `var(--surface-bg)` to `color-mix(in srgb, var(--surface-bg) 0%, transparent)`. **Never bare `transparent`,** and never a hard-coded token. This includes the composer's `::before` fade. **The composer bar's own background becomes `var(--surface-bg)`.**
3. **A pinned structure,** one pattern:
   - **the frame** (`.lime-fade-frame`, `position: relative`, the fade host, not scrolling) contains
   - **the scroller** (`.lime-fade-scroll`, the only element with `overflow: auto`) plus
   - **the fade elements** as siblings of the scroller.
   - Restructure **every** usage to this pattern, and pass the frame as `fadeHost` to `wireScrollFades`.
   - The old `.has-fade-y`/`.has-fade-x` structure goes. Keep the class names only if renaming is noisy, and say which.
   - **The reply list and the settings pane get fades too,** if they scroll.
4. **Horizontal (Recent row):** the same pattern, with left and right fades pinned to the row's visible edges.
5. **Where the composer overlaps the thread,** the thread's bottom fade sits **above the composer** (anchored to the composer's top, as the `::before` does now) and uses the same colours. Unify so there's one bottom fade, not two stacked.

**Verification (Playwright + Firefox, 1567×905):**
1. For each scroll area, scroll to the middle. **The fade rects are identical before and after scrolling** (pinned; report them), and the fades are visible only in the directions with hidden content.
2. **A background test:**
   - set `--surface-bg` on the center and right panels to 3 test colours (a pale green like the user's `#cfe3c6`, a dark `#1e2a24`, and a saturated `#ffd7a8`), via a temporary diagnostic, **removed before commit**;
   - screenshot each, and **sample pixels** at each fade's outer edge (it must equal the background ±3 per channel) and midpoint (it must lie between the background and the content, with **no grey dip**; report the RGB values);
   - the composer bar matches the background (±3).
3. The real app loads in jsdom with zero errors, and `git diff public/index.html` shows only the fade restructuring.

**Gate:** in Firefox, change a panel's background the way you did in devtools (or ask tend for its test toggle). The fades at the top, the bottom, the sides and around the message box blend perfectly, and they stay at the panel's edges while you scroll.

**Record:** add a `## LIME-46` entry to `TEND.md`. Commit: `refactor: one fade system, pinned to panel edges, coloured by surface background`, trailer `Brief: LIME-46`, plus the attribution trailer.

---

### LIME-47 → `tend` (after LIME-46, before LIME-40): message bubbles wrap properly and are rounder; the reply quote shows its media; the DM details crumb

**The user's QA (2026-09-29, screenshots):**
1. **Long messages break out of their bubble.** An unbroken string (and long list items or links) runs past the bubble's right edge and under the details panel, so the bubble "isn't responsive to the content". Bubbles should also be **more rounded, matching the composer box.**
2. **The reply panel's quote shows only the word "Photo"** for an image message, so it's hard to tell what's being replied to.
3. **(Plot's own observation)** In a DM with the details panel open, the breadcrumb reads "Messages / Jean Chung / Jean Chung", a duplicate.

**Root causes (plot read `lime.css` ~2667–2680 and `renderQuote` in `app.js` ~2436):**
- `.lime-message__content` (radius `--seed-radius-md`, padding `14px 18px`) and `.lime-message__text` have **no `overflow-wrap`/`word-break`** rule anywhere in `lime.css`.
- The column containing the bubble likely lacks `min-width: 0`, so flex items can't shrink below their content. Confirm this.
- `renderQuote` renders `plainPreviewFor(message)` only; it never renders attachments.

**Also (carried over; the LIME-46 instruction wasn't done):** `.lime-messages { padding-bottom: var(--composer-clearance, 200px) }` is still in **both** `lime.css` ~2552 and `gradients.css` ~112. Keep it only in `lime.css` and delete the `gradients.css` copy. The cascade result is unchanged; confirm the computed value is the same before and after.

**Scope:**
- **May touch:** the message bubble, text, rich-text and reply-quote rules in `public/css/lime.css`, and the duplicate padding rule in `public/css/gradients.css`; `renderQuote` and `renderCrumbs` in `public/js/app.js`; and `TEND.md`.
- **May not touch:** the bubble's colours, the album layout (LIME-41), or the replies list itself.

**The change:**
1. **Wrapping:**
   - `overflow-wrap: anywhere` on bubble text, rich text, links and list items;
   - `min-width: 0` on every flex ancestor between the message row and the bubble;
   - the bubble keeps its existing max width (`min(70ch, 640px)` or whatever applies) and **shrinks to its content** for short messages;
   - `pre` code blocks scroll horizontally **inside** the bubble (`overflow-x: auto`; `white-space: pre`) rather than wrapping or overflowing.
   - The same rules apply to replies in the reply panel.
2. **Rounder bubbles:** use the composer box's radius token (`.lime-composer__box`'s `border-radius`: read it and reuse the **same token**, don't copy a number). Keep the padding proportional: check that single-line bubbles don't look pill-cramped, and adjust the padding only if needed, reporting the before and after.
3. **The reply quote shows media:**
   - for a message with image attachments, render **a small thumbnail** (48px, rounded, `object-fit: cover`) beside or under the quoted sender, and a "+N" for more than one image;
   - for a file or audio attachment, a compact file chip (icon plus name);
   - the caption text as now.
   - Use the same attachment read the thread uses (`getAttachments`, or LIME-38's `metadata.path` compatibility), so it keeps working after LIME-41.
   - Clicking the thumbnail opens the lightbox.
4. **The DM details crumb:** when the open panel is the person's details **and** the conversation is a DM with that person, the panel crumb reads **"Profile"** instead of repeating the name. Group and other-person cases are unchanged.

**Verification (Playwright + Firefox, 1567×905 and 767px):**
- Send a 300-character unbroken string, a long URL, a list with a long unbroken item, and a code block with a long line. For each, the bubble's right edge is ≤ its container's right edge (report them), and the code block scrolls (`scrollWidth > clientWidth`).
- Short messages still hug their content.
- The bubble's border-radius equals the composer box's.
- The reply quote of an image message contains an `<img>` thumbnail; clicking it opens the lightbox.
- The DM crumb shows "Profile".
- The real app loads in jsdom with zero errors.

**Gate:** in Firefox:
- **Long text:** paste a very long word or link. It wraps inside a rounder bubble, and nothing runs off the side.
- **Reply quote:** reply to a photo. The thread panel shows a small thumbnail of that photo.
- **One-to-one crumb:** in a one-to-one chat, open the person's details. The breadcrumb ends "… / Profile".

**Record:** add a `## LIME-47` entry to `TEND.md`. Commit: `fix: bubbles wrap and match composer radius; reply quote shows media; DM profile crumb`, trailer `Brief: LIME-47`, plus the attribution trailer.

---

### LIME-40 → `tend`: the lightbox: close at the photo's top-left, arrows between photos

**QA:** the close × sits at the top-right, cut off by the window edge. "Close button should be on the left top corner of the photo, and if multiple photos we need arrows on the left and right."

**The change** (`lime.css` `.lime-lightbox*` ~1406, and the lightbox code in `app.js`):
1. **The close button** is positioned **relative to the image's box**, at its top-left corner (inset `--seed-space-3` inside the image, or overlapping its corner), never outside the viewport. It's a round button with a neutral translucent fill, `aria-label="Close"`, and Escape still closes.
2. **Navigation:** the lightbox opens with the **list of images in the current conversation** (in chronological order) and the clicked one's index.
   - With more than one image, show **left and right arrow buttons**, vertically centred at the viewport's sides, plus the ←/→ keys and a muted "3 / 7" counter.
   - It doesn't wrap. Hide the arrow at either end.
3. **Fit:** the image fits within the viewport minus a margin (`max-width: calc(100vw - 128px)`, `max-height: calc(100vh - 96px)`), and the buttons never cover the image's content beyond the corner.

**Verification (Playwright + Firefox):** the close button's rect sits inside the viewport at the image's top-left (report both rects); the arrows and keys change the image and counter; the ends hide their arrows; Escape closes.

**Gate:** click a photo. The × sits at the photo's top-left, and arrows or ←/→ move between that chat's photos.

**Record:** add a `## LIME-40` entry to `TEND.md`. Commit: `fix: lightbox close at image corner, arrows between photos`, trailer `Brief: LIME-40`, plus the attribution trailer.

---

### LIME-41 → `tend`: several attachments in one message: an album grid and a gallery view

**QA:** sending several photos creates one message per photo. The user wants **WhatsApp's album** (one bubble, a 2×2 grid, "+N" on the last tile) and **Apple's** gallery grid ("9 Photos" opens a grid of all of them).

**The data model change** (production-ready; this supersedes LIME-38's "one message per file"):
- **Schema:** a new table `message_attachments` (`id text pk`, `message_id` references `messages` on delete cascade, `path`, `name`, `size`, `mime`, `width`, `height`, `position`, `created_at`), with RLS by `is_member` via the message's conversation.
- Any message (including text) can have 0 to n attachments. **Typed text becomes the caption of the same message,** not a separate message.
- **The contract:** `sendMessage(conversationId, { content, metadata, replyTo, attachments: [{ path, name, size, mime, width, height }] })`. Add a read, `getAttachments(messageId)`.
- **Backward compatibility:** LIME-38's existing `image`/`file` messages (with their `metadata.path`) are read as a message with one attachment. Don't break existing local data. Document the mapping.
- Record the image width and height at upload (decode via `Image` or `createImageBitmap`) so the grid can lay out without jumping.

**Rendering:**
- **1 image:** as today, the thumbnail from LIME-38, max 240 × 180.
- **2 images:** side by side.
- **3:** one large plus two stacked.
- **4 or more:** a 2×2 grid; with more than 4, the 4th tile shows a **"+N"** overlay.
- Tiles are square-cropped (`object-fit: cover`) in one rounded bubble, with the caption below if any.
- **Clicking a tile** opens the LIME-40 lightbox at that image, **scoped to this message's images**.
- A small "N photos" label above an album (N ≥ 5) opens a **gallery modal**: a responsive grid of all the images in the message, with the blur backdrop and a close button. Clicking one opens the lightbox.
- **Non-image files** in the same message render as file cards below the album (LIME-42 improves the cards).
- **List previews:** "📷 N photos", or "📎 name" for one file, or the caption if there is one.

**Also fix (seen in the user's screenshots):** the composer's attachment error ("… is over the 10MB limit") **stays visible after sending.** Clear it on send, on removing a chip, and on the next file pick.

**Verification:**
- jsdom + Playwright + Firefox: sending 7 photos with a caption creates **one** message with 7 attachments and the caption.
- Grid tiles 2, 3 and 4 plus "+3" render per layout. Report the tile rects.
- A tile opens the lightbox with 7 images; "7 photos" opens the gallery.
- Old single-image messages still render.
- After a reload, the album layout doesn't shift (the width and height are used).

**Gate:** select several photos, add a caption, and send. One bubble shows a grid with "+N". Click a tile to open it large, with arrows. "N photos" opens the full grid.

**Record:** add a `## LIME-41` entry to `TEND.md`. Commit: `feat: multi-attachment messages: album grid and gallery; message_attachments table`, trailer `Brief: LIME-41`, plus the attribution trailer.

---

### LIME-40-fix → `tend` (before LIME-42): the lightbox close button sits outside the image and is clearly visible

**The user's QA (2026-09-29, screenshot):** "the close button is not accessible on hover, and it needs to be on the outside of the image, not on top of it." In the screenshot, a dark translucent × (`rgba(19,27,23,0.55)`, lime.css ~1469) sits on the photo's dark top-left corner, so it's nearly invisible, and its hover state barely changes.

**The design:** a **toolbar row above the image** replaces absolute positioning on the image. This rules out the LIME-40 off-screen bug by construction.
- The lightbox content becomes a column: **a top bar** (the close button on the left, the "2 / 7" counter on the right) above **the image**.
- The image's max height becomes `calc(100vh - <bar height> - margins)`, so the bar can never be pushed off-screen.
- The bar's left edge aligns with the image's left edge, and its right edge with the image's right edge (the bar's width follows the image's rendered width). If that's awkward, align it to the image column and report which.
- **The close button:**
  - a 40px round target on a **solid, opaque** surface (`--soil-bg-elevated`, the `--soil-text` icon, `--seed-shadow-sm`);
  - hover uses `--calm-bg-subtle-hover`;
  - **a visible focus ring** (the neutral focus style);
  - `aria-label="Close"`, the `title` tooltip kept;
  - **≥ 3:1 contrast against the backdrop** (non-text contrast). Report the ratio.
- **The counter** moves into the bar, the same neutral pill.
- **The arrows** stay at the viewport's sides, restyled to the same solid, opaque style as the close button, for consistency and contrast.
- The **gallery modal's** close button (LIME-41) gets the same treatment, if it has the same problem.

**Scope:** the lightbox and gallery markup in `public/index.html` and `app.js` (only if structure is needed), the `.lime-lightbox*` and gallery close rules in `public/css/lime.css`, and `TEND.md`.

**Verification (Playwright + Firefox, 1567×905 and 500×500):**
- The close button's rect is **outside** the image rect (above it), fully inside the viewport, and aligned to the image's left edge (±2px).
- The contrast of the button against the backdrop is ≥ 3:1.
- The hover and focus styles are visibly different (report their computed backgrounds and outlines).
- Escape, the ← and → keys, and the arrows still work.
- The real app loads in jsdom with zero errors.

**Gate:** open a photo. The × sits in a bar just above the photo's top-left, clearly visible on any photo, and highlights on hover. The counter is at the top-right of the same bar.

**Record:** add a `## LIME-40-fix` entry to `TEND.md`. Commit: `fix: lightbox controls in a bar outside the image, solid and accessible`, trailer `Brief: LIME-40-fix`, plus the attribution trailer.

---

### LIME-41-fix → `tend` (before LIME-43): album captions keep their formatting; viewer controls; a full-screen photo wall instead of the gallery card

**The user's QA (2026-09-29, three screenshots):**
1. **An album's caption loses its formatting** (bold, lists and so on), and renders as plain wide text with no bubble.
2. **"5 photos" should sit directly under the grid.** Right now it's centred with a gap, floating between the grid and the caption.
3. **Viewer (lightbox):** "remove the 1px border on all the nav items" (the close, arrow and counter controls). "Move the number counter to the bottom centre of the media, and the close button to the top-right corner of the media."
4. **The gallery:** its close button should be at the top right, **outside** the content. And the grid "doesn't provide enough value." **Make it full-screen over the blurred app, like the photo viewer: a Pinterest-style wall**, where choosing a photo shows that photo alone.

**Plot's reading of the positions:** keep the LIME-40-fix principle, **controls outside the photo**, so the photo is never covered:
- **the close button sits just outside the image's top-right corner** (above it, right-aligned to the image's right edge);
- **the counter is centred just below the image;**
- the arrows stay at the viewport's sides.
The image's max height reserves room above and below, so nothing goes off-screen. **If the user meant overlaid on the photo, it's a one-line change.** Flag it at the gate.

**Plot's note on the borders:** the 1px borders were added in LIME-40-fix as "load-bearing" for 3:1 non-text contrast. Removing them is fine for accessibility **as long as each control's icon itself contrasts ≥ 3:1 with its own fill** (a dark icon on a white fill does), and the control is separated from the blurred backdrop by a **soft shadow** (`--seed-shadow-md`) instead of a border. Report the icon-to-fill ratio.

**Scope:** album and caption rendering in `public/js/app.js`, the lightbox and gallery markup and JS, the `.lime-lightbox*`/gallery/album rules in `public/css/lime.css`, and `TEND.md`.

**The change:**
1. **Album caption:** render the caption **inside a normal message bubble** directly under the grid, the same width rules as text messages (LIME-47), using `metadata.html` through `renderRichHtml` when present, the same path as text messages. **Find why the album path skipped it** (probably plain `content` used for captions) and share one caption renderer. Check that sending an album with a formatted caption **stores** `metadata.html` at all, and fix the send path too if not.
2. **"N photos":** a small left-aligned link directly under the grid (`--seed-space-1` gap), before the caption bubble, with muted text, underlined on hover. It opens the wall (below).
3. **Viewer controls:** no borders, a soft shadow, the close button outside the image's top right, the counter centred below it, and the sizing reserves space for both. Keep Escape, the arrow keys, hover and focus styles, and the LIME-40 no-wrap behaviour.
4. **The photo wall** (replacing the gallery card modal):
   - **full-screen over the blurred backdrop** (the same backdrop as the viewer), with no white card;
   - a **masonry wall** (CSS `columns` with `break-inside: avoid`, **natural aspect ratios**, not square crops), with the column count responsive to width: about 5 at 1567px, 3 at 900px and 2 at 500px;
   - **the close button at the top right of the viewport**, outside the wall, with the same styling as the viewer;
   - the wall scrolls inside the full-screen layer (the LIME-46 fade frame, with fades using the backdrop colour).
   - **Choosing a photo** opens the viewer on that photo, scoped to the album. **The viewer then shows a "back to all photos" control** (a grid icon, top left, outside the image) that returns to the wall at the same scroll position.
   - **Escape:** in the viewer (when opened from the wall), it returns to the wall; on the wall, it closes. This replaces LIME-41's close-gallery-first hand-off with a clear two-level stack. Handle Escape in **one** place so nothing double-fires.
   - Reached from "N photos", and from the "+N" tile.

**Verification (Playwright + Firefox, 1567×905 and 500×500):**
- An album sent with a bold word and a list caption renders the formatting inside a bubble (and `metadata.html` is stored).
- "5 photos" sits within 8px under the grid, left-aligned.
- **Viewer:** the controls have `border-width: 0`; the close button is outside the image at its top right and the counter is below its centre, both inside the viewport (report the rects); the icon-to-fill contrast is reported.
- **Wall:** full-screen; the tiles keep their aspect ratios (report 3 ratios against the originals); the column count at each width; the close button at the viewport's top right. Choosing a tile opens the viewer, "all photos" returns with the scroll position restored, and Escape behaves at each level.
- The real app loads in jsdom with zero errors.

**Gate:** in Firefox:
- **Caption:** send photos with a formatted caption. It keeps its formatting, in a bubble under the grid, with "5 photos" right under the grid.
- **Viewer:** open a photo. The × is outside its top right, the counter is centred below it, and there are no borders.
- **Wall:** "5 photos" opens a full-screen, Pinterest-style wall. Choose a photo to see it alone, then "back to all photos".
- **Ask:** should the controls sit outside the photo (as built) or on it?

**Record:** add a `## LIME-41-fix` entry to `TEND.md`. Commit: `fix: formatted album captions, viewer controls, full-screen photo wall`, trailer `Brief: LIME-41-fix`, plus the attribution trailer.

---

### LIME-42 → `tend`: audio attachments play inline; file cards by type

**QA:** audio uploads should work like WhatsApp's. "Same for audio and files."

**The change:**
- **Audio attachments** (`audio/*`) render as an inline player that matches the existing voice-message bubble (play/pause with the waveform style and duration, via a hidden `<audio>` element). The duration comes from metadata.
- **File cards:**
  - an extension badge (PDF, DOC, XLS, PPT, ZIP, TXT, or generic), each with a neutral tinted tile. **Not lime.** Use Seed calm/bad/warn/good tints by category only if they pass contrast, otherwise neutral;
  - the name (ellipsis-truncated in the middle, keeping the extension);
  - the size;
  - a Download button;
  - **PDFs and images** open in a new tab from the card.
- **List previews:** "🎵 Audio", or "📎 name".

**Verification:** Playwright + Firefox with a small mp3 and pdf from the scratchpad. The audio plays and pauses (the `<audio>` element's `paused` flips); the cards show the right badge; long names truncate while keeping the extension.

**Gate:** attach an audio file, and it plays in the chat. Attach a PDF, a Word file and a zip, and each shows a clear card.

**Record:** add a `## LIME-42` entry to `TEND.md`. Commit: `feat: inline audio player and typed file cards`, trailer `Brief: LIME-42`, plus the attribution trailer.

---

### LIME-43 → `tend`: delivered ✓ and viewed ✓✓

**Decided:** both are neutral grey. Hover shows who viewed and when.

**Production-ready derivation (no new columns):**
- A message is **delivered** once the store persists it. **Viewed by X** when X's membership `last_read_at >= message.created_at`, which LIME-36 already writes via `markRead`.
- **In a DM:** ✓✓ when the other person has viewed it.
- **In a group:** ✓✓ when **all** other members have viewed it. The tooltip lists "Viewed by Jean, Grace" plus "Not yet: …".
- Document this in `data-model.md`, and note that a real backend with realtime updates the ticks live.

**The change:**
- Only on **your own** messages: a small ✓ or ✓✓ after the time in the meta line (use `dew-check` doubled, or an inline SVG if a double-check icon doesn't exist), `--soil-text-muted`, with an `aria-label` ("Delivered" or "Viewed").
- Hovering or focusing it shows a tooltip with the viewers and their times.
- It updates on `lime:conversations-changed` (the read kind).
- A **privacy setting** to turn off read receipts is a future Settings item. Note it.

**Verification:** jsdom. A message you sent in Jean's DM shows ✓. Simulating Jean's `markRead` (test hook, as Jean) makes it ✓✓, with the tooltip "Viewed by Jean · <time>". In conv-011, ✓✓ appears only once all 9 others have read.

**Gate:** send a message and see ✓. Sign in as the other person (after LIME-33), or ask tend for a demo toggle, and it becomes ✓✓. Hover shows who.

**Record:** add a `## LIME-43` entry to `TEND.md`. Commit: `feat: delivered and viewed receipts derived from last_read_at`, trailer `Brief: LIME-43`, plus the attribution trailer.

---

### LIME-44 → `tend`: link preview cards, built for real and demoed with samples

**Decided:** build it the real way, demo with samples. A browser can't fetch other sites' metadata (CORS, and `file://`), so this needs a server piece later.

**Production design** (documented in `data-model.md` and `schema.sql`):
- A Supabase Edge Function, `unfurl(url)`: fetch with a timeout and a size cap, parse Open Graph and Twitter meta plus `<title>`, `favicon`, `og:image`, `description`, `site_name`; block private IP ranges (SSRF); cache the result.
- A table `link_previews` (`url pk`, `title`, `description`, `image_url`, `site_name`, `favicon_url`, `fetched_at`).
- **The contract:** `getLinkPreview(url)`, resolving to a preview or null.

**Local adapter:**
- A small **fixture map** of 3–4 demo URLs with realistic previews (plausible education links; images as bundled local assets or none), for a full card.
- **Any other URL** gets a minimal card: the site's domain as the title, the full URL muted, and no image.
- **No network calls.**

**The UI:**
- The **first** link in a message's content gets a card below the bubble text: the image on the left (or top when wide), the site name muted, the title bold (2 lines max), the description muted (2 lines max).
- The whole card is a link (`rel="noopener noreferrer"`, `target="_blank"`), with neutral styling, a subtle border, and radius.
- A composer-side preview before sending (with an × to drop the preview) is **optional**; include it if simple.

**Verification:** jsdom plus Playwright + Firefox. A fixture URL shows its full card; an unknown URL shows the minimal card; no network requests happen (use the fail-fast recipe); the card doesn't overflow the bubble; the message content itself is unchanged.

**Gate:** paste one of the demo links (tend lists them) and send. A card with a title, description and image appears. Any other link shows a simple site card.

**Record:** add a `## LIME-44` entry to `TEND.md`. Commit: `feat: link preview cards (unfurl contract; local fixtures)`, trailer `Brief: LIME-44`, plus the attribution trailer.

---

### LIME-45 → `tend`: customisable chat backgrounds, with gradients that follow them

**The user's spec:**
- An icon in the thread header, **between the header avatars and the "…" button**, opens background customisation: **accessible background colours, a few patterns, and uploading your own photo.**
- **"Something critical to the success of this is the gradients need to be dynamic,** so that we don't see broken gradients that don't align to the colour background changes."

**Plot's design decisions (flag anything that doesn't hold up):**
- **Scope of a choice:** it's **per user, per conversation** (a WhatsApp-like "for this chat"), with an **"Apply to all chats"** option that sets **your default.**
  - **Production:** `conversation_members.background jsonb` for per-chat, and a `user_settings.default_background jsonb` for the default (add `user_settings` to the schema if it's missing).
  - **The contract:** `setChatBackground(conversationId | null, background)`.
  - **Local:** the store snapshot, with photos in IndexedDB via `uploadAttachment`.
- **The shape:** `{ kind: 'default' | 'color' | 'pattern' | 'photo', color, patternId, path, avgColor }`.
- **Colours:** 8 preset swatches built from Seed tokens and brand ramps, **each checked**: the message bubble surface keeps ≥ 3:1 against the background (so bubbles read as objects), and any text drawn **directly** on the background (the date dividers, sender names, times, reply summaries) is ≥ 4.5:1. **Swatches that fail don't ship.**
- **Patterns:** 3–4 subtle line patterns as **CSS or inline SVG** (no downloaded assets), tinted from the base colour at very low contrast, over a chosen base colour.
- **Photos:** upload, then compute the **average colour** via canvas (downscale to 16 × 16 and average) and store it as `avgColor`. Show a **scrim** over the photo (a semi-opaque layer of `avgColor`) so on-background text stays legible.
- **Dynamic gradients (the critical part): LIME-46 builds the system.** Here, setting the chat background just sets `--surface-bg` on the thread surface (and on the composer), and the fades follow. Don't add a second mechanism.
  - **One variable, `--chat-bg`,** is set on the thread container: the colour, or the pattern's base colour, or a photo's `avgColor`.
  - **Every fade touching the thread** (`gradients.css` ~35–62: the thread's top/bottom fades and the composer fade; audit all of them) uses `--chat-bg`, **never `--soil-bg-canvas` directly** there.
  - Fade to a **transparent version of the same colour** (`color-mix(in srgb, var(--chat-bg) 0%, transparent)`, or `rgb(from var(--chat-bg) r g b / 0)`), **not the bare `transparent` keyword**, which interpolates through grey.
  - **For photos,** the fades use `avgColor` over the scrim, so they blend.
  - The composer's backdrop matches too.
  - **The reply panel isn't in scope.** It keeps its default background.
- **On-background legibility:** when the background isn't default, the date dividers and the metadata drawn directly on it (sender names, times, the reply summary) get a subtle pill backdrop, `color-mix` of `--soil-bg-surface` at ~80%.

**The UI:**
- A header icon button (`dew-sun` or a palette-like dew icon; if there's no good one, a neutral inline SVG), `aria-label="Chat background"`.
- It opens a popover or small dialog in the menu and modal style:
  - a "Colors" swatch grid (with the current one marked);
  - "Patterns" (thumbnails);
  - "Photo" ("Upload photo", and "Remove" if one is set);
  - "Reset to default";
  - an "Apply to all chats" checkbox.
- Choices apply **live** as a preview, and persist.

**Verification:**
- jsdom plus Playwright + Firefox for each kind (default, 2 colours, a pattern, a photo):
  - compute and report the contrast ratios (bubble surface vs the background; divider and meta text vs the background, with the pill);
  - **sample the fade pixels** in screenshots at the thread's top and bottom and above the composer. There must be **no visible band**: the fade's end colour equals the background (±3 per channel), and its midpoint has no grey dip;
  - per-chat versus "Apply to all" behaves correctly;
  - the settings persist across reload;
  - a photo's `avgColor` is sensible;
  - Reset returns to default.
- **Attach the screenshots to the `TEND.md` entry as file paths** in the scratchpad, for plot to review.

**Gate:** open the background icon, try a colour, a pattern and your own photo. Text stays readable, and the fades at the top, the bottom and around the message box always blend into the background, with no hard edges or grey bands. "Apply to all chats" changes the other chats too.

**Record:** add a `## LIME-45` entry to `TEND.md`. Commit: `feat: per-chat backgrounds (colour, pattern, photo) with background-aware fades`, trailer `Brief: LIME-45`, plus the attribution trailer.

---

### LIME-39 → `tend` (after LIME-38): the last message is never hidden behind a growing composer

**Found by tend in LIME-37 (`f43ee40`), confirmed as pre-existing against the older HEAD:** `.lime-messages` (lime.css ~2437) is `position: absolute; inset: 0` with a **fixed** `padding-bottom: 80px`, and the main composer is absolutely positioned over its bottom. As the composer grows (multi-line text, lists, attachments from LIME-38), the thread's visible area doesn't shrink, so the last message ends up behind the composer. LIME-10-fix15's static calibration can't cover a composer whose height now varies much more.

**Amended 2026-09-29 (the user's QA: "when I refresh it doesn't go to the latest message"):** after a reload, the thread doesn't end at the newest message. The likely cause is that images (LIME-38) load *after* the initial scroll-to-bottom, and push the content down. Same mechanism, so it's included here: **the thread also stays pinned when its content grows** (image loads, new messages), and **it opens at the latest message** after all its media has laid out. Observe the content too: a `ResizeObserver` on the message list's content, and/or `load` listeners on the thread's images. Verify with a reload in Playwright + Firefox on a chat that has photos: `scrollTop` ends at the bottom (±2px).

**Goal:** in both the main thread and the reply panel, the latest message always stays visible above the composer at any composer height. If you were at the bottom before the composer grew, you stay pinned to the bottom. If you'd scrolled up to read history, your position isn't yanked.

**Capability assumptions:** can edit files, run commands and commit. Load the real app in jsdom (zero errors). **Measure with Playwright + Firefox** per `TEND.md` LIME-31-fix.

**Scope:**
- **May touch:** `public/js/app.js` (a small helper wired to both composers, via `createComposer` if that's the natural place), the `.lime-messages` and `.lime-replies-panel__list` padding rules in `public/css/lime.css` (and the fade's offset, if it depends on the composer height), and `TEND.md`.
- **May not touch:** the composer's own layout, the Send position, the toolbar collapse (LIME-32), or the fades' design.

**The change:**
1. **Measure the composer's real height:** a `ResizeObserver` on each composer (main `#composer`; for the reply panel, check whether its composer overlaps the list or sits in normal flow, and apply this only where it overlaps) writes a CSS variable, e.g. `--composer-clearance: <height + --seed-space-4>px`, on the thread's scroll container.
2. **Use it:** `.lime-messages { padding-bottom: var(--composer-clearance, 80px); }`, and the same for the reply list if needed. If the gradient fade's offset (`gradients.css` / LIME-10-fix15) is tied to the composer height, drive it from the same variable.
3. **Stay pinned:** before applying a new clearance, record whether the scroller was at the bottom (`scrollHeight - scrollTop - clientHeight <= 8`). Afterwards, if it was, set `scrollTop = scrollHeight`. Don't move it otherwise.
4. Add a comment pointing at LIME-10-fix15, and saying why a static value can't work any more.

**Verification (Playwright + Firefox, 1567×905 and 767px):**
- With the composer collapsed, expanded, and holding 6+ lines (including a list), in both the main thread and the reply panel: `lastMessage.bottom <= composerBox.top - 8`. Report the numbers for each state.
- Scroll up to the middle of the history, then grow the composer: `scrollTop` is unchanged.
- At the bottom, grow the composer: it stays at the bottom.
- The real app loads in jsdom with zero errors.

**Gate:** in Firefox:
- **Growing box:** type a long multi-line message, or a list, in the main box. The last message moves up and stays visible above it.
- **Reply box:** the same.
- **Reading history:** scroll up to read older messages, then type. The view doesn't jump.

**Record:** add a `## LIME-39` entry to `TEND.md`. Commit: `fix: thread keeps the latest message visible above a growing composer`, trailer `Brief: LIME-39`, plus the attribution trailer.

> **Shared context for LIME-34 to 38: the "solid place" QA pass** (user, 2026-09-28). **These run BEFORE the milestone (LIME-33 → 29).**
>
> **The user's QA list and decisions:**
> 1. **The menu differs between chats.** Decided: **the same items on every chat; items you can't use are greyed out with a short reason.**
> 2. **Rename should edit the name itself,** not open a second field beside it. The screenshot shows the title *and* a green-outlined input.
> 3. **The Recent row must be dynamic** (it's a static mockup at `index.html` ~211–265).
> 4. **Every avatar and name in a thread should open that person's own details.** Today everything opens Jean's static profile panel (`index.html` ~486).
> 5. **Breadcrumbs should be dynamic,** especially for reply threads. Today they're `crumb-teachers` / `crumb-thread` / a static "Details" (`index.html` ~149–153).
> 6. **Formatting should really work in both composers, and + should attach a file.** Decided: **live (WYSIWYG) formatting.**
> - **Also decided:** Delete on a DM = **"Delete for me"**. It clears your copy only; a new message from them brings a fresh chat back.
>
> **Capability assumptions for all five:** can edit files, run commands and commit. Load the real app in jsdom (zero errors). **Measure with Playwright + Firefox per `TEND.md` LIME-31-fix. Check `git diff` of `index.html` before every commit.** Production-ready rules apply (see the LIME-24 context): per-user state lives on the membership; UI goes through `LimeStore`; contract and schema changes go into the docs in the same commit.

### LIME-34 → `tend`: one consistent chat menu (greyed items with reasons), Delete for me on DMs, rename in place

**Scope:**
- **May touch:** `public/js/app.js` (`CONVERSATION_ACTIONS` and menu rendering, rename), `public/css/lime.css` (the disabled menu item and the in-place rename), `public/js/store.js` + `local-adapter.js` (Delete for me), `docs/data-model.md` + `docs/schema.sql`, and `TEND.md`.
- **May not touch:** other menus, or the delete-for-everyone semantics for owned groups.

**The change:**
1. **The same menu everywhere:** Star · Rename · Archive · divider · Delete, on **every** conversation. (LIME-27 will later add Copy link and Share, visible everywhere too.)
   - **Instead of hiding** an item `can()` rejects, render it with `aria-disabled="true"`, muted (`--soil-text-disabled`, no hover background, `cursor: default`), and a **one-line muted reason** under the label in `--seed-text-xs`.
   - Its key hint doesn't fire.
   - Add `canReason(action, conversation)` next to `can()` in the store, so the rule and its explanation live together:
     - **Rename on a DM:** "Direct messages are named after the person".
     - **Rename on a non-owned group:** "Only the group owner can rename".
     - **Delete on a non-owned group:** "Only the group owner can delete. Archive hides it for you".
2. **Delete for me (DMs):**
   - **Schema:** `conversation_members.cleared_at timestamptz`.
   - **Contract:** `deleteForMe(conversationId)` sets `cleared_at = now()` on **your** membership.
   - **Reads:** for you, messages with `created_at <= cleared_at` are hidden, and a DM with no messages after `cleared_at` is hidden from your lists. A new message from them makes it reappear, with only the new messages.
   - **Menu:** DM Delete is **enabled**, labelled **"Delete for me"**, with a confirm dialog: 'Delete your copy of this chat with <name>? They'll still have theirs.' The confirm label is "Delete", red.
   - Owned groups keep the existing delete-for-everyone; non-owned groups are greyed (above).
   - Update the RLS notes (a member may update their own `cleared_at`) and the mapping table.
3. **Rename in place** (it replaces LIME-26's sibling-input approach):
   - The breadcrumb title itself becomes editable: `contenteditable="plaintext-only"` on `#crumb-thread`, falling back to `"true"` with paste stripped to plain text.
   - **Same font and size.** Its text is fully selected. It gets a subtle `--calm-bg-subtle-hover` background and `--seed-radius-sm`, with **no border and no green ring**. The focus indicator is the background plus the caret.
   - Enter saves; Escape reverts; blur saves; an empty title reverts to the auto title. It must **not** trigger the title's click action (opening the details panel) while editing.
   - **Remove** the sibling input code and CSS entirely.

**Verification:**
- jsdom: every conversation type shows 4 items plus the divider; the disabled items have `aria-disabled` and the right reason, and their keys do nothing.
- **Delete for me:** delete for me on Alexi's DM: it vanishes, and Alexi's copy is untouched (check his membership row). Simulate a new message from Alexi (store write as Alexi via a test hook): it reappears with only that message.
- **Rename in place:** only one title element exists while editing (no second field), the selection covers the whole title, and Escape restores the text.
- Playwright + Firefox: the disabled item styling; the editing title has no outline or box-shadow; and a before/after screenshot of the breadcrumb while editing.

**Gate:** in Firefox:
- **Same menu:** every chat's ⌄ menu shows the same four items. Unavailable ones are grey with a reason.
- **Rename:** it edits the name right where it is.
- **Delete for me:** on a one-to-one chat it asks, then removes your copy.

**Record:** add a `## LIME-34` entry to `TEND.md`. Commit: `feat: consistent chat menu with reasons, delete-for-me on DMs, rename in place`, trailer `Brief: LIME-34`, plus the attribution trailer.

---

### LIME-35 → `tend`: everyone's own details panel (and group members), plus dynamic breadcrumbs

**Scope:**
- **May touch:** `public/index.html` (the profile panel becomes a template, and the breadcrumb markup), `public/js/app.js`, `public/css/lime.css` (small additions), and `TEND.md`.
- **May not touch:** the replies panel's internals (except the breadcrumb hook), or the store.

**The change:**
1. **The details panel is rendered from data:** `showPersonDetails(profileId)` fills the right panel from `LimeStore.getProfile(id)`.
   - It shows the avatar, name, pronouns, role and school, "About me" (the bio), and contact information (email, **local time** computed from `timezone`, and status).
   - Missing fields are simply omitted.
   - **No hard-coded Jean.**
   - When it's **your own** profile, add an "Edit profile" button that opens Settings → Profile.
2. **Triggers:**
   - **Every avatar and sender name** in the main thread and the reply panel (quote and replies) opens *that sender's* details. Use one delegated listener with `data-profile-id` on those elements.
   - In a DM, the header avatars open the other person's details.
   - **In a group, the header opens a Members panel:** the member list with avatars, names and roles (Owner or Member), each clickable through to that person's details, with a back chevron to Members.
   - On mobile, these set `data-mobile-view="panel"`, as today.
3. **Dynamic breadcrumbs,** one renderer, `renderCrumbs()`, called on every state change:
   - `Messages` (or `Communities`, following the active tab) / `<conversation title>` ⌄ / `<panel>`.
   - `<panel>` is the person's name (details), "Members", or **"Thread"** (the reply panel; on mobile, "Thread · <parent sender's short name>" if it fits), and it's absent when the right panel is closed.
   - Each ancestor crumb navigates back: the scope crumb goes to the contacts view on mobile, and the title crumb closes the panel and returns to the thread.
   - The ⌄ menu stays attached to the title crumb.
   - Delete the static "Details" crumb.

**Verification:**
- jsdom:
  - clicking Grace's avatar in conv-011 shows Grace's panel (her name and school), never Jean's;
  - a reply's avatar opens that reply-sender's panel;
  - the group header opens Members (10 rows, with Jean as Owner);
  - your own avatar shows "Edit profile";
  - the crumbs read correctly in each of the four states (no panel, person, Members, Thread), and each ancestor click navigates correctly, on desktop and at mobile width.
- Playwright + Firefox: screenshots of the four crumb states and the panel layout, with no overflow at 767px.

**Gate:** in Firefox:
- **Details:** click different people's avatars and names in a chat. Each opens *their own* details.
- **Groups:** a group's header opens its member list.
- **Breadcrumbs:** they follow what you're looking at ("… / Thread" in a reply thread), and clicking back through them works.

**Record:** add a `## LIME-35` entry to `TEND.md`. Commit: `feat: per-person details and group members panels; dynamic breadcrumbs`, trailer `Brief: LIME-35`, plus the attribution trailer.

---

### LIME-36 → `tend`: a dynamic Recent row with real unread state

**Scope:**
- **May touch:** `public/index.html` (replace the static Recent items with an empty container), `public/js/app.js`, `public/js/store.js` (a read helper only, if needed, added to the contract doc), `public/css/lime.css` (only if needed), `docs/data-model.md`, and `TEND.md`.

**The change:**
1. **The row is rendered from data:**
   - **"Me" first.** It opens your own details (LIME-35).
   - Then **up to 10 people** you've recently interacted with: the other participants of your non-archived Messages conversations, ordered by the latest activity involving them (the latest message *they* sent in any shared conversation, or your latest DM activity with them). Each person appears once.
   - Each item has an avatar with presence, and a first name plus last initial.
   - Re-render on `lime:messages-changed` and `lime:conversations-changed`.
2. **Unread:**
   - Opening a conversation calls `markRead(conversationId)` (the contract already has it).
   - A person gets the **unread ring** (the existing `lime-recent__item--unread` style, which stays lime by the user's earlier choice) if any conversation you share with them has a message **from someone else** newer than your `last_read_at`.
   - Document "unread" in `data-model.md` as derived from `last_read_at`.
3. **Click:** open your DM with that person, creating it through `createConversation({ type: 'direct' })` if there isn't one (it reuses the existing one via `dm_key`). The active item follows the open DM.
4. The horizontal scrolling and fades still work, and the search filter uses `data-search-text`.

**Verification:**
- jsdom: the order matches the latest activity; sending in conv-011 as someone else (test hook) moves that person to the front with an unread ring; opening it clears the ring; the static markup is gone.
- Playwright + Firefox: the row renders with the fade, and there's no overflow at 767px.

**Gate:** in Firefox:
- **Order:** Recent shows the people you've been talking with, most recent first.
- **Unread:** the green ring means there's something you haven't read, and it clears when you open that chat.
- **Clicking:** a person opens your chat with them.

**Record:** add a `## LIME-36` entry to `TEND.md`. Commit: `feat: dynamic Recent row with unread from last_read_at`, trailer `Brief: LIME-36`, plus the attribution trailer.

---

### LIME-37 → `tend`: live (WYSIWYG) formatting in both composers

**Plot's design decisions (flag anything that doesn't work):**
- **Storage format.** `messages.content` stays **plain text** (for previews, notifications and search). The formatted version goes in `metadata.html`, as a **sanitised allow-list HTML subset**: `p`, `br`, `strong`, `b`, `em`, `i`, `u`, `s`, `a[href]` (http, https or mailto only; add `rel="noopener noreferrer" target="_blank"` on render), `ul`, `ol`, `li`, `blockquote`, `code`, `pre`. Everything else is stripped.
- **The same sanitiser runs on send and on render.** Note in `data-model.md` that a real backend must sanitise server-side as well.
- **Why not Markdown:** underline has no Markdown form. Update the docs.

**Scope:**
- **May touch:** `public/index.html` (both composers' input elements), `public/js/app.js` (a **single shared** `createComposer(rootEl, { onSend })` used by the main and reply composers, replacing the duplicated logic), `public/js/store.js` (`sendMessage` accepts `metadata.html`), `public/css/lime.css`, `docs/data-model.md`, and `TEND.md`.
- **May not touch:** attachments (LIME-38), or the Send button position and the collapse rules (LIME-32).

**The change:**
1. **Input:** replace each `<textarea>` with a `contenteditable` div (`role="textbox"`, `aria-multiline="true"`, `aria-label`), with the placeholder via `:empty::before`.
   - **Keep existing behaviour:** the expand-on-focus toolbar, the auto-grow and max height, the `is-active` Send state, and the ≤480px short placeholder (LIME-12-fix4).
   - **Paste** is sanitised through the same allow-list.
2. **Toolbar commands** (both composers, including the "…" overflow menu items, which must now really work):
   - Bold, Italic, Underline, Strikethrough.
   - **Link:** a small inline popover to enter or edit the URL. Validate http, https or mailto, and add `https://` if there's no scheme.
   - Numbered list, Bulleted list, Quote, Code: inline code for a selection within a line, a code block otherwise.
   - Buttons show a pressed state (`aria-pressed`, neutral `--calm-bg-subtle-active`) when the caret is inside that format.
   - `document.execCommand` is acceptable for the prototype. Comment that a production editor (e.g. TipTap or Lexical) would replace it behind the same `createComposer` API.
3. **Keyboard:**
   - `Cmd/Ctrl+B`, `I` and `U`; `Cmd/Ctrl+Shift+X` for strikethrough; `Cmd/Ctrl+K` for a link.
   - **Enter sends,** *except* inside a list or code block, where it adds a new item or line. **Shift+Enter** is always a newline, and **Cmd/Ctrl+Enter** always sends.
   - Empty or whitespace-only input doesn't send.
4. **Sending:** derive `content` (plain text via `innerText`, trimmed) and `metadata.html` (sanitised); omit `html` when there's no formatting.
5. **Rendering** (main thread and replies): if `metadata.html` exists, render it **re-sanitised**; otherwise use the existing escaped text. Style lists, quotes and code to fit the bubble with Seed tokens, and use `--seed-font-mono` if it exists.

**Verification:**
- jsdom:
  - each command produces the expected sanitised HTML;
  - a paste of `<script>`, `<img onerror>`, `style` or `javascript:` links is stripped (report the input and output);
  - Enter inside a list doesn't send; Cmd+Enter sends;
  - a message sent from each composer renders formatted, and its preview in the list is plain text;
  - replies and both composers share one implementation (grep for the duplicated handlers: gone);
  - LIME-31, 32 and 26 behaviours are intact.
- Playwright + Firefox: formatting renders in bubbles, the toolbar's pressed states work, and the composer still grows upward without covering the last message.

**Gate:** in Firefox:
- **Formatting:** type in the main box and use bold, italic, underline, strikethrough, a link, both lists, quote and code. Each looks right as you type and after sending.
- **Reply box:** the same.
- **Enter:** sends, but adds a new line inside a list.

**Record:** add a `## LIME-37` entry to `TEND.md`. Commit: `feat: live rich-text formatting in both composers, sanitised storage and rendering`, trailer `Brief: LIME-37`, plus the attribution trailer.

---

### LIME-38 → `tend` (after LIME-37): attach files with +

**Plot's design decisions:**
- `messages.type` gains `'file'` (the schema check already allows `'image'`).
- `metadata = { name, size, mime, path }`.
- **The adapter contract** gains `uploadAttachment(file, { conversationId })`, which resolves to `{ path }`, and `getAttachmentUrl(path)`, which resolves to a URL.
- **Local adapter:** stores blobs in **IndexedDB** (`lime-files` database; **not** `localStorage`, which caps at about 5 MB). URLs come from `URL.createObjectURL`.
- **Production** (documented): a Supabase Storage bucket `attachments`, path `<conversationId>/<messageId>/<filename>`, with storage RLS by `is_member`.
- **Limits:** 10 MB per file, and up to 5 files per message. Any type is allowed. Images (`image/*`) render inline, and everything else renders as a file card.
- **Reset demo data** clears `lime-files` too.

**Scope:**
- **May touch:** `public/index.html` (a hidden `<input type="file" multiple>` per composer), `public/js/app.js` (the + button, pending-attachment chips in `createComposer`, sending, rendering), `public/js/store.js` + `local-adapter.js`, `public/css/lime.css`, `docs/data-model.md` + `docs/schema.sql`, and `TEND.md`.

**The change:**
1. **Choosing files:** + opens the file picker. Chosen files appear as **removable chips** above the input inside the composer box: an image thumbnail, or an icon with the name and size.
   - Over-limit files are rejected with an inline error.
   - Send is active when there's text **or** at least one attachment.
2. **Sending:** each file uploads through the store (optimistically showing a sending state), then **one message per file** of type `image` or `file`. If the user typed text, it's sent as a text message first. Keep it simple and document it.
3. **Rendering:**
   - **Images:** a thumbnail (max 240 × 180, rounded), clicking to open full size in a lightbox modal (blur backdrop).
   - **Files:** a card with an icon, the name, a muted size, and a Download link.
   - Both appear in the main thread and replies.
   - **List previews:** "📎 filename" or "Photo".
4. **Drag and drop** onto a composer is optional; include it only if it's trivial with the same path.

**Verification:**
- jsdom with File and IndexedDB stubs, or Playwright + Firefox with real files from the scratchpad (an image and a PDF): uploads persist across reload (the blob is in IndexedDB), and they render.
- An 11 MB file is rejected. Previews are correct. Reset clears the files.
- Playwright + Firefox: the chips don't overflow the composer, and the Send gap is still ≥ 8px (LIME-32).

**Gate:** in Firefox:
- **Photo:** click + in the main box and attach a photo. A preview chip appears, and sending shows the image in the chat. Click it to enlarge.
- **Other files:** attach a PDF and it shows as a file card with Download.
- **Reply box:** the same.
- **Remembering:** reload, and they're still there.

**Record:** add a `## LIME-38` entry to `TEND.md`. Commit: `feat: file and image attachments via +, IndexedDB-backed locally`, trailer `Brief: LIME-38`, plus the attribution trailer.

> **Shared context for LIME-33 and LIME-29: the "sign up → sign in → find a teacher → message them" milestone** (user, 2026-09-28): "I want to plan to have a version running that I can sign in to and sign up an account, then create a message, search and find the new teacher to message." **Decided: accounts live in this browser** (local). The user runs into usage limits often, so this milestone is **prioritised ahead of LIME-27 and 28** and kept to two briefs.
>
> **Survey (plot):**
> - `login.html` checks one hard-coded credential from the gitignored `demo-config.local.js` and writes `lime-demo-session`.
> - `signup.html` calls `supabase.js` with **placeholder** keys, so it can't work.
> - `auth.js` (`LimeAuth`) has `changeEmail`, `changePassword` (validation only) and `signOut`.
> - `store.js` ~56 resolves the current user from `lime-demo-session`'s email and **falls back to teacher-002 when there's no session.**
> - The global search modal is a static mockup.
> - There's no "new message" UI.
>
> **Production-ready rule:** the auth seam must look like Supabase auth (`signUp`, `signInWithPassword`, `signOut`, `getSession`), so the switch is a body swap. **Credentials are kept separate from profiles,** as Supabase keeps `auth.users` separate from `public.profiles`.
>
> **Capability assumptions for both briefs:** can edit files, run commands and commit. Load the real app in jsdom (zero errors). Measure with Playwright + Firefox per `TEND.md` LIME-31-fix. Check `git diff` of the HTML files before committing.

### LIME-33 → `tend` (next, after LIME-49's check; amended 2026-09-30): local accounts, with real sign up and sign in

**Goal:**
- `signup.html` creates a real (browser-local) account, and a profile that appears in the teacher directory.
- `login.html` signs in with any local account, **or** any seed teacher's email plus the shared demo password.
- `index.html` requires a session, and sign out works.
- A second account can be created, signed out of, and signed back into, in the same browser.

**Scope:**
- **May touch:** `public/js/auth.js`, `public/js/store.js` and `public/js/local-adapter.js` (profile creation and the session read), `public/login.html` and `public/signup.html` (their inline scripts and script tags), `public/index.html` (the session gate script tag, if needed), `docs/data-model.md` (the auth seam section), and `TEND.md`.
- **May not touch:** `supabase.js` (leave it untouched and unused; remove it from `signup.html`'s script tags, and note it in the switch checklist), the seed JSON, or the app UI beyond the session gate.

**The change:**
1. **The `LimeAuth` API, shaped like Supabase's:**
   - `signUp({ email, password, displayName })`
   - `signInWithPassword({ email, password })`
   - `signOut()`
   - `getSession()`
   All return Promises. Keep `changeEmail` and `changePassword`, and update `changePassword` so it **really works** for local accounts (verify the current password, then store the new hash).
2. **Local credentials,** under their own `localStorage` key, `lime-auth-v1`: `{ [email]: { userId, salt, hash } }`.
   - The hash is **PBKDF2-SHA256 via `crypto.subtle`**, with a random 16-byte salt and ≥100,000 iterations. **Never store plain passwords.**
   - Add a comment: "local demo only; Supabase auth replaces this entirely".
   - **Rules:** email format, emails are unique across credentials **and** profiles, the password is ≥ 8 characters, and a display name is required.
3. **Seed teachers can sign in:**
   - If the email matches a seed profile with no local credential, accept it with `window.LIME_DEMO_CREDENTIALS.password` (the existing gitignored file).
   - If that file is missing, show the existing "demo credentials aren't configured" message **only for seed emails.** Local accounts don't need the file.
4. **Sign-up creates a profile** through the store:
   - Add a store write, `createProfile({ id, email, display_name })`, and document it in the contract.
   - The `id` is `crypto.randomUUID()`. The other fields are null.
   - It persists in the `lime-state-v1` snapshot, and **the `seedVersion` check must not discard snapshots that contain user-created profiles.** Confirm how.
   - Then sign in and redirect to `index.html`.
5. **Session:** `lime-demo-session` becomes `{ userId, email }`, written by `signIn`/`signUp` and cleared by `signOut`.
   - `store.js` resolves the current user by `userId` (falling back to email for old sessions).
   - **Remove the teacher-002 fallback for the real app:** `index.html` with no valid session redirects to `login.html`. Keep a test-only override for jsdom (e.g. a flag the test sets) and document it.
6. **Reset demo data** wipes `lime-auth-v1` as well as the data snapshot, then signs out to `login.html`. Update the confirm dialog's message to say accounts are removed too.
7. **`login.html` and `signup.html`:** errors appear inline in the existing error elements. On success, go to `index.html`. `signup.html` still requires the terms checkbox. Each page links to the other (check the existing links).

**Verification:**
1. `node --check` and jsdom (zero errors) for `index.html`, `login.html` and `signup.html`.
2. **In jsdom:**
   - sign up `new.teacher@example.com` / "Test Teacher": a profile exists, and a credential exists **without the plain password anywhere in `localStorage`** (grep every key for it);
   - a duplicate email is rejected;
   - a short password is rejected;
   - sign out, then sign in with the wrong password (rejected) and the right one (succeeds);
   - sign in as the seed email `shem.robinson@ps113.edu` with the demo password, and the app renders as Shem;
   - `index.html` with no session redirects to `login.html`;
   - `changePassword` works for the local account;
   - reset wipes both keys.
3. **Playwright + Firefox:** the end-to-end sign up → land in the app as the new user (an empty list) → sign out → the login page.

**Amendment (plot, 2026-09-30, before sending):**
- **Verify the end-to-end flow in the real installed Firefox and in Chrome** (the LIME-52-fix5 rule: `crypto.subtle`, `localStorage` and redirects all have per-browser `file://` behaviour), not only Playwright's bundled Firefox. Report which binaries were used. `crypto.subtle` needs a secure context, so **confirm it exists on `file://` in both browsers before building on it**. If it doesn't, stop and ask the user.
- LIME-49 (`912240a`) added `avatar_url` handling and a shared avatar helper. A new account starts with no photo (initials) and can add one in Settings. Include that in the end-to-end test.
- Survey the current code first: many line references across `PLOT.md` predate LIME-50 to 54.

**Gate:** in Firefox:
- **Sign up:** open `file:///Users/shem/Sites/lime/public/signup.html` and sign up as a new teacher. You land in Lime as them, with an empty list.
- **Sign in as yourself:** sign out, then sign in as `shem.robinson@ps113.edu` with the demo password.
- **(Finding and messaging them is LIME-29.)**

**Record:** add a `## LIME-33` entry to `TEND.md`. Commit: `feat: local accounts with sign up, sign in and session gate`, trailer `Brief: LIME-33`, plus the attribution trailer.

---

### LIME-29 → `tend` (next, after LIME-48's check; amended 2026-09-30): New message: find any teacher and start a DM or group

**Goal:**
- A **New message** button next to the Messages/Communities tabs opens a people picker in the search-modal style.
- Type a name, email or school to find any teacher, **including accounts just signed up**. Pick one to start (or reopen) a DM, or several for a group with an optional name.
- It lands in the conversation with the composer focused.
- The other person sees it when they sign in.

**Scope:**
- **May touch:** `public/index.html` (the button, and the picker markup if it isn't built dynamically), `public/js/app.js`, `public/css/lime.css` (small additions reusing `.lime-menu__*`, the search modal and the LIME-26 dialog styles), `public/js/store.js` (only if a read is missing, e.g. `listProfiles()`; add it to the contract doc), `docs/data-model.md`, and `TEND.md`.
- **May not touch:** creating communities (that waits for LIME-28), the global nav search modal (still a mockup), or the store's write semantics.

**The change:**
1. **The button:** an icon button (`dew-plus`, `title` and `aria-label` "New message") at the right of the tabs row, neutral style. It fits beside the tabs at every width. Measure it.
2. **The picker** (the search modal's look, with the blur backdrop, a close ×, Escape and a focus trap):
   - a search input ("Search teachers by name, email, phone or school"), autofocused;
   - **phone search (user, 2026-09-29):** match `profiles.phone`, comparing **digits only** on both sides (so "+1 (555) 012-3456", "555-0123" and "5550123" all match), and only once ≥ 4 digits are typed;
   - **an unknown email or phone (user, 2026-09-29):** when the query is a valid email address, or ≥ 7 digits, and matches **no** profile, show a row: "No teacher found with <query>", with an **"Invite"** button, disabled, with a small "Soon" pill (LIME-23 style) and an accessible label ("Invites coming soon"). **Production** (for `data-model.md` and the switch checklist): invites are a server action sending an email (Supabase Edge Function or auth invite) or an SMS (a provider such as Twilio), stored in an `invites` table (`id`, `inviter_id`, `email` or `phone`, `conversation_id`, `status`, `created_at`); accepting one on sign-up adds the new user to the waiting DM. **Document only; don't build it;**
   - results from `listProfiles()` excluding yourself, filtered case-insensitively on name, email and school (and phone, as below);
   - each result shows an avatar, the name, and a muted school or email, and arrow keys plus Enter work;
   - **with an empty query,** show everyone, sorted by name (the directory is small);
   - **selecting a person** adds a removable chip above the list. Enter with the query empty, or the **"Start"** button (the primary, lime), creates it.
   - **One chip → DM:** `createConversation({ type: 'direct', memberIds })`, which returns the existing DM if there is one.
   - **2+ chips → group:** an optional "Group name" field appears (blank means auto-title), then `createConversation({ type: 'group', memberIds, name })`. The current user becomes the owner.
   - Then close, select the conversation, and focus the composer.
3. **Empty states:**
   - a brand-new account's Messages list shows a muted line, "No conversations yet", with a "New message" text button that opens the picker;
   - no search results shows "No teachers match "…"".
4. **After the first message,** the conversation sorts to the top (existing behaviour) and is visible to the other member on sign-in (membership rows).

**Verification:**
1. `node --check`, and jsdom (zero errors).
2. **In jsdom:**
   - searching "valene" finds Valene, and "ps113" finds PS 113 staff;
   - a signed-up test account appears in results;
   - picking Alexi opens the **existing** DM (no duplicate; the `dm_key` rule);
   - picking a new person creates a DM, and sending a message puts it at the top of All;
   - two people create a group, named or auto-titled, and the current user is owner (Rename and Delete visible in its ⌄ menu).
3. **The end-to-end scenario, via jsdom or Playwright + Firefox:**
   - sign up "Test Teacher" and sign out;
   - sign in as Shem, New message, search "Test", start a DM and send "Welcome!";
   - sign out, sign in as Test Teacher: the DM is there, with "Welcome!".
4. **Playwright + Firefox:** the picker is centred over the blur, the chips wrap without overflow, and the New message button doesn't crowd the tabs at 1567px or 767px.

**Amendment (plot, 2026-09-30, before sending):**
- **Sign-in and sign-up now live in `auth.html`** (LIME-48 `3ac4b6d`; `login.html`/`signup.html` redirect there). Every end-to-end step goes through it.
- **Preview and verify over `http://localhost:8000/public/…`**, not `file://`. Verify the end-to-end scenario in the **real installed Firefox and in Chrome**. With `puppeteer-core`, restore Firefox's real defaults via `extraPrefsFirefox` (see `TEND.md` LIME-33-fix).
- Both accounts share one browser's local data, which is what makes "the other person sees it on sign-in" work locally. Say so in `docs/data-model.md`: production gets it from Supabase membership rows plus RLS.
- **Confirm `profiles.phone` exists** in the schema and seed data before building phone search. If it doesn't, stop and ask the user.
- The line references above predate LIME-49 to 48. Survey first.

**Gate:** the user runs the milestone in Firefox at `http://localhost:8000/public/auth.html`:
1. Sign up a new teacher.
2. Sign out.
3. Sign in as yourself.
4. Click **New message**, search their name, and start a chat.
5. Send a message.
6. Sign out, sign in as the new teacher, and see your message.

**Record:** add a `## LIME-29` entry to `TEND.md`. Commit: `feat: new message picker: find any teacher, start a DM or group`, trailer `Brief: LIME-29`, plus the attribution trailer.

### LIME-27 → `tend` (next, after LIME-29's check; amended 2026-09-30): Share and Copy link, deep links, and toasts

> **REVISED 2026-09-29 (user feedback; this supersedes the Actions section below where they conflict):**
> - **Share moves out of the menus into its own header button.** Remove "Share link" from the header "…" menu (`#more-menu`, `index.html` ~177). **Don't** add Copy link or Share to the title ⌄ menu (drop that part of item 3 below).
> - Add a **Share icon button** (`dew-share`) in the thread header **right after the avatars**. The header order becomes: avatars · Share · Background (LIME-45) · "…".
> - **It opens a popover modelled on Claude's "Share session" panel:**
>   - **Title** 'Share "<chat title>"', with the close × at the top right, and a muted subline: "Only people in this chat can see its messages" (for communities: "Anyone in Lime can view this community").
>   - **"Add people by email"** field plus an **Invite** button, **for groups only.**
>     - It looks up `findProfileByEmail`. A match gets added to the group (a new store write, `addMembers(conversationId, profileIds)`, allowed when `can('addMembers')` is the owner, with a greyed reason otherwise; document the RLS against the existing `is_owner` insert policy).
>     - No match shows "No teacher with that email · Invite (Soon)", reusing LIME-29's invite placeholder.
>     - **For DMs** the field is replaced by a muted line: "To add people, start a group from New message."
>   - **"Who has access":** a row with a lock icon, "Only people in this chat" (a globe and "Anyone in Lime" for communities), and a disabled chevron (link-access settings are future); then the **member list**: avatar, name ("(you)" for yourself), email, and the role (Owner or Member), scrolling if long.
>   - **A small muted note:** "Don't share personal information about students or families without permission."
>   - **Footer:** a **"Copy link"** primary button (lime, the primary action) with `dew-link`. It uses the deep link and toast from this brief.
>   - **Not included:** Claude's "Share with your team / Upgrade" row, and the settings gear.
> - Deep links, the access rule and toasts stay as specified below.

**Context:** the lifecycle sequence. LIME-26 (`e90bfd1`) left a slot comment in `CONVERSATION_ACTIONS` (app.js ~1045): "LIME-27 adds Share and Copy link here, between Rename and Archive." Seed ships a toast component (`vendor/seed/components/toast/toast.css`, with container positions; the JS pattern is in `toast.html`), which isn't linked yet. Per the RLS draft, **only members can open a DM or group; community conversations are readable by any signed-in user.**

**Capability assumptions:** can edit files, run commands and commit. Load the real app in jsdom (zero errors). **Measure with Playwright + Firefox per `TEND.md` LIME-31-fix. Check `git diff public/index.html` before committing.**

**Scope:**
- **May touch:** `public/index.html` (link `toast.css`, a toast container, the share dialog markup if it isn't built dynamically), `public/js/app.js`, `public/css/lime.css` (small overrides only), `docs/data-model.md` (the deep-link format and access rule), and `TEND.md`.
- **May not touch:** the store's write semantics, Seed files, or Communities UI.

**The change:**
1. **Toasts:**
   - Link Seed's `toast.css` and add one container, `bottom-center`.
   - Add a helper, `showToast(message, { tone = 'neutral', duration = 3000 })`, following `toast.html`'s pattern.
   - The container is `role="status"` and `aria-live="polite"`. Toasts are dismissible and never cover the composer's Send button (measure).
   - The neutral tone uses neutral Seed tokens. **No lime** (the lime rule).
2. **Deep links:**
   - The format is `#c=<conversationId>` on the app URL, and it lives in one helper, `conversationLink(id)`, built from `location.href` without its hash.
   - On load, **after `LimeStore.init()`**: if the hash names a conversation that exists, isn't deleted, and **the current user may read** (a member, or `type === 'community'`), open it.
   - Otherwise open the default and show the toast "That chat isn't available to you."
   - When a conversation is selected, `history.replaceState` updates the hash, so a reload keeps your place without adding history entries.
   - Document the format and the access rule in `data-model.md`. **In production this is the deployed app URL. The `file://` form is local-only.**
3. **Actions** (in the slot, between Rename and Archive):
   - **Copy link** (key L, `dew-link`): copies `conversationLink(id)` via `navigator.clipboard.writeText`, then shows the toast "Link copied".
     - If the clipboard API is unavailable or rejected (it can be on `file://`), fall back to a hidden textarea plus `document.execCommand('copy')`.
     - If that also fails, open the Share dialog so the user can copy it by hand.
   - **Share…** (no key, `dew-share`): a small dialog using the LIME-26 dialog styling.
     - Title: 'Share "<title>"'.
     - A read-only field with the link, and a "Copy" button beside it (the same copy path, with the toast).
     - A muted line: "Only people in this chat can open it." For communities: "Anyone in Lime can open it."
     - A "Done" button. It closes with Escape or the backdrop, and uses the blur backdrop.
   - Both are visible for every conversation type.

**Verification:**
1. `node --check`, the brace count, and the real app in jsdom (zero errors).
2. **In jsdom:**
   - `conversationLink('conv-011')` ends with `#c=conv-011`.
   - Loading with `#c=conv-004` opens Alexi's DM. `#c=conv-008` (STEM Squad, **not a member**) opens the default and shows the "not available" toast. A deleted conversation behaves the same.
   - Selecting a conversation updates the hash through `replaceState` (`history.length` unchanged).
   - Copy link calls the clipboard path and shows "Link copied". Force the fallback and confirm the dialog opens.
3. **Playwright + Firefox:**
   - the menu order: Star · Rename (if permitted) · Copy link · Share… · Archive · divider · Delete (if permitted);
   - the toast is positioned bottom-centre and doesn't overlap the composer's Send button (report both rects);
   - the Share dialog is centred over the blur, and its field doesn't overflow;
   - **a real deep-link load in Firefox** opens the right chat.

**Amendment (plot, 2026-09-30, before sending): this settles every conflict between the REVISED box and the older sections.**
- **Where Share lives:** only the header **Share button** (right after the header avatars, then the palette/Appearance button from LIME-50 to 52, then "…"). **Neither Copy link nor Share… goes into the title ⌄ menu**, so skip "3. Actions" and remove the LIME-26 slot comment in `CONVERSATION_ACTIONS`. Remove "Share link" from the "…" menu. **Copy link is the popover's footer button**; its clipboard fallback chain (clipboard API → hidden textarea → select the link text in a read-only field in the popover) stays as specified. The "Share…" small dialog is replaced by the Claude-style popover from the REVISED box.
- **Verification is replaced accordingly:** the ⌄ menu order is unchanged from today (Star · Rename · Archive · Delete); the header order is avatars · Share · palette · "…"; the popover shows the title, subline, add-by-email (groups only; a DMs line instead), "Who has access", members with roles, the students note, and Copy link.
- **`addMembers(conversationId, profileIds)`** is a new store write: owner-only via `can('addMembers')`, persisted, visible to the added member on sign-in, and documented with its RLS. **The newly added member gets a system line in the chat** ("Shem added Valene") **only if** a system-message type already exists. Otherwise skip it and note it for later.
- **Preview and verify over `http://localhost:8000/public/…`**, not `file://`. The deep link is `http://localhost:8000/public/index.html#c=<id>` locally. **Verify in the real installed Firefox and in Chrome** (clipboard behaviour differs), and with `puppeteer-core`, restore Firefox's real defaults via `extraPrefsFirefox` (`TEND.md` LIME-33-fix). **A deep link opened while signed out** goes to `auth.html`, then **back to the linked chat** after sign-in (carry the hash through the session gate and the `?from=auth` redirect).
- **Saving:** LIME-29 added `LimeStore.flush()` before sign-out. **Anything this brief writes must survive an immediate reload or tab close.** Add a `pagehide` flush (the general fix for the 100ms debounce race) if it's small. If not, report it.
- The line references above predate LIME-33 to 29. Survey first.

**Gate:** in Firefox, at `http://localhost:8000/public/index.html`:
- **Copy link:** Share → Copy link, and a small "Link copied" notice appears. Paste the link into a new tab: it opens straight to that chat.
- **Share…:** ⌄ → Share… shows the link with a Copy button and who can open it.
- **Reload:** reloading keeps you on the chat you were in.
- **No access:** open a link to a chat you're not in (tend will give you one), and it says it isn't available.

**Record:** add a `## LIME-27` entry to `TEND.md`. Commit: `feat: share and copy link, deep links, toasts`, trailer `Brief: LIME-27`, plus the attribution trailer.

### LIME-32 → `tend` (queued after LIME-26; the user said "future update"): the main composer toolbar collapses by its own width, like the reply composer

**The user's QA (2026-09-28, screenshot):** with a narrower window (right panel closed), the main composer's expanded toolbar (B I U S | link, numbered, bulleted | quote, code) runs under the Send ↵ button, which overlaps the code icon. "The chatbox icons need to be responsive like the reply chatbox."

**Root cause (plot read `lime.css` ~2905–2955):** the main composer only collapses extra tools into "…" at `@media (max-width: 480px)`, a **viewport** breakpoint, plus a right-panel-state size tweak. The composer's **own** width depends on the window, the left and right panels, and the 75% box rule, so no viewport breakpoint can be right. The reply composer avoids the problem by collapsing unconditionally (LIME-18-fix3).

**Capability assumptions:** can edit files, run commands and commit. **Measure with headless Chrome** at several widths (see Patterns).

**Scope:**
- **May touch:** the composer toolbar rules in `public/css/lime.css` (~2880–2960), and `TEND.md`.
- **May not touch:** the composer's markup and JS (the "…" overflow menu already exists for both composers), the Send button's position, or the reply composer's current look.

**The change** (a CSS container query: the composer responds to its own width, not the window's):
1. `.lime-composer__box { container-type: inline-size; container-name: composer; }`. Check this doesn't break the box's existing `width: 75%` or its absolutely positioned Send button, and report.
2. **Measure** the width the full toolbar needs: every tool, the dividers and gaps, **plus** the Send button's footprint and a comfortable gap (≥ 8px). Call it `W`.
3. Replace the `@media (max-width: 480px)` collapse with `@container composer (max-width: <W>px)`: hide `.lime-composer__tool--overflow` (and any divider left dangling) and show `.lime-composer__overflow`.
4. **The reply composer:** replace its unconditional collapse with the **same container rule.** Its box is narrow enough that it should still collapse at every realistic width. Verify it; if it ever wouldn't, keep the unconditional rule for it and say why.
5. Remove or trim the now-redundant `#layout:not(.seed-layout--right-hidden) .lime-composer__tool` size tweak **only if** measurement shows it's no longer needed. Otherwise keep it.
6. Add a comment: "Composer width varies with window + panels; key the collapse off the composer's own width (container query), never the viewport."

**Verification (headless Chrome, both composers expanded, typing so Send is active):**
- Test at window widths of 1567, 1280, 1100 and 900px, with the right panel both open and closed, and at 767px.
- Report whether the toolbar is collapsed, the gap between the last visible tool's right edge and Send's left edge (**must be ≥ 8px everywhere**), and that nothing overflows the box.
- The "…" menu still opens, fully on-screen (LIME-20).
- Firefox supports container queries (110+). Note the version assumption in the comment.

**Gate:** in Firefox, open a chat, click into the message box, then make the window narrower and wider. The formatting icons tuck into "…" before they ever reach the Send arrow. The reply box behaves the same.

**Record:** add a `## LIME-32` entry to `TEND.md`. Commit: `fix: composer toolbars collapse by their own width (container query)`, trailer `Brief: LIME-32`, plus the attribution trailer.

### LIME-31-fix → `tend` (before LIME-26): Settings layout: compact rows, an always-visible Save/Cancel, clean focus, nothing touching the edges

**The user's check of LIME-30/31 (2026-09-28), with Notion's Account page and Claude's Profile settings as references ("I like some of the way the content is organized in these examples, let's update before we move forward"):**
1. **Save and Cancel are always visible** at the bottom, so it's clear how to commit or back out.
2. **All content fits in the modal without scrolling,** if possible.
3. **No green focus outlines** on fields. Keep it clean, as the app already does elsewhere.
4. **The profile image sits next to the name** (Notion).
5. **Padding all round:** no field touches the modal's edge. In the screenshot, the Login & security password inputs run past the pane's right edge, and a horizontal scrollbar appears.
6. **Organisation like the references:** a label on the left with a compact control on the right (Claude), and grouped subsections with headings and dividers (Notion).

**Root causes (plot read `lime.css` ~1290–1600 and Seed's `input.css` ~44–110):**
- **The overflow** is the same recurring bug: `.seed-input` is `width: 100%` plus padding in content-box, and nothing inside `.lime-settings` sets `border-box`. That's the fifth time (18-fix4, 20, 21b, the composer, now here).
- **The green ring** is Seed's `.seed-input:focus` `--seed-shadow-focus` (`rgba(9, 169, 80, 0.30)`). The nav search field already overrides it (lime.css ~1846).
- **It's too tall** because every Profile field is a stacked label over a full-width input, which roughly doubles the height of a label + control row.

**Capability assumptions:** can edit files, run commands and commit. Load the real app in jsdom (zero errors). **Measure with headless Chrome at 1567×905** (see Patterns).

**Scope:**
- **May touch:** the settings markup and rendering in `public/js/app.js` and `public/index.html`, and the `.lime-settings*` and `.lime-password-field*` rules in `public/css/lime.css`, plus `TEND.md`.
- **May not touch:** the store or auth contract and its behaviour (validation, discard confirmation, no password storage), other modals, and global focus styles outside settings.

**The change:**
1. **A scoped box-model fix:** `.lime-settings, .lime-settings *, .lime-settings *::before, .lime-settings *::after { box-sizing: border-box; }`, with a comment pointing at the open "global border-box reset" thread. This is deliberately scoped, and plot will decide the global reset separately.
2. **Clean focus, still accessible:** inside `.lime-settings`, `.seed-input:focus` gets `box-shadow: none` and `border-color: var(--calm-border-bold-default)`. **A visible focus indicator must remain** for keyboard users; this dark border is it. Buttons and nav items keep a neutral `:focus-visible` outline.
3. **Always-visible footer:**
   - The pane becomes a column: a scrolling body plus a **fixed footer** (not sticky-inside-scroll) with a top divider and padding matching the body.
   - **Profile:** "Cancel" (neutral) and "Save changes" (the primary, lime). Both are always shown and **disabled until the form is dirty**.
   - Cancel reverts the form. Save keeps the current validation.
   - **Login & security has no footer.** Its changes are per-row, below.
4. **The Profile layout** (Claude rows plus Notion grouping):
   - **Top block:** the avatar (56px) **beside** the Display name field (label above that one input, as in Notion), plus the "Upload photo · Soon" control under or beside it.
   - **Then compact rows** (the label left, a control ≤ 280px wide right-aligned, a divider between rows, ~44px row height): Pronouns, Role, School, Grade levels, Subjects, Timezone, Phone.
   - **Bio** last: a label, then a 2–3-line textarea spanning the content width.
   - The pane padding is `--seed-space-6` on all sides, so no control touches an edge.
5. **The Login & security layout** (Notion's "Account security"):
   - Rows with a label plus a muted value under it on the left, and a small "Change" button on the right: Email (the address), and Password ("Set a new password for your account").
   - **Change** expands a compact inline form **inside the pane's padding**:
     - email: one input plus Cancel and Save;
     - password: current, new and confirm, **each ≤ 360px wide,** with the show/hide toggle inside the field, plus Cancel and Save.
   - Then a divider, and an "Account" subsection with the Sign out row.
   - Use subsection headings ("Account security", "Account") styled like the references: `--seed-text-base` semibold with a divider under them.
6. **Fitting without scrolling:** at 1567×905 (the modal is 720px tall), **Profile's body should not scroll.** Tighten the spacing (title and description margins, row padding) until it fits, keeping readability. If it can't fit without cramping, keep the footer fixed, let only the body scroll, and report how much overflowed. Don't shrink text below `--seed-text-sm`.

**Verification:**
1. `node --check`, the brace count, the real app in jsdom (zero errors), and every LIME-31 behaviour check re-run: validation, discard confirmation, email change, password validation, and **nothing stored**.
2. **Headless Chrome, 1567×905:**
   - the Profile body's `scrollHeight` ≤ `clientHeight` (report both);
   - the footer is visible without scrolling, and Save is disabled until an edit;
   - **every input's right edge is inside the pane's padding box** (report the max overshoot; it must be ≤ 0), for both sections, including the expanded password form;
   - no horizontal scrollbar (`scrollWidth` = `clientWidth`);
   - a focused input's computed `box-shadow` is `none` and its border colour is `--calm-border-bold-default`;
   - the avatar sits beside the Display name field (report both rects).
3. **At 767px:** the full-screen layout still works; rows may stack (label above control) below ~560px wide.

**Gate:** in Firefox, Settings:
- **Fit:** Profile fits without scrolling, with your photo beside your name and compact rows.
- **Footer:** Save and Cancel are always at the bottom, greyed out until you change something.
- **Focus:** no green glow when you click into a field, just a darker border.
- **Login & security:** open Change on the password. Nothing runs off the right edge, and there's no sideways scrollbar.

**Record:** add a `## LIME-31-fix` entry to `TEND.md`. Commit: `fix: settings layout: compact rows, persistent footer, clean focus, contained fields`, trailer `Brief: LIME-31-fix`, plus the attribution trailer.

### LIME-26 → `tend` (after LIME-31): Rename (inline), Archive (with an Archived section), Delete (red, confirmed), and the app's own confirm dialog

**Context:** the lifecycle decisions: Archive **and** Delete, **only Delete is red**, actions **only** in the title ⌄ menu. LIME-25 built `CONVERSATION_ACTIONS` (app.js ~850) with Star/S. LIME-30/31 built `createModal` (app.js ~1554, with `onBeforeClose`) and the blurred `.lime-modal-backdrop`. The store already has `renameConversation`, `setArchived`, `deleteConversation` (a soft delete) and `can()` (store.js ~196: rename = owner and not a DM; delete = owner).

**Ownership in the seed (plot checked):**
- The current user **owns** conv-007 "Math Teachers NYC" and conv-010 "Jean, Mary, Jimin & Me".
- Jean owns conv-006 and conv-011.
- **DMs have no owner** (seed DMs have no `created_by`, and the adapter's role check uses the raw field).
- **Decision (plot): DMs get Star and Archive only**, with no Rename (the title is the person) and no Delete (removing a DM for yourself is what Archive is for; there's no "delete for both" in v1). Non-owned groups get Star and Archive only; "Leave group" is a later brief. Document this in `docs/data-model.md`'s permissions note.

**Capability assumptions:** can edit files, run commands and commit. Load the real app in jsdom (zero errors). Use headless Chrome for visuals (see Patterns).

**Scope:**
- **May touch:** `public/js/app.js`, `public/index.html` (the Archived section scaffold and the confirm dialog markup, if it's not built dynamically), `public/css/lime.css` (the confirm dialog, the rename input, the menu divider), `docs/data-model.md` (the permissions note only), and `TEND.md`.
- **May not touch:** the store's write semantics (if a gap turns up, stop and ask **the user**), Communities, Share (LIME-27), or Create (LIME-29).

**The change:**
1. **Confirm dialog** (reusable): `confirmDialog({ title, message, confirmLabel, cancelLabel = 'Cancel', danger = false })` returns a Promise of true or false.
   - Built on `createModal` with the blurred backdrop.
   - Styling: `min(400px, calc(100vw - 32px))` wide, the settings modal's surface, radius and shadow; the title in `--seed-text-base` semibold; the message muted; buttons right-aligned.
   - **Buttons:** Cancel is neutral. Confirm uses `--bad-bg-bold-default` with white text when `danger`, otherwise the primary style.
   - Focus lands on **Cancel**. Escape or the backdrop means cancel; Enter on a focused button activates it.
   - **Replace both native `confirm()` calls** (Reset demo data at app.js ~1497, and settings' "Discard changes?" at ~1766) with it. `onBeforeClose` is currently synchronous; if it needs to await, extend `createModal` minimally and document it.
2. **Action list:**
   - Extend `CONVERSATION_ACTIONS` with `{ divider: true }` support. A divider renders only when there are visible items on both sides.
   - **The final order:** Star (S) · Rename (R, `dew-pencil`, visible when `can('rename')`) · Archive / Unarchive (A, `dew-archive`, the label from `membership.archived_at`) · divider · Delete (D, `dew-trash`, `danger: true`, visible when `can('delete')`).
   - LIME-27 will add Share and Copy link between Rename and Archive. Leave a comment saying so.
3. **Inline rename**, Claude-style (the user's reference: the title becomes a rounded input with the whole name selected):
   - Rename swaps `#crumb-thread` for an `<input>` with the current title, **all text selected**, auto-sized to its content (min 120px, capped at the available breadcrumb width), a 1px `--calm-border-normal-default` border, `--seed-radius-md`, and a visible focus ring.
   - **Enter or blur** saves via `renameConversation`; **Escape** cancels. An empty value clears the name back to the auto title (store behaviour).
   - Then restore the button. The list rows, breadcrumb and header update via `lime:conversations-changed`.
4. **Archive:**
   - Archiving removes the conversation from All and Starred. **An "Archived" section** at the bottom of the Messages panel (the same `lime-section` pattern, `data-section-id="archived"`, **collapsed by default**, header "Archived") lists archived conversations with the same row builder. It's hidden entirely when empty.
   - Unarchive (from the menu when the archived chat is open) returns it to its sections.
   - An open conversation stays open when archived.
   - New messages don't auto-unarchive (v1).
5. **Delete:**
   - Delete → `confirmDialog({ title: 'Delete "<title>"?', message: 'This removes it for everyone in it. This can’t be undone.', confirmLabel: 'Delete', danger: true })`.
   - On confirm: `deleteConversation`. If it was open, select the top conversation in All (or show the empty thread state if none remain).
   - Its rows disappear everywhere.
6. **Keyboard:** R, A and D work while the menu is open, like S. They only fire for visible actions.

**Verification:**
1. `node --check`, the brace count, and the real app in jsdom (zero errors).
2. **In jsdom:**
   - **The menu for each case:** a DM shows Star and Archive; conv-006 (not owned) shows Star and Archive; conv-010 (owned) shows Star, Rename, Archive, a divider and Delete.
   - **Renaming conv-010** to "Trivia Crew": the breadcrumb and row update, and it persists. Clearing the name returns "Jean, Mary & Jimin".
   - **Archiving Alexi:** it leaves All and appears under Archived. Unarchive brings it back.
   - **Deleting conv-007:** the confirm opens, cancel keeps it, confirm removes it, and the selection moves.
   - Both former native confirms now use the dialog (grep: no `window.confirm` left).
3. **Headless Chrome:**
   - the menu's divider and red Delete: the computed Delete colour is `--bad-text-bold-default`;
   - the rename input's text is selected on open (report `selectionStart`/`selectionEnd`);
   - the confirm dialog is centred over the blur, with the red confirm button;
   - the Archived section starts collapsed.

**Gate:** in Firefox:
- **What each menu offers:** open "Math Teachers NYC" (yours): its ⌄ menu has Star, Rename, Archive and a red Delete. A chat you don't own, and one-to-one chats, only get Star and Archive.
- **Rename:** the name becomes an editable box with the text selected. Type a new name and press Enter.
- **Archive:** archive a chat. It moves to a collapsed "Archived" section at the bottom, and Unarchive brings it back.
- **Delete:** a confirm dialog appears first (with a red Delete button), and Cancel keeps the chat.
- **"Reset demo data"** and **"Discard changes?"** now use the same dialog.
- Ask whether one-to-one chats having no Delete (only Archive) matches their intent.

**Record:** add a `## LIME-26` entry to `TEND.md`. Commit: `feat: rename, archive and delete conversations; app confirm dialog`, trailer `Brief: LIME-26`, plus the attribution trailer.

> **Shared context for LIME-30 and 31: the Settings modal** (user, 2026-09-27; **prioritised to run right after LIME-25, before LIME-26**).
>
> **What the user asked for:**
> - "a settings/preference page in [a] modal, so that updating profile, password, email… is easy to edit since it will be connected to a real database soon."
> - References: Claude's settings modal (a left nav with search, grouped sections, and label + description rows with the control on the right) and Notion's Preferences.
> - "I like the blurred-out version instead of just a dark overlay."
>
> **Decisions:**
> - **Sections for v1: Profile, and Login & security.** Notifications and Preferences aren't in v1 (they can be added later as nav items).
> - **Theme: light only.** Dark mode was never designed, and it'll be its own design pass. There's no theme control in v1.
>
> **Survey:**
> - The profile menu's "Settings" item (`index.html` ~118) is dead.
> - The profile menu header shows **static** "shem@example.com" and "+1 555-0123" (~114–115), not the current user's data.
> - The `profiles` table has no `phone`.
> - Seed has `input`, `toggle` and `tabs` components.
> - The search modal already has a backdrop, a focus trap and a close × (LIME-22). Reuse its patterns.
> - `app.js` line ~4 applies a stored `lime-theme`. Leave it alone.
>
> **Production-ready rules apply** (see the LIME-24 context): all data goes through `LimeStore`. **Email and password belong to the auth provider, not `profiles`.** On Supabase they go through `supabase.auth.updateUser`, with `profiles.email` synced by trigger. **Passwords are never stored locally,** in any form.

### LIME-30 → `tend` (after LIME-25): the Settings modal shell, a blurred backdrop for all modals, and read-only Profile and Login & security

**Goal:**
- "Settings" in the profile menu opens a modal in the style of the references: a left nav (a search field, an "Account" group label, then **Profile** and **Login & security**, with dew icons) and a scrollable right pane with a title, a short description, and label + value rows separated by subtle dividers.
- Both sections show the **current user's real data read-only** from `LimeStore` (editing is LIME-31).
- The modal has a top-right close ×, and closes with Escape or a backdrop click. There's a focus trap, and focus returns to the trigger.
- **Every modal backdrop (settings and search) is a light blur instead of a dark overlay.**

**Capability assumptions:** can edit files, run commands and commit. Load the real app in jsdom (zero errors). Use headless Chrome for visuals and measurements (see Patterns).

**Scope:**
- **May touch:** `public/index.html` (the modal markup, and the Settings item's `id="settings-btn"`), `public/css/lime.css` (the modal and backdrop styles, and moving the search backdrop onto the shared class), `public/js/app.js` (open/close, the focus trap, nav switching, search filtering, and read-only rendering; reuse or extract the search modal's focus-trap logic rather than duplicating it), and `TEND.md`.
- **May not touch:** the store contract, the data docs, or theme handling.

**The change:**
1. **A shared backdrop:** add `.lime-modal-backdrop` with `background: rgba(19, 27, 23, 0.12)`, `backdrop-filter: blur(8px)` and `-webkit-backdrop-filter: blur(8px)`, plus `@supports not (backdrop-filter: blur(1px))`, which falls back to today's `rgba(19, 27, 23, 0.3)`. The search modal's backdrop switches to this class (delete its duplicate rules). The settings modal uses it too.
2. **The modal:** `.lime-settings`, `role="dialog"`, `aria-modal`, `aria-labelledby` on the pane title.
   - `position: fixed`, centred, `width: min(960px, calc(100vw - 64px))`, `height: min(720px, calc(100vh - 64px))`
   - `--soil-bg-elevated`, `--seed-radius-lg`, `--seed-shadow-xl`, and the same z-index as the search modal
   - **Nav column** 240px wide, `--soil-bg-canvas`, padding `--seed-space-3`:
     - a search field in the nav search pill style;
     - the group label in `lime-menu__label` style;
     - items in `lime-menu__item` style;
     - the active item uses `--calm-bg-subtle-hover` with medium weight. It's a neutral selection, not lime, per LIME-21b.
   - **The pane** scrolls. Title in `--seed-text-lg` semibold, a muted description line under it, then the rows.
   - **Rows:** a label (`--soil-text`, medium) with an optional muted description under it on the left, the value or control on the right, and a 1px `--soil-border-subtle` divider between rows.
   - **The close ×** reuses LIME-22's close-button pattern, top-right of the modal.
3. **Content (read-only in this brief):**
   - **Profile:** a photo row (the current avatar at 48px, and a disabled "Upload photo" button with a small "Soon" pill, reusing LIME-23's style), then display name, pronouns, role, school, grade levels, subjects, bio, timezone, and phone ("Not set", since there's no column yet).
   - **Login & security:** email; password as "••••••••"; a disabled "Change" button on each (LIME-31 enables them); and a "Sign out" row whose button calls the existing sign-out handler.
   - All values come from `LimeStore.getCurrentUser()`. Nothing is hard-coded.
4. **Nav search:** filters the nav items **and** the row labels. Typing "pron" shows Profile, with the Pronouns row highlighted or scrolled into view. Keep it simple: hide non-matching nav items; clicking a match shows its section.
5. **Mobile (≤767px):** the modal goes full-screen (radius 0). The nav becomes a list; picking a section shows it with a back chevron to the list.
6. **The profile menu header:** replace the static email and phone with the current user's email, and phone or nothing.

**Verification:**
1. `node --check`, the brace count, and the real app in jsdom (zero errors). In jsdom: Settings opens, both sections render the current user's values (report 3), the search filters, and Escape, × and the backdrop all close it, with focus returned to the trigger.
2. **Headless Chrome at 1567px:**
   - the modal rect is centred and within the viewport;
   - the backdrop's computed `backdrop-filter` is `blur(8px)`, for both the settings and search backdrops;
   - the nav is 240px;
   - the rows' label/control alignment is consistent. Report 3 rows' rects.
3. **At 767px:** it's full-screen, and the list → section → back flow works.

**Gate:** in Firefox:
- **Opening:** Profile menu → Settings opens a modal over a **blurred** app.
- **Profile:** shows your real details.
- **Login & security:** shows your email.
- **Closing:** the × and Escape close it.
- **Search:** it's also blurred behind now.
- **Profile menu:** shows your real email.
- (Editing comes next, in LIME-31.)

**Record:** add a `## LIME-30` entry to `TEND.md`. Commit: `feat: settings modal shell (profile, login & security, read-only) and blurred modal backdrops`, trailer `Brief: LIME-30`, plus the attribution trailer.

---

### LIME-31 → `tend` (after LIME-30): editable Profile and Login & security, through the data contract

**Goal:**
- **Profile** fields are editable and saved through `LimeStore.updateProfile`. The change shows everywhere at once (avatars and initials, the sidebar name, message senders).
- **Login & security** can change the email and change the password, through an **auth seam** that maps cleanly onto Supabase auth later.
- The docs and schema are updated first.

**Capability assumptions:** as in LIME-30.

**Scope:**
- **May touch:** `docs/data-model.md`, `docs/schema.sql`, `public/js/store.js`, `public/js/local-adapter.js`, `public/js/app.js`, `public/index.html`, `public/css/lime.css` (the settings form styles only), and `TEND.md`.
- **May not touch:** `signup.html`, `supabase.js` or `login.html` logic, beyond reading the session key.

**The change:**
1. **Docs first:**
   - `schema.sql`: add `profiles.phone text`, and profile RLS: `select` for authenticated users, `update` only where `id = current_profile_id()`.
   - `data-model.md` contract:
     - `updateProfile(patch)`, with the allowed fields `display_name`, `pronouns`, `role`, `school`, `grade_levels`, `subjects`, `bio`, `timezone`, `phone`. Anything else is rejected. It emits `lime:profile-changed`.
     - The **auth seam**, a new small module, e.g. `auth.js`: `changeEmail(newEmail)`, `changePassword({ current, next })`, `signOut()`.
       - **Local behaviour:** `changeEmail` checks format and uniqueness against profiles, then updates `profiles.email` and the `lime-demo-session` email. `changePassword` validates only (minimum 8 characters, next ≠ current, and they match their confirmation) and **stores nothing**; the UI says "Password changes take effect once connected to the real account system."
       - **Supabase behaviour:** `supabase.auth.updateUser({ email })` (with confirmation-email semantics) and `updateUser({ password })`.
     - Add both to the switch checklist.
2. **Store and adapter:** implement `updateProfile` (optimistic, persisted, event) and add `phone` to the normalized profile (null by default). Make the `seedVersion` fingerprint handle the new field.
3. **Editing UX:**
   - **Profile** is a form. Plain inputs (Seed's `seed-input`), a textarea for the bio, comma-separated text for grade levels and subjects (chips come later), and a select for the timezone (common US zones plus the current value).
   - A **"Save changes" bar** appears at the bottom of the pane only when something has changed, with Save (the **primary** action, so it may use lime, per the lime rule) and Discard.
   - Validation: the display name is required, and the phone is loose (digits, spaces, `+`, `-`, `()`). Errors are shown under each field in `--bad-text-bold-default`.
   - Leaving the section, or closing the modal, with unsaved changes asks "Discard changes?".
   - **Login & security:** "Change" opens an inline form under its row.
     - Email: new email plus Save.
     - Password: current, new and confirm, with the show/hide toggle from `password-toggle.js` if it fits.
     - Show success and error inline.
4. **Everywhere updates:** on `lime:profile-changed`, re-render the sidebar user name, the profile menu header, every avatar for that person (the initials come from the name), and the open thread's sender names.

**Verification:**
1. `node --check`, the brace count, and the real app in jsdom (zero errors). **In jsdom:**
   - change the display name to "Shem Robinson-Test": the sidebar, avatars and thread senders update, and it persists (snapshot method);
   - an empty name blocks saving;
   - `changeEmail` to an existing teacher's email is rejected;
   - to a new one, it succeeds, and the session email updates;
   - `changePassword` validation works in all three failure cases and **writes nothing to `localStorage`** (grep the snapshot and keys for the test password: it must be absent).
2. **Headless Chrome:** the Save bar appears only when the form is dirty; the error text is under its field.
3. Reset demo data restores the profile.

**Gate:** in Firefox:
- **Profile:** Settings → Profile → change your display name and save. Your name and initials update across the app and survive a reload.
- **Unsaved changes:** edit something, then try closing. It asks before discarding.
- **Login & security:** change your email to a new address, and it updates. Try a short password, and you get a clear error.

**Record:** add a `## LIME-31` entry to `TEND.md`. Commit: `feat: editable profile and login & security through the data contract and auth seam`, trailer `Brief: LIME-31`, plus the attribution trailer.

### LIME-25 → `tend` (after LIME-24b): the title actions menu, with Star, and a real Starred section

**Context:** the lifecycle sequence (see that open thread). The user decided actions live **only** in the title caret menu, Claude-style, and **only Delete is red**. LIME-24b (`a870c1e`) delivered the store contract (`public/js/store.js`, `local-adapter.js`), with `setStarred` and `getMyMembership` available. **Per-user state:** starred is the current user's membership flag.

**Capability assumptions:** can edit files, run commands and commit. Load the real app in jsdom (zero errors). Use headless Chrome for placement and visuals (see Patterns).

**What plot read:**
- `index.html` ~148: `.lime-topbar__crumb-caret`, a dead "Switch conversation" button
- ~264–320: the Starred section is **still static markup** with fake "2" badges
- `app.js`: `conversationRowHtml` ~494 and `selectConversation` ~549
- the store's write functions (~212–308), which emit `lime:conversations-changed` with `kind`
- the dew icons available: `dew-star`, `dew-pencil`, `dew-share`, `dew-link`, `dew-archive`, `dew-trash`, `dew-undo`

**Goal:**
- The ⌄ next to the chat title opens a menu (the shared `.lime-menu` pattern from LIME-21b) whose first action is **Star** / **Unstar**.
- The Starred section lists exactly the conversations you've starred, live, sorted by latest activity.
- The menu is built so LIME-26 and 27 can add Rename, Share, Copy link, Archive and Delete by adding entries, not by restructuring.

**Scope:**
- **May touch:** `public/index.html` (the caret button's attributes; replace the static Starred `<li>`s with `<ul class="lime-contact-list" id="starred-list"></ul>`; add the menu container), `public/js/app.js`, `public/js/local-adapter.js` (demo starred defaults only), `seed-data/seed.ts` (the same defaults, for parity), `public/css/lime.css` (only if something new is needed; prefer the existing `.lime-menu` styles), and `TEND.md`.
- **May not touch:** the store contract (if something's missing, stop and ask **the user**), the Recent row, Communities, or other menus' behaviour.

**Phase 2 — The change:**
1. **The caret becomes the actions trigger.**
   - `id="conversation-menu-toggle"`, `title="Conversation actions"`, `aria-haspopup="menu"`, `aria-expanded` kept in sync.
   - Menu container: `<div class="lime-menu" id="conversation-menu" role="menu"></div>`.
   - Wire it with `wireDropdownToggle('conversation-menu-toggle', 'conversation-menu', { fixed: true })`, so it opens below and gets the LIME-20 flip, clamp and one-at-a-time behaviour.
2. **A data-driven action list** in `app.js`:
   - `CONVERSATION_ACTIONS = [{ id, label(conversation, membership), icon, key, isVisible(conversation), danger?: false, run(conversation) }]`
   - The menu's items are **rebuilt from this list each time it opens**, for the current conversation.
   - Each item is `<button type="button" class="lime-menu__item" role="menuitem">`, with a `dew` icon, the label, and a right-aligned muted key hint (`<span class="lime-menu__kbd">S</span>`; add a small CSS rule in the menu block: `margin-left: auto`, `--soil-text-muted`, `--seed-text-xs`).
   - **While the menu is open, pressing the hint key runs the action** (like Claude's). Escape still closes.
   - A `danger: true` item gets a `lime-menu__item--danger` class. Add the rule now, using `--bad-text-bold-default` for text and icon, and `--bad-bg-subtle-default` on hover. Nothing uses it until LIME-26's Delete.
   - **This brief adds exactly one action:** `star`, labelled "Star" or "Unstar" by `membership.starred`, with the `dew-star` icon, key `S`, run as `LimeStore.setStarred(id, !starred)`.
3. **A real Starred section:**
   - Rows come from `listConversations(...)` filtered by `getMyMembership(id).starred`, rendered with the same `conversationRowHtml` and sorted like "All".
   - Re-render on `lime:conversations-changed` and `lime:messages-changed`. Rows are safe to rebuild since 24b's delegated listeners.
   - The active highlight covers every row of the open conversation, in both sections.
   - **When there are no starred chats,** show one muted line inside the section: "Star a chat from its title menu." (the section header stays).
   - Delete the static Starred markup, including its fake badges and chevron.
4. **Demo defaults** (so the prototype isn't empty on first load):
   - `LocalAdapter`'s normalization marks the **current user's** membership `starred = true` for `conv-001` (Jean's DM) and `conv-010` ("Jean, Mary, Jimin & Me"), via a small, commented `DEMO_MEMBER_STATE`.
   - Mirror it in `seed.ts`, so a database seed matches.
   - The `seedVersion` fingerprint should change if these defaults change. Include them in the fingerprint or bump it, and say which.

**Phase 3 — Verification:**
1. `node --check` on every JS file, the brace count, and the real app in jsdom (zero errors).
2. **In jsdom:**
   - On load, Starred has 2 rows (Jean, and "Jean, Mary, Jimin & Me").
   - Open Alexi's DM, open the menu, click Star: Starred now has 3 rows, sorted by activity. Pressing `S` again in the reopened menu unstars it.
   - The label flips between "Star" and "Unstar".
   - Starred rows update when a message is sent.
   - At mobile width, tapping a Starred row goes to the thread view.
3. **Headless Chrome, 1567px and 767px:** the menu opens below the caret, fully on-screen, in the search-modal item style, with the key hint right-aligned. Report the rects.
4. **Persistence:** unstar Jean, then reload (or 24b's snapshot method); Jean is still unstarred. Reset restores the two defaults.

**Gate:** in Firefox:
- **The menu:** click the ⌄ next to a chat's name. A menu with **Star** (and an "S" hint) appears.
- **Starring:** star Alexi's chat, and it appears under Starred. Open the menu again: it says **Unstar**. Press S, and it's gone from Starred.
- **Remembering:** reload, and your stars are remembered.
- **Look:** Starred has no fake "2" badges any more.

**Record:** add a `## LIME-25` entry to `TEND.md`. Commit: `feat: conversation actions menu with Star; data-driven Starred section`, trailer `Brief: LIME-25`, plus the attribution trailer.

> **Shared context for LIME-24a and 24b: production-ready data layer** (user, 2026-09-27): "make sure that everything we're adding can easily be production ready when needed, meaning when we're ready to test with multiple email logins over an open-source database we can make the switch." **This replaces the earlier single LIME-24 draft, which was never sent.**
>
> **What the repo already assumes** (plot read `seed-data/seed.ts`, `useMockData.ts`, `README.md`, `public/login.html`):
> - The target is **Supabase (open-source Postgres)**, with the tables `profiles`, `conversations` (`id`, `type`, `name`, `description`, `created_by`, `created_at`, `updated_at`), `conversation_members` (`conversation_id`, `user_id`, `role` owner|member, `joined_at`), `messages` (`id`, `conversation_id`, `sender_id`, `content`, `type`, `metadata`, `reply_to`, `created_at`, `updated_at`) and `message_reactions` (`message_id`, `user_id`, `emoji`, `created_at`).
> - `seed.ts` converts the seed's `{emoji, count}` reactions into per-user reaction rows (the first N senders in that conversation react).
> - Login is a demo: `login.html` checks one credential from the gitignored `demo-config.local.js`, and stores `{email, displayName}` under `lime-demo-session`.
> - The app ignores all of this. `CURRENT_USER_ID = 'teacher-002'` is hard-coded in `data.js`, `participants` sits on the conversation, reactions are counts plus a local "did I react" `Set`, and everything is in-memory.
>
> **Production-ready principles** (these apply to 24a, 24b and every later lifecycle brief):
> 1. **Match the Supabase schema** in the local model: normalized tables, the same names, derived views.
> 2. **Per-user state lives on the membership, not the conversation.** Starred, archived and last-read belong to `conversation_members` (per user). Otherwise starring would star a chat for everyone. Shared state (name, deletion) lives on `conversations`.
> 3. **Reactions are rows** (`message_id`, `user_id`, `emoji`); counts and "did I react" are derived.
> 4. **One data seam:** the UI never touches storage. Reads are synchronous from an in-memory cache. **Writes are async** (they return Promises) through a store, which updates the cache optimistically, persists through an **adapter**, and emits change events. Today's adapter is `LocalAdapter` (`localStorage`); later a `SupabaseAdapter` implements the same interface, and realtime pushes into the same cache and events.
> 5. **An auth seam:** `getCurrentUserId()` resolves the session to a profile id. There are no hard-coded ids in UI code.
> 6. **New ids are `crypto.randomUUID()`;** seed ids keep their text form (Postgres `text` ids). Timestamps are ISO 8601 UTC.
> 7. **Permissions are written down** for when RLS exists: owner vs member for rename and delete, and communities are public-read. The UI checks through a `can(action, conversation)` helper, so the rules live in one place.
> 8. **UI preferences** (panel widths, collapsed sections, theme) stay in their own `localStorage` keys. They're device preferences, not data.

### LIME-24a → `tend` (after LIME-19b-fix): the data contract (docs only, no code)

**Goal:** a written, reviewable contract that the local implementation (24b) and a future Supabase implementation both follow.

**Capability assumptions:** can create files and commit. There's no code to run.

**Scope:**
- **May touch:** create `docs/data-model.md` and `docs/schema.sql`; `TEND.md`.
- **May not touch:** app code or the seed data.

**Contents:**
1. **`docs/schema.sql`:** Postgres DDL for Supabase.
   - The 5 tables from `seed.ts`, with types, primary and foreign keys, and `on delete cascade` where appropriate. Ids are `text`, since the seed uses readable ids and new ones are UUID strings.
   - **Added columns:**
     - `conversations.deleted_at timestamptz null`, for soft deletes (owner only)
     - `conversation_members.starred boolean not null default false`
     - `conversation_members.archived_at timestamptz null`
     - `conversation_members.last_read_at timestamptz null`
     - `profiles.email` must be unique
     - `message_reactions` is unique on (`message_id`, `user_id`, `emoji`)
   - Indexes for `messages (conversation_id, created_at)` and `messages (reply_to)`.
   - **An RLS section**, as commented, not-yet-enabled policies:
     - members read their conversations and messages;
     - members insert messages into conversations they belong to;
     - only the `owner` renames or soft-deletes;
     - each user updates only their own membership row (star, archive, read);
     - communities are readable by any authenticated user and joinable.
   - A header comment: "Draft. Aligns with seed-data/seed.ts."
2. **`docs/data-model.md`:**
   - the principles above;
   - an entity diagram, as a text list;
   - how each current UI concept maps to tables:
     - title = `name`, or derived from members
     - a DM = type `direct` with 2 members
     - starred and archived = your membership row
     - reply = `reply_to`
     - reaction count = count of rows
   - **The store API** (the adapter contract): the function names, arguments, return types (Promises for writes) and the event names 24b will implement, listed in item 3;
   - the auth seam: `getCurrentUserId()`, how the demo session maps email → profile, and how Supabase auth replaces it;
   - **the switch checklist:** add a `SupabaseAdapter` implementing the contract, add config (URL and anon key via a gitignored `*.local.js`, like `demo-config.local.js`), enable RLS, run `seed.ts` (updated for the new columns), and flip `LIME_BACKEND` from `'local'` to `'supabase'`.
3. **The contract to write down (plot's proposal; tend copies it faithfully and flags anything inconsistent with the schema):**
   - **Reads (sync, from the cache):**
     - `getProfile(id)`, `getCurrentUserId()`, `getCurrentUser()`
     - `listConversations({ types, includeArchived })`, `getConversation(id)`, `getMembers(conversationId)`, `getMyMembership(conversationId)`
     - `listMessages(conversationId, { threadOnly })`, `listReplies(messageId)`, `getReactions(messageId)` returning `[{ emoji, count, mine }]`
     - `getConversationTitle(conversation)`, `getLatestActivity(conversationId)`, `can(action, conversation)`
   - **Writes (async; each returns a Promise of the record):**
     - `sendMessage(conversationId, { content, type, metadata, replyTo })`
     - `toggleReaction(messageId, emoji)`
     - `createConversation({ type, memberIds, name, description })`
     - `renameConversation(id, name)`
     - `setStarred(id, bool)`, `setArchived(id, bool)`
     - `deleteConversation(id)` (a soft delete)
     - `markRead(conversationId)`
   - **Events** (on `document`): `lime:conversations-changed`, `lime:messages-changed`, `lime:reactions-changed`, each with `detail: { conversationId, messageId?, kind }`.
   - **Lifecycle:** `await LimeStore.init()` before the first render; `LimeStore.reset()` for the local adapter only.

**Gate:** the user skims `docs/data-model.md`, mainly the principles and the switch checklist, to confirm it matches their intent. Plot also reviews the contract before 24b is sent.

**Record:** add a `## LIME-24a` entry to `TEND.md`. Commit: `docs: data model and Supabase schema draft`, trailer `Brief: LIME-24a`, plus the attribution trailer.

---

### LIME-24a-fix → `tend` (before LIME-24b): plot's review of the data contract (docs only)

**Plot reviewed `9e5506f` (2026-09-27).** It's solid overall: principles 1–8 are captured faithfully, the switch checklist is clear, and both flagged gaps are real and well reasoned. **Five issues need fixing before 24b builds on it**, the first two because they're exactly what "multiple email logins" depends on.

**Scope:**
- **May touch:** `docs/schema.sql`, `docs/data-model.md`, and `TEND.md`.
- **May not touch:** app code or the seed data. `seed.ts` is fixed in 24b.

**The changes:**
1. **Link profiles to real logins.** `profiles.id` is readable text (`teacher-002`), but Supabase's `auth.uid()` is a **uuid**, so every drafted policy comparing `user_id = auth.uid()` would never match: it's a type mismatch, and the ids differ anyway.
   - Add `profiles.auth_user_id uuid unique references auth.users(id)` (nullable; seed profiles get linked when their accounts are created).
   - Add a SQL helper `current_profile_id()`, `returns text`, `stable security definer`, that selects `id` from `profiles` where `auth_user_id = auth.uid()`.
   - Rewrite **every** policy to use `current_profile_id()` instead of `auth.uid()`.
   - In `data-model.md`'s auth seam: on Supabase, `getCurrentUserId()` = the profile whose `auth_user_id` matches the session. **Onboarding:** a new signup gets a profile row, via trigger or on first login; a seed teacher is linked by matching email on first login.
   - Add both to the switch checklist.
2. **Avoid the policy recursion trap.** Policies on `conversation_members` that query `conversation_members` recurse infinitely in Postgres/Supabase (a well-known RLS pitfall).
   - Add a `security definer` helper `is_member(conv_id text) returns boolean` and `is_owner(conv_id text)`, and use them in all policies.
   - **Complete the policy set:**
     - `conversation_members` **select** for members of the same conversation, so a user can see who's in their chats;
     - **insert** on `conversations` and `conversation_members` for creating a conversation (the creator becomes owner; the creator may add members);
     - `message_reactions` select (members) and insert/delete of your **own** rows only;
     - `messages` update/delete of your own rows (not used yet, but define intent);
     - community **messages** readable by any authenticated user (today only the community's conversation row is public);
     - **filter `deleted_at is null`** in the select policies.
3. **Make DMs unique between two people.** Nothing stops two direct conversations between the same pair, and the contract's `createConversation` promises to return the existing DM.
   - Add `conversations.dm_key text` = the two member ids sorted and joined with `:`, set only for `type = 'direct'`, with `create unique index … on conversations (dm_key) where dm_key is not null`.
   - Document that the store computes it.
4. **Fix the status values.** The seed uses `online` / `offline` / `busy` (the schema matches), but the UI shows *Active / Away / Busy / DND* via `presenceFor`.
   - Document the mapping in the mapping table. The schema is fine; just note that "away" and "dnd" have no stored value yet: they're a UI fallback, and a future presence feature decides.
5. **Fix the reactor algorithm.** Replace the "dedupe the senders" suggestion with plot's decision:
   - A reaction's reactors are **the conversation's distinct members** (participant order), sliced to `min(count, member count)`.
   - Reason: a reaction count can't exceed the number of people who can react. The only seed reaction today is `msg-006` 😍×5 in a **2-person DM**, so it becomes 😍×2, one of them the current user's ("mine").
   - `seed.ts` and the local adapter both use this. `seed.ts` is changed in 24b.
   - Update both the `schema.sql` comment and the known-gaps entry.

**Verification:** re-read both docs for internal consistency. Every policy uses the helpers, and every table has its select policy defined. Report the final policy list, one line each.

**Gate:** plot re-reviews. The user needs nothing here beyond the note about reaction counts (😍5 → 😍2 in Jean's chat, which becomes visible in 24b).

**Record:** add a `## LIME-24a-fix` entry to `TEND.md`. Commit: `docs: auth-linked profiles, recursion-safe RLS, DM uniqueness, reactor rule`, trailer `Brief: LIME-24a-fix`, plus the attribution trailer.

---

### LIME-24b → `tend` (after LIME-24a-fix): the local implementation of the contract

**Goal:** the app runs entirely on the contract from 24a, through a `LocalAdapter` persisted to `localStorage`.
- Behaviour is **identical** to now, except that changes survive reload, there's "Reset demo data", and list clicks are delegated.
- The current user comes from the session.
- No UI code reads the seed arrays or `localStorage` data directly.

**Capability assumptions:** can edit files, run commands and commit. Load the real app in jsdom (zero errors). Use headless Chrome with a throwaway `--user-data-dir` in the scratchpad for the reload checks.

**Scope:**
- **May touch:** `public/js/data.js` (it becomes the store plus the local adapter, split into `store.js` and `local-adapter.js` if that's clearer; add them to `index.html`'s script list in order), `public/js/app.js` (switch every data call to the contract, delegate the two load-time bindings ~1406/~1471, add reset), `public/index.html` (script tags and the "Reset demo data" menu item), `docs/data-model.md` (only to record deviations), and `TEND.md`.
- **May not touch:** the seed JSON or its embedded copy, CSS, `login.html` logic (read `lime-demo-session` only), or visible behaviour.

**Plot's re-review of 24a-fix (`30563a8`): passed**, with one gap to close in this brief.
- `messages_insert_member` (`docs/schema.sql` ~273) checks membership but **not the sender**, so a member could insert a message as someone else. Change it to `with check (is_member(conversation_id) and sender_id = current_profile_id())`. Add `docs/schema.sql` to this brief's scope for that one line only.
- The store's local `sendMessage` must likewise always set `sender_id = getCurrentUserId()`, never take it from the caller.

**Phase 1 — Survey:** list every place in `app.js` that calls a `data.js` function or reads `CURRENT_USER_ID`, `messages`, `conversations`, `teachers`, `userReactedKeys` or `reply_count`. That's the migration checklist; report its size. **If migrating everything in one commit becomes unwieldy (over ~40 call sites or so), stop and propose a split to the user** (e.g. reads first, then writes).

**Phase 2 — The change:**
1. **Normalize at load (`LocalAdapter`):**
   - Build `profiles`, `conversations` (with `dm_key` for DMs, per 24a-fix), `conversation_members` (from `participants`, `role = owner` if `created_by`, all flags default), `messages` and `message_reactions` from the embedded seed.
   - Reactions come from `{emoji, count}` using **the corrected reactor rule from 24a-fix**: the conversation's distinct members in participant order, sliced to `min(count, member count)`.
   - **Also apply the same rule to `seed-data/seed.ts`** (the only change allowed there; add `seed-data/seed.ts` to scope), so local and database seeds match.
   - If a valid snapshot (`lime-state-v1`, with the `seedVersion` fingerprint check) exists, load it instead.
2. **The store** implements the contract as written in `docs/data-model.md`: sync reads from the cache; async writes that update the cache, persist through the adapter (debounced ~100ms is fine), then emit the documented events.
3. **Auth seam:** `getCurrentUserId()` reads `lime-demo-session`'s email and matches it to `profiles.email`. With no match or no session, fall back to `teacher-002` and log once. Remove the `CURRENT_USER_ID` constant from UI use.
4. **Reactions:**
   - Render from `getReactions(messageId)` → `[{emoji, count, mine}]`; `mine` drives the neutral "active" chip.
   - Delete `userReactedKeys`.
   - **Seed side effect (expected; the user has been told):** `msg-006`'s 😍 goes from 5 to **2** (a 2-person DM can't have 5 reactors), and it shows as "mine" (neutral active chip). Report it.
5. **Async writes in the UI:** `handleSend`, `submitReply` and the reaction handlers `await` (or `.then`) the store call, and render from the returned record or the event.
   - Keep the UI instant: optimistic cache updates happen synchronously before the Promise resolves.
   - Wrap the first render in `LimeStore.init().then(...)`.
   - **Keep the script-order and TDZ lessons in mind** (LIME-18-fix, LIME-20). Load-order crashes have happened twice.
6. **Delegated clicks:** replace the two load-time `.lime-contact, .lime-recent__item` `forEach` bindings with delegated `document` listeners. Behaviour stays identical.
7. **The list** subscribes to `lime:conversations-changed` and `lime:messages-changed` (re-render or re-sort; rows can now be created at any time). Replace 19b's `lime:activity` with `lime:messages-changed`, and remove `lime:activity`.
8. **Reset:** add "Reset demo data" to the profile menu, above Sign Out. A native `confirm()` for now (LIME-26 brings the real dialog), then `LimeStore.reset()` and reload.
9. **`can(action, conversation)`:** implement it per the doc (owner can rename and delete; DMs can't be renamed). Nothing in the UI uses it yet; LIME-25/26 will.

**Phase 3 — Verification:**
1. `node --check` on every JS file, and the real app in jsdom (zero errors).
2. **The migration grep:** `app.js` no longer references `CURRENT_USER_ID`, `userReactedKeys`, the raw seed arrays or `window.LIME_SEED_DATA`. Report the grep results.
3. **In jsdom:** every read function returns data consistent with the pre-change UI (the same list order and the same message counts per conversation). Each write resolves and emits its event.
4. **Headless Chrome, a throwaway profile:**
   - **Run 1:** send a message, reply, react and star (via a temporary script).
   - **Run 2:** all persisted.
   - **Reset:** back to the seed.
   - **Session:** with `lime-demo-session` set to Jean's email, the app renders as Jean. Her messages are on the "sent" side, and the list shows her conversations. Report 3 facts.
   - Remove the diagnostic script afterwards; `git diff public/index.html` shows only the intended changes.
5. **Visually identical** to before at 1567px (a screenshot comparison or key rects), apart from reaction chips that are now "mine" per item 4.

**Gate:** in Firefox:
- **Everything works as before.**
- **Remembering:** send, reply and react, then reload. It's all still there.
- **Reset:** Profile menu → "Reset demo data" brings back the original.
- Tend reports which reaction chips now show as "yours" from the seed. Confirm that's fine.

**Record:** add a `## LIME-24b` entry to `TEND.md`, listing any deviations from the contract (also recorded in `docs/data-model.md`). Commit: `feat: store + local adapter on the data contract, persisted, session-based current user`, trailer `Brief: LIME-24b`, plus the attribution trailer.

---

### LIME-19b-fix → `tend`: drop the list member count; fix the group header's avatars

**The user's check of LIME-19b (`0b5b3c7`, 2026-09-27):**
1. "The number count for the group next to the names in the messages [list] is confusing and can be mistaken for the number of recent comments. Remove [it from] the list and leave it in the chat's top right."
2. The header ("4 members" / "10 members") is a good place for the count, "however I can't see the avatars, let's give them more space."
3. "The hover is broken, and the avatar order should change: it should be all the avatars and +# at the right end. Also the spacing between a larger group and a small group in this component is inconsistent."

**Root causes (plot read `app.js` ~483–509 and `lime.css` ~320–340, ~973–996 and ~1156–1174, plus Seed's `avatar.css` ~142–161):**
- `.lime-topbar__avatars` is fixed at **36px wide** with `margin-left: -20px` on each 28px avatar. That was sized for a DM's 2 avatars. A group's 5 or 6 avatars show only about 8px each, so the initials are hidden, and the row **overflows its box to the left**.
- **The hover is broken** because `.lime-avatar-trigger`'s hover background only covers its box, and the avatars spill outside it.
- **Seed's `.seed-avatar-group` is `flex-direction: row-reverse`,** so the first DOM child renders at the *right*. `conversationHeaderAvatarsHtml` appends "+N" last, so it lands on the **left**.
- **The spacing differs between group sizes** because `.lime-topbar__member-count` uses a `margin-left: 20px` hack to clear the overflow. The overflow width depends on the avatar count, so the gap changes.

**Goal:**
- The list rows show no member count.
- In the thread header, a group shows its avatars left to right (most recent speaker first), each clearly readable, with "+N" at the **right** end, then "N members".
- The spacing is identical for small and large groups.
- The hover highlight covers the whole avatar row and the label.
- The DM header is unchanged.

**Capability assumptions:** can edit files, run commands and commit. Load the real app in jsdom (zero errors). **Measure with headless Chrome** (see Patterns).

**Scope:**
- **May touch:** `conversationHeaderAvatarsHtml` and the row builder's count in `public/js/app.js`; header avatar, member-count and trigger rules plus the `.lime-contact__count` rule in `public/css/lime.css`; and `TEND.md`.
- **May not touch:** the list's avatar cluster, the DM header's look, Seed files, or the mobile contacts-view rule at ~3328 (except to keep it working).

**Phase 2 — The change:**
1. **List:** remove the member count from the row builder (app.js ~467) and delete the `.lime-contact__count` rule (~1702). Update any comment that mentions it.
2. **Group header markup:** give the group's avatar span an extra `lime-topbar__avatars--group` class. Build its children **in reverse DOM order**, so Seed's `row-reverse` shows them left to right: `+N` tile first (if any), then the shown avatars from last to first. The result reads, left to right: most recent speaker … 5th speaker, then +N. Keep the `title` with every name. The member-count label stays a sibling after the group.
3. **Group header CSS** (new `--group` rules; the DM rules stay as they are):
   - `.lime-topbar__avatars--group`: `width: auto; margin-right: 0;`
   - `.lime-topbar__avatars--group .seed-avatar`: 28px, with `margin-left: -8px` (Seed's standard overlap, so about 20px of each avatar shows). The `:last-child` (visually leftmost) keeps `margin-left: 0`.
   - **Rings:** the avatar border colour is `var(--lime-cluster-ring, var(--soil-bg-canvas))`. `.lime-avatar-trigger:hover` sets `--lime-cluster-ring: var(--calm-bg-subtle-hover)`, so the rings match the hover pill.
   - `.lime-topbar__member-count`: remove the 20px margin hack. The trigger's `gap` (`--seed-space-2`) provides the spacing. Update the trigger's comment, which describes the old collision workaround.
   - `.lime-avatar-trigger`: make sure its padding fully contains the avatars and the label (a small horizontal padding, e.g. `--seed-space-1` vertical and `--seed-space-2` horizontal). Keep the negative margin only if it's still needed to align with the header edge, and measure that.

**Phase 3 — Verification:**
1. Run `node --check`, the brace count, and the real app in jsdom (zero errors). List rows contain no `.lime-contact__count`.
2. **Headless Chrome, 1567px.** Open conv-011 (10 members), then conv-006 (4 members), then Jean's DM. Report:
   - each avatar's visible width (≥ 18px for all but the frontmost);
   - the left-to-right order of `data-name` (must be the most-recent-speaker order) with the "+N" tile rightmost;
   - the gap between the last avatar or "+N" and "N members": **the same for conv-011 and conv-006** (±1px);
   - the trigger's rect, which fully contains every avatar and the label;
   - that the DM header's rects are unchanged from before this fix.
3. **At 767px:** the header fits on one line without overlapping the breadcrumb or the "…" button.

**Gate:** the user checks in Firefox:
- **List:** no numbers after group names.
- **Big group:** open "PS 113 Staff Room". Five readable faces, then "+4" at the right end, then "10 members".
- **Small group:** open "PS 113 7th Grade Team". The same spacing before "4 members".
- **Hover:** the grey highlight covers the whole avatar-and-label area.
- **DMs:** look the same as before.

**Record:** add a `## LIME-19b-fix` entry to `TEND.md`. Commit: `fix: group header avatars readable and ordered, list member count removed`, trailer `Brief: LIME-19b-fix`, plus the attribution trailer.

> **Shared context for LIME-19b and 19c: the merged "Messages" list.**
>
> **User decisions (2026-09-27):**
> - The tabs become **"Messages"** (1:1 and group chats together) and **"Communities"**. The "Group Chat" tab goes away.
> - Earlier decisions still stand: chats with the newest activity move to the top, Starred becomes real (data-driven), and the fake unread "2" badges are removed.
> - The "conversations I'm in" versus "spaces I've joined" split was presented. The user went straight to naming the tabs, which plot reads as acceptance.
>
> **Survey (plot, read-only, 2026-09-27).** Seed data for the current user (teacher-002):
> - **Messages = 6 conversations:**
>   - DMs: conv-001 (Jean, 9 messages, including 3 replies), conv-004 (Alexi, 5), conv-005 (Kai, **0 messages**)
>   - groups: conv-006 "PS 113 7th Grade Team" (5), conv-007 "Math Teachers NYC" (5), conv-010 "Jean, Mary, Jimin & Me" (4)
> - Communities: 3 of 9 include the current user. They're **out of scope here.**
>
> **The code today:**
> - The list IIFE (`app.js` ~220–470) renders only direct conversations into `#contacts-list`, via `otherParticipant()`.
> - `renderThread(conversationId, teacher)` uses **one `teacher` as the sender of every non-me message.** That's wrong for groups.
> - `selectConversation` sets `#crumb-thread` to the teacher's name.
> - The header avatars (`#open-profile-avatars`, `index.html` ~152) are static "Shem R" + "Jean Chung".
> - Tabs (`index.html` ~185–187): `data-scope="teachers|groups|communities"`. The segmented pill width is `calc((100% - 6px) / 3)` (`lime.css` ~1437).
> - The Group Chat panel (~335) and Community panel (~393) are **static mockups** with names that aren't in the seed data. The Recent row and Starred section are static too.
> - **Listener constraint:** `app.js` binds click listeners **once at load** to every `.lime-contact` (~1245, the recent highlight; ~1310, mobile `setView('thread')`). Rows must be **created once at init** (the list IIFE runs earlier in the file), then **updated in place and reordered by moving the existing nodes. Never re-created.**
> - The contact-preview truncation pass (~475) only wraps bare text nodes. JS-built rows already use `.lime-contact__preview-text`, so it isn't needed for them.
>
> **Capability assumptions for both briefs:** can edit files, run commands and commit. Load the real app in jsdom (zero errors). Use headless Chrome for visual and position checks (see Patterns). The user previews at `file:///Users/shem/Sites/lime/public/index.html`.

### LIME-19b → `tend`: "Messages" tab: DMs and groups in one live, recency-sorted list

**Goal:**
- The first tab, "Messages", lists all of the user's DM and group conversations (6 in the seed, plus the new 10-person conv-011) in one "All" section, newest activity first. Each row shows its latest message or reply, and updates and reorders immediately when you send a message or reply.
- Opening a group shows the right sender on every message, the group's name in the breadcrumb, and its members in the header.
- Two tabs: Messages and Communities.

**Scope:**
- **May touch:** `public/js/data.js`; `public/js/app.js` (the list IIFE, `renderThread`, `selectConversation`, `handleSend`, `submitReply`, the scope/tab code if it hard-codes scope names); `public/index.html` (tabs, the Messages panel's "All" section heading, removing the Group Chat panel, the header avatar group's initial markup, the breadcrumb's initial text); `public/css/lime.css` (segmented pill width, a new group avatar mark); and `TEND.md`.
- **May not touch:** the Starred section and Recent row (still static; 19c handles Starred), the Communities panel (still static), the profile panel's contents, the reply panel, or the seed data, **except adding conv-011 as specified.** (`seed-data/*.json` and `public/js/seed-data.js` may be touched for that alone.)

**Phase 1 — Survey:**
1. Confirm the facts above, especially the listener constraint's line order, and every place that names the scopes `teachers`/`groups` (the JS scope filter ~1190–1225, CSS, `index.html`).
2. Report how the profile panel behaves when the header avatars are clicked. Plot expects a static Jean mockup. **Don't change it.** For groups, just note in `TEND.md` that the profile panel isn't group-aware yet.
3. If anything differs, stop and ask **the user**.

**Phase 2 — The change:**
1. **`data.js`:**
   - `getMessageConversations()`: the current user's conversations of type `direct` or `group`.
   - `getConversationTitle(conversation)`:
     - a group's `name`;
     - for a DM, the other participant's `display_name`;
     - for an unnamed group, the other participants' first names joined as "Jean, Mary & Jimin".
   - `getLatestActivity(conversationId)`: the last item of `getMessagesByConversation` (which **includes** replies), or `null`.
2. **One row builder, `conversationRowHtml(conversation)`:**
   - **DM:** the current avatar-with-presence markup.
   - **Group:** a group avatar **cluster** (see "Group avatar cluster" below) at list size, plus the group's member count after the title (see below).
   - **Name:** `getConversationTitle`.
   - **Preview:** `previewFor(latest)`. For **groups** only, prefix it with the sender's short first name, or "You", plus ": ". Otherwise "No messages yet".
   - **Time:** `formatTime(latest.created_at)`, or empty.
   - **Attributes:** `data-conversation-id`, and `data-search-text` = the title plus every participant's display name, lowercase.
   - **Group avatar cluster, a system that scales to large groups** (user direction, 2026-09-27, with Apple Messages and KakaoTalk as references; "3 is not the max… large group chats… systemize"): a group gets **one avatar made of its members' circles**, not one person's avatar. Build it as **one reusable component** (`<span class="lime-avatar-cluster lime-avatar-cluster--lg" data-count="…">` containing `<span class="seed-avatar lime-avatar lime-avatar-cluster__member" data-name="…">` elements).
     - **Members shown:** the other participants (never the current user), most recent speaker first, then participant order.
     - **Layout by the number of *other* members, in a 40px square** (matching `.lime-avatar-frame--lg`, so group and DM rows align):
       - **2:** two 26px circles on a diagonal (`0,0` and `14,14`).
       - **3:** a triangle of 22px circles (top-centre `9,0`; bottom `0,18` and `18,18`).
       - **4 or more:** a 2×2 grid of 20px circles (KakaoTalk style), overlapping by about 1px so the rings merge. With exactly 4, all four are faces. **With more than 4, the 4th tile is a neutral "+N" tile** (N = others − 3): `--calm-bg-normal-default` fill, `--calm-text-normal-default` text, 9px medium. So a 10-person group (9 others) shows 3 faces and "+6".
       - Initials 9–10px medium. **The list cluster caps at 4 tiles on purpose.** 5 or more circles in 40px aren't legible. The larger "5–7" preview lives in the thread header (below).
     - **Ring:** each circle has a 2px ring, `box-shadow: 0 0 0 2px var(--lime-cluster-ring, var(--soil-bg-canvas))`. Set `--lime-cluster-ring` on hovered and active rows to that row's background.
     - Paint every member with `paintAvatar`.
     - **Tune offsets by measuring in headless Chrome,** and report the final values for each layout.
   - **Thread header for a group** (#open-profile-avatars, user direction: "maybe 5–7 max we show, then we tell the total number"):
     - An overlapping row of **up to 5** member avatars (a Seed `seed-avatar-group` at `seed-avatar--sm`, as the header uses today), others first by most recent speaker.
     - If there are more, a neutral "+N" circle in the same style as the list's +N tile.
     - Then a muted `N members` label (the total, including the current user), `--soil-text-muted`, `--seed-text-xs`.
     - **5, not 7:** the header shares its row with the breadcrumb and the "…" button, and has to fit at mobile width. Flag this at the gate; the user may want more.
     - The `title` attribute lists every member's name.
     - DMs keep today's header exactly.
   - **Seed data example of a large group:** the seed has no group bigger than 5. Add **one** 10-member group for the current user, so the system is exercised:
     - `conv-011`, "PS 113 Staff Room", `type: 'group'`
     - participants teacher-002 (the current user) plus teacher-001, 010, 013, 014, 015, 016, 018, 022, 024
     - 5–6 plausible short staff-room messages from at least 4 different members, with timestamps within the seed's date range; make the newest one of the most recent in the whole seed, so it sorts near the top.
     - **Add it to both `seed-data/conversations.json` and `seed-data/messages.json` (the source of truth) and the embedded copy in `public/js/seed-data.js`.** Keep them in sync, and match the existing record shapes exactly (read a few records first).
     - This is the only seed data change allowed in this brief.
   - **Member count:** for groups, show the total member count, including the current user, after the title as `<span class="lime-contact__count">N</span>` in `--soil-text-muted`, regular weight, 4px gap, the way KakaoTalk shows "4". DMs don't get a count.
3. **Render and sort:**
   - At init, render every Messages conversation into `#contacts-list`: newest `latest.created_at` first, no-activity rows last in title order.
   - Paint avatars (the later one-time sweep also covers this; confirm).
   - The default selection on load is the top row.
4. **Live updates:**
   - After `sendMessage` in `handleSend` and after `sendReply` in `submitReply`, dispatch `document.dispatchEvent(new CustomEvent('lime:activity', { detail: { conversationId } }))`. This decouples the replies IIFE from the list IIFE.
   - The list IIFE listens for it, updates that row's preview and time **in place**, and re-sorts by **moving existing nodes** (`appendChild` in sorted order). It never re-creates rows.
5. **Opening a conversation:**
   - `selectConversation(conversation)` takes just the conversation. It sets `#crumb-thread` to the title and marks the active row.
   - It rebuilds `#open-profile-avatars`'s contents. For a **DM**, keep today's avatar group (the current user plus the other person). For a **group**, use the group header treatment above (up to 5 avatars, then +N, then "N members").
   - `renderThread(conversationId)` resolves each message's sender with `getTeacherById(m.sender_id)`, falling back to a placeholder name if missing. It no longer takes a single `teacher`.
6. **Tabs and markup:**
   - Tabs become `data-scope="messages"` "Messages" and `data-scope="communities"` "Communities".
   - The first panel's `data-scope-panel` becomes `messages`.
   - Delete the Group Chat tab and its static panel (~335–392).
   - Rename the "All Teachers" heading to "All" (keep its `data-section-id` unless something depends on the text).
   - The breadcrumb's initial text becomes "Messages".
   - Update any JS or CSS that names the old scopes.
   - Segmented pill width: `calc((100% - 6px) / 2)`.
7. **Comments:** a short header comment on the list IIFE describing the merged, conversation-based list and the listener constraint.

**Phase 3 — Verification:**
1. `node --check` passes on both JS files, the brace counts in `lime.css` are equal, and the real app loads in jsdom with zero errors.
2. **In jsdom:**
   - The "All" list has 7 rows (6 existing plus conv-011), sorted by latest activity; Kai (no messages) is last.
   - Group rows show "Name: preview".
   - Opening "PS 113 7th Grade Team" renders messages whose sender names match each message's `sender_id` (report 3 examples), and the breadcrumb shows the group name.
   - After sending in Alexi's DM, Alexi's row moves to the top with the new text. After replying in Jean's thread, Jean's row shows the reply.
   - **Listener check:** at mobile width, clicking a row still sets `data-mobile-view="thread"`.
3. **Headless Chrome:**
   - The two tabs split the control evenly, with the pill under the active tab.
   - Group clusters fit inside a 40px square, lined up with the DM avatars. Report the rects for each layout: 3-member groups (triangle), and conv-011 (2×2 with "+6"). With conv-011 open, the header shows 5 avatars, "+4" (the 9 other members minus the 5 shown) and "10 members", and fits on one line at 1567px and at 767px.
   - No row overflows its list.
4. `grep -rn 'data-scope="groups"\|Group Chat' public/` returns nothing.

**Gate:** the user checks in Firefox:
- **Tabs:** just "Messages" and "Communities".
- **One list:** Messages shows people and groups together, newest first. Groups show a small cluster of member avatars (like Apple Messages or KakaoTalk): a triangle for small groups, and a 2×2 grid with "+N" for big ones like the new 10-person "PS 113 Staff Room". A member count follows the name. **Open the big group:** the header shows 5 faces, "+4" and "10 members". Ask whether 5 faces is the right cap.
- **Groups:** open one. Each message shows who actually sent it, and the header shows the group name.
- **Live:** send a message or reply, and the list updates and reorders straight away.
- **Still placeholders:** Starred, the Recent row and Communities are unchanged for now. Starred is next (19c).

**Record:** add a `## LIME-19b` entry to `TEND.md`. Commit: `feat: merged Messages list (DMs + groups), live and recency-sorted`, trailer `Brief: LIME-19b`, plus the attribution trailer.

---

### LIME-19c → `tend` (after LIME-19b): a real Starred section

**Goal:** Starred shows real, live conversation rows (DMs or groups), identical to their rows in "All", and kept in sync when you send or reply. There are no fake badges.

**Plot's choice, flagged at the gate:** stars now belong to *conversations*, not people. Starring UI (adding or removing stars) is out of scope. The starting set is `STARRED_CONVERSATION_IDS = ['conv-001', 'conv-010']`: Jean's DM, and "Jean, Mary, Jimin & Me", which covers Mary. The old static Starred list had Valene, but the current user has no conversation with her, so she drops out. The user can name a different set at the gate.

**Scope:**
- **May touch:** `public/index.html` (replace the static Starred `<li>`s with `<ul class="lime-contact-list" id="starred-list"></ul>`), `public/js/app.js` (the list IIFE only), and `TEND.md`.
- **May not touch:** the Recent row, Communities, or star/unstar UI.

**The change:**
- Render Starred rows at init using 19b's `conversationRowHtml`, into `#starred-list`, sorted by the same rule. This is before the load-time listeners bind, the same constraint as 19b.
- The `lime:activity` handler updates and re-sorts **every** row for that conversation, in both lists.
- The active state marks every row for that conversation in both lists.
- Remove the static rows' fake "2" badges and chevron (the markup is being replaced anyway).

**Verification:**
- The real app loads in jsdom with zero errors. Starred has 2 rows showing real previews.
- Sending in Jean's DM updates Jean's row in **both** Starred and All, and both move to the top of their sections.
- Clicking a Starred row opens the conversation and highlights both copies.
- At mobile width, tapping a Starred row goes to the thread view.

**Gate:** in Firefox, Starred shows Jean and "Jean, Mary, Jimin & Me" with real previews and times, and updates when you send. Ask the user whether that's the starred set they want.

**Record:** add a `## LIME-19c` entry to `TEND.md`. Commit: `feat: data-driven Starred section`, trailer `Brief: LIME-19c`, plus the attribution trailer.

---

### LIME-23 → `tend`: a legible "Soon" badge (neutral grey pill)

**User QA (2026-09-27):** the Jam row's "Soon" badge "is not clear when the menu is default". It only reads on hover. The user asked for legible, accessible, and in keeping with Lime's look, and **chose a neutral grey pill** over a lime outline.

**Root cause:** `.lime-badge--soon` (lime.css ~583) uses `--calm-bg-subtle-default` (#FDF9F6, nearly the canvas colour #F9F8F4) with `--soil-text-disabled` (#C0BAB0), about **1.8:1** contrast. That's both invisible and semantically wrong: Jam isn't disabled, "Soon" is a status.

**The change** (`lime.css` `.lime-badge--soon` only; don't touch its collapsed-rail and mobile display rules):
- `background: var(--calm-bg-normal-default)` (#E8E4DB, the **same fill as the nav Search field** above it, so it reads as part of the same family)
- `color: var(--calm-text-normal-default)` (#504840). Plot computes about **7.1:1** on #E8E4DB, AA for small text. The pill carries its own fill, so the contrast is the same at rest and on the lime hover row.
- `font-weight: var(--seed-weight-medium)`
- Keep the size, padding, radius and margin.
- Replace the comment above the rule (~567–582) with a short one: "Status tag, not a disabled state: neutral fill matching the nav Search field; ~7:1 text contrast (LIME-23)."

**Scope:**
- **May touch:** that one rule and its comment, and `TEND.md`.
- **May not touch:** the notification count badge, nav hover colours, and the rules that hide the badge in the collapsed rail.

**Verification:**
- The brace counts in `lime.css` are equal.
- Headless Chrome (see Patterns): the computed background is `rgb(232, 228, 219)` and the text colour `rgb(80, 72, 64)`. Report the contrast ratio (expect ≥ 7:1).
- The badge is still hidden in the collapsed desktop rail and still visible in the mobile drawer.

**Gate:** in Firefox, the "Soon" pill next to Jam is clearly readable at rest, looks like a quiet grey tag in the same family as the Search field, and still reads on hover.

**Record:** add a `## LIME-23` entry to `TEND.md`. Commit: `fix: legible neutral "Soon" badge`, trailer `Brief: LIME-23`, plus the attribution trailer.

### LIME-18-fix7 → `tend`: correct fix5's wrong premise; bring the main composer down to the reply composer's level

**What happened in fix5 (`cb6b4bc`):**
- It assumed `#right-panel` has Seed's 16px padding and cancelled it with `margin-right` and `margin-bottom` of `-16px` on `.lime-replies-panel__composer`.
- **That premise is false.** `lime.css` ~111–114 sets `.seed-layout__left, .seed-layout__right { padding: 0; }`, which comes after Seed's rule with the same specificity, so the panel has **no** padding.
- Result: the reply composer was pushed 16px past the panel's right edge (clipped, so it reads as flush) and 16px down.
- fix5 also removed `position: relative` from `.lime-replies-panel__composer`. Harmless, since `#replies-composer` is that element itself (`index.html` ~601) and isn't absolutely positioned.

**The user's direction (2026-09-27):**
- **Keep the reply composer at its current, lower height.** They like it better.
- **Move the main (center) composer down to match it.**
- **Restore the reply composer's right gap,** equal to the toggle icon's distance from the window edge, as fix5 intended.

**Capability assumptions:** can edit files, run commands and commit. **Measure; don't compute. Two rounds of computed pixel fixes have been wrong.** Chrome is installed at `/Applications/Google Chrome.app`, and the extension isn't needed:
- Add a **temporary** diagnostic `<script>` at the end of `index.html` that, after load (with the thread panel open via the same code path the Reply button uses, e.g. `openReplies('msg-003')` if it's reachable, or by clicking the button), writes a JSON of the rects below into `document.body.dataset.measure`.
- Run `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --allow-file-access-from-files --window-size=1567,905 --virtual-time-budget=3000 --dump-dom file:///Users/shem/Sites/lime/public/index.html` and parse the value out.
- **Remove the script afterwards**, and confirm `git diff public/index.html` is empty.
- If headless Chrome can't be made to work, stop and tell the user before changing any values.

**Measurements (viewport px, 1567×905):**
- A: the main `.lime-composer__box` bottom; B: the reply `.lime-composer__box` (inside `#replies-composer`) bottom.
- The baselines/bottoms of the main and reply `.lime-composer__privacy`.
- C: the toggle glyph's right gap (`#right-panel-toggle .dew`: `innerWidth − rect.right`); D: the reply box's right gap.
- E: the "Thread" title's left x; F: the reply box's left x.
- Also `getComputedStyle(#right-panel).padding`, to confirm the premise.

**Goal:**
- The main composer box's bottom and privacy row sit at the reply composer's **current** (post-fix5) y, within ±1px.
- The reply box's right gap D equals the toggle glyph gap C (±1px). Its left edge F lines up with the "Thread" title E (±1px).
- The reply composer's vertical position stays where it is now.

**Scope:**
- **May touch:** `lime.css` rules for `.lime-replies-panel__composer` / `#replies-composer`, and for the main composer's vertical placement (`.lime-composer`, `.lime-chat-body`, or the center panel's bottom spacing, whichever is the true constraint). Also `TEND.md`, and `index.html` **temporarily** for the diagnostic.
- **May not touch:** the toggle's position, the main composer's width, the mobile layout, or Seed files.

**Phase 1 — Survey:** take the baseline measurements above and report them. Identify what limits how low the main composer can sit: plot expects the center card's bottom edge, which is inset by `#layout`'s 16px padding, while the right panel is flush. **If moving the main composer down requires changing the center card's size or `#layout`'s padding, report exactly what else that would move** (the message list's bottom padding and fade from LIME-10-fix15, which were calibrated to the composer's height). Proceed only if the side effects are limited to the composer area and the thread's bottom clearance stays positive. Otherwise stop and ask **the user**.

**Phase 2 — The change:**
1. **Reply side:** replace fix5's negative `margin-right` with a right padding that makes D equal C. Remove `margin-bottom` **only if** the reply composer's y can be held at its current value some other way. The user wants its current height kept, so the vertical position must not move. Fix the comment so it states the real premise: the panel's padding is zeroed at lime.css ~112.
2. **Main side:** lower the main composer to match the reply composer's y, using the least invasive mechanism found in the survey. Re-check the message list's bottom clearance: it must stay positive in both collapsed and expanded states (LIME-10-fix15's method).

**Phase 3 — Verification:** re-run the headless measurement and report before and after for A–F plus both privacy rows. All targets must be within ±1px. Also: the thread's bottom clearance is positive in both composer states; at 767px wide, both composers are still fully on-screen with even side gaps; the diagnostic script is removed (`git diff public/index.html` is empty); the brace counts in `lime.css` are equal.

**Gate:** the user checks in Firefox at the file:// URL:
- **Same height:** with a thread open on a wide window, both chat boxes and the rows under them sit at the same (lower) height.
- **Right gap:** the reply box has a right gap matching the panel toggle icon above it.
- **Last message:** the final message isn't hidden behind the main chat box.

**Record:** add a `## LIME-18-fix7` entry to `TEND.md` with the before/after numbers, and correct fix5's entry if it states the padding premise as fact. Commit: `fix: correct reply composer gutter, lower main composer to match`, trailer `Brief: LIME-18-fix7`, plus the attribution trailer.

> **Shared context for LIME-20 and LIME-21 (menus).** The user's QA (2026-09-27, screenshot with the notifications, user and voice menus all open at once): "these hovers all work differently and some of them are broken… let's fix them (utilise Seed when necessary, fix position, dropdown item length, default and hover colours)."
>
> **Survey (plot, read-only).** Lime has **three separate menu styles** and doesn't use Seed's dropdown component at all:
> - `.lime-nav-dropdown` (lime.css ~595–663; `position: fixed`, JS-positioned, **always opens upward**). Used by notifications `#notif-dropdown`, user `#user-dropdown`, voice `#voice-mode-dropdown`/`#replies-voice-mode-dropdown`, and toolbar overflow `#composer-toolbar-overflow-dropdown`/`#replies-…`.
> - `.lime-dropdown` (~879–918; absolute). Used by the header "…" `#more-menu`.
> - `.lime-notif` rows (~665–712) inside the notifications menu.
> - Seed's `vendor/seed/components/dropdown/dropdown.css` is **not linked** in `index.html`.
>
> **Bugs seen in the screenshot:**
> 1. **Items stick out past the menu.** `.lime-nav-dropdown__item` and `.lime-dropdown__item` are `width: 100%` plus padding in content-box, so every hover or active highlight is 24px wider than the menu. That's the lime "Default – MacBook Pro Microphone" row overflowing to the right. It's the same no-`border-box` cause as LIME-18-fix4. **Seed's own `.seed-dropdown__item` has the identical bug** (`width: 100%` plus padding, no border-box), so Lime needs an override. Log it for upstreaming to Seed.
> 2. **Several menus can be open at once.** Each toggle calls `stopPropagation()`, so the document-level "close on outside click" never fires for the *other* open menus (`wireDropdownToggle`, app.js ~929).
> 3. **The notifications menu opens upward from the bell** (near the top of the screen), so it's pushed off the top edge.
> 4. **The voice menu's text doesn't line up:** only the active row has a check icon, so its text is indented and the others aren't.
> 5. **Inconsistent styling:** different paddings, radii, backgrounds (`--soil-bg-surface` vs Seed's `--soil-bg-elevated`) and z-indexes (1000 vs 100) between the two menu styles.
>
> **Order:** LIME-20 (behaviour: JS only) first, then LIME-21 (one visual system on Seed). **Capability assumptions for both:** can edit files, run commands and commit. For JS, load the real app in jsdom with zero errors. Chrome is preferred for position checks. The user previews at `file:///Users/shem/Sites/lime/public/index.html`.

### LIME-20 → `tend`: menus open in the right place, and only one at a time

**Goal:** every JS-toggled menu opens where it fits (below its trigger if there's room, otherwise above), stays fully on-screen, and opening one menu closes any other.

**Scope:**
- **May touch:** `wireDropdownToggle` and its call sites in `public/js/app.js`, and `TEND.md`.
- **May not touch:** CSS or markup (that's LIME-21), the reaction picker (it has its own positioning), or the search modal.

**Phase 1 — Survey:**
1. List every `wireDropdownToggle(...)` call and whether it's fixed. Plot expects 7 fixed plus the non-fixed `more-menu`.
2. Confirm the stopPropagation cause of the "several open at once" bug by reading the code.
3. If anything differs, stop and ask **the user**.

**Phase 2 — The change** (inside `wireDropdownToggle` only; keep its signature):
1. **One open at a time.** When opening a menu, first remove `is-open` from every other element that `wireDropdownToggle` manages. Keep a module-level `Set` of registered dropdowns.
2. **Flip plus clamp, fixed mode only.** On open, after adding `is-open` so the menu can be measured:
   - `rect` is the trigger's rect; `h` and `w` are the menu's `offsetHeight` and `offsetWidth`; the gap is 8px.
   - **Vertical:** if `rect.bottom + gap + h <= innerHeight - 8`, open **below**: set `top = rect.bottom + gap` and clear `bottom`. Otherwise open **above**: set `bottom = innerHeight - rect.top + gap` and clear `top`. If it fits neither way, use the side with more room.
   - **Horizontal:** keep LIME-18-fix4's clamp, `left = clamp(8, rect.left, innerWidth - w - 8)`.
   - Clear any stale `top`/`bottom` inline values from a previous opening.
3. **Escape closes the open menu.** Add one keydown listener in the same helper.
4. **`more-menu`:** switch it to fixed mode, so every menu uses one positioning path. Don't change its CSS here. LIME-21 moves it to the shared fixed style; until then its `.lime-dropdown` absolute rule will be overridden by the inline values, which is acceptable for one commit. **If** it visibly breaks in the interim, leave it non-fixed and note that in `TEND.md`.

**Phase 3 — Verification:**
1. `node --check` passes, and the real app loads in jsdom with zero errors.
2. In jsdom, open the notifications menu, then the user menu: only the user menu has `is-open`. Press Escape: none are open.
3. If Chrome is available (desktop width):
   - the notifications menu opens **below** the bell and is fully on-screen;
   - the user menu opens **above** the avatar;
   - the voice and "…" composer menus open above their buttons;
   - the header "…" opens below.
   Report each menu's rect. Without Chrome, say so, and reason from the numbers.

**Gate:** the user checks in Firefox:
- **Notifications:** opens downward and fully visible.
- **One at a time:** opening any menu closes the one that was open.
- **Escape:** closes menus.
- **Near screen edges:** menus never run off the screen.

**Record:** add a `## LIME-20` entry to `TEND.md`. Commit: `fix: menus flip to fit, stay on-screen, and close each other`, trailer `Brief: LIME-20`, plus the attribution trailer.

---

### LIME-20-fix → `tend` (before LIME-21): notifications opens to the right of the bell

**User QA of LIME-20 (`e9d3783`, 2026-09-27):** "the notifications dropdown should be to the right of the icon so that I can see the other nav icons below notifications." It currently opens below the bell and covers the nav.

**Capability assumptions:** can edit files, run commands and commit. Load the real app in jsdom (zero errors). Measure placement with headless Chrome (see Patterns).

**Scope:**
- **May touch:** `wireDropdownToggle` and the `notif-btn` call site in `public/js/app.js`, and `TEND.md`.
- **May not touch:** CSS or markup, or any other menu's placement. The user menu keeps flip-above.

**The change:**
1. Add an option to `wireDropdownToggle`: `{ fixed = false, placement = 'vertical' } = {}`. When `placement === 'right'` in fixed mode, on open:
   - `left = rect.right + gap`, and `top = rect.top`, with `bottom` cleared.
   - Clamp vertically: `top = Math.max(8, Math.min(rect.top, innerHeight - h - 8))`.
   - **Fallback:** if `rect.right + gap + w > innerWidth - 8` (no room on the right, e.g. a narrow mobile drawer), use the existing vertical flip-and-clamp path unchanged.
2. Pass `{ fixed: true, placement: 'right' }` for `notif-btn` only.
3. Add a one-line comment on why: the menu opens beside the bell so the nav items below it stay visible.

**Verification:**
1. `node --check` passes, and the real app loads in jsdom with zero errors.
2. Headless Chrome at 1567×905: with the sidebar expanded **and** collapsed, the notifications menu's left edge is ≥ the bell's right edge, its top is within 1px of the bell's top, and it's fully on-screen. Report the rects.
3. At a narrow width where the right side doesn't fit, it falls back to below or above and stays on-screen.

**Gate:** in Firefox, open notifications with the sidebar expanded, then collapsed. It opens to the right of the bell, and Link and Jam stay visible below it.

**Record:** add a `## LIME-20-fix` entry to `TEND.md`. Commit: `fix: notifications menu opens beside the bell`, trailer `Brief: LIME-20-fix`, plus the attribution trailer.

---

### LIME-21b → `tend` (after LIME-20-fix): every menu uses the search modal's pattern; lime only for nav and primary actions

> **Replaces LIME-21 (the Seed dropdown styling version), which was never executed.** The user's direction (2026-09-27), on seeing the search modal: "I like how the search modal handles roundedness and the hover states of each item in the list, can we use this pattern for all of the dropdowns. Leave the lime green colour for the nav and primary actions like the chat box return buttons." And for reactions and panel dividers: "use the same neutral patterns [as] the search modal." **Seed's `dropdown.css` is NOT adopted.** Its edge-to-edge rows aren't the look the user wants. Seed *tokens* are still used throughout.

**The search modal pattern (lime.css ~1191–1282), the reference:**
- **container:** `--soil-bg-elevated`, `--seed-radius-lg`
- **list padding:** `--seed-space-2`
- **items:** `padding: --seed-space-2`, `gap: --seed-space-3`, `border-radius: --seed-radius-md`, `--seed-text-sm`, `--soil-text`; hover/focus-visible `background: --calm-bg-subtle-hover`
- **item icons:** 14px, `--soil-text-muted`
- **section label:** `--seed-text-xs`, medium, `--soil-text-muted`, padding `8px 8px 4px`

**Why its items never overflow:** they're `<button>`s, and browsers default buttons to `box-sizing: border-box`. The broken menu rows are `<div>`s with `width: 100%` plus padding (content-box). That's the "items extend outside" bug.

**Goal:**
- All 8 menus (notifications, user, header "…", both voice menus, both toolbar-overflow menus) and the search modal's list share one item/label/divider style: the search modal's.
- Lime appears only on nav and primary actions.
- Menu selection, your own reactions and panel-divider hover use neutral greys.

**Capability assumptions:** can edit files, run commands and commit. Load the real app in jsdom (zero errors). Use headless Chrome for measurements (see Patterns).

**Scope:**
- **May touch:** `public/index.html` (menu markup and the search modal's item classes), `public/css/lime.css`, the `wireDropdownToggle` call for `more-menu` in `public/js/app.js`, and `TEND.md`.
- **May not touch:**
  - `vendor/`
  - the nav's lime (`.lime-nav__btn` hover/active, user-trigger hover)
  - the Send/return button's lime (`.lime-composer__return.is-active`)
  - the `--selected-*` retune in the light-theme block (the nav still uses it)
  - menu contents and positioning logic (LIME-20 and 20-fix)
  - the reaction picker's own layout

**Phase 1 — Survey:**
1. List every element and selector using `lime-nav-dropdown`, `lime-dropdown`, `lime-notif`, `lime-search-modal__item` or `lime-search-modal__label`.
2. List every remaining **non-nav, non-primary** use of lime: grep `var(--selected-` and `var(--seed-lime-` in `lime.css` and classify each as nav, primary action, or other. Plot expects "other" to include `.lime-nav-dropdown__item--active` (~647), `.lime-reaction--active` (~2003), the divider hovers (~84/90, ~1355/1360, now `--selected-bg-subtle-hover`/`-active` from LIME-14), and possibly `.lime-message__avatar` rings (~1550) and `~2071`. **Report the list before changing anything. Change only items the user named** (menus, reactions, dividers). List anything else as a question in `TEND.md` and at the gate.

**Phase 2 — The change:**
1. **One shared menu style in `lime.css`,** in a single commented block ("Menu pattern — mirrors the search modal (LIME-21b)"):
   - `.lime-menu`: `display: none`, `position: fixed`, `background: --soil-bg-elevated`, `border: 1px solid --soil-border-subtle`, `border-radius: --seed-radius-lg`, `box-shadow: --seed-shadow-md`, `padding: --seed-space-2`, `min-width: 220px`. Keep z-index 1000, the current value that clears the mobile panel overlay. `.lime-menu.is-open { display: block; }`
   - `.lime-menu__item`: the search modal item's values, plus `box-sizing: border-box; width: 100%;`, reset button/anchor defaults (`border: none; background: none; font-family: var(--seed-font-ui); text-align: left; text-decoration: none; cursor: pointer;`). Hover and focus-visible use `--calm-bg-subtle-hover`. Icons inside are 14px `--soil-text-muted`.
   - `.lime-menu__item--selected`: `font-weight: --seed-weight-medium`. **No lime** and no background at rest; its check icon is `--soil-text`.
   - `.lime-menu__label`: the search modal label's values.
   - `.lime-menu__divider`: 1px `--soil-border-subtle`, margin `--seed-space-2` 0.
   - `.lime-menu__header`: the item's padding, `--soil-text-muted`, `--seed-text-sm`, no hover, `cursor: default`. For information like email and phone.
   - `.lime-menu__check`: a fixed 14px slot, so text lines up whether or not a check shows.
2. **Search modal:** its result items become `class="lime-menu__item"` and its label `lime-menu__label`. Delete `.lime-search-modal__item*` and `__label` rules that are fully covered. Keep any modal-only rule, and say why.
3. **All 8 menus:**
   - Each container becomes `class="lime-menu"` (ids unchanged). Notifications and voice get `min-width: 280px` via an id or modifier rule; notifications keeps `max-width: 320px` with ellipsis previews.
   - All items become `lime-menu__item`. Use `<button type="button">` for actionable rows where the element is currently a `<div>`; notification rows stay `<a class="lime-menu__item lime-notif">` with their inner avatar/name/time/preview.
   - Voice rows: every row gets a `<span class="lime-menu__check">`, holding a `dew-check` only on the selected row, which gets `lime-menu__item--selected`.
   - User menu: email and phone go into one `.lime-menu__header`, followed by a divider, Settings and Sign Out as normal items (no red).
   - The header "…" menu becomes `lime-menu`. In `app.js`, switch its call to `{ fixed: true }` and remove LIME-20's explanatory comment about why it wasn't.
4. **Delete** the old `.lime-nav-dropdown*`, `.lime-dropdown*` and `.lime-more-menu` rules (keep the wrapper only if something still needs it, and say why). Restyle `.lime-notif*` so only its inner layout remains; the row's padding, radius and hover come from `.lime-menu__item`.
5. **Reactions (neutral):**
   - `.lime-reaction--active`: `background: --calm-bg-subtle-active`, `border-color: --calm-border-normal-default`.
   - Its hover goes one step: `--calm-bg-subtle-hover` stays the plain-chip hover. For the active chip on hover, use `--calm-bg-subtle-active` with a `--calm-border-bold-default` border so it still changes.
   - Comment: "neutral, per the user: lime is reserved for nav and primary actions (LIME-21b)."
6. **Panel dividers (neutral):** hover → `--calm-border-normal-default`; dragging → `--calm-border-bold-default`, for both the outer handles (~84/90) and the center handle (~1355/1360). Update the long comment at ~64–74 to match.

**Phase 3 — Verification:**
1. `grep -rn 'lime-nav-dropdown\|lime-dropdown\b\|lime-search-modal__item\|lime-search-modal__label' public/` returns nothing.
2. The brace counts are equal, `node --check` passes, and the real app loads in jsdom with zero errors. All 8 menus, plus search, open and close; one at a time; Escape works.
3. **Headless Chrome.** For every menu and the search list:
   - max(item right edge) ≤ container inner right edge (report the overflow; it must be ≤ 0);
   - the item border-radius equals the search modal's;
   - item hover background = `--calm-bg-subtle-hover`;
   - the selected voice row has no lime (report its computed background);
   - the header "…" opens below its button, fully on-screen;
   - notifications still opens to the right of the bell.
4. Your own reaction chip computes a neutral background (no lime). Divider hover and drag colours are neutral.
5. Lime still appears on the nav hover/active and on the active Send button (report the computed values).

**Gate:** the user checks in Firefox at the file:// URL:
- **Every menu:** open each one (notifications, profile, header "…", both microphone menus, both formatting "…" menus). They should look like the search modal: rounded rows, grey hover, nothing sticking out.
- **Microphone menu:** the chosen microphone has a checkmark, not lime, and the names line up.
- **Reactions:** your reactions are grey, not lime.
- **Panel dividers:** grey on hover.
- **Lime still where it belongs:** the nav and the Send arrow.
- **Other lime spots:** answer any questions tend listed about lime it found elsewhere.

**Record:** add a `## LIME-21b` entry to `TEND.md`. Commit: `refactor: one menu pattern (search-modal style), lime reserved for nav and primary actions`, trailer `Brief: LIME-21b`, plus the attribution trailer. Don't edit `PLOT.md`.

---

### LIME-22 → `tend` (after LIME-21b): close button on the search modal

**User request (2026-09-27):** the search modal "needs a close x button in the top right."

**Scope:**
- **May touch:** the search modal markup in `public/index.html` (~668–680), its CSS in `lime.css` (~1191–1240), its open/close IIFE in `app.js` (~943–1000, including the focus trap), and `TEND.md`.

**The change:**
- Add `<button type="button" class="lime-icon-btn lime-search-modal__close" id="search-modal-close" aria-label="Close search" title="Close"><span class="dew dew-close"></span></button>` as the last child of `.lime-search-modal__field`, so it sits at the top right on the field's row, after the input. Check the dew icon name exists (`grep -o 'dew-close\|dew-x' vendor/seed/icons/dew/dist/dew.css`); use whichever exists, and report it.
- Wire it to the same `close()` the backdrop and Escape use.
- Make sure the focus trap includes it (it's a normal button, so `focusable()` should pick it up; confirm).
- CSS: `flex-shrink: 0`, and a `margin-right` of `calc(-1 * var(--seed-space-2))` only if needed to align the glyph with the field's 16px inset. Measure it, don't guess.

**Verification:**
- The real app loads in jsdom with zero errors. Clicking the close button closes the modal and returns focus the way Escape does.
- Headless Chrome: the button sits at the top right of the modal; the glyph's right gap from the modal's edge equals the search icon's left gap (±1px).

**Gate:** in Firefox, open search. There's an × at the top right, and it closes the modal.

*(Plot checked: `dew-close` exists.)*

**Record:** add a `## LIME-22` entry to `TEND.md`. Commit: `feat: close button on search modal`, trailer `Brief: LIME-22`, plus the attribution trailer.

---

### LIME-18-fix6 → `tend` (after 18-fix5): reply summary underlined only on hover, never on avatars

**User QA (2026-09-27):** "the reply links and avatar letters are all underlined and should only be on hover." The screenshot shows the "SR" avatar initials, "1 reply" and "Last reply today at 8:45 AM" all underlined at rest.

**Plot's reading of an ambiguous line, flagged at the gate:** the user also wrote "the avatar characters should have a hover underline". Plot reads this as avatar initials **never** being underlined (an underlined initial in a circle reads as a bug), with the text parts underlined on hover only. If the user meant the avatars should underline on hover too, that's a one-line follow-up.

**Root cause:** `.lime-message__replies` (lime.css ~1904) sets `text-decoration: underline` on the whole button, which propagates to every in-flow descendant: the avatar initials, the count and the time. The count is also a bare text node (app.js ~137), so it can't be styled on its own.

**Capability assumptions:** can edit files, run commands and commit. Run the real app in jsdom for the JS change.

**Scope:**
- **May touch:** `replyIndicatorHtml` in `public/js/app.js` (markup only), the `.lime-message__replies` / `.lime-replies__*` rules in `public/css/lime.css` (~1894–1925), and `TEND.md`.
- **May not touch:** colours, sizes, the avatar stack or spacing.

**Phase 2 — The change:**
1. **`replyIndicatorHtml`:** wrap the count in `<span class="lime-replies__count">N reply/replies</span>`. Nothing else in the markup changes.
2. **CSS:**
   - Remove `text-decoration: underline` from `.lime-message__replies`, and set `text-decoration: none` there instead.
   - Add `.lime-message__replies:hover .lime-replies__count, .lime-message__replies:hover .lime-replies__time { text-decoration: underline; }`.
   - Add `.lime-message__replies:focus-visible .lime-replies__count { text-decoration: underline; }`, so keyboard focus gets the same cue.
   - Avatars never get an underline. Since the button itself no longer has one, nothing propagates to them.

**Phase 3 — Verification:**
1. `node --check` passes, the real app loads in jsdom with zero errors, and the rendered summary contains `.lime-replies__count`.
2. The brace counts in `lime.css` are equal.
3. If Chrome is available: at rest, the computed `text-decoration-line` is `none` on the button, count, time and avatars. On hover (forced `:hover`), it's `underline` on the count and time only.

**Gate:** the user checks in Firefox at the file:// URL:
- **At rest:** nothing under a message is underlined.
- **On hover:** hovering the reply summary underlines "1 reply" and "Last reply …", but never the avatar letters.
- Ask them to confirm this is what they meant about the avatars.

**Record:** add a `## LIME-18-fix6` entry to `TEND.md`. Commit: `fix: reply summary underlines only on hover, never on avatars`, trailer `Brief: LIME-18-fix6`, plus the attribution trailer.

### LIME-18-fix5 → `tend`: the two composers line up, and the right panel's gutters match

**User QA (2026-09-27, desktop, screenshot):**
1. "Look at them side by side: the reply component is slightly higher than the center input component. They should be in the same position." The reply composer (box and the +/mic/secure row under it) must sit at **the same vertical position** as the main composer.
2. "The width should be consistent with the panel it's in." Each composer keeps its own panel-relative width: the main one stays 75% of the center, and the reply one fills its panel minus gutters. Don't make them equal widths.
3. "Look at the top-right sidebar toggle icon and the reply chat input: the right-side spacing from the browser window edge isn't equal. It should be the same as the toggle icon's distance."

**Capability assumptions:** can edit files, run commands and commit. **This brief is about pixel measurement, so Chrome is strongly preferred.** Without it, compute each position from the CSS chain, show the arithmetic in `TEND.md`, and tell the user the result is computed, not measured.

**What plot read:**
- `lime.css`: `.lime-composer` (~2199, absolute, bottom 0, padding `12px 16px 8px`), `.lime-chat-body` (~1670, the main composer's positioning context), `.lime-replies-panel__composer` (~2889, the reply composer's positioning context, padding 12px), `.lime-replies-panel__header` (~2751, padding 0 16px), `.lime-panel-close` (~2648, `#right-panel-toggle`, absolute top/right 12px), `.lime-composer__return` (~2389), `.lime-composer__privacy` (~2505)
- `vendor/seed/components/layout/layout.css`: flush mode (~222–265)

Plot suspects the two composers sit in different containers whose bottom edges differ: the center card sits inside `#layout`'s 16px padding, while the right panel is in flush mode. The small padding differences on top of that are what shift them. **Plot did not measure this.** Find the actual cause in the survey.

**Goal:**
- On desktop with the thread panel open and both composers **collapsed**, the main and reply composers' boxes have the same bottom y, and their +/mic/secure rows have the same text baseline (±1px).
- In the right panel, the reply composer box's right edge sits the same distance from the window's right edge as the toggle icon's visible glyph (±1px). Its left edge lines up with the "Thread" title's left edge.

**Scope:**
- **May touch:** `public/css/lime.css` rules for `#replies-composer`, `.lime-replies-panel__composer`, `.lime-replies-panel__header`, `.lime-panel-close`, and `.lime-composer` if the fix belongs there. Also `TEND.md`.
- **May not touch:** the main composer's 75% width, Seed `vendor/` files, flush mode itself, the toolbar-collapse rules, or mobile layouts. Check that mobile isn't made worse, but don't redesign it.
- Prefer moving the **reply** side to match the main composer and the toggle, not the reverse. If the only clean fix moves the main composer or the toggle, stop and ask **the user**, with the numbers.

**Phase 1 — Survey.** Measure, and report the numbers:
1. Main composer box: bottom y. Reply composer box (collapsed): bottom y. The baseline y of the "secure" text in each row.
2. The toggle icon glyph's right edge (the `.dew` inside `#right-panel-toggle`, not the button) → distance to the viewport's right edge. The reply composer box's right edge → distance to the viewport's right edge. The "Thread" title's left x and the reply box's left x.
3. The cause of each difference: which container, padding or offset produces it.

**Phase 2 — The change:** adjust only the reply-side and right-panel values needed to hit the goal numbers. Use Seed spacing tokens (`--seed-space-*`) rather than magic pixels where a token fits; if a token doesn't fit exactly, explain the literal in a comment. Add a short comment on each changed rule saying what it's aligned to (e.g. "matches the main composer's bottom" or "matches #right-panel-toggle's glyph inset").

**Phase 3 — Verification:**
1. Re-measure everything from Phase 1 and report before/after. All differences must be within 1px.
2. Expand the reply composer (focus it): it grows **upward only**, and its bottom and action row don't move.
3. At mobile width (≤767px) in the "panel" view, the reply composer is still fully on-screen with even side gaps, as LIME-18-fix4 left it.
4. The brace counts in `lime.css` are equal.

**Gate:** the user checks in Firefox at the file:// URL:
- **Side by side:** with a thread open on a wide window, the two chat boxes and the rows under them sit at exactly the same height.
- **Right edge:** the reply box's right edge is the same distance from the window edge as the panel toggle icon above it.

**Record:** add a `## LIME-18-fix5` entry to `TEND.md` with the before/after numbers. Commit: `fix: align reply composer with main composer and right-panel gutter`, trailer `Brief: LIME-18-fix5`, plus the attribution trailer.

### LIME-18-fix4 → `tend`: the reply composer runs off the right edge, and its "…" menu is clipped

**User QA (2026-09-27), narrow "Thread" panel view:** the reply input looks cut off on the right, the spacing is uneven (inset on the left, none on the right), and the "…" menu is clipped at the screen edge.

**Capability assumptions:** can edit files, run commands and commit. Run the real app in jsdom (scratchpad) for any JS change. Chrome is optional.

**What plot read:**
- `lime.css`: 2199–2245 (`.lime-composer`, `.lime-composer__box`, `#replies-composer .lime-composer__box`), 2425–2436 (`__actions` and the reply override), 2885–2910 (`.lime-replies-panel__composer`), 3172–3186 (mobile panel view)
- `app.js`: 929–956 (`wireDropdownToggle`)
- a grep of Seed and Lime CSS for `box-sizing`

**Root cause (plot's reading; confirm in the survey):**
- **The overflow:** there is **no global `box-sizing: border-box`** anywhere (Seed sets it only on `.seed-layout` itself). `#replies-composer .lime-composer__box` is `width: 100%` **plus** 12px left and right padding **plus** a 1px border in content-box sizing, so it renders 26px wider than its container and pushes past the right edge. `#replies-composer .lime-composer__actions` (`width: 100%` plus 4px side padding) overflows by 8px the same way. The main composer never shows this because its box is 75% wide.
- **The clipped "…" menu:** `wireDropdownToggle` in fixed mode always left-aligns the dropdown to its trigger, with no check against the viewport's right edge. Near the right edge of a narrow panel it runs off-screen.

**Goal:** the reply composer sits evenly inset (the same gap left and right) inside its panel at every width, and fixed-position dropdowns never render past the viewport's edge.

**Scope:**
- **May touch:** `public/css/lime.css` (the two `#replies-composer` width overrides only), `public/js/app.js` (`wireDropdownToggle` only), and `TEND.md`.
- **May not touch:** the main composer, any global `box-sizing` reset (too broad for this fix; plot may raise it separately), the toolbar-collapse rules from 18-fix3, or the reply panel layout.

**Phase 1 — Survey:**
1. Confirm there's no global `box-sizing` reset (`grep -rn 'box-sizing' public/css vendor/seed`).
2. Confirm the two width overrides and the padding and border values above.
3. If the survey disagrees, stop and ask **the user**.

**Phase 2 — The change:**
1. **`lime.css`:** add `box-sizing: border-box;` to both `#replies-composer .lime-composer__box` and `#replies-composer .lime-composer__actions`. Add a one-line comment on the first: "width:100% + padding/border overflowed the panel — no global border-box reset in this app".
2. **`app.js`, `wireDropdownToggle`:** in the fixed branch, clamp the horizontal position after the dropdown is open (it has to be visible to be measured). Restructure the click handler so that when opening a fixed dropdown it:
   - toggles `is-open`;
   - measures `dropdown.offsetWidth`;
   - sets `left = Math.max(8, Math.min(rect.left, window.innerWidth - dropdown.offsetWidth - 8))` in px;
   - keeps the existing `bottom` logic unchanged.
   Closing is unchanged. Add one comment line on why the clamp exists.

**Phase 3 — Verification:**
1. The brace counts in `lime.css` are equal. `node --check` passes. The real app loads in jsdom with zero errors.
2. **Reply composer:** if Chrome is available, in the mobile "panel" view (≤767px) and in the desktop right panel, the reply `.lime-composer__box`'s right edge sits inside its panel, with left and right gaps equal (±1px). Otherwise verify by computing: content + padding + border = the container's content width.
3. **Dropdowns:** the reply composer's "…" menu, opened in the narrow panel, sits entirely on-screen. The notifications, user and voice-mode dropdowns still open in the same place as before on desktop (the clamp shouldn't move them when there's room).

**Gate:** the user checks in Firefox at the file:// URL:
- **Narrow window:** open a thread and expand the reply box. It has an even gap on both sides, and nothing is cut off. Open "…": the whole menu is visible.
- **Wide window:** same check in the right panel.
- **Other menus:** the notifications, profile and microphone menus still open normally.

**Record:** add a `## LIME-18-fix4` entry to `TEND.md`. Commit: `fix: reply composer overflowing its panel, clamp fixed dropdowns to viewport`, trailer `Brief: LIME-18-fix4`, plus the attribution trailer.

**Open thread this raises (not for this brief):** Lime has no global `box-sizing: border-box` reset. Every `width: 100%` + padding element is a latent version of this bug. Candidate cleanup brief: add a reset and check for layout shifts. It's risky, so it needs a careful visual pass.

> **Shared context for LIME-17, 18 and 19** (the user's QA from 2026-09-27): reacting to the quoted message in the thread panel didn't show on the main thread; sending a reply didn't update the original message; the chat list doesn't show the latest message or reply; and the original message is missing replier avatars and a "last reply" time. Run them in order. Each builds on the previous one. **Capability assumptions for all three:** can edit files, run commands and commit. Chrome is optional, for internal checks only. The user previews in Firefox at `file:///Users/shem/Sites/lime/public/index.html`. **What plot read:** `app.js` 1–335 (thread, reactions, contact list) and 665–830 (replies panel), 1000–1150 (scope filter and load-time contact bindings); all of `data.js`; `index.html` 262–335 (Starred and All Teachers); and the seed data via node (conv-001 has 9 messages, 3 of them replies to msg-003; only 3 direct conversations exist for teacher-002: with Jean Chung (001), Alexi Daily (006) and Kai Nakamura (009)).

### LIME-17 → `tend`: live sync between the thread panel and the main thread

**Goal:** a reaction or reply made anywhere shows up everywhere that message is on screen, and replies never render as ordinary messages in the main thread.

**Scope:**
- **May touch:** `public/js/app.js`, `public/js/data.js`, and `TEND.md`.
- **May not touch:** CSS, the reply-indicator's look (that's LIME-18), the contact list (that's LIME-19), or the seed data.

**Phase 1 — Survey (read-only):**
1. At the file:// URL, open Jean Chung (conv-001). Check whether any reply to msg-003 (msg-004, msg-1004, msg-1005) currently renders inline in the main thread. Plot expects yes: `renderThread` uses `getMessagesByConversation`, which doesn't exclude `reply_to` messages. Report which.
2. Confirm `getMessagesByConversation` is also used by the contact list (~app.js 311). That caller stays unchanged in this brief.
3. If the survey turns up related issues, raise them before proceeding. If anything doesn't match, stop and ask **the user**.

**Phase 2 — The change:**
1. **`data.js`:** add `getThreadMessages(conversationId)`, which returns `getMessagesByConversation(conversationId)` filtered to messages without `reply_to`. Add a one-line comment saying replies live in the thread panel, not the main thread.
2. **`renderThread`:** use `getThreadMessages` instead of `getMessagesByConversation`.
3. **Reaction sync:** in the reaction click handler (~app.js 128–166), after `addReaction` or `toggleReaction`, re-render reactions on **every** element that is both in `REACTABLE` and has that `data-message-id`, not just the clicked one:
   ```js
   function renderReactionsEverywhere(messageId, reactions) {
     document.querySelectorAll(REACTABLE).forEach((el) => {
       if (el.dataset.messageId === messageId) renderReactions(el, reactions);
     });
   }
   ```
   Use it in both the picker branch and the pill branch.
4. **Reply indicator refresh:**
   - Move `replyIndicatorHtml` out of the first IIFE to top level, next to `reactionsHtml`, unchanged.
   - Add a top-level `refreshReplyIndicator(messageId)`. It finds `#thread-messages .lime-message[data-message-id="…"]`; if found, it removes any existing `.lime-message__reply-indicator` inside it and inserts `replyIndicatorHtml(messageId)` directly after that message's `.lime-message__reactions`.
   - Call it in `submitReply` right after `sendReply(...)`.

**Phase 3 — Verification.** Report facts, not raw output:
1. `node --check` passes on both files.
2. In conv-001, the main thread no longer shows msg-004, msg-1004 or msg-1005 inline. The "3 replies" indicator still shows on msg-003.
3. Open the thread panel on any message and react to the quote: the same emoji and count appear on that message in the main thread. Do the reverse, reacting in the main thread while the panel shows it: the quote updates.
4. Reply to a message that has no replies: "1 reply" appears under it in the main thread immediately. Switch conversations and back: the reply is not inline in the main thread.
5. If Chrome isn't available, say so and verify by reading the source.

**Gate:** the user checks in Firefox:
- **Reactions:** react on the quoted message in the thread panel, and the original message shows the same reaction.
- **Replies:** send a reply, and "1 reply" appears under the original straight away.
- **No duplicates:** replies don't show up as regular messages in the main chat.

**Record:** add a `## LIME-17` entry to `TEND.md`. Commit it with the change: `fix: sync reactions and replies between thread panel and main thread`, trailer `Brief: LIME-17`, plus the attribution trailer.

---

### LIME-18 → `tend`: restore the reply summary under the original message (after LIME-17)

**Background:** the original mockup (commit `fe4631b`, static markup in `index.html`) had a Slack-style summary: replier avatars, "4 replies", then "Last reply 7 days ago". It disappeared in `367fae8` when the thread started rendering from seed data, and LIME-11-fix5 later added a plainer "💬 N replies" button (`.lime-message__reply-indicator`) in its place. **Its CSS is still in `lime.css` (~1880–1917: `.lime-message__footer`, `.lime-replies__avatars`, `.lime-message__replies`, `.lime-replies__time`), unused.** This brief restores that design, now driven by live data. The user's reference: two avatars, **"2 replies"**, then muted **"Last reply today at 1:09 PM"**.

**Goal:** every main-thread message with replies shows the replier avatars, "N replies" and "Last reply {when}", using the original classes and CSS. The thread panel's meta line uses the same "when".

**Scope:**
- **May touch:** `public/js/app.js` (`replyIndicatorHtml`, `refreshReplyIndicator`, the indicator click delegate, `renderMeta`, a new time helper, and avatar painting where indicators are inserted), `public/css/lime.css` (delete the now-unused `.lime-message__reply-indicator` rules, ~1980–2001), and `TEND.md`.
- **May not touch:** the restored `.lime-message__footer`/`.lime-replies__*`/`.lime-message__replies` CSS. Reuse it as it is; if something visibly needs adjusting, raise it at the gate instead. Also off limits: the thread panel layout and the contact list.

**Phase 1 — Survey:**
1. Confirm LIME-17 has landed (`refreshReplyIndicator` exists at top level).
2. Run `git show fe4631b -- public/index.html | grep -n "lime-message__replies" -B8 -A3` to see the original markup.
3. Confirm the four old CSS rules above still exist, and that nothing currently uses them (`grep -n 'lime-message__replies\|lime-replies__' public/js public/index.html` returns nothing).
4. Run `grep -n 'reply-indicator' public/` and list every reference; they all get renamed.
5. Check whether `.seed-avatar-group` in `vendor/seed/components/avatar/avatar.css` overlaps avatars. Report how it looks either way, and don't change it.

**Phase 2 — The change:**
1. **Time helper.** Add a top-level `formatLastReply(iso)`, next to `formatTime`. It returns the text after "Last reply ":
   - same calendar day → `today at 1:09 PM` (uses `formatTime`)
   - the previous calendar day → `yesterday at 1:09 PM`
   - 2–29 days → `N days ago`
   - older → a short date like `Jul 8`
2. **`replyIndicatorHtml(messageId)`** (keep the zero-replies early return). Rebuild it on the original structure:
   ```html
   <div class="lime-message__footer">
     <button type="button" class="lime-message__replies" data-message-id="…">
       <span class="seed-avatar-group lime-replies__avatars">
         <span class="seed-avatar seed-avatar--xs lime-avatar" data-name="…"></span> …
       </span>
       N replies<span class="lime-replies__time">Last reply {formatLastReply(last.created_at)}</span>
     </button>
   </div>
   ```
   - Avatars are the distinct reply senders, most recent replier first, at most 5.
   - "1 reply" or "N replies", lowercase.
   - Don't reuse the old `id="open-replies"`; it would repeat on every message.
3. **Rename the JS hooks** from `.lime-message__reply-indicator` to `.lime-message__replies`:
   - the click delegate (~app.js 773), which opens the replies panel, as before;
   - `refreshReplyIndicator`, which now removes and replaces the whole `.lime-message__footer` inside that message and inserts it after `.lime-message__reactions`.
4. **Paint the avatars.** Call `paintAvatar` on the new `.lime-avatar[data-name]` elements everywhere an indicator is inserted: the end of `renderThread`, and `refreshReplyIndicator`.
5. **`renderMeta`:** change it to `N replies · last reply {formatLastReply(...)}`.
6. **CSS:** delete the `.lime-message__reply-indicator`, `:hover` and `.dew` rules (~1980–2001) and their comment, now unused. Leave everything else alone.

**Phase 3 — Verification:**
1. `node --check public/js/app.js` passes, and the brace counts in `lime.css` are equal.
2. `grep -rn 'reply-indicator' public/` returns nothing.
3. On msg-003 (Jean's chat), the summary shows painted avatars for each distinct replier, "3 replies" and "Last reply {date}". Send a reply: your avatar comes first, and it reads "4 replies" and "Last reply today at {now}". Clicking the summary opens the panel.
4. Report `formatLastReply` outputs for fake dates: now, earlier today, yesterday, 3 days ago, and 40 days ago.
5. If Chrome isn't available, say so and verify by reading the source.

**Gate:** the user checks in Firefox that the original message shows the avatars, "N replies" and "Last reply today at …", like their Slack reference and the original mockup. If the restored styling needs tuning (the old CSS underlines the count and uses dark text, where Slack uses coloured text without an underline), that's a follow-up brief. Ask them.

**Record:** add a `## LIME-18` entry to `TEND.md`. Commit: `feat: restore reply summary (avatars, count, last reply) on thread messages`, trailer `Brief: LIME-18`, plus the attribution trailer.

---

### LIME-19 → SUPERSEDED (never executed)

Replaced by LIME-19b and 19c (drafted near the top of this section) after the user merged the Teachers and Group Chat tabs.

### LIME-15 → Claude Code, `tend` session

Stop the drawer's logo mark from vanishing on hover on small screens.

**Capability assumptions:** can edit files, run commands and commit. Chrome is optional and only for internal checks.

**What plot read:** `lime.css` lines 349–420 (brand and collapsed-rail hover swap), 1159–1245 (mobile block 1), 3040–3070 (mobile block 2: collapsed-left overrides), and `app.js` 542–603 (`wireHoverPreviewToggle`, the left-panel toggle).

**Root cause (plot's reading; confirm in the survey):**
- On desktop, the collapsed rail swaps the logo mark for the sidebar toggle on hover: `.seed-layout--collapsed-left .lime-sidebar__brand:hover [data-brand-mark] { opacity: 0 }` hides the mark, and the toggle fades in over it.
- At ≤767px, `#left-panel-toggle` is `display: none` (the hamburger lives in the center panel instead). But if `#layout` still carries the stale `seed-layout--collapsed-left` class (persisted in localStorage, the same leftover dealt with in LIME-12-fix2 and fix5), the mark still fades out on hover and nothing replaces it. The user sees an empty gap before the "lime" wordmark.
- The user's intent: on small screens, the logo should stay visible on hover, because the menu toggle already sits to the right.

#### Goal

At ≤767px, hovering the drawer's brand row never hides the logo mark, whether or not `seed-layout--collapsed-left` is present.

#### Scope boundary

- **May touch:** `public/css/lime.css`, only inside the existing `@media (max-width: 767px)` block that holds the `.seed-layout--mobile-open.seed-layout--collapsed-left` overrides (~3040–3070). Also `TEND.md`.
- **May not touch:** desktop hover-swap behaviour, JS, HTML, colours, or the push model.

#### Phase 1 — Survey

1. Confirm the rule `.seed-layout--collapsed-left .lime-sidebar__brand:hover [data-brand-mark]` exists (~393) and is the only rule that zeroes the mark's opacity.
2. Confirm `#left-panel-toggle` is `display: none` at ≤767px (~1179).

#### Phase 2 — The change

Directly after the `.seed-layout--mobile-open.seed-layout--collapsed-left [data-brand-wordmark]` rule (~3060), add:
```css
  /* LIME-15: desktop's collapsed rail swaps the mark for the sidebar
     toggle on hover, but that toggle is display:none at this width (the
     hamburger lives in the center panel), so the swap left an empty gap.
     Keep the mark visible here regardless of the stale collapsed class. */
  .seed-layout--collapsed-left .lime-sidebar__brand:hover [data-brand-mark] {
    opacity: 1 !important;
  }
```

#### Phase 3 — Verification

1. The brace counts `{` and `}` in `lime.css` are equal.
2. If Chrome is available, use the file:// URL, a width ≤767px, the drawer open, and `?collapsedLeft=1` (the LIME-12-fix6 forcing param, if it still exists; otherwise add the class via the console). With the brand hovered (or `:hover` forced in devtools), `[data-brand-mark]` computes `opacity: 1`. At desktop width with the rail collapsed, hovering still swaps the mark for the toggle. If Chrome isn't available, say so and verify by reading the source.
3. `git diff --stat` shows only `lime.css` and `TEND.md`.

#### Gate

The user checks in Firefox at `file:///Users/shem/Sites/lime/public/index.html`:
- **Narrow window with the menu open:** hovering the logo keeps the green circle visible.
- **Wide window with the sidebar collapsed:** hovering the logo still shows the open-sidebar button.

#### Record step

Add a `## LIME-15` entry to `TEND.md` and commit it with the change: `fix: keep logo mark visible on hover in the mobile drawer`, trailer `Brief: LIME-15`, plus the attribution trailer.

---

### LIME-16 → Claude Code, `tend` session (after LIME-15 is committed)

Fix the dark overlay that appears when the drawer is open and the window is widened. Remove the leftover backdrop from the push model entirely.

**Capability assumptions:** the same as LIME-15.

**What plot read:** `app.js` 1070–1108 (mobile nav IIFE) and 542–554 (`wireHoverPreviewToggle`), `index.html` line 38 (`#mobile-nav-backdrop`), `lime.css` 1155–1245, and `vendor/seed/components/layout/layout.css` 640–740.

**Root cause (plot's reading; confirm in the survey):**
- Opening the drawer still adds `is-open` to `#mobile-nav-backdrop` (`applyOpen`, ~1095). This is left over from the overlay design that LIME-12-fix2 replaced.
- At ≤767px, CSS force-hides the backdrop (`display: none !important`), so it's invisible there. Widen past 767px and that rule stops applying: `.lime-mobile-nav-backdrop.is-open { display: block }` wins, and the dark tint covers the app. This is the user's screenshot.
- `seed-layout--mobile-open` also stays on `#layout` at desktop width, where it has no control to close it.

**Latent bug in the same code:** `wireHoverPreviewToggle` keeps its own private `state`. The Escape handler closes the drawer via `applyOpen(false)` without updating that state, so the next hamburger click "toggles" to closed and does nothing. The user has to click twice. The resize fix below would hit the same bug, so fix both through one mechanism.

#### Goal

The push-model drawer has no backdrop anywhere, and it closes itself (with its toggle state kept in sync) when the window widens past the mobile breakpoint or Escape is pressed.

#### Scope boundary

- **May touch:** `public/js/app.js` (the mobile nav IIFE and `wireHoverPreviewToggle`), `public/index.html` (remove only the `#mobile-nav-backdrop` element), `public/css/lime.css` (remove only the `.lime-mobile-nav-backdrop` rules), and `TEND.md`.
- **May not touch:** the search modal's backdrop (`#search-modal-backdrop`; it's separate and correct), Seed's `vendor/` files, the push-model CSS, or the other two `wireHoverPreviewToggle` callers' behaviour.
- Don't touch the 768px vs 767px breakpoint mismatch. It's logged as a separate thread in `PLOT.md`. Mention anything you observe about it.

#### Phase 1 — Survey

1. Reproduce the double-click bug first: at ≤767px, open the drawer, press Escape, then click the hamburger once. Record whether it opens (plot expects it won't).
2. Run `grep -n 'mobile-nav-backdrop' public/`. Expect `index.html` ~38, `app.js` ~1083/1084/1095/1102, and `lime.css` ~1159–1169 and ~1240–1242.
3. Confirm the other `wireHoverPreviewToggle` callers (left panel ~603, and any right-panel caller) ignore its return value.

#### Phase 2 — The change

1. **`wireHoverPreviewToggle`:** at the end of the function, return a setter that syncs its private state:
   ```js
   return {
     set(next) {
       state = next;
       apply(state);
       paint(state);
     },
   };
   ```
   Add one comment line above it saying that external closers (Escape, a breakpoint change) use this so the toggle's next click stays correct.
2. **Mobile nav IIFE:**
   - Remove every `backdrop` reference: the `getElementById`, the guard (it becomes `if (!layout || !toggle) return;`), the `classList.toggle` in `applyOpen`, and the backdrop click listener.
   - Keep `const nav = wireHoverPreviewToggle(...)`.
   - Change the Escape handler to call `nav.set(false)`.
   - Add a breakpoint listener:
     ```js
     const mobileQuery = window.matchMedia('(max-width: 767px)');
     mobileQuery.addEventListener('change', (e) => {
       if (!e.matches) nav.set(false);
     });
     ```
   - Rewrite the IIFE's header comment to describe the push model: no Seed overlay and no backdrop. It closes via the hamburger, Escape, or widening past the breakpoint.
3. **`index.html`:** delete the `#mobile-nav-backdrop` div (~38) only.
4. **`lime.css`:**
   - Delete `.lime-mobile-nav-backdrop` and `.lime-mobile-nav-backdrop.is-open` (~1159–1169).
   - Delete the `display: none !important` backdrop rule and its comment inside the mobile block (~1237–1242).

#### Phase 3 — Verification

1. `grep -rn 'mobile-nav-backdrop' public/` returns nothing.
2. The brace counts `{` and `}` in `lime.css` are equal. `node --check public/js/app.js` passes, if node is available.
3. If Chrome is available (file:// URL):
   - **(a)** ≤767px, open the drawer, press Escape, click the hamburger once: the drawer opens.
   - **(b)** Open the drawer, widen past 767px: `#layout` no longer has `seed-layout--mobile-open`, and there's no dark tint.
   - **(c)** Narrow again: the drawer is closed and one click opens it.
   - **(d)** The search modal still opens with its own backdrop.
   If Chrome isn't available, say so and verify by reading the source.
4. `git diff --stat` shows only `app.js`, `index.html`, `lime.css` and `TEND.md`.

#### Gate

The user checks in Firefox at the file:// URL:
- **Resize:** narrow the window, open the menu, widen the window. There's no dark overlay.
- **Escape:** open the menu, press Escape, click the menu button once. It opens on the first click.
- **Search:** it still opens normally.

#### Record step

Add a `## LIME-16` entry to `TEND.md` and commit it with the change: `fix: remove leftover mobile nav backdrop, close drawer on widen/Escape in sync`, trailer `Brief: LIME-16`, plus the attribution trailer.

### LIME-14 → Claude Code, fresh `tend` session

Make the nav's lime the app-wide "chosen / current" colour, using Seed's own `selected` state family, with stepped default, hover and pressed shades. This removes the one-off `--lime-nav-hover` token.

**Capability assumptions:** can read and edit files, run shell commands, and commit to `main`. Chrome is optional and only for internal DOM checks. The user previews in Firefox only.

**What plot read:** `lime.css` lines 18–30 (the light-theme block), 60–92 (panel dividers), 128–143 (token block), 500–535 (nav buttons), 625–642, 723–760, 1340–1362, 1996–2010, and 2398–2420. Also `vendor/seed/tokens/tokens.css` lines 135–260 and the naming section of `vendor/seed/README.md`.

**Decision already made by the user (2026-09-27), not open for reinterpretation:**
- **Option A:** Lime overrides Seed's `--selected-*` background scale with its lime shades, so everything "chosen" in the app turns lime instead of mint.
- **"Stepped":**
  - resting / current = `--seed-lime-100` (#E4F9BE)
  - hover = `--seed-lime-200` (#C8F09A)
  - pressed = `--seed-lime-300` (#A3E18A)

**Plot's interpretation of "stepped", flagged at the gate:** hovering a *non-current* nav row shows the resting lime, exactly as it does today. Hovering the *current* row deepens it to hover. Pressing anything shows pressed. This keeps the nav looking as it does at rest and adds feedback. If the user rejects it at the gate, the alternative is that every hover goes to #C8F09A.

#### Goal

Anything chosen or current in Lime uses one lime family with default, hover and pressed steps, all through Seed-named tokens. No component references `--lime-nav-hover` or raw `--seed-lime-*` directly.

#### Scope boundary

- **May touch:** `public/css/lime.css`, and `TEND.md` for the record step.
- **May not touch:** `vendor/` (Seed stays stock), the dark theme, `--selected-*` text, icon, bold or disabled tokens, `--lime-badge-light` (the "Soon" badge), `--calm-*` hover usages, any JS or HTML, or anything on the mobile nav's push/overlay model.
- Disabled, focus and error states are later briefs. Don't start them here. If the survey turns up related issues, raise them before proceeding. If anything here doesn't match what you find, stop and ask **the user**.

#### Phase 1 — Survey (read-only)

1. Run `grep -n 'lime-nav-hover' public/css/lime.css`. Expect 1 definition (~line 142), comment mentions (~lines 67 and 70), and 7 uses (~84, 526, 531, 759, 1355, 2406, 2410). If the list differs, stop and ask.
2. Run `grep -n 'var(--seed-lime-' public/css/lime.css`. Expect ~90 and ~1360 (divider dragging) plus the two token definitions at ~135 and ~142.
3. Run `grep -n 'var(--selected-' public/css/lime.css`. Expect ~12 uses. Note which ones use `bg-subtle` or `border-subtle`: those will change colour, and the gate checks them.

#### Phase 2 — The change

**1. Retune Seed's selected scale, light theme only.** In the existing `[data-theme="light"]` block near the top of `lime.css` (~line 20), after the two `--soil-bg-*` lines, add:
```css
  /* Lime's "chosen / current" colour (LIME-14): Seed's own --selected-*
     family, retuned from Seed's mint to the lime the nav has always used.
     Stepped per Seed's flower convention: resting, hover, pressed. */
  --selected-bg-subtle-default: var(--seed-lime-100);
  --selected-bg-subtle-hover:   var(--seed-lime-200);
  --selected-bg-subtle-active:  var(--seed-lime-300);
  --selected-border-subtle-default: var(--seed-lime-300);
```
**Amendment (2026-09-27, raised mid-execution by tend):** the stock text colour (lime-600) on lime-100 measured 4.46:1, just below the 4.5:1 minimum for text. Also retune text and icon in the same block, and remove them from the "may not touch" list:
```css
  --selected-text-normal-default: var(--seed-lime-700);
  --selected-icon-normal-default: var(--seed-lime-600);
```
Plot's computed ratios:
- lime-700 text: ≈7.2:1 on lime-100, ≈6.3:1 on lime-200, ≈5.3:1 on lime-300.
- lime-600 icon: ≈4.4:1 on lime-100. Icons need 3:1. The old lime-500 icon was ≈2.7:1, which already failed, and failed on mint too.

The border is retuned too because Seed's mint border (`--seed-lime-45`) around a lime-100 chip would be the one mint thing left (the reaction chips at ~2003).

**2. Remove `--lime-nav-hover`.** Delete its definition (~142) and the 6-line comment directly above it. Leave `--lime-badge-light` and its own comment alone. In the panel-divider comment (~64–74), replace the references to `--lime-nav-hover` with `--selected-bg-subtle-*`. Keep the comment's reasoning, and rewrite only as much as needed to stay accurate.

**3. Repoint every consumer:**

| Where (approx. line) | Selector | New value |
|---|---|---|
| ~84 | divider handles `:hover::after` | `var(--selected-bg-subtle-hover)` |
| ~90 | divider handles `.is-dragging::after` | `var(--selected-bg-subtle-active)` |
| ~1355 | `.lime-center-handle:hover::after` | `var(--selected-bg-subtle-hover)` |
| ~1360 | `.lime-center-handle.is-dragging::after` | `var(--selected-bg-subtle-active)` |
| ~526 | `.lime-nav__btn:hover` | `var(--selected-bg-subtle-default)` |
| ~531 | `.lime-nav__btn--active` | `var(--selected-bg-subtle-default)` |
| ~759 | `.lime-sidebar__user-trigger:hover` | `var(--selected-bg-subtle-default)` |
| ~2406 | `.lime-composer__return.is-active` | `var(--selected-bg-subtle-default)` |
| ~2410 | `.lime-composer__return.is-active:hover` | `var(--selected-bg-subtle-hover)` |

The dividers go from lime-100 to lime-200 on hover. That's intended: an earlier session noted the pale shade barely read on a 1px line.

**4. Add the new hover and pressed steps.** Source order matters, because the pressed rule must come *after* the hover rules it shares specificity with.
- Directly after `.lime-nav__btn--active` (~531–533), add:
  ```css
  .lime-nav__btn--active:hover {
    background: var(--selected-bg-subtle-hover);
  }

  .lime-nav__btn:active {
    background: var(--selected-bg-subtle-active);
  }
  ```
- Directly after `.lime-sidebar__user-trigger:hover`, add `.lime-sidebar__user-trigger:active { background: var(--selected-bg-subtle-active); }`.
- Directly after `.lime-composer__return.is-active:hover`, add `.lime-composer__return.is-active:active { background: var(--selected-bg-subtle-active); }`.

**5. Update the Send comment** in `.lime-composer__return.is-active` (it currently says active and hover share one colour) to:
```css
  /* Seed's --selected-* scale, same as the nav (LIME-14): resting,
     deeper on hover, deeper again while pressed. */
```

#### Phase 3 — Verification

Report these facts, not raw output:
1. `grep -c 'lime-nav-hover' public/css/lime.css` returns 0.
2. `grep -n 'var(--seed-lime-' public/css/lime.css` matches only token definitions (`--lime-badge-light` and the four new `--selected-*` lines), never a component property.
3. The brace counts `{` and `}` in `lime.css` are equal.
4. **Contrast:** `--selected-text-normal-default` (#078040) on #E4F9BE is roughly 4.5:1 or better (used by the voice-device dropdown's active item at ~634). Report the computed ratio. If it's below 4.5, stop and ask the user.
5. If Chrome is available, open `file:///Users/shem/Sites/lime/public/index.html` (**not** a localhost server started inside `public/`, which 404s Seed's CSS; see Patterns). Check that the current nav row computes `rgb(228, 249, 190)` at rest and `rgb(200, 240, 154)` on hover. If Chrome isn't available, say so and state that the values were checked by reading the source.
6. `git diff --stat` shows only `public/css/lime.css` and `TEND.md`.

#### Gate

Yes, a human looks before this counts as done. Point the user to **`file:///Users/shem/Sites/lime/public/index.html` in Firefox**. Ask them to check, in plain terms:
- **Nav:** looks the same at rest. Hovering the current item makes it a bit deeper, and clicking any item flashes deeper still.
- **Send:** the arrow button is lime once you type, deeper on hover.
- **Reactions:** your own reaction chips under messages are now lime instead of mint.
- **Voice mode:** the chosen microphone in the device list is now lime.
- **Dividers:** the lines between panels show a slightly stronger lime on hover.
- Ask whether "hovering a non-current nav row shows the resting lime" is what they meant by stepped.

#### Record step

Add a `## LIME-14` entry to `TEND.md`: what was retuned, every consumer repointed, the contrast ratio, and how it was verified. Commit `lime.css` and `TEND.md` together:
```
feat: lime becomes the system "selected" colour with stepped states

Brief: LIME-14
```
followed by the attribution trailer the session requires.

---

### LIME-13 → Claude Code (SENT, landed as cd39519, gate passed)

QA and commit the user's hand-made visual CSS edits: fix the three places those edits break things, then commit edits and fixes together.

**Capability assumptions:** can read and edit files, run shell commands, open Chrome for internal DOM checks only (preview in Firefox only, per the user's standing rule), and commit to `main`.

**What plot read:** `git diff public/css/lime.css` (uncommitted, made by the user by hand), `lime.css` around lines 430–540, 715–770, 2380–2420, 2560–2585, 3055–3085, and the sidebar markup in `public/index.html` (lines 61–128).

**What plot assumed:** the user's edits are intentional design. They made `.lime-sidebar__user-trigger` a copy of `.lime-nav__btn`, wrapped the footer in the same inset as `.lime-nav`, dropped the search button's extra bottom margin (`.lime-nav`'s 24px gap already spaces it), and moved the Send button's active and hover states to `--lime-nav-hover`. None of that is to be reverted or restyled.

#### Goal

The user's visual edits are committed, and they don't break (a) the Send button's text clearance, (b) the desktop collapsed rail, or (c) the mobile drawer.

#### Scope boundary

- **May touch:** `public/css/lime.css` only, and only the rules named below. Also `TEND.md` for the record step.
- **May not touch:** any other hunk of the user's edits, `index.html`, JS, `vendor/`, or `README.md`. Nothing on the mobile nav's push/overlay model.
- If the survey turns up related issues, raise them before proceeding. If something here doesn't match what you find, stop and ask **the user**, not plot.

#### Phase 1 — Survey (read-only)

1. Run `git diff --stat public/css/lime.css` and confirm the uncommitted diff is still roughly +17/−11 in the same four areas: `.lime-nav-search` margin, `.lime-sidebar__footer`/`__user-trigger`, `.lime-composer__return`, and `textarea.lime-composer__input` padding. If it has grown, stop and ask the user what changed.
2. Confirm each of the three problems below exists as described.

#### Phase 2 — The change

**Fix 1: typed text runs under Send (real bug).**
In `textarea.lime-composer__input`, the user added `padding-left` and `padding-right` longhands after the shorthand. The `padding-right: var(--seed-space-2)` line overrides the shorthand's 40px, which exists to reserve room for the absolutely positioned Send button (`.lime-composer__return`). Keep the user's 8px left inset and restore the 40px right.

Find:
```css
  padding: var(--seed-space-1) 40px var(--seed-space-1) 0; /* right: reserves room for the corner-anchored Send button so typed text doesn't render under it */
  padding-left: var(--seed-space-2);
  padding-right: var(--seed-space-2);
```
Replace with:
```css
  padding: var(--seed-space-1) 40px var(--seed-space-1) var(--seed-space-2); /* right: reserves room for the corner-anchored Send button so typed text doesn't render under it */
```

**Fix 2: the collapsed desktop rail's user trigger is misaligned with the nav icons.**
The trigger now takes 12px horizontal inset from the new footer padding. In the 56px rail that leaves it 32px wide, while the nav buttons above it are 40×40 inside an 8px inset (`.seed-layout--collapsed-left .lime-nav` and `.lime-nav__btn`). Also, the existing collapsed rule's `padding: var(--seed-space-3) 0` now sits inside a fixed 40px height, leaving 16px of content box for a 24px avatar. Mirror the nav's collapsed treatment.

Find:
```css
.seed-layout--collapsed-left .lime-sidebar__user-trigger {
  padding: var(--seed-space-3) 0;
  justify-content: center;
}
```
Replace with:
```css
.seed-layout--collapsed-left .lime-sidebar__footer {
  padding: var(--seed-space-2);
}

.seed-layout--collapsed-left .lime-sidebar__user-trigger {
  width: 40px;
  padding: 0;
  justify-content: center;
}
```

**Fix 3: the mobile drawer override still restores the old trigger padding.**
Inside the mobile media query, the LIME-12-fix5 override restores the trigger to the *old* base padding. It also now has to undo Fix 2's rail width and footer padding.

Find (indentation as in the file):
```css
  .seed-layout--mobile-open.seed-layout--collapsed-left .lime-sidebar__user-trigger {
    padding: var(--seed-space-3) var(--seed-space-4) !important;
    justify-content: flex-start !important;
  }
```
Replace with:
```css
  .seed-layout--mobile-open.seed-layout--collapsed-left .lime-sidebar__footer {
    padding: var(--seed-space-2) var(--seed-space-3) !important;
  }

  .seed-layout--mobile-open.seed-layout--collapsed-left .lime-sidebar__user-trigger {
    width: 100% !important;
    padding: 0 var(--seed-space-3) !important;
    justify-content: flex-start !important;
  }
```

**Fix 4: stale comment (text only, no behaviour change).**
In `.lime-composer__return.is-active`, the comment still explains the old `--calm-bg-subtle-default` choice. Replace the three comment lines with:
```css
  /* Same token as .lime-nav__btn's hover/active state — active and
     hover deliberately share one colour, matching the nav convention. */
```
Do **not** delete the `.lime-composer__return.is-active:hover` rule, even though it now repeats the same value. Without it, `.lime-composer__return:hover` (same specificity, later in the source) would turn an active Send button grey on hover.

#### Phase 3 — Verification

Use Chrome only as an internal diagnostic. Remove any temporary diagnostic script afterwards and confirm `git diff public/index.html` is empty. Report these facts, not raw output:

1. **Send clearance:** the composer textarea's computed `padding-right` is `40px` and `padding-left` is `8px`, for both `#composer` and `#replies-composer`. Type a long single line: the text must not render under the Send button.
2. **Desktop expanded:** the user trigger measures 40px tall and has the same left edge (±1px) as the `.lime-nav__btn` rows above it. On hover its background is `--lime-nav-hover`.
3. **Desktop collapsed rail** (`seed-layout--collapsed-left`): the user trigger measures 40×40 and its horizontal centre matches the nav buttons' centre (±1px). The avatar is not clipped.
4. **Mobile drawer with a stale collapsed class** (`?collapsedLeft=1`, as in LIME-12-fix6, drawer open): the user trigger is full width with the name visible (`display: block`), and its left edge matches the nav rows' left edge (±1px). Mobile drawer without the stale class: same result.
5. **Send states:** Send's background is `--lime-nav-hover` when active and unchanged on hover. When inactive and hovered, it's still `--calm-bg-subtle-hover`.
6. `git diff --stat` shows only `public/css/lime.css` and `TEND.md`.

#### Gate

Yes, a human looks before this counts as done. Open the result in **Firefox** for the user to check (a) that the sidebar footer and user row still look the way they designed them on desktop, and (b) the collapsed rail and the mobile drawer footer. Their own edits must look unchanged. Only the rail and drawer alignment should differ.

#### Record step

Add a `## LIME-13` entry to `TEND.md` describing the user's hand-made edits (as the user's) and the four fixes, plus the verification measurements. Commit everything (the user's edits, the fixes, and `TEND.md`) in one commit:

```
fix: QA pass on manual sidebar/composer style edits

Brief: LIME-13
```
followed by the attribution trailer the session requires.
