#!/bin/zsh
# LIME-284c3f: touches the hero in the iOS simulator's Safari (a tap, a hold and drag, scrolling, a swipe) and records the screen. Needs the site served on :8099 (python3 -m http.server 8099 -d site/com).
set -e
D=8AC7DD22-E8CE-4925-9441-E22973B8198E; mkdir -p /tmp/284c3f
cd "$(dirname $0)/../../ios"
cp ../tools/hero-video/SafariTouch.swift LimeUITests/SafariTouch.swift
xcodegen generate >/dev/null
xcodebuild build-for-testing -project Lime.xcodeproj -scheme Lime -destination "id=$D" -derivedDataPath $TMPDIR/dd28 | tail -1
xcrun simctl terminate $D com.apple.mobilesafari >/dev/null 2>&1 || true
xcrun simctl openurl $D "http://localhost:8099/"; sleep 5
xcrun simctl io $D recordVideo --codec h264 --force /tmp/284c3f/ios-touch.mp4 & REC=$!
sleep 2
xcodebuild test-without-building -project Lime.xcodeproj -scheme Lime -destination "id=$D" -derivedDataPath $TMPDIR/dd28 -only-testing:LimeUITests/SafariTouch/testTouch | grep -E "passed|failed|error:" | head -3 || true
kill -INT $REC; wait $REC 2>/dev/null || true
rm LimeUITests/SafariTouch.swift; xcodegen generate >/dev/null
