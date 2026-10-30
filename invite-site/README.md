# invite-site

The page behind Lime's invite links, `https://limemessenger.com/u/<username>` (LIME-97b). Static files, no scripts that call out, no analytics, no cookies.

- `u/index.html` is served for every `/u/<anything>` (`_redirects`, a Cloudflare Pages rule). It shows "@name invited you to Lime" (the name is checked against `[A-Za-z0-9._]{3,20}` and shown as text) and says the app is coming soon. The key fingerprint after `?k=` is for the app; the page never reads or sends it.
- `index.html` is a one-line holding page for `limemessenger.com/`.
- **No `/terms` or `/privacy` pages yet:** Settings → About links `https://limemessenger.com/terms` and `/privacy`, and this site only serves `/u/*` and the holding page, so those two links show nothing until the compliance pack writes the pages (the links can stay).
- Universal links (opening the app straight from the link) come with the paid Apple account: add `/.well-known/apple-app-site-association` here then.

## Host it (free): Cloudflare Pages

1. Create a free Cloudflare account, then **Workers & Pages → Create → Pages → Upload assets**.
2. Name the project `lime-invite`, upload this `invite-site/` folder, deploy. You get `lime-invite.pages.dev`; check `https://lime-invite.pages.dev/u/grace.h`.
3. **Custom domains → Set up a custom domain → `limemessenger.com`** (and optionally `www.limemessenger.com`). Cloudflare shows the DNS record to add (below).

## Point limemessenger.com at it (DNS in deSEC)

limemessenger.com's DNS lives in deSEC (desec.io → Domain Management → limemessenger.com → Records). **Do not delete existing records**: `send.limemessenger.com` (and any MX/TXT/DKIM/SPF records) carry the email Lime sends through Resend.

Pages needs the name to point at its hostname. deSEC does not flatten CNAMEs at the apex, so use one of:

- **Subdomain only (simplest, no clash):** add `CNAME  www  lime-invite.pages.dev.` (note the final dot), use `https://www.limemessenger.com/u/<username>` in invites. If you prefer the bare `limemessenger.com/u/…` links in the app, you need the apex option below, and then `InviteLink.host` stays `limemessenger.com`.
- **Apex (`limemessenger.com`):** add Cloudflare's A/AAAA records for the apex as shown when you add the custom domain, or move the zone to Cloudflare (change the registrar's name servers). If `limemessenger.com` already serves something (the old web app or a Supabase page), tell me before pointing it elsewhere.

Allow a few minutes for DNS; Cloudflare issues the HTTPS certificate on its own.

### Alternative: Codeberg Pages

Push this folder's contents to a `pages` branch of a Codeberg repo, then in deSEC add `CNAME www pages.codeberg.org.` plus the TXT record Codeberg shows (`.domains` file in the repo with `www.limemessenger.com`). Codeberg has no `_redirects` support for `/u/*`, so copy `u/index.html` to `404.html` (Codeberg serves it for unknown paths).
