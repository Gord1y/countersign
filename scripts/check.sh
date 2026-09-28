#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
scripts/check-build.sh
scripts/check-test.sh
scripts/check-lint.sh
scripts/check-scripts.sh
swift scripts/release-index.swift --check
echo "check: ok"
