# Lime for iOS

A native SwiftUI iPhone app. This is the skeleton (LIME-87): a static Messages list, a chat screen and the dock, styled from the web app's tokens. There is no networking, no accounts and no encryption yet; everything is sample data in memory.

- Minimum iOS 17. Liquid Glass (`glassEffect`) on iOS 26+, `.ultraThinMaterial` plus a hairline below that.
- Swift 6 language mode, iPhone only, portrait and landscape.
- The bundle identifier `com.famkind.lime` is a placeholder until the app is registered with Apple.

## Prerequisites

1. Xcode (opened once, licence accepted, an iOS Simulator runtime installed) and `xcode-select` pointing at it.
2. [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.

## Generate the project

The project is defined in `project.yml`. `Lime.xcodeproj` is generated and gitignored.

```bash
cd ios
./generate.sh
```

## Run it

```bash
open Lime.xcodeproj
```

Pick an iPhone simulator and press Run. Or from the terminal:

```bash
xcodebuild -scheme Lime -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
```

Switch light/dark in the Simulator with Features → Toggle Appearance (or Settings → Developer → Dark Appearance).

## Tests

```bash
xcodebuild test -scheme Lime -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

`LimeTests` covers the sample data, the store and the theme (own bubble colour, 4.5:1 text contrast in light and dark). `LimeUITests` launches the app, opens a chat, sends a message and goes back.

## Layout

```
Lime/App        the @main app, root view, in-memory store
Lime/Theme      colours, typography, the limeGlass() modifier
Lime/Features   Messages, Chat, Dock
Lime/Model      Conversation, Message, Person, SampleData
Lime/Resources  asset catalog (AppIcon, logo, colour sets)
```

## Theme

Colours live in `Lime/Resources/Assets.xcassets` (light / dark) and are read through `Theme`. They come from `public/css/lime.css`, except one:

| Token | Light | Dark |
|---|---|---|
| Canvas | `#F9F8F4` | `#131B17` |
| Own bubble and send arrow (primary) | `#E4F9BE` | `#A3E18A` (the accent) |
| Own bubble ink | `#131B17` | `#131B17` |
| Accent (unread badges, dock badge, Messages "+") | `#A3E18A` | `#A3E18A` |
| Accent ink | `#131B17` | `#131B17` |

**Dark primary is native-only.** The web's dark `--lime-primary-bg` (`#0D2016`) is almost the same as the canvas and disappears, so on iOS the dark own bubble and send arrow use the accent `#A3E18A` (ink 11.4:1; the tests require 4.5:1 and at least 8 OKLab units from the canvas). The web app is frozen, so it keeps its own value; if the web ever changes, align them then. Light values are unchanged.

On iOS 26+ the screens use the system toolbar (back button, swipe back, glass groups) and the soft scroll edge effect top and bottom, as in Apple Messages. On iOS 17-25 they keep custom glass pills, a `TopFade` (a subtle progressive blur and low-opacity canvas veil from the top of the screen to about 10pt under the header buttons) and `SwipeBack`, which re-enables the edge-swipe gesture with the navigation bar hidden.

## Run on your iPhone

1. In Xcode, Settings → Accounts, sign in with your Apple ID (a free Personal Team is enough).
2. On the phone: Settings → Privacy & Security → Developer Mode → on (it restarts the phone).
3. Copy `Local.xcconfig.example` to `Local.xcconfig` (gitignored; never commit it) and put your team id in `DEVELOPMENT_TEAM`. The team id is the `OU=` field of your "Apple Development" certificate, not the id in parentheses in its name. `./generate.sh` keeps it, so you never re-pick the team in Xcode.
4. `./generate.sh`, open `Lime.xcodeproj`, pick your phone and press Run.
5. First launch: Settings → General → VPN & Device Management → your Apple ID → Trust.

A Personal Team build expires after 7 days; press Run again to refresh it. Without `Local.xcconfig` everything still builds for the Simulator.
