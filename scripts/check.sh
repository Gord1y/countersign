#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build
swift test
swift format lint --strict --recursive Package.swift Sources Tests
if grep -rnE --include='*.swift' '(^|[[:space:]])//|/\*' Sources Tests; then
  echo "check: comments are not allowed"
  exit 1
fi
if sed 1d Package.swift | grep -nE '(^|[[:space:]])//|/\*'; then
  echo "check: comments are not allowed"
  exit 1
fi
scripts/test-commit-msg.sh
scripts/test-worktree-cleanup.sh
scripts/test-release-index.sh
scripts/test-install.sh
echo "check: ok"
