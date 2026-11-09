# Messages (link tab) — Android differences

The spec is the iOS Messages list (`ios/Lime/Features/Messages/MessagesView.swift`); this page lists only where Android differs.

- **Navigation:** a bottom bar (link · call · jam) with Material 3; the system back gesture closes a chat or Requests; no swipe-back edge.
- **Header:** the "lime" wordmark and your avatar (iOS: logo, search, avatar). Search and the avatar's Settings come later; for now the avatar opens a small profile dialog with Sign out.
- **Rows:** one TalkBack stop each ("name, pinned, muted, preview, time, N unread"); 48 dp minimum height; the count badge is ink on the lime accent.
- **Filters:** All | Unread as two radio chips. The iOS filter menu (kind, pinned, muted, label, requests) is not built; Requests has its own row.
- **Refresh:** pull to refresh (Material 3 `PullToRefreshBox`); while the app is in front it also syncs every 5 s (iOS listens for a realtime nudge).
- **Not built yet:** swipe actions (delete, mute, pin, mark unread), mute state, search, new message.
