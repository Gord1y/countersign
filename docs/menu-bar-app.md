# The menu-bar app

What the optional menu-bar app is for: pausing and snoozing from the menu bar, opening Settings,
trying your settings on a test panel, starting at login, checking for updates and getting help.
Read it when you want Countersign's status in your menu bar, or wonder whether you need the app
running at all.

You don't need it for approvals. Every panel comes from the short-lived hook process an agent
starts for its request, never from the app, so approvals work exactly the same whether the app is
running, was never opened, or was quit, unless you [pause them when you quit](#quit).

## Open it

Open Countersign.app from the Finder, Spotlight or Launchpad. The curl installer puts it in
`~/Applications`; Homebrew keeps it at `$(brew --prefix)/opt/countersign/Countersign.app`, and the
Settings window offers to link it into `~/Applications`. The curl installer also opens it for you
at the end of a fresh install, unless you set `COUNTERSIGN_SETUP=0`; see
[release.md](release.md#opening-countersign-at-the-end).

The curl installer asks whether to install the app, and skipping it is fine: `countersign setup`
covers everything the app's Settings window does, and `pause`, `resume`, `snooze` and `status`
cover the menu's toggles. To add the app later, rerun the installer with `COUNTERSIGN_APP=1` set:

```sh
curl -fsSL https://raw.githubusercontent.com/Gord1y/countersign/main/install.sh | COUNTERSIGN_APP=1 sh
```

This updates the CLI to the same release alongside installing the app.

Opening the app starts it in the menu bar and opens the Settings window. Opening it again while it
runs brings Settings to the front instead of starting a second copy. Started at login, it stays in
the menu bar without opening a window.

## What the icon shows

An outline fountain-pen nib while Countersign is on. While paused, a small pause-bars mark sits in
the nib's bottom-right corner; during quiet time, a small moon sits there instead. The icon is the
same size in every state, so the nib never shifts. Pausing or snoozing from the terminal or from a
panel shows up in the icon within two seconds.

## Pause, snooze and pending requests

- **Pause Countersign** and **Resume Countersign** do the same as `countersign pause` and
  `countersign resume`. While paused, no panel appears, and every request is left to its agent (see
  [agents.md](agents.md#when-countersign-gives-no-answer)). Pausing also ends quiet time, so
  **Snooze** is disabled while paused: a pause already sends every request to its agent, and a
  snooze underneath it would only resurface later as a surprise.
- **Snooze** starts quiet time for one of your presets (the top-level `snoozeMinutes` in the
  [config file](configuration.md)), like `countersign snooze`. Requests wait and come back one at a
  time when it ends. Once quiet time is running, **Snooze** is replaced by a single **End Quiet
  Time (until …)** entry that ends it early.
- The menu lists the requests waiting for a panel, oldest first, by agent, project and tool. The
  list is for reading only; each request is answered in its own panel.

## Settings

**Settings…** (<kbd>⌘</kbd><kbd>,</kbd> while the menu is open) opens the Settings window. Under
the line that says whether Countersign is on, its five groups are **Agents**, where you
[connect your agents](setup.md), **Panels**, for how panels behave, **App**, for what this app
does, **Help**, for guides, updates and ways to support Countersign, and **Advanced**, for where
the [config file](configuration.md) is. Closing the window leaves the app running.

The first time Settings opens, a short four-step tour appears over it: what wiring an agent does,
how a panel waits for you before it appears, the test panel, and what's under App. Skip or Done on
its last step means it won't come back on its own; **Show the Tour** under **Help**, in the menu or
in Settings, brings it back whenever you want it.

## Test panel

**Show a Test Panel** shows what your settings do without waiting for an agent to ask for
something. It brings up a panel for a harmless sample command, `git push origin main`, from a
project called "Countersign test", with a **Test** label next to the name. It shows right away,
without your grace period or a pause in your typing, and then behaves like a real panel with your
current settings: it ignores keys and clicks for the arm delay, offers your Snooze presets, and if
you switch to another app it steps aside and comes back after your idle wait.

Only one test panel shows at a time, and real requests always come first. While it is up,
**Show a Test Panel** is dimmed. If a panel is already on screen, or a request is waiting for
one, the test panel doesn't show and an alert says which: "A panel is already on screen; answer it
first." or "A request is waiting for a panel; answer it first." A request that arrives while the
test panel is up closes it and takes its place.

Try every key and button: whatever you choose only closes the test panel. Nothing runs, and
nothing reaches an agent. Picking a Snooze duration closes it too, without starting quiet time.
Because you asked for it, it appears even while Countersign is paused or in quiet time, and
`handoffApps` doesn't apply.

In Settings, **Show a test panel** at the end of **Panels** has a button for each kind:
**Command**, **Question** and **Plan**. They are dimmed and the row says "Showing a test panel…"
while one is up, and a test panel that doesn't show says why on the row. From the terminal,
`countersign test-panel` does the same, and `countersign test-panel question` and
`countersign test-panel plan` show a set of questions or a plan instead; when it can't show, it
prints the reason, such as `countersign: a panel is already on screen; answer it first`, and
exits with status 1. What you chose is
written to the log, `~/Library/Logs/Countersign/countersign.log`, on a line starting with
`test panel: `.

## Launch at Login

**Launch at Login** registers Countersign.app itself as a login item, with no helper app or launch
agent, so it starts in the menu bar when you log in. When macOS wants your approval first, the item
says so and takes you to System Settings > General > Login Items. The login item points at the app
where it was when you turned this on, so check that list after moving the app. The Settings window
has the same switch under **App** when it runs from Countersign.app.

## Check for updates

The update check is off by default. Set `checkForUpdates` to `true` in the
[config file](configuration.md), or turn it on under **App** in Settings, and the app checks at
most once every 24 hours. **Check for Updates…** checks right away, whatever the setting.

A check is one HTTPS `GET` of
`https://raw.githubusercontent.com/Gord1y/countersign/main/releases/index.json`, the list of
releases: no cookies, no query and no body, only the standard headers macOS adds to any web
request. When a newer
release exists, the menu shows **Update available** with its release notes and the command to
upgrade (`brew upgrade countersign` for a Homebrew install, the curl installer otherwise) to copy.
The app never downloads or installs anything and never shows a notification. Choosing **Check for
Updates…** answers with an alert once the check completes: up to date, the new version with its
upgrade command and release notes, or that the check failed. The automatic daily check stays
silent; a failed automatic check is only written to the log. The time of the last check is kept in
`~/Library/Application Support/Countersign/update-check.json`.

Settings ▸ **Help** also has a **Check for Updates** button, for checking without the menu-bar app
running at all. It runs the same check and shows the same release notes and upgrade command, but
doesn't read or write `update-check.json` and doesn't affect the app's next scheduled check.

## Help

- **Show the Tour** opens Settings and shows the first-run tour again, whether or not you've seen
  it before.
- **Documentation** opens the README on GitHub.
- **Report a Problem…** opens a new GitHub bug report, filled in with your macOS version, your
  Countersign version and the report `countersign doctor` prints, with your home folder shown as
  `~`. Nothing is sent until you submit it yourself.
- **Ask a Question…** opens GitHub Discussions, and **Contact the Developer…** opens
  [gord1y.dev](https://www.gord1y.dev/).
- **Support the Developer** links to GitHub Sponsors and Buy Me a Coffee.

Settings ▸ **Help** offers the same: the tour, documentation, asking a question, reporting a
problem, contacting the developer, checking for updates and the two support links, all in one
group. It's there for anyone who runs `countersign settings` without ever opening this menu, such
as someone who installed only the command-line tool. `countersign help` prints the same Help and
support links in the terminal, alongside every command.

## Quit

Panels come from your agents' hooks, not from the app, so they keep appearing after you quit it.
**Quit Countersign** therefore asks first: "Keep showing approval panels while Countersign is
closed?"

- **Keep showing** (<kbd>Return</kbd>) quits the app. Waiting requests keep waiting and panels keep
  appearing.
- **Pause until I reopen** quits the app and pauses Countersign, ending quiet time if it was
  running. Until you open it again, no panel appears and your agents ask in their own chat. Opening
  the app, or its start at login, resumes; `countersign status` says
  `state: paused until Countersign opens` meanwhile, and `countersign resume` ends the pause early.
- **Cancel** (<kbd>Esc</kbd>) keeps the app running.

Tick **Don't ask again** to make your choice stick: the app then quits straight away and does the
same next time. It is saved as `quitBehavior` in the [config file](configuration.md); change it in
Settings under **App**, **When Countersign quits**, where **Ask** brings the question back.

Only **Quit Countersign** asks. Logging out, restarting or shutting down closes the app without
asking and never pauses anything.

A pause you set yourself, from the menu, Settings or `countersign pause`, is not touched by quitting
or opening the app: it lasts until you resume. While it is on, **Quit Countersign** doesn't ask at
all, since neither answer would change anything: the app quits straight away, whatever **When
Countersign quits** says, and nothing is saved. Quiet time stays as it is too. The Settings window
saves each change as you make it, so quitting never asks about settings.
