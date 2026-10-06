#!/bin/sh
# Regenerates ios/Lime.xcodeproj from project.yml (the .xcodeproj is gitignored).
set -e
cd "$(dirname "$0")"
command -v xcodegen >/dev/null 2>&1 || { echo "XcodeGen is missing: brew install xcodegen" >&2; exit 1; }
# LimeCore (Rust): builds the static libs, the Swift bindings and the xcframework the project links.
../core/build-ios.sh
xcodegen generate --spec project.yml
