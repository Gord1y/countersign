# Documentation

Every page about Countersign beyond the README, grouped by who it is for. Read it to find the page
for what you want to do; each line says when that page is the one to open.

## Using Countersign

- [Connect your agents](setup.md): read it when you install Countersign, add another agent, or
  want to know what setup wrote to your files and how to undo it.
- [Configuration](configuration.md): read it when you want to change how long the panel waits,
  the snooze presets, quiet hours, the sound, waiting-agent notices, the update check, context
  checkpoints, or a setting for one agent, or try your settings on a test panel.
- [What each agent gets](agents.md): read it to know what Approve, Deny or "Answer in chat" does
  in Claude Code, Codex, Cursor or Antigravity, and which requests get a panel.
- [The menu-bar app](menu-bar-app.md): read it when you want pause, snooze, Settings and a test
  panel in your menu bar, Launch at Login, or the update check.
- [Troubleshooting](troubleshooting.md): read it when no panel appears, a panel goes away on its
  own, an agent asks twice, or you want to report a problem.
- [Limitations](limitations.md): read it before relying on Countersign for something specific, to
  see what it can't do yet, agent by agent.
- [Safety and privacy](safety-and-privacy.md): read it to see why nothing is ever approved by
  accident, what Countersign reads and writes on your Mac, and its one network request.

## Contributing

- [Tooling](tooling.md): read it before changing a script, the commit message check, a CI
  workflow or a repository setting on GitHub.
- [Releasing](release.md): read it when you cut a release or change the curl installer.
- [Screenshots](screenshots.md): read it when a README screenshot needs updating.
- [Release notes](../releases/README.md): read it when you write a release note.
- [Design overview](design/README.md): read it first, for the path from a prompt arriving to a
  decision; each note below explains one part and why it works that way.
  - [Panel](design/panel.md): the keyboard alert, waiting for a pause, the test panel, questions
    and plans, the permission view, snapshots.
  - [Queue](design/queue.md): the display lock, liveness, warm standby and the queue handoff.
  - [Resolution watching](design/resolution.md): noticing an answer in Claude Code's chat, and
    skipping non-interactive sessions.
  - [Hosts](design/hosts.md): the Claude Code, Codex, Cursor and Antigravity adapters and what each
    host sends and accepts.
  - [What the hook answers](design/answers.md): the exact output and log line for every way a
    request can end, per host.
  - [Setup internals](design/setup.md): the entries setup writes, how it recognises its own,
    byte-for-byte editing, backups, and the stable path.
  - [Settings internals](design/settings.md): how the config file is resolved and parsed, and how
    the settings window saves it.
  - [Doctor internals](design/doctor.md): every check `countersign doctor` runs, in order.
  - [The app bundle and the menu-bar companion](design/app.md): bundle layout, signing, app mode vs
    CLI, the companion's single instance, menu, test panel launch and update check.
  - [The app icon](design/icon.md): the app icon: what it is, why amber, and the copy of its mark
    the panel's header draws in code.
  - [Context checkpoints](design/checkpoints.md): how a Claude Code session's context size is
    measured from its transcript.
  - [Waiting notices](design/notice.md): how an agent that ended its turn is recorded, how the
    corner card decides when to show and when to close, and what it never does.
- [Roadmap](../ROADMAP.md): read it for the ideas under consideration and what would move each one
  forward.
