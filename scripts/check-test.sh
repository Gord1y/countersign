#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
scripts/run-quietly.sh test swift test
