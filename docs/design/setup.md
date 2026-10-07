# Setup internals

How `countersign setup` and the Agents group of the settings window edit the agents' hook files:
the exact entries written, how our entry is recognised, why files are edited byte for byte,
backups, which executable path ends up in the command, and how a second installed copy of
Countersign is found. Read it before changing `HookSetup`, `HookCommand`, `CursorHookSetup`,
`AntigravityHookSetup`, `SetupRun`, `HostWiring`, `StableExecutablePath`, `InstalledCopies`,
`AgentFollowUps`, `CodexHookTrust`, `CodexTrustVerdict` or the window's Agents group. What setup does, from a user's side, is in [../setup.md](../setup.md).

## The entries setup writes

Which file each host uses, and when a host counts as installed, is in "What it changes" in
[../setup.md](../setup.md) (`HookConfigLocation`). Claude Code's entry sits among the file's other
top-level keys:

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

Codex's `hooks.json` gets the same shape with `--host codex` and one more field,
`"statusMessage": "Waiting for the approval panel"`.

### The Context checkpoints entry

While Context checkpoints are on, which is the default, Claude Code's file gets a second entry,
under `hooks.UserPromptSubmit`, in one group without a `matcher` (the event has none):

```json
"hooks": {
  "UserPromptSubmit": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "/opt/homebrew/bin/countersign hook --host claude",
          "async": true,
          "timeout": 3600
        }
      ]
    }
  ]
}
```

The command is the same string as the `PermissionRequest` entry's; the hook tells the two events
apart by `hook_event_name` in its input. Three facts decide the shape:

- `async: true` keeps the prompt from waiting. Claude Code runs the hook in the background,
  applies no timeout to it once backgrounded, and delivers its `additionalContext` at Claude's
  next request (verified live on Claude Code 2.1.278). Without `async`, a `UserPromptSubmit` hook
  that times out blocks the prompt, which Claude Code documents.
- `timeout: 3600` covers a Claude Code that ignores `async`: the prompt then waits for the panel
  instead of being blocked at the 30 second default.
- Recognition is the same as for the `PermissionRequest` entry (see "How our entry is
  recognised"), searched under `hooks.UserPromptSubmit`. Anyone else's hooks under the event are
  never touched.

`ContextHookSetup.install` adds the entry, or refreshes it when one of ours already exists under
the event: the `command`, `async` and `timeout` are set with the same rules as "Install" (a value
that is already right, however it is spelled, is left as written). The Settings toggle
(`ContextHookRun`) calls it when the feature is turned on, and `HookSetup.install` calls it for
Claude Code when `addsContextEntry` is true, which is what Wire, Update and `countersign setup` pass
while checkpoints are on (see "The context entry follows the setting" below). With
`addsContextEntry` false, `HookSetup.install` only refreshes an existing `UserPromptSubmit` entry
of ours and never adds one, so a person who has turned the feature off never gets an entry, and one
who has it on never keeps a stale one. A stale entry shows as "Needs an update" in the Agents rows.

### The context entry follows the setting

Setup and Update add Claude Code's async `UserPromptSubmit` context entry while checkpoints are on,
which is the default, and only refresh it while they are off. `HookSetup.install` takes
`addsContextEntry` beside `addsWaitingEntry`, and `HostWiring.status` reports a missing entry as an
update (`HostWiringUpdate.addsContextEntry`) only for Claude Code. `countersign setup` and Settings
pass the resolved `contextCheckpoints.enabled`; `Doctor` does the same so its wiring check agrees.
The Settings toggle still adds and removes the entry itself (`ContextHookRun`).

Why: checkpoints became on by default in 0.2.0, and before this only the toggle wrote the entry,
so a default-on setting would have had no hook behind it, and everyone who never touched the
toggle would have been "on" with doctor warning.

### The waiting-agent entry

Waiting-agent notices add one more entry for Claude Code, under `hooks.Stop`, in one group without
a `matcher`:

```json
"Stop": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "<exe> hook --host claude --event waiting",
        "async": true,
        "timeout": 30
      }
    ]
  }
]
```

- `async` so the end of a turn never waits for Countersign. 30 seconds because the hook only
  records the turn end and exits.
- The command says what it is with `--event waiting` (`HookOptions.event`, `HookCommand` with its
  `event` parameter) instead of relying on the payload's `hook_event_name`: Antigravity's payloads
  have no event-name field, so every host's waiting entry names itself on its own command line.
  `HookCommand.isCommand` compares the event too, so the approval and the waiting command of one
  host never match each other.
- Notices are on by default, so setup adds it. `HookSetup.install` takes `addsWaitingEntry`, with
  no default: every caller passes the resolved `waitingNotices` setting (`SetupRun`,
  `HostWiring.status`, the Settings model, `countersign setup`, Doctor). When true it calls
  `WaitingHookSetup.install`, which adds the `Stop` entry or refreshes the one that is there
  (command path, `async`, `timeout`), so Wire, Update and every `countersign setup` put it in the
  same diff as the permission entry. When false it calls `WaitingHookSetup.refresh`, which only
  refreshes an existing entry and never adds or removes one: with notices off, setup leaves a
  leftover entry alone and Doctor reports it. `HostWiring.status` runs the same install, so an
  agent wired before 0.2.0 reads "Needs an update" (`HostWiringUpdate.addsWaitingEntry`, "Adds the
  Stop entry for waiting-agent notices") until setup or Update applies it. Turning the Settings
  toggle off removes the entries through `WaitingHookRun` (preview, then apply with a backup, over
  the wired hosts in `WaitingHookSetup.supportedHosts`) and writes `waitingNotices: false`, which
  is what keeps setup from adding them again; turning it on adds them the same way.
  `countersign setup --remove` removes it too, and someone else's `Stop` hooks stay untouched.
- Until the notice runtime exists, `hook --event waiting` logs `waiting: <host> not handled yet`
  and exits 0.

Cursor's `hooks.json` has no groups and no `type`: each event holds a plain list of entries, and
ours goes under both events Countersign answers, shell commands and MCP tools:

```json
{
  "version": 1,
  "hooks": {
    "beforeShellExecution": [
      {
        "command": "/opt/homebrew/bin/countersign hook --host cursor",
        "timeout": 3600
      }
    ],
    "beforeMCPExecution": [
      {
        "command": "/opt/homebrew/bin/countersign hook --host cursor",
        "timeout": 3600
      }
    ]
  }
}
```

Cursor only asks the hook about commands it runs outside its sandbox, and about every MCP call; the
reasons are in "The Cursor adapter" in [hosts.md](hosts.md).

Antigravity's `hooks.json` holds named hooks at the top level, each with its own events. Setup
adds one named `countersign`, in exactly this shape:

```json
{
  "countersign": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/opt/homebrew/bin/countersign hook --host antigravity",
            "timeout": 3600
          }
        ]
      }
    ]
  }
}
```

Antigravity rejects the whole file when any entry in it is invalid, and then runs none of its
hooks, so setup never writes anything but this shape. Antigravity calls the hook before every tool
call; Countersign answers only for commands and MCP tools (see "The Antigravity adapter" in
[hosts.md](hosts.md)).

For the first three hosts the file's directory is the one that was detected; for Antigravity,
`~/.gemini/config/` is created, with the file, when it is missing. A file that holds only
whitespace is treated like a missing one. An empty `CLAUDE_CONFIG_DIR` or `CODEX_HOME` counts as
unset; Cursor and Antigravity have no variable for their directories. When no host is detected,
setup says so and exits 0.

### The waiting entries of Codex, Cursor and Antigravity

The other three hosts are wired the same way as Claude Code: setup adds the entry while notices
are on and only refreshes it while they are off, the toggle adds and removes it through
`WaitingHookRun` (every wired host's file appears in one diff), and `countersign setup --remove`
and `HookSetup.uninstall` remove it. Each shape follows the host's existing Countersign entry, and
each detail that needed a capture lives in one named constant of `WaitingHookSetup`
(`cursorEventName`, `antigravityHookName` and `CodexHookTrust.waitingEventLabel`) so a fix is one
line. The Codex and Cursor captures of 2026-10-01 confirmed `waitingEventLabel` (`stop`) and
`cursorEventName` (`stop`). None of the three has `async`, which only Claude Code has: the hook
exits at once, with a 30 second timeout.

- Codex, `hooks.Stop`, the layout of Claude's entry without `async`: one group with no `matcher`
  and no `statusMessage`, holding `{"type": "command", "command": "<exe> hook --host codex --event
  waiting", "timeout": 30}`.
- Cursor, `hooks.stop`, a plain entry like the others: `{"command": "<exe> hook --host cursor
  --event waiting", "timeout": 30}`. `stop` is never added to `CursorAdapter.events`: setup adds
  every event in that list unconditionally, and the waiting entry depends on the setting.
  `CursorHookSetup.sites`, which
  scans only that list, never sees the `stop` key, so Cursor's own install and uninstall leave the
  entry alone; `WaitingHookSetup` owns it and recognises it with `CursorHookSetup.isCountersignEntry`.
- Antigravity, a second named hook, `countersign-waiting`, with `Stop` as its one event. `Stop` is
  flat: its array holds the handler `{"type": "command", "command": "<exe> hook --host antigravity
  --event waiting", "timeout": 30}` directly, with no `matcher` and no `hooks` group. Only the tool
  events, `PreToolUse` and `PostToolUse`, take the grouped shape; the hooks reference built into
  the Antigravity CLI says so ("Flat (list of handler objects directly)" for `Stop`), and CLI
  1.2.17 rejects a grouped `Stop` with `invalid hook "countersign-waiting": command hook must
  specify 'command'`. An early 0.2.0 build wrote the grouped shape, and because Antigravity rejects
  the whole file, that also silenced the `countersign` approval hook. Antigravity rejects the whole
  file when any entry is invalid, so the entry must keep the exact shape
  `AntigravityHookSetup.flatEntry(inSetupShape:event:)` checks, and anything else under that name,
  the grouped shape included, is replaced on install. A second name is the point: the
  `countersign` hook keeps its one-event shape, and its install, uninstall and doctor code stay
  untouched, where adding `Stop` to it would have broken the rule that the name holds exactly one
  event.

Codex runs a new hook only once the person trusts it, so the `Stop` entry has its own trust record,
`AppPaths.codexWaitingHookTrustFile` (`codex-waiting-hook-trust.json`), the same format as the
approval entry's record with the key `<hooks.json path>:stop:<group>:<hook>`
(`CodexHookTrust.current(hooksFileBytes:hooksFilePath:event:label:)`; the label `stop` is Codex's
snake_case of the event name, confirmed by the record Codex wrote when the entry was trusted). `WaitingHookRun.apply` and `SetupRun` save that
record whenever they write Codex's file and the `Stop` entry exists afterwards, and delete it
otherwise. Nothing persists a learned hash for it: `countersign doctor` judges it from what was
stored at write time, so a change of the stored hash still reads as trusted. Turning the
notices on in Settings for a Codex file that changes adds one sentence to the confirmation: Codex
then asks you to trust the new Stop hook, in `/hooks` in a Codex session.

## How our entry is recognised

Our entry is a hook object whose `type` is `command` and whose `command` has, as its first word,
an executable path named `countersign` and, as its second word, `hook`. A first word in single or
double quotes counts as one word, so a path with spaces is still found. Only
`hooks.PermissionRequest` is searched, and for Claude Code also `hooks.UserPromptSubmit` (see "The
Context checkpoints entry"); an entry of ours under any other event is left alone. Only
those two words count: an entry of ours with anything else after `hook`, another host, no
`--host` or an extra word, is still ours, and install rewrites its command (see "Install").

In Cursor's file, where `type` is optional, an entry with no `type` counts too, and only
`hooks.beforeShellExecution` and `hooks.beforeMCPExecution` are searched.

In Antigravity's file, only the top-level named hook `countersign` is ours, and its entry counts
only when the named hook is in exactly the shape above: one `PreToolUse` event and nothing else,
one group whose only members are `"matcher": "*"` and `hooks`, and one hook object of ours whose
members are `type`, `command` and, optionally, `timeout`, each once. An entry of ours inside
another named hook is someone else's and is left alone.

## Install

Install, when our entry exists anywhere under `hooks.PermissionRequest`, compares the words of its
`command` with `<executable path> hook --host <host>`. When they differ in any way, another path,
another host, a missing `--host` or an extra word, it replaces the whole `command` string with the
canonical one: a hand-written `/Users/x/.local/bin/countersign hook --host claude --verbose`
becomes `/opt/homebrew/bin/countersign hook --host claude`. Words are compared by their values, so
a path in quotes it does not need, extra spaces, or a command spelled with JSON escapes such as
`\/`, is already canonical and left as written. Nothing after `hook` is worth keeping: the hook
takes `--host` and nothing else, refuses any other argument, and reads every setting from the
config file (see "Precedence" in [settings.md](settings.md)). It then sets `timeout` (and for
Codex `statusMessage`) to the values above,
adding the field when it is missing. A `timeout` that is already 3600, however it is spelled
(`3600.0`, `3.6e3`), is left as written. When several entries of ours exist, each one is updated;
none is removed. When there is no entry of ours, install appends a new group
`{ "matcher": "", "hooks": [ ours ] }` to `hooks.PermissionRequest`, creating `hooks` and
`PermissionRequest` when they are missing. No other hook, group, key or event is touched.

For Cursor, the same update applies to every entry of ours under either event (there is no
`statusMessage`). Then each of the two events that holds no entry of ours gets one appended,
`{ "command": ..., "timeout": 3600 }`, creating `hooks` and the event's array when they are
missing, so an entry that sits under only one event is completed rather than duplicated. A missing
file, or a blank one, becomes the whole document shown above. A file without a top-level
`version` gets `"version": 1`, since every Cursor hooks file carries one; an existing `version` is
never changed. Everyone else's entries, under these events or any other, are kept as they are.

For Antigravity, a named hook `countersign` in the shape above gets the same update as the other
hosts' entries: the `command` and `timeout` (there is no `statusMessage`).
A `countersign` named hook in any other shape, such as one with `"enabled": false`, another
`matcher`, a second event or no entry of ours, is replaced whole by the shape above, so a file
setup has touched never holds a named hook Antigravity could reject. A file without the named hook
gets it appended as the last top-level member, and a missing or blank file becomes the whole
document shown above. Every other named hook is kept as it is.

A path that needs quoting for the shell (anything outside letters, digits and `/._-+@%:,=`) is
written in single quotes. Install refuses an executable that is not named `countersign`: its entry
would not be recognised on the next run, and every run would append another one.

## Why minimal-diff editing

People keep hand-written settings: key order that means something to them, their own indentation,
Windows line endings, escaped characters, numbers written the way they like. Parsing the file into
a dictionary and serialising it again would reorder and reformat all of that, and the diff the user
approves would be the whole file instead of the lines that matter.

So setup never re-serialises. `JSONSpanReader` is a small JSON reader that records the byte range
of every value and key in the original file. `JSONSourceDocument` then splices
replacement text into those ranges and leaves every other byte alone: key order, indentation,
spacing, line endings, the trailing newline or its absence, escapes and number spellings. After
each splice the document is parsed again, so every edit is checked to still be valid JSON.

New text copies the file's own style. The indentation unit is the first nesting step found in the
file (two spaces, four spaces, a tab), the newline is `\r\n` when the first line break is one, and
the spacing around the colon comes from the file's first key. A new member or element is placed
after the last one, on its own line with the same indentation when the container spans lines, or
with the same separator when it is written on one line. An empty `{}` or `[]` is expanded one
indentation step deeper than the line it sits on. A new or blank file gets two spaces and `\n`.

A file that is not valid JSON is reported for that file and left untouched; setup carries on with
the other host and exits 1. JSON with comments or trailing commas counts as invalid. So does a
top level that is not an object, a `hooks` that is not an object, or a `PermissionRequest` (for
Cursor, a `beforeShellExecution` or `beforeMCPExecution`) that is not an array. Antigravity's file
has no `hooks` key, so for it only a top level that is not an object counts. The reader stops
at 64 levels of nesting, far beyond any settings file, so hostile input cannot exhaust the stack.

## The terminal flow

For each detected file, setup prints the path and a unified diff of the change (`---`/`+++`
headers, `@@` hunks, three lines of context; a new file is diffed against `/dev/null`), then asks
`Apply? [y/N]`. Only `y` or `yes`, in any case, applies. `--yes` skips the question. When stdin is
not a terminal and `--yes` is absent, setup prints the diffs and applies nothing. A file with
nothing to change prints `<path>: already up to date`, so running setup twice changes nothing the
second time. `SetupRun`, behind this flow and the window's host buttons alike, never reads or
writes Countersign's config file.

The diff reuses `FileDiffBuilder.numberedDiff`, the line diff behind the panel's file cards, and
`UnifiedDiff` only groups its lines into hunks. Carriage returns are not printed.

Setup is not the hook path: it prints errors and exits 1 when any file failed. It exits 0 when
every file was applied, declined or already up to date. An error is one line,
`<path>: error: <message>`: the editor's own errors read as described above (`not valid JSON at
line 3, column 5`, `hooks is not an object`), and a file-system error prints its localized
description, not the whole `NSError` with its user info, which spans several lines.

`--yes`, `--uninstall` and `--host` belong to the terminal flow: without `--cli` they print the
usage and exit 1, so a script written for the terminal never opens a window instead.

The per-host flow lives in `ApprovalCore.SetupRun`, which takes the printing and the question as
closures, so `ApprovalCoreTests` drive it against temporary directories. `SetupCommand` only finds
the hosts, resolves the executable and answers the question from the terminal or `--yes`.

## The setup window

Plain `countersign setup` opens a small window, "Set Up Countersign", 460 pt wide, not resizable,
as tall as its step needs. The installer's last step and the first open of Countersign.app are
meant to open the same window. `setup --cli` keeps the terminal flow, and `countersign settings`
keeps the full window (see "The window"). The window is a `SetupModel`, which owns a
`SettingsModel` and reads its `hostRows`, and a `SetupView`. The write path is the Settings
window's own: `requestHostChange` and `confirmHostChange`, then `refreshFromDisk`. The window adds
no wiring logic of its own.

It has three steps, each short enough to read at a glance. The user chose this layout over one
long page from renders on 2026-10-07. The user asked for no panel they didn't request: a panel
appearing by itself right after Wire reads like a real request.

1. **Wire your agents.** The intro, then one row per agent that is installed: its glyph, name and
   status. A row to wire adds `Countersign adds a hook to <its file>.`, with `~` for the home
   folder, and a collapsed `Show the change (<DiffSummary.text>)` over that row's diff. A row
   that can't be set up shows its reason, which is the status's own text, so no path or reason is
   written into the view. Agents that are not installed are one `Not installed: …` line. The
   footer reads `1 of 3`, with `Not Now` and `Wire <n> Agents` (`Wire <name>` for one).
2. **Try it.** No panel shows on its own. The step says nothing done in a test panel reaches an
   agent, lists the panel's keys as keycaps (the keys line of the retired tour, now
   `KeyHintFlowLayout`, shared by both views) and offers `Show a Test Panel` to the right of that
   text, with `Back` and `Next`.
3. **All set.** Every found agent is wired. The rows again, the Codex next step when there is one
   (the other agents' good-to-know lines stay in Settings), the not-installed line and a pointer
   to Settings, with `Open Settings` and `Done`.

### Wire is the consent

The `Wire` button is the consent. The window shows no confirm popup: the change each row makes is
behind that row's disclosure, which shows `preview.text` in `HookDiffPreview`, the diff view the
Settings popup uses. Nothing is written before the person presses `Wire`.

### What is wired

`SetupAgents` sorts the rows by status. One action wires every found agent that is Not wired or
Needs an update. An agent that can't be set up is shown with its reason and never wired. An agent
that is not installed is only named.

### Moving on, and failing

`wire()` writes each host in turn. The window moves to step 2 only when every write succeeded and
no row still waits to be wired; it shows no panel. A row whose preview has a failure counts as
failed, so a write that never happened cannot read as success. Otherwise the window stays on step 1
in the failed state: the failed row reads `Couldn't be wired` with its error, a warning says how
many agents couldn't be wired and that Countersign left their files unchanged, and the buttons are
`Done`, `Open Settings` and `Try Again`. `Try Again` writes only the failed rows again; the rows
that were written stay wired.

### Opening, no agents, closing

A window opened when every found agent is already wired starts on step 3, so running setup again
shows `All set`, not an offer to wire nothing. With no agent found, step 1 reads `No agents found`
with `Check Again` and `Not Now`; `Check Again` reads the disk again and moves to step 1 or 3,
whichever the files now say. Showing the window writes an empty `setup-shown` file in the support
folder (`AppPaths.setupShownFile`), creating the folder when needed and ignoring a failure, so the
first-open check (`SetupLaunch`) can tell the window has been shown.

`Done` and `Not Now` close the window, and the process exits 0. `Open Settings` closes it and
opens the Settings window in the same process; closing that one exits 0. Back from step 2 to step
1 when every agent is already wired shows the rows with `Next` in place of `Wire`.

## The window

`countersign settings` opens one titled, closable, resizable window,
"Countersign", with its header (the mark, version, Pause, Snooze and Close) fixed at the top, the
sidebar fixed on the left, and only the selected group's content in a scroll view; a page taller
than the window, or a diff disclosed later, scrolls while everything above and beside it stays in
place. Its size and where the frame is remembered are in "Window size" in [settings.md](settings.md),
its header in "Header" there, its groups, Agents, App, Panels and Help in a sidebar plus Advanced
behind a button at the bottom of App, in "Groups and layout" there, next to the header's status controls, the
Panels, App and Advanced groups, and when each preference is written; this section covers the
Agents group and how the window runs.

Run from the CLI, the process becomes an AppKit app with the `.accessory` activation policy (no
Dock icon), orders the window in front, activates itself, and exits 0 when the window is closed.
Activating is the opposite of the panel's rule (see "Never activating" in [panel.md](panel.md)) on
purpose: the panel interrupts whatever the person is doing, while this window is something they
just asked for, so it takes the keyboard. A small main menu gives the window ⌘W and the Edit
shortcuts (⌘X, ⌘C, ⌘V, ⌘A, ⌘Z) in its text fields; an accessory app never shows its menu bar, but
the menu's key equivalents still reach the key window. The companion's "Settings…", and opening
Countersign.app by hand, open the same
window inside the companion process (see "Settings…" and "Opening Countersign" in
[app.md](app.md)).

### Agents

One row per host, from the same files as the terminal flow (`HookConfigLocation`), with the status
`ApprovalCore.HostWiring.status` derives from the file's bytes, the stable path (see "The stable
path" below) and whether the host directory exists:

| Status | When | Action |
| --- | --- | --- |
| Not installed | the host directory does not exist (for Antigravity, none of its three) | none |
| Not wired | the file is missing or blank, or holds no entry of ours; for Antigravity also a `countersign` named hook in another shape, which "Wire" replaces | "Wire" |
| Wired | install would change nothing, where the terminal says `already up to date` | "Remove", a link |
| Needs an update | install would change something: an entry of ours names another executable, runs it with anything but `hook --host <host>`, lacks the `timeout` or `statusMessage` setup writes, or, for Cursor, is missing from one of its two events | "Update" |
| Can't be set up | the file cannot be read or is not valid JSON, has the wrong shape, or the running binary is not named `countersign` | none; the reason shows in red |

"Needs an update" comes from running the install the button would run and comparing the result
with the file's bytes, so the status and the button never disagree about whether there is anything
to do. The row's second line says what an update does: the other executable paths it replaces,
the other arguments it replaces with `hook --host <host>`, the Cursor events it adds the entry
under, or, when none of those, that it refreshes the entry's fields. The Cursor and Antigravity
rows have no trust step; neither asks anything before it runs a new hook. They do get a permanent
good-to-know line once wired, which is a different thing from a trust step (see "Follow-up lines"
below). A row whose host is not
installed shows the directories it looked for, all three for Antigravity. When `config.json` sets
values for the host under `hosts`, the row shows them in one read-only line with a link that opens
the file (see "Panels and App" in [settings.md](settings.md)); no button on the row writes that
file.

Wire, Update and Remove write nothing on click. Each asks first in a popup (`HostHookPrompt`, an
`NSAlert` shown as a sheet on the Settings window) titled for the action, such as "Update
Countersign's Claude Code hook?", whose line under the title names the file and either says it is
created or that a backup is kept, and whose buttons are the action's own name and Cancel. Below
them it shows the text `setup --cli` would print for the same answer: the file's path and unified
diff, or its `already up to date` line, and for a wired row the diff of removing the entry. Only
the action's button writes, and it applies the action that was shown, even if the row changed while
the popup was open; while a popup is up every row's button is disabled. `SetupRun.preview`
produces the text by running
`SetupRun` with `writesFiles: false`, which prints every diff, counts every change as applied
without asking, writes nothing and never touches the Codex hook trust record. The diff
(`HookDiffPreview`, the same view as the waiting-notices and context-hook popups) is monospaced
and selectable, added lines green and removed lines red. It sits behind a disclosure
(`HookDiffDisclosure`), collapsed by default as one row, "Show the change (3 lines added, 1
removed)", whose count is `DiffSummary` of the diff; clicking the triangle or the label expands it
in place, relabels the row "Hide the change" and re-lays the alert out. The triangle is the one
accessibility element, carrying the label's text and the expanded state; the label is hidden from
VoiceOver so the control is read once. Long lines wrap by
character, and a wrapped continuation is indented one character so it sits after the `+`/`-`/space
marker column; the view is as tall as its content, at most twelve lines, and scrolls vertically
past that. A diff shown by default buried the popup's one-line question under thirty lines of JSON,
and a line running off the side with a hidden scroller read as if part of the change were being
withheld. A failure text, or `Nothing to change.`, is the answer itself, so it shows directly with
the same wrapping and no disclosure. `countersign snapshot --hook-prompt` draws the popup, collapsed
or with `--expanded` (see "Snapshots" in [panel.md](panel.md)).

When more than one copy of Countersign is installed, a notice sits at the top of the group, above
the rows; the copies it lists are in "More than one copy installed" below, and the notice itself
in "More than one copy" in [settings.md](settings.md).

The button is the consent. It runs `SetupRun.apply` with a question that is always answered yes, so
backups, atomic writes and every error rule are the terminal flow's own. The first failure
`SetupRun` records (`failures`, one line each, as printed in the terminal) shows as one red line in
the row. After a click that wired or updated Codex's entry, the row's follow-up recomputes and
shows Codex's next step again, since the click just wrote a fresh trust record that has seen no
trust yet (see "The Codex hook trust record" below). A preview that already fails shows that
failure and disables the button, since the click could not change anything. The button acts at
once, like every control in the window, and writes only the host's own file and, for Codex, the
trust record, never `config.json` (see "Writing a change" in [settings.md](settings.md)).

### Copying Countersign.app

A link into Homebrew's prefix is invisible to Spotlight and Launchpad, for two measured reasons:
Spotlight indexes nothing under `/opt/homebrew` (`mdfind -onlyin /opt/homebrew -count
"kMDItemFSName == '*'"` prints 0), and it never indexes a symbolic link, so 0.2.0's link at
`~/Applications/Countersign.app` could not be found. A real bundle in `~/Applications` is indexed.
So Countersign copies the app there instead, and keeps the copy current after `brew upgrade`.
`ApprovalCore.AppBundleCopy` holds the rules. The source is
`<directory of the binary>/../Countersign.app`, the layout of the release tarball and of a Homebrew
install, named by Homebrew's `opt` path for a Cellar install, since the Cellar folder is removed on
the next upgrade and `opt` follows the installed version. Run from inside `Countersign.app`, the
candidate would be inside the bundle itself, which never exists, so there is no offer. It must be a directory whose `CFBundleShortVersionString` reads. Versions come from each bundle's
`Info.plist`, never from Cellar folder names, which can carry a revision suffix (`0.2.0_1`).

What is at `~/Applications/Countersign.app` decides the offer:

| At the destination | Offer |
| --- | --- |
| nothing | add the copy |
| a symbolic link, dangling or not, wherever it points | replace the link with the copy |
| a directory with a lower `x.y.z` version than the source | update from that version |
| a directory with an equal or higher version | none |
| a directory whose version is unreadable or not `x.y.z` | none |
| a regular file | none |

Versions compare as `UpdateCheck.semverParts` arrays, lexicographically.

The App group's Install row shows while there is an offer or a message. Its title is
`Countersign.app`, and the caption and button follow the offer:

| Offer | Caption | Button |
| --- | --- | --- |
| add | Found next to this countersign binary. A copy in ~/Applications shows in Spotlight and Launchpad. | Copy into ~/Applications |
| replace the link | ~/Applications/Countersign.app is a link, which Spotlight and Launchpad don't show. | Replace the Link with a Copy |
| update | The copy in ~/Applications is `<from>`; this one is `<version>`. | Update the Copy |

The click runs `perform` on the main actor, which is fine: the bundle is about 18 MB, and
`~/Applications` and `/opt/homebrew` share an APFS volume, where the copy clones. Success reads
"Copied Countersign.app `<version>` into ~/Applications. Spotlight and Launchpad find it there."
and a failure shows the error's description as a problem message; both replace the offer once the
hosts refresh.

The refresh rule is for the app running from the copy. It applies only when the running bundle,
standardized, is `~/Applications/Countersign.app` and that is a directory (not a link) with a
readable version. Then, for each Homebrew prefix in order (`/opt/homebrew`, `/usr/local`), the first
`<prefix>/opt/countersign/Countersign.app` that resolves to a directory with a higher version than
the copy's is the source of the refresh.

`perform` never leaves half a bundle at the destination. It resolves the source through symbolic
links, creates `~/Applications` when missing, and copies the bundle to a hidden sibling,
`.Countersign.app.copying-<UUID>`. Only a complete sibling is moved into place: over a symbolic link
the link itself is removed (never its target) and the sibling moved in; over a directory
`FileManager.replaceItemAt(_:withItemAt:)` swaps them in one step; over nothing the sibling is
moved. On any error the sibling is removed and the error rethrown.

A plain file copy keeps Countersign.app's ad-hoc signature and its bundle identifier, so Launch at
Login and the menu-bar app keep working from the copy.

## Backups and writing

Before a file that already exists is written, it is copied to
`<name>.countersign-<yyyyMMdd-HHmmss>.bak` in the same directory, in local time, for example
`settings.json.countersign-20260926-143012.bak`. If that name is already taken, nothing is written
and the file is reported as failed.

After the copy, `ConfigFileStore` keeps the newest three backups of that file
(`ConfigFileStore.keptBackups`) and removes the rest. Every write takes a backup, so without a limit
each Settings session, Update, notice toggle and Always allow left one more next to the file, and
they piled up by the day. Only names in exactly the pattern above count, so a hand-made
`settings.json.countersign-keep.bak` or another file's backup is never removed. Names sort by time,
so the oldest go first, except across the hour a clock goes back or a time-zone change, where a
newer local-time stamp can sort before an older one and go first; three recent copies remain either
way. A backup that can't be removed stays and the write goes ahead: pruning tidies up, it never
decides whether a write succeeds.

The new content goes to a temporary file in the same directory, which gets the original file's
permission bits, and is then renamed over the original. Readers see the old file or the new one,
never half of each, and a `0600` settings file stays `0600`. A config file that is a symlink, as in
a dotfiles repository, is written through: the link's target is replaced and the backup sits next
to the target, so the link itself survives.

## Uninstall

Uninstall removes every hook object of ours under `hooks.PermissionRequest`. A group left with an
empty `hooks` array is removed, and `PermissionRequest` is removed when it is left empty. `hooks`
itself stays, even when it ends up as `{}`. Uninstall never creates a file. When install added
`PermissionRequest` beside other events, or our group beside other groups, uninstall takes out
exactly the text install added, so the file is back to its original bytes.

In Cursor's file, uninstall removes every entry of ours under `hooks.beforeShellExecution` and
`hooks.beforeMCPExecution`, and an event whose array is left empty. `hooks` and `version` stay, so
a file install created from nothing ends up as `{ "version": 1, "hooks": {} }`, and a file install
added `version` to keeps it. Everyone else's entries, and entries of ours under any other event,
are left alone.

In Antigravity's file, uninstall removes the top-level named hook `countersign`, whatever its shape
(every one, if the key appears more than once), and nothing else. A file install created from
nothing ends up as `{}`, and a file install appended the named hook to is back to its original
bytes. Every other named hook, including one that runs countersign, is left alone.

In Claude Code's file, uninstall (Remove, and `setup --cli --uninstall`) removes every entry of
ours under both `hooks.PermissionRequest` and `hooks.UserPromptSubmit`, with the same rules for a
group or an event left empty. `hooks` stays. Someone else's hooks under `UserPromptSubmit` are
left alone.

## The stable path

The command must name a path that survives upgrades. Setup resolves the running binary
(`Bundle.main.executableURL`, symlinks resolved). Homebrew installs each version under its own
Cellar directory, `/opt/homebrew/Cellar/countersign/0.1.0/bin/countersign`, and that path is
removed on the next upgrade, which would leave the hook pointing at nothing. So when the resolved
path contains `/Cellar/countersign/`, setup uses `<prefix>/bin/countersign`, Homebrew's stable
link (`/opt/homebrew/bin/countersign` on Apple silicon, `/usr/local/bin/countersign` on Intel), and
that holds for an app bundle inside the Cellar too.

A `curl | sh` install puts two physical copies of the same binary on the Mac: the CLI at
`~/.local/bin/countersign` and the menu-bar companion inside `~/Applications/Countersign.app`
(`install.sh`, at the repository root). Without a rule for that pair, whichever copy happens to
run setup wins: opening the Settings window from the app writes the app's own inner path into
every host's hook entries, running `countersign setup` from the CLI flips them all back, and
`countersign doctor` warns that every entry "differs from the stable path" no matter which copy ran
last. So a resolved path that is the binary inside `Countersign.app`,
`<anything>/Countersign.app/Contents/MacOS/countersign`, and is outside a Cellar, maps to
`~/.local/bin/countersign` when that file exists and is executable. The CLI wins over the app:
dragging the app to the Trash is the more likely way for a person to lose a copy of the binary, so
hooks stay pointed at the one that survives that. Next comes Homebrew: a Homebrew install copies
the app into `~/Applications` too, and that copy resolves outside any Cellar, so without this step
wiring from it would write the copy's inner path into every hook, which breaks when the copy is
replaced or trashed. So when there is no user CLI, `<prefix>/bin/countersign` is tried for each of
`/opt/homebrew` and `/usr/local`, in that order, and the first executable one wins. When none of
them is executable, the app's own path is used as it is, so hooks still work on a Mac with only the
app installed. Any other resolved path, such as `~/.local/bin/countersign` itself or a bare binary run
from a source checkout, is used as it is.

Running setup again after moving the binary rewrites the existing entry's command with the new
path; the entry keeps its place in the file.

## More than one copy installed

People end up with two installs, typically the curl installer and Homebrew. Each one updates on its
own: `brew upgrade` leaves `~/.local/bin/countersign` at its old version, and `~/.local/bin`
usually comes before Homebrew's `bin` on `PATH`, so `countersign` in the terminal and the hooks can
run different versions. The stable path above keeps every hook entry on one path, but it cannot
make the other copy go away. `ApprovalCore.InstalledCopies` finds every copy, and doctor,
`setup --cli` and the settings window say so when there is more than one.

A copy is one install, grouped by where it came from:

| Copy | Found when | Its paths | Version | Removed with |
| --- | --- | --- | --- | --- |
| Homebrew | `<prefix>/bin/countersign` exists, for `/opt/homebrew` and `/usr/local` | that link; the keg, what `<prefix>/opt/countersign` resolves to; a `~/Applications/Countersign.app` link into the keg (see "Copying Countersign.app"), or a real `~/Applications/Countersign.app` directory when `~/.local/bin/countersign` is not a regular file, the keg has a `Countersign.app` with a readable version, and the copy's version is equal to or lower than it | the keg's folder name, `…/Cellar/countersign/<version>` | `brew uninstall countersign`, plus `rm ~/Applications/Countersign.app` for a link, or `rm -rf ~/Applications/Countersign.app` for a real copy |
| Installer | `~/.local/bin/countersign` is a regular file, not a link | that file, and `~/Applications/Countersign.app` when it is a real directory | that app's `CFBundleShortVersionString`, else what `~/.local/bin/countersign --version` prints within 2 seconds; both are kept for the version check below | `rm ~/.local/bin/countersign`, plus `rm -rf ~/Applications/Countersign.app` for its app |
| Countersign.app | `/Applications/Countersign.app` is a real directory, or `~/Applications/Countersign.app` is one and no installer copy owns it | the bundle | its `CFBundleShortVersionString` | `rm -rf <the bundle>` |

The installer row covers both `install.sh` at the repository root and `scripts/install.sh`, which
writes only the CLI. Older version folders under `<prefix>/Cellar/countersign/` are Homebrew's to
clean up (`brew cleanup`), not copies. Symbolic links are resolved, and a file or bundle already
counted, compared by resolved path, is never counted again: a `~/.local/bin/countersign` linked to
Homebrew's binary is no installer copy, and an `/Applications` that links to `~/Applications` does
not make the installer's app a second copy. A dangling link counts as nothing. A version that
cannot be read shows as "version unknown".

A real copy of Homebrew's own app in `~/Applications` is part of the Homebrew install, not a second
one: Countersign makes that copy itself for Homebrew users and keeps it current (see "Copying
Countersign.app"). It is claimed for Homebrew only at the keg app's version or lower, read from
`CFBundleShortVersionString` and never from the keg's folder name, which can carry a `_1`; a higher
or unreadable version stays a Countersign.app copy of its own. A claimed copy lower than the keg app
is not a duplicate but a version mismatch, which Doctor's `versions` line and Settings report as "The
copy of Countersign.app in ~/Applications is older than Homebrew's", with `countersign settings` as
the command. The installer's app-versus-CLI mismatch keeps priority over it.

With two copies or more, each is marked with what is known about it. The hooks call it: every
entry's executable path, read the way doctor reads it (`Doctor.executablePaths`), resolved and
matched against each copy's executables, so `/opt/homebrew/bin/countersign` and the Cellar binary it
links to are the same copy; an entry that names no copy at all, such as a source checkout's build,
is not counted. It is running now. It is the newest: its version, compared with
`UpdateCheck.semverParts` after dropping a Homebrew revision suffix such as the `_1` in `0.2.0_1`
(the label keeps the keg's real name), is the highest known one. A copy is the newest only when at
least two copies have a known version and those versions are not all equal, since "Newest" on every
copy says nothing; a version that is unknown or not `major.minor.patch` is never the newest. It
has the menu-bar
app: the installer's own `~/Applications/Countersign.app`, a keg with `Countersign.app` inside, or
an app copy.

Nothing decides which copy stays. The settings window asks, and `DuplicateInstall.suggestedIndex`
only picks the choice selected to start with: the newest, ties broken by the copy the hooks call,
then the one with the app, then the running one, then the first; with no newest copy, the same
order over every copy. `steps(keeping:)` turns a choice into steps. A copy with a command-line tool
that the hooks don't call first gets its own `setup --cli --yes`, by its shown path, so the hooks
move to it before anything is removed; then every other copy's removal command, joined with `&&`
into one. A copy the hooks already call gets only that removal. An app on its own has no
command-line tool to run setup with, so after the removal it says to open that app and click
Update on each agent, which rewires the hooks to the running app (see "The stable path").
`agentPrompt` describes every copy with the same marks, says whether the hooks call one, none or
more than one, and asks the agent to explain the options and change nothing without asking, for a
person who wants to talk the choice through.

Commands write the home directory as `~`, as the rest of the interface does
(`HomePath.abbreviating`), and quote a path only when the shell needs it, with the rule hook
commands use (see "Install"); `~/` stays outside the quotes so the shell still expands it. With
both Homebrew prefixes installed, each command names its own `brew`, as in
`/usr/local/bin/brew uninstall countersign`, since a bare `brew` acts on whichever prefix comes
first on `PATH`, which may be the copy being kept.

Nothing is ever removed for the person, and there is no "use this one" button. Removing an install
is destructive, the copy an agent is running right now may be the one a button would take away, and
which install method to keep is the person's call. An earlier version kept the copy the hooks
called and offered to remove the rest whatever their versions, which could mean removing a newer
app to keep an older CLI; so the choice is now always the person's, with the newest only selected
to start with. Pointing the hooks at a copy already exists: each host row's Update rewires its
entry to the copy running the window (see "The stable path"), and `countersign setup` does the same
from the terminal.

The installer's two halves can drift apart with a single copy too: rerunning `install.sh` with
`COUNTERSIGN_APP=0`, or `scripts/install.sh`, which writes only the CLI, updates
`~/.local/bin/countersign` and leaves the app at its old version, and an app replaced by hand does
the reverse. `InstalledCopies.versionMismatch` looks only at the installer copy with both
halves present, and returns an `InstallVersionMismatch` when both versions parse and differ. When
the app is older, its command is `install.sh` with `COUNTERSIGN_APP=1`, which updates the app with
the CLI; when the CLI is older it is the plain curl install, and the advice says the agents' hooks
run the CLI, since that is the half that answers them.

`InstalledCopies` reads through `InstallFileSystem`, which answers what kind of thing is at a path
without following its last link, where a path resolves to, and a file's contents; `.local` reads
the disk. The system paths, `/opt/homebrew`, `/usr/local` and `/Applications`, are read under a
root, `/` except in a snapshot with `--home` (see "Snapshots" in [panel.md](panel.md)), and shown
without it. `ApprovalCoreTests` build every layout in a temporary directory with real symbolic
links. Running `~/.local/bin/countersign --version` is the one step outside `ApprovalCore`:
`InstallCopiesCheck.cliVersion` in the `countersign` target runs it with a 2-second timeout and is
passed in as a closure. `InstalledCopies.version(fromVersionOutput:)` takes the version only from a
`countersign <version>` line; a timeout, a failed launch or any other output means no version.

Doctor prints one `copies` line and, after it, one `versions` line for a mismatch (see
[doctor.md](doctor.md)). `setup --cli` prints the `copies` line after its per-file output,
including after "no host detected", reading every host's file again after its own writes, so the
marks reflect what it just wired. The settings window shows both notices; it looks again whenever
it rereads the hosts' files, so a copy removed in the terminal is gone from the window as soon as it
becomes key. The `--version` probe runs for every installer copy, since the CLI's version is what
the mismatch compares with the app's, and `InstallCopiesCheck` memoizes its answer, a failure
included, by path, modification date and size: the copies and the version check share one probe,
and a window that becomes key again launches nothing until the file changes. A snapshot never runs
it. None of this runs on the hook path.

## Follow-up lines

Once an agent is wired, there is sometimes one more thing worth telling the person: Codex needs a
manual trust step before its panel appears at all; Cursor and Antigravity have a permanent quirk
worth knowing. `ApprovalCore.AgentFollowUp` models exactly one such line per host: `host`, `kind`
(`.nextStep` or `.goodToKnow`), `text`, and `offersMarkAsDone`. `AgentFollowUps.current(host:
wiringStatus:codexTrust:)` is the single place that decides whether a host gets one right now:

| Host and state | Line |
| --- | --- |
| Claude Code | none, ever |
| Codex, trust `.unknown` | `.nextStep`: `AgentFollowUps.codexNextStep`, with "Mark as done" |
| Codex, trust `.pending(reason:offersMarkAsDone:)` | `.nextStep`: the reason, when there is one, then `codexNextStep`; "Mark as done" only when the state offers it |
| Codex, trust `.trusted` or `.markedDone` | none |
| Cursor, Antigravity | a permanent `.goodToKnow` |

The Codex states are in "The Codex hook trust record" below. Every case requires
`wiringStatus == .wired`: an agent that needs an update or was never wired gets no line, the same
gate the Agents rows already used for "Wired". The texts themselves
(`AgentFollowUps.codexNextStep`, `cursorGoodToKnow`, `antigravityGoodToKnow`, and the two move
reasons in `CodexTrustVerdict`) are the single source other code quotes rather than duplicating;
`countersign doctor` (see [doctor.md](doctor.md)) and the Agents rows (see "Agents" above and
"Groups and layout" in [settings.md](settings.md)) both build their lines from these instead of
composing their own wording. The window shows the line's text under the row with a "Next step" or
"Good to know" label, and "Mark as done" under it when offered.

After the run's summary, `countersign setup --cli` prints the lines
`AgentFollowUps.setupLines(wiring:codexTrust:changedHosts:uninstall:)` returns. `SetupCommand` only
gathers each host's wiring status, Codex's trust state (`CodexHookTrust.check`, which also saves a
newly learned hash) and the hosts whose files the run changed, and prints what comes back. An
uninstall, or a run that changed no file, prints none of this. Otherwise: "Next step for Codex: …"
whenever Codex ends the run wired with a next step, `.unknown` or `.pending`, whether or not this
particular run touched Codex's file, since the step is a standing reminder; "Good to know for
Cursor: …" and "Good to know for Antigravity: …" only for a host this run actually wired or
updated, so a plain `setup --cli` on an already-wired Mac does not repeat a permanent note every
time.

## The Codex hook trust record

Codex runs a new hook only once the person has trusted it, and only the terminal `/hooks` can record
that trust. Where Codex keeps it, and why Countersign never recomputes the hash Codex stores, is in
"How Codex records hook trust" in [hosts.md](hosts.md). Countersign reads that store, notices the
stored hash change after it writes its own entry, and keeps its own record of what it saw.
`AppPaths.codexHookTrustFile` is `<support directory>/codex-hook-trust.json`
(`CodexHookTrustRecord`, read and written by `CodexHookTrustRecordStore`):

```json
{
  "hookKey": "/Users/dev/.codex/hooks.json:permission_request:0:0",
  "command": "/opt/homebrew/bin/countersign hook --host codex",
  "hashAtWriteKnown": true,
  "hashAtWrite": "sha256:…",
  "learnedHash": "sha256:…",
  "markedDone": false
}
```

| Field | Holds |
| --- | --- |
| `hookKey`, `command` | the entry the record belongs to: its key in Codex's own format and its command, verbatim |
| `hashAtWriteKnown` | whether `$CODEX_HOME/config.toml` was read when the record was written: `true` when it was read or did not exist, `false` when it could not be read or understood |
| `hashAtWrite` | when known, the `trusted_hash` at `hookKey` right after Countersign wrote the entry; absent when there was none |
| `learnedHash` | the hash Codex stored once it trusted this entry, learned from the first change after the write; absent until then |
| `markedDone` | the person clicked "Mark as done" |

In code the two `hashAtWrite` fields are one value, `CodexHashAtWrite`: `.stored(hash)`, `.absent`
(read, and no hash at our key) or `.unread`, so "Codex had no hash at our key" and "the file could
not be read" can never be confused. A missing `hashAtWriteKnown` reads as `false`, whatever
`hashAtWrite` says; a missing `learnedHash` or `markedDone` reads as absent or `false`; a field of
the wrong type makes the whole record unreadable, which reads as no record. The record is never part of
`config.json`: it is Countersign's own bookkeeping, not a preference, and it must survive
independently of anything a person edits by hand.

`CodexHookTrust.current(hooksFileBytes:hooksFilePath:)` is a pure function that finds our entry in
Codex's `hooks.json` the same way `HookSetup.sites` already does, and returns its key and command
(`CodexHookTrustCurrent`); when the entry appears more than once, it uses the first and reports
`hasMultipleEntries`.

### Who writes the record

- `SetupRun`, when it actually writes Codex's file for an install or update, writes a fresh record
  (`CodexHookTrust.writtenRecord`): the new entry's key and command, and as `hashAtWrite` the value
  at that key in `config.toml`, `.absent` when there is none or `config.toml` does not exist, and
  `.unread` when `config.toml` cannot be read or understood. When our entry cannot be found or the
  save fails, it deletes the record instead, which reads as `.unknown`. An uninstall that removed
  the entry deletes the record. It
  never touches the record during `SetupRun.preview` (`writesFiles: false`) or when the file was
  already up to date. This is what makes clicking Wire or Update, from the terminal or the window,
  put the next step back: the fresh record has seen no trust yet.
- "Mark as done" (`CodexHookTrust.markAsDone`, from `CodexHookTrust.markedRecord`) writes the record
  for the entry Codex's file holds right now, with `markedDone: true`. It keeps `learnedHash` when
  the command is unchanged, and `hashAtWrite` when the key is unchanged too; for an entry that has
  moved it takes the value now at the new key as `hashAtWrite`, so trusting in the terminal later is
  still noticed, or `.unread` when `config.toml` cannot be read right then.
- The settings window on every refresh, and `setup --cli` after its run, call
  `CodexHookTrust.check(_:recordFile:persistsLearnedHash: true)`, which saves a newly learned hash
  into the record. `countersign doctor` judges the same way and writes nothing (see
  [doctor.md](doctor.md)), and so does `countersign snapshot --settings` (see "Why snapshot never
  reads the file" in [settings.md](settings.md)).

### The verdict

`CodexTrustVerdict.judge(record:current:table:)` is a pure function over the record, our current
entry and the `trusted_hash` values read from `config.toml` (`CodexTrustTable`; see "How Codex
records hook trust" in [hosts.md](hosts.md)). It returns a `CodexHookTrustState` and, when it learned
one, the hash for the caller to save:

1. No record, no entry of ours, or a record whose `command` differs from the entry's: `.unknown`. A
   changed command is a changed entry, and everything the record saw belongs to the old one. This is
   the key-and-command match of the first version, kept as the gate.
2. `config.toml` is missing, unreadable, not UTF-8, or holds hook state in a shape the reader does
   not understand: `.markedDone` when the record is marked and our key is unchanged, `.unknown`
   otherwise.
3. A learned hash exists: it alone decides. Equal to the value at our current key: `.trusted`.
   Otherwise `.markedDone` when marked at an unchanged key, else `.pending`, with the move reason
   when our key moved within the same list, and without "Mark as done".
4. Nothing learned, key unchanged: when `hashAtWrite` is known, a value that exists and differs
   from it means Codex stored a trust at our key since we wrote the entry: `.trusted`, and that
   value becomes the learned hash. When `hashAtWrite` is `.unread` there is nothing to compare
   against, so this inference is off for the record, whatever `config.toml` holds later. Otherwise
   `.markedDone` when marked, else `.pending(reason: nil)`, offering "Mark as done" unless
   `hashAtWrite` is `.absent`.
5. Nothing learned, key moved within the same `hooks.json` and event: `.pending` with the move
   reason, offering "Mark as done". A key in another `hooks.json` or event, or one not of the form
   `<path>:<event>:<group>:<handler>`: `.unknown`.

Why these rules:

- Codex's hash covers the entry's content, not its position, so the value it stores when the person
  trusts our entry is the same at any key. That is what lets a learned hash recognise trust after a
  move, and why adding a hook for another event, or after ours in the same group or a later one,
  never asks again: our key and the value stored under it do not change, and trusting only the new
  hook stores a value under the new hook's key, not ours.
- Our key moves when a hook is inserted before ours in `hooks.PermissionRequest`, which moves ours
  to a later slot: "Codex asks again because another hook was added before Countersign's." It also
  moves when a hook before ours is removed, which moves ours to an earlier slot: "Codex asks again
  because a hook before Countersign's was removed." Codex itself stops running our hook until it is
  trusted under the new key, so asking is right.
- Once a hash is learned, it alone decides, because "the value changed since the write" can later
  be wrong: ours at `0:0` is trusted, a hook is inserted before it (ours moves to `1:0`), both are
  trusted, then that hook is removed. Ours is back at `0:0`, which now holds the other hook's hash;
  Codex asks again, and "changed since the write" would call it trusted. The narrow cost: editing
  our entry by hand without setup, command unchanged so the record survives, and trusting it again
  leaves the step pending, since the stored hash no longer equals the learned one, until Update or
  wiring again writes a fresh record. A hand edit of the timeout or status message already shows
  "Needs an update".
- "Mark as done" is offered exactly where the verdict can be wrong: `.unknown`; a moved key with
  nothing learned; and an unchanged key with nothing learned whose `hashAtWrite` was `.stored` or
  `.unread`. `.stored` is Remove then Wire with the same binary: the entry written is identical,
  Codex already holds its hash, so Codex trusts it without asking and `config.toml` never changes.
- An `.unread` record never infers trust. Treating "could not read" as "no hash" would call any
  value that appears later a trust of ours, and learn it: marked after a move while `config.toml`
  was unreadable, at a key that still holds another hook's hash, the record would learn that hash,
  and once our entry moved back to a key holding it, report Codex as trusting ours while Codex asks
  again. So only a learned hash it already carries, kept by "Mark as done" from the record before,
  or the mark itself makes it done; until then it stays pending with "Mark as done".
- One blind spot remains before anything is learned: when our entry moves away and back while
  another hook was trusted at our old key, the value at our key has changed and reads as trust.
