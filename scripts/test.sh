#!/bin/sh
# Compile the shared sources with the test runner and execute it.
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -O Sources/Shared/*.swift Tests/main.swift -o build/usage-parser-tests
./build/usage-parser-tests
