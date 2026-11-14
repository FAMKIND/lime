#!/bin/sh
# Runs the instrumented tests on both emulators, one at a time, headless; shuts each down after. Extra args go to Gradle
# GRADLE_TASK=connectedReleaseLikeAndroidTest with "-Plime.testBuildType=releaseLike" runs the plain suite against the R8-minified build (LIME-411).
# NO_STAGING=1 skips the @Staging tests. (for example: -Pandroid.testInstrumentationRunnerArguments.class=com.limemessenger.lime.FoundationsTest).
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
status=0
for avd in ${AVDS:-lime-api36 lime-api26}; do
  tools/emu.sh start $avd >/dev/null
  echo "== $avd"
  # A leftover install from a manual run would stop Gradle's own install ("already exists").
  adb uninstall com.limemessenger.lime >/dev/null 2>&1; adb uninstall com.limemessenger.lime.test >/dev/null 2>&1
  # STAGING_ONLY=1 skips this first, non-staging pass (a re-run of just the staging classes).
  # A failed pass keeps its report (Gradle overwrites it on the next run): copied to $FAILURES (default ~/Desktop/lime-android-night4/failures) first.
  [ -n "$STAGING_ONLY" ] || ./gradlew -q ${GRADLE_TASK:-connectedDebugAndroidTest} -Pandroid.testInstrumentationRunnerArguments.notAnnotation=com.limemessenger.lime.Staging "$@" || { status=1; d="${FAILURES:-$HOME/Desktop/lime-android-night4/failures}/$(date +%H%M%S)-$avd"; mkdir -p "$d"; cp -R app/build/outputs/androidTest-results/connected/. "$d"/ 2>/dev/null; cp -R app/build/reports/androidTests/connected "$d/html" 2>/dev/null; echo "failing report copied to $d"; }
  if [ -z "$NO_STAGING" ]; then
    # The staging tests: install, then for each test class push Ada's and Ben's FRESH sessions into the debug app (a test's sign-out ends
    # its session on the server, so each class needs its own), start Ben (the host-side partner) with a fresh store (Ada's keys are new
    # every time), run only that @Staging class, stop Ben, clean up.
    ./gradlew -q installDebug installDebugAndroidTest || status=1
    # The server allows 10 device registrations per hour per account (staging's LIME_RATE_REGISTER_PER_HOUR), and every class registers Ada once, so
    # only the chat and groups tests run by default (LIME-303); STAGING_CLASSES="StagingSignInTest StagingChatTest" runs both.
    for cls in ${STAGING_CLASSES:-StagingChatTest StagingGroupsTest StagingActionsTest StagingListTest StagingVoiceFilesTest StagingJamTest StagingJamWriteTest StagingModerationTest StagingGifTest StagingComposerTest StagingMentionTest StagingLinkPreviewTest StagingVideoTest StagingBlockGroupTest StagingJamPictureTest StagingBandTest StagingBandViewTest StagingCallsTest}; do
      tools/staging-test-accounts.sh --push >/dev/null || status=1
      tools/partner/run reset >/dev/null || status=1
      case "$cls" in
        StagingGroupsTest*|StagingMentionTest*|StagingBlockGroupTest*)
          # Groups (LIME-303): Ben and Cleo both answer in every group and accept invitations (a fresh store each).
          tools/partner/run reset --as cleo >/dev/null || status=1
          tools/partner/run group-echo >/tmp/lime-partner.log 2>&1 &
          partner=$!
          tools/partner/run group-echo --as cleo >/tmp/lime-partner-cleo.log 2>&1 &
          partner2=$! ;;
        StagingActionsTest*)
          # Message actions (LIME-304): Ben reacts to every message and prints what Ada edits and deletes.
          tools/partner/run actions-echo >/tmp/lime-partner.log 2>&1 &
          partner=$!
          partner2= ;;
        StagingCallsTest*)
          # Calls (LIME-424): Ben answers Ada's first message, then calls her and hangs up 1.5 s later: a missed call on her phone. Started BEFORE Ada acts.
          tools/partner/run call-miss >/tmp/lime-partner.log 2>&1 &
          partner=$!
          partner2= ;;
        StagingBandViewTest*)
          # LIME-315d: Ben AND Cleo need a device before Ada's first messages: plain echoes now, swapped for band-join / band-subscribe when Ada logs her band's invite link.
          tools/partner/run reset --as cleo >/dev/null || status=1
          tools/partner/run echo >/tmp/lime-partner-echo.log 2>&1 &
          partner=$!
          tools/partner/run echo --as cleo >/tmp/lime-partner-cleo-echo.log 2>&1 &
          partner2=$! ;;
        StagingBandTest*)
          # LIME-315c: Ben must have a device BEFORE Ada's first message (a message to a teacher with no device is lost): a plain `echo` runs until Ada logs her band's invite link (below),
          # then `band-join` takes over on the same store.
          tools/partner/run echo >/tmp/lime-partner-echo.log 2>&1 &
          partner=$!
          partner2= ;;
        StagingJamWriteTest*|StagingJamPictureTest*)
          # Jam writing (LIME-312): Ben follows Ada's jam when she creates it, says what arrives, and comments on each new post.
          tools/partner/run jam-echo >/tmp/lime-partner.log 2>&1 &
          partner=$!
          partner2= ;;
        StagingJamTest*)
          # Jam reading (LIME-311): Ben's jam and three posts are published first, then Ben answers comments.
          tools/partner/run jam-publish >/tmp/lime-partner-publish.log 2>&1 || status=1
          tools/partner/run jam-echo >/tmp/lime-partner.log 2>&1 &
          partner=$!
          partner2= ;;
        *)
          tools/partner/run echo >/tmp/lime-partner.log 2>&1 &
          partner=$!
          partner2= ;;
      esac
      if [ "$cls" = "StagingBandTest" ] || [ "$cls" = "StagingBandViewTest" ]; then
        # The test logs "BAND_TEST link=<invite link>" once Ada has made her band; then Ben joins by it.
        adb logcat -c
        adb shell am instrument -w -e annotation com.limemessenger.lime.Staging -e class com.limemessenger.lime.$cls com.limemessenger.lime.test/androidx.test.runner.AndroidJUnitRunner > /tmp/lime-band-instrument.out 2>&1 &
        inst=$!
        link=""
        for _ in $(seq 1 150); do
          link="$(adb logcat -d -s BAND_TEST:E 2>/dev/null | grep -o 'link=https://[^ ]*' | tail -1 | sed 's/^link=//' | tr -d '\r')"
          [ -n "$link" ] && break
          kill -0 "$inst" 2>/dev/null || break
          sleep 3
        done
        if [ -n "$link" ]; then
          kill "$partner" $partner2 2>/dev/null; pkill -f "MainKt echo" 2>/dev/null; pkill -f "MainKt call-miss" 2>/dev/null; sleep 3
          tools/partner/run band-join "$link" >/tmp/lime-partner.log 2>&1 &
          partner=$!
          if [ "$cls" = "StagingBandViewTest" ]; then
            tools/partner/run band-subscribe "$link" --as cleo >/tmp/lime-partner-cleo.log 2>&1 &
            partner2=$!
          fi
        else
          echo "$cls: Ada never logged an invite link"
        fi
        wait "$inst"
        out="$(cat /tmp/lime-band-instrument.out)"
      else
        out="$(adb shell am instrument -w -e annotation com.limemessenger.lime.Staging -e class com.limemessenger.lime.$cls com.limemessenger.lime.test/androidx.test.runner.AndroidJUnitRunner)"
      fi
      echo "$cls: $(echo "$out" | grep -E '^(OK|FAILURES)' | head -1)"
      echo "$out" | grep -q "^OK" || { status=1; echo "$out" | head -12; }
      # Groups: the partners must have seen Ada leave.
      # (Ada's leave is delivered in the test's last second: give the partner up to 40 s to poll it.)
      case "$cls" in StagingGroupsTest*) for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do grep -qi "system: .*left" /tmp/lime-partner.log && break; sleep 2; done ;; esac
      case "$cls" in StagingGroupsTest*) grep -qi "system: .*left" /tmp/lime-partner.log || { status=1; echo "$cls: the partner never saw Ada leave"; } ;; esac
      case "$cls" in StagingActionsTest*)
        for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do grep -q "^deleted: Delete me" /tmp/lime-partner.log && break; sleep 2; done
        grep -q "^edited: Hello Ben (edited)" /tmp/lime-partner.log || { status=1; echo "$cls: the partner never saw the edit"; }
        grep -q "^deleted: Delete me" /tmp/lime-partner.log || { status=1; echo "$cls: the partner never saw the delete"; } ;; esac
      case "$cls" in StagingJamWriteTest*)
        # Ben must have followed Ada's jam, received her post and her article, seen the edit and seen the delete.
        for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do grep -q "^jam: post removed" /tmp/lime-partner.log && break; sleep 2; done
        grep -q '^jam: subscribed to Ada' /tmp/lime-partner.log || { status=1; echo "$cls: the partner never followed Ada's jam"; }
        grep -q '^jam: received quick' /tmp/lime-partner.log || { status=1; echo "$cls: the partner never received the post"; }
        grep -q '^jam: received article' /tmp/lime-partner.log || { status=1; echo "$cls: the partner never received the article"; }
        grep -q '^jam: edited' /tmp/lime-partner.log || { status=1; echo "$cls: the partner never saw the edit"; }
        grep -q '^jam: post removed' /tmp/lime-partner.log || { status=1; echo "$cls: the partner never saw the delete"; } ;; esac
      case "$cls" in StagingComposerTest*)
        # Ben must have received exactly the Markdown the core makes of what Ada formatted (bold, a list, a link).
        grep -qF 'markdown: **bold** word' /tmp/lime-partner.log || { status=1; echo "$cls: Ben never got the bold message as **bold** word"; }
        grep -qF 'markdown: - one\n- two' /tmp/lime-partner.log || { status=1; echo "$cls: Ben never got the list as - one, - two"; }
        grep -qF 'markdown: see the [plan](https://limemessenger.com/plan) today' /tmp/lime-partner.log || { status=1; echo "$cls: Ben never got the link"; } ;; esac
      case "$cls" in StagingLinkPreviewTest*)
        mkdir -p "$HOME/Desktop/lime-android-407"; adb exec-out run-as com.limemessenger.lime cat files/shots/15-link-bubble-real-chat.png > "$HOME/Desktop/lime-android-407/15-link-bubble-real-chat.png" 2>/dev/null
        # Ben must have received the card's fields (and the picture, decrypted): url, title, site, bytes.
        grep -Eq '^preview: https://example.org/lesson\|Fractions made visible\|example.org\|[1-9][0-9]* bytes' /tmp/lime-partner.log || { status=1; echo "$cls: Ben never got the card fields"; } ;; esac
      case "$cls" in StagingCallsTest*)
        # Ben called Ada (a call.offer) and hung up (call.end): both ops went out.
        grep -Eq '^call: offered partner-call-' /tmp/lime-partner.log && grep -Eq '^call: ended partner-call-' /tmp/lime-partner.log || { status=1; echo "$cls: Ben never offered and ended the call"; } ;; esac
      case "$cls" in StagingBandViewTest*)
        # LIME-315d: Ben (a member) joined the band's group and answered in it; Cleo (a SUBSCRIBER) saw the band's post as the band and could NOT see the members or the invite.
        grep -Eq '^band: received quick "A post from the band" as jam by "Staff Room Band"' /tmp/lime-partner.log || { status=1; echo "$cls: Ben never received the band post as the band"; }
        grep -Eq '^band: group "Band chat" message "Hello band group"' /tmp/lime-partner.log || { status=1; echo "$cls: Ben never received the message in the band group"; }
        grep -Eq '^band-view: received quick "A post from the band" as jam by "Staff Room Band"' /tmp/lime-partner-cleo.log || { status=1; echo "$cls: Cleo never received the band post as the band"; }
        grep -Eq '^band-view: members visible (0|error)' /tmp/lime-partner-cleo.log || { status=1; echo "$cls: Cleo could see the members (or never looked)"; }
        grep -q '^band-view: invite refused' /tmp/lime-partner-cleo.log || { status=1; echo "$cls: Cleo could see the invite (or never looked)"; }
        grep -q '^band-view: my bands 0' /tmp/lime-partner-cleo.log || { status=1; echo "$cls: Cleo was listed as a member of the band"; } ;; esac
      case "$cls" in StagingBandTest*)
        # Ben joined by the invite, was listed with his role (made a Writer by Ada) and received the band's post, shown as the band (LIME-315c).
        grep -q '^band: joined\|^band: join state joined' /tmp/lime-partner.log || { status=1; echo "$cls: Ben never joined the band"; }
        grep -q '^band: my role writer' /tmp/lime-partner.log || { status=1; echo "$cls: Ben never saw himself a writer"; }
        grep -Eq '^band: received quick "A post from the band" as jam by "Staff Room Band"' /tmp/lime-partner.log || { status=1; echo "$cls: Ben never received the band post as the band"; } ;; esac
      case "$cls" in StagingJamPictureTest*)
        # Ben fetched Ada's PUBLIC jam picture from her page and said how big it is (LIME-412b).
        grep -Eq "^jam: Ada's jam picture [1-9][0-9]* bytes" /tmp/lime-partner.log || { status=1; echo "$cls: Ben never fetched the jam picture"; } ;; esac
      case "$cls" in StagingVideoTest*)
        # Ben must have downloaded and decrypted Ada's video whole: type, size, length, size in pixels, a poster and a thumbnail.
        grep -Eq '^video: video/mp4\|[1-9][0-9]* bytes\|[1-9][0-9]* ms\|[1-9][0-9]*x[1-9][0-9]*\|poster [1-9][0-9]* bytes\|thumb [0-9]+ bytes' /tmp/lime-partner.log || { status=1; echo "$cls: Ben never got the video whole"; } ;; esac
      case "$cls" in StagingMentionTest*)
        # Ben must have received the mention as the core's markup: [@Ben Android](mention:<his id>).
        grep -Eq 'markdown: hi \[@Ben Android\]\(mention:[0-9a-f-]+\) there' /tmp/lime-partner.log || { status=1; echo "$cls: Ben never got the mention as [@Ben Android](mention:<id>)"; } ;; esac
      kill "$partner" $partner2 2>/dev/null; pkill -f "MainKt echo" 2>/dev/null; pkill -f "MainKt actions-echo" 2>/dev/null; pkill -f "MainKt jam-echo" 2>/dev/null; pkill -f "MainKt band-join" 2>/dev/null; pkill -f "MainKt band-subscribe" 2>/dev/null; pkill -f "MainKt group-echo" 2>/dev/null
    done
    adb uninstall com.limemessenger.lime >/dev/null 2>&1
    adb uninstall com.limemessenger.lime.test >/dev/null 2>&1
  fi
  tools/emu.sh stop; sleep 8
done
exit $status
