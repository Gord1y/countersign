---
version: 0.3.0
date: 2026-10-07
title: "Countersign 0.3.0: a setup window, a Spotlight-visible app for Homebrew and a Skills page"
summary: "A three-step setup window wires the agents it finds, with every change shown first, and replaces the tour. With Homebrew, Settings copies Countersign.app into ~/Applications, where Spotlight finds it, and keeps it current after brew upgrade. Settings gets a read-only Skills group, and the command line and update check get fixes."
type: minor
breaking: false
highlights:
  - "A setup window that wires the agents it finds in three steps, replacing the tour"
  - "A Spotlight-visible Countersign.app copy for Homebrew installs, kept current after brew upgrade"
  - "A read-only Skills group in Settings for the countersign-skills you have installed"
tags:
  - claude-code
  - codex
  - setup
  - homebrew
testedWith:
  claudeCode: "2.1.278"
  codex: "0.159.3"
---

## Added

- A setup window. `countersign setup`, the last step of the curl installer and the first time you
  open Countersign.app on a new Mac show three steps: wire the agents Countersign found with one
  button, with each change behind **Show the change**; try a test panel; then finish, or open
  Settings. **Help ▸ Set Up…** opens it again and replaces **Show the Tour**. `countersign settings`
  opens Settings, and `countersign setup --cli` stays the terminal flow.
- A copy of Countersign.app for Homebrew installs. **Settings ▸ App** copies the app into
  `~/Applications`, so Spotlight and Launchpad find it, which the 0.2.0 link did not. It replaces
  a 0.2.0 link and updates an older copy.
- A **Skills** group in Settings, read only. It lists the skills and rules countersign-skills
  installed, their versions, which have updates and the command that runs them. It reads local
  files only. A skills folder in Documents, Desktop, Downloads, iCloud Drive or on an external
  drive is read only after you choose **Show Skills from This Folder**, and macOS then asks for
  access. Hide it with **Skills in the sidebar** in **App ▸ Appearance**, or `showSkills` in
  `config.json`.
- `--help` after any command prints that command's usage.
- `snooze` accepts up to 24 hours and says so when you ask for more.

## Changed

- **Wire**, **Update** and **Remove** fold the line-by-line change behind **Show the change (N
  lines added)**, and long lines wrap instead of running off the side.
- Settings no longer switches to another group right after it opens, and shows each agent's
  current status from the first frame. In 0.2.0 it could show "Needs an update" for a second, then switch.
- After `brew upgrade`, the menu-bar app updates its copy in `~/Applications` and restarts itself.
- `countersign doctor` counts that copy as part of the Homebrew install and says when it is older
  than Homebrew's. Hooks and the upgrade command point at Homebrew's `countersign`, also from the
  copied app.
- `pause`, `resume` and `status` refuse extra arguments. `pause --help` used to pause.
- The "Update available" line disappears once you install that version. A failed update check no
  longer erases an update it already knew about, and retries an hour later. **Check for
  Updates…** answers while a scheduled check is running, and a check started in Settings shows in
  the menu.

## Fixed

- A hook exits cleanly when the agent closes the reply early.
- A request whose file was removed is skipped at once.
- The menu-bar app retries its lock instead of deferring to an instance that is gone.
- The `config.json` schema accepts every time and duration the app accepts.
- VoiceOver reads each installed copy in **More than one copy** as one choice.
- Wiring an agent twice within the same second no longer fails on the second backup of its
  config file.
- The docs name `setup --cli --uninstall`, not `setup --remove`, list the per-agent keys in
  configuration, and describe doctor's `rules` line.

## Removed

- The tour, replaced by the setup window.

## Security

- None.

## Upgrading

- With Homebrew, open **Settings ▸ App** once and copy the app into `~/Applications`. A 0.2.0 link
  is replaced.

## Notes

- Nothing you configured stops working.
