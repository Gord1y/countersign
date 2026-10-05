---
version: 0.2.0
date: 2026-10-05
title: "Countersign 0.2.0: allow and deny rules, waiting-agent notices and context checkpoints"
summary: "Rules answer routine requests before a panel shows, in Settings or config.json, for all four agents. A corner card tells you when an agent is waiting or an approval is stuck behind your typing. Claude Code gets context checkpoints, on by default. Cursor's Esc now follows its Run Mode, and you can answer from the menu bar."
type: minor
breaking: false
highlights:
  - "Allow and deny rules that answer before a panel shows, for all four agents"
  - "Corner cards when an agent is waiting for you or an approval is stuck behind your typing"
  - "Context checkpoints for Claude Code, and Esc in Cursor that follows its Run Mode"
tags:
  - claude-code
  - codex
  - cursor
  - antigravity
testedWith:
  claudeCode: "2.1.278"
  codex: "0.159.3"
  cursor: "3.23.12"
  antigravity: "1.2.17"
---

## Added

- Allow and deny rules. A rule answers a request before any panel shows: an allow rule lets it
  through, a deny rule blocks it and tells the agent why. Rules apply to Claude Code, Codex, Cursor
  and Antigravity, live in the `rules` list of `config.json`, and can be narrowed by agent, project
  folder, tool name or shell command. A deny rule always beats an allow rule.
- A **Rules** page in Settings to add, edit and remove rules, with a confirmation before a rule is
  removed, and four suggested rules you add with one click: deny `rm -rf`, deny git history
  rewrites, deny `sudo`, and allow read-only git.
- **Always allow** in the **Approve ▾** menu for Codex. It approves the request and saves a rule
  for Codex and that project, which then shows up under Settings ▸ Rules.
- Waiting-agent notices, on by default. Once an agent has finished a turn and waited for you, a
  corner card says it is waiting, with a **Go there** button that opens the app it runs in. Setup
  and Update in Settings ▸ Agents add the extra hook that makes this work, after showing you the
  change. **Notice after** (10 seconds by default) sets how long the agent waits before the card
  appears, and **Show notice for** (10 seconds by default) sets how long it stays; both are in
  Settings ▸ Panels.
- Approval cards. When a request has been waiting for you to pause and you keep typing, a small
  corner card, such as "Cursor needs your approval · shop-api", has a **Show** button that brings
  the panel up at once. On by default for Codex, Cursor and Antigravity, off for Claude Code, which
  also waits in its chat. Choose the agents and each agent's delays in Settings ▸ Panels, and try
  the cards from Settings. At most two corner cards show at once, and an approval card goes first.
- Context checkpoints for Claude Code, on by default. Countersign estimates how large a session's
  context has grown and, at three checkpoints, shows a panel or quietly adds a note. Choose
  **Continue**, **Not this session**, **Compact after this step** or **Hand off & start fresh**;
  Claude's reply tells you what to run. Turn it off in Settings ▸ Panels, tune it on the new
  **Context** tab with its notes edited in popups, and optionally show each live session's size in
  the menu-bar app.
- Answer pending requests from the menu bar. Each waiting request offers **Show Now**, **Deny**
  and, where the agent can take it, **Answer in Chat**, so you can answer without opening the
  panel. There is no Approve there. **Show Now** brings the panel up even during a snooze or quiet
  hours.
- **Recent Decisions** in the menu bar: your last ten answers, newest first, with a mark for
  approved, denied, answered in the chat or a checkpoint choice, and `rule` for requests a rule
  answered. **Clear History** empties it.
- Quiet hours: recurring windows, such as weekday evenings, in which panels wait like a snooze. Enter
  times as `9`, `9:30` or `21:30`. End now in the menu or the Settings header skips the window that
  is running.
- An optional sound when a panel appears, chosen in Settings ▸ Panels.
- Time settings accept units, such as `500ms`, `90s`, `2m` or `1h`, in Settings and in `config.json`.
- Cursor commands on Cursor's own command allowlist skip the panel when Cursor would run them
  without asking.
- Settings asks which editor to use the first time you choose Open in Editor for `config.json`, and
  remembers the choice.
- Settings and panels work with VoiceOver, Increase Contrast and Reduce Motion.
- A test panel answer now shows what a real request would have done, in a card with a close button.
- Settings shows a reset arrow beside a row only for changes you made in this visit, and its action
  buttons sit on the right.

## Changed

- The ⓘ explanations in Settings open when you hover them, not only when you click.
- Panels ignore keys and clicks for their first 500 ms instead of 800 ms.
- `idleSeconds` and `graceSeconds` in `config.json` now take only the ranges Settings always
  offered, 1 to 30 and 0 to 30 seconds. A value outside them falls back to the default, and
  `countersign doctor` names it.
- <kbd>⌘</kbd><kbd>Return</kbd> only opens a ▾ menu or fires **Deny & stop**. Where a panel has
  neither, it does nothing; it no longer approves or answers in place of <kbd>Return</kbd>.
- Esc on a Cursor request follows Cursor's Run Mode, so Cursor no longer runs a command you
  stepped away from. In Allowlist mode Esc hands the request back to Cursor's own prompt, as
  before. In Auto-review and Run Everything, where Cursor would run it without asking, Esc or a
  click outside puts the panel away as **Later**: a corner card shows at once, and its **Show** or
  **Show Now** in the menu bar brings the panel back. A request left there is denied after an hour
  with "No answer in Countersign within an hour, so Cursor did not run this."
- Pause and Snooze moved into a slimmer Settings header.
- Settings always opens on Agents, instead of the group you last left it on.
- Settings ▸ Panels and App group their rows into titled blocks, such as Delays, Interruptions
  and Corner cards, as the new Context tab does.
- **Wire**, **Update** and **Remove** in Settings ▸ Agents show the change in a popup and write
  only when you confirm it, replacing **Show changes**.
- Settings scrolls more smoothly.
- Shell highlighting in panels is readable on both light and dark appearances.

## Fixed

- Cursor payloads sent to Claude Code's hook are ignored instead of being treated as a Claude Code
  request.
- Panels stay on a usable display when you connect or disconnect screens.
- A test panel stays up when you press a key it doesn't use.
- A panel no longer opens while Mission Control or App Exposé is on screen, or right after you
  swipe to another Space. It waits until you have left them and paused.

## Removed

- None.

## Security

- Any error, crash or timeout still means "no decision", never an approval. If Countersign can't
  read Cursor's run mode, it keeps the command waiting rather than letting Cursor run it.
- A command Countersign can't split safely is never decided by a command rule and shows the panel:
  any command with a `$` outside single quotes (a variable, `$(...)`, `$'...'` or `${...}`),
  backticks, parentheses, braces, a `#` comment, or an output redirection to a file. A compound
  command is allowed only when an allow rule covers every part of it.
- Still no account and no telemetry.

## Upgrading

- The first time 0.2.0 starts, Settings opens on Agents if an agent needs an update for
  waiting-agent notices or context checkpoints. Choose Update on each, or run setup again; each
  change is shown before it is written.
- Codex asks you to trust the new Stop hook once: run `/hooks` in Codex in a terminal and trust it.

## Notes

- Cursor currently ignores an approval from a hook, a bug Cursor has confirmed, so after you
  approve, Cursor's run mode decides: in Allowlist mode Cursor asks you again. **Deny** always
  blocks. For the same reason, Cursor and Antigravity get no **Always allow**, and an allow rule for
  them only keeps the panel away.
- Countersign reads Cursor's run mode and command allowlist from Cursor's local settings, which
  Cursor does not document. If it can't read them, it treats the mode as unknown and keeps the
  command waiting rather than letting Cursor run it.
- A rule's command matches as a prefix, so allowing `rm -rf build` also allows `rm -rf build /tmp`.
  Deny rules catch the spellings they name; anything else, such as `rm -r -f`, still shows the
  panel.
- Context checkpoints are Claude Code only, read an estimate from the session transcript that can
  lag a turn, and cannot run `/compact` themselves. Every known gap is listed in
  [Limitations](https://github.com/Gord1y/countersign/blob/main/docs/limitations.md).
