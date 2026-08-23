#!/usr/bin/env bash
# scripts/ci.sh
# Local CI: regenerate project, generate icons, build macOS, build iOS, run tests.
#
# This is the local equivalent of GitHub Actions — no remote runners.
# Tests must pass before this script exits 0.
#
# Env:
#   SKIP_IOS_BUILD   Skip iOS build (faster local iteration)
#   SKIP_MACOS_BUILD Skip macOS build
#   SKIP_NOTARIZE    Skip notarization
#   SKIP_UPLOAD      Skip TestFlight upload
set -euo pipefail

cd "$(dirname "$0")/.."

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

step() { echo -e "${GREEN}==>${NC} $*"; }
warn() { echo -e "${YELLOW}WARN:${NC} $*"; }
fail() { echo -e "${RED}FAIL:${NC} $*"; exit 1; }

step "Sanity: xcodebuild, xcrun, xcodegen, python3, iconutil"
for cmd in xcodebuild xcrun xcodegen python3 iconutil; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        fail "$cmd not found in PATH"
    fi
done

step "Regenerating Xcode project"
xcodegen generate --quiet

step "Regenerating app icons"
python3 scripts/gen_appiconset.py

step "Validating app icon catalogs"
python3 scripts/validate_appiconsets.py

step "Compiling Swift sources (sanity)"
xcodebuild \
    -project ThoxWarRoom.xcodeproj \
    -scheme "ThoxWarRoom macOS" \
    -destination "generic/platform=macOS" \
    -configuration Debug \
    -derivedDataPath build/ci-derived \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    build-for-testing 2>&1 | tail -20

step "Running macOS tests"
xcodebuild \
    -project ThoxWarRoom.xcodeproj \
    -scheme "ThoxWarRoom macOS" \
    -destination "platform=macOS" \
    -configuration Debug \
    -derivedDataPath build/ci-derived \
    CODE_SIGNING_ALLOWED=NO \
    test-without-building 2>&1 | tail -40

if [ -z "${SKIP_MACOS_BUILD:-}" ]; then
    step "Building unsigned macOS packaging artifact (CI validation only)"
    SIGNING_MODE=unsigned SKIP_NOTARIZE=1 BUILD_DIR=build/macos-ci ./scripts/build_macos.sh
fi

if [ -z "${SKIP_IOS_BUILD:-}" ]; then
    step "Building iOS archive"
    SKIP_UPLOAD=${SKIP_UPLOAD:-1} BUILD_DIR=build/ios-ci ./scripts/build_ios.sh
fi

step "All CI checks passed"
