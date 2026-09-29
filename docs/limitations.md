# Limitations

What Countersign can't do today, and why, agent by agent. Read it before you rely on Countersign
for something specific, or when it behaves differently from what you expected and
[troubleshooting.md](troubleshooting.md) doesn't explain it.

## Every agent

- Countersign cannot tell which chat tab you are looking at. The idle rule and the fast "answered
  in chat" detection are what keep it out of the way for the chat you are reading.

## Claude Code

- Knowing that a prompt was answered in the chat relies on Claude Code's session registry and
  transcript, which are undocumented internals (verified against Claude Code 2.1.278). If a future
  release changes them, the panel still works; it just stays up until you close it.
- Two prompts pending in the same Claude session share one status, so if you answer one in the
  chat, the other's panel only notices once its tool finishes.
- Context checkpoints are Claude Code only; Codex, Cursor and Antigravity have none.
- A context reading can lag one turn, because Claude Code writes the transcript asynchronously,
  and it is an estimate from the token counts in that transcript: a nudge, not a meter.
- The panel cannot run `/compact` or `/clear`. It steers Claude with a note, and Claude's reply
  tells you what to run.
- A checkpoint prints no line in the terminal: Claude Code never shows the messages of a hook that
  runs in the background.

## Codex

- A Codex prompt holds its Codex turn while it waits in the queue, because Codex asks hooks before
  showing its own prompt. The frontmost handoff and "Answer in chat" keep that short.
- Codex supports only allow and deny: it has no `AskUserQuestion` or plan-approval hook to answer.
- A Codex request is never noticed as answered in the chat.

## Cursor

- Cursor is asked only about shell commands it runs outside its sandbox and about MCP tool calls;
  file edits and sandboxed commands follow Cursor's own settings.
- Cursor's hooks cover only shell commands and MCP tool calls, so its own questions and its file
  edits never reach Countersign.
- A Cursor request is never noticed as answered elsewhere.
- The MCP request shape was captured from a remote MCP server; a local (stdio) server's has not
  been captured yet, so that case follows Cursor's documentation.

## Antigravity

- Antigravity can't yet take an approval from a hook: it ignores "allow" and asks you itself
  anyway ([google-antigravity/antigravity-cli#1053](https://github.com/google-antigravity/antigravity-cli/issues/1053)).
  So for now **Approve** in the panel is followed by Antigravity's own prompt, and you approve
  twice; **Deny** works right away. Once Google fixes it, Approve will be enough, with nothing to
  change in Countersign.
- Antigravity is asked only about commands and MCP tool calls, and a request is never noticed as
  answered elsewhere.
- Only the `agy` CLI was tried by hand; the Antigravity app and IDE read the same hooks file but
  have not been exercised.
