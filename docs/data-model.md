# Lime data model

Draft contract for the app's data layer. `LIME-24b` implements this locally,
against `localStorage`; a later `SupabaseAdapter` implements the same
contract against the schema in [`schema.sql`](./schema.sql). Nothing in the
UI should ever need to know which one is running.

The goal, in the user's own words (2026-09-27): "make sure that everything
we're adding can easily be production ready when needed, meaning when we're
ready to test with multiple email logins over an open-source database we can
make the switch."

## Principles

1. **Match the Supabase schema in the local model.** Normalized tables, the
   same names, derived views — not a shortcut shape that has to be
   translated later.
2. **Per-user state lives on the membership, not the conversation.**
   Starred, archived and last-read belong to `conversation_members` (one
   row per user per conversation). Otherwise starring a chat would star it
   for everyone in it. Shared state — the conversation's name, whether it's
   deleted — lives on `conversations`.
3. **Reactions are rows** (`message_id`, `user_id`, `emoji`), never a
   stored count. A message's reaction counts and whether the current user
   reacted are both derived by querying `message_reactions`.
4. **One data seam.** The UI never touches storage directly. Reads are
   synchronous, from an in-memory cache. Writes are **async** — they
   return Promises — and go through a store, which updates the cache
   optimistically, persists through an **adapter**, and emits change
   events. Today's adapter is `LocalAdapter` (`localStorage`). Later, a
   `SupabaseAdapter` implements the identical interface, and realtime
   pushes update the same cache and fire the same events.
5. **An auth seam.** `getCurrentUserId()` resolves the current session to a
   profile id. No UI code hard-codes an id.
6. **New ids are `crypto.randomUUID()`.** Seed ids keep their existing text
   form (`teacher-002`, `conv-011`) — Postgres columns are `text`, not
   `uuid`, precisely so seed rows and real rows can coexist without a type
   mismatch.
7. **Permissions are written down**, for when RLS exists: owner vs. member
   for rename and delete; communities are public-read. The UI checks
   through one `can(action, conversation)` helper, so the rule lives in
   exactly one place instead of being re-implemented at each call site.
8. **UI preferences stay separate.** Panel widths, collapsed sections,
   theme — these are device preferences, not data, and keep their own
   `localStorage` keys outside this contract entirely.

## Entity diagram (as a list)

```
profiles
  ├─< conversations.created_by
  ├─< conversation_members.user_id
  ├─< messages.sender_id
  └─< message_reactions.user_id

conversations
  ├─< conversation_members.conversation_id  (who's in it, and their own star/archive/read state)
  └─< messages.conversation_id

messages
  ├─< messages.reply_to        (a message replying to another message, same table)
  └─< message_reactions.message_id
```

Read `├─<` as "one of these has many of those."

## Mapping today's UI concepts onto these tables

| UI concept | Table / derivation |
|---|---|
| A conversation's title | `conversations.name` if set, else derived from the other member(s)' `profiles.display_name` (see `getConversationTitle` below) |
| A DM | `conversations.type = 'direct'`, exactly 2 rows in `conversation_members` |
| Starred / archived | The current user's own row in `conversation_members` (`starred`, `archived_at`) — never the conversation itself |
| A reply | `messages.reply_to` pointing at the parent message's `id` |
| A reaction count | `count(*)` of `message_reactions` for that `(message_id, emoji)` |
| "Did I react" | `exists` a `message_reactions` row for `(message_id, current_user_id, emoji)` |
| Latest activity (for list sorting) | The most recent row in `messages` for that `conversation_id`, replies included |

## The store API (the adapter contract)

Everything below is implemented once, by the store, on top of whichever
adapter (`LocalAdapter` today, `SupabaseAdapter` later) is active. The UI
only ever calls the store, never the adapter directly.

### Reads (synchronous, from the in-memory cache)

- `getProfile(id)`
- `getCurrentUserId()`
- `getCurrentUser()`
- `listConversations({ types, includeArchived })`
- `getConversation(id)`
- `getMembers(conversationId)`
- `getMyMembership(conversationId)`
- `listMessages(conversationId, { threadOnly })`
- `listReplies(messageId)`
- `getReactions(messageId)` → `[{ emoji, count, mine }]`
- `getConversationTitle(conversation)`
- `getLatestActivity(conversationId)`
- `can(action, conversation)`

### Writes (async — each returns a `Promise` of the affected record)

- `sendMessage(conversationId, { content, type, metadata, replyTo })`
- `toggleReaction(messageId, emoji)`
- `createConversation({ type, memberIds, name, description })`
- `renameConversation(id, name)`
- `setStarred(id, bool)`
- `setArchived(id, bool)`
- `deleteConversation(id)` — a soft delete (`conversations.deleted_at`), not a row delete
- `markRead(conversationId)`

### Events (dispatched on `document`)

- `lime:conversations-changed`
- `lime:messages-changed`
- `lime:reactions-changed`

Each carries `detail: { conversationId, messageId?, kind }`. `kind`
distinguishes what changed within that category (e.g. a new message vs. a
rename) without requiring three more event names per action.

### Lifecycle

- `await LimeStore.init()` must resolve before the first render — it's what
  loads/builds the cache from the adapter.
- `LimeStore.reset()` exists only on the local adapter (wipes back to the
  seed); a `SupabaseAdapter` has no equivalent — "reset" isn't a
  meaningful action against a shared database.

## The auth seam

`getCurrentUserId()` is the one function anything in the UI calls to find
out "who am I." Today: it reads `lime-demo-session` from `localStorage`
(`{ email, displayName }`, set by `public/login.html` after checking one
hardcoded credential in the gitignored `public/js/demo-config.local.js`),
and matches `email` against `profiles.email` in the cache. With no session,
or no matching profile, it falls back to `teacher-002` and logs once, so
the app still renders something during local development without a login
step.

When Supabase auth replaces this: `getCurrentUserId()` reads the Supabase
session instead (`supabase.auth.getUser()` or equivalent) and resolves its
`email` (or `id`, once profiles are keyed by the auth user's own uuid) the
same way. Nothing else in the UI changes, because nothing else in the UI
calls anything auth-related directly — this function is the only seam.

## The switch checklist

When it's time to point this app at a real, shared Supabase project instead
of `localStorage`:

1. Add a `SupabaseAdapter` implementing the same adapter interface
   `LocalAdapter` does (same method names, same return shapes).
2. Add config: a Supabase project URL and anon key, via a gitignored
   `*.local.js` file, the same pattern `demo-config.local.js` already
   uses for the demo login.
3. Enable the RLS policies drafted (as comments) in `schema.sql`.
4. Run `seed-data/seed.ts` against the new database — **after** fixing the
   reactor-duplication bug flagged in `schema.sql`'s comments; as written
   today it would fail against `message_reactions`' own primary key.
5. Flip `LIME_BACKEND` from `'local'` to `'supabase'`.

Nothing else changes — the store, the events, and every UI call site stay
exactly as they are, because they were never talking to `localStorage` or
to Supabase directly in the first place.

## Known gaps, flagged rather than silently resolved

- **Community `avatar_color` / `member_count`:** today's seed data gives
  `community`-type conversations two extra fields that don't fit this
  schema — `avatar_color` (presentational) and `member_count` (a stored
  number that contradicts principle 2's "derive it from the real
  membership rows" — none of the 9 seed communities actually lists that
  many participant ids). Communities are still a static mockup in the app
  (LIME-28 in the drafted lifecycle is what makes them live); this is
  worth resolving when that brief defines what a community page actually
  needs, not guessed at here.
- **`seed-data/seed.ts`'s reactor selection doesn't dedupe senders before
  slicing**, which would violate `message_reactions`' own primary key if
  run against this schema as written. Full detail and a concrete repro
  (`conv-001`'s `msg-006`) are in `schema.sql`'s comments, right above the
  table it affects. Production-ready principle 4 asks `LIME-24b`'s local
  adapter to match `seed.ts`'s exact reactor algorithm — it should match
  a *corrected* version of that algorithm (dedupe first, then slice), not
  reproduce this bug locally too.
