#!/usr/bin/env bash
# scripts/build_ios.sh
# Build iOS ThoxWarRoom.app + export for App Store + upload to TestFlight.
#
# Requires: xcodebuild, xcrun, xcodegen, altool or notarytool, Apple
#           Distribution certificate + App Store provisioning profile for
#           ai.thox.warroom in the THOX AI LLC team (DVJ6Z5343U).
#
# Env:
#   BUILD_DIR       Output dir (default: ./build/ios)
#   BUILD_CONFIG    Release | Debug (default: Release)
#   SKIP_UPLOAD     Skip TestFlight upload if set
#   SKIP_GEN_ICONS  Skip icon regeneration
#   APPLE_ID        Apple ID for altool auth
#   APPLE_PASSWORD  App-specific password
#   API_KEY_ID      App Store Connect API key ID (TKYHH5J4C3)
#   API_ISSUER_ID   App Store Connect API issuer ID
#                   (c97d7004-992d-49d4-b2a2-bcab1e090187)
#   ASC_API_KEY_P8  Path to .p8 API key (overrides ID/password)
set -euo pipefail

cd "$(dirname "$0")/.."

BUILD_DIR=${BUILD_DIR:-build/ios}
BUILD_CONFIG=${BUILD_CONFIG:-Release}
PROJECT_NAME="ThoxWarRoom"
SCHEME="ThoxWarRoom iOS"
TEAM_ID=${APPLE_TEAM_ID:-DVJ6Z5343U}
BUNDLE_ID="ai.thox.warroom"
API_KEY_ID=${API_KEY_ID:-TKYHH5J4C3}
API_ISSUER_ID=${API_ISSUER_ID:-c97d7004-992d-49d4-b2a2-bcab1e090187}

echo "==> Regenerating Xcode project"
xcodegen generate --quiet

if [ -z "${SKIP_GEN_ICONS:-}" ]; then
    echo "==> Regenerating app icons"
    python3 scripts/gen_appiconset.py
fi

mkdir -p "$BUILD_DIR"

echo "==> Archive ($BUILD_CONFIG)"
xcodebuild \
    -project "$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$BUILD_CONFIG" \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$BUILD_DIR/derived" \
    -archivePath "$BUILD_DIR/$PROJECT_NAME.xcarchive" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_IDENTITY="Apple Distribution" \
    -allowProvisioningUpdates \
    clean archive | tee "$BUILD_DIR/archive.log" >/dev/null

tail -30 "$BUILD_DIR/archive.log"

ARCHIVE="$BUILD_DIR/$PROJECT_NAME.xcarchive"
if [ ! -d "$ARCHIVE" ]; then
    echo "ERROR: archive at $ARCHIVE missing"
    exit 1
fi

EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>destination</key>
    <string>export</string>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadSymbols</key>
    <true/>
    <key>uploadBitcode</key>
    <false/>
    <key>compileBitcode</key>
    <false/>
    <key>manageVersion</key>
    <false/>
</dict>
</plist>
EOF

echo "==> Exporting archive"
EXPORT_DIR="$BUILD_DIR/export"
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS" | tee "$BUILD_DIR/export.log" >/dev/null

tail -30 "$BUILD_DIR/export.log"

IPA_PATH=$(find "$EXPORT_DIR" -name "*.ipa" | head -1 || true)
if [ -z "${IPA_PATH:-}" ]; then
    echo "ERROR: .ipa not found in $EXPORT_DIR"
    exit 1
fi

echo "==> IPA at: $IPA_PATH"

if [ -z "${SKIP_UPLOAD:-}" ]; then
    echo "==> Uploading to TestFlight via xcrun altool"
    if [ -n "${ASC_API_KEY_P8:-}" ]; then
        xcrun altool --upload-app \
            --type ios \
            --file "$IPA_PATH" \
            --apiKey "$API_KEY_ID" \
            --apiIssuer "$API_ISSUER_ID"
    elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_PASSWORD:-}" ]; then
        xcrun altool --upload-app \
            --type ios \
            --file "$IPA_PATH" \
            --username "$APPLE_ID" \
            --password "$APPLE_PASSWORD"
    else
        echo "ERROR: no upload credentials provided"
        echo "       Set ASC_API_KEY_P8 (preferred) or APPLE_ID+APPLE_PASSWORD"
        exit 1
    fi
else
    echo "==> Skipping upload (SKIP_UPLOAD set)"
fi

echo "==> Done"
echo "Archive: $ARCHIVE"
echo "IPA:     $IPA_PATH"
echo "Bundle:  $BUNDLE_ID"
echo "Team:    $TEAM_ID"
