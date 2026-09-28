#!/bin/sh
set -eu

scripts=$(cd "$(dirname "$0")" && pwd)
script="$scripts/release-index.swift"
work=$(mktemp -d "${TMPDIR:-/tmp}/test-release-index.XXXXXX")
trap 'rm -rf "$work"' EXIT
failures=0

fail() {
  echo "test-release-index: $1" >&2
  failures=$((failures + 1))
}

run() {
  swift "$script" "$@"
}

assert_ok() {
  if ! run --dir "$1" >"$work/out" 2>"$work/err"; then
    fail "$2: expected success: $(cat "$work/err")"
    return
  fi
  if ! grep -qF "release-index: ok" "$work/out"; then
    fail "$2: missing success message: $(cat "$work/out")"
  fi
}

assert_fails() {
  dir=$1
  substring=$2
  name=$3
  if run --dir "$dir" >"$work/out" 2>"$work/err"; then
    fail "$name: expected failure"
    return
  fi
  if ! grep -qF -- "$substring" "$work/err"; then
    fail "$name: did not report '$substring': $(cat "$work/err")"
  fi
  if [ -e "$dir/index.json" ]; then
    fail "$name: wrote index.json despite errors"
  fi
}

case_dir() {
  d=$(printf '%s' "$work/$1" | sed 's#//*#/#g')
  mkdir -p "$d"
  echo "$d"
}

valid=$(case_dir valid)
cat >"$valid/release-0.10.0.md" <<'NOTE'
---
version: 0.10.0
date: 2026-01-15
title: "Faster approvals"
summary: 'Approvals now render in half the time.'
type: minor
breaking: false
highlights:
  - Panel opens faster
  - New hover cards
tags:
  - perf
testedWith:
  claudeCode: 1.2.3
  codex: 4.5.6
---

## Added
- Hover cards.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.

## Upgrading
- Re-run setup.

## Notes
- Nothing special.
NOTE
cat >"$valid/release-0.9.1.md" <<'NOTE'
---
version: 0.9.1
date: 2026-01-01
title: Patch release
summary: A small fix.
type: patch
breaking: false
highlights:
  - Fixed a crash
tags:
testedWith:
  claudeCode: 1.2.0
  codex: 4.5.0
---

## Added
- None.

## Changed
- None.

## Fixed
- Crash on launch.

## Removed
- None.

## Security
- None.
NOTE
cat >"$valid/release-0.9.0.md" <<'NOTE'
---
version: 0.9.0
date: 2025-12-01
title: Initial release
summary: First public release.
type: major
breaking: true
highlights:
  - First release
tags:
  - launch
testedWith:
  claudeCode: 1.1.0
  codex: 4.4.0
---

## Added
- Everything.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE

assert_ok "$valid" "valid notes"

cat >"$work/expected-index.json" <<NOTE
{
  "schemaVersion": 1,
  "releases": [
    {
      "version": "0.10.0",
      "date": "2026-01-15",
      "title": "Faster approvals",
      "summary": "Approvals now render in half the time.",
      "type": "minor",
      "breaking": false,
      "highlights": [
        "Panel opens faster",
        "New hover cards"
      ],
      "tags": [
        "perf"
      ],
      "testedWith": {
        "claudeCode": "1.2.3",
        "codex": "4.5.6"
      },
      "notes": "$valid/release-0.10.0.md"
    },
    {
      "version": "0.9.1",
      "date": "2026-01-01",
      "title": "Patch release",
      "summary": "A small fix.",
      "type": "patch",
      "breaking": false,
      "highlights": [
        "Fixed a crash"
      ],
      "tags": [],
      "testedWith": {
        "claudeCode": "1.2.0",
        "codex": "4.5.0"
      },
      "notes": "$valid/release-0.9.1.md"
    },
    {
      "version": "0.9.0",
      "date": "2025-12-01",
      "title": "Initial release",
      "summary": "First public release.",
      "type": "major",
      "breaking": true,
      "highlights": [
        "First release"
      ],
      "tags": [
        "launch"
      ],
      "testedWith": {
        "claudeCode": "1.1.0",
        "codex": "4.4.0"
      },
      "notes": "$valid/release-0.9.0.md"
    }
  ]
}
NOTE

if ! diff -u "$work/expected-index.json" "$valid/index.json" >"$work/diff"; then
  fail "valid notes: index.json did not match expected output: $(cat "$work/diff")"
fi

if ! run --check --dir "$valid" >"$work/out" 2>"$work/err"; then
  fail "up-to-date index: expected --check to pass: $(cat "$work/err")"
fi

echo "extra line" >>"$valid/release-0.10.0.md"
sed -i.bak 's/type: minor/type: patch/' "$valid/release-0.10.0.md"
rm -f "$valid/release-0.10.0.md.bak"
if run --check --dir "$valid" >"$work/out" 2>"$work/err"; then
  fail "stale index: expected --check to fail"
elif ! grep -qF "index.json is stale" "$work/err"; then
  fail "stale index: did not report staleness: $(cat "$work/err")"
fi

empty=$(case_dir empty)
assert_ok "$empty" "empty directory"
if ! diff -u - "$empty/index.json" <<'NOTE'
{
  "schemaVersion": 1,
  "releases": []
}
NOTE
then
  fail "empty directory: index.json did not match the empty index"
fi

d=$(case_dir version-mismatch)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.1
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_fails "$d" "does not match filename" "version mismatch"

d=$(case_dir version-not-semver)
cat >"$d/release-abc.md" <<'NOTE'
---
version: abc
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_fails "$d" "is not semver x.y.z" "version not semver"

d=$(case_dir bad-date)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-13-40
title: t
summary: s
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_fails "$d" "must be a valid YYYY-MM-DD date" "invalid date"

d=$(case_dir long-title)
long_title=$(printf 'x%.0s' $(seq 1 91))
cat >"$d/release-1.0.0.md" <<NOTE
---
version: 1.0.0
date: 2026-01-01
title: $long_title
summary: s
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_fails "$d" "more than 90" "title too long"

d=$(case_dir long-summary)
long_summary=$(printf 'x%.0s' $(seq 1 401))
cat >"$d/release-1.0.0.md" <<NOTE
---
version: 1.0.0
date: 2026-01-01
title: t
summary: $long_summary
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_fails "$d" "more than 400" "summary too long"

d=$(case_dir bad-type)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: massive
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_fails "$d" "must be one of major, minor, patch" "invalid type"

d=$(case_dir bad-breaking)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: yes
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_fails "$d" "must be true or false" "invalid breaking"

d=$(case_dir too-many-highlights)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
  - b
  - c
  - d
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_fails "$d" "between 1 and 3 items" "too many highlights"

d=$(case_dir too-many-tags)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
tags:
  - a
  - b
  - c
  - d
  - e
  - f
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_fails "$d" "at most 5 items" "too many tags"

d=$(case_dir missing-codex)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_fails "$d" "missing 'codex'" "testedWith missing codex"

d=$(case_dir with-cursor)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
  cursor: 3.21.18
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_ok "$d" "testedWith with cursor"
if ! grep -qF '"cursor": "3.21.18"' "$d/index.json"; then
  fail "testedWith with cursor: index.json missing cursor"
fi

d=$(case_dir without-cursor)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_ok "$d" "testedWith without cursor"
if grep -qF '"cursor"' "$d/index.json"; then
  fail "testedWith without cursor: index.json unexpectedly has cursor"
fi

d=$(case_dir malformed-codex)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: "1.0.0
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_fails "$d" "unsupported value syntax for 'codex'" "testedWith malformed codex"

d=$(case_dir malformed-cursor)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
  cursor: "3.21.18
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_fails "$d" "unsupported value syntax for 'cursor'" "testedWith malformed cursor"

d=$(case_dir with-antigravity)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
  antigravity: 1.2.12
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_ok "$d" "testedWith with antigravity"
expected='      "testedWith": {
        "claudeCode": "1.0.0",
        "codex": "1.0.0",
        "antigravity": "1.2.12"
      },'
actual=$(sed -n '/"testedWith"/,/^      },$/p' "$d/index.json")
if [ "$actual" != "$expected" ]; then
  fail "testedWith with antigravity: unexpected testedWith block: $actual"
fi

d=$(case_dir with-cursor-and-antigravity)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  antigravity: 1.2.12
  cursor: 3.21.18
  claudeCode: 1.0.0
  codex: 1.0.0
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_ok "$d" "testedWith with cursor and antigravity"
expected='      "testedWith": {
        "claudeCode": "1.0.0",
        "codex": "1.0.0",
        "cursor": "3.21.18",
        "antigravity": "1.2.12"
      },'
actual=$(sed -n '/"testedWith"/,/^      },$/p' "$d/index.json")
if [ "$actual" != "$expected" ]; then
  fail "testedWith with cursor and antigravity: unexpected testedWith block: $actual"
fi

d=$(case_dir without-antigravity)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_ok "$d" "testedWith without antigravity"
expected='      "testedWith": {
        "claudeCode": "1.0.0",
        "codex": "1.0.0"
      },'
actual=$(sed -n '/"testedWith"/,/^      },$/p' "$d/index.json")
if [ "$actual" != "$expected" ]; then
  fail "testedWith without antigravity: unexpected testedWith block: $actual"
fi

d=$(case_dir malformed-antigravity)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
  antigravity: '1.2.12
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_fails "$d" "unsupported value syntax for 'antigravity'" "testedWith malformed antigravity"

d=$(case_dir unknown-tested-with)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
  gemini: 0.61.0
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_fails "$d" "unknown field 'testedWith.gemini'" "testedWith unknown host"

d=$(case_dir unknown-field)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
extra: nope
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_fails "$d" "unknown field 'extra'" "unknown field"

d=$(case_dir duplicate-field)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_fails "$d" "duplicate field 'version'" "duplicate field"

d=$(case_dir missing-opening)
cat >"$d/release-1.0.0.md" <<'NOTE'
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_fails "$d" "missing frontmatter opening" "missing opening delimiter"

d=$(case_dir missing-closing)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0

## Added
- None.
NOTE
assert_fails "$d" "missing frontmatter closing" "missing closing delimiter"

d=$(case_dir bad-indentation)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
    - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_fails "$d" "unexpected indentation" "bad indentation"

d=$(case_dir mixed-list-map)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
  key: value
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_fails "$d" "mixes a list and a map" "mixed list and map"

d=$(case_dir wrong-section-order)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
---

## Changed
- None.

## Added
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_fails "$d" "expected section '## Added' but found '## Changed'" "wrong section order"

d=$(case_dir missing-section)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
---

## Added
- None.

## Changed
- None.

## Fixed
- None.
NOTE
assert_fails "$d" "missing section '## Removed'" "missing section"

d=$(case_dir empty-section)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
---

## Added
- None.

## Changed

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_fails "$d" "must not be empty; use '- None.'" "empty section"

d=$(case_dir extra-section)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
---

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.

## Extra
- oops
NOTE
assert_fails "$d" "sections after '## Security' must be only" "extra section"

d=$(case_dir preamble)
cat >"$d/release-1.0.0.md" <<'NOTE'
---
version: 1.0.0
date: 2026-01-01
title: t
summary: s
type: major
breaking: false
highlights:
  - a
tags:
testedWith:
  claudeCode: 1.0.0
  codex: 1.0.0
---
Stray text.

## Added
- None.

## Changed
- None.

## Fixed
- None.

## Removed
- None.

## Security
- None.
NOTE
assert_fails "$d" "unexpected content before the first" "stray content before sections"

if run --dir >"$work/out" 2>"$work/err"; then
  fail "missing --dir value: expected failure"
elif ! grep -qF "requires a value" "$work/err"; then
  fail "missing --dir value: did not report the error: $(cat "$work/err")"
fi

if run --dir "$empty" --bogus >"$work/out" 2>"$work/err"; then
  fail "unknown argument: expected failure"
elif ! grep -qF "unknown argument" "$work/err"; then
  fail "unknown argument: did not report the error: $(cat "$work/err")"
fi

if [ "$failures" -ne 0 ]; then
  echo "test-release-index: $failures failed" >&2
  exit 1
fi
echo "test-release-index: ok"
