#!/bin/zsh
# Builds a Release, ad-hoc signed build/EasyControl-<version>.dmg (drag-to-Applications disk image).
# Not notarized: there is no Apple Developer account yet, so users approve it once (see README).
# Usage: scripts/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

EC_ADHOC=1 scripts/build-app.sh Release
APP=build/EasyControl.app
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="build/EasyControl-$VERSION.dmg"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "EasyControl" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" > /dev/null
(cd build && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "DMG READY: $DMG"
cat "$DMG.sha256"
