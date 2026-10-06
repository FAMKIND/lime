#!/bin/sh
# Runs the API v2 tests against the LOCAL Supabase stack (Docker via Colima). Starts the stack if
# it is not running. Throwaway users are created and deleted through the local admin API.
set -e
cd "$(dirname "$0")/.."

for tool in supabase deno docker; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing $tool. See supabase/README.md (Prerequisites)." >&2; exit 1; }
done
if ! docker info >/dev/null 2>&1; then
  command -v colima >/dev/null 2>&1 && { echo "Starting Colima..."; colima start; } || { echo "Docker is not running." >&2; exit 1; }
fi
supabase status >/dev/null 2>&1 || supabase start

eval "$(supabase status -o env | grep -E '^(API_URL|DB_URL|ANON_KEY|SERVICE_ROLE_KEY)=')"
export LIME_API_URL="$API_URL" LIME_DB_URL="$DB_URL" LIME_ANON_KEY="$ANON_KEY" LIME_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY"

exec deno test --allow-net --allow-env --allow-read supabase/tests/ "$@"
