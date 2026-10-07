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

## Chatting (LIME-95)

- **New Message** (the "+" button, or the card on an empty Messages): a sheet with a glass ✕ and, in a card, **Find by Username**, **Find by Email** and a dimmed **New Group** ("Coming soon"). Below it are **the teachers you already message** (accepted one-to-one chats), A–Z with an index rail. A floating glass search field at the bottom ("Name, username or email") filters the list as you type; pressing search on a whole username or email does the exact server lookup and shows the teacher as a row (tap to message; there is no separate button). Find by Username / Email are pushed screens (‹, a centred title, **Next** top right, dimmed until the field is valid). Nothing is listed or partly matched by the server.
- A message you send shows **Sending…**, then **Sent** once the server accepted it (a failure says "Not sent. Tap to retry"). It is end-to-end encrypted (LimeCore, Olm); the server cannot read it.
- **Receiving:** while the app is open, a private Realtime channel nudges the phone the moment something arrives and it fetches its mailbox. It also fetches when the app comes to the front and on pull-to-refresh. (There is no push yet, so a closed app only catches up when opened.)
- **Requests:** a message from someone you have not chatted with waits in a **Requests** row at the top of Messages. Open it to read, then **Accept** (it moves into Messages and you can reply) or **Block** (it disappears and that person's new messages are not shown on this phone).
- **Debug demo:** the launch argument `-lime-demo-chat` (with `-lime-skip-sign-in`) shows made-up conversations in memory (a request, a chat with a message still sending); the UI tests and screenshots use it.

## Notifications (LIME-102, stage 1: no push yet)

Everything is decided on this phone, from messages decrypted on this phone; no server sees what an alert says.

- **While Lime is open:** a message in *another* chat shows a glass banner at the top (tap to open the chat or thread; it goes by itself, or swipe up) and plays the system message sound (which follows the silent switch). In the chat or thread you are looking at, a soft haptic tick only.
- **Just after leaving Lime** (iOS lets the app run for a short time): the listener keeps going, and a message that arrives becomes a **local notification** (the name and message by default, grouped by chat; a reply says "Replied in a thread"; tapping opens the chat or thread). The icon badge is the number of chats with something unread. When iOS ends that time, nothing arrives until Lime is opened again. **APNs and a notification service extension are stage 2** (they need the paid Apple account); until then a closed app only catches up when opened.
- **Settings → Notifications:** on or off; Preview (**Name and message** / **Name only** / **No preview**); Sound (**Default** / **None**); muted chats (each can be unmuted). A chat's **⋯** menu mutes it for 1 hour, 8 hours, 1 week or always (a bell with a slash then shows on its row). A message request never shows its words.
- **Permission:** a short explainer (why, then "Turn on notifications" or "Not now") comes up once after signing in; the system's own prompt follows only from the button. "Not now" is respected: Settings → Notifications offers it again, and says so when iOS Settings has it off.
- **The chime** is not bundled yet (nothing is synthesised). `Lime/Resources/Sounds/README.md` says exactly how to add `lime-chime.caf` and the one-case change that makes it an option and the default.
- Code: `Lime/Core/Notifications/` (settings, the pure rules in `NotificationPolicy`, the coordinator and the iOS pieces); the arrivals are spotted in `ConversationStore.reload`. Debug launch arguments: `-lime-notif-denied`, `-lime-notif-undetermined` (the default in demo mode is "allowed"), `-lime-demo-screen notif-banner`, `-lime-demo-screen settings/notifications`.

## Checks

- `./ios/check-warnings.sh`: builds everything (app and both test targets) **from clean**, for a **simulator and a device** destination (unsigned), and fails on **any** warning in Lime's own sources (not the generated UniFFI file). An incremental `xcodebuild` only prints warnings for files it recompiled, so use this, not a quick build, to say "no warnings".
- `./ios/run-e2e-local.sh`: the real app code against the local stack, including two phones chatting live (the Realtime nudge), accepting, restarting and blocking.
- `./ios/run-e2e-staging.sh`: the same two-phone conversation against staging with two throwaway accounts made and deleted through the admin API (no email, no inbox). The service key stays in that process's memory.

## When something goes wrong (LIME-95-fix)

- Messages says **why** Lime cannot reach the server, in true words: "Your session has ended. Please sign in again." (with a **Sign in** button; the chats and keys stay on the phone, so signing in again as the same person loses nothing), "You're offline", "Too many requests", or "Lime's server had a problem". "Check your connection" is only for a real connection failure. Debug builds log each request's method, path and HTTP status (no query, body or token) under the `app.lime` / `network` category in Console.app.
- A phone that signs in with no keys (after signing out, or a new phone) **replaces the account's keys**; a contact is asked to **Accept new key** in the chat before messages move again, and a message that was waiting for the old phone says **Not delivered. Tap to resend**. See `docs/api-v2.md` section 11.
- Avatar colours come from the user id alone (`AvatarTone`), the same everywhere and on every phone.
- `-lime-demo-screen key-change` / `session-ended` open those states in the in-memory demo.

## Search (LIME-99)

- **Messages:** the magnifier in the header opens search: one field, then **Chats** (a name or title that matches) and **Messages** (the words in context, matched words in bold). Matching is by word prefix and ignores case and accents ("cafe" finds "Café"). Tap a message to open its chat scrolled to it, with the message outlined for a moment.
- **In a chat:** the magnifier in the chat header opens a find bar: "3 of 12" with up (older) and down (newer) arrows and Done. It starts at the newest match.
- **It never leaves the phone.** The search runs in LimeCore over an FTS5 index inside the encrypted database; no search function takes a network transport, and a test checks that searching makes no request. The screen says so.
- `-lime-demo-screen search | search-name | chat-focus | chat-find` open these states in the in-memory demo.

## Formatting (LIME-100)

- **Composer (design 04):** the text above, and under it `+`, emoji and **Aa** on the left, mic or send on the right. Return is a new line; the arrow sends. You see bold, italic and so on as you type (no asterisks).
- **The formatting toolbar** is a floating glass capsule above the keyboard: **B**, *I*, U, ~~S~~, link, code, bulleted list, numbered list, each shown pressed when it is on for the caret or selection, with a round **✕** at the right end. It scrolls sideways when it does not fit. It appears **whenever text is selected**, and when you tap **Aa** (it then stays until ✕ or send). Code with several lines selected makes a code block; with one word it is inline code. Return in a list starts the next item; Return on an empty item ends the list.
- **Link:** the toolbar's link button opens a sheet for the address (and the words to show, when nothing is selected). Only http, https and mailto links are accepted.
- **Bubbles** draw the formatting natively; a link that is not https asks before it opens. See `docs/message-format.md`.
- `-lime-demo-screen format | compose` open a chat of formatted messages, and the composer with the toolbar up, in the in-memory demo.

## Reply threads (LIME-101)

- **Long-press a message, Reply in thread.** The message shows "N replies · Last reply <time>" with up to three replier avatars (and a dot when something is new); tap it to open the thread. Replies are not in the main chat.
- **The thread screen** (a normal navigation push): the message at the top, then its replies, then its own composer with formatting. New replies arrive live. A search hit inside a thread opens the thread on that reply.
- **Links** are green (a token per bubble surface, each at least 4.5:1 on its surface) and underlined, and show pressed when tapped; `__underline__` keeps the text colour with a plain underline. A link that is not https asks before opening.
- `-lime-demo-screen thread | thread-open | links` open these in the in-memory demo.
