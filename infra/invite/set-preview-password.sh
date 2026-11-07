#!/usr/bin/env bash
# Sets (or changes) the password for limemessenger.com/preview/ (LIME-289). Run it yourself in the Terminal app: it asks for the password with
# nothing shown, makes a bcrypt hash here, and sends only the hash to the call server, where Caddy reads it (/etc/caddy/preview-auth.caddy, readable by
# root and caddy only). The password itself is never written anywhere, never put on a command line, never sent. The user name is "team".
# Safe to run again: it replaces the old password, and (once infra/sfu/setup.sh has put the login in the Caddyfile) reloads Caddy so the change is live at once.
#
#   bash infra/invite/set-preview-password.sh [root@host]     # default root@178.156.199.1
set -euo pipefail
HOST="${1:-root@178.156.199.1}"
command -v htpasswd >/dev/null || { echo "htpasswd is missing (it ships with macOS)." >&2; exit 1; }
[ -t 0 ] || { echo "Run this in the Terminal app: it needs to ask you for the password." >&2; exit 1; }
read -rs -p "Preview password (12 or more characters): " P; echo
read -rs -p "Again: " Q; echo
[ "$P" = "$Q" ] || { echo "The two did not match. Nothing was saved." >&2; exit 1; }
[ "${#P}" -ge 12 ] || { echo "Too short (12 or more characters). Nothing was saved." >&2; exit 1; }
HASH="$(printf '%s' "$P" | htpasswd -niBC 12 team | cut -d: -f2- | tr -d '\r\n')"; unset P Q
case "$HASH" in '$2'*) ;; *) echo "Could not make the hash. Nothing was saved." >&2; exit 1 ;; esac
# The hash goes in on ssh's stdin (it has $ characters in it) into a new file, which replaces the old one only if Caddy still accepts the whole config.
REMOTE='set -euo pipefail
F=/etc/caddy/preview-auth.caddy
read -r H
case "$H" in \$2*) ;; *) echo "not a bcrypt hash" >&2; exit 1 ;; esac
install -d -m 755 /etc/caddy
umask 027
printf "basicauth @preview {\n\tteam %s\n}\n" "$H" > "$F.new"
chgrp caddy "$F.new"; chmod 640 "$F.new"
[ -f "$F" ] && cp -p "$F" "$F.old" || true
mv -f "$F.new" "$F"
if grep -q "import $F" /etc/caddy/Caddyfile 2>/dev/null; then   # the login is already in the Caddyfile: make it live
  if caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1 && systemctl reload caddy; then rm -f "$F.old"
  else [ -f "$F.old" ] && mv -f "$F.old" "$F"; echo "Caddy did not accept the new login; the old one is back." >&2; exit 1; fi
fi'
printf '%s\n' "$HASH" | ssh "$HOST" "$REMOTE"
unset HASH
echo saved
