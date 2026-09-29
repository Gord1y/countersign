# Screenshots

This page explains how the README images are made: `scripts/screenshots/` renders them from
realistic requests through `countersign snapshot` (see "Snapshots" in [panel.md](design/panel.md)),
so nothing appears on screen while they are made. Read it when a UI change needs the images redone,
or when you add a request or change the demo they are rendered from.

```sh
scripts/screenshots/render.sh [out-dir]
swift scripts/screenshots/compose-hero.swift <out-dir>/claude-edit-dark.png docs/images/hero.png
```

`render.sh` builds the package, then renders every request in light and dark as
`<out-dir>/<request>-<appearance>.png`, and the settings window's Agents tab as
`<out-dir>/settings-<appearance>.png`
plus a README crop, `<out-dir>/settings-<appearance>-readme.png` (see "The README settings crop"
below). The default `out-dir` is `.build/screenshots`, which git ignores. `claude-edit` renders with
`--waiting 2` so the waiting chip shows.

## What is in `scripts/screenshots`

| Path | What it is |
| --- | --- |
| `demo/shop-api/` | A small Swift package. The requests point into its files. |
| `demo/claude/projects/shop-api/` | A made-up Claude Code session for the nested-subagent request. |
| `demo/home/` | A demo home directory for the settings render (see "The demo home and the settings render" below). |
| `requests/<host>-<name>.json` | One request each. The prefix before the first `-` is the `--host`. |
| `render.sh` | Substitutes the demo path and renders every request and the settings window, then composes the README screenshot tiles. |
| `compose-hero.swift` | Puts one snapshot on the gradient background used for the README hero. |
| `compose-tile.swift` | Puts one snapshot, scaled down to fit and centred, on the same gradient background as a fixed 1600×1200 opaque JPEG tile (quality 0.92, square corners) for the README's Screenshots table — about 150 KB instead of a 1.3 MB PNG, and JPEG has no transparency for a rounded canvas. |
| `crop-top.swift` | Crops the settings render to the README image (see "The README settings crop" below). |

The requests are an edit, a command, questions, a plan, a Codex patch, a command from a subagent
two levels deep, a Cursor shell command and MCP call, and an Antigravity `run_command`.

## Real files, real diffs

The panel reads the file an edit or patch targets and shows the change inside it, with line
numbers and expandable context. When it cannot read the file, it falls back to the bare change and
says so. The demo exists so every screenshot shows the real rendering:

- An `Edit` request's `old_string` must match `demo/shop-api` byte for byte.
- An `apply_patch` hunk's context lines must match the file they update, and a deleted file must
  exist.
- Cards show paths relative to the request's `cwd`, and the header shows the `cwd`'s last
  component, so the images read `shop-api` and `Sources/Checkout/…`.

## The `{{DEMO}}` placeholder

Requests write the demo's location as `{{DEMO}}`. `render.sh` copies each request to a temporary
directory with `{{DEMO}}` replaced by the absolute path of `scripts/screenshots/demo`, and it
stops if any other `{{…}}` is left.

A path that is only displayed and never read uses a literal `/Users/dev/Projects/shop-api/…`
instead. The plan's `planFilePath` is the one case: the plan view prints it in full, and a
`{{DEMO}}` path would put the checkout's absolute path into the image.

## Claude transcripts and the chat-tracking warning

`snapshot` runs `ChatTrackingHealth.evaluateTranscript` on every Claude request, exactly like the
`hook` path does. A `transcript_path` that does not resolve to a readable file makes the panel show
the chat-tracking warning, the small yellow triangle next to the project name in the header. Every
`claude-*` request's
`transcript_path` must therefore point at a real file under `demo/claude/projects/shop-api/`, and
`render.sh` refuses to render a request whose transcript is missing, after substituting `{{DEMO}}`,
by reading `transcript_path` with `plutil -extract transcript_path raw -o - <file>` and checking the
result exists. A request with no `transcript_path` (every non-Claude request) passes the check
untouched.

## The nested subagent

`claude-subagent.json` comes from agent `a7c41e9d2b05f836e` ("Verify checkout totals", depth 2),
which agent `a3f9c2e1b7d40568e` ("Move discounts to tiered pricing", depth 1) spawned from the
main session. The session folder follows Claude Code's layout: the main transcript
`<session>.jsonl`, and `<session>/subagents/agent-<id>.meta.json` next to `agent-<id>.jsonl`. Each
meta file's `toolUseId` is the id of the `Agent` tool call in its parent's transcript. The request's
`transcript_path` points at the main transcript, so a header that walks the chain finds both
agents.

## Adding a request

Start from the shape of a real payload in `Tests/ApprovalCoreTests/Fixtures`, never from invented
fields. Point file paths into the demo with `{{DEMO}}`, add or change demo files to match, and name
the file `<host>-<name>.json`.

## The demo home and the settings render

`countersign snapshot --settings --home <dir>` (see "Snapshots" in [panel.md](design/panel.md))
roots every host's hook file under `<dir>` instead of the real home, so the settings window can be
rendered against a made-up setup. `demo/home/` holds that made-up setup: each host's hook file
(`.claude/settings.json`, `.codex/hooks.json`, `.cursor/hooks.json`, `.gemini/config/hooks.json`),
already containing a countersign hook entry, plus empty `.gemini/antigravity-cli/`,
`.gemini/antigravity/` and `.gemini/antigravity-ide/` directories so Antigravity reads as
installed. It holds no installed copy of Countersign, neither `.local/bin/countersign`,
`Applications/Countersign.app` nor a `root/` folder, where `--home` looks for `/opt/homebrew`,
`/usr/local` and `/Applications`, so the render never shows the notice about a second copy,
whatever the rendering Mac has installed. Each hook entry's executable path is the placeholder `{{EXECUTABLE}}`, substituted by
`render.sh` the same way `{{DEMO}}` is substituted, but with the absolute path of the `countersign`
binary doing the rendering, resolved past the `.build/debug` symlink exactly as
`Bundle.main.executableURL?.resolvingSymlinksInPath()` resolves it at runtime — a mismatched
resolution makes every host read as needing an update instead of wired.

That substitution is what makes every host row read "Wired" and the header show no pause or quiet
caption: `HostWiring.status` compares each file against what installing again would produce, byte for
byte, and a hook entry already pointing at the exact path the rendering binary resolves to compares
equal. **The settings render must never pass `--show-changes`, and every demo host must stay wired.**
`resolvedExecutable` and the `stablePath` derived from it name the binary taking the snapshot, not
the `--home` directory, and `--home` does not touch them: a host that needed an update, or one whose
"Show changes" was expanded, would render that real path — the checkout's own `.build/debug/countersign`
— into the image.

## The README settings crop

The README's settings image is a crop of the dark settings render, not the full window. The render
shows the Agents group, selected in the sidebar, at the window's default size, so neither the
config path nor the "Ask your coding agent" prompt, both in Advanced, appear in a shared image; the
crop stops just below the Agents group's card, so the image is the header, the
sidebar and the Agents group, with nothing half-shown below the card. `render.sh` writes the full
render as `<out-dir>/settings-<appearance>.png` and the crop as
`<out-dir>/settings-<appearance>-readme.png`, made by
`crop-top.swift <in.png> <height-in-pixels> <out.png>`: it opens no window either, and crops with
`CGImage.cropping(to:)` to the full width and the given height, measured from the top-left corner
of the render. That height is `settings_readme_crop_height`, the one named value at the top of
`render.sh`, in pixels at the render's 2x scale (points × 2; the render is the window's default
size, `SettingsWindowPlacement.defaultContentSize` = 820 x 800 pt = 1640 x 1600 px). It is pinned by
rendering and looking, not computed from the layout, since it has to land just below the Agents
card's bottom border, with the page background showing beneath it and nothing else —
**re-check it, by rendering and looking, whenever the Settings layout changes.** `crop-top.swift`
refuses a height taller than the render, so a layout that gets shorter stops `render.sh` rather
than producing a wrong image.

## The hero image

`compose-hero.swift` uses only CoreGraphics and ImageIO, so it opens no window either. It draws:

- a diagonal gradient from `#241833` through `#8A3B2A` to Countersign's amber `#E6B04A`,
- a soft white radial glow behind the panel,
- the panel clipped to its 18 pt corner radius, with a 40 pt blur shadow,
- margins of 20% of the panel's width at the sides and 14% above and below,
- 24 pt rounded corners on the canvas.

The output is tagged 144 dpi, so it displays at the panel's point size.

## Which render each README image comes from

The images in `docs/images/` are rendered by this tooling. Regenerate them from it after UI changes.

| Image | Source |
| --- | --- |
| `icon.png` | `scripts/app/AppIcon.icns`, exported at 256 px with `sips` |
| `hero.png` | `compose-hero.swift` over `claude-edit-dark.png` |
| `tile-edit.jpg` | `compose-tile.swift` over `claude-edit-dark.png` |
| `tile-command.jpg` | `compose-tile.swift` over `claude-command-dark.png` |
| `tile-questions.jpg` | `compose-tile.swift` over `claude-questions-dark.png` |
| `tile-plan.jpg` | `compose-tile.swift` over `claude-plan-dark.png` |
| `tile-codex.jpg` | `compose-tile.swift` over `codex-patch-dark.png` |
| `tile-cursor.jpg` | `compose-tile.swift` over `cursor-command-dark.png` |
| `tile-antigravity.jpg` | `compose-tile.swift` over `antigravity-command-dark.png` |
| `tile-settings.jpg` | `compose-tile.swift` over `settings-dark-readme.png` |
