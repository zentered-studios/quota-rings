#!/bin/sh
# Build Release, copy the app to ~/Applications and launch it.
set -eu
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage -configuration Release \
  -derivedDataPath build/DerivedData -quiet build
APP="build/DerivedData/Build/Products/Release/Claude Usage.app"
DEST="$HOME/Applications/Claude Usage.app"
mkdir -p "$HOME/Applications"
pkill -x "Claude Usage" 2>/dev/null || true
rm -rf "$DEST"
cp -R "$APP" "$DEST"
open "$DEST"
echo "Installed $DEST"
