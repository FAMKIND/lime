#!/usr/bin/env bash
# Publishes limemessenger.com (LIME-172d, LIME-284c2): the home page and its small pages (site/com/) with the invite page, the legal pages and /.well-known (invite-site/) laid over
# it, copied to the call server, where Caddy serves them at limemessenger.com (the Caddy site itself is written by infra/sfu/setup.sh and does not change).
# `/u/*` and `/b/*` still show u/index.html (Caddy rewrites them); /privacy, /terms, /guidelines, /safety, /security and /.well-known/security.txt come from invite-site/.
# Run from the repo root; safe to run again after any change. It replaces /srv/invite wholesale.
#
#   bash infra/invite/deploy.sh [root@host]                 # the home page + invite + legal (default root@178.156.199.1)
#   bash infra/invite/deploy.sh --invite-only [root@host]   # the old one-line holding page instead of the home page
set -euo pipefail
ONLY=0; [ "${1:-}" = "--invite-only" ] && { ONLY=1; shift; }
HOST="${1:-root@178.156.199.1}"
cd "$(dirname "$0")/../.."
# A page that still carries placeholder people must not go out (LIME-284c3c: `data-illustrative` marks examples that are labelled; `data-placeholder` marks ones that are not).
if grep -rn "data-placeholder" site/com >&2; then echo "Refusing to publish: site/com still has data-placeholder (see above). Label it (data-illustrative) or replace it." >&2; exit 1; fi
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
if [ "$ONLY" = 0 ]; then
  # The invite page and the legal pages first, then the home page's files over them (its index.html and brand/ replace the holding page's).
  tar -C invite-site --exclude README.md -cf - . | tar -C "$STAGE" -xf -
  tar -C site/com --exclude '*.md' -cf - . | tar -C "$STAGE" -xf -
else
  tar -C invite-site --exclude README.md -cf - . | tar -C "$STAGE" -xf -
fi
tar -C "$STAGE" -cf - . | ssh "$HOST" 'install -d -m 755 /srv/invite && find /srv/invite -mindepth 1 -delete && tar -C /srv/invite -xf - && chmod -R a+rX /srv/invite'
echo "limemessenger.com copied to $HOST:/srv/invite ($([ "$ONLY" = 1 ] && echo "holding page" || echo "home page + invite + legal"))"
