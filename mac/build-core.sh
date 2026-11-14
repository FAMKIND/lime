#!/bin/sh
# Builds LimeCore for the Mac: a macOS (Apple silicon) slice and a Mac Catalyst (Apple silicon)
# slice, the Swift bindings (UniFFI), and mac/Frameworks/LimeCoreFFI.xcframework.
# Outputs are gitignored. Same module name as iOS (LimeCoreFFI), so shared Swift compiles unchanged.
# Does not edit anything under core/ except core/target (build products).
set -e
MAC_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE_DIR="$MAC_DIR/../core"
cd "$CORE_DIR"

# rustup from Homebrew is keg-only, and rustup-init puts proxies in ~/.cargo/bin.
PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"
if ! command -v cargo >/dev/null 2>&1; then
  echo "Rust is missing. Install it (user-level, no sudo):" >&2
  echo "  brew install rustup && rustup-init -y --no-modify-path" >&2
  exit 1
fi

# The pinned toolchain (core/rust-toolchain.toml) has no Mac targets; add them locally.
rustup target add aarch64-apple-darwin aarch64-apple-ios-macabi

# Minimums: macOS 14 for the Mac slice, iOS 17 for the Catalyst slice (C code, i.e. SQLCipher, follows).
export MACOSX_DEPLOYMENT_TARGET=14.0
export IPHONEOS_DEPLOYMENT_TARGET=17.0

for target in aarch64-apple-darwin aarch64-apple-ios-macabi; do
  cargo build --release --target "$target" --lib
done

# Swift bindings, generated from the compiled macOS library (UniFFI "library mode").
GEN="$CORE_DIR/target/uniffi-out-mac"
rm -rf "$GEN" && mkdir -p "$GEN"
cargo run --quiet --release --features cli --bin uniffi-bindgen -- \
  generate --library "$CORE_DIR/target/aarch64-apple-darwin/release/liblime_core.a" \
  --language swift --no-format --out-dir "$GEN"

HEADERS="$CORE_DIR/target/xcframework-headers-mac"
rm -rf "$HEADERS" && mkdir -p "$HEADERS"
cp "$GEN"/*.h "$HEADERS/"
cp "$GEN"/*.modulemap "$HEADERS/module.modulemap"

SWIFT_OUT="$MAC_DIR/Lime/Generated"
rm -rf "$SWIFT_OUT" && mkdir -p "$SWIFT_OUT"
cp "$GEN"/*.swift "$SWIFT_OUT/"

XCFRAMEWORK="$MAC_DIR/Frameworks/LimeCoreFFI.xcframework"
rm -rf "$XCFRAMEWORK" && mkdir -p "$MAC_DIR/Frameworks"
xcodebuild -create-xcframework \
  -library "$CORE_DIR/target/aarch64-apple-darwin/release/liblime_core.a" -headers "$HEADERS" \
  -library "$CORE_DIR/target/aarch64-apple-ios-macabi/release/liblime_core.a" -headers "$HEADERS" \
  -output "$XCFRAMEWORK"

echo "LimeCore built: $XCFRAMEWORK and $SWIFT_OUT"
