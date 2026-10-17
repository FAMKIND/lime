# Sending with no internet: the statuses, the banner and the switch (LIME-142)

For Android to match. All words are the app's own; none uses colour alone.

## A message's status (under the bubble, after the time)

| State | Words | Icon | Meaning | Tap |
|---|---|---|---|---|
| `sending` | Sending… | none | being sent | nothing |
| `waiting` | **Waiting for a phone nearby** | antenna waves | sealed and kept for nearby phones; no phone has taken a copy | nothing |
| `passed` | **Passed to a nearby phone** | arrow in a circle | another phone acknowledged taking a copy | nothing |
| `sent` | Sent | none | the server has it (by this phone, or by a relay that uploaded it) | nothing |
| `offline` | **Waiting for internet** | crossed Wi-Fi | cannot travel through nearby phones: a picture or file, someone who has not accepted you yet, or "Help pass on nearby messages" is off | **one line saying why** |
| `failed` | Not sent. Tap to retry | none, red | a real failure, or 48 hours with no route | retry |

- The first three offline states are **grey**, never red, and **have no retry**: sending resumes by itself on any link or connection.
- VoiceOver / TalkBack read the words in full ("Waiting for a phone nearby"). "Waiting for internet" is a button (hint "Says why").
- A message that is in flight (`sending`, `waiting`, `passed`, `offline`) cannot be reacted to or replied to yet.
- No animation when a status changes with Reduce Motion on (there is none otherwise either).
- **The one-line reasons** (the alert on tapping "Waiting for internet"): a file: "Pictures and files need the internet. This goes as soon as you're connected." Someone who has not accepted you: "This person hasn't accepted your messages yet, so nearby phones can't carry this. It goes as soon as you're connected." Otherwise: "Nearby phones aren't passing messages on right now. This goes as soon as you're connected."

## The offline banner (the Messages list)

One element, at least 44 pt tall, a button (hint "Explains how messages are sent with no internet"):
- the mesh on: **"Offline: lime will send through nearby phones, and when you're back online."**
- the mesh off or not allowed: **"Offline: messages will send when you're back online."**
Tapping it opens a short sheet, "Sending with no internet": three short paragraphs: messages stay sealed on the phone and nearby phones running lime pass them on without being able to read them; a message moves when phones meet and at least one is awake, and not if lime has been swiped away, and it goes through when any phone carrying it (or this one) reaches the internet; pictures, files and messages to people who have not accepted you wait for the internet.

## The switch (Settings → Privacy)

**"Help pass on nearby messages"**, **on by default**, a switch row at least 44 pt tall, with the line "Uses a little battery. Messages you carry are sealed; you can't read them." Off: lime stops passing messages on for others and stops sending yours through nearby phones (offline sends wait for the internet).

## The explanation before Bluetooth

A one-time alert, shown the first time the phone is offline (or when the switch is turned on), never at first launch, before the system's Bluetooth prompt: "Pass messages phone to phone?" "lime can pass messages phone-to-phone when there's no internet. It uses Bluetooth, and iOS will ask you to allow it." Buttons: Not now (turns the switch off) / Continue.
