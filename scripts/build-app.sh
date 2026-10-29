#!/bin/zsh
# Generates the Xcode project and builds build/EasyControl.app.
# Signs with an "Apple Development" identity when one exists (so Camera/Accessibility grants survive
# rebuilds), otherwise ad-hoc. Usage: scripts/build-app.sh [Debug|Release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG=${1:-Debug}

xcodegen generate --quiet
mkdir -p build

IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
SIGN_ARGS=(CODE_SIGN_IDENTITY=-)
if [[ -n "$IDENTITY" ]]; then
  TEAM=$(security find-certificate -c "$IDENTITY" -p | openssl x509 -noout -subject | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p')
  SIGN_ARGS=(CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM")
  echo "Signing with: $IDENTITY"
else
  echo "No Apple Development identity: ad-hoc signing (permissions reset on every rebuild)"
fi

xcodebuild -project EasyControl.xcodeproj -scheme EasyControl -configuration "$CONFIG" \
  -derivedDataPath build/DerivedData "${SIGN_ARGS[@]}" build > build/xcodebuild.log 2>&1 || {
  grep -E "error:" build/xcodebuild.log | sort -u | head -30
  echo "BUILD FAILED (full log: build/xcodebuild.log)"
  exit 1
}
rm -rf build/EasyControl.app
cp -R "build/DerivedData/Build/Products/$CONFIG/EasyControl.app" build/
if [[ -z "$IDENTITY" ]]; then
  # An ad-hoc signature's identity is the binary's hash, so macOS drops the Camera/Accessibility grants on
  # every rebuild (System Settings still shows them on). Pin the identity to the bundle id instead.
  # No hardened runtime here: that's for notarized release builds signed with a real identity.
  codesign --force --sign - \
    --entitlements App/Resources/EasyControl.entitlements \
    --requirements '=designated => identifier "dev.hamroz.easycontrol"' \
    build/EasyControl.app
fi
echo "warnings: $(grep -cE "warning:" build/xcodebuild.log || true)"
echo "BUILD SUCCEEDED: build/EasyControl.app"
