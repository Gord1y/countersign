---
version: 0.4.0
date: 2026-10-13
title: "Countersign 0.4.0: a stop checkpoint, cache warnings and checkpoints for Codex"
summary: "Context checkpoints gain a fourth rung that asks Claude to stop and write a handoff, also checked after each tool call. A corner card warns 10 minutes before a large idle session's cache goes cold, approval panels show the session's context size, and Codex gets checkpoint notes at 50, 60 and 70% of its window with a stop at 80%. Copy and cut work in the panel's fields."
type: minor
breaking: false
highlights:
  - "A stop checkpoint that asks Claude to collect its subagents' findings and write a handoff"
  - "A corner card 10 minutes before a large idle session's prompt cache goes cold"
  - "Context checkpoints for Codex: notes at 50, 60 and 70% of its window, a stop at 80%"
tags:
  - claude-code
  - codex
  - context
  - panel
  - setup
testedWith:
  claudeCode: "2.1.296"
  codex: "0.159.3"
---

## Added

- A stop checkpoint. Context checkpoints have a fourth rung: at 160K tokens in a 200K window, or
  600K in a 1M window, Countersign tells Claude, without a panel and in either mode, to start
  nothing new, collect what its subagents have found, write the handoff file and tell you it is
  ready for `/clear`. Countersign also checks it after each tool call of the main session, so a
  long run that never waits for a prompt still reaches it. The note is **Stop** under **Edit
  Notes…** in Settings ▸ Context.
- A cold-cache card. While the menu-bar app runs, a corner card appears 10 minutes before an idle
  Claude Code session past its first checkpoint loses its 1-hour prompt cache, once per idle
  stretch. **Copy handoff prompt** copies the handoff note to paste into that session. Pause and
  quiet time hold the card. Turn it off with **Warn before the cache goes cold** in Settings ▸
  Context, or `contextCheckpoints.coldCacheCard`.
- The session's context size on approval panels. Claude Code permission, question and plan panels
  show it as a chip, `<size> · <percent>%`, next to the permission mode. Hover it for the size
  against the window, the checkpoints, cache warmth and the model.
- Cache warmth in the menu-bar meter: each session's line ends with `warm, N min left` or `cold`.
  The meter stays off by default; turn on **Context in the menu bar** in Settings ▸ Context.
- Context checkpoints for Codex, as notes only: at 50, 60 and 70% of the context window Codex
  reports, and a stop note at 80%, also checked after each tool call. They follow the same switch
  as Claude Code's and are on by default. `contextCheckpoints.hosts.codex` takes `enabled`,
  `rearmBelow`, `handoffFile` and `notes`.

## Changed

- The default checkpoint ladders are 100K, 120K, 140K and 160K for a 200K window, and 200K, 300K,
  400K and 600K for a 1M window. `thresholds` takes three or four numbers; with three, there is no
  stop checkpoint, so a config that sets three keeps working as before.
- The switch is now **Context checkpoints (Claude Code and Codex)**, in its own block in Settings ▸
  Panels. Turning it on or off also changes Codex's `hooks.json`, and the Context tab lists
  **Claude Code hooks** and **Codex hooks**, each with its own **Update**.
- While context checkpoints are on, setup writes two context entries per agent, `UserPromptSubmit`
  and `PostToolUse`. Claude Code's run in the background; Codex's run in line with a 30-second
  timeout.

## Fixed

- Copy, cut, paste, select all, undo and redo work in the panel's text fields: the Other answer,
  the deny reason, plan feedback and the question note. ⌘C and ⌘X used to do nothing there.

## Removed

- None.

## Security

- None.

## Upgrading

- The first time 0.4.0 starts, Settings opens on **Agents** if an agent's hooks need an update:
  Claude Code gains the `PostToolUse` entry, and Codex both context entries. Each **Update** shows
  its change before writing it; `countersign setup` does the same from a terminal.
- Codex then asks you to trust the new hooks: open Codex in a terminal, not the desktop app, run
  `/hooks` and trust them. Codex runs no checkpoints until you do.

## Notes

- A stop note sent after a tool call arrives next to that tool's result, and a model can take it
  for part of the result and ignore it. The note sent with your next prompt does not have that
  problem.
- Codex gets notes only: no panel, meter, card or chip. Cursor and Antigravity get no context
  checkpoints.
