---
paths:
  - Sources/countersign/**
---

# The panel, the hook runtime and the CLI

- The `hook` path never writes to stderr and never exits non-zero. Every failure, timeout or
  crash means "no decision": exit 0, empty stdout. Nothing is ever decided by a timeout.
- The panel never activates its own app. It is a non-activating panel that becomes key; see
  "Never activating" and "Keyboard alert without activation" in
  [docs/design/panel.md](../../docs/design/panel.md).
- While a panel is visible it owns the keyboard: Return is the primary action; ⌘Return opens the
  step's ▾ menu where it has one (Approve ▾ on a permission panel with rules, then: on a plan) and
  closes it again, denies and stops in the Permission deny step, and otherwise does what Return
  does, Esc answers in the chat, Delete opens the deny step (Permission) or the feedback step
  (Plan) when the view uses it, and keys and clicks during the arm lock are swallowed, never
  passed through.
- The idle gate, the queue and the display lease decide when a panel may appear. Change them only
  with the matching section of [docs/design/panel.md](../../docs/design/panel.md) and
  [docs/design/queue.md](../../docs/design/queue.md) updated in the same commit.
- Builders never put a window on screen: no `countersign preview`, `hook`, `setup` or `settings`,
  and never `scripts/install.sh`. Check layouts with the offscreen `countersign snapshot` (see
  "Snapshots" in [docs/design/panel.md](../../docs/design/panel.md)) and list the PNGs in the
  report. What a PNG cannot show, keyboard, focus and animation, is reported for the orchestrator
  to check on `main`.
