#!/bin/bash
# Builds and installs the app to /Applications, which is where the login item
# points. Running a build straight out of the source directory instead leaves
# two bundles with the same identifier but different code identities, and the
# Keychain grants them separately — so each one prompts on its own.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_NAME="ClaudeUsageMenuBar.app"
DESTINATION="/Applications/$APP_NAME"

./Scripts/build-app.sh "$CONFIG"

pkill -f "$APP_NAME/Contents/MacOS" || true
rm -rf "$DESTINATION"
cp -R "$APP_NAME" "$DESTINATION"
open "$DESTINATION"

echo "Installed to $DESTINATION and launched."
