# countersign

A native macOS approval panel that answers Claude Code and Codex `PermissionRequest` hooks,
Cursor's `beforeShellExecution` and `beforeMCPExecution` hooks, and Antigravity's `PreToolUse`
hook.

## Rules

- Zero comments in Swift source: no `//`, no `/* */`, no doc comments. Names carry the meaning.
  Rationale that would otherwise be a comment goes into `docs/design/<topic>.md` for an internal
  design note, or `docs/<topic>.md` for a user-facing page.
- `ApprovalCore` never imports AppKit or SwiftUI. Every type in it is fully covered by
  `ApprovalCoreTests`.
- The `hook` path never writes to stderr and never exits non-zero. Every failure means "no
  decision": exit 0, empty stdout.
- No dependencies. No `Any`/`AnyObject` in public APIs, no force unwrap `!`, no `try!`, no `as!`
  in Sources.
- Conventional Commits, one task per commit.

## Gates

```sh
swift format format --in-place --recursive Package.swift Sources Tests
scripts/check.sh
```

Both must succeed before a change is done.

## Rules by area

Claude Code loads these automatically for matching paths; other agents read them from here.

- [.claude/rules/core.md](.claude/rules/core.md): `Sources/ApprovalCore`, `Tests`
- [.claude/rules/panel.md](.claude/rules/panel.md): `Sources/countersign`
- [.claude/rules/tooling.md](.claude/rules/tooling.md): `scripts`, `.github`, `.claude`,
  `Package.swift`, `.swift-format`
