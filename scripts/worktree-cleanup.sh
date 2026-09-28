#!/bin/sh
set -eu

export LC_ALL=C

usage() {
  echo "usage: worktree-cleanup.sh [--dry-run] [--into <branch>] [--session <id>]" \
    "[--projects-dir <dir>] [--other-sessions <worktree>...]" >&2
  exit 2
}

die() {
  echo "worktree-cleanup: $1" >&2
  exit 2
}

dry_run=0
into=
session=${CLAUDE_CODE_SESSION_ID:-}
projects_dir=
other_names=

while [ "$#" -gt 0 ]; do
  case $1 in
  --dry-run) dry_run=1 ;;
  --into | --session | --projects-dir)
    [ "$#" -ge 2 ] || usage
    case $1 in
    --into) into=$2 ;;
    --session) session=$2 ;;
    --projects-dir) projects_dir=$2 ;;
    esac
    shift
    ;;
  --other-sessions)
    shift
    while [ "$#" -gt 0 ]; do
      case $1 in
      --*) break ;;
      esac
      other_names="$other_names$1
"
      shift
    done
    [ -n "$other_names" ] || usage
    continue
    ;;
  *) usage ;;
  esac
  shift
done

main_root=$(git worktree list --porcelain | sed -n '1s/^worktree //p')
[ -n "$main_root" ] || die "run this inside the repository"
main_branch=$(git worktree list --porcelain | awk 'NR == 1, /^$/' | sed -n 's|^branch refs/heads/||p')

if [ -z "$into" ]; then
  into=$main_branch
  [ -n "$into" ] || die "the main checkout is not on a branch, pass --into <branch>"
fi
git rev-parse --verify --quiet "refs/heads/$into" >/dev/null || die "no branch named $into"

if [ -z "$projects_dir" ]; then
  projects_dir="$HOME/.claude/projects/$(printf '%s' "$main_root" | sed 's/[^A-Za-z0-9]/-/g')"
fi
if [ -z "$session" ] && [ -z "$other_names" ]; then
  die "no session, set CLAUDE_CODE_SESSION_ID or pass --session <id>"
fi

tab=$(printf '\t')
candidates=$(mktemp "${TMPDIR:-/tmp}/worktree-cleanup.XXXXXX")
errors="$candidates.errors"
trap 'rm -f "$candidates" "$errors"' EXIT
reported=0

record_of() {
  record_path=$(plutil -extract worktreePath raw -o - "$1" 2>/dev/null) || return 0
  record_branch=$(plutil -extract worktreeBranch raw -o - "$1" 2>/dev/null) || record_branch=
  if [ -d "$record_path" ]; then
    record_path=$(cd "$record_path" && pwd -P)
  fi
  printf '%s\t%s\n' "$record_path" "$record_branch"
}

if [ -n "$session" ]; then
  for meta in "$projects_dir/$session"/subagents/*.meta.json; do
    [ -f "$meta" ] || continue
    record_of "$meta" >>"$candidates"
  done
fi

while IFS= read -r name; do
  [ -n "$name" ] || continue
  found=0
  for meta in "$projects_dir"/*/subagents/*.meta.json; do
    [ -f "$meta" ] || continue
    if [ -n "$session" ]; then
      case $meta in
      "$projects_dir/$session/"*) continue ;;
      esac
    fi
    line=$(record_of "$meta")
    path=${line%%"$tab"*}
    if [ -n "$line" ] && { [ "$path" = "$name" ] || [ "${path##*/}" = "$name" ]; }; then
      printf '%s\n' "$line" >>"$candidates"
      found=1
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "kept $name: no builder of another session recorded a worktree by that name"
    reported=$((reported + 1))
  fi
done <<EOF
$other_names
EOF

worktree_entry() {
  git worktree list --porcelain |
    WORKTREE="$1" awk 'BEGIN { RS = ""; FS = "\n" } $1 == ("worktree " ENVIRON["WORKTREE"]) { print; exit }'
}

commits() {
  if [ "$1" -eq 1 ]; then echo "1 commit"; else echo "$1 commits"; fi
}

unlanded_count() {
  cherry=$(git cherry "$into" "$1" 2>/dev/null) || return 1
  printf '%s\n' "$cherry" | grep -c '^+' || true
}

add_reason() {
  reasons="${reasons:+$reasons; }$1"
}

branch_outcome() {
  git show-ref --verify --quiet "refs/heads/$1" || return 0
  if [ "$1" = "$into" ] || [ "$1" = "$main_branch" ]; then
    echo "kept branch $1: it is the target branch"
  elif [ -n "$(git config --get "branch.$1.remote" || true)" ]; then
    echo "kept branch $1: tracks an upstream"
  elif ! count=$(unlanded_count "$1"); then
    echo "kept branch $1: cannot compare it with $into"
  elif [ "$count" -gt 0 ]; then
    echo "kept branch $1: $(commits "$count") not on $into"
  elif [ "$dry_run" -eq 1 ]; then
    echo "would delete branch $1"
  elif git branch -D "$1" >/dev/null 2>"$errors"; then
    echo "deleted branch $1"
  else
    echo "kept branch $1: $(head -n 1 "$errors")"
  fi
}

clean_up() {
  path=$1
  recorded_branch=$2
  [ "$path" != "$main_root" ] || return 0
  entry=$(worktree_entry "$path")
  [ -n "$entry" ] || return 0

  reasons=
  if printf '%s\n' "$entry" | grep -q '^locked'; then
    lock_reason=$(printf '%s\n' "$entry" | sed -n 's/^locked //p')
    add_reason "locked${lock_reason:+ ($lock_reason)}"
  fi
  if printf '%s\n' "$entry" | grep -q '^prunable'; then
    add_reason "its directory is missing"
  elif ! status=$(git -C "$path" --no-optional-locks status --porcelain 2>/dev/null); then
    add_reason "git status failed"
  elif [ -n "$status" ]; then
    add_reason "uncommitted changes"
  fi
  head_commit=$(printf '%s\n' "$entry" | sed -n 's/^HEAD //p')
  if ! count=$(unlanded_count "$head_commit"); then
    add_reason "cannot compare it with $into"
  elif [ "$count" -gt 0 ]; then
    add_reason "$(commits "$count") not on $into"
  fi

  if [ -n "$reasons" ]; then
    echo "kept $path: $reasons"
    return 0
  fi

  current_branch=$(printf '%s\n' "$entry" | sed -n 's|^branch refs/heads/||p')
  branches=$recorded_branch
  if [ -n "$current_branch" ] && [ "$current_branch" != "$recorded_branch" ]; then
    branches="$branches $current_branch"
  fi

  if [ "$dry_run" -eq 1 ]; then
    line="would remove $path"
  elif git worktree remove "$path" 2>"$errors"; then
    line="removed $path"
  else
    echo "kept $path: $(head -n 1 "$errors")"
    return 0
  fi
  for branch in $branches; do
    outcome=$(branch_outcome "$branch")
    [ -z "$outcome" ] || line="$line, $outcome"
  done
  echo "$line"
}

unique=$(awk -F "$tab" '!seen[$1]++' "$candidates")
while IFS="$tab" read -r path branch; do
  [ -n "$path" ] || continue
  outcome=$(clean_up "$path" "$branch")
  [ -n "$outcome" ] || continue
  echo "$outcome"
  reported=$((reported + 1))
done <<EOF
$unique
EOF

if [ "$reported" -eq 0 ]; then
  echo "worktree-cleanup: nothing to clean"
fi
