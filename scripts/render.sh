#!/bin/sh
# Render the widget views to PNGs in build/render for a visual check.
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
swiftc Sources/Shared/*.swift Sources/Widget/WidgetViews.swift Tests/Render/main.swift -o build/render-widget
./build/render-widget build/render
