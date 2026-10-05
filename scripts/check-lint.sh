#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
scripts/run-quietly.sh lint swift format lint --strict --recursive Package.swift Sources Tests
if grep -rnE --include='*.swift' '(^|[[:space:]])//|/\*' Sources Tests; then
  echo "check: comments are not allowed"
  exit 1
fi
if sed 1d Package.swift | grep -nE '(^|[[:space:]])//|/\*'; then
  echo "check: comments are not allowed"
  exit 1
fi
