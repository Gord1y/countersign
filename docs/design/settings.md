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

## Time values and units

Every time key accepts a number in its own unit or a string `^[0-9]+(\.[0-9]+)?(ms|s|m|h)$`; the
keys and their units are unchanged (seconds for `armDelay`, `chainedArmDelay`, `idleSeconds` and
`graceSeconds`, `waitingNoticeDelay` and `approvalCardDelay`, minutes for `snoozeMinutes`), so an
existing file reads exactly as before. `waitingNoticeDelay` replaced `waitingNoticeMinutes` before
that key ever shipped, so there is no migration and the old key is an unknown key. `ConfigFileParser.durationValue` converts either form to seconds, and every range
check runs on those seconds: arm delays `0...3` (clamped), idle `1...30`, grace `0...30`, a snooze
preset `10 s...24 h`, the notice delay `10 s...1 h`. The model is in seconds throughout:
`Settings.snoozePresets` and `Settings.waitingNoticeDelay` are `TimeInterval`s, and the file keys
keep their names because they are the contract users already have.

Writing keeps the file as the person would write it. The seconds keys are written as numbers with up
to three decimals, because a typed value keeps millisecond precision (`PreferenceRules.armDelay`
rounds to 0.001 s; the slider rounds to 0.1 s through `sliderArmDelay`). The minutes keys are
written as an integer when the value is whole minutes and otherwise as the `DurationText.compact`
string, the largest unit that is exact with no space (`500ms`, `1.5s`, `90s`, `2m`, `90m`), so a
preset list reads `["30s", 5, 15]`. A value that already holds the choice, in either form, is left
untouched.

The duration fields in Settings accept the same words. The snooze text field accepts them too, with a bare number as minutes, and shows whole minutes
as bare numbers and anything else through `compact`. `SnoozeTitle` titles a preset that is not whole
minutes in seconds (`90 seconds`), because `DurationText.describe` rounds to the nearest minute.

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

### Opening

The model reads `config.json` before it derives any agent row. The window reads the hosts' files,
the config file and the installed copies again before it is ordered in front, on a new window and
on one reused from an earlier open, so the first frame shows the current state and never a verdict
from defaults or from the last visit. It reads them once more whenever it becomes key.

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
they are the state Countersign is in right now, not a setting. Below the header, a sidebar lists Agents, App, Panels, Rules (and Context while that feature is on) and Help,
in that order, at every window width (`SettingsPane.sidebar`; `ApprovalCore.SettingsPane` also holds
each group's title and subtitle). The selected item is highlighted; the content area to its right
shows that one group, scrolled to its top, with only its subtitle above it, not its title again,
since the sidebar already names it:

| Group | Holds | What it changes |
| --- | --- | --- |
| Agents | a row per agent (Wire, Update and Remove, each confirmed in a popup that shows its diff), the notice about a second copy, on each row the values `hosts.<agent>` sets, and, once wired, its follow-up line and Codex's "Mark as done" (`AgentFollowUp`; see "Follow-up lines" and "The Codex hook trust record" in [setup.md](setup.md)) | each agent's own hook file; the Codex hook trust record, never `config.json` |
| Panels | five blocks: Delays (Same delays for all agents, then while it is off an Agent picker with the four agents, then Wait for idle, Grace period, Arm delay, Arm delay after an answer, Show card after), Interruptions (Hand off when frontmost, Snooze presets, Quiet hours, Sound), Corner cards (Waiting-agent notices, Notice after, Show notice for, Approval card with one checkbox per agent), Claude Code (Notes on answers, Mode after a plan, Context checkpoints) and Try it (Show a test panel, Show a test card), then Restore Defaults | `config.json`, for every agent, or under `hosts.<agent>` for the delays and the Approval card checkboxes |
| App | General (Launch at login, Check for updates, When Countersign quits), Appearance (Appearance, Accent colour) and, while there is an offer to link Countersign.app, Install, then Advanced… and Restore Defaults | macOS's login items, `config.json`, `~/Applications` |
| Rules | the intro line, one row per rule in file order with a remove button, the unreadable-entries notice (see "Rules" below) | `config.json`, the top-level `rules` array |
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

Panels, App and Context split their rows into titled blocks (`SettingsBlock`, stacked by
`SettingsBlocks`). Each block is a `SettingsGroup` card whose first line is its title in 13 pt
semibold, the way the Rules tab's Suggestions card is titled, and blocks sit
`SettingsMetrics.blockSpacing` (14 pt) apart. A block gathers the rows that answer one question
(how long panels wait, what keeps them away, the corner cards, what only Claude Code uses, trying
it out), so a pane of twenty rows reads as five short cards instead of one long one. The pane's
footer buttons (Restore Defaults; Advanced… on App; Turn Off Context Checkpoints on Context) sit
below the last block, outside any card, flush with the cards' right edge. Titles above the cards,
in the System Settings manner, and untitled cards were both rendered in light and dark and set
aside in favour of titles inside, which match the Rules tab.

Action buttons (Show a test panel, Try a checkpoint, Check for Updates and its companions) sit on
the right of their row like every other control, never below it; a long caption wraps onto more
lines instead of shrinking the buttons.

Advanced (the config file's path, Open in Editor, Copy Path, Open with, the schema, what only the file
can set, and the prompt for a coding agent) has no place in the sidebar: it is reached through an
**Advanced…** button below App's blocks, sharing its row with Restore Defaults.
Clicking it selects
`SettingsPane.advanced` (`SettingsModel.select(_:)`), which shows Advanced's content in the same
area, with a **‹ App** link above it that selects `.app` again; the sidebar keeps App highlighted
the whole time, since `.advanced` is not one of its rows (`SettingsSidebar.isSelected(_:)` treats
App and Advanced as the same row). `SettingsPane.advanced` remains a real case: it is still what
`--tab` takes, just not listed in the sidebar.

Every open starts on Agents (`SettingsPane.standard`). Each `SettingsWindowController` makes a new
`SettingsModel`, and the menu-bar app makes a new controller whenever the window was closed, so
closing Settings and opening it again lands on Agents; choosing Settings… while the window is still
open keeps the group on screen. Agents is where an upgrade or a new agent needs attention, so a
remembered group could hide it. Up to 0.1.0 the group was remembered under the user-defaults key
`Countersign Settings Pane`; nothing reads that key any more. A caller that needs another group
passes it to the companion's `openSettings(pane:)`, and `snapshot --settings` takes `--tab`.

Switching group rebuilds the content area, so no view keeps its own state across it. What matters
lives in `SettingsModel`: the text in the Snooze presets field and the add field for Hand off when
frontmost, and "Show copies". The two text fields commit when
they disappear, exactly as when they lose focus (see "Writing a change"), so leaving a field by
switching group counts as leaving it. The scroll view's identity is the selected group, so each
group opens scrolled to its top. Only the content column scrolls, never the sidebar.

#### Scrolling

The content column is an AppKit `NSScrollView` (`SettingsScrollView`) whose document view hosts
`SettingsContent` in an `NSHostingView`, not a SwiftUI `ScrollView`. On macOS, SwiftUI's `ScrollView`
re-lays out the whole hosted pane and re-runs hover hit-testing through every row on each scroll
frame: a `sample` of fast scrolling on Panels showed the main thread about 19% busy even with
elasticity fixed, about 525 of 6434 samples in `NSHostingView.layout` and about 318 in hover
hit-testing. An `NSScrollView` scrolls by moving the clip view's bounds over content that is already
drawn, so a scroll frame runs neither. The document view is pinned to the clip view's top, leading
and trailing edges and takes its height from the hosted content's intrinsic size, so rows that
expand or collapse resize it and the scroller follows.

The document view is a plain flipped `NSView` (`SettingsDocumentView`) with the `NSHostingView`
pinned to all four of its edges, not the hosting view itself. `NSHostingView` overrides
`scrollWheel(with:)`, so its class answers false to `isCompatibleWithResponsiveScrolling`, and
AppKit then scrolls on the main thread (`NSScrollingBehaviorSingleThreadedVBL`) instead of its
concurrent responsive path. An Animation Hitches trace of fast trackpad scrolling on Panels in that
setup showed the main thread only 3.7% busy, yet about 10% of frames presented one refresh late,
and a long main-thread iteration preceded only about one in five of those: the frames waited on the
main-thread scroll cadence, not on work. A plain `NSView` is compatible, and scroll events still
reach the hosting view first, which passes the ones SwiftUI doesn't use up the responder chain to
the scroll view. The container must be flipped: the clip view takes its flippedness from the
document view, and an unflipped one would open each group scrolled to the bottom.

It keeps the old behaviour: no rubber-banding (`verticalScrollElasticity = .none`), an always
visible vertical scroller, no horizontal scrolling, and each group opens at the top (the
representable scrolls the clip view to its origin when the selected group changes).
`SettingsContent` carries its own trailing `SettingsMetrics.padding`, so the last card's bottom edge
has room above the window's edge once scrolled all the way down.

Every pane opens at its top because the hosted root is measured at the width it is shown at.
`NSHostingView` computes its intrinsic size from an unspecified proposal, so a line that only wraps
at the real column width (Agents' long "Points at ..." paths) made the height too short: the
content was taller than the document view, SwiftUI centred the overflow, and the pane opened with
its top cut off while the clip view's origin was still 0. `SettingsDocumentView.layout()` therefore
hands the hosted root (`SettingsDocumentContent`) the document view's width whenever it changes,
and the root wraps `SettingsContent` in `.frame(width:)`, so the intrinsic height is the height at
that width. Constraints still carry it to the document view.

The root also fixes its vertical size (`.fixedSize(horizontal: false, vertical: true)`), so the
content keeps its ideal height for the width instead of compressing or stretching, and sits in
`.frame(maxHeight: .infinity, alignment: .top)`, so in the pass between a width change and the new
measurement it overflows at the bottom, never at the top. Views with a flexible height must never
see a tall height proposal: the Rules suggestion cards (`maxHeight: .infinity`, so the cards of a
grid row match heights) stretch into tall empty boxes under one. A grid row still stretches its
cells to the row's tallest cell.

A frame-based document view that measured the content with `NSHostingController.sizeThatFits` and
set its own frame rendered correctly off-screen, yet in the on-screen window it opened panes with a
large blank area above the content and stopped scrolling. Keep the height on constraints.
`snapshot --settings` renders at the content's full height unless given `--size`, so it never
exercises the scroll view: check a change to it with `--size` at two widths, then on screen.

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
presets (`CompanionMenu.snoozePresets`, titled by `SnoozeTitle`) and each starts quiet time through
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
| Panels | Wait for idle, a duration field and a stepper | `idleSeconds` | `1s` to `30s`, a bare number is seconds; the stepper moves in 1 s steps |
| Panels | Grace period, a duration field and a stepper | `graceSeconds` | `0s` to `30s`, a bare number is seconds; the stepper moves in 1 s steps |
| Panels | Arm delay, a slider and a duration field | `armDelay` | `0` to `3` s, a bare number is seconds; the slider moves in 0.1 s steps, typed values keep milliseconds |
| Panels | Arm delay after an answer, a slider and a duration field | `chainedArmDelay` | `0` to `3` s, a bare number is seconds; the slider moves in 0.1 s steps, typed values keep milliseconds |
| Panels | Hand off when frontmost, a list | `handoffApps` | bundle IDs, added and removed one at a time |
| Panels | Snooze presets, a text field | `snoozeMinutes` | `1, 5, 15, 30`: 1 to 6 durations, each `10s` to `24h`; a bare number is minutes, `30s`, `15m` and `1h` carry a unit; error `"<word>" isn't a duration` |
| Panels | Quiet hours, a list above one editor line: day toggles, two time fields and Add, all on one `HStack`; the fields take `H`, `HH`, `H:MM`, `HH:MM`, `HMM` or `HHMM`, and the file always gets `HH:mm` | `quietHours` | up to 7 windows, each with at least one day and different start and end times; the whole array is rewritten on every add or remove; errors `Pick at least one day` and `Enter a time like 9, 0930 or 21:30.` |
| Panels | Notes on answers, a switch | `questionNotes` | on or off |
| Panels | Mode after a plan, a menu | `modeAfterPlan` | "Ask before edits", "Accept edits" or "Auto" |
| Panels | Sound, a menu and a play button | `panelSound` | None, then the names in `/System/Library/Sounds`; the button (`speaker.wave.2`, label `Play <name>`) is disabled for None |
| Panels | Waiting-agent notices, a switch | `waitingNotices` | on or off; never written directly, see below |
| Panels | Notice after, a duration field, directly under the Waiting-agent notices switch | `waitingNoticeDelay` | `10s` to `1h`, a bare number is seconds; disabled while notices are off |
| Panels | Show notice for, a duration field, directly under Notice after | `waitingNoticeDuration` | `3s` to `1h`, a bare number is seconds; top level only; disabled while notices are off |
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

`ApprovalCore.PreferenceRules` holds the bounds and the parsing. Since U25, an idle or grace value
in the file outside the stepper bounds is logged and read as the default, so a stepper never shows
a value it cannot reach. The five time rows (`PreferenceName.durationField`: idle, grace, both arm
delays and the notice delay) are duration fields. A field shows its value through
`DurationText.compact` (`500ms`, `1.5s`, `2m`), takes a bare number in the key's own unit (seconds,
minutes for the notice delay) or a number with `ms`, `s`, `m` or `h`, and commits on Return or when
it loses focus (`PreferenceRules.duration(from:spec:)`, rounded to a millisecond). While the text is
not a valid duration inside the key's range the field shows one red line under it, and nothing is
written until it is valid: typed input is rejected, never clamped. On the arm delay rows, dragging
the slider shows the dragged value in the field, and typing never moves the slider until the text
is committed. Snooze presets are separated by commas or spaces. Text that breaks the schema's rules
shows one red line under the field as it is typed and is never written (see "Writing a change"
below). A new bundle ID is trimmed and must be non-empty, without spaces and not already listed.

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

#### Delays per agent

The five delay rows (Wait for idle, Grace period, Arm delay, Arm delay after an answer, Show card
after; `PreferenceName.agentDelays`) sit in the Delays block, headed by the switch "Same delays for
all agents".
On, each row edits the top-level value. Off, an Agent segmented picker appears and each row edits
`hosts.<agent>` for the selected agent (`SettingsModel.delaysPerAgent`, `delayAgent`): a field shows
the agent's own value, or is empty with the shared value (top level, else the default) as its
placeholder; committing an empty field removes the agent's value, and a valid value writes it
(`PreferenceEdit.forAgent`). The stepper and slider show the agent's effective value and write to
the agent. Validation and the red line are the same as in shared mode. A row's reset arrow follows
the mode: in per-agent mode it shows whenever the selected agent has its own value for that row,
whether or not it changed in this visit, and it removes that value (`forAgent(agent,
.reset(name))`), so the row falls back to the shared value its help names ("Use the shared value:
5s"). It never resets the shared value from an agent's view.

The mode is not stored. On every reload it turns on when any agent has an own delay
(`PreferenceOverrides.agentsWithOwnDelays(in:)`), with the first such agent selected, else Codex,
and stays on until the person turns the switch back on, so clearing the last own value does not
make the card jump back. Turning the switch off writes nothing. Turning it on while agents have own
delays asks first ("Use the same delays for every agent?", `PreferenceOverrides.sameDelaysPromptText`)
because it removes those values from the file (`PreferenceEdit.removingAgentDelays(in:)`); Cancel
leaves the switch off. Show card after is disabled while the shown agent (or, in shared mode, every
agent) has the approval card off. Restore Defaults resets the shared values only and never touches
`hosts`; the Approval card checkboxes write `hosts.<agent>.approvalCard` per agent, and its reset
removes the key everywhere.

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
test panel, the buttons stay enabled and their help reads "Bring back the test panel": a click
calls `TestPanelLauncher.showRunning()` instead of launching another. It finds the running test
panel's ticket (a live ticket whose pid is the process's) and sends it `MenuAnswer.show`, the
menu's Show Now, so a panel hidden by an app switch or focus loss comes back without waiting for
idle, and nothing happens when it is already on screen. Disabling the buttons left no way back to
a hidden test panel. A launch that
fails shows one red line on the row, "The test panel could not start: <error>", and so does a test
panel that refuses to show, "The test panel didn't show: <reason>", with the reason it printed
(see "One at a time, never ahead of a real request" in [panel.md](panel.md)). The row sits outside the config-backed rows, which a config file with a problem
disables: a test panel reads such a file as defaults, as a hook does.

Right after it, "Show a test card" has two buttons, Notice and Approval, in the same secondary
style, with the caption "See the small corner cards, right away. Nothing reaches an agent." Notice
shows a waiting notice for "Codex" in "Countersign test" and its Go there closes the card;
Approval shows an approval card for "Cursor" in "Countersign test" and its Show closes the card and
opens the Command test panel, so the whole flow can be seen. Both are built by
`TestCornerCards` through `CornerCard.inFreeSlot` with the Settings appearance, post the same
accessibility announcement as a real card, and are titled `Countersign test notice` and
`Countersign test approval card`. There is one test card of each kind at a time: a click while it
is up does nothing. A test card takes a real slot (see "The shared corner card" in
[notice.md](notice.md)), so a test notice closes by itself after Show notice for (visible, un-hovered time, like a real
one), a test approval card after 20 seconds, and both when the Settings window
closes, rather than hold the slot for a long time: Settings can stay open in the menu-bar app
while real agents need the spots. With no free slot the row shows one red line, "Both card spots
are taken; close a card first."

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
| Wait for idle, Grace period, Arm delays, Notice after (duration fields) | on Return, or when the field loses focus, and only while the text is valid |
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
- `PreferenceEdit.forAgent(host, edit)` applies one of a short list of edits under
  `hosts.<agent>`, creating `hosts` and the agent's object as needed: `armDelay`,
  `chainedArmDelay`, `idleSeconds`, `graceSeconds`, `waitingNoticeDelay`, `approvalCard`,
  `approvalCardDelay`, and `reset` of those names (the file can still set
  `hosts.<agent>.waitingNoticeDelay` and it wins, but the Settings delays list leaves it out: the
  notice is about the agent's turn, not about the panel, so it is not one of
  `PreferenceName.agentDelays`, and neither a reset nor "Same delays for all agents" touches it). Any other inner edit is ignored: no write, no
  error, because those keys are top-level only. Resetting a key removes it and can leave the
  agent's object as `{}`; that is kept, since the object is the person's and an empty one reads the
  same as a missing one. `PreferenceEdit.removingAgentDelays(in:)` lists the resets for every
  per-agent delay key a file sets (`PreferenceName.agentDelays`), never `approvalCard`.
- `reset(.approvalCard)` removes the top-level `approvalCard` and every `hosts.<agent>.approvalCard`,
  since the setting is the set of agents that show the card.
- Restore defaults resets the shared values only: it removes no per-agent delay. Removing those is
  a separate action built from `removingAgentDelays(in:)`.
- A `handoffApps` that is not a list of strings is replaced by a list with the new ID, since the
  window showed the default in its place.
- The file is backed up the way setup backs up a hook file (see "Backups and writing" in
  [setup.md](setup.md)), once per window session, before its first write, not once per change.
  The first backup already holds the file as it was before the session, which is the copy worth
  keeping; a backup per change would push it out after three stepper clicks, since only the newest
  three backups of a file are kept; and a
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
window. A config file that can no longer be read shows the same problem line as when the window
opens on one, rather than leaving the old values up as if they were still the file's. That reread
never replaces text the person is typing: while the Snooze presets field has
the focus, or shows an error, it keeps its text, and the add field is never touched by a reread.
Every other control shows the file's new value. A write reads the file again first, so it lands on
top of an edit made elsewhere instead of undoing it.

The agent rows' Wire, Update and Remove write their agent's hook file once their popup is
confirmed (see "Agents" in [setup.md](setup.md)). The Launch at login switch, which registers a
login item with macOS rather than writing a config value, the header's Pause, Resume, Snooze and
End now, the test panel buttons and "Open in Editor" act at once too, each on its own file, a process or macOS, never
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

The Context tab appears in the sidebar only while the feature is on, and turning the feature off,
here or in the file, while Context is showing selects Panels. Its blocks, in order: Hook (the
hook status: Wired, Not wired or Needs an update, from `ContextHookRun.status`, with "Update" for
the last two, which shows the same popup as the switch and never touches the config), Checkpoints
(Checkpoint style, the 200K and 1M ladders, the per-model ladders, Start over below), Notes and
handoff (Notes, one row with an "Edit Notes…" button, then Handoff file), Menu bar (Context in the
menu bar) and Try it (a button that shows a context test panel), then a footer with "Turn Off
Context Checkpoints" left of Restore Defaults. That button calls `requestContextCheckpoints(false)` and so shows the same "Turn off context checkpoints?" popup as the Panels switch (the row presents it for the `.toggle` origin, and only one tab is on screen at a time, so one `contextChange` shows one alert); it is disabled while a change is pending or Claude Code isn't installed.

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

### Waiting-agent notices

The switch never writes `config.json` on its own. Changing it asks `SettingsModel` for a
`WaitingHookChange`: `WaitingHookRun.preview` over the wired hosts that
`WaitingHookSetup.supportedHosts` names, shown by `WaitingHookPrompt` (a sibling of
`ContextHookPrompt`, sharing `HookDiffPreview`) as "Turn on waiting-agent notices?" or "Turn off
waiting-agent notices?", with "Countersign changes <paths> and keeps a backup." and the buttons Turn
On / Turn Off and Cancel, or OK alone with the failure lines when a file cannot be changed. On
confirm, `WaitingHookRun.apply` writes the hook file with a backup and only then is `waitingNotices`
written. It applies to the locations the popup previewed, which `WaitingHookChange` keeps, not to
the wired agents at confirm time: the window rereads the agents when it becomes key, so an agent
wired while the popup was open would otherwise be changed without its diff ever being shown. With
no wired Claude Code the popup shows "Nothing to change." and confirming writes only
the config. Two fields sit directly under the switch, outside the delays group: Notice after, and
below it Show notice for (`waitingNoticeDuration`, how long a notice stays up before it closes by
itself; see "Closing by itself" in [notice.md](notice.md)). Both always show and edit the
top-level value, even while "Same delays for all agents" is off, and Show notice for has no
per-agent form at all. They are ordinary rows. Restore Defaults for Panels resets both fields
and never the switch, since flipping it needs the popup; the switch has no reset button.

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

Panels and App each have a **Restore Defaults** button below their last block
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
spelled out — "0.5 seconds", "1, 5, 15 and 30 minutes", "No apps" — read from `Settings.default*`
through the same formatters the rest of the module uses, so a changed default changes the text
without anyone hand-editing a string). Launch at Login isn't a `PreferenceName`, so its explanation
and default text ("Off") are constants next to its caption in `LaunchAtLoginRow` instead.

The title-and-caption block of a `PreferenceRow`, and of `LaunchAtLoginRow`, carries `.help(
explanation)` as a hover tooltip, and the title gains an info button (SF Symbol `info.circle`,
borderless, secondary) that opens a `.popover` holding `SettingsExplanationView`: the explanation,
then a secondary "Default: `<defaultText>`" line. The popover opens when the pointer has rested on
the button for 0.3 seconds (`SettingsInfoButton.openDelay`), or at once on a click, so reading an
explanation takes no click at all. It closes 0.2 seconds (`closeDelay`) after the pointer has left
both the button and the popover; the short grace lets the pointer cross the gap onto the popover
without closing it, and any return within it cancels the close. A click outside still closes it
at once, as for any transient popover. The Test panel row and Advanced's other rows
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
  label and the shown text (`0.5 s`, `60%`) as their value; the separate value text is hidden so
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
chosen app's name, or "Ask every time" when none is chosen: "Ask every time" first, then one item
per app from `NSWorkspace.shared.urlsForApplications(toOpen:)` for `config.json` (name and icon,
the same apps Finder's own Open With offers), a divider, then "Other…", which opens an
`NSOpenPanel` scoped to `/Applications` and `.application`. Choosing an app writes its bundle
identifier with `PreferenceEdit.editorApp`; choosing "Ask every time" resets it like any other
row.

`SettingsModel.openConfigInEditor` never falls back to the system's default app for `.json`, because
that opened an editor the person had never been asked about. With no `editorApp` it sets
`SettingsModel.editorChoice` (`EditorChoice`, carrying the `ConfigEditorOrigin`), and
`SettingsPage` presents it as one sheet (`EditorChoiceSheet`), so Advanced's button and an agent's
own "Open in Editor" link (`ConfigEditorOrigin.host`) share it. The sheet is titled "Open
config.json with" and lists the installed apps that open `config.json` (icon and name, the
system's default first and marked "(default)"; the name is Finder's display name without a trailing
`.app`, which Finder adds when "Show all filename extensions" is on), an "Other…" button (the same `NSOpenPanel`; the
picked app joins the list and is selected), an "Always use this app" checkbox that starts ticked,
and Cancel and Open, with Open the default action and disabled until a row is selected;
double-clicking a row opens with it. `SettingsModel.chooseEditor(bundleID:always:)` opens the file
with `NSWorkspace.shared.open(_:withApplicationAt:configuration:)` and, when the box is ticked,
writes `PreferenceEdit.editorApp`, so later clicks open directly; `cancelEditorChoice()` dismisses
the sheet and opens nothing. A stored app that was uninstalled since it was chosen asks again the
same way, with one line above the list, "<bundle id> is not installed. Pick another app."; the
stale value stays in `config.json` until a pick with the box ticked replaces it, or "Ask every
time" resets it.

The line reads "Only the file can set values for one agent, under hosts, and approvalCard,
approvalCardDelay, includeHeadlessSessions." (`PreferenceOverrides.fileOnlyNote`). Its keys are computed, not listed
by hand: the parser's top-level keys minus every key a row writes anywhere in the window
(`PreferenceName`) and minus `hosts`, `$schema` and `rules` (the Rules pane shows them), so a key added to the file without a row is
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

The tour, the context notes sheet and the rule sheet all use `SettingsSheetWindow`: a borderless
window whose `canBecomeKey` is overridden to true. AppKit lets a window become key only when it has
a title bar or a resize bar, so a plain borderless sheet never became key: its text fields took no
typing, and Return and Esc never reached its default and cancel buttons.

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
primary colour, so it reads as a heading rather than an error; below it, "Show copies"
(`ChangesDisclosure`, a chevron that turns down when open) discloses the rest:

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

## Rules

The Rules pane (`SettingsPane.rules`, SF Symbol `checklist`) sits between Panels and Context in the
sidebar. Top to bottom it shows an intro line ("Rules answer before any panel shows. Deny wins; a
compound command is allowed only when every part is."), then one row per rule in file order, then
the notice about unreadable entries. A row has the decision ("Allow" in the accent colour the
Approve button uses, "Deny" in red), a scope line (the agent's display name or "Any agent", then the
project abbreviated with `~` or "Any project"), the pattern in the code font (the `command`, else
`tool <pattern>`, else "Any request"), for a deny rule with a message the message, and a trailing
remove button laid out like the one in the handoff apps list. The trailing stack is an `HStack` so
an edit button can sit beside the remove button. With no rules the pane says how to get some: the
Add Rule… button, or the Always allow choice in the Approve ▾ menu of Codex panels.

The pane has no Restore Defaults and no `preferenceNames`. The default is "no rules", so restoring
it would delete every rule the person wrote, and one wrong click would lose work that the other
panes' resets only ever lose as a tuned number.

The remove button asks first (`RemoveRulePrompt`, an `NSAlert` sheet on the Settings window like
the Restore Defaults prompt): "Remove this rule?", the rule in two lines (decision and pattern,
then the scope line), and Remove / Cancel. A rule has no undo, and a deny rule written by hand can
take a while to get right, so one stray click on a small button should not lose it.

Removal is `PreferenceEdit.removeRule(ApprovalRule)`. `ConfigEdit` reads each element of the
top-level `rules` array through the same per-entry reader `ConfigFileParser` uses and removes the
first element that reads as a rule equal to the one given. Matching on the parsed rule and not on
a list index means entries the parser dropped (which do not appear in the list) never shift which
element goes. No match changes nothing, and removing the last rule leaves `"rules": []`. The edit
is not allowed per agent, because rules are top-level only (see
[rules.md](rules.md#why-rules-are-top-level-only)). `PreferenceEdit.key` is optional for this
reason: a rule edit writes no preference, so a failed write is reported in the pane
(`SettingsModel.rulesError`) and not under a preference name.

An "Add Rule…" button opens the rule sheet. It sits right of the intro line, which wraps beside it,
whenever that leaves the line at least 240 pt (`RulesSection.introMinWidth`): a `ViewThatFits`
whose first child gives the line that ideal width, so the stacked fallback (the button under the
line) only appears in a pane narrower than the window's minimum width allows today. Each row has a pencil button (and a
double-click) that opens the same sheet filled with that rule. The sheet is an AppKit sheet like the
context notes sheet (`RuleSheet`), 440 pt wide: Decision (Allow | Deny), Agent, Project (a text
field plus Choose…, an `NSOpenPanel` limited to one directory, shown abbreviated with `~`), Tool,
Command (code font) and, only while Deny is selected, Message. Empty fields mean "any". The pure
state lives in `RuleDraft` (`ApprovalCore`): its `problems` mirror what the file reader rejects
(a project that is not a full path or does not start with `~`; a command that splits into several
parts, because a rule matches each part of a compound command on its own; a command that
`ShellCommandSegments.split` cannot read, with its own line saying such a command always gets its
panel, since a rule could never match it), and Save stays disabled while there are any. A
message on an allow rule is dropped when the rule is built, as the reader would ignore it. An
allow rule with no agent, project, tool and command shows the warning "This allows every request
from every agent." in the warning style; it does not block saving, because a blanket allow is a
legitimate choice that should only be a deliberate one.

New rules go through `PreferenceEdit.addRules`, edits through `PreferenceEdit.replaceRule(old:new:)`,
which replaces the first element that reads as a rule equal to `old` with the new object, in place,
so the rule keeps its position in the file. Like removal it matches on the parsed rule and not on an index. Both
run through `SettingsModel.write`, so a failed write keeps the sheet open and shows
`rulesError` in it. When `old` is no longer in the file, because it was edited or removed there
while the sheet was open, `replaceRule` throws `RuleEditError.changedOnDisk` instead of writing
nothing: a write that changes nothing counts as saved, so the sheet would close and the edit would
be lost without a word. Removing a rule that is already gone still succeeds, since the file already
says what the person asked for.

Entries the parser dropped are counted from the config's log lines: every line that starts with
`rules` except the "only used by deny rules" note, which does not drop an entry. When the count is
above zero the pane warns "<n> rule(s) in config.json couldn't be read. countersign doctor lists
them." and offers Open in Editor, which opens the file from the `.rules` origin so a failure to
open it is shown in this pane. Unreadable entries are never listed or editable here: Settings
shows only what the evaluator uses.

A second group, Suggestions, sits under the rules group while any card is offered. The cards
are laid out by an eager `Grid` inside a `ViewThatFits` (two columns when two 220-pt cards fit,
else one; an odd last row is padded with a clear cell, and cards in a row share its height), not a
`LazyVGrid`: Settings sizes its AppKit scroll view from the hosting view's fitting height, which a
lazy grid misreports. The catalog is
`RuleSuggestion.all` in `ApprovalCore` and not a table in the view, so its copy and its patterns
are covered by tests that run them through `RuleEvaluator`. A card shows while any of its rules is
missing from the list, compared on decision, agent, project, tool and command and ignoring the
message, so a hand-written `deny rm -rf` with its own message already covers the card's. Editing a
suggested rule (say, narrowing it to a project) brings the card back offering only the rule that
changed, the card lists only the missing patterns, and Add (`SettingsModel.addSuggestion`) writes
only the missing rules through `PreferenceEdit.addRules`, so a second click never duplicates. A
failed write shows in the rules group's `rulesError` line. Every suggested rule has no agent,
project or tool, and the person narrows it afterwards with the pencil.

The git patterns use `base:glob` and not a prefix. An agent writes `git push origin main --force`,
which the prefix `git push --force` misses, while `git:push*--force*` matches the flag anywhere
after `push`. The same reasoning gives `git:push* -f*` and `git:reset*--hard*`. `git clean` is a
plain prefix: short of a dry run (`-n`), it deletes untracked files that no commit can bring back,
so the card stops every form of it. The deny cards catch the common
spellings and nothing more: `rm -r -f`, `sudo` behind `env` and `git -C dir push -f` are not matched,
and a miss is not an allow, so that command gets its panel as before.

## Why snapshot never reads the file

`countersign snapshot` renders `PanelModel`/`PanelRootView` directly, with no `PanelController`
and no config read, so its PNGs stay identical on every machine regardless of what settings a
person or a CI runner happens to have on disk. `PanelController`'s and `PanelModel`'s `armDuration`,
`snoozePresets` and `questionNotes` parameters default to the built-in values (`0.5`,
`[60, 300, 900, 1800]` seconds and `false`), and `SnapshotCommand` passes none of them unless asked, so it stays
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
