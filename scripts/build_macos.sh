#!/usr/bin/env bash
# scripts/build_macos.sh
# Build a signed ThoxWarRoom.app + a distributable arm64 .dmg.
#
# Requires: xcodebuild, xcrun, xcodegen, hdiutil, codesign, iconutil
# Apple Team: DVJ6Z5343U (THOX AI LLC)
#
# Env:
#   BUILD_DIR        Output dir (default: ./build/macos)
#   BUILD_CONFIG     Release | Debug (default: Release)
#   ARCH             arm64 | x86_64 (default: arm64)
#   SKIP_GEN_ICONS   Skip icon regeneration if set
#   SKIP_NOTARIZE    Skip notarization if set (default: notarize if creds available)
#   APPLE_ID         Apple ID for notarization
#   APPLE_PASSWORD   App-specific password
#   APPLE_TEAM_ID    Team ID (defaults to DVJ6Z5343U)
set -euo pipefail

cd "$(dirname "$0")/.."

BUILD_DIR=${BUILD_DIR:-build/macos}
BUILD_CONFIG=${BUILD_CONFIG:-Release}
ARCH=${ARCH:-arm64}
PROJECT_NAME="ThoxWarRoom"
SCHEME="ThoxWarRoom macOS"
APP_NAME="ThoxWarRoom.app"
TEAM_ID=${APPLE_TEAM_ID:-DVJ6Z5343U}
BUNDLE_ID="ai.thox.warroom"

echo "==> Regenerating Xcode project"
xcodegen generate --quiet

if [ -z "${SKIP_GEN_ICONS:-}" ]; then
    echo "==> Regenerating app icons"
    python3 scripts/gen_appiconset.py
fi

mkdir -p "$BUILD_DIR"

echo "==> Building $SCHEME ($BUILD_CONFIG, $ARCH)"
xcodebuild \
    -project "$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$BUILD_CONFIG" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$BUILD_DIR/derived" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_IDENTITY="Apple Development" \
    ARCHS="$ARCH" \
    ONLY_ACTIVE_ARCH=NO \
    ENABLE_HARDENED_RUNTIME=YES \
    clean build | tee "$BUILD_DIR/build.log" >/dev/null

# Tail the last 40 lines of the log so we can see what happened
tail -40 "$BUILD_DIR/build.log"

APP_PATH=$(find "$BUILD_DIR/derived/Build/Products" -name "$APP_NAME" -type d | head -1 || true)
if [ -z "${APP_PATH:-}" ]; then
    echo "ERROR: build succeeded but $APP_NAME not found in derived data"
    exit 1
fi

echo "==> App built at: $APP_PATH"

# Verify code signature
echo "==> Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1 | head -20
codesign -dv "$APP_PATH" 2>&1 | head -20

# Stage for DMG
STAGING="$BUILD_DIR/staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -sfn /Applications "$STAGING/Applications"

DMG_PATH="$BUILD_DIR/ThoxWarRoom-$BUILD_CONFIG-$ARCH.dmg"
echo "==> Creating DMG at $DMG_PATH"
hdiutil create -volname "ThoxWarRoom" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"

# Notarize if creds available
if [ -z "${SKIP_NOTARIZE:-}" ] && [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_PASSWORD:-}" ]; then
    echo "==> Submitting for notarization"
    NOTARY_OUT="$BUILD_DIR/notary.zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$NOTARY_OUT"
    xcrun notarytool submit "$NOTARY_OUT" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"
    echo "==> Re-packaging notarized DMG"
    hdiutil create -volname "ThoxWarRoom" \
        -srcfolder "$STAGING" \
        -ov -format UDZO \
        "$DMG_PATH"
else
    echo "==> Skipping notarization (no APPLE_ID/APPLE_PASSWORD)"
fi

echo "==> Done"
echo "APP:    $APP_PATH"
echo "DMG:    $DMG_PATH"
echo "Bundle: $BUNDLE_ID"
echo "Team:   $TEAM_ID"
