#!/bin/sh
# Render the app icon into the asset catalog.
set -eu
cd "$(dirname "$0")/.."
mkdir -p build Sources/App/Assets.xcassets
[ -f Sources/App/Assets.xcassets/Contents.json ] || \
  printf '{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n' > Sources/App/Assets.xcassets/Contents.json
swiftc Sources/Shared/*.swift Sources/Widget/WidgetViews.swift Tools/Icon/main.swift -o build/render-icon
./build/render-icon Sources/App/Assets.xcassets/AppIcon.appiconset
