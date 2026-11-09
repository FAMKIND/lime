#!/bin/sh
# Builds the partner: LimeCore's host library (a cdylib, as check-android.sh does for Android; core/ is not changed), the same generated
# Kotlin bindings the app uses, and Main.kt, into android/tools/partner/build/ (gitignored).
set -e
cd "$(dirname "$0")"
HERE="$(pwd)"
CORE="$HERE/../../../core"
PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"
JNA="$CORE/target/jna-5.14.0.jar"
[ -s "$JNA" ] || curl -fsSL -o "$JNA" https://repo1.maven.org/maven2/net/java/dev/jna/jna/5.14.0/jna-5.14.0.jar
GEN="$HERE/../../app/build/generated/uniffi"
[ -n "$(find "$GEN" -name '*.kt' 2>/dev/null | head -1)" ] || sh "$HERE/../../build-core.sh"
(cd "$CORE" && cargo rustc --release --lib --crate-type cdylib)
mkdir -p build
cp "$CORE/target/release/liblime_core.dylib" build/
kotlinc -nowarn -cp "$JNA" "$(find "$GEN" -name '*.kt')" Main.kt -include-runtime -d build/partner.jar
echo "partner: built"
