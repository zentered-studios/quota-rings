#!/bin/sh
# Render 2880x1800 marketing screenshots into docs/screenshots.
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
swiftc Sources/Shared/*.swift Sources/Widget/WidgetViews.swift Tools/Screenshots/main.swift -o build/render-screenshots
./build/render-screenshots docs/screenshots
