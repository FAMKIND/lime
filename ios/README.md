# Lime for iOS

A native SwiftUI iPhone app. This is the skeleton (LIME-87): a static Messages list, a chat screen and the dock, styled from the web app's tokens. There is no networking, no accounts and no encryption yet; everything is sample data in memory.

- Minimum iOS 17. Liquid Glass (`glassEffect`) on iOS 26+, `.ultraThinMaterial` plus a hairline below that.
- Swift 6 language mode, iPhone only, portrait and landscape.
- The bundle identifier `com.famkind.lime` is a placeholder until the app is registered with Apple.

## Prerequisites

1. Xcode (opened once, licence accepted, an iOS Simulator runtime installed) and `xcode-select` pointing at it.
2. [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
3. Rust, for LimeCore (`brew install rustup && rustup-init -y --no-modify-path`). `./generate.sh` now builds `../core` first (the first run takes a couple of minutes) and fails with a clear message if Rust is missing. See [`../core/README.md`](../core/README.md).

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
Lime/Core       generated Swift bindings for LimeCore (gitignored)
Frameworks      LimeCoreFFI.xcframework (gitignored)
```

## Theme

Colours live in `Lime/Resources/Assets.xcassets` (light / dark) and are read through `Theme`. They come from `public/css/lime.css`, except one:

| Token | Light | Dark |
|---|---|---|
| Canvas | `#F9F8F4` | `#131B17` |
| Own bubble and send arrow (primary) | `#E4F9BE` | `#8ECF73` (the accent, about 6.7% dimmer) |
| Own bubble ink | `#131B17` | `#131B17` |
| Accent (unread badges, dock badge, Messages "+") | `#A3E18A` | `#A3E18A` |
| Accent ink | `#131B17` | `#131B17` |

**Dark primary is native-only.** The web's dark `--lime-primary-bg` (`#0D2016`) is almost the same as the canvas and disappears, so on iOS the dark own bubble and send arrow use `#8ECF73`, the same hue and chroma as the accent `#A3E18A` at about 6.7% lower OKLab lightness (ink 9.5:1; the tests require 4.5:1 and at least 8 OKLab units from the canvas). The badges and the Messages "+" keep `#A3E18A` in both modes. The web app is frozen, so it keeps its own value; if the web ever changes, align them then. Light values are unchanged.

On iOS 26+ the screens use the system toolbar (back button, swipe back, glass groups) and the soft scroll edge effect top and bottom, as in Apple Messages. On iOS 17-25 they keep custom glass pills, a `TopFade` (a subtle progressive blur and low-opacity canvas veil from the top of the screen to about 10pt under the header buttons) and `SwipeBack`, which re-enables the edge-swipe gesture with the navigation bar hidden.

## Run on your iPhone

1. In Xcode, Settings → Accounts, sign in with your Apple ID (a free Personal Team is enough).
2. On the phone: Settings → Privacy & Security → Developer Mode → on (it restarts the phone).
3. Copy `Local.xcconfig.example` to `Local.xcconfig` (gitignored; never commit it) and put your team id in `DEVELOPMENT_TEAM`. The team id is the `OU=` field of your "Apple Development" certificate, not the id in parentheses in its name. `./generate.sh` keeps it, so you never re-pick the team in Xcode.
4. `./generate.sh`, open `Lime.xcodeproj`, pick your phone and press Run.
5. First launch: Settings → General → VPN & Device Management → your Apple ID → Trust.

A Personal Team build expires after 7 days; press Run again to refresh it. Without `Local.xcconfig` everything still builds for the Simulator.

## Storage

The app reads and writes through LimeCore's encrypted local store (SQLCipher). On first launch it generates a random 32-byte key and keeps it in the Keychain (`AfterFirstUnlockThisDeviceOnly`, so it never goes to an iCloud backup). The database is `Application Support/Lime/lime.db`, with file protection `completeUntilFirstUserAuthentication`. The made-up sample conversations are seeded into an empty database; messages you send persist across launches. Every store call runs off the main thread. Launch with `-lime-reset-store` to start from a fresh sample database (the UI tests do; **Debug builds only**, a Release build ignores it). Long-press the logo for About Lime, which shows "Encryption self-test" and "Storage: encrypted".

### Backups and an unopenable store

The database is **never backed up**: the folder and every database file are marked `isExcludedFromBackup` on each launch, because a restored phone would get the file but not the this-device-only Keychain key. History is meant to come back through Lime's own recovery-key backup and device linking (later briefs), not iCloud.

If the store cannot be opened (the Keychain key is missing or wrong, or the file is damaged), the old file is moved aside to `lime-<ISO time>.unreadable.db` (the newest two are kept), a new key and a fresh store are made, and Messages shows a one-time notice. A first launch (no key, no database) is not an error and shows nothing. Debug-only test hooks: `-lime-test-corrupt-key` and `-lime-test-delete-key`.

`project.yml` sets `xcodeVersion: "2700"` and `STRING_CATALOG_GENERATE_SYMBOLS: YES`, so Xcode 27 does not offer "Update to recommended settings" (which `./generate.sh` would overwrite).

## Network (LimeCore's transport)

LimeCore owns the protocol and asks the platform to make the HTTPS calls: `Lime/Core/Network/URLSessionTransport.swift` implements its `Transport` callback with `URLSession` (blocking, called from a background task; it adds the project URL and the public `apikey`). Nothing in the app calls it yet: sign-in and the visible phone-to-phone chat are the next brief. Debug builds show a "Developer: staging" row in About Lime ("Not connected").

## Signing up

The app opens at a welcome screen, then one question per screen: your email or username, a confirmation ("Is this correct?"), then either **sign-up** (an emailed 6-digit code, a password of at least 10 characters, your name with an optional username and school) or **sign-in** (your password, then a new emailed code every time a device signs in). "Forgot password?" asks for a code and a new password. A new account's Messages is empty ("No chats yet"). **Sign out** is in About Lime (long-press the logo); it asks first and then removes the tokens and the local store from this phone. Phone numbers are not supported yet and say so.

The app talks to the backend named in `supabase/.staging.public.env` (written by `supabase/deploy-staging.sh`; `./generate.sh` reads it, so run `./generate.sh` after deploying). To sign up on staging the project needs a real email sender: see `supabase/README.md`.

Debug builds only (launch arguments): `-lime-skip-sign-in` (signed in with no backend), `-lime-load-sample-chats` (the made-up chats; also a "Load sample chats" row in About), `-lime-fake-auth` (a stand-in backend: any email starting with "new" is a new account, the code is `123456`, the password `correct horse battery`), `-lime-reset-session`, `-lime-onboarding-screen <name>` (open one screen, for screenshots), and `-lime-api-url` / `-lime-api-key` (point at another backend, for example the local stack). `./ios/run-e2e-local.sh` runs the real app code (sign-up, both steps, the device registering through LimeCore, sign-out, sign-in by username) against the local Supabase stack.
