# Chat — Android differences

The spec is the iOS chat (`ios/Lime/Features/Chat/ChatView.swift`, `MessageText.swift`, `MessageSpeech.swift`); this page lists only where Android differs.

- **Header:** a back arrow, the avatar and the name; the system back gesture does the same.
- **Messages:** bubbles as iOS (own colour on the right, theirs on the left), run grouping, day separators, the time on the last of a run, "· Sending…", "· Sent", "· Not sent. Tap to retry", "· Not delivered. Tap to resend" under my newest message (and under any unsettled one). Each message is **one TalkBack stop** ("<who>, <words>, <time>, <state>, <reactions>, <replies>") whose actions (Copy, Reply, Retry sending) are TalkBack custom actions and also the long-press menu.
- **Composer:** plain text above the keyboard (`imePadding`); send is the one lime action (ink arrow on the accent circle, 56 dp). No formatting toolbar yet; text typed as Markdown (`**bold**`, `*italic*`) is drawn formatted.
- **Replies:** Reply sets a reply bar above the field; the reply goes into the message's thread (as on iOS) and the message shows "N replies", which opens a read-only list of the replies.
- **A stranger's first message:** the chat shows "<name> isn't in your chats yet. Accept to reply." with Accept (Block comes later); Requests lists them.
- **Not built yet:** photos and files, voice, reactions, edit, delete, forward, find, mentions, link previews, formatting toolbar, group management.

## Photos and new message (LIME-299)

- **Sending a photo:** the composer has a photo button that opens the system **Photo Picker** (no storage permission; up to 10). A chosen photo shows in a tray above the field with an "Alt" chip (48 dp) that opens "Describe this photo" (250 characters, travels inside the encrypted message, read by TalkBack). Photos are redrawn to at most 2048 px on the long edge, upright, with no EXIF/GPS, as JPEG quality 80, plus a tiny preview (iOS's rules).
- **In a chat:** a photo is a rounded 240 dp bubble (tiny preview first, the real picture once this phone has it; pictures download by themselves). The message is still **one TalkBack stop**: "<who>, <caption>, Photo: <description>, <time>, <state>", with an "Open photo" action. Tap opens a full-screen viewer (pinch to zoom, drag to pan, swipe between photos, the description at the bottom, Close and the system back).
- **New message:** the "+" (the one lime action on the list), or the empty state's cards. A search field ("Name, username or email"); Next looks up ONE exact username or email; the teachers you already message are listed A to Z and filter as you type. Results: the person (tap to message), "That's you. Try another teacher.", "No teacher found with that username or email.", or the problem in words. The chat you start is yours: accepted, in Messages.
- **Not built yet:** files and voice messages, videos, GIFs and stickers, the camera, "Scan QR code", "Invite a teacher".
