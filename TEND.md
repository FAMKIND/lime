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
