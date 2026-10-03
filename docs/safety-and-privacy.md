# Safety and privacy

How Countersign answers a request without ever approving anything by accident, what it reads and
writes on your Mac and where, and the one network request it can make. Read it before you install
Countersign, or when you want to know why a crash or a timeout can never approve a command.

## How it works

Every permission prompt starts a short-lived `countersign hook` process. It either prints one
decision for the agent, or exits without printing anything, which means "no decision, show your
usual prompt". There is no background service: the [menu-bar app](menu-bar-app.md) is optional,
and approvals work the same without it. When you hand a Cursor or Antigravity request back to its
chat, the hook answers `ask` instead of staying silent, so that agent shows its own prompt too.
How each answer plays out, agent by agent, is in [agents.md](agents.md); the design behind it is in
[design/README.md](design/README.md).

## It fails safe

- Any error, crash or timeout means "no decision", never an approval. The hook never writes to
  stderr and never exits with an error status: Codex treats "exit 2 plus stderr" as a denial, so a
  crash can never look like one either.
- Nothing is decided by a timeout. If a hook times out, the agent shows its own prompt. Cursor lets
  a command run when its hook times out, so a Cursor request still unanswered a minute before its
  timeout is handed back to Cursor's own prompt. The one exception: in Cursor's Auto-review or Run
  Everything mode, handing it back would run the command without asking you, so that request is
  denied instead ("No answer in Countersign within an hour, so Cursor did not run this.").
  Antigravity doesn't document what it does on a hook timeout, so its requests are handed back the
  same way.
- The panel takes the keyboard, but its app never becomes the active app, and a guard hands
  activation straight back if macOS ever tries. It never grabs the keyboard back: when focus leaves
  it, for another app or the lock screen, it steps aside until your next pause.
- Keys and clicks in the first moments after a panel appears are swallowed, never passed through:
  0.5 seconds by default (`armDelay`), 0.1 seconds for a panel that follows one you just answered
  (`chainedArmDelay`).

## What it reads

- The request each agent sends to the hook.
- For an edit, the file being edited, to show the change in context. It is only read.
- Claude Code's session registry and the session's transcript, to notice that you answered a
  request in the chat, and the subagent files Claude Code keeps next to that transcript, to show
  which subagent asked.
- With context checkpoints on, the tail of the session transcript Claude Code names in the hook
  input, for the token counts, the model name and compaction markers only. Message text is not
  used.
- With waiting-agent notices on, the growth of the session's transcript, to tell when the agent
  works again (see [below](#what-it-writes)). Message text is not used.
- The chain of parent processes, to tell which app a request came from.
- While a request waits for you to pause, which windows are on screen: for each, the app that owns
  it, its layer and its size, to tell when Mission Control or App Exposé is open. Window titles and
  contents are not used.
- The agents' hook config files, when you run setup, doctor or the Settings window.
- Codex's `config.toml`, at the same times, for one thing only: the trust Codex stores for its hooks,
  to tell whether Codex has trusted Countersign's hook. Everything else in that file is skipped.
- Its own config file.

None of this leaves your Mac, and none of it is written to the log.

## What it writes

| What | Where |
| --- | --- |
| Binary (Homebrew) | `$(brew --prefix)/bin/countersign` |
| Binary (curl installer or from source) | `~/.local/bin/countersign` |
| App bundle (Homebrew) | `$(brew --prefix)/opt/countersign/Countersign.app` |
| App bundle (curl installer) | `~/Applications/Countersign.app` |
| Config file | `~/.config/countersign/config.json` (or `$XDG_CONFIG_HOME/countersign/config.json`) |
| Queue and display lock | `~/Library/Application Support/Countersign/queue/` |
| Context checkpoint state, one small file per Claude Code session | ~/Library/Application Support/Countersign/context/ |
| Decision history, the last 200 answers | `~/Library/Application Support/Countersign/history.jsonl` |
| Waiting-agent records, one per waiting session, their `*.lock` and `slot-<n>.lock` files, and `approval-claim.json` (the process id of a request whose approval card waits for a corner) | `~/Library/Application Support/Countersign/waiting/` |
| Pause switch | `~/Library/Application Support/Countersign/paused` |
| Quiet time | `~/Library/Application Support/Countersign/quiet-until` |
| Menu-bar app lock | `~/Library/Application Support/Countersign/companion.lock` |
| Last update check | `~/Library/Application Support/Countersign/update-check.json` |
| Codex hook trust record | `~/Library/Application Support/Countersign/codex-hook-trust.json` |
| First-run tour shown | `~/Library/Application Support/Countersign/tour-shown` |
| Log (rotates at 1 MB) | `~/Library/Logs/Countersign/countersign.log` |

A request waiting in the queue is a small file naming its agent, project and tool, and the
subagent that asked, if any; it is removed when the request ends. An answer you pick for it from
the menu bar is a one-word file next to it (`show`, `deny` or `chat`), removed as soon as the
request reads it, or with the request. The agents' own hook files, and a
backup next to each one, are written only when you run setup or click a host button in Settings
(see [setup.md](setup.md)). The Codex hook trust record holds Countersign's own entry in Codex's
`hooks.json` and the trust hashes Codex stored for it; setup and the Settings window write it when
they wire Codex, notice that Codex trusted the hook, or you click **Mark as done**. The config file
is written only when you change a preference in
Settings or click its **Open in Editor**, and by **Don't ask again** in the menu-bar app's
[quit question](menu-bar-app.md#quit). The first-run tour's empty marker file is written when you
skip or finish it, so it won't show again on its own; it holds no content, only its own existence.

The decision history is a JSON Lines file that feeds the menu-bar app's **Recent Decisions**
submenu. Each line holds the time, the agent, the project, the tool, your answer (approved, denied,
answered in the chat, resolved elsewhere, or a context checkpoint choice) and a one-line title:
the first line of a command, the name of a file, an MCP tool's name, a question's header, `Plan`,
or `Context at 240K`, cut to 80 characters. It never holds a whole command, a file's contents, a
question's answer or a deny reason. A panel writes its line when it finishes, and a request that is
resolved in the chat while it waits or is shown gets one too; test panels never write. It keeps
the last 200 lines: once the file passes 250, it is trimmed to 200. **Clear History** in the menu
deletes them all, and so does removing the file. A failed write is logged and never affects the
answer.

A waiting-agent record exists only with waiting-agent notices on, and only while a notice is
pending. It is a small JSON file named after the agent and session, holding the agent, the session
id, the project's name and path, the path of the session's transcript, the agent's app (bundle id,
process id and name), the agent's process id and a time. It never holds message text. It is deleted
when the notice closes, which it does when the agent works again, and a notice gives up and deletes
it after 12 hours. The lock files next to it only keep one notice per session and place the cards
apart; they hold nothing. To find a Codex session's transcript, Countersign looks in
`~/.codex/sessions` for a file named after the session id, in the last 14 day folders. A notice
then watches the session's transcript, only to see whether it has grown with a real message: it
reads the type of each new row, not its text. Turning notices off stops all of this.

The log records metadata only: time, agent, tool name, project, subagent type, the app the request
came from, and what became of the request. Commands, file contents, answers and deny reasons are never written. When it passes
1 MB, the current log becomes `countersign.log.1`, replacing the previous one.

## The network

Countersign makes one kind of network request, and only from the menu-bar app: the
[update check](menu-bar-app.md#check-for-updates). It is off unless you turn it on, or choose
**Check for Updates…**. It fetches
`https://raw.githubusercontent.com/Gord1y/countersign/main/releases/index.json` with no cookies, no
query and no body, and never downloads or installs anything. The hook, setup, doctor and the
panel never touch the network.

**Report a Problem…**, **Ask a Question…** and the other Help items open pages in your browser;
nothing is sent until you submit something there yourself.
