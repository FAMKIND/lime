# Android calls: the two-real-phones test

What the emulators cannot prove (a real microphone and camera, a real ringer, a lock screen, Bluetooth, the battery and what iOS and Android do to each other). **Two real phones, ideally one Android phone and one iPhone, plus a third phone for groups.** About 45 minutes. Phone **A** is the Android phone under test; **B** is the other phone (an iPhone for rows marked *iOS*, otherwise a second Android phone); **C** is a third phone for the group rows.

Each row has what to do on each phone, what the network is (**I** = internet on, **BT** = Bluetooth, **lime** = lime's own nearby mode, not used by calls yet: calls need the internet) and what to see. Tick a row only if every "see" is true. A teacher account on each phone; A and B have already exchanged one message and accepted the chat (a call to a phone that has not accepted is dropped by the core).

Before you start: Android 12 or later on A if you can (rows 10 to 12 are about Android 12+), A on a debug or release build from `android`, Settings → Calls open once so the ring status line is on screen.

## 1:1 audio

| # | Phone A (Android) | Phone B | Network | You should see and hear |
|---|---|---|---|---|
| 1 | lime open on the Calls tab; tap B's phone button | lime open | A: I, B: I | B's call screen rings; A hears ringback; B answers; both show the same **four emoji** and a running time; speech both ways, **no echo** on speaker, none at the ear |
| 2 | Same call: tap **Speaker**, then **Mute** | B talks | I | the sound moves to the loudspeaker; B stops hearing A when muted and B's screen shows "Muted" |
| 3 | Hold the phone to the ear in a voice call | | I | the screen goes dark at the ear and wakes when moved away (the proximity sensor); not on the speaker |
| 4 | B calls A (*iOS* if you have one) | B places the call | I | A rings; A answers; same emoji on both; audio both ways between Android and iOS |
| 5 | Switch Wi-Fi to mobile data mid-call | | A: I changes | the call survives a few seconds of silence or reconnects; it does not end |

## 1:1 video

| # | Phone A | Phone B | Network | You should see |
|---|---|---|---|---|
| 6 | Video call to B from the Calls tab | answers | I | both pictures; the small tile of the near phone's picture is **not mirrored wrongly**; B's picture fills A |
| 7 | **Flip camera**; **Camera** off and on | | I | the other side sees the flip; on camera off they see the avatar and "<Name>'s camera is off", never a frozen frame |
| 8 | In a **voice** call tap **Video** | B's screen turns to video with **B's camera off** | I | B turns the camera on and both pictures show; the sound moved to the speaker; one entry in the history, marked video |
| 9 | iOS → Android video | B (iOS) calls A | I | picture and sound both ways; a mid-call upgrade from either side works (the control channel is the same JSON on both) |

## Routes and the phone's own surfaces

| # | Phone A | Phone B | Network | You should see |
|---|---|---|---|---|
| 10 | Connect a Bluetooth headset, start a call | | I, BT | the sound goes to the headset (on Android 12+ the first time **Allow Bluetooth headsets** is in the audio-output list); switch the headset off: the sound returns to the phone and "Audio now on Phone" shows |
| 11 | Wired headphones in and out during a call | | I | the sound follows the headphones; unplugging does not blast the speaker |
| 12 | Open the audio-output list | | I | the routes the phone has, a tick on the current one, the button's words say "Audio output, now …" |
| 13 | **Lock** A; B calls | B places a voice call | I | A takes the **lock screen** with the caller's name and Answer and Decline and rings with the ringtone and vibration; **Answer** connects without unlocking |
| 14 | Unlocked, lime in the **background** (Home) | B calls | I | a heads-up banner with Answer and Decline rings; tapping Answer opens lime in the call; **Decline** declines without opening lime |
| 15 | lime in front | B calls | I | the call screen rings, **no** notification |
| 16 | Phone's Do Not Disturb on | B calls | I | silent; a missed call appears in A's Calls tab; B is told **nothing** |
| 17 | Settings → Notifications → lime → turn **Incoming calls** off | B calls | I | no ring behind the app; Settings → Calls says why in words; the in-app ring still works with lime open |
| 18 | Android 14+: turn **Full-screen notifications** off for lime | B calls (A locked) | I | a heads-up banner that rings instead of the full-screen call; Settings → Calls says so and has the button to the phone's page |
| 19 | In a call press **Back** | | I | the bar under the status bar on Messages, Jam, a chat, Settings: name, time, **Mute**, **End**; tap the name to return |
| 20 | In a **video** call press **Home** | B watches | I | A floats in Picture in Picture with a Hang up button; B sees A's avatar while A's camera is held; back in lime the camera returns |
| 21 | Swipe lime away from recents during a call | | I | the call ends (the foreground service stops); no notification is left behind |
| 22 | lime closed (swiped away), B calls | | I | no ring (no push service yet: DESIGN-37); B hears nothing; after 45 s B's call ends as "No answer" |

## Group calls

(Needs a group of A, B and C, all accepted.) The group call carries **LiveKit's end-to-end frame encryption with each person's own key**; the server forwards ciphertext only. Both of these rows are the first time Android and iOS meet in a group call: a failure here is the most important finding of the day.

| # | Phone A | Phones B, C | Network | You should see |
|---|---|---|---|---|
| 23 | In the group chat tap **Voice call** | B and C see the banner (lime open) and tap **Join the call** | all I | three tiles; each says "Securely connecting…" for a moment and then shows the person; speech between all three; the **same four emoji on all three** |
| 24 | **Video call** in the group | B (*iOS*) and C (Android) join | all I | every picture on every phone, Android ↔ iOS both ways (**if an Android tile stays "Securely connecting…" or black for more than 20 seconds with an iPhone in the call, the key interop is broken: stop and report it**) |
| 25 | Mute, camera, flip; **Leave** | C leaves first | all I | the mute mark and ring around the speaker show on the others; when C leaves the call goes on for A and B; the emoji change (keys were renewed) and both still hear each other |
| 26 | Press Back in the group call | | I | the mini-bar (the group's name, time, Mute, Leave); tap to return |
| 27 | Join a call while the phone is on mobile data | | A: mobile data | the picture steps down (Low Data Mode on: smaller and slower) and holds |

## Battery and heat (one 20-minute video call)

| # | Phone A | Phone B | Network | Write down |
|---|---|---|---|---|
| 28 | 20-minute video call, screen on, battery at about 80% to start | same | I | the battery used and whether A gets hot to the touch; the call stays smooth the whole time |
| 29 | 20-minute **group** video call with 3 people | | I | the same; the picture should not drop to a slide show |

## When something fails

Note the row number, both phones, the network and what you saw, and send it with the time of the call: the app writes nothing about a call to any server except the call's own signalling, so the phone's logcat (`adb logcat -s lime`) and the other phone's screen are what there is.
