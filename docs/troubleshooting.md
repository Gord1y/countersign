# Troubleshooting

How to find out why Countersign isn't doing what you expect: checking your setup with
`countersign doctor`, the common situations and what to do about each, and how to report a
problem. Read it when no panel appears, a panel goes away on its own, an agent asks you twice, or a
setting seems to be ignored.

## Check your setup

```sh
countersign doctor
```

Doctor looks at your setup, changes nothing, and prints one line per finding:
`<status> <check>: <detail>`. Nothing it prints is secret: it shows paths and Countersign's own hook
command, never the content of your settings or config files, so you can paste it into a bug
report. It exits with status 1 when any line is `fail`.

| Status | Meaning |
| --- | --- |
| `ok` | Checked and fine. |
| `warn` | Not broken, but worth a look; usually fixed by running `countersign setup` again. |
| `fail` | Broken: the hook can't answer until this is fixed. Fix these first. |
| `info` | Just a fact: an agent that isn't installed, the queue, whether you're paused. |

It checks, in this order: which `countersign` is running and the path setup would write, and
whether more than one copy of Countersign is installed, and whether the curl install's menu-bar
app and command-line tool are on different versions; for each agent, its hook file and every
Countersign entry in it; the config file; the approval rules; the queue; pause and quiet time; and the log file. The
lines worth acting on:

| Doctor says | What to do |
| --- | --- |
| `copies: 2 copies of Countersign are installed; …` | Choose one to keep; see [below](#two-copies-of-countersign-are-installed) |
| `versions: the menu-bar app is older than the command-line tool: …`, or the other way round | Run the command at the end of the line; see [below](#the-menu-bar-app-and-the-command-line-tool-are-on-different-versions) |
| `no countersign entry in …`, or `… is missing` or `… is empty` | Connect that agent: `countersign setup`, or **Wire** in Settings |
| `… differs from the stable path …` | `countersign setup`; an upgrade or a second install moved the binary |
| `… does not exist or is not executable` | `countersign setup` from the copy you use now |
| `timeout is …, below 600s` | `countersign setup` puts back the 3600 seconds it writes |
| `no countersign entry under hooks.<event>` (Cursor) | `countersign setup` adds the missing one |
| `… is not in the shape setup writes` (Antigravity) | `countersign setup` rewrites it |
| `… is not valid JSON` or `… could not be read` | Fix the file by hand; setup won't edit it until then |
| `arguments … differ from hook --host …` | `countersign setup` rewrites the command; settings belong in the config file |
| a `warn` line under `config` | Fix that key; see [configuration.md](configuration.md#mistakes-in-the-file) |

Every check and status is listed in [design/doctor.md](design/doctor.md).

## No panel appears

Go through these in order:

1. **Does a test panel appear?** Run `countersign test-panel`, or choose **Show a Test Panel** in
   the menu-bar app — see "Try your settings" in
   [configuration.md](configuration.md#try-your-settings) for what it uses. If it appears,
   Countersign's display works, and the problem is the agent's wiring: the checks below cover
   that. If it says a panel is already on screen or a request is waiting for one, answer that
   first. If no panel appears either, keep going.
2. **Paused or in quiet time?** `countersign status` prints `state: paused` or
   `quiet: until <time>`. `countersign resume` or `countersign snooze off` ends them, and so does
   the menu-bar app. `state: paused until Countersign opens` means you chose **Pause until I
   reopen** when you quit the menu-bar app, or its **When Countersign quits** setting is **Pause
   panels**: opening Countersign.app ends it (see [menu-bar-app.md](menu-bar-app.md#quit)).
3. **Still waiting for a pause?** A panel appears only after you've stopped typing, clicking and
   scrolling for 5 seconds (`idleSeconds`), and only one panel is on screen at a time, so another
   request may be ahead of this one. `countersign status` shows how many are queued.
4. **A request Countersign isn't asked about?** Cursor doesn't ask about commands in its sandbox or
   about file edits, Antigravity asks only about commands and MCP tools, and non-interactive
   Claude Code runs such as `claude -p` get no panel by default. See [agents.md](agents.md).
5. **Was the app in front on your `handoffApps` list when the panel was due?** Then a request from
   that app goes to the agent's own prompt, by design. It's checked when the panel would appear,
   after the pause in your typing, not when the request arrives.
6. **Is the agent wired to this Countersign?** Run `countersign doctor` and act on its `warn` and
   `fail` lines above.
7. **Codex:** have you trusted the hook? See [below](#codex-shows-no-panel).
8. **Antigravity:** Antigravity ignores its whole `~/.gemini/config/hooks.json` when any hook in it
   is invalid, someone else's included. The `agy` CLI says so in
   `~/.gemini/antigravity-cli/cli.log`.

The log, `~/Library/Logs/Countersign/countersign.log`, says what happened to each request. A
request starts with a `start host=… tool=… project=…` line and ends with what became of it, such as
`skipped: sandboxed command`, `skipped: on Cursor's allowlist`, `handoff: <bundle id> frontmost`,
`resolved during grace: registry` or `outcome: allow`; a paused Countersign logs just `paused`.
Each Cursor request that gets past the sandbox check logs `cursor: run mode …` first, naming the run
mode and where the command allowlist came from. A request answered by one of your
[rules](configuration.md#allow-and-deny-rules) logs `rule: allowed by rules[2]` or
`rule: denied by rules[2]` and then `outcome: allow` or `outcome: deny`. The number is the rule's
position in `config.json`, counting from 0 and counting only the rules Countersign could read;
`countersign doctor` lists the entries it dropped. If the agent asks and nothing at all is logged,
the agent never ran the hook: check its wiring.
Cursor also runs Claude Code's hooks; those runs log `ignored: a Cursor payload in a Claude Code
hook` and change nothing.

## No waiting-agent notice appears

Go through these in order:

1. **Is the feature on?** It is on by default; check Settings ▸ Panels ▸ Waiting-agent notices.
2. **Is the agent wired for it?** `countersign doctor` reports each agent's Stop entry on its
   `claude waiting`, `codex waiting`, `cursor waiting` and `antigravity waiting` lines; if one is
   not `ok`, run `countersign setup` or press Update in Settings ▸ Agents, which shows the change
   before it writes the entry.
3. **Codex:** has Codex trusted the new Stop entry? Doctor says `Codex has not trusted
   Countersign's Stop entry yet` until you run `/hooks` in a Codex session and trust it.
4. **Paused or in quiet time?** Both hold a notice back and show it when they end; see
   [No panel appears](#no-panel-appears).
5. **Were you in the agent's app?** Being there counts as having seen it, so leaving it restarts
   the wait: the card comes after the delay (10 seconds by default, `waitingNoticeDelay`), counted
   from when you left.
6. **Is a Countersign panel for that session open?** The panel is its own notice, so the card waits
   for it.
7. **Did the agent resume first?** A notice closes as soon as the agent works again, such as when
   you answered it in its chat, so one that was answered before the delay never shows.
8. **A headless session?** Non-interactive runs such as `claude -p` never get a notice.

A notice closes by itself once it has been on screen for Show notice for (10 seconds by default,
`waitingNoticeDuration`), counting only the time it is visible and not hovered; the log says
`notice: closed (shown long enough)`, and it does not come back for the same stop. A notice that
nobody dismisses and never shows gives up after 12 hours. The log,
`~/Library/Logs/Countersign/countersign.log`, says why one did not show, on lines starting with
`waiting:` and `notice:`.

## No context checkpoint appears

Go through these in order:

1. **Is the feature on?** It is on by default for Claude Code; if you turned it off, turn it back on
   in Settings ▸ Panels ▸ Context checkpoints. `countersign test-panel context` shows a checkpoint
   panel with your settings, whatever the session.
2. **Is the hook wired?** `countersign doctor` reports it on its `claude context` line; if it is
   not `ok`, open Settings ▸ Context: the Claude Code hook row says Not wired or Needs an update,
   and Update shows the change before it writes the entry again (see [setup.md](setup.md)).
3. **Paused or in quiet time?** Both hold checkpoints back, as they do any panel; see
   [No panel appears](#no-panel-appears).
4. **A headless session?** Non-interactive runs such as `claude -p` get no panel.
5. **Below the first checkpoint?** Nothing fires until the context passes it: 100K tokens on a
   200K window, 200K on a 1M window, or your own thresholds.
6. **Already muted?** **Not this session** mutes the session; a new session starts unmuted.

A reading can lag one turn, so a checkpoint may show one prompt after the size was crossed.

## A panel went away on its own

That is expected when:

- you answered the same request in Claude Code's chat;
- the agent stopped waiting, or quit;
- Countersign was paused, or quiet time started: with quiet time the request comes back when it
  ends;
- you switched to another app or typed a key the panel has no use for: it steps aside, swallowing
  that one key, and comes back after your next pause;
- a Cursor or Antigravity request went unanswered for 59 minutes: it was handed back to the agent's
  own prompt a minute before the hook's timeout, since a Cursor hook that times out lets the command
  run.

## Two copies of Countersign are installed

Doctor's `copies` line, `countersign setup --cli`, and a notice at the top of Agents in the Settings
window all say so when Countersign is installed more than once, most often with both the curl
installer (`~/.local/bin/countersign` and `~/Applications/Countersign.app`) and Homebrew. Each copy
updates on its own, so after `brew upgrade` the curl copy keeps its old version, and since
`~/.local/bin` usually comes first on your `PATH`, `countersign` in the terminal can run a
different version from the one your agents' hooks run. Both copies work; nothing is broken yet.

Which copy to keep is your call; Countersign never removes one for you. In Settings, click **Show
copies** under the notice. It lists every copy with its version and paths, marks the one your hooks
call, the one running now, the newest and each one that includes the menu-bar app, then asks
**Which one do you want to keep?** with one choice per copy. The newest is selected to start with,
or, when they're on the same version, the one your hooks call; pick another to see its steps
instead.

Below the choice, Settings shows the steps for the copy you picked, each command with its own
**Copy** button. When your hooks already call that copy, there is one step, the command that
removes the others. For example, with the hooks on the curl copy and Homebrew's picked:

```sh
/opt/homebrew/bin/countersign setup --cli --yes
```

points your agents' hooks at Homebrew's copy first, and then

```sh
rm ~/.local/bin/countersign && rm -rf ~/Applications/Countersign.app
```

removes the curl copy. When the copy you pick is a Countersign.app on its own, with no
command-line tool, you remove the others and then open that app and click **Update** on each agent
under **Agents**, so the hooks call it.

Not sure which to keep? **Copy a Prompt for Your Agent** copies a description of every copy, with
the same marks, and asks your agent to explain the options and give you the exact commands without
deleting or changing anything before you say so. Paste it into Claude Code, Codex or any other
agent.

`countersign doctor`'s `copies` line lists every copy and the command that removes each one; it
doesn't pick one to keep. When Settings linked Countersign.app into `~/Applications` for the
Homebrew copy, that copy's command also removes the link, which `brew uninstall` leaves behind. Old
version folders Homebrew keeps are not copies; `brew cleanup` removes them.

### The menu-bar app and the command-line tool are on different versions

The curl installer puts two things on your Mac, `~/.local/bin/countersign` and
`~/Applications/Countersign.app`, and rerunning it with `COUNTERSIGN_APP=0` updates only the
first. When their
versions differ, Doctor's `versions` line and a notice at the top of Agents in Settings say which is
older, with the command that updates it, even when only one copy is installed. When the app is
older:

```sh
curl -fsSL https://raw.githubusercontent.com/Gord1y/countersign/main/install.sh | COUNTERSIGN_APP=1 sh
```

and when the command-line tool is older, which matters more because your agents' hooks run it:

```sh
curl -fsSL https://raw.githubusercontent.com/Gord1y/countersign/main/install.sh | sh
```

## Codex shows no panel

The most common reason is that Codex hasn't trusted Countersign's hook. Codex asks you to trust a
hook it hasn't seen before, and only the terminal `/hooks` can record that trust — the Codex desktop
app shares the same `~/.codex`, but its own `/hooks` can't write the trust record, so trusting there
does nothing. Open a terminal, run `codex`, then `/hooks`, and trust Countersign's hook. Codex's
hooks.json isn't hot-reloaded by a running session
([openai/codex#17636](https://github.com/openai/codex/issues/17636), open), but trusting a hook in
`/hooks` does refresh sessions you already have open
([openai/codex#19882](https://github.com/openai/codex/pull/19882)), so you don't need to restart
them.

An entry setup has since changed — a new path after an upgrade, a second install — is untrusted
again, since Codex keys trust to the exact entry. So is Countersign's entry after another hook is
added before it, or one before it is removed, in Codex's `hooks.json`: Codex keys trust to the
entry's position too, and `countersign doctor` says which of the two happened. Adding a hook after
Countersign's, or for another event, changes nothing.

Countersign reads the trust Codex stores in `~/.codex/config.toml`, so once you trust its hook in the
terminal, the next step clears by itself: the Codex row in Settings, `countersign setup --cli` and
`countersign doctor` stop asking. When Countersign can't tell, for example when `config.toml` holds
something it doesn't understand, the row offers **Mark as done**; click it once you've trusted the
hook. See [setup.md](setup.md#codex-asks-you-to-trust-the-hook).

## Cursor asks again after you approve

That is Cursor, not Countersign: it ignores an approval from a hook and decides by its own run
mode, so in Allowlist mode it asks you itself and you approve twice. **Deny** works right away.
Cursor's staff have confirmed the bug
([forum thread](https://forum.cursor.com/t/support-authoritative-allow-deny-and-ask-verdicts-from-hooks/161342));
once it is fixed, Approve in the panel will be enough, with nothing to change in Countersign. In
Auto-review mode Cursor's AI review decides after you approve, which usually runs the command.

## Antigravity asks again after you approve

That is Antigravity, not Countersign: it ignores an approval from a hook and asks you itself
anyway, so for now you approve twice. **Deny** works right away. It is Antigravity's bug
[google-antigravity/antigravity-cli#1053](https://github.com/google-antigravity/antigravity-cli/issues/1053);
once it is fixed, Approve in the panel will be enough, with nothing to change in Countersign.

## A setting seems to be ignored

- A value under `hosts.<agent>` wins over the top-level one for that agent. In Settings, that
  agent's row under **Agents** lists these values, with a link to open the file.
- A key with a mistake falls back to its default. Doctor lists it under `config`.
- The Settings window saves a slider when you let go of it, and **Snooze presets** when you press
  Return or leave the field. A red line under a row means that change wasn't saved; the row shows
  what the file still holds, and the line says why.
- The menu-bar app started from the Finder or at login doesn't see `XDG_CONFIG_HOME` set only in
  your shell profile, so its Settings window may edit a different file than your hooks read. Run
  `countersign settings` from that shell instead.
- A request already waiting keeps the settings it started with; the next one reads the file again.

## Report a problem

- **A bug:** run `countersign doctor` and open a
  [bug report](https://github.com/Gord1y/countersign/issues/new?template=bug.yml) with its output.
  In the menu-bar app, **Help > Report a Problem…** opens one already filled in with it.
- **A question:** ask in
  [Discussions](https://github.com/Gord1y/countersign/discussions/new?category=q-a).
- **A feature idea:** open a
  [feature request](https://github.com/Gord1y/countersign/issues/new/choose);
  [ROADMAP.md](../ROADMAP.md) lists what's already planned.
- **A security issue:** follow [SECURITY.md](../SECURITY.md) instead of opening a public issue.
- **Anything else:** reach the developer at [gord1y.dev](https://www.gord1y.dev/).
