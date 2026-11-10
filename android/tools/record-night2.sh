#!/bin/sh
# Films the night-2 walk-through (groups, actions, list controls, search, Appearance, Lock lime, a voice message) on a headless emulator and saves the clip +
# screenshots OUTSIDE the repo.
#   tools/record-night2.sh [<out dir>] [<avd>]      defaults: ~/Desktop/lime-android-night2  lime-api36
# It installs the debug app, pushes fresh Ada/Ben/Cleo sessions, starts Ben and Cleo (`partner group-echo --direct`, one process each), runs Night2RecordingTest under
# `screenrecord`, then takes a largest-font and a dark-mode screenshot. Both partners and the emulator stop at the end.
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
OUT="${1:-$HOME/Desktop/lime-android-night2}"; AVD="${2:-lime-api36}"
mkdir -p "${OUT:?}"; rm -f "${OUT:?}"/*.png
tools/emu.sh start "$AVD" >/dev/null || exit 1
adb shell settings put system font_scale 1.0; adb shell cmd uimode night no >/dev/null
adb uninstall com.limemessenger.lime >/dev/null 2>&1
./gradlew -q installDebug installDebugAndroidTest || exit 1
adb shell pm grant com.limemessenger.lime android.permission.RECORD_AUDIO
tools/staging-test-accounts.sh --push >/dev/null || exit 1
tools/partner/run reset >/dev/null; tools/partner/run reset --as cleo >/dev/null
tools/partner/run group-echo --direct >/tmp/lime-partner.log 2>&1 &
ben=$!
tools/partner/run group-echo --direct --as cleo >/tmp/lime-partner-cleo.log 2>&1 &
cleo=$!
sleep 12
adb shell rm -f /sdcard/lime-night2.mp4
adb shell screenrecord --size 540x1200 --bit-rate 4000000 --time-limit 175 /sdcard/lime-night2.mp4 &
rec=$!
sleep 2
result="$(adb shell am instrument -w -e annotation com.limemessenger.lime.Staging -e class com.limemessenger.lime.Night2RecordingTest com.limemessenger.lime.test/androidx.test.runner.AndroidJUnitRunner)"
echo "$result" | grep -E '^(OK|FAILURES)'
adb shell pkill -2 screenrecord; wait $rec 2>/dev/null; sleep 2
adb pull /sdcard/lime-night2.mp4 "${OUT:?}/$(date +%H%M)-night2.mp4" >/dev/null
for f in $(adb shell run-as com.limemessenger.lime ls files/shots 2>/dev/null | tr -d '\r'); do
  adb exec-out run-as com.limemessenger.lime cat "files/shots/$f" > "${OUT:?}/$f"
done
# The signed-in app at the largest font, then in dark mode.
adb shell settings put system font_scale 2.0
adb shell am force-stop com.limemessenger.lime; adb shell am start -n com.limemessenger.lime/.MainActivity >/dev/null; sleep 14
adb exec-out screencap -p > "${OUT:?}/11-largest-font.png"
adb shell settings put system font_scale 1.0; adb shell cmd uimode night yes >/dev/null; sleep 5
adb exec-out screencap -p > "${OUT:?}/12-dark.png"
adb shell cmd uimode night no >/dev/null
kill "$ben" "$cleo" 2>/dev/null; pkill -f "MainKt group-echo" 2>/dev/null
tools/emu.sh stop
echo "saved to $OUT"; echo "$result" | grep -q "^OK"
