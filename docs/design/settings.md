# Settings internals

How the config file is found, parsed and applied, and how the settings window reads and writes it:
where each key is consumed, the precedence function, why one bad key never spoils the rest, the
window's size, header controls, its five groups and how they are laid out, when each change is written,
and why `snapshot` ignores the file. Read it before changing `Settings`, `ConfigFileParser`,
`PreferenceRules`, `PreferenceValues`, `PreferenceOverrides`, `SettingsPane`, the settings window,
or the schema. Every key, from a user's side, is in [../configuration.md](../configuration.md).

## The config file

`hook`, `preview` and the menu-bar companion read `$XDG_CONFIG_HOME/countersign/config.json` when
`XDG_CONFIG_HOME` is set and non-empty, else `~/.config/countersign/config.json`.
`AppPaths.configFile` computes the path; `AppPaths.standard` reads `XDG_CONFIG_HOME` from the
environment, and `AppPaths(home:xdgConfigHome:)` takes it as a parameter. A missing file is
normal: every setting falls back to its built-in default, and nothing is logged, since a person who
has never created the file is not misconfiguring anything.

The file is edited by hand, or through the settings window, which changes top-level keys only (see
"The settings window" below). `SetupRun`, behind `setup --cli` and the window's host buttons,
never reads or writes it. The menu-bar companion resolves the path with its own environment, which
can differ from a hook's `XDG_CONFIG_HOME` (see "Settings…" in [app.md](app.md)).

## Where each key is used

- **`armDelay`** feeds `PanelController`'s `armDuration` (see "The arm lock" in
  [panel.md](panel.md)): how long the panel ignores input after appearing. A value outside `0...3`
  is clamped to that range rather than rejected.
- **`chainedArmDelay`** takes the place of `armDelay` for a panel shown right after the previous
  one was answered, through the queue handoff (see "Warm standby and the queue handoff" in
  [queue.md](queue.md)). Every other panel, including one shown after a step-aside, a snooze or a
  stale handoff, uses `armDelay`. `0` arms the panel at once. It is clamped to `0...3` like
  `armDelay`, and it is its own setting: an `armDelay` in the file never changes it. Why a chained
  panel needs less is in "The arm lock" in [panel.md](panel.md).
- **`idleSeconds`** feeds `ActivityGate(idleSeconds:)` in `HookRunner` (see "Waiting for a pause
  before showing" in [panel.md](panel.md)): how long the person must be idle before a queued panel
  is shown.
- **`graceSeconds`** is the grace period `HookRunner` waits, before enqueueing a ticket, for the
  request to resolve elsewhere (see [queue.md](queue.md)).
- **`handoffApps`** is a list of bundle IDs: when the frontmost app's bundle identifier is in this
  list, *and* that frontmost app is also the one this request came from (see "Detecting the host
  app from the process tree" in [hosts.md](hosts.md)) at the moment its panel would appear, the
  hook exits with no decision, logging `handoff: <bundle id> frontmost`, instead of showing the
  panel (see "Handing off to the asking app" in [panel.md](panel.md)). For Cursor, "no decision" on this path still writes `{"permission":"ask"}`
  before exiting, the same reply "Answer in chat" gives, because empty stdout would let Cursor's
  auto-run carry on unasked (see "The Cursor adapter" in [hosts.md](hosts.md)). Antigravity gets
  `{"decision":"ask"}` on this path, for the same reason (see "The Antigravity adapter" in
  [hosts.md](hosts.md)).
- **`snoozeMinutes`** are the durations, in menu order, offered by the panel's Snooze menu (see
  "Quiet time" in [panel.md](panel.md)). The first entry's button reads "Quiet for `<duration>`",
  the rest just "`<duration>`", both rendered with `ApprovalCore.SnoozeTitle.describe`. The
  menu-bar companion's Snooze submenu offers the same presets with the same titles, but from the
  top-level value only: it acts for no single host, so the `hosts.*` blocks never apply to it.
- **`checkForUpdates`** turns on the menu-bar companion's automatic release check, at most once
  every 24 hours, on top-level `checkForUpdates: true` only. It has no per-host override, since the
  companion acts for no single host (see "Update check" in [app.md](app.md)). Choosing "Check for
  Updates…" in the menu always checks immediately regardless of this setting.
- **`quitBehavior`** decides what the menu-bar companion's "Quit Countersign" does: `"ask"` (the
  default) shows the quit question, `"keepShowing"` quits at once, `"pause"` quits at once and
  pauses panels until the companion opens again (see "Quit" in [app.md](app.md)). A string outside
  those three is logged and falls back to `"ask"`. Top level only, like `checkForUpdates`, and the
  one key besides the window's own that something else writes: the quit question's "Don't ask
  again" writes it through `ConfigEdit`.
- **`includeHeadlessSessions`** disables `HeadlessSessionGate`'s skip of non-interactive Claude
  sessions (a headless `claude -p` run has nobody at a chat to answer) for this host; see
  "Skipping non-interactive sessions" in [resolution.md](resolution.md). It has no effect for
  Codex, Cursor or Antigravity, which have no equivalent session registry.
- **`questionNotes`** feeds `PanelModel.questionNotes`, read by `QuestionView` to show or hide
  "+ Add a note" and the note field, and to pass `includeNotes` to `QuestionResponse.outcome` (see
  "A question submitted" in [answers.md](answers.md)). No per-host override, since a question's
  shape doesn't depend on which agent asked it, only on whether the person wants the extra field at
  all.
- **`contextCheckpoints`** is parsed into `ContextCheckpointFileValues` (top level, and the
  `hosts.claude` block inside it) and resolved into `ContextCheckpointSettings` on
  `Settings.contextCheckpoints`, used by the hook's checkpoint path. The per-host override exists
  only for `claude`: the feature reads Claude Code's transcript, so any other host resolves to the
  disabled default, and `hosts.codex|cursor|antigravity` inside the block are logged and ignored.
  Notes resolve one by one (host, then top level, then the built-in text).

## Precedence

For a hook of host X, in order: `hosts.X` in the config file beats the top-level value, which
beats the built-in default. `checkForUpdates`, `questionNotes` and `quitBehavior` have no per-host
value, so for them the order starts at the top level. A `hosts.X` list, such as `handoffApps`,
replaces the top-level list for that host rather than adding to it.

The config file is the only source. `countersign hook` takes `--host <host>` and nothing else:
`HookOptions.parse` refuses any other argument, and the hook treats that like every other failure,
as no decision. One place for settings means the Settings window, `doctor` and a person reading
the file all see the values a hook uses; a hook command can never quietly override them.

`ApprovalCore.Settings.resolve(file:host:)` is the pure function that applies this order; `hook`
and `preview` both call it.

## Bad input

Parsing never blocks a panel, never decides an outcome, never writes to stderr on the hook path,
and never exits non-zero: every failure just falls back to defaults, matching the rest of the hook
contract in the root `CLAUDE.md`.

- **The file does not exist.** Normal; every key uses its default; nothing is logged.
- **The file cannot be read, or is not valid JSON, or is not a JSON object.** One log line, all
  keys use their defaults.
- **A key has the wrong type, or a value outside its rules** (a negative `idleSeconds`, a
  `snoozeMinutes` array with 0 or more than 6 entries or an out-of-range entry, a non-string
  `handoffApps` entry, and so on). One log line naming the key and the default it falls back to;
  every other key is still read normally. `armDelay` and `chainedArmDelay` are the exception: a
  number outside `0...3` is clamped and logged, not discarded, since a person who wrote `5` clearly
  meant "as long as possible" rather than nothing at all.
- **An unknown key**, at the top level, inside `hosts`, or inside a host block. One log line
  naming it, then ignored.

`ConfigFileParser.parse` reads each key independently with `ApprovalCore.JSONValue` rather than a
`Codable` struct, specifically so one bad key cannot fail the whole file (see "Why `JSONValue`
keeps `int` and `double` apart" in [hosts.md](hosts.md) for why numbers go through `JSONValue` in
the first place rather than a plain `Double`).

`hook` writes each log line to its `EventLog` with the prefix `config: `, alongside its other
`start`/`outcome`/`handoff` lines. `preview` prints each line to stderr the same way it prints its
other diagnostics, with no prefix, since stderr there is nothing but diagnostics already.

## The settings window

`countersign settings`, plain `countersign setup` and the menu-bar companion's "Settings…" open the
same window. Its Agents group and how the window runs are in "The window" in [setup.md](setup.md);
this section covers its size, its groups and their layout, the header's status controls, the Panels and App
controls, when each change is written, Advanced, and the notice about a second copy at the top of
Agents.

### Window size

The window is resizable, with no maximum. Its content opens at 820 × 800 pt, shrunk to fit the
screen's visible frame on a small screen, and centered; it never goes below 680 × 480 pt
(`contentMinSize`). `ApprovalCore.SettingsWindowPlacement` holds those sizes and the rule below,
so the tests cover them. 800 pt is Panels measured at 820 pt wide, the tallest of the four sidebar
groups with the demo fixture's four agents wired (Agents, App and Help are all shorter there), rounded up
to the nearest 10 and pinned as a constant rather than measured live, so the window's height never
depends on what a person's own config happens to hold. A shorter group simply leaves space below its
last card; a taller one, or a narrower window that wraps more captions, scrolls (see "Header" for
what stays fixed above the scroll, and the paragraph below for why it never bounces).

The window's `collectionBehavior` is `.fullScreenNone`: a resizable titled window is otherwise
full-screenable by default, and a Settings window filling a whole Space is wrong for a menu-bar
app's small preferences panel. With full screen off, the green title-bar button falls back to its
pre-full-screen behaviour, standard zoom (`NSWindow.zoom(_:)`, filling the screen's visible frame,
and back on a second click) instead of offering full screen.

The window remembers its frame across opens and launches through AppKit's frame autosave, under the
name "Countersign Settings": AppKit keeps it in the standard user defaults of the process showing
the window, `dev.gord1y.countersign` for a binary inside Countersign.app, and a binary outside the
app has a domain of its own. The frame is never written to `config.json` and has no Settings row:
it is the state of one Mac's screens, not a setting a hook reads, it changes with every drag, and
writing it would rewrite a file people edit by hand, with a backup each session.

A remembered frame is used only when its content is at least the minimum size and the whole frame
lies inside one screen's visible frame. Anything else, such as a frame left on a monitor that was
unplugged or a screen whose resolution dropped, is dropped with `NSWindow.removeFrame(usingName:)`
and the window opens at the default size, centered, so it never opens too small or out of reach.
`SettingsWindowController` restores and checks the frame first and sets the autosave name last, so
setting the name cannot bring back a frame that was just rejected.

The check at open is not enough on its own: a display unplugged or rearranged while the window is
open can leave it on a screen that is gone or partly off every screen. So each time the window is
shown, and on every `NSApplication.didChangeScreenParametersNotification` while it is open, the
controller runs its frame through `ScreenPlacement` (see "Centered on the mouse's display, over a
blurred backdrop" in [panel.md](panel.md)): the window moves onto the screen holding its centre,
else the one it overlaps most, else the first, and is clamped into that screen's visible frame. It
keeps its size unless it is larger than that visible frame, and the frame autosave records where it
ends up.

### Groups and layout

The header's pause and snooze controls (see "Status" below) sit at the top, outside every group:
they are the state Countersign is in right now, not a setting. Below the header, a sidebar lists Agents, App, Panels and Help,
in that order, at every window width (`SettingsPane.sidebar`; `ApprovalCore.SettingsPane` also holds
each group's title and subtitle). The selected item is highlighted; the content area to its right
shows that one group, scrolled to its top, with only its subtitle above it, not its title again,
since the sidebar already names it:

| Group | Holds | What it changes |
| --- | --- | --- |
| Agents | a row per agent (Wire, Update, Remove, Show changes), the notice about a second copy, on each row the values `hosts.<agent>` sets, and, once wired, its follow-up line and Codex's "Mark as done" (`AgentFollowUp`; see "Follow-up lines" and "The Codex hook trust record" in [setup.md](setup.md)) | each agent's own hook file; the Codex hook trust record, never `config.json` |
| Panels | Wait for idle, Grace period, Arm delay, Arm delay after an answer, Hand off when frontmost, Snooze presets, Notes on answers, Mode after a plan, then Show a test panel | `config.json`, for every agent |
| App | Launch at login, Check for updates, When Countersign quits, Appearance, Accent colour, the offer to link Countersign.app, then Advanced… | macOS's login items, `config.json`, `~/Applications` |
| Help | the tour, documentation, ask a question, report a problem, contact the developer, updates, then support links | nothing in `config.json`; never `update-check.json` |
| Advanced | the config file's path, Open in Editor, Copy Path, Open with, the schema, what only the file can set, and the prompt for a coding agent | `config.json` for Open with; otherwise nothing beyond creating a missing `config.json` to open it |

The groups follow what a control changes and where the change lands, so one subtitle can say it
for every row in the group. One long scroll mixing them, with a section named "Preferences" inside
a window named Settings, would say nothing about which of them a row belongs to, and no group is
named "Preferences" for the same reason. Check for updates and When Countersign quits are written
to `config.json` like the Panels rows, but only the menu-bar app reads them, so they sit in App;
Launch at login is there because it registers the app with macOS. Appearance and Accent colour
change how the whole app looks, the Settings window as much as the panels, and change nothing about
how a panel behaves, so they sit in App too, and App's Restore Defaults covers them. Help holds
nothing from `config.json` at all — `SettingsPane.help.preferenceNames` is empty — so it has no
Restore Defaults and no row can be "changed"; it exists so a person who runs `countersign settings`
without ever opening the menu-bar app still reaches what the companion's Help and Support the
Developer menus offer.

Advanced (the config file's path, Open in Editor, Copy Path, Open with, the schema, what only the file
can set, and the prompt for a coding agent) has no place in the sidebar: it is reached through an
**Advanced…** button at the bottom of the App group, sharing its row with Restore Defaults.
Clicking it selects
`SettingsPane.advanced` (`SettingsModel.select(_:)`), which shows Advanced's content in the same
area, with a **‹ App** link above it that selects `.app` again; the sidebar keeps App highlighted
the whole time, since `.advanced` is not one of its rows (`SettingsSidebar.isSelected(_:)` treats
App and Advanced as the same row). `SettingsPane.advanced` remains a real case: it is still what
gets stored, restored and passed to `--tab`, just not listed in the sidebar.

The selected group is remembered across opens and launches under the key
`Countersign Settings Pane`, in the standard user defaults of the process showing the window, the
same domain as the frame below, and for the same reasons never in `config.json`: it is how one
person last looked at the window, not something a hook reads. `SettingsWindowController` reads it
when it creates the window and writes it on every switch; a missing or unknown value opens Agents
(`SettingsPane(storedValue:)`), and a stored `"advanced"` reopens Advanced with App highlighted, the
same as reaching it through the button. `snapshot --settings` never reads or writes it and takes
`--tab` instead.

Switching group rebuilds the content area, so no view keeps its own state across it. What matters
lives in `SettingsModel`: the text in the Snooze presets field and the add field for Hand off when
frontmost, the open "Show changes" disclosures and "Show copies". The two text fields commit when
they disappear, exactly as when they lose focus (see "Writing a change"), so leaving a field by
switching group counts as leaving it. The scroll view's identity is the selected group, so each
group opens scrolled to its top. The scroll view asks for `.scrollIndicators(.visible)` and leaves
the scroller's style to the system setting; only the content column scrolls, never the sidebar.

Content scrolls only when it overflows the window, and never rubber-bands past either end:
`.scrollBounceBehavior(.basedOnSize)` turns bouncing off altogether when the content already fits,
and `ScrollElasticityDisablerView`, a tiny `NSViewRepresentable` sitting in the scrollable content,
sets its `enclosingScrollView`'s `verticalScrollElasticity` to `.none` as a backstop for when it
does scroll, so dragging past either end never shows empty space under the content. `SettingsContent`
carries its own trailing `SettingsMetrics.padding` inside the scroll view, so the last card's bottom
edge always has room to breathe above the window's edge once scrolled all the way down, rather than
sitting flush against it.

### Header

The header sits above the sidebar and the scroll view, full width, and never scrolls away: a 20 pt
`CountersignMark` (the same size as the panel's own header mark), "Countersign" in semibold, the
version in a smaller, secondary, selectable caption (`CountersignVersion.current`,
`.textSelection(.enabled)` so it can be copied into a bug report), then at the trailing edge a
caption naming an active state, a **Pause** icon, a **Snooze** icon and the **Close** button. Close
asks `NSWindow.performClose(nil)`, so it takes the same path as ⌘W and the window's own close
button, and the window closes at once; it is not the default button, since Return belongs to the
text fields. There is no footer: Close sits in the header.

The header is slim (12 pt above and below) and has the window background with a 1 px separator
along its bottom edge. The sidebar and the scroll view start right at that line, and the scroll
content keeps its own `SettingsMetrics.contentTopInset` so the first row is not glued to it:
content scrolls up to the line and disappears there, so the settings read as scrolling under the
header.

### Status

There is no longer a status card above the groups: a card that mostly said "Countersign is on"
spent a full row of height on the state that needs no attention, and the header now carries the
same controls in icon form. The state is the companion menu's own (`ApprovalCore.CountersignStatus`,
which `CompanionMenu` uses for its status line too), read from the same pause switch and quiet-time
files as `countersign status`. What each control shows and does comes from
`ApprovalCore.SettingsHeaderControls`, which the tests cover:

| State | Caption | Pause icon | Snooze icon |
| --- | --- | --- | --- |
| Active | none | secondary; click pauses (`StateSwitches.pause()`, exactly `countersign pause`) | secondary; click opens the popover of presets |
| "Paused" | "Paused" in yellow | yellow; click resumes (`PauseSwitch.resume()`, exactly `countersign resume`) | disabled |
| "Paused until Countersign opens" | the same words in yellow | as Paused | disabled |
| Quiet until 14:05 | "Until 14:05" in blue | secondary; click pauses, which ends quiet time first | blue; the popover reads "Quiet until 14:05" and **End now** (`QuietTime.clear()`, exactly `countersign snooze off`) |

The Snooze popover, opened beside the icon like the info buttons' popovers, lists the menu bar's
presets (`CompanionMenu.snoozeMinutes`, titled by `SnoozeTitle`) and each starts quiet time through
`StateSwitches.snooze(until:)`, exactly as the menu does. The Pause icon is its own control rather
than the old status action because the old action turned into End now during quiet time, and a
user who wants to pause during quiet time would have ended it instead.

"Paused until Countersign opens" is the pause the menu-bar companion's quit question can leave
behind, which ends when the companion starts again (see "Quit" in [app.md](app.md)); the header
reads it through `PauseSwitch.state`. The companion's own window never shows it, since the companion
ends that pause as it starts, but `countersign settings` run while the companion is closed does.
Paused wins over quiet time, as in the menu; after Resume, a quiet time still running shows next.
The controls act at once, like every control in the window. A failed write shows one red line under
the header row. The files change from other processes
(`countersign pause`, a panel's Snooze menu, the companion), so a repeating 2 s `Timer` in `.common`
mode reads them again while the window is open, the same interval as the companion's icon, and the
window reads them when it becomes key too.

### Panels and App

The window edits top-level keys only:

| Group | Control | Key | In the window |
| --- | --- | --- | --- |
| Panels | Wait for idle, a stepper | `idleSeconds` | `1` to `30` s, in 1 s steps |
| Panels | Grace period, a stepper | `graceSeconds` | `0` to `30` s, in 1 s steps |
| Panels | Arm delay, a slider | `armDelay` | `0` to `3` s, in 0.1 s steps |
| Panels | Arm delay after an answer, a slider | `chainedArmDelay` | `0` to `3` s, in 0.1 s steps |
| Panels | Hand off when frontmost, a list | `handoffApps` | bundle IDs, added and removed one at a time |
| Panels | Snooze presets, a text field | `snoozeMinutes` | `1, 5, 15, 30`: 1 to 6 whole numbers, each `1` to `1440` |
| Panels | Quiet hours, a list with day toggles and two `HH:mm` fields | `quietHours` | up to 7 windows, each with at least one day and different start and end times; the whole array is rewritten on every add or remove; errors `Pick at least one day` and `Enter a start and end time, like 19:00` |
| Panels | Notes on answers, a switch | `questionNotes` | on or off |
| Panels | Mode after a plan, a menu | `modeAfterPlan` | "Ask before edits", "Accept edits" or "Auto" |
| App | Launch at login, a switch | none, `SMAppService.mainApp` | see below |
| App | Check for updates, a switch | `checkForUpdates` | on or off |
| App | When Countersign quits, a menu | `quitBehavior` | "Ask", "Keep showing panels" or "Pause panels" |
| App | Appearance, a segmented control | `appearance` | "System", "Light" or "Dark" |
| App | Accent colour, six swatches and a color well | `accentColor` | Amber, Blue, Green, Purple, Pink, Graphite, or any color as `#RRGGBB` |

Every one of these rows is a `PreferenceRow`, the one component that lays out a row's title, its
caption, a trailing control, an optional detail below (Hand off when frontmost's list and add
field, the test panel's buttons) and the row's write error. For a config key the title and caption
come from `ApprovalCore.PreferenceName.title` and `caption`, so a row's words are defined in one
place, and the note on an agent's row (below) names its values with the same titles.

`ApprovalCore.PreferenceRules` holds the bounds and the parsing. The steppers are narrower than the
file, which takes any number `>= 0`: a stepper needs bounds, and these cover every useful value. A
value from the file outside them is shown as it is and clamped on the first step. Snooze presets are
separated by commas or spaces. Text that breaks the schema's rules shows one red line under the
field as it is typed and is never written (see "Writing a change" below). A new bundle ID is
trimmed and must be non-empty, without spaces and not already listed.

When `hosts.claude`, `hosts.codex`, `hosts.cursor` or `hosts.antigravity` sets a value, that
agent's row under Agents shows it in one quiet line, named the way the Panels rows name it, with
the value, in Panels order: "Own values in config.json: grace period 3 s", entries separated by
semicolons since a list value has commas of its own (`PreferenceOverrides.note(for:in:)`).
`includeHeadlessSessions` shows as "headless sessions on" or "off": no row sets it, but it is still
a value the file sets for that agent alone. The note sits on the agent's row because that is where
a person looks to see what one agent does differently, and a value there wins over the Panels row
for that agent. The window never edits a host block; those values stay in the file, for hand
editing, and the note's "Open in Editor" link opens it with the same `openConfigInEditor` as
Advanced. A failure to open it shows one red line under that note rather than in Advanced, which
may not be the group currently shown (`ConfigEditorOrigin`). A value the parser rejects is not
named, because the hook ignores it as well.

At the end of Panels, "Show a test panel" has three buttons, Command, Question and Plan
(`TestPanelKind.title`), in the window's secondary button style, below the row's caption: a menu
would need a style of its own, and three buttons show every kind at a glance. Each calls
`TestPanelLauncher.launch(kind:)`, the launcher behind the companion's "Show a Test Panel" (see
"Show a Test Panel" in [app.md](app.md)), which starts `countersign test-panel <kind>` as its own
process, so the panel reads the file the window has just written. Clicking a button leaves a text
field focused, so the model first commits a Snooze presets entry or bundle ID still being typed
(`commitEditing()`): the panel then shows what the window shows. The caption, "See your settings
in a real panel, right away. Nothing reaches an agent.", says the panel skips the grace period and
the idle wait. While the launcher's observable `isRunning` is true, whichever surface started the
test panel, the three buttons are disabled and "Showing a test panel…" follows them. A launch that
fails shows one red line on the row, "The test panel could not start: <error>", and so does a test
panel that refuses to show, "The test panel didn't show: <reason>", with the reason it printed
(see "One at a time, never ahead of a real request" in [panel.md](panel.md)). The row sits outside the config-backed rows, which a config file with a problem
disables: a test panel reads such a file as defaults, as a hook does.

"When Countersign quits" is a menu-style `Picker` over `QuitBehavior.allCases`, titled by
`QuitBehavior.title`, right after "Check for updates" and inside the same config-backed rows, so a
config file with a problem disables it too. It is written as soon as an item is chosen, like every
other preference; choosing "Ask" over another value writes `"ask"` rather than removing the key. It shows what the file holds, including
an answer the quit question's "Don't ask again" wrote, so it is where a person brings the question
back.

"Appearance" follows it: a segmented `Picker` over `AppearanceChoice.allCases`, titled by
`AppearanceChoice.title`. Three short choices fit side by side, so all of them show at once
instead of behind a menu. "Accent colour" comes last: a round swatch per `AccentPreset`, in the
preset's color, with a ring around the one that matches the accent, then a SwiftUI `ColorPicker`
without opacity for any other color. The swatches are buttons with the preset's name as their help
and accessibility label; the color well shows the current accent, preset or not, and opens the
system color panel. The window takes both at once: the model sets the Settings window's
`NSWindow.appearance` and `CountersignPalette`'s accent whenever it loads the file (see "Where the
accent and the appearance come from" in [panel.md](panel.md)), and every panel shown afterwards
reads them from `config.json` when it is created. A reset or Restore Defaults line names a preset
by its title and any other color by its `#RRGGBB` (`AccentPreset.name(of:)`).

Launch at login mirrors the companion's menu item (see "Launch at Login" in [app.md](app.md)):
registering or unregistering `SMAppService.mainApp`, with "Approve in System Settings" while macOS
waits for approval. `SMAppService.mainApp` means the running app bundle, so outside
`Countersign.app`, where the CLI binary has no bundle to register, the switch is disabled and reads
"Available in Countersign.app". Inside the app its caption says that macOS keeps this one, not
`config.json`, since the two switches below it in App are in the file.

### Writing a change

Every control in the window acts as soon as it is used, the way System Settings does: there is no
Save, no Revert and nothing unsaved, so closing the window or quitting the menu-bar companion never
asks about settings. A preference is written at the moment its control is done changing:

| Control | Written |
| --- | --- |
| Check for updates, Notes on answers (switches) | when flipped |
| Appearance (segmented control) | when a segment is chosen |
| Accent colour (a swatch) | when clicked |
| Accent colour (the color well) | 0.4 s after the color panel stops changing it, or when the window closes |
| When Countersign quits, Open with (menus) | when an item is chosen |
| Wait for idle, Grace period (steppers) | on each step |
| Arm delay, Arm delay after an answer (sliders) | when the drag ends |
| Snooze presets (text field) | on Return, or when the field loses focus or disappears |
| Hand off when frontmost (add field) | on Return, on Add, or when the field loses focus or disappears |
| Hand off when frontmost (a bundle ID's remove button) | when clicked |
| Snooze presets and the add field, still being typed in | when a test panel button is clicked |

A slider writes the value its drag ended on, not every value it passed through: a drag crosses up
to thirty 0.1 s steps, and writing each would rewrite the file, and wake any editor that has it
open, many times for one choice, while a hook starting mid-drag would read a delay nobody picked.
`DelaySlider` keeps the dragged value in view state, so the number beside the slider follows the
drag, and writes it when `Slider`'s `onEditingChanged` reports the end of editing. A change that
arrives with no drag in progress, such as one from the keyboard, is written at once.

The accent's color well has the same problem with no end-of-drag signal: the system color panel
sends a color for every point a drag in its wheel or sliders passes, and `ColorPicker` reports no
end of editing. `SettingsModel.pickCustomAccentColor(_:)` therefore keeps the latest color as
`customAccentColor`, applies it to `CountersignPalette` at once, so the window shows it live, and
writes it 0.4 s (`customAccentPause`) after the last change; `commitEditing()` writes one still
waiting when the window closes or the app quits. Choosing a swatch, or resetting the row, drops a
color still waiting instead of writing it.

The two text fields write when the person is done with them for the same reason: "1, 5, 1" on the
way to "1, 5, 15" is valid, and writing on each keystroke would write values the person only passes
through. Snooze presets are still checked on every keystroke, so a mistake shows at once. Closing
the window, or quitting, counts as the field losing focus: `windowWillClose` and each app
delegate's `applicationWillTerminate` (the companion's and the one `countersign settings` runs)
call `SettingsModel.commitEditing()`, which writes a valid Snooze presets entry and adds a typed
bundle ID, because SwiftUI's focus change cannot be relied on to arrive before the window, or the
process, is gone. Leaving the add field while it is empty adds nothing and shows no error; Return
or Add on an empty field shows "Enter a bundle ID".

A value the controls already show is not written. `ApprovalCore.PreferenceValues` holds the values
read from the file, and `applying(_:)` gives the values an edit would leave; when the two are equal,
such as a slider clicked without moving, the current menu item chosen again, or Return in an
unchanged field, nothing is written and no backup is taken. Otherwise the write reads the file,
applies that one edit through the minimal-diff editor described in "Why minimal-diff editing" in
[setup.md](setup.md), and replaces the file atomically through `ConfigFileStore`, only when its
bytes changed, then reads it back, so the controls always show what the file holds:

- Only the edited key is touched: a value is replaced, or the key is appended after the last
  member in the file's own style. Every other byte stays, including `hosts`.
- A missing or blank file is created from `ConfigFileStarter.contents` first, so it starts with the
  `$schema` reference.
- A value the file already holds, however it is spelled (`0.80` for `0.8`), stays as written. A
  value equal to the built-in default is still written when the person chose it over another value
  in the file: they chose it, and a later change to the default should not change their setting.
- A `handoffApps` that is not a list of strings is replaced by a list with the new ID, since the
  window showed the default in its place.
- The file is backed up the way setup backs up a hook file (see "Backups and writing" in
  [setup.md](setup.md)), once per window session, before its first write, not once per change.
  The first backup already holds the file as it was before the session, which is the copy worth
  keeping; a backup per change would leave dozens of copies after a few stepper clicks; and a
  backup's name has one-second resolution, so two changes within the same second would need the
  same name and the second write would fail. A window session is one `SettingsModel`: each time the
  window opens, the first write backs up again.

Text that breaks the rules is not written. Snooze presets that fail `PreferenceRules` show their
red line under the field, the file keeps its last value, and the field keeps the text with its
error until the person fixes it, so they can see what was not taken. A new bundle ID that is
empty, has spaces or is already listed shows its red line under the add field and is not added.

A failed write shows one red line on that control's row (`InlineMessage` with the problem tone,
held in `SettingsModel.writeErrors` under the edit's `PreferenceName`), and the control shows the
file's value again: the model shows the chosen value while it writes and puts back the values read
from the file when the write fails, so a switch flips back rather than claiming a value the file
does not hold. The line stays until a write from that row succeeds. A bundle ID whose write failed
stays in the add field, so Return tries again.

A config file that cannot be read, is not valid JSON, or whose top level is not an object disables
the controls that write it, in Panels and in App, with the reason in one line at the top of each of
the two groups, so it shows whichever group is open; Launch at login, the test panel buttons and
"Open in Editor" still work.

The window reads the hosts' files again whenever it becomes key, and the config file too when its
bytes changed on disk, so a change made in an editor shows up when the person comes back to the
window. That reread never replaces text the person is typing: while the Snooze presets field has
the focus, or shows an error, it keeps its text, and the add field is never touched by a reread.
Every other control shows the file's new value. A write reads the file again first, so it lands on
top of an edit made elsewhere instead of undoing it.

The agent rows' Wire, Update and Remove (each shows its diff first under "Show changes"; see
"Agents" in [setup.md](setup.md)), the Launch at login switch, which registers a login item with
macOS rather than writing a config value, the header's Pause, Resume, Snooze and End now, the test
panel buttons and "Open in Editor" act at once too, each on its own file, a process or macOS, never
on a preference beyond committing the text fields as the table says.

### Context checkpoints

The Panels tab ends with the switch "Context checkpoints (Claude Code)", showing the file's
`contextCheckpoints.enabled`. It is the one Panels row that changes a host file, so flipping it
writes nothing: it opens a confirmation popup (`ContextHookPrompt`, an `NSAlert` sheet on the
Settings window like `RestoreDefaultsPrompt`; the model's `contextChange` is what the row presents,
and confirm and cancel stay model calls). The popup asks "Turn on context checkpoints?" or "Turn
off context checkpoints?" ("Update Countersign's Claude Code hook?" from the hook row), says
"Countersign changes <path> and keeps a backup.", and shows the diff `ContextHookRun.preview` gives
for Claude Code's `settings.json` in a selectable monospaced scroll view about 12 lines tall, with
two buttons, "Turn On" or "Turn Off" (primary) and "Cancel". A preview with failures shows the
failure lines and only "OK"; dismissing it changes nothing and leaves the failure as the row's red
line. The primary button applies the hook change through
`ContextHookRun.apply` (a backup of the file, like every hook-file write), and only then the
config and state change: on, it writes `contextCheckpoints.enabled: true`; off, it removes the
`UserPromptSubmit` entry, deletes the files in `AppPaths.contextCheckpointsDirectory`
(`ContextCheckpointStore.removeAll()`) and writes `enabled: false`. Everything else in
`contextCheckpoints` is kept, so turning it on again finds the thresholds and notes as they were.
A failure in the hook step shows one red line on the row and changes nothing else. The order
matters: the config never says "on" while the hook is missing because of a failed write. If Claude
Code's directory is missing the switch is disabled and the caption reads "Claude Code isn't
installed."

The Context tab appears in the sidebar only while the feature is on. The stored pane falls back
to Agents when it is off (`SettingsPane(storedValue:showsContext:)`), and turning the feature off,
here or in the file, while Context is showing selects Panels. Its rows, in order: the hook status
(Wired, Not wired or Needs an update, from `ContextHookRun.status`, with "Update" for the last two,
which shows the same popup as the switch and never touches the config), Checkpoint
style, the 200K and 1M ladders, the per-model ladders, Start over below, Handoff file, Notes (one
row with an "Edit Notes…" button), Context in the menu bar, a button that shows a context test panel, and a last row with "Turn Off Context Checkpoints" left of Restore Defaults. That button calls `requestContextCheckpoints(false)` and so shows the same "Turn off context checkpoints?" popup as the Panels switch (the row presents it for the `.toggle` origin, and only one tab is on screen at a time, so one `contextChange` shows one alert); it is disabled while a change is pending or Claude Code isn't installed.

Write rules follow the table above. The two ladder fields take three ascending whole numbers of
thousands, 1 to 2000 (`PreferenceRules.contextLadder`), checked on each keystroke, and are written
on Return, blur or disappearance; an invalid value shows "Enter three ascending numbers of
thousands of tokens" and is never written. The per-model list adds a pair (prefix, ladder) on Add
or Return in either field, like Hand off when frontmost, and removes one with its button. Start
over below is a slider from 10 % to 95 % in steps of 5, written when the drag ends. The handoff
file is written on blur, Return or disappearance; empty shows "Enter a file path".
`commitEditing()` commits every pending ladder and handoff file field, so leaving the window or
showing a test panel never drops one.

The notes are edited in a sheet (`ContextNotesSheet`, a SwiftUI view in an `NSHostingController`
presented with `beginSheet`, the way the tour is), about 560 by 620, titled "Context notes", whose
caption names the `{tokens}` and `{handoffFile}` placeholders. It shows the five notes in order,
each with its caption, an editor about five lines tall and a "Restore Default" button enabled only
while the text differs from the default. The pending texts live in the sheet's own state, not in
`contextTexts`, and nothing is written on blur, so `commitEditing()` no longer touches the notes.
"Cancel" (Esc) discards every edit. "Save" (Return, the default button) checks all five with
`PreferenceRules.contextNote` first (empty shows "Enter the note", and a note is at most 4000
characters, the limit the config parser enforces), and writes the changed ones only when every
note is valid; otherwise the sheet stays open with the red line under the offending note, and a
failed write keeps it open too. The Context pane's Restore Defaults still resets the notes.

`contextCheckpointsEnabled` is in no pane's Restore Defaults and has no reset arrow: restoring
defaults must not unwire a hook file or delete state. The Context tab's Restore Defaults covers
its own rows only.

### Resetting to defaults

Every Panels and App row backed by a `PreferenceName` can be reset on its own, and so can
Advanced's Open with. `PreferenceReset` decides, per name, whether the file's top-level value
differs from `Settings.default*`: `ConfigFile`'s fields are `nil` both when a key is absent and
when the parser rejected its value (both fall back to the same default and `ConfigFile` keeps no
separate record of which happened), so "changed" here means "present in the parsed file with a
value that isn't the default" — the same rule the parser already uses to decide whether a value
reaches the row at all. `editorApp` has no `Settings.default*` to compare against, since its
default is absence rather than a value; "changed" for it means only "present in the parsed file",
whatever the string. A row's reset
button (the SF Symbol `arrow.uturn.backward`, left of the control) shows only when that is true
and the row was changed in this visit. The arrow is an undo for what the person just did, not a
standing marker of every non-default value: a row that differs from its default but was set in an
earlier visit shows no arrow, and Restore Defaults is the way back for it. `SettingsVisit` in
`ApprovalCore` is the bookkeeping: `SettingsModel` records the names of every successful write's
edits (`PreferenceEdit.key`), forgets the names a row reset or Restore Defaults resets, and begins
a fresh visit, emptying the set, when the selected pane changes (`select(_:)`) and whenever the
Settings window is shown, first show and every re-show. `SettingsModel.isResettable(_:)` is
`isChanged(_:) && visit.contains(_:)`, and the button follows it on every pane. Restore Defaults
ignores the visit: it is enabled whenever the pane has a value that differs from its default.
Clicking the arrow writes `PreferenceEdit.reset(name)`, which `ConfigEdit` turns into removing that
top-level member with `JSONSourceDocument.removeMember`, the same minimal-diff editor every other
edit uses; it is a no-op when the key is already absent, and it never reaches into `hosts` or
touches `$schema`, since the key it removes is always one of `PreferenceName`'s own. A reset goes
through the same `SettingsModel` write path as any other edit, so it takes the one-per-session
backup and shows the same red line on failure; pending text in the Snooze presets field or the
Hand off when frontmost add field is discarded rather than committed first, since a reset means
"forget what I was typing here too."

Panels and App each have a **Restore Defaults** button at the bottom of their group
(`SecondaryButtonStyle`), disabled when `SettingsModel.changedNames(in:)` for that group's
`SettingsPane.preferenceNames` is empty. Clicking it opens an `NSAlert` sheet on the Settings
window, built the way the quit prompt's alert is (`RestoreDefaultsPrompt`, mirroring `QuitPrompt`):
"Restore the Panels defaults?" or "Restore the App defaults?", informative text with one
`<title>: <current> → <default>` line per changed setting in the group
(`PreferenceReset.confirmationLines`, reusing the rows' own formatters: seconds as the stepper and
slider show them, the snooze list as the text field shows it, hand-off apps as a count, booleans as
On/Off, quit behaviour by its titles), plus one more line, "Values set for one agent under hosts in
config.json stay as they are.", only when some `hosts.<agent>.<key>` in the file sets a key in that
group — since Restore Defaults, like every row's reset, only ever touches the top level. Confirming
writes every changed name's `.reset` edit in one call, so it is one backup and one file write, not
one per row.

Launch at Login has neither a reset button nor a place in App's Restore Defaults: macOS's login
item isn't a `config.json` value, so there is no default in the file to restore it to, and clicking
Restore Defaults for App must never touch it.

`snapshot --settings --restore-prompt panels|app` renders the confirmation alert's content view
offscreen against the given `--home`'s config, the same way `--quit-prompt` renders the quit
question, for checking the exact wording without opening a window.

### Explanations

Every Panels and App row backed by a `PreferenceName`, and Launch at Login, carries two pieces of
text beyond its title and caption, both defined once and reused everywhere they're shown:
`PreferenceName.explanation` (2 to 4 plain sentences: what the setting does, when you'd change it,
and how it relates to a neighbouring setting, such as arm delay against arm delay after an answer,
or wait for idle against grace period) and `PreferenceName.defaultText` (the built-in default,
spelled out — "0.8 seconds", "1, 5, 15 and 30 minutes", "No apps" — read from `Settings.default*`
through the same formatters the rest of the module uses, so a changed default changes the text
without anyone hand-editing a string). Launch at Login isn't a `PreferenceName`, so its explanation
and default text ("Off") are constants next to its caption in `LaunchAtLoginRow` instead.

The title-and-caption block of a `PreferenceRow`, and of `LaunchAtLoginRow`, carries `.help(
explanation)` as a hover tooltip, and the title gains an info button (SF Symbol `info.circle`,
borderless, secondary) that opens a `.popover` holding `SettingsExplanationView`: the explanation,
then a secondary "Default: `<defaultText>`" line. The Test panel row and Advanced's other rows
have no `PreferenceName` and get neither; Open with does, and gets both like any Panels or App
row. The reset button introduced above also reads its `.help` text
from `defaultText` now, rather than formatting the default itself, so the two places a person can
learn "what does resetting this give me back" agree on the wording.

`snapshot --settings --explanation <preferenceName>` renders `SettingsExplanationView`'s content
alone, at its natural width, since a `.popover`'s chrome and arrow can't be drawn offscreen; it
needs no `--home`, since both `explanation` and `defaultText` are pure functions of the name and
the built-in defaults, never of a config file.

### Accessibility

- **Header caption.** The `Paused` and `Paused until Countersign opens` captions use
  `HeaderControlTint.amber`, not `.yellow`. System yellow is about 1.3:1 on the light window
  background; amber is `sRGB(0.55, 0.36, 0)` on light, about 4.8:1, and system yellow on dark,
  where it already clears 4.5:1. The Pause icon keeps `.yellow`, since an icon needs only 3:1. The
  Pause button also reads its state through `SettingsHeaderControls.pauseAccessibilityValue`
  (`Paused` or `Not paused`), so VoiceOver does not depend on the colour.
- **Sliders.** `DelaySlider` and `ContextRearmSlider` take the row title as their accessibility
  label and the shown text (`0.8 s`, `60%`) as their value; the separate value text is hidden so
  it is not read twice. A VoiceOver adjustment arrives while no drag is in progress, so it takes
  the non-dragging branch and commits at once, the same as a drag end.
- **Sidebar.** The selected pane's row carries the `.isSelected` trait, Advanced counting as
  selected under App, as it does visually. The row icons are hidden; the pane title names the row.
- **Decorative glyphs and status rows.** Icons that repeat the text beside them are hidden from
  VoiceOver: the agent status glyph, the inline message, note and follow-up symbols, the
  disclosure chevron, the app-link glyph and the installed-copy radio glyph (the row carries
  `.isSelected` instead). An agent row reads its name and its status line as one element, and an
  inline message reads as one element.
- **Increase Contrast.** The header rule, `SettingsDivider` and the `SettingsGroup` border use
  `SettingsHairline` and the group stroke, which switch from `Color.primary` at 8 to 12 percent
  opacity to the solid `separatorColor` when `colorSchemeContrast` is `.increased`.

### Help

Unlike Advanced, Help sits in the sidebar as a normal `SettingsPane` case, since it needs no config
file to disable and nothing in it depends on `hosts` or a second copy. Its subtitle,
`SettingsPane.help.subtitle`, is the only description any of this needs: `preferenceNames` is empty,
so it never appears in a Restore Defaults line or a reset button.

The group holds three `SettingsGroup` cards, `HelpSection` in `SettingsHelpView.swift`, separated by
`SettingsSection`'s own spacing rather than a metric of their own:

1. Tour, Documentation, Ask a question, Report a problem, Contact the developer, each a
   `PreferenceRow` with a single trailing button and no `PreferenceName` behind it (like the Test
   panel row and Advanced's rows, they carry no info button or reset). Show the Tour calls
   `SettingsModel.requestTour`, a closure `SettingsWindowController.init` sets to
   `presentTourIfNeeded(force: true)`, the same call the companion's own "Show the Tour" menu item
   reaches through `openSettings(forceTour: true)`. Documentation, Ask a question and Contact the
   developer open `CompanionMenu.documentationURL`, `.askAQuestionURL` and `.contactDeveloperURL`
   the same way the companion's Help submenu does, skipping the button when the URL is `nil`, and
   Report a problem calls `ReportProblem.url()`. That type, in `ReportProblem.swift`, holds the body
   `MenuBarCompanion.openReportAProblem` used to build inline: `Doctor.report` over
   `DoctorCommand.gatherInput()`, joined and passed to `BugReportURL.build` with the macOS version,
   `CountersignVersion.current` and the home directory to mask. The companion now calls
   `ReportProblem.url()` too, so the menu and Settings build the exact same URL from one place, and
   opening it goes through plain `NSWorkspace.shared.open`, not the companion's `openInDefaultApp`,
   since Settings has no menu-triggered failure to log.
2. Updates, one row reporting `SettingsModel.updateCheckPhase` (`idle`, `checking`, `upToDate`,
   `newerAvailable(UpdateAvailability)` or `failed`) in its caption, with `checkForUpdates()`
   awaiting `UpdateFetcher.fetch(currentVersion:)` on the model, the same fetcher the companion's
   scheduled and manual checks use, and turning the outcome into a phase with the same
   `Bundle.main.executableURL`-derived upgrade command as `MenuBarCompanion.currentUpdateAvailability`.
   Settings never reads or writes `update-check.json`: it has no scheduled check to persist a last
   attempt for, and a person who wants that behaviour already has the companion running. Because a
   fourth "Copy Upgrade Command" or "Release Notes" button next to "Check for Updates" can outgrow
   the row's width beside a short caption, the row's control is `EmptyView()` and its buttons live in
   `detail`, the same full-width slot Show a test panel's three buttons and Hand off when frontmost's
   list use, rather than trailing the title the way a Panels or App row's single control does. Copy
   Upgrade Command reuses `SettingsModel.copy(_:)` and its "Copied" flip through a new
   `SettingsCopyTarget.upgradeCommand`, read back from `updateCheckPhase` rather than stored
   separately, so there is exactly one source of truth for the current upgrade command.
3. Support Countersign, one row with up to two buttons, Sponsor on GitHub and Buy Me a Coffee, each
   skipped when its `CompanionMenu` URL is `nil`, mirroring the companion's own "Support the
   Developer" submenu (`CompanionMenu.supportEntry`).

`snapshot --settings --tab help` renders the group like any other pane, through the same
`SettingsPane(rawValue:)` the other tabs use; no new snapshot flag was needed.

### Advanced

The group shows the config file's path, "Open in Editor" (which creates the starter file when it
is missing, then opens the file with the chosen app), "Copy Path", "Open with", the schema's URL
as a link, a line naming what only the file can set, and a prompt to paste into a coding agent,
with a "Copy" button (`SettingsPrompt`).

"Open with" (`PreferenceName.editorApp`) is a `PreferenceRow` like a Panels or App row, with the
same info button and reset button; it just lives in Advanced because it changes what "Open in
Editor" does rather than a panel or the menu-bar app. Its control is a `Menu` titled with the
chosen app's name, or the default app's name when none is chosen: "Default app (<name>)" first,
then one item per app from `NSWorkspace.shared.urlsForApplications(toOpen:)` for `config.json`
(name and icon, the same apps Finder's own Open With offers), a divider, then "Other…", which
opens an `NSOpenPanel` scoped to `/Applications` and `.application`. Choosing an app writes its
bundle identifier with `PreferenceEdit.editorApp`; choosing "Default app" resets it like any other
row. `SettingsModel.openConfigInEditor` resolves the stored bundle ID to a URL with
`NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` and opens the file with
`NSWorkspace.shared.open(_:withApplicationAt:configuration:)`; when that lookup fails because the
app was uninstalled since it was chosen, it falls back to the default app and shows "<bundle id>
is not installed; opened with the default app." under the config path block, the same place a
plain open failure shows, since both origins are `ConfigEditorOrigin.advanced`. An agent's own
"Open in Editor" link on its row (`ConfigEditorOrigin.host`) goes through the same method, so it
opens with the same chosen app and falls back the same way.

The line reads "Only the file can set values for one agent, under hosts, and
includeHeadlessSessions." (`PreferenceOverrides.fileOnlyNote`). Its keys are computed, not listed
by hand: the parser's top-level keys minus every key a row writes anywhere in the window
(`PreferenceName`) and minus `hosts` and `$schema`, so a key added to the file without a row is
named here without anyone remembering to, and a test pins today's list. The prompt:

```text
Change my Countersign settings in <path>: <what you want>. The file follows the JSON Schema at
https://raw.githubusercontent.com/Gord1y/countersign/main/schema/config.schema.json; keep every
other key as it is.
```

### The first-run tour

The window shows a four-step tour the first time Settings opens: whenever
`SettingsWindowController.show(forceTour:)` runs with `forceTour` false, which is every path that
opens the window except the menu bar's Help ▸ Show the Tour, it presents the tour as a sheet
(`window.beginSheet`, an `NSHostingController<FirstRunTourView>`) unless
`AppPaths.tourShownFile` already exists. Skip or Done, on any step, creates that empty file and
ends the sheet; Back and Next swap the hosting controller's `rootView` for the neighbouring step
without tearing the sheet down. Closing the settings window while the tour is up ends the sheet
without creating the file, so the tour is still owed next time.

The steps, their titles and bodies, and the count, live in `ApprovalCore` as `FirstRunTourStep`
and `FirstRunTour`, so they're covered by `ApprovalCoreTests` like every other piece of copy; a
body is a `[FirstRunTourSegment]` of `.text` and `.key` pieces rather than one string, so
`FirstRunTourView` can render the three keys in "How a panel waits" as the same `KeyHint` keycaps
the panel itself uses, in place of the raw ⏎, ⎋ and ⌫ glyphs, and a custom `Layout` flows text and
keycaps together with normal word wrap.

`AppPaths.tourShownFile` sits in the state folder, `~/Library/Application
Support/Countersign/tour-shown`, next to `paused` and `quiet-until`, not in the config file and not
in `UserDefaults`: it isn't a preference a person sets, it's "has this Mac seen the tour", and the
state folder is the one place both Countersign.app and a `countersign settings` run from the
terminal already read and write without disagreeing (see "What it writes" in
[safety-and-privacy.md](../safety-and-privacy.md)). `UserDefaults` would tie it to
`Countersign.app`'s bundle identifier alone and miss the CLI entirely.

The menu bar's Help ▸ Show the Tour opens Settings and presents the tour with `forceTour: true`,
skipping the `tourShownFile` check, so it always shows regardless of whether it's been seen.
`countersign snapshot --tour 1|2|3|4` renders one step's `FirstRunTourView` alone, the same way
`--quit-prompt` renders the quit question's content view (see "Snapshots" in
[panel.md](panel.md)).

### More than one copy

When more than one copy of Countersign is installed (which copies count, how they are marked and
the steps are in "More than one copy installed" in [setup.md](setup.md)), the Agents group opens
with a notice above its rows, "Two copies of Countersign are installed", the count spelled out up
to four. It is an `InlineMessage` with the warning tone, an orange triangle beside text in the
primary colour, so it reads as a heading rather than an error; below it, "Show copies" discloses
the rest with the same chevron as an agent row's "Show changes":

- one line on why it matters: each copy updates on its own;
- the question, "Which one do you want to keep?", in 13 pt semibold;
- one choice per copy: a radio circle, filled in the accent colour when selected, its name and
  version ("Installer 0.1.0"), a green "Hooks call this one" chip and "Running now", "Newest" and
  "Menu-bar app" chips where they apply, and its paths, one per line; the whole row selects it;
- "To keep Countersign.app 0.2.0:" and the steps for the selected copy, each a sentence, and when
  it has a command, a Copy button beside the sentence that reads "Copied" for 1.5 s, like Copy
  Path, and the command in a code card;
- a "Copy a Prompt for Your Agent" button, which reads "Copied" the same way, with the caption
  "Paste it into Claude Code, Codex or any agent to talk it through."

The selection starts on `DuplicateInstall.suggestedIndex`, usually the newest, and is kept across
refreshes while the list of copies stays the same; a different list, such as after a copy is
removed in the terminal, selects the suggested copy again.

The notice has no button that removes or rewires anything, for the reasons in setup.md. The
window looks for copies whenever it reads the hosts' files, on opening, on becoming key and after a
host button, so running the command in the terminal and coming back clears the notice. With one
copy there is no notice and nothing else changes.

Above it, even with one copy, a second notice appears when the installer's menu-bar app and
command-line tool are on different versions (see setup.md): the same warning `InlineMessage` with
`InstallVersionMismatch.title`, such as "The menu-bar app is older than the command-line tool", then
its advice with a Copy button and the command that updates the older half in a code card. It is
checked in the same refresh as the copies.

The context rows edit the top-level `contextCheckpoints` block by key path: every `PreferenceName`
has a `keyPath` (`[rawValue]` for the flat keys, such as `["contextCheckpoints", "thresholds",
"200k"]` for the 200K ladder), and `ConfigEdit` finds or creates each object on the way down and
sets or removes only the leaf, in the file's own style, so every other byte stays. A reset removes
the leaf member only; an object left empty stays as `{}`. The window never edits
`contextCheckpoints.hosts`, the same rule it follows for the top-level `hosts`, so
`contextCheckpoints` no longer counts among the keys only the file can set. The switch that turns
`contextCheckpointsEnabled` on wires a hook, so it belongs to no pane's `preferenceNames` and
Restore Defaults never flips it.

## Why snapshot never reads the file

`countersign snapshot` renders `PanelModel`/`PanelRootView` directly, with no `PanelController`
and no config read, so its PNGs stay identical on every machine regardless of what settings a
person or a CI runner happens to have on disk. `PanelController`'s and `PanelModel`'s `armDuration`,
`snoozeMinutes` and `questionNotes` parameters default to the built-in values (`0.8`,
`[1, 5, 15, 30]` and `false`), and `SnapshotCommand` passes none of them unless asked, so it stays
config-independent. `--question-notes` is the one way to see the question view with notes on in a
snapshot, since there is no config file to flip a switch in, and `--accent #RRGGBB` the one way to
see another accent than amber; see "Snapshots" in [panel.md](panel.md).

`snapshot --settings` is the exception: the settings window shows nothing but what the files say,
so it reads the hosts' files and the config file through `CLAUDE_CONFIG_DIR`, `CODEX_HOME` and
`XDG_CONFIG_HOME`, which a fixture points at directories of its own (see "Snapshots" in
[panel.md](panel.md)). Cursor's and Antigravity's files have no such variable, so without
`--home` their rows reflect the real `~/.cursor/hooks.json` and `~/.gemini/config/hooks.json`;
`--home <dir>` roots every host's file and the config file under `dir` instead, ignoring those
variables, and reads the installed copies under `dir` too. It never writes any of them, nor the
Codex hook trust record: the window saves a hash it learns there on every refresh (see "Who writes
the record" in [setup.md](setup.md)), and the snapshot builds its `SettingsModel` with
`savesLearnedCodexTrust: false`.

## The schema

`schema/config.schema.json` is a JSON Schema (draft 2020-12) for editor validation, referenced from
a config file's own `$schema` key. Its `$id` is the file's URL on GitHub, so an editor can fetch it
straight from a config file's `$schema` key. `ConfigSchemaTests` reads the schema's top-level and
`$defs.hostOverrides` property
names and checks them against `ConfigFileParser.topLevelKeys`/`hostKeys` directly, so the two
cannot silently drift apart.
