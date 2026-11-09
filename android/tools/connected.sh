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
    # The staging tests: install, then for each test class push Ada's and Ben's FRESH sessions into the debug app (a test's sign-out ends
    # its session on the server, so each class needs its own), start Ben (the host-side partner) with a fresh store (Ada's keys are new
    # every time), run only that @Staging class, stop Ben, clean up.
    ./gradlew -q installDebug installDebugAndroidTest || status=1
    # The server allows 10 device registrations per hour per account (staging's LIME_RATE_REGISTER_PER_HOUR), and every class registers Ada once, so
    # only the chat test (it signs in too) runs by default; STAGING_CLASSES="StagingSignInTest StagingChatTest" runs both.
    for cls in ${STAGING_CLASSES:-StagingChatTest}; do
      tools/staging-test-accounts.sh --push >/dev/null || status=1
      tools/partner/run reset >/dev/null || status=1
      tools/partner/run echo >/tmp/lime-partner.log 2>&1 &
      partner=$!
      out="$(adb shell am instrument -w -e annotation com.limemessenger.lime.Staging -e class com.limemessenger.lime.$cls com.limemessenger.lime.test/androidx.test.runner.AndroidJUnitRunner)"
      echo "$cls: $(echo "$out" | grep -E '^(OK|FAILURES)' | head -1)"
      echo "$out" | grep -q "^OK" || { status=1; echo "$out" | head -12; }
      kill "$partner" 2>/dev/null; pkill -f "MainKt echo" 2>/dev/null
    done
    adb uninstall com.limemessenger.lime >/dev/null 2>&1
    adb uninstall com.limemessenger.lime.test >/dev/null 2>&1
  fi
  tools/emu.sh stop; sleep 8
done
exit $status
