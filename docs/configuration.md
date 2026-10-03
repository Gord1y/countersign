# Configuration

Every setting in Countersign's config file: what it does, its default, and when you would change
it. Read it when you want the panel to wait longer or shorter before it appears, change the snooze
presets, turn on the update check, choose what quitting the menu-bar app does, make the panels
light, dark or another color, or set something differently for one agent.

## The file

Countersign reads `$XDG_CONFIG_HOME/countersign/config.json` when `XDG_CONFIG_HOME` is set and not
empty, and `~/.config/countersign/config.json` otherwise. The file is optional: without it, every
setting uses its default. For example:

```json
{
  "$schema": "https://raw.githubusercontent.com/Gord1y/countersign/main/schema/config.schema.json",
  "idleSeconds": 8,
  "graceSeconds": 3,
  "checkForUpdates": true
}
```

Changes apply to the next request; nothing needs restarting. The menu-bar app reads the file when
you open its menu.

## Settings

`countersign settings`, or **Settings…** in the menu-bar app, opens the Settings window, which
edits the file's top-level keys directly, plus Launch at Login, which isn't a key at all. Each
change is saved as soon as you make it: a switch or menu when you pick, a stepper on each click, a
slider when you let go, and **Snooze presets** or a new **Hand off when frontmost** app when you
press Return, move to another field or close the window, so there's nothing to save and closing
never asks. An entry with a mistake shows a red line under it and isn't saved; the file keeps what
it had.

Changed a setting and want it back the way it was? A row you just changed shows a small reset
button beside its control; clicking it removes that key from `config.json`, so the setting follows
the built-in default again, even if that default later changes. The button is an undo for the
current visit: once you close the Settings window or switch to another tab, it is gone from that
row, even though the value still differs from the default. **Panels** and **App** each also have a
**Restore Defaults** button that resets every changed setting in that group at once, after you
confirm, whenever it was changed.

Its settings are in a sidebar with four groups — Agents, App, Panels and Help, the last holding the
tour, documentation, questions and problem reports, updates, and support links — in that order at
every window width, plus **Advanced**, opened through a button at the bottom of App. Drag the
window's edges to resize it: the sidebar's order never changes. It opens again at the size, place
and group you left it with.

### Agents

Connects your agents — **Wire**, **Update**, **Remove**, and **Show changes** first, for Claude
Code, Codex, Cursor and Antigravity; see [setup.md](setup.md) for what each writes. It sets no key
in `config.json` itself; that group edits each agent's own hook file instead. When `hosts.<agent>`
sets one of the Panels keys below for that agent, its row shows the values in one line, with a
link to open the file — see "Settings for one agent" under [Advanced](#advanced).

### Panels

How approval panels behave, for every agent unless a key is overridden for one under
`hosts.<agent>` (see "Settings for one agent" under Advanced). Settings sets the delays for all
agents at once, or, with "Same delays for all agents" off, for one agent at a time under
`hosts.<agent>`; its Approval card checkboxes choose which agents show the card:

| Setting | Key | Default |
| --- | --- | --- |
| Wait for idle | `idleSeconds` | `5` |
| Grace period | `graceSeconds` | `0` |
| Arm delay | `armDelay` | `0.5` |
| Arm delay after an answer | `chainedArmDelay` | `0.1` |
| Hand off when frontmost | `handoffApps` | `[]` |
| Snooze presets | `snoozeMinutes` | `[1, 5, 15, 30]` |
| Quiet hours | `quietHours` | `[]` |
| Notes on answers | `questionNotes` | `false` |
| Mode after a plan | `modeAfterPlan` | `"default"` |
| Sound | `panelSound` | `"none"` |
| Waiting-agent notices | `waitingNotices` | `true` |
| Notice after | `waitingNoticeDelay` | `10` (seconds) |
| Show notice for | `waitingNoticeDuration` | `10` (seconds) |

Every time setting takes a number in its own unit or a string with a unit, so `"500ms"`, `"0.5s"`,
`"90s"`, `"2m"` and `"1h"` all work (`ms`, `s`, `m` and `h`, written without a space). A bare number
keeps the unit in the key: seconds for `idleSeconds`, `graceSeconds`, `armDelay`,
`chainedArmDelay`, `waitingNoticeDelay`, `waitingNoticeDuration` and `approvalCardDelay`, minutes for `snoozeMinutes`. The
range of each key applies after the unit is converted, so `"90s"` is a valid `waitingNoticeDelay`
and `"2m"` is out of range for `idleSeconds`. Settings writes a whole number of minutes back as a number, and anything
shorter as a string, for example `["30s", 5, 15]`.

All of these except **Quiet hours**, **Notes on answers**, **Mode after a plan**, **Sound** and
**Waiting-agent notices** live at the top level of `config.json` and can
also be set per agent, under `hosts.<agent>`. `quietHours`, `questionNotes`, `modeAfterPlan`,
`panelSound` and `waitingNotices` are top-level only, like the App group's
keys below.

- **Wait for idle** (`idleSeconds`): how long since your last keyboard, mouse or scroll input a
  panel needs before it appears — counted from that last input, not from when the request
  arrives, so if you've already been away that long the panel appears at once. `1` to `30`
  seconds. Raise it if panels still appear while you pause mid-thought; lower it if you want them
  sooner.
- **Grace period** (`graceSeconds`): how long a request waits for you to answer it in the chat
  before it joins the queue. `0` to `30` seconds. Set it to a few seconds if you often answer Claude
  Code in the chat right away — a request you answer there during the grace period never gets a
  panel at all. Only Claude Code's chat answers are noticed, so for the other agents it only
  delays the panel.
- **Arm delay** (`armDelay`): how long a new panel ignores keys and clicks, so a keystroke meant
  for something else can't answer it. `0` to `3`. Raise it if keys you meant for another app still
  land in the panel; lower it if the pause before a panel accepts input feels slow.
- **Arm delay after an answer** (`chainedArmDelay`): the same, for a panel that appears right after
  you answered the previous one. `0` to `3`. It is separate from `armDelay` and never falls back to
  it: you are already looking at the panel when the next one appears, so it can be short.
- **Hand off when frontmost** (`handoffApps`): bundle IDs of apps where you'd rather answer in the
  chat. When a panel is about to appear and the app in front is on this list and is also the app
  the request came from, no panel appears; the request goes to the agent's own prompt, where you
  are already looking. This is checked at that moment, after **Wait for idle**, not when the
  request arrives: switch to another app before then and you get a panel; stay in the asking app
  and its own prompt comes only after that pause (Codex shows "Waiting for the approval panel"
  meanwhile). A request from any other app still gets a panel. Cursor and Antigravity show their
  own approval prompt in this case.
- **Snooze presets** (`snoozeMinutes`): the durations the Snooze menus offer, in order. 1 to 6
  durations, each from 10 seconds to 24 hours: a number of minutes, or a string such as `"30s"` or
  `"1h"`. Set the presets you actually use. The menu-bar app's own
  Snooze menu isn't tied to one agent, so it always uses the top-level value, even when an agent's
  `hosts` block sets its own.
- **Quiet hours** (`quietHours`): recurring windows in which panels wait, like a snooze that
  repeats. Up to 7 entries, each with `days` (any of `"mon"` to `"sun"`), `from` and `to` as
  a time of day in your local time: `9`, `09`, `9:30`, `0930` and `21:30` all work, and
  Countersign writes `HH:mm`. Panels wait exactly as during a snooze: requests go to their chats
  and can still be answered there. The window is over at the minute `to` is reached.

  ```json
  {
    "quietHours": [
      { "days": ["mon", "tue", "wed", "thu", "fri"], "from": "19:00", "to": "09:00" },
      { "days": ["sat", "sun"], "from": "00:00", "to": "12:00" }
    ]
  }
  ```

  A `to` earlier than `from` makes the window run past midnight, and `days` names the day it
  starts: the first entry above starts Monday 19:00 and ends Tuesday 09:00, so Saturday 03:00 is
  quiet because Friday's window is still running. `from` and `to` must differ. Windows that touch or
  overlap, such as Mon 19:00 to 00:00 and Tue 00:00 to 09:00, are one quiet period that lasts
  until the last end, and End now skips the whole period. A snooze that ends later than a window
  extends it. End now (the menu, the Settings
  header, `countersign snooze off`) ends a snooze and also skips the window that is running now;
  the next day's window applies as usual. Pause still wins over quiet hours. A bad entry gets one
  line in the log and is dropped, and the rest apply. `countersign status` prints `quiet: until
  09:00 (quiet hours)` while a window is running. Settings, Panels, adds and removes windows.
- **Notes on answers** (`questionNotes`): off by default, so a question panel shows only its
  options. Turn it on if you want a way to add context to the option you pick; it shows a **+ Add
  a note** link under a question's options, and the note you type comes back to Claude in the
  answer's `annotations`.
- **Mode after a plan** (`modeAfterPlan`): the permission mode Claude Code continues in once you
  approve a plan, `"default"` (Ask before edits) unless you change it. `"acceptEdits"` lets it
  edit files without asking; `"auto"` hands the decisions to Claude Code's auto mode. The plan
  panel's **then: …** menu starts on this choice, and you can still pick another there for a
  single plan. Only Claude Code sends plans, so the other agents are unaffected.
- **Sound** (`panelSound`): a macOS sound played once when a panel appears, `"none"` (nothing)
  unless you change it. Use `"Basso"`, `"Blow"`, `"Bottle"`, `"Frog"`, `"Funk"`, `"Glass"`,
  `"Hero"`, `"Morse"`, `"Ping"`, `"Pop"`, `"Purr"`, `"Sosumi"`, `"Submarine"` or `"Tink"`, the
  files in `/System/Library/Sounds`; a name that is not installed logs one line and falls back to
  `"none"`. It plays for approval panels, context checkpoints and test panels, so you can hear
  your choice, but not for the next panel in a chain you are already answering, and never for the
  result card or a notice. The speaker button beside the menu in Settings plays the chosen sound.
- **Waiting-agent notices** (`waitingNotices`): `true` shows a corner card, "Claude Code is
  waiting for you", once an agent has finished a turn and waited for you. `true` unless you change
  it. While it is on, `countersign setup` and Update in Settings ▸ Agents add Countersign's `Stop`
  hook next to the permission hook in each agent's hook file (Claude Code, Codex, Cursor and
  Antigravity), in the same diff. Turn it off from Settings, not by editing the file: that removes
  those hooks, after showing you the change, and writes `false`, and setup then leaves them out.
  Codex asks you to trust its new hook once; see
  [agents.md](agents.md#the-waiting-agent-notice). At most two corner cards show at once; a
  third notice waits for room. Notices hide while any Countersign panel is on screen, a test panel
  included, and come back when it closes.
- **Notice after** (`waitingNoticeDelay`): how long an agent has been waiting before the
  notice appears, from 10 seconds to 1 hour: a number of seconds or a string such as `"90s"` or
  `"2m"`, `10` unless you change it. A value outside the range or of another type logs one line
  and falls back to `10`. It can also be set for one agent, under `hosts.<agent>`, and wins there;
  Settings shows only the top-level value, in a field under the Waiting-agent notices switch,
  disabled while notices are off.
- **Show notice for** (`waitingNoticeDuration`): how long a notice stays on screen before it
  closes by itself, from 3 seconds to 1 hour: a number of seconds or a string such as `"10s"` or
  `"1m"`, `10` unless you change it. A value outside the range or of another type logs one line
  and falls back to `10`. Only the time the notice is visible counts: while a panel, quiet time or
  a pause hides it, or while the pointer rests on it, the clock stops. A notice that closes this
  way is deleted like one you dismiss with the ✕, and the log reads
  `notice: closed (shown long enough)`. It is top level only: `hosts.<agent>` does not take it.
  Settings shows it directly under Notice after, disabled while notices are off. Approval cards
  never close by themselves.

#### Try your settings

Choose **Show a Test Panel** in the menu-bar app, click **Command**, **Question** or **Plan**
under **Show a test panel** in Settings' **Panels**, or run `countersign test-panel` (add
`question` or `plan` for those kinds), to see a panel for a harmless sample request with your
current settings: the arm delay, the Snooze presets, `questionNotes`, the App group's appearance
and accent colour, and the idle wait if you switch away and it steps aside. It shows right away,
without the grace period or the idle wait. Only one test panel shows at a time, and a real request
always comes first: while a panel is on screen or a request is waiting for one, the test panel
doesn't show and says why, and a request that arrives while it is up closes it. Nothing you choose
in it reaches an agent, and once you answer, a small card says what you picked and what a real
request would have done. It reads the file when it starts, so save your changes first, and it uses
Claude Code's settings, `hosts.claude` included. More in
[menu-bar-app.md](menu-bar-app.md#test-panel).

### App

What the menu-bar app does, and how panels and the Settings window look:

| Setting | Key | Default |
| --- | --- | --- |
| Launch at login | none | off |
| Check for updates | `checkForUpdates` | `false` |
| When Countersign quits | `quitBehavior` | `"ask"` |
| Appearance | `appearance` | `"system"` |
| Accent colour | `accentColor` | `"#E6B04A"` (Amber) |

- **Launch at login**: registers Countersign as a macOS login item, so it starts automatically when
  you log in. macOS keeps this, not `config.json`. More in
  [menu-bar-app.md](menu-bar-app.md#launch-at-login).
- **Check for updates** (`checkForUpdates`): turn it on to be told about new releases; what the
  check contacts is in [menu-bar-app.md](menu-bar-app.md#check-for-updates). **Check for
  Updates…** in the menu works whether it is on or off.
- **When Countersign quits** (`quitBehavior`): `"ask"` shows a question each time you choose **Quit
  Countersign** in the menu-bar app. `"keepShowing"` quits without asking and panels keep
  appearing; `"pause"` quits without asking and pauses panels until you open the app again.
  Ticking **Don't ask again** in the question writes your answer here. See
  [menu-bar-app.md](menu-bar-app.md#quit).
- **Appearance** (`appearance`): `"system"` follows the light or dark appearance chosen in macOS;
  `"light"` and `"dark"` keep every panel and the Settings window that way whatever macOS uses.
- **Accent colour** (`accentColor`): the color of Approve and the other filled buttons, and of
  highlights such as a selected option, on every panel and in the Settings window. Settings offers
  Amber, Blue, Green, Purple, Pink and Graphite, and a color well for any other; the file takes any
  `"#RRGGBB"`. Text drawn in the color is darkened in light appearance, or lightened in dark, until
  it is easy to read, and a filled button's label is near-black or white, whichever reads better.
  Deny stays red, the mark in a panel's header keeps the app icon's amber, and the menu-bar icon
  stays monochrome.

### Advanced

Shows the config file's path, **Open in Editor** (creates the file with the `$schema` line when
it's missing), **Copy Path**, the schema's URL as a link, and what only the file can set.

- **Open with** (`editorApp`, default: ask every time): which app **Open in Editor** opens
  `config.json` with, on this row and on an agent's own "Open in Editor" link. Absent means ask:
  Open in Editor shows a list of the apps that open JSON files, with "Always use this app" ticked,
  and a pick with it ticked is stored here so later clicks open directly. Pick one from the menu
  yourself, or **Other…** for an app the menu doesn't offer; **Ask every time** removes the key.
  If the chosen app is later uninstalled, Open in Editor asks again and says so.

The menu-bar app started from the Finder or at login doesn't see variables set in your shell
profile. If you set `XDG_CONFIG_HOME` only there, its Settings window edits
`~/.config/countersign/config.json` while hooks started from that shell read the other file; run
`countersign settings` from that shell instead.

#### What only the file can set

- **`includeHeadlessSessions`** (default `false`): show panels for non-interactive Claude Code
  runs too. By default a non-interactive run, such as `claude -p`, gets no panel, because nobody
  is at a chat to answer it; it gets Claude Code's own handling instead. Set it to `true` to see
  panels for those runs as well. It has no effect for Codex, Cursor or Antigravity. It can be set
  at the top level or per agent, under `hosts.<agent>`, like the Panels keys above.
- **`approvalCard`** (default: on for Codex, Cursor and Antigravity, off for Claude Code): a small
  corner card, "Cursor needs your approval · shop-api", with a **Show** button, when a request has
  waited `approvalCardDelay` seconds for **Wait for idle** while you keep typing or moving the
  mouse. A panel waits for a pause so it never takes keys meant for something else, but if you
  never pause, Cursor and Antigravity just stop and wait, with no prompt of their own, and Codex
  only says "Waiting for the approval panel". The card never takes focus, so your typing is safe.
  **Show** brings the panel up at once, still with the arm delay; the close button dismisses the
  card and the panel waits for a pause as before. If the panel appears and steps aside because you
  went back to work without answering, the card comes back at once, unless you dismissed it. No
  card shows during quiet time or while paused (a card that is up when quiet time starts closes,
  and comes back after it), and never for a test panel or a context checkpoint; it goes away when
  the panel appears or the request ends. At most two corner cards show at once, and an approval
  card goes first: when both places hold waiting-agent notices, the newer notice steps back until
  there is room again. Claude Code is off by default because its
  request also waits in the chat, where you can answer it while you work. Set it at the top level
  for every agent, or per agent under `hosts.<agent>`, which wins: for example
  `"hosts": { "claude": { "approvalCard": true } }` turns it on for Claude Code alone. A value
  that isn't `true` or `false` logs one line and the agent's default applies.
- **`approvalCardDelay`** (default `5`): how long a request waits for a pause before its
  card appears, from `1` second to `10` minutes: a number of seconds or a string with a unit, such
  as `"1.5s"` or `"2m"`. Counted from when the request's turn comes and it
  starts waiting for your pause, not from when it arrived; after its panel steps aside unanswered
  there is no delay. A value outside the
  range or of another type logs one line, `expected a duration from 1s to 10m, using default 5s`, and falls back to `5`. It can be set at the top level or
  per agent, under `hosts.<agent>`.
- **`hosts.claude`, `hosts.codex`, `hosts.cursor`, `hosts.antigravity`**: per-agent values; see
  "Settings for one agent" below.

#### Settings for one agent

Every key except `checkForUpdates`, `questionNotes`, `quitBehavior`, `modeAfterPlan`, `panelSound`,
`waitingNotices`, `appearance`, `accentColor` and `editorApp` can also be set for one agent, under
`hosts.claude`, `hosts.codex`, `hosts.cursor` or `hosts.antigravity`:

```json
{
  "idleSeconds": 5,
  "hosts": {
    "codex": { "idleSeconds": 2 }
  }
}
```

The keys an agent block takes are `armDelay`, `chainedArmDelay`, `idleSeconds`, `graceSeconds`,
`handoffApps`, `snoozeMinutes`, `includeHeadlessSessions`, `waitingNoticeDelay`, `approvalCard`
and `approvalCardDelay`.

For a request from an agent, its `hosts` value wins over the top-level one, which wins over the
default. This file is the only place settings live: the hook command takes nothing but
`--host <agent>`. The menu-bar app's Snooze menu isn't tied to one agent, so it always uses the
top-level `snoozeMinutes`, and quiet hours are top-level only too.

#### Mistakes in the file

A mistake never stops a panel and never answers anything; Countersign falls back and carries on:

- A file that can't be read or isn't a valid JSON object: every setting uses its default.
- A key with the wrong type or a value outside its range: that key uses its default, and every
  other key is read as usual. `armDelay` and `chainedArmDelay` are the exception: a value outside
  `0` to `3` seconds is moved to the nearest end instead. A string that isn't a number followed by
  `ms`, `s`, `m` or `h` counts as the wrong type; the log line quotes a value as you wrote it.
- An unknown key: ignored.

Each mistake is written to the log, `~/Library/Logs/Countersign/countersign.log`, on a line starting
with `config: `, and `countersign doctor` lists them as `warn` lines.

#### JSON Schema

[`schema/config.schema.json`](../schema/config.schema.json) describes every key. Point the file's
`$schema` at `https://raw.githubusercontent.com/Gord1y/countersign/main/schema/config.schema.json`,
as in the example above, and an editor that understands JSON Schema completes and checks keys as
you type. `$schema` itself is ignored by Countersign; it only lets your editor validate the file.

## Context checkpoints (Claude Code)

Off by default, and for Claude Code only. When on, Countersign watches how large a Claude Code
session's context has grown and adds a note asking it to wrap up, compact or hand off. The
`contextCheckpoints` object takes these keys, all optional and all edited in the file only:

- `enabled`: `true` or `false`. Default `false`.
- `mode`: `"panel"` asks you in a panel, `"silent"` only adds the note. Default `"panel"`.
- `thresholds`: the three checkpoints, in tokens, by context window. `200k` defaults to
  `[100000, 130000, 160000]` and `1m` to `[200000, 300000, 400000]`. Each is exactly three whole
  numbers of 1 or more, strictly ascending.
- `modelThresholds`: an object from a model identifier, as Claude Code reports it, to a ladder of
  three ascending whole numbers. It wins over `thresholds`. A bad entry is dropped.
- `rearmBelow`: a number from `0.1` to `0.95`. Default `0.6`. A checkpoint fires again only once
  the context has fallen below this fraction of its size, for example after `/compact`.
- `handoffFile`: a non-empty path. Default `"notes/handoff.md"`.
- `notes`: the text of `soft`, `status`, `insist`, `compact` and `handoff`, each 1 to 4000
  characters. Two placeholders work in every note: `{tokens}` becomes the context size (`212K`, or
  `1.3M` from 999,500 tokens up) and `{handoffFile}` becomes `handoffFile`.
- `menuBarMeter`: `true` or `false`. Default `false`.
- `hosts.claude`: any of the keys above except `hosts`, winning over the top-level value, note by
  note. `hosts.codex`, `hosts.cursor` and `hosts.antigravity` are ignored with a log line.

A key with a mistake uses its default and the rest of the block is read as usual, like every other
key on this page.

To turn the feature off, use the "Context checkpoints (Claude Code)" switch in Settings > Panels or
the "Turn Off Context Checkpoints" button at the bottom of the Context tab. Both show what changes
in Claude Code's `settings.json` before anything is written.

#### Ask your coding agent

Advanced also has a prompt you can copy into a coding agent, naming the file's path and its
schema, if you'd rather ask one to make a change than edit the file yourself.
