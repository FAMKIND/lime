#!/bin/sh
# Runs the Mac UI test (LimeMacUITests) against staging as Ada Mac, with the partner answering as Ben Mac.
set -e
cd "$(dirname "$0")"
./generate.sh >/dev/null
./handover.sh
tools/partner/build/partner --as b echo > "${TMPDIR:-/tmp}/lime-mac-echo.log" 2>&1 &
ECHO=$!
trap 'kill $ECHO 2>/dev/null' EXIT
sleep 6
# The partner dies at start-up when staging refuses it (e.g. RateLimited): stop here with its log instead of running a test that cannot pass.
if ! kill -0 "$ECHO" 2>/dev/null; then
  echo "Ben's partner is not running; its log says:" >&2
  tail -n 5 "${TMPDIR:-/tmp}/lime-mac-echo.log" >&2
  exit 1
fi
xcodebuild test -project LimeMac.xcodeproj -scheme LimeMac -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath build/DerivedData -allowProvisioningUpdates -only-testing:LimeMacUITests
