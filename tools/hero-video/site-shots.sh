#!/bin/zsh
# LIME-286r: capture the app's real screens for the website into /tmp/286r/shots (iPhone 17 simulator, status bar 9:41).
set -e
D=8AC7DD22-E8CE-4925-9441-E22973B8198E; mkdir -p /tmp/286r/shots
cd "$(dirname $0)/../../ios"
cp ../tools/hero-video/SiteShots.swift LimeUITests/SiteShots.swift
xcodegen generate >/dev/null
xcodebuild build-for-testing -project Lime.xcodeproj -scheme Lime -destination "id=$D" -derivedDataPath $TMPDIR/dd28 | tee $TMPDIR/dd28-build.log | tail -1
# LIME-349b: a failed build used to be swallowed and the tests then ran against the PREVIOUS app (stale seeds). Stop instead (a damaged package cache: delete $TMPDIR/dd28).
grep -q "TEST BUILD SUCCEEDED" $TMPDIR/dd28-build.log || { echo "BUILD FAILED: see $TMPDIR/dd28-build.log (delete $TMPDIR/dd28 and retry)"; exit 1; }
xcrun simctl status_bar $D override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
BARS="--cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3"
for t in ${=1:-testChats testGroup testCall testCallMini testOfflineNoSignal testOfflineSent testThemes}; do
  # LIME-349c: the two offline shots that show "no connection" have Wi-Fi off and no service in the status bar.
  if [[ $t == testOfflineNoSignal ]]; then xcrun simctl status_bar $D override --cellularMode failed --cellularBars 0 --wifiMode failed --wifiBars 0 --operatorName ""; else xcrun simctl status_bar $D override ${=BARS}; fi
  xcodebuild test-without-building -project Lime.xcodeproj -scheme Lime -destination "id=$D" -derivedDataPath $TMPDIR/dd28 -only-testing:LimeUITests/SiteShots/$t | grep -E "passed|failed|error:" | head -3
done
xcrun simctl status_bar $D clear
rm LimeUITests/SiteShots.swift; xcodegen generate >/dev/null
