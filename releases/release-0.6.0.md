---
version: 0.6.0
date: 2026-11-09
title: "Countersign 0.6.0: keep your Mac awake while agents work, and more from the terminal"
summary: "An opt-in Keep Mac Awake holds off idle sleep from the menu-bar app for a time you choose and lets go at a battery level you set. The command line can now do most of what the app does: recent decisions, waiting requests, deny rules, every setting, quitting the app and more. It can never approve a request or add an allow rule."
type: minor
breaking: false
highlights:
  - "Keep Mac Awake: opt in once, pick how long, and it lets go at your battery cutoff"
  - "New commands for decisions, waiting requests, rules, settings, updates and context"
  - "The command line can deny a request but never approve one"
tags:
  - menu-bar
  - command-line
  - settings
testedWith:
  claudeCode: "2.1.318"
  codex: "0.159.3"
---

## Added

- **Keep Mac Awake.** Turn it on once under Settings ▸ App, after a short explanation of what it
  does. Then start it from the menu-bar app or Settings for 1, 4, 8 or 12 hours, or until you turn
  it off. A small dot on the menu-bar icon shows it is holding.
- **A battery cutoff for Keep Mac Awake.** On battery power it lets go at your cutoff, 15% by
  default, and picks up again when you plug in. The display still sleeps as usual.
- **`countersign keep-awake on|off|status`.** Start and stop it from a terminal, with `--for 90m` or
  `--forever`, and see it in `countersign status`. It needs the opt-in and the menu-bar app running.
- **`countersign decisions`.** Lists your recent answers; `decisions clear` empties them.
- **`countersign pending`.** Lists the requests waiting for a panel with their IDs, and
  `pending show|deny|chat <id>` answers one the way the menu does.
- **`countersign rules list` and `rules deny`.** Print your rules, or add a deny rule with the same
  checks as Settings.
- **`countersign config get|set|reset|open`.** Read or change any setting with the same limits as
  Settings, restore one setting or a whole pane, or open `config.json`.
- **`countersign update-check` and `countersign context`.** Check for a new release now, and see the
  context used by live Claude Code sessions.
- **`countersign test-card notice|approval`.** Show a sample corner card; nothing reaches an agent.
- **`countersign quit [--pause]` and `countersign launch-at-login on|off`.** Control the running
  menu-bar app from a terminal.

## Changed

- None.

## Fixed

- None.

## Removed

- None.

## Security

- None.

## Notes

- An agent can run `countersign`, so no command approves a request or adds an allow rule.
  `config set` also leaves the Keep Mac Awake opt-in, the mode after a plan and the two settings
  that change your agents' hook files to Settings.
- A closed lid still sleeps the Mac. Every launch of the app starts with Keep Mac Awake off, and
  quitting the app ends it.
