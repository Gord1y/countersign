---
paths:
  - scripts/**
  - .github/**
  - .claude/**
  - Package.swift
  - .swift-format
---

# Scripts, CI and agent configuration

- `scripts/check.sh` is the definition of done, run after
  `swift format format --in-place --recursive Package.swift Sources Tests`. Changing what it
  checks, `.swift-format`, `Package.swift`, `scripts/git-hooks/**`, workflows or
  `.claude/settings.json` needs the user's approval before the edit. No permission rule asks for
  it: `.claude/settings.json` has no `ask` list and `.codex/rules/default.rules` no `prompt` rule,
  so inside the sandbox nothing prompts.
- The sandbox is the boundary. `.claude/settings.json` turns it on, and a sandboxed command runs
  without a prompt. An allow rule exists only for a command that has to run outside the sandbox,
  one in `sandbox.excludedCommands` (SwiftPM, `gh` and the scripts that call them), and its forms
  that run another program or write outside the repository are denied. Never allow a command that
  works sandboxed: the rule would also approve its unsandboxed retry, with no prompt.
- Scripts are POSIX `sh` with `set -eu`. Most need nothing beyond macOS, git and `plutil`; the
  build, release and screenshot scripts also need the Swift toolchain, and so does
  `scripts/test-release-index.sh`, which runs `scripts/release-index.swift` directly;
  `scripts/rulesets.sh` needs `gh` and `jq`. The zero-comment rule applies to scripts and
  workflows too; rationale goes into `docs/`.
- The repository's rulesets live in `.github/rulesets/*.json`. Change a ruleset by editing its
  file and running `scripts/rulesets.sh --apply`, never only in GitHub's settings: the `lint`
  job's `--check` fails on any drift.
- GitHub Actions: pin every action to a full commit SHA (a trailing `# vX.Y.Z` version comment is
  allowed, it is machine-maintained), set least-privilege `permissions` per job, a
  `timeout-minutes`, `concurrency` with `cancel-in-progress`, and `persist-credentials: false` on
  checkout. Never use `pull_request_target`, except in `pr-assign.yml`, which checks out nothing
  and reads only the pull request's number and author login, through `env:`.
- No workflow reads a secret. One that needs a secret runs only where nobody else can trigger it:
  never on a fork's pull request, never on `pull_request_target`, and never on a comment someone
  else can post. There is no automated review; reviews follow
  [docs/review-checklist.md](../../docs/review-checklist.md).
- Commits follow Conventional Commits, one task per commit, with no AI co-author trailer and no
  "Generated with" line.
