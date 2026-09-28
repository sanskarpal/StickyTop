#!/usr/bin/env bash
# Packages dist/StickyTop.app into a drag-to-Applications disk image.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/StickyTop.app"
[[ -d "$APP" ]] || { echo "Run scripts/build-app.sh first" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="dist/StickyTop-$VERSION.dmg"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "StickyTop $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
echo "==> Built $DMG"
