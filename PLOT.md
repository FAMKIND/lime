# PLOT.md

Planning state for Lime. Written only by `plot` sessions. `TEND.md` is the execution record.

## ▶ START HERE: session-end note (plot, 2026-09-29, written at "end")

**The next plot session (`rtb`) reads this first.** The history below it is kept for reference. Anything above the "Continuation note (2026-09-27)" heading supersedes older queue lines.

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
8. **LIME-28 Communities: BLOCKED on a planning pass.** Present a **decision surface** from the user's mockups (the discovery cards, the feed of posts with likes, community pages with channels) before briefing.

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
- **Landed (2026-09-30):** LIME-48-fix2 `c88bcfc` (the new video); **LIME-56 `c7f5009`** (Warm surface `#f0eee6`, Sage greyer, Add/Send ink now a theme-aware token; a dark-mode 1.03:1 regression was caught and fixed). **LIME-57 Phase 1:** the preview is done and `lime-silhouette.svg` is extracted (untracked). Plot looked at it: the nub reads as a **speech-bubble tail** at 40px and up (a nice fit for a messaging app), and it's barely visible at 28–32px, where it's harmless. Plot's lean is to keep 28px. **The user confirmed 28px. Landed (2026-09-30):** LIME-57 `5a17cbb` (no 28–31px avatars exist, so in practice md/lg/xl = 32/40/56px are shaped and sm/xs stay round; `border-radius: 0` is needed, or the circle clip eats the nub; the unread ring is now a `.lime-avatar-ring` wrapper, because box-shadow on a masked element is invisible), LIME-58 `f578558`, LIME-59 `6db2847` (a hand-drawn Share SVG; bubbles = list hover through one token). **The user's gate checks on 56–59 are pending.** `Logomark-outline.svg` and `signin-teachers.mp4` are still untracked. Ask whether to commit the logomark as a brand asset. **The user's check found the Recent row's presence dots clipped** (the ring wrapper is an always-masked ancestor), so LIME-57-fix was drafted. The user then asked for Slack-style status icons in a cut-out notch, so **LIME-57-fixb (which supersedes it) runs next.** Then: the Communities decision surface.
- **New finding (tend, LIME-56): white text on the solid green `#09a950` buttons** (e.g. "Continue with email", Seed's `seed-button--primary`) is **under 4.5:1 on every tone** (white on `#09a950` ≈ 3.1:1, computed). It's a brand-level decision. Options put to the user: **A.** ink text `#131b17` on `#09a950` (≈ 5.7:1, computed; keeps the brand green); **B.** darker green `#078040` (`--seed-lime-600`) with white text (≈ 5.0:1, computed); **C.** leave it (large or bold text only needs 3:1, and a 16px semibold button label doesn't qualify). Plot's lean: **A.** Upstream candidate for Seed too. **DECIDED: A (the user, 2026-09-30) → LIME-58 drafted.** Its hover and press go lighter (lime-400/300), because ink on the darker lime-600 is only ≈ 3.5:1.

### Unbriefed candidates (offer when the queue thins)
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
- **CSS masks clip every descendant** (LIME-57): a masked wrapper hides child badges and dots, and box-shadows on masked elements vanish. Any mask brief must verify that no indicator sits inside a masked **ancestor**, with element screenshots of each indicator.
- **Debounced saves lose data on navigation** (LIME-33, LIME-29): `scheduleSave()` waits 100ms, and a sign-out, redirect or reload inside that window drops the write. Only the real Firefox and Chrome caught it. Any brief that writes and then navigates must flush first (`LimeStore.flush()`); a `pagehide` flush is the general fix (folded into LIME-27).
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
