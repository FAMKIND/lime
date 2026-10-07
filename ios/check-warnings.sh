#!/bin/sh
# Fails on ANY compiler warning in Lime's own sources (the app, the unit tests, the UI tests; not the
# generated UniFFI file), the way Xcode's issue navigator would show them.
#
# Why it exists: an incremental `xcodebuild` only recompiles the files that changed, so a warning in a
# file that did not change is never printed; and some diagnostics (Swift 6 concurrency and
# availability) appear only for the device SDK. So this builds everything from CLEAN, and for BOTH a
# simulator and a device destination (unsigned), tests included.
#
#   ./ios/check-warnings.sh
set -e
cd "$(dirname "$0")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
status=0
for destination in 'generic/platform=iOS Simulator' 'generic/platform=iOS'; do
  log="$work/build.log"
  echo "== $destination"
  if ! xcodebuild clean build-for-testing -project Lime.xcodeproj -scheme Lime -destination "$destination" \
      -derivedDataPath "$work/derived" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO >"$log" 2>&1; then
    tail -30 "$log"
    echo "The build failed." >&2
    exit 1
  fi
  # Warnings in our own files (xcodebuild prints each once per architecture and target: de-duplicate).
  # "Ours" is any .swift file under a Lime, LimeTests or LimeUITests folder, except the generated
  # UniFFI bindings and anything inside the build's own derived data.
  all="$(grep -E ': warning: ' "$log" | sort -u || true)"
  own="$(printf '%s\n' "$all" | grep -E '/(Lime|LimeTests|LimeUITests)/.*\.swift:[0-9]+' |
    grep -v -E '/Core/Generated/' | grep -v -F "$work" || true)"
  printf '%s\n' "$own" >"$work/own.txt"
  other="$(printf '%s\n' "$all" | grep -v -x -F -f "$work/own.txt" || true)"
  if [ -n "$own" ]; then
    echo "$own"
    status=1
  fi
  if [ -n "$other" ]; then
    echo "(not in Lime's sources, listed for information)"
    echo "$other" | head -10
  fi
done
if [ "$status" -ne 0 ]; then
  echo "WARNINGS in Lime's own sources." >&2
  exit 1
fi
echo "0 warnings in Lime's own sources (simulator and device, from clean)."
