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
runs `scripts/release-index.swift` directly to test it. `scripts/rulesets.sh` needs `gh`, since it
talks to GitHub's API, and `jq`, which macOS ships in `/usr/bin`; its test needs only `jq`.

The scripts that change this repository's own gates or a person's machine have a test script that
`scripts/check.sh` runs: `scripts/test-commit-msg.sh` covers `scripts/git-hooks/commit-msg`, the
commit message rules; `scripts/test-worktree-cleanup.sh` covers `scripts/worktree-cleanup.sh`,
which removes a builder's landed worktrees and branches; `scripts/test-release-index.sh` covers
`scripts/release-index.swift`, which regenerates `releases/index.json`;
`scripts/test-install.sh` covers `install.sh`, the installer people run on their own machine; and
`scripts/test-run-quietly.sh` covers `scripts/run-quietly.sh`, which shapes what the gates print;
and `scripts/test-rulesets.sh` covers `scripts/rulesets.sh` against a fake `gh` that serves the
committed rulesets, so it runs offline.
`scripts/build-app.sh`, `scripts/package-release.sh` and `scripts/screenshots/render.sh` have no
test script; they are checked by running them.

`scripts/check.sh` runs four parts in order, and each also runs on its own:
`scripts/check-build.sh` runs `swift build`, which compiles every target except the tests;
`scripts/check-test.sh` runs `swift test`; `scripts/check-lint.sh` runs
`swift format lint --strict` and rejects code comments; `scripts/check-scripts.sh` runs the six
test scripts above. CI runs the parts as parallel jobs; see [`ci.yml`](#ciyml--ci). Last,
`check.sh` runs `swift scripts/release-index.swift --check` against the repository's own
`releases/index.json`, which CI checks in its separate `release-index` job; the test script only
exercises `--check` on fixtures, so without this line a stale index passed locally.

`check-build.sh`, `check-test.sh` and `check-lint.sh` run their tool through
`scripts/run-quietly.sh`, which keeps the output in a temporary log. When the tool passes, it
prints one line: the tool's own summary (`Build complete!`, `Test run with N tests … passed`) or
`<label>: ok`. When it fails, it prints the lines naming the problem (`error:`, `warning:`, `✘`),
or the last 30 lines when none match, then the log's path, and exits with the tool's status. A
passing `check.sh` therefore prints a handful of lines instead of every compiled file and every
test. That is what a person needs from a passing gate, and what a coding agent otherwise carries in
its context after every run: in agent sessions, gate logs were the largest single kind of command
output, often cut off at the 30,000-character limit. `CHECK_VERBOSE=1` prints the full output
locally. CI always prints it, since GitHub Actions sets `CI` and a failed job's log is the only
place to read it, so `ci.yml` needs no change.

`swift test` compiles everything again with testing enabled rather than reusing `swift build`'s
output, so the two compiles cannot be merged into one. Measured on CI on 2026-09-28, with each
time as SwiftPM reported it, `swift build --build-tests` followed by `swift test --skip-build` took
118 seconds to build, no less than `swift build` (41) and `swift test`'s own build (73)
together. Running the two as separate jobs overlaps them instead.

`scripts/build-app.sh` builds the release binary and assembles it into `.build/Countersign.app`,
ad-hoc signed; see [design/app.md](design/app.md) for the bundle layout and why. It copies the
committed `scripts/app/AppIcon.icns` into the bundle as it is, since no script generates the icon;
see [design/icon.md](design/icon.md). `scripts/package-release.sh` builds on it to produce a
downloadable release; see [release.md](release.md).

## Commit messages

`scripts/git-hooks/commit-msg` is the one rule set. Locally git runs it as a hook; in CI,
`scripts/check-commits.sh <base> <head>` runs the same file over every non-merge commit in
`base..head` and prefixes each violation with the commit's short SHA, and `pr-title.yml` runs it
over the subject a pull request's squash commit will get. There is no second copy of the rules to
drift.

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

The hook uses no here-documents. A shell writes a here-document to a temporary file, and where it
can't create one, as inside an agent's sandbox, the loop reading it never runs: the trailer went
unreported and the hook exited 0. Each check pipes its matching lines through `sed` instead, and
`scripts/test-commit-msg.sh` fails if the hook contains `<<`.

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

## Repository settings

These GitHub settings live outside the tree, so this section is their record: change a setting
and this section together. The rulesets are the exception: their files under `.github/rulesets/`
are the record, and this section only explains them.

### Branches and rulesets

`staging` takes every change through a pull request that is squash-merged, and `main` takes
`staging` through a pull request merged with a merge commit when a release is cut (see
[release.md](release.md#cutting-a-release)). Rebase merging is off. A squash commit's subject is
the pull request's title followed by ` (#<number>)`, which GitHub appends, and its body is empty.
A merge commit into `main` also takes its subject from the pull request's title, and its body is
empty: the repository's merge commit title is set to the pull request title, and its message to
blank.

Three rulesets enforce this. Each is committed as `.github/rulesets/<name>.json` in GitHub's own
ruleset format, and the files are the source of truth. None has a bypass actor, so they bind the
owner too:

- `main`: no deletion, no force push, changes only through a pull request (no approving review
  required; merge commit only), and the required checks `gates`, `commits`, `release-index`,
  `lint` and `title`, each expected from the GitHub Actions app.
- `staging`: the same, except squash only, and the branch must be up to date with `staging`
  before it merges.
- `release tags`: a `v*` tag can be created but never moved or deleted.

No ruleset requires an approving review. Nobody can approve their own pull request, and only the
maintainer can merge, so a required approval would only block the maintainer's own work. Review
happens outside GitHub's approval: the maintainer reviews everyone else's pull requests, Dependabot's
included, before merging them (CODEOWNERS asks for it), and reviews their own work locally before
each release against [review-checklist.md](review-checklist.md). An automated Claude review ran
here until 0.2.0 and was removed: it approved a release it had not read.

Only `staging` requires an up-to-date branch. Each release's merge commit exists only on `main`,
and `staging`, which takes changes only by squash, can never contain it, so requiring it on `main`
would block every release after the first. The checks of a `staging` → `main` pull request still
run on its merge with `main`'s current tip.

Automatic deletion of head branches is off, because it would delete `staging` after every
release pull request.

GitHub never reads those files itself. `scripts/rulesets.sh --apply` writes each one to GitHub,
updating the ruleset of the same name or creating it, and then checks; run it with `gh` signed in
as the owner. `scripts/rulesets.sh --check` compares every file with GitHub's ruleset and fails on
any difference, on a file with no ruleset, and on a ruleset with no file. The `lint` job runs the
check on every pull request and every push to `main`, so a ruleset changed in GitHub's settings
fails CI until its file follows. To change a ruleset, edit its file in a pull request and run
`--apply` from that branch: the pull request's `lint` fails until you do. GitHub hides bypass
actors from a token without admin rights; when they come back hidden, the check compares
everything but them, so only `--check` run as the owner covers them. A ruleset is never deleted by the script: remove it in GitHub's settings and delete its
file in the same pull request.

Auto-merge is on. With no approval required, "Enable auto-merge" on a pull request merges it by
itself once the required checks pass, and for `staging` once the branch is up to date.

### Actions

- Allowed actions are GitHub's own; the workflows use only `actions/checkout`.
- Every action must be pinned to a full commit SHA, enforced by the repository setting as well as
  by the rule under [CI](#ci).
- The workflows' default `GITHUB_TOKEN` is read-only, and GitHub Actions may not create or approve
  pull requests: no workflow needs either.
- The repository has no Actions secrets.
- Workflows for any outside contributor's fork pull request wait for the maintainer's approval.
- Dependabot's update jobs run on Actions but bypass these policies, as GitHub documents.

### Security

- Private vulnerability reporting is on; [SECURITY.md](../SECURITY.md) and the issue template's
  security link send reports there.
- Dependabot alerts and Dependabot security updates are on, and so are secret scanning and push
  protection.

### Community

- Discussions are on. Its Q&A category, slug `q-a`, is where the README, the issue template's
  question link and the app's Ask a Question… go. `.github/DISCUSSION_TEMPLATE` holds the forms
  for Q&A and Ideas.
- The wiki and Projects are off: the documentation lives in `docs/` and the plan in
  [ROADMAP.md](../ROADMAP.md).
- Sponsorships are on, from `.github/FUNDING.yml`.
- CLA Assistant (cla-assistant.io) reads the agreement from a public gist,
  <https://gist.github.com/Gord1y/c6ba6735119a4ab91197b41678108d1a>, which holds a copy of
  [CLA.md](../CLA.md): change both together. Its status on a pull request is not a required check.
- `.github/CODEOWNERS` names Gord1y for every path, so GitHub requests the maintainer's review on
  every pull request someone else opens, Dependabot's included. The rulesets do not require a code
  owner's review, since they require no review at all (see
  [Branches and rulesets](#branches-and-rulesets)).

## CI

Every workflow under `.github/workflows` pins its actions to a full commit SHA (the trailing
`# vX.Y.Z` comment is machine-maintained, not documentation), starts from `permissions: {}` at the
top of the file and grants each job only the permissions it uses (`contents: read` for a job that
checks out the repository, plus the pull request access the assignee job needs), sets
`timeout-minutes` on every job, uses `concurrency` with `cancel-in-progress: true` so a new push
supersedes a run already in flight, and passes `persist-credentials: false` to every
`actions/checkout` step. Only `pr-assign.yml` uses `pull_request_target`, because it has to write
to pull requests from forks, and it checks out nothing; no workflow reads a secret.

GitHub-hosted runners, macOS included, cost nothing on a public repository. The macOS jobs below
still run only where they buy something: a push to `main`, a pull request, or a manual run, never
on a schedule, because a macOS run takes minutes and queues behind other jobs.

### `ci.yml` — CI

Triggers: `push` to `main`, `pull_request`, `workflow_dispatch`.

- `build`, `test` and `static` run in parallel on `macos-26`, whose default Xcode ships Swift 6.2,
  the version this package requires. `build` prints `swift --version` and runs
  `scripts/check-build.sh`, `test` runs `scripts/check-test.sh`, and `static` runs
  `scripts/check-lint.sh` and `scripts/check-scripts.sh`. Together they are `scripts/check.sh`,
  the command a contributor runs locally before committing. Run as one job, `check.sh` took
  3 minutes 38 seconds on 2026-09-28: 41 seconds to build, 73 to rebuild for the tests, 12 to run
  them and about 90 for lint and the script suites, one after another, each build time as SwiftPM
  reported it. Split into these three jobs, the whole CI run took 2 minutes 23 seconds, with
  `test` the longest at 2 minutes 9 seconds, so `test` is the critical path. Building the tests
  in a separate step (`swift build --build-tests`, then `swift test --skip-build`) was measured
  and saves nothing; caching `.build` between runs has not been tried.
- `gates` is the check the rulesets require. It runs on `ubuntu-latest` once `build`, `test` and
  `static` have finished and fails unless all three ended in `success`. It runs even when one of
  them failed (`!cancelled()`), because a required check that is skipped counts as passing.
  Keeping the name `gates` left the rulesets' required checks unchanged when the job was split.
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
`scripts/*/*.sh`, `scripts/git-hooks/*` and the root `install.sh`. Last, it runs
`scripts/rulesets.sh --check` with the job's read-only token, which can read a public repository's
rulesets (see [Branches and rulesets](#branches-and-rulesets)).

### `pr-title.yml` — PR title

Triggers: `pull_request` (`opened`, `edited`, `reopened`, `synchronize`), on `ubuntu-latest`. Its
one job, `title`, runs `scripts/git-hooks/commit-msg` over the subject the squash commit will get:
the pull request's title followed by ` (#<number>)`, which GitHub appends. Checking the title
alone would pass a title just under the 100-character limit whose squash subject is over it.

A pull request lands on `staging` as one squash commit with that subject, and `commits`
checks only the branch's own commits, which the squash discards. Without `title`, a subject nobody
checked would land on `staging`, and `commits` would then fail every `staging` → `main` pull
request after it.

- `edited` re-runs the check when the title is corrected, and `synchronize` gives every new head
  commit its own result, which a required check needs.
- The job checks out the base commit (`github.event.pull_request.base.sha`), so the hook that
  judges the title is the base branch's, not one the pull request rewrote.
- The title and the number reach the hook only through `env:`, written to a file under
  `$RUNNER_TEMP`, never interpolated into the script.

### `pr-assign.yml` — PR assignee

Triggers: `pull_request_target` (`opened`, `reopened`), on `ubuntu-latest`. Its one job, `assign`,
adds the pull request's author as its assignee. Dependabot's pull requests are skipped here and
assigned by `dependabot.yml` instead.

- A fork's pull request gets a read-only token under `pull_request`, which cannot assign anyone;
  `pull_request_target` runs with the base repository's token instead. That is the risk this
  trigger is known for, so the job checks out nothing, runs no code from the pull request, and
  reads only the pull request's number and its author's login, both through `env:`. Its only
  permission is `pull-requests: write`.
- GitHub's add-assignees call succeeds even when it ignores a login it cannot assign, so the job
  reads the assignees back and warns when the author is not among them.

### `release.yml` — Release

Triggers: `push` of a `v*` tag, on `macos-26`. It has the one macOS job whose `permissions` grant
`contents: write` and `discussions: write`, scoped to that job alone, to create the GitHub release
and its Announcements discussion; every other job and the workflow's own top-level `permissions`
stay at read or `{}`. See [release.md](release.md) for what
it builds, publishes and why.

### `dependabot.yml`

Weekly updates for the `github-actions` ecosystem, so a pinned action SHA does not go stale
silently. Two entries cover the same ecosystem and directory:

- Version updates go to `staging` (`target-branch: staging`), like every other change.
- Security updates always open against the default branch, `main`, and an entry with a
  `target-branch` does not configure them. The second entry, with no `target-branch`, exists for
  them alone: its `open-pull-requests-limit: 0` turns off its version updates. Before merging a
  security update, change its base to `staging` and bring it up to date with "Update branch".

Both entries set `commit-message: prefix: ci`, so every subject starts with `ci: `. Dependabot's
default `Bump …` fails the commit hook, and with it the required `commits` and `title` checks.

Both entries also assign every Dependabot pull request to Gord1y. Reviewers come from
`.github/CODEOWNERS` instead of Dependabot's own `reviewers` option, which GitHub is retiring.

Dependabot reads this file from the default branch, so a change to it takes effect once it
reaches `main`.

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
