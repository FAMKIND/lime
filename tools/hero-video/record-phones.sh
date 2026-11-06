#!/bin/zsh
# LIME-284e2: record the two phone screens (jam feed scroll, a chat reply) on the iPhone 17 simulator.
# usage: tools/hero-video/record-phones.sh OUT_DIR   (then encode with the commands in TEND.md, LIME-284e2)
set -e
D=8AC7DD22-E8CE-4925-9441-E22973B8198E; OUT=${1:?out dir}; mkdir -p $OUT
cd "$(dirname $0)/../../ios"
cp ../tools/hero-video/PhoneRecordings.swift LimeUITests/PhoneRecordings.swift
xcodegen generate >/dev/null
xcodebuild build-for-testing -project Lime.xcodeproj -scheme Lime -destination "id=$D" -derivedDataPath $TMPDIR/dd28 | tail -1
xcrun simctl status_bar $D override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
for t in Jam Chat; do
  xcrun simctl io $D recordVideo --codec h264 --force $OUT/$t.mov >/dev/null 2>&1 &
  sleep 2
  xcodebuild test-without-building -project Lime.xcodeproj -scheme Lime -destination "id=$D" -derivedDataPath $TMPDIR/dd28 -only-testing:LimeUITests/PhoneRecordings/test$t | grep -E "passed|failed" | head -2
  pkill -INT -f "simctl io" || true; sleep 3
done
xcrun simctl status_bar $D clear
rm LimeUITests/PhoneRecordings.swift; xcodegen generate >/dev/null
