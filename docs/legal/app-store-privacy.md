# App Store privacy answers (worksheet)

> **Draft, pending legal review.** Ready to paste into App Store Connect in November. Tracking: **none** (no data is used to track people across other companies' apps or sites; no ad SDKs, no analytics).

"Linked to you" means tied to the account. Every item is used only for **App Functionality**, never for advertising, analytics or marketing.

| Apple's data type | Collected? | Linked? | Why / what is true |
| --- | --- | --- | --- |
| Contact info: **Email address** | Yes | Linked | Sign-in and account emails (sent through Resend). |
| Contact info: **Name** | Yes | Linked | The display name a teacher sets; shown on their profile according to the profile setting. |
| Contact info: phone number, physical address | No | | Never asked. |
| **Contacts** (address book) | **No** | | lime never reads Contacts (Apple's picker runs out of process). |
| User content: **Photos or videos** | Yes | Linked | Profile photo, background and public posts when set to "Everyone on lime". Chat photos and videos are end-to-end encrypted: the server cannot read them. |
| User content: **Audio data** | Yes | Linked | Voice messages and podcast recordings the person records and sends or publishes. Chat audio is end-to-end encrypted. |
| User content: **Other user content** | Yes | Linked | Public band and jam posts, comments, likes. Encrypted messages are not readable by lime. |
| User content: Customer support | Yes | Linked | Only if someone emails us. |
| Identifiers: **User ID** | Yes | Linked | Account id, username, device keys. |
| Identifiers: **Device ID** | Yes | Linked | A lime device id (public keys). No advertising identifier (IDFA). |
| Usage data (product interaction, advertising data) | **No** | | No analytics. |
| Diagnostics (crash data, performance data) | **No** | | No crash-reporting SDK. [Confirm: TestFlight crash reports come from Apple.] |
| Location (precise or coarse) | **No** | | Never used. The emergency "Where" is free text the person types. |
| Health and fitness, financial info, sensitive info, browsing history, search history | **No** | | |
| Purchases | **No** | | lime is free. |
| Other data: **Reports** (what a reporter chose to send) | Yes | Linked | Moderation only. Sealed to lime's moderation key. |

## Specific answers

- **Camera:** scan QR codes, take a profile photo, record photos and videos to send. Nothing is recorded or uploaded unless the person sends it.
- **Microphone:** voice messages, the sound of videos, and calls. Nothing is recorded unless the person records.
- **Bluetooth (the mesh):** no Bluetooth identifier is collected. A random link id changes every 15 minutes. No location. Applies once the mesh ships in Release.
- **Photo library:** add-only (saves a photo when asked); reading is through the system picker.
- **Third parties** that receive data: Supabase (storage), Resend (email), Hetzner (calls). Processors only.
- **Account deletion:** in the app, Settings, Account, Delete Account.
- **Encryption:** standard, exempt encryption for export compliance (confirm with the lawyer).

## To confirm before pasting

1. Whether TestFlight crash logs or our own function logs count as "Diagnostics" collected.
2. Whether usernames and profile text count as "Name", "User ID", or both.
3. The final policy URL: `https://limemessenger.com/privacy` (LIME-282b).

Sources: `docs/release-checklist.md`, `docs/dpia-mesh.md`, `docs/moderation.md`, `ios/project.yml` usage strings.
