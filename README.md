# Lime

Secure, open-source communication for teachers.

## Preview

```bash
git clone https://github.com/FAMKIND/lime.git
cd lime
git submodule update --init --recursive
open public/index.html
```

## Running tests

The regression suites live in `tests/` (LIME-72). One-time setup, then one command:

```
cd tests && npm install     # once: installs jsdom and puppeteer-core (node_modules is gitignored)
npm test                    # all suites; or: node run.mjs smoke css auth sync toasts
```

Suites: **smoke** (real `index.html` and `auth.html` load in jsdom with zero errors), **css** (no stray `*/`, and each stylesheet's browser-parsed rule count), **auth** (sign up, sign in, wrong password, the seed-teacher hint, sign out), **sync** (two tabs, a live message, no lost writes 20 + 20; Firefox and Chrome), **toasts** (queue across pages, max 3, an error stays). Each run starts its own static server on a free port and drives your installed Firefox and Chrome. See `tests/README.md`.

## Constraints

1. Use seed (`vendor/seed/`), `seed-*` classes, token grammar
2. `data-theme` on every `<html>`
3. Prototype: HTML/CSS/vanilla JS only
4. Local-first future: design for P2P/offline

## Decisions (2026-09-21)

- Prototype: mocked auth, 1:1 DM, group chat, community
- Stack: HTML/CSS/vanilla JS
- Consume seed: submodule

## Decisions (2026-09-23)

- Mobile nav (<768px): push model, not overlay. Opening the drawer resizes
  the grid (`.seed-layout__left` 0 → 240px) and shifts the center panel
  over — no `position: fixed`, no dark backdrop, no tap-to-close scrim.
  Confirmed explicitly (twice) after briefs repeatedly proposed reverting
  to an overlay+backdrop; do not revert without asking first.
- Mobile drawer shows the full sidebar (text labels, wordmark, user name),
  never the desktop icon-only collapsed rail — that collapse state is
  desktop-only.
- Mobile drawer is narrower than desktop's sidebar (240px, not 280px) and
  its logo mark aligns horizontally with the hamburger toggle it replaces
  (`.lime-center-top`'s own icon inset) — not desktop's wider logo inset,
  which exists there to optically center the logo over nav icons in a
  permanent rail.

## Open

- [ ] Icon gaps in dew (send, mic, paperclip)
