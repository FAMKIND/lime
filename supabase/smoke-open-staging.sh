#!/bin/sh
# Smoke-tests the open-posts server pieces on STAGING with open_posts_enabled OFF (LIME-210a). Throwaway user, deleted afterwards. Never turns the flag on.
set -e
cd "$(dirname "$0")/.."
set -a
. "$HOME/.lime/staging.env"
. supabase/.staging.public.env
set +a
SERVICE_ROLE_KEY="$(supabase projects api-keys --project-ref "$SUPABASE_PROJECT_REF" -o json 2>/dev/null |
  python3 -c 'import sys, json
keys = json.load(sys.stdin)
pick = [k for k in keys if k.get("name") == "service_role" or k.get("type") == "secret"]
print(pick[0]["api_key"] if pick else "")')"
[ -n "$SERVICE_ROLE_KEY" ] || { echo "Could not read the service key." >&2; exit 1; }
export LIME_API_URL="$SUPABASE_URL" LIME_ANON_KEY="$SUPABASE_ANON_KEY" LIME_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY"
exec deno run --allow-net --allow-env --allow-read supabase/tests/smoke_open_staging.ts
