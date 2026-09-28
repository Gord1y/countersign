---
name: release-notes
description: Use when writing or checking a Countersign release note.
---

# Release notes

A release note is `releases/release-<x.y.z>.md`. `releases/index.json` is generated from every
note's frontmatter; it is never hand-edited.

## Format

See [releases/README.md](../../../releases/README.md) for the file naming rule, the full
frontmatter field table with types and limits, how to express an empty `tags` list in the
supported YAML subset, and the required body section order with the `- None.` rule.

## Tone

The body is user-facing: describe what changed for someone running Countersign, not the
implementation. "The panel now stays open when you switch Spaces" reads correctly; "fixed a
window-level bug in `PanelController`" does not. The GitHub release body is this note's body
verbatim, so it needs to stand on its own without the commit history behind it.

Never include install instructions in the note. `.github/workflows/release.yml` appends an
"Install this version" section with the curl command, pre-filled with that release's own version,
after the note's body; a note that repeats it would duplicate or drift from what the workflow
generates.

## Filling `testedWith`

`claudeCode` and `codex` are the versions of Claude Code and Codex actually used to check the
release before publishing it, not a minimum or a guess. Run `claude --version` and check the Codex
CLI's own version output, and record exactly what you tested with.

`cursor` is optional: fill it in only when the release was also checked with Cursor, with the
version actually used. Find it from Cursor > About, or from the `cursor_version` field Cursor
sends in its hook payloads.

`antigravity` is optional in the same way: fill it in only when the release was also checked with
Google Antigravity, with the version actually used. Run `agy --version` for the CLI, or read it from
the desktop app's About window when the release was checked there instead. Antigravity's hook
payloads carry no version.

## Steps

1. Write `releases/release-<x.y.z>.md` following the format above.
2. Run `swift scripts/release-index.swift` to regenerate `releases/index.json`.
3. Run `swift scripts/release-index.swift --check` to confirm the note is valid and the index is
   up to date.
4. Commit both files together: `docs(release): add <x.y.z> notes`.
