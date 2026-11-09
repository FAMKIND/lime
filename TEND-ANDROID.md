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
