#!/usr/bin/env bash
# Publishes lime's invite page (LIME-172d): copies invite-site/ to the call server, where Caddy serves it at limemessenger.com
# (the Caddy site itself is written by infra/sfu/setup.sh). Run from the repo root; safe to run again after any change to the page.
#
#   bash infra/invite/deploy.sh [root@host]      # default root@178.156.199.1
set -euo pipefail
HOST="${1:-root@178.156.199.1}"
cd "$(dirname "$0")/../.."
tar -C invite-site --exclude README.md -cf - . | ssh "$HOST" 'install -d -m 755 /srv/invite && find /srv/invite -mindepth 1 -delete && tar -C /srv/invite -xf - && chmod -R a+rX /srv/invite'
echo "invite page copied to $HOST:/srv/invite"
