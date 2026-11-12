#!/bin/sh
# The Back-with-a-number screenshots for LIME-409 (0, 3, 99+, 200% font, dark). Saved OUTSIDE the repo.   tools/shots-409.sh [<out dir>] [<avd>]
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
OUT="${1:-$HOME/Desktop/lime-android-night4/409}"; AVD="${2:-lime-api36}"
mkdir -p "${OUT:?}"; rm -f "${OUT:?}"/*.png
tools/emu.sh start "$AVD" >/dev/null || exit 1
adb shell settings put system font_scale 1.0; adb shell cmd uimode night no >/dev/null; adb shell settings put system accelerometer_rotation 0; adb shell settings put system user_rotation 0
adb uninstall com.limemessenger.lime >/dev/null 2>&1; adb uninstall com.limemessenger.lime.test >/dev/null 2>&1
./gradlew -q installDebug installDebugAndroidTest || exit 1
run() { adb shell am instrument -w -e class "com.limemessenger.lime.BackCountShotsTest#$1" com.limemessenger.lime.test/androidx.test.runner.AndroidJUnitRunner | grep -E '^(OK|FAILURES)'; }
for t in none three ninetyNinePlus largestFont largestFontOver99 dark; do echo "$t: $(run $t)"; done
adb shell settings put system user_rotation 0; adb shell settings put system accelerometer_rotation 1
for f in $(adb shell run-as com.limemessenger.lime ls files/shots 2>/dev/null | tr -d '\r'); do
  adb exec-out run-as com.limemessenger.lime cat "files/shots/$f" > "${OUT:?}/$f"
done
tools/emu.sh stop
echo "saved to $OUT"
