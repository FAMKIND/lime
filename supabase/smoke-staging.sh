#!/bin/sh
# A smoke test against STAGING: two throwaway users, one device each, one sealed send, one fetch,
# one ack. Then it deletes the throwaway users. The service-role key is read from the Supabase
# CLI into this process's memory only, to create and delete the users; it is never printed or
# written anywhere.
set -e
cd "$(dirname "$0")/.."
ENV_FILE="$HOME/.lime/staging.env"
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a
[ -f supabase/.staging.public.env ] || { echo "Run ./supabase/deploy-staging.sh first." >&2; exit 1; }
set -a
. supabase/.staging.public.env
set +a
SERVICE_ROLE_KEY="$(supabase projects api-keys --project-ref "$SUPABASE_PROJECT_REF" -o json 2>/dev/null |
  python3 -c 'import sys, json
keys = json.load(sys.stdin)
pick = [k for k in keys if k.get("name") == "service_role" or k.get("type") == "secret"]
print(pick[0]["api_key"] if pick else "")')"
[ -n "$SERVICE_ROLE_KEY" ] || { echo "Could not read the service key." >&2; exit 1; }
export LIME_API_URL="$SUPABASE_URL" LIME_ANON_KEY="$SUPABASE_ANON_KEY" LIME_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY"
exec deno run --allow-net --allow-env --allow-read supabase/tests/smoke_staging.ts
