#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
scripts/test-commit-msg.sh
scripts/test-worktree-cleanup.sh
scripts/test-release-index.sh
scripts/test-install.sh
scripts/test-run-quietly.sh
