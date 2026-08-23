#!/usr/bin/env bash
# Secret-free PR/local CI. This script never archives, signs, exports, uploads,
# notarizes, or invokes either release packaging script.
set -euo pipefail

cd "$(dirname "$0")/.."

for command_name in xcodebuild xcrun python3 iconutil; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "ERROR: $command_name is required" >&2
        exit 1
    fi
done

XCODEGEN_BIN=$(./scripts/bootstrap_xcodegen.sh)
echo "==> Using $($XCODEGEN_BIN --version) from the repository tool directory"

echo "==> Generating the Xcode project and app icons"
"$XCODEGEN_BIN" generate --quiet
python3 scripts/gen_appiconset.py
python3 scripts/validate_appiconsets.py
python3 scripts/validate_generated_drift.py "$XCODEGEN_BIN"

DERIVED_DATA="${CI_DERIVED_DATA:-build/unsigned-ci-derived}"

echo "==> Building macOS tests without signing"
xcodebuild \
    -project ThoxWarRoom.xcodeproj \
    -scheme "ThoxWarRoom macOS" \
    -destination "generic/platform=macOS" \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    build-for-testing

echo "==> Running macOS tests without signing"
xcodebuild \
    -project ThoxWarRoom.xcodeproj \
    -scheme "ThoxWarRoom macOS" \
    -destination "platform=macOS" \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    test-without-building

echo "==> Building iOS app and tests for a generic Simulator without signing"
xcodebuild \
    -project ThoxWarRoom.xcodeproj \
    -scheme "ThoxWarRoom iOS" \
    -destination "generic/platform=iOS Simulator" \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    build-for-testing

echo "==> Unsigned CI passed"
