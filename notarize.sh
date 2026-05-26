#!/usr/bin/env bash
# Submit Lights.app to Apple's notary service, staple the ticket, repack zip.
#
# Prerequisites (one-time per machine):
#   1. Generate an app-specific password at https://appleid.apple.com
#      (Sign-In and Security → App-Specific Passwords → "+")
#   2. Store credentials in the keychain:
#        xcrun notarytool store-credentials lights-notary \
#            --apple-id "your@apple.id" \
#            --team-id  "K2D6DE8NGJ" \
#            --password "xxxx-xxxx-xxxx-xxxx"
#
# Then just run: ./notarize.sh [version]
set -euo pipefail
cd "$(dirname "$0")"

PROFILE="lights-notary"
APP="Lights.app"
DIST="dist"

if [ -n "${1:-}" ]; then
    VERSION="$1"
else
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
fi
ZIP="$DIST/Lights-v$VERSION.zip"

if [ ! -f "$ZIP" ]; then
    echo "✗ $ZIP not found. Run ./release-app.sh $VERSION first." >&2
    exit 1
fi

echo "→ Submitting $ZIP to Apple notary service (5-30 min)…"
xcrun notarytool submit "$ZIP" \
    --keychain-profile "$PROFILE" \
    --wait

echo
echo "→ Stapling ticket to $APP…"
xcrun stapler staple "$APP"

echo
echo "→ Verifying stapled signature:"
spctl -a -t exec -vv "$APP"

echo
echo "→ Re-packing zip with stapled ticket…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo
echo "✓ Done. Updated:"
ls -lh "$ZIP"
echo
echo "Replace the existing release asset:"
echo "  gh release upload v$VERSION \"$ZIP\" --clobber"
