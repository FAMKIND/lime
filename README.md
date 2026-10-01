# Lime

Secure, open-source communication for teachers.

## Preview

```bash
git clone https://github.com/FAMKIND/lime.git
cd lime
git submodule update --init --recursive
open public/index.html
```

## Running the dev server

```bash
node server/dev-server.mjs          # Node 23, no install needed
```

It serves the app exactly like the Python server did (`/public/…`, `/vendor/…`) and also the `/api/v1` API described in [`docs/api.md`](docs/api.md). It prints two links:

- **This computer:** `http://localhost:8000/public/index.html`
- **On your network:** `http://192.168.x.x:8000/public/index.html`: open this on a phone on the same Wi-Fi.

The web app does not use the API yet (it still keeps everything in the browser; LIME-74 connects it), so the two links show the same app and **do not share data yet**.

- **Data** lives in `data/` (gitignored): the op log (`oplog.jsonl`, the source of truth), a cache of the derived state, accounts and sessions, and uploaded files. It survives restarts, and a crash loses nothing that was acknowledged. First run seeds from the same seed the app uses.
- **Seed teachers** can sign in to the API with the shared demo password from `public/js/demo-config.local.js` (gitignored), as in the browser demo. Without that file they cannot sign in to the API until it exists and the data is reset.
- **Reset:** stop the server and delete `data/`, or `curl -X POST -H 'X-Lime-Dev: 1' http://localhost:8000/api/v1/dev/reset`.
- **Port busy?** It says so. Start it elsewhere with `--port 8001` (and `--data` to use another folder).
- **Local network only.** It binds `0.0.0.0` and is a development tool. Do not expose it to the internet. Note that `public/js/demo-config.local.js` is served like any other file under `public/`, so anyone on your Wi-Fi can read the demo password.

## Running tests

The regression suites live in `tests/` (LIME-72). One-time setup, then one command:

```
cd tests && npm install     # once: installs jsdom and puppeteer-core (node_modules is gitignored)
npm test                    # all suites; or: node run.mjs smoke css auth sync toasts
```

Suites: **api** (the dev server and the v1 contract: endpoints, permissions, idempotency, DM dedup, backfill, feed visibility, files, realtime, restart persistence; starts its own server on a temp folder), **smoke** (real `index.html` and `auth.html` load in jsdom with zero errors), **css** (no stray `*/`, and each stylesheet's browser-parsed rule count), **auth** (sign up, sign in, wrong password, the seed-teacher hint, sign out), **sync** (two tabs, a live message, no lost writes 20 + 20; Firefox and Chrome), **toasts** (queue across pages, max 3, an error stays). Each run starts its own static server on a free port and drives your installed Firefox and Chrome. `LIME_TEST_SERVER=dev npm test` runs the browser suites against the dev server instead of the Python one. See `tests/README.md`.

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
