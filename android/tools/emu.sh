#!/bin/sh
# Headless emulator helper: tools/emu.sh start <avd> | stop
SDK=/opt/homebrew/share/android-commandlinetools
case "$1" in
  start)
    "$SDK/emulator/emulator" -avd "$2" -no-window -no-audio -no-boot-anim -no-snapshot-save -gpu swiftshader_indirect >/tmp/emu-$2.log 2>&1 &
    "$SDK/platform-tools/adb" wait-for-device
    until [ "$("$SDK/platform-tools/adb" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 3; done
    echo "booted $2" ;;
  stop) "$SDK/platform-tools/adb" emu kill >/dev/null 2>&1 ;;
esac
