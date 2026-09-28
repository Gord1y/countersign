#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build --build-tests
swift test --skip-build
