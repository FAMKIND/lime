# PLOT.md

Planning state for Lime. Written only by `plot` sessions. `TEND.md` is the execution record.

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
  - `PLOT.md` is still untracked. Gather it at the next clean pause. Its gate feedback led to 18-fix5: vertical alignment of the two composers and the right-panel gutter.
- **Minor, not urgent:** 18-fix3 swaps the reply disclaimer text in JS at load instead of just changing the words in `index.html`. It works but is roundabout. Fold it into a later cleanup.
- LIME-17, 18 and 19 were drafted from the user's thread and chat-list QA. **LIME-19 is ON HOLD, don't send it:** it will be redrafted to be conversation-based once the tab-merge decision below lands.

## Open thread: merge the Teachers and Group Chat tabs (raised 2026-09-27)

- **The user's proposal:** two tabs instead of three. Teachers (1:1 and group chats together) and Community.
- **Plot agrees.** Proposed rule: first tab = "conversations I'm in" (private, invite-only, small: DMs, ad-hoc groups, named teams); Community = "spaces I've joined" (open or joinable, topic-based, many members).
- **Waiting on the user:** (1) whether that rule matches their view; (2) the first tab's name ("Teachers" vs "Messages"/"Chats"; plot leans slightly to "Messages").
- **Leans for the redraft:**
  - group rows get a stacked two-avatar mark, the group name (or "Jean, Mary & Jimin" if unnamed), and a sender-prefixed preview ("Jean: …");
  - sections become Recent / Starred / All, and groups can be starred.
- **Survey facts:**
  - The seed data has 5 group conversations (3 include teacher-002), e.g. "PS 113 7th Grade Team", "Math Teachers NYC", and "Jean, Mary, Jimin & Me" (ad-hoc). It also has 9 community conversations (3 include teacher-002).
  - `index.html`'s Group Chat panel (~332) and Community panel (~390) are **static mockups** whose names ("Grade Three", "Staff Lounge", "FAM Wide"…) don't match the seed data.
  - Tabs: `data-scope="teachers|groups|communities"` (~182–184). The scope filter lives in app.js ~1003.
- **Redrafted LIME-19** (conversation-based rows, not teacher-based) should cover: DMs and groups in one live, recency-sorted list; a data-driven Starred section; and removing the Group Chat tab. Community going live is a separate later brief.

## Open threads

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
- **Upstream to Seed (Seed's owner is FAM, the same person as the user):** `.seed-dropdown__item` is `width: 100%` plus padding with no `box-sizing: border-box`, so it overflows its menu. Lime works around it in LIME-21. Also candidates: the lime `selected` scale (LIME-14), and whether Seed should ship a global border-box reset.
- **The 768px breakpoint doesn't match.** Seed's layout.css mobile rules use `max-width: 768px` and Lime's use `max-width: 767px`. At exactly 768px wide, Seed hides the left panel (`display: none`) and Lime's hamburger isn't shown, so there's probably no way to reach the nav at that single width. It isn't reported yet. Candidate small brief: align Lime's queries to 768px, or override Seed's. Verify live first.
- **Briefs keep re-proposing overlays.** An overlay/backdrop version of the mobile nav was proposed three times against the settled push model (LIME-12-fix2/3/4/6). The decision is now logged in `README.md` → "Decisions (2026-09-23)". Any brief touching the mobile nav must be checked against it.
- **`STATUS.md` is stale.** It still says only "Link screen renders". It needs a refresh brief at some point. Low priority.
- **Unverified live:** the 20px sidebar width gap (LIME-12-fix2) and the ≤480px placeholder trigger (LIME-12-fix4). Both are minor.

## Patterns learned

- **Previewing:** `index.html` loads Seed via `../vendor/...`, so it must be served from the repo root or opened as a `file://` URL. A server started inside `public/` (as the LIME-13 tend session did, with `python -m http.server 8756`) returns 404 for all Seed CSS, and the page renders unstyled. Every brief's gate should give the preview URL as `file:///Users/shem/Sites/lime/public/index.html`, or as `localhost:<port>/public/index.html` with the server started from the repo root.
- **Pixel alignment must be measured, not computed.** LIME-18-fix2 and fix5 both computed positions from CSS "by arithmetic" and got the premise wrong (fix5 assumed Seed's panel padding, which `lime.css` zeroes). Without the Chrome extension, use headless Chrome (`/Applications/Google Chrome.app`, `--headless=new --dump-dom` plus a temporary diagnostic script that's removed afterwards). Every alignment brief must require this.
- **JS verification must load the real app.** `node --check` and testing extracted functions missed LIME-18's load-order crash, which froze every click in the app. Every brief that touches JS must require that `seed-data.js`, `data.js` and `app.js` are loaded as real scripts against the real `index.html` (jsdom in the session scratchpad, not the repo, when Chrome isn't connected), with zero errors reported. Tend adopted this from LIME-18-fix onward.
- **Handoff:** every brief handoff ends with a copy-paste prompt for tend, e.g. `tend LIME-14`. Tend reads the full brief from this file, so the brief must be saved here before handing off.
- The user isn't technical. Explain decisions in plain terms: what the user will see, not selector mechanics.
- The user makes visual CSS edits by hand, then asks plot to review them and tend to QA them. Treat those edits as design intent. Fix only what breaks behaviour or consistency, and don't restyle.
- The `seed-layout--collapsed-left` class can persist into mobile views through `localStorage`. Any change to a sidebar row's base styling must also be checked in (a) the desktop collapsed rail and (b) the `.seed-layout--mobile-open.seed-layout--collapsed-left` `!important` overrides in `lime.css`'s mobile media query.

---

## Drafted briefs

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

### LIME-19 → `tend`: live chat list (after LIME-18)

**User decisions (2026-09-27):**
- Chats with the newest activity move to the top.
- The "Starred" section becomes real (data-driven), with the same 3 people starred. Adding or removing stars stays out of scope.

**Goal:** both "Starred" and "All Teachers" show each chat's true latest activity (message **or** reply) with its preview and time, sorted newest first, and update immediately when you send a message or reply.

**Scope:**
- **May touch:** `public/js/app.js` (the contact-list code inside the first IIFE, `handleSend`, `submitReply`), `public/js/data.js`, `public/index.html` (replace only the 3 static Starred `<li>`s with an empty `<ul id="starred-list">`), `public/css/lime.css` (one chevron rule), and `TEND.md`.
- **May not touch:** the "Recent" avatar row (still static), Group Chat and Community lists, unread-count logic, or star/unstar UI.

**Plot's design choices, flagged at the gate:**
- **Unread badges:** the "2" badges are fake, and no unread data exists. They're removed, not faked. Real unread counts would be their own feature.
- **Starred people with no conversation yet:** Valene Rajoon and Mary Lee have no direct conversation with the current user in the seed data. Their rows show "No messages yet" and no time, and they sort below chats with activity. Clicking one opens an empty thread you can message into. That's done by `getOrCreateDirectConversation(teacherId)` in `data.js`: it returns the existing direct conversation, or pushes a new in-memory one (`id: 'conv-new-' + teacherId`, `type: 'direct'`, participants `[CURRENT_USER_ID, teacherId]`, `created_at`/`updated_at` now). The list shows this as a new chat; no seed data changes.
- **Preview of a reply:** a reply's text is the preview, the same as a normal message.

**Phase 1 — Survey:**
1. Confirm LIME-17 and LIME-18 have landed.
2. **Important listener constraint:** `app.js` binds click listeners **once at load** to every `.lime-contact` (~1065, the recent-item highlight; ~1129, mobile `setView('thread')`). Rows must therefore be **created once at init**, before those lines run (the list IIFE already runs earlier in the file; confirm), and afterwards only **updated in place and reordered by moving the existing nodes** (`appendChild`/`insertBefore`). Never re-create them, or mobile navigation silently breaks. Confirm the line order.
3. Confirm the local search filter (~1010) works on `[data-search-text]`, so rows keep that attribute.
4. If anything doesn't match, stop and ask **the user**.

**Phase 2 — The change:**
1. **`data.js`:**
   - Add `getOrCreateDirectConversation(teacherId)`, as described above.
   - Add `getLatestActivity(conversationId)`: the last item of `getMessagesByConversation` (which includes replies), or `null`.
2. **`app.js` list code:**
   - Factor the row markup into one `contactRowHtml(teacher)`. Its preview is `previewFor(latest)` or "No messages yet", and its time is `formatTime(latest.created_at)` or empty. Include `<span class="dew dew-chevron-right lime-contact__chevron"></span>` in every row.
   - Each row carries `data-teacher-id` and `data-conversation-id` (when a conversation exists) plus `data-search-text`.
   - Add a hard-coded `STARRED_TEACHER_IDS = ['teacher-001', 'teacher-003', 'teacher-004']` with a comment: star/unstar isn't built yet.
   - Render the Starred rows into `#starred-list` and the existing direct conversations into `#contacts-list`, both at init. Clicking a row calls `selectConversation(getOrCreateDirectConversation(teacherId), teacher)`, then sets the row's `data-conversation-id` if it was missing.
   - Add `refreshContactRows(conversationId)`. It updates the preview and time in place for **every** row of that conversation (Jean appears in both sections), then re-sorts each list by moving existing nodes: newest first, no-activity rows last in name order.
   - Call `refreshContactRows` after `sendMessage` in `handleSend` and after `sendReply` in `submitReply`.
   - `selectConversation` marks `lime-contact--active` on every matching row in **both** lists, matched by `data-teacher-id`, and clears it from all the others.
   - Re-apply the contact preview truncation treatment (~app.js 345) to updated previews, if it depends on a one-time pass. Survey how it works first.
3. **`index.html`:** replace the three static Starred `<li>`s with `<ul class="lime-contact-list" id="starred-list"></ul>`. Add an HTML comment like the one on `#contacts-list`.
4. **`lime.css`:** add `.lime-contact:not(.lime-contact--active) .lime-contact__chevron { display: none; }` after the `.lime-contact__chevron` rule (~1669), so the chevron shows only on the active row.

**Phase 3 — Verification:**
1. `node --check` passes on both JS files. The brace counts in `lime.css` are equal.
2. On load: Starred shows Jean (real latest preview and time), then Valene and Mary with "No messages yet". There are no "2" badges. All Teachers is sorted newest first.
3. Send a message to Alexi: Alexi's row jumps to the top of All Teachers, showing your text and the current time.
4. Reply in Jean's thread: Jean's rows in **both** sections show the reply text and time.
5. Click Valene: an empty thread opens. Send a message: Valene's row shows it and moves above Mary.
6. The local search still filters the rows. On mobile width, tapping a row still switches to the thread view (that tests the listener constraint).
7. If Chrome isn't available, say so and verify by reading the source.

**Gate:** the user checks in Firefox:
- **Sending:** send a message and a reply, and the chat list updates and reorders straight away.
- **Starred:** shows real previews.
- **Two choices to confirm:** the fake "2" badges are gone, and Valene and Mary show "No messages yet".

**Record:** add a `## LIME-19` entry to `TEND.md`. Commit: `feat: live, recency-sorted chat list with data-driven Starred section`, trailer `Brief: LIME-19`, plus the attribution trailer.

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
