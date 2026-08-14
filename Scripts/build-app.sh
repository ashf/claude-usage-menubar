#!/bin/bash
# Packages the SwiftPM executable as a proper .app bundle, launched via
# `open` rather than `swift run` so it registers with LaunchServices as a
# real menu bar app (Info.plist's LSUIElement hides its Dock icon).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
APP_NAME="ClaudeUsageMenuBar.app"
BIN_NAME="ClaudeUsageMenuBar"
IDENTITY_NAME="ClaudeUsageMenuBar Local Signing"

swift build -c "$CONFIG"

rm -rf "$APP_NAME"
mkdir -p "$APP_NAME/Contents/MacOS"
cp ".build/$CONFIG/$BIN_NAME" "$APP_NAME/Contents/MacOS/$BIN_NAME"
cp "Resources/Info.plist" "$APP_NAME/Contents/Info.plist"

# A certificate-backed identity keeps the designated requirement stable across
# rebuilds, so the Keychain "Always Allow" grant survives. Ad-hoc does not.
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY_NAME"; then
    codesign --force --deep --sign "$IDENTITY_NAME" "$APP_NAME"
else
    codesign --force --deep --sign - "$APP_NAME"
    echo "warning: signed ad-hoc; macOS will ask for your password again after" >&2
    echo "         every code change. Run ./Scripts/create-signing-identity.sh once." >&2
fi

echo "Built $APP_NAME"
echo "Run with: open $APP_NAME"
