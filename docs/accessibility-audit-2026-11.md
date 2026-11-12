# Accessibility audit, November 2026 (LIME-130, Phase 1: findings only)

Audited 7 November 2026 at commit `86a2ce7` (the app as of LIME-285), against WCAG 2.2 AA and Apple's accessibility features (VoiceOver, Dynamic Type, Voice Control, Switch Control, Reduce Motion, Reduce Transparency, Increase Contrast, Differentiate Without Color, Bold Text). **Nothing was fixed in this run.** This file supersedes the 2026-10 name in the brief (that document was never written).

## Summary

**277 code-review findings:** **3 blocker, 100 major, 174 minor** (blocker = a task cannot be done with the assistive technology; major = hard or confusing, or fails a WCAG AA criterion; minor = polish or a lime-bar miss). Plus the Accessibility audit run on 60 screens in three passes: **508 issues at the default size, 295 at the largest accessibility size, 516 in dark mode** (counts of element flags, not distinct bugs; one cause often flags several elements).

| area | blocker | major | minor | total |
|---|---|---|---|---|
| jam | 0 | 20 | 62 | 82 |
| chat | 1 | 18 | 22 | 41 |
| common | 0 | 13 | 22 | 35 |
| calls | 1 | 11 | 20 | 32 |
| attachments | 1 | 11 | 12 | 24 |
| profile | 0 | 8 | 9 | 17 |
| settings | 0 | 8 | 9 | 17 |
| themes | 0 | 2 | 8 | 10 |
| onboarding | 0 | 4 | 5 | 9 |
| emergency | 0 | 3 | 3 | 6 |
| groups | 0 | 2 | 2 | 4 |

(Areas are the *suggested area* for the fix briefs: plot may split 130-1…130-n along them. `common` = shared components and app-wide patterns.)

### The five worst

1. **Every message action is long-press only (blocker, chat).** React, Reply (start a thread), Forward, Edit, Copy, Select, Report and Delete have no accessibility action; Voice Control and Switch Control cannot open the menu, and a VoiceOver user needs the undiscoverable double-tap-and-hold. `ChatView.swift:981`, `AttachmentViews.swift:555`.
2. **A voice message cannot be recorded with VoiceOver, Voice Control or Switch Control (blocker, attachments).** The microphone is a zero-distance `DragGesture` (hold, release to send, slide to cancel or lock); an accessibility tap starts and ends it at once. `ChatComposer.swift:242-276`.
3. **Video-call controls hide after 5 s and are `accessibilityHidden` (blocker, calls).** Mute, Camera and End call cannot be reached again with VoiceOver, Switch Control or Voice Control; the only way back is a tap on the picture. `CallView.swift:82-98,355-358` (the jam player guards the same pattern with `isVoiceOverRunning`; the call does not).
4. **Almost nothing is announced (major, common/chat/calls).** A new message in the open chat, delivery state, call phases, people joining a group call, the offline banner, the 2 s "Couldn't send/Copied" banner, errors and saved states, jam comments and band-join results: none posts an accessibility announcement (WCAG 4.1.3). The one app banner also disappears in 2 s (2.2.1).
5. **Red text and the call buttons fail contrast (major, common/calls).** `Color.red` text is 3.34:1 on the light canvas (3.05 on a surface) in about 50 places (every destructive label and error); white on red is 3.55:1 and **white on the green Accept button 2.22:1**. The theme engine's guard keeps chat text above 4.5:1 in every theme × light/dark × Increase Contrast (verified), so the failures are the hard-coded colours.

Next in line: row and header text that clips or breaks mid-word at the largest size (the Settings rows, the jam feed filter and cards, group-call tiles, fixed-height sheets), 44 pt targets (the jam tabs, reactions, voice-speed pill, the A–Z rail), gesture-only crop screens (photo and background), no alt text for photos, no captions or transcripts for voice messages and videos longer than 5 minutes, and no Differentiate Without Color or Bold Text handling anywhere.

### What is good

Settings Appearance (accent, background and text-size rows are named, selected, guarded), the terms checkbox (`isToggle`, label and value), password show/hide, the call mini player's actions, group-call Reduce Motion, the jam player's Reduce-Motion marquee, the @-mention list, the composer's text view label and announcements, the Move flow's progress announcements, the trim and waveform sliders, list swipe actions mirrored as accessibility actions in the drafts list, and the theme engine's contrast guard.

## How the audit was done

1. **Code review** of all of `ios/Lime/Features` and the app shell, in four areas (Jam; Chat/Messages/Attachments/Groups/Photos/Search; Calls/Emergency/Settings/Profile/Onboarding/Invite/Move/Moderation/Common/shell; and a contrast-and-themes measurement). Each section ends with its honest coverage list. Evidence is `file:line`.
2. **Simulator audit** with Apple's `performAccessibilityAudit` (the same checks as Xcode's Accessibility Inspector audit) on iPhone 17 (iOS 27.0), one launch per demo screen, three passes: default size and light; the **largest accessibility size** (accessibility-extra-extra-extra-large); dark mode. Harness: `tools/a11y/A11yAudit130.swift` (copied into the UI-test folder to run; not part of the target). Raw results: `docs/qa-shots/130/audit-issues.json`.
3. **Screenshots at the largest text size** for every audited screen: `docs/qa-shots/130/ax5/` (downscaled).
4. The failing group-call test, run on the iPhone 17 and the 13 mini.

## Accessibility Inspector audit, per screen (issue counts)

The audit flags *elements*; "dyntype" = a text element that does not scale with Dynamic Type, "clipped" = text cut off, "hit area" = a target smaller than 44 pt, "contrast" = a failed (or "near") contrast check, "no description" = an element with no useful accessibility information. At the largest size the hit-area count falls (6 vs 156) because rows and buttons grow, while clipping and non-scaling text remain.

| screen | default | largest text | dark | main kinds (default) |
|---|---|---|---|---|
| signin-welcome | 3 | 2 | 3 | 2 clipped, 1 hit area |
| signin-terms | 4 | 0 | 4 | 3 hit area, 1 contrast |
| messages | 3 | 6 | 2 | 1 dyntype, 1 contrast, 1 contrast (near) |
| calls-list | 3 | 6 | 2 | 1 dyntype, 1 contrast, 1 contrast (near) |
| calls-list-many | 3 | 6 | 2 | 1 dyntype, 1 contrast, 1 contrast (near) |
| call-voice | 12 | 11 | 12 | 4 clipped, 4 contrast, 3 dyntype, 1 no description |
| call-video | 14 | 13 | 14 | 4 clipped, 4 contrast, 3 dyntype, 3 no description |
| call-group-4 | 20 | 21 | 20 | 9 clipped, 7 dyntype, 3 contrast, 1 dyntype (partial) |
| call-group-incoming | 8 | 7 | 7 | 5 contrast, 1 dyntype, 1 clipped, 1 contrast (near) |
| move-offer | 0 | 0 | 0 |  |
| chat-themed-deep-meadow | 15 | 6 | 18 | 6 hit area, 2 dyntype, 2 dyntype (partial), 2 clipped, 2 inaccessible text, 1 contrast (near) |
| emoji-gif-panel | 9 | 5 | 9 | 4 hit area, 2 dyntype, 1 dyntype (partial), 1 label, 1 contrast |
| jam-handover-offer | 2 | 4 | 1 | 1 dyntype, 1 contrast |
| jam-writer-review | 14 | 7 | 13 | 7 hit area, 4 dyntype, 3 contrast |
| jam-band-people-owner | 10 | 4 | 9 | 3 hit area, 2 clipped, 2 no description, 2 contrast, 1 dyntype |
| jam-mine-open-posts | 14 | 7 | 13 | 7 hit area, 4 dyntype, 3 contrast |
| chat | 15 | 5 | 17 | 6 hit area, 2 dyntype (partial), 2 dyntype, 2 clipped, 2 inaccessible text, 1 contrast (near) |
| call-bubbles | 30 | 6 | 30 | 12 contrast, 9 hit area, 2 dyntype (partial), 2 dyntype, 2 clipped, 2 inaccessible text, 1 contrast (near) |
| format | 17 | 2 | 15 | 7 contrast, 6 hit area, 2 inaccessible text, 1 dyntype, 1 dyntype (partial) |
| attachments-gif | 9 | 5 | 9 | 4 hit area, 2 dyntype, 1 dyntype (partial), 1 label, 1 contrast |
| attachments-remote | 6 | 3 | 12 | 3 contrast, 1 hit area, 1 dyntype, 1 dyntype (partial) |
| chat-deleted-person | 15 | 5 | 17 | 6 hit area, 2 dyntype (partial), 2 dyntype, 2 clipped, 2 inaccessible text, 1 contrast (near) |
| note-to-self | 6 | 3 | 6 | 3 hit area, 1 dyntype, 1 dyntype (partial), 1 contrast |
| group | 11 | 7 | 13 | 6 hit area, 2 dyntype (partial), 1 dyntype, 1 clipped, 1 contrast |
| group-details | 16 | 8 | 15 | 6 dyntype, 3 hit area, 2 clipped, 2 no description, 2 contrast, 1 contrast (near) |
| group-details-plain | 17 | 9 | 16 | 9 dyntype, 3 hit area, 2 no description, 1 clipped, 1 contrast, 1 contrast (near) |
| groups-rows | 11 | 6 | 9 | 7 contrast, 2 clipped, 1 dyntype, 1 contrast (near) |
| band-group-rows | 11 | 7 | 9 | 7 contrast, 2 clipped, 1 dyntype, 1 contrast (near) |
| new-group-name | 6 | 6 | 6 | 3 clipped, 2 no description, 1 inaccessible text |
| profile-me | 6 | 3 | 5 | 2 hit area, 2 no description, 1 clipped, 1 contrast |
| profile-lee | 8 | 4 | 8 | 3 hit area, 2 clipped, 2 no description, 1 label |
| profile-sam | 16 | 6 | 17 | 7 hit area, 4 clipped, 2 no description, 1 dyntype, 1 label, 1 contrast (near) |
| settings | 1 | 1 | 1 | 1 dyntype |
| scan-band | 5 | 7 | 5 | 3 inaccessible text, 2 clipped |
| key-change | 16 | 8 | 19 | 7 hit area, 2 dyntype, 2 dyntype (partial), 2 inaccessible text, 1 clipped, 1 contrast (near), 1 contrast |
| session-ended | 3 | 4 | 2 | 1 dyntype, 1 contrast, 1 contrast (near) |
| jam | 2 | 2 | 1 | 1 dyntype, 1 contrast |
| jam-discover | 14 | 11 | 13 | 5 hit area, 4 dyntype, 3 clipped, 2 contrast |
| jam-following | 20 | 6 | 19 | 10 hit area, 5 dyntype, 3 contrast, 2 clipped |
| jam-mine | 14 | 7 | 13 | 7 hit area, 4 dyntype, 3 contrast |
| jam-mine-asjam | 19 | 21 | 31 | 9 hit area, 5 dyntype, 5 contrast |
| jam-mine-podcast | 21 | 14 | 20 | 7 hit area, 7 dyntype, 4 contrast, 2 clipped, 1 dyntype (partial) |
| jam-mine-profile | 10 | 4 | 9 | 3 hit area, 2 clipped, 2 no description, 2 contrast, 1 dyntype |
| jam-series | 19 | 5 | 18 | 10 hit area, 4 dyntype, 3 contrast, 2 clipped |
| jam-community | 15 | 6 | 16 | 7 hit area, 3 clipped, 2 no description, 1 dyntype, 1 label, 1 contrast (near) |
| settings-account | 2 | 1 | 2 | 1 label, 1 contrast |
| settings-privacy | 0 | 0 | 0 |  |
| settings-emergency | 1 | 0 | 1 | 1 hit area |
| settings-my-gifs | 1 | 0 | 1 | 1 contrast |
| settings-linked-devices | 0 | 0 | 0 |  |
| settings-work-hours | 0 | 0 | 0 |  |
| settings-customize | 1 | 1 | 1 | 1 clipped |
| settings-about | 0 | 1 | 0 |  |
| settings-customize-text-size | 1 | 1 | 1 | 1 clipped |
| settings-customize-appearance | 6 | 3 | 6 | 5 clipped, 1 inaccessible text |
| settings-customize-background | 1 | 1 | 1 | 1 clipped |
| settings-notifications-sounds | 2 | 1 | 3 | 2 contrast |
| settings-notifications | 0 | 0 | 0 |  |
| settings-storage | 0 | 0 | 0 |  |
| settings-calls | 0 | 0 | 0 |  |

**Totals (element flags):** default 508, largest size 295, dark 516.

**What the tool's flags amount to** (recurring elements, default pass):
- **Hit areas under 44 pt** are real for the jam tabs (Posts, Articles, Podcasts, Drafts: 8 screens), the "New comments" dot, the reaction and byline controls, the profile "Test Teacher, Nov 7" row; the chat timestamps ("Today", the time, "· Sent", "· Sending…", 11 screens) are static text the audit treats as a tap target (they are part of the message group and the time-reveal), so read them as the code review's "a message is 3-6 separate stops" finding.
- **"dyntype"** is dominated by the **avatar initials** ("TT" 24 screens, "SP" 11, "LW", "PR"…), the status-badge "z" and GIF badges: fixed-size text in circles.
- **Contrast** failures are mostly small overlays on avatars/photos ("TT" in the header pill, emoji reactions on the call screen, the call-bubble strip: 12 flags on `call-bubbles`) and the status text on the call screens; the dark pass has more "near" flags (38 vs 16). The code review's red-text, Accept-button and status-dot findings are the substantive ones.
- **"No description"** is a full-screen element on the call screens (10 screens); **"label not human-readable"** is "Poster.jpg" (a photo labelled by its file name), "@sam.park", "@lee.wong" and an email address.
- Screens that came back clean: `move-offer`, Settings Privacy, Linked devices, Work hours, Notifications, Storage and Calls pages (0 flags): the tool cannot judge their reading order, announcements or gestures.
- The audit **errored with "Invalid target app" on later screens of a long run** (the audit service goes stale); those screens were rerun in chunks of five and every screen in the table has a valid result. The largest-text pass skipped nothing.

## Largest text size: what the screenshots show (`docs/qa-shots/130/ax5/<screen>.jpg`)

- **Messages, Calls list, chat bubbles, the sign-up terms screen:** rows grow and wrap, the page scrolls: acceptable. The floating tab bar's labels ("link", "call", "jam") and the composer toolbar icons stay small (`messages.jpg`, `chat.jpg`): fixed-size.
- **Settings rows break words mid-line** because the value text is `lineLimit(1)` beside the title in one HStack: "Emer-genc-y group … None", "Mod e … Syst…", "Ac-cent … Li…", "Bac-kgro-und … Pla…" (`settings-emergency.jpg`, `settings-customize-appearance.jpg`, `settings-customize.jpg`); the Settings root's "Emer-gency" breaks too (`settings.jpg`). Major, settings.
- **Group call:** the header reads "Shem,… 4 >" and the tiles "Jean…", "Lee…", "Sh…"; the controls stay fixed-size (`call-group-4.jpg`).
- **1:1 call:** the name enlarges until the header chevron collides with the Minimise button (`call-voice.jpg`); the controls and emoji stay fixed (acceptable for controls).
- **Jam feed:** the filter chips clip ("All Posts Arti…"), the card title and byline truncate ("Songs for the…", "TEST TE…"), the action icons stay small (`jam-mine-podcast.jpg`).
- **Profile:** the Details row truncates the value ("Username … @tea…", `profile-me.jpg`); a chat's file card truncates to "W…pdf" and the chat header title is clipped under the blur (`chat.jpg`).
- Not reachable or cut: the `settings-*` pages were audited by scrolling to each row at the largest size; the fixed-detent sheets (call details, Confirm sheets, the notifications explainer, the Terms-updated sheet) are code-review findings, as the demo screens do not open them.

## Contrast, colour and themes (measured)

Method: the tokens come from the asset catalogue (`Resources/Assets.xcassets/*.colorset`), `ThemeEngine.swift` / `ThemeBackgrounds.swift`, `ChatLook`, `ButtonPalette` and the hard-coded colours in the views; opacities are blended over the background they sit on; ratios are WCAG 2.2 relative luminance (python, scripts in the session scratchpad, not in the repo). **Not measurable statically:** photo wallpapers, the Living palette, Jam covers and hero photos, live or remote video behind call text, Liquid Glass tints and blurs, `.secondary` and swipe-action tints (checked with UIKit systemRed #FF3B30 light / #FF453A dark). Those are marked as risk, not fact.

**The theme engine's contrast guard (`ThemeEngine.swift:69-124, 140-176`).** Thresholds: text 4.5, large 3.0, Increase Contrast 7.0 (the 4.5 equals WCAG's). It *clamps* (nudges a colour toward black or white in 0.02 steps until it clears), it never refuses a theme. It guards: text (canvas, surface, other bubble), secondary (canvas, surface), link (bubble, canvas), placeholder (canvas only), ownInk (my bubble), linkOwn, accentInk, and the hairline (Increase Contrast only). It does **not** guard: secondary on bubbles/chips/my bubble, link on surface, placeholder on surface, ownInk at 0.7 opacity, the hairline and bubble edge, any hard-coded colour, photo and Living backgrounds. `ResolvedTheme.passes()` (line 127) exists but nothing calls it (test-only).

**Matrix result.** All 8 accents × 8 backgrounds × light/dark × Increase Contrast (chalkboard forced dark): *the guarded pairs never fall below* text on canvas 8.92 (bulletin light), text on other bubble 6.70 (chalkboard), text on surface 8.49, secondary on canvas 4.90, ownInk on my bubble 6.43 (Pink dark), linkOwn 4.53 (Orange dark), link on bubble 4.51, accentInk on accent 7.47 (Lavender). With Increase Contrast text on canvas/bubble is at least 7.01. **No combination of the chat message text on its bubble, or the chat text on its background, falls below 4.5:1** (the brief's "every theme × light/dark" check passes). Per-chat looks: all 16 tone × deep/pastel pairs are 5.56–14.49. Pattern backgrounds: worst pixel under text keeps text ≥ 7.97 and secondary ≥ 3.79 (secondary fails 4.5 on lined-dark 3.79 and dots-dark 3.91).

**Tokens (light | dark).** canvas F9F8F4 | 131B17; surface F0EEE6 | 212925; text 131B17 | F5F3ED; textSecondary 504840 | A09890; other bubble FFFEFE | 3D4441; my bubble (lime) E4F9BE | 8ECF73 (ink 131B17); accent A3E18A (ink 131B17); link in other bubble 1B7A3A | 8ECF73; hairline DDDDD9 | 3D4441; placeholder 6E665E | 8C857E; status dots (hard-coded, `StatusViews.swift:18-24`) available 33B85C, away F5B21A, do-not-disturb E0474D.

**Pair table** (needed | light | dark | verdict | where):

| pair | needed | light | dark | verdict | where |
|---|---|---|---|---|---|
| text / canvas, surface | 4.5 | 16.51 / 15.10 | 15.81 / 13.44 | PASS | ThemeEngine.swift:50 |
| textSecondary / canvas, surface | 4.5 | 8.44 / 7.72 | 6.17 / 5.25 | PASS | ThemeEngine.swift:50 |
| text / other bubble | 4.5 | 17.43 | 9.01 | PASS | Theme.swift:41 |
| **textSecondary / other bubble** (link-preview and attachment captions) | 4.5 | 8.91 | **3.52** | dark FAIL | LinkPreviews.swift:141; AttachmentViews.swift:227 |
| ownInk / my bubble (lime) | 4.5 | 15.53 | 9.46 | PASS | ThemeEngine.swift:164 |
| ownInk@0.7 / my bubble (lime) | 4.5 | 6.12 | 4.73 | PASS (lime only; other accents in dark 3.84–4.46) | LinkPreviews.swift:141 |
| link / other bubble, canvas | 4.5 | 5.36 / 5.08 | 5.39 / 9.46 | PASS | ThemeEngine.swift:158 |
| link / surface | 4.5 | 4.65 | 8.04 | PASS (fails on Paper light + Pink: 4.29) | not in guard |
| accentInk / accent (unread badge, +, Subscribe) | 4.5 | 11.44 | 11.44 | PASS | MessagesView.swift:863 |
| placeholder / canvas | 4.5 | 5.30 | 4.82 | PASS | ThemeEngine.swift:159 |
| **placeholder / surface** | 4.5 | 4.85 | **4.10** | dark FAIL | guarded against canvas only |
| chevrons, off-state icons (secondary@0.7) | 3 | 3.84 | 3.69 | PASS | SettingsView.swift:233; ChatView.swift:925 |
| accent A3E18A as a control edge / canvas | 3 | **1.44** | 11.44 | light FAIL (label identifies the control: low) | Accent.colorset |
| brand lime 09A950 as text / canvas | 4.5 | 2.90 | 5.68 | not used as text anywhere (do not start) | — |
| **systemRed text / canvas** | 4.5 | **3.34** | 5.15 | light FAIL | ~50 uses, see findings |
| **systemRed text / surface** | 4.5 | **3.05** | **4.38** | light + dark FAIL | SettingsView.swift:229 |
| onboarding error red B82C33 / canvas | 4.5 | 5.73 | **2.88** | dark FAIL (fixed colour) | OnboardingScreens.swift:161,300,328 |
| **white / Color.red fill** (Decline, End call, offline banner, recording) | 4.5 text (3 icon) | 3.55 | 3.41 | text FAIL, icon PASS | MessagesView.swift:41; CallView.swift:278-327 |
| **white / systemGreen** (Accept) | 3 | **2.22** | **2.02** | FAIL | CallView.swift:279 |
| red text in QR error box (red@0.1 over canvas) | 4.5 | 2.93 | 4.69 | light FAIL | QRScreens.swift:211 |
| emergency card border red@0.8 / canvas | 3 | 2.80 | 3.66 | light FAIL | EmergencyViews.swift:42 |
| available dot / canvas, surface | 3 | **2.43 / 2.23** | 6.78 / 5.76 | light FAIL | StatusViews.swift:18 |
| away disc F5B21A / canvas | 3 | **1.75** | 9.44 | light FAIL | StatusViews.swift:21 |
| white moon glyph on away disc | 3 | **1.86** | 1.86 | FAIL | StatusViews.swift:22 |
| dnd disc / canvas | 3 | 3.80 | 4.34 | PASS | StatusViews.swift:24 |
| find match vs my bubble | 3 | 1.09 | 1.51 | FAIL (text stays 11–14:1) | MessageText.swift:253 |
| call-row ring (secondary@0.5) | 3 | **2.44** | 2.51 | FAIL (the ring is the only boundary) | CallsTab.swift:369; ChatView.swift:1421 |
| call button fill white@0.18 vs bg 121412 | 3 | 1.73 | 1.73 | boundary FAIL (glyph 9.9) | CallView.swift:338 |
| ButtonPalette label/fill (6 colours) | 4.5 | 6.09–15.77 | 9.03–15.16 | PASS | JamButtons.swift:23-41 |
| disabled text: Save (@0.6) 3.04, index letters (@0.5) 2.44, step button 2.87, disabled Save/accent 3.01 | 4.5 | — | — | FAIL, exempt as inactive (1.4.3), still should stay perceivable | ProfileScreens.swift:55; NewMessageSheet.swift:425; ChatAppearanceScreen.swift:176; AccountScreens.swift:144 |
| podcast recorder placeholder white@0.55 | 4.5 | 4.09 | 4.09 | FAIL | PodcastRecorder.swift:977 |
| podcast waveform unplayed (UI) | 3 | **1.84** | 2.39 | FAIL | PodcastPlayer.swift:339 |
| call text white@0.6–0.92 on call bg | 4.5 | 7.14–15.66 | same | PASS | CallHeaderViews.swift:112 |
| dark glass tab chevron, fallback, Reduce Transparency | 3 | 9.23 / 5.74 / 16.56 | same | PASS | CallMiniPlayer.swift:288-293 |

Hypothetical worst cases (depend on the video or photo; risk): call text on a white remote video with no scrim 1.0:1; white@0.7 on a black@0.6 pill over white video 3.76:1; Jam hero meta white@0.8 on a 0.45 scrim over a white photo 2.74:1; Living-dark secondary text over a white or yellow palette 2.45–2.56:1 (the veil is 72 %).

**Colour-only meaning / Differentiate Without Color.** `accessibilityDifferentiateWithoutColor` is used nowhere. Candidates: reaction "mine" (accent fill only, `ReactionCluster.swift:70`), find-in-chat current match (hue and lightness only), missed call (red plus outcome text, so meaning survives), status dots (shape carries the state: moon, z, ring: passes 1.4.1, fails 1.4.11 on the dot itself). Passing: unread (bold + count badge), delivery state (words + icon), links (underlined), wallpaper/accent swatches (ring + checkmark). **Increase Contrast:** `colorSchemeContrast` is read only in `ProfileHero.swift:199` and `JamMedia.swift:256`; the theme engine reads `UIAccessibility.isDarkerSystemColorsEnabled` and raises text to 7:1; every hard-coded colour (red, call overlays, status dots, disabled greys) ignores it.


### Contrast findings (from the measurement above)

| screen | finding | where | WCAG | severity | area |
|---|---|---|---|---|---|
| Chat (dark): link-preview and attachment captions | textSecondary on the other person's dark bubble is 3.52:1 (the guard checks secondary only on canvas and surface) | LinkPreviews.swift:141; AttachmentViews.swift:227,229 | 1.4.3 | major | chat |
| Chat (my bubble, dark, non-lime accents) | ownInk@0.7 captions and h6 drop to 3.84 (Pink, Lavender), 3.90 (Orange), 3.96 (Blue), 4.40 (Peach), 4.46 (Yellow) | LinkPreviews.swift:141; AttachmentViews.swift:227,229; MessageText.swift:51 | 1.4.3 | major | chat |
| Themes (Paper light + Pink) | link on surface is 4.29:1 (the guard checks bubble and canvas only) | ThemeEngine.swift:158 | 1.4.3 | minor | themes |
| Themes (all dark backgrounds) | placeholder is guarded against canvas only; on dark surface fields it is 4.03-4.10:1 (3.52 chalkboard, 3.76 bulletin dark) | ThemeEngine.swift:159 | 1.4.3 | major | themes |
| Themes (reaction chip, non-Plain) | secondary text on chipMine reaches 3.39-4.06:1 (lined, dots, Living dark; Pink on chalkboard/bulletin) | ThemeEngine.swift:169-170 | 1.4.3 | minor | themes |
| Themes (Living background, dark) | veil is 0.72 over the photo palette: secondary text 2.45-2.56:1 on a white or yellow palette (computed worst case) | ThemeBackgrounds.swift:164-168 | 1.4.3 | major | themes |
| Themes (Increase Contrast) | hairline nudged to 3:1 only with IC (1.28-1.94 otherwise); link, placeholder, chips stay at 4.5 | ThemeEngine.swift:156-157 | 1.4.11 | minor | themes |
| Whole app: red text (every destructive label and error) | systemRed text is 3.34:1 on canvas and 3.05:1 on surface in light; dark 5.15 / 4.38 | CallsTab.swift:103; ChatView.swift:1244,1015,1019; ProfileView.swift:846; SettingsView.swift:229-230; AccountScreens.swift:133; DeleteAccountScreen.swift:120,139; SoundScreens.swift:94; LinksScreen.swift:37; ProfileScreens.swift:20; NewMessageSheet.swift:504; ConfirmSheet.swift:60; GroupDetailsView.swift:319-331; JamArticle.swift:712-713; FormattingToolbar.swift:136,278,310; MessageActions.swift:324,490; PhotoScreens.swift:255; ModerationScreen.swift:97-193 (+~40 more Color.red) | 1.4.3 | major | common |
| Onboarding errors | fixed red B82C33 is 5.73:1 light but 2.88:1 on the dark canvas (not appearance-aware) | OnboardingScreens.swift:161,300,328; OnboardingComponents.swift:59 | 1.4.3 | major | onboarding |
| Calls: Decline, End call, offline banner, recorder | white on systemRed 3.55/3.41: icons pass 3:1, the 12 pt banner text and the labels fail 4.5 | CallView.swift:278,291,305,327; GroupCallView.swift:260; MessagesView.swift:41; CallMiniPlayer.swift:191 | 1.4.3 | major | calls |
| Calls: Accept | white on systemGreen 2.22 (light) / 2.02 (dark) | CallView.swift:279 | 1.4.11 / 1.4.3 | major | calls |
| Messages/Profile: availability badge | available dot 2.43 on canvas / 2.23 on surface; away 1.75; white moon on yellow 1.86 (shape carries the state; the dot and glyph need 3:1) | StatusViews.swift:18-22 | 1.4.11 | major | common |
| Disabled and inactive text | disabled controls at 0.4-0.6 opacity are 2.4-3.0:1 (exempt as inactive, but the labels must stay perceivable) | ProfileScreens.swift:55; GroupDetailsView.swift:493; NewMessageSheet.swift:425; AccountScreens.swift:144; ChatAppearanceScreen.swift:176; JamEngagement.swift:285; PodcastRecorder.swift:1063,1096 | 1.4.3 | minor | common |
| Calls: call-row and chat call-back buttons | ring is secondary@0.5 = 2.44/2.51:1 and is the control's only boundary | CallsTab.swift:369; ChatView.swift:1421 | 1.4.11 | minor | calls |
| Calls: button fills | white@0.18 circle vs dark call bg 1.73:1 (glyph 9.9); the off state is shown by fill only | CallView.swift:338,372; GroupCallView.swift:268 | 1.4.11 | minor | calls |
| Calls: overlay text over live/remote video | white@0.7-0.9 over bright video without a scrim can fall to ~1:1; pills (black 0.35-0.6) 3.76 at worst; not measurable statically | CallView.swift:60,216,236; GroupCallView.swift:80,90,223,347; CallHeaderViews.swift:29-58 | 1.4.3 | major | calls |
| Jam: recorder and player | prompt white@0.55 4.09:1; unplayed waveform 1.84/2.39:1 | PodcastRecorder.swift:977; PodcastPlayer.swift:339 | 1.4.3 / 1.4.11 | minor | jam |
| Jam: hero and series meta over cover photos | white@0.8-0.92 over a cover with a partial scrim; worst case 2.74:1 (photos not measurable) | SeriesShow.swift:133-139; OrgProfile.swift:422-461; GroupDetailsView.swift:264 | 1.4.3 | major | jam |
| Chat: find in chat | match highlight 1.09-1.51:1 vs my bubble; the current match differs from other matches by hue/lightness only | MessageText.swift:253; Theme.swift:73-74 | 1.4.1 | minor | chat |
| Chat: reactions | "mine" is shown only by the accent fill | ReactionCluster.swift:70-72 | 1.4.1 | minor | chat |
| Calls: missed call | red alone on name and icon, but outcome text/different symbol carries the meaning; the red fails 4.5 on light (see red finding) | CallsTab.swift:103; ChatView.swift:1244; ProfileView.swift:846 | 1.4.1 | minor | calls |
| Emergency card | red border 2.80:1 in light (label has text) | EmergencyViews.swift:33,42 | 1.4.11 | minor | emergency |
| Whole app: Differentiate Without Color | accessibilityDifferentiateWithoutColor is used nowhere | grep | 1.4.1 | minor | common |
| Whole app: Increase Contrast | colorSchemeContrast read in two places; every hard-coded colour ignores Increase Contrast | ProfileHero.swift:199; JamMedia.swift:256; ThemeEngine.swift:222 | 1.4.3 / 1.4.6 | minor | common |
| Themes: hairline and bubble edge | dividers 1.28/1.76:1; bubble vs canvas 1.06:1 (no field relies on the hairline alone) | ThemeEngine.swift:50-62 | 1.4.11 | minor | themes |

The measurement rated the red-text finding a blocker; by this audit's definition (a task cannot be done with the assistive technology) it is **major**.

## Chat, Messages, Attachments, Groups, Photos, Search (code review; paths under `ios/Lime/Features/` unless stated)

### Cross-cutting

| finding | where | WCAG / feature | severity | area |
|---|---|---|---|---|
| `limeGlass` has no Reduce Transparency or Increase Contrast branch (glassEffect on iOS 26, `.ultraThinMaterial` + 0.5 pt hairline on 17-25); only LiveCallButton (ChatView:1311-1318) and MessageActions (:43-44,54,172) branch; system materials normally go solid by themselves (UNVERIFIED on device); no stronger border for IC | Theme/Glass.swift:5-17; ChatView:541,569,576,714,742,769; ChatComposer:145; FormattingToolbar:40,43; MessageActions:236,504,600; Mentions:119; NewMessageSheet:305,366,371; GroupScreens:129; MessageSearchScreen:313,335; AddSheet:250,256; ThreadView:262; IncomingBannerView:34; FloatingPlus:35-43; ComposerPanel:58,113 | Reduce Transparency, Increase Contrast | minor | common |
| `Color.red` text: 3.34:1 on canvas, 3.05 on surface in light (the text says "Not sent"/"Missed", so not colour-only) | ChatView:764,1015,1019,1244; FormattingToolbar:136,278,310; NewMessageSheet:504; MessageActions:324; GroupDetailsView:319,325,331; PhotoScreens:255 | 1.4.3 | major | common |
| About 120 fixed `.font(.system(size: N))` sites (mostly glyphs in fixed circles, acceptable; the text cases are separate findings) | grep | 1.4.4 | minor | common |
| `withAnimation`/`.animation`/`.transition`/`scaleEffect` without a Reduce Motion branch in 14 places (the branch exists in MessageActions:59,167, Mentions:60-61, GIFs, ComposerBlocks:320) | ChatView:192,196,246,281,284; ThreadView:44,48,103,186; MessagesView:142,258; ChatComposer:160-161,246; IncomingBannerView:41; AttachmentViews:343 | Reduce Motion, 2.3.3 | minor | common |
| Sheet headers made of plain Text (no heading rotor target) in 8 places (SheetHeader, ComposerPanel and AddSheet:246 do have `.isHeader`) | MessageActions:355,389,426,536; ChatView:1156; FormattingToolbar:115; GroupAvatarEditor:~108 | 1.3.1, 2.4.6 | minor | common |

### Messages list

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| Each row is one combined element with a rich label, but the person's **status badge (available/away/DND/offline) is dropped** from it: status is visual only | MessagesView:755-757; StatusViews:99 | 1.3.1 | minor | chat |
| Filter button 40×40 (label "Filter, N active" is good), glyph fixed 17 pt; segmented control `maxWidth: 220/300` (can truncate at AX, UNVERIFIED) | FilterRow:35,56-59 | 2.5.8, 1.4.4 | minor | common |
| `CountBadge`: fixed height 22, single-digit circle, `minimumScaleFactor(0.8)`: may clip at AX (UNVERIFIED); unread also by bold + row label | MessagesView:859-866 | 1.4.4 | minor | chat |
| The "lime menu" button's hint "Press and hold for About lime" is wrong in a release build (the long-press exists only under `#if DEBUG`) | MessagesView:96-105,548-556 | VoiceOver hint accuracy | minor | common |
| The connection/offline banner, low-storage banner and recovery notice appear and disappear with no announcement (NotificationCoordinator outside this review) | MessagesView:329-383,514,787 | 4.1.3 | minor | chat |
| "No chats yet" is not a header; the iOS 17-25 header avatar button is 36×36 | MessagesView:472-475,570-575 | 1.3.1, 2.5.8 | minor | chat |
| Status badge: hard-coded colours; white moon on away-yellow ≈1.85:1, white "z" on DND red ≈4.05:1 (shape and label carry the state) | StatusViews:21-26,37-40 | 1.4.11 | minor | profile |
| **Incoming-message banner**: auto-dismisses after 4.5 s, dismissible only by a swipe-up DragGesture (no accessibility action), no announcement when it appears | IncomingBannerView:25-37 | 2.2.1, 4.1.3, 2.5.7 | major | common |
| New-message button: lime-tinted glass at 0.55/0.75 opacity under `accentInk` over a scrolling list (variable contrast, UNVERIFIED), no Reduce Transparency branch (the emergency action is a named accessibility action: good) | FloatingPlus:35-43 | 1.4.11 | minor | chat |

Good: row swipe actions (Delete, Mute, Leave, Clear, Read/Unread, Pin) are exposed as custom actions.

### Chat: header, find bar, scroll (ChatView)

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| The header title pill has a fixed width (`max(120, width−196)`) with `lineLimit(1)` on name and subtitle: truncates at large sizes, no layout fallback; the whole iOS 17-25 header is capped at `.dynamicTypeSize(...xxxLarge)` | ChatView:118,409,424,437,587 | 1.4.4, 1.4.10 | major | chat |
| The verified-seal is a 13 pt glyph with `onTapGesture`, no 44 pt frame and no `contentShape` (effective hit area ≈13 pt) | ChatView:411-417 | 2.5.8 (<24) | major | chat |
| Find bar: up/down 32×36; "3 of 12" and "No matches" not announced on query change (same in ThreadView:226-264) | ChatView:502-543 | 2.5.8, 4.1.3 | minor | chat |
| The earlier-messages page loads on scroll and VoiceOver is not told | ChatView:156-176 | 4.1.3 | minor | chat |
| **A new message or reply arriving in the open chat is not announced** (no live region; the view only scrolls) | ChatView:283-287; ThreadView:101-105 | 4.1.3 | major | chat |
| **Functional bug: the "Waiting for internet" explanation alert is attached only in `legacyContent` (iOS 17-25); on iOS 26 `onWhy` sets `offlineReason` but nothing presents it, so the "Says why" button does nothing** (breaks the hint too) | ChatView:148-150 vs 103-133 | 3.3.1, 4.1.3 | major | chat |
| "N messages deleted", "Waiting for messages…" and "Earlier messages" have no `wallpaperChip` and sit directly on a photo/pattern wallpaper (UNVERIFIED on a photo) | ChatView:168,354-361,386-389 | 1.4.3 | minor | themes |

### Chat: bubbles and message kinds (ChatView, AttachmentViews, ReactionCluster, VoiceMessages, VideoMessages)

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| **In a one-to-one chat nothing says who wrote a message** (sender name only in groups, DM avatar label is `""`, own vs other only by alignment and colour); in a group your own messages carry no "You" | ChatView:847-902 | 1.3.1, 1.3.3 | major | chat |
| **A message is a `.contain` group of 3-6 separate elements** (name, text, reaction chips, time, "· Edited", "· Sent", thread summary; a hidden 1×1 element carries the time): many swipes per message; order name, text, reactions, time | ChatView:862-898 | 1.3.2, 2.4.3 | major | chat |
| **BLOCKER: every message action is long-press only** (React, Reply/start a thread, Forward, Edit, Copy, Select, Save to my GIFs, Report, Delete): no `.accessibilityAction`; Voice Control and Switch Control cannot open the menu; VoiceOver needs the undiscoverable double-tap-and-hold; a reply thread and Select mode cannot be started without it | ChatView:981; AttachmentViews:555-556 | 2.1.1, 2.5.1, 2.5.7 | **blocker** | chat |
| Delivery-state changes (Sending, Sent, Failed, Not delivered, Waiting for internet) are not announced; a failure is only red button text; the `·` separators are read aloud; the footer is `lineLimit(1)` and truncates at large sizes | ChatView:1003-1044 | 4.1.3, 1.4.4 | major | chat |
| The red retry buttons are 3.05-3.34:1 in light and have no 44 pt target | ChatView:1015,1019 | 1.4.3, 2.5.8 | major | chat |
| Live group call card: people joining/leaving and "Call ended" are not announced (the ordinary call bubble is fine: one element, "Missed voice call, 0:00", button, hint) | ChatView:1206-1269 | 4.1.3 | minor | calls |
| **Reaction chips**: 30×30 (hit ≈38); emoji `size:16`, count `size:10`, "+N" `size:12` fixed so the count is unreadably small at large sizes; "mine" only by accent fill (A3E18A on canvas 1.44:1) | ReactionCluster:62-91 | 1.4.4, 1.4.1, 2.5.8 | major | chat |
| ThreadSummaryRow: `.fixedSize()` + `lineLimit(1)` overflows the column at accessibility sizes (UNVERIFIED), ≈30 pt tall, unread dot colour only (label covers it) | ChatComposer:532-566 | 1.4.4, 1.4.10, 2.5.8 | major | chat |
| **A photo's label is the sender's file name ("IMG_4821.JPG") or "Photo", with no way to add alt text**; a received lime sticker reads only "Sticker" although its name is known (`LimeSticker.label`); an album's 4th tile does not say "and N more" | AttachmentViews:34-38,59,67,84 | 1.1.1 | major | attachments |
| **GIFs loop with no pause control** (up to 6 at once) unless Reduce Motion is on | AttachmentViews:146; GIFSupport:90-140 | 2.2.2 | major | attachments |
| The "Play GIF" button (Reduce Motion) sits inside an `accessibilityHidden` container: invisible to VoiceOver, Voice Control and Switch Control in the chat (the viewer's own Play button is fine) | AttachmentViews:142-184 (:169, :427) | Voice Control | minor | attachments |
| GIFs are arbitrary user files; there is no flash check | GIFSupport | 2.3.1 | UNVERIFIED | attachments |
| **Captions on the other person's dark bubble: `textSecondary` on `bubbleOther` is 3.52:1** (file card, link card, availability text) | AttachmentViews:227,229,640-652; LinkPreviews:141 | 1.4.3 | major | attachments |
| Own-bubble cards use `ink.opacity(0.7/0.8)`; a custom bubble colour is guarded only for full ink (default lime passes 6.08/4.73) | AttachmentViews:227,229; LinkPreviews:141; VoiceMessages:325 | 1.4.3 | minor | themes |
| File card fixed width 248 (middle truncation); link card fixed width 248, title 2 lines | AttachmentViews:212-244; LinkPreviews:122-175 | 1.4.4 | minor | attachments |
| **Voice message: play button 40×40; the speed pill (1×) ≈18-20 pt with no `contentShape`; position and progress are not exposed as an accessibility value, the waveform is hidden: a voice message cannot be scrubbed** | VoiceMessages:294-345 | 2.5.8, 2.1.1 | major | attachments |
| **No transcript or captions for user-made voice or video messages**, and the players offer none | VoiceMessages:294-345; VideoMessages:119-139,160-190 | 1.2.1, 1.2.2 | major | attachments |
| When one voice message ends the next starts automatically with no announcement | VoiceMessages:279-288 | 1.4.2 | minor | attachments |
| Video tile label "Video, 0:12" omits the sender and the download/removed/size state that pictures include; the ring updates are not live | VideoMessages:138-140 | 4.1.3 | minor | attachments |
| In Select mode the row label is the message text only (no sender, no time) | ChatView:896-901 | 1.3.1 | minor | chat |

Good: the time-reveal drag has an equivalent accessibility action (:195), day lines are headers (:344).

### Message actions overlay, reaction bar, who-reacted, emoji picker (MessageActions)

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| **The overlay is not modal to VoiceOver**: no `.isModal`, the chat behind is only blurred, focus is not moved to the menu; the backdrop is `accessibilityHidden` with a tap gesture and there is no escape/dismiss action: once open, a VoiceOver or Switch user cannot dismiss it except by choosing an action | MessageActions:56-58,136-176 | 2.4.3, 2.1.2 | major | chat |
| The actions list is capped (`dynamicTypeSize(...xxxLarge)`) and fixed at 270 pt: rows (minHeight 48) cannot reach the accessibility sizes | MessageActions:153,632 | 1.4.4 | major | chat |
| Reaction bar: "mine" is an accent fill with no `.isSelected`; fixed 28 pt emoji, 40×44 buttons | MessageActions:206-239 | 4.1.2, 1.4.1 | minor | chat |
| Action rows: icon fonts fixed 17 pt (rows are 48 pt, labelled) | MessageActions:316-332 | 1.4.4 | minor | chat |
| Who-reacted sheet: "Reactions" title not a header; person rows (36 pt) and the own-reaction remove button under 44; emoji `size:30` fixed | MessageActions:416-477 | 2.5.8, 1.4.4 | minor | chat |
| Emoji picker: the 1×1 `EmojiKeyboardField` at opacity 0.01 may be a stray focus stop (UNVERIFIED) | MessageActions:407 | 1.1.1 | minor | chat |
| Forward/Edit sheets: selected chips 30 pt tall; chat titles `lineLimit(1)` | MessageActions:345-374,515-624 | 2.5.8 | minor | chat |

### Thread / replies (ThreadView)

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| The root author's avatar is an `onTapGesture` with no label and no button trait, 30 pt | ThreadView:150-153 | 4.1.2, 2.5.8 | major | chat |
| "N replies" is a combined element but not a header; the same bubble, long-press and announcement problems as Chat | ThreadView:53-193 | 1.3.1, 2.1.1, 4.1.3 | minor | chat |

### Composer (ChatComposer, RichComposer, FormattingToolbar, ComposerPanel, Mentions)

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| **BLOCKER: the microphone is `DragGesture(minimumDistance: 0)` (hold to record, release to send, slide left to cancel, slide up to lock).** A VoiceOver double-tap or a Voice Control/Switch Control tap is a zero-length drag, so recording starts and ends at once and is dropped: **there is no accessible way to record a voice message**, and cancel/lock have no alternative | ChatComposer:242-276 | 2.1.1, 2.5.1, 2.5.7 | **blocker** | attachments |
| Recording start, lock, cancel and send are not announced; the recording bar is a red blinking dot at ≈1 Hz plus bars and a timer; "Slide to cancel" is gesture-only guidance | ChatComposer:295-308; VoiceMessages:396-422 | 4.1.3, 2.3.3 | major | attachments |
| Emoji, Aa, keyboard and plus buttons 44×40; send circle 36 pt in a 44×40 frame; icons fixed 15-20 pt | ChatComposer:103-133,397 | 2.5.8 | minor | chat |
| Link-preview "Remove" 36×36; "Preparing video… N%" and the draft link card appearing are not announced | ChatComposer:49-55,410-423 | 4.1.3, 2.5.8 | minor | attachments |
| The per-chat text size is applied through the SwiftUI environment; the composer is a UIKit text view whose `baseFont` uses `TextPreferences.overrideCategory`, not the chat's own step: it may not follow a chat's size (UNVERIFIED) | ChatView:74; RichComposer:693-720 | 1.4.4 | minor | themes |
| Formatting toolbar items 42×38, list shifts 44×44, fixed 46 pt strip, fonts 15-18 fixed | FormattingToolbar:11-97 | 2.5.8, 1.4.4 | minor | chat |
| Link/Button sheets: a red error under the field is not announced or tied to it; "Add" is disabled with no reason for VoiceOver | FormattingToolbar:101-358 | 3.3.1, 4.1.3 | minor | chat |
| Panel: a GIF with no words reads only "GIF"; the panel is a fixed-height keyboard replacement and its segmented Picker (fixed 42 pt) may clip at AX; search results count and "Nothing matches" not announced; `.regularMaterial` | ComposerPanel:25-202 | 1.1.1, 1.4.4, 4.1.3 | minor | chat |

Good: the text view is labelled "Message" with `adjustsFontForContentSizeCategory` and announces mention/panel/keyboard changes; @mention list is labelled, scaled, Reduce-Motion aware; GIF/sticker buttons labelled with hints; tab switch announced.

### Add sheet, GIF library, viewer, video player

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| Add sheet: every recent-photo tile reads "Photo" (or "Video, 0:12") with no differentiator; the select circle is `white.opacity(0.9)` on a photo with no scrim; "Manage" is secondary text with no frame; the title uses `minimumScaleFactor(0.75)` with 96 pt padding each side | AddSheet:199-201,242-326 | 1.1.1, 1.4.11, 2.5.8, 1.4.4 | minor | attachments |
| My GIFs: the "That isn't a GIF" notice is not announced (cells have named custom actions: good) | GIFLibrary:160,222-239 | 4.1.3 | minor | attachments |
| **Picture viewer: white glyphs on `.ultraThinMaterial` circles directly over the photo/video; the viewer does not force a dark scheme, so on a light-appearance phone the material is light and white icons are near 1.2:1** (buttons 44 pt and labelled; UNVERIFIED on device) | AttachmentViews:358-376,586-607; VideoMessages:169-172 | 1.4.11, Reduce Transparency | major | attachments |
| Viewer: "Saved to Photos" is a label swap with no announcement; the reaction popup's open state has no `.isExpanded`; the zoom photo's label is a fixed "Photo" | AttachmentViews:371-376,587-619; ZoomablePhoto:34-39 | 4.1.3 | minor | attachments |
| **Draft strip remove button is a 20 pt glyph (< 24) with the same label "Remove" for every draft; the draft thumbnails have no labels** | AttachmentViews:501-505 | 2.5.8, 2.4.6 | major | attachments |
| Video player: captions depend on the file, none are generated; the close button sits over AVKit's controls | VideoMessages:160-190 | 1.2.2 | minor | attachments |

### New Message, groups, search, photos

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| Lookup states (Searching, found, "No teacher found", error) appear with no announcement | NewMessageSheet:268-281,566-574; MessageSearchScreen:135-147 | 4.1.3 | major | chat |
| The A–Z rail: 22 pt wide, 11 pt fixed fonts, ≈19 pt tall letters (< 24), 27 extra VoiceOver stops (per-letter actions exist: good), dimmed letters `opacity(0.5)` | NewMessageSheet:412-450 | 2.5.8, 1.4.4 | major | chat |
| The search-field clear button is a bare `xmark.circle.fill` ≈17-20 pt with no frame (labelled "Clear") | NewMessageSheet:297-300; MessageSearchScreen:328-331 | 2.5.8 | major | chat |
| Disabled primary buttons at 0.4×0.6 opacity with no reason given | NewMessageSheet:526-535; GroupScreens:39-46,177-183 | 1.4.3 | minor | chat |
| New Group picker: selected-people chips ≈36 pt; the "N Members" count is static | GroupScreens:56-66 | 2.5.8, 4.1.3 | minor | groups |
| Search: result count and "No results" not announced; message and jam row labels override the content and drop the date/time | MessageSearchScreen:150-206 | 4.1.3 | minor | chat |
| Group details: media cells use `onTapGesture` with no `isButton`, every cell reads "Photo"/"Video" with no date or sender | GroupDetailsView:407-414 | 4.1.2, 1.1.1 | major | groups |
| **Group details: the "New key not accepted" warning icon inside a member row is swallowed by the row's custom label ([name, role])**: the warning is visual only to VoiceOver | GroupDetailsView:443-455 | 1.3.1 | major | groups |
| Group hero: white name and `white.opacity(0.92)` over the photo (scrim in ProfileHero:34 is Reduce-Transparency and Increase-Contrast aware; not verified for every photo) | GroupDetailsView:238-279 | 1.4.3 | minor | groups |
| **Profile/group photo crop is DragGesture + MagnifyGesture only**, no accessible alternative to move or zoom and no label or adjustable actions (Save with the default centred crop works) | PhotoScreens:119-131 | 2.5.7, 2.1.1 | major | profile |
| Photo screen: the busy state and failure text are not announced | PhotoScreens:200-201,284-301 | 4.1.3 | minor | profile |
| Chat appearance: wallpaper names `lineLimit(1)`, fixed 170 pt preview (hidden, decorative), disabled slider `opacity(0.45)`, "Reset this chat" and "Use for all chats" have no confirmation | ChatAppearanceScreen:84-216 | 1.4.4 | minor | themes |

### Coverage

Read in full: Chat/ChatView, MessageActions, ChatComposer (incl. ThreadSummaryRow, LinkOpening), ReactionCluster, ThreadView, ChatAppearanceScreen, KeepsNewestAboveKeyboard, KeyboardDismissal, Composer/FormattingToolbar, ComposerPanel; Messages/MessagesView, StatusViews, FloatingPlus, IncomingBannerView, LabelCapsule, Avatar, NewMessageSheet; Attachments/AttachmentViews, GIFLibrary, VideoMessages, StickerPack; Groups/GroupDetailsView, GroupScreens, GroupAvatarEditor; Photos/PhotoScreens; Search/MessageSearchScreen. Read in part: AddSheet (150-449), VoiceMessages (150-422), LinkPreviews (100-192), ChatLook, MessageText, Mentions (40-178), RichComposer (80-304), ComposerBlocks (1-60, 186-330), ZoomablePhoto and GIFSupport. Only grepped: ComposerDocument, ComposerSizing, AttachmentModels, GIFFixtures, GroupAvatarPlan, PhotoProcessing, SearchModels (model/logic files, no accessibility code). Not reviewed: ConfirmSheet, EmergencyPanel/EmergencyCardView, NotificationCoordinator, ThemeBackgroundView, the jam article editor's UI beyond the block markers. All contrast ratios are computed from asset-catalogue values, not measured on device.


## Jam (code review; paths under `ios/Lime/Features/Jam/` unless stated)

Source: static read of the Jam folder (coverage at the end of this section). **UNVERIFIED** = needs a simulator or VoiceOver check.

### Jam: cross-cutting patterns

| finding | where | WCAG / feature | severity | area |
|---|---|---|---|---|
| `limeGlass` (Theme/Glass.swift:5-17) has no Reduce Transparency or Increase Contrast branch and no border for IC; white controls over video and photos on glass have no solid fallback | JamFilter:72, JamDiscover:88, JamArticle:415/453/477/511, JamMedia:426/439/454/541/755/986/1000/1016/1066/1071, JamAudio:255/286, JamDrafts:251/302, PodcastRecorder:462/485/563/573/648, OrgEdit:50, RootView:258 | Reduce Transparency, Increase Contrast, 1.4.11 | major | common |
| `withAnimation`/`.animation`/`.transition` with no reduceMotion branch in 12+ places (highlight fade, "more" expand, Discover group expand, DraftInviteBanner spring slide, article pill/bar, player tint crossfade, cursor-tag fade, segment scrollTo) | JamPage:167,241; JamDiscover:98,113,280,293; JamArticle:267,426; JamDrafts:312,319; JamMedia:327; CoEdit:853; JamFilter:82 | Reduce Motion, 2.3.3 | minor | common |
| Fixed `.font(.system(size: N))` on icons and some text in 60+ places (reader fonts do scale) | JamEngagement:19,44,136,283; JamAudio:141,148,250; PodcastPlayer:270,291; JamMedia:110,182,426,540,558; JamComposeSheet:684,695,705,746,754; PodcastRecorder:811,816; CoEdit:878 (13 pt cursor tag); OrgMembers:202; BylineAvatar:56 | 1.4.4, Dynamic Type | minor | common |
| Errors and status are red text, not announced, not tied to a field; several failures are silent (`_ = await`) | JamComposeSheet:319 (can sit off screen at the top), CreatePublication:45, SeriesShow:419,429, OrgCover:49, OrgEdit:95,178,183, OrgMembers:35, BeforePublish:71, PodcastRecorder "problem", OrgProfile:509 (community toggle), JamEngagement:149 (comment send), OrgMembers (join/role/remove) | 4.1.3, 3.3.1 | major | common |
| Red text uses `Color.red` (3.34:1 on the light canvas) | OrgMembers:35, JamReader:426, JamArticle:1242-1243, OrgProfile:518, OrgEdit:95, SeriesShow:419/429, CreatePublication:45, JamComposeSheet:319 | 1.4.3 | major | common |
| Disabled primary buttons use `Theme.accent.opacity(0.4)` then `.opacity(0.6)` stacked; disabled state shown by opacity only; the dummy "remix"/"share" buttons are focusable and do nothing | OrgFieldSheet, EditSeriesSheet:410, NewBandGroupSheet:245, CreatePublication:138, BeforePublish:81; JamEngagement:279-287; JamMedia:733-757 | 4.1.2, Differentiate Without Color | minor | common |
| Decorative SF Symbols inside labelled rows not hidden (UNVERIFIED whether VoiceOver prepends the symbol name) | JamArticle:712,715; JamReader:375; OrgGroupsTab | VoiceOver | minor | common |
| **No alt-text input** for photos in posts, covers or articles; readers get "Photo 2 of 5"; the print HTML `<img>` has no alt | JamReader:234, JamPhoto:313, OpenInlineImage:320, JamArticle:843 | 1.1.1 | major | attachments |
| `.onTapGesture` cards (JamPhotoRow, JamVideoCard, JamPodcastCard, JamLinkCard) carry `.isButton` or inner Buttons; JamLinkCard:155 is `.ignore` + onTapGesture + `.isLink` (UNVERIFIED that double-tap activates) | JamLinkCard:155 | 4.1.2 | minor | jam |
| **"Shared" toast**: 2 s auto-dismiss, `.updatesFrequently` only, no announcement | JamMedia:814; ConversationStore:1022; RootView:251-266 | 4.1.3, 2.2.1 | major | common |

### Jam feed and post cards (JamPage)

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| **A post card is 5-8 focus stops** (avatar, name, "by", byline, content, More, like, comment, remix, share); the byline reads three times; no combined element, no custom actions | JamPage:257-282 | 1.3.1, VoiceOver | major | jam |
| The article cover is a Button with a long overridden label that contains the Save Button and SeriesTag Button (nested buttons probably unreachable by VoiceOver/Switch Control; Save also in ⋯); "Unread" and "Saved" are not in the spoken label (UNVERIFIED) | JamPage:215-218; JamArticle:140-143,121 | 4.1.2 | major | jam |
| Unread is a 12 pt white dot on the photo; the cover is a fixed-height frame, title `lineLimit(3)`, subtitle `lineLimit(2)` on an image gradient: clipped at AX sizes | JamArticle:121,149-151 | 1.4.4, 1.4.10 | major | jam |
| "New comments" dot is accent 9 pt, colour only, 2.90:1 on light; it is its own focus stop | JamPage:238 | 1.4.11, Differentiate Without Color | minor | jam |
| Name, "by …" and byline `lineLimit(1)`; "by" `.fixedSize` can widen the row | JamPage:263,271,276,295 | 1.4.4, 1.4.10 | minor | jam |
| Co-author and hand-over request cards arrive at the top of the feed with no announcement; Accept/Decline labels carry no context when several cards | JamPage:55-107 | 4.1.3, 2.4.6 | minor | jam |
| Skeleton→content, pagination and filter results are not announced; "No posts match" is plain text | JamPage:136-172 | 4.1.3 | minor | jam |
| Filter result count not announced | JamFilter:94-108 | 4.1.3 | minor | jam |
| A post opened from a notification is highlighted by a 0.14 accent tint only, animated | JamPage:166-167 | Differentiate Without Color | minor | jam |
| "more" expansion not announced, animation unguarded | JamPage:227 | Reduce Motion | minor | jam |
| Menu label "Saved ✓" announces the ✓ glyph | JamPostMenu:50; JamArticle:674 | VoiceOver | minor | jam |

Checked, nothing found: JamCardChoice, JamRead (logic), JamPostMenu (labels, 44×44, Delete last, destructive confirm).

### Podcast card, mini player, player (JamPodcastCard, JamAudio, PodcastPlayer, JamMedia)

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| Whole card has onTapGesture plus inner Buttons for cover, title and pill: duplicates | JamPodcastCard:46 | VoiceOver | minor | jam |
| Org name caption2 `lineLimit(1)` truncates; 96 pt cover fixed | JamPodcastCard:29,63,66 | 1.4.4 | minor | jam |
| Waveform scrubber is adjustable with a spoken value (good); 32 pt high; unplayed bars 1.82:1 | JamAudio:137-155; PodcastPlayer:321-360 | 2.5.7, 1.4.11 | minor | jam |
| "Couldn't play this recording" is plain text, not announced; the card version (JamAudioCard) shows nothing on failure or load; ProgressView unlabelled | PodcastPlayer:279-281; JamAudio | 4.1.3 | major | jam |
| "Reading speed" label does not match the visible "1×/1.25×/1.5×" and has no value | JamAudio:246-249 | 2.5.3, 4.1.2 | minor | jam |
| Start of playback, queue advance and "Listening" (read-aloud) not announced | JamAudio:256-309; JamArticle:751-760 | 4.1.3 | minor | jam |
| Controls auto-hide after 3 s while playing, skipped only for VoiceOver; Switch Control and Voice Control users lose them | JamMedia:1085-1086 | 2.2.1, Switch Control | major | jam |
| Caption line and elapsed time over video frames; the time text has no scrim | JamMedia:119-147,1048-1067 | 1.4.3 | minor | jam |
| **Captions/transcript only when captions exist, and on-device captions stop at 300 s** (`CaptionMaker.maxSeconds`); longer podcasts and videos have none and no manual way to add one | JamMedia:116-119,547-552; CaptionMaker:10; JamComposeSheet:533; PodcastRecorder:1257 | 1.2.1, 1.2.2, 1.2.3 | major | attachments |
| Muted video autoplays in the feed at 50 % visible (respects `isVideoAutoplayEnabled`, pauses off screen) but the card has no pause control | JamMedia:161-168,199-207 | 2.2.2 | major | jam |
| Audio cover exposed as an element "Cover" (noise); the video stage button label is generic | JamMedia:490,889 | VoiceOver | minor | jam |
| Subscribe pills in the player are 36 and 28 pt high | JamMedia:574-576,604 | 2.5.8 | minor | jam |
| Marquee runs forever when motion is allowed (pauses with Reduce Motion) | JamMarquee:39-52 | 2.2.2 | minor | jam |
| Lock-screen skip is 10/10 s, the screen buttons −10/+30, PodcastBar −10/+10 | PodcastPlayer:200-204; JamMedia:537,545 | consistency | minor | jam |

Checked, nothing found: Marquee (full text via `.ignore` + label), TextOver (`.isModal`, close button), AirPlayButton, PlayerTimeline (adjustable), JamFileCard, UpNextSheet.

### Article reader and end card (JamReader, JamArticle)

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| Action pill hidden with opacity 0 and `allowsHitTesting(false)` on scroll while kept in the a11y tree: focus can land on an invisible control that may not activate (UNVERIFIED) | JamArticle:255-264 | 2.4.7, 2.4.11, Switch Control | major | jam |
| Navigation bar and back button hidden and replaced by a custom glass Back; the system back swipe and the VoiceOver two-finger Z escape may not pop (no `accessibilityPerformEscape`) (UNVERIFIED) | JamArticle:268-269,407 | 2.1.1 | major | jam |
| The top bar slides off on scroll (opacity 0) while staying focusable (Subscribe, ⋯) | JamArticle:423-426 | 2.4.7 | minor | jam |
| Jam name line and the end card's section headings ("Share", jam card) are not headers (the title is) | JamArticle:292 | 1.3.1 | minor | jam |
| Find-in-post field has only the placeholder as its name | JamArticle:499 | 3.3.2 | minor | jam |
| Display-settings font/size chips show selection by an accent border plus `.isSelected` | JamArticle:583-589,615-619 | Differentiate Without Color | minor | jam |
| Options sheet destructive rows are `Color.red` (3.34:1); row icon fixed 20 pt | JamArticle:712,721 | 1.4.3 | minor | jam |
| Read-aloud (ArticleSpeaker) has no announcement on start, pause or finish | JamArticle:739-780 | 4.1.3 | minor | jam |
| Print/PDF export `<img>` has no alt | JamArticle:843 | 1.1.1 | minor | jam |
| Subscribers "Remove" is red text | JamReader:407-446 | 1.4.3 | minor | jam |
| Quick-post photo tiles say "Photo 1 of 3"; no alt text | JamReader:233-236 | 1.1.1 | minor | jam |
| Full-screen photo: close button 44×44 and background tap; no zoom control (pinch only), no alt text | JamReader:325 | 1.1.1, 2.5.1 | minor | attachments |

### Comments and likes (JamEngagement)

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| "Cancel reply" xmark has no frame: about 22 pt target | JamEngagement:123-128 | 2.5.8 | major | jam |
| "Reply" is minHeight 32; "Comment options" ⋯ 36×36 | JamEngagement:176,187 | 2.5.8 | minor | jam |
| Posting a comment: no announcement of success or failure; a failed send silently stays; focus is not moved to the new comment | JamEngagement:130-139,149 | 4.1.3 | major | jam |
| Replies are indented with a vertical line only; nothing says "reply to X"; pending comments are 0.6 opacity plus text | JamEngagement:86-94,172-193 | 1.3.1 | minor | jam |
| The counts line "20 likes · 3 comments" is plain text, not a header | JamEngagement:82 | 1.3.1 | minor | jam |

### Discover (JamDiscover)

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| "More" ⋯ is a Menu overlaid on a combined card Button; opens only Report; overlaps the header row | JamDiscover:152-161 | 2.5.8 | minor | jam |
| Group expand/collapse has value and hint but `withAnimation` unguarded | JamDiscover:98-113 | Reduce Motion | minor | jam |
| Like/Comment for a non-subscriber opens an inline "Subscribe to like and comment" prompt with no announcement | JamDiscover:280-294 | 4.1.3 | minor | jam |

### Drafts (JamDrafts)

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| **Fixed row height 84 and a fixed List height (rows × 84 + 8), non-scrolling; title and status lines `lineLimit(1)`: clipped or cut at AX sizes** | JamDrafts:14,38-40,87-88 | 1.4.4, 1.4.10 | major | jam |
| Title, "X is writing", review state, "Edited · names" all `lineLimit(1)` (VoiceOver gets the full label) | JamDrafts:107,141-150 | 1.4.4 | minor | jam |
| 5-second polling of "is writing" never announces; entering selection mode has no announcement | JamDrafts:44-50 | 4.1.3 | minor | jam |
| **DraftInviteBanner**: glass, auto-dismisses after 6 s, a swipe-up DragGesture with no accessibility action, no announcement on arrival, spring slide unguarded | JamDrafts:278-323 | 2.2.1, 4.1.3, Reduce Motion | major | jam |
| Selection bar icon fixed 18 pt | JamDrafts:238-269 | 1.4.4 | minor | jam |

Good: swipe actions are mirrored as `.accessibilityAction` (Edit, Copy, Pin, Delete/Leave, Select) and context menus.

### Bands (OrgProfile, OrgMembers, OrgEdit, OrgCover, CreatePublication, Handover)

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| Band hero: white text at 0.92 on a photo/blurred background with no scrim in this file (depends on `ProfileHeroBackground`) (UNVERIFIED) | OrgProfile:420-428,457 | 1.4.3 | major | profile |
| Info-card titles ("About", "Tags", "Owners") are not headers | OrgProfile:608 | 1.3.1 | minor | jam |
| JamOrgsSection: scaled row height but 4 lines per row `lineLimit(1)` inside a fixed List height (UNVERIFIED) | OrgProfile:94,117,138-141 | 1.4.4 | major | jam |
| Toolbar labels "Edit band", "Edit cover", "Done editing" differ from the visible "Edit", "Edit Cover", "Done" (contain the visible word) | OrgProfile:349-357 | 2.5.3 | minor | jam |
| Tab switch (Info/Posts/Articles/Members) is silent | OrgProfile:549-570 | 4.1.3 | minor | jam |
| Members: "Make owner" has no `.accessibilityAction` (Make writer and Remove do) | OrgMembers:26-27,99-101 | 2.5.1 | minor | jam |
| Invite link "New link" replaces the old one and "Turn off" disables it with no confirmation; state not announced | OrgMembers:145-146 | 3.3.4, 4.1.3 | minor | jam |
| Join/asked/joined/full states are plain text that replaces the button, with no announcement (also CommunityJoinRow) | OrgMembers:208,314-320; JamCommunity:48-54 | 4.1.3 | major | jam |
| Group-name field silently truncates at 50 characters | OrgMembers:251 | 3.3.1 | minor | jam |
| Band edit: counter turns red over the limit (number visible, so not colour-only), not announced or tied to the field; FlowChips minHeight 36 | OrgEdit:94-96,199 | 3.3.1, 2.5.8 | minor | jam |
| Create band: field labels "Name"/"About" override the visible prompt ("What is your band called?"); failure red text not announced | CreatePublication:38-41,73,81 | 2.5.3, 4.1.3 | minor | jam |
| Hand-over offer card arrives with no announcement (failure is an alert: good) | Handover:24-26,60-75 | 4.1.3 | minor | jam |

Checked, nothing found: OrgCover swatches (48 pt, named, selected trait + checkmark), ReviewListSheet, OrgPictureSheet, OrgInviteSheet. `GroupPickerScreen` is outside the folder and not reviewed.

### Series (SeriesShow, JamSeries)

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| "Play next" exists only as a swipe action (no `accessibilityAction`) | SeriesShow:48-54,251-252 | 2.5.1 | minor | jam |
| Row label says "played" for articles that are read | SeriesShow:250 | 4.1.2 | minor | jam |
| JamPostMenu overlay top-right on rows whose title can run under it | SeriesShow:254 | 2.5.8 | minor | jam |
| Hero text white at 0.8/0.92 over a computed wash (UNVERIFIED) | SeriesShow:137,139 | 1.4.3 | minor | jam |
| Hosts and "More from" are horizontal scrolls with fixed 96/160 widths and `lineLimit(1/2)`: truncation at AX | SeriesShow:282-296,333-347 | 1.4.4 | minor | jam |
| Series chip text `lineLimit(1)` truncates the selected series; SeriesTag minHeight 28, white at 0.9 on a scrim | JamSeries:146-147; JamSkeleton:14-17 | 1.4.4, 2.5.8 | minor | jam |

### Composer, Before you post, captions, privacy (JamComposeSheet, BeforePublish, CaptionMaker, StudentPrivacy)

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| Spoken labels differ from visible text: "Write an article" vs "Write article", "Record a podcast", "Create a band" | JamComposeSheet:635-637,762-764 | 2.5.3 | minor | jam |
| "Remove the video recording" vs visible "Recording 0:12"; clips row 36 pt | JamComposeSheet:593-597 | 2.5.3, 2.5.8 | minor | jam |
| Body field (`RichComposerField`, outside the folder) draws its placeholder as hidden Text; the text view's own label not verifiable (UNVERIFIED) | JamComposeSheet:253-306 | 3.3.2 | major | jam |
| Photo thumbnails have no VoiceOver label (only "Remove photo n"); cannot be reviewed or described | JamComposeSheet:577-581 | 1.1.1 | minor | attachments |
| Heading menu font fixed `.system(size: 20 − n)`; "Add cover", compact pills and chips `lineLimit(1)` + `fixedSize` can run past the edge at AX | JamComposeSheet:443,675,705,773 | 1.4.4, 1.4.10 | minor | jam |
| The top bar holds up to 5 buttons in one HStack (avatars, Ready, Send back, Done/Next): overflows at AX (UNVERIFIED) | JamComposeSheet:137-168 | 1.4.10 | minor | jam |
| Before you post: row label Text and chip are separate elements under `.contain`; summary lines `lineLimit(2)`; "problem" text not announced; Post/Publish disabled by opacity | BeforePublish:59-110 | 4.1.2, 4.1.3 | major | jam |
| Student privacy: the "photo has faces" warning appears asynchronously with no announcement; the confirmation is a Button with a value but no `.isToggle`; panel background `surface.opacity(0.5)` | StudentPrivacy:59-78 | 4.1.3, 1.4.11 | minor | jam |
| Captions editor: time column fixed `frame(width: 44)` clips at large sizes; line field labelled only by the placeholder "Line" | CaptionMaker:91-118 | 1.4.4, 3.3.2 | minor | attachments |
| **"No captions for this one"** gives no way to supply captions or a transcript | JamComposeSheet:547-566 | 1.2.1 | major | attachments |

Good: block reorder has a non-drag alternative (Move up/down dialog); audience choice shows a confirm sheet.

### Podcast studio and recorder (PodcastRecorder)

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| **Record/Stop/pause/elapsed time are not announced** (only "Draft saved" is) | PodcastRecorder:469-480,1287 | 4.1.3 | major | jam |
| White text on the red recording pill 3.5:1 | PodcastRecorder:417-421 | 1.4.3 | major | jam |
| Live level bars hidden from VoiceOver (static capsule with Reduce Motion: good); no audio-level feedback for VoiceOver users | PodcastRecorder:393-397,884 | 4.1.3 | minor | jam |
| Trim handles 16 pt wide (hit area ≈ 32); adjustable in 1-second steps: slow for long recordings | PodcastRecorder:641-698 | 2.5.7, 2.5.8 | minor | jam |

### Co-editing (CoEdit)

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| Cursor tags are UIKit views with a fixed 13 pt font; the tag and caret are accessibility elements inside the text area, which adds noise to the editor's reading order | CoEdit:437-463,850,878 | 1.4.4, VoiceOver | minor | jam |
| `editingLine` builds a spoken string ("Jean is editing the third paragraph") but no caller posts it; remote edits spliced in place are silent for VoiceOver users (UNVERIFIED outside the folder) | CoEdit:600-611 | 4.1.3 | major | jam |
| Tag fade animation unguarded | CoEdit:853 | Reduce Motion | minor | jam |

Good: peer colours darkened to 3:1, names are in the tags (not colour-only), authors avatars are one combined button "Authors: you, Jean (here now)".

### Jam: coverage

Read fully: JamRead, JamEditSheet, JamCardChoice, JamCommunity, PodcastMic, BylineAvatar, JamPostMenu, JamButtons, JamSkeleton, Handover, BeforePublish, JamFilter, JamPodcastCard, OrgCover, JamMarquee, LocalDrafts, StudentPrivacy, JamAudience, JamSeries, OrgEdit, JamEngagement, JamDrafts, JamDiscover, OrgMembers, JamAudio, PodcastPlayer, JamPage, JamReader, JamArticle, SeriesShow, OrgProfile, CreatePublication, JamMedia. Mostly read: CaptionMaker. **Partially read:** JamComposeSheet (lines 90-790 and 1230-1447 of ~1447), CoEdit (225-345, 380-470, 560-925 of 925), PodcastRecorder (388-500, 580-715, 1180-1345 plus a grep of the whole file, of 1369). **Not reviewed** (outside the folder): RichComposerField, FormattedMessageText, ProfileTabs, FilterMenuButton, FloatingPlus, SheetHeader, AvatarView, AvatarCache, GroupPickerScreen, PostCover, AttachmentViewer, LinkCardView; `ConversationStore+Jam*.swift` announcements were not read.


## Calls, Emergency, Settings, Profile, Onboarding, Invite, Move, Moderation, shell (code review; paths under `ios/Lime/` unless stated)

### App-wide patterns

| finding | where | WCAG / feature | severity | area |
|---|---|---|---|---|
| No handling of Bold Text or Differentiate Without Color anywhere (`legibilityWeight`, `differentiateWithoutColor` not used); Bold Text on lime's custom typefaces (`Theme.font` → `LimeTypeface`) UNVERIFIED | grep | Bold Text, Differentiate Without Color | minor | common |
| `limeGlass` and the system materials have no hand-written Reduce Transparency/Increase Contrast branch except `CallMiniPlayer:208-211` and `TabGlass:288`; the system probably falls back by itself (UNVERIFIED on device); same for `FloatingPlus:42` | Theme/Glass.swift:9-16 | Reduce Transparency, Increase Contrast | minor | common |
| Row icons use fixed `.font(.system(size:))` (do not scale with lime's text size or Dynamic Type); several round buttons are 40×40 | CallsTab:129-130,368; CallMiniPlayer:175,190; FilterRow:56; ProfileView:426; BackgroundScreen:151; AccountScreens:15; Settings row icons (size 20 + frame 28) | 1.4.4, 2.5.8 | minor | common |
| **`Color.red` text on light surfaces** (3.34:1 on canvas, 3.05 on surface; white on red 3.55); dark mode passes on canvas (5.15) | SettingsView:229-230; DeleteAccountScreen:120,137-139; AccountScreens:133; ConfirmSheet:60; ModerationScreen:49,97,110,193; ReportSheet:91; QRScreens:211; EmergencyViews:33,76,342,366; SoundScreens:94; ProfileView:846; FieldEditorSheet:20; LinksScreen:37 | 1.4.3 | major | common |
| **Settings group titles are not headings** (`SettingsFootnote`/plain Text, no `.isHeader`): heading navigation skips them and radio rows read without their group ("Forever, selected" without "Keep media") | NotificationScreens:28,37,54,66; StorageScreens:23,34,40,48; BackgroundScreen:51; ProfileView:779,789,818; ProfileLinks:77; ModerationScreen:128; AddSoundSheet:63 (CallsTab group headers are fine) | 1.3.1, 2.4.6 | major | settings |
| **Errors, "Saved", busy spinners and scan results are not announced and not tied to a field**; only Move, the password eye and the mute announcement post announcements | OnboardingComponents:56-62; ConfirmationSheet:160; PasswordScreen:297-302; ProfileScreen:327; AccountScreens:99,110,132; DeleteAccountScreen:94,105,119; SoundScreens:94; BackgroundScreen:44-45; LinksScreen:36-39,50; FieldEditorSheet:19-22; ReportSheet:25,91; QRScreens:112-141 | 4.1.3, 3.3.1 | major | common |
| **The one app banner** ("Couldn't send", "Forwarded", "Copied") auto-dismisses after 2 s and never posts an announcement (only `.updatesFrequently`) | ConversationStore.swift:1022-1038; RootView.swift:251-266 | 4.1.3, 2.2.1 | major | common |
| Only `JamMedia:1086` checks `isVoiceOverRunning`; the auto-hiding call controls do not | grep | 2.2.1, 2.1.1 | see Call screen | calls |

### Call screen, 1:1 (CallView, CallHeaderViews, CallEffects)

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| **BLOCKER: video-call controls fade after 5 s and are set `accessibilityHidden`; the only way back is a tap on the screen, which is not an accessibility element.** With VoiceOver, Switch Control or Voice Control the user cannot reach Mute, Camera or End call once they vanish | CallView:82-86,98,355-358 | 2.2.1, 2.1.1 | **blocker** | calls |
| Mute, Camera, Speaker and Video have fixed labels and no value or `.isSelected`; on/off is carried by white fill vs translucent only (the group call's labels do switch) | CallView:361-373 | 4.1.2, 1.4.1 | major | calls |
| The route-change toast, the "phone may be off" hint and "camera paused" appear with no announcement; only `remoteMuted` posts one; phase changes (Ringing, Connecting, Connected, Ended, reconnecting) are not announced | CallView:56-72,232,236 | 4.1.3 | major | calls |
| White text over full-bleed video: name pill black at only 0.35 (≈2.4:1 on white video); status/timer, hint (white 0.7), "camera paused" and the "Muted" chip have no scrim | CallHeaderViews:35; CallView:56-62,225,236 | 1.4.3, 1.4.11 | major | calls |
| Round control buttons are white glyphs on white at 0.2 over live video (≈1.1:1 on a bright picture); the Minimise button on a voice call too | CallView:78,337,371-372; CallEffects:117-118 | 1.4.11 | major | calls |
| The call details sheets use fixed detents (`.height(300)`, `.height(380/440)`) with no ScrollView: they clip at accessibility sizes (emoji sheet has a fixed 52 pt emoji font) | CallView:245-266; CallHeaderViews:94-119 | 1.4.4, 1.4.10 | major | calls |
| Self-view tile: DragGesture to move and onTapGesture to swap on a handle labelled "Swap the pictures"; no `isButton`, no `accessibilityAction`, no non-drag way to move the corner | CallView:156-168 | 2.5.7, 4.1.2 | minor | calls |
| Fade and spring animations do not check Reduce Motion (the group call does) | CallView:107,163,166 | Reduce Motion | minor | calls |
| **Call effects (confetti, fireworks, lasers, balloons)** are drawn into the video and sent to the other side; no Reduce Motion or flashing control, and the other party cannot turn them off; flash rate UNVERIFIED | CallEffects:92-131; CallView:286,299 | 2.3.1, Reduce Motion | minor | calls |
| Fixed 24 pt icons and 56/64 pt circles; header name `lineLimit(1)` (acceptable for call controls) | CallView:361-373; CallHeaderViews:27 | 1.4.4 | minor | calls |
| Incoming Accept/Decline: colour plus glyph plus label; no visible text for Voice Control "tap Accept" | CallView:279-281 | Voice Control | minor | calls |
| RoutePicker wrapped with `.ignore` and a custom label but no `.isButton` | CallView:130-135 | 4.1.2 | minor | calls |

### Group call, mini player, tuck tab, PiP grid

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| **People joining, leaving or becoming the active speaker are not announced**; the tile value (Speaking, Muted) updates only if the tile is focused | GroupCallView:276-341 | 4.1.3 | major | calls |
| Self-view tile is DragGesture-only with no `.accessibilityAction` | GroupCallView:178-184,213-219 | 2.5.7 | minor | calls |
| The controls row falls back to a horizontal ScrollView at 44 pt; Leave is in the scroll row and may be off screen at large sizes | GroupCallView:240-243 | 1.4.10, 2.5.8 | minor | calls |
| Tile name pill `minimumScaleFactor(0.7)` + `lineLimit(1)`; state words hidden when compact (VoiceOver still reads them) | GroupCallView:305,347 | 1.4.4 | minor | calls |
| Incoming banner buttons have no hint; `.regularMaterial` with no solid fallback (system probably handles it, UNVERIFIED); the invite sheet's hand-drawn grabber is not hidden from VoiceOver | GroupCallView:445-475,492-540 | Reduce Transparency, 1.1.1 | minor | calls |
| Mini player: tuck tab is 24×48 (meets 2.5.8, not lime's 44); mute label is the action ("Unmute") while the value is the state ("Muted"); no announcement when the call ends or the mini player appears/tucks | CallMiniPlayer:112-132,180-181,89-100 | 2.5.8, 4.1.2, 4.1.3 | minor | calls |
| PiP grid: fixed 11 pt labels, "speaking" is a lime ring (#A3E18A) plus bold on video | Core/Calls/PiPGridView:50,115,142 | 1.4.4, 1.4.11 | minor | calls |

Handled well: the mini player's return and "Tuck away call controls" are accessibility actions; group-call Reduce Motion is gated; the people sheet rows are combined.

### Calls list and New Call (CallsTab, FilterRow)

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| **A missed call shows only the red name colour on screen** (the outcome note shows only for DND/unavailable); "missed" is only in the VoiceOver label | CallsTab:101-103 | 1.4.1, Differentiate Without Color | major | calls |
| The call name `lineLimit(1)` beside the time in an HStack, groups `lineLimit(1)`; truncated at accessibility sizes, no vertical/`ViewThatFits` layout | CallsTab:104-107,325 | 1.4.4, 1.4.10 | major | calls |
| Each row is three VoiceOver stops (avatar "details", the row, a round call button that duplicates the row) | CallsTab:86-136 | 2.4.3, 1.3.1 | minor | calls |
| Swipe-to-delete only (List swipeActions are exposed as custom actions, UNVERIFIED) | CallsTab:212-215 | 2.5.1 | minor | calls |
| Segmented control capped at maxWidth 220/300; filter button 40×40 whose label adds a value ("Filter, 2 active" plus "2") | FilterRow:32-72 | 2.5.8, 4.1.2 | minor | common |
| "Find by Username" icon fixed 18 pt | CallsTab:293,367 | 1.4.4 | minor | calls |

### Shared components (read because Calls and Profile use them)

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| **A–Z index rail** (New Call, New Message): 22 pt wide, 27 letters at fixed 11 pt, each cell ≈19 pt high (< 24); every letter is a VoiceOver "Jump to X" button (27 extra stops); dimmed letters not marked disabled; touch jump is a DragGesture | Messages/NewMessageSheet:412-450 | 2.5.8, 1.4.4, 2.5.7 | minor | common |
| The avatar button in the tab-root header is labelled "Settings" but opens your profile | Calls/RootHeader:26-44 | 2.5.3, 4.1.2 | minor | common |

### Emergency

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| Roll-up "needs help" entries use `onTapGesture` to open the person's thread with only `.combine` and no `isButton` (the full list at 397 has it) | EmergencyViews:337-352 | 4.1.2, 2.5.1 | major | emergency |
| **Status changes and "need help" arrivals are not announced**; the panel updates silently | EmergencyViews:355-433 | 4.1.3 | major | emergency |
| A send failure goes through the 2 s banner; on send `dismiss()` happens with no spoken confirmation | EmergencyViews:223 | 4.1.3 | major | emergency |
| The card label is red 12 pt text (3.34:1); the word EMERGENCY and the icon are not colour-only | EmergencyViews:33,42 | 1.4.3 | minor | emergency |
| The "EMERGENCY" title is not a heading; the student stepper is two buttons plus a Text, not an adjustable element (labels present) | EmergencyViews:76-78,122-127 | 2.4.6, 4.1.2 | minor | emergency |

Good: Safe/Need-help has `isSelected` and moves focus on appear; the Emergency long-press has a named accessibility action; Close is 60 pt.

### Settings (root and pages)

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| Every row's value Text is `lineLimit(1)` beside the title in one HStack, no vertical fallback at accessibility sizes | SettingsView:225-236 | 1.4.4, 1.4.10 | major | settings |
| Settings root: chevrons and row icons not hidden (VoiceOver may read symbol names, UNVERIFIED); external-link rows (Donate, Terms, Privacy, Guidelines, Safety) have no "opens in browser" hint | SettingsView:103-106,200,233,427-443 | 1.1.1, 3.2.4 | minor | settings |
| Text size: the Text size/Font segmented Picker's accessibility label is "Settings" | TextSizeScreen:27 | 2.4.6, 4.1.2 | minor | settings |
| **Background cover crop is DragGesture + MagnifyGesture only** (hint "Drag and pinch"), no adjustable steps or custom actions: VoiceOver/Switch Control users cannot reposition | BackgroundScreen:244-255 | 2.5.7, 2.5.1 | major | profile |
| Background: busy ProgressView and problem text not announced; the visibility footer sits after the card and is not a heading | BackgroundScreen:44-51,171 | 4.1.3 | major | settings |
| Change password: error not announced or tied to the field, done state not announced, the busy ProgressView has no label (the code field has oneTimeCode and paste: good for 3.3.8) | AccountScreens:93-141 | 4.1.3, 3.3.1 | major | settings |
| **Blocked: "Unblock" has no person name in its label**, minHeight 36, does not announce, the row is not grouped | AccountScreens:283-292 | 2.4.6, 4.1.2, 2.5.8 | major | settings |
| **Notifications: "Unmute" has no chat name**; several muted chats all read "Unmute" | NotificationScreens:149-160 | 2.4.6, 2.5.3 | major | settings |
| Notifications: the explainer sheet has a fixed `.medium` detent with a Spacer and no ScrollView; clips at accessibility sizes | NotificationScreens:187 | 1.4.4, 1.4.10 | major | settings |
| **Add-your-own-sound sliders (Start, Length) have no accessibilityLabel**: VoiceOver reads a bare percentage; the preview play has no stop control | SoundScreens:75-77 | 4.1.2, 1.3.1 | major | settings |
| Custom-sound Rename/Delete only in `.contextMenu` (footnote: "Press and hold"), no accessibilityAction (UNVERIFIED); the sound preview has no visual/text equivalent | NotificationScreens:45-89,122-138 | 2.5.1, 1.2.1 | minor | settings |
| Sounds: title not a heading, Cancel without a 44 pt minimum | SoundScreens:63,94-95 | 4.1.3 | minor | settings |
| Account Email row, Linked-devices row and Storage size rows are not grouped; Linked-devices icon unlabelled | AccountScreens:14-26,342; StorageScreens:15-16,74-83 | 1.3.1 | minor | settings |
| Safety Numbers: the fingerprint is read as a run of characters, no spoken grouping; mono font ignores lime's text size; Acknowledgements mono caption likewise | AccountScreens:317-320,481 | 1.3.1, 1.4.4 | minor | settings |
| Delete account: error not announced; destructive button white on red 3.55:1 (disabled: white 0.6 on red 0.4); typing "DELETE" is a typing confirmation, not a cognitive test | DeleteAccountScreen:88-140 | 3.3.8, 1.4.3, 4.1.3 | minor | settings |
| Links editor: "Saved ✓" and the error footer not announced; visibility rows have no group heading | LinksScreen:36-50,72-89 | 4.1.3, 1.3.1 | minor | profile |
| Edit field: the hidden `EmojiKeyboardField` overlay (1×1, opacity 0.01) is not hidden from VoiceOver (UNVERIFIED stray stop); validation not announced; the emoji button's label does not carry the current emoji | ProfileScreens:19-22,39,57,68-90 | 4.1.3, 4.1.2 | minor | profile |
| Not reviewed in depth: WorkHoursScreen, StatusSheet, ProfilePhotoScreen, MyGIFsSettingsScreen, ChatAppearanceSheet (day chips have labels and `isSelected`) | StatusViews:99,194; PhotoScreens:173; GIFLibrary:289 | — | UNVERIFIED | settings |

Checked, nothing found: Appearance (accent grid: ring + check, names, guarded ink), Privacy toggles, Calls settings, Links list edit mode (VoiceOver Move up/down), Storage media rows.

### Profile

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| **Shared-media grid cells use `onTapGesture` with label "Photo"/"Video" only**: no `isButton`/`isImage`, no description, no alt text | ProfileView:795-798,955-958 | 4.1.2, 1.1.1 | major | profile |
| **Shared links and files rows: `onTapGesture` with no `isButton`/`isLink` and no combined label** (FileRow not combined) | ProfileView:906-941 | 4.1.2 | major | profile |
| Hero video loops muted for up to 10 s with no visible pause control; pause exists only as a VoiceOver custom action "Pause background" (a blank-named action when there is no video); it respects Reduce Motion, Low Power Mode and scenePhase | ProfileView:346-354,501; ProfileHero:241-246; ProfileHeroVideo:37-84 | 2.2.2, Reduce Motion | minor | profile |
| White name and lines over a user photo with an adaptive scrim (designed for 4.5:1, stronger for Reduce Transparency/Increase Contrast); real contrast UNVERIFIED; the name is not `.isHeader` | ProfileHero:6-11,198-215; ProfileView:468-476 | 1.4.3, 2.4.6 | minor | profile |
| "Copied" toast not announced; several "See all" links without the kind in the label; value text `lineLimit(1)`; the username-copy row has no hint; the hero `.animation(.easeInOut)` is not gated | ProfileView:283-289,304-315,756-826 | 4.1.3, 2.4.4, 1.4.4, Reduce Motion | minor | profile |
| Tabs: ", tab, 1 of N" is hard-coded in the label instead of tab traits (not localisable) | ProfileView:983-1007 | 4.1.2 | minor | profile |

Checked, nothing found: edit pencils (44 pt, labelled), links card (`isLink`, SFSafariViewController), AmbientHero drift (gated by Reduce Motion and Low Power).

### Onboarding (sign-in, sign-up, code, terms, password)

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| **Visible field labels ("Email or username", "Password", "Name") are separate Text; the TextField/SecureField name is only the placeholder** ("you@example.com", "Your password"): VoiceOver and Voice Control read the placeholder | OnboardingComponents:86-166 | 1.3.1, 3.3.2, 2.5.3 | major | onboarding |
| Error line is a fixed red #B82B33: 5.76:1 on the light canvas, **2.87:1 on the dark canvas**; not announced | OnboardingComponents:56-62; OnboardingScreens:161,300,328 | 1.4.3, 4.1.3 | major | onboarding |
| **Fixed-height sheets with no scrolling**: ConfirmationSheet `.height(320)`; the Terms-updated sheet `.medium` with a Spacer and `interactiveDismissDisabled`, so at accessibility sizes "I agree" may need scrolling that is not there | OnboardingScreens:169,420 | 1.4.4, 1.4.10 | major | onboarding |
| Code entry: the real field is invisible (opacity 0.01) labelled "Code from the email" (boxes hidden from VoiceOver; oneTimeCode and paste supported: good); box digits fixed `.system(title)`, 8 boxes may clip at AX sizes (UNVERIFIED); the Resend label changes every second | OnboardingScreens:187-231 | 1.4.4, 3.3.8, 4.1.3 | minor | onboarding |
| Terms screen: the checkbox is a Button with `.isToggle`, label and value (good); the Terms/Privacy/Guidelines buttons have no link trait | OnboardingScreens:353-390 | 4.1.2 | minor | onboarding |
| Welcome headline is not a heading; Terms/Privacy are markdown links in a Text with `.underline()` (link rotor UNVERIFIED) | OnboardingScreens:31-46 | 2.4.6 | minor | onboarding |
| The scaffold's top bar is fixed 60 pt with fixed 18 pt icons; "Next" shows a ProgressView with no spoken state; step change `.animation(.easeInOut)` ungated | OnboardingComponents:19-38,196-215; OnboardingScreens:82 | 1.4.4, 4.1.3, Reduce Motion | minor | onboarding |
| Invite flow: icon not hidden; "Invite a teacher" not a heading | InviteScreens:183-204 | 1.1.1, 2.4.6 | minor | onboarding |

Good: password show/hide has labels and posts "Password shown/hidden"; `OnboardingModel` not read; no cognitive test or CAPTCHA seen (3.3.8 OK).

### Move, QR, Report, Moderation

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| **"Verify in person" is camera-only**: no manual compare or paste (Debug only); Safety Numbers says compare "is coming later"; a blind or Switch Control user cannot verify; the camera preview has no label or hint | QRScreens:100-141,296-302 | 2.1.1, VoiceOver | major | profile |
| Scan states (checking, found, mismatch) are not announced; the mismatch warning is red 14 pt on red@0.1 ≈ 3.1:1 | QRScreens:129-141,209-216 | 4.1.3, 1.4.3 | major | profile |
| **Report sheet: the "sent" state swaps the form for a thank-you with no announcement or focus move**; the send failure is red caption text, not announced | ReportSheet:25-34,91,144-160 | 4.1.3, 1.4.3 | major | profile |
| Move: the 6-digit code is fixed `.system(size:52)` with `minimumScaleFactor(0.6)` and `lineLimit(1)`; "Copy the code" gives no confirmation; "Looking for…/Waiting…" and the old phone's done state not announced (progress every 10 %, failure and moved-away are) | MoveViews:19-26,230-232,284,345-357 | 1.4.4, 4.1.3 | minor | settings |
| Moderation (moderator-only): red text on a surface 3.34:1, URGENT pill, card titles not headings | ModerationScreen:49,97,110,193 | 1.4.3 | minor | profile |

Good: Move's QR has a text fallback (DisclosureGroup with copy/paste) and an "Enter the code" alternative.

### Shell, tab bar, banners

| finding | where | WCAG | severity | area |
|---|---|---|---|---|
| Re-tap on the selected tab (scroll to top/pop to root) is detected by a gesture recognizer on raw touches: VoiceOver, Switch Control and Voice Control activations may not produce touches (UNVERIFIED) | TabRetap:46-87 | 2.1.1 | minor | common |
| Tab labels are lowercase "link/call/jam" (unclear to VoiceOver users as Messages/Calls/Jam); the badge text is fixed 12 pt; badge contrast not computed | RootView:77-86; TabBadgeStyle:13 | 2.4.6, 1.4.4 | minor | common |
| No focus management when the call screen opens (starts at the first element) | RootView:43-60 | 2.4.3 | minor | calls |
| **The offline/problem banner appears and disappears with no announcement and no live-region trait**; it is the only cue for offline-first behaviour (relay/Bluetooth); the low-storage banner likewise | Messages/MessagesView:329-383,787-802 | 4.1.3 | major | common |
| Nearby: the offer bar (Debug) appears silently, and there is no persistent indicator that Nearby/relay mode is active | Chat/ChatView:1348-1384; AccountScreens:234-238 | 4.1.3 | minor | common |
| About (Debug): self-test results change with no announcement | About/AboutView | 4.1.3, 2.5.1 | minor | settings |
| **ConfirmSheet (used for ~30 confirmations)**: `.height(min(measured, 640))` with no ScrollView, so at accessibility sizes with 3-6 buttons Cancel can be pushed off screen; tap-to-dismiss uses a `simultaneousGesture` (tapping a gap closes it); destructive text red 3.3:1 | Common/ConfirmSheet:43,60 | 1.4.4, 1.4.10, 1.4.3 | major | common |

### Coverage

Read fully: Calls (CallView, CallHeaderViews, RootHeader, CallsTab, CallMiniPlayer, GroupCallView; GroupCallLayout grepped), EmergencyViews, Settings (SettingsView, TextSizeScreen, AppearanceScreen, BackgroundScreen, AccountScreens, NotificationScreens, SoundScreens, StorageScreens, CallSettingsScreen, DeleteAccountScreen, LinksScreen, ProfileScreens), Profile (ProfileView, ProfileLinks, ProfileHero 150-394, AmbientHero 215-277; ProfileHeroVideo grepped), Onboarding (OnboardingScreens, OnboardingComponents), Invite (InviteScreens, QRScreens), MoveViews, Moderation, AboutView, Common, App (RootView, TabBadgeStyle, TabRetap), plus Core/Calls/CallEffects and PiPGridView, Theme/Glass, FloatingPlus, NewMessageSheet pieces, ChatView helpers, MessagesView banners. **Skipped or only grepped:** EmergencyModel, FieldEditorModel, ChangePasswordModel, AppearanceSetting, OnboardingModel, DebugOnboarding, Invite/Invite.swift, GroupCallLayout, ProfileHero 1-150, ProfileHeroVideo internals, the Core/Calls managers, all `ConversationStore+*` files, AvatarView/StatusBadge, ThemeBackgrounds, Jam profile sections, ChatAppearanceSheet, ProfilePhotoScreen, MyGIFs, IncomingBannerView, DraftInviteBanner, JoinBandSheet. **UNVERIFIED on device:** the glass/material Reduce Transparency fallback, VoiceOver reading of SF Symbols inside labelled Buttons, context-menu exposure to VoiceOver, tab re-tap under assistive tech, the AX-size clipping findings, real hero contrast over user photos, Bold Text on custom fonts, the effects' flash rate.


## The failing `GroupCallHeaderUITests…ThePillOpensThePeopleSheet…` test

Run on **both** the iPhone 17 (iOS 27.0) and the **Lime 13 mini 27** simulator, `-only-testing:LimeUITests/GroupCallHeaderUITests` (logs: `docs/qa-shots/130/groupcall-17.log`, `groupcall-mini.log`).

| device | result |
|---|---|
| iPhone 17 | 3 tests, **1 failure**: `testThePillOpensThePeopleSheetWhichHasTheLayoutAtTheTopAndMinimiseStaysInTheControls` |
| 13 mini | 3 tests, **1 failure**: the same test (the other two pass on both) |

**It is not mini-specific, and it is not the detent or the layout buttons.** The failure is at `GroupCallHeaderUITests.swift:41`: `Failed to get matching snapshot: No matches found for Elements matching predicate '"People" IN identifiers'`, i.e. `app.staticTexts["People"]` is not found. The assertions before it (the pill opens the sheet, `Layout: Grid` and `Layout: Speaker` exist, Grid is `Selected`) are on lines 36-40 and pass. The sheet's section header is `Section("People")` in `GroupCallView.swift:384`; on iOS 27 a List section header is evidently not exposed as a static text with the identifier or label "People" (a different element type, or a different case, UNVERIFIED). So the test's way of finding the header is out of date; the sheet itself works. **Suggested fix (for the calls brief):** locate the header by `app.otherElements`/`descendants(matching: .any)` with the label, or give the header an accessibility identifier, rather than opening the sheet at `.large` on small screens.

## VoiceOver walk-through script for the gate (Settings → Accessibility → VoiceOver on; a real iPhone; triple-click side button to toggle)

Do each step with VoiceOver on and your eyes off the screen if you can. **Today the audit expects the steps marked ⚠ to fail or be confusing**; the point of the walk-through is to hear how bad each is, and to re-run it after the fixes.

1. **Messages.** Swipe right through the list. Each chat should read as one item (name, last message, time, unread count, muted/pinned). ⚠ Does it tell you the person's status (available, away)? Double-tap a chat to open it.
2. **Send a message.** Find the "Message" field, type, find Send. ⚠ Does the new message get announced when it is sent? Does a failed one say so?
3. **Hear the chat.** Swipe through the messages. ⚠ In a one-to-one chat, does anything say who wrote a message? Each message is 3-6 stops (text, time, reactions): is that bearable?
4. **React and reply.** Land on a message and look for actions: swipe up/down for the actions rotor. ⚠ Expect no "React", "Reply" or "Delete". Try double-tap-and-hold. This is the first blocker (all message actions are long-press only).
5. **Voice message.** ⚠ Find the microphone button and try to record one (double-tap and hold). Expect it to fail (second blocker). Play a received voice message: can you hear progress or scrub?
6. **Start a call.** Calls tab → a person → call. On the call screen find Mute, Speaker, Camera, End. ⚠ Does Mute say whether it is on? For a **video** call wait 6 s, then try to reach End call (third blocker: the controls hide and are no longer reachable).
7. **Minimise and return.** Use Minimise, find the mini player, return to the call (it has an action: "Return to call"), end the call. ⚠ Is "call ended" announced?
8. **Answer a call.** Have someone call you: is the incoming call announced? Accept/Decline.
9. **Settings → Text size.** Settings (top right) → Customize → Text size: move the slider with swipe up/down; the value should be spoken. ⚠ Settings group titles (Keep media, …) are not headings: use the Headings rotor in Storage.
10. **Jam.** Open Jam, swipe through a post: ⚠ a post card is 5-8 stops. Open an article: use Back. ⚠ Does the screen's two-finger "Z" scrub go back? Play a podcast.
11. **Sign-up screen (use a test address).** The terms checkbox reads "I teach, I'm 18 or older, and I agree… not checked"; the fields: ⚠ do they say "Email or username", or only the placeholder?
12. **Then (no VoiceOver):** set the **largest text size** (Settings → Accessibility → Display & Text Size → Larger Text → Larger Accessibility Sizes, slide to the end) and use Messages, a chat, Calls and your profile; then turn on **Reduce Transparency**, **Reduce Motion**, **Increase Contrast**, **Differentiate Without Color** and **Bold Text** and look at a chat, the call screen and the jam feed.

## What this audit did not do

- **Real VoiceOver, Voice Control and Switch Control on a device:** not run (Phase 1 needs no device install). The VoiceOver findings come from reading the code and from the simulator audit's element checks, and the items marked UNVERIFIED need the walk-through above.
- **The iPhone 13 mini size** was used only for the group-call test above; the screenshots and the audit passes are the iPhone 17.
- **Photos, video and live call video** behind text cannot be measured statically (listed as risk).
- **Dark mode** was audited for the same screens (third pass); **Increase Contrast, Reduce Transparency and Reduce Motion** were not toggled in the simulator passes.
- **The audit tool's own limits:** it checks element descriptions, hit areas (< 44 pt), clipping, Dynamic Type support and the contrast of text it can see; it cannot judge reading order, announcements, gesture-only actions or meaning, which is why the code review exists.


## LIME-321 status (130-m1: the minors for common, chat, attachments and calls)

Added by LIME-321 (2026-11-11). Nothing above is changed; line numbers are this file's own. **Fixed already** = by an earlier 130 brief; **Fixed in 321** = changed now; **Ask / deferred** = needs a product decision, a device check, or is acceptable as it is. No row is stale (the code moved but every finding still pointed at something real).

| line | status | note |
|---|---|---|
| 203 | ask / deferred | disabled text is exempt from 1.4.3; labels stay readable (deferred) |
| 204 | fixed in 321 |  |
| 205 | fixed in 321 |  |
| 209 | fixed in 321 |  |
| 210 | already fixed | 130-3a (the ring and ', including you') |
| 211 | already fixed | 130-2/130-4 (`Theme.danger`, the word Missed) |
| 213 | ask / deferred | nothing is carried by colour alone in the call controls, the Missed word or the badges; no branch added (deferred until a colour-only state turns up) |
| 214 | already fixed | 130-2/130-7 (the theme resolves Increase Contrast) |
| 225 | already fixed | 130-2 (Glass.swift) |
| 227 | ask / deferred | about 290 fixed glyph sizes, mostly in fixed circles (deferred; the text cases are separate findings) |
| 228 | fixed in 321 |  |
| 229 | fixed in 321 |  |
| 235 | fixed in 321 |  |
| 236 | fixed in 321 |  |
| 237 | fixed in 321 |  |
| 238 | fixed in 321 |  |
| 239 | fixed in 321 |  |
| 240 | fixed in 321 |  |
| 243 | fixed in 321 |  |
| 253 | fixed in 321 |  |
| 254 | fixed in 321 |  |
| 268 | fixed in 321 |  |
| 273 | already fixed | 130-3a (a named Play GIF action) |
| 277 | fixed in 321 |  |
| 280 | fixed in 321 |  |
| 281 | fixed in 321 |  |
| 282 | fixed in 321 |  |
| 292 | fixed in 321 |  |
| 293 | fixed in 321 |  |
| 294 | fixed in 321 |  |
| 295 | fixed in 321 |  |
| 296 | fixed in 321 |  |
| 303 | fixed in 321 |  |
| 311 | fixed in 321 |  |
| 312 | fixed in 321 |  |
| 314 | fixed in 321 |  |
| 315 | fixed in 321 |  |
| 316 | fixed in 321 | labels, announcement and the Send-to flows fixed; the picker's fixed row height and the .regularMaterial fallback are deferred |
| 324 | fixed in 321 |  |
| 325 | fixed in 321 |  |
| 327 | fixed in 321 | Saved to Photos announced, React expanded/collapsed, 44 pt targets; the zoom photo's label was already alt-aware |
| 329 | ask / deferred | captions for chat videos are a product decision; the close button over AVKit's controls is a layout question |
| 338 | fixed in 321 |  |
| 340 | fixed in 321 |  |
| 362 | ask / deferred | the sites are jam files: 130-m3/m4 (LIME-323/324) |
| 363 | ask / deferred | the sites are jam files: 130-m3/m4 (LIME-323/324) |
| 366 | ask / deferred | the sites are jam files: 130-m3/m4 (LIME-323/324) |
| 367 | ask / deferred | the sites are jam files: 130-m3/m4 (LIME-323/324) |
| 426 | fixed in 321 | the full-screen photo now reads its description; a zoom control is a behaviour change (deferred) |
| 495 | fixed in 321 |  |
| 500 | fixed in 321 |  |
| 535 | ask / deferred | Bold Text needs a device check; nothing reads legibilityWeight |
| 536 | already fixed | 130-2 |
| 537 | fixed in 321 | the 40 pt circles are 44 now; fixed glyph sizes deferred |
| 554 | already fixed | 130-4a |
| 555 | already fixed | 130-4a |
| 556 | already fixed | 130-4c |
| 557 | ask / deferred | the audit itself says acceptable for call controls |
| 558 | ask / deferred | visible Accept/Decline captions would be a layout change |
| 559 | already fixed | 130-4a |
| 566 | already fixed | 130-4b |
| 567 | already fixed | 130-4b |
| 568 | already fixed | 130-4b |
| 569 | fixed in 321 | grabber hidden, hints added; the .regularMaterial fallback is deferred (the system usually handles it) |
| 570 | already fixed | 130-4b |
| 571 | fixed in 321 |  |
| 581 | already fixed | 130-4b |
| 582 | fixed in 321 |  |
| 583 | fixed in 321 |  |
| 584 | ask / deferred | a 28 pt frame glyph (acceptable) |
| 590 | already fixed | 130-5a/earlier (one adjustable rail) |
| 591 | fixed in 321 |  |
| 674 | ask / deferred | needs a device test with VoiceOver, Switch Control and Voice Control |
| 675 | ask / deferred | renaming the tabs is a product decision; the 12 pt badge font is deferred |
| 676 | fixed in 321 |  |
| 678 | fixed in 321 |  |

## LIME-322 status (130-m2: the minors for profile, settings, themes, onboarding, emergency, groups)

Added by LIME-322 (2026-11-11). Same meaning as the table above: **already fixed** (an earlier brief), **fixed in 322**, **ask / deferred**. No row is stale.

| line | status | note |
|---|---|---|
| 193 | already fixed | 130-7 (the guard sweep covers link on surface) |
| 195 | already fixed | 130-7 (secondary checked on the pill fills) |
| 197 | already fixed | 130-7 (text pairs at 4.5:1; the hairline is 3:1 only with Increase Contrast, left: nothing relies on it alone) |
| 212 | already fixed | 130-2 (`Theme.danger` is guarded; the label is text) |
| 215 | ask / deferred | hairline and bubble-edge colours would change the look: a design decision (nothing relies on the hairline alone) |
| 241 | already fixed | 130-2 (away/DND colours re-chosen; shape carries it) |
| 257 | fixed in 322 | wallpaper chips on the three quiet lines |
| 276 | fixed in 322 | the voice message's time uses the guarded caption colour |
| 313 | ask / deferred | the composer's font does not follow a chat's own text size; needs a signature change and a device test |
| 339 | fixed in 322 | chips 44 pt; the count is spoken as people are picked |
| 343 | ask / deferred | white name over a photo: contrast per photo needs a device test; a scrim on the name is a visual change |
| 345 | fixed in 322 | the spinner is "Working" and a problem is announced |
| 346 | fixed in 322 | names wrap at accessibility sizes (a confirmation for Reset is ask) |
| 600 | already fixed | 130-2 |
| 601 | fixed in 322 | the sheet title is a heading; with VoiceOver the students row is one adjustable element (the buttons stay for touch) |
| 610 | fixed in 322 | chevrons and icons hidden; external links say "Opens in your browser" |
| 611 | fixed in 322 | the picker is named "Text size or font" |
| 619 | fixed in 322 | Rename and Delete are actions on the custom sounds (the footnote wording is ask) |
| 620 | fixed in 322 | title is a heading; Cancel is 44 pt |
| 621 | fixed in 322 | Email, Linked devices and Storage rows are one stop for VoiceOver |
| 622 | fixed in 322 | with VoiceOver the fingerprint is read character by character (the mono font not scaling is ask) |
| 623 | already fixed | 130-5a (`dangerFill` with white text; the error is announced and a hint) |
| 624 | already fixed | 130-5a (announced; the visibility heading is a Section header) |
| 625 | fixed in 322 | the emoji field overlay is hidden; the emoji button names the current emoji |
| 636 | fixed in 322 | the blank hero action is gone (a visible pause button is ask) |
| 637 | fixed in 322 | the name is a heading (contrast over real photos needs a device check) |
| 638 | fixed in 322 | "Copied" announced; "See all" names its list; values wrap; the hero fade honours Reduce Motion |
| 639 | ask / deferred | the tab label's hard-coded ", tab, 1 of N" is a wording decision (and a localisation one) |
| 650 | fixed in 322 | Resend code keeps one name, the wait is its value (box clipping at accessibility sizes needs a device check) |
| 651 | fixed in 322 | Terms, Privacy and Guidelines are links |
| 652 | fixed in 322 | the welcome headline is a heading (the markdown links need a device check) |
| 653 | fixed in 322 | the top bar grows with the text; Next says Working; the step animation honours Reduce Motion |
| 654 | fixed in 322 | the icon is hidden; the title is a heading |
| 665 | fixed in 322 | the code scales with the text; copy, looking, waiting and done are announced (wrapping the code is ask) |
| 666 | fixed in 322 | card titles are headings |
| 679 | fixed in 322 | the self-test result is announced |


## LIME-323 status

First 31 jam minors plus rows 362, 363, 366, 367 (jam files). Line numbers are the audit's.

| Row | Status | Note |
|---|---|---|
| 207 | open | prompt and unplayed-waveform contrast: carried to LIME-324 |
| 369 | already fixed | the tap cards carry the button trait or inner Buttons; the link card too |
| 379 | fixed | the dot is hidden under VoiceOver and Switch Control; the card label says "New comments" (mine only) |
| 380 | fixed | name, "by" and byline wrap at accessibility sizes |
| 381 | fixed | request cards announce who added you; Accept/Decline carry the post title |
| 382 | fixed | post count announced after load; the empty result is announced when shown |
| 383 | fixed | same: the filtered count and the empty state are announced |
| 384 | fixed | the highlight fade honours Reduce Motion |
| 385 | fixed | "Showing the whole post" is announced; the expansion honours Reduce Motion |
| 386 | fixed | the spoken label is "Saved" (menu and options row); the icons are hidden |
| 394 | already fixed | the card-level tap is not an element; the cover, title and pill are the Buttons |
| 395 | open | org name truncation and the fixed 96 pt cover: carried to LIME-324 |
| 396 | open | scrubber height and unplayed-bar contrast: carried to LIME-324 |
| 398 | fixed | "Reading speed" now has a spoken value |
| 399 | fixed | read-aloud announces Listening, Paused, Stopped and Finished (player queue start is open, LIME-324) |
| 401 | open | scrim behind the caption and elapsed time: carried to LIME-324 |
| 404 | fixed | the audio cover is no longer an element |
| 405 | fixed | Subscribe pills are 44 pt |
| 406 | open | marquee runs forever with motion allowed: carried to LIME-324 |
| 407 | open | skip intervals differ between lock screen and screen; a choice: ask |
| 417 | already fixed | the top bar is hidden from VoiceOver while it is off screen |
| 418 | fixed | the jam name line is a heading |
| 419 | fixed | the find field has a name |
| 420 | open | selection by border plus .isSelected: carried to LIME-324 |
| 421 | already fixed | destructive rows use Theme.danger (guarded to 4.5:1); the icon scales |
| 422 | fixed | see 399 |
| 423 | already fixed | the export carries alt text |
| 424 | already fixed | Remove uses Theme.danger and a labelled name |
| 425 | already fixed | photo tiles say their alt text when there is one |
| 433 | fixed | Reply and ⋯ are 44 pt; both say whose comment |
| 435 | fixed | each row reads "Comment by" or "Reply by"; Reply says "Reply to NAME" |
| 362 | partly fixed | feed, highlight, expand, scroll: done; Discover, player tint, cursor tag: carried to LIME-324 |
| 363 | open | fixed icon sizes in 60+ places (options row done): carried to LIME-324 |
| 366 | partly fixed | stacked opacity removed in CreatePublication, EditSeriesSheet, NewBandGroupSheet; BeforePublish, OrgFieldSheet and the dummy buttons: LIME-324 |
| 367 | partly fixed | options rows hide their icons; JamReader and OrgGroupsTab: LIME-324 |
