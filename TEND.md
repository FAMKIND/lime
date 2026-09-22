# TEND.md

Record of work landed via the `tend` skill.

## LIME-03a — Sidebar Polish

- Logo: replaced the inline-JS SVG brand system (`LIME_MARK`/`LIME_WORDMARK` strings in `app.js`, broadcast via `innerHTML`) with static files loaded through `<img>`: `public/assets/logo-mark.svg` (plain lime-green circle) and `public/assets/logo-wordmark.svg` ("lime" text, fill baked in since `<img>` content can't take `currentColor`). Deleted the redundant unused `lime-mark.svg`/`lime-wordmark.svg` pair that predated this brief.
- Nav order (Search → Notifications → gap → Link → Jam) already matched the brief; added a red "3" badge (reusing `seed-badge--bad seed-badge--sm`, repositioned via `.lime-nav__badge`) to the notifications bell.
- Icon sizing: nav search icon was 14px, nav buttons were 20px — normalized both to 20px.
- Collapsed-rail toggle: hidden by default (`opacity:0; pointer-events:none`) and revealed on `:hover` of `.lime-sidebar__top`, mirroring Claude's sidebar. Used opacity/pointer-events rather than `display` so the existing hover-preview icon swap in `app.js` (`wireHoverPreviewToggle`) kept working with no JS changes.

Deviation from literal brief text: the brief's placeholder mark request ("simple lime-colored circle") is visually simpler than the sunburst-ray mark it replaced — flagged to the user at the gate; no objection raised before the next brief arrived, taken as approval.
