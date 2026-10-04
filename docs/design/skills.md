# Skills

Countersign 0.3.0 plans a Skills pane over the shared agent setup (`Gord1y/countersign-skills`).
This note covers the `ApprovalCore` groundwork, which no command or window uses yet.

## The catalog

The setup describes what it ships in one file, `catalog.json`. Its contract is countersign-skills'
`docs/catalog.md`: schema version 1, a `skills` list, a `rules` list and an `agents` list. A new
field does not bump the schema version, so Countersign ignores keys it does not know.
`SkillCatalog` parses it.

Countersign reads the file from two places: a pinned countersign-skills release, and each
addition, which is another folder laid out the same way, at `<folder>/catalog.json`.

- **One malformed entry fails the whole catalog.** The generator writes the file and CI checks it,
  so a bad entry means a corrupt or hand-edited file. A partial list would look complete and hide
  what is missing, so the reader reports the first problem and returns no list.
- **`path` must stay inside its folder.** A loader resolves `path` against the folder the catalog
  came from, and an addition is someone else's folder. An absolute path, an empty path or a `..`
  component is rejected, so a catalog can never point a loader at a file outside its own folder.
- **`agents` stays as the catalog's strings, not `Host`.** The setup has no Cursor, and it may add
  agents Countersign does not know. Mapping to `Host` would drop those entries or force a release
  to show them.
- **A missing list is an empty list.** A catalog with only a schema version is valid; a list that is
  present but not an array is not.

## The installer's state

The installer keeps its state in `${XDG_CONFIG_HOME:-$HOME/.config}/countersign/skills/`, which
is `AppPaths.skillsStateDirectory`. `SkillsInstallState.read` reads it; every piece is optional,
and a missing file or folder is an empty list, never an error.

- `sources.tsv`: one absolute folder per line. The first is the countersign-skills checkout
  itself (`setupFolder`), every later line an addition. The installer rewrites it on every
  install. A fresh machine has none, which is how Countersign knows nothing is installed.
- `additions.tsv`: one absolute folder per line, appended by `install.sh --addition <folder>`.
- `manifest.tsv`: written only by `install.sh --copy`, one line per installed file with five tab
  separated columns: agent, skill, version, file (relative to the skill folder) and sha256. A
  linked install, the default, writes none, so an empty manifest means "linked or not installed",
  not "broken".
- `backups/<yyyymmdd-hhmmss>/`: one folder per install that moved something aside; the installer
  keeps the newest five. The names sort by time, so the list is the names in reverse order.
  Plain files in `backups` are not backups and are ignored, and so are hidden entries, here and
  in an agent's skills folder.

`settings-layer.json`, `base/` and `originals/` live in the same folder and are not read.

- **A malformed line is skipped, not a failure.** The installer appends to `additions.tsv`, so a
  half-written line can sit at the end of the file. One bad line must not hide the rest, so a
  folder line that is not an absolute path, and a manifest line without exactly five fields or
  without a 64-character lowercase hex sha256, is dropped and the other lines are kept.
- **Trailing whitespace is trimmed from folder lines only.** A path may legitimately contain
  inner spaces; the installer never writes trailing ones.

### Where each agent's skills live

`AppPaths.agentSkillsDirectory(for:)` computes the folder for the agents the setup knows:

| Agent | Skills folder |
| --- | --- |
| `claude` | `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills` |
| `codex` | `$HOME/.agents/skills` |
| `antigravity` | `$HOME/.gemini/antigravity-cli/skills` |

Any other agent, Cursor included, has none and gets `nil`. The installer writes the Codex folder
only when `$HOME/.codex` exists and the Antigravity folder only when
`$HOME/.gemini/antigravity-cli` exists. `agentSkillsDirectory` is pure path computation and does
not apply that rule: a caller checks that the folder exists before it reports the agent as
installed or missing.

`InstalledSkill.scan` lists one such folder. A linked install leaves a symbolic link per skill
pointing into the source folder, which scans as `linked` with its target (a relative target is
resolved against the scanned folder and standardized); a copy install leaves a real folder, which
scans as `copied`. Plain files and hidden entries are not skills and are skipped.

## A release

A countersign-skills release is a GitHub release of `Gord1y/countersign-skills`, tagged
`v<x.y.z>`. It attaches three assets: `countersign-skills-<x.y.z>.tar.gz`, its checksum file
`countersign-skills-<x.y.z>.tar.gz.sha256`, and `catalog.json`. An asset downloads from
`https://github.com/Gord1y/countersign-skills/releases/download/v<x.y.z>/<asset>`.
`SkillsRelease` builds those names and URLs from a version and refuses an asset name that is not
plain file-name characters.

Countersign pins one version and trusts an archive only when its SHA-256 matches the release's
checksum file (the 2026-10-01 loader decision). SHA-256 comes from CryptoKit, a system framework,
so the check adds no dependency.

The check is strict about the checksum file's shape: one line, 64 lowercase hex characters, two
spaces, the archive's file name and a newline (the newline may be missing, nothing may follow it).
The file is generated by `scripts/package-release.sh`, so any other shape means the wrong file or
a damaged one, and a name other than the pinned archive's means the checksum belongs to another
release.

Nothing downloads yet, and countersign-skills is not published. The first loader commit adds the
network request together with the privacy docs: the README "Privacy" section and
`docs/safety-and-privacy.md` promise one network request today, the update check.
