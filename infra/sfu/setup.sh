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

DOMAIN="${DOMAIN:-sfu.limechat.org}"
TURN_DOMAIN="${TURN_DOMAIN:-turn.limechat.org}"
EMAIL="${EMAIL:-shem@limechat.org}"
LIVEKIT_VERSION=1.13.9
SHA256_AMD64=0b7fa208b662d09cfdeae8c06cf4c481aead0556086558b48250501e2e2d6e20
SHA256_ARM64=c5e4e5a6d6cf0a449651aa3178532ecc7a2bf2502538396ebe6e51ff13424056
MEDIA_MIN=50000      # UDP media; must not overlap coturn's relay range 49152-49999
MEDIA_MAX=60000
TCP_PORT=7881        # ICE over TCP, for networks that block UDP
DIR=/etc/lime-sfu
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
install -d -m 755 "$ACME_ROOT"
cat > /etc/caddy/Caddyfile <<CADDY
# Written by infra/sfu/setup.sh. Do not edit by hand.
{
	email $EMAIL
}

$DOMAIN {
	reverse_proxy 127.0.0.1:7880
}

# coturn's certificate is renewed by certbot ("webroot"); Caddy only serves the challenge file.
http://$TURN_DOMAIN {
	handle /.well-known/acme-challenge/* {
		root * $ACME_ROOT
		file_server
	}
	respond 404
}
CADDY
systemctl enable caddy >/dev/null 2>&1
systemctl restart caddy

# --- coturn's certificate: standalone (needs port 80 to itself) -> webroot (Caddy answers on 80)
RENEWAL="/etc/letsencrypt/renewal/$TURN_DOMAIN.conf"
if [ -f "$RENEWAL" ] && grep -q '^authenticator = standalone' "$RENEWAL"; then
  certbot reconfigure --non-interactive --cert-name "$TURN_DOMAIN" --authenticator webroot --webroot-path "$ACME_ROOT" >/dev/null
fi
if [ -f "$RENEWAL" ]; then
  certbot renew --dry-run --cert-name "$TURN_DOMAIN" >/dev/null 2>&1 \
    && echo "coturn's certificate renewal works through Caddy (dry run passed)" \
    || { echo "WARNING: the dry-run renewal of $TURN_DOMAIN failed: check 'certbot renew --dry-run'" >&2; exit 1; }
fi

systemctl daemon-reload
systemctl enable lime-sfu >/dev/null 2>&1
systemctl restart lime-sfu
sleep 3
systemctl is-active --quiet lime-sfu && echo "LiveKit $LIVEKIT_VERSION is running for $DOMAIN (media $MEDIA_MIN-$MEDIA_MAX/udp, $TCP_PORT/tcp)" \
  || { systemctl status lime-sfu --no-pager | tail -20; exit 1; }
