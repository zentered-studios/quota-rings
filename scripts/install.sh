#!/bin/sh
# Build Release, copy the app to ~/Applications and launch it.
set -eu
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project QuotaRings.xcodeproj -scheme QuotaRings -configuration Release \
  -derivedDataPath build/DerivedData -quiet build
APP="build/DerivedData/Build/Products/Release/Quota Rings.app"
DEST="$HOME/Applications/Quota Rings.app"
mkdir -p "$HOME/Applications"
pkill -x "Quota Rings" 2>/dev/null || true
rm -rf "$DEST"
cp -R "$APP" "$DEST"
open "$DEST"
echo "Installed $DEST"
