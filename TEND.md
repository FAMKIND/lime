# TEND.md

Record of work landed via the `tend` skill.

## LIME-03a — Sidebar Polish

- Logo: replaced the inline-JS SVG brand system (`LIME_MARK`/`LIME_WORDMARK` strings in `app.js`, broadcast via `innerHTML`) with static files loaded through `<img>`: `public/assets/logo-mark.svg` (plain lime-green circle) and `public/assets/logo-wordmark.svg` ("lime" text, fill baked in since `<img>` content can't take `currentColor`). Deleted the redundant unused `lime-mark.svg`/`lime-wordmark.svg` pair that predated this brief.
- Nav order (Search → Notifications → gap → Link → Jam) already matched the brief; added a red "3" badge (reusing `seed-badge--bad seed-badge--sm`, repositioned via `.lime-nav__badge`) to the notifications bell.
- Icon sizing: nav search icon was 14px, nav buttons were 20px — normalized both to 20px.
- Collapsed-rail toggle: hidden by default (`opacity:0; pointer-events:none`) and revealed on `:hover` of `.lime-sidebar__top`, mirroring Claude's sidebar. Used opacity/pointer-events rather than `display` so the existing hover-preview icon swap in `app.js` (`wireHoverPreviewToggle`) kept working with no JS changes.

Deviation from literal brief text: the brief's placeholder mark request ("simple lime-colored circle") is visually simpler than the sunburst-ray mark it replaced — flagged to the user at the gate; no objection raised before the next brief arrived, taken as approval.

## LIME-03b — Search Field + Avatar Status

- Center panel search field (`.lime-search-field .seed-input`): fixed height to 36px (`box-sizing: border-box` + `line-height: 36px`) to match the nav search button. Focus state now overrides `box-shadow: none` and uses `border-color: var(--soil-border)` instead of Seed's base `--seed-shadow-focus` green glow. Added a `:hover` rule (`--calm-bg-normal-hover`) to match the nav search's hover feedback, which the field previously lacked.
- Avatar status: asked the user whether to switch the presence cutout to a true CSS `mask`/`clip-path` technique or keep the existing box-shadow-ring illusion (documented in `lime.css` as a deliberate choice to avoid inconsistent transparency across the app's varying row backgrounds). User chose to keep the box-shadow technique.
- Fixed a real bug found during survey: DND was reusing Away's gray hollow-ring styling almost verbatim (plus a stray "z"), not resembling Busy at all. Changed DND to Busy's solid-fill pattern with `--bad-bg-bold-default` (red) and a knocked-out "–" glyph instead of "z" — the dash was an unspecified choice since the brief didn't say what DND's icon should be; flagged at the gate, no objection.

## LIME-03c — Recent Teachers + Contact List

- Expanded the recent row from 4 to 8 people, adding Nina Park, David Kim, Rosa Martinez, Chris Wong as specified.
- Story rings (`.lime-avatar-frame--story-unseen`/`--story-seen`): implemented as a same-shaped circle sitting behind the avatar at `z-index: -1` with `inset: -3px`, so the opaque avatar disc covers its center and only the outer band shows — no mask needed, works on any background. Distributed unseen/seen/none across the 8 people myself (brief named the 4 new people but not which ring state each gets); flagged at the gate, no objection.
- Fixed the three bare "11:30" contact-list times (Valene Rajoon, Mary Lee, Alexi Daily) to "11:30 PM". Left weekday abbreviations ("Sat", "Mon", etc.) and the conversation pane's own timestamps untouched — brief's example list only forbids bare clock times, and its title scopes this brief to the recent row + contact list, not the message thread.
- `.lime-contact--active` now uses the same background token as `:hover` (`--calm-bg-subtle-hover`) instead of a separate `--calm-bg-subtle-default`, so Jean Chung's default-selected row reads as already-hovered on load, per the brief.
- Horizontal scroll + hidden scrollbar on the recent row already existed before this brief (hover-to-reveal thin thumb) — no change needed there.

## LIME-03d — Chat Thread + Floating Composer

- Removed Valene Rajoon's and Alexi Daily's standalone messages from Jean's 1:1 thread, keeping Jean's "4 Replies" footer (and its avatar stack, which still references Mary Lee/Valene as repliers) per "keep reply indicators."
- Scope note: also removed Shem's "Works for me — I'll send the updated date to the group tonight" message, which the brief didn't name — it was a direct reply to Valene's deleted question and would've read as a non-sequitur left in place. Flagged at the gate, no objection.
- Floating composer (absolute-positioned, messages scroll underneath, bottom fade gradient) already existed before this brief — no changes needed.
- Added the top-of-thread fade gradient (`.lime-chat-body::before`), matching the same pinned-overlay convention already used for the composer's fade and the contact list's bottom fade (`.lime-list-col::after`) — kept the app internally consistent rather than inventing a new gradient style, which is what "match seed panel gradient style" was read to mean (Seed's own layout.css has no gradient/fade utility of its own to match).
- Map placeholder: added a centered inline SVG map-pin (teardrop with a punched hole matching the gray background) inside `.lime-message__map`. No pin icon exists in the vendored `dew` icon set (53 icons, none location-related) and there's no real maps integration, so a hand-drawn pin was the closest fit to the brief's two offered options.

## LIME-03e — Reply Thread Panel

- Added `.lime-replies-panel` as a sibling of `.lime-profile-panel` inside `#right-panel`, toggled purely via `#right-panel[data-panel]` ("profile" | "replies") — no inline styles set from JS, CSS reads the attribute.
- "4 Replies" (`#open-replies`) forces the right panel open (reusing the existing `seed-layout--right-hidden` toggle) then flips `data-panel` to "replies"; `#replies-back` flips it back to "profile".
- Chose "replaces" over "overlays" for the profile panel (brief offered either) — matches the brief's own single-panel ASCII diagram.
- Reply panel content (quoted original message, 4 mock replies from Mary Lee/Valene Rajoon/Shem R×2, a separate non-functional reply composer) is invented placeholder copy — the brief specified structure, not content.

## LIME-03f — Mobile-First Responsive

- Asked the user how mobile should handle viewing a teacher's profile, since the brief only named Contacts/Thread/Reply-panel as mobile views. Decision: profile and replies share one "panel" mobile screen (the existing right-sidebar region from LIME-03e), rather than inventing a 4th named view.
- `#layout[data-mobile-view]` ("contacts"|"thread"|"panel") is the single source of truth for which full-width region shows below 768px; JS only ever sets the attribute, CSS reads it. Existing triggers (contact rows, `open-profile-name`/`open-profile-avatars`/`open-replies`) got an *additional* listener layered on top of their existing LIME-03e behavior, rather than being rewritten.
- Reused Seed's own dormant `.seed-layout--mobile-open` overlay mechanism (already fully built in vendored `layout.css`, just never wired up) for the hamburger nav drawer, instead of building a parallel system. Added the hamburger trigger + a click-outside/Esc backdrop, which Seed's mechanism doesn't itself provide.
- Found and had to work around a real ordering bug: `.lime-list-col`/`.lime-conversation` have unconditional width/display rules elsewhere in the file at equal specificity to my new mobile overrides — moved the whole mobile media-query block to the end of the file so it reliably wins in the cascade, rather than reaching for `!important` everywhere.
- Auto-collapse (right panel + sidebar) is scoped to *crossing down through 1024px only*, as a one-shot nudge — doesn't attempt every possible resize path (e.g. growing from mobile back into tablet doesn't force a re-collapse). Flagged as a bounded-scope choice for this prototype, not full robustness.
- "Toolbar icons shift left with center panel" and "sidebar icons align to panel edge" were concluded to already happen for free via the existing CSS Grid reflow — no new code added for these; flagged as unverified-by-new-code at the gate.
- Hid the desktop collapse-to-rail sidebar toggle while the mobile drawer is open (collapsing to a rail inside a fixed-width overlay would look broken) — inferred fix, not explicitly requested.

## LIME-03g — Mobile Polish

- Local search + breadcrumbs both now hidden ≥768px, shown only on mobile — same media query, since desktop/tablet use the nav sidebar's global search and don't need a "where am I" trail (both panels already visible).
- Rebuilt the breadcrumb as 3 fixed segments (Teachers/Jean Chung/Bio) with CSS `[data-mobile-view]` attribute selectors toggling visibility + which one gets the "current location" bold treatment — chose this over the brief's suggested "JS rewrites the text" approach, since it's the same attribute-driven pattern already established for the contacts/thread/panel views in LIME-03f, and avoids a second, redundant way of expressing the same state.
- **Behavior change**: removed "Link" entirely and renamed `#open-profile-name` → `#crumb-thread`. This breadcrumb segment used to double as an "open profile panel" trigger (since LIME-03e); the brief's table redefines "Jean Chung" to mean "go to thread" instead, so that old wiring was removed — profile/replies access on mobile now only comes through the avatar stack or "4 Replies".
- Icon-button hover shape: replaced hardcoded `border-radius: 50%` with the `--seed-radius-full` token on `.lime-icon-btn`, `.lime-composer__aux`, `.lime-composer__send` — same visual result, token-driven. Left `.lime-avatar-frame::before`/`.lime-presence` (story rings/status dots, not buttons) and `.lime-sidebar__user-icon` (decorative, not a clickable button) alone as out of scope.
- Hamburger → moved from a fixed-position button to inline in `.lime-center-top` (aligned with breadcrumbs), now just a `.lime-icon-btn` reusing the same open/closed icon-swap + hover-preview pattern as the left/right panel toggles, rather than its own bespoke click handler.
- Bottom composer gradient: verified via code review (not a new fix) that no `overflow: hidden` sits between `.lime-composer::before` and its containing panel at any breakpoint — nothing needed changing.

## LIME-03g revision — Mobile Polish (follow-up)

- A second, differently-worded "LIME-03g" brief arrived after the first was already committed (`b8793ce`) — a genuine revision/fixup pass on the same feature, not a duplicate.
- Real conflict found and resolved via user decision: Task 5's code referenced `document.getElementById('open-profile-name')`, an id that no longer existed (renamed to `crumb-thread` in the prior pass, which had redefined "Jean Chung" in the breadcrumb to mean "go to thread"). This brief's constraint explicitly wanted "clicking Jean's name... should show panel" instead — asked the user, who confirmed reverting to "opens panel". `crumb-thread` now sets the mobile view to "panel"; `right-panel-toggle` was also added to that same panel-trigger list (this later turned out to cause the LIME-03h close-bug, fixed there).
- Removed the `#mobile-back` button and its CSS/JS entirely, per explicit instruction — no back-button replacement was specified, so there's currently no dedicated "step back" affordance beyond "Teachers" (→ contacts) and tapping a contact row (→ thread).
- Rewrote `.lime-topbar__crumb` for single-line ellipsis truncation instead of wrap; shortened `.lime-composer::before` from 36px → 24px.
- Logo files (`logo-mark.svg`/`logo-wordmark.svg`) were already copied over the placeholders in a prior step (LIME-03g's Task 1 duplicated that instruction) — no action needed there.

## LIME-03h — Layout Alignment + Logo Hover

- Brief arrived truncated (cut off mid-Task-2, no Task 3, no Commit line) plus a freeform addendum reporting two separate bugs. Surveyed all four before touching anything.
- Task 1 (tabs/chat-header alignment): real, confirmed bug — `.lime-contacts` had 0 top padding vs. `.lime-messages`'s 16px, so the two panels' content started at different Y positions. Fixed by adding matching 16px top padding to `.lime-contacts` (not by removing the chat side's padding, which the brief's own suggested fix implied, since that would push the top-fade gradient further onto the first message's actual text).
- Task 2 (gradient overlapping header): investigated and found no actual bug — `.lime-chat-body` is a normal flex sibling that starts after the 56px header row, so it can't structurally overlap it. The brief also referenced a `.lime-messages::before` selector that doesn't exist (the real gradient lives on `.lime-chat-body::before`), suggesting the brief was written against a stale understanding of the code. Left unchanged; flagged prominently at the gate, no objection raised.
- Breadcrumb truncation bug (freeform report): root cause found — `.lime-center-top__spacer`'s empty `flex:1` box absorbed all available shrinkage before the breadcrumb (`flex-basis:auto`, resists shrinking) ever did, so it overflowed instead of ellipsizing. Fixed by giving the crumb `flex:1 1 0%` (same flex-basis as the spacer) and zeroing the spacer on mobile, so the crumb is the one thing that actually yields.
- Right-panel-toggle mobile close bug (freeform report): root cause found — the LIME-03g-revision pass had added `right-panel-toggle` to the mobile router's list of one-way "go to panel" triggers, so every click forced the view back to "panel" and it could never close. Given its own dedicated handler that mirrors its actual open/close semantics instead.

## LIME-03i — Mobile Scroll, Gradients, Context-Aware Header

- Task 1 (mobile scroll): brief guessed `overflow: hidden` was blocking it, but `.lime-messages`/`.lime-list-col` already had `overflow-y: auto`. Real cause found: flipping `.lime-center-body` to column-direction on mobile (LIME-03f) left `.lime-list-col`/`.lime-conversation` sizing to their own content instead of available viewport height, so there was nothing to actually scroll within. Fixed with `flex: 1; min-height: 0;` on both; also added the requested `-webkit-overflow-scrolling: touch`.
- Task 2 (gradient 24px→48px) and Task 3 (search field padding) both directly reversed or overlapped with LIME-03h's just-committed fixes. Resolved Task 3 by scoping the padding reduction to mobile only — the alignment concern it would undo only applies on desktop/tablet where both panels show side by side; that concern doesn't exist on mobile (single panel at a time).
- Task 4 (breadcrumb tracks tab selection): implemented inside the existing `setScope()` function rather than the brief's suggested second parallel `.seed-tab` click listener, to keep "which tab is active" logic in one place.
- Task 6 (avatar sizing): the brief's exact numbers (36px wrapper, 28px avatars, Seed's default -8px overlap) don't fit geometrically — two 28px avatars at -8px overlap are 48px wide, wider than the 36px wrapper. Used -20px overlap instead so they actually fit.
- Task 7 (breadcrumbs single line): already fully satisfied by LIME-03g/03h's existing CSS — no change made.
- Process note: committed the logo-asset swap, LIME-03g-revision, and LIME-03h as three separate commits, but the latter two had landed in the same files (`lime.css`, `app.js`) without an intermediate commit between them, so they were combined into one commit rather than risk a bad split.

## LIME-03j — Composer Gradient + Scroll

- Task 3 (`.lime-composer`'s `position:absolute; bottom:0;` + canvas background) was already in place from earlier work — no change needed. Only Tasks 1/2 required edits: `.lime-messages` padding-bottom 88px→80px, `.lime-composer::before` gradient 48px→64px.

## LIME-03k — Logo Size + Hover Toggle

- Moved `#left-panel-toggle` inside `.lime-sidebar__brand` per the brief; `.lime-sidebar__brand` now owns the space-between/flex:1 role `.lime-sidebar__top` used to provide (toggle is no longer its sibling).
- **Deviation**: the brief's own CSS set `.lime-sidebar__toggle { display: none; }` as the unconditional default, only becoming visible when `.seed-layout--collapsed-left` was already active — meaning, taken literally, there would be no way to collapse the sidebar in the first place once expanded. The brief's "Expected Result" section only describes the collapsed→hover→expand direction, so this reads as an oversight, not an intentional removal. Kept the toggle a normal, always-visible `.lime-icon-btn` while expanded (unchanged from before); the new absolute-overlay hover-fade-swap only applies when collapsed. Flagged at the gate, no objection.
- Collapsed mark size: 18px → 24px, per the brief.

## LIME-03l — Logo Size, Panel Alignment, Toggle Position

- Task 2 (align contacts tabs with nav icons) was already fully satisfied — `.lime-contacts`'s top padding was already exactly `var(--seed-space-4)` from LIME-03h, added there for a different reason (aligning with chat messages) that happened to land on the same value.
- Task 3 (move `#right-panel-toggle` into `#right-panel`, close-only) was a real structural refactor — four separate places relied on the old "click it to toggle either way" behavior (the main init IIFE, `open-profile-avatars`, `open-replies`, the mobile router, auto-collapse-on-shrink). Introduced a shared top-level `setRightPanelOpen(isOpen)` helper (mirroring `wireHoverPreviewToggle`'s own top-level placement) that all of these now call directly instead of simulating `.click()` on a button that no longer toggles both ways. Removed the now-dead icon-swap/hover-preview logic entirely (nothing to preview toward on a close-only button) and the now-redundant `#layout[data-mobile-view="contacts"] #right-panel-toggle {display:none}` rule (the button's new parent is already hidden in that state).
- Fixed the brief's own icon-name typo: used the real `dew-sidebar-right-closed` instead of the brief's `dew-sidebar-right-close`, which doesn't exist in the vendored `dew` icon set.
- Enlarging the mark 22px→40px shifts its optical center further right within the sidebar's top row — the existing 24px left-padding was tuned for the smaller size. Left as-is (brief didn't ask for repadding) but flagged at the gate as a cosmetic nuance worth a visual check.

## LIME-03m — Mobile Profile Panel + Demo Content

- Task 2's real gap: Seed's `.seed-breadcrumbs` defaults to `flex-wrap: wrap`, and none of the three prior truncation passes (LIME-03g/03h/03i) had ever overridden it — added `flex-wrap: nowrap` explicitly, plus `#crumb-bio { flex-shrink: 0; }`.
- Task 3 (profile trigger) was already fully satisfied by existing code — `crumb-thread`/`open-profile-avatars` already call `setView('panel')`. `open-profile-name` (the brief's referenced id) doesn't exist, same stale reference as two briefs ago. No change made.
- Task 4 (demo content): the brief's system-message example ("Jean added you to the group") describes a group action, but this thread is deliberately Shem↔Jean 1:1 only (LIME-03d) — swapped to "You and Jean Chung are connected on Lime" instead. Used a camera-icon placeholder for the image message rather than a live `picsum.photos` URL, matching the map placeholder's existing precedent of avoiding real third-party dependencies. Link-preview and file-attachment components have no prior design in this codebase — built both from scratch since the brief only gave example markup for image/voice/emoji.


## LIME-03n — Desktop Breadcrumbs, Logo Sizing, Profile Trigger

- Task 1: removed the >=768px hide rule for `.lime-topbar__crumb` (kept it for `.lime-contacts__search`, which stays mobile-only). Also made the crumb's flex-basis-0/spacer-zeroing overflow fix (LIME-03m) unconditional instead of mobile-scoped, since the same overflow risk now applies on desktop. Found and removed a duplicate unconditional `.lime-center-top__spacer { flex: 1; }` base rule that, left in place, would have silently overridden the fix's `flex: 0 0 0px` on every breakpoint (later rule wins at equal specificity).
- Task 2: left the existing "Bio" (panel-view) breadcrumb segment untouched -- the brief's table only documents the Contacts/Thread rows, not a removal of the third level. Flagged at the gate as an open question, no objection raised.
- Task 3/4: logo unified to 32px both states (collapsed override removed entirely); brand gap was already `var(--seed-space-2)` from LIME-03k, no change needed.
- Task 5 (profile opens on any message's sender/avatar click): implemented literally, matching the brief's own unfiltered selector -- clicking Shem's own sent-message avatar also opens "Jean Chung's profile" (the panel has no per-sender content), which is a bit incoherent, but the brief didn't filter by sender either. Used the shared `setRightPanelOpen()` helper directly rather than the brief's `toggle.click()` snippet, which assumed the pre-LIME-03l always-toggles behavior.
- Task 6: fully reverted LIME-03l's Task 3 -- moved `#right-panel-toggle` back to `.lime-center-top` (after the video icon), restored the bidirectional open/close icon-swap toggle (removed the close-only version), updated the mobile router's toggle handler back to mirroring both directions, and restored the `[data-mobile-view="contacts"] #right-panel-toggle {display:none}` rule that briefly became redundant while the button lived inside `#right-panel`.
