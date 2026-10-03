# Releasing

This page explains how a Countersign release is built, published and installed: the files a
release ships, the curl installer, why nothing is notarized, the release workflow and the steps to
cut one. Read it when you cut a release, or when you change the installer, the packaging script or
the release workflow.

A release is a git tag, `v<x.y.z>`, on a commit of `main`. Pushing the tag triggers
`.github/workflows/release.yml`, which builds the artifacts below and publishes them as a GitHub
release.

## The artifacts

`scripts/package-release.sh <version>` builds four files into `.build/release-artifacts/`:

| File | What it is |
| --- | --- |
| `countersign-<version>-macos.tar.gz` | The release archive, named for the version. |
| `countersign-<version>-macos.tar.gz.sha256` | Its checksum, in `shasum -a 256` format. |
| `countersign-macos.tar.gz` | The same archive under a version-free name, for `install.sh` and GitHub's `releases/latest/download/` alias. |
| `countersign-macos.tar.gz.sha256` | Its checksum, naming the version-free file. |

The archive's single top-level folder, `countersign-<version>/`, holds `countersign` (a universal
`arm64`/`x86_64` binary, built by `scripts/build-app.sh --universal`; see [design/app.md](design/app.md) for the
non-universal, host-architecture build that flag skips), `Countersign.app`, `LICENSE` and
`README.md`. `package-release.sh` refuses to run unless `<version>` matches what the freshly built
binary's `--version` prints, ad-hoc signs the standalone `countersign` copy the same way
`build-app.sh` already signs the app (see [design/app.md](design/app.md#why-ad-hoc-signing) for why ad-hoc and
not a real identity), and checks the result with `file` (both architectures must be present in the
universal binary) and `codesign --verify --strict` (on the app bundle) before writing the tarballs.
Taring runs with `COPYFILE_DISABLE=1`, because macOS `tar` otherwise ships each signed file's
resource fork alongside it as a `._<name>` AppleDouble entry, which nobody extracting the archive
wants.

## The curl installer

```sh
curl -fsSL https://raw.githubusercontent.com/Gord1y/countersign/main/install.sh | sh
```

`install.sh`, at the repository root, downloads `countersign-macos.tar.gz` and its `.sha256` from
`${COUNTERSIGN_BASE_URL:-https://github.com/Gord1y/countersign/releases/latest/download}` into a
temporary directory, verifies the download with `shasum -a 256 -c`, and on success installs the
CLI to `$HOME/.local/bin/countersign` (mode 755, written under a temporary name and renamed into
place so a running instance is never half-written). It never uses `sudo`, refuses to run on
anything older than macOS 14, and prints a hint to add `$HOME/.local/bin` to `PATH` when it isn't
already there.

### Whether the app gets installed

The CLI alone is fully usable: `countersign setup` and `countersign settings` open the same
Settings window a bare binary would, and `pause`, `resume`, `snooze` and `status` cover the
menu-bar app's toggles. So the installer only installs `$HOME/Applications/Countersign.app` when
it has reason to:

- `COUNTERSIGN_APP=1` installs or updates the app, no question asked.
- `COUNTERSIGN_APP=0` never touches `$HOME/Applications/Countersign.app`. An existing app is left
  exactly as it is; a missing one stays missing, with a line explaining how to add it later.
  Anything else in `COUNTERSIGN_APP` (neither empty, `0` nor `1`) is rejected with a non-zero exit
  and a message on stderr, before any download starts.
- Left unset, an already-installed app is updated without asking, so the app and the CLI never
  drift apart. With no app installed yet, the installer asks, reading the answer from `/dev/tty`
  rather than its own stdin, since `curl | sh` gives the script's stdin to the piped script itself,
  not to a terminal. Empty, `y` or `yes` (any case) installs the app; `n` or `no` (any case) skips
  it; anything else asks again, and reaching the end of input without an answer counts as the
  default and installs the app. When no terminal is available to ask on — `/dev/tty` can't be
  opened for both reading and writing — the installer installs the app rather than block forever
  waiting for an answer that can never come.

`COUNTERSIGN_APP` takes effect before any of `COUNTERSIGN_BASE_URL` or `COUNTERSIGN_VERSION`
below, and independently of them: whichever release the CLI installs from is also where the app,
if installed, comes from.

### Opening Countersign at the end

Rather than leave you to run `countersign setup` yourself, the installer opens Countersign as its
last step, right after it prints `installed countersign <version>`:

- `COUNTERSIGN_SETUP=1` always opens it; `COUNTERSIGN_SETUP=0` never does, printing
  `next: countersign setup` instead. Anything else in `COUNTERSIGN_SETUP` (neither empty, `0` nor
  `1`) is rejected with a non-zero exit and a message on stderr, before any download starts, the
  same as `COUNTERSIGN_APP`.
- Left unset, the installer asks, reading the answer from `/dev/tty` the same way as the app
  question: `Open Countersign now to set up your agents? [Y/n]`. Empty, `y` or `yes` (any case)
  opens it; `n` or `no` (any case) skips it, printing `next: countersign setup`; anything else asks
  again, and reaching the end of input without an answer counts as the default and opens it. When
  no terminal is available to ask on (the same `/dev/tty` probe described above), it prints
  `next: countersign setup` instead, since there's nobody there to show a window to.
- If `$HOME/Applications/Countersign.app` exists once the install is done, whether installed just
  now or already there and left in place, it runs `open "$app_dir"`: an ordinary launch, which
  starts the menu-bar app and opens its Settings window, and prints
  `opening Countersign to set up your agents`. If `open` itself fails, for example an SSH session
  with a terminal but no GUI login for LaunchServices to hand the app to, that failure doesn't fail
  the install: it's swallowed and `next: countersign setup` is printed instead, the same as when
  nothing is opened at all. Otherwise it starts `$HOME/.local/bin/countersign setup` in the
  background, detached from the installer (stdin from `/dev/null`, output to `/dev/null`,
  backgrounded with `&`) so the installer exits at once rather than wait on the Settings window, and
  prints `opening Countersign Settings to set up your agents`.
- If the app bundle already existed and this run just replaced it while a previous
  `Countersign.app` process was still running (`pgrep -f "$app_dir/Contents/MacOS/countersign"`),
  it also prints
  `Countersign.app is still running the previous version; quit it from the menu bar and open it again`.
  The open still happens either way: the running copy simply won't reflect it until it's quit and
  reopened.

`COUNTERSIGN_BASE_URL` exists so the installer can be pointed at a mirror or, for testing, a local
directory: curl accepts `file://` URLs, and `scripts/test-install.sh` uses exactly that to run the
installer against a fake release without touching the network. Set it to override where the
tarball and checksum come from; leave it unset to install the latest published release.

The pty cases in `scripts/test-install.sh` run `install.sh` under `script` to give it a terminal.
`script` closes the pty as soon as its child exits, which can hang up the background
`countersign setup` (or `open`) the installer starts before `nohup` has taken effect. To give that
background process time, `run_install_pty` runs the installer through a wrapper that keeps the
session open for 0.2 seconds after the installer exits. A real terminal stays open long after the
installer finishes, so this is a property of the test harness, not of `install.sh`. For the same
reason, `wait_for_marker` allows up to 20 seconds for the background process to leave its mark: a
full `scripts/check.sh` run loads the machine, and the bound only lengthens a failing run.

`COUNTERSIGN_VERSION` pins the install to one tagged release instead of the latest one: set it to
`x.y.z` or `vx.y.z` (anything else is rejected with a non-zero exit and a message on stderr) and
`install.sh` downloads `countersign-<x.y.z>-macos.tar.gz` and its `.sha256` from
`https://github.com/Gord1y/countersign/releases/download/v<x.y.z>` instead of the
`releases/latest/download/` alias, verifying the checksum exactly as the latest path does. When
both variables are set, `COUNTERSIGN_BASE_URL` wins for where the files are fetched from, but the
file names are still the versioned ones `COUNTERSIGN_VERSION` names — this is how
`scripts/test-install.sh` exercises the pinned path against a local fixture. With
`COUNTERSIGN_VERSION` unset, none of this applies. The installer always prints the
version it installed, right before it opens Countersign or prints "next: countersign setup" as
described above.

## Why ad-hoc signing and no notarization

Nothing here is notarized, and the CLI and app are both only ad-hoc signed (`codesign --force
--sign -`, no Developer ID). A `curl | sh` install, and the tarball `install.sh` extracts, never
passes through a browser download, so nothing sets the `com.apple.quarantine` extended attribute
on the files it writes. Gatekeeper only ever assesses a quarantined file, so it never assesses
these regardless of who signed them. Ad-hoc signing exists for what *does* check a signature
locally — `SMAppService`, which the menu-bar companion's Launch at Login uses; see
[design/app.md](design/app.md#why-ad-hoc-signing) — not for Gatekeeper.

## The release workflow

`.github/workflows/release.yml` triggers only on a pushed `v*` tag. It derives the version by
stripping the leading `v` (kept in an environment variable throughout, never interpolated
directly into a `run:` script, so a crafted tag name can't inject shell syntax), then:

1. Fails unless `releases/release-<version>.md` exists and
   `swift scripts/release-index.swift --check` passes, so a release can't ship without a note or
   with a stale index.
2. Runs `scripts/package-release.sh <version>`.
3. Creates the GitHub release with `gh release create "v<version>"`, titled from the note's
   `title` field and bodied with the note's body, frontmatter stripped, verbatim — the same rule
   [releases/README.md](../releases/README.md) states for the body reaching GitHub, plus a footer
   the workflow appends after it: an "Install this version" heading, the curl command from
   [above](#the-curl-installer) with `COUNTERSIGN_VERSION` filled in to that release's own
   version, and a line noting that Homebrew installs the latest version only. A release note never
   repeats this command itself; the workflow is what adds it, for every release, so it can't go
   stale. The four artifacts above are attached.

`GH_TOKEN` is scoped to `${{ github.token }}` and only set in the release-creation step's own
`env`, and the job's `permissions: contents: write` is likewise scoped to that one job, on top of
the workflow's `permissions: {}` default.

## Cutting a release

1. Write `releases/release-<x.y.z>.md` with the [release-notes skill](../.claude/skills/release-notes/SKILL.md).
2. Bump `CountersignVersion.current` in `Sources/ApprovalCore/CountersignVersion.swift` to
   `<x.y.z>`, and the version `CountersignVersionTests` expects, in the same commit; the gate fails
   until both match.
3. Open a pull request with both into `staging`, titled `chore: prepare release <x.y.z>`, and
   squash-merge it once its checks pass and the Claude review approves.
4. Open a pull request from `staging` into `main`, titled `chore: release countersign <x.y.z>`,
   and merge it with a merge commit once its checks pass and the Claude review approves.
5. Tag `main`'s new merge commit and push the tag: `git fetch origin`, then
   `git tag v<x.y.z> origin/main` and `git push origin v<x.y.z>`. A pushed `v*` tag can never be
   moved or deleted, so check `git log -1 origin/main` first.
6. Once `release.yml` has published the release, update the tap formula
   (`Gord1y/homebrew-tap`, formula `countersign`) to point at the new tarball: set `url` to
   `https://github.com/Gord1y/countersign/releases/download/v<x.y.z>/countersign-<x.y.z>-macos.tar.gz`
   and `sha256` to what `curl -fsSL <url> | shasum -a 256` prints for that URL, then commit and push
   the tap. The formula installs this tarball as-is: no bottle, no `brew test-bot` pull request and
   no `brew pr-pull` step.

The pushed tag is what starts the release workflow; merging into `main` on its own does not.
