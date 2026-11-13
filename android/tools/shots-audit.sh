#!/bin/sh
# The Android shots of the LIME-421 audit (real screens, sample data; light, dark, 200% font) on API 36. Saved OUTSIDE the repo.   tools/shots-audit.sh [<out dir>] [<avd>]
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
OUT="${1:-$HOME/Desktop/lime-android-design/audit-raw}"; AVD="${2:-lime-api36}"
mkdir -p "${OUT:?}"; rm -f "${OUT:?}"/*.png
tools/emu.sh start "$AVD" >/dev/null || exit 1
adb shell settings put system font_scale 1.0; adb shell cmd uimode night no >/dev/null
adb uninstall com.limemessenger.lime >/dev/null 2>&1; adb uninstall com.limemessenger.lime.test >/dev/null 2>&1
./gradlew -q installDebug installDebugAndroidTest || exit 1
adb shell am instrument -w -e class com.limemessenger.lime.AuditShotsTest com.limemessenger.lime.test/androidx.test.runner.AndroidJUnitRunner | grep -vE '^(INSTRUMENTATION_|$)' | tail -40
for f in $(adb shell run-as com.limemessenger.lime ls files/shots 2>/dev/null | tr -d '\r'); do adb exec-out run-as com.limemessenger.lime cat "files/shots/$f" > "${OUT:?}/$f"; done
tools/emu.sh stop
echo "saved to $OUT"
