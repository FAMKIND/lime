#!/usr/bin/env bash
# Publishes limemessenger.com (LIME-172d, LIME-284c2, LIME-289), copied to the call server, where Caddy serves it at limemessenger.com (the Caddy site itself is written by
# infra/sfu/setup.sh and does not change when this runs). It replaces /srv/invite wholesale; run it from the repo root; safe to run again after any change.
# `/u/*` and `/b/*` still show u/index.html (Caddy rewrites them); /privacy, /terms, /guidelines, /safety, /security and /.well-known/security.txt come from invite-site/.
#
#   bash infra/invite/deploy.sh [root@host]                 # DEFAULT (LIME-289): the public landing at /, the full site at /preview/ (behind the team login), invite + legal
#   bash infra/invite/deploy.sh --full [root@host]          # going public: the full site (site/com) at /, invite + legal; no landing, no /preview/
#   bash infra/invite/deploy.sh --invite-only [root@host]   # the old one-line holding page instead
#   add  --out DIR  to build the same layout into DIR on this machine and copy nothing (a dry run; DIR is created and must be empty)
# Default host root@178.156.199.1.
set -euo pipefail
MODE=landing; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --full) MODE=full; shift ;;
    --invite-only) MODE=holding; shift ;;
    --out) OUT="${2:?--out needs a directory}"; shift 2 ;;
    --*) echo "Unknown option $1" >&2; exit 2 ;;
    *) break ;;
  esac
done
HOST="${1:-root@178.156.199.1}"
cd "$(dirname "$0")/../.."
# A page that still carries placeholder people must not go out (LIME-284c3c: `data-illustrative` marks examples that are labelled; `data-placeholder` marks ones that are not).
if grep -rn "data-placeholder" site/com site/landing >&2; then echo "Refusing to publish: a site page still has data-placeholder (see above). Label it (data-illustrative) or replace it." >&2; exit 1; fi
if [ -n "$OUT" ]; then
  [ -z "$(ls -A "$OUT" 2>/dev/null)" ] || { echo "--out $OUT must be empty or new." >&2; exit 2; }
  mkdir -p "$OUT"; STAGE="$OUT"
else
  STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
fi
# the invite page and the legal pages come first in every layout
tar -C invite-site --exclude README.md -cf - . | tar -C "$STAGE" -xf -
case "$MODE" in
  full)
    # today's layout: the full site's files over them (its index.html and brand/ replace the holding page's)
    tar -C site/com --exclude '*.md' -cf - . | tar -C "$STAGE" -xf -
    ;;
  landing)
    # the list's small pages are public (the emails link to them), with what they use
    tar -C site/com -cf - android-list check-email confirmed get left try-again mini.css LICENSES.txt brand fonts | tar -C "$STAGE" -xf -
    # the landing, and only the media it uses: the three hero videos (both shapes, both codecs) and their posters
    tar -C site/landing -cf - . | tar -C "$STAGE" -xf -
    mkdir -p "$STAGE/media"
    ( cd site/com/media && tar -cf - $(ls hero-wide* hero2-wide* hero3-wide* hero-tall* hero2-tall* hero3-tall* | grep -v -e '-px\.mp4$') ) | tar -C "$STAGE/media" -xf -
    # the full site, for the team, under /preview/ (marked so it is never mistaken for the public site)
    mkdir -p "$STAGE/preview"
    tar -C site/com --exclude '*.md' -cf - . | tar -C "$STAGE/preview" -xf -
    sed -e 's|<!--preview-tag-->|<span class="ptag" role="note">Preview: not public</span>|' -e 's|<title>lime: |<title>Preview · lime: |' "$STAGE/preview/index.html" > "$STAGE/preview/index.html.new" && mv "$STAGE/preview/index.html.new" "$STAGE/preview/index.html"
    grep -q 'class="ptag"' "$STAGE/preview/index.html" || { echo "The preview tag did not go in (no <!--preview-tag--> in site/com/index.html)." >&2; exit 1; }
    ;;
  holding) ;;
esac
LAYOUT=$([ "$MODE" = holding ] && echo "holding page" || { [ "$MODE" = full ] && echo "the full site at the root + invite + legal" || echo "landing + /preview/ + invite + legal"; })
if [ -n "$OUT" ]; then echo "Built into $OUT ($LAYOUT); nothing copied."; exit 0; fi
tar -C "$STAGE" -cf - . | ssh "$HOST" 'install -d -m 755 /srv/invite && find /srv/invite -mindepth 1 -delete && tar -C /srv/invite -xf - && chmod -R a+rX /srv/invite'
echo "limemessenger.com copied to $HOST:/srv/invite ($LAYOUT)"
