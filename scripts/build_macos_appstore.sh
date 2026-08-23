#!/usr/bin/env bash
# Archive, export, and optionally upload the sandboxed macOS app to App Store
# Connect for TestFlight/App Store distribution. This is separate from the
# Developer ID/notarized DMG path in build_macos.sh.
set -euo pipefail

cd "$(dirname "$0")/.."

BUILD_DIR=${BUILD_DIR:-build/macos-appstore}
BUILD_CONFIG=${BUILD_CONFIG:-Release}
PROJECT_NAME="ThoxWarRoom"
SCHEME="ThoxWarRoom macOS"
TEAM_ID=${APPLE_TEAM_ID:-DVJ6Z5343U}
BUNDLE_ID="ai.thox.warroom"

validate_asc_credentials() {
    if [ -z "${ASC_API_KEY_ID:-}" ] || [ -z "${ASC_API_ISSUER_ID:-}" ] || [ -z "${ASC_API_KEY_P8:-}" ]; then
        echo "ERROR: ASC API authentication requires ASC_API_KEY_ID, ASC_API_ISSUER_ID, and ASC_API_KEY_P8" >&2
        return 1
    fi
    if [ ! -f "$ASC_API_KEY_P8" ] || [ ! -r "$ASC_API_KEY_P8" ]; then
        echo "ERROR: ASC_API_KEY_P8 must reference a readable regular file" >&2
        return 1
    fi
    case "$ASC_API_KEY_P8" in
        *.p8) ;;
        *) echo "ERROR: ASC_API_KEY_P8 must reference a .p8 file" >&2; return 1 ;;
    esac
    # Some Xcode versions emit the generated bearer token on stderr.
    if ! xcrun altool --generate-jwt \
        --api-key "$ASC_API_KEY_ID" \
        --api-issuer "$ASC_API_ISSUER_ID" \
        --p8-file-path "$ASC_API_KEY_P8" >/dev/null 2>&1; then
        echo "ERROR: App Store Connect API credential validation failed" >&2
        return 1
    fi
    echo "==> App Store Connect API credential structure validated"
}

if [ -n "${VALIDATE_CREDENTIALS_ONLY:-}" ]; then
    validate_asc_credentials
    exit 0
fi

XCODE_AUTH_ARGS=()
if [ -n "${ASC_API_KEY_ID:-}${ASC_API_ISSUER_ID:-}${ASC_API_KEY_P8:-}" ]; then
    validate_asc_credentials
    XCODE_AUTH_ARGS=(
        -authenticationKeyPath "$ASC_API_KEY_P8"
        -authenticationKeyID "$ASC_API_KEY_ID"
        -authenticationKeyIssuerID "$ASC_API_ISSUER_ID"
    )
fi

echo "==> Scanning tracked source for secret material"
python3 scripts/scan_source_secrets.py

echo "==> Regenerating Xcode project"
XCODEGEN_BIN=$(./scripts/bootstrap_xcodegen.sh)
echo "==> Using $($XCODEGEN_BIN --version) from the repository tool directory"
"$XCODEGEN_BIN" generate --quiet

if [ -z "${SKIP_GEN_ICONS:-}" ]; then
    echo "==> Regenerating app icons"
    python3 scripts/gen_appiconset.py
fi
python3 scripts/validate_appiconsets.py
python3 scripts/validate_privacy_manifest.py App/PrivacyInfo.xcprivacy

mkdir -p "$BUILD_DIR"
echo "==> Generating source-revision SPDX SBOM"
SBOM_OUTPUT="$BUILD_DIR/ThoxWarRoom.spdx.json" ./scripts/generate_sbom.sh

ARCHIVE="$BUILD_DIR/$PROJECT_NAME.xcarchive"
echo "==> Archiving Mac App Store build ($BUILD_CONFIG)"
xcodebuild \
    -project "$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$BUILD_CONFIG" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$BUILD_DIR/derived" \
    -archivePath "$ARCHIVE" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    -allowProvisioningUpdates \
    ${XCODE_AUTH_ARGS[@]+"${XCODE_AUTH_ARGS[@]}"} \
    clean archive | tee "$BUILD_DIR/archive.log" >/dev/null
tail -30 "$BUILD_DIR/archive.log"

APP_PATH="$ARCHIVE/Products/Applications/$PROJECT_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: archived app missing from $ARCHIVE" >&2
    exit 1
fi
python3 scripts/validate_privacy_manifest.py \
    "$APP_PATH/Contents/Resources/PrivacyInfo.xcprivacy"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ENTITLEMENTS="$BUILD_DIR/archive-entitlements.plist"
codesign -d --entitlements :- "$APP_PATH" >"$ENTITLEMENTS" 2>/dev/null
if ! /usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$ENTITLEMENTS" 2>/dev/null | grep -q '^true$'; then
    echo "ERROR: archived macOS app is missing app sandbox entitlement" >&2
    exit 1
fi
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$ENTITLEMENTS" 2>/dev/null | grep -q '^true$'; then
    echo "ERROR: archived macOS app contains get-task-allow=true" >&2
    exit 1
fi

EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat >"$EXPORT_OPTIONS" <<EOF
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
    <key>manageVersion</key>
    <false/>
</dict>
</plist>
EOF

EXPORT_DIR="$BUILD_DIR/export"
if [ -e "$EXPORT_DIR" ]; then
    echo "ERROR: export directory already exists; choose a new BUILD_DIR" >&2
    exit 1
fi
mkdir -p "$EXPORT_DIR"
echo "==> Exporting Mac App Store package"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates \
    ${XCODE_AUTH_ARGS[@]+"${XCODE_AUTH_ARGS[@]}"} | tee "$BUILD_DIR/export.log" >/dev/null
tail -30 "$BUILD_DIR/export.log"

PACKAGE_PATH=$(find "$EXPORT_DIR" -maxdepth 1 -type f -name '*.pkg' -print -quit)
if [ -z "$PACKAGE_PATH" ]; then
    echo "ERROR: exported Mac App Store .pkg not found" >&2
    exit 1
fi
pkgutil --check-signature "$PACKAGE_PATH"

if [ -z "${SKIP_UPLOAD:-}" ]; then
    echo "==> Uploading macOS build to App Store Connect"
    if [ -n "${ASC_API_KEY_ID:-}${ASC_API_ISSUER_ID:-}${ASC_API_KEY_P8:-}" ]; then
        xcrun altool --upload-app \
            --type macos \
            --file "$PACKAGE_PATH" \
            --api-key "$ASC_API_KEY_ID" \
            --api-issuer "$ASC_API_ISSUER_ID" \
            --p8-file-path "$ASC_API_KEY_P8"
    elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_PASSWORD:-}" ]; then
        xcrun altool --upload-app \
            --type macos \
            --file "$PACKAGE_PATH" \
            --username "$APPLE_ID" \
            --password "$APPLE_PASSWORD"
    else
        echo "ERROR: no App Store Connect upload credentials provided" >&2
        exit 1
    fi
else
    echo "==> Skipping upload (SKIP_UPLOAD set)"
fi

echo "==> Done"
echo "Archive: $ARCHIVE"
echo "Package: $PACKAGE_PATH"
echo "SBOM:    $BUILD_DIR/ThoxWarRoom.spdx.json"
echo "Bundle:  $BUNDLE_ID"
echo "Team:    $TEAM_ID"
