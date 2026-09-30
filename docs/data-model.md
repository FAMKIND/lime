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
- `getAppearance()` — added in LIME-50; resolves `{ theme, canvas, pattern }` for the current user, defaulting any unset field (`canvas: 'warm'`, `theme`/`pattern`: `null`) so callers never have to guard against a missing key (see "Appearance" below)
- `listMessages(conversationId, { threadOnly })`
- `listReplies(messageId)`
- `getReactions(messageId)` → `[{ emoji, count, mine }]`
- `getAttachments(messageId)` — added in LIME-41; `[{ path, name, size, mime, width, height, duration_seconds, position }]`, sorted by `position`. `duration_seconds` added in LIME-42, same reasoning as `width`/`height` — recorded once at upload time, `null` for a non-audio attachment or one synthesized from a legacy message (which never had one). Synthesizes a single-row result from a legacy `'image'`/`'file'` message's own `metadata.path` when the message has no real `message_attachments` rows (see "Multi-attachment messages" below) — every caller uses this one function regardless of which era a message is from
- `getReceiptStatus(messageId)` — added in LIME-43; `{ status: 'delivered' | 'viewed', viewedBy: [{ profile, last_read_at }], notYet: [{ profile }] }`. Meaningful only for one of the *current* user's own sent messages (see "Delivered/viewed receipts" below) — never called for someone else's
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
- `getLinkPreview(url)` — added in LIME-44; resolves `{ url, minimal, title, description, site_name, image_url }`, never `null` for a well-formed URL (see "Link previews" below)
- `setAppearance(patch)` — added in LIME-50; merges `patch` onto the current user's own `{ theme, canvas, pattern }`, so `{ canvas: 'sage' }` alone never touches `theme`/`pattern`. Emits `lime:appearance-changed`. LIME-45's `setChatBackground`/`getEffectiveBackground` (per-chat backgrounds) were removed 2026-09-29 in favor of this one app-wide setting (see "Appearance" below)
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

## Delivered/viewed receipts (LIME-43)

**Removed from the UI on 2026-09-29 (user decision).** The derivation
from `last_read_at` stays valid. To reinstate, revert the LIME-43-revert
commit.

- **No new columns — a pure derivation from data that already exists.**
  "Delivered" needs no state of its own: once a message exists in this
  store at all, it's delivered. "Viewed by X" compares X's own
  `conversation_members.last_read_at` (LIME-36's `markRead`) against the
  message's own `created_at` — `last_read_at >= created_at` means X has
  read past this message. `LimeStore.getReceiptStatus(messageId)` reads
  every *other* member of that message's conversation (never the sender
  themselves) and buckets them into `viewedBy`/`notYet`.
- **The rule for the tick itself**: a DM (one other member) shows ✓✓ the
  moment that one person has viewed it. A group shows ✓✓ only once
  *every* other member has — `notYet.length === 0` and at least one
  member exists to view it at all. Otherwise it's a plain ✓ (delivered),
  even if some — not all — members have already viewed it; that partial
  state is exactly what the hover/focus tooltip is for.
- **Only ever shown on your own messages** (`isSent` in `messageHtml`) —
  a receipt reflects what happened to a message *you* sent; rendering
  one on someone else's would be showing you information about a message
  that isn't yours to see the read state of.
- **The tick**: neutral grey throughout (`--soil-text-muted`), both
  states — no color distinguishes ✓ from ✓✓, only the second checkmark's
  presence. `dew-check`, doubled (this icon set has no dedicated
  double-check glyph — checked directly, the same way LIME-40/LIME-42
  each checked for their own missing icons).
- **The tooltip** (native `title` attribute — hover *and* keyboard focus,
  both native browser behavior, no custom tooltip component built for
  this) always shows the full breakdown, not just whatever the tick's own
  binary state implies: `"Delivered"` when nobody's viewed it yet;
  `"Viewed by <name> · <time>"` for a DM's single other viewer;
  `"Viewed by <name>, <name>"` for multiple viewers, with a second line,
  `"Not yet: <name>, <name>"`, appended whenever the group isn't
  unanimous. Names are `firstName`, not the sender-label `shortName`
  ("First L.") convention used elsewhere in this app — matches the
  brief's own two literal examples exactly, and reads more naturally in
  a short, conversational tooltip.
- **Live updates**: `markRead` already emits `lime:conversations-changed`
  with `kind: 'read'` (LIME-36). The open thread listens for that event
  (scoped to the currently-open conversation) and patches just the
  affected `.lime-message__receipt` elements in place — not a full
  thread re-render, which would disturb scroll position for no reason.
- **A real layout bug found and fixed live, caused by this brief's own
  new element**: `.lime-message__actions` (the hover-revealed react/
  reply/more bar) sits at a fixed offset relative to the whole message
  and genuinely overlaps a receipt tick's own position at the end of the
  meta line for a short sender name/time — confirmed by reading both
  elements' real rects while hovering, not assumed. Without its own
  stacking context, the receipt lost every pointer event in that overlap
  to `.lime-message__actions` (later in DOM order), making it literally
  impossible to hover the very control that exists to show a tooltip.
  Fixed with `position: relative; z-index: 1` on `.lime-message__receipt`
  alone — doesn't touch `.lime-message__actions`' own existing position
  or behavior at all.
- **Not built:** a live cross-tab/cross-session sync of another member's
  read state into an already-open window — this prototype has none of
  its own to piggyback on (`localStorage` doesn't fire in the writing
  tab, and this app has no `storage` event listener). Verified instead
  with the same "a real store write from the other person's own session"
  test hook LIME-34 established: a second `JSDOM` window, sharing the
  same persisted snapshot, logged in as the other member, calling
  `markRead` for real. A production `SupabaseAdapter` with realtime
  subscriptions would update the ticks live across sessions for free;
  noted here, not built, since this app has no realtime layer at all yet.
- **Not built:** a privacy setting to turn off read receipts entirely —
  noted per the brief's own "a future Settings item," not implemented.

## Link previews (LIME-44)

- **"Built for real and demoed with samples":** the *contract*
  (`getLinkPreview(url)`, resolving to a preview) is the production
  shape. A real `SupabaseAdapter` would call an `unfurl(url)` Edge
  Function and read/write a `link_previews` cache table (`schema.sql`)
  instead of the local adapter's own fixture map — every caller
  (`app.js`) only ever knows this one Promise-returning function,
  unchanged either way.
  - `unfurl(url)`: fetch with a timeout and a size cap, parse Open Graph
    and Twitter meta plus `<title>`, `favicon`, `og:image`,
    `description`, `site_name`; block private IP ranges (SSRF); cache
    the result in `link_previews` (keyed by URL, not per-message or
    per-conversation — an unfurl means the same thing regardless of who
    linked it).
  - A browser can't fetch another site's metadata itself (CORS, and this
    app's own `file://` origin during local dev has no fetch access at
    all) — this genuinely needs a server piece, which is why the local
    adapter never attempts a real network call at all, not even as a
    best-effort fallback.
- **Local adapter: a small fixture map, no network calls, ever.** Three
  realistic, hand-authored education-themed URLs resolve a full card
  (`minimal: false`); any other well-formed URL resolves the brief's own
  explicit minimal fallback (`minimal: true`: the domain as the title,
  `description`/`site_name`/`image_url` all `null`) — never `null`
  itself, the same way a real `unfurl()` would always resolve *some*
  preview (even a bare-domain one) for any URL it could actually fetch.
  Two of the three fixtures' `image_url` are small inline SVG data URIs
  (self-contained in `local-adapter.js`, not separate bundled asset
  files — nothing to fetch, nothing to go stale); the third has none, to
  exercise the full card's own no-image fallback (a `dew-link` icon tile)
  separately from the minimal card's own no-image case.
- **Rendering** (`app.js`): the first `https?://` URL found in a
  message's own plain `content` (checked against the raw string, never
  the sanitized/rendered `metadata.html`) gets a card rendered as a
  sibling **below** the text bubble — not merged into the bubble's own
  background — via a two-step paint, the same `data-*` placeholder →
  async-resolve pattern `paintAttachments`/`paintAvatar` already use.
  Scoped to plain text messages in the main thread and the reply list
  only, not album captions (out of this brief's own gate/verification,
  and captions already carry a lot of visual weight on their own).
  `message.content` itself is never touched — the URL stays exactly as
  typed, in the message's own text, whether or not a card ends up
  attached below it.
- **A real CSS Containment bug found and fixed, not obvious from the
  spec alone:** the card and its own `container-type`/`container-name`
  (for the brief's own "image on the left, or top when wide" responsive
  layout) can't live on the *same* element — a container can never be
  restyled by its own `@container` rule (excluded specifically to avoid
  a circular "my own size changes my own layout" dependency), confirmed
  with a minimal repro before landing on the real fix: a permanent
  `.lime-link-preview-slot` wrapper (inserted synchronously, holds
  `container-type`/`-name`, and — separately — an explicit `320px` width,
  since `contain: inline-size` also breaks ordinary shrink-to-fit sizing
  for an element with no explicit width of its own) with the actual
  `<a class="lime-link-preview">` card as its child, one level down,
  which *can* respond to the `@container` condition. The minimal card
  variant resets `container-type: normal` on its own slot (it never
  needs the query, and inheriting containment while also trying to
  shrink-to-content reproduced the exact same collapse, just worse —
  found live: its own text wrapped one character per line without the
  reset).
- **A real, live-only scroll bug found and fixed, distinct from the
  above:** unlike an attachment (whose placeholder reserves its real,
  final box size *synchronously*, so `createStickyScroll`'s own
  late-image-`load` mechanism only ever has to handle a *decode*
  finishing late, never a *layout* shift), the link-preview slot starts
  at zero height and only grows once `getLinkPreview`'s own Promise
  resolves — a genuine asynchronous height change, not just a late
  decode. Relying on the existing `load`-event mechanism alone measured
  live as **flaky** even for a card with an image (repeated runs: at the
  bottom / not / at the bottom), and **never fires at all** for an
  image-less card (the minimal fallback, or the `image_url: null`
  fixture) — confirmed both empirically before fixing. `paintLinkPreviews`
  now takes an optional `stickyScroll` controller and calls
  `.maybeStayAtBottom()` explicitly, right after the height-changing DOM
  mutation — the same pattern `renderThread`/`appendMessage` already use
  for their own synchronous inserts, sidestepping both failure modes
  outright rather than trying to make the indirect mechanism more
  reliable.

## Chat backgrounds (LIME-45, removed 2026-09-29 in favor of app-wide appearance)

**Removed on 2026-09-29 (LIME-50, user decision):** per-chat backgrounds
are gone — `setChatBackground`/`getEffectiveBackground`, the `--surface-bg`
override on `.lime-chat-body`, the 8-swatch/4-pattern/photo popover, and
`conversation_members.background` are all deleted, not just deprecated.
The replacement is one **app-wide** canvas tone (see "Appearance
(LIME-50)" below) — the user's own screenshots showed LIME-45's
per-chat colour painting only the chat card, "which looks broken,"
against a reference where one pale tone tints every panel. The
resolution/contrast methodology below (computed swatches, real
Playwright verification, bugs found live) stays a valid record of how
that system worked and was verified — kept for history, per this
project's own convention (see LIME-43-revert's identical treatment of
receipts), not because any of this code still runs. To reinstate,
revert the LIME-50 commit's removal of it specifically (not a wholesale
revert of LIME-50 itself, which also carries the app-wide canvas work).

- **Reuses LIME-46's own `--surface-bg` fade system directly — no second
  variable.** The brief's own draft named a new `--chat-bg` variable, but
  `.lime-composer` already lives *inside* `.lime-chat-body`
  (`public/index.html`) and both its own background and every fade
  (`gradients.css`) already read the inherited `--surface-bg`
  (`lime.css`) — LIME-46's own comment on `body`'s declaration had
  already anticipated exactly this ("LIME-45 (later) will override this
  on the thread specifically… every fade there follows automatically,
  for free"). So `app.js` overrides `--surface-bg` as a local inline
  style on `.lime-chat-body` alone; the composer's background and every
  fade in `gradients.css` pick it up through ordinary CSS inheritance,
  with zero edits to either file. `.lime-chat-body` itself had no
  `background` property at all before this brief — that one rule
  (`lime.css`) is the only thing that was actually missing for the
  override to paint anything.
- **The contract**, mirroring `setStarred`/`updateProfile` (a plain
  field on an existing snapshot row, not a new adapter capability — no
  file storage or network call of its own, so no `adapter().…`
  delegate):
  - `getEffectiveBackground(conversationId)` (read) / `setChatBackground(conversationId | null, background)` (write) — see the Reads/Writes lists above for the exact resolution order and the "apply to all chats" semantics.
  - `background` shape: `{ kind: 'default' | 'color' | 'pattern' | 'photo', color, patternId, path, avgColor }`.
  - Production: `conversation_members.background jsonb` (per chat) and a new `user_settings.default_background jsonb` (per user — `user_settings` didn't exist before this brief; added to `schema.sql` with its own owner-only RLS).
  - Local: the same store snapshot (both fields just ride along on the existing `profiles`/`conversation_members` arrays `LocalAdapter.save`/`.load` already persist wholesale — no schema plumbing needed there), with photos in IndexedDB via the existing `uploadAttachment`/`getAttachmentUrl` (LIME-38).
- **"Apply to all chats" clears this user's own per-chat overrides, not just future ones.** Read literally, "changes the other chats too" (the brief's own gate) can't be true for a chat that already has its own explicit background unless something actively touches it — so `setChatBackground(null, background)` both sets `default_background` **and** deletes `background` off every one of the current user's own `conversation_members` rows. A conversation with no override left falls back to the new default automatically (`getEffectiveBackground`'s own resolution order), so every chat visibly matches immediately, not just ones that were already on the default.
- **8 colour swatches, computed, not eyeballed.** `.lime-message__content`'s
  fixed `--soil-bg-surface` (`#f0eee6`) needs ≥3:1 against whichever
  swatch paints the thread behind it, or the bubble stops reading as a
  distinct object (the brief's own requirement — "swatches that fail
  don't ship"). A full sweep of Seed's `lime`/`meadow`/`soil`/`brick`/
  `yellow` ramps (script: `contrast-sweep.js`, scratchpad) found that
  **every light/pastel shade in every ramp measured under 1.3:1** — the
  bubble and a pastel wallpaper are simply too close in lightness to
  ever clear 3:1 against this specific bubble colour. Only mid-to-dark
  shades clear it; the 8 that shipped (two each from `brick`/`lime`/
  `yellow`/`soil`, a light-ish and a dark-ish one per ramp — `meadow` has
  no shade dark enough in the ramp to qualify, so it has no
  representative) range from 3.10:1 to 8.94:1. The pill's own
  ink-on-pill contrast (metadata text, see below) cleared >10:1 for
  every candidate regardless — never the binding constraint.
- **Patterns:** 4 presets (`dots`/`diag`/`grid`/`chevron`), each a fixed
  `{ patternId, color }` pair rather than a separate colour-then-pattern
  picker (the brief's own UI list names one picker step, "Patterns
  (thumbnails)", not two). Rendered as an inline SVG data URI
  (`patternSvgDataUri`, `app.js`) — white lines/dots at a low fixed
  opacity (0.08–0.12) over the flat base colour, which reads as "subtle…
  tinted from the base colour at very low contrast" regardless of the
  base hue, without computing a separate lighten/darken tint per swatch.
- **Photos:** upload via the existing `uploadAttachment`/`getAttachmentUrl`
  seam (no new storage mechanism). `avgColor` is computed client-side —
  draw the resolved `<img>` to a 16×16 canvas and average every pixel
  (`computeAverageColor`, `app.js`) — then stored alongside `path` on the
  background object; a photo's own fade/composer colour is this
  `avgColor`, never the photo itself (a gradient can't blend into a
  bitmap). The visible background layer is a `linear-gradient` scrim at
  `avgColor`, 55% opacity, stacked under the photo — the brief's own
  "semi-opaque layer of avgColor" — not a separate overlay element.
- **On-background legibility pills**, scoped to `.lime-chat-body--custom-bg`
  (set whenever the effective background's `kind !== 'default'`, so the
  plain canvas default never gets an always-on visual change nobody
  asked for): `.lime-date-divider`, `.lime-message__meta` (sender + time
  together, one pill, not two), and `.lime-message__replies` (the "N
  replies" summary — the only other place text is drawn directly on the
  thread background rather than inside a bubble or the out-of-scope
  reply panel) get `color-mix(in srgb, var(--soil-bg-surface) 80%,
  var(--surface-bg) 20%)` — the brief's own "~80%" reading as a mix
  *with* the active background (keeping its own tint faintly present),
  not a flat opaque chip that ignores it.
- **A real event-bubbling bug found and fixed, not obvious from the
  spec alone:** `wireDropdownToggle` (`app.js`) installs one shared
  `document.addEventListener('click', () => dropdown.classList.remove
  ('is-open'))` per dropdown, with no per-menu opt-out — correct for
  every *other* `.lime-menu` in this app (one action, then close), but
  wrong here: the brief's own "applies live as a preview" implies trying
  several picks in a row without the panel closing after each one. Found
  live via Playwright, not reasoned about in advance: a second pick right
  after a first (checking "Apply to all chats", then choosing a colour)
  silently closed the menu before the second click landed, making the
  next target time out as "not visible." Fixed with `e.stopPropagation()`
  at the top of the popover's own delegated click handler, so interior
  clicks never reach that document-level listener at all.
- **The popover panel is bounded and scrollable** (`max-height: min(420px,
  70vh); overflow-y: auto`) rather than growing to fit whatever
  `renderChatBgMenu()` last rendered — its *position* (`wireDropdownToggle`)
  is computed once, at the click that opens it, from whatever content
  height existed at that instant; content that grows taller afterward
  (e.g. once "Remove photo" appears) could otherwise push the panel past
  where it was measured to fit.
- **The reply panel is out of scope, unchanged** — it keeps its own
  fixed default background regardless of the open conversation's chat
  background, per the brief.

## Appearance (LIME-50 canvas, LIME-51 mode)

- **The contract**, mirroring `setStarred`/`updateProfile` (a plain field
  on the existing snapshot, not a new adapter capability): `getAppearance()`
  / `setAppearance(patch)` — see the Reads/Writes lists above. Shape:
  `{ theme, canvas, pattern }`. Production: `user_settings` (`theme text`,
  `canvas text`, `pattern jsonb`; the table already existed from LIME-45,
  repurposed here — `schema.sql`). Local: the same store snapshot
  (`profile.appearance`, riding along on the existing `profiles` array
  `LocalAdapter.save`/`.load` already persists wholesale).
- **Ported from Seed, not reimplemented — with attribution.** `CANVAS_P`
  (5 presets) and `makeCanvasRamp(hex)` are copied from Seed's own brand
  customiser (`vendor/seed/components/layout/layout.html` ~48-88) into a
  new `public/js/appearance.js`, since `vendor/` itself can't be edited
  and this logic needs to run against Lime's own stored preference
  (`LimeStore.getAppearance()`), not Seed's demo-only `localStorage`
  keys. Not modified beyond the port itself.
- **A load-bearing gap found in survey, not assumed from the brief:**
  Seed's own mechanism only works if the semantic tokens it retints
  (`--soil-bg-canvas`, etc.) actually *read* the raw `--seed-soil-*` ramp
  it overrides. Lime's `[data-theme="light"]` block had hardcoded
  `--soil-bg-canvas`/`--soil-bg-surface` as **literal hex values**
  instead — porting `CANVAS_P`/`applyCanvas` alone would have changed
  nothing visible at all. Fixed by routing `--soil-bg-canvas` through
  `var(--seed-soil-0)` (`lime.css`) — Seed's own stock `'warm'` ramp
  already opens at `#F9F8F4`, byte-identical to Lime's old hardcoded
  value, so this is zero visual change for the default preset (verified
  live, not just reasoned about — TEND.md). `--soil-bg-surface` stays a
  hardcoded literal, deliberately **not** ramp-routed: it matches Seed's
  own reference behaviour (bg-surface is independently hardcoded there
  too, never ramp-derived) and sidesteps a real conflict — the ramp's
  own stop-100 is already claimed by `--soil-border-subtle`, and forcing
  bg-surface onto the same stop would have shifted border colour on
  every preset just to chase a bubble tone. Bubbles/composer/search
  fields keep one fixed warm tone across every canvas tone; verified
  per-preset via `bubble vs canvas contrast` (TEND.md) that this never
  drops to the point of the bubble blending into the canvas.
- **`--seed-soil-900` is never touched by `applyCanvas`, on purpose.**
  Lime already pins this one raw stop to a fixed ink (`#131b17`, `lime.css`,
  its own comment: the avatar identity system reads it directly for a
  theme-invariant colour) — `SOIL_RAMP_INDEXES` in `appearance.js`
  skips it explicitly, so a canvas tone can never move it. Verified live
  in a real browser (not just jsdom, whose custom-property computed-style
  support is unreliable) that `--seed-soil-900` reads identically before
  and after a tone switch.
- **A second load-bearing gap, also found in survey:** `--soil-text-muted`
  at its Seed default (`--seed-soil-500`) passed contrast against
  today's own `'warm'` canvas by the barest margin (4.58:1) and **failed
  outright against most of the other 7 presets** (as low as 2.90:1 —
  `contrast-sweep`/`canvas-verify` scripts, TEND.md). Since Lime's own
  `--soil-text-muted` mapping is fixed regardless of which preset is
  active, "every preset must pass" (the brief) was mathematically
  impossible without moving that mapping. One step darker
  (`--seed-soil-600`, `lime.css`) clears ≥4.5:1 against all 8 shipped
  presets with real margin (4.74–8.44:1) — visibly, if subtly, darker
  muted text than before across the whole app, flagged for the gate.
- **8 canvas presets, not the brief's suggested 7–8 by coincidence — all
  8 candidates shipped.** Seed's own 5 (`warm` default, `cool-gray`,
  `warm-cream`, `blue-tint`, `pure-white`) plus 3 new pale tints generated
  (not hand-picked) via `makeCanvasRamp` from a chosen base hex (`lemon`,
  `sage`, `lilac`). `sage`'s base hex needed one round of tuning
  (`#EAF1E6` → `#E3EDDC`) to clear the muted-text check above; the other
  two cleared it on the first try. None needed dropping once muted text
  moved to `--seed-soil-600` — the full contrast table (ink, muted,
  border, bubble, per preset) is in TEND.md, computed twice (a Node
  script during design, then cross-checked against real rendered pixels
  via Playwright).
- **Fades are CSS masks now, not colour-matched overlays** — see
  `gradients.css`'s own header comment for the full mechanism and why:
  in short, a mask makes the scrolling content itself fade to
  transparent at its own edge, revealing whatever is actually behind it
  (a flat tone today; a pattern or photo in LIME-52), with no colour of
  its own to keep in sync. `--surface-bg` (LIME-46) is fully retired —
  grep confirms zero remaining declarations or `var(--surface-bg)`
  call sites anywhere. Verified with a temporary checkerboard diagnostic
  background (Playwright): sampling inside the fade zone shows genuine
  black/white variance from the checkerboard showing through, not one
  flat colour a colour-matched overlay would have produced.
- **Panels unified**, per the brief's own explicit list: the right panel's
  distinct Seed-flush colour (`var(--calm-bg-subtle-default)`) is
  replaced with the same `var(--soil-bg-canvas)` every other panel
  shows — verified by sampling real rendered pixels (not each element's
  own `background-color`, which can legitimately be `transparent` while
  still displaying the right colour through inheritance) at the list
  column, the thread, and the right panel, confirming they match within
  antialiasing tolerance.
- **The Appearance UI** lives in two places sharing one set of functions
  (`renderAppearanceMenu`/`renderPreferencesSection`, both build the same
  `.lime-appearance-swatches` markup from `LimeAppearance.CANVAS_P`):
  the header shortcut (`#appearance-toggle`, a palette icon — dew has no
  sun/palette icon, checked — replacing LIME-45's sun) opens a compact
  popover with the 8 round swatches plus "More in Settings"; Settings ->
  Preferences (a new nav item, `dew-gear`) -> Appearance has the same
  swatches inline. Both apply live (no Save/Cancel — matches Login &
  security's own "changes are per-row" pattern) and persist immediately.
- **A real event-bubbling bug, same root cause LIME-45 already found and
  fixed once:** the header popover also needs to stay open across a few
  picks (a live preview), so its own delegated click handler calls
  `e.stopPropagation()` too, for the same reason and against the same
  shared `wireDropdownToggle` document-level close listener.

### Tone-relative layers (LIME-50-fix)

- **Root cause, found by reading `lime.css` rather than guessed:** LIME-50
  only routed `--soil-bg-canvas` through the ramp. `--soil-bg-surface`
  stayed a hardcoded literal, and Seed's own `--calm-bg-subtle-*`/
  `--calm-bg-normal-*` map to ramp stops (`soil-25/30/40/50/75`) that
  `CANVAS_P`'s 11-value presets never touch at all — so on every tone but
  Warm, bubbles, the composer box, the segmented toggle, hovered/selected
  list rows and the mic pill stayed the old Warm-tinted beige/grey,
  clashing with the tinted canvas around them (the user's own QA
  screenshots, lemon and sage).
- **One relative system, both themes.** Five tokens
  (`--lime-layer-raised`/`-surface`/`-hover`/`-active`, `--lime-border-subtle`)
  are each the canvas mixed toward ink (light) or white (dark) via
  `color-mix(in oklab, ...)` — OKLab specifically, not `srgb`, for the
  same reason LIME-46 picked it for fades: perceptually-uniform mixing
  avoids a "grey dip" partway through. Every dependent Seed token
  (`--soil-bg-surface`, `--soil-bg-elevated`, `--calm-bg-subtle-default/
  -hover/-active`, `--calm-bg-normal-default/-hover`, `--soil-border-subtle`,
  `--calm-border-normal-default`) is remapped to one of the five in
  Lime's own theme blocks — every component that already reads those
  tokens (including Seed's own `tabs.css`, unedited) follows the tone
  with no per-component changes.
- **Percentages tuned by measurement, not guessed** — light: surface 3%,
  hover 8%, active 12%, border 14% (toward ink), raised 70% (toward
  white); dark: surface 6%, hover 10%, active 14%, border 18%, raised
  22% (toward white). Verified across all 8 canvas tones plus dark: body
  text and muted text both ≥4.5:1 on surface and active; surface-vs-
  canvas, hover-vs-surface, and active-vs-hover each ΔL(OKLab) ≥ ~0.02;
  the raised layer clearly distinct from surface. `sage` needed a second
  base-hue retune (`#E3EDDC` → `#D8E6D0`, `appearance.js`) once its
  muted-text margin, already thin from LIME-50, met the new surface
  layer's own slight darkening. Full table in TEND.md.
- **A real, self-inflicted parser bug found live, not from reading the
  diff:** a comment written as `--calm-bg-subtle-*/--calm-bg-normal-*`
  contains a literal `*/` — closing the CSS comment early and silently
  truncating every declaration after it in the stylesheet (confirmed via
  the browser's own parsed `CSSStyleSheet.cssRules`: only 2 rules
  registered from a ~660-rule file). Every layer token, and everything
  remapped to them, was empty until this was found and fixed — a good
  reminder that "the file has no syntax errors" isn't the same claim as
  "the CSS parser agrees," and that a real browser's own parsed
  stylesheet is worth checking directly when computed styles don't match
  what the source appears to say.
- **The mic pill has no fill at rest**, matching the `+` button
  (`.lime-composer__voice`'s own permanent `--calm-bg-subtle-default`
  background removed; `.lime-composer__aux`'s shared `background: none`
  now applies to both) — the brief's own explicit ask, once every other
  subtle fill in the app started following the tone and a permanently-lit
  mic pill read as a separate, disconnected chip.
- **The lime accent (`--selected-*`, the nav active state and primary
  buttons) is unchanged** — checked against all 8 tones, still clearing
  the brief's own ≥3:1 bar for the non-text fills.

### Mode (LIME-51)

- **Why this needed its own brief, confirmed in survey rather than
  assumed:** Seed's own `[data-theme="dark"]` token block (`tokens.css`)
  is comprehensive — `--soil-*`, `--calm-*`, `--good-*`/`--warn-*`/
  `--bad-*`, and `--selected-*` all already have real dark values, and
  Lime's own component CSS almost entirely reads those semantic tokens
  rather than hardcoding colours. Setting `data-theme="dark"` alone
  already made most of the app look reasonable. The gaps were narrow but
  real (below), not a ground-up dark palette.
- **The mode itself:** Light / Dark / System, a `.seed-tabs--pill`
  segmented control (Seed's own tab component, not a new one) shared
  between the header popover and Settings -> Preferences -> Appearance
  (`modeTabsHtml`, top-level in `app.js`, not IIFE-private, the same
  reasoning `escapeHtml` already is). Stored in `getAppearance().theme`
  (`'light' | 'dark' | 'system'`); `LimeAppearance.applyTheme(mode)`
  resolves `'system'` via `matchMedia('(prefers-color-scheme: dark)')`
  and sets `data-theme` on `<html>`. A single `matchMedia` change
  listener, installed once, re-reads the *stored* mode on every fire
  (not the mode captured when the listener was created) and only acts
  if it's still `'system'` — live-following the OS preference without
  fighting an explicit Light/Dark choice made after the listener was
  installed.
- **No flash of light theme, the brief's own hard requirement:** a tiny
  inline `<script>` in `<head>` — before any `<link rel="stylesheet">` —
  reads a raw `lime-theme` localStorage key directly and sets
  `data-theme="dark"` immediately if needed, since `LimeStore` itself
  loads asynchronously and can't be consulted this early. The identical
  block is duplicated in `index.html`, `login.html` and `signup.html`
  (the brief's own explicit ask) rather than factored into a shared file
  — an external `<script src>` here would itself be a render-blocking
  request, defeating the point. `LimeAppearance.applyTheme` keeps this
  raw key in sync every time it runs, so the next load's guess is
  accurate; `LimeAppearance.init()` (`LimeStore.getAppearance().theme`)
  corrects it authoritatively once the real profile loads, for the rare
  case the two disagree (a different browser profile, or a change made
  in a different tab).
- **Replaces, not adds to, a dead read:** `app.js` used to read
  `localStorage.getItem('lime-theme')` unconditionally at parse time,
  after most stylesheets had already been requested — confirmed via
  `grep` that nothing anywhere ever *wrote* that key, so it was already
  fully inert before this brief touched it. Removed outright, not kept
  alongside the new mechanism.
- **A real, load-bearing bug found live via Playwright, not visible from
  reading the code:** `body` never set its own `color` at all — every
  element without an explicit colour of its own (the message bubble text
  among them) fell through to the browser's own UA default, black, not
  `--soil-text`. Invisible in light mode (`--soil-text` resolves to
  `#131b17`, indistinguishable from pure black at normal sizes) and only
  exposed once dark mode gave `--soil-text` an actually different value
  to diverge from — measured live at **1.31:1** (bubble text on a dark
  bubble) before the fix, **14.50:1** after adding `color: var(--soil-text)`
  to `body` (`lime.css`).
- **Avatar pastels got real dark variants, not a blanket recolour.** The
  12 `--lime-avatar-*` tokens moved from a theme-invariant `:root` block
  into `[data-theme="light"]`/`[data-theme="dark"]` pairs — each dark
  value computed from its light counterpart's own HSL (-15 saturation,
  floored at 20; -10 lightness, floored at 55; never hand-eyeballed),
  verified to clear **9.58:1 to 12.97:1** against the one ink colour that
  still never changes (`--seed-soil-900`, pinned for the avatar identity
  system specifically — same reasoning canvas tones already respect it).
- **The only other hardcoded-colour gap the audit found:**
  `.lime-recent`/`.lime-messages`'s own visible scrollbar thumbs (every
  other scroller hides its thumb entirely). A black-based translucent
  thumb reads fine on a light canvas and is nearly invisible on a
  near-black one — wrapped in a new `--lime-scrollbar-thumb` token with
  real light/dark values, rather than left as the one bare literal.
- **Canvas tones are light-mode-only** (Seed's own convention, per the
  brief) — the swatch grid renders `disabled` (not hidden) in dark mode,
  with "Tones apply in light mode" printed inline, in both the header
  popover and Preferences.
- **Everything else audited and left alone, with reasoning, not
  silently:** the confirm-dialog's danger button (`color: #fff` on a
  bold red background), the album/reply-quote "+N" photo overlays
  (`rgba(19, 27, 23, ...)` scrims with white text over a photo), and the
  modal backdrop's own blur tint are all genuinely theme-invariant by
  design (a bold-coloured surface or a scrim over arbitrary photo
  content, not a themed panel) — kept as literals, not converted to
  tokens that would have no second value to hold anyway. The
  `--good-bg-bold-default` decorative gradient endpoint (`#14b8a6`, the
  "story unseen" avatar ring) is a fixed accent colour, not sampled for
  contrast against anything, and reads fine in both themes (checked via
  screenshot, not assumed). `gradients.css`'s own `#000` values are
  every one inside a `mask-image` gradient — a mask's alpha channel, not
  a colour that ever gets painted; grep-visible but not a real hit.
- **Nav/primary-button accent needed no Lime-specific dark override at
  all** — checked, not assumed: Seed's own dark `--selected-*` tokens
  (already lime-hued by default, unlike the "mint" Lime's own light
  override retunes) measured **5.58:1** (primary button text on its own
  background) and **11.09:1**/**8.06:1** (nav "selected" text/icon) —
  all clearing the brief's own 4.5:1/3:1 bars before any Lime-specific
  change, so none was made.

### Pattern (LIME-52)

- **All 4 built-in presets (dots, grid, diagonal, noise) are drawn
  in-house as inline SVG data URIs (`appearance.js`)** — the same
  technique LIME-44/45 already used for their own inline images. No
  third-party pattern-tile assets are used anywhere in the app, so no
  credit line is needed. (LIME-54, 2026-09-30: an earlier draft tried
  sourcing real third-party tiles plus a matching upload-your-own-tile
  slot; the user dropped that direction and both were removed.)
- **One fixed layer, `body::before`**, behind every panel — `position:
  fixed; inset:0; z-index:-1`, sitting behind `#layout`'s own normal-flow
  content in the same stacking context without needing to touch
  `#layout` itself (already `background: transparent`, LIME-50). One
  rule serves all three pattern states (none/preset/upload) via CSS
  custom properties `appearance.js`'s `applyPattern()` sets or leaves at
  their no-op fallback (`none`/`transparent`) — no class toggle needed.
- **Presets are tinted masks, not fixed assets** — a low-alpha colour
  (`--lime-pattern-tint`, `color-mix(in srgb, ink|white intensity%,
  transparent)`) masked into the pattern's own shape
  (`--lime-pattern-mask`, the mask's alpha channel, not luminance — white
  shapes on a transparent ground). Tints toward ink in light, white in
  dark — matching LIME-50-fix's own tone-relative layer convention
  exactly (a bug in an earlier draft tinted toward ink unconditionally,
  caught while writing this brief's own contrast verification, not
  visually). Recolours with the tone and mode automatically since the
  tint is token-derived, never a fixed hex.
- **Uploads blend against body's own canvas colour** via `mix-blend-mode`
  (`multiply` in light, `screen` in dark — the brief's own explicit
  choice) at a capped `opacity`, re-applied whenever the theme changes
  (an upload's own blend mode depends on it) — `LimeAppearance.applyTheme`
  calls `applyPattern` again internally for exactly this reason, so a
  live System-mode follow updates an active upload too, not just a fresh
  pattern pick. Stored via the existing `uploadAttachment`/
  `getAttachmentUrl` seam (LIME-38), path namespaced `appearance/…` (the
  brief's own literal ask), ≤ 1 MB enforced client-side with the same
  inline-error pattern (`setFieldError`) the Profile form already uses —
  no native `window.alert()`.
- **Intensity (Low/Medium) tuned by computation, not guessed — and
  Medium needed adjusting from the value that first shipped.** The
  darkest possible pattern pixel is deterministic (mask fully opaque ->
  the tint's own full stated alpha over canvas; masking can only show
  *less* of a layer's own colour, never more, so this is a true ceiling,
  not an approximation) — checked analytically against on-canvas text
  for 2 light tones plus dark, both intensities. Medium at its first
  value (11%) measured 4.49:1 in dark mode — just under the 4.5:1 floor,
  the darkest canvas in the set having the least room — found while
  writing this exact check, not visually. Dropped to 9%, clearing 4.77:1
  with real margin, without needing a separate per-theme value.
- **Contrast verification is computed, not screenshot-sampled** — three
  separate attempts at pixel-sampling this from a live render each
  landed on *real UI content* instead of the pattern layer itself (the
  sidebar's own muted-text labels; an avatar's initials text sitting
  just above the composer; the "No messages yet." empty state's own
  anti-aliased edges past a supposedly generous exclusion margin). Since
  the pattern's own colour range is fully known from its own formula,
  computing the exact worst case directly is both correct and immune to
  whatever happens to be on screen — TEND.md's own table.
- **The fades (LIME-50's own masks) needed no change, confirmed by
  grep, not just by the brief's own claim** — `gradients.css` has no
  `lime-pattern` reference anywhere; a mask that reveals "whatever's
  behind" the scroller was already agnostic to what that background
  actually contains.
- **`prefers-contrast: more` hides the pattern outright**, not just
  dims it further — "Low" is already the minimum intensity this app
  offers, so there's no lower step to fall back to.

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
