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

echo "==> Validating deterministic release SBOM generation"
python3 -m unittest discover -s scripts/tests -p 'test_*.py'
python3 scripts/scan_source_secrets.py
ALLOW_DIRTY_SBOM=1 \
    SBOM_OUTPUT=build/unsigned-ci/ThoxWarRoom.spdx.json \
    ./scripts/generate_sbom.sh

echo "==> Generating the Xcode project and app icons"
"$XCODEGEN_BIN" generate --quiet
python3 scripts/gen_appiconset.py
python3 scripts/validate_appiconsets.py
python3 scripts/validate_privacy_manifest.py App/PrivacyInfo.xcprivacy
python3 scripts/validate_generated_drift.py "$XCODEGEN_BIN"

echo "==> Testing standalone Swift packages with warnings as errors"
for package_manifest in Packages/*/Package.swift; do
    package_dir="${package_manifest%/Package.swift}"
    echo "==> swift test: $package_dir"
    # Regenerate the test runner for the selected toolchain. Reusing a runner
    # emitted by another Xcode can retain a link to Swift Testing even though
    # this repository's packages contain XCTest suites only.
    swift package --package-path "$package_dir" clean
    # Every package currently uses XCTest. Disabling the unused Swift Testing
    # runner avoids linking Xcode's Testing support library into these XCTest-only
    # bundles, which is unavailable in some otherwise supported Xcode toolchains.
    swift test \
        --package-path "$package_dir" \
        --disable-swift-testing \
        -Xswiftc -warnings-as-errors
done

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

python3 scripts/validate_privacy_manifest.py \
    "$DERIVED_DATA/Build/Products/Debug/ThoxWarRoom.app/Contents/Resources/PrivacyInfo.xcprivacy"

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

python3 scripts/validate_privacy_manifest.py \
    "$DERIVED_DATA/Build/Products/Debug-iphonesimulator/ThoxWarRoom.app/PrivacyInfo.xcprivacy"

echo "==> Unsigned CI passed"
