#!/bin/sh
# The LIME-424 screenshots (the Calls tab, details, the chat's call bubbles, Settings → Calls; light, dark, 200% font). Saved OUTSIDE the repo.   tools/shots-calls1.sh [<out dir>] [<avd>]
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
OUT="${1:-$HOME/Desktop/lime-android-calls1}"; AVD="${2:-lime-api36}"
mkdir -p "${OUT:?}"
tools/emu.sh start "$AVD" >/dev/null || exit 1
adb shell settings put system font_scale 1.0; adb shell cmd uimode night no >/dev/null
adb uninstall com.limemessenger.lime >/dev/null 2>&1; adb uninstall com.limemessenger.lime.test >/dev/null 2>&1
./gradlew -q installDebug installDebugAndroidTest || exit 1
adb shell am instrument -w -e class com.limemessenger.lime.CallsShotsTest com.limemessenger.lime.test/androidx.test.runner.AndroidJUnitRunner | grep -E '^(OK|FAILURES|Tests run)'
for f in $(adb shell run-as com.limemessenger.lime ls files/shots 2>/dev/null | tr -d '\r'); do adb exec-out run-as com.limemessenger.lime cat "files/shots/$f" > "${OUT:?}/424-$f"; done
tools/emu.sh stop
echo "saved to $OUT"
