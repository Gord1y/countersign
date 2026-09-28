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
  `.claude/settings.json` needs the user's approval; those edits prompt on purpose.
- Scripts are POSIX `sh` with `set -eu`. Most need nothing beyond macOS, git and `plutil`; the
  build, release and screenshot scripts also need the Swift toolchain, and so does
  `scripts/test-release-index.sh`, which runs `scripts/release-index.swift` directly. The
  zero-comment rule applies to scripts and workflows too; rationale goes into `docs/`.
- GitHub Actions: pin every action to a full commit SHA (a trailing `# vX.Y.Z` version comment is
  allowed, it is machine-maintained), set least-privilege `permissions` per job, a
  `timeout-minutes`, `concurrency` with `cancel-in-progress`, and `persist-credentials: false` on
  checkout. Never use `pull_request_target`, except in `pr-assign.yml`, which checks out nothing
  and reads only the pull request's number and author login, through `env:`.
- Secrets reach only jobs that cannot be triggered by someone else: an automatic Claude review
  runs only for pull requests the repository owner opens from a branch of this repository, and
  `/review` runs only when the comment's `author_association` is `OWNER`. Pull request text is
  untrusted input, so the review model gets no shell and no file tools and writes nothing but its
  progress comment; the verdict it returns is submitted by a later step that runs no model.
- Commits follow Conventional Commits, one task per commit, with no AI co-author trailer and no
  "Generated with" line.
