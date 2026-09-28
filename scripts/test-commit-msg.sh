#!/bin/sh
set -eu

scripts=$(cd "$(dirname "$0")" && pwd)
hook="$scripts/git-hooks/commit-msg"
work=$(mktemp -d "${TMPDIR:-/tmp}/test-commit-msg.XXXXXX")
trap 'rm -rf "$work"' EXIT
failures=0

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com

fail() {
  echo "test-commit-msg: $1" >&2
  failures=$((failures + 1))
}

repeat() {
  printf "%$2s" '' | tr ' ' "$1"
}

accepts() {
  printf '%b' "$2" >"$work/message"
  if ! "$hook" "$work/message" 2>"$work/errors"; then
    fail "rejected $1: $(cat "$work/errors")"
  fi
}

rejects() {
  printf '%b' "$2" >"$work/message"
  if "$hook" "$work/message" 2>"$work/errors"; then
    fail "accepted $1"
  elif ! grep -qiF -- "$3" "$work/errors"; then
    fail "$1 did not report '$3': $(cat "$work/errors")"
  fi
}

accepts "a plain header" 'feat: add the thing'
accepts "a scope and a body" 'fix(panel): keep the hint inside the button\n\nThe body explains why.\n'
accepts "a breaking marker" 'feat!: drop the old flag'
accepts "a scope with path characters" 'refactor(core/queue.v2_x-y): rename the lease'
for type in build chore ci docs perf revert style test; do
  accepts "the $type type" "$type: do the thing"
done
accepts "comment lines and trailing blank lines" \
  'docs: explain the queue\n\n# Please enter the commit message.\n# Lines starting with # are ignored.\n\n\n'
accepts "leading blank lines" '\n\nchore: tidy the scripts\n'
accepts "trailing spaces on the header" 'feat: add the thing   \n'
accepts "a merge header" "Merge branch 'side' into main\n"
accepts "a revert header" 'Revert "feat: add the thing"\n\nThis reverts commit 0123456.\n'
accepts "a human co-author" 'feat: pair on it\n\nCo-Authored-By: Jane Doe <jane@gmail.com>\n'
accepts "a human whose name contains ai" 'feat: pair on it\n\nCo-Authored-By: Kai Tanaka <kai@example.com>\n'
accepts "generated with inside a sentence" 'docs: note it\n\nThe images are generated with the snapshot command.\n'
accepts "a 100 character header" "feat: $(repeat x 94)"
accepts "a 100 character header with multibyte characters" "feat: $(repeat x 93)…"
accepts "attribution below the scissors line" \
  'feat: commit verbosely\n\n# ------------------------ >8 ------------------------\n# Do not modify or remove the line above.\ndiff --git a/x b/x\n+Co-Authored-By: Claude <noreply@anthropic.com>\n+Generated with Claude Code\n'

rejects "no type" 'Add the thing' "header must be"
rejects "no colon" 'feat add the thing' "header must be"
rejects "an unknown type" 'feature: add the thing' "header must be"
rejects "an uppercase type" 'Feat: add the thing' "header must be"
rejects "an uppercase scope" 'feat(Panel): add the thing' "header must be"
rejects "an empty scope" 'feat(): add the thing' "header must be"
rejects "an empty subject" 'feat: \n' "header must be"
rejects "a missing space after the colon" 'feat:add the thing' "header must be"
rejects "a trailing period" 'feat: add the thing.' "must not end with a period"
rejects "a 101 character header" "feat: $(repeat x 95)" "header is 101 characters"
rejects "an empty message" '' "the message is empty"
rejects "a comment-only message" '# nothing here\n\n' "the message is empty"
rejects "a revert header without quotes" 'Revert the thing' "header must be"
rejects "a Claude co-author" \
  'feat: add it\n\nCo-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>\n' "co-author"
rejects "a lowercase Copilot co-author" \
  'feat: add it\n\nco-authored-by: GitHub Copilot <copilot@github.com>\n' "co-author"
rejects "a Cursor co-author" \
  'feat: add it\n\nCo-authored-by: Cursor Agent <cursoragent@cursor.com>\n' "co-author"
rejects "an anthropic address" 'feat: add it\n\nCo-Authored-By: Some Bot <noreply@anthropic.com>\n' "co-author"
for name in OpenAI ChatGPT Codex Gemini AI Anthropic; do
  rejects "a $name co-author" "feat: add it\n\nCo-Authored-By: $name <bot@example.com>\n" "co-author"
done
rejects "an indented co-author" 'feat: add it\n\n  Co-Authored-By: Claude <x@example.com>\n' "co-author"
rejects "a generated-with line" \
  'feat: add it\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n' "generated-with"
rejects "a plain generated-with line" 'feat: add it\n\nGenerated with Codex\n' "generated-with"
rejects "a merge with an AI co-author" \
  "Merge branch 'side'\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n" "co-author"

printf '%b' 'Add the thing.\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n' >"$work/message"
if "$hook" "$work/message" 2>"$work/errors"; then
  fail "accepted a message with three violations"
elif [ "$(wc -l <"$work/errors" | tr -d ' ')" -ne 3 ]; then
  fail "expected one line per violation: $(cat "$work/errors")"
fi

repo="$work/repo"
git init -q -b main "$repo"

commit() {
  git -C "$repo" commit -q --allow-empty --no-verify "$@"
}

short_head() {
  git -C "$repo" rev-parse --short HEAD
}

commit -m "chore: start"
base=$(short_head)
commit -m "feat: add a good change"
good=$(short_head)
commit -m "Add a bad header"
bad=$(short_head)
git -C "$repo" switch -q -c side
commit -m "fix: land a side change"
git -C "$repo" switch -q main
git -C "$repo" merge -q --no-ff --no-verify -m "Not a conventional merge" side
merge=$(short_head)
commit -m "feat: credit a bot" -m "Co-Authored-By: Claude <noreply@anthropic.com>"
trailer=$(short_head)

if (cd "$repo" && "$scripts/check-commits.sh" "$base" HEAD) >"$work/range" 2>&1; then
  fail "check-commits accepted a range with bad commits"
fi
grep -q "^$bad: header must be" "$work/range" || fail "check-commits missed $bad: $(cat "$work/range")"
grep -q "^$trailer: remove the AI co-author" "$work/range" ||
  fail "check-commits missed $trailer: $(cat "$work/range")"
if grep -q -e "^$merge:" -e "^$good:" "$work/range"; then
  fail "check-commits flagged a merge or a good commit: $(cat "$work/range")"
fi
if ! (cd "$repo" && "$scripts/check-commits.sh" "$base" "$good") >"$work/range" 2>&1; then
  fail "check-commits rejected a good range: $(cat "$work/range")"
fi

if [ "$failures" -ne 0 ]; then
  echo "test-commit-msg: $failures failed" >&2
  exit 1
fi
echo "test-commit-msg: ok"
