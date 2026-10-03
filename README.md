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

Suites: **e2e-server** (three people in Firefox, a second Firefox started with `-private`, and Chrome, all on the dev server: live DMs, groups, replies, reactions, rename/add/delete, name and photo changes, attachments, DM dedup, offline sending, 20 + 20 writes, reset), **api** (the dev server and the v1 contract: endpoints, permissions, idempotency, DM dedup, backfill, feed visibility, files, realtime, restart persistence; starts its own server on a temp folder), **smoke** (real `index.html` and `auth.html` load in jsdom with zero errors), **css** (no stray `*/`, and each stylesheet's browser-parsed rule count), **auth** (sign up, sign in, wrong password, the seed-teacher hint, sign out), **sync** (two tabs, a live message, no lost writes 20 + 20; Firefox and Chrome), **mobile** (the phone layout, 360 to 844 wide, in Chrome and Firefox), **auth-phone** (sign-in on a phone with the keyboard open), **toasts** (queue across pages, max 3, an error stays). Each run starts its own static server on a free port and drives your installed Firefox and Chrome. `LIME_TEST_SERVER=dev npm test` runs the browser suites against the dev server instead of the Python one; add `LIME_TEST_ORIGIN=lan` to use this computer's LAN address (an insecure context, like a phone). `npm run test:safari` drives Safari once it allows remote automation (`safaridriver --enable`). See `tests/README.md`.

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

- ~~Mobile nav (<768px): push-model drawer~~ **Superseded 2026-10-03** (see the dock decision below). The drawer, its hamburger
  button and its push behaviour are gone on phones.
- ~~Mobile drawer shows the full sidebar / is narrower than desktop's sidebar~~ Superseded with the drawer.

## Decisions (2026-10-03)

- **Phones (<768px) use a bottom dock, not a drawer** (the user's choice, from their Penpot design; supersedes the 2026-09-23
  push-drawer decision above). A floating, rounded, neutral dock sits at the bottom of the Messages screen with four items,
  lowercase: **link** (Messages; badge = all unread), **jam** (a "coming soon" placeholder), **calls** (a "coming soon" toast) and
  **account** (your avatar; opens Settings → Profile, where sign-out lives). There is no Communities item and no notifications
  bell on phones: notifications live inside link (unread badges and live previews). Communities is deferred.
- The Messages screen is **one list** (pinned chats first, then by recency), with search and a filter (All, Unread, Pinned,
  Groups, Archived); no Recent row, section headers or tabs on phones.
- Navigation is a **stack**: tapping a chat pushes the chat screen (no dock inside a chat), details and threads push on top of
  it, and "‹" goes back. The browser's back button, the Android back button and iOS's edge swipe do the same, and `#c=` deep
  links still open that chat. Desktop (>=768px) is unchanged.

- **The phone chat (LIME-79):** others' messages sit on the left (avatar and name on the first message of a run) in the neutral
  bubble; your own sit on the right in light green (`--seed-lime-300`, the user's choice) with ink text and no avatar. Under each
  bubble: reaction chips, an add-reaction button, and the time (lowercase on phones: "7:32 am") with a receipt slot; **press and
  hold** a message (~400ms) for a glass menu with six quick reactions, Reply in thread and Copy text. The
  composer is one pill until its text field is focused, then grows into a text area above a toolbar; **on phones the keyboard's
  Return key sends** (`enterkeyhint="send"`, the common messaging pattern), so there is no newline from the keyboard (lists and code
  still use it, and Shift+Enter always adds one).
- **Default avatars use eight soft tints** (Seed lime / meadow / warm soil steps and 50/50 mixes of them, at least 6 apart in
  OKLab in light and about 6 in dark), picked deterministically by name, at every width (replacing the 12 pastels).
- **Glass (LIME-79-fix):** on phones the dock, the chat header and every menu are translucent with a backdrop blur (iOS-style),
  with a solid fallback where `backdrop-filter` is missing. The Messages header is a fixed bar; search and the filter scroll with the
  list and fade under it. The chat header is an iOS-style navigation bar ("‹ 13", the avatars and title centred); tapping it opens
  Members (a DM shows both people). The microphone is one button (no device list): it says voice messages are coming soon.

## Open

- [ ] Voice messages: the microphone button only shows "coming soon" today. The real feature records with a live sound-wave view.
- [ ] Icon gaps in dew (send, mic, paperclip)
