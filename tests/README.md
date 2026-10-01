# Lime tests (LIME-72)

```
npm install        # once
npm test           # everything (about a minute)
node run.mjs sync  # one or more suites by name: smoke css auth sync toasts api e2e-server
LIME_TEST_SERVER=dev npm test   # browser suites against server/dev-server.mjs instead of Python
```

Exit code is 1 if anything fails. Each run starts its own `python3 -m http.server` from the repo root on a free port and stops it afterwards, so nothing needs to be running first.

**Browsers.** `puppeteer-core` drives your *installed* browsers: Chrome over CDP and Firefox (`/Applications/Firefox.app`) over WebDriver BiDi, each on a throwaway profile. Playwright is not used: its Firefox is a patched build that is not the one you use, and it cannot drive the stock one. Suites that care about browser differences (`sync`, `css`) use Firefox; `sync` runs in both.

**What each suite covers**
- `e2e-server`: three people in three browsers (Firefox, a second Firefox started with `-private`, Chrome) on a throwaway dev server: live DM and group messages, a thread reply, a reaction, rename/add/delete, name and photo changes, an attachment (members yes, a non-member refused), per-user star and archive not leaking, DM dedup when two people start the same DM at once, presence, the picker and directory, no phone ever shown, link previews from the API, **offline sending** (server stopped, three messages written with a clock 10 minutes behind, server restarted: delivered in order with "Sent ... · delivered ..."), 20 + 20 writes with none lost, the demo password file answering 404 (also over the LAN address), and a reset sending everyone to sign-in. Skipped when Firefox or Chrome is missing. The "private" Firefox is a second Firefox started with `-private`; under BiDi it did not become a true private window in this environment, which the suite reports.
- `api`: the dev server (LIME-73) and the v1 contract: signup/signin/refresh rotation, every op's permissions, replays (idempotency), DM dedup and alias, backfill, feed visibility (no per-user rows, phone and email rules), files authorisation, SSE and presence, restart persistence including a hard kill. Starts its own server on a free port with a throwaway data folder; seed-teacher sign-in is only checked when `public/js/demo-config.local.js` exists.
- `smoke`: the real pages load in jsdom (real scripts, real HTML), zero errors, the app renders.
- `css`: a stray `*/` outside a comment (it silently drops the rest of a stylesheet) and a minimum parsed-rule count per stylesheet in the real browser. The minimums sit just under today's counts (`lime.css` 737, `gradients.css` 25, `auth.css` 39); raise them when a stylesheet grows on purpose.
- `auth`: sign up, no plain password stored, per-tab session, sign out, the gate, wrong password, right password, the seed-teacher hint.
- `sync`: two tabs in one browser as two people: a live group and message, 20 + 20 messages with none lost, order preserved, sign-out stays per tab.
- `toasts`: a toast queued before navigation shows once, at most 3 visible, an error stays, an action runs, sending a message does not toast.

**Known noise (ignored on purpose):** the missing gitignored `demo-config.local.js` (404), blocked Google Fonts when offline, `ResizeObserver loop`, and Firefox/BiDi's `SecurityError: The operation is insecure` when a tab navigates away on sign-out (also on a clean checkout before LIME-69).

**Adding a suite:** create `suites/<name>.mjs` exporting `run({ base, check })`, call `check(name, condition, detail)`, and add the name to `ALL` in `run.mjs`.
