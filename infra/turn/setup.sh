#!/usr/bin/env bash
# Installs and configures coturn (Lime's TURN relay) on a fresh Ubuntu server. Idempotent: run it again to repair or update.
#
#   ssh root@<server> 'bash -s' < infra/turn/setup.sh
#
# What it does: installs coturn and certbot; gets a TLS certificate for $DOMAIN (the A record must already point here);
# writes /etc/turnserver.conf with time-limited REST credentials (`use-auth-secret`); opens the firewall; starts coturn.
# The shared secret is created once, at /etc/lime-turn/secret (root only, never printed). Supabase's `turn-credentials`
# function needs the same value (see infra/turn/README.md for how to copy it without it appearing anywhere).
set -euo pipefail

DOMAIN="${DOMAIN:-turn.limechat.org}"
EMAIL="${EMAIL:-shem@limechat.org}"
RELAY_MIN=49152
RELAY_MAX=49999
SECRET_FILE=/etc/lime-turn/secret

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq coturn certbot ufw curl >/dev/null

# --- the shared secret (created once, kept on this server only)
# The folder is traversable by coturn (for the certificate copy); the secret file itself stays root-only (600).
install -d -m 750 -g turnserver /etc/lime-turn
if [ ! -s "$SECRET_FILE" ]; then
  umask 077
  head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$SECRET_FILE"
fi
chmod 600 "$SECRET_FILE"

# --- firewall
ufw allow 22/tcp >/dev/null
ufw allow 80/tcp >/dev/null            # certificate issuing and renewals
ufw allow 3478/tcp >/dev/null
ufw allow 3478/udp >/dev/null
ufw allow 5349/tcp >/dev/null
ufw allow 5349/udp >/dev/null
ufw allow ${RELAY_MIN}:${RELAY_MAX}/udp >/dev/null
ufw --force enable >/dev/null

# --- the certificate
if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  certbot certonly --standalone --non-interactive --agree-tos -m "$EMAIL" -d "$DOMAIN"
fi
# coturn runs as an unprivileged user: it gets its own readable copy of the certificate, refreshed on every renewal.
install -d -m 750 -o root -g turnserver /etc/lime-turn/tls
cat > /etc/letsencrypt/renewal-hooks/deploy/lime-turn.sh <<HOOK
#!/bin/sh
cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /etc/lime-turn/tls/fullchain.pem
cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /etc/lime-turn/tls/privkey.pem
chown root:turnserver /etc/lime-turn/tls/*.pem
chmod 640 /etc/lime-turn/tls/*.pem
systemctl restart coturn
HOOK
chmod 755 /etc/letsencrypt/renewal-hooks/deploy/lime-turn.sh
RENEWED_LINEAGE=1 /etc/letsencrypt/renewal-hooks/deploy/lime-turn.sh || true

# --- coturn
PUBLIC_IP="$(curl -fsS -4 https://ifconfig.me || true)"
cat > /etc/turnserver.conf <<CONF
# Written by infra/turn/setup.sh. Do not edit by hand.
listening-port=3478
tls-listening-port=5349
fingerprint
realm=$DOMAIN
server-name=$DOMAIN

# Time-limited credentials (the coturn REST API): username "<expiry>:<user>", password = base64(HMAC-SHA1(secret, username)).
use-auth-secret
static-auth-secret=$(cat "$SECRET_FILE")

cert=/etc/lime-turn/tls/fullchain.pem
pkey=/etc/lime-turn/tls/privkey.pem
no-tlsv1
no-tlsv1_1

min-port=$RELAY_MIN
max-port=$RELAY_MAX
${PUBLIC_IP:+external-ip=$PUBLIC_IP}

# Relay for calls only: no CLI, no peers on private or local networks, bounded use.
no-cli
no-multicast-peers
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=100.64.0.0-100.127.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=169.254.0.0-169.254.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.0.0.0-192.0.0.255
denied-peer-ip=192.168.0.0-192.168.255.255
denied-peer-ip=224.0.0.0-255.255.255.255
user-quota=12
total-quota=600
stale-nonce=600
log-file=/var/log/turnserver/turn.log
simple-log
CONF
chmod 640 /etc/turnserver.conf
chown root:turnserver /etc/turnserver.conf
install -d -o turnserver -g turnserver /var/log/turnserver

# Some packages ship an "enabled" switch.
[ -f /etc/default/coturn ] && sed -i 's/^#\?TURNSERVER_ENABLED=.*/TURNSERVER_ENABLED=1/' /etc/default/coturn || true
systemctl enable coturn >/dev/null 2>&1
systemctl restart coturn
sleep 2
systemctl is-active --quiet coturn && echo "coturn is running for $DOMAIN (relay ports $RELAY_MIN-$RELAY_MAX)" || { systemctl status coturn --no-pager | tail -20; exit 1; }
