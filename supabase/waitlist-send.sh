#!/bin/sh
# LIME-287a: sends the ONE launch email, or the ONE Android email, to the confirmed rows of a list. It is a DRY RUN (counts only) unless you add --send.
#
#   ./supabase/waitlist-send.sh staging launch  https://apps.apple.com/app/id000  --emails a@x.test,b@x.test        dry run for two addresses
#   ./supabase/waitlist-send.sh staging launch  https://apps.apple.com/app/id000  --emails a@x.test,b@x.test --send  send to those two only
#   ./supabase/waitlist-send.sh production launch <the App Store link> --send                                        launch day (see the runbook in TEND.md)
#   ./supabase/waitlist-send.sh production android <the Google Play link> --send                                     Android day
#
# `--emails` limits the run to those addresses (tests); without it every confirmed row of the list that has not had its email is sent to. A rerun sends nothing twice.
# The environment's service key is read from the CLI into memory only to authorise the call: it is never printed, written to a file or put on a command line.
# Needs `supabase login` and ~/.lime/<staging|production>.env (SUPABASE_PROJECT_REF).
set -e
cd "$(dirname "$0")/.."
ENVNAME="$1"; KIND="$2"; URL="$3"; shift 3 2>/dev/null || true
case "$ENVNAME" in staging|production) ;; *) echo "usage: $0 <staging|production> <launch|android> <store-url> [--emails a,b] [--send]" >&2; exit 2;; esac
case "$KIND" in launch|android) ;; *) echo "kind must be launch or android" >&2; exit 2;; esac
[ -n "$URL" ] || { echo "the store link is required" >&2; exit 2; }
EMAILS=""; SEND=false
while [ $# -gt 0 ]; do
  case "$1" in
    --send) SEND=true ;;
    --emails) shift; EMAILS="$1" ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
ENV_FILE="$HOME/.lime/$ENVNAME.env"
[ -f "$ENV_FILE" ] || { echo "Missing $ENV_FILE (SUPABASE_PROJECT_REF)." >&2; exit 1; }
set -a; . "$ENV_FILE"; set +a
[ -n "$SUPABASE_PROJECT_REF" ] || { echo "$ENV_FILE must set SUPABASE_PROJECT_REF." >&2; exit 1; }
SERVICE_KEY="$(supabase projects api-keys --project-ref "$SUPABASE_PROJECT_REF" -o json 2>/dev/null | python3 -c 'import sys, json
keys = json.load(sys.stdin)
pick = [k for k in keys if k.get("name") == "service_role"]
print(pick[0]["api_key"] if pick else "")')"
[ -n "$SERVICE_KEY" ] || { echo "Could not read the service key (supabase login?)." >&2; exit 1; }
ENDPOINT="https://$SUPABASE_PROJECT_REF.supabase.co/functions/v1/waitlist-send"
BODY="$(KIND="$KIND" URL="$URL" EMAILS="$EMAILS" SEND="$SEND" python3 -c 'import os, json
b = {"kind": os.environ["KIND"], "url": os.environ["URL"], "send": os.environ["SEND"] == "true"}
if os.environ["EMAILS"]: b["emails"] = [e for e in os.environ["EMAILS"].split(",") if e]
print(json.dumps(b))')"
call() {   # the key goes in through stdin as a curl config, never on the command line
  printf 'header = "authorization: Bearer %s"\n' "$SERVICE_KEY" | curl -s --config - -X POST "$ENDPOINT" -H "content-type: application/json" -d "$BODY" -w '\n%{http_code}'
}
echo "$ENVNAME / $KIND / send=$SEND${EMAILS:+ / only: $EMAILS}"
while :; do
  OUT="$(call)"; CODE="$(printf '%s' "$OUT" | tail -n 1)"; JSON="$(printf '%s' "$OUT" | sed '$d')"
  echo "[$CODE] $JSON"
  [ "$CODE" = "200" ] || exit 1
  [ "$SEND" = "true" ] || exit 0
  LEFT="$(printf '%s' "$JSON" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("remaining", 0))')"
  [ "$LEFT" -gt 0 ] || exit 0
done
