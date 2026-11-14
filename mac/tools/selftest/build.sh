#!/bin/sh
# Builds and runs the core self-test on this Mac. Needs mac/build-core.sh to have run first.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
MAC_DIR="$HERE/../.."
SLICE="$MAC_DIR/Frameworks/LimeCoreFFI.xcframework/macos-arm64"
OUT="$HERE/build"
rm -rf "$OUT" && mkdir -p "$OUT"
swiftc -O \
  -I "$SLICE/Headers" -Xcc -fmodule-map-file="$SLICE/Headers/module.modulemap" \
  "$MAC_DIR/Lime/Generated/lime_core.swift" "$HERE/main.swift" \
  "$SLICE/liblime_core.a" \
  -framework Security -framework SystemConfiguration -framework CoreFoundation \
  -o "$OUT/selftest"
"$OUT/selftest"
