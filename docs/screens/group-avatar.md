# Group pictures (LIME-150 item 11, LIME-152b)

For the Android build. The rule is `GroupAvatarPlan` (`ios/Lime/Features/Messages/GroupAvatarPlan.swift`); the SwiftUI avatar and the PiP's UIKit twin both draw from it. A group with its own photo or emoji shows that; otherwise it shows its members **and you** as overlapping circles inside one avatar of side `S`, others first, you last.

Every circle has a thin outline ring in the screen's background colour (width `max(1.2, 0.035 · S)`), so a face reads where circles overlap; later circles are drawn on top.

| People in all | What is drawn | Diameter | Centres (offsets from the middle, in units of `S`; y is down) |
|---|---|---|---|
| 1 (just you) | you, one circle | `1.0 · S` | (0, 0) |
| 2 (you and one other) | you behind, the other in front | `0.62 · S` | you (−0.17, +0.10), the other (+0.17, −0.10) |
| 3 | a triangle: the two others, then you | `0.50 · S` | top (0, −0.25), bottom left (−0.215, +0.145), bottom right (+0.215, +0.145) |
| 4 | a circle of circles: the three others, then you | `0.44 · S` | top (0, −0.26), right (+0.26, 0), bottom (0, +0.26), left (−0.26, 0) |
| 5 or more | the first three others and a "+N" (N counts you, so N = people − 3) | `0.44 · S` | the four positions above; the "+N" is the fourth |

The "+N" circle is a neutral surface with the number centred (`0.38 ·` its diameter).
