# What the hook answers

The exact output `countersign hook` produces for every way a request can end, for each host, the
line it logs, and what the host does with it. Read it before changing a host adapter's `encode`, an
`ApprovalOutcome`, or any path in `HookRunner` that ends a request; what each answer means to a
user is in [../agents.md](../agents.md).

Every prompt starts a short-lived `countersign hook` process. It reads one request JSON object on
stdin and either prints one decision object to stdout, or exits with empty stdout, which the root
[CLAUDE.md](../../CLAUDE.md) hook contract makes mean the same thing every time: "no decision, show
your usual prompt." This note is that contract worked out for every way a request can end: the
exact JSON `ApprovalCore`'s host adapters print (from
[`ClaudeAdapter.swift`](../../Sources/ApprovalCore/ClaudeAdapter.swift) and
[`CodexAdapter.swift`](../../Sources/ApprovalCore/CodexAdapter.swift), matched against
`ClaudeAdapterTests`/`CodexAdapterTests`), and what the host does with it. Cursor and Antigravity
speak different protocols; their outcomes are in "Cursor" and "Antigravity" at the end.

The JSON below is pretty-printed for reading; the hook actually writes it with sorted keys on one
line (`JSONEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]`), followed by a
newline. Both hosts read this shape as `PermissionRequestDecision`: `{"behavior": "allow", ...}` or
`{"behavior": "deny", ...}`, confirmed against Claude Code's own type definitions via context7.
Codex's own hook engine falls back to "the normal approval flow", its own prompt, whenever no hook
returns a decision, confirmed against the Codex CLI source (`run_permission_request_hooks`) via
context7; that is the mechanism behind every "no answer" row below on the Codex side.

Claude Code's downstream handling of a decision once it reaches Claude (for example, exactly how it
uses a deny `message` as feedback, or an `updatedInput.answers` object) is not documented beyond the
type shape itself, so those effects are marked unverified below rather than guessed at.

## Approve

**Return**, or clicking **Approve**, sends the request through unchanged. `PermissionView` calls
`model.finish(.allowAsIs)` (see "The permission view" in [panel.md](panel.md)).

Claude:

```json
{
  "hookSpecificOutput": {
    "decision": { "behavior": "allow" },
    "hookEventName": "PermissionRequest"
  }
}
```

Codex encodes the same outcome the same way; Codex's adapter never emits `updatedInput` or
`updatedPermissions` regardless of what the outcome carries (see "Why the Codex adapter drops
fields" in [hosts.md](hosts.md)). Both hosts read `behavior: allow` as approval and run the tool
call as originally requested.

## Approve ▾ "Always allow" a rule (Claude only)

Claude Code's own `permission_suggestions` become the **Approve ▾** menu's rules (see "How
suggestion labels are built" in [hosts.md](hosts.md)); picking one sends that suggestion's raw JSON
back as an `updatedPermissions` entry, unmodified:

```json
{
  "hookSpecificOutput": {
    "decision": {
      "behavior": "allow",
      "updatedPermissions": [{ "type": "addRules", "rules": [{ "toolName": "Bash", "ruleContent": "npm test" }] }]
    },
    "hookEventName": "PermissionRequest"
  }
}
```

Codex sends no `permission_suggestions` in its request in the first place (`CodexAdapter.parse`
always builds `suggestions: []`), so this menu entry never appears for a Codex request. Claude Code
applies the rule; what "applying" a given rule `type` (`addRules`, `setMode`, `addDirectories`, an
unrecognized type) changes in the session beyond this request is Claude Code's own behavior and is
not verified here beyond what the type name implies.

## Deny, with or without a reason

<kbd>⌫</kbd> or **Deny** opens a reason field; **Deny** with it empty, or with only whitespace,
still sends a decision: `ApprovalOutcome.deny(reason:interrupt:)` trims the reason and substitutes
`ApprovalOutcome.defaultDenyMessage`, `"Denied in the approval panel."`, when nothing meaningful is
left (see "The deny message default" in [hosts.md](hosts.md)):

```json
{
  "hookSpecificOutput": {
    "decision": { "behavior": "deny", "message": "Denied in the approval panel." },
    "hookEventName": "PermissionRequest"
  }
}
```

A typed reason replaces that message verbatim. Codex encodes `behavior` and `message` the same way
and drops nothing here; only `interrupt` is Claude-only. Both hosts treat this as a denial and stop
that tool call; whether or how the message reaches the model beyond that is not verified here.

## Deny & stop (Claude only)

**Deny & stop** sends the same deny decision with `interrupt: true`:

```json
{
  "hookSpecificOutput": {
    "decision": {
      "behavior": "deny",
      "interrupt": true,
      "message": "Denied in the approval panel."
    },
    "hookEventName": "PermissionRequest"
  }
}
```

`interrupt` is a Claude-only extension, so `PermissionView` shows **Deny & stop** only when
`host.supportsInterrupt`, which is true for Claude alone: a Codex panel offers plain **Deny** and
nothing else. `CodexAdapter.encode` never emits `interrupt` either, so even an outcome that carried
it would reach Codex as the identical body a plain **Deny** sends. What `interrupt: true` changes in
the running Claude turn beyond stopping the call, is documented only as the field's presence in
`PermissionRequestDecision`; anything more specific is unverified here.

## Answer in chat

<kbd>Esc</kbd>, the **Answer in chat** button, and a click outside the panel all call
`model.finish(.noDecision)` (`PanelController`, `PanelStyle`). `ApprovalCore.ClaudeAdapter.encode`
and `CodexAdapter.encode` both return `nil` for `.noDecision`, so the hook writes nothing to stdout
and exits 0. Both hosts read empty stdout as "no decision" and fall back to their own permission
prompt for that request, the same fallback as every row in "No answer at all" below. Cursor gets
`{"permission":"ask"}` instead, and Antigravity `{"decision":"ask"}` (see "Cursor" and
"Antigravity" below). Why no decision rather than a deny is in "Why "Answer in chat" returns no
decision" in [panel.md](panel.md).

## Deny and Answer in Chat from the menu bar

The menu bar's pending list offers **Deny** and **Answer in Chat** for each request (see
"Answering from the menu bar" in [queue.md](queue.md)). They send exactly the outcomes above:
**Deny** is `ApprovalOutcome.deny(reason: "", interrupt: false)`, the "Deny, with or without a
reason" body with the default message for every host, and **Answer in Chat** is `.noDecision`,
empty stdout for Claude Code and Codex, `ask` for Cursor and Antigravity. The log shows
`answered from the menu: deny` or `answered from the menu: chat`, then the same `outcome: deny` or
`outcome: no decision` a panel answer leaves.

## A question submitted (Claude `AskUserQuestion` only)

Answering every tab and choosing **Submit** calls `ApprovalCore.QuestionResponse.outcome`, which
copies the original `tool_input` and adds an `answers` object keyed by each question's own text.
`questionNotes` in the [config file](../configuration.md) is `false` by default, and with it off
`QuestionView` shows no "+ Add a note" link or field, and `outcome`'s `includeNotes` is `false`, so
no note is offered or sent; the single-select answer's `preview` annotation is unaffected and is
still added exactly as below, whatever the setting. Turned on, it is exactly the behaviour below:
`QuestionView` also shows "+ Add a note", and `outcome` adds a `notes` entry to the annotation for
any question that got one. Either way, `annotations` is only added when at least one question ends
up with a non-empty annotation:

```json
{
  "hookSpecificOutput": {
    "decision": {
      "behavior": "allow",
      "updatedInput": {
        "questions": [ { "question": "Which approach?", "options": [ { "label": "A" }, { "label": "B" } ] } ],
        "answers": { "Which approach?": "A" },
        "annotations": { "Which approach?": { "notes": "keep it simple" } }
      }
    },
    "hookEventName": "PermissionRequest"
  }
}
```

`updatedPermissions` is always empty for this outcome. Codex has no `AskUserQuestion` hook at all
(its adapter never builds a `.questions` request kind), so this path only exists for Claude. Exactly
how Claude turns `answers`/`annotations` back into the next assistant turn is not documented beyond
the fact that `updatedInput` replaces the tool's input; it is not verified further here.

## A plan approved with a mode (Claude `ExitPlanMode` only)

Choosing a mode in **then: …** and pressing <kbd>Return</kbd> calls
`ApprovalCore.PlanResponse.approve(toolInput:mode:)`: the original `tool_input` goes back unchanged
as `updatedInput`, and the chosen mode is sent as a `setMode` permission update, scoped to
`"session"`:

```json
{
  "hookSpecificOutput": {
    "decision": {
      "behavior": "allow",
      "updatedInput": { "plan": "1. Do the thing\n2. Test it" },
      "updatedPermissions": [ { "type": "setMode", "mode": "auto", "destination": "session" } ]
    },
    "hookEventName": "PermissionRequest"
  }
}
```

`mode` is one of `default`, `acceptEdits` or `auto` (`ApprovalCore.PlanApprovalMode`, shown as "Ask
before edits", "Accept edits" and "Auto"), a subset of Claude Code's own `PermissionMode` type.
Codex has no `ExitPlanMode` hook, so this path is Claude-only. What Claude does with `setMode`
beyond changing the mode named in its own `PermissionMode` type is not verified further here.

## "Keep planning" feedback (Claude `ExitPlanMode` only)

<kbd>⌫</kbd> or **Keep planning** opens a feedback field. Typing feedback and pressing
<kbd>Return</kbd> calls `ApprovalCore.PlanResponse.keepPlanning`,
which is a plain deny, `interrupt: false`, with its own default message, not the panel's regular
"Denied in the approval panel." default:

```json
{
  "hookSpecificOutput": {
    "decision": {
      "behavior": "deny",
      "message": "Not approved yet. Keep planning."
    },
    "hookEventName": "PermissionRequest"
  }
}
```

Blank feedback sends that default message; typed feedback replaces it verbatim. This is Claude-only
for the same reason as plan approval: Codex has no `ExitPlanMode` hook to answer.

## A context checkpoint (Claude `UserPromptSubmit`)

A context checkpoint answers `UserPromptSubmit`, not `PermissionRequest`. The hook entry is async:
Claude Code runs it in the background and puts `hookSpecificOutput.additionalContext` in front of
Claude at its next request. `ClaudeAdapter.encode(.addContext(text))` prints exactly this, with
sorted keys, and every other host encodes `.addContext` as `nil`:

```json
{"hookSpecificOutput":{"additionalContext":"<the rendered note>","hookEventName":"UserPromptSubmit"}}
```

`ContextCheckpointChoice.outcome(for:)` maps each panel choice:

| Choice | Output |
| --- | --- |
| **Continue** | Nothing on stdout (`.noDecision`) |
| **Not this session** | Nothing on stdout (`.noDecision`); the session is also muted |
| **Compact after this step** | The JSON above with `notes.compact` rendered |
| **Hand off & start fresh** | The JSON above with `notes.handoff` rendered |

Rendering fills `{tokens}` (for example `131K`) and `{handoffFile}`. Silent mode prints the same
JSON with the note of the level that fired (`soft`, `status` or `insist`), without a panel.

Nothing on stdout, exit 0, means "nothing to add" in every other case: Esc, a click outside the
panel, a panel closed or abandoned (parent exited, session compacted meanwhile, another checkpoint
took over), a reading that is unknown, a level that did not cross, a muted session and a disabled
feature. An async hook's `systemMessage` is never shown to the user, so this feature never prints
one.

## No answer at all

Every row here ends the hook process with nothing on stdout and exit 0, the same "no decision" the
host reads as "show your usual prompt", logged with a reason so `countersign doctor` and the log
file can explain why a panel never showed or went away on its own.

| When | What the person sees | Logged as | What the host does |
| --- | --- | --- | --- |
| Paused (`countersign pause`, or the menu) | Nothing new; no panel is shown, and one already on screen closes | `paused`, if noticed before the request is even parsed; otherwise `resolved during grace: paused`, `resolved while queued: paused`, `resolved while waiting for idle: paused` or `resolved while displayed: paused`, depending on where the pause was noticed (panel closes first if one was up) | Falls back to its own prompt |
| Snoozed (quiet time active) | An already-shown panel closes; a queued one never shows until quiet time ends | `stepped aside: quiet time` while shown; a request that arrives during quiet time simply waits in `.waitingForIdle` until it ends | Falls back to its own prompt if quiet time doesn't end before the host's own timeout |
| The host-app handoff (`handoffApps`) | Nothing; checked each time its panel is about to appear, after the idle gate or right before a panel chained from a queue handoff, so it holds its place in the queue until then (see "Handing off to the asking app" in [panel.md](panel.md)) | `handoff: <bundle id> frontmost` | Falls back to its own prompt (Cursor gets `{"permission":"ask"}` and Antigravity `{"decision":"ask"}` on stdout instead of nothing here; see "Cursor" and "Antigravity" below) |
| A headless Claude session (`claude -p`, no chat to answer) | Nothing; checked once, before the grace period, for Claude only | `skipped: non-interactive session (kind=<kind>)` | Falls back to its own prompt |
| A Cursor payload in a Claude Code hook (Cursor runs `~/.claude/settings.json` hooks too) | Nothing; checked before anything else, for `--host claude` only | `ignored: a Cursor payload in a Claude Code hook` | Carries on as it would without Countersign; Cursor's own hook entries still reach Countersign |
| Answered in the chat during the grace period | Nothing; the panel is never built | `resolved during grace: registry` or `resolved during grace: transcript` | Nothing further; the chat's own answer already stands |
| Answered in the chat while queued | Nothing; ticket removed before display | `resolved while queued: registry` or `resolved while queued: transcript` | Nothing further |
| Answered in the chat while idling for a pause, or while on screen | An on-screen panel closes | `resolved while waiting for idle: <reason>` or `resolved while displayed: <reason>` | Nothing further |
| The host process is gone (parent exited) | An on-screen panel closes, if one was up | `resolved during grace/while queued/while waiting for idle/while displayed: parentExited`, detected by `getppid()` changing from the value recorded at hook start | Nothing further; there is no process left to read a decision |
| A hook timeout | Whatever was on screen is torn down when the host kills the process; a still-queued or still-idling one is torn down the same way | Nothing: the process is killed before it can log or has already logged whatever it was doing | Falls back to its own prompt (Codex: confirmed by its hook engine treating "no decision" as "proceed with the normal approval flow"; Claude Code's own behavior on a `PermissionRequest` timeout is not separately documented beyond the same "no decision" contract, so it is unverified beyond that) |
| Any other error (bad arguments, unparseable JSON, a queue write that failed) | Nothing; the hook exits before building a panel | One `EventLog` line naming the problem (`bad arguments`, `unparseable input: <message>`, `failed to enqueue: <error>`) | Falls back to its own prompt |

A request that is next in line has usually built its panel already, without showing it (see
"Warm standby and the queue handoff" in [queue.md](queue.md)). When such a request ends in one of
the `resolved while queued` rows, that panel closes unseen and `prepared panel discarded: resolved`
is logged just before the `resolved while queued` line.

A config file that fails to parse never ends a request: `ConfigFileLoader.load` logs one
`config: <problem>` line per bad key, and `Settings.resolve` falls back to that key's built-in (or
next-in-precedence) value for the rest of the run, exactly as "Bad input" in
[settings.md](settings.md) describes. The request is queued and shown normally.

The Claude-side "answered in chat" detection is `ResolutionWatcher` polling the session registry and
transcript every 250 ms (see "The race" and "Registry: see waiting first, then any transition away"
in [resolution.md](resolution.md)); Codex has no equivalent registry, and every captured Codex
fixture sends `transcript_path: null`, so the "answered in the chat" rows never fire for a Codex
request. The headless-session row is Claude-only, checked only when `options.host == .claude`.
Every other row (paused, snoozed, the handoff, the parent exiting, a hook timeout, and any other
error) applies to Claude Code and Codex the same way; how Cursor and Antigravity read them is in
"Cursor" and "Antigravity" below.

## Cursor

Cursor's hook reply is `{"permission": ...}`, not a `hookSpecificOutput` envelope
([`CursorAdapter.swift`](../../Sources/ApprovalCore/CursorAdapter.swift), matched against
`CursorAdapterTests`). The replies below were each tried by hand against Cursor 3.21.18 on
2026-09-27; the reasoning is in "The Cursor adapter" in [hosts.md](hosts.md).

| When | stdout | Logged as | What Cursor does |
| --- | --- | --- | --- |
| **Approve** | `{"permission":"allow"}` | `outcome: allow` | Runs the command or MCP tool |
| **Deny**, with a reason or the default | `{"agent_message":"<reason>","permission":"deny","user_message":"<reason>"}` | `outcome: deny` | Blocks it, shows `user_message` to the person and hands `agent_message` to the agent |
| **Deny & stop** | not offered: Cursor has no `interrupt` | — | — |
| **Answer in chat**, <kbd>Esc</kbd>, or a click outside the panel | `{"permission":"ask"}` | `outcome: no decision` | Shows its own approval prompt, even for a command it would run in its sandbox |
| Still unanswered 3540 s after the hook started, anywhere from the grace period to on screen | `{"permission":"ask"}` | `handed back: cursor timeout near` | Shows its own approval prompt; the panel, if one was up, closes and the next request takes the display |
| A shell command Cursor runs in its sandbox (`sandbox: true`) | nothing | `skipped: sandboxed command`, right after parsing, before the grace period | Carries on as it would without Countersign |
| A shell command on Cursor's allowlist, in Allowlist, Auto-review or Run Everything mode | nothing | `skipped: on Cursor's allowlist`, after `cursor: run mode …` | Runs it, as it would without Countersign |
| The host-app handoff (`handoffApps`) | `{"permission":"ask"}` | `handoff: <bundle id> frontmost` | Shows its own approval prompt, the same as "Answer in chat" |
| Every other row of "No answer at all" above (paused, unparseable input, resolved during grace or while queued, a hook timeout, any other error) | nothing | as in that table | Carries on as it would without Countersign, which under auto-run can mean running the command without asking |
| A hook timeout (an entry whose `timeout` is below the hand-back, edited by hand) | nothing; the process is killed | nothing | Runs the command: Cursor fails open on a timeout, per cursor.com/docs/hooks; `countersign doctor` warns below 600 s |

A Cursor request has no "answered in the chat" rows: `ResolutionWatcher` watches only the hook's
parent process for it, and `ChatTrackingHealth` never warns. There are no question or plan rows
either; Cursor has no hook for those. The MCP rows follow the `beforeMCPExecution` shape captured
from a remote server on 2026-09-27; a stdio server has not been captured yet.

## Antigravity

Antigravity's `PreToolUse` reply is `{"decision": ...}`
([`AntigravityAdapter.swift`](../../Sources/ApprovalCore/AntigravityAdapter.swift), matched against
`AntigravityAdapterTests`). The replies below were each tried by hand against the `agy` CLI 1.2.12
on 2026-09-27; the reasoning is in "The Antigravity adapter" in [hosts.md](hosts.md). The same hook
runs for the Antigravity app and the Antigravity IDE, which read the same hooks file.

| When | stdout | Logged as | What Antigravity does |
| --- | --- | --- | --- |
| **Approve** | `{"decision":"allow"}` | `outcome: allow` | Shows its own approval prompt anyway, so the person approves a second time there: Antigravity ignores a hook's `allow` until it fixes [google-antigravity/antigravity-cli#1053](https://github.com/google-antigravity/antigravity-cli/issues/1053). Once fixed, it runs the command or MCP tool |
| **Deny**, with a reason or the default | `{"decision":"deny","reason":"<reason>"}` | `outcome: deny` | Blocks it and shows the reason, also under `--dangerously-skip-permissions` |
| **Deny & stop** | not offered: Antigravity has no `interrupt` | — | — |
| **Answer in chat**, <kbd>Esc</kbd>, or a click outside the panel | `{"decision":"ask"}` | `outcome: no decision` | Shows its own approval prompt. Under `--dangerously-skip-permissions` it ignored even `force_ask` in the spike, so expect it to run the call there |
| Still unanswered 3540 s after the hook started, anywhere from the grace period to on screen | `{"decision":"ask"}` | `handed back: antigravity timeout near` | Shows its own approval prompt; the panel, if one was up, closes and the next request takes the display |
| Any tool call other than `run_command` and `call_mcp_tool` (reading or editing files, searches, the browser, …) | nothing | `skipped: <tool name> not asked about`, right after parsing, before the grace period | Carries on as it would without Countersign |
| The host-app handoff (`handoffApps`) | `{"decision":"ask"}` | `handoff: <bundle id> frontmost` | Shows its own approval prompt, the same as "Answer in chat" |
| Every other row of "No answer at all" above (paused, unparseable input, resolved during grace or while queued, any other error) | nothing | as in that table | Carries on with its own permission check, which asks in its default mode |
| A hook timeout (an entry whose `timeout` is below the hand-back, edited by hand) | nothing; the process is killed | nothing | Not documented and not tried; `countersign doctor` warns below 600 s |

An Antigravity request has no "answered in the chat" rows: `ResolutionWatcher` watches only the
hook's parent process for it, and `ChatTrackingHealth` never warns. There are no question or plan
rows either: Antigravity's own questions and plans are tool calls Countersign is not asked about.
