---
version: 0.5.0
date: 2026-10-19
title: "Countersign 0.5.0: checkpoints that ask before they stop, and keep your work"
summary: "Context checkpoints now have three rungs by default: a prompt to compact or continue, a prompt to hand off or compact, and a stop that has Claude finish the task in hand and hand off without tearing anything down. Each checkpoint's choices are configurable, Countersign counts compactions and stops offering Compact after five, and a panel that steps aside comes back as you left it."
type: minor
breaking: false
highlights:
  - "Three checkpoints by default: compact or continue, hand off or compact, then a stop that keeps your work"
  - "Choose what each checkpoint offers, and stop offering Compact after a set number of compactions"
  - "A panel that steps aside comes back with what you typed, picked and scrolled to"
tags:
  - claude-code
  - context
  - panel
testedWith:
  claudeCode: "2.1.299"
  codex: "0.159.3"
---

## Added

- **Choose what each checkpoint offers.** Settings ▸ Context has a row per checkpoint with
  Compact, Hand off, Continue and Not this session, and a Highlighted menu for the one Return
  picks. In `config.json` this is `contextCheckpoints.choices`. By default the first checkpoint
  offers Continue, Compact and Not this session, and the second Hand off, Compact and Continue.
  Not this session is off the second by default, so an answer there can never mute the stop.
- **A compaction limit.** Countersign counts how often a session has been compacted. Once it
  reaches **Compactions before hand-off only** (`maxCompactions`, default 5), a checkpoint no
  longer offers Compact, because a summary of a summary keeps too little. The panel says how many
  times the session has been compacted, and in silent mode a new `limit` note asks Claude to hand
  off instead.

## Changed

- **Three checkpoints by default.** The 200K ladder is now 100K, 130K and 160K, and the 1M ladder
  200K, 300K and 500K: a prompt to compact or continue, a prompt to hand off or compact, and the
  stop as the backstop when the second goes unanswered. The 1M stop sits at half the window, well
  before Claude Code's own auto-compact.
- **A ladder takes two to four numbers.** With three or four, the last is the stop; two turn the
  stop off; four add a third prompt, insist, before the stop.
- **The stop and hand-off notes keep your work.** Claude finishes the task in hand, starts nothing
  new, and leaves worktrees, branches, uncommitted changes and run folders as they are, so the
  next session does not have to rebuild them. It writes the handoff the way the project's own
  instructions say, and falls back to the handoff file when they name no way.
- **The second checkpoint asks, in silent mode too.** Its note now has Claude stop after the
  current step and ask you whether to compact or hand off, instead of only posting a status.
- **The log names the app that took the keyboard.** When a panel steps aside, the line in
  `~/Library/Logs/countersign/countersign.log` now reads `stepped aside: app switch to <app id>`
  or `stepped aside: focus lost, <app id> frontmost`, so you can tell which app keeps pulling
  panels away.

## Fixed

- **A panel that steps aside comes back as you left it.** Switching apps, another app bringing
  itself to the front, quiet time, a snooze or Later used to bring the request back with an empty
  panel. Now your answers to a question, your own answer and notes, the tab you were on, a deny
  reason, plan feedback, the mode picked for after the plan, the diff lines you revealed and the
  scroll position all come back, and so does the text field you were typing in, with the cursor
  where you left it, so you can carry on typing.

## Removed

- None.

## Security

- None.

## Upgrading

- A ladder you set yourself with three numbers now ends in the stop. To keep a ladder without a
  stop, give it two numbers; give it four to keep the insist prompt before the stop.
- If you never set a ladder, you get the new three-rung defaults.
- Notes you rewrote keep your text; only notes left at their default get the new wording.
- Countersign works best with countersign-skills 1.4.0, whose `context-transfer` and
  `orchestrate` act on these notes. Pull it and re-run its `install.sh`.

## Notes

- Codex keeps its four checkpoints at 50, 60, 70 and 80% of its window, and its compactions are
  not counted.
- Countersign does not change Claude Code's auto-compact settings.
