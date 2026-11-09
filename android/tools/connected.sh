#!/bin/sh
# Runs the instrumented tests on both emulators, one at a time, headless; shuts each down after. Extra args go to Gradle
# NO_STAGING=1 skips the @Staging tests. (for example: -Pandroid.testInstrumentationRunnerArguments.class=com.limemessenger.lime.FoundationsTest).
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
status=0
for avd in lime-api36 lime-api26; do
  tools/emu.sh start $avd >/dev/null
  echo "== $avd"
  ./gradlew -q connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.notAnnotation=com.limemessenger.lime.Staging "$@" || status=1
  if [ -z "$NO_STAGING" ]; then
    # The staging tests: install, push Ada's and Ben's fresh sessions into the debug app, run only @Staging, then clean up.
    ./gradlew -q installDebug installDebugAndroidTest || status=1
    tools/staging-test-accounts.sh --push || status=1
    out="$(adb shell am instrument -w -e annotation com.limemessenger.lime.Staging com.limemessenger.lime.test/androidx.test.runner.AndroidJUnitRunner)"
    echo "$out" | tail -4
    echo "$out" | grep -q "^OK" || status=1
    adb uninstall com.limemessenger.lime >/dev/null 2>&1
    adb uninstall com.limemessenger.lime.test >/dev/null 2>&1
  fi
  tools/emu.sh stop; sleep 8
done
exit $status
