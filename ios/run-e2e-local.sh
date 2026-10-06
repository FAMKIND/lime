#!/bin/sh
# Runs the app's end-to-end test against the LOCAL Supabase stack: LiveAuthService, AccountSession,
# URLSessionTransport and LimeCore against the real server functions, with the emailed codes read
# from the local mail catcher. Starts the stack if needed. Nothing secret is written down.
set -e
cd "$(dirname "$0")/.."
supabase status >/dev/null 2>&1 || supabase start
supabase migration up --local >/dev/null 2>&1 || true
docker restart supabase_edge_runtime_lime >/dev/null 2>&1 || true
sleep 3
eval "$(supabase status -o env | grep -E '^(API_URL|ANON_KEY)=')"
cd ios
export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"
TEST_RUNNER_LIME_E2E_API_URL="$API_URL" TEST_RUNNER_LIME_E2E_ANON_KEY="$ANON_KEY" TEST_RUNNER_LIME_E2E_MAIL_URL="http://127.0.0.1:54324" \
  xcodebuild test -scheme Lime -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:LimeTests/LocalBackendE2ETests
