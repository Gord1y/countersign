# Tooling

This page explains the repository's own machinery: what the scripts need, the commit message hook,
the strict formatter rules, the generated release index, the CI workflows and the worktree cleanup
script. Read it when you change a script, a workflow or a gate, or when a check fails and you need
to know what it enforces and why.

## The scripts

The scripts under `scripts/` are POSIX `sh` with `set -eu`. Most need nothing beyond macOS, git
and `plutil`, so a fresh clone, a builder's worktree and a CI runner can all run them without
installing anything. `scripts/build-app.sh`, `scripts/package-release.sh` and
`scripts/screenshots/render.sh` also need the Swift toolchain, because each builds or runs Swift
code as part of its job. `scripts/test-release-index.sh` needs the Swift toolchain as well, since it
runs `scripts/release-index.swift` directly to test it.

The scripts that change this repository's own gates or a person's machine have a test script that
`scripts/check.sh` runs: `scripts/test-commit-msg.sh` covers `scripts/git-hooks/commit-msg`, the
commit message rules; `scripts/test-worktree-cleanup.sh` covers `scripts/worktree-cleanup.sh`,
which removes a builder's landed worktrees and branches; `scripts/test-release-index.sh` covers
`scripts/release-index.swift`, which regenerates `releases/index.json`; and
`scripts/test-install.sh` covers `install.sh`, the installer people run on their own machine.
`scripts/build-app.sh`, `scripts/package-release.sh` and `scripts/screenshots/render.sh` have no
test script; they are checked by running them.

`scripts/build-app.sh` builds the release binary and assembles it into `.build/Countersign.app`,
ad-hoc signed; see [design/app.md](design/app.md) for the bundle layout and why. It copies the
committed `scripts/app/AppIcon.icns` into the bundle as it is, since no script generates the icon;
see [design/icon.md](design/icon.md). `scripts/package-release.sh` builds on it to produce a
downloadable release; see [release.md](release.md).

## Commit messages

`scripts/git-hooks/commit-msg` is the one rule set. Locally git runs it as a hook; in CI,
`scripts/check-commits.sh <base> <head>` runs the same file over every non-merge commit in
`base..head` and prefixes each violation with the commit's short SHA. There is no second copy of the
rules to drift.

Turn the hook on once per clone:

```sh
git config core.hooksPath scripts/git-hooks
```

The setting lives in the repository's shared config, so every worktree made from this clone uses
it. `scripts/git-hooks` is a relative path, and git resolves a relative `core.hooksPath` against
the root of whichever worktree is committing, so with this command each worktree runs its own
checked-out copy of the hook. An absolute path resolves to the same directory no matter which
worktree is committing, so a clone configured that way has every worktree run the main checkout's
copy instead, missing whatever a builder's worktree has locally changed under
`scripts/git-hooks`. Use the relative form.

### What it checks

- The header is `<type>[(scope)][!]: <subject>`, with `type` one of `build`, `chore`, `ci`, `docs`,
  `feat`, `fix`, `perf`, `refactor`, `revert`, `style` or `test`, and a scope of lowercase letters,
  digits and `._/-`.
- The header is at most 100 characters and does not end with a period.
- git's own `Merge …` and `Revert "…"` headers pass unchanged. Their bodies are still checked.
- No `Co-Authored-By:` line names Claude, Anthropic, OpenAI, ChatGPT, Codex, Copilot, Gemini,
  Cursor or AI, in any case. `noreply@anthropic.com` is covered by the Anthropic name.
- No "Generated with" line.

Every violation prints one line to stderr, and the hook exits 1 if there is any.

### How it reads the message

git runs `commit-msg` before it cleans the message up, so the hook repeats the parts of git's
default cleanup that matter: it drops everything from the scissors line (`# ---…--- >8 ---…---`,
which `git commit -v` writes above the diff) to the end, drops `#` comment lines, strips trailing
whitespace from each line and ignores leading and trailing blank lines. Without the scissors rule, a
verbose commit that touches this hook's own tests would fail on the diff below the line.

Names match as whole words, so `Kai` and `jane@gmail.com` are not mistaken for "AI". Punctuation
counts as a word boundary, so `claude[bot]`, `noreply@anthropic.com` and `cursoragent@cursor.com`
still match.

A "Generated with" line is one whose first word is "Generated with", after any leading emoji or
punctuation. That catches the `🤖 Generated with [Claude Code](…)` footer and plain variants, and it
leaves a sentence such as "The images are generated with the snapshot command." alone.

The header length counts characters, not bytes. The hook runs in the C locale so its patterns
behave the same everywhere, and it counts UTF-8 lead bytes, so `…` counts as one character.

## Strict formatting rules

`.swift-format` is the output of `swift format dump-configuration` with three rules switched on:
`NeverForceUnwrap`, `NeverUseForceTry` and `NeverUseImplicitlyUnwrappedOptionals`. Everything else
stays at the tool's defaults. The rules turn the "no `!`, `try!`, `as!` or implicitly unwrapped
optionals" rule from `CLAUDE.md` into a lint error under `swift format lint --strict`, which
`scripts/check.sh` runs. `NeverForceUnwrap` also covers `as!`.

When a newer swift-format adds rules, regenerate the file the same way rather than editing it by
hand, so new rules arrive with the tool's defaults.

## The generated release index

`releases/index.json` is generated from the frontmatter of every `releases/release-<x.y.z>.md`
file by `scripts/release-index.swift`, never hand-edited. A generated file drifts from its source
the moment someone edits one without the other, and a hand-maintained index is one more place a
release's version, date or highlights can disagree with its note. Generating it removes that
second copy: the note is the only place the facts live, and the index is a projection of it.

```sh
swift scripts/release-index.swift
swift scripts/release-index.swift --check
```

The first form parses every note, validates it, and rewrites `releases/index.json`. `--check`
does the same parsing and validation but writes nothing; it fails when a note is invalid or when
`releases/index.json` does not match what regenerating it would produce, which is what CI runs to
guard against a note that was added or edited without regenerating the index alongside it.

It is a standalone Swift script, run directly with `swift scripts/release-index.swift` rather than
built as a package target, so it runs in CI and in a fresh clone without a `swift build` and
without adding a dependency to `Package.swift` for something that only ever runs as a script.

CI runs `swift scripts/release-index.swift --check` on every change, the same as `check.sh` does
locally.

## Building from source needs Xcode

Building this package needs Xcode 26 or later (Swift 6.2), not just the Command Line Tools. Checked
on 2026-09-26: the Command Line Tools (CLT 27.0.0, Swift 6.4) with their default SDK, MacOSX27.0,
fail the build with `external macro implementation type 'SwiftUIMacros.StateMacro' could not be
found for macro 'State()'; plugin for module 'SwiftUIMacros' not found`, because the macOS 27 SDK's
SwiftUI expands `@State` through the `SwiftUIMacros` compiler plugin, which ships with Xcode and
not with the Command Line Tools. The same Command Line Tools with the macOS 26.5 SDK
(`SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`) build it, and so does Xcode
26.0.1 (Swift 6.2, macOS 26.0 SDK).

## CI

Every workflow under `.github/workflows` pins its actions to a full commit SHA (the trailing
`# vX.Y.Z` comment is machine-maintained, not documentation), starts from `permissions: {}` at the
top of the file and grants each job only the permissions it uses (`contents: read` for a job that
checks out the repository, plus the pull request access the Claude review needs), sets
`timeout-minutes` on every job, uses `concurrency` with `cancel-in-progress: true` so a new push
supersedes a run already in flight, and passes `persist-credentials: false` to every
`actions/checkout` step. None of them uses `pull_request_target`, and only the Claude review
touches a secret.

GitHub-hosted runners, macOS included, cost nothing on a public repository. The macOS jobs below
still run only where they buy something: a push to `main`, a pull request, or a manual run, never
on a schedule, because a macOS run takes minutes and queues behind other jobs.

### `ci.yml` — CI

Triggers: `push` to `main`, `pull_request`, `workflow_dispatch`.

- `gates` runs on `macos-26`, whose default Xcode ships Swift 6.2, the version this package
  requires. It prints `swift --version` and then runs `scripts/check.sh`, the same command a
  contributor runs locally before committing.
- `commits` runs on `ubuntu-latest` with full history and replays `scripts/check-commits.sh`
  over the commits the event introduces: `base.sha..head.sha` for a pull request, `before..after`
  for a push, skipped when `before` is the all-zeros SHA a branch's first push reports.
- `release-index` runs on `ubuntu-24.04`, pinned there because it needs the image's Swift
  toolchain to run `swift scripts/release-index.swift --check`. `ubuntu-latest` starts moving from
  Ubuntu 24.04 to 26.04 on 2026-10-19, and the 26.04 image ships no Swift toolchain yet
  (actions/runner-images#14740, open, no committed date); once that lands, the job goes back to
  `ubuntu-latest`. The other Linux jobs here stay on `ubuntu-latest` because nothing they use is
  missing from 26.04.

### `lint.yml` — Lint

Triggers: `push` to `main`, `pull_request`, `workflow_dispatch`, on `ubuntu-latest`. It runs
actionlint over `.github/workflows`, fetched with actionlint's own `download-actionlint.bash`
pinned to a commit SHA, and shellcheck, already installed on the image, over `scripts/*.sh`,
`scripts/*/*.sh`, `scripts/git-hooks/*` and the root `install.sh`.

### `release.yml` — Release

Triggers: `push` of a `v*` tag, on `macos-26`. It has the one macOS job whose `permissions` grant
`contents: write`, scoped to that job alone, to create the GitHub release; every other job and the
workflow's own top-level `permissions` stay at read or `{}`. See [release.md](release.md) for what
it builds, publishes and why.

### `claude-review.yml` — Claude review

Claude reviews a pull request for correctness bugs and for breaks of this repository's rules, and
posts what it finds as inline review comments. Both jobs run on `ubuntu-latest`. There are two ways
in, and only the repository owner can use either:

- **Automatic:** `pull_request` (`opened`, `synchronize`, `reopened`, `ready_for_review`), when the
  pull request is not a draft, its author is the repository owner
  (`github.event.pull_request.user.login == github.repository_owner`) and its head branch lives in
  this repository (`github.event.pull_request.head.repo.full_name == github.repository`).
- **On request:** `issue_comment` (`created`) on a pull request, when the comment starts with
  `/review` and its `author_association` is `OWNER`.

Anything else, a comment on an issue, a comment from anyone else or a pull request from a fork,
starts a run whose jobs are all skipped. Concurrency is set per job, keyed by the pull request
number, so a stray comment, whose run skips both jobs, never cancels a review in flight, while a new
push or a new `/review` does.

#### Why a fork never gets the secret

For the automatic trigger, GitHub by default withholds secrets from runs for fork pull requests,
and the job's condition requires the head repository to be this one whatever that setting says.
`issue_comment` is different: it always runs the default branch's workflow with the repository's
secrets, and its payload does not say where the pull request's head lives. So `/review` takes two
jobs:

1. `gate` has no secret and only `pull-requests: read`. It reads the pull request with the
   preinstalled `gh api` and the workflow's own token, and outputs three values: whether the head
   repository is this one, the head SHA and the base SHA. None of them is pull request text.
2. `review` runs only when `gate` reported that the head repository is this one, and it checks out
   exactly the head SHA that `gate` read, so the commit it reviews is the one that was checked.

The repository also requires approval before workflows run for fork pull requests from outside
contributors. The conditions above do not rely on it; it keeps an outsider's pull request from
running any workflow before the owner has looked at it.

#### Token and permissions

- Claude authenticates with the `CLAUDE_CODE_OAUTH_TOKEN` secret, passed as the action's
  `claude_code_oauth_token` input. There is no API key input and no fallback to one.
- For GitHub, the action gets the workflow's own `github.token` through its `github_token` input
  instead of exchanging an OIDC token for the Claude GitHub App's token, so no job needs
  `id-token: write` and the app does not have to be installed. The token carries only what `review`
  declares: `contents: read` to check out, `pull-requests: write` to post review comments.
- The action writes that token into the remote URL in the checkout's `.git/config`, where Claude's
  `Read` tool can see it. That is accepted: it is limited to the job's two permissions and expires
  when the job ends.
- The action sorts inline comments that were not posted with `confirmed: true` through a
  classification call that needs `ANTHROPIC_API_KEY`. Without that key it posts all of them
  unclassified, so an OAuth-only setup loses no comment. The prompt asks for `confirmed: true`
  anyway, which posts each comment at once.

#### What Claude may do

Pull request content, the diff, the commit subjects and the files, is untrusted input: even the
owner's own pull request can carry text copied from elsewhere, written to steer a model. A review
needs to read the change, not run it, so the model gets no shell and no way to change the checkout:

- `--allowedTools` grants `Read`, `Glob`, `Grep` and
  `mcp__github_inline_comment__create_inline_comment`, the action's tool for posting a comment on a
  line of the pull request. That tool cannot approve or merge.
- `--disallowedTools` removes `Bash`, `Edit`, `Write`, `MultiEdit`, `NotebookEdit`, `WebFetch` and
  `WebSearch`. Naming `Bash` there is what matters most: the action loads the project settings, and
  this repository's `.claude/settings.json` allows many shell commands for local agents, among them
  `swift build`, which runs `Package.swift`. A deny rule overrides an allow rule, so the explicit
  `Bash` is what leaves the review without a shell.
- Before Claude starts, the action restores `.claude/`, `CLAUDE.md` and its other Claude
  configuration paths from the base branch (for `/review`, the default branch) and keeps the pull
  request's versions under `.claude-pr/` for reference only. The rules the review applies are
  therefore `main`'s, not ones the pull request rewrote.
- Nothing from the pull request is interpolated into a `run:` script or into the prompt. The prompt
  is static, and the only values that pass from the event into a step, the SHAs and the pull request
  number, go through `env:`.

#### Why a step prepares the diff

With no shell, Claude cannot run `git diff` or `gh pr diff`, and when the workflow supplies its own
prompt the action gives the model that prompt and nothing else: no diff, no file list, no commits.
So a step before the action, with no secret in its environment, writes
`git diff "$BASE_SHA...HEAD"` to `.build/review/changes.diff` and
`git log --no-merges --format='%h %s' "$BASE_SHA..HEAD"` to `.build/review/commits.txt`, and the
prompt tells Claude to read both first. `BASE_SHA` comes from `github.event.pull_request.base.sha`
for the automatic trigger and from `gate`'s `base-sha` output for `/review`, only ever through
`env:`. The checkout uses `fetch-depth: 0` so the base commit and the merge base are present.

Comments can only be posted on lines of the diff, so a finding about a commit subject goes on the
first changed line of that commit's most relevant file.

#### Repository setup

- The repository secret `CLAUDE_CODE_OAUTH_TOKEN`, created with `claude setup-token`, is the only
  secret this workflow reads.
- The fork approval setting described above is turned on.

### `dependabot.yml`

Weekly updates for the `github-actions` ecosystem, so a pinned action SHA does not go stale
silently.

## Worktree cleanup

An orchestrated run gives every builder its own git worktree and branch, and the orchestrator
cherry-picks what comes back. `scripts/worktree-cleanup.sh` removes the worktrees whose work has
landed and leaves everything else alone.

```sh
scripts/worktree-cleanup.sh --dry-run
scripts/worktree-cleanup.sh
```

### Which worktrees it considers

Only the ones the current session's builders were given. Claude Code records each subagent in
`~/.claude/projects/<project>/<session>/subagents/agent-<id>.meta.json`, and a subagent spawned
with a worktree has `worktreePath` and `worktreeBranch` there. The script reads those two fields
with `plutil -extract <key> raw`. A record without them, or whose worktree no longer exists, is
skipped without a line.

- `<session>` is `$CLAUDE_CODE_SESSION_ID`, which Claude Code exports to the commands it runs.
  `--session <id>` overrides it.
- `<project>` is the main checkout's path with every character other than a letter or digit
  replaced by `-`, the way Claude Code names the folder. `--projects-dir <dir>` overrides the whole
  path. A checkout path with non-ASCII characters needs the override, because the script replaces
  each byte where Claude Code replaces each character.

A worktree someone made by hand has no record, so it is never considered. Neither is a worktree
from another session. `--other-sessions <worktree>…` is the only way to reach those: it takes
worktree names (the folder name, such as `agent-a1d1a78a9567e5d70`) or full paths, and matches
them only against other sessions' builder records. A name no other session recorded gets a `kept`
line and nothing else.

### When it removes one

All three must hold:

- **Unlocked.** Claude Code locks a builder's worktree with a reason naming its pid. A lock counts
  even when that pid is dead, because a builder that crashed can leave work behind that nobody has
  looked at. `git worktree unlock <path>` is a deliberate human step.
- **Clean.** `git status --porcelain` is empty, untracked files included. Ignored files such as
  `.build/` do not count and are deleted with the worktree.
- **Landed.** Every commit on the worktree's `HEAD` is patch-equivalent to one on the target
  branch: `git cherry <target> <HEAD>` prints no `+` line. Cherry-picking changes a commit's SHA,
  so ancestry alone would call every builder's work unlanded; `git cherry` compares the diffs. A
  pick that needed conflict resolution changes the diff too, so that worktree is kept for a human
  to check. The target is the branch the main checkout is on, or `--into <branch>`.

Removal is `git worktree remove <path>`, never `--force`, so git's own checks still apply on top.

### Branches

After removing a worktree, the script deletes its branches with `git branch -D`: the one the
record names and, if different, the one the worktree had checked out. `-D` is needed because a
cherry-picked branch is never an ancestor of the target, so `-d` would refuse it. The script's own
checks stand in for `-d`'s: a branch is kept when it is the target branch, when it has an upstream
configured, or when `git cherry` finds a commit on it that has not landed.

### Output

One line per worktree:

- `removed <path>`, followed by `, deleted branch <name>` or `, kept branch <name>: <reason>` for
  each branch.
- `kept <path>: <reasons>`, with every reason that applies, separated by `;`.
- With `--dry-run`, `would remove <path>` and `would delete branch <name>` instead, and nothing
  changes.
- `worktree-cleanup: nothing to clean` when no worktree qualified for a line at all.
