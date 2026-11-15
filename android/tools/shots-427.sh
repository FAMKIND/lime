#!/bin/sh
# The LIME-427 screenshots of the phone's own surfaces: the incoming-call notification as a heads-up and expanded in the shade (real system UI), light and dark.
#   tools/shots-427.sh [<out dir>] [<avd>]
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
OUT="${1:-$HOME/Desktop/lime-android-calls2}"; AVD="${2:-lime-api36}"
mkdir -p "${OUT:?}"
tools/emu.sh start "$AVD" >/dev/null || exit 1
adb uninstall com.limemessenger.lime >/dev/null 2>&1; adb uninstall com.limemessenger.lime.test >/dev/null 2>&1
./gradlew -q installDebug installDebugAndroidTest || exit 1
adb shell pm grant com.limemessenger.lime android.permission.POST_NOTIFICATIONS
adb shell pm grant com.limemessenger.lime android.permission.RECORD_AUDIO
poster() { adb shell am instrument -w -e class com.limemessenger.lime.CallNotificationPoster -e post 1 "$@" com.limemessenger.lime.test/androidx.test.runner.AndroidJUnitRunner >/dev/null; }
for mode in light dark; do
  adb shell cmd uimode night $([ $mode = dark ] && echo yes || echo no) >/dev/null
  adb shell input keyevent KEYCODE_HOME; sleep 2
  poster -e name Ben_Test
  for i in 1 2 3; do adb exec-out screencap -p > "/tmp/lime-headsup-$mode-$i.png"; sleep 1; done
  # (the emulator did not show a heads-up within the capture window: the frames are kept in /tmp only; the heads-up is a real-phone check)
  sleep 6
  adb shell cmd statusbar expand-notifications; sleep 2
  adb exec-out screencap -p > "$OUT/427-2-notification-shade-$mode.png"
  adb shell cmd statusbar collapse; sleep 1
  poster -e cancel 1
  poster -e name Ben_Test -e video 1
  sleep 8; adb shell cmd statusbar expand-notifications; sleep 2
  adb exec-out screencap -p > "$OUT/427-3-notification-video-shade-$mode.png"
  adb shell cmd statusbar collapse; poster -e cancel 1
done
adb shell cmd uimode night no >/dev/null
tools/emu.sh stop
echo "saved to $OUT"
