#!/bin/sh
# Runs the LimeCore integration tests against a real Supabase stack.
#
#   ./core/run-integration.sh            the LOCAL stack (starts it if needed)
#   ./core/run-integration.sh staging    the STAGING project (needs `supabase login` and ~/.lime/staging.env)
#
# Nothing secret is written to disk or printed: the keys are read into this process's environment
# only. Throwaway accounts are created and deleted by the test itself.
set -e
cd "$(dirname "$0")"
PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"

if [ "$1" = "staging" ]; then
  ENV_FILE="$HOME/.lime/staging.env"
  [ -f "$ENV_FILE" ] || { echo "Missing $ENV_FILE." >&2; exit 1; }
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
  keys="$(supabase projects api-keys --project-ref "$SUPABASE_PROJECT_REF" -o json 2>/dev/null)"
  pick() { printf '%s' "$keys" | python3 -c "import sys, json
keys = json.load(sys.stdin)
want = '$1'
for k in keys:
    if k.get('name') == want or (want == 'anon' and k.get('type') == 'publishable') or (want == 'service_role' and k.get('type') == 'secret'):
        print(k['api_key']); break"; }
  export LIME_API_URL="https://$SUPABASE_PROJECT_REF.supabase.co"
  export LIME_ANON_KEY="$(pick anon)" LIME_SERVICE_ROLE_KEY="$(pick service_role)"
  unset keys SUPABASE_DB_PASSWORD
else
  cd ..
  supabase status >/dev/null 2>&1 || supabase start
  supabase migration up --local >/dev/null 2>&1 || true
  eval "$(supabase status -o env | grep -E '^(API_URL|ANON_KEY|SERVICE_ROLE_KEY)=')"
  export LIME_API_URL="$API_URL" LIME_ANON_KEY="$ANON_KEY" LIME_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY"
  cd core
fi
[ -n "$LIME_ANON_KEY" ] && [ -n "$LIME_SERVICE_ROLE_KEY" ] || { echo "Could not read the API keys." >&2; exit 1; }
# LIME_TEST_FILTER=call_signalling runs just the tests whose name contains it.
exec cargo test --features integration --test integration $LIME_TEST_FILTER -- --test-threads=1 --nocapture
