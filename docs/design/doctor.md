# Doctor internals

Every check `countersign doctor` runs, in the order it prints them, which status each finding
gets, why doctor never touches the display lock, and how the command is split between gathering
facts and judging them. Read it before changing `Doctor`, `DoctorCommand`, or anything whose state
doctor reports (the hook entries, the config file, the queue). What the report means to a user,
and what to do about it, is in [../troubleshooting.md](../troubleshooting.md).

Each line reads `<status> <check>: <detail>`, one of `ok`, `warn`, `fail` or `info`. Doctor exits
`1` when any line is `fail`, `0` otherwise. Nothing it prints is secret: it never shows a settings
or config file's content, only paths and our own hook entry's command.

## Checks, in order

1. **`version`**: the running version, the executable's resolved path, and the stable path
   `countersign setup` would write for it (see "The stable path" in [setup.md](setup.md)). Always
   `info`. Right after it, only when more than one copy of Countersign is installed (see "More
   than one copy installed" in [setup.md](setup.md)), one **`copies`** line, `warn`: how many
   copies, then each one's name, version and paths, marked `called by the hooks`, `running now` and
   `newest` where that applies, `the hooks call none of them` when none is, and the command that
   removes each copy. It never names a copy to keep; which one stays is the person's call, and
   `countersign settings` shows the steps for the copy they pick:

   ```text
   warn copies: 2 copies of Countersign are installed; Installer 0.1.0: ~/.local/bin/countersign, ~/Applications/Countersign.app (called by the hooks); Countersign.app 0.2.0: /Applications/Countersign.app (running now, newest); keep the one you want and remove the other; the command that removes each: Installer 0.1.0: rm ~/.local/bin/countersign && rm -rf ~/Applications/Countersign.app, Countersign.app 0.2.0: rm -rf /Applications/Countersign.app; countersign settings shows the steps for the copy you pick
   ```

   It is `warn`, not `fail`: every copy works and the hooks still answer; the risk is the terminal
   and the hooks running different versions, and the next update reaching only one of them. It is
   the one line that writes the home directory as `~`, since its commands are meant to be pasted.
   After it, only when the installer copy's `~/.local/bin/countersign` and
   `~/Applications/Countersign.app` both report a version and the two differ, one **`versions`**
   line, `warn`, with or without other copies: which of the two is older, both versions, and the
   command that updates the older one (see "More than one copy installed" in
   [setup.md](setup.md)):

   ```text
   warn versions: the menu-bar app is older than the command-line tool: Countersign.app is 0.1.0 but countersign is 0.2.0. Update the app: curl -fsSL https://raw.githubusercontent.com/Gord1y/countersign/main/install.sh | COUNTERSIGN_APP=1 sh
   ```
2. **`claude`**, then **`codex`**, then **`cursor`**, then **`antigravity`**: one host at a time,
   from [`HookConfigLocation`](../../Sources/ApprovalCore/HookConfigLocation.swift), honouring
   `CLAUDE_CONFIG_DIR` and `CODEX_HOME` (Cursor's file is always `~/.cursor/hooks.json`,
   Antigravity's always `~/.gemini/config/hooks.json`):
   - the host's directory doesn't exist (for Antigravity, none of `~/.gemini/antigravity-cli`,
     `~/.gemini/antigravity` and `~/.gemini/antigravity-ide` does): `info … not installed`, naming
     the directories looked for.
   - the directory exists but its settings file doesn't: `warn`.
   - the file exists but can't be read: `fail`, with the reason.
   - the file exists but holds only whitespace, the same as a missing file everywhere else in this
     project (see "The entries setup writes" in [setup.md](setup.md)): `warn … is empty`.
   - the file isn't valid JSON: `fail`. For Antigravity the line adds that Antigravity ignores the
     whole file when any part of it is invalid, since then none of its hooks run, ours included.
   - the file is valid JSON but holds no countersign entry under `hooks.PermissionRequest` (for
     Cursor, under either `hooks.beforeShellExecution` or `hooks.beforeMCPExecution`; for
     Antigravity, no top-level named hook `countersign`): `warn`.
   - for Cursor, an entry under one of those two events but none under the other: one `warn`
     naming the event that lacks it, since Cursor would then skip the panel for that kind of call.
   - for Antigravity, a `countersign` named hook that is not in the exact shape setup writes (see
     "The entries setup writes" in [setup.md](setup.md)): one `warn` saying so, with the same note
     that Antigravity ignores the whole file when any part of it is invalid. Its entry is not
     checked further; `countersign setup` rewrites the named hook.
   - each countersign entry found is checked on its own (labelled `entry`, or `entry 1`, `entry 2`,
     … when there is more than one; for Cursor the label names the event, as in
     `beforeShellExecution entry`, and the numbers count within that event):
     - its executable path differs from the stable path above: `warn` (an upgrade moved the
       binary; `countersign setup` fixes it).
     - its executable doesn't exist or isn't executable: `fail`.
     - its `timeout` is missing or below 600 seconds: `warn`. The panel waits for a person, and a
       short hook timeout kills the request mid-wait. For Cursor it is worse than a lost panel: a
       timed-out Cursor hook lets the command run, and the hook's own hand-back is timed against
       the 3600 seconds setup writes (see "Handing back before Cursor's timeout" in
       [hosts.md](hosts.md)). Antigravity's hand-back is timed the same way.
     - its arguments are anything but `hook --host <host>`, for the host whose file it sits in
       (an extra word, another host, no host): `warn`. The hook takes `--host` and nothing else
       and refuses any other argument, which means no panel for that host, and an entry for
       another host reads this host's requests with the wrong adapter (see "Precedence" in
       [settings.md](settings.md)). It is not `fail` because doctor reads the command's words,
       not the shell: a hand-added `2>/dev/null` counts as an extra word, yet the hook still
       works. `countersign setup` rewrites the command (see "Install" in [setup.md](setup.md)).
     - an entry with none of the above prints a single `ok` line naming its path and timeout, so a
       clean host still shows up in the output instead of staying silent.

   After the lines above, for Claude Code's file only, when it is valid JSON, lines with the check
   name **`claude context`** cover the `hooks.UserPromptSubmit` entry that Context checkpoints
   need (see "The Context checkpoints entry" in [setup.md](setup.md)). They depend on
   `Doctor.Input.contextCheckpointsEnabled`, which the caller fills from `config.json`:
   - enabled (the default) and no entry of ours: `warn`, since the feature is on and nothing calls
     the hook; `countersign setup`, or Update in Settings ▸ Agents, adds the entry. The line reads
     "context checkpoints are on, but <file> has no UserPromptSubmit entry of Countersign's; run
     countersign setup, or choose Update in Settings ▸ Agents".
   - disabled and an entry of ours present: `warn`; turning Context checkpoints off in
     `countersign settings` removes it.
   - an entry whose `async` is not `true`: `warn`, because without `async` every prompt waits for
     the checkpoint panel; `countersign setup` refreshes it.
   - the entry's executable path, missing executable and `timeout` are checked with the same rules
     and wording as the `PermissionRequest` entry's, labelled `UserPromptSubmit entry`.
   - enabled and the entry fine: one `ok` line, `UserPromptSubmit entry in <path>, async`.
   - disabled and no entry: no line.

   Lines named **`claude waiting`** cover the `hooks.Stop` entry of Waiting-agent notices (see "The
   waiting-agent entry" in [setup.md](setup.md)), with the same shape, driven by
   `Doctor.Input.waitingNoticesEnabled`:
   - enabled and no entry: `warn`, "waiting-agent notices are on, but <file> has no <event> entry
     of Countersign's; run countersign setup, or Update in Settings ▸ Agents", which adds it.
   - disabled and an entry present: `warn`; turning the notices off removes it.
   - not async: `warn`, because every turn end would wait for it; `countersign setup` refreshes it.
   - the path and executable checks are the `PermissionRequest` entry's, and the arguments must
     include `--event waiting`; the 600 second minimum timeout does not apply, since the entry
     runs for 30 seconds.
   - enabled and fine: one `ok` line, `Stop entry in <path>, async`.

   Lines named **`codex waiting`**, **`cursor waiting`** and **`antigravity waiting`** cover the
   other hosts' entries (`hooks.Stop`, `hooks.stop` and the `countersign-waiting` hook) with the
   same three cases and the same path, executable and arguments checks, without the async line:
   the `ok` line is `<event> entry in <path>` (`stop` for Cursor), since only Claude Code's entry
   is async. For Codex, while the notices are on and the entry exists, one more line is the trust
   verdict for the `Stop` entry, judged from `Doctor.Input.codexWaitingHookTrustRecord`
   (`codex-waiting-hook-trust.json`) the way the approval entry is (see "The verdict" in
   [setup.md](setup.md)): pending is a `warn`, `Codex has not trusted Countersign's Stop entry yet;
   run /hooks in a Codex session and trust it`; unknown is an `info`, `cannot tell whether Codex
   trusts Countersign's Stop entry; run /hooks in a Codex session to check`; trusted or marked as
   done adds nothing.
3. Right after each host's lines, only when that host ends up wired and up to date (the same gate
   the Agents rows use for "Wired"; see "Follow-up lines" in [setup.md](setup.md)): for Codex, one
   line for the state `CodexTrustVerdict.judge` gives (see "The verdict" in [setup.md](setup.md)),
   where `<next step>` is `AgentFollowUps.codexNextStep`:

   | State | Line |
   | --- | --- |
   | `.trusted` | `ok codex: Codex trusts Countersign's hook` |
   | `.markedDone` | `ok codex: you marked Countersign's hook as trusted in Codex` |
   | `.pending` with a reason | `warn codex: <reason> <next step>` |
   | `.pending` without one, no "Mark as done" | `warn codex: Codex has not trusted Countersign's hook yet. <next step>` |
   | `.pending` without one, with "Mark as done"; `.unknown` | `info codex: cannot tell whether Codex trusts Countersign's hook. <next step>` |

   `.pending` is `warn`, not `fail`: the hook is wired, and Codex falls back to its own prompt until
   the person trusts it. A pending without a reason that offers "Mark as done" is one the verdict
   cannot be sure of (see "The verdict" in [setup.md](setup.md)), so doctor does not claim Codex
   has not trusted the hook. Doctor only reads: a hash the verdict learns is saved by the settings
   window or `setup --cli`, never by doctor. Claude Code never gets a line here. For Cursor and
   Antigravity, one permanent `info` line quoting
   `AgentFollowUps.cursorGoodToKnow` and `antigravityGoodToKnow` (the Antigravity one says it asks
   again after an approval until it fixes google-antigravity/antigravity-cli#1053; see "Approve is
   not enough yet" in [hosts.md](hosts.md)).
4. **`config`**: the config file's path (see "The config file" in [settings.md](settings.md)):
   - missing: `info … using defaults`.
   - present but every key parsed cleanly: `ok`.
   - present with bad keys: one `warn` line per line `ConfigFileLoader` logged, verbatim.
5. **`rules`**: the approval rules from the config file: `info … none` when there are none, else
   `ok` with the count and how many allow and how many deny, such as `2 (1 allow, 1 deny)`.
6. **`queue`**: the queue directory and how many tickets `TicketQueue.liveTickets()` currently
   considers live. `info`. Listing prunes dead tickets the same way every other listing does (see
   "Liveness and pid reuse" in [queue.md](queue.md)), so this count can drop between two runs.
7. **`state`**: active, paused, or "paused until Countersign opens" for the pause the menu-bar
   app's quit question sets (`PauseState.description`, the same words `countersign status`
   prints; see "Quit" in [app.md](app.md)), and quiet time's end or `off`. `info`.
8. **`log`**: the log file's path and size, or that it hasn't been created yet. `info`.

## Why it never locks `display.lock`

Doctor lists live tickets to count them, exactly like `countersign status`, but it never calls
`acquireDisplayIfHead` and never opens `display.lock`. A doctor run must never compete for the
lock a real panel is about to take: someone runs `doctor` while debugging a stuck request, and the
last thing that request needs is a diagnostic tool adding its own contender for the display lease.

## Structure

`DoctorCommand` (`Sources/countersign`) gathers plain facts: file bytes, resolved paths,
environment variables, the queue listing, pause and quiet state, and the log file's size. It hands
them to `Doctor.report`, a pure function in `ApprovalCore` that turns those facts into the lines
above. The `copies` line arrives already built: `DoctorCommand` runs `InstallCopiesCheck` with the
hook entries' executable paths it read for the host checks and sets `Doctor.Input.duplicateInstall`,
which stays `nil` with one copy, and `InstallCopiesCheck.versionMismatch` for
`Doctor.Input.installVersionMismatch`, which stays `nil` unless the installer's app and CLI
versions differ. `Doctor.Input.codexHookTrustRecord` arrives the same way:
`DoctorCommand` loads it with `CodexHookTrustRecordStore.load(file:
paths.codexHookTrustFile)`, and reads Codex's `config.toml` (`CodexHookTrust.configFile(for:)`) into
`Doctor.Input.codexConfigFile`, which `Doctor.report` hands to `CodexTrustTable.read`.
`Doctor.report` recomputes each host's wiring status with
`HostWiring.status`, the same function the Agents rows call, to decide whether a follow-up line
belongs there (see "Follow-up lines" in [setup.md](setup.md)). `Doctor` reuses `HookSetup.sites`
(`CursorHookSetup.sites` and `missingEvents` for Cursor, `AntigravityHookSetup.hookNodes` and its
setup-shape check for Antigravity) and `HookCommand.words` to find and parse a host's countersign
entries, the same recognition `setup` uses, rather than walking the JSON a second way. The menu-bar
companion's "Report a Problem…" builds its prefilled bug report from the same `Doctor` model (see
"What the menu does" in
[app.md](app.md)).
