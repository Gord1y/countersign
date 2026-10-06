---
paths:
  - Sources/ApprovalCore/**
  - Tests/**
---

# ApprovalCore and its tests

- `ApprovalCore` never imports AppKit or SwiftUI. Anything that needs either belongs in
  `Sources/countersign`.
- Every type in `ApprovalCore` is fully covered by `ApprovalCoreTests` (Swift Testing). A new type
  ships with its suite in the same commit.
- Fixtures in `Tests/ApprovalCoreTests/Fixtures` are real payloads captured from a host. Never
  invent a payload shape; when a host's shape is unknown, stop and ask for a capture.
- Host internals are undocumented and change without notice: the Claude Code session registry,
  transcripts and subagent `*.meta.json` files, and the other hosts' files. Read them
  defensively. Any missing file, unknown field or parse failure means "unknown", never a crash
  and never a decision.
- Rationale lives in `docs/`: design notes in `docs/design/<topic>.md` —
  [hosts](../../docs/design/hosts.md), [queue](../../docs/design/queue.md),
  [resolution](../../docs/design/resolution.md), [panel](../../docs/design/panel.md),
  [answers](../../docs/design/answers.md), [setup](../../docs/design/setup.md),
  [settings](../../docs/design/settings.md), [doctor](../../docs/design/doctor.md),
  [app](../../docs/design/app.md),
  [checkpoints](../../docs/design/checkpoints.md), [notice](../../docs/design/notice.md), [rules](../../docs/design/rules.md) —
  user-facing pages in `docs/<topic>.md` —
  [setup](../../docs/setup.md), [configuration](../../docs/configuration.md),
  [agents](../../docs/agents.md), [menu-bar-app](../../docs/menu-bar-app.md),
  [troubleshooting](../../docs/troubleshooting.md), [limitations](../../docs/limitations.md),
  [safety-and-privacy](../../docs/safety-and-privacy.md) — and the maintainer page
  [release](../../docs/release.md). Update the matching doc in the same commit when behaviour
  changes.
