#!/bin/sh
# Proves the debug-only test sign-in is NOT in the release APK or the release bundle (AAB): none of its strings (the pushed file's name, its button text, its test tags)
# appear in the release dex or resources, while they do appear in the debug APK (so the check itself works).
set -e
cd "$(dirname "$0")/.."
./gradlew -q assembleDebug assembleRelease bundleRelease
count() { # <apk-or-aab> -> number of marker hits in its dex + resources (an AAB keeps them under base/dex and base/resources.pb)
  d="$(mktemp -d)"; unzip -q -o "$1" -d "$d"
  n=0
  for f in "$d"/classes*.dex "$d"/resources.arsc "$d"/base/dex/*.dex "$d"/base/resources.pb; do
    [ -f "$f" ] && n=$((n + $(strings -a "$f" | grep -cE 'test-accounts\.json|Use a test account|test-account-|use-test-account' || true)))
  done
  rm -rf "$d"; echo "$n"
}
debug="$(count app/build/outputs/apk/debug/app-debug.apk)"
apk="app/build/outputs/apk/release/app-release.apk"; [ -f "$apk" ] || apk="app/build/outputs/apk/release/app-release-unsigned.apk"
release="$(count "$apk")"
bundle="$(count app/build/outputs/bundle/release/app-release.aab)"
echo "debug APK markers: $debug   release APK markers: $release   release AAB markers: $bundle"
[ "$debug" -gt 0 ] || { echo "check is broken: the debug APK has no markers" >&2; exit 1; }
[ "$release" -eq 0 ] || { echo "FAIL: the release APK contains the test sign-in" >&2; exit 1; }
[ "$bundle" -eq 0 ] || { echo "FAIL: the release bundle contains the test sign-in" >&2; exit 1; }
echo "OK: the release APK and the release bundle have no test sign-in"
