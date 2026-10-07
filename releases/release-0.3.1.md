---
version: 0.3.1
date: 2026-10-07
title: "Countersign 0.3.1: the copied app keeps your hooks on Homebrew's countersign"
summary: "With Homebrew, Settings in the Countersign.app copy in ~/Applications listed correctly wired agents as needing an update, and Update then pointed their hooks into the copy. It now wires them to Homebrew's countersign, and shows them as wired."
type: patch
breaking: false
highlights:
  - "Settings in the copied app keeps your hooks on Homebrew's countersign"
tags:
  - homebrew
  - setup
testedWith:
  claudeCode: "2.1.278"
  codex: "0.159.3"
---

## Added

- None.

## Changed

- None.

## Fixed

- With Homebrew, Settings in the Countersign.app copy in `~/Applications` no longer lists agents
  wired to Homebrew's `countersign` as needing an update. **Update**, **Wire** and the setup
  window wire them to Homebrew's `countersign` instead of into the copy.

## Removed

- None.

## Security

- None.

## Upgrading

- If you pressed **Update** or **Wire** in the copied app's Settings in 0.3.0, your hooks point
  into the copy. Open **Settings ▸ Agents** and press **Update** on each agent it lists as
  needing one, or run `countersign setup --cli --yes`. `countersign doctor` warns while any hook
  still points into the copy.
