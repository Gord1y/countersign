---
version: 0.1.0
date: 2026-09-28
title: "Countersign 0.1.0: one approval panel for Claude Code, Codex, Cursor and Antigravity"
summary: "The first release. Permission prompts from every Claude Code, Codex, Cursor and Antigravity session wait in one queue and appear one at a time in a native panel, only once you pause, with real context for edits and commands. Answer in the chat instead and the panel steps aside; any error leaves the agent's own prompt in charge."
type: major
breaking: false
highlights:
  - "One queue for every agent session, shown only once you stop typing"
  - "Edits in their enclosing function with real line numbers; questions and plans in the panel"
  - "Settings and an optional menu-bar app to wire agents, tune panels, pause or snooze"
tags:
  - claude-code
  - codex
  - cursor
  - antigravity
testedWith:
  claudeCode: "2.1.278"
  codex: "0.157.1"
  cursor: "3.21.18"
  antigravity: "1.2.12"
---

## Added

- One native macOS panel for Claude Code and Codex permission requests, the shell commands Cursor
  runs outside its sandbox, Cursor's MCP tool calls, and Antigravity's commands and MCP tool calls.
- Requests from every session and every agent wait in one queue and appear one at a time, only
  once you stop typing, clicking or scrolling (5 seconds by default).
- While a panel is up it owns the keyboard without taking focus from your app: <kbd>Return</kbd>
  approves, <kbd>⌫</kbd> opens Deny, <kbd>Esc</kbd> answers in the chat, and keys and clicks in its
  first moments are ignored so a stray keystroke can't answer it.
- Answer in Claude Code's chat instead and its panel, or the queued request, drops out by itself;
  an optional grace period skips the panel entirely when you answer there first.
- Edits and Codex patches shown inside their enclosing function with real line numbers, and rows
  that expand the unchanged lines around them.
- **Approve ▾** lists the "Always allow" rules Claude Code suggests, each with the exact rule and
  where it is saved; <kbd>⌘</kbd><kbd>Return</kbd> opens it. Deny takes a reason, and for Claude
  Code also offers **Deny & stop**.
- Claude's questions as tabs with numbered options, multi-select and an Other field; plans as
  Markdown with the mode Claude continues in, which starts on your **Mode after a plan** setting.
- Snooze for a preset time, or pause Countersign so every request goes to its chat.
- A Settings window: the status at the top; **Agents** to wire, update or remove each agent's hooks,
  showing every change before it is written and backing up each file first; **Panels** and **App**
  for timing, appearance and accent colour, each setting with an explanation and a reset; **Help**
  for the tour, documentation, updates and support links; and test panels to try your settings on.
- An optional menu-bar app with the status, Pause, Snooze, Settings, a test panel, Launch at Login
  and Check for Updates.
- `countersign doctor`, a plain report to paste into a bug report. It and Settings warn when
  Countersign is installed twice, help you choose which copy to keep, and flag a menu-bar app older
  than its command-line tool.
- `countersign help` lists every command with the help and support links.
- A Homebrew formula in `gord1y/tap` and an install script that asks whether to add the menu-bar app
  and whether to open setup when it's done.

## Changed

- None.

## Fixed

- None.

## Removed

- None.

## Security

- Any error, crash or timeout means "no decision", never an approval: the agent falls back to its
  own prompt.
- No account and no telemetry. The only network request Countersign can make is the update check,
  which is off until you turn it on or choose Check for Updates.

## Notes

- Codex asks you to trust Countersign's hook once: run `/hooks` in Codex in a terminal and trust it.
- Antigravity still asks once more in its own prompt after you approve in the panel, until Google
  fixes [antigravity-cli#1053](https://github.com/google-antigravity/antigravity-cli/issues/1053).
  Every known gap is listed in
  [Limitations](https://github.com/Gord1y/countersign/blob/main/docs/limitations.md).
- The app is ad-hoc signed, not notarized. Install with Homebrew or the install script rather than
  opening an archive downloaded in a browser, which macOS quarantines and refuses to open.
