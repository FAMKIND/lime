#!/bin/sh
# LIME-103: a Release build must contain none of the Bluetooth field test: no Bluetooth background
# modes, no Bluetooth usage text, no CoreBluetooth, and none of the Nearby test's code or screen.
#
#   ./ios/check-release-no-bluetooth.sh
set -e
cd "$(dirname "$0")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
xcodebuild build -project Lime.xcodeproj -scheme Lime -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$work/derived" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO >"$work/build.log" 2>&1 || { tail -30 "$work/build.log"; echo "The Release build failed." >&2; exit 1; }
app="$(find "$work/derived/Build/Products" -name Lime.app -maxdepth 3 | head -1)"
plist="$app/Info.plist"
fail=0
# The only background modes a Release build may have are "audio" and "voip" (an ongoing call keeps playing; the system call screen); nothing about Bluetooth.
modes="$(plutil -extract UIBackgroundModes json -o - "$plist" 2>/dev/null || echo '[]')"
case "$modes" in
  '[]'|'["audio"]'|'["audio","voip"]'|'["voip","audio"]'|'["voip"]') ;;
  *) echo "FAIL: Info.plist has background modes other than audio and voip: $modes"; fail=1 ;;
esac
if plutil -p "$plist" | grep -q -i 'bluetooth'; then echo "FAIL: Info.plist mentions Bluetooth:"; plutil -p "$plist" | grep -i 'bluetooth'; fail=1; fi
if otool -L "$app/Lime" | grep -q CoreBluetooth; then echo "FAIL: the Release binary links CoreBluetooth"; fail=1; fi
if strings "$app/Lime" | grep -q -E 'NearbyTransport|NearbyTestScreen|NearbyBlob|Nearby test|6C696D65-6E65-6172-6279'; then echo "FAIL: the Release binary contains the Nearby test"; fail=1; fi
[ "$fail" = 0 ] || exit 1
echo "Release build: no Bluetooth background modes, no usage text, no CoreBluetooth, no Nearby test."
