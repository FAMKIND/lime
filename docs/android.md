# Android

Lime's Android app lives in `android/` (Kotlin + Jetpack Compose, `com.limemessenger.lime`, minSdk 26) and runs LimeCore. This page records the plan, how to run the app, how to check that the shared core still builds for Android, and the logic still owed to the core.

## The plan

Kotlin and Jetpack Compose on top of **LimeCore** (the Rust core, `core/`), reached through UniFFI-generated Kotlin bindings. The core owns the protocol, encryption, the encrypted store and, increasingly, the app's non-UI logic; Compose is views only. The platform adapters, written in Kotlin:

- calls: ConnectionService / Telecom;
- push: FCM;
- mesh messaging: Android BLE;
- media: CameraX and WebRTC;
- keys: the Android Keystore;
- the minimised call window: the system Picture in Picture.

## Running the app

```sh
cd android
./gradlew assembleDebug            # builds liblime_core.so + the Kotlin bindings first (android/build-core.sh), then the APK
./gradlew installDebug             # onto the running emulator or phone
./gradlew connectedDebugAndroidTest
```

- **JDK:** AGP 9 and Gradle 9.9 need a JDK 17–25; this Mac's system JDK is 27. A Temurin 21 sits in `~/.lime/jdk21` and `~/.gradle/gradle.properties` points `org.gradle.java.home` at it (machine-local; not in the repo).
- **SDK:** `android/local.properties` (gitignored; see `local.properties.example`) names the SDK. compileSdk 37 (needed by the current Compose BOM), targetSdk 36, minSdk 26.
- **Emulators:** AVDs `lime-api26` and `lime-api36` (arm64-v8a). `android/tools/emu.sh start <avd>` boots one headless; `emu.sh stop` shuts it down.
- The first build compiles OpenSSL and the core for two ABIs (about 5 minutes); later builds reuse it.
- Skeleton screenshots: `docs/design/android/`.

### Playing with it on staging

1. `android/tools/staging-test-accounts.sh --push` makes (or reuses) the two throwaway accounts `android-a@example.invalid` (Ada) and `android-b@example.invalid` (Ben) and pushes fresh sessions into the debug app on the running emulator. It reads the staging keys in memory only and touches nothing else on staging. `--delete` removes both.
2. `./gradlew installDebug`, open lime, tap **Use a test account** → Ada (a debug-only button; a release build has none, proved by `android/tools/check-release-clean.sh`).
3. In a terminal: `android/tools/partner/run reset` (once per fresh sign-in of Ada: her keys are new and Ben pins the old ones), then `android/tools/partner/run echo`. Ben accepts Ada's first message and answers every message with `Ben here: got "<first 40 characters>"`; he answers a photo with its size and a photo of his own. `run send "<text>"` and `run photo <file>` send Ben's own.
4. `android/tools/connected.sh` runs every instrumented test on API 26 and API 36, one emulator at a time and headless, including the real Ada ↔ Ben exchange. `android/tools/record-demo.sh` films the walk-through into `~/Desktop/lime-android-prototype/`.
5. **Staging allows 10 device registrations per hour per account** (`LIME_RATE_REGISTER_PER_HOUR`); the app registers on every launch, so a day of test runs can use them up ("Busy").

## Checking the core builds for Android

```sh
./core/check-android.sh
```

It builds `liblime_core.so` for arm64-v8a and x86_64 (via `cargo-ndk`, requesting a `cdylib` so `Cargo.toml`'s `crate-type` and the iOS build are unchanged), prints their sizes, generates the Kotlin bindings with `uniffi-bindgen`, and **compiles** them with `kotlinc` against JNA plus a tiny harness (`core/android-check/Main.kt`). It does not run anything: that needs a device or emulator. It exits non-zero on any failure and stops early with a message if the NDK or JDK is missing. Outputs are under `core/target/`.

Tooling it needs: the rustup Android targets (pinned in `core/rust-toolchain.toml`), `cargo-ndk`, `kotlin` (Homebrew), a JDK (Temurin), and the Android NDK with `ANDROID_NDK_HOME` set (command-line tools from `brew install --cask android-commandlinetools`, then `sdkmanager "ndk;<version>"`). Last verified with cargo-ndk 4.1.2, Kotlin 2.4.21, NDK 30.0.16248370.

How it builds on Android:

- **SQLCipher** needs a crypto library. Apple builds use CommonCrypto; Android has none, so `core/Cargo.toml` turns on `rusqlite`'s `bundled-sqlcipher-vendored-openssl` for `target_os = "android"` only, which builds OpenSSL from source. The Apple features are unchanged.
- **vodozemac** and the other crates needed nothing special.
- The Kotlin is generated from a **non-stripped** host build, because the release profile's `strip = true` can drop the metadata UniFFI reads.
- Sizes at the time of writing (release, arm64-v8a / x86_64): about 6.8 MB / 7.5 MB.

## Rule: names exposed through UniFFI

**No UniFFI-exposed type, enum or enum variant may be named `List`, `Map`, `Set`, `String`, `Int` or `Unit` (or `Result`).** A variant named like that becomes a Kotlin nested class that shadows the standard type inside its sealed class, and the generated Kotlin stops compiling (this happened with `Block::List`, renamed `ItemList` in LIME-136). `check-android.sh` catches it.

## Android debt

Logic that lives in Swift today and must move into the core before (or as) Android needs it (LIME-133). Inventory by LIME-293 (2026-11-09); `ios/Lime/` paths, `~lines` = lines that decide something (not the whole file). Order: what an Android skeleton needs first (sign-in, chat list, open chat, send and receive), then the rest. "Needed tonight by" = which of LIME-295 (foundations) / 296 (sign-in) / 297 (chat list) / 298 (chat) must write a Kotlin twin of the rule; "none" = not needed tonight. Names follow the UniFFI rule (no `List`/`Map`/`Set`/`String`/`Int`/`Unit`/`Result` in type names). Core means `core/src/`.

| # | Area | Swift file(s) | ~lines | Core twin? | Proposed move (one commit) | Risk | Needed tonight by |
|---|---|---|---|---|---|---|---|
| 1 | Sign-in: server error to app error, and its words | `Core/Auth/LiveAuthService.swift:187-207`, `Core/Auth/AuthModels.swift:80-117` | 59 | No | `auth::AuthFailure` enum + `auth_failure_for(status, code, message)` + `auth_failure_words(failure)` | low | 296 |
| 2 | Sign-in: the server calls (identify, sign in, codes, reset, refresh, profile parse) | `Core/Auth/LiveAuthService.swift:16-185`, `Core/Auth/AuthService.swift` | 186 | No (core `Transport` exists; no auth client) | `auth::AuthClient` over `Transport`, same endpoints and JSON; Swift `LiveAuthService` becomes a wrapper | med | 296 |
| 3 | Onboarding rules: identifier kind, username and password checks, resend countdown, submit gates | `Features/Onboarding/OnboardingModel.swift:76-127,346-406` | 115 | No (`store/usernames.rs` only stores shared names) | `onboarding::classify_identifier`, `username_error`, `password_strength`, `resend_seconds` | low | 296 |
| 4 | Onboarding step machine (welcome, identifier, code, terms, password, profile per intent: sign up, sign in, reset) | `Features/Onboarding/OnboardingModel.swift:22-345` | 220 | No | `onboarding::OnboardingFlow` (events in, next step + effects out) | med | 296 |
| 5 | Terms re-agreement rule | `Core/Auth/TermsAcceptance.swift` | 29 | No | `onboarding::terms_need_agreement(accepted_version, current)` | low | 296 |
| 6 | Account session phases (launching, signed out, choosing move, signed in), resume, offer-a-move rule | `Core/Auth/AccountSession.swift:9-190` (Keychain part stays) | 300 | Partial (`client/account.rs` keeps account data; not the phases) | `session::SessionMachine` (resume, completed sign-in, start fresh) | high | 296 |
| 7 | Connection problem from any error; offline banner words | `Core/Network/ConnectionProblem.swift` | 62 | Partial (core has `StoreError`) | `ConnectionProblem` enum + `connection_problem_for(error)` + `offline_banner_words(mesh_on)` | low | 296, 297 |
| 8 | Chat list load and sync cycle (queued sends first, stale-token fallback, sync, reload, threads folded into chats) | `App/ConversationStore.swift:498-562,827-872` | 114 | Partial (`list_conversations`, `sync`, `deliver_queued` exist; the order and folding are Swift) | `client::chat_list()` returning entries with thread summaries and unread replies; `SyncCycle` that runs deliver, sync, reload and reports the problem | med | 297, 298 |
| 9 | Unread counts: marked-unread = 1, opening clears both, tab badge = chats unread, thread unread leaves the chat number | `Model/Models.swift:215-218`, `App/ConversationStore.swift:775-792,893-913,940-955` | 60 | Partial (core gives `unread`, `marked_unread`) | `unread_badge(unread, marked_unread)`, `unread_chat_total(entries)`, `mark_chat_read` returns the new numbers | low | 297 |
| 10 | Mute state and durations (row "muted" mark, the Muted filter) | `Core/Notifications/NotificationSettings.swift:118-145,202-215` | 45 | No | `settings::MuteState` (`is_muted(chat, now)`, `mute_until(duration, now)`), stored in core settings | low | 297 |
| 11 | List filters: kind, pinned, muted, label; All or Unread; active count; label list. Calls filters (video, direction, missed) | `Model/ListFilters.swift` | 58 | No | `filters::ChatFilter`, `filter_chats(entries, filter, unread_only, muted)`, `chat_labels(entries)`, `CallFilter` + `filter_calls` | low | 297 (chat filter only) |
| 12 | Chat and person derived fields: group or direct, subtitle, last message, initials, avatar tone from an id | `Model/Models.swift:3-18,178-262,264-270` | 110 | No | `ChatEntry` record built in core (`is_group`, `title`, `subtitle`, `preview`); `avatar_tone(id)`, `initials(name)` | med | 297 |
| 13 | Time words: list time (clock, Yesterday, date), day separators, thread summary, call time label | `Model/MessageFormat.swift`, `Model/Models.swift:157-164`, `Core/Calls/CallGrouping.swift:38-60` | 53 | No | `time::day_bucket(date_ms, now_ms, utc_offset_minutes)` returning Today, Yesterday, Weekday, Date; platform formats the words (locale stays in the UI) | low | 297, 298 |
| 14 | Delivery state: which states are in flight, words, mesh states (waiting, passed, offline) | `Model/Models.swift:20-65` | 46 | Partial (core emits the state names) | `DeliveryState` enum in core with `is_in_flight()` and `status_words()` | low | 298 |
| 15 | Chat rows: day separators, show avatar on first of a run, system lines, collapse 2+ deleted, run ends within 5 minutes | `Model/ChatRows.swift` | 82 | No | `chat::chat_rows(messages, utc_offset_minutes)` returning `ChatRow` records | med | 298 |
| 16 | Chat and thread paging windows (60 first, 60 per page, 200 first for threads, cover an index) | `Model/ChatWindow.swift` | 41 | No | `chat::RowWindow` (`shown`, `hidden`, `grown`, `covering`) with the two presets | low | 298 |
| 17 | Send path: trim, empty refused, deleted person refused, signed-in account always queues, local-only otherwise, deliver if linked; preview send | `App/ConversationStore.swift:764-774,986-1016`, `App/ConversationStore+Forward.swift:46-64` | 50 | Partial (`queue_text`, `send_local_message` exist) | `client::send_text(chat, text, signed_in, linked)` returning `SendOutcome` (queued, refused with reason, empty) | low | 298 |
| 18 | Message action rules: edit and delete-for-everyone for 24 hours on own sent messages | `Model/Models.swift:94-104`, `App/ConversationStore+Actions.swift:24-54` | 40 | No (not found in core) | `message_ops::can_edit(message, now)` and `can_delete_for_everyone(message, now)` | low | 298 |
| 19 | Message text blocks drawn: numbered list markers, block mapping over core `format::parse` | `Features/Chat/MessageText.swift:125-170` | 46 | Yes for parsing (`format.rs`); markers are Swift | `format::numbered_markers(items)` (parse stays the one twin) | low | 298 |
| 20 | Profile context rule: where a profile was opened from decides the shared chat and sender (DM = everyone; group = this person only) | `Features/Profile/ProfileView.swift:5-18`, `App/ConversationStore+Profile.swift:15-47` | 44 | No | `profile::profile_context(user, opened_from)` returning shared chat and sender | low | none |
| 21 | Status and work hours: statuses, manual vs hours, next start and end, caption, quiet-call reason | `Core/Status/StatusPlan.swift:4-144`, `App/ConversationStore+Status.swift` | 167 | Partial (`store/status.rs` `effective_period` for contacts; work hours in `store/calls.rs`) | `status::StatusPlan::make(manual, hours, now_ms, utc_offset)` + `quiet_call_reason`; delete the Swift twin | high (time zones, DST) | none |
| 22 | Call history rules: grouping, outcome keys and lines, missed counting, call back or join, call bubble parse | `Core/Calls/CallGrouping.swift:21-60`, `Core/Calls/CallLog.swift:24-55`, `Model/CallBubble.swift`, `Features/Calls/CallsTab.swift:24-35`, `Core/Calls/CallManager.swift:624-637` | 175 | Partial (`store/calls.rs` keeps history, `call_history_missed_unseen_count`) | `calls::group_calls(records)`, `call_outcome_words`, `call_back_action`, `CallBubble::parse` | med | none |
| 23 | 1:1 call signalling state machine: phases, timeouts, busy, unavailable, glare, breakthrough rule, renegotiation, `lime-ctl` handling, fingerprint | `Core/Calls/CallManager.swift:54-198,245-570,571-660,705-735,759-830` | 560 | Partial (`store/calls.rs` events, `client/calls.rs` sending; no machine) | `calls::CallMachine` (events and timers in, actions out); media, CallKit, PiP stay platform | high | none |
| 24 | Group call decisions: phases, ring or invite, stuck tiles, subject choice, poll interval | `Core/Calls/GroupCallManager.swift:40-60,264-420,425-640,693-760,887-1017` | 400 | Partial (`store/group_calls.rs`, `client/group_calls.rs`) | `group_calls::GroupCallMachine` | high | none |
| 25 | PiP grid plan: grid or speaker view, which people fill the cells | `Core/Calls/PiPGridPlan.swift` | 117 | No | `calls::pip_grid_plan(people, recent, speaker, all_live)` | low | none |
| 26 | Notification policy: show, mute, preview words, shortening, new-arrival detector | `Core/Notifications/NotificationPolicy.swift`, `Core/Notifications/NotificationCoordinator.swift` (decision parts) | 200 | No | `notify::NotificationPolicy` (`presentation`, `content`, `ArrivalDetector`) | med | none |
| 27 | Mesh policy: RSSI gate, who initiates, keep one link, reconnect backoff and storm guard, key-check gate, framing, fragments, reassembly | `Core/Mesh/MeshLinkPolicy.swift`, `Core/Mesh/MeshReconnect.swift`, `Core/Mesh/MeshFraming.swift`, `Core/Mesh/MeshOutboxRunner.swift`, `Core/Mesh/MeshDriver.swift` | 450 | Partial (`mesh.rs`, `mesh/fetch.rs` are the protocol; link policy and framing not found) | `mesh::link_policy`, `mesh::framing` (byte-exact with iOS; test vectors first) | high | none |
| 28 | Media policy: auto-download, keep media, storage guard | `Core/Storage/MediaPolicy.swift`, `App/ConversationStore+Storage.swift` | 110 | Partial (`storage_allows` in `store/storage.rs`) | `storage::media_policy(setting, item, network)` | low | none |
| 29 | Attachment limits and words: size text, summary, too large, GIF checks | `Features/Attachments/AttachmentModels.swift:66-135`, `Features/Attachments/GIFSupport.swift:19-30` | 95 | No | `attachments::limits`, `attachment_summary(items)`, `is_gif(bytes)` | low | none |
| 30 | Mention matching (fold case and accents, limit 30, everyone) | `Features/Chat/Composer/Mentions.swift:4-52` | 50 | Partial (`format::restrict_mentions`, `valid_mention_id`) | `format::mention_matches(query, people, everyone, limit)` | low | none |
| 31 | App lock delay rule | `Core/Security/AppLock.swift:6-20,87` | 25 | No | `security::should_lock(elapsed, delay)` | low | none |
| 32 | Realtime nudge frame interpretation | `Core/Network/RealtimeNudges.swift:111-142` | 35 | No | `transport::interpret_nudge(frame, topic)` | low | none |
| 33 | Other store rules: band links and codes, handover lists, review, band cleanup, report payload, series lookups | `App/ConversationStore+Orgs.swift`, `App/ConversationStore+Handover.swift`, `App/ConversationStore+Review.swift`, `App/ConversationStore+BandCleanup.swift`, `App/ConversationStore+Moderation.swift:49-92`, `App/ConversationStore+Series.swift` | 300 | Mostly (these wrap `core.*` calls; the rules are small) | One commit per file into `client/` modules; band link parse first | low | none |

Total: 33 rows, about 4,450 lines of decision code (of ~59k Swift lines; ~20k are generated bindings, ~30k views).

Not debt: SwiftUI views, layout and animation (including `GroupCallLayout.swift` geometry), `ConversationStore+JamDemo`, `+QA`, `+SiteDemo`, `+SiteJamDemo` and `LimeApp` demo code (DEBUG only), thin adapters to CallKit, PushKit, CoreBluetooth, AVFoundation, WebRTC, LiveKit, Photos and Keychain (`CallKitSystem`, `CallMedia`, `MeshBluetooth`, `StorageKeychain`, `SessionKeychain`, `URLSessionTransport`, `Move*` wrappers over core).

Unsure (not counted above):

- `Features/Settings/FieldEditorModel.swift` (153): profile field validation and about presets; may be rules, may be form state.
- `Features/Chat/Composer/ComposerDocument.swift`, `RichComposer.swift`, `FormattingToolbar.swift` (about 2,300): UIKit attributed text, but the markdown it writes out may hold rules core should own.
- `Features/Jam/CoEdit.swift` (925): drives core `draft*` calls; unclear how much merge or reconcile logic stays in Swift.
- `Core/Move/MovedSettings.swift` (72): which settings keys travel on a move; tied to UserDefaults, the list itself is a rule.
- `Features/Chat/ChatLook.swift` (323) and `Core/Notifications/CustomSounds.swift`: tone-to-colour and contrast rules belong with the shared tokens (DESIGN-28), not necessarily core.
- `Features/Chat/LinkPreviews.swift:9-19` (`firstURL`) and `Features/Jam/*` view models (JamCompose, JamDiscover, JamDrafts, about 3,000): not read line by line; may hold sorting and filtering.

## Lesson carried over from iOS: system windows take explicit data

On iOS, a SwiftUI view inside the system-hosted Picture in Picture window crashed because it read the app's environment, which that window does not have (LIME-135-fix). The Android twin: the views shown in the system PiP window (and any other system-hosted surface, such as a notification or widget) must take explicit data and read nothing from the app's dependency graph, `CompositionLocal`s, view models or singletons that the system window does not provide.
