#!/bin/sh
# The LIME-420 design-gallery screenshots (light and dark, 100% and 200% font) on each AVD. Saved OUTSIDE the repo.   tools/shots-design.sh [<out dir>] [<avd> ...]
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
OUT="${1:-$HOME/Desktop/lime-android-design}"; shift; AVDS="${*:-lime-api36 lime-api26}"
mkdir -p "${OUT:?}"
for AVD in $AVDS; do
  api="${AVD#lime-}"
  tools/emu.sh start "$AVD" >/dev/null || exit 1
  adb shell settings put system font_scale 1.0; adb shell cmd uimode night no >/dev/null
  adb uninstall com.limemessenger.lime >/dev/null 2>&1; adb uninstall com.limemessenger.lime.test >/dev/null 2>&1
  ./gradlew -q installDebug installDebugAndroidTest || exit 1
  for t in font100 font200; do echo "$api $t: $(adb shell am instrument -w -e prefix "420-$api" -e class "com.limemessenger.lime.DesignGalleryShotsTest#$t" com.limemessenger.lime.test/androidx.test.runner.AndroidJUnitRunner | grep -E '^(OK|FAILURES)')"; done
  for f in $(adb shell run-as com.limemessenger.lime ls files/shots 2>/dev/null | tr -d '\r'); do adb exec-out run-as com.limemessenger.lime cat "files/shots/$f" > "${OUT:?}/$f"; done
  tools/emu.sh stop; sleep 5
done
echo "saved to $OUT"
