#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

fail() {
  echo "test-rulesets: $1" >&2
  exit 1
}

stub=$(mktemp -d "${TMPDIR:-/tmp}/countersign-test-rulesets.XXXXXX")
trap 'rm -rf "$stub"' EXIT
mkdir "$stub/bin" "$stub/api"

cat >"$stub/bin/gh" <<'EOF'
#!/bin/sh
set -eu
[ "$1" = api ] || exit 9
shift
method=GET
filter=.
input=
path=
while [ $# -gt 0 ]; do
  case "$1" in
    -X) method=$2; shift 2 ;;
    --jq) filter=$2; shift 2 ;;
    --input) input=$2; shift 2 ;;
    *) path=$1; shift ;;
  esac
done
echo "$method $path" >>"$STUB/calls"
case "$method" in
  GET)
    jq -r "$filter" "$STUB/api/$(basename "$path").json"
    ;;
  PUT)
    id=$(basename "$path")
    jq --argjson id "$id" '. + {id: $id}' "$input" >"$STUB/api/$id.json"
    jq -r "$filter" "$input"
    ;;
  POST)
    jq '. + {id: 99}' "$input" >"$STUB/api/99.json"
    jq --arg name "$(jq -r .name "$input")" '. + [{id: 99, name: $name}]' \
      "$STUB/api/rulesets.json" >"$STUB/list"
    mv "$STUB/list" "$STUB/api/rulesets.json"
    jq -r "$filter" "$input"
    ;;
esac
EOF
chmod +x "$stub/bin/gh"

serve() {
  : >"$stub/calls"
  rm -f "$stub/api"/*.json
  echo '[]' >"$stub/api/rulesets.json"
  id=10
  for file in .github/rulesets/*.json; do
    id=$((id + 1))
    jq --argjson id "$id" '. + {id: $id, source: "Gord1y/countersign"}' "$file" >"$stub/api/$id.json"
    jq --argjson id "$id" --arg name "$(jq -r .name "$file")" '. + [{id: $id, name: $name}]' \
      "$stub/api/rulesets.json" >"$stub/list"
    mv "$stub/list" "$stub/api/rulesets.json"
  done
}

edit() {
  jq "$2" "$stub/api/$1.json" >"$stub/edited"
  mv "$stub/edited" "$stub/api/$1.json"
}

unlist() {
  jq --arg name "$1" 'map(select(.name != $name))' "$stub/api/rulesets.json" >"$stub/list"
  mv "$stub/list" "$stub/api/rulesets.json"
}

run() {
  PATH="$stub/bin:$PATH" STUB="$stub" sh scripts/rulesets.sh "$@"
}

set -- .github/rulesets/*.json
[ $# -eq 3 ] || fail "expected three committed rulesets, found $#"
[ "$(jq -r .name .github/rulesets/staging.json)" = staging ] || fail "staging.json is not the staging ruleset"

serve
out=$(run --check) || fail "matching rulesets failed the check: $out"
[ "$out" = "rulesets: ok" ] || fail "a passing check did not print only ok: $out"
for id in 11 12 13; do
  grep -qx "GET repos/Gord1y/countersign/rulesets/$id" "$stub/calls" || fail "the check never read ruleset $id"
done

serve
edit 13 '(.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count) = 1'
status=0
out=$(run --check) || status=$?
[ "$status" -eq 1 ] || fail "a drifted ruleset passed the check"
echo "$out" | grep -q '"staging" on GitHub differs' || fail "a drift did not name its ruleset: $out"
echo "$out" | grep -q '^+.*"required_approving_review_count": 1' || fail "a drift did not show the GitHub value: $out"

serve
for id in 11 12 13; do edit "$id" '.bypass_actors = null'; done
out=$(run --check) || fail "bypass actors the token cannot see failed the check: $out"

serve
edit 11 '.bypass_actors = [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}]'
status=0
out=$(run --check) || status=$?
[ "$status" -eq 1 ] || fail "a bypass actor added on GitHub passed the check"
echo "$out" | grep -q '"main" on GitHub differs' || fail "a new bypass actor did not name main: $out"

serve
jq '. + [{id: 20, name: "extra"}]' "$stub/api/rulesets.json" >"$stub/list"
mv "$stub/list" "$stub/api/rulesets.json"
status=0
out=$(run --check) || status=$?
[ "$status" -eq 1 ] || fail "a ruleset only on GitHub passed the check"
echo "$out" | grep -q '"extra" is on GitHub but not in .github/rulesets' || fail "an extra ruleset was not named: $out"

serve
unlist "release tags"
status=0
out=$(run --check) || status=$?
[ "$status" -eq 1 ] || fail "a ruleset missing on GitHub passed the check"
echo "$out" | grep -q '"release tags" from .github/rulesets/release-tags.json is not on GitHub' ||
  fail "a missing ruleset was not named: $out"

serve
edit 13 '(.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count) = 1'
out=$(run --apply) || fail "applying over a drift did not end in a passing check: $out"
grep -qx "PUT repos/Gord1y/countersign/rulesets/13" "$stub/calls" || fail "apply did not update staging"
echo "$out" | grep -qx 'rulesets: updated "staging"' || fail "apply did not report the update: $out"
echo "$out" | tail -n 1 | grep -qx 'rulesets: ok' || fail "apply did not end with a passing check: $out"

serve
unlist staging
out=$(run --apply) || fail "applying a missing ruleset did not end in a passing check: $out"
grep -qx "POST repos/Gord1y/countersign/rulesets" "$stub/calls" || fail "apply did not create staging"
echo "$out" | grep -qx 'rulesets: created "staging"' || fail "apply did not report the creation: $out"

expect_usage() {
  status=0
  run "$@" 2>/dev/null || status=$?
  [ "$status" -eq 2 ] || fail "\"$*\" did not exit with usage status 2"
}
expect_usage
expect_usage --nope
expect_usage --check --apply

echo "test-rulesets: ok"
