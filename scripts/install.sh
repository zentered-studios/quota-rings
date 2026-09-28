#!/bin/sh
# Build Release, copy the app to /Applications and launch it.
set -eu
cd "$(dirname "$0")/.."
xcodegen generate --quiet
# macOS registers widgets from any app bundle it finds, including build products.
# Clear old products so a renamed app cannot leave a stale widget behind.
rm -rf build/DerivedData/Build/Products
xcodebuild -project QuotaRings.xcodeproj -scheme QuotaRings -configuration Release \
  -derivedDataPath build/DerivedData -quiet build
APP="build/DerivedData/Build/Products/Release/Quota Rings.app"
DEST="/Applications/Quota Rings.app"
pkill -x "Quota Rings" 2>/dev/null || true
# A widget process keeps running the old build until it exits, even after the app is replaced.
pkill -x QuotaRingsWidget 2>/dev/null || true
# Earlier versions installed to ~/Applications. A second copy registers a second widget.
rm -rf "$HOME/Applications/Quota Rings.app"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
open "$DEST"
echo "Installed $DEST"
