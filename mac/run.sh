#!/bin/sh
# Builds the Debug Mac app, hands Ada Mac's tokens to it (handover.sh) and opens it. Start the partner afterwards: `mac/tools/partner/build/partner --as b echo`.
set -e
cd "$(dirname "$0")"
./generate.sh >/dev/null
xcodebuild -project LimeMac.xcodeproj -scheme LimeMac -destination 'platform=macOS,variant=Mac Catalyst' \
  -configuration Debug -derivedDataPath build/DerivedData -allowProvisioningUpdates build -quiet
./handover.sh
open -a "$PWD/build/DerivedData/Build/Products/Debug-maccatalyst/lime.app" --args -lime-use-test-account
echo "lime is open, signed in as Ada Mac"
