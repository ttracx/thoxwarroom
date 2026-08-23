#!/usr/bin/env bash
# Restore ignored generated icon catalogs before Xcode compiles assets.
set -euo pipefail

cd "$(dirname "$0")/.."

validator_python=$(command -v python3 || true)
if [ -n "$validator_python" ] && "$validator_python" scripts/validate_appiconsets.py >/dev/null 2>&1; then
    exit 0
fi

icon_python="${THOX_ICON_PYTHON:-}"
for candidate in "$icon_python" "$validator_python" /opt/homebrew/bin/python3 /usr/local/bin/python3; do
    if [ -n "$candidate" ] && [ -x "$candidate" ] \
        && "$candidate" -c 'from PIL import Image, ImageDraw' >/dev/null 2>&1; then
        icon_python="$candidate"
        break
    fi
done

if [ -z "$icon_python" ] || ! "$icon_python" -c 'from PIL import Image, ImageDraw' >/dev/null 2>&1; then
    echo "ERROR: app icon generation requires a Python 3 interpreter with Pillow." >&2
    echo "Run ./scripts/bootstrap.sh from a configured development shell or set THOX_ICON_PYTHON." >&2
    exit 1
fi

echo "==> Generated app icons are missing or invalid; regenerating"
"$icon_python" scripts/gen_appiconset.py
"$icon_python" scripts/validate_appiconsets.py
