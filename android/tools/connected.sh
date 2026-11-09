#!/bin/sh
# Runs the instrumented tests on both emulators, one at a time, headless; shuts each down after. Extra args go to Gradle
# (for example: -Pandroid.testInstrumentationRunnerArguments.class=com.limemessenger.lime.FoundationsTest).
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
status=0
for avd in lime-api36 lime-api26; do
  tools/emu.sh start $avd >/dev/null
  echo "== $avd"
  ./gradlew -q connectedDebugAndroidTest "$@" || status=1
  tools/emu.sh stop; sleep 8
done
exit $status
