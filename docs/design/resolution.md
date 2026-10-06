# Resolution watching

This note explains how a waiting hook notices that its request was already answered in the host's
own chat, or that the host is gone, and drops its panel instead of asking a question that no
longer matters. It covers Claude Code's session registry and transcripts, the sessions Countersign
skips, and the warning a panel shows when it cannot follow the chat. Read it when a panel stays up
after the person answered in the chat, or when you change how Claude Code sessions are read.
A context checkpoint panel is not watched here: `ContextCheckpointWatcher` abandons it instead
(see "Choices and what Claude receives" and "The hook path" in [checkpoints.md](checkpoints.md)).

## Where Claude Code's session registry lives

`AppPaths.claudeSessionsDirectory` is `$CLAUDE_CONFIG_DIR/sessions` when `CLAUDE_CONFIG_DIR` is set
and non-empty, else `~/.claude/sessions`, mirroring how `AppPaths.configDirectory` already honours
`XDG_CONFIG_HOME`. Claude Code documents `CLAUDE_CONFIG_DIR` as moving its whole `~/.claude` tree,
and the hook inherits the environment of the Claude Code process that runs it, so a person who has
relocated that tree still gets a working `ResolutionWatcher` without any countersign-specific
setting.

## Skipping non-interactive sessions

A headless `claude -p` run has nobody at a chat to answer, so a panel raised for it would only
block the run until it times out or the process is killed — there is no person to click Approve.
`HookRunner` looks up this session's registry entry the same way `ResolutionWatcher` does
(`SessionRegistry.findEntry`, a `*.json` whose `sessionId` matches, newest wins) once at hook
start, before the grace period. `HeadlessSessionGate.decide` is the pure decision: an entry whose
`kind` is a string other than `interactive` skips the request outright — logging
`skipped: non-interactive session (kind=<kind>)` and exiting 0 with no decision — unless
`includeHeadlessSessions` is set for this host. Everything else (no entry, a missing or non-string
`kind`, a read or parse failure) means "unknown," which this gate treats the same as
`interactive`: the request goes on to the grace period as usual, matching the "never a crash and
never a decision" rule for undocumented host internals.

`interactive` is the only `kind` observed in this session registry so far — every entry captured
on this machine carries it. The registry format is undocumented, so a future Claude Code version
could introduce another interactive-but-differently-named `kind`, and this gate would skip it by
mistake, silently dropping a panel that should have shown. `includeHeadlessSessions` (per host, see
[configuration.md](../configuration.md)) is the escape hatch: setting it to `true` disables the skip entirely
regardless of what `kind` says.

Codex requests are unaffected: the check runs only when `options.host == .claude`, since Codex has
no equivalent session registry to read (see [hosts.md](hosts.md)).

## The race

Claude Code runs our hook at the same time as its own chat permission dialog. Whichever answers
first wins, and a hook that loses is not killed: it keeps running until something tells it the
prompt is already gone. `ResolutionWatcher` is that something. The caller polls it every 250 ms
on the main thread and drops the panel silently the moment it reports a reason, instead of
showing a decision that no longer matters.

## When the host goes away

Every host runs the hook as its child process. `ResolutionWatcher` records the hook's parent pid
(`getppid()`) when it is created, and every poll first compares the current parent pid with it:
when the host exits, the hook is reparented, `getppid()` returns another pid, and the watcher
reports `.parentExited`. That check runs for every host. The registry and transcript checks below
run only for Claude requests.

## Registry: see waiting first, then any transition away

The session registry's `status` field only tells us the session's current state, not that it
changed because of this specific prompt. A session could start out `busy`, and `busy` alone is
not evidence of anything. Requiring `sawWaiting` first means we only fire on a transition that
plausibly corresponds to the dialog this watcher is tracking: it went to `waiting` (consistent
with the chat surfacing a prompt) and then left `waiting` (consistent with it being answered).
`waitingFor` and `statusUpdatedAt` are not used because they describe cause, not state, and
`ResolutionWatcher` only trusts direct state observation.

## Why the initial scan never fires

A transcript can already contain the exact tool call we are about to ask about, fully resolved,
from an earlier turn. If the initial scan could fire, a stale identical call finishing before we
even start polling would look like our prompt being answered. So the first read of a transcript
only establishes a baseline: which matching calls are already resolved, and which are still
pending. Only prompts that resolve after that baseline count as signal.

## Why matching compares string keys only

The hook's `tool_input` can differ from what ends up in the transcript's `input` by added
defaults (the tool call gets defaults filled in between the permission hook firing and the
assistant message being written). Comparing every field would make real matches disappear.
Comparing only the string-valued top-level keys of the original request is stable against that
kind of enrichment while still being specific enough to avoid false positives; when the request
carries no string-valued keys at all, there is nothing selective to compare, so full equality is
required instead.

## Where a subagent's tool calls are read

A subagent's tool calls are not written to the main transcript file; they go to
`<transcript_path without .jsonl>/subagents/agent-<agentID>.jsonl`. When a request carries an
`agentID`, `ResolutionWatcher` reads only that file and never the parent transcript.

## When tracking drifts

Everything above assumes the registry and the transcript keep telling the truth about this
session. When they stop, `ResolutionWatcher` doesn't crash or guess — it just stops firing, and the
panel would sit there looking exactly as confident as it does when tracking is healthy, even though
answering in the chat would no longer close it. `ChatTrackingHealth.evaluate(request:sessionsDirectory:)`
names that gap so the panel can say so instead of staying silent about it.

For a Claude request, drift is any of:

- **No registry entry** for this session, or one that can't be parsed as a JSON object. The lookup
  (`SessionRegistry.findEntry`, the same one [above](#skipping-non-interactive-sessions) uses) scans
  every `*.json` in the sessions directory by content, matching on `sessionId`; it has no filename to
  single out "this session's file," so a corrupt or truncated file for this session and no file at
  all for this session look identical from here, and both report `.noRegistryEntry`.
- **A `status` other than `idle`, `busy` or `waiting`** — including a missing `status` field —
  reported as `.unknownStatus`, since [the registry section above](#registry-see-waiting-first-then-any-transition-away)
  depends on `status` meaning one of exactly those three things.
- **The transcript file missing or unreadable**, at the same path `ResolutionWatcher` itself resolves
  (`ResolutionWatcher.resolveTranscriptURL`, including the subagent redirect from
  [hosts.md](hosts.md)'s "Walking the subagent chain"), reported as `.transcriptUnreadable`. No
  `transcript_path` at all counts as unreadable too — there's nothing to read.

This is evaluated once, the first time a panel is actually about to be shown for this hook
invocation (not at hook start): by then the grace period, the queue wait and the idle wait have
all already polled the registry many times over, so a normal startup race — the entry not written
yet in the first instant after the hook launched — has long since resolved and isn't reported as
drift. `HookRunner` logs `chat tracking: <reason>` once per hook, the first time drift is found, and
carries the same (possibly `nil`) result into every `PanelController` shown for this ticket even
across a step-aside or a snooze, rather than re-evaluating and re-logging on every re-show.

**Codex** has no source to check at all today: `ResolutionWatcher` never reads a registry for Codex
(there isn't one), and every Codex `PermissionRequest` capture in this repo's fixtures carries
`transcript_path: null` — the field exists in the shape Codex sends, but nothing has ever been
observed to populate it. Inventing a check against an unconfirmed payload shape would violate this
project's "never invent a payload shape" rule for host internals, so
`ChatTrackingHealth.evaluate` returns `nil` unconditionally for `host == .codex`, and no warning
ever appears on a Codex panel. If a future Codex version is captured sending a real transcript
path, `ChatTrackingHealth.evaluateTranscript` already applies the exact same "missing or unreadable"
rule Claude gets — host-independent — and only needs to be called from `evaluate` for Codex once a
real capture confirms the shape.

**In the panel**, the header shows a yellow `exclamationmark.triangle.fill` right after the project
name only when `chatTrackingDrift` is non-nil; hovering it opens a `.hoverCard` reading
"Countersign can't follow this chat, so answering there won't close this panel. Answer here, or
press Esc." — the same message regardless of which of the three reasons fired, since none of them
change what the person should do about it.

## Known limits

- Two prompts answered in the same session share one `status` value in the registry, so the
  registry signal cannot distinguish which prompt was answered if two are outstanding at once.
- The transcript lags: nothing is written between the dialog being answered and the tool call
  actually finishing, so `.transcript` can arrive noticeably after the real answer, and never
  before the registry would have already fired for Claude's own dialog.
- `*.key` files in the sessions directory are never opened. Only entries whose extension is
  exactly `json` are read, both when scanning for the registry entry and when re-validating a
  cached one.
