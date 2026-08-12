#!/bin/bash
# Packages the SwiftPM executable as a proper .app bundle, launched via
# `open` rather than `swift run` so it registers with LaunchServices as a
# real menu bar app (Info.plist's LSUIElement hides its Dock icon).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
APP_NAME="ClaudeUsageMenuBar.app"
BIN_NAME="ClaudeUsageMenuBar"

swift build -c "$CONFIG"

rm -rf "$APP_NAME"
mkdir -p "$APP_NAME/Contents/MacOS"
cp ".build/$CONFIG/$BIN_NAME" "$APP_NAME/Contents/MacOS/$BIN_NAME"
cp "Resources/Info.plist" "$APP_NAME/Contents/Info.plist"

codesign --force --deep --sign - "$APP_NAME"

echo "Built $APP_NAME"
echo "Run with: open $APP_NAME"
