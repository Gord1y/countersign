# Roadmap

Ideas Countersign might grow into, grouped by theme. No dates and no promises: within a theme,
"Next" is closer to being picked up than "Later" or "Watching", not a schedule. Bugs and gaps get
fixed as they're found, not listed here. Have an idea of your own? Open a [feature
request](https://github.com/Gord1y/countersign/issues/new/choose).

## More agent hosts

### Next

Hosts whose hook fires only when they're about to show their own approval prompt, the same shape
Claude Code's `PermissionRequest` already is:

- JetBrains Junie CLI
- Qwen Code
- Tencent CodeBuddy Code

### Later

Hosts whose hook fires before every tool call, like Cursor's, so Countersign first needs a rule
for which calls deserve a panel and which get skipped:

- GitHub Copilot CLI
- Factory Droid
- Crush
- Kiro
- Cline
- Amp
- Augment (Auggie)

### Watching

- OpenCode — moves forward if its `permission.ask` plugin hook gets fixed.
- Zed — moves forward if its agent gains hooks at all.
- Z.ai ZCode — it only went open source days ago; watching until its hook contract settles.
- Devin CLI — moves forward once its permission hook is confirmed against a real payload.
- Kimi Code — moves forward once its `PermissionRequest` hook can actually decide, not just
  observe.
- cursor-agent, Cursor's own CLI — it reads the same `hooks.json` Cursor does, but that hasn't
  been checked yet.

DeepSeek, Qwen, Kimi, GLM and MiniMax models already work today, because every one of those
vendors documents running its model through Claude Code, and Countersign hooks into Claude Code,
not the model behind it.

## Platforms and distribution

### Later

- macOS 13 Ventura. Claude Code, Codex and Antigravity already run there. Countersign needs macOS
  14 for the Observation framework, a few SwiftUI modifiers and the cooperative activation calls
  its focus guard uses to hand focus back to your app. Each has an older equivalent, but the guard
  was designed and measured under macOS 14's activation rules, so it needs testing on a real macOS
  13 Mac, which GitHub's hosted runners no longer offer. Launch at Login's `SMAppService` already
  works on 13. macOS 12 would also mean rebuilding Launch at Login on the older login-item APIs,
  and Claude Code doesn't support it.
- Windows as a native app, sharing the same design docs and test fixtures, starting with a spike
  on showing a focused panel without activating the app.
- Linux, both X11 and Wayland.
- A WSL bridge, so an agent running inside WSL can still raise a native panel.
- Developer ID signing and notarization, so Gatekeeper stops warning on a fresh install.
- A Homebrew cask that installs Countersign.app straight into /Applications, once the app is
  signed and notarized.
- winget and Scoop packages, once Countersign runs on Windows.

## Panel and behaviour

### Later

- Detecting "answered in the host" for Cursor, from its agent transcripts, and for Codex, if it
  ever gains a session registry.
- Context checkpoints for Codex, Cursor and Antigravity, once they expose a transcript with token
  counts.
- Touch ID confirmation for risky commands.
- Editing a command before approving it, on hosts that accept updated input back.
- Approvals from a phone or an Apple Watch.

### Watching

- Approve and **Always allow** that Cursor and Antigravity honor. Both ignore an approval from a
  hook today and ask again (Cursor's open bug ticket; Antigravity's
  [antigravity-cli#1053](https://github.com/google-antigravity/antigravity-cli/issues/1053)), so
  their panels offer no Always allow. Moves forward when either fixes it. For Cursor, Always allow
  could instead write the command into Cursor's own allowlist, but a `terminalAllowlist` in
  `~/.cursor/permissions.json` replaces the in-app list and locks it, so that waits for a cleaner
  way in.
- A haptic cue. macOS plays haptics only on a Force Touch trackpad during a touch, so a panel
  appearing on its own cannot trigger one.

## Quality

### Later

- Localization through translation catalogs.
