#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: check-commits.sh <base> <head>" >&2
  exit 2
fi

hook="$(cd "$(dirname "$0")" && pwd)/git-hooks/commit-msg"
message_file=$(mktemp "${TMPDIR:-/tmp}/check-commits.XXXXXX")
trap 'rm -f "$message_file"' EXIT

commits=$(git rev-list --reverse --no-merges "$1..$2")
checked=0
failed=0

for sha in $commits; do
  checked=$((checked + 1))
  git log -1 --format=%B "$sha" >"$message_file"
  if ! report=$("$hook" "$message_file" 2>&1); then
    short=$(git rev-parse --short "$sha")
    printf '%s\n' "$report" | sed "s/^commit-msg: /$short: /" >&2
    failed=$((failed + 1))
  fi
done

if [ "$failed" -ne 0 ]; then
  echo "check-commits: $failed of $checked commits failed" >&2
  exit 1
fi
echo "check-commits: $checked commits ok"
