#!/bin/sh
# The LIME-422 before/after screenshots (Messages with the tab bar, a chat; light, dark, 200% font) on each AVD. Saved OUTSIDE the repo.
#   tools/shots-422.sh <before|after> [<avd> ...]   -> ~/Desktop/lime-android-design/422-<before|after>-<api>-<name>.png
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
WHEN="${1:?before or after}"; shift; AVDS="${*:-lime-api36 lime-api26}"; OUT="$HOME/Desktop/lime-android-design"; mkdir -p "$OUT"
for AVD in $AVDS; do
  api="${AVD#lime-}"
  tools/emu.sh start "$AVD" >/dev/null || exit 1
  adb shell settings put system font_scale 1.0; adb shell cmd uimode night no >/dev/null
  adb uninstall com.limemessenger.lime >/dev/null 2>&1; adb uninstall com.limemessenger.lime.test >/dev/null 2>&1
  ./gradlew -q installDebug installDebugAndroidTest || exit 1
  C=com.limemessenger.lime.AuditShotsTest
  adb shell am instrument -w -e class "$C#messages,$C#messagesDark,$C#messagesLargest,$C#chat,$C#chatDark,$C#chatLargest" com.limemessenger.lime.test/androidx.test.runner.AndroidJUnitRunner | grep -E '^(OK|FAILURES|Tests run)'
  for n in messages messages-dark messages-font2 chat chat-dark chat-font2; do adb exec-out run-as com.limemessenger.lime cat "files/shots/$n.png" > "$OUT/422-$WHEN-$api-$n.png"; done
  tools/emu.sh stop; sleep 5
done
