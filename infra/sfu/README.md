# Lime's group-call media server (LIME-112b)

Calls inside a lime group go through one LiveKit server (an SFU: it receives each person's audio and video once and forwards it to the others).
The media is **end-to-end encrypted by the phones** (a key per sender, sent over lime's own encrypted channel, LIME-112b phase 3), so this
server and Caddy only ever see ciphertext, IP addresses, timing, packet sizes and how many people are in a room: never media, never names.
1:1 calls do not use this server (they are phone to phone, through the TURN relay when needed: `infra/turn/`).

- **Server:** today it shares Hetzner Cloud CPX11 `lime-turn-1` (Ashburn, Ubuntu 26.04, `178.156.199.1`) with coturn. Name: `sfu.limechat.org`
  (an A record in deSEC). Moving to its own server later is a rerun of `setup.sh` plus one DNS change (see Cost and growth).
- **Ports:** 443 TCP (HTTPS and WSS, Caddy), 7881 TCP (ICE over TCP for networks that block UDP), 50000-60000 UDP (media; coturn's relay
  range 49152-49999 does not overlap), 80 TCP (Caddy: certificates), 22. LiveKit's own signalling port (7880) listens on `127.0.0.1` only.
- **What runs:** `lime-sfu.service` (LiveKit, pinned version, checksum verified, runs as its own user) and `caddy.service`.
  No recording or egress service, no webhooks, LiveKit's built-in TURN is **off**, no Google STUN (the config points clients at lime's coturn).
  Logs are warn-and-above only, because routine LiveKit logs carry room names and addresses.
- **TURN for the phones** comes from the app, not from this server: it asks the existing `turn-credentials` function for time-limited coturn
  credentials and gives them to the LiveKit SDK (`ConnectOptions.iceServers`); **Always relay calls** also set `iceTransportPolicy: .relay`,
  so the SFU never sees the phone's address. The coturn secret is never copied into LiveKit's config.
- **Access:** the Edge Function `livekit-token` gives a signed-in session a 10-minute join token for a room named by the call's random 64-hex id
  and a random per-call identity (never the user id). Join, publish, subscribe and data only: no admin, no recording. It stores and logs nothing.

## Install or repair (idempotent)

```sh
ssh root@178.156.199.1 'bash -s' < infra/sfu/setup.sh
```

It installs Caddy and a pinned LiveKit (SHA-256 checked), writes `/etc/lime-sfu/livekit.yaml`, the Caddyfile and the systemd unit, opens ufw,
and **switches coturn's certificate renewal from certbot "standalone" to "webroot"** (Caddy now owns ports 80 and 443; it serves only the
challenge path for `turn.limechat.org`), then proves it with `certbot renew --dry-run`. The API key and secret are created **once**
in `/etc/lime-sfu/` (root only, never printed). Re-running keeps them. The A record for `sfu.limechat.org` must already point here (Caddy gets
its own certificate for that name); if a Hetzner Cloud Firewall is attached to the server, it must allow 443/tcp, 7881/tcp and 50000-60000/udp.

> If `infra/turn/setup.sh` is ever run on a *new* server after this one, it gets its first certificate with certbot "standalone" on port 80:
> run it **before** `infra/sfu/setup.sh` there (or stop Caddy for that minute).

## Giving Supabase the key, the secret and the address (without them ever appearing on screen)

Nothing prints them. In Terminal on your Mac, for each project (`<ref>` is the project reference; staging is in `~/.lime/staging.env`):

```sh
K="$(ssh root@178.156.199.1 cat /etc/lime-sfu/api_key)" && S="$(ssh root@178.156.199.1 cat /etc/lime-sfu/api_secret)" \
  && supabase secrets set LIVEKIT_API_KEY="$K" LIVEKIT_API_SECRET="$S" LIVEKIT_URL="wss://sfu.limechat.org" --project-ref <ref>; unset K S
```

Until all three are set the function answers `503 not_configured` and the app says group calls are not available yet.

## Checking it

- Certificate and signalling: `curl -sS -o /dev/null -w '%{http_code}\n' https://sfu.limechat.org/` (LiveKit answers `200` with `OK` on its root).
- The service: `ssh root@178.156.199.1 'systemctl is-active lime-sfu caddy; ufw status | grep -E "443|7881|50000"'`
- Reachable from outside: `nc -zv sfu.limechat.org 443`, `nc -zv sfu.limechat.org 7881`, and a UDP media test with `lk load-test` (below).
- coturn's certificate still renews: `ssh root@178.156.199.1 'certbot renew --dry-run --cert-name turn.limechat.org'`
- A load test, from a machine that is **not** the server (`brew install livekit-cli`; keep the key and secret in shell variables, never on the command line history):
  `lk load-test --url wss://sfu.limechat.org --api-key "$K" --api-secret "$S" --room loadtest-6 --video-publishers 6 --audio-publishers 6 --subscribers 6 --video-resolution high --duration 75s`
  and watch the server with `ssh root@178.156.199.1 'top -b -n1 | head -15; ss -s'` while it runs. (Load-test rooms are plain, unencrypted
  test streams; they use a room name that is not 64 hex characters, so they never collide with a real call: real tokens only come from the function.)
- Logs: `journalctl -u lime-sfu` (warn and above) and `journalctl -u caddy`.

## Cost and growth

CPX11 (2 shared vCPU, 2 GB) is already paid for and fits a handful of people: the CPU is the limit, not memory. Measured numbers (3, 6 and 10 participants, all publishing and subscribing, 720p simulcast) are in
`TEND.md` (LIME-112b): at 10 the server used about a quarter of one core, 190 MB and 37 Mbps out, so this box is far from its CPU limit at call sizes of
10 or fewer; the practical limit is how many video streams each phone receives (egress grows with the square of the people who send video). For 50-100 people per room, or several rooms at once, move to a dedicated server (**D1 = A**): a dedicated-vCPU Hetzner
instance (CCX23 or CCX33 class), `ssh root@<new> 'bash -s' < infra/sfu/setup.sh`, point `sfu.limechat.org` at it, and keep coturn where it is
(the SFU's own address is reachable directly, so relay-only phones reach it through coturn as today). Egress is the cost driver: a room of N people
sends each person about (N-1) simulcast streams; the plan includes 20 TB per server per month.
