#!/bin/sh
# Builds LimeCore for iOS: a static library for the device and the Apple-silicon simulator, the
# Swift bindings (UniFFI), and ios/Frameworks/LimeCoreFFI.xcframework. All outputs are gitignored.
# Run by ios/generate.sh; it can also be run on its own.
set -e
cd "$(dirname "$0")"
CORE_DIR="$(pwd)"
IOS_DIR="$CORE_DIR/../ios"

# rustup from Homebrew is keg-only, and rustup-init puts proxies in ~/.cargo/bin.
PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"
if ! command -v cargo >/dev/null 2>&1; then
  echo "Rust is missing. Install it (user-level, no sudo):" >&2
  echo "  brew install rustup && rustup-init -y --no-modify-path" >&2
  echo "then run this again (the toolchain and iOS targets are pinned in core/rust-toolchain.toml)." >&2
  exit 1
fi

for target in aarch64-apple-ios aarch64-apple-ios-sim; do
  cargo build --release --target "$target" --lib
done

# Swift bindings, generated from the compiled library (UniFFI "library mode").
GEN="$CORE_DIR/target/uniffi-out"
rm -rf "$GEN" && mkdir -p "$GEN"
cargo run --quiet --release --features cli --bin uniffi-bindgen -- \
  generate --library "$CORE_DIR/target/aarch64-apple-ios-sim/release/liblime_core.a" \
  --language swift --out-dir "$GEN"

# The C header and module map go into the xcframework; the Swift file is compiled into the app.
HEADERS="$CORE_DIR/target/xcframework-headers"
rm -rf "$HEADERS" && mkdir -p "$HEADERS"
cp "$GEN"/*.h "$HEADERS/"
cp "$GEN"/*.modulemap "$HEADERS/module.modulemap"

SWIFT_OUT="$IOS_DIR/Lime/Core/Generated"
rm -rf "$SWIFT_OUT" && mkdir -p "$SWIFT_OUT"
cp "$GEN"/*.swift "$SWIFT_OUT/"

XCFRAMEWORK="$IOS_DIR/Frameworks/LimeCoreFFI.xcframework"
rm -rf "$XCFRAMEWORK" && mkdir -p "$IOS_DIR/Frameworks"
xcodebuild -create-xcframework \
  -library "$CORE_DIR/target/aarch64-apple-ios/release/liblime_core.a" -headers "$HEADERS" \
  -library "$CORE_DIR/target/aarch64-apple-ios-sim/release/liblime_core.a" -headers "$HEADERS" \
  -output "$XCFRAMEWORK"

echo "LimeCore built: $XCFRAMEWORK and $SWIFT_OUT"
