# TEND-ANDROID.md

The record for tend-Android (branch `android`). One `## LIME-29x` per brief. PLOT.md and TEND.md are never edited here.

## LIME-293 — the Android debt inventory (docs/android.md)

Landed: `docs/android.md` "Android debt" is now a 33-row table (about 4,450 lines of decision code in Swift, out of about 59k Swift lines: about 20k generated, about 30k views), with a "Needed tonight by" column. Read-only otherwise; no Swift or Rust touched. `cargo test` not re-run for 293 (nothing in core changed; it runs at the end of every brief's green check).

**Kotlin twins the chain needs (Swift files to copy exactly):**
- **296 (sign-in), rows 1–7:** `Core/Auth/LiveAuthService.swift` (incl. `error(for:)` 187–207), `AuthModels.swift` (`AuthError`, 80–117), `AuthService.swift`, `Features/Onboarding/OnboardingModel.swift` (22–406), `TermsAcceptance.swift`, `AccountSession.swift` (9–190), `Core/Network/ConnectionProblem.swift`.
- **297 (chat list), rows 7–13:** `ConnectionProblem.swift`; `App/ConversationStore.swift` (498–562 sync+deliver, 827–872 reload, unread 775–792, 893–913, 940–955); `Model/Models.swift` (`Conversation`/`Person`, `AvatarTone`, unread props); `NotificationSettings.swift` (`isMuted`, `MuteDuration`); `Model/ListFilters.swift` (`ChatFilter`); `Model/MessageFormat.swift` (`listTime`).
- **298 (chat), rows 8, 13–19:** `Model/ChatRows.swift`, `ChatWindow.swift`; `Models.swift` (`DeliveryState` 20–65, `canEdit`/`canDeleteForEveryone`); `MessageFormat.swift` (`day`, `clock`); `ConversationStore.swift` (`sendNow`, `resend`); `+Forward`, `+Actions`; `Features/Chat/MessageText.swift` (`MessageRender`). Parsing is already core `format.rs`.
- 295: none on its own. None for rows 20–33 tonight.

For plot:
- Rows: 33. The six known items are rows 9, 11, 20, 21, 22, 23; group-call decisions (row 24) are a seventh.
- Core twin status: no row has a full twin; core stores the data (`store/calls.rs`, `status.rs`, `storage.rs`, `format.rs`) but not the rules.
- Riskiest moves: (1) call signalling, rows 23 + 24 (glare, timeouts, renegotiation; ~960 lines); (2) mesh link policy/framing, row 27 (bytes must match iOS; needs test vectors first); (3) account session phases, row 6, and status/work hours, row 21 (time zones, DST).
- Unsure: `FieldEditorModel.swift` (153), `Features/Chat/Composer/` (~2,300, markdown rules?), `Jam/CoEdit.swift` (925), `MovedSettings.swift` (72), `ChatLook.swift` (323) + `CustomSounds.swift` (colour/contrast belongs with DESIGN-28 tokens), `LinkPreviews.firstURL` and the Jam view models (~3,000, not read line by line).
- Commit: see git log (`docs(android): inventory the logic still in Swift`, Brief: LIME-293).

## LIME-294 — the app skeleton runs LimeCore

Landed: `android/` (Gradle Kotlin DSL, version catalog, wrapper 9.9.0), `android/build-core.sh` (wired as an `Exec` task before `preBuild`), one `MainActivity` screen (core version + encryption self-test result, brand colours, light/dark, strings in `strings.xml`), `CoreSmokeTest` (instrumented), `android/tools/emu.sh` (headless emulator helper), `app/lint.xml`, Android lines in `.gitignore`, docs/android.md "Running the app", screenshots in `docs/design/android/`.

Verification (all run): `assembleDebug` OK; `connectedDebugAndroidTest` passes on `lime-api26` (Android 8.0.0) and `lime-api36`; the screen shows "Core version 0.1.0" and "Encryption self-test: passed" on both; `testDebugUnitTest lintDebug` OK (0 errors); `core/check-android.sh` OK; `cargo test` in core: 428 passed.

For plot:
- Versions: AGP 9.5.1 (built-in Kotlin), Kotlin 2.4.21 (compose plugin), Compose BOM 2026.09.00, activity-compose 1.13.0, Gradle 9.9.0, JNA 5.14.0@aar, **compileSdk 37** (the BOM's libraries require it; I installed `platforms;android-37.0`), **targetSdk 36** (the newest stable behaviour set the BOM doesn't force; lint warns OldTargetApi because 37 exists; I did not verify Play's current required level from developer.android.com: 36 ≥ the 35 required since Aug 2025).
- APK: debug 33.6 MB (unstripped debug .so). Build: first run ~5.3 min (OpenSSL + core, two ABIs), incremental ~11 s.
- Core on a real Android runtime: no problems. JNA loads, SQLCipher/OpenSSL linked fine, self-test passes on API 26 and 36.
- Lint: UniFFI's generated Kotlin references `java.lang.ref.Cleaner` (API 33); the generated code only uses it off Android, so `lint.xml` ignores NewApi under `generated/uniffi`. Warnings (10): Aligned16KB ×3 (**JNA 5.14.0's x86_64 `libjnidispatch.so` is not 16 KB aligned; Play needs 16 KB for target 35+ on arm64 only matters for arm64 devices, which is aligned; the x86_64 one only matters for emulators**), DataExtractionRules (295 adds the rules), MissingApplicationIcon (no icon asset yet), NewerVersionAvailable ×2, OldTargetApi, UseTomlInstead (the `@aar` JNA line).
- Choices made (the user to confirm): the JDK situation above (Temurin 21 in `~/.lime/jdk21`, wired through the user-level `~/.gradle/gradle.properties`; nothing machine-specific committed); targetSdk 36.
- Not exercised: real hardware. Contrast: the lime-green "passed" text on #f9f8f4 is below 4.5:1 (it's a skeleton screen; 295's tokens fix it).

## LIME-295 — foundations: tokens, the transport, keys, the encrypted store

Landed: `net/BackendConfig` + Gradle step reading `supabase/.staging.public.env` into `BuildConfig` (missing file builds; the app shows "No backend configured"); `net/HttpTransport` (HttpURLConnection, connect 30 s / read 60 s, never logs URLs/headers/bodies); `keys/KeyWrapper` (AES-256-GCM, IV + ciphertext, name bound as AAD), `keys/KeystoreKey` (Android Keystore AES key, no export), `keys/SecureBlobStore` (sealed files in `noBackupFilesDir/secrets`); `storage/StorageBootstrap` (the twin of iOS's: per-account spaces `accounts/<id>`, wrong key/corrupt → old file moved aside, 2 kept, fresh store); `LimeApp`; `ui/theme/LimeColors` + `LimeTheme` (light + dark, values from iOS's asset catalog, Material 3 mapped onto them); `ui/shell` three-tab bottom bar (link · call · jam; call/jam "Coming soon on Android"); manifest `allowBackup=false` + data-extraction/backup rules excluding everything; `docs/android-icons.md`; `tools/emu.sh`, `tools/connected.sh` (both emulators, one at a time, headless, shut down after).

Verification (all run): `assembleDebug testDebugUnitTest lintDebug` OK (0 errors, 9 warnings); unit tests (KeyWrapper round trip, tamper, wrong key, wrong purpose, blob store; HttpTransport against a local server: headers + body + 404, and no-response = `TransportException.Failed`); instrumented `CoreSmokeTest` + `FoundationsTest` (Keystore round trip; store opens/closes/reopens with the same key; missing key → old file aside + fresh; transport → staging `identify` for an unknown username returns 404) pass on `lime-api26` and `lime-api36`; `core/check-android.sh` OK; `cargo test`: 428 passed. Screenshots: `docs/design/android/shell-api36*.png`.

For plot:
- Kotlin twins: `StorageBootstrap` (Swift file `Core/Storage/StorageBootstrap.swift`; platform file logic, not a core candidate); `HttpTransport` is the Android adapter. No Swift decision rules were copied in 295 (row table says none).
- Choices made (the user to confirm): wrapping key = Android Keystore AES-GCM wrapping a random 32-byte DB key stored as a sealed file (no `EncryptedSharedPreferences`); secrets under `noBackupFilesDir`; Kotlin coroutines added for Dispatchers.IO in 296+ (JetBrains, not a third-party SDK); `adoptOldStore` (pre-accounts store migration) not ported — there is no pre-accounts Android install; `StorageBootstrap.wipe` is there for 296's sign-out/remove paths.
- Warnings (9): Aligned16KB ×3 (JNA x86_64 only), MissingApplicationIcon (no icon asset yet), NewerVersionAvailable ×2, OldTargetApi, UseTomlInstead, one lint-lib note.
- Not exercised: real Keystore hardware (emulators use software-backed); the 16 KB alignment of JNA's x86_64 lib (emulator-only ABI).
