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

`scripts/check.sh` runs four parts in order, and each also runs on its own:
`scripts/check-build.sh` runs `swift build`, which compiles every target, the app included;
`scripts/check-test.sh` runs `swift test`; `scripts/check-lint.sh` runs
`swift format lint --strict` and rejects code comments; `scripts/check-scripts.sh` runs the four
test scripts above. CI runs the parts as parallel jobs; see [`ci.yml`](#ciyml--ci). Last,
`check.sh` runs `swift scripts/release-index.swift --check` against the repository's own
`releases/index.json`, which CI checks in its separate `release-index` job; the test script only
exercises `--check` on fixtures, so without this line a stale index passed locally.

`swift test` compiles everything again with testing enabled rather than reusing `swift build`'s
output, so the two compiles cannot be merged into one. Measured on CI on 2026-09-28,
`swift build --build-tests` followed by `swift test --skip-build` took 118 seconds to build, no
less than `swift build` (41) and `swift test`'s own build (73) together. Running the two as
separate jobs overlaps them instead.

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
and this section together.

### Branches and rulesets

`staging` takes every change through a pull request that is squash-merged, and `main` takes
`staging` through a pull request merged with a merge commit when a release is cut (see
[release.md](release.md#cutting-a-release)). Rebase merging is off. A squash commit's subject is
the pull request's title followed by ` (#<number>)`, which GitHub appends, and its body is empty.

Three rulesets enforce this. None has a bypass actor, so they bind the owner too:

- `main`: no deletion, no force push, changes only through a pull request (one approving review,
  dismissed when new commits are pushed; merge commit only), and the required checks `gates`,
  `commits`, `release-index`, `lint` and `title`, each expected from the GitHub Actions app.
- `staging`: the same, except squash only, and the branch must be up to date with `staging`
  before it merges.
- `release tags`: a `v*` tag can be created but never moved or deleted.

On the owner's own pull requests the approval comes from the
[Claude review](#claude-reviewyml--claude-review), since nobody can approve their own; on everyone
else's, including Dependabot's, it comes from the owner, whom CODEOWNERS asks for it.

Only `staging` requires an up-to-date branch. Each release's merge commit exists only on `main`,
and `staging`, which takes changes only by squash, can never contain it, so requiring it on `main`
would block every release after the first. The checks of a `staging` → `main` pull request still
run on its merge with `main`'s current tip.

Automatic deletion of head branches is off, because it would delete `staging` after every
release pull request.

### Actions

- Allowed actions are GitHub's own, `anthropics/claude-code-action@*` and `oven-sh/setup-bun@*`.
  `claude-code-action` is a composite action whose `action.yml` runs `oven-sh/setup-bun`, and an
  action called from another action must pass the same allow list. If a Dependabot bump makes
  `claude-code-action` call another action, the review job fails with that action not allowed
  until it is added here.
- Every action must be pinned to a full commit SHA, enforced by the repository setting as well as
  by the rule under [CI](#ci).
- The workflows' default `GITHUB_TOKEN` is read-only. GitHub Actions may create and approve pull
  requests, which the Claude review's verdict step needs; only jobs that declare
  `pull-requests: write` get that far.
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
  owner's review: the maintainer's own pull requests are approved by the Claude review.

## CI

Every workflow under `.github/workflows` pins its actions to a full commit SHA (the trailing
`# vX.Y.Z` comment is machine-maintained, not documentation), starts from `permissions: {}` at the
top of the file and grants each job only the permissions it uses (`contents: read` for a job that
checks out the repository, plus the pull request access the Claude review and the assignee job
need), sets `timeout-minutes` on every job, uses `concurrency` with `cancel-in-progress: true` so
a new push supersedes a run already in flight, and passes `persist-credentials: false` to every
`actions/checkout` step. Only `pr-assign.yml` uses `pull_request_target`, because it has to write
to pull requests from forks, and it checks out nothing; only the Claude review touches a secret.

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
  3 minutes 38 seconds on 2026-09-28: 38 seconds to build, 73 to rebuild for the tests, 12 to run
  them and about 90 for lint and the script suites, one after another.
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
`scripts/*/*.sh`, `scripts/git-hooks/*` and the root `install.sh`.

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
`contents: write`, scoped to that job alone, to create the GitHub release; every other job and the
workflow's own top-level `permissions` stay at read or `{}`. See [release.md](release.md) for what
it builds, publishes and why.

### `claude-review.yml` — Claude review

Claude reviews a pull request for correctness bugs and for breaks of this repository's rules. It
posts a progress comment while it works and ends with a formal review from `github-actions`: a
request for changes when it finds a verified Blocker, an approval otherwise, with every finding
graded in its body. On the owner's own pull requests that approval is the one the rulesets
require (see [Branches and rulesets](#branches-and-rulesets)). Both jobs run on `ubuntu-latest`.
There are two ways in, and only the repository owner can use either:

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
  declares: `contents: read` to check out, `pull-requests: write` to post the progress comment and
  submit the review.
- The action writes that token into the remote URL in the checkout's `.git/config`, where Claude's
  `Read` tool can see it. That is accepted: it is limited to the job's two permissions and expires
  when the job ends.

#### What Claude may do

Pull request content, the diff, the commit subjects and the files, is untrusted input: even the
owner's own pull request can carry text copied from elsewhere, written to steer a model. A review
needs to read the change, not run it, so the model gets no shell and no way to change the checkout:

- `--allowedTools` grants `Read`, `Glob` and `Grep`. `track_progress: true` puts the action in its
  tag mode, which adds its own list: `LS`, `mcp__github_comment__update_claude_comment` for the
  progress comment, three `mcp__github_ci__*` tools that read CI status and job logs, and the git
  commands `git add`, `git commit`, `git rm` and the action's `git push` wrapper, each as a `Bash`
  rule. Tag mode also runs Claude with `--permission-mode acceptEdits`, which allows any file edit
  inside the checkout without asking. None of these tools can approve or merge.
- `--disallowedTools` removes `Bash`, `Edit`, `Write`, `MultiEdit`, `NotebookEdit`, `WebFetch` and
  `WebSearch`. It is appended after tag mode's list, and a deny rule overrides every allow rule and
  the permission mode, so Claude still has no shell and cannot write a file. Naming `Bash` there is
  what matters most: tag mode's git commands are `Bash` rules, and the action also loads the project
  settings, where this repository's `.claude/settings.json` allows many shell commands for local
  agents, among them `swift build`, which runs `Package.swift`. The explicit `Bash` is what leaves
  the review without a shell, and the explicit file-writing tools are what leave `acceptEdits`
  nothing to allow.
- The verdict is structured output, not a file Claude writes. Under `acceptEdits`, a `Write`
  allowed for one report file cannot be kept to that file: every edit inside the checkout is
  allowed, `.git/` included, so a review steered by the pull request could plant a hook or rewrite
  `.git/config` and get its own code run when the action later runs git. Structured output needs
  no file tool at all.
- Before Claude starts, the action restores `.claude/`, `CLAUDE.md` and its other Claude
  configuration paths from the base branch (for `/review`, the default branch) and keeps the pull
  request's versions under `.claude-pr/`. The prompt says so, and the review judges by the base
  branch's rules (for `/review`, the default branch's), with one exception: when the pull request
  itself changes a rule, the rest of the pull request is judged by the new version and the rule
  change is listed as a Minor finding, so it is visible. Only the owner's pull requests are
  reviewed, and such a change has to be in the diff the owner wrote; judging by the base rule alone
  would block every pull request that adds a rule together with the change that needs it, since
  nobody else can approve the owner's pull requests.
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

#### The verdict

`--json-schema` makes Claude end the run with structured output, which the action exposes as the
step's `structured_output` output. The schema allows exactly two fields, both required:

- `verdict`: `REQUEST_CHANGES` only when Claude found at least one verified 🔴 Blocker, `APPROVE`
  otherwise. No other value passes the schema.
- `body`: the review in Markdown, in fixed sections: Verdict, Impact, Issues (one line counting
  each severity), Findings, Missing tests, Nits, Verification questions and Read (the files and
  commits it read).

The prompt grades every finding. 🔴 Blocker is a verified break of the safety contract or a hard
rule: an approval the person never gave, the `hook` path writing to stderr or exiting non-zero, a
crash on a primary path, a hook or config file lost, a secret reachable by someone else, or a
breach of `CLAUDE.md`'s hard rules. 🟠 Major is a bug a person will hit, 🟡 Minor an edge case, a
missing `ApprovalCore` test or docs that now contradict the code, 🔵 Nit a small convention point.
Only a Blocker blocks: a wrong block costs the owner a new review run, while a Major finding is
listed in an approving review and fixed in a follow-up. The prompt also names what other checks
already enforce (comments, formatting, commit subjects and titles, workflow and shell lint, the
release index), so the review never repeats them. Findings go in the body, not in inline
comments. If Claude ends without structured output, the action's step fails.

A later step with no model in it submits the verdict. It gets `structured_output` only through
`env:`, like every other value that reaches a script, takes both fields out with `jq`, and posts the
review through the REST reviews API with `commit_id` set to the commit the job checked out, the
same `head.sha` or `gate` output the checkout used. `gh pr review` always reviews the pull request's
current head, so a push landing while Claude read the old commit would have turned its approval
into one for code it never read; pinned to the reviewed commit, that approval is stale on arrival
and, with stale approvals dismissed, counts for nothing. The step then checks the review GitHub
returns from that call: its state must be `APPROVED` or `CHANGES_REQUESTED` to match, and its
commit the reviewed one. Reading the response, rather than listing the pull request's reviews,
means no page limit can hide the review just posted. An empty body, an unknown verdict or a review
GitHub does not record that way fails the job.

A failed run, like a request for changes, leaves the owner's pull request without the approval the
rulesets require. GitHub counts each reviewer's latest review, so the way out is a new run: push a
fix, since every push runs the review again; comment `/review` on the pull request; or re-run the
failed job.

#### Repository setup

- The repository secret `CLAUDE_CODE_OAUTH_TOKEN`, created with `claude setup-token`, is the only
  secret this workflow reads.
- The fork approval setting described above is turned on.
- "Allow GitHub Actions to create and approve pull requests" is on, because the verdict step
  approves.

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
