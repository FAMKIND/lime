#!/bin/sh
# Films the scripted walk-through on a headless emulator and saves the clip + screenshots OUTSIDE the repo.
#   tools/record-demo.sh [<out dir>] [<avd>]      defaults: ~/Desktop/lime-android-prototype  lime-api36
# It installs the debug app, pushes fresh Ada/Ben sessions, starts Ben (partner echo), runs DemoRecordingTest under `screenrecord`, then takes
# a largest-font and a dark-mode screenshot of the signed-in app. Ben stops and the emulator shuts down at the end.
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
OUT="${1:-$HOME/Desktop/lime-android-prototype}"; AVD="${2:-lime-api36}"
mkdir -p "$OUT"
tools/emu.sh start "$AVD" >/dev/null || exit 1
adb shell settings put system font_scale 1.0; adb shell cmd uimode night no >/dev/null
adb uninstall com.limemessenger.lime >/dev/null 2>&1
./gradlew -q installDebug installDebugAndroidTest || exit 1
tools/staging-test-accounts.sh --push >/dev/null || exit 1
tools/partner/run reset >/dev/null; tools/partner/run echo >/tmp/lime-partner.log 2>&1 &
partner=$!
adb shell rm -f /sdcard/lime-demo.mp4
adb shell screenrecord --size 540x1200 --bit-rate 4000000 --time-limit 170 /sdcard/lime-demo.mp4 &
rec=$!
sleep 2
result="$(adb shell am instrument -w -e annotation com.limemessenger.lime.Staging -e class com.limemessenger.lime.DemoRecordingTest com.limemessenger.lime.test/androidx.test.runner.AndroidJUnitRunner)"
echo "$result" | grep -E '^(OK|FAILURES)'
adb shell pkill -2 screenrecord; wait $rec 2>/dev/null; sleep 2
adb pull /sdcard/lime-demo.mp4 "$OUT/$(date +%H%M)-walkthrough.mp4" >/dev/null
for f in $(adb shell run-as com.limemessenger.lime ls files/shots 2>/dev/null | tr -d '\r'); do
  adb exec-out run-as com.limemessenger.lime cat "files/shots/$f" > "$OUT/$f"
done
# The signed-in app at the largest font, then in dark mode.
adb shell settings put system font_scale 2.0
adb shell am force-stop com.limemessenger.lime; adb shell am start -n com.limemessenger.lime/.MainActivity >/dev/null; sleep 12
adb exec-out screencap -p > "$OUT/9-largest-font.png"
adb shell settings put system font_scale 1.0; adb shell cmd uimode night yes >/dev/null; sleep 5
adb exec-out screencap -p > "$OUT/10-dark.png"
adb shell cmd uimode night no >/dev/null
kill "$partner" 2>/dev/null; pkill -f "MainKt echo" 2>/dev/null
tools/emu.sh stop
echo "saved to $OUT"; echo "$result" | grep -q "^OK"
