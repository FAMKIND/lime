#!/bin/sh
# LIME-425, the media proof (PROOF=video runs LIME-426's video proof instead: a video call and a voice call turned to video, the other side's mute over the control channel): two emulators (Ada on lime-api36, Ben on lime-api26) each run the real app signed in as a staging test account and call each other over WebRTC.
# Prints what each saw (the four verification emoji, the inbound audio statistics) and checks the emoji are equal. Needs ~/.lime/staging.env (the test-account tooling).
#   tools/call-media-proof.sh [<out dir>]
cd "$(dirname "$0")/.."
SDK=/opt/homebrew/share/android-commandlinetools
export PATH="$SDK/platform-tools:$PATH" ANDROID_HOME="$SDK"
if [ "$PROOF" = video ]; then CLASS=StagingCallVideoTest; PREFIX=video-proof; OUT="${1:-$HOME/Desktop/lime-android-calls2}"; else CLASS=StagingCallMediaTest; PREFIX=call-proof; OUT="${1:-$HOME/Desktop/lime-android-calls1}"; fi
mkdir -p "$OUT"
A=emulator-5554; B=emulator-5556
AUDIO="${EMU_AUDIO:--no-audio}"
boot() { # <avd> <port>
  "$SDK/emulator/emulator" -avd "$1" -port "$2" -no-window -read-only $AUDIO -no-boot-anim -no-snapshot-save -gpu swiftshader_indirect >/tmp/emu-$1-proof.log 2>&1 &
  adb -s "emulator-$2" wait-for-device
  until [ "$(adb -s "emulator-$2" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 3; done
}
# Two instances of one AVD need -read-only; AVD_A and AVD_B choose them (the API 26 image has no microphone to capture from when headless, so it sends nothing: use two lime-api36 for a two-way proof).
boot "${AVD_A:-lime-api36}" 5554; boot "${AVD_B:-lime-api26}" 5556
for d in $A $B; do adb -s $d uninstall com.limemessenger.lime >/dev/null 2>&1; adb -s $d uninstall com.limemessenger.lime.test >/dev/null 2>&1; done
./gradlew -q installDebug installDebugAndroidTest || exit 1
for d in $A $B; do
  adb -s $d shell pm grant com.limemessenger.lime android.permission.RECORD_AUDIO
  adb -s $d shell pm grant com.limemessenger.lime android.permission.CAMERA
  adb -s $d shell pm grant com.limemessenger.lime android.permission.POST_NOTIFICATIONS 2>/dev/null
done
# One push signs the three accounts in fresh and ends their earlier sessions, so push once and put the SAME file on the second emulator.
ANDROID_SERIAL=$A tools/staging-test-accounts.sh --push >/dev/null || exit 1
adb -s $A exec-out run-as com.limemessenger.lime cat files/test-accounts.json > /tmp/lime-ta.json
adb -s $B push /tmp/lime-ta.json /data/local/tmp/lime-ta.json >/dev/null; rm -f /tmp/lime-ta.json
adb -s $B shell "run-as com.limemessenger.lime sh -c 'mkdir -p files && cp /data/local/tmp/lime-ta.json files/test-accounts.json'"
adb -s $B shell rm /data/local/tmp/lime-ta.json
run() { # <serial> <role> <out>
  adb -s "$1" shell am instrument -w -e role "$2" -e class com.limemessenger.lime.$CLASS com.limemessenger.lime.test/androidx.test.runner.AndroidJUnitRunner >"$3" 2>&1
}
run $B ben /tmp/proof-ben.out &
ben_job=$!
sleep 25   # Ben signs in and registers his device first (a message to a person with no device is lost)
run $A ada /tmp/proof-ada.out
wait $ben_job
status=0
for r in ada ben; do
  d=$A; [ $r = ben ] && d=$B
  adb -s $d exec-out run-as com.limemessenger.lime cat files/$PREFIX-$r.txt > "$OUT/$PREFIX-$r.txt" 2>/dev/null
  echo "== $r"; grep -E "^(OK|FAILURES|Tests run)" /tmp/proof-$r.out; cat "$OUT/$PREFIX-$r.txt" 2>/dev/null
done
if [ "$PROOF" != video ]; then
ea="$(grep '^emoji=' "$OUT/$PREFIX-ada.txt")"; eb="$(grep '^emoji=' "$OUT/$PREFIX-ben.txt")"
[ -n "$ea" ] && [ "$ea" = "$eb" ] && echo "emoji equal: $ea" || { echo "EMOJI DIFFER or missing: ada=[$ea] ben=[$eb]"; status=1; }
else
for r in ada ben; do grep -q "^OK" /tmp/proof-$r.out || status=1; done
fi
adb -s $A emu kill >/dev/null 2>&1; adb -s $B emu kill >/dev/null 2>&1
exit $status
