# Context checkpoints

How Countersign measures a Claude Code or Codex session's context and nudges it toward a
deliberate compaction; read it before changing anything named `Context…`.

## On by default, Claude Code and Codex

`ContextCheckpointSettings.defaultEnabled` is `true`, and `.default` carries it. Claude Code and
Codex resolve it; Cursor and Antigravity resolve to `.off`, `.default` with `enabled` false, so
they never get checkpoints. The hook is the `UserPromptSubmit` entry, plus the `PostToolUse` entry
for the stop check (see "After a tool call"), in Claude Code's settings file and, as synchronous
entries with a 30 second timeout, in Codex's `hooks.json`: setup and Update add them while
checkpoints are on for that host (`addsContextEntry`, see "The context entry follows the setting" in
[setup.md](setup.md)), and the Settings toggle adds and removes them (`ContextHookRun`).

## Measuring context

`ContextUsageReader` reads the session transcript, an undocumented file, so every failure means
"unknown": a missing, unreadable or empty file, a line that is not JSON and a row with an
unexpected shape all yield no reading rather than a crash or a guess.

The size of the context is the usage of the latest main-thread `assistant` row:
`input_tokens + cache_creation_input_tokens + cache_read_input_tokens`. Output tokens are not part
of it. A missing field counts as 0, and a field that is not an integer makes the whole row
unusable, so the reader falls back to the row before it. Rows with `isSidechain: true` belong to
subagents and are ignored, since a subagent's context is not the session's. One API response is
written as several `assistant` rows that carry the same usage, so the last one in file order is
the latest.

Transcripts grow without bound, so the reader looks only at the last 512 KiB. When the read did
not start at offset 0, the first line is cut off mid-row and is dropped. If the tail holds no
usable row at all, for example because a long run of tool output pushed the last usage row out of
it, the hook's read, `read(transcriptURL:identity:)`, falls back to reading the whole file once.
The tail-only `read(transcriptURL:)` that the watcher and the menu-bar meter call on every tick has
no fallback and returns nothing: the meter shows the session's last saved tokens, and the watcher
looks again when the file next grows. With a fallback there, a transcript of hundreds of
megabytes would be read whole on every growth.

A compaction writes a `system` row with `subtype: "compact_boundary"`, a `uuid` and
`compactMetadata.postTokens`. When that row comes after the latest main usage row, the next usage
row has not been written yet, so `postTokens` is the best available size. A `postTokens` that is
missing or not an integer is not used as a source. The `uuid` of the latest boundary is reported
as the compaction id, so a caller can tell one compaction from another.

The reading also carries `lastActivity` and `cacheLifetime`, which say whether the prompt cache is
still warm. `lastActivity` is the `timestamp` of the same row the size comes from; a missing or
unparseable timestamp (ISO 8601, with or without fractional seconds) gives `nil`. `cacheLifetime`
comes from `message.usage.cache_creation`: walking back from the end, the first main-thread
`assistant` row with a positive `ephemeral_5m_input_tokens` or `ephemeral_1h_input_tokens` decides
it. When both are positive, 5 minutes wins, because the part of the context written with the
shorter lifetime goes cold first and the next request re-reads it at full price. A row with no
positive write is skipped: a cache read refreshes the lifetime the cache was written with, so the
last write still names it. An ephemeral field that is absent counts as 0; one that is present but
not an integer makes that row unusable. Sidechain rows never count. The search never crosses a
`compact_boundary`: rows before it describe a context that no longer exists, so when no row after
the boundary wrote the cache, the lifetime is `nil`. When the boundary follows the latest usage
row, both `lastActivity` and `cacheLifetime` are `nil`: the compacted context has not been cached
yet as far as the transcript shows.

The model comes from the latest `attachment` row whose `attachment.type` is `model`, read from
`attachment.identity.modelId`. Assistant rows carry `message.model` without any suffix, so it is
only a fallback for the name and never proves the window size. The window is decided by
`ContextWindow.hasMillionTokens`, in this order:

1. A size above 200,000 tokens is 1M: only a 1M window can hold it.
2. `CLAUDE_CODE_DISABLE_1M_CONTEXT` set to `1`, `true` or `yes` (the hook reads its own
   environment) forces 200K.
3. No model id means 200K: an unknown model keeps the smaller window.
4. A `[1m]` suffix on the id means 1M.
5. A model that predates the 1M default means 200K. The list is closed: every `claude-3` and
   older id, `claude-instant`, Sonnet 4 and 4.x, Haiku 4 and 4.x, Opus 4 and Opus 4.1 to 4.6
   (also as Bedrock or Vertex ids and with a date suffix).
6. Everything else is 1M: Opus 4.7 and later, every Claude 5 model, Fable, and ids not yet known.

Claude Code 2.1.301 stopped writing `[1m]` for the models whose default window is 1M, so the marker
alone misread a live Opus 5.5 session of 1M as 200K and ran it up the 200K ladder. `[1m]` is still
written, and still needed, for Opus 4.6 and Sonnet 4.6.

Claude Code writes that identity row at session start and on a model switch only, so in a long
session it is older than the last 512 KiB and the tail cannot see it. Reading only the tail then
misjudges a 1M session as a 200K one: the assistant rows carry no `[1m]` marker, so a live 1M
session reached the `status` level at 142K. The hook path therefore uses
`ContextUsageReader.read(transcriptURL:identity:)`. When the tail holds no identity row, it scans
backwards from the start of the tail in chunks of the tail size, down to the offset the previous
scan already covered, and stops at the first identity row. A line cut by a chunk boundary is
joined with its other half, and the line cut by the start of the tail is included whole, so no
identity row is dropped or half-parsed. Malformed lines are skipped.

The result, a `ContextModelIdentity` holding the latest `modelId` and the file size the scan
covered, is cached in the session's checkpoint state as `modelIdentity`. The next prompt scans
only the bytes appended since, and when nothing new is found it keeps the cached model. A cache
whose `scannedThrough` is larger than the file means the file was replaced and is ignored. The
cache is read without the lock before the transcript is scanned: a stale value only costs a longer
scan, and the fresh identity is written back inside the existing lock. The watcher polling every
250 ms and the menu-bar meter keep the tail-only `read(transcriptURL:)`, because they need tokens
and must never start scanning a whole transcript on every tick.

The transcript is written asynchronously, so a reading can lag the session by one turn. Treat a
reading as an estimate that is at most one turn old, never as the exact state.

## Levels and re-arming

A checkpoint ladder has four levels, `soft`, `status`, `insist` and `stop`, each tied to a token
count. A ladder is two to four ascending positive token counts. The last of three or four is the
stop; two rungs are soft and status with no stop; four add insist between status and stop.
`ContextLevel.levels(forRungCount:)` is the one mapping every reader uses (the planner, the gauge,
the chip, the panel's ladder caption), so a level without a count can never be crossed.

Defaults:

| Window | soft | status | insist | stop |
| --- | --- | --- | --- | --- |
| Standard (200K) | 100,000 | 130,000 |  | 160,000 |
| 1M | 200,000 | 300,000 |  | 500,000 |

The stop exists because long sessions grow huge and then sit idle. Once the prompt cache has
expired, a `/compact` or a handoff re-reads the whole context uncached, which is slow and costly.
The stop rung makes Countersign tell Claude, without asking, to finish the task in hand, start
nothing new, keep every unfinished piece (worktrees, branches, uncommitted work, run folders) where
it is, and hand off, then wait for `/clear`, while the cache is still warm. A stop that tears state
down makes the next session research it again, which costs more than the context it saves (the
user's call, 2026-10-19). Every handoff note defers to the project's own way of handing off and
falls back to `handoffFile` when the instructions name none.
The user chose these ladders on 2026-10-19: a prompt to compact or continue at the first rung, a
prompt to compact or hand off at the second, and the stop at the third as the backstop when the
second goes unanswered; the 1M stop sits at 50% of the window, well before Claude Code's own
auto-compact at about 967K. Until 0.5.0 the defaults had four rungs (`[100000, 120000, 140000,
160000]` and `[200000, 300000, 400000, 600000]`) and three rungs meant no stop.

A `modelThresholds` entry maps a model-id prefix to a ladder. The longest matching prefix wins,
and it beats both defaults. Model ids carry a `[1m]` suffix only on models whose default window is 200K (`claude-opus-4-6[1m]`), and a
prefix may include it, so one model can have a different ladder with and without the suffix.

Each level fires at most once per session. When a reading jumps over several thresholds, only the
highest crossed level fires, and the lower levels count as fired too, so a later reading never
replays them.

A session re-arms (fired levels cleared, peak reset to the current tokens) in two cases:

- the reading carries a compaction id that differs from the stored one, because a compaction
  shrinks the context and the ladder starts over;
- the tokens fall below `rearmBelow` times the peak (default 0.6), which catches a `/clear` or a
  compaction whose id was not seen.

"Not this session" mutes the session. A muted session never fires again, even after a re-arm.

State files also count compactions (`compactions`, 0 for a fresh session or an older file). It
goes up by one each time the compaction id changes, the first id seen included, and not on the
`rearmBelow` collapse, which cannot tell a compaction from a `/clear`. The count is what
`maxCompactions` is compared with (see "Choices and what Claude receives").

State is one small JSON file per session, `<session id>.json`, in
`~/Library/Application Support/Countersign/context/`. Session ids may contain only
`A-Z`, `a-z`, `0-9` and `-`; any other id is rejected, so an id can never escape the folder.
Writes go to a temporary file in the same folder and are renamed into place. A missing, unreadable
or undecodable file means "no state"; a key missing from an older file decodes as its fresh
value. Concurrent hooks for one session serialise on `<session id>.lock` (a non-blocking `flock`,
retried for about a second, after which the hook does nothing). State files, and temporary files a
failed save left behind, are pruned once untouched for 30 days. A lock file is pruned only when its
session has no state file left and nobody holds the lock: `flock` never changes a file's
modification time, so a lock file is always older than a long session's state, and deleting a held
one would let a second hook lock a new file at the same path and plan alongside the first. The
store deletes a lock while holding it, and `ExclusiveFileLock` refuses a lock on a path that no
longer names the file it opened (see "Why the lock file is never deleted" in
[queue.md](queue.md)), so a hook that opened the old file just before it went retries on the new
one. Turning checkpoints off removes every lock the same way.

## The menu-bar meter

`ContextMeter.rows` builds the menu's "Context in live sessions" list from the per-session state
files the hook keeps. A session counts only while it is live: the Claude Code session registry
(`~/.claude/sessions/*.json`) has an entry with its id and that entry's `pid` is a running process.
Files outlive their process, so anything unknown, such as a missing entry or pid, means "not live".

Rows are built through `ContextGauge.make`, shared with the context chip on approval panels (see
"The context chip" in [panel.md](panel.md)), so the two always agree about the window.

Each live session is read fresh from its stored `transcriptPath` with `ContextUsageReader`, because
the stored `lastTokens` is only as new as the last prompt. If the transcript cannot be read, the
row falls back to `lastTokens`. The row title is `<project> · <size> tokens · <percent>%`, with
`Claude Code` when no project was stored, followed by the cache warmth (see "Cache warmth"). The
percent is the size over the window: 1M when the size is above 200,000, otherwise the window the
hook recorded in the state (`hasMillionTokenWindow`), because the app cannot see the hook's
environment and so cannot know about `CLAUDE_CODE_DISABLE_1M_CONTEXT`. Without a recorded window,
1M when the fresh reading says so or when the stored `modelID` calls for it (the hook keeps the
identity-resolved id, which the tail read alone can miss); otherwise 200K. Rows are sorted by tokens, largest first, capped
at eight. The read happens only when the menu opens; nothing polls, and the icon timer never
reads transcripts.

## Cache warmth

A session left idle loses its prompt cache after the cache's lifetime, 5 minutes or 1 hour. The
next request, a `/compact` or a handoff then re-reads the whole context at full price, so the
meter says, per session, whether the cache is still warm and for how long, and the user can act
before it goes cold.

`ContextWarmth.of(reading, now:)` compares `lastActivity + cacheLifetime` with `now`: `unknown`
when either is missing (also when the transcript could not be read, so there is no fresh
reading), `cold` from the expiry instant on, otherwise `warm(secondsLeft:)`. The title suffix is
` · warm, N min left` with the remaining time rounded up to whole minutes, ` · warm, under a
minute left` below 60 seconds, ` · cold`, or nothing for `unknown`. The value is computed when
the menu opens and is not refreshed while it is open.

## The cold-cache card

The meter only helps when the menu is open, so the menu-bar app also checks on its own: a timer of
30 seconds in `CompanionController` calls `ColdCacheCardController.tick`, which asks
`ColdCacheWarning.candidates` for sessions whose cache is about to go cold and shows a corner card
for the first one. Nothing checks while the menu-bar app is not running, and the hook path never
shows this card.

A session is a candidate when all of these hold, tested cheapest first. A fresh transcript reading
is required; `lastTokens` from the stored state is never used, because a stale size must not warn.

- Checkpoints and `coldCacheCard` are both on.
- The session is idle: its Claude Code process is alive and its registry `status` is `idle`. A
  busy or waiting session is about to refresh its cache or is in front of the user.
- The cache lifetime is 1 hour. A 5-minute cache would warn after every short pause.
- The context is at or past the first rung of the session's ladder (`ContextGauge.ladder`). A small
  context is cheap to re-read.
- The cache is warm with 600 seconds or less left (`ColdCacheWarning.leadTime`), and more than 0.
  Ten minutes is enough time to paste the handoff prompt and let the handoff finish while the cache
  is still warm.

Candidates are sorted by seconds left, then session id. `ColdCacheWarningLedger` keeps one
`lastActivity` per session and the card shows at most once per value, so one idle stretch never
warns twice; a new turn changes `lastActivity` and re-arms the session. A card that is dismissed,
actioned or closed because the session stopped being a candidate keeps its ledger entry. A card
hidden for an approval claim, or for pause or quiet time, forgets it, so it shows again once the
hold is over if the session is still due.

The card reads `N tokens go cold in M min` with the minutes rounded up, refreshed every tick, and
closes when the session stops being a candidate (it got busy, or its cache expired). Its action,
Copy handoff prompt, puts the rendered handoff note on the general pasteboard, with `{tokens}` and
`{handoffFile}` filled in as for a checkpoint, ready to paste into that session. Pause and quiet
time hold the card: nothing shows and an open card closes (logged as hidden). The card is a
`CornerCard`; see "The shared corner card" in [notice.md](notice.md).

## Choices and what Claude receives

There are four choices. **Continue** and **Not this session** send nothing; the second also
mutes the session. **Compact after this step** sends the `compact` note and **Hand off & start
fresh** sends the `handoff` note, each with `{tokens}`, `{handoffFile}` and `{compactions}` filled
in, as `additionalContext` (the exact JSON is in "A context checkpoint" in
[answers.md](answers.md)). Esc, a click outside, and a closed or abandoned panel send nothing.

Each level's panel offers its own configured list (`choices.soft`, `choices.status`,
`choices.insist`), and the first in the list is the highlighted one, so Return picks it. The
defaults are `soft` Continue, Compact, Not this session; `status` and `insist` Hand off, Compact,
Continue. **Not this session** is off the second checkpoint by default so that an answer there can
never mute the session before the stop, which would otherwise never fire (the owner's call,
2026-10-19). `ContextCheckpointChoices.offered` builds the list a prompt carries.

Past `maxCompactions` (default 5) compactions in one session, Compact is never offered: a summary
of a summary keeps too little. A list that held only Compact falls back to Hand off and Continue,
and `0` removes Compact from every panel; in `silent` mode `0` sends the `limit` note from the
first checkpoint. An empty list (the stop's) stays empty. `ContextCheckpointChoices.ordered` is the
one place that turns a set plus a highlighted choice into a list, in the order Compact, Hand off,
Continue, Not this session after the highlighted one.

`silent` mode skips the panel and sends the note of the level that fired (`soft`, `status`,
`insist` or `stop`) straight away. Once the session has been compacted `maxCompactions` times, a
silent `soft`, `status` or `insist` sends the `limit` note instead, which asks Claude to write the
handoff and stop for `/clear` and names the count through `{compactions}`.

The `stop` level never shows a panel and offers no choices. In both modes it sends the `stop` note
as `additionalContext`, and the hook logs `outcome: context note (stop)` instead of
`outcome: context note (silent, <level>)`. It never swaps in the `limit` note.

`ContextCheckpointPlanner.plan` and `ContextLadder.step` take a `levels` parameter that limits
which levels can count as crossed; everything else, including the fired set, behaves as before.
The prompt hook passes all levels.

The hook entry is async, so Claude Code runs it in the background and delivers its
`additionalContext` at Claude's next request. Its `systemMessage` would never be shown to the user,
so a checkpoint never prints one; the panel is the only thing the user sees.

Because the panel can stay open while the session moves on, `ContextCheckpointWatcher` polls and
abandons the panel, with no output, for the first of three reasons it sees:

- `parentExited`: the hook's parent process changed, so the Claude Code session is gone.
- `superseded`: the stored state for the session names another hook process as pending, so a newer
  checkpoint took over.
- `compacted`: the transcript grew and now carries a compaction id that differs from the one seen
  when the panel was planned, so the user already compacted and the question is stale.

The transcript is looked at at most once every 2 seconds, and only when its size changed since the
last look; an unreadable transcript keeps the watch going. Once a reason is found, `poll` keeps
returning it.

## The hook path

`HookRunner.run` hands a Claude Code input whose `hook_event_name` is `UserPromptSubmit` to
`ContextCheckpointRunner.run`, right after the pause check and before the `PermissionRequest`
parse. Every stop below exits 0 with empty stdout and one log line; nothing goes to stderr.

1. The input does not parse: `context: unparseable input`.
2. `contextCheckpoints.enabled` is false: `context: off`.
3. `HeadlessSessionGate` skips the session, exactly as for a permission request (see "Skipping
   non-interactive sessions" in [resolution.md](resolution.md)):
   `context: skipped, non-interactive session (kind=<kind>)`.
4. No `transcript_path`, or `ContextUsageReader` finds no reading: `context: no reading`.
5. The session id is one the store rejects: `context: unusable session id`. Otherwise state files
   older than 30 days are pruned, and under the session's lock the state is loaded (or starts
   fresh), planned, given `pendingProcessID` = this hook's pid when the plan is a panel, and saved.
   A lock not won within about a second logs `context: state busy`; a failed save logs
   `context: state not saved: <error>`.
6. The reading is logged: `context: <tokens> tokens, <level> fired` or `context: <tokens> tokens`.
7. Nothing fired: exit. In `silent` mode the note goes out as `additionalContext` and
   `outcome: context note (silent, <level>)` is logged. In `panel` mode the checkpoint goes to
   `HookRunner.showPanel` in `PanelRunMode.checkpoint`.

**Pause consumes nothing.** The pause check and the headless gate both run before the state file
is touched, so no level is marked fired: a paused Countersign was switched off on purpose, and a
level spent while it was off would be a checkpoint the person never saw. The level fires on the
first prompt after resume, if the session is still past it. Once the plan is saved, the level is
consumed: a panel that is later dismissed, paused away or abandoned does not give it back.

**No clock.** The hook entry is async, so the hook may wait on its panel as long as it takes;
nothing times it out and the prompt is never held. A checkpoint therefore has no grace period and
no timeout hand-back, and it never hands off to the asking app (`handoffApps`), since Claude Code
has no prompt of its own for it. It honours quiet time and the idle gate like any request.

**Approvals first.** An approval holds up an agent; a checkpoint holds up nothing. So a checkpoint
never takes the display while an approval ticket waits: before writing its ticket it polls every
250 ms until `TicketQueue.approvalCount(excluding: nil)` is 0, logging `waiting for approvals`
once and checking the abandon reasons on every poll (`resolved while waiting for approvals:
<reason>`). An approval that arrives later waits behind the checkpoint, as the queue is FIFO (see
"Checkpoint tickets" in [queue.md](queue.md)).

**Abandoning.** In place of `ResolutionWatcher`, the abandon reasons are `ContextCheckpointWatcher`
(its baseline is the compaction id of the reading that fired) and the pause switch. They are
logged with the same `resolved …: <reason>` lines as any request, with `parentExited`,
`superseded`, `compacted` or `paused` as the reason.

**Choices.** `sessionIdle` is true when the session's registry entry has `status` `idle` at the
moment the panel is built; a panel prepared in warm standby reads it then. A choice logs
`context choice: <choice>` (`continueWorking`, `compactAfterStep`, `handOff`, `notThisSession`);
`notThisSession` then sets `muted` in the session's state under its lock, logging
`context: mute not saved: <reason>` when that fails. The outcome is written like a permission
panel's answer, and `outcome: context <choice>` is logged, or `outcome: context dismissed` when the
panel closed with no choice (Esc or a click outside). Logs name the choice, never the note text.

### After a tool call

An autonomous run never submits a prompt, so a checkpoint checked only on `UserPromptSubmit` sails
past the stop rung. `HookRunner.run` therefore also hands a Claude Code input whose `hook_event_name`
is `PostToolUse` to `ContextCheckpointRunner.runAfterToolCall`, right after the Cursor-payload check.
The hook entry is async and is installed together with the `UserPromptSubmit` one, as one feature:
both entries or neither. Update adds the `PostToolUse` entry to a file that has only the prompt
entry; refresh never adds it.

**Only the stop rung.** The planner runs with `levels: [.stop]`, so firing it marks every lower rung
fired. The lower rungs ask for a status or a compact at a natural breakpoint, which the next prompt
gives; the stop rung is the one that must not wait. The stop note is injected in both modes, never a
panel.

**Main thread only.** A subagent's call carries `agent_id`, and a note there would steer the
subagent, which cannot hand off the session. Such a call exits quietly.

**Quiet.** This runs after every tool call, so every stop exits 0 with empty stdout and no log line,
except `context: unparseable tool call` and `context: state not saved: <error>`. The stops, in
order: paused, unparseable, a subagent's call, `contextCheckpoints.enabled` false, the headless gate
skipping the session, an unusable session id, no `transcript_path` or no reading, a lock not won.
The config warnings are not logged for this event either, so one warning does not repeat on every
tool call. When the stop rung fires, the runner writes the note and logs
`context: <tokens> tokens after a tool call, stop fired` and
`outcome: context note (stop, after a tool call)`.

**No waiting-record clear.** `WaitingRecorder.clearRecord` deletes the session's waiting record as
"working again". An async `PostToolUse` that finishes after the `Stop` hook would delete the record
that hook just wrote, so this event is routed before the clear.

**Shared with the prompt path.** The pause switch, the headless gate, the per-session lock and the
state file. The tool-call path does not prune old state files and never sets `pendingProcessID`.

**Delivery.** In a real run (Claude Code 2.1.296, `claude -p`, Haiku) an async `PostToolUse` hook
that printed `hookSpecificOutput.additionalContext` reached the model at its next request. The model
first read the note as part of the tool's result and said it would ignore it, then followed it in its
final reply. So delivery works, and a model may still distrust a note that arrives next to a tool
result.

## Codex

**Notes only.** Codex gets context checkpoints as notes and never as a panel: the user chose it,
and Codex has no way to answer this event with a panel's choice (the hook can only add context).
`ContextCheckpointSettings.resolve` therefore forces `mode` to `.silent` for Codex, and `menuBarMeter`
and `coldCacheCard` to false; `mode`, `thresholds`, `modelThresholds`, `menuBarMeter` and
`coldCacheCard` under `hosts.codex` are logged `Claude Code only, ignored` and not stored.
`enabled`, `rearmBelow`, `handoffFile` and `notes` resolve host over top over default as for
Claude Code, and the same Context checkpoints switch covers both hosts.

**A ladder of percents.** Codex reports its window (`model_context_window`) next to every usage
row, and it differs by model, so token ladders do not fit. `ContextLadder.codexPercents` is
`[50, 60, 70, 80]` and `ContextCheckpointSettings.forCodex(windowTokens:)` turns it into token
thresholds with `ContextLadder.codexThresholds(windowTokens:)`, rounded to the nearest token, for
`soft`, `status`, `insist` and `stop`. For the 258,400-token window of the captured session that is
129,200, 155,040, 180,880 and 206,720. The runner plans with that copy, `mode` `.silent`, no model
thresholds and a `ContextReading` with no model id, no million window and no compaction id, so
every fired level is an injected note.

**The reading.** `CodexUsageReader.read(rolloutURL:)` reads the rollout file named by the input's
`transcript_path`: the latest `token_count` event's `last_token_usage.input_tokens` is the context
size and `model_context_window` the window. Like every host file it is read defensively: a missing
file or an unexpected row is "no reading".

**Both events.** `HookRunner.run` hands a Codex `UserPromptSubmit` to `CodexCheckpointRunner` right
after the pause check, with all levels and the logs `context: codex off`, `context: codex
unparseable input`, `context: codex no reading`, `context: codex <tokens> tokens` and
`context: codex <tokens> tokens, <level> fired`, then `outcome: context note (codex, <level>)`. A
Codex `PostToolUse` goes there before `WaitingRecorder.clearRecord`, with the same quiet rules as
"After a tool call" and only the stop rung: `context: codex <tokens> tokens after a tool call, stop
fired` and `outcome: context note (codex, stop, after a tool call)`, and `context: unparseable codex
tool call` for an input that does not parse. No headless gate runs, since the session registry only
covers Claude Code.

**Main thread only.** Both paths skip an input that carries `agent_id`: a note there would steer a
subagent, which cannot hand off the session. The prompt path logs `context: codex subagent prompt,
skipped`; the tool-call path exits quietly. The prompt path also logs
`context: codex unusable session id`, `context: codex state busy` (a lock not won) and
`context: codex state not saved: <error>`.

**Re-arming.** Only the drop below `rearmBelow` of the session's peak re-arms the ladder. No Codex
compaction marker has been captured, so there is no compaction id to compare.

**Shared state.** The state files in `contextCheckpointsDirectory`, the per-session lock and the
30-day prune (on the prompt path only) are the same as Claude Code's; Codex and Claude session ids
do not collide.

**Delivery.** A hook that printed `{"hookSpecificOutput":{"hookEventName":"<event>",
"additionalContext":"<text>"}}` had the text inserted into the session as a `developer` message,
and the model followed it every time it was tried (Codex 0.162.0, `UserPromptSubmit` and
`PostToolUse`). The envelope is the one Claude Code takes, so `CodexAdapter.encodeContext` shares
`ClaudeAdapter.encodeContext`.
