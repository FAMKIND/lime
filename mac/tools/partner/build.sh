#!/bin/sh
# Builds the partner with swiftc against LimeCore's macOS slice and the generated bindings (run mac/build-core.sh first).
# The transport is iOS's URLSessionTransport.swift, compiled by reference (Foundation only; its DEBUG logging is not compiled in).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
MAC_DIR="$HERE/../.."
SLICE="$MAC_DIR/Frameworks/LimeCoreFFI.xcframework/macos-arm64"
OUT="$HERE/build"
mkdir -p "$OUT"
swiftc -O -swift-version 5 \
  -I "$SLICE/Headers" -Xcc -fmodule-map-file="$SLICE/Headers/module.modulemap" \
  "$MAC_DIR/Lime/Generated/lime_core.swift" "$MAC_DIR/../ios/Lime/Core/Network/URLSessionTransport.swift" "$HERE/main.swift" \
  "$SLICE/liblime_core.a" \
  -framework Security -framework SystemConfiguration -framework CoreFoundation \
  -o "$OUT/partner"
echo "partner: built $OUT/partner"
