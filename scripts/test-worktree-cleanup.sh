#!/bin/sh
set -eu

scripts=$(cd "$(dirname "$0")" && pwd)
cleanup="$scripts/worktree-cleanup.sh"
work=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-worktree-cleanup.XXXXXX")" && pwd -P)
trap 'rm -rf "$work"' EXIT
failures=0

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE CLAUDE_CODE_SESSION_ID
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com

repo="$work/repo"
trees="$work/worktrees"
projects="$work/projects"

fail() {
  echo "test-worktree-cleanup: $1" >&2
  failures=$((failures + 1))
}

in_repo() {
  git -C "$repo" "$@"
}

commit_in() {
  printf '%s\n' "$2" >>"$1/notes.txt"
  git -C "$1" add notes.txt
  git -C "$1" commit -q --no-verify -m "$2"
  git -C "$1" rev-parse HEAD
}

builder() {
  in_repo worktree add -q -b "worktree-$2" "$trees/$2" main
  mkdir -p "$projects/$1/subagents"
  printf '{"agentType":"general-purpose","worktreePath":"%s","worktreeBranch":"%s","spawnDepth":1}' \
    "$trees/$2" "worktree-$2" >"$projects/$1/subagents/agent-$2.meta.json"
}

run_cleanup() {
  (cd "$repo" && "$cleanup" --session this-session --projects-dir "$projects" "$@") >"$work/out" 2>&1 ||
    fail "worktree-cleanup $* exited non-zero: $(cat "$work/out")"
}

expect_line() {
  grep -qxF -- "$1" "$work/out" || fail "missing line '$1' in: $(cat "$work/out")"
}

expect_no_mention() {
  if grep -qF -- "$1" "$work/out"; then
    fail "unexpected mention of $1 in: $(cat "$work/out")"
  fi
}

expect_worktree() {
  in_repo worktree list --porcelain | grep -qxF "worktree $1" || fail "worktree $1 is gone"
}

expect_no_worktree() {
  if in_repo worktree list --porcelain | grep -qxF "worktree $1"; then
    fail "worktree $1 is still there"
  fi
}

expect_branch() {
  in_repo show-ref --verify --quiet "refs/heads/$1" || fail "branch $1 is gone"
}

expect_no_branch() {
  if in_repo show-ref --verify --quiet "refs/heads/$1"; then
    fail "branch $1 is still there"
  fi
}

snapshot_state() {
  {
    in_repo worktree list --porcelain
    in_repo for-each-ref --format='%(refname) %(objectname)'
    ls "$trees"
  } >"$1"
}

git init -q -b main "$repo"
commit_in "$repo" "start" >/dev/null

builder this-session landed
in_repo cherry-pick "$(commit_in "$trees/landed" "landed change")" >/dev/null

builder this-session dirty
printf 'edit\n' >>"$trees/dirty/notes.txt"

builder this-session locked
sh -c 'exit 0' &
dead_pid=$!
wait "$dead_pid" || true
in_repo worktree lock --reason "claude agent agent-locked (pid $dead_pid)" "$trees/locked"

builder this-session unlanded
commit_in "$trees/unlanded" "unlanded change" >/dev/null

builder this-session tracked
in_repo branch -q --set-upstream-to=main worktree-tracked

builder this-session switched
commit_in "$trees/switched" "abandoned change" >/dev/null
git -C "$trees/switched" switch -q -c side-switched main

builder other-session foreign
in_repo cherry-pick "$(commit_in "$trees/foreign" "foreign change")" >/dev/null

in_repo worktree add -q -b handmade "$trees/handmade" main

mkdir -p "$projects/this-session/subagents"
printf '{"agentType":"Explore","spawnDepth":1}' >"$projects/this-session/subagents/agent-plain.meta.json"
printf '{"worktreePath":"%s","worktreeBranch":"worktree-gone"}' "$trees/gone" \
  >"$projects/this-session/subagents/agent-gone.meta.json"

snapshot_state "$work/before"
run_cleanup --dry-run
snapshot_state "$work/after"
diff "$work/before" "$work/after" >/dev/null || fail "--dry-run changed the repository"
expect_line "would remove $trees/landed, would delete branch worktree-landed"
expect_line "kept $trees/dirty: uncommitted changes"
expect_line "kept $trees/locked: locked (claude agent agent-locked (pid $dead_pid))"
expect_line "kept $trees/unlanded: 1 commit not on main"

run_cleanup
expect_line "removed $trees/landed, deleted branch worktree-landed"
expect_no_worktree "$trees/landed"
expect_no_branch worktree-landed

expect_line "kept $trees/dirty: uncommitted changes"
expect_worktree "$trees/dirty"
expect_branch worktree-dirty

expect_line "kept $trees/locked: locked (claude agent agent-locked (pid $dead_pid))"
expect_worktree "$trees/locked"

expect_line "kept $trees/unlanded: 1 commit not on main"
expect_worktree "$trees/unlanded"
expect_branch worktree-unlanded

expect_line "removed $trees/tracked, kept branch worktree-tracked: tracks an upstream"
expect_branch worktree-tracked

expect_line "removed $trees/switched, kept branch worktree-switched: 1 commit not on main, deleted branch side-switched"
expect_branch worktree-switched
expect_no_branch side-switched

expect_no_mention handmade
expect_worktree "$trees/handmade"
expect_no_mention foreign
expect_worktree "$trees/foreign"
expect_no_mention gone
[ "$(wc -l <"$work/out" | tr -d ' ')" -eq 6 ] || fail "expected six lines: $(cat "$work/out")"

run_cleanup --other-sessions foreign handmade
expect_line "removed $trees/foreign, deleted branch worktree-foreign"
expect_no_worktree "$trees/foreign"
expect_line "kept handmade: no builder of another session recorded a worktree by that name"
expect_worktree "$trees/handmade"

run_cleanup --session empty-session
expect_line "worktree-cleanup: nothing to clean"

if [ "$failures" -ne 0 ]; then
  echo "test-worktree-cleanup: $failures failed" >&2
  exit 1
fi
echo "test-worktree-cleanup: ok"
