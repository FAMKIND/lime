#!/bin/sh
# Proves LimeCore builds for Android (arm64-v8a + x86_64 .so) and that its Kotlin bindings generate
# and compile. Compile only: running them needs a device or emulator. Exits non-zero on any failure.
# All outputs are under core/target (gitignored). See docs/android.md.
set -e
cd "$(dirname "$0")"
CORE_DIR="$(pwd)"

PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"
[ -f "$HOME/.zprofile" ] && [ -z "$ANDROID_NDK_HOME" ] && . "$HOME/.zprofile" 2>/dev/null || true

fail() { echo "check-android: $1" >&2; exit 1; }

command -v cargo >/dev/null 2>&1 || fail "Rust is missing (see core/build-ios.sh)."
command -v cargo-ndk >/dev/null 2>&1 || fail "cargo-ndk is missing: cargo install cargo-ndk"
[ -n "$ANDROID_NDK_HOME" ] && [ -d "$ANDROID_NDK_HOME" ] || fail "ANDROID_NDK_HOME is unset or missing. Install the NDK with sdkmanager \"ndk;<version>\" (docs/android.md)."
java -version >/dev/null 2>&1 || fail "no JDK found (JAVA_HOME unset?). brew install --cask temurin"
command -v kotlinc >/dev/null 2>&1 || fail "kotlinc is missing: brew install kotlin"
command -v curl >/dev/null 2>&1 || fail "curl is missing."

# 1. The .so files. cdylib is requested here, so Cargo.toml's crate-type (and the iOS build) is untouched.
LIBS="$CORE_DIR/target/android-libs"
rm -rf "$LIBS"
cargo ndk -t arm64-v8a -t x86_64 -o "$LIBS" rustc --release --lib --crate-type cdylib
for abi in arm64-v8a x86_64; do
  so="$LIBS/$abi/liblime_core.so"
  [ -f "$so" ] || fail "missing $so"
  echo "$abi: $(wc -c < "$so" | tr -d ' ') bytes  $so"
done

# 2. Kotlin bindings, from a non-stripped host build (the release profile strips UniFFI's metadata).
cargo build --lib
GEN="$CORE_DIR/target/uniffi-kotlin"
rm -rf "$GEN" && mkdir -p "$GEN"
cargo run --quiet --features cli --bin uniffi-bindgen -- \
  generate --library "$CORE_DIR/target/debug/liblime_core.a" --language kotlin --out-dir "$GEN"
KT="$(find "$GEN" -name '*.kt' | head -1)"
[ -n "$KT" ] || fail "no Kotlin was generated"

# 3. Compile them with a tiny harness against JNA (cached under core/target).
JNA_VERSION=5.14.0
JNA="$CORE_DIR/target/jna-$JNA_VERSION.jar"
if [ ! -s "$JNA" ]; then
  curl -fsSL -o "$JNA" "https://repo1.maven.org/maven2/net/java/dev/jna/jna/$JNA_VERSION/jna-$JNA_VERSION.jar" \
    || { rm -f "$JNA"; fail "could not download JNA"; }
fi
OUT="$CORE_DIR/target/android-check-classes"
rm -rf "$OUT" && mkdir -p "$OUT"
kotlinc -nowarn -cp "$JNA" "$KT" "$CORE_DIR/android-check/Main.kt" -d "$OUT"

echo "check-android: OK (2 .so files built, Kotlin bindings generated and compiled)"
