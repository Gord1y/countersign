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

## feature-pr-description

| Fact | Countersign |
| --- | --- |
| PR description contract (a doc the description must follow, if any) | [`.github/pull_request_template.md`](../.github/pull_request_template.md): a Summary (what and why) and its checklist; the squash commit's body is empty, so the description never becomes history ([CONTRIBUTING.md](../CONTRIBUTING.md#branches-and-pull-requests)) |
| Branch flow and the default base branch for a feature PR | base `staging`; one task per pull request, squash-merged; `main` moves only when a release is cut |
| Paths whose change widens a PR's blast radius (for example middleware, auth, shared UI) | the hook path (`Sources/countersign/HookRunner.swift` and what it calls), the host adapters (`Sources/ApprovalCore/*Adapter.swift`), anything that writes an agent's hook file or `config.json` (`HostWiring`, `ConfigEdit`, `ConfigFileStore`, `RuleFileWriter`), `RuleEvaluator`, the idle gate and queue (`ActivityGate`, `SystemActivity`, `TicketQueue`, `DisplayLease`), `scripts/install.sh`, `scripts/git-hooks/**`, `.github/workflows/**` |
| Where uncommitted drafts go | `writeups/changes/<date>-<branch>/` in the main checkout (gitignored) |
| Allowed PR title types | a Conventional Commit, the types `scripts/git-hooks/commit-msg` accepts: `build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`, `style`, `test`; the `title` check runs that hook on it |
| Release index command, if any | `swift scripts/release-index.swift` (regenerate) and `--check` (verify) |

## promotion-pr-description

| Fact | Countersign |
| --- | --- |
| Promotion PR contract (a doc the description must follow, if any) | [docs/release.md](../docs/release.md#cutting-a-release) steps 3 to 5; the release note `releases/release-<x.y.z>.md` is what readers get, so the description summarises it rather than repeating it |
| Branch flow | release branch → `chore: prepare release <x.y.z>` into `staging` (squash) → `chore: release countersign <x.y.z>` from `staging` into `main` (merge commit) |
| Title convention for promotion PRs | `chore: prepare release <x.y.z>` into `staging`, `chore: release countersign <x.y.z>` into `main` |
| Does the repo tag releases? | yes: `v<x.y.z>` on `main`'s new merge commit, pushed by the maintainer; a pushed `v*` tag can never be moved or deleted |
| CI checks that run only on promotion PRs | none: every pull request runs `gates`, `commits`, `release-index`, `lint` and `title`; `release.yml` runs only on the pushed tag |
| Branch protection on the target branch | `main`: pull request only, no approving review required, merge commit only, the five checks above, no up-to-date requirement; `staging`: the same but squash only and up to date; committed in `.github/rulesets/`, applied and checked with `scripts/rulesets.sh` ([docs/tooling.md](../docs/tooling.md#branches-and-rulesets)) |
| Where uncommitted drafts go | `writeups/releases/<x.y.z>/` (`promotion-staging.md`, `promotion-main.md`) |

## thorough-diff-review

| Fact | Countersign |
| --- | --- |
| Review checklist file | [docs/review-checklist.md](../docs/review-checklist.md) |
| Convention docs or skills to read for each touched area | `.claude/rules/core.md` (`Sources/ApprovalCore`, `Tests`), `.claude/rules/panel.md` (`Sources/countersign`), `.claude/rules/tooling.md` (`scripts`, `.github`, `.claude`, `Package.swift`, `.swift-format`), and the matching `docs/design/<topic>.md` ([index](../docs/design/README.md)) |
| Architecture rules and the tool that enforces them | `ApprovalCore` never imports AppKit or SwiftUI and every type in it has `ApprovalCoreTests` coverage; the `hook` path never writes stderr or exits non-zero; zero comments; no `!`, `try!`, `as!`, implicitly unwrapped optionals or public `Any`. `scripts/check-lint.sh` enforces the comment and unwrap rules (`swift format lint --strict`); the import boundary and the hook contract are enforced by review, which grades either as a Blocker ([docs/review-checklist.md](../docs/review-checklist.md)) |
| Shared utilities to reuse before writing new ones | in `ApprovalCore`: `AppPaths` (every file location), `HomePath`, `ConfigEdit` and `ConfigFileStore` (config writes), `CommandPattern` and `ShellCommandSegments` (command matching), `DurationText` and `PreferenceRules` (times and limits), `JSONValue`, `TicketQueue`; in `Sources/countersign`: the button styles and `KeyHint` in `PanelStyle.swift`, and `SettingsSection` |
| The full check command | `swift format format --in-place --recursive Package.swift Sources Tests && scripts/check.sh` |
| Unit test command | `swift test` (`scripts/check-test.sh`); add `--disable-sandbox` when running inside an agent's sandbox |
| e2e command and when it's required | none automated; on-screen behaviour (keyboard, focus, the idle gate, real agents) is checked by hand on an installed build, and layouts offscreen with `countersign snapshot` |
| Translation check and generate commands, if the repo has translations | none: Countersign is English only |

## qa-tester

| Fact | Countersign |
| --- | --- |
| The surfaces, and how to reach each | the CLI (`countersign --help`), the approval panel (a real agent request, or `countersign test-panel [command\|question\|plan\|context]`), the Settings window (`countersign settings`), the menu-bar app (`~/Applications/Countersign.app`), corner cards (Settings ▸ Panels has test buttons), and offscreen PNGs (`countersign snapshot <fixture> --host <host>`) |
| Which port or process serves which checkout | no server; the installed build is `~/.local/bin/countersign` plus `~/Applications/Countersign.app`, from `scripts/install.sh && scripts/build-app.sh` in the checkout under test; the maintainer quits the app before each reinstall |
| The local QA account (email and local-only password, committed) and how to create it when it is missing | none: Countersign has no accounts |
| How to sign in (form, token endpoint, MFA) | nothing to sign in to |
| Smoke checks per surface | `countersign doctor` (every line `ok` or `info`), `countersign status`, a `test-panel` of each kind, Settings opens on every pane, the menu-bar icon shows its menu, and `countersign snapshot` of `claude-edit.json` in both appearances |
| How to create test data | config rules and other writes prefixed `qa-` and removed afterwards (the config file is `~/.config/countersign/config.json`; back it up first); request payloads come from `Tests/ApprovalCoreTests/Fixtures`; ask "ready?" before anything that puts a panel on screen |
| Where writeups go | `writeups/changes/<date>-<branch>/qa/` |

## walkthrough

| Fact | Countersign |
| --- | --- |
| Where drafts and walkthroughs go | `writeups/changes/<date>-<branch>/walkthrough.md`; a release's `writeups/releases/<x.y.z>/walkthrough.html` |
| How to reach the product, and how to sign in | install with `scripts/install.sh && scripts/build-app.sh`, then the surfaces listed under qa-tester; no sign-in |
| Where release notes live, and who reads them | `releases/release-<x.y.z>.md`, read by people running Countersign on the GitHub release page |
| The brand look to copy | the mark and the one accent colour in [docs/design/icon.md](../docs/design/icon.md) and "Countersign's mark and one accent" in [docs/design/panel.md](../docs/design/panel.md); screenshots in `docs/images/` |
| Words banned from customer-facing text | as for release notes: Swift type, file and function names and internal terms (lease, ticket, display watch) |

## orchestrate

| Fact | Countersign |
| --- | --- |
| When a run ends with a walkthrough: `always`, `when UI changed` or `off` | `when UI changed` |
| The surfaces the product has, and how to reach each | as under qa-tester; builders never put a window on screen and check layouts with `countersign snapshot` only |

## codebase-research

| Fact | Countersign |
| --- | --- |
| Sibling repos research may read, with their absolute paths | none needed: Countersign is self-contained. The shared agent setup is `Gord1y/countersign-skills`, a separate repo |
| Architecture rules (layers, boundaries) and the tool that enforces them | as under thorough-diff-review |
| Docs and skills to read first, per area | `CLAUDE.md`, then the area's `.claude/rules/*.md` and `docs/design/<topic>.md` ([index](../docs/design/README.md)); user-facing behaviour in `docs/*.md` |

## pr-review-triage

| Fact | Countersign |
| --- | --- |
| The review workflow, and who posts the formal review and the tracking comment | none: there is no automated review and the rulesets require no approval; the maintainer reviews locally ([docs/review-checklist.md](../docs/review-checklist.md)) and reviews outside contributors' pull requests on GitHub |
| The severity scale, and what is never reported | 🔴 Blocker (safety contract or hard rule; requests changes), 🟠 Major, 🟡 Minor, 🔵 Nit; unverified findings are questions, never invented ([docs/review-checklist.md](../docs/review-checklist.md#severity)) |
| How to serve the PR head for a browser pass | no browser surface; build the PR head in a worktree and install it (`scripts/install.sh && scripts/build-app.sh`) after the maintainer quits the app |
| Git commands the repo denies, so the person lands fixes themselves | `.claude/settings.json` denies force pushes, `git push --mirror` and `--delete`, `git reset --hard`, `git clean`, `git rebase`, `git filter-branch`, `git update-ref -d`, `git checkout -- …` and `git restore .`; no rule allows any other push |
| Where uncommitted drafts go | `writeups/reviews/pr-<n>/` |

## writeups-cleanup

| Fact | Countersign |
| --- | --- |
| Where drafts go | `writeups/` in the main checkout |
| The ref that holds what has been released | `origin/main`, at the newest `v*` tag |
| How releases are tagged | `v<x.y.z>` on `main`'s release merge commit, pushed by the maintainer |

## how-it-works

| Fact | Countersign |
| --- | --- |
| Docs and skills to read first, per area | `CLAUDE.md` "Rules by area", then the area's `docs/design/<topic>.md` ([index](../docs/design/README.md)) |

## impact-check

| Fact | Countersign |
| --- | --- |
| Where to run a throwaway proof script | a Swift file under `$TMPDIR`, run with `swift <file>`; a proof that needs `ApprovalCore` goes in a scratch test in a throwaway worktree under `.claude/worktrees/`, never committed |

## i18n-translate

| Fact | Countersign |
| --- | --- |
| Source locale and its message folder | none: Countersign is English only and has no translation catalogs ([ROADMAP.md](../ROADMAP.md) lists localization) |
| Target locales | none |
| Product register (tone, formality, who the reader is) | plain, direct English for developers running coding agents |
| Glossary file (never-translate terms and per-language rules) | none |
| Command that lists changed keys | none |
| Translation check command | none |
