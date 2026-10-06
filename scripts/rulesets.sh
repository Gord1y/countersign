#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

repository=Gord1y/countersign
directory=.github/rulesets
fields='{bypass_actors, conditions, enforcement, name, rules, target}'

usage() {
  echo "usage: scripts/rulesets.sh --check | --apply" >&2
  exit 2
}

ruleset_id() {
  gh api "repos/$repository/rulesets" --jq ".[] | select(.name == \"$1\") | .id"
}

check() {
  scratch=$(mktemp -d "${TMPDIR:-/tmp}/countersign-rulesets.XXXXXX")
  trap 'rm -rf "$scratch"' EXIT
  status=0
  gh api "repos/$repository/rulesets" --jq '.[].name' >"$scratch/live-names"
  : >"$scratch/file-names"
  for file in "$directory"/*.json; do
    name=$(jq -r .name "$file")
    echo "$name" >>"$scratch/file-names"
    id=$(ruleset_id "$name")
    if [ -z "$id" ]; then
      echo "rulesets: \"$name\" from $file is not on GitHub"
      status=1
      continue
    fi
    gh api "repos/$repository/rulesets/$id" --jq "$fields" >"$scratch/live.json"
    filter=.
    if [ "$(jq '.bypass_actors == null' "$scratch/live.json")" = true ]; then
      filter='del(.bypass_actors)'
    fi
    jq -S "$filter" "$file" >"$scratch/want.json"
    jq -S "$filter" "$scratch/live.json" >"$scratch/have.json"
    if ! diff -u "$scratch/want.json" "$scratch/have.json" >"$scratch/diff"; then
      echo "rulesets: \"$name\" on GitHub differs from $file (- file, + GitHub):"
      cat "$scratch/diff"
      status=1
    fi
  done
  while IFS= read -r name; do
    if ! grep -Fxq "$name" "$scratch/file-names"; then
      echo "rulesets: \"$name\" is on GitHub but not in $directory"
      status=1
    fi
  done <"$scratch/live-names"
  if [ "$status" -eq 0 ]; then
    echo "rulesets: ok"
  fi
  return "$status"
}

apply() {
  for file in "$directory"/*.json; do
    name=$(jq -r .name "$file")
    id=$(ruleset_id "$name")
    if [ -n "$id" ]; then
      gh api -X PUT "repos/$repository/rulesets/$id" --input "$file" --jq .name >/dev/null
      echo "rulesets: updated \"$name\""
    else
      gh api -X POST "repos/$repository/rulesets" --input "$file" --jq .name >/dev/null
      echo "rulesets: created \"$name\""
    fi
  done
  check
}

[ $# -eq 1 ] || usage
case "$1" in
  --check) check ;;
  --apply) apply ;;
  *) usage ;;
esac
