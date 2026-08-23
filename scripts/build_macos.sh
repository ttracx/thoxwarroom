#!/usr/bin/env bash
# Build and validate a macOS app and DMG.
#
# Default: Developer ID Application signing, notarization through a notarytool
# Keychain profile, stapling, and Gatekeeper validation of the exact final DMG.
# Local/CI examples (never release-ready):
#   SIGNING_MODE=unsigned SKIP_NOTARIZE=1 ./scripts/build_macos.sh
#   SIGNING_MODE=adhoc SKIP_NOTARIZE=1 ./scripts/build_macos.sh
#
# Environment:
#   BUILD_DIR          Output directory (default: build/macos)
#   BUILD_CONFIG       Release | Debug (default: Release)
#   ARCH               arm64 | x86_64 (default: arm64)
#   SIGNING_MODE       developer-id | adhoc | unsigned (default: developer-id)
#   SIGNING_IDENTITY   Optional exact Developer ID certificate name or SHA-1.
#                      When omitted, resolve the certificate by APPLE_TEAM_ID.
#   NOTARY_PROFILE     notarytool Keychain profile name (distribution only)
#   SKIP_NOTARIZE      Set to 1 only for a non-release/local build
#   SKIP_GEN_ICONS     Set to 1 to keep the existing generated icons
#   APPLE_TEAM_ID      Team ID (default: DVJ6Z5343U)
set -euo pipefail

cd "$(dirname "$0")/.."

BUILD_DIR=${BUILD_DIR:-build/macos}
BUILD_CONFIG=${BUILD_CONFIG:-Release}
ARCH=${ARCH:-arm64}
SIGNING_MODE=${SIGNING_MODE:-developer-id}
SKIP_NOTARIZE=${SKIP_NOTARIZE:-0}
PROJECT_NAME="ThoxWarRoom"
SCHEME="ThoxWarRoom macOS"
APP_NAME="ThoxWarRoom.app"
TEAM_ID=${APPLE_TEAM_ID:-DVJ6Z5343U}
SIGNING_IDENTITY=${SIGNING_IDENTITY:-}
BUNDLE_ID="ai.thox.warroom"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

case "$SIGNING_MODE" in
    developer-id|adhoc|unsigned) ;;
    *) fail "SIGNING_MODE must be developer-id, adhoc, or unsigned" ;;
esac

case "$SKIP_NOTARIZE" in
    0|1) ;;
    *) fail "SKIP_NOTARIZE must be 0 or 1" ;;
esac

if [ "$SIGNING_MODE" != "developer-id" ] && [ "$SKIP_NOTARIZE" != "1" ]; then
    fail "$SIGNING_MODE builds cannot be notarized; set SKIP_NOTARIZE=1"
fi

if [ "$SIGNING_MODE" = "developer-id" ]; then
    IDENTITY_LIST=$(security find-identity -v -p codesigning)
    TEAM_IDENTITY_SHA=$(printf '%s\n' "$IDENTITY_LIST" | awk -v team="$TEAM_ID" '
        index($0, "Developer ID Application:") && index($0, "(" team ")") { print $2; exit }
    ')
    if [ -z "$TEAM_IDENTITY_SHA" ]; then
        fail "no Developer ID Application signing identity for team $TEAM_ID is available in the Keychain"
    fi
    if [ -n "$SIGNING_IDENTITY" ]; then
        if ! printf '%s\n' "$IDENTITY_LIST" | grep -F "$SIGNING_IDENTITY" | grep -Fq "($TEAM_ID)"; then
            fail "SIGNING_IDENTITY does not resolve to a Developer ID Application certificate for team $TEAM_ID"
        fi
    else
        SIGNING_IDENTITY=$TEAM_IDENTITY_SHA
    fi
    if [ "$SKIP_NOTARIZE" = "0" ] && [ -z "${NOTARY_PROFILE:-}" ]; then
        fail "NOTARY_PROFILE is required for a notarized distribution build; use a notarytool Keychain profile or explicitly set SKIP_NOTARIZE=1 for local validation"
    fi
fi

echo "==> Regenerating Xcode project"
XCODEGEN_BIN=$(./scripts/bootstrap_xcodegen.sh)
echo "==> Using $($XCODEGEN_BIN --version) from the repository tool directory"
"$XCODEGEN_BIN" generate --quiet

if [ -z "${SKIP_GEN_ICONS:-}" ]; then
    echo "==> Regenerating app icons"
    python3 scripts/gen_appiconset.py
fi

echo "==> Validating reviewed privacy declarations"
python3 scripts/validate_privacy_manifest.py App/PrivacyInfo.xcprivacy

mkdir -p "$BUILD_DIR"

echo "==> Generating source-revision SPDX SBOM"
if [ "$SIGNING_MODE" = "developer-id" ]; then
    SBOM_OUTPUT="$BUILD_DIR/ThoxWarRoom.spdx.json" ./scripts/generate_sbom.sh
else
    ALLOW_DIRTY_SBOM=1 \
        SBOM_OUTPUT="$BUILD_DIR/ThoxWarRoom.spdx.json" \
        ./scripts/generate_sbom.sh
fi

XCODE_SIGNING_ARGS=()
case "$SIGNING_MODE" in
    developer-id)
        XCODE_SIGNING_ARGS+=(
            CODE_SIGN_STYLE=Manual
            "CODE_SIGN_IDENTITY=$SIGNING_IDENTITY"
            "DEVELOPMENT_TEAM=$TEAM_ID"
            PROVISIONING_PROFILE_SPECIFIER=
        )
        ;;
    adhoc)
        XCODE_SIGNING_ARGS+=(
            CODE_SIGN_STYLE=Manual
            CODE_SIGN_IDENTITY=-
            DEVELOPMENT_TEAM=
            PROVISIONING_PROFILE_SPECIFIER=
        )
        ;;
    unsigned)
        XCODE_SIGNING_ARGS+=(
            CODE_SIGNING_ALLOWED=NO
            CODE_SIGNING_REQUIRED=NO
            CODE_SIGN_IDENTITY=
            DEVELOPMENT_TEAM=
        )
        ;;
esac

echo "==> Building $SCHEME ($BUILD_CONFIG, $ARCH, signing: $SIGNING_MODE)"
if ! xcodebuild \
    -project "$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$BUILD_CONFIG" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$BUILD_DIR/derived" \
    "${XCODE_SIGNING_ARGS[@]}" \
    ARCHS="$ARCH" \
    ONLY_ACTIVE_ARCH=NO \
    ENABLE_HARDENED_RUNTIME=YES \
    clean build | tee "$BUILD_DIR/build.log" >/dev/null; then
    tail -40 "$BUILD_DIR/build.log"
    fail "xcodebuild failed"
fi

tail -40 "$BUILD_DIR/build.log"

APP_PATH=$(find "$BUILD_DIR/derived/Build/Products/$BUILD_CONFIG" -name "$APP_NAME" -type d | head -1 || true)
[ -n "${APP_PATH:-}" ] || fail "build succeeded but $APP_NAME was not found in derived data"

echo "==> App built at: $APP_PATH"
python3 scripts/validate_privacy_manifest.py \
    "$APP_PATH/Contents/Resources/PrivacyInfo.xcprivacy"

assert_no_debug_entitlement() {
    local app_path=$1
    local entitlements_path="$BUILD_DIR/verified-entitlements.plist"

    codesign -d --entitlements :- "$app_path" >"$entitlements_path" 2>/dev/null || \
        fail "could not read signed entitlements from $app_path"
    if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$entitlements_path" 2>/dev/null | grep -q '^true$'; then
        fail "$app_path contains forbidden com.apple.security.get-task-allow=true"
    fi
}

verify_developer_id_app() {
    local app_path=$1
    local details

    codesign --verify --deep --strict --verbose=2 "$app_path"
    details=$(codesign -dv --verbose=4 "$app_path" 2>&1)
    echo "$details" | grep -Fq "Authority=Developer ID Application:" || \
        fail "$app_path is not signed with Developer ID Application"
    echo "$details" | grep -Fq "TeamIdentifier=$TEAM_ID" || \
        fail "$app_path is not signed by expected team $TEAM_ID"
    assert_no_debug_entitlement "$app_path"
}

if [ "$SIGNING_MODE" = "developer-id" ]; then
    echo "==> Verifying Developer ID app signature and release entitlements"
    verify_developer_id_app "$APP_PATH"
elif [ "$SIGNING_MODE" = "adhoc" ]; then
    echo "==> Verifying ad hoc app signature (not for distribution)"
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
else
    echo "==> Unsigned app build selected; signature trust checks are intentionally skipped"
fi

# Staple before staging so the app embedded in the final DMG has an offline ticket.
if [ "$SKIP_NOTARIZE" = "0" ]; then
    APP_NOTARY_ZIP="$BUILD_DIR/ThoxWarRoom-notary.zip"
    rm -f "$APP_NOTARY_ZIP"
    echo "==> Submitting signed app for notarization"
    ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$APP_NOTARY_ZIP"
    xcrun notarytool submit "$APP_NOTARY_ZIP" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    echo "==> Stapling and validating app ticket"
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"
    verify_developer_id_app "$APP_PATH"
else
    echo "==> Notarization explicitly skipped; output is not release-ready"
fi

STAGING="$BUILD_DIR/staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP_PATH" "$STAGING/$APP_NAME"
ln -s /Applications "$STAGING/Applications"

DMG_PATH="$BUILD_DIR/ThoxWarRoom-$BUILD_CONFIG-$ARCH.dmg"
echo "==> Creating final DMG at $DMG_PATH"
hdiutil create -volname "ThoxWarRoom" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"

if [ "$SIGNING_MODE" = "developer-id" ]; then
    echo "==> Signing final DMG with Developer ID Application"
    codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
    codesign --verify --strict --verbose=2 "$DMG_PATH"
fi

if [ "$SKIP_NOTARIZE" = "0" ]; then
    echo "==> Submitting final signed DMG for notarization"
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    echo "==> Stapling and validating final DMG ticket"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
fi

verify_final_dmg() {
    local mount_point
    local mounted_app

    echo "==> Verifying the exact final DMG"
    codesign --verify --strict --verbose=2 "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"

    mount_point=$(mktemp -d "$BUILD_DIR/verify-mount.XXXXXX")
    hdiutil attach -readonly -nobrowse -mountpoint "$mount_point" "$DMG_PATH" >/dev/null
    mounted_app="$mount_point/$APP_NAME"
    if [ ! -d "$mounted_app" ]; then
        hdiutil detach "$mount_point" >/dev/null || true
        rmdir "$mount_point" || true
        fail "$APP_NAME is missing from final DMG"
    fi

    (
        trap 'hdiutil detach "$mount_point" >/dev/null 2>&1 || true; rmdir "$mount_point" >/dev/null 2>&1 || true' EXIT
        python3 scripts/validate_privacy_manifest.py \
            "$mounted_app/Contents/Resources/PrivacyInfo.xcprivacy"
        verify_developer_id_app "$mounted_app"
        xcrun stapler validate "$mounted_app"
        spctl --assess --type execute --verbose=2 "$mounted_app"
    )
}

if [ "$SIGNING_MODE" = "developer-id" ] && [ "$SKIP_NOTARIZE" = "0" ]; then
    verify_final_dmg
else
    echo "==> Final Gatekeeper/stapler checks skipped for non-notarized local artifact"
    hdiutil verify "$DMG_PATH"
fi

CHECKSUM_PATH="$DMG_PATH.sha256"
shasum -a 256 "$DMG_PATH" >"$CHECKSUM_PATH"

echo "==> Done"
echo "APP:       $APP_PATH"
echo "DMG:       $DMG_PATH"
echo "SHA-256:   $CHECKSUM_PATH"
echo "Bundle:    $BUNDLE_ID"
echo "Team:      $TEAM_ID"
echo "Signing:   $SIGNING_MODE"
echo "Notarized: $([ "$SKIP_NOTARIZE" = "0" ] && echo yes || echo no)"
