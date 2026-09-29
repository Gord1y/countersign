#!/bin/sh
set -eu

if [ $# -lt 2 ]; then
  echo "usage: scripts/run-quietly.sh <label> <command> [argument...]" >&2
  exit 2
fi

label=$1
shift

if [ -n "${CI:-}" ] || [ "${CHECK_VERBOSE:-}" = 1 ]; then
  exec "$@"
fi

log=$(mktemp "${TMPDIR:-/tmp}/countersign-$label.XXXXXX")
if "$@" >"$log" 2>&1; then
  summary=$(grep -E 'Build complete!|Test run with [0-9]+ tests? .*passed' "$log" | tail -1 || true)
  echo "$label: ${summary:-ok}"
  rm -f "$log"
  exit 0
else
  status=$?
fi

echo "$label: failed with exit status $status"
problems=$(grep -E 'error:|warning:|✘' "$log" | head -40 || true)
if [ -n "$problems" ]; then
  echo "$problems"
else
  tail -30 "$log"
fi
echo "$label: full log at $log"
exit "$status"
