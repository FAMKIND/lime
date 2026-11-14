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
xcodebuild test -project LimeMac.xcodeproj -scheme LimeMac -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath build/DerivedData -allowProvisioningUpdates -only-testing:LimeMacUITests
