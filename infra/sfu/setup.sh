#!/usr/bin/env bash
# Installs and configures Lime's group-call media server (LiveKit, LIME-112b) on an Ubuntu server. Idempotent: run it again to repair or update.
#
#   ssh root@<server> 'bash -s' < infra/sfu/setup.sh
#
# What it does: installs a pinned LiveKit server (checksum verified) and Caddy (the HTTPS front); writes the LiveKit config; opens the
# firewall; and, if coturn's certificate is renewed by certbot "standalone" on port 80 (infra/turn/setup.sh), switches that renewal to the
# "webroot" method served by Caddy, because Caddy now owns ports 80 and 443. The API key and secret are created once in /etc/lime-sfu/
# (root only, never printed). Media is end-to-end encrypted by the phones (per-sender keys sent over Lime's own channel); this server
# only forwards ciphertext. There is no recording or egress service, no webhooks, and the TURN built into LiveKit is off.
set -euo pipefail

# The call server answers to two names while the move to limemessenger.com happens (LIME-172a); set ALT_DOMAIN="" / TURN_ALT_DOMAIN="" for one.
DOMAIN="${DOMAIN:-sfu.limechat.org}"
ALT_DOMAIN="${ALT_DOMAIN-sfu.limemessenger.com}"
TURN_DOMAIN="${TURN_DOMAIN:-turn.limechat.org}"
TURN_ALT_DOMAIN="${TURN_ALT_DOMAIN-turn.limemessenger.com}"
# coturn's certificate lineage (infra/turn/setup.sh): one certificate for both turn names, named for the first.
TURN_CERT="${TURN_CERT:-turn.limemessenger.com}"
EMAIL="${EMAIL:-shem@limechat.org}"
LIVEKIT_VERSION=1.13.9
SHA256_AMD64=0b7fa208b662d09cfdeae8c06cf4c481aead0556086558b48250501e2e2d6e20
SHA256_ARM64=c5e4e5a6d6cf0a449651aa3178532ecc7a2bf2502538396ebe6e51ff13424056
MEDIA_MIN=50000      # UDP media; must not overlap coturn's relay range 49152-49999
MEDIA_MAX=60000
TCP_PORT=7881        # ICE over TCP, for networks that block UDP
DIR=/etc/lime-sfu
INVITE_HOST="${INVITE_HOST-limemessenger.com}"   # the invite page (LIME-172d, files from infra/invite/deploy.sh); INVITE_HOST="" to leave it out
INVITE_ROOT=/srv/invite
ACME_ROOT=/var/lib/lime-acme   # not under /var/www: that folder can be root-only (mode 700), and Caddy must read this one

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq caddy ufw curl ca-certificates >/dev/null

# --- the LiveKit server (pinned, checksum verified)
case "$(uname -m)" in
  x86_64)  ARCH=amd64; SHA="$SHA256_AMD64" ;;
  aarch64) ARCH=arm64; SHA="$SHA256_ARM64" ;;
  *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac
if ! /usr/local/bin/livekit-server --version 2>/dev/null | grep -q "$LIVEKIT_VERSION"; then
  TMP="$(mktemp -d)"
  curl -fsSL -o "$TMP/lk.tgz" "https://github.com/livekit/livekit/releases/download/v${LIVEKIT_VERSION}/livekit_${LIVEKIT_VERSION}_linux_${ARCH}.tar.gz"
  echo "$SHA  $TMP/lk.tgz" | sha256sum -c - >/dev/null || { echo "LiveKit download failed its checksum" >&2; rm -rf "$TMP"; exit 1; }
  tar -xzf "$TMP/lk.tgz" -C "$TMP" livekit-server
  install -m 755 "$TMP/livekit-server" /usr/local/bin/livekit-server
  rm -rf "$TMP"
fi
id livekit >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin livekit

# --- the API key and secret (created once, kept on this server only)
install -d -m 750 -g livekit "$DIR"
if [ ! -s "$DIR/api_secret" ]; then
  umask 077
  printf 'lime%s' "$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')" > "$DIR/api_key"
  head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$DIR/api_secret"
fi
chmod 600 "$DIR/api_key" "$DIR/api_secret"
# LiveKit reads "key: secret" from a file; this copy is readable by the livekit user only.
( umask 037; printf '%s: %s\n' "$(cat "$DIR/api_key")" "$(cat "$DIR/api_secret")" > "$DIR/keys" )
chown root:livekit "$DIR/keys"; chmod 640 "$DIR/keys"

# --- LiveKit's configuration
PUBLIC_IP="$(curl -fsS -4 https://ifconfig.me || true)"
[ -n "$PUBLIC_IP" ] || { echo "could not find this server's public address" >&2; exit 1; }
cat > "$DIR/livekit.yaml" <<CONF
# Written by infra/sfu/setup.sh. Do not edit by hand.
port: 7880
bind_addresses:
  - "127.0.0.1"          # only Caddy (HTTPS/WSS on 443) reaches the signalling port
key_file: $DIR/keys
rtc:
  tcp_port: $TCP_PORT
  port_range_start: $MEDIA_MIN
  port_range_end: $MEDIA_MAX
  use_external_ip: false
  node_ip: $PUBLIC_IP    # no STUN lookup at all (the default would ask Google's)
  stun_servers:
    - $TURN_DOMAIN:3478  # clients are told to use Lime's own STUN, not Google's
  # TURN for the phones comes from the app (Lime's coturn, with time-limited credentials); none is configured here.
turn:
  enabled: false
room:
  auto_create: true
  max_participants: 100
  empty_timeout: 30
  departure_timeout: 20
logging:
  level: warn            # warn and above only: routine logs carry room names and addresses
  json: false
CONF
chown root:livekit "$DIR/livekit.yaml"; chmod 640 "$DIR/livekit.yaml"

cat > /etc/systemd/system/lime-sfu.service <<UNIT
[Unit]
Description=Lime group-call media server (LiveKit)
After=network-online.target
Wants=network-online.target

[Service]
User=livekit
Group=livekit
ExecStart=/usr/local/bin/livekit-server --config $DIR/livekit.yaml
Restart=always
RestartSec=2
LimitNOFILE=65536
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

# --- the firewall
ufw allow 22/tcp >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw allow ${TCP_PORT}/tcp >/dev/null
ufw allow ${MEDIA_MIN}:${MEDIA_MAX}/udp >/dev/null
ufw --force enable >/dev/null

# --- Caddy: HTTPS for the SFU, and the ACME challenge path for coturn's certificate (port 80)
install -d -m 755 "$ACME_ROOT" "$INVITE_ROOT"
INVITE_BLOCK=""
if [ -n "$INVITE_HOST" ]; then
  INVITE_BLOCK="
# The invite page: static files, no access log (nothing about who opened which link is kept). A browser never sends the part after #.
www.$INVITE_HOST {
	redir https://$INVITE_HOST{uri} permanent
}

$INVITE_HOST {
	root * $INVITE_ROOT
	header {
		Strict-Transport-Security \"max-age=31536000\"
		Referrer-Policy no-referrer
		X-Content-Type-Options nosniff
	}
	rewrite /u/* /u/index.html
	rewrite /b/* /u/index.html
	file_server
}
"
fi
cat > /etc/caddy/Caddyfile <<CADDY
# Written by infra/sfu/setup.sh. Do not edit by hand.
{
	email $EMAIL
}

$DOMAIN${ALT_DOMAIN:+, $ALT_DOMAIN} {
	reverse_proxy 127.0.0.1:7880
}

# coturn's certificate is renewed by certbot ("webroot"); Caddy only serves the challenge file, for both turn names.
http://$TURN_DOMAIN${TURN_ALT_DOMAIN:+, http://$TURN_ALT_DOMAIN} {
	handle /.well-known/acme-challenge/* {
		root * $ACME_ROOT
		file_server
	}
	respond 404
}
$INVITE_BLOCK
CADDY
systemctl enable caddy >/dev/null 2>&1
systemctl restart caddy

# --- coturn's certificate(s): standalone (needs port 80 to itself) -> webroot (Caddy answers on 80). Both lineages, the old one and the shared one.
for CERT in "$TURN_DOMAIN" "$TURN_CERT"; do
  RENEWAL="/etc/letsencrypt/renewal/$CERT.conf"
  [ -f "$RENEWAL" ] || continue
  if grep -q '^authenticator = standalone' "$RENEWAL"; then
    certbot reconfigure --non-interactive --cert-name "$CERT" --authenticator webroot --webroot-path "$ACME_ROOT" >/dev/null
  fi
  certbot renew --dry-run --cert-name "$CERT" >/dev/null 2>&1 \
    && echo "coturn's certificate $CERT renews through Caddy (dry run passed)" \
    || { echo "WARNING: the dry-run renewal of $CERT failed: check 'certbot renew --dry-run'" >&2; exit 1; }
done

systemctl daemon-reload
systemctl enable lime-sfu >/dev/null 2>&1
systemctl restart lime-sfu
sleep 3
systemctl is-active --quiet lime-sfu && echo "LiveKit $LIVEKIT_VERSION is running for $DOMAIN${ALT_DOMAIN:+ and $ALT_DOMAIN} (media $MEDIA_MIN-$MEDIA_MAX/udp, $TCP_PORT/tcp)" \
  || { systemctl status lime-sfu --no-pager | tail -20; exit 1; }
