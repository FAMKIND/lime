#!/bin/sh
# The LIME-422b screenshots (the Back pill with 0/1/12/99+, Messages rows with pinned/muted/unread/plain, group avatars at 200%, a chat, a group chat; light, dark, normal and 200% font) on each AVD.
#   tools/shots-422b.sh [<avd> ...]   -> ~/Desktop/lime-android-design/422b-<api>-<name>.png
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
AVDS="${*:-lime-api36 lime-api26}"; OUT="$HOME/Desktop/lime-android-design"; mkdir -p "$OUT"
for AVD in $AVDS; do
  api="${AVD#lime-}"
  tools/emu.sh start "$AVD" >/dev/null || exit 1
  adb shell settings put system font_scale 1.0; adb shell cmd uimode night no >/dev/null
  adb uninstall com.limemessenger.lime >/dev/null 2>&1; adb uninstall com.limemessenger.lime.test >/dev/null 2>&1
  ./gradlew -q installDebug installDebugAndroidTest || exit 1
  C=com.limemessenger.lime.AuditShotsTest
  adb shell am instrument -w -e class "$C#backPills,$C#backPillsDark,$C#backPillsLargest,$C#rowsMix,$C#rowsMixDark,$C#rowsMixLargest,$C#avatarsLargest,$C#avatarsLargestDark,$C#messages,$C#messagesDark,$C#messagesLargest,$C#chat,$C#chatDark,$C#chatLargest,$C#group" com.limemessenger.lime.test/androidx.test.runner.AndroidJUnitRunner | grep -E '^(OK|FAILURES|Tests run)'
  for n in back-pills back-pills-dark back-pills-font2 rows-mix rows-mix-dark rows-mix-font2 avatars-font2 avatars-font2-dark messages messages-dark messages-font2 chat chat-dark chat-font2 group; do adb exec-out run-as com.limemessenger.lime cat "files/shots/$n.png" > "$OUT/422b-$api-$n.png"; done
  tools/emu.sh stop; sleep 15
done
