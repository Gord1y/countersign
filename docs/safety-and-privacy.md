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
  timeout is handed back to Cursor's own prompt. Antigravity doesn't document what it does on a
  hook timeout, so its requests are handed back the same way.
- The panel takes the keyboard, but its app never becomes the active app, and a guard hands
  activation straight back if macOS ever tries. It never grabs the keyboard back: when focus leaves
  it, for another app or the lock screen, it steps aside until your next pause.
- Keys and clicks in the first moments after a panel appears are swallowed, never passed through:
  0.8 seconds by default (`armDelay`), 0.1 seconds for a panel that follows one you just answered
  (`chainedArmDelay`).

## What it reads

- The request each agent sends to the hook.
- For an edit, the file being edited, to show the change in context. It is only read.
- Claude Code's session registry and the session's transcript, to notice that you answered a
  request in the chat, and the subagent files Claude Code keeps next to that transcript, to show
  which subagent asked.
- The chain of parent processes, to tell which app a request came from.
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
| Pause switch | `~/Library/Application Support/Countersign/paused` |
| Quiet time | `~/Library/Application Support/Countersign/quiet-until` |
| Menu-bar app lock | `~/Library/Application Support/Countersign/companion.lock` |
| Last update check | `~/Library/Application Support/Countersign/update-check.json` |
| Codex hook trust record | `~/Library/Application Support/Countersign/codex-hook-trust.json` |
| First-run tour shown | `~/Library/Application Support/Countersign/tour-shown` |
| Log (rotates at 1 MB) | `~/Library/Logs/Countersign/countersign.log` |

A request waiting in the queue is a small file naming its agent, project and tool, and the
subagent that asked, if any; it is removed when the request ends. The agents' own hook files, and a
backup next to each one, are written only when you run setup or click a host button in Settings
(see [setup.md](setup.md)). The Codex hook trust record holds Countersign's own entry in Codex's
`hooks.json` and the trust hashes Codex stored for it; setup and the Settings window write it when
they wire Codex, notice that Codex trusted the hook, or you click **Mark as done**. The config file
is written only when you change a preference in
Settings or click its **Open in Editor**, and by **Don't ask again** in the menu-bar app's
[quit question](menu-bar-app.md#quit). The first-run tour's empty marker file is written when you
skip or finish it, so it won't show again on its own; it holds no content, only its own existence.

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
