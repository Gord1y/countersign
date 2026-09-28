# The app bundle and the menu-bar companion

How `Countersign.app` is assembled and signed, how one binary decides between app mode and CLI
mode, and how the menu-bar companion works: why it never shows panels, how it stays a single
instance, how it tells a login launch from a person opening it, its menu model, the test panel it
starts, Launch at Login and the update check. Read it before changing `scripts/build-app.sh`,
`scripts/app/Info.plist`, `AppLaunchMode`, `MenuBarCompanion`, `MenuBarIcon`, `CompanionMenu`,
`TestPanelLauncher` or the update check. What the menu-bar app does for a user is in
[../menu-bar-app.md](../menu-bar-app.md).

`scripts/build-app.sh` assembles `.build/Countersign.app` around the same `countersign` binary
that `scripts/install.sh` puts on the CLI path. It is one binary either way: run bare it is the
CLI, run from inside the bundle with no arguments it is the menu-bar companion (see "Menu-bar
companion" below).

The quit question and the pause it can leave behind are in "Quit" below; read it before changing
`QuitPrompt`, `QuitQuestion` or `PauseSwitch.pauseUntilAppOpens`.

## Layout

```
Countersign.app/Contents/
  MacOS/countersign      the release build of the countersign target
  Info.plist             scripts/app/Info.plist, with the version keys filled in
  PkgInfo                the fixed four-plus-four bytes "APPL????"
  Resources/AppIcon.icns scripts/app/AppIcon.icns, the app icon; the menu-bar icon is drawn by
                          `MenuBarIcon`, not a bundled resource
```

`scripts/app/Info.plist` is the checked-in template: `CFBundleIdentifier` `dev.gord1y.countersign`,
`CFBundleExecutable` `countersign`, `CFBundleIconFile` `AppIcon`, `LSUIElement` and the platform
minimums. It carries the placeholder version `0.0.0` in both `CFBundleShortVersionString` and
`CFBundleVersion`, because the template has no build to ask. `build-app.sh` copies it into the
bundle, then asks the freshly built binary for its own version with `--version` and writes that into
both keys with `plutil -replace`, so the bundle's version and the binary's `countersign --version`
output can never drift apart. The binary itself still only knows one version:
`CountersignVersion.current` in `ApprovalCore`, a single constant with its own test in
`ApprovalCoreTests`.

The bundle's icon is `scripts/app/AppIcon.icns`, copied in by `scripts/build-app.sh`.

`build-app.sh` builds for the host's own architecture only, `arm64` or `x86_64`, unless it is
passed `--universal`, which builds both with `swift build -c release --arch arm64 --arch x86_64
--product countersign` and takes the binary from `.build/apple/Products/Release/countersign`
(SwiftPM's path for a multi-arch build) instead of `.build/release/countersign`. Release packaging
is the one caller that passes it; see [release.md](../release.md).

## Why `LSUIElement`

Countersign has no windows of its own to show in the Dock or the app switcher; the panel is a
borderless, non-activating alert that appears over whatever app the person is using (see
[panel.md](panel.md)). `LSUIElement` keeps the bundle out of the Dock and the ⌘-Tab list, which is
what a menu-bar-only companion needs: its status item is its only presence on screen.

The one exception is Settings: it is an ordinary titled window, and one that can end up behind
other windows with no menu-bar icon to click back to once it is out of view. `SettingsWindowController`
switches the app to `NSApplication.ActivationPolicy.regular` while its window is open and back to
`.accessory` when it closes, so Settings gets a Dock icon and a ⌘-Tab entry for exactly as long as
it needs one. This applies whether Settings was opened from the menu-bar companion or from the bare
`countersign settings` CLI binary; the CLI binary has no bundle and so no `CFBundleIconFile`, which
is why `SettingsWindowController` also renders `CountersignMark` at 256pt into
`NSApplication.applicationIconImage` the first time it needs to show a Dock icon, rather than
leaving the Dock to fall back to a generic one.

## Why ad-hoc signing

`build-app.sh` signs with `codesign --force --sign - `, which signs with no identity at all. There
is no Developer ID here, and none of the ways people get this binary need one: `scripts/install.sh`
builds from a clone, and a Homebrew or `curl | sh` install is never quarantined by Gatekeeper, so
Gatekeeper never assesses the bundle either way. Ad-hoc signing exists for what *does* check a
signature on this Mac: launch-at-login through `SMAppService`, which the companion's "Launch at
Login" item uses, refuses to register an unsigned bundle. Ad-hoc satisfies that check without a
certificate; it stops short of anything that needs a real identity, such as notarization or a
signature that survives the bundle being copied to another Mac.

## App mode vs CLI

`AppLaunchMode.detect(bundleIdentifier:arguments:)` in `ApprovalCore` is the pure decision: app mode
only when the bundle identifier is `dev.gord1y.countersign` and no arguments are left once any
argument starting with `-psn_` is dropped. `main.swift` calls it with
`Bundle.main.bundleIdentifier` and the process's own arguments.

`-psn_` is an old LaunchServices process serial number, passed as the sole argument when the Finder
or Dock launches a pre-notarization-era app bundle directly; some macOS versions still pass it to a
plain, unsigned bundle like this one. It carries no intent from the person, so it is filtered out
before asking whether any *real* arguments remain. A bundle launched with an actual argument, for
example the binary at `Contents/MacOS/countersign` run by hand with `--version`, behaves exactly
like the bare CLI: `AppLaunchMode.detect` sees a non-`-psn_` argument and returns CLI mode.

App mode runs the menu-bar companion, `MenuBarCompanion.run()`, and never returns from it.

Every subcommand but `hook` follows the same convention: a usage line or an error goes to stderr
through the shared `CommandLineOutput.fail`/`writeError`, the exit code is non-zero for an error,
and only the command's actual result — a report, a status line, a diff, an encoded reply,
`--version` — goes to stdout. `hook` is the deliberate exception: it never writes to stderr and
never exits non-zero (see "No answer at all" in [answers.md](answers.md)).

## Menu-bar companion

### A companion, not the thing that shows panels

Panels stay in hook processes. Every prompt starts its own `countersign hook`, which queues, shows
its own panel and exits (see [queue.md](queue.md) and [panel.md](panel.md)). The companion never
shows a panel, never writes a ticket, never takes the display lock, and no hook ever talks to it.
It only reads and writes the same files the CLI does: the pause switch, the quiet-time file, the
queue directory and the config file. Its "Show a Test Panel" item keeps to that: it starts a
separate `countersign test-panel` process, which writes a ticket and shows its panel the way a
hook does (see "Show a Test Panel" below).

That split is deliberate. If panels lived in a long-running menu-bar process, every approval would
depend on that one process staying alive: quitting it by accident, or one crash, would turn every
prompt into the host's own fallback, or worse, leave hooks waiting on a process that is gone. A
short-lived hook per prompt already has no such single point of failure, so the companion is kept
strictly optional: hooks work exactly the same whether it runs, was never started, was quit or has
crashed. The one exception is a person's own choice: quitting it can pause panels until it opens
again (see "Quit" below), which is an ordinary pause on disk that the hooks read like any other.

### Launch and single instance

App mode first takes an exclusive, non-blocking `flock` on `companion.lock` in the support
directory (`AppPaths.companionLockFile`, `~/Library/Application Support/Countersign/companion.lock`)
through `ExclusiveFileLock`, the same open-and-lock code the display lease uses (see "Why head plus
flock" and "O_CLOEXEC" in [queue.md](queue.md)): opened with `O_RDWR | O_CREAT | O_CLOEXEC`,
creating the support directory if needed. If another process holds the lock, it asks that companion
to open its settings window (see "Opening Countersign" below), logs `companion: already running,
asked it to open Settings` and exits 0 at once, before creating `NSApplication`, so opening the app a
second time, or opening it by hand after a login launch, never adds a second icon. A lock file that
cannot be opened at all is logged (`companion: could not open companion.lock: <error>, exiting`)
and also exits 0, asking nothing, since no companion is known to be running. Otherwise it keeps the
descriptor for the rest of the process's life, runs `NSApplication` with the `.accessory`
activation policy, and once launching has finished, before anything reads the pause switch, ends a
pause that the last quit set until the app opens (see "Quit" below), logging `companion: resumed
the pause set at quit`. It then creates one square `NSStatusItem` and logs `companion: started`, or
`companion: started at login`, to the event log the CLI and the hooks use
(`AppPaths.standard.logFile`). Only the process that holds the lock resumes: a second launch that
exits at once leaves the pause alone, since the companion it defers to already did.

Why a lock file and not a scan of running apps: a hook that shows a panel builds an `NSApplication`
of its own, and once hook entries point at the bundle's binary, `Contents/MacOS/countersign`, that
hook process is registered under the same bundle identifier, `dev.gord1y.countersign`. A scan with
`NSRunningApplication.runningApplications(withBundleIdentifier:)` would count it as a second
companion and quit the real one whenever a panel is up. Only the companion ever touches
`companion.lock`, so the lock cannot be confused with a hook. It also removes the launch race a scan
has, where two instances opened in the same instant each see the other and both exit: the kernel
grants the lock to exactly one of them. And it leaves no stale state behind, since the kernel drops
the lock when the holder exits or crashes; the next launch simply takes it. Like `display.lock`,
the file itself is never deleted (see "Why the lock file is never deleted" in [queue.md](queue.md)):
a process that unlinked it while another held it would let a third instance lock a fresh inode at
the same path.

### Opening Countersign

Opening Countersign.app by hand, from the Finder, Spotlight, Launchpad or `open`, always ends with
the settings window in front, so a person who never uses a terminal can reach setup and settings:

| Opened | What happens |
| --- | --- |
| Nothing running yet | The companion starts, adds its icon and opens the settings window |
| At login, by "Launch at Login" | The companion starts and stays in the menu bar, with no window |
| The companion is already running | Its settings window opens, or comes to the front |

Telling a login launch apart: macOS starts every app with an "open application" Apple event
(`kAEOpenApplication`), and for a login item that event carries `keyAEPropData` set to
`keyAELaunchedAsLogInItem` (`AERegistry.h`: "If present in a kAEOpenApplication event, application
was launched as a login item"). `SMAppService.mainApp`, which "Launch at Login" registers, is the app
itself as a login item. The companion reads `NSAppleEventManager.shared().currentAppleEvent` in
`applicationDidFinishLaunching`, the only point where that launch event is still current, and
`ApprovalCore.CompanionLaunch.opensSettings` decides: every launch opens the window except that one.
A launch with no Apple event at all, such as running `Contents/MacOS/countersign` from a terminal,
counts as the person's. Whether a login launch from `SMAppService.mainApp` carries the parameter is
what the header and the widely used LaunchAtLogin-Modern package (which pairs
`SMAppService.mainApp` with the same check) rely on; it has not been checked on a real login here
yet, so the log says which it was: `companion: started at login` or `companion: started`.

When the companion is already running, there are two ways the second opening reaches it:

- LaunchServices usually finds the running app and sends it a reopen event instead of starting a
  second copy. `applicationShouldHandleReopen(_:hasVisibleWindows:)` opens the settings window,
  logs `companion: reopened, opening settings` and returns `false`, since there is no default
  window to restore.
- When a second process does start, for example with `open -n`, from another copy of the bundle, or
  by running the binary directly, it finds `companion.lock` taken and posts the distributed
  notification `dev.gord1y.countersign.openSettings`
  (`CompanionLaunch.openSettingsNotificationName`) with `deliverImmediately`, then exits. The
  companion observes it with `suspensionBehavior: .deliverImmediately`, since an accessory app is
  inactive nearly all the time and the default behaviour would hold the notification until it
  activated. It logs `companion: another launch asked to open settings` and opens the window.

Either way the window opens exactly as "Settings…" opens it: one window at a time, brought to the
front and activated when it is already open. No hook ever posts or observes the notification.

### The icon and the 2 s refresh

The status item shows a template `NSImage` that `MenuBarIcon` draws in code, so it follows the menu
bar's light, dark and tinted appearance the same way a template SF Symbol would. The drawing is an
outline fountain-pen nib in an 18 x 18 pt canvas: alone while Countersign is on, with a small
pause-bars mark added in its empty bottom-right corner while paused, and with a small moon added
there instead during quiet time. The canvas is the same 18 x 18 pt in every state, so the nib never
moves when the state changes: the status item uses `squareLength` and re-fits whatever image it is
given, so a wider image (the old badge-beside-the-pen layout) shifted the pen sideways as states
changed. Paused wins over quiet time, since while paused no hook shows anything at all.
`CompanionIcon` in `ApprovalCore` still decides which state applies and its spoken VoiceOver label;
`MenuBarIcon.image(for:)` turns that state into the drawn, labelled `NSImage`.

The pause and quiet-time files change from other processes (`countersign pause`, `countersign
snooze`, a panel's own Snooze menu) and nothing notifies the companion, so a repeating 2 s `Timer`
on the main run loop, in `.common` mode so it also fires while the menu is open, reads both files
and swaps the image only when the icon actually changes. Two small file reads every 2 s cost
nothing measurable, and the icon is never more than 2 s out of date. The icon is also refreshed
right after any menu action.

The queue is not polled. The menu is rebuilt from scratch in `NSMenuDelegate.menuNeedsUpdate(_:)`
every time it opens, which reads the pause switch, quiet time, the config file, launch-at-login
status and the live tickets at that moment. A menu that stays open does not update itself; the next
open does.

### What the menu does

`ApprovalCore.CompanionMenu.items(for:timeZone:)` is a pure model: from plain inputs
(`CompanionMenuInput`) it decides every title, enabled state, checkmark, key equivalent, order and
action, and `ApprovalCoreTests` covers it. `CompanionController` in `MenuBarCompanion.swift` only
renders those items into `NSMenuItem`s, with `autoenablesItems` off so the model's enabled state
is the one shown, and performs the chosen `CompanionMenuAction`.

| Item | What it does | File |
| --- | --- | --- |
| "Countersign is on", "Paused" or "Quiet until 14:05" | Disabled status line; paused wins over quiet time. The time is local, `HH:mm`, from `TimeOfDayText`, the same formatter `countersign status` uses | reads `paused`, `quiet-until` |
| "N requests pending" | Submenu listing every live ticket oldest first, read-only. "No requests pending", disabled, when there are none | reads `queue/` |
| "Pause Countersign" / "Resume Countersign" | `StateSwitches.pause()` ends quiet time then pauses, exactly `countersign pause`; "Resume Countersign" is `PauseSwitch.resume()`, exactly `countersign resume` | writes `paused`, `quiet-until` |
| "Snooze" | Disabled with no submenu while paused; while quiet time is active, replaced by a single "End Quiet Time (until 14:05)" entry (`QuietTime.clear()`); otherwise quiet time for each preset (`StateSwitches.snooze(until:)`) | writes `quiet-until` |
| "Settings…" (⌘,) | Opens the settings window, or brings it to the front | through the window |
| "Show a Test Panel" | Starts `countersign test-panel command` as a separate process (see "Show a Test Panel" below) | none; the test panel writes its own ticket |
| "Launch at Login" | Registers or unregisters the app as a login item | Login Items |
| "Help" | "Documentation" opens `https://github.com/Gord1y/countersign#readme`, "Report a Problem…" opens a prefilled bug report, "Ask a Question…" opens `https://github.com/Gord1y/countersign/discussions/new?category=q-a`, "Contact the Developer…" opens `https://www.gord1y.dev/` | none |
| "Support the Developer" | "Sponsor on GitHub" opens `https://github.com/sponsors/Gord1y`, "Buy Me a Coffee" opens `https://buymeacoffee.com/gord1y` | none |
| "Countersign 0.1.0" | Disabled, from `CountersignVersion.current` | none |
| "Quit Countersign" (⌘Q) | Asks whether panels keep appearing, then quits the companion, and only the companion (see "Quit" below) | may write `quitBehavior`, `paused` |

`TimeOfDayText` pins the `en_US_POSIX` locale, Apple's advice for fixed-format dates, so the
person's own locale and 12/24-hour preference never rewrite `HH:mm`; `countersign status` and
`countersign snooze` print their times through it too, so the menu and the CLI always agree.

The pending rows read like the panel's waiting list (see "The waiting list" in
[panel.md](panel.md)): host · project · tool, then the subagent's task description, falling back
to its agent type, when the ticket has one (`TicketSummary.agentLabel`, shared by both). A ticket
whose content cannot be decoded still gets a row, "Unknown request", so the count in the title and
the number of rows always agree. The list comes from `TicketQueue.waitingEntries()` (see "Listing
waiters, not just counting them" in [queue.md](queue.md)), which prunes dead tickets exactly as
`countersign status` does; the companion never takes the display lock.

The Snooze presets are the top-level `snoozeMinutes` from the config file, falling back to
`Settings.defaultSnoozeMinutes`; the `hosts.*` blocks never apply, since the companion acts for no
single host. The titles are the panel's own ("Quiet for 1 minute", "5 minutes", …, from
`SnoozeTitle.describe`). Quiet time and pause take effect in the hooks the same way as from the
CLI: a hook that is waiting or showing a panel sees the pause file on its next tick and exits with
no decision, and a panel on screen steps aside on its next tick when quiet time starts (see "Quiet
time" in [panel.md](panel.md)).

`ApprovalCore.StateSwitches` is the one place that keeps pause and quiet time consistent: pausing,
from the menu, `countersign pause`, the Settings status card or the quit question's "Pause until I
reopen", always clears quiet time first, and snoozing while paused is refused
(`SnoozeRefusal.paused`) rather than silently queued. A pause already sends every request to its
agent's own chat, so a snooze underneath it would only resurface later as a surprise once the pause
ends. `countersign snooze off` still clears quiet time on its own, since ending quiet time is never
a surprise.

The Help submenu is the same on every install and needs no input: "Documentation" opens the
README on GitHub, "Ask a Question…" opens a new GitHub Discussion under the Q&A category, and
"Contact the Developer…" opens `https://www.gord1y.dev/`. None of it collects an email address.
"Report a Problem…" is the one dynamic entry: choosing it builds the bug report URL from the same
`Doctor` model `countersign doctor` prints (see [doctor.md](doctor.md)), through
`ApprovalCore.BugReportURL.build(macOSVersion:countersignVersion:doctorText:homeDirectory:)`,
a pure function covered by its own tests. It fills the bug template's `macos-version`,
`countersign-version` and `doctor` query fields from `ProcessInfo.operatingSystemVersionString`,
`CountersignVersion.current` and the doctor report's own text, every value percent-encoded so a
path, a version string or a doctor line can never break the URL or smuggle in an extra query
field. The doctor text's paths still name the person's own account: every place it starts with the
same home directory `Doctor.Input` used (`FileManager.default.homeDirectoryForCurrentUser`), that
prefix is shown as `~` instead, so `/Users/gord1y/.local/bin/countersign` becomes
`~/.local/bin/countersign` before the report ever leaves the Mac; a path outside home, or one that
only shares a prefix with it (`/Users/alexander` when the account is `/Users/alex`), is left alone.
GitHub silently truncates an overlong issue URL, so `BugReportURL` caps the whole string at 8000
characters itself: when the encoded doctor text would not fit, it drops the report's trailing lines
one at a time and ends whatever survives with a `…` line, so the report a person actually sees
always matches what shows up in the prefilled form. A report from a healthy setup is a few hundred
characters and never comes close to the cap.

The Support the Developer submenu takes an optional Buy Me a Coffee link in `CompanionMenuInput`,
defaulting to `CompanionMenu.buyMeACoffeeURL` (`https://buymeacoffee.com/gord1y`) the same way
`sponsorURL` defaults to `CompanionMenu.sponsorURL`; passing `nil` hides "Buy Me a Coffee" under
"Sponsor on GitHub" with no layout work. It sits below "Check for Updates…", separate from Help,
so donation links never read as part of getting help.

Every action that writes a file logs a failure to the event log (`companion: failed to pause:
<error>` and so on), and the successful ones log what they did (`companion: paused`, `companion:
quiet time until 14:05 (15 minutes)`). The only alert the menu shows is the quit question (see
"Quit" below), and its only window is the settings window. Problems in the config file are logged with the same `config: ` prefix `hook`
uses, once per distinct set of problems rather than on every menu open.

### Settings…

"Settings…" opens the settings window, the same one `countersign settings` and plain
`countersign setup` open (see "The window" in [setup.md](setup.md) and "The settings window" in
[settings.md](settings.md)), inside the companion process. Its first row repeats the menu's status
line, with Pause, Resume or End now beside it (see "Status" in [settings.md](settings.md)). The
companion activates itself for it: the person chose the menu item, so the window takes the
keyboard, unlike a panel. There is one window at a time; choosing "Settings…" again brings it to
the front. Closing it leaves the companion running. To open it again, choose "Settings…" (⌘, while
the menu is open), open Countersign.app again (see "Opening Countersign" above), or run
`countersign setup` or `countersign settings`, which opens its own copy of the window in the
terminal's process. The window writes each preference as soon as it changes (see "Writing a
change" in [settings.md](settings.md)), so neither closing it nor choosing "Quit Countersign" asks
anything about settings; a Snooze presets entry or bundle ID still being typed is written as the
window closes or the companion quits.

The window's "Open in Editor" creates a missing config file, and its directory, containing exactly
`ConfigFileStarter.contents`:

```json
{
  "$schema": "https://raw.githubusercontent.com/Gord1y/countersign/main/schema/config.schema.json"
}
```

so an editor that understands `$schema` offers completion and validation from the first keystroke.
A test checks that this reference equals the schema's own `$id`. The file is written with
`.withoutOverwriting`, so an existing file, or one created at the same moment by hand, is never
replaced. Then `NSWorkspace.shared.open` opens it in whatever app is the default for JSON. Writing
a preference change from the window starts a missing file from the same contents.

The companion resolves the config path, and the hosts' files, with its own environment. Opened from
the Finder or at login it gets launchd's environment, which normally has no `XDG_CONFIG_HOME`,
`CLAUDE_CONFIG_DIR` or `CODEX_HOME` even when the person's shell sets them, while a hook inherits the
environment of the Claude Code, Codex, Cursor or Antigravity process that started it. With
`XDG_CONFIG_HOME` set only in a shell profile, the companion's window therefore edits
`~/.config/countersign/config.json` and the Snooze presets come from there, while hooks started
from that shell read `$XDG_CONFIG_HOME/countersign/config.json`. `countersign settings` run from
that shell sees the shell's variables.

### Show a Test Panel

"Show a Test Panel", right after "Settings…", shows a panel for a built-in sample command with the
person's current settings: the arm delay, the Snooze presets, the idle wait after it steps aside
(see "The test panel" in [panel.md](panel.md) for what it runs, what it skips, why it shows at
once and never ahead of a real request, and where the sample comes from). The companion does not
show that panel itself. `TestPanelLauncher.shared.launch(kind:onRefusal:)` starts the running
executable, `Bundle.main.executableURL`, with the arguments `test-panel command` through
`Process`, the way an agent starts a hook, and returns. Any argument keeps the bundle's binary in
CLI mode (see "App mode vs CLI"). The child's stdin and stdout are `/dev/null`, its stderr is a
pipe, and it inherits the companion's environment, so it reads the same config file the
companion's window edits.

`TestPanelLauncher` is a main-actor `@Observable` singleton. It keeps each `Process` in a set
until the child has exited, so reaping it never depends on how `Process` keeps itself alive while
nothing else holds it, and `isRunning` is true while the set is not empty. A background read
drains the pipe to its end, so a chatty child can never fill it and block, then waits for the exit
and hops back to the main actor. An exit with a non-zero status is a refusal: the stderr text,
without its `countersign: ` prefix, goes to the caller's `onRefusal`. A crash is not a refusal.
`launch` does nothing while one is running, so two quick clicks start one test panel. The menu
item is disabled while `isRunning` is true, and a refusal shows an alert built like the quit
prompt's, `TestPanelRefusalAlert`: "The test panel didn't show", with the reason as a sentence.
The settings window's "Show a test panel" buttons, at the end of its Panels group, start any of
the three kinds through the same launcher, from the companion or from `countersign settings`
alike (see "Panels and App" in [settings.md](settings.md)); the menu item offers the command only,
and the window shows a failed launch or a refusal on the row instead.

A separate process keeps the reason panels live in hooks: a crash, a hang or a wedged run loop in
the test panel ends or blocks only that process, and the menu, the icon and the settings window
carry on. The companion logs `companion: started a test panel (command)`, or
`companion: failed to start a test panel: <error>` when the process cannot be started; everything
after that is the test panel's own log lines, under its own pid, `test panel: refused (<reason>)`
included. The later answer, or a crash, is not reported back to the companion.

### Launch at Login

The item uses `SMAppService.mainApp`, which registers the app bundle itself as a login item: no
helper app and no LaunchAgent plist. The item mirrors `SMAppService.mainApp.status`:

| Status | Item | Choosing it |
| --- | --- | --- |
| `.enabled` | "Launch at Login", checked | `unregister()` |
| `.notRegistered`, `.notFound` | "Launch at Login" | `register()` |
| `.requiresApproval` | "Launch at Login (approve in System Settings)" | `SMAppService.openSystemSettingsLoginItems()` |
| a thrown error, or a status macOS adds later | "Launch at Login (unavailable)", disabled | nothing |

`.requiresApproval` means the item is registered but macOS wants the person to allow it, or they
turned it off under General > Login Items; only they can switch it on there. `.notFound` is treated
as "not registered", since registering is the only way to find out whether it works. When
`register()` or `unregister()` throws, the error is logged (`companion: launch at login
unavailable: <error>`) and the item stays unavailable until the companion is started again.

Ad-hoc signing matters here (see "Why ad-hoc signing" above): `SMAppService` will not register an
unsigned bundle at all. An ad-hoc signature carries no stable identity, though, so every rebuild of
the bundle is a new signature, and a registration points at the bundle's path, so a bundle moved
after registering leaves a login item behind for a path that no longer holds it. Whether macOS asks
for approval again after a rebuild has not been checked on a real login yet.

### Quit

The companion holds no ticket, no display lease and no child processes but the test panels it
started, only `companion.lock`, which the kernel releases as the process exits, so quitting it
changes nothing about approvals on its own: hooks that are waiting keep waiting, queued panels keep
appearing in turn, a test panel started from the menu carries on as its own process with its own
ticket, and a pause or quiet time stays exactly as it is on disk. A person who quits the menu-bar app may well expect the
panels to stop too, so "Quit Countersign" asks which they want.

#### The question

`quitFromMenu()` reads the top-level `quitBehavior` (default `"ask"`) and the pause switch's
`state`, and hands both to `ApprovalCore.QuitQuestion.decision(for:pause:)`. With a pause already
on, it quits at once whatever `quitBehavior` says, with an outcome that neither pauses nor
remembers anything, and logs `companion: quit without asking, panels were already paused` once the
quit goes ahead: panels already appear nowhere, a plain pause is never replaced (see below), so
neither answer could change anything and the question would only be a hurdle. A marked pause cannot
normally be on while the companion runs, since launch ends it, but one that is gets the same
treatment. With no pause on, `"keepShowing"` and `"pause"` quit at once with that outcome, and
`"ask"` shows the question, the `NSAlert` that `QuitPrompt.makeAlert()` builds (the
same factory `snapshot --quit-prompt` renders): "Keep showing approval panels while Countersign is
closed?", with **Keep showing** first, so Return picks it, then **Pause until I reopen**, then
**Cancel**, which NSAlert gives Esc because of its title, and the suppression checkbox titled
"Don't ask again". The companion is an accessory app that is almost never active, so
`QuitPrompt.ask()` activates it before `runModal()`; otherwise the alert would open behind the
frontmost app without the keyboard. `QuitQuestion.decision(for:dontAskAgain:)` maps the answer:
Cancel keeps the companion running whatever the checkbox says; Keep showing and Pause quit, only
Pause pauses, and with the checkbox ticked the outcome also carries the answer to remember as
`quitBehavior`. Both functions are pure and covered by `QuitBehaviorTests`.

Only the menu's "Quit Countersign" asks. Logout, restart and shutdown quit the app through its quit
Apple event, which goes straight to `NSApplication.terminate`, and `kill` is a signal; none of them
passes through the menu action, so none can be held up by a question nobody may be there to answer,
and none pauses: a logout that silently switched panels off for the next session is a surprise
nobody chose. The companion does not implement `applicationShouldTerminate`, so once a quit starts
nothing asks anything more: the settings window has no unsaved changes to ask about (see "Writing a
change" in [settings.md](settings.md)).

#### Applying the answer when the quit is certain

Answering is not the end of the quit. `quitFromMenu()` keeps the outcome in `pendingQuit`, calls
`NSApplication.terminate(nil)`, and applies nothing itself: the outcome is applied in
`applicationWillTerminate`, which runs only once the quit is certain, so a pause or a remembered
choice can never be left behind a companion that is still running. `terminate` returns only for a
quit its delegate cancels, which the companion never does; `quitFromMenu()` still clears
`pendingQuit` after it, so an outcome that was not applied can never be picked up by a later quit,
such as a logout.

`applicationWillTerminate` first lets the settings window, when it is open, write a Snooze presets
entry or bundle ID still being typed (`SettingsModel.commitEditing()`, see "Writing a change" in
[settings.md](settings.md)). Then it applies `pendingQuit`: it writes `quitBehavior` when the answer
is to be remembered, pauses when the answer was Pause, then logs `companion: quit`. A logout reaches
it too, with nothing pending, so it does neither.

The remembered answer goes through `ConfigEdit`, the minimal-diff editor the settings window writes
with, and touches only `quitBehavior`. It is written without a backup: it is one key the person
just chose, and when the settings window wrote the file a moment earlier, its session backup may
carry the same second in its name, since backup names have one-second resolution, and a second
backup under that name would fail the write. It logs `companion: saved quitBehavior "pause"`, or
`companion: failed to save quitBehavior: <error>`, for example for a config file that is not valid
JSON; the quit and the pause go ahead either way.

#### The pause that ends at the next launch

Pause writes a marked pause through `StateSwitches.pauseUntilAppOpens()`, which ends quiet time the
same way the menu's own Pause does, but only when it actually pauses: `PauseSwitch.pauseUntilAppOpens()`
writes the pause file with the text `until Countersign opens` and a newline, atomically, where
`pause()` writes an empty file. It logs `companion: paused until Countersign opens`. The hook, the
companion's icon and every other reader
still ask only whether the file exists (`isPaused`), so a marked pause is a pause like any other:
the hook answers nothing, the agent shows its own prompt, and nothing is approved.
`PauseSwitch.state` reads the content to tell the two apart: exactly the marker is
`.pausedUntilAppOpens`; anything else, an empty file or one written by hand, is `.paused`.

The marker lives in the pause file itself rather than in a second file so that the pause stays one
fact. `isPaused` and the hook's check do not change. A plain pause from anywhere, the menu,
Settings, `countersign pause`, an older binary or `touch`, overwrites the marker in the same write,
and `resume()`, or deleting the file by hand, removes both at once. A separate marker file could
outlive the pause it described: after the pause was ended by hand or by an older binary, the next
plain pause would find the stale marker and be ended by the next launch.

`pauseUntilAppOpens()` leaves a plain pause as it is and logs `companion: already paused, the pause
stays after Countersign opens`: the person paused on purpose, and quitting with Pause must not turn
that into a pause the next launch ends. With the question skipped while paused, this is only
reached when a pause starts between the answer and the quit, such as a `countersign pause` landing
in that moment. Keep showing never resumes a pause either; quitting only decides whether to add
one.

On launch, `applicationDidFinishLaunching` calls `resumeIfPausedUntilAppOpens()` first, before the
icon or the menu reads the switch, for a person's launch and a login launch alike: the pause was
chosen to last until the app opens again, and a login start is the app opening. A plain pause is
left as it is. Reading the content and removing the file are two steps, so a `countersign pause`
landing in the microseconds between them would be removed with the marked pause.

`countersign status` (`state: paused until Countersign opens`), the `doctor` report's `state` line
and the Settings window's status row ("Paused until Countersign opens") name a marked pause, through
`PauseState.description` and `CountersignStatus.pausedUntilAppOpens`. The menu's status line and
icon only see a plain pause, since the companion ends a marked one as it starts.

### Update check

The companion can check `https://raw.githubusercontent.com/Gord1y/countersign/main/releases/index.json`
for a newer release, the same index `scripts/release-index.swift` generates (see
[releases/README.md](../../releases/README.md)). `Sources/countersign/UpdateFetcher.swift` makes
one `GET` through an ephemeral `URLSession` that neither sends nor accepts cookies, with a 15 s
request timeout. Parsing is defensive: `ApprovalCore.ReleaseIndex` reads only `schemaVersion` and
each release's `version`, ignores every other field, and treats a response that is not JSON, not
an object, missing `schemaVersion`, on an unknown `schemaVersion`, or missing a usable `version` as
"unknown" rather than an error. `ApprovalCore.UpdateCheck.compare` then reads the newest entry's
`version` and `CountersignVersion.current` as `x.y.z` and reports `newerAvailable` only when the
release is strictly newer; anything that does not parse as three dot-separated integers, including
a pre-release suffix our own tooling never produces, is "unknown" too. A 404, or any other
non-200 response, folds into "unknown" the same way. An unknown outcome is logged once per check,
`update check: <reason>`; a newer
release or "up to date" is not logged, since it changes nothing on its own.

The check is opt-in: it only runs automatically when the top-level `checkForUpdates` key in the
config file is `true` (default `false`, see [settings.md](settings.md)), so nobody's companion
talks to the network without asking first. When it is on, `CompanionController` evaluates
`ApprovalCore.UpdateCheckSchedule.isDue` on launch and then every hour from a repeating `Timer`,
the same pattern as the icon's 2 s refresh; the rule is at most one attempt per 24 hours, tracked by
the time of the last attempt in `<AppPaths.supportDirectory>/update-check.json`
(`ApprovalCore.UpdateCheckStateStore`, written atomically the same way `QuietTime` writes
`quiet-until`). A last-attempt stamp later than `now` can only come from a clock that was once set
wrong, not from a real future check, so `isDue` treats it the same as no stamp at all and returns
true rather than waiting out however long the clock was ahead; one extra check is harmless. The
normal rule, at most one attempt per 24 hours, is unaffected. "Check for Updates…", right under
Help in the menu, is always present regardless of the setting and always checks immediately, since
choosing it is itself the person's consent.

`ApprovalCore.UpdateCheck.evaluate` combines the parse and the comparison into one
`ApprovalCore.UpdateCheckOutcome`, which is what gets persisted and shown. When it is
`newerAvailable`, the menu (`CompanionMenu.items`) adds an "Update available: x.y.z" submenu above
"Check for Updates…", with "Open Release Notes" opening
`https://github.com/Gord1y/countersign/releases/tag/vx.y.z` and "Copy Upgrade Command" copying the
command `ApprovalCore.UpdateCommand.upgrade(forResolvedExecutablePath:)` picks: `brew upgrade
countersign` when the running binary resolves under a Homebrew Cellar (the same rule
`StableExecutablePath` uses to find the stable link), otherwise the `curl | sh` installer. A manual
check ("Check for Updates…") that finds nothing newer instead shows a disabled "Countersign is up
to date" line in that same spot, and a failed manual check shows "Couldn't check for updates"; both
disappear the next time the menu closes, tracked in memory by `CompanionController`, never
persisted. A background check that finds nothing newer shows neither line, since nobody asked to be
told.

Only a manual check answers with an alert (`ApprovalCore.UpdateCheckAnswer.answer`, shown through
`UpdateCheckAlert`), because choosing "Check for Updates…" closes the menu the in-menu line would
have appeared in; the automatic daily check stays silent, the same as before. The companion never
shows a notification for any of this, and it never downloads or installs anything: `curl | sh` and
Homebrew are already this project's only update paths, each
fetching the same prebuilt release tarball and checking it against a published checksum. A
companion that updated itself would need to replace a running, ad-hoc-signed binary with one
fetched over the network with no code-signing identity to check against, which is exactly the kind
of unverified-code execution this project exists to gate in the first place.
