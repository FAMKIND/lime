#!/bin/sh
# The composer's screenshots for LIME-406 (the mention panel, a long draft expanded, the Editing banner, the "/" strip, 200% font, dark) and, with the emulator turned to landscape, the
# expanded draft there. Saved OUTSIDE the repo.   tools/shots-406.sh [<out dir>] [<avd>]      defaults: ~/Desktop/lime-android-406  lime-api36
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
OUT="${1:-$HOME/Desktop/lime-android-406}"; AVD="${2:-lime-api36}"
mkdir -p "${OUT:?}"; rm -f "${OUT:?}"/*.png
tools/emu.sh start "$AVD" >/dev/null || exit 1
adb shell settings put system font_scale 1.0; adb shell cmd uimode night no >/dev/null; adb shell settings put system accelerometer_rotation 0; adb shell settings put system user_rotation 0
adb uninstall com.limemessenger.lime >/dev/null 2>&1; adb uninstall com.limemessenger.lime.test >/dev/null 2>&1
./gradlew -q installDebug installDebugAndroidTest || exit 1
run() { adb shell am instrument -w -e class "com.limemessenger.lime.ComposerShotsTest#$1" com.limemessenger.lime.test/androidx.test.runner.AndroidJUnitRunner | grep -E '^(OK|FAILURES)'; }
for t in mentionPanel mentionPanelDark expandedDraft editingBanner editingBannerLargestFontDark slashStrip slashStripFontDark; do echo "$t: $(run $t)"; done
adb shell settings put system user_rotation 1; sleep 3
echo "landscapeExpanded: $(run landscapeExpanded)"
adb shell settings put system user_rotation 0; adb shell settings put system accelerometer_rotation 1
for f in $(adb shell run-as com.limemessenger.lime ls files/shots 2>/dev/null | tr -d '\r'); do
  adb exec-out run-as com.limemessenger.lime cat "files/shots/$f" > "${OUT:?}/$f"
done
tools/emu.sh stop
echo "saved to $OUT"
