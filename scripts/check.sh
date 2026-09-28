#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
scripts/check-build.sh
scripts/check-lint.sh
scripts/check-scripts.sh
echo "check: ok"
