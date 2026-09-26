#!/bin/sh
# Build a Developer ID signed, notarized and stapled DMG in build/release.
#
#   TEAM_ID=ABCDE12345 ./scripts/release.sh
#
# One-time setup:
#   1. Xcode > Settings > Accounts: sign in with the paid developer account.
#      The export step creates the "Developer ID Application" certificate if it is missing.
#   2. Store notarization credentials (app-specific password from account.apple.com):
#        xcrun notarytool store-credentials quota-rings --apple-id YOU@example.com --team-id ABCDE12345
#
# SKIP_NOTARIZE=1 builds and signs the DMG without submitting it to Apple.
set -eu
cd "$(dirname "$0")/.."

: "${TEAM_ID:?Set TEAM_ID to your Apple Developer Team ID}"
NOTARY_PROFILE="${NOTARY_PROFILE:-quota-rings}"
OUT=build/release
ARCHIVE="$OUT/QuotaRings.xcarchive"

rm -rf "$OUT"
mkdir -p "$OUT"
xcodegen generate --quiet

echo "==> Archive"
xcodebuild -project QuotaRings.xcodeproj -scheme QuotaRings -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
  -allowProvisioningUpdates -quiet archive

echo "==> Export with Developer ID"
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" -allowProvisioningUpdates -quiet

APP="$OUT/export/Quota Rings.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$OUT/QuotaRings-$VERSION.dmg"
codesign --verify --deep --strict "$APP"

echo "==> Package $DMG"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Quota Rings" -srcfolder "$STAGE" -ov -format UDZO "$DMG" -quiet
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "($TEAM_ID)" | awk '{print $2}' | head -1)
[ -n "$IDENTITY" ] || { echo "No Developer ID Application certificate for team $TEAM_ID" >&2; exit 1; }
codesign --sign "$IDENTITY" --timestamp "$DMG"

if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
  echo "Skipped notarization. Signed DMG: $DMG"
  exit 0
fi

echo "==> Notarize"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
echo "Release ready: $DMG"
