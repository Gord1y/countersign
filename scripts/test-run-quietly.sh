#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

fail() {
  echo "test-run-quietly: $1" >&2
  exit 1
}

run() {
  env -u CI -u CHECK_VERBOSE sh scripts/run-quietly.sh "$@"
}

out=$(run demo sh -c 'echo noise; echo "Build complete! (1.00s)"')
[ "$out" = "demo: Build complete! (1.00s)" ] || fail "a passing build did not print only its summary: $out"

out=$(run demo sh -c 'echo noise; echo "✔ Test run with 12 tests in 3 suites passed after 0.5 seconds."')
[ "$out" = "demo: ✔ Test run with 12 tests in 3 suites passed after 0.5 seconds." ] || fail "a passing test run did not print only its summary: $out"

out=$(run demo sh -c 'echo noise')
[ "$out" = "demo: ok" ] || fail "a passing command without a summary did not print ok: $out"

status=0
out=$(run demo sh -c 'echo noise; echo "Sources/X.swift:3:1: error: missing"; exit 3') || status=$?
[ "$status" -eq 3 ] || fail "a failing command's exit status was not kept: $status"
echo "$out" | grep -q '^demo: failed with exit status 3$' || fail "a failure was not announced"
echo "$out" | grep -q 'error: missing' || fail "a failure did not print its error line"
echo "$out" | grep -q 'noise' && fail "a failure with error lines also printed unrelated output"
log=$(echo "$out" | sed -n 's/^demo: full log at //p')
[ -f "$log" ] || fail "a failure did not keep its log"
rm -f "$log"

status=0
out=$(run demo sh -c 'echo first; echo last; exit 1') || status=$?
echo "$out" | grep -q '^last$' || fail "a failure without error lines did not print the log's tail"
rm -f "$(echo "$out" | sed -n 's/^demo: full log at //p')"

out=$(CHECK_VERBOSE=1 sh scripts/run-quietly.sh demo sh -c 'echo noise')
[ "$out" = noise ] || fail "CHECK_VERBOSE=1 did not print the full output"

out=$(CI=true sh scripts/run-quietly.sh demo sh -c 'echo noise')
[ "$out" = noise ] || fail "CI did not print the full output"

status=0
run demo >/dev/null 2>&1 || status=$?
[ "$status" -eq 2 ] || fail "a missing command did not exit 2"

echo "test-run-quietly: ok"
