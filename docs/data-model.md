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
   exactly one place instead of being re-implemented at each call site —
   `canReason(action, conversation)` sits next to it, returning the
   one-line explanation a disabled menu item shows, so the rule and its
   explanation can't drift apart.
   **DMs have no owner** (no `created_by`, and `can()`'s own `isOwner`
   check is false for everyone in one as a result). **LIME-34 supersedes
   LIME-26's own original decision here**: every conversation's title
   menu now shows the *same* four items (Star · Rename · Archive ·
   Delete) always — an item `can()` rejects renders disabled with its
   `canReason`, rather than being hidden. A DM's Rename stays disabled
   (its title is always the other person, not something to rename), but
   its **Delete is enabled** — for a DM specifically, Delete means
   "delete for me" (`cleared_at`, above), not delete-for-everyone, so
   ownership (which a DM doesn't have) is beside the point. A group the
   current user doesn't own gets a disabled Rename *and* a disabled
   Delete, both with their own `canReason` ("Only the group owner
   can…") — Archive stays enabled either way, and "Leave group"
   (distinct from Delete, which only an owner can do) is a later brief.
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
| A DM | `conversations.type = 'direct'`, exactly 2 rows in `conversation_members`, `dm_key` set (the store computes it — the two member ids, sorted, joined with `:` — never the UI directly) so the same pair can't get a second DM |
| Starred / archived / deleted-for-me | The current user's own row in `conversation_members` (`starred`, `archived_at`, `cleared_at`) — never the conversation itself. "Deleted for me" (LIME-34) hides the conversation once nothing after `cleared_at` remains, and hides individual messages at or before it — both computed at read time, nothing pre-filtered or stored |
| A reply | `messages.reply_to` pointing at the parent message's `id` |
| A reaction count | `count(*)` of `message_reactions` for that `(message_id, emoji)` |
| "Did I react" | `exists` a `message_reactions` row for `(message_id, current_user_id, emoji)` |
| Latest activity (for list sorting) | The most recent row in `messages` for that `conversation_id`, replies included |
| Presence dot (Active / Away / Busy / DND) | `presenceFor(profiles.status)` — `online → Active`, `busy → Busy`, `offline → Away`. **"Away" and "DND" as *distinct* states have no stored value yet**: today's `status` column only ever holds `online`/`offline`/`busy` (matching the seed and this schema exactly), so `presenceFor`'s "away" is really just its fallback for "anything else," and the UI's separate "DND" dot exists only in still-static markup (the Recent row), never derived from a real profile. A future presence feature decides whether "away" and "DND" become real, distinct stored values. |

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
- `canReason(action, conversation)` — added in LIME-34; `null` when `can()` is already true
- `getMessage(id)` — added in LIME-24b (see "Deviations from the contract" below)

### Writes (async — each returns a `Promise` of the affected record)

- `sendMessage(conversationId, { content, type, metadata, replyTo })`
- `toggleReaction(messageId, emoji)`
- `createConversation({ type, memberIds, name, description })`
- `renameConversation(id, name)`
- `setStarred(id, bool)`
- `setArchived(id, bool)`
- `deleteConversation(id)` — a soft delete (`conversations.deleted_at`), not a row delete. Owner-only (`can('delete', …)`), removes it for everyone in it
- `deleteForMe(id)` — added in LIME-34; sets only the **current user's own** `conversation_members.cleared_at`, never `conversations.deleted_at`. Available on any conversation the current user doesn't own (in practice, today, only ever exposed in the UI for DMs — Archive covers the same "make it go away for me" need for a group)
- `markRead(conversationId)`
- `updateProfile(patch)` — updates the **current user's own** profile.
  `patch` may only contain `display_name`, `pronouns`, `role`, `school`,
  `grade_levels`, `subjects`, `bio`, `timezone`, `phone`; any other key
  rejects the whole call (nothing partially applies). `display_name`, if
  present in the patch, may not be empty. **Email and password are never
  accepted here** — they belong to the auth seam below, not this
  whitelist, because on Supabase they're auth-provider concerns, not
  columns this call would ever be allowed to touch directly.

### Events (dispatched on `document`)

- `lime:conversations-changed`
- `lime:messages-changed`
- `lime:reactions-changed`
- `lime:profile-changed` — `detail: { profileId }`. Fired by
  `updateProfile` and by the auth seam's `changeEmail` (which updates
  `profiles.email` too, once the auth-provider-side change succeeds).
  Anything rendering a profile's name, avatar initials, or email
  (sidebar, profile menu header, contact rows, thread sender names, the
  settings pane itself) subscribes to this rather than re-deriving on a
  timer.

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

When Supabase auth replaces this: `getCurrentUserId()` resolves to the
profile whose `profiles.auth_user_id` matches the current session's
`auth.uid()` — via the `current_profile_id()` SQL helper in `schema.sql`,
which every RLS policy also calls, so the app and the database agree on
"who's asking" through the exact same lookup. **Not** a direct comparison
of `profiles.id` to `auth.uid()` — they're different types (readable text
vs. uuid) and different ids entirely (LIME-24a-fix caught this: the first
draft of this doc missed it, and every policy that compared them directly
would simply never have matched).

**Onboarding**, the two ways a profile ends up linked:
- **A brand-new signup** gets a `profiles` row created for them (via a
  Supabase trigger on `auth.users` insert, or on their first successful
  login — either works; whichever is simpler when this is actually built),
  with `auth_user_id` set immediately.
- **An existing seed teacher** (e.g. `teacher-002`) gets linked the first
  time someone logs in with that teacher's `email`: find the `profiles` row
  by email, set its `auth_user_id` to the new session's `auth.uid()`, once.
  This is exactly what "test with multiple email logins" needs — a real
  login attaches to the seed identity that already has all its messages
  and conversations, rather than starting that person over from empty.

Nothing else in the UI changes, because nothing else in the UI calls
anything auth-related directly — `getCurrentUserId()` is the only seam.

### `auth.js` — the write half of the auth seam (LIME-31)

`getCurrentUserId()` above is the *read* half of the auth seam (who am
I); `auth.js` is the *write* half (change who I am, or how I sign in).
Three functions, all returning Promises, all called directly by the UI —
never through `LimeStore`, since email and password are explicitly **not**
`updateProfile`'s concern (production-ready rule: they belong to the auth
provider, not `profiles`).

- **`changeEmail(newEmail)`**
  - **Local:** validates the format, rejects if another profile already
    has that email (`LimeStore.findProfileByEmail`), then writes
    `profiles.email` (via a narrow store method, not `updateProfile` —
    see "Deviations" below) and updates the `email` field inside the
    `lime-demo-session` `localStorage` value, so the session still
    resolves to the same profile on the next `LimeStore.init()`. Without
    that second part, changing your email would silently log you back in
    as `teacher-002` (the fallback) on your very next reload, since
    `getCurrentUserId()` would no longer find a profile matching the
    session's stale email.
  - **Supabase:** `supabase.auth.updateUser({ email })`, which sends a
    confirmation email and only takes effect once it's clicked —
    `profiles.email` updates via a database trigger on that
    confirmation, not synchronously in this function. The local version's
    "succeeds immediately" behavior is a deliberate simplification for
    the prototype, not a preview of production behavior.
- **`changePassword({ current, next, confirm })`**
  - **Local:** validates only — `next` is at least 8 characters, `next`
    differs from `current`, and `next` matches `confirm`. **Stores
    nothing, anywhere, in any form** — there is no real password to check
    `current` against locally (the demo login's one hardcoded credential
    lives in the gitignored `demo-config.local.js`, which this module
    never reads), so `current` is validated for shape only, never
    verified. Resolves with a message the UI shows as-is: "Password
    changes take effect once connected to the real account system."
  - **Supabase:** `supabase.auth.updateUser({ password })`, after
    Supabase itself re-authenticates `current` server-side (this module
    would still send `current`, just to Supabase instead of validating it
    locally).
- **`signOut()`** — clears `lime-demo-session` and redirects to
  `login.html`. Identical to what `#sign-out-btn`'s own handler already
  did before this brief; that handler now just calls this instead, so
  the logic exists in exactly one place.

## The switch checklist

When it's time to point this app at a real, shared Supabase project instead
of `localStorage`:

1. Add a `SupabaseAdapter` implementing the same adapter interface
   `LocalAdapter` does (same method names, same return shapes).
2. Add config: a Supabase project URL and anon key, via a gitignored
   `*.local.js` file, the same pattern `demo-config.local.js` already
   uses for the demo login.
3. Create the `current_profile_id()`, `is_member()` and `is_owner()` SQL
   helpers from `schema.sql`, then enable the RLS policies drafted there
   (as comments) — the policies call the helpers, so the helpers have to
   exist first.
4. Wire up the onboarding linking described in "The auth seam" above (new
   signup → a profile row with `auth_user_id` set; existing seed teacher →
   linked by email on first login), so `current_profile_id()` actually
   resolves to something for every real login.
5. Run `seed-data/seed.ts` against the new database (it's fixed to use the
   corrected reactor rule in LIME-24b — no longer a blocker by the time
   this checklist is used for real).
6. Swap `auth.js`'s local `changeEmail`/`changePassword` bodies for their
   Supabase equivalents (`supabase.auth.updateUser({ email })` /
   `updateUser({ password })`) — same function names and signatures, so
   nothing calling `LimeAuth.changeEmail`/`changePassword` needs to change.
   `signOut()` swaps to `supabase.auth.signOut()`.
7. Flip `LIME_BACKEND` from `'local'` to `'supabase'`.

Nothing else changes — the store, the events, and every UI call site stay
exactly as they are, because they were never talking to `localStorage` or
to Supabase directly in the first place.

## Known gaps, flagged rather than silently resolved

- **"Delete for me" (`cleared_at`) hides messages at the store/UI layer
  only, not via RLS.** `LimeStore.listMessages` filters out anything at
  or before the reader's own `cleared_at`; the (still-commented-out)
  `messages_select_member` policy in `schema.sql` does not, and doing so
  properly would need its own per-row subquery against the reader's
  `conversation_members.cleared_at` rather than the simple `is_member()`
  check it has today. Not written, since nothing today needs that
  guarantee to hold below the UI — worth a brief of its own if a real
  backend ever needs the database itself to enforce it.
- **Community `avatar_color` / `member_count`:** today's seed data gives
  `community`-type conversations two extra fields that don't fit this
  schema — `avatar_color` (presentational) and `member_count` (a stored
  number that contradicts principle 2's "derive it from the real
  membership rows" — none of the 9 seed communities actually lists that
  many participant ids). Communities are still a static mockup in the app
  (LIME-28 in the drafted lifecycle is what makes them live); this is
  worth resolving when that brief defines what a community page actually
  needs, not guessed at here.

**Resolved by LIME-24a-fix** (kept here for the record, not because it's
still open): the reactor algorithm gap flagged in the first draft of this
doc — `seed-data/seed.ts` selecting reactors without deduping, which would
violate `message_reactions`' primary key — is now a decided rule, not an
open question: a reaction's reactors are the conversation's distinct
members (participant order), sliced to `min(count, member_count)`. Full
reasoning and the same `conv-001`/`msg-006` repro (😍×5 → 😍×2, since it's
a 2-person DM) are in `schema.sql`'s comments. **`seed-data/seed.ts` is
updated to this rule as of LIME-24b** — see that brief's `TEND.md` entry.

## Deviations from the contract (LIME-24b)

- **Added `getMessage(id)`** to the reads — a plain lookup of one message
  record by id. It wasn't in this doc's original list, but the UI has no
  other way to resolve a single message id to its record (the reply
  panel's quote needs the parent message's own content/sender; `sendReply`
  folding into `sendMessage(id, { replyTo })` means finding a reply's
  target conversation needs the same lookup). The old `data.js` had the
  exact equivalent (`findMessageById`) — this was very likely an
  omission in the original contract listing, not a deliberate exclusion,
  so it's added rather than worked around with a less direct query.
- Nothing else needed to deviate: `sendReply` was never a separate
  contract method to begin with (`sendMessage`'s own `replyTo` field
  already covered it, per the very first draft of this doc) — LIME-19b's
  old separate `sendReply`/`lime:activity` pair from `data.js` is what's
  gone now, not anything this contract promised.

## Deviations from the contract (LIME-31)

- **Added `findProfileByEmail(email)`** to the reads — `changeEmail`'s own
  uniqueness check ("checks format and uniqueness against profiles," per
  the brief's own words) has no other way to ask "does any profile
  already have this email" without it. A plain lookup, same shape as
  `getMessage(id)`'s own justification in LIME-24b.
- **Added `setProfileEmail(id, email)`** to the writes — a narrow,
  internal write, **not** part of `updateProfile`'s whitelist and not
  meant to be called from UI code directly. `auth.js`'s `changeEmail` is
  its only caller: locally, there's no separate `auth.users` table for
  email to live on, so this is what actually writes `profiles.email`
  after `changeEmail`'s own validation passes — playing the same role a
  real Supabase trigger plays after a confirmed `auth.users` email
  change. Emits the same `lime:profile-changed` event `updateProfile`
  does, since email is still profile data from the UI's own rendering
  perspective (it shows in Login & security and the profile menu header).
