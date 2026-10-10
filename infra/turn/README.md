# Lime's TURN relay (LIME-111)

Calls between two phones go directly (WebRTC). When a direct path is blocked (many school and mobile networks) the media is relayed
through this coturn server. The media is end-to-end encrypted between the phones (DTLS-SRTP, bound to the Lime identity by the signed
call offer), so the relay only ever carries ciphertext.

- **Server:** Hetzner Cloud CPX11 "lime-turn-1" in Ashburn, Ubuntu 26.04, IPv4 `178.156.199.1`. Name: `turn.limechat.org` (an A record in deSEC).
- **Ports:** 3478 UDP+TCP (STUN/TURN), 5349 TCP/UDP (TURN over TLS), 49152-49999 UDP (relay), 80 TCP (certificate renewals), 22.
- **Credentials:** time-limited, from the coturn "REST API" scheme (`use-auth-secret`). The Supabase Edge Function `turn-credentials` makes them
  (username `<expiry>:<user id>`, password `base64(HMAC-SHA1(secret, username))`, valid one hour) for signed-in sessions only.

## Install or repair (idempotent)

```sh
ssh root@178.156.199.1 'bash -s' < infra/turn/setup.sh
```

It installs coturn and certbot, gets the certificate for `turn.limechat.org`, writes `/etc/turnserver.conf`, opens the firewall and starts coturn.
The shared secret is created **once** at `/etc/lime-turn/secret` (root only, never printed). Re-running keeps it.

## Giving Supabase the same secret (without it ever appearing on screen)

The secret goes from the server straight into the function secret; nothing prints it. In Terminal on your Mac, for each project
(`<ref>` is the project reference; staging is in `~/.lime/staging.env`):

```sh
ssh root@178.156.199.1 cat /etc/lime-turn/secret | { IFS= read -r S && supabase secrets set TURN_SECRET="$S" --project-ref <ref>; unset S; }
```

If you would rather type or paste a value yourself (for example one you generated), use a hidden prompt:

```sh
read -s -p "TURN secret: " S; echo; supabase secrets set TURN_SECRET="$S" --project-ref <ref>; unset S
```

(If you set a value yourself, put the same one on the server: `printf %s "$S" | ssh root@178.156.199.1 'cat > /etc/lime-turn/secret && bash -s' < infra/turn/setup.sh`.)

Until `TURN_SECRET` is set the function answers 503 `not_configured` and the app falls back to a direct connection only.

## Checking it

- Certificate: `echo | openssl s_client -connect turn.limechat.org:5349 -servername turn.limechat.org | grep Verification`
- An allocation with a real credential, run on the server so the secret stays there:
  `ssh root@178.156.199.1 'U="$(( $(date +%s) + 600 )):check"; P=$(printf %s "$U" | openssl dgst -sha1 -hmac "$(cat /etc/lime-turn/secret)" -binary | base64); turnutils_uclient -t -u "$U" -w "$P" -y -n 1 -m 1 -l 100 turn.limechat.org | tail -4'`
- Logs: `/var/log/turnserver/turn.log`.

## Cost and growth

One small box carries many relayed calls (about 1.5-2 GB of egress per relayed video hour; the plan includes 20 TB). Group calls (LIME-112) will use a
separate, larger LiveKit server, so this always-on box stays small. The relay denies peers on private and local networks.
