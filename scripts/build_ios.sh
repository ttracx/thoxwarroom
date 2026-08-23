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
#   ASC_API_KEY_ID       App Store Connect API key ID
#   ASC_API_ISSUER_ID    App Store Connect API issuer ID
#   ASC_API_KEY_P8       Path to the matching private .p8 key
#   VALIDATE_CREDENTIALS_ONLY  Validate the ASC key locally, then exit
set -euo pipefail

cd "$(dirname "$0")/.."

BUILD_DIR=${BUILD_DIR:-build/ios}
BUILD_CONFIG=${BUILD_CONFIG:-Release}
PROJECT_NAME="ThoxWarRoom"
SCHEME="ThoxWarRoom iOS"
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
    # altool writes the generated bearer token to stderr on some Xcode
    # versions. Suppress both streams so validation can never disclose it.
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

echo "==> Regenerating Xcode project"
XCODEGEN_BIN=$(./scripts/bootstrap_xcodegen.sh)
echo "==> Using $($XCODEGEN_BIN --version) from the repository tool directory"
"$XCODEGEN_BIN" generate --quiet

if [ -z "${SKIP_GEN_ICONS:-}" ]; then
    echo "==> Regenerating app icons"
    python3 scripts/gen_appiconset.py
fi

echo "==> Validating app icon catalogs"
python3 scripts/validate_appiconsets.py
echo "==> Validating reviewed privacy declarations"
python3 scripts/validate_privacy_manifest.py App/PrivacyInfo.xcprivacy

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
    -allowProvisioningUpdates \
    "${XCODE_AUTH_ARGS[@]}" \
    clean archive | tee "$BUILD_DIR/archive.log" >/dev/null

tail -30 "$BUILD_DIR/archive.log"

ARCHIVE="$BUILD_DIR/$PROJECT_NAME.xcarchive"
if [ ! -d "$ARCHIVE" ]; then
    echo "ERROR: archive at $ARCHIVE missing"
    exit 1
fi

python3 scripts/validate_privacy_manifest.py \
    "$ARCHIVE/Products/Applications/$PROJECT_NAME.app/PrivacyInfo.xcprivacy"

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
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates \
    "${XCODE_AUTH_ARGS[@]}" | tee "$BUILD_DIR/export.log" >/dev/null

tail -30 "$BUILD_DIR/export.log"

IPA_PATH=$(find "$EXPORT_DIR" -name "*.ipa" | head -1 || true)
if [ -z "${IPA_PATH:-}" ]; then
    echo "ERROR: .ipa not found in $EXPORT_DIR"
    exit 1
fi

echo "==> IPA at: $IPA_PATH"

IPA_PRIVACY_MANIFEST=$(mktemp "${TMPDIR:-/tmp}/thoxwarroom-privacy.XXXXXX")
trap 'rm -f "$IPA_PRIVACY_MANIFEST"' EXIT
if ! unzip -p "$IPA_PATH" "Payload/$PROJECT_NAME.app/PrivacyInfo.xcprivacy" >"$IPA_PRIVACY_MANIFEST"; then
    echo "ERROR: exported IPA does not contain PrivacyInfo.xcprivacy at the app-bundle root" >&2
    exit 1
fi
python3 scripts/validate_privacy_manifest.py "$IPA_PRIVACY_MANIFEST"

if [ -z "${SKIP_UPLOAD:-}" ]; then
    echo "==> Uploading to TestFlight via xcrun altool"
    if [ -n "${ASC_API_KEY_ID:-}${ASC_API_ISSUER_ID:-}${ASC_API_KEY_P8:-}" ]; then
        xcrun altool --upload-app \
            --type ios \
            --file "$IPA_PATH" \
            --api-key "$ASC_API_KEY_ID" \
            --api-issuer "$ASC_API_ISSUER_ID" \
            --p8-file-path "$ASC_API_KEY_P8"
    elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_PASSWORD:-}" ]; then
        xcrun altool --upload-app \
            --type ios \
            --file "$IPA_PATH" \
            --username "$APPLE_ID" \
            --password "$APPLE_PASSWORD"
    else
        echo "ERROR: no upload credentials provided"
        echo "       Set ASC_API_KEY_ID+ASC_API_ISSUER_ID+ASC_API_KEY_P8 (preferred)"
        echo "       or APPLE_ID+APPLE_PASSWORD"
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
