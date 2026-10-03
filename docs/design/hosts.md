# Host adapters

This note explains how Countersign talks to each coding agent it serves, Claude Code, Codex, Cursor
and Antigravity: what each one sends, how it is shown, what each answer prints back, and what each
host does with an empty reply or a timeout. Read it when you add or change a host, when a host
changes its payload, or when an agent does something unexpected after an answer.

## Why `JSONValue` keeps `int` and `double` apart

Claude and Codex both send JSON numbers, and a naive decode into `Double` would turn `1` into
`1.0` and change what gets echoed back in `updatedInput`. Echoed input (`updatedInput` for
AskUserQuestion/ExitPlanMode, `updatedPermissions` entries) must carry numbers exactly as
received, so `JSONValue` decodes in the order null, bool, Int64, Double, String, array, object,
and keeps whichever one round-trips exactly.

## Why the Codex adapter drops fields

Codex's `PermissionRequest` output only supports `behavior: allow` and `behavior: deny` with a
`message`. `updatedInput`, `updatedPermissions` and `interrupt` are Claude-only extensions the
Codex hook runtime does not read, so `CodexAdapter.encode` never emits them, regardless of what
the outcome carries.

## How a Codex argv command is shown

Codex sends `Bash` commands either as a single string or as an argv array (`execve`-style,
already split). A plain string is shown as-is. A three-element `[shell, flag, script]` array is
the common `bash -lc "..."` shape, so its script string is shown directly instead of a quoted
argv dump. Any other array is rejoined into a single displayable line, quoting only the elements
that need it (empty, or containing whitespace or shell metacharacters) so short flags stay
readable.

## How Codex records hook trust

Codex runs a hook from `$CODEX_HOME/hooks.json` (`~/.codex` by default) only after the person has
trusted it, and keeps that trust in `$CODEX_HOME/config.toml`, one table per hook. These are the
last two lines of a real 101-line `config.toml`, path and hash masked:

```toml
[hooks.state."/Users/<name>/.codex/hooks.json:permission_request:0:0"]
trusted_hash = "sha256:<64 lowercase hex>"
```

The fixture `Tests/ApprovalCoreTests/Fixtures/codex-config-hook-trust.toml` keeps exactly that
shape, with a made-up path and hash. From the openai/codex source:

- The key is `<absolute hooks.json path>:<event label>:<group index>:<handler index>` (`hook_key` in
  `codex-rs/hooks/src/lib.rs`). For `PermissionRequest` the label is `permission_request`, and the
  indexes are zero-based positions in `hooks.PermissionRequest[group].hooks[handler]`.
- `trusted_hash` is `hook_hash` in `codex-rs/hooks/src/engine/discovery.rs`: a SHA-256 over Codex's
  normalized TOML encoding of the entry (`command`, `command_windows`, `timeout`, `async`,
  `statusMessage`, `additionalContextLimit`, `type` and the group's `matcher`), not over the file's
  bytes. A hook counts as trusted only when the stored hash equals the hash of its current entry
  (`hook_trust_status`, same file). The hash follows the entry's content, not its position, so the
  value Codex stores when the person trusts an entry is the same under any key.
- Countersign never recomputes that hash. The normalized encoding is Codex's internal detail, and a
  copy of it would break without notice the day Codex changes it. Countersign only compares values
  Codex stored; how it turns those into a verdict is in "The Codex hook trust record" in
  [setup.md](setup.md).
- Only the terminal `/hooks` writes `trusted_hash`. The Codex desktop app shares `~/.codex` but
  cannot write it (openai/codex#47283). A running session does not reload `hooks.json` on its own
  (openai/codex#17636, open), but trusting in `/hooks` refreshes sessions already open
  (openai/codex#19882).

`CodexTrustTable` reads `config.toml` without a TOML library. It follows TOML's statements, so text
inside strings, multi-line strings, arrays and inline tables is never taken for a table header, and
from tables of exactly the form `[hooks.state."<key>"]` it takes only `trusted_hash = "<value>"`.
Everything unrelated to `hooks.state` is ignored, including other keys inside those tables. Any
other form of hook state means "cannot tell": an inline `state = {…}` under `[hooks]`, dotted keys
such as `hooks.state."…".trusted_hash = …` or keys under `[hooks.state]`, an array of tables
`[[hooks.state…]]`, a key in single quotes or without quotes, a table nested under a hook's table, a
`trusted_hash` that is not a one-line double-quoted string, and a table or `trusted_hash` given
twice. So do a file that is not UTF-8 and one that is not valid TOML anywhere, since Codex refuses
to load such a file too. A missing file is "cannot tell" for the verdict; for the record `SetupRun`
writes, it means no hash was stored yet, while a file that cannot be read or understood leaves the
record's hash at write unknown (`CodexHashAtWrite.unread`).

## Stop hooks

Waiting-agent notices hook each host's end-of-turn event. No payload of the Codex, Cursor and
Antigravity events has been captured yet, so none is parsed and each entry's shape follows that
host's existing Countersign entry; the unconfirmed details are named constants (see "The waiting
entries of Codex, Cursor and Antigravity" in [setup.md](setup.md)). Every entry runs
`<exe> hook --host <host> --event waiting` with a 30 second timeout and no `async`, which only
Claude Code has.

- Claude Code: `hooks.Stop` in `settings.json`, `async`.
- Codex: `hooks.Stop` in `$CODEX_HOME/hooks.json`, in one group without a matcher. Codex runs it
  only after the person trusts it with `/hooks` in a Codex session, recorded under
  `<hooks.json path>:stop:<group>:<hook>` in `config.toml` (the label `stop` is unconfirmed), so
  the entry has its own trust record and Doctor line.
- Cursor: `hooks.stop` in `~/.cursor/hooks.json`, outside `CursorAdapter.events`.
- Antigravity: the named hook `countersign-waiting` in `~/.gemini/config/hooks.json`, with `Stop`
  as its one event and the `*` matcher (unconfirmed for `Stop`), beside the `countersign` hook.

## The deny message default

A denial with no reason, or one that is only whitespace, is silently unhelpful on the other end
of the hook. `ApprovalOutcome.deny(reason:interrupt:)` trims the reason and substitutes
`ApprovalOutcome.defaultDenyMessage` when nothing meaningful is left, so a bare "deny" click
always produces a legible message.

## Walking the subagent chain

Claude Code writes a subagent's own actions to
`<transcript_path without .jsonl>/subagents/agent-<agentID>.jsonl`, next to
`agent-<agentID>.meta.json`, which holds `agentType`, `description` (the task name),
`spawnDepth`, `toolUseId` and `model`. `toolUseId` is the id of the `Agent` tool call that spawned
this agent, and that call sits in the *parent's* transcript: the main session's
`<session>.jsonl` for a depth-1 agent, or another `agent-<parentID>.jsonl` for anything deeper.
Both files are undocumented, unversioned, and can drift without notice, so
`ApprovalCore.SubagentChainReader.chain(transcriptPath:agentID:)` reads them defensively: it walks
from the requesting agent up to the depth-1 root, and any missing file, missing field, or parse
failure anywhere along the way returns `nil` for the whole chain rather than a partial one, so the
header can fall back to the plain `subagent · <agentType>` chip.

The walk is meta-first. Checked on Claude Code 2.1.278 against 933 local metas: `parentAgentId` is
a top-level key of `agent-<id>.meta.json` only (never in a `.jsonl` row), it is present exactly
when `spawnDepth` is 2 or more (176 at depth 2, 4 at depth 3), and absent on all 753 depth-1
agents, whose parent is the main session. So each hop reads one small meta file: a
`parentAgentId` names the next hop, a meta without one and with `spawnDepth` 1 ends the chain at
the main session, and neither opens a transcript. The cost is one meta read per level instead of a
full read of the main transcript plus every sibling `agent-*.jsonl` per level.

A meta with no `parentAgentId` whose `spawnDepth` is missing or above 1 (an older Claude Code, or
an inconsistent file) falls back to the transcript walk for that hop: each step reads the current
agent's `toolUseId` and finds which transcript contains it: the main transcript first (that agent
is the root, and the walk stops), otherwise each `agent-*.jsonl` in the same `subagents` directory
except the current agent's own file. The match is a byte search for the id string, not a JSON parse of
the whole transcript — these files can be large, and the reader only needs to know which file the
id appears in, not what else is on that line. A `Set` of visited agent ids guards against a cycle,
and the walk gives up after 10 levels regardless, so a malformed or looping chain degrades to the
fallback chip instead of hanging or growing without bound.

## The Claude `UserPromptSubmit` input

The same command, `countersign hook --host claude`, serves `PermissionRequest` and
`UserPromptSubmit`. The hook reads `hook_event_name` first with `ClaudeAdapter.eventName(of:)`,
which returns the top-level string or `nil` for anything that is not a JSON object with one, and
only then parses: `ClaudeAdapter.parse` keeps rejecting any event but `PermissionRequest`, and
`ClaudeAdapter.parseUserPromptSubmit` rejects any event but `UserPromptSubmit`.

A `UserPromptSubmit` input carries exactly `cwd`, `hook_event_name`, `permission_mode`, `prompt`,
`prompt_id`, `scratchpad_dir`, `session_id` and `transcript_path` (a real capture,
`claude-user-prompt-submit.json`). `parseUserPromptSubmit` requires `session_id`, `cwd` and the
event name, reads `transcript_path` and `permission_mode` when present, and ignores `prompt`, so
the text a person typed never leaves the parser. It returns a `ContextCheckpointInput`, which
`ApprovalRequest.contextCheckpoint(_:prompt:)` turns into a request with tool name
`Context checkpoint` and an empty tool input, so the panel and the queue treat it like any other
request.

## Cursor payloads in Claude Code hooks

Cursor also runs the hooks in `~/.claude/settings.json`, through its Claude Code compatibility, so
a Cursor prompt or end of turn reaches `countersign hook --host claude` with a Cursor payload: no
`cwd`, Cursor's own fields, and an event name that is not Claude Code's. Before anything else, the
hook checks the input with `ClaudeAdapter.isCursorPayload(_:)`: a JSON object with a
`cursor_version` key (every captured Cursor payload has one), or whose `hook_event_name` starts
with a lowercase letter (Claude Code's event names start with a capital, Cursor's with a lowercase
letter). Such an input exits 0 with empty stdout and one log line, `ignored: a Cursor payload in a
Claude Code hook`. Cursor's own entries in `~/.cursor/hooks.json` reach Countersign as
`--host cursor`, so nothing is lost; before the check, every Cursor turn logged `unparseable input:
missing cwd` and `waiting: unparseable input`.

## The waiting record's envelope

A waiting entry (`hook --event waiting`, see [notice.md](notice.md)) reads only the envelope each
host sends with every hook, never a Stop-specific field: only Claude Code's Stop payload is captured
(`claude-stop.json`), and fields such as `stop_hook_active` wait for the other hosts' captures.
`WaitingEnvelope.parse(_:host:)` reads, treating an empty string as missing:

| Host | Session id | Project path | Transcript |
| --- | --- | --- | --- |
| Claude Code | `session_id` | `cwd` | `transcript_path` |
| Codex | `session_id` | `cwd` | `transcript_path` (`null` in `codex-bash.json`) |
| Cursor | `conversation_id`, else `session_id` | `workspace_roots[0]`, else `cwd` | `transcript_path` |
| Antigravity | `conversationId` | `workspacePaths[0]` | `transcriptPath` |

No session id or no project path means no record. The project name is the path's last component,
as `ApprovalRequest.projectName` derives it.

Codex keeps each session's transcript at
`$CODEX_HOME/sessions/YYYY/MM/DD/rollout-<local time>-<session id>.jsonl` (day folder = start day),
which `CodexRolloutLocator` finds when the payload's `transcript_path` is `null`; see "Codex rollout
lookup" in [notice.md](notice.md).

## How suggestion labels are built

`permission_suggestions` entries are structured data meant for a settings file, not for display.
The label rules turn each entry into one short, readable caption: rules are joined by name and
content, the behavior verb defaults to "Always allow", and the destination becomes a trailing
parenthetical that says where the rule will be written. The panel's Approve dropdown shows
`addRules` and `addDirectories` entries as two lines instead, the exact rule and where it is
saved, from `PermissionSuggestionText` (see "The Approve split button" in [panel.md](panel.md)),
and keeps the label for every other entry type.

## Detecting the host app from the process tree

No host's payload, Claude Code's, Codex's, Cursor's or Antigravity's, says which app the person is
actually sitting in front of — a terminal, an editor, whatever launched the CLI. `hook` only knows its own
process. `ApprovalCore.ProcessAncestry.chain(from:)` walks parent PIDs upward from `getppid()`
(`hook`'s own parent) with repeated `sysctl(KERN_PROC_PID)` calls — the same call `ProcessLiveness`
already makes for ticket liveness — collecting each ancestor's pid, bounded to 64 steps and
cycle-safe (a `Set` of visited pids stops a malformed or looping chain from spinning forever), until
it reaches pid 1 (`launchd`) or a lookup fails. `Sources/countersign/HostApp.resolve()` then walks
that chain looking for the first ancestor `NSRunningApplication(processIdentifier:)` exists for with
`activationPolicy == .regular` — a real, Dock-visible application, as opposed to a background agent,
a shell, or a helper process with no policy at all — and that is "the host app": the Terminal, iTerm,
VS Code, Cursor or similar window the person is actually working in for this request. `hook` logs
`host app: <localized name> (<bundle id>)` once it resolves this, or `host app: unknown` when no
ancestor up to `launchd` qualifies.

### Why the handoff rule is per-app

A handoff check that only asks "is the frontmost app one of these bundle IDs," with no idea where
the request itself came from, is wrong whenever more than one host is running at once: a Claude
Code session left running in a terminal must not be handed off to whatever chat surface the person
happens to be looking at right now just because Codex's own app is frontmost — that hands the panel
to a chat that was never asked the question. So the rule also requires that the frontmost app *is*
the host app this specific request came from, compared by pid
(`NSRunningApplication.processIdentifier`, not bundle identifier, so a second instance of the same
app doesn't count as a match): hand off only when the frontmost app's bundle id is in
`handoffApps` **and** either the host app is unknown (the bundle-ID-only check, kept as a
permissive fallback when the process tree can't be walked) or the frontmost app and the host app
are the exact same running process.

## The Cursor adapter

Cursor has no `PermissionRequest` event. Its hooks live in `~/.cursor/hooks.json`, one array of
`{"command", "timeout"}` entries per event, and a hook answers a permission event with
`{"permission": "allow" | "deny" | "ask"}`. Countersign registers two of them:
`beforeShellExecution` and `beforeMCPExecution` (`CursorAdapter.events`). Everything below was
checked against Cursor 3.21.18 on 2026-09-27 by a spike that logged every hook call and tried each
reply by hand; where a fact comes from cursor.com/docs/hooks instead, it says so.

### What Cursor sends

A `beforeShellExecution` call carries `conversation_id`, `generation_id`, `model`, `command`,
`cwd`, `sandbox`, `session_id` (equal to `conversation_id`), `hook_event_name`, `cursor_version`,
`workspace_roots`, `user_email` and `transcript_path`. `cwd` was an empty string in every capture,
so the working directory, and with it the project name in the header, is `workspace_roots[0]`;
`cwd` is used only when there is no workspace root. `transcript_path` is `null` on the first call
of a chat and afterwards points at `~/.cursor/projects/<slug>/agent-transcripts/<id>/<id>.jsonl`.
The session is `session_id`, or `conversation_id` when that is missing.

The command goes to the same command view as a Claude `Bash` request, with the tool name `Shell`,
which is what Cursor itself calls the tool in its `preToolUse` calls. An MCP call goes to the MCP
view: the server is `mcp_server_name`, the tool `tool_name`, the arguments `tool_input`. The server
falls back to `mcp_server_url`, `url` or `command`, in that order, when a call has no name.

Cursor also called `preToolUse`, `beforeReadFile`, `postToolUse`, `afterShellExecution`,
`sessionStart` and `stop` during the spike. Countersign registers none of them. Cursor's agent did
not run the Claude Code hook entry in `~/.claude/settings.json` either, so a Claude Code setup
never answers for Cursor.

### The captured MCP call

No MCP server was configured during the spike, so `beforeMCPExecution` went uncaptured there. A
real call was logged afterwards: Cursor 3.21.18, 2026-09-27, a remote server (context7) called
through `resolve-library-id`. Its shape is the common fields of every captured call plus
`tool_name`, `tool_input`, `mcp_server_name`, `mcp_server_url` and `url`; `tool_input` arrives as a
string of JSON, not an object, matching cursor.com/docs/hooks, so the adapter accepts both: a
string that parses as JSON becomes the arguments, an object is used as it is, and any other string
is shown as the raw string. `cursor-mcp-url.json` is built from that capture, sanitized the same
way as the other fixtures. A stdio server (`command` instead of `mcp_server_url`/`url`) has not
been captured yet; the adapter's fallback to `command` for the server name is covered by an inline
test in `CursorAdapterTests` instead of a fixture.

### Only unsandboxed commands

Cursor runs most agent commands in its own sandbox; `sandbox: false` marks a command it runs
outside it, for example one that needs the network. Countersign acts only on those, and on every
MCP call. A sandboxed shell call sets `ApprovalRequest.runsInSandbox`, and the hook exits right
after parsing, before the grace period and the queue, with empty stdout and `skipped: sandboxed
command` in the log, so Cursor carries on exactly as it would without Countersign. A call whose
`sandbox` is missing or not a boolean counts as outside the sandbox and gets a panel: showing a
panel it did not need is the cheaper mistake.

### What each answer prints

| Outcome | stdout |
| --- | --- |
| Approve | `{"permission":"allow"}` |
| Deny | `{"agent_message":"<reason>","permission":"deny","user_message":"<reason>"}` |
| Answer in chat (`.noDecision` from the panel) | `{"permission":"ask"}` |
| Any failure | nothing |

The reason is the typed one, or `ApprovalOutcome.defaultDenyMessage`, the same default the other
hosts get. Cursor shows `user_message` to the person and hands `agent_message` to the agent, so both
carry the same text. Cursor has nothing like `updatedInput`, `updatedPermissions` or `interrupt`,
so `CursorAdapter.encode` drops them, and the panel hides **Deny & stop** (`supportsInterrupt` is
false).

`.noDecision` encodes to `ask` for Cursor, where the other hosts print nothing, because empty
stdout means something else to Cursor. The spike showed that an empty reply makes Cursor carry on
with its normal flow, which under auto-run runs the command without asking anybody, so "Answer in
chat" would quietly approve it. `ask` makes Cursor show its own approval prompt, even for a command
it would run in the sandbox, which is what "Answer in chat" means for the other hosts. A failure
still prints nothing: the rule that a failure is never an answer outranks the difference.

The frontmost-app handoff ("Why the handoff rule is per-app" above) is the same case: for Claude
Code and Codex it is a silent exit like any other, but `Host.handoffOutcome` is `.noDecision` for
Cursor too, so `hook` still logs `handoff: <bundle id> frontmost` and then writes
`{"permission":"ask"}` before exiting, rather than leaving stdout empty. Pausing Countersign stays
silent for every host, including Cursor, because a pause means behaving as if Countersign weren't
installed; the handoff never means that, so it is the one silent-for-the-other-hosts exit where
Cursor gets an answer instead.

### Handing back before Cursor's timeout

Cursor documents that a hook that times out fails open: the command runs. The spike confirmed that
it honours a long `timeout` (a hook that waited 45 s under `timeout: 3600` was waited for), so setup
writes 3600 seconds, as for the other hosts. A panel still unanswered after an hour would then let
the command through without a word from anybody, so the Cursor hook hands back first: 60 seconds
(`TimeoutHandBack.marginSeconds`) before the entry timeout
(`TimeoutHandBack.entryTimeoutSeconds`, which is `HookSetup.timeoutSeconds`), that is 3540
seconds after the hook process started, it prints `{"permission":"ask"}`, logs `handed back: cursor
timeout near` (`TimeoutHandBack.logLine(for:)`), and exits 0, whether the request was in the grace
period, queued, waiting for a pause or on screen. That is not a decision: Cursor shows its own prompt, as it does for "Answer in
chat".

The clock is `ContinuousClock`, which keeps counting while the Mac sleeps. If Cursor's own timer
pauses during sleep, the hand-back comes early rather than late. The payload does not carry the
entry's timeout, so an entry edited by hand to a shorter one is not noticed; `countersign doctor`
warns about any timeout below 600 seconds. Claude Code and Codex fall back to their own prompt on a
timeout, so they need no hand-back (`TimeoutHandBack.deadline(for:)` is `nil` for them). Antigravity
hands back on the same deadline (see "Handing back before Antigravity's timeout" below).

Setup never writes Cursor's `failClosed` option. With it, a hook that produces no output blocks the
action, which would turn every "no decision" path, from a paused Countersign to a sandboxed skip,
into a denial.

### No chat tracking

Cursor has no documented session registry, and its transcripts are an undocumented internal, so
`ResolutionWatcher` watches only the hook's parent process for a Cursor request and
`ChatTrackingHealth` never warns about drift, as for Codex. When Cursor stops waiting and kills the
hook process, the panel goes with it.

### The host app

Cursor's app, `com.todesktop.230313mzl4w4u92` in the log's `host app:` line, starts the hook from
its extension host, so the process-tree walk above finds it like any other host app. `handoffApps`
works for Cursor through that detection; there is no Cursor entry in the default list.

### Reading Cursor's run mode and allowlist

The hook uses Cursor's run mode and command allowlist to decide whether a request needs the panel.
Both come from places Cursor does not promise to keep stable, so every read is defensive and every
failure means "unknown", never a decision.

The run mode and the in-app allowlist live in Cursor's settings database,
`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`: a SQLite file in WAL mode
with one table, `ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)`. The row we read is
the key
`src.vs.platform.reactivestorage.browser.reactiveStorageServiceImpl.persistentStorage.applicationUser`,
whose value is JSON text. This is an undocumented internal. `CursorStateDatabase` opens the file
with `SQLITE_OPEN_READONLY`, which works while Cursor has it open, waits at most 200 ms on a busy
lock, and returns `nil` for a missing file, a file that is not a database, a missing table or a
missing row. Nothing is written to stderr.

Inside that JSON, `composerState.modes4` is a list of modes, and the entry with id `agent` decides
the run mode. `CursorRunMode.resolve` maps it in one function:

1. The `agent` entry is missing, or `autoRun` is not a bool: unknown.
2. `autoRun` is false: asks every time, Cursor's deprecated "Ask Every Time".
3. `fullAutoRun` or `smartModeAutoRun` is missing or not a bool: unknown.
4. `fullAutoRun` is true, or `composerState.yoloEnableRunEverything` is true: run everything.
5. `smartModeAutoRun` is true: auto-review.
6. Otherwise: allowlist.

This mapping was inferred from one machine's database and the documented run modes (Auto-review,
Allowlist, Run Everything), so the fixture is a trimmed copy of that one value. Keeping it in one
function makes a correction a one-line change.

`composerState.yoloCommandAllowlist` is the in-app command allowlist: an array of strings, or
unknown when it is absent or holds anything else.

Cursor also reads `terminalAllowlist`, an array of strings, from `~/.cursor/permissions.json` (per
user) and `<workspace>/.cursor/permissions.json` (per repo). When both files exist Cursor
concatenates the arrays, and once either file defines the field the in-app list is not used.
`CursorCommandAllowlist.resolve` follows that: the defined arrays are joined in order, user file
first, and only when neither file defines the field does the in-app list apply. An empty array is a
defined, empty list. Cursor documents the file as `jsonc`, so it is decoded with
`allowsJSON5` to accept comments and trailing commas. A missing file, an unparseable file, a root
that is not an object, an absent key, a value that is not an array, or one non-string element all
count as "the file does not define the field". With no list from any source the allowlist is
unknown, and the hook shows the panel as it does today.

The database is read through `import SQLite3`, the system library in the macOS SDK, so it adds no
dependency. An in-process read takes about a millisecond; spawning `sqlite3` for every hook would
cost a process launch each time, on a path that runs for every Cursor request.

## The Antigravity adapter

Google Antigravity has no `PermissionRequest` event either. Its hooks live in one global file,
`~/.gemini/config/hooks.json`, which the `agy` CLI, the Antigravity app and the Antigravity IDE all
read, again on every message. The file holds named hooks at the top level, each
`{"enabled"?: bool, "<Event>": [{"matcher", "hooks": [{"type": "command", "command", "timeout"}]}]}`.
Countersign adds one named hook, `countersign`, with a single `PreToolUse` group matching `*`
(`AntigravityHookSetup`). Everything below was checked against `agy` 1.2.12 on 2026-09-27 by a
spike that logged every hook call and tried each reply by hand; the app and the IDE read the same
file but were not exercised.

### What Antigravity sends

A `PreToolUse` call carries `conversationId`, `workspacePaths` (an array), `transcriptPath`,
`artifactDirectoryPath`, `modelName`, `stepIdx` and `toolCall: {name, args}`, and no event name.
`transcriptPath` points at `<data>/brain/<id>/.system_generated/logs/transcript_full.jsonl`, where
`<data>` is `~/.gemini/antigravity-cli` for the CLI, `~/.gemini/antigravity` for the app and
`~/.gemini/antigravity-ide` for the IDE; those three directories are also how setup and doctor tell
that Antigravity is installed. Every tool's `args` carry `toolAction` and `toolSummary`, two short
lines the model writes about the call ("Running the tests", "Run the tests").

- `run_command` has `CommandLine`, `Cwd` and `WaitMsBeforeAsync` (5000 or 10000 in the captures).
  It goes to the same command view as a Claude `Bash` request, under the tool name `run_command`:
  the command is `CommandLine`, and `toolSummary` is the description line under the title, where
  Claude's own `Bash` description goes. `toolAction` is not shown. The request's tool input is
  `args` as received, `Cwd` included.
- `call_mcp_tool` has `ServerName`, `ToolName` and `Arguments`, the MCP tool's own arguments. It
  goes to the MCP view: the server is `ServerName`, the tool and the request's tool name are
  `ToolName`, and the arguments, which are also the request's tool input, are `Arguments`. Before an
  MCP call, `agy` reads the tool's schema with an ordinary `view_file` of
  `<data>/mcp/<server>/<tool>.json`, which is skipped like any other tool below.

The session is `conversationId`. The working directory, and with it the project name in the header,
is `workspacePaths[0]`; `Cwd` is used only when there is no workspace path. A command run in a
subdirectory still names its workspace in the header, as Cursor's does, and its `Cwd` stays in the
tool input.

### Only commands and MCP tools

`PreToolUse` fires for every tool call, reading a file as much as running a command, and it fires
before Antigravity's own permission check. A panel for every file read would make Antigravity
unusable, so Countersign answers only for the two kinds of call that act on the world outside the
editor: `AntigravityAdapter.askedTools`, which is `run_command` and `call_mcp_tool`, matched
exactly. Any other call still parses, with `ApprovalRequest.isAskedAbout` false, and the hook exits
right after parsing, before the grace period and the queue, with empty stdout and `skipped: <tool
name> not asked about` in the log. Empty stdout hands the call to Antigravity's own permission check
unchanged, so an edit or a read is asked about, or not, exactly as Antigravity's own settings say.
A tool Antigravity adds later is skipped the same way until it is added here: skipping never runs
anything Antigravity would not have run without Countersign.

### What each answer prints

| Outcome | stdout |
| --- | --- |
| Approve | `{"decision":"allow"}` |
| Deny | `{"decision":"deny","reason":"<reason>"}` |
| Answer in chat (`.noDecision` from the panel) | `{"decision":"ask"}` |
| Any failure | nothing |

The spike tried each: empty stdout lets Antigravity carry on with its own flow, which asks in its
default mode; `deny` blocks the call and shows the reason; `ask` and `force_ask` both make it show
its own prompt; `allow` does not approve (see "Approve is not enough yet" below). Under
`--dangerously-skip-permissions`, `force_ask` was ignored and `deny` still blocked. The reason is the
typed one or `ApprovalOutcome.defaultDenyMessage`. Antigravity has nothing like `updatedInput`,
`updatedPermissions` or `interrupt`, so `AntigravityAdapter.encode` drops them and the panel hides
**Deny & stop**. The other replies Antigravity documents, `deny_unless_prior_grant`,
`permissionOverrides` and the undocumented `overwrite`, are never sent.

`.noDecision` encodes to `ask`, as for Cursor and for the same reason: empty stdout hands the call to
Antigravity's own check, which under a permissive setting runs it without asking anybody, so
"Answer in chat" would quietly approve it. `Host.handoffOutcome` is `.noDecision` for Antigravity
too, so the frontmost-app handoff also writes `{"decision":"ask"}`. Pausing stays silent, as for
every host. A failure still prints nothing.

### Approve is not enough yet

Antigravity ignores a hook's `allow` for a call it would otherwise ask about: the spike's `allow`
was followed by Antigravity's own prompt, and adding `permissionOverrides` did not change that. This
is [google-antigravity/antigravity-cli#1053](https://github.com/google-antigravity/antigravity-cli/issues/1053),
open upstream. Antigravity still ships as a normal host, wired by setup like the others, because
everything else works: the panel queues and waits like any other, **Deny** blocks, and "Answer in
chat" hands over. Until the bug is fixed, **Approve** is followed by Antigravity's own prompt, so
the person approves twice. The README, [limitations.md](../limitations.md),
[agents.md](../agents.md), [troubleshooting.md](../troubleshooting.md), the Antigravity table in
[answers.md](answers.md) and an `info` line in `countersign doctor` and the Agents rows, both built
from `AgentFollowUps.antigravityGoodToKnow` (see "Follow-up lines" in [setup.md](setup.md)), say so.

When Google fixes it, nothing in Countersign has to change for Approve to be enough: the adapter
already sends `{"decision":"allow"}`. What changes then is the wording: every page named above,
the Approve row of the Antigravity table in [answers.md](answers.md),
`AgentFollowUps.antigravityGoodToKnow` and this section, checked against the fixed Antigravity
version.

### The strict hooks file

Antigravity validates the whole hooks file and, when any entry in it is invalid, rejects all of it
and runs none of its hooks. The spike saw this: a `Stop` entry written as `{"hooks": [...]}` instead
of a flat list of handlers put `Failed to parse hooks file …: invalid hook "…": command hook must
specify 'command'` in `~/.gemini/antigravity-cli/cli.log`, and no hook ran, the valid ones included.
So setup writes exactly one shape, and recognises our entry only in that shape (see "How our entry
is recognised" in [setup.md](setup.md)): a `countersign` named hook in any other shape is
replaced whole rather than patched, and `countersign doctor` warns about one, and adds the
whole-file note to a file that does not parse. Setup cannot know every rule Antigravity checks, so
it never touches, and doctor never judges, the other named hooks: an invalid neighbour silently
disables ours too, and `cli.log` is where that shows.

### Handing back before Antigravity's timeout

What Antigravity does when a hook times out, and whether it honours a long `timeout` (its default is
30 seconds), is undocumented and was not tried. It is treated like Cursor's: setup writes 3600
seconds, and 60 seconds before that, 3540 seconds after the hook started, the hook prints
`{"decision":"ask"}`, logs `handed back: antigravity timeout near` and exits 0
(`TimeoutHandBack.deadline(for:)`, the same constants as "Handing back before Cursor's timeout"
above). If Antigravity fails open on a timeout, that keeps a forgotten panel from approving by
silence; if it fails closed, it costs nothing.

### No chat tracking, no trust step

Antigravity has no session registry, and its transcript format is undocumented, so
`ResolutionWatcher` watches only the hook's parent process for an Antigravity request and
`ChatTrackingHealth` never warns about drift, as for Codex and Cursor. Antigravity asks nothing
before it runs a new hook, so it gets no trust step, only a good-to-know line (see "Follow-up
lines" in [setup.md](setup.md)).

### The host app

`agy` starts the hook itself; in the spike the process tree ran from the hook through `agy`, the
shell and `login` to Terminal, so the process-tree walk finds the terminal the person runs `agy` in.
The app and the IDE were not captured.
