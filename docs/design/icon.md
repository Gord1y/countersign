# The app icon

This note records what `Countersign.app`'s icon is and how it was drawn: a cream fountain-pen nib
signing in amber ink, `#E6B04A`, on a warm charcoal tile, with a simplified drawing for the images
of 32 px and below. The panel's header draws the same mark in code. Read it when you replace or
touch up the icon or the panel's mark, or wonder why they are amber.

`scripts/app/AppIcon.icns` is the icon's source. It is committed as it is, no script generates it,
and changing the icon means replacing that file and redrawing the panel's copy of the mark (see
"The mark in the panel header" below). `scripts/build-app.sh` copies the file into
`Contents/Resources`, and `CFBundleIconFile` `AppIcon` in `scripts/app/Info.plist` points the
bundle at it, so neither a local build nor a release build draws anything.

## The grid

Everything is drawn in a 1024-unit design square and scaled to the pixel size of each image. The
tile is the body of the macOS app icon template: 824 by 824 at an inset of 100 on every side, which
leaves room for the drop shadow below it. Its corners are a continuous rounded rectangle, the
"squircle" of macOS icons, with a radius of 0.2237 of the side (about 184) and a corner smoothing
of 0.6. With smoothing, each corner is a shorter circular arc joined to the straight edges by two
cubic curves that reach 1.6 times the radius along each edge, so the curvature ramps up instead of
starting abruptly where a plain rounded rectangle's arc meets the edge.

The tile is a vertical gradient of warm charcoal, `#4C4642` at the top to `#282421` at the bottom,
with a faint white glow at the top, a 10-unit rim that is lighter at the top edge and darker at the
bottom, and a soft drop shadow.

## The artwork

A cream fountain-pen nib (`#F4EFE8`) writes a signature in the accent color. Above it, a faint
gray scribble (white at 34%) is the signature already on the page, so the accent stroke is the
second one: the countersignature. The nib has a slit and a breather hole in `#1E1B19`, its right
half is 13% darker, and it casts its own shadow onto the tile.

## Stroke weight below 128 px

Every stroke width (both signatures, the slit and the breather hole's radius) is multiplied by
`1 + 0.18 × log2(128 / pixels)` below 128 px: 1.18 at 64 px, 1.36 at 32 px and 1.54 at 16 px.
Scaled down with no boost, the 24-unit first scribble would be 0.375 px wide at 16 px and the slit
0.2 px, which anti-aliasing turns into a faint smear. The boost itself is continuous; the one
deliberate step between neighboring sizes is the switch to the simplified art below.

## Small sizes: 32 px and below

The `.icns` holds ten images, and the three of 32 px or smaller carry the simplified art:

| Image | Pixels | Art |
| --- | --- | --- |
| `icon_16x16` | 16 | simplified |
| `icon_16x16@2x` | 32 | simplified |
| `icon_32x32` | 32 | simplified |
| `icon_32x32@2x` | 64 | full |
| `icon_128x128` | 128 | full |
| `icon_128x128@2x` | 256 | full |
| `icon_256x256` | 256 | full |
| `icon_256x256@2x` | 512 | full |
| `icon_512x512` | 512 | full |
| `icon_512x512@2x` | 1024 | full |

The rule is about pixels, not points, because macOS picks a representation by the pixels it needs:
a 16 pt icon on a Retina display draws the 32 px image. From 64 px up, the full art is used; at
64 px the first scribble is still about 1.8 px wide and reads as a faint line.

At 32 px the full art breaks down. The first scribble is about 1 px of 34% white, which reads as
noise rather than as a signature, and the two peaks of the accent signature sit about 2.75 px apart
under a stroke nearly 2 px wide, so they merge into a blob. The simplified art:

- drops the faint first scribble;
- draws the accent signature as one taller arch with a rising tail into the nib, instead of two
  peaks, at 68 units instead of 44 before the boost: about 3.2 px wide at 32 px and 1.8 px at 16 px;
- enlarges the pen group, stroke and nib together, by 1.12 around `(531, 502)`, the center of the
  group without the scribble, so it stays centered on the tile and uses the room the scribble
  leaves, while the stroke's start still clears the tile's rounded corner;
- widens the slit from 14 to 20 units and the breather hole's radius from 26 to 28, both before
  the boost.

At 16 px the slit and the breather hole are under 2 px and blend into one gray dot on the cream
nib. That is as far as this composition goes at 16 px; the image only appears on displays that are
not Retina.

## The mark in the panel header

Every panel's header starts with this mark at 20 × 20 pt, drawn by `CountersignMark` in
`Sources/countersign/CountersignMark.swift`. Why the panel carries Countersign's mark rather than
anything of the agent's is in "Countersign's mark and one accent" in [panel.md](panel.md). It is
drawn in code, not loaded from the `.icns`: the `hook` path runs as one binary copied to
`~/.local/bin`, with no bundle and no resources, so everything a panel shows is compiled in.

`CountersignMark` is a SwiftUI `Canvas` ported from the renderer that drew the `.icns`, which is no
longer in the repository (`git show 22faef2^:scripts/icon/render-icon.swift` prints it). It keeps
the renderer's design square, colors, tile gradient, top glow and rim, the simplified art's
signature points and stroke width, the nib's outline, shading, slit and breather hole, the pen
group's 1.12 enlargement around `(531, 502)`, the nib's drop shadow, and the stroke boost below
128 px. Three things differ:

- **The tile fills the frame.** The 824-unit tile spans the whole 20 pt, without the 100-unit
  margin around it in the `.icns` and the tile's drop shadow that margin holds. The margin is room
  for the Dock's shadow; in the header it would only shrink the tile to about 16 pt, and a tile
  that fills its frame sits flush with the header's 20 pt padding.
- **The corner is SwiftUI's.** The tile is `RoundedRectangle(cornerRadius:style: .continuous)`
  with the renderer's radius, 0.2237 of the side, rather than the renderer's own smoothed-corner
  construction. Both approximate the continuous corner of macOS icons, and at 20 pt they differ by
  less than a pixel.
- **It always draws the simplified art.** The 20 pt tile is 40 px on a Retina display, the size
  of the tile in a 50 px icon image, where the `.icns` rule above would pick the full art. There
  the full art's first scribble would be about 1.5 px of 34% white and the accent signature's two
  peaks about 4 px apart under a 2.7 px stroke, both at the edge of legibility, while the
  simplified art was drawn for exactly this range.

The boost follows the pixels as in the renderer: `CountersignMark` reads the environment's
`displayScale`, converts the tile's pixel width to the equivalent icon image size (× 1024 / 824)
and applies `1 + 0.18 × log2(128 / pixels)`, 1.25 on a Retina display and 1.43 on one that is not.

## The accent: `#E6B04A`

The signature is amber ink, `#E6B04A`, for three reasons. The same amber is the panel's default
accent (see "Countersign's mark and one accent" in [panel.md](panel.md)), so the same reasons hold
there. A person can pick another accent in Settings; the mark in the panel's header keeps its amber
ink even then (`CountersignMark.signatureInk`), since it is this icon and the icon does not change.

- **It is not an agent's color.** An icon in Claude's terracotta `#D97757` or Codex's green
  `#10A37F` would read as that agent's app, and the terracotta is the obvious warm pick to avoid.
  Amber's hue is about 39°, well clear of the terracotta's 15°.
- **It has the most contrast on the tile.** Three candidates were rendered side by side: amber,
  vermilion `#E2433A` and violet `#AB7AE8`. Against the tile under the stroke, about `#342F2C`,
  amber's contrast ratio is about 6.7:1, violet's 4.2:1 and vermilion's 3.2:1, so amber stays the
  most legible at 16 and 32 px.
- **It is not red.** Red is the panel's Deny: both "Deny" buttons in `PermissionView` (the one
  that opens the reason step and the one that sends it) use `DestructiveButtonStyle`, which is
  red. An approval tool's icon should not lead with the color of refusing.

## Known limit

The dark tile has little contrast against a dark background at 16 and 32 px, such as a Finder list
in dark mode. Only the lighter rim along its top edge separates it from the background. That comes
from the warm charcoal tile itself, not from the accent. The panel's header in dark appearance is
such a background: the tile's lower half is close to the header's own gray, so the mark's outline
fades toward the bottom, and the cream nib and the amber stroke carry it.
