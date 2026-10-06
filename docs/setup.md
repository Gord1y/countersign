# Connect your agents

What connecting Countersign to Claude Code, Codex, Cursor and Antigravity changes in each agent's
config, how to do it from the Settings window or the terminal, and how to undo it. Read it when you
first install Countersign, start using another agent, or want to know exactly what was written to
your files.

An agent only asks Countersign when its own hook config has an entry that runs
`countersign hook`. Setup adds, updates or removes that one entry per agent, and shows you the
exact change before it writes anything.

## Install options

Both Homebrew and the curl installer install the prebuilt release; neither needs Xcode. Don't open
a release archive you downloaded in a browser instead: macOS quarantines it and refuses the ad-hoc
signed app, since only a browser download sets the quarantine flag Gatekeeper checks.

The curl installer asks whether to also install the optional [menu-bar app](menu-bar-app.md)
(default yes); the CLI alone is fully usable, so put `COUNTERSIGN_APP=0` before `sh` to skip the
app, or `COUNTERSIGN_APP=1` to install it without being asked. It then asks whether to open
Countersign so you can set up your agents (default yes); put `COUNTERSIGN_SETUP=0` before `sh` to
skip that without asking, or `COUNTERSIGN_SETUP=1` to open it without asking. For an older release, put
`COUNTERSIGN_VERSION=<x.y.z>` before `sh` in the curl command; Homebrew always installs the latest.
The full installer behaviour, including what each variable rejects and how it picks a default
without a terminal to ask in: [release.md](release.md#the-curl-installer).

To build from source instead (Xcode 26 or later), clone the repository and run
`scripts/install.sh`.

## From the Settings window

The curl installer asks at the end of a fresh install and opens this window for you unless you say
no (see [release.md](release.md#the-curl-installer)); otherwise open Countersign.app from the Finder,
Spotlight or Launchpad, or run `countersign setup`. Setup opens a small window with three steps:

1. **Wire your agents.** Each agent Countersign found gets a row. **Wire** writes the hook into
   every agent that is Not wired or Needs an update, and each row's change is behind its
   **Show the change** line. Pressing **Wire** is the confirmation, so there is no popup. An agent
   that can't be set up is shown with its reason and left alone.
2. **Try it.** A test panel shows on its own once every file was written. Nothing you do in it
   reaches an agent, and the step lists its keys.
3. **All set.** A summary, and **Open Settings** or **Done**.

If a file can't be written, the window stays on step 1 and offers **Try Again**; Countersign leaves
that file unchanged. Running setup when every agent is wired opens on **All set**.

`countersign settings` opens the full window, and so does **Open Settings** in the setup window.
If you installed the CLI only, without the [menu-bar app](menu-bar-app.md), both still open from
the terminal. In the full window, under **Agents**, each agent gets a row with one of these
statuses:

| Status | What it means | What to do |
| --- | --- | --- |
| Not installed | Countersign found no data directory for this agent | Nothing, until you install the agent |
| Not wired | The agent's hook file has no Countersign entry | **Wire** |
| Wired | The entry is there and up to date | Nothing, or **Remove** to take it out |
| Needs an update | The entry points at another copy of `countersign`, runs it with anything but `hook --host <agent>` (`hook --host <agent> --event waiting` for the Stop entry), lacks a field setup writes, or lacks the Stop entry of waiting-agent notices while they are on | **Update** |
| Can't be set up | The file can't be read, isn't valid JSON or has a shape setup can't edit, or the running binary isn't named `countersign` | Fix what the row names; setup won't write until then |

Each button first shows the exact diff it would write, in a popup with the button's name and
**Cancel**; nothing is written until you confirm. When your [config file](configuration.md) sets values for one agent,
under `hosts`, that agent's row lists them too, with a link to open the file. Once a row is Wired,
it may show one more line below it: a next step for Codex (see below), or a permanent good-to-know
line for Cursor or Antigravity (see [agents.md](agents.md)).

With a Homebrew install, the window's **App** group also offers to copy Countersign.app into
`~/Applications`, so Spotlight and Launchpad find it. The menu-bar app keeps it current at
Homebrew's version after `brew upgrade`.

## From the terminal

```sh
countersign setup --cli [--yes] [--uninstall] [--host claude|codex|cursor|antigravity]
```

`setup --cli` stays the terminal flow; plain `setup` opens the window above.

For each agent it finds, setup prints the file's path and a diff of the change, then asks
`Apply? [y/N]`. `--yes` applies without asking. Without a terminal to ask in, and without `--yes`,
it only prints the diffs and applies nothing. `--host` limits the run to one agent. A file with
nothing to change prints `already up to date`, so running setup twice is safe. When it finds no
agent at all, it says so. It exits 1 when a file failed or a change was not applied (you answered N, or there was no
terminal and no `--yes`), and 0 otherwise. `--yes`, `--uninstall` and `--host` work only together
with `--cli`.

## What it changes

| Agent | File | Set up when | The entry |
| --- | --- | --- | --- |
| Claude Code | `$CLAUDE_CONFIG_DIR/settings.json`, else `~/.claude/settings.json` | that directory exists | under `hooks.PermissionRequest` |
| Codex | `$CODEX_HOME/hooks.json`, else `~/.codex/hooks.json` | that directory exists | under `hooks.PermissionRequest` |
| Cursor | `~/.cursor/hooks.json` | `~/.cursor` exists | under `hooks.beforeShellExecution` and `hooks.beforeMCPExecution` |
| Antigravity | `~/.gemini/config/hooks.json` | `~/.gemini/antigravity-cli`, `~/.gemini/antigravity` or `~/.gemini/antigravity-ide` exists | a named hook `countersign` with one `PreToolUse` entry |

An empty environment variable counts as unset. A missing file is created. The `agy` CLI, the
Antigravity app and the Antigravity IDE all read the one Antigravity file, so one entry covers all
three. Claude Code's entry looks like this:

```json
"hooks": {
  "PermissionRequest": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "/opt/homebrew/bin/countersign hook --host claude",
          "timeout": 3600
        }
      ]
    }
  ]
}
```

Every agent's entry runs `countersign hook --host <agent>` with a 3600-second timeout, so a request
can wait up to an hour for you. The hook takes nothing else: every setting lives in the
[config file](configuration.md), and connecting or removing an agent never touches it. An entry of
Countersign's with any other arguments is rewritten to this command. The exact shape for each
agent is in [design/setup.md](design/setup.md).

Turning on Context checkpoints in the Settings window adds a second entry to Claude Code's file,
under `hooks.UserPromptSubmit`. It runs the same command and is marked `"async": true`, so your
prompts never wait for it. Remove takes out both entries.

[Waiting-agent notices](agents.md#the-waiting-agent-notice) are on by default, so setup's diff also
includes a second entry for each agent, for the end of a turn (`hooks.Stop`; `hooks.stop` for
Cursor; the hook `countersign-waiting` for Antigravity). An agent wired before notices were on by
default shows Needs an update until you press Update or run setup again. Turning the notices off in
Settings ▸ Panels removes those entries and setup then leaves them out.

Setup touches only its own entry. Everything else in the file, other hooks, key order,
indentation, line endings, stays exactly as it was. Before it changes a file that already exists,
it saves a copy next to it, `<file>.countersign-<yyyyMMdd-HHmmss>.bak`, and prints where. Only the
newest three copies of each file are kept; saving a fourth removes the oldest. A file
that isn't valid JSON, including JSON with comments or trailing commas, is reported and left alone.
Antigravity ignores its whole hooks file when any entry in it is invalid, so setup writes its entry
in one exact shape, and replaces a `countersign` hook it finds in any other shape.

The command names a path that survives upgrades: Homebrew's `$(brew --prefix)/bin/countersign`
rather than the versioned folder it installs into, and `~/.local/bin/countersign` when the curl
installer put both that CLI and Countersign.app on your Mac, whichever of the two runs setup. If
you move the binary, run setup again; only the path in the entry changes.

Switching between the curl installer and Homebrew leaves the old copy in place, and the two then
update separately. Setup and the Settings window warn when more than one copy is installed; Settings
asks which one you want to keep and shows the steps for it, and Countersign never removes one for
you; see
[troubleshooting.md](troubleshooting.md#two-copies-of-countersign-are-installed).

## Undo it

Click **Remove** in the window, or run `countersign setup --cli --uninstall`, with `--host` for a
single agent. Only Countersign's entries are removed. A file setup added to is usually back to its
original bytes; a Cursor file keeps its `version` and `hooks` keys. Uninstall never touches
Countersign's own config file. The newest three backups of each file stay where setup saved them,
so copying one over its file restores that file exactly as it was before that change.

Remove the entries this way before you uninstall Countersign itself, so no agent is left with a
hook that points at a missing file.

## Codex asks you to trust the hook

Codex asks you to trust a hook it hasn't seen before, and only the terminal can record that trust —
the Codex desktop app shares the same `~/.codex`, but its own `/hooks` can't write the trust record.
Until Codex has trusted its hook, the Codex row in Settings, and `countersign setup --cli` and
`countersign doctor`, all say:

```text
Open Codex in a terminal, not the desktop app, run /hooks and trust Countersign's hook. Codex
sessions already open pick it up after /hooks or in a new session.
```

Do that once. Sessions you already have open pick up the trust as soon as you run `/hooks`, without
needing to restart them. Countersign reads the trust Codex stores in `config.toml`, next to its
`hooks.json`, so the step goes away by itself; `countersign doctor` then says
`ok codex: Codex trusts Countersign's hook`. Wiring or updating Codex's entry again (an upgrade, a
new install path) brings the step back, since Codex asks about the new entry too.

Adding another hook to Codex's `hooks.json` after Countersign's, or for another event, never brings
it back. Adding one before Countersign's, or removing one that came before it, moves Countersign's
entry, and Codex asks again; the step then starts with the reason:

```text
Codex asks again because another hook was added before Countersign's.
Codex asks again because a hook before Countersign's was removed.
```

When Countersign can't tell whether Codex trusts its hook, for example when `config.toml` holds
something it doesn't understand or the entry moved before Countersign ever saw it trusted, the row
also offers **Mark as done**: click it once you've trusted the hook, and the step goes away. The
same goes for an entry wired while `config.toml` couldn't be read: the step then never clears by
itself, since Countersign has nothing to compare against. If Codex's panel never appears, this is
the first thing to check.

Cursor and Antigravity have no trust step, but each has one permanent thing worth knowing once it's
wired — see [agents.md](agents.md#cursor) and [agents.md](agents.md#antigravity).
