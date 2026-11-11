#!/bin/sh
# The link-card screenshots for LIME-407 (the draft card, the bubble card, the Privacy row; dark and 200% font). Saved OUTSIDE the repo.   tools/shots-407.sh [<out dir>] [<avd>]      defaults: ~/Desktop/lime-android-407  lime-api36
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
OUT="${1:-$HOME/Desktop/lime-android-407}"; AVD="${2:-lime-api36}"
mkdir -p "${OUT:?}"; rm -f "${OUT:?}"/*.png
tools/emu.sh start "$AVD" >/dev/null || exit 1
adb shell settings put system font_scale 1.0; adb shell cmd uimode night no >/dev/null; adb shell settings put system accelerometer_rotation 0; adb shell settings put system user_rotation 0
adb uninstall com.limemessenger.lime >/dev/null 2>&1; adb uninstall com.limemessenger.lime.test >/dev/null 2>&1
./gradlew -q installDebug installDebugAndroidTest || exit 1
run() { adb shell am instrument -w -e class "com.limemessenger.lime.ComposerShotsTest#$1" com.limemessenger.lime.test/androidx.test.runner.AndroidJUnitRunner | grep -E '^(OK|FAILURES)'; }
for t in linkDraft linkDraftDarkLargestFont linkBubbleDark linkBubbleLargestFont privacyRow privacyRowDarkLargestFont; do echo "$t: $(run $t)"; done
adb shell settings put system user_rotation 0; adb shell settings put system accelerometer_rotation 1
for f in $(adb shell run-as com.limemessenger.lime ls files/shots 2>/dev/null | tr -d '\r'); do
  adb exec-out run-as com.limemessenger.lime cat "files/shots/$f" > "${OUT:?}/$f"
done
tools/emu.sh stop
echo "saved to $OUT"
