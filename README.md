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

Served this way the web app uses the API (`LimeBackend` in `public/js/api-adapter.js` notices `/api/v1/health` and the app stops keeping its own private copy of the data): **everyone who opens the printed link, on any device, shares one Lime, live**. Served by anything else (the Python server, `file://`) it works as before, local to that browser.

**Try it with two people:** sign in as `shem@famkind.com` and `jean@famkind.com` (the familiar demo Shem Rajoon and Jean Chung, with all their existing chats) in two different browsers (or one normal and one private window), or on a computer and a phone. Messages, replies, reactions, renames, new chats and profile changes show up on the other side within a second.

**Logins.** Every demo teacher's email is `<first name>@famkind.com` (for example `grace@famkind.com`) and signs in with the shared demo password from `public/js/demo-config.local.js` (gitignored). Shem and Jean can have a password and phone number of their own: put them in `seed-data/test-accounts.local.json` (gitignored, never committed; copy `seed-data/test-accounts.example.json` and edit it). The server prints their emails when it starts. After changing the seed or that file, **re-seed**: stop the server and delete `data/`, or `curl -X POST -H 'X-Lime-Dev: 1' http://localhost:8000/api/v1/dev/reset`.

**Rule: demo emails are `@famkind.com`, which could be real mailboxes. Local and staging must never send real email or SMS.** Any future invite, notification or sign-up feature has to stub delivery everywhere except production.

**On a phone:** the phone must be on the same Wi-Fi as this computer. Open the "On your network" link the server prints (like `http://192.168.0.127:8000/public/index.html`) in the phone's browser and sign in as one of the two logins above; sign in as the other on the computer.

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

Suites: **e2e-server** (three people in Firefox, a second Firefox started with `-private`, and Chrome, all on the dev server: live DMs, groups, replies, reactions, rename/add/delete, name and photo changes, attachments, DM dedup, offline sending, 20 + 20 writes, reset), **api** (the dev server and the v1 contract: endpoints, permissions, idempotency, DM dedup, backfill, feed visibility, files, realtime, restart persistence; starts its own server on a temp folder), **smoke** (real `index.html` and `auth.html` load in jsdom with zero errors), **css** (no stray `*/`, and each stylesheet's browser-parsed rule count), **auth** (sign up, sign in, wrong password, the seed-teacher hint, sign out), **sync** (two tabs, a live message, no lost writes 20 + 20; Firefox and Chrome), **toasts** (queue across pages, max 3, an error stays). Each run starts its own static server on a free port and drives your installed Firefox and Chrome. `LIME_TEST_SERVER=dev npm test` runs the browser suites against the dev server instead of the Python one; add `LIME_TEST_ORIGIN=lan` to use this computer's LAN address (an insecure context, like a phone). `npm run test:safari` drives Safari once it allows remote automation (`safaridriver --enable`). See `tests/README.md`.

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
