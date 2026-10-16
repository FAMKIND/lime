# Emergency mode and Nearby mode (LIME-143)

For the Android build. The rules are in LimeCore (`core/src/store/emergency.rs`, `core/src/client/emergency.rs`); the screens below are what the iOS app does. Debug-gated for now, like the mesh.

## Nearby mode

- Settings → Privacy, under "Help pass on nearby messages": **Nearby mode**. Off by default.
- On: lime scans without a duty cycle, and the screen stays awake **only while lime is in front** (iOS allows nothing more). Turns itself off after **2 hours** and asks "Turn on again?".
- Status line: **"Nearby mode on · keeps lime awake · uses more battery"**, plus "Keep your phone plugged in if you can, and keep lime open on the screen."
- The offer in a chat (once, ever): a message is "Waiting for signal", the mesh is on, no phone is in range, Nearby mode is off → "No signal. Keep lime awake to reach people nearby?" [Turn on Nearby mode] [Not now].
- Honest promise: delivery when phones meet and at least one is awake; not after lime is swiped away.
- Starting an emergency turns Nearby mode on.

## Emergency mode

**Setup (Settings → Emergency):** the emergency group (also: a group's ⋯ → "Make this my emergency group"); **"Safewords"** (on; "Show your school's safety words (Hold, Secure, Lockdown, Evacuate, Shelter) as quick choices."); "Emergency alerts make a sound" (off; "In a lockdown, a sound can reveal where people are hiding. Turn this on where loud is safer, for example natural disasters."); the "Call 911 first" line with the region's number (`emergency_number(region)`); and the honest note about background delivery until push exists.

**Starting:** long-press "+" in Messages, or "Emergency" in a group's ⋯ menu. (A Lock Screen / Control Center control is a later brief.)

**The sheet (one screen, every control ≥ 60 pt, VoiceOver order Status → Students → Where → Send):**
1. **"Call 911 first if you can"** (a tap places the call) and "lime does not alert the police. Call first."
2. **Safe / Need help**
3. The five SRP actions as chips (Hold, Secure, Lockdown, Evacuate, Shelter) when Safewords is on
4. **Students with me**: − / + (default: the last value used)
5. **Where**: free text, last value pre-filled; no GPS
6. A note (optional)
7. **Send to**: the emergency group, "Change"
8. **Send**: one tap

A status is a normal text message (so it travels the mesh like any message) with an `emergency` object in the payload (`api-v2.md` §13). Limits: place 60 characters, note 200, students 0–9999.

**The card (in the chat):** a small label row (the word **EMERGENCY** on one line, with an icon, in red; never colour alone), then the status line as the main text ("Safe · Lockdown · 24 students · Room 204"), the note, then the sender and time. At accessibility text sizes the label may wrap. Announced by VoiceOver as a whole. **Forwarding is disabled** for emergency messages (also in core).

**Announcing an arrival (`emergency_alert_policy(sound_enabled)`):**
- Shown even in Do Not Disturb / work hours / quiet hours / a muted chat (iOS "time sensitive"), **silent** (no sound, no vibration) unless the person turned the sound setting on.
- When lime is open: a banner, and a high-priority VoiceOver announcement.

**The roll-up panel (top of the group chat while an emergency is active):** one line per person; **Need help first, then No response yet, then Safe** (newest first within each); totals "N safe · N need help · N no response · N students"; tap a person → their chat; **Send my status**; **End emergency** (anyone; posts an end card "Emergency ended by <Name>"). The latest status of a person replaces earlier ones.


## Core API (UniFFI)

`send_emergency(conversation_id, EmergencyDraft)`, `end_emergency(conversation_id)`, `emergency_rollup(conversation_id) -> EmergencyRollup?`, `emergency_settings()` / `set_emergency_settings(..)`, `emergency_alert_policy(sound_enabled) -> EmergencyAlert`, `emergency_number(region) -> String`; `MessageItem.emergency: EmergencyInfo?`.
