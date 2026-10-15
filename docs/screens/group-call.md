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

Two modes, switched by the person **in the people sheet** (the sheet the header's pill opens has a "Layout" section at its top, "Grid" and
"Speaker" with the current one checked; the accessibility labels are "Layout: Grid" and "Layout: Speaker", the current one has the value
"Selected"); **the choice is remembered on this device** and wins over the default:

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
visible**: the buttons shrink (56, 50, then 44 dp) before anything would scroll. Targets are at least 44 dp. The header (below an iPad window's own window controls) is
the 1:1 call header's look (LIME-147/112e): **one glass pill** at the top left with up to three of the people's pictures (overlapping), their first
names (they truncate) and **how many are in the call (it never truncates)**, then a ›; **if a person chose the group's name** (the core says so: renamed, or made with a name other than the first-names default) the pill shows that name instead of the first names, and the people sheet's title and the mini player follow the same rule; tapping it opens the people sheet (the layout, then
the people). Under the pill, one line: the timer, a lock, the four emoji of the encryption check (tap: how to compare them; "Waiting for
everyone's keys…" while any key is missing). **Nothing on the right.** Minimise is only in the controls row.
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

## The call mini player (LIME-148c)

A minimised call (group or 1:1) is shown as a capsule, like a podcast player. It replaces the old "Return to call" bars, which covered the header buttons.

- **Shape:** a glass capsule (Liquid Glass where the system has it, a material otherwise, a solid fill with Reduce Transparency), at least 60 dp tall, with the screen's side margins. It never sits at the top and never over a button.
- **Contents:** the call's picture on the left (the group's photo or emoji or the member composite; the person's photo for 1:1); the name in bold, one line, truncating; under it "Video call · 3 in call · 1:01" or "Voice call · …" (1:1 shows just the timer). On the right: **Mute/Unmute** (a mic that fills and takes the accent when muted; the state is also spoken as a value, never colour alone) and **Leave** (a red hang-up circle that leaves at once, with no confirmation). Both targets are at least 44 dp.
- **Tapping** anywhere else on the capsule goes back to the full call screen.
- **Where:** in the bottom inset of every screen: just above the tab bar where there is one, otherwise just above the bottom safe area; in a chat, **just above the composer**. Every screen reserves that space (a bottom inset), so the last row and the composer are never covered.
- **When:** whenever a call is minimised: in the group's own chat too (the call button stays), and while the floating video window is up. Never on the full call screen.
- **Accessibility:** one element "Call with Grade 4 Team, 4 in call, 1 minute 30 seconds. Double-tap to return", then Mute and Leave as separate buttons. With large text the count drops first, then the line truncates; the buttons never go.
