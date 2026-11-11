#!/bin/sh
# The composer's screenshots (LIME-403) on a headless emulator, saved OUTSIDE the repo: empty, a six-line message, a photo draft, recording, font scale 2.0, dark.
#   tools/shots-403.sh [<out dir>] [<avd>]      defaults: ~/Desktop/lime-android-403  lime-api36
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
OUT="${1:-$HOME/Desktop/lime-android-403}"; AVD="${2:-lime-api36}"
mkdir -p "${OUT:?}"; rm -f "${OUT:?}"/*.png
tools/emu.sh start "$AVD" >/dev/null || exit 1
adb shell settings put system font_scale 1.0; adb shell cmd uimode night no >/dev/null
adb uninstall com.limemessenger.lime >/dev/null 2>&1; adb uninstall com.limemessenger.lime.test >/dev/null 2>&1
./gradlew -q installDebug installDebugAndroidTest || exit 1
adb shell pm grant com.limemessenger.lime android.permission.RECORD_AUDIO
result="$(adb shell am instrument -w -e class com.limemessenger.lime.ComposerShotsTest com.limemessenger.lime.test/androidx.test.runner.AndroidJUnitRunner)"
echo "$result" | grep -E '^(OK|FAILURES)'
for f in $(adb shell run-as com.limemessenger.lime ls files/shots 2>/dev/null | tr -d '\r'); do
  adb exec-out run-as com.limemessenger.lime cat "files/shots/$f" > "${OUT:?}/$f"
done
tools/emu.sh stop
echo "saved to $OUT"; echo "$result" | grep -q "^OK"
