# Chat — Android differences

The spec is the iOS chat (`ios/Lime/Features/Chat/ChatView.swift`, `MessageText.swift`, `MessageSpeech.swift`); this page lists only where Android differs.

- **Header:** a back arrow, the avatar and the name; the system back gesture does the same.
- **Messages:** bubbles as iOS (own colour on the right, theirs on the left), run grouping, day separators, the time on the last of a run, "· Sending…", "· Sent", "· Not sent. Tap to retry", "· Not delivered. Tap to resend" under my newest message (and under any unsettled one). Each message is **one TalkBack stop** ("<who>, <words>, <time>, <state>, <reactions>, <replies>") whose actions (Copy, Reply, Retry sending) are TalkBack custom actions and also the long-press menu.
- **Composer:** plain text above the keyboard (`imePadding`); send is the one lime action (ink arrow on the accent circle, 56 dp). No formatting toolbar yet; text typed as Markdown (`**bold**`, `*italic*`) is drawn formatted.
- **Replies:** Reply sets a reply bar above the field; the reply goes into the message's thread (as on iOS) and the message shows "N replies", which opens a read-only list of the replies.
- **A stranger's first message:** the chat shows "<name> isn't in your chats yet. Accept to reply." with Accept (Block comes later); Requests lists them.
- **Not built yet:** photos and files, voice, reactions, edit, delete, forward, find, mentions, link previews, formatting toolbar, group management.
