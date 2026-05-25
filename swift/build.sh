#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Paster.app"
SOURCES="$ROOT/Sources"
RES="$ROOT/Resources"

ARCHS=(arm64 x86_64)

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

TMP_BINS=()
for arch in "${ARCHS[@]}"; do
    echo "==> Compiling for $arch…"
    out="$BUILD/Paster-$arch"
    swiftc \
        -O \
        -target "${arch}-apple-macos13" \
        -framework Cocoa \
        -framework SwiftUI \
        -framework Carbon \
        -framework CryptoKit \
        -framework Security \
        -framework ServiceManagement \
        -lsqlite3 \
        -o "$out" \
        "$SOURCES"/*.swift
    TMP_BINS+=("$out")
done

echo "==> Linking universal binary…"
lipo -create "${TMP_BINS[@]}" -output "$APP/Contents/MacOS/Paster"
rm "${TMP_BINS[@]}"
file "$APP/Contents/MacOS/Paster"

echo "==> Bundling resources…"
cp "$RES/Info.plist"   "$APP/Contents/Info.plist"
cp "$RES/icon.icns"    "$APP/Contents/Resources/icon.icns"
cp "$RES/menubar.png"  "$APP/Contents/Resources/menubar.png"
for lproj in "$RES"/*.lproj; do
    [[ -d "$lproj" ]] || continue
    cp -R "$lproj" "$APP/Contents/Resources/"
done

echo "==> Ad-hoc signing…"
codesign --force --sign - "$APP"

echo "==> Done: $APP"
du -sh "$APP"
