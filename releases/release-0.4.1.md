---
version: 0.4.1
date: 2026-10-17
title: "Countersign 0.4.1: checkpoints follow the 1M window again"
summary: "Since Claude Code 2.1.301, sessions on models with a 1M-token window by default, such as Opus 5.5, hit the 200K checkpoints and were told to stop at 160K. Countersign now knows which models default to 1M and uses the 1M checkpoints for them."
type: patch
breaking: false
highlights:
  - "1M-window sessions get the 1M checkpoints again"
tags:
  - claude-code
  - context
testedWith:
  claudeCode: "2.1.302"
  codex: "0.159.3"
---

## Added

- None.

## Changed

- None.

## Fixed

- **Checkpoints and the context gauge use the 1M window for models that have it by default.**
  Opus 4.7 and later and every Claude 5 model count as 1M, as does any model id with `[1m]`;
  older models, an unknown model, or `CLAUDE_CODE_DISABLE_1M_CONTEXT` set keep the 200K ladder.

## Removed

- None.

## Security

- None.
