# The group call screen (the layout rules, for iOS and Android)

Written for LIME-148 and LIME-148b so Android can match without reading Swift. The iOS code is `GroupCallLayout.swift` (pure functions with
tests), `GroupCallView.swift` and `GroupCallManager.swift`. The rules are the spec; screenshots are in `docs/design/mobile/group-call-*.png`.

## Always true

- **Nothing scrolls.** Every tile fits the visible area at once, at every size, and tiles shrink rather than scroll. (The one exception is
  none today: even the speaker strip fits.)
- **No thin strips.** A tile's shape is between **3:4 and 16:9**; the speaker's large tile between 3:5 and 2:1. The video **aspect-fills** the
  tile (a little crop is fine) and is never squashed.
- **The layout is chosen from the container's size, not the device or the screen** (an iPad window, Split View and a phone on its side all
  work the same way). The container is the area between the header and the controls.
- **My own picture floats** as a small tile (about 30% of the short side, between 96 and 180 dp long side, 3:4 in portrait and 4:3 in
  landscape) in a corner, with a 10 dp margin; dragging it snaps it to the nearest corner. It is not one of the grid's tiles from 3 people up
  (with 2 people it is the floating tile in one-on-one; in a grid of 2 it is a tile).
- Tiles are inside the safe area; the dark background may reach the edges.
- A tile with no picture shows the person's profile photo (initials on their colour if they have none), never black. A tile whose key has
  not arrived says "Connecting securely…" and shows no video. Words and an icon, never colour alone: Muted + crossed microphone, Speaking +
  waveform + a ring, Camera off.

## Shapes (window modes)

Chosen from the container size `W x H`:

| Shape | When |
|---|---|
| **flat** | `H < 280` and `W > 1.8 H` (a phone on its side, a short window) |
| **narrow** | `W < 330` |
| **normal** | otherwise |

## Modes and the default

Two modes, switched by the person (an icon and a word in the header, "Grid" or "Speaker"; the accessibility label is "Layout: Grid" or
"Layout: Speaker"); **the choice is remembered on this device** and wins over the default:

- **Grid**: everyone equal.
- **Speaker**: the person speaking is large, the others are in a strip.

The default when nothing has been chosen, for `n` people in the call including me:

1. `n == 2` -> **Speaker** (this is *one-on-one*: the other person fills the area edge to edge and my picture floats);
2. flat shape and `n >= 3` -> **Speaker** (a grid of tiny tiles is no use in a strip);
3. `n <= 4` -> **Grid**; `n > 4` -> **Speaker**.

## The grid

For `k` tiles (everyone but me from 3 people up) try every `columns x rows` (no empty row), fit the largest allowed-shape tile into each cell
(gap 6 dp), and take the one with the largest tiles, with a mild preference (`(min/max of columns and rows)^0.3`) for a nearly square block over one
long strip. The block is centred and a short last row is centred under the others. 2 tiles: stacked in portrait, side by side in landscape; 4
tiles: 2 x 2 where there is room.

## The speaker layout

Everyone but the speaker and me goes in the strip (up to 8), laid out like the grid inside the strip's own area, so it fits without scrolling.

- **portrait** (`W <= H`): the speaker on top, the strip below; the strip takes 26% of the height for up to 2 others, 32% for up to 4, 38% for more
  (at least 70 dp).
- **landscape and flat** (`W > H`): the speaker on the left, the strip down the right side with the same shares of the width (at least 80 dp).
- **one-on-one** (no others): the speaker fills the area.

**Who is the speaker:** the person speaking now (never me); when nobody else is speaking, the last other person who spoke; before anyone has
spoken, the first other person.

## The controls

One row at the bottom (landscape included): mute, camera (video calls), flip camera, **minimise**, speaker, **leave**. **Leave is always
visible**: the buttons shrink (56, 50, then 44 dp) before anything would scroll. Targets are at least 44 dp. The header has the minimise chevron
(top left, below an iPad window's own window controls), the group's name and the timer, the layout switch and the people count (a list sheet).
Reading order for a screen reader: the header, the tiles (the speaker first), the controls, my own floating picture last.

## Minimising

Minimise opens that group's chat so the person can type while talking. A video call floats in the system's picture-in-picture window (the
speaker, or the speaker's photo when their camera is off or their key is missing; a short hold of 2 s before it moves to a new speaker; the
group's own picture, the same as the chat's avatar, when nobody else is there). A voice call (or a video call that cannot float) shows a slim
**return bar** ("Return to <group> · N in call · timer") on every screen **except that group's own chat**, where the lime call circle in the chat's
header is the way back; the bar is also hidden while the floating window is up. The call circle in a group chat's header is always its own circle
beside the search and more capsule, lime with the call's icon (and no count) while a call is live.

## Not in these rules yet

Screen sharing (LIME-149: a screen share would take the speaker's place), the mini grid when minimised (LIME-150), and the emoji check (LIME-147).
