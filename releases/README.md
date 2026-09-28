# Release notes

This page is the format every release note must follow: the file name, the frontmatter fields and
their limits, the body's sections, the generated index and the commit that adds a note. Read it
when you write or check a release note, or when `swift scripts/release-index.swift --check`
rejects one.

Every Countersign release is one file here, plus a generated index. See
[.claude/skills/release-notes/SKILL.md](../.claude/skills/release-notes/SKILL.md) for the
step-by-step writing guidance, and
[docs/tooling.md](../docs/tooling.md#the-generated-release-index) for why the index is generated
rather than hand-maintained.

## File naming

`releases/release-<x.y.z>.md`, where `<x.y.z>` is the release's semver version and must match the
`version` field inside the file exactly.

## Frontmatter

Between two `---` lines, at the top of the file:

| Field | Type | Limit |
| --- | --- | --- |
| `version` | string | semver `x.y.z`, must match the file name |
| `date` | string | `YYYY-MM-DD`, a valid calendar date |
| `title` | string | at most 90 characters |
| `summary` | string | at most 400 characters |
| `type` | string | one of `major`, `minor`, `patch` |
| `breaking` | boolean | `true` or `false` |
| `highlights` | list of strings | 1 to 3 items |
| `tags` | list of strings | 0 to 5 items |
| `testedWith` | map | `claudeCode` and `codex` required, `cursor` and `antigravity` optional, each a version string |

The frontmatter supports a small YAML subset: plain, single-quoted and double-quoted scalar
strings, unquoted `true`/`false`, `- item` lists, and the one-level `testedWith` map. Nothing else
is recognized, and `swift scripts/release-index.swift` reports anything outside that subset as an
error naming the file and line.

`type` says how big the release is for someone running Countersign, not which semver number moved:
`major` for the first release or one that changes how you use Countersign, `minor` for new
features, `patch` for fixes only.

An empty list has no supported flow syntax: `tags: []` is rejected, because `[]` is not a
recognized scalar and is parsed as a plain string, not an empty list. Write the key with nothing
after it and no `- item` lines under it instead:

```yaml
tags:
```

## Body

`## ` sections, in exactly this order:

1. `## Added`
2. `## Changed`
3. `## Fixed`
4. `## Removed`
5. `## Security`

All five are required, and each must have content: write `- None.` when a section has nothing to
report for this release. No text is allowed before `## Added`.

After `## Security`, two more sections are optional, in this order if present:

6. `## Upgrading` — a manual step the release needs, such as re-running setup or re-trusting the
   Codex hooks.
7. `## Notes` — anything else worth calling out.

Nothing else goes in the body. The GitHub release body is this note's body, verbatim.

## The generated index

`releases/index.json` is generated from every note's frontmatter by
`swift scripts/release-index.swift`; it is never hand-edited. Run it after writing or changing a
note to regenerate the index, and run `swift scripts/release-index.swift --check` to confirm a
note is valid and the index matches what regenerating it would produce.

## Committing a note

A commit that adds a release note is `docs(release): add <x.y.z> notes` and includes both the note
and the regenerated `releases/index.json`.
