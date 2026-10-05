# What each agent gets

What Countersign does for each agent it supports: which requests get a panel, what each answer
does in that agent, and where each agent falls short. Read it when you want to know what Approve,
Deny or "Answer in chat" will actually do for a request from Claude Code, Codex, Cursor or
Antigravity.

## Answers at a glance

| Answer | Claude Code | Codex | Cursor | Antigravity |
| --- | --- | --- | --- | --- |
| **Approve** (<kbd>Return</kbd>) | Runs the call | Runs the call | Cursor decides by its run mode; in Allowlist mode it asks you once more (see [below](#cursor)) | Asks you once more in its own prompt (see [below](#antigravity)) |
| **Always allow** (Approve ▾) | Approves, and hands Claude Code the rule to keep | Approves, and saves a Countersign rule | Not offered: Cursor ignores it | Not offered: Antigravity ignores it |
| **Deny**, with a reason | Blocks the call | Blocks the call | Blocks it and shows the reason to you and the agent | Blocks it and shows the reason |
| **Deny & stop** (<kbd>⌘</kbd><kbd>Return</kbd> in the deny step) | Blocks the call and asks Claude Code to interrupt | Not offered | Not offered | Not offered |
| **Answer in chat** (<kbd>Esc</kbd>, a click outside) | Claude Code shows its own prompt | Codex shows its own prompt | Cursor shows its own approval prompt; in Auto-review and Run Everything the request waits as **Later** instead | Antigravity shows its own approval prompt |
| Questions and plans | Answered in the panel | Stay in Codex | Stay in Cursor | Stay in Antigravity |
| No answer at all | Claude Code shows its own prompt | Codex shows its own prompt | Cursor carries on as it would without Countersign | Antigravity carries on with its own permission check |

A matching [allow or deny rule](configuration.md#allow-and-deny-rules) answers before any panel,
with the same result as **Approve** or **Deny**.

A deny with an empty reason sends "Denied in the approval panel." The exact output behind every
cell, and the line each one leaves in the log, are in [design/answers.md](design/answers.md).

The menu bar's list of pending requests offers **Deny** and **Answer in Chat** too, without
opening the panel (see [menu-bar-app.md](menu-bar-app.md#pause-snooze-and-pending-requests)).
Each sends exactly what the panel's button sends, for every agent: **Deny** from the menu is a
plain **Deny** with the default reason, never **Deny & stop**, and **Answer in Chat** from the
menu is the same as <kbd>Esc</kbd>. There is no Approve from the menu. The one exception: a Cursor
request in Auto-review or Run Everything mode isn't offered **Answer in Chat**, because there
Cursor would run the command without asking you (see [Cursor](#cursor) below).

## Claude Code

**What gets a panel:** every permission prompt Claude Code would otherwise show you, including its
questions (`AskUserQuestion`) and plan approval (`ExitPlanMode`).

- **Approve ▾** lists the "Always allow" rules Claude Code itself suggests for this request, such
  as allowing a command from now on. Each shows the exact rule, such as
  `Bash(git push origin *)`, and where it is saved: this project on this Mac, this project shared,
  all projects, or this session. Picking one approves the request and passes that rule back for
  Claude Code to apply.
- **Deny & stop** sends the denial and asks Claude Code to interrupt the turn rather than carry
  on.
- **Questions** show as tabs with numbered options. Your answers go back to Claude as the answers to
  its question. Turn on `questionNotes` in the [config file](configuration.md) to add a note under
  the option you pick, sent back too; it's off by default.
- **Plans** show as Markdown. Approving sends the plan back with the mode Claude continues in for
  the session, chosen under **then: …**: Ask before edits, Accept edits or Auto. The menu starts
  on `modeAfterPlan` from the [config file](configuration.md) (Ask before edits by default), and
  you can still pick another mode there for a single plan.
  <kbd>⌫</kbd> or **Keep planning** opens a feedback field; sending it, or leaving it empty, tells
  Claude "Not approved yet. Keep planning." instead.
- **Answering in the chat** works as it always did. Countersign notices within about a second and
  the panel, or the request still waiting in the queue, goes away. Answer during the grace period
  (`graceSeconds`, off by default) and no panel appears at all.
- **Non-interactive runs**, such as `claude -p`, get no panel, since nobody is at a chat to answer
  them. `includeHeadlessSessions` in the [config file](configuration.md) turns that off.

Noticing a chat answer relies on Claude Code internals that aren't documented; if a Claude Code
release changes them, the panel still works but stays up until you close it. Details are in
[limitations.md](limitations.md).

### Context checkpoints

On by default for Claude Code; turn it off in Settings ▸ Panels ▸ Context checkpoints.
Countersign reads the session's transcript on each prompt, estimates the context size, and at
three checkpoints shows a panel, or in silent mode adds a note without one. Thresholds, silent mode and
the rest are in [configuration.md](configuration.md#context-checkpoints-claude-code); how the size
is measured is in [design/checkpoints.md](design/checkpoints.md).

- **Continue** sends nothing. Esc or a click outside does the same.
- **Not this session** sends nothing and mutes the session: no further checkpoint until it ends.
- **Compact after this step** sends Claude a note to finish its current step and suggest
  compacting. Countersign cannot run `/compact` itself, so Claude's reply tells you what to run.
- **Hand off & start fresh** sends Claude a note to write a handoff and suggest starting a fresh
  session; Claude's reply tells you what to run.

The prompt never waits for a checkpoint: the hook runs in the background, and the note reaches
Claude at its next request, or with your next message when Claude is idle.

### After wiring

Nothing to do. Claude Code picks up a hook edit through its own file watcher; restart it only if a
request still gets no panel a minute or two after wiring.

## Codex

**What gets a panel:** every permission prompt Codex sends to its hooks: shell commands, MCP tool
calls, and `apply_patch` edits, shown against the real file like Claude Code's edits.

- Approve and Deny (with a reason) work as for Claude Code. Codex has no "Always allow" rules of
  its own to offer, no **Deny & stop**, and no hook for its question and plan tools, so those stay
  in Codex.
- **Approve ▾ → Always allow** saves a rule for Codex in this project and approves the request. For
  a shell command it saves the exact command, or each distinct part of a compound command; for
  anything else, such as an `apply_patch` edit or an MCP call, it saves the tool. See and remove it
  in Settings ▸ Rules, or in `config.json`.
- Codex asks you to trust Countersign's hooks once in `/hooks`: the permission hook and, while
  waiting-agent notices are on, the Stop hook. See "After wiring" below.
- Countersign can't see a Codex chat, so answering there doesn't close the panel. It goes away when
  you answer it, or when the Codex process that asked is gone.
- Codex asks its hooks before it shows its own prompt, so a Codex request waiting in the queue
  holds its Codex turn until you answer. "Answer in chat" keeps that short. `handoffApps` hands it
  to Codex's own prompt only when its panel would appear, after the queue and the pause in your
  typing, so it holds the turn until then too.

### After wiring

Open Codex in a terminal, not the desktop app, run `/hooks` and trust Countersign's hooks. It has to
be the terminal: the desktop app shares the same `~/.codex`, but its own `/hooks` can't write the
trust record Codex checks. Codex sessions already open pick up the trust as soon as you run
`/hooks`, without needing a new session, even though Codex doesn't otherwise reload `hooks.json` on
its own while a session is running. Countersign reads the trust Codex stores, so the step clears
itself once you've trusted the hooks in a terminal. See
[Codex asks you to trust the hook](setup.md#codex-asks-you-to-trust-the-hook) for the exact wording,
when **Mark as done** shows up, and why a changed entry (an upgrade, a new install path, a hook
added before Countersign's) needs trusting again.

## Cursor

**What gets a panel:** shell commands Cursor runs outside its sandbox, for example one that needs
the network, and every MCP tool call. Commands inside the sandbox and file edits follow Cursor's
own settings, as they would without Countersign. Commands on Cursor's command allowlist (the
in-app list, or `terminalAllowlist` in `permissions.json`) get no panel when Cursor would run them
without asking; a compound command gets a panel unless every part is on the list.

- **Approve isn't always enough.** Cursor currently ignores an approval from a hook and decides by
  its own run mode: in Allowlist mode it asks you itself, so you approve twice; in Auto-review its
  AI review decides; in Run Everything the command runs. Cursor's staff call this an open bug: only
  a deny from a hook is respected today
  ([forum thread](https://forum.cursor.com/t/support-authoritative-allow-deny-and-ask-verdicts-from-hooks/161342)).
  Once it is fixed, Approve will be enough, with nothing to change in Countersign.
- **Deny** blocks it, shows your reason to you and hands it to the agent. There is no
  **Deny & stop**, and no questions or plans.
- **No Approve ▾ → Always allow.** Cursor would ignore the saved rule's approval too, so Approve
  has no ▾ menu here and <kbd>⌘</kbd><kbd>Return</kbd> does nothing; <kbd>Return</kbd>
  approves. An allow rule you add in Settings ▸ Rules keeps Countersign's panel away; Cursor still
  decides by its run mode.
- **Answer in chat** depends on Cursor's run mode. In Allowlist mode (and the old Ask Every Time),
  it makes Cursor show its own approval prompt, even for a command it would have run in its
  sandbox, and `handoffApps` does the same. In Auto-review or Run Everything mode, Cursor's prompt
  would not reach you: the command would go to Cursor's AI review or simply run. So there the link
  reads **Later** instead: <kbd>Esc</kbd> or a click outside puts the panel away, the next request
  takes the screen, and a corner card shows at once. The panel comes back when you click the
  card's **Show** or choose **Show Now** from the menu bar; the request keeps waiting until then.
  The menu doesn't offer **Answer in Chat** for it, and `handoffApps` doesn't apply. The same goes
  when Countersign can't tell which mode Cursor is in.
- **An hour limit.** Cursor runs a command when its hook times out, so a request still unanswered
  59 minutes after it arrived doesn't wait any longer, and the next request takes the screen. In
  Allowlist mode it goes back to Cursor's own prompt. In Auto-review or Run Everything mode it is
  denied with "No answer in Countersign within an hour, so Cursor did not run this.", since handing
  it back would run it.
- **No answer at all**, for example while Countersign is paused, lets Cursor carry on as if
  Countersign weren't installed, which under auto-run can mean running the command without asking.
- Countersign can't see a Cursor chat, so answering there doesn't close the panel.

### After wiring

Nothing to do, but worth knowing: only commands Cursor runs outside its sandbox, and MCP tool
calls, get a panel — the rest follow Cursor's own settings, as above. A command on Cursor's command
allowlist gets no panel when Cursor would run it without asking, and a compound command gets one
unless every part is on the list. Cursor reloads `hooks.json` on
save, so wiring or updating takes effect right away; restart it only if a request still gets no
panel.

## Antigravity

**What gets a panel:** every command (`run_command`) and every MCP tool call (`call_mcp_tool`), from
the `agy` CLI, the Antigravity app and the Antigravity IDE. Reading and editing files, searches,
the browser, and Antigravity's own questions and plans follow Antigravity's own settings.

- **Approve isn't enough yet.** Antigravity ignores an approval from a hook and asks you itself
  anyway, so you approve twice: in the panel, then in Antigravity. This is Antigravity's bug,
  [google-antigravity/antigravity-cli#1053](https://github.com/google-antigravity/antigravity-cli/issues/1053).
  Once it is fixed, Approve will be enough, with nothing to change in Countersign.
- **Deny** blocks the call and shows your reason, even under `--dangerously-skip-permissions`.
- **No Approve ▾ → Always allow**, for the same reason: Antigravity would ignore the saved rule's
  approval and ask you anyway. An allow rule you add in Settings ▸ Rules keeps Countersign's panel
  away; Antigravity still asks.
- **Answer in chat** makes Antigravity show its own approval prompt; `handoffApps` does the same.
  Under `--dangerously-skip-permissions` expect it to run the call instead.
- **An hour limit**, as for Cursor: a request still unanswered after 59 minutes goes back to
  Antigravity's own prompt.
- **No answer at all** leaves the call to Antigravity's own permission check, which asks you in its
  default mode.
- Countersign can't see an Antigravity chat, so answering there doesn't close the panel.

### After wiring

Nothing to do, but worth knowing: after you approve in the panel, Antigravity still asks once more
in its own prompt until Google fixes
[google-antigravity/antigravity-cli#1053](https://github.com/google-antigravity/antigravity-cli/issues/1053)
(see "Approve isn't enough yet" above). Antigravity's own docs don't say whether it reloads
`hooks.json` on its own, so restart it after wiring or updating if a request still gets no panel.

## The waiting-agent notice

On by default. While it is on, `countersign setup` and Update in Settings ▸ Agents add one more
entry, for the end of an agent's turn, next to the permission entry in each agent's hook file, in
the same diff. An agent that was wired before shows "Needs an update" until you apply it. Turning
it off in Settings ▸ Panels ▸ Waiting-agent notices shows the change and removes the entries, and
setup then leaves them out; `countersign setup --remove` takes them out too. Each entry only records that the turn ended and exits,
so it never holds the agent up. When you have been away from the agent for the notice delay (10 seconds by default), a
corner card says it is waiting, and it closes by itself after it has been on screen for Show notice
for (10 seconds by default). What it does, and when it closes, is in
[configuration.md](configuration.md#panels) and [design/notice.md](design/notice.md).

| Agent | The entry |
| --- | --- |
| Claude Code | A `Stop` entry in `~/.claude/settings.json`, run in the background |
| Codex | A `Stop` entry in `~/.codex/hooks.json`. Codex runs a new hook only once you trust it: run `/hooks` in a Codex session and trust the new Stop entry |
| Cursor | A `stop` entry in `~/.cursor/hooks.json` |
| Antigravity | A second hook named `countersign-waiting`, on `Stop`, in `~/.gemini/config/hooks.json`, beside the `countersign` hook |

The notice also appears when you hand a request back to the agent's own prompt, since the agent is
then waiting for you just the same. Doctor checks each entry (`claude waiting` and the matching
lines for the other agents), and for Codex it says when the Stop entry is not trusted yet.

## When Countersign gives no answer

These are the cases where no panel shows, or a panel goes away without your answer. Unless the
request comes back later, the agent handles it its own way, as in the last row of the table above.

| When | What you see |
| --- | --- |
| Countersign is paused | No panel; one already on screen closes |
| Quiet time (snooze) | The panel steps aside and the request waits. It comes back when quiet time ends, unless it was answered in Claude Code's chat or the agent stopped waiting meanwhile |
| The app in front is in `handoffApps` and asked for this request when its panel would appear | No panel; the agent's own prompt |
| You answered in Claude Code's chat | The panel, or the waiting request, goes away |
| The agent stopped waiting, or quit | The panel closes |
| The agent's hook timed out | Whatever was waiting is gone; the agent decides on its own |
| Anything went wrong inside Countersign | No panel; the agent's own prompt or handling |

A mistake in the config file is not one of them: the setting it affects falls back to its default,
and the request gets its panel as usual.
