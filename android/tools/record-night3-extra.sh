#!/bin/sh
# The screens of night 3 that need no partner (the GIF panel and a sticker, the Report sheet, Settings > Blocked): screenshots only, into the same folder as `record-night3.sh`.
#   tools/record-night3-extra.sh [<out dir>] [<avd>]
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
OUT="${1:-$HOME/Desktop/lime-android-night3}"; AVD="${2:-lime-api36}"
mkdir -p "${OUT:?}"
tools/emu.sh start "$AVD" >/dev/null || exit 1
adb shell settings put system font_scale 1.0; adb shell cmd uimode night no >/dev/null
adb uninstall com.limemessenger.lime >/dev/null 2>&1
./gradlew -q installDebug installDebugAndroidTest || exit 1
tools/staging-test-accounts.sh --push >/dev/null || exit 1
result="$(adb shell am instrument -w -e annotation com.limemessenger.lime.Staging -e class com.limemessenger.lime.Night3RecordingTest#extraShots com.limemessenger.lime.test/androidx.test.runner.AndroidJUnitRunner)"
echo "$result" | grep -E '^(OK|FAILURES)'
for f in $(adb shell run-as com.limemessenger.lime ls files/shots 2>/dev/null | tr -d '\r'); do
  adb exec-out run-as com.limemessenger.lime cat "files/shots/$f" > "${OUT:?}/$f"
done
tools/emu.sh stop
echo "saved to $OUT"; echo "$result" | grep -q "^OK"
