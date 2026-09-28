# Contributing to Countersign

## Build and test

Requirements: macOS 14 Sonoma or later, and Xcode 26 or later (Swift 6.2). The Command Line Tools
with the macOS 27 SDK cannot build it: that SDK's SwiftUI expands `@State` through a compiler
plugin that ships only with Xcode, so resolving `@State` fails; the same Command Line Tools with
the macOS 26 SDK build it. See [docs/tooling.md](docs/tooling.md) for the verified failure.

```sh
swift build
```

For UI work, render any request without a host:

```sh
.build/debug/countersign preview --host claude Tests/ApprovalCoreTests/Fixtures/claude-edit.json --waiting 2
```

To check a layout without anything appearing on screen, render the panel to a PNG instead (see
"Snapshots" in [docs/design/panel.md](docs/design/panel.md)):

```sh
.build/debug/countersign snapshot Tests/ApprovalCoreTests/Fixtures/claude-edit.json --host claude --appearance dark -o /tmp/claude-edit.png
```

Before any change is considered done, run both gates:

```sh
swift format format --in-place --recursive Package.swift Sources Tests
scripts/check.sh
```

`scripts/check.sh` builds, runs the tests, lints with `swift format --strict`, and rejects code
comments. See [docs/tooling.md](docs/tooling.md) for what each gate covers.

## Commit hook

Turn on the commit message check once per clone:

```sh
git config core.hooksPath scripts/git-hooks
```

It enforces Conventional Commits (`<type>[(scope)][!]: <subject>`) and rejects any `Co-Authored-By`
line naming an AI tool or a "Generated with" line. Details in
[docs/tooling.md](docs/tooling.md).

## Branches and pull requests

Open every pull request against `staging`; `main` only moves when a release is cut.

- One task per pull request. It is squash-merged into `staging` as a single commit whose subject
  is the pull request's title followed by ` (#<number>)`, and whose body is empty, so write the
  title as a Conventional Commit (`<type>[(scope)][!]: <subject>`). The `title` check enforces it.
- A pull request merges once `gates`, `commits`, `release-index`, `lint` and `title` pass and the
  branch is up to date with `staging` ("Update branch" on the pull request brings it up to date).
- For a pull request from a fork, the workflows wait until the maintainer approves them to run.
- Nobody pushes to `staging` or `main` directly, the maintainer included. At release time a pull
  request from `staging` into `main` is merged with a merge commit; see
  [docs/release.md](docs/release.md#cutting-a-release).

## Working with an AI agent

Claude Code reads [CLAUDE.md](CLAUDE.md) and `.claude/`, including the path-scoped rules under
`.claude/rules/` and the skills under `.claude/skills/`. Codex reads the same instructions through
`AGENTS.md` (a symlink to `CLAUDE.md`), plus `.codex/config.toml` and `.codex/rules/default.rules`
for the parts Claude Code applies automatically but Codex does not, and `.agents/skills` (a symlink
to `.claude/skills`) for the skills. The rules are the same for both agents.

## House rules

The full rules live in [CLAUDE.md](CLAUDE.md); in short:

- Zero comments in Swift source. Names carry the meaning; rationale that would have been a comment
  goes into `docs/design/<topic>.md` for an internal design note, or `docs/<topic>.md` for a
  user-facing page.
- No force unwrap (`!`), no `try!`, no `as!`, no `Any`/`AnyObject` in public APIs.
- `ApprovalCore` never imports AppKit or SwiftUI, and every type in it is fully covered by
  `ApprovalCoreTests`.
- Fixtures under `Tests/ApprovalCoreTests/Fixtures` are real captured payloads, not hand-written
  approximations.
- One task per commit, as a Conventional Commit.

## Contributor License Agreement

The CLA Assistant bot asks you to sign on your first pull request, by commenting on the PR as it
instructs. See [CLA.md](CLA.md) for the agreement text. Signing keeps the option open to offer
Countersign under licenses other than GPL-3.0 later, alongside the current one.
