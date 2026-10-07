#!/bin/sh
# Runs the two-phone chat test against STAGING: the real app code (LiveAuthService, AccountSession,
# URLSessionTransport, the Realtime nudge listener, LimeCore) with two throwaway accounts made and
# deleted through the admin API. No email is sent and no inbox is read. The service key is read from
# the Supabase CLI into this process's environment only; it is never printed or written to disk.
set -e
cd "$(dirname "$0")/.."
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
ANON="$(pick anon)"
SERVICE="$(pick service_role)"
unset keys SUPABASE_DB_PASSWORD
cd ios
export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"
TEST_RUNNER_LIME_E2E_API_URL="https://$SUPABASE_PROJECT_REF.supabase.co" TEST_RUNNER_LIME_E2E_ANON_KEY="$ANON" \
  TEST_RUNNER_LIME_E2E_SERVICE_KEY="$SERVICE" \
  xcodebuild test -scheme Lime -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:LimeTests/LocalBackendE2ETests/testTwoPhonesChatLiveOnStaging 2>&1 | grep -E "error:|Test Case|TEST (SUCCEEDED|FAILED)|Timed out|XCTAssert|skipped"
