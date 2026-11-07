# invite-site

The page behind Lime's invite links, `https://limemessenger.com/u/<username>` (LIME-97b). Static files, no scripts that call out, no analytics, no cookies.

- `u/index.html` is served for every `/u/<anything>` (Caddy rewrites it) and for every `/b/<anything>`. It shows "@name invited you to Lime" (the name is checked against `[A-Za-z0-9._]{3,20}` and shown as text) and says the app is coming soon. The key fingerprint sits after the `#` (`/u/grace.h#k=…`), and a band's token too (`/b/#…`): a browser never sends what follows `#` to any server, and the page never reads it. The app still reads the older `?k=` and `/b/<token>` forms.
- `index.html` is a one-line holding page for `limemessenger.com/`. Since LIME-284c2 `infra/invite/deploy.sh` publishes the home page (`site/com/`) over this folder: its `index.html` and `brand/` win, everything else here (the invite page, the legal pages, `/.well-known`) stays; `--invite-only` publishes this holding page instead.
- **`/privacy`, `/terms`, `/guidelines`, `/safety`, `/security` and `/.well-known/security.txt` are generated drafts (LIME-282a; deployed 2026-11-01 by LIME-282b) from `docs/legal/` by `python3 tools/build-legal-pages.py`; don't edit the HTML by hand.** Before that: no `/terms` or `/privacy` pages: Settings → About links `https://limemessenger.com/terms` and `/privacy`, and this site only serves `/u/*` and the holding page, so those two links show nothing until the compliance pack writes the pages (the links can stay).
- Universal links (opening the app straight from the link) come with the paid Apple account: add `/.well-known/apple-app-site-association` here then.

## Host it: Caddy on the call server

The page is served by Caddy on `lime-turn-1` (the same server as coturn and LiveKit), at `limemessenger.com`; `www` redirects to the apex. Caddy gets the HTTPS certificate on its own, keeps no access log, and sends HSTS and `Referrer-Policy: no-referrer`.

1. **DNS (deSEC → limemessenger.com → Records):** `A  @  178.156.199.1` and `A  www  178.156.199.1`. Do not touch the `send` records or any MX/TXT/DKIM/SPF: they carry the email lime sends through Resend.
2. **The Caddy site** is written by `infra/sfu/setup.sh` (`ssh root@178.156.199.1 'bash -s' < infra/sfu/setup.sh`; it also keeps the call server's blocks).
3. **The files:** `bash infra/invite/deploy.sh` copies the home page and this folder to `/srv/invite` on the server (it replaces the folder wholesale). Run it again after any change to either.

`/u/*` and `/b/*` both show `u/index.html` (Caddy rewrites them). Check `https://limemessenger.com/u/grace.h` and `/b/x`.
