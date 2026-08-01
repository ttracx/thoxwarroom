#!/bin/bash
# Create Windows installer packages for ThoxWarRoom.
# Produces both a portable ZIP and an MSIX installer.
#
# Usage: ./scripts/create_windows_installer.sh
# Requires: flutter build windows --release already completed.

set -e

APP_NAME="ThoxWarRoom"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE_DIR="$PROJECT_ROOT/build/windows/x64/runner/Release"

if [ ! -d "$RELEASE_DIR" ]; then
  echo "ERROR: $RELEASE_DIR not found. Run 'flutter build windows --release' first."
  exit 1
fi

VERSION=$(grep '^version:' "$PROJECT_ROOT/pubspec.yaml" | awk '{print $2}' | cut -d '+' -f 1)
ZIP_OUTPUT="$PROJECT_ROOT/build/windows/${APP_NAME}-${VERSION}-windows-x64.zip"

# Create ZIP package
echo "Creating ZIP: $ZIP_OUTPUT"
cd "$RELEASE_DIR"
zip -r -9 "$ZIP_OUTPUT" ./*
cd "$PROJECT_ROOT"

echo "ZIP created: $ZIP_OUTPUT"
echo "Size: $(du -h "$ZIP_OUTPUT" | cut -f1)"

# Create MSIX (requires msix package and signing certificate)
echo ""
echo "Creating MSIX installer..."
dart run msix:create || echo "WARNING: MSIX creation requires a signing certificate. Skipping."

echo ""
echo "Windows installer packages created in build/windows/"