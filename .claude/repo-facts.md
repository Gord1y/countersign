# Repo facts

Countersign's values for the shared agent setup's skills (`Gord1y/countersign-skills`). Each row
is named exactly as the skill's "Repo facts" table names it. Where a row and the contract doc
disagree, the contract doc wins.

## release-notes

| Fact | Countersign |
| --- | --- |
| Where release notes live (folder and contract doc) | `releases/release-<x.y.z>.md`, with the contract in [`releases/README.md`](../releases/README.md) |
| Where uncommitted drafts go | the gitignored `writeups/` folder in the main checkout, `writeups/releases/<x.y.z>/` for a release |
| Branch flow | feature branch → squash-merged pull request into `staging`; a release branch such as `release-0.2.0` → one squash-merged pull request `chore: prepare release <x.y.z>` into `staging` → a merge-commit pull request `chore: release countersign <x.y.z>` into `main` ([docs/release.md](../docs/release.md#cutting-a-release)) |
| Validator and index commands | `swift scripts/release-index.swift` regenerates `releases/index.json`, `swift scripts/release-index.swift --check` verifies the notes and the index |
| What CI generates from release notes | the `release-index` check on every pull request; on a pushed `v*` tag, `.github/workflows/release.yml` creates the GitHub release and appends an "Install this version" section after the body, so a note never carries install steps |
| Who reads the notes | people running Countersign, on the GitHub release page |
| Entry format and field limits | [`releases/README.md`](../releases/README.md): frontmatter fields and limits, the body's section order, `testedWith`, tone; `scripts/release-index.swift` enforces them |
| Paths whose changes never get an entry | `Tests/**`, `.github/**`, `.claude/**`, `.codex/**`, `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `docs/design/**`, and the gate, hook and test scripts under `scripts/`; no released note has carried a tooling, CI or agent-file entry |
| Where the notes are rendered and which fields readers see | the GitHub release: `title` as its title, the body verbatim plus the workflow's install footer; the app's update check reads only `version` from `releases/index.json` |
| Jargon banned from reader-facing text | Swift type, file and function names (`PanelController`, `HookRunner`) and internal terms (lease, ticket, display watch); config keys, commands and UI labels a reader uses are fine |
| Commit type for release notes | `docs(release): add <x.y.z> notes`, committing the note and the regenerated `releases/index.json` together |
| Version bump convention | `CountersignVersion.current` in `Sources/ApprovalCore/CountersignVersion.swift` and the version `CountersignVersionTests` expects, in one `chore: bump the version to <x.y.z>` commit |
| Does the repo tag releases? | yes: the maintainer tags `main`'s release merge commit `v<x.y.z>` and pushes the tag, which starts `release.yml` |
