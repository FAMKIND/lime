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
| Presence dot (Active / Away / Busy / DND) | `presenceFor(profiles.status)` — `online → Active`, `busy → Busy`, `offline → Away`. **"Away" and "DND" as *distinct* states have no stored value yet**: today's `status` column only ever holds `online`/`offline`/`busy` (matching the seed and this schema exactly), so `presenceFor`'s "away" is really just its fallback for "anything else." A future presence feature decides whether "away" and "DND" become real, distinct stored values. |
| Unread (Recent row ring, LIME-36) | Derived, never stored: a person carries the unread ring if any conversation you share with them has a `messages` row from someone else newer than your own `conversation_members.last_read_at` for that conversation. Opening the conversation calls `markRead`, which sets `last_read_at` to now and clears the ring |

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
- `getAttachments(messageId)` — added in LIME-41; `[{ path, name, size, mime, width, height, duration_seconds, position }]`, sorted by `position`. `duration_seconds` added in LIME-42, same reasoning as `width`/`height` — recorded once at upload time, `null` for a non-audio attachment or one synthesized from a legacy message (which never had one). Synthesizes a single-row result from a legacy `'image'`/`'file'` message's own `metadata.path` when the message has no real `message_attachments` rows (see "Multi-attachment messages" below) — every caller uses this one function regardless of which era a message is from
- `getConversationTitle(conversation)`
- `getLatestActivity(conversationId)`
- `can(action, conversation)`
- `canReason(action, conversation)` — added in LIME-34; `null` when `can()` is already true
- `getMessage(id)` — added in LIME-24b (see "Deviations from the contract" below)

### Writes (async — each returns a `Promise` of the affected record)

- `sendMessage(conversationId, { content, type, metadata, replyTo, attachments })` — `metadata.html` (LIME-37) carries the sanitised rich-text version of `content`, omitted when the message has no formatting. `attachments` (LIME-41, `duration_seconds` added LIME-42) is an array of `{ path, name, size, mime, width, height, duration_seconds }` — already-uploaded files (via `uploadAttachment` below) that become that same message's album; `content`, if present alongside them, is that album's caption, not a separate message
- `toggleReaction(messageId, emoji)`
- `createConversation({ type, memberIds, name, description })`
- `renameConversation(id, name)`
- `setStarred(id, bool)`
- `setArchived(id, bool)`
- `deleteConversation(id)` — a soft delete (`conversations.deleted_at`), not a row delete. Owner-only (`can('delete', …)`), removes it for everyone in it
- `deleteForMe(id)` — added in LIME-34; sets only the **current user's own** `conversation_members.cleared_at`, never `conversations.deleted_at`. Available on any conversation the current user doesn't own (in practice, today, only ever exposed in the UI for DMs — Archive covers the same "make it go away for me" need for a group)
- `markRead(conversationId)`
- `uploadAttachment(file, { conversationId })` — added in LIME-38; resolves `{ path }`, an opaque key handed to `getAttachmentUrl` below, never parsed by the caller
- `getAttachmentUrl(path)` — added in LIME-38; resolves a URL string safe to use directly in `<img src>` or a Download link's `href`
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

## Message formatting (LIME-37)

- **`messages.content` stays plain text** — previews (the conversation
  list, notifications), search, and any place that just needs "what did
  they say" read this, never the HTML. It's derived from the composer's
  own `innerText`, trimmed.
- **The formatted version lives in `messages.metadata.html`**, a
  **sanitised allow-list HTML subset**: `p`, `br`, `strong`, `b`, `em`,
  `i`, `u`, `s`, `a[href]` (`http:`, `https:` or `mailto:` only — a bare
  `example.com` gets `https://` prepended, matching the Link toolbar's own
  behavior; anything else strips the link down to its text), `ul`, `ol`,
  `li`, `blockquote`, `code`, `pre`. Every other tag is either unwrapped
  (its own children survive, re-sanitised, just not the tag itself — a
  pasted `<div>` or `<span>` becomes plain inline content) or, for `script`
  and `style` specifically, removed **with its content** — there's no
  reading of "what was inside a script tag" that belongs in a message.
  Every attribute is stripped except `href` on `a`, so a pasted `style="…"`
  or `onerror="…"` never survives regardless of which tag it rode in on.
  **Omitted entirely** (not stored as an empty string) when nothing in the
  composer actually used formatting — a plain-text message has no
  `metadata.html` key at all.
- **The same sanitiser runs twice**: once on send (before anything is
  stored) and again on render (before `metadata.html` is ever put in the
  DOM) — never trust that what's already in storage is still safe, since
  it could be old data from before a sanitiser bug was fixed, or (once a
  real backend exists) written by a client this one doesn't control.
  `rel="noopener noreferrer"` and `target="_blank"` are added to links at
  render time only, never stored — they're a rendering concern, not part
  of the message's own content.
- **A real backend must sanitise server-side too.** This client-side
  sanitiser protects this app's own render path; it does nothing to stop
  a different client (or a direct API call) from writing unsanitised HTML
  straight into `messages.metadata.html`. Once `SupabaseAdapter` exists,
  either a database trigger or an edge function needs to run the
  equivalent allow-list before a row is accepted — documented here rather
  than assumed, since it's easy to ship a client-only sanitiser and call
  message formatting "done."
- **Why not Markdown:** underline has no Markdown form (`__x__` is
  conventionally bold-alt, not underline, and no widely-used Markdown
  dialect defines one) — since the brief calls for a real Underline
  button, storing Markdown and rendering it would mean either inventing a
  non-standard escape sequence just for this app, or dropping underline
  entirely. Sanitised HTML has no such gap and needs no dialect decision.

## File and image attachments (LIME-38)

> **Superseded by LIME-41 below** for anything sent from now on — kept
> here because old messages sent under this design still exist and still
> render, via the backward-compatibility mapping the next section
> documents. The "one message per file" sending model, and `content` on
> an attachment message always being `null`, are no longer how new
> messages are produced.

- **`messages.type` gains `'file'`** (`'image'` already existed in the
  schema, unused until now). An attachment message's `content` is always
  `null` — attachments carry no text of their own; if the user also typed
  something, that's a **separate** text message, sent first.
- **`metadata` for an `'image'`/`'file'` message is `{ name, size, mime,
  path }`** — `size` in bytes, `mime` the file's own `type`, `path` an
  **opaque key** no reader ever parses or constructs, only ever hands to
  `getAttachmentUrl` below. This is deliberate: it's what lets the local
  adapter and a real `SupabaseAdapter` use completely different path
  shapes (a local IndexedDB key vs. a Storage object path) without the UI
  ever knowing or caring which one is active.
- **The adapter contract gains two calls**, both async (return a
  `Promise`, like every other write):
  - `uploadAttachment(file, { conversationId })` → `{ path }`
  - `getAttachmentUrl(path)` → a URL string, safe to put directly in an
    `<img src>` or a Download link's `href`
- **Local adapter: IndexedDB, not `localStorage`.** A `lime-files`
  database (object store `attachments`, keyed by `path`) holds the raw
  file `Blob`s — `localStorage`'s ~5MB total quota couldn't hold even one
  attachment near this brief's own 10MB-per-file limit, let alone several.
  `getAttachmentUrl` resolves via `URL.createObjectURL(blob)` — a fresh
  object URL **per call**, valid only for this page's current lifetime
  (never stored; re-resolved every time a message renders). Local's own
  `path` is `<conversationId>/<uuid>-<filename>` — deliberately *not* the
  production shape below (`uploadAttachment` never receives a `messageId`;
  the file uploads *before* the message that will reference it exists),
  which is fine precisely because `path` is opaque per the point above.
- **Production** (documented in `schema.sql`, not built): a Supabase
  Storage bucket `attachments`, object path
  `<conversationId>/<messageId>/<filename>`, with storage-policy RLS
  restricted to `is_member`.
- **Limits, enforced client-side only:** 10MB per file. Originally capped
  at 5 files per message too; LIME-41 removes that count cap entirely (an
  album is the point of that brief, and its own verification sends 7 in
  one message) — only the size limit remains. Same caveat as the LIME-37
  sanitiser either way — a real backend would need to enforce the size
  limit again itself (a Storage bucket size limit), since nothing stops a
  direct API call from ignoring what the client checked.
- **Sending is deliberately simple, not one atomic multi-part message:**
  if there's typed text, it sends as its own ordinary text message first;
  then each attached file uploads and sends as **its own message**, one
  per file, in the order they were attached. A message with three photos
  is three separate `messages` rows, not one row with a three-item array —
  simpler to reason about, and it's what "one message per file" in the
  brief's own words means literally.
- **Reset demo data clears `lime-files` too** (the whole IndexedDB
  database, not just its records) — otherwise a reset would bring back
  the original seed conversations while orphaned attachment blobs from
  the wiped session lingered on disk indefinitely.

## Multi-attachment messages (LIME-41)

- **New table, `message_attachments`** (schema.sql): `{ id, message_id,
  path, name, size, mime, width, height, duration_seconds, position,
  created_at }` (`duration_seconds` added LIME-42), one row
  per file, `position` giving display order. Supersedes LIME-38's "one
  message per file, `metadata.path` on the message itself" — any message,
  including one with real `content`, can now carry 0..n attachments.
  `width`/`height` are recorded at upload time (read via a
  `readImageDimensions(file)` helper before the file ever hits the wire)
  so the album grid can lay itself out — and stay laid out identically
  after a reload — without waiting for the image itself to load first.
- **No data migration.** Old `'image'`/`'file'` messages (LIME-38 shape)
  are left exactly as they are; they carry no `message_attachments` rows.
  `messages.type` keeps `'image'`/`'file'` in its check constraint purely
  to keep those old rows valid — nothing sends those values any more.
- **Backward-compatibility mapping, the documented contract**: when
  `getAttachments(messageId)` finds no real `message_attachments` rows for
  a message, and that message's own `type` is `'image'` or `'file'` with a
  `metadata.path`, it synthesizes a single-item result:
  `[{ path: metadata.path, name: metadata.name, size: metadata.size, mime: metadata.mime, width: null, height: null, position: 0 }]`.
  `width`/`height` come back `null` for these — no dimensions were ever
  recorded for them — so their rendering falls back to the old
  intrinsic-size single-thumbnail behavior rather than being forced into
  a grid tile sized for data it doesn't have. Every reader (album
  rendering, the lightbox, previews) calls `getAttachments` and never
  branches on `message.type` itself, so old and new messages render
  through the identical code path.
- **Sending, one message for the whole pick:** attaching N files and
  optionally typing a caption uploads all N files (`uploadAttachment`,
  unchanged from LIME-38) and sends **one** `sendMessage` call with
  `content` set to the caption (or `null`) and `attachments` set to the N
  resulting `{ path, name, size, mime, width, height }` entries, `type`
  always `'text'`. This replaces LIME-38's "typed text first, then one
  message per file" entirely for new sends.
- **Album rendering** (by attachment count, images only — non-image files
  always render as file cards below the album, never inside the grid):
  1 image is the existing single 240×180 thumbnail; 2 side-by-side; 3 one
  large plus two stacked; 4 or more a 2×2 grid, the 4th tile carrying a
  `+N` overlay when there are more than 4. All tiles `object-fit: cover`
  inside one rounded bubble; the caption, if any, renders below. 5 or more
  images additionally show an "N photos" label that opens a gallery modal
  (a responsive grid over a blur backdrop, with its own close button)
  rather than relying on the 2×2 tile grid alone to represent them.
- **Lightbox scoping changes for albums**: clicking a tile from a
  multi-attachment message opens the LIME-40 lightbox scoped to **that
  message's own images only** (via `getAttachments(messageId)`, images
  filtered by `mime`), not the whole conversation's images as LIME-40's
  single-image click behavior still does.
- **List previews** (`previewFor`/`plainPreviewFor`): caption text, if
  present, always wins over any attachment summary. With no caption, a
  single image still reads "Photo", a single file still reads "📎
  filename" (unchanged from LIME-38); multiple attachments read "📷 N
  photos", "📎 N files", or "📷 N photos, 📎 M files" for a mixed album.

## Audio attachments and typed file cards (LIME-42)

- **Audio attachments** (`mime` starting `audio/`) are their own category
  within a message's attachments, split out from "files" the same way
  images already are (`isAudioAttachment`, alongside `isImageAttachment`).
  They render as a real inline player — a visible play/pause button, a
  waveform-styled bar, and a duration label — backed by a genuine hidden
  `<audio>` element (`data-attachment-path`, resolved the same lazy,
  two-step way every other attachment already is via `paintAttachments`),
  not the decorative, unwired `'voice'` message type (LIME-10), which
  this brief leaves completely untouched. `duration_seconds` is read once
  at upload time (`readAudioDuration(file)`, mirroring
  `readImageDimensions`'s own reasoning exactly) so the label never has
  to wait on the file actually loading to show a real number.
- **Playback**: clicking the play button toggles the real `<audio>`
  element's own `.play()`/`.pause()`; starting one attachment's audio
  pauses any other attachment's audio currently playing (only one plays
  at a time). The button's icon and `aria-label` reflect the `<audio>`
  element's own live `paused`/`ended` state (via non-bubbling `play`/
  `pause`/`ended` listeners on the capturing phase — those events don't
  bubble, so a document-level delegated listener has to use `true` for
  its third argument to ever see them at all), not just an assumption
  about what the one click that triggered it did.
- **Typed file cards**: a non-image, non-audio attachment's card now
  carries an extension badge — a two-to-four-letter label (PDF, DOC, XLS,
  PPT, ZIP, TXT) on a Seed calm/bad/warn/good-tinted tile, keyed off the
  attachment's own filename extension (checked against `FILE_CATEGORY_BY_EXT`
  in app.js), or a plain neutral tile with a generic file glyph for
  anything not in that list. All four tint pairings (their own
  `-text-bold-default` on `-bg-subtle-default`) measured at 6.4:1 contrast
  or better in both light and dark mode — comfortably clear of the
  "only if it passes contrast, otherwise neutral" bar the brief itself
  set, so none needed the neutral fallback.
- **Name truncation**: the filename's base (everything before the last
  dot) ellipsis-truncates on overflow; the extension is a separate,
  never-shrinking element after it, so a long filename always keeps its
  extension visible rather than losing it to a plain end-truncation.
- **PDFs open in a new tab from the card** — the badge+meta area
  (`.lime-filecard__open`) is a real `<a target="_blank" rel="noopener">`
  for `mime === 'application/pdf'` (a plain `<div>` otherwise), resolved
  by the same `paintAttachments` pass every other attachment already
  goes through. Not a JS `window.open()` call: tried first, and found —
  live, in Firefox — to silently fail, since a `blob:` URL is scoped to
  the Document that created it and can't reliably be handed to a
  genuinely separate browsing context opened that way, even same-origin.
  A real anchor click's own "open as an auxiliary browsing context"
  navigation resolves it correctly instead — the same proven path the
  Download link right beside it already relies on. Images never reach
  this at all, since an image attachment always renders as an album/grid
  tile (`imageTileHtml`), never a file card — the brief's own "PDFs and
  images open in a new tab from the card" only has a file-card half to
  implement here.
- **List previews**: a single audio attachment (no caption) reads "🎵
  Audio" (the brief's own exact wording, no count — matching "Photo"'s
  own no-count form for a single image); a real multi-attachment mix
  extends the existing "📷 N photos"/"📎 N files" pattern with "🎵 N
  audio" ("audio" doesn't pluralize).
- **A pre-existing, out-of-scope CSS finding, not fixed here:** surveying
  the old file-card CSS turned up a genuinely dead, unreferenced
  `.lime-message__file` block further down `lime.css` (no `-card`,
  nothing in `app.js` has ever rendered it) that happens to redeclare the
  bare `.lime-message__file-name`/`.lime-message__file-download` class
  names the *real* card also used — since neither selector is scoped to
  a parent, the later one in the file silently wins for every element
  carrying that class, meaning the real download button had been
  rendering at 28×28 (the dead block's own size) rather than the 32×32
  its own, earlier rule stated, ever since LIME-38. LIME-42's own new
  file-card markup uses fresh `.lime-filecard__*` names specifically to
  avoid inheriting this collision, but the dead block and the pre-LIME-42
  collision it caused are both still sitting in `lime.css`, untouched —
  flagged here rather than silently cleaned up, since removing dead code
  wasn't this brief's own scope.

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
