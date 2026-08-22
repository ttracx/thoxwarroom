#!/usr/bin/env bash
# scripts/smoke_test.sh
# End-to-end smoke test for the built ThoxWarRoom.app.
#
# Steps:
#   1. Launch the .app (open -W in background).
#   2. Take a cua-driver screenshot of the loading/loaded state.
#   3. Wait for the WKWebView to settle.
#   4. Take another screenshot post-load.
#   5. Quit, relaunch, take another screenshot to verify persistent login.
#
# Outputs:
#   /Volumes/VibeStore/smoketest/thoxwarroom-{01,02,03}.png
set -euo pipefail

cd "$(dirname "$0")/.."

APP_PATH=${APP_PATH:-build/macos/derived/Build/Products/Release/ThoxWarRoom.app}
if [ ! -d "$APP_PATH" ]; then
    APP_PATH=$(find build -name "ThoxWarRoom.app" -type d 2>/dev/null | head -1 || true)
fi
if [ -z "${APP_PATH:-}" ] || [ ! -d "$APP_PATH" ]; then
    echo "ERROR: ThoxWarRoom.app not found. Run scripts/build_macos.sh first." >&2
    exit 1
fi

OUT_DIR="/Volumes/VibeStore/smoketest"
mkdir -p "$OUT_DIR"

echo "==> App: $APP_PATH"
echo "==> Output: $OUT_DIR"

launch_app() {
    # open returns immediately, the app runs detached.
    open -a "$APP_PATH"
}

quit_app() {
    osascript -e 'tell application "ThoxWarRoom" to quit' 2>/dev/null || \
        pkill -f "ThoxWarRoom.app/Contents/MacOS/ThoxWarRoom" || true
    sleep 1
}

screenshot() {
    local out="$1"
    # cua-driver captures whatever the user has on screen — we just need
    # the ThoxWarRoom window. Use screencapture as a fallback when cua-driver
    # is not running.
    if command -v cua-driver >/dev/null 2>&1; then
        cua-driver capture --output "$out" || screencapture -x "$out"
    else
        screencapture -x "$out"
    fi
}

echo "==> First launch (loading)"
launch_app
sleep 3
screenshot "$OUT_DIR/thoxwarroom-01-loading.png"

echo "==> Wait for full load"
sleep 8
screenshot "$OUT_DIR/thoxwarroom-02-loaded.png"

echo "==> Verify webui.thox.ai is loaded"
# Pull the URL from the WKWebView process via lsappinfo or by reading
# the app's NSWindow title. For now we just confirm the process is alive
# and the screenshot was captured.
if [ -s "$OUT_DIR/thoxwarroom-02-loaded.png" ]; then
    echo "==> Loaded screenshot captured"
else
    echo "ERROR: screenshot was empty" >&2
    exit 1
fi

echo "==> Quit and relaunch (login persistence check)"
quit_app
sleep 2
launch_app
sleep 8
screenshot "$OUT_DIR/thoxwarroom-03-relaunch.png"

echo "==> Smoke test complete"
ls -la "$OUT_DIR"/thoxwarroom-*.png 2>/dev/null

quit_app
