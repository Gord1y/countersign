# Context checkpoints

How Countersign measures a Claude Code session's context and nudges it toward a deliberate
compaction; read it before changing anything named `Context…`.

## On by default, Claude Code only

`ContextCheckpointSettings.defaultEnabled` is `true`, and `.default` carries it. Every host but
Claude Code resolves to `.off`, `.default` with `enabled` false, so Codex, Cursor and Antigravity
never get checkpoints. The hook is the `UserPromptSubmit` entry in Claude Code's settings file:
setup and Update add it while checkpoints are on (`addsContextEntry`, see "The context entry
follows the setting" in [setup.md](setup.md)), and the Settings toggle adds and removes it
(`ContextHookRun`).

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

The model comes from the latest `attachment` row whose `attachment.type` is `model`, read from
`attachment.identity.modelId`. A `[1m]` suffix on that id means a 1M-token window. Assistant rows
carry `message.model` without the suffix, so it is only a fallback for the name and never proves
the window size. Since a session can hold more than 200K tokens only with the 1M window, a size
above 200,000 also counts as a 1M window when no identity says so.

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

A checkpoint ladder has three levels, `soft`, `status` and `insist`, each tied to a token count.
A ladder is exactly three ascending positive token counts.

Defaults:

| Window | soft | status | insist |
| --- | --- | --- | --- |
| Standard (200K) | 100,000 | 130,000 | 160,000 |
| 1M | 200,000 | 300,000 | 400,000 |

The 200K window gets its own ladder because Claude Code auto-compacts before a 200K session
reaches the first step of the 1M ladder (200,000), so that ladder would never fire there.

A `modelThresholds` entry maps a model-id prefix to a ladder. The longest matching prefix wins,
and it beats both defaults. Model ids may carry a `[1m]` suffix (`claude-opus-5-5[1m]`), and a
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

Each live session is read fresh from its stored `transcriptPath` with `ContextUsageReader`, because
the stored `lastTokens` is only as new as the last prompt. If the transcript cannot be read, the
row falls back to `lastTokens`. The row title is `<project> · <size> tokens`, with `Claude Code`
when no project was stored. Rows are sorted by tokens, largest first, capped at eight. The read
happens only when the menu opens; nothing polls, and the icon timer never reads transcripts.

## Choices and what Claude receives

A panel offers four choices. **Continue** and **Not this session** send nothing; the second also
mutes the session. **Compact after this step** sends the `compact` note and **Hand off & start
fresh** sends the `handoff` note, each with `{tokens}` and `{handoffFile}` filled in, as
`additionalContext` (the exact JSON is in "A context checkpoint" in [answers.md](answers.md)). The
highlighted choice follows the level: `soft` and `status` highlight **Compact after this step**,
`insist` highlights **Hand off & start fresh**. Esc, a click outside, and a closed or abandoned
panel send nothing.

`silent` mode skips the panel and sends the note of the level that fired (`soft`, `status` or
`insist`) straight away.

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
