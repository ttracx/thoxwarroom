#!/bin/bash
# Create a macOS DMG installer for ThoxWarRoom.
# Usage: ./scripts/create_dmg.sh [output_path]
#
# Requires: flutter build macos --release already completed.

set -e

APP_NAME="ThoxWarRoom"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$PROJECT_ROOT/build/macos/Build/Products/Release/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: $APP_PATH not found. Run 'flutter build macos --release' first."
  exit 1
fi

VERSION=$(grep '^version:' "$PROJECT_ROOT/pubspec.yaml" | awk '{print $2}' | cut -d '+' -f 1)
OUTPUT="${1:-$PROJECT_ROOT/build/macos/${APP_NAME}-${VERSION}.dmg}"

# Prepare staging directory
STAGING="$PROJECT_ROOT/build/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Create the DMG
echo "Creating DMG: $OUTPUT"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$OUTPUT"

# Clean up
rm -rf "$STAGING"

echo "DMG created: $OUTPUT"
echo "Size: $(du -h "$OUTPUT" | cut -f1)"