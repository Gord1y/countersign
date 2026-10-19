---
version: 0.4.2
date: 2026-10-19
title: "Countersign 0.4.2: a panel that steps aside keeps your answer"
summary: "When another app takes the keyboard while a panel is up, the panel steps aside and comes back after your next pause. Until now it came back empty, so anything you had typed or picked was lost. It now comes back as you left it."
type: patch
breaking: false
highlights:
  - "A panel that steps aside comes back with what you typed, picked and scrolled to"
tags:
  - panel
testedWith:
  claudeCode: "2.1.299"
  codex: "0.159.3"
---

## Added

- None.

## Changed

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
