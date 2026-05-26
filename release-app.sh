#!/usr/bin/env bash
# Build, Developer-ID-sign, and zip a release-ready Lights.app for GitHub release.
# Usage: ./release-app.sh [version]   (default: read from Info.plist)
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="Developer ID Application: Yiqi Feng (K2D6DE8NGJ)"
APP="Lights.app"
DIST="dist"

# Version: arg → Info.plist CFBundleShortVersionString
if [ -n "${1:-}" ]; then
    VERSION="$1"
else
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
fi
ZIP="$DIST/Lights-v$VERSION.zip"

echo "→ Building app bundle (ad-hoc sign first)..."
./build-app.sh

echo "→ Re-signing with Developer ID (hardened runtime)..."
codesign --force --deep --options runtime --timestamp \
    --sign "$IDENTITY" "$APP"

echo "→ Verifying signature..."
codesign --verify --verbose=2 "$APP"
echo
echo "→ Gatekeeper assessment (will fail until notarized — expected):"
spctl -a -t exec -vv "$APP" || true

echo
echo "→ Zipping to $ZIP..."
mkdir -p "$DIST"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo
echo "✓ Done:"
ls -lh "$ZIP"
echo
echo "Next steps:"
echo "  gh release create v$VERSION \"$ZIP\" --title \"Lights v$VERSION\" --notes-file RELEASE_NOTES.md"
