#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Paster.app"
PKG="$ROOT/build/Paster.pkg"
STAGE="$ROOT/build/pkg-stage"
SCRIPTS="$ROOT/build/pkg-scripts"

if [[ ! -d "$APP" ]]; then
    echo "App not built. Run ./build.sh first."
    exit 1
fi

rm -rf "$STAGE" "$SCRIPTS" "$PKG"
mkdir -p "$STAGE" "$SCRIPTS"

cp -R "$APP" "$STAGE/"
xattr -cr "$STAGE/Paster.app"

cat > "$SCRIPTS/postinstall" << 'EOF'
#!/bin/bash
# Strip any quarantine that may have been added during install
/usr/bin/xattr -cr /Applications/Paster.app 2>/dev/null || true
exit 0
EOF
chmod +x "$SCRIPTS/postinstall"

echo "==> Building pkg…"
pkgbuild \
    --root "$STAGE" \
    --identifier com.paster.clipboard \
    --version 0.3.0 \
    --install-location /Applications \
    --scripts "$SCRIPTS" \
    "$PKG"

rm -rf "$STAGE" "$SCRIPTS"

echo "==> Done"
ls -lh "$PKG"
