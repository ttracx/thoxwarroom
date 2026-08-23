#!/usr/bin/env bash
# Install the repository-pinned XcodeGen release under .tools/.
# Nothing is written to /usr/local, Homebrew, or another global location.
set -euo pipefail

cd "$(dirname "$0")/.."

XCODEGEN_VERSION="2.46.0"
XCODEGEN_SHA256="4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"
XCODEGEN_URL="https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"
INSTALL_ROOT="$PWD/.tools/xcodegen/$XCODEGEN_VERSION"
XCODEGEN_BIN="$INSTALL_ROOT/xcodegen/bin/xcodegen"

for command_name in curl shasum unzip; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "ERROR: $command_name is required to bootstrap XcodeGen" >&2
        exit 1
    fi
done

if [ -x "$XCODEGEN_BIN" ]; then
    installed_version=$($XCODEGEN_BIN --version)
    if [ "$installed_version" = "Version: $XCODEGEN_VERSION" ]; then
        printf '%s\n' "$XCODEGEN_BIN"
        exit 0
    fi
    echo "ERROR: cached XcodeGen version does not match $XCODEGEN_VERSION" >&2
    exit 1
fi

temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT
archive="$temporary_directory/xcodegen.zip"

echo "Downloading repository-pinned XcodeGen $XCODEGEN_VERSION" >&2
curl --fail --silent --show-error --location \
    --proto '=https' --tlsv1.2 \
    "$XCODEGEN_URL" \
    --output "$archive"

actual_sha256=$(shasum -a 256 "$archive" | awk '{print $1}')
if [ "$actual_sha256" != "$XCODEGEN_SHA256" ]; then
    echo "ERROR: XcodeGen archive checksum mismatch" >&2
    exit 1
fi

mkdir -p "$(dirname "$INSTALL_ROOT")"
staging="$temporary_directory/install"
mkdir -p "$staging"
unzip -q "$archive" -d "$staging"
if [ ! -x "$staging/xcodegen/bin/xcodegen" ]; then
    echo "ERROR: verified XcodeGen archive has an unexpected layout" >&2
    exit 1
fi
rm -rf "$INSTALL_ROOT"
mv "$staging" "$INSTALL_ROOT"

installed_version=$($XCODEGEN_BIN --version)
if [ "$installed_version" != "Version: $XCODEGEN_VERSION" ]; then
    echo "ERROR: bootstrapped XcodeGen failed its version check" >&2
    exit 1
fi

printf '%s\n' "$XCODEGEN_BIN"
