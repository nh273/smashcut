#!/bin/bash
# Smashcut E2E Quick Check
# Builds, installs, launches the app and takes a launch screenshot.
# For the full visual e2e report with flow walkthroughs, use the Mayor's
# mobile MCP test runner (run in Claude Code session).
#
# Usage: ./scripts/run-e2e.sh [DEVICE_ID]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REPORT_DIR="$PROJECT_DIR/reports"
SCREENSHOT_DIR="$REPORT_DIR/screenshots"
BUNDLE_ID="com.nh273.smashcut"

# Find device
DEVICE_ID="${1:-}"
if [ -z "$DEVICE_ID" ]; then
    DEVICE_ID=$(xcrun simctl list devices booted | grep "iPhone" | head -1 | grep -oE '[0-9A-F-]{36}')
fi

if [ -z "$DEVICE_ID" ]; then
    echo "ERROR: No booted iPhone simulator found."
    exit 1
fi

echo "=== Smashcut E2E Quick Check ==="
echo "Device: $DEVICE_ID"

mkdir -p "$SCREENSHOT_DIR"

# Build
echo "Building..."
cd "$PROJECT_DIR"
if ! xcodebuild -project Smashcut.xcodeproj -scheme Smashcut \
    -destination "platform=iOS Simulator,id=$DEVICE_ID" \
    -quiet build 2>&1; then
    echo "FAIL: Build failed"
    exit 1
fi
echo "PASS: Build succeeded"

# Install
APP_PATH=""
for d in ~/Library/Developer/Xcode/DerivedData/Smashcut-*/Build/Products/Debug-iphonesimulator/Smashcut.app; do
    if [ -f "$d/Smashcut" ]; then
        APP_PATH="$d"
    fi
done

if [ -z "$APP_PATH" ]; then
    echo "FAIL: No .app bundle found"
    exit 1
fi

xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
echo "PASS: Installed"

# Launch
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null
sleep 2
xcrun simctl io "$DEVICE_ID" screenshot "$SCREENSHOT_DIR/launch.png" 2>/dev/null
echo "PASS: Launched (screenshot: reports/screenshots/launch.png)"

# Check for crashes in last 5 seconds
CRASHES=$(xcrun simctl spawn "$DEVICE_ID" log show \
    --predicate 'process == "Smashcut"' \
    --last 5s --style compact 2>/dev/null | grep -i "fatal error" || true)

if [ -n "$CRASHES" ]; then
    echo "FAIL: Crash detected: $CRASHES"
    exit 1
fi

echo "PASS: No crashes"
echo ""
echo "=== Quick check passed. For full visual report, run e2e in Claude Code. ==="
