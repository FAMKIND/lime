#!/bin/sh
# Builds LimeCore for Android and generates its Kotlin bindings into the app (all gitignored outputs):
#   app/src/main/jniLibs/<abi>/liblime_core.so   and   app/build/generated/uniffi/**.kt
# Same steps as core/check-android.sh 1-2, different output places. Run by Gradle before preBuild.
set -e
cd "$(dirname "$0")"
ANDROID_DIR="$(pwd)"
CORE_DIR="$ANDROID_DIR/../core"
PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"
[ -f "$HOME/.zprofile" ] && [ -z "$ANDROID_NDK_HOME" ] && . "$HOME/.zprofile" 2>/dev/null || true
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-/opt/homebrew/share/android-commandlinetools/ndk/30.0.16248370}"
fail() { echo "build-core: $1" >&2; exit 1; }
command -v cargo >/dev/null 2>&1 || fail "Rust is missing (see core/build-ios.sh)."
command -v cargo-ndk >/dev/null 2>&1 || fail "cargo-ndk is missing: cargo install cargo-ndk"
[ -d "$ANDROID_NDK_HOME" ] || fail "ANDROID_NDK_HOME is unset or missing."

cd "$CORE_DIR"
JNI="$ANDROID_DIR/app/src/main/jniLibs"
rm -rf "$JNI"
cargo ndk -t arm64-v8a -t x86_64 -o "$JNI" rustc --release --lib --crate-type cdylib
for abi in arm64-v8a x86_64; do [ -f "$JNI/$abi/liblime_core.so" ] || fail "missing $abi .so"; done

cargo build --lib
GEN="$ANDROID_DIR/app/build/generated/uniffi"
rm -rf "$GEN" && mkdir -p "$GEN"
cargo run --quiet --features cli --bin uniffi-bindgen -- \
  generate --library "$CORE_DIR/target/debug/liblime_core.a" --language kotlin --out-dir "$GEN"
[ -n "$(find "$GEN" -name '*.kt' | head -1)" ] || fail "no Kotlin was generated"
echo "build-core: OK"
