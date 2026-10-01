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
- `addMembers(conversationId, profileIds)` — added in LIME-27 (see "Deviations from the contract" below)
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
  `grade_levels`, `subjects`, `bio`, `timezone`, `phone`, `avatar_url`
  (added LIME-49 — the column already existed, this is its first
  writer); any other key rejects the whole call (nothing partially
  applies). `display_name`, if present in the patch, may not be empty.
  **Email and password are never accepted here** — they belong to the
  auth seam below, not this whitelist, because on Supabase they're
  auth-provider concerns, not columns this call would ever be allowed
  to touch directly.

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
out "who am I." As of LIME-33: it reads `lime-demo-session` from
`localStorage` — `{ userId, email }`, written by `LimeAuth.signUp`/
`signInWithPassword` — and resolves by `userId` first (checked against
`profiles.has(...)`), falling back to a lookup by `email` for an
old-shape session (one written before this brief, still just `{ email }`
or `{ email, displayName }`), so a browser that was already signed in
isn't silently logged out by the shape change alone. With no session, or
no match either way, it falls back to `teacher-002` and logs once — but
that fallback is **not actually reachable in real browser use any more**:
`app.js`'s own session gate (below) redirects to `login.html` before
`LimeStore.init()` ever runs without a valid session. The fallback stays
in `resolveCurrentUserId()` mainly for jsdom test harnesses that don't
bother setting up a session at all, avoiding a mass rewrite of every
existing test.

**The session gate (`app.js`, LIME-33):** the very first executable logic
in `app.js` checks for a valid session and, with none, redirects to
`login.html` — replacing the earlier LIME-05a "no gate" decision, made
back when there was no real backend or real session to check against. It
auto-skips whenever `navigator.userAgent` contains `jsdom` (every jsdom
test harness, with zero per-test configuration needed), with two explicit
overrides for a test that wants non-default behavior:
`window.LIME_TEST_FORCE_AUTH_GATE` (exercise the redirect even under
jsdom) and `window.LIME_TEST_SKIP_AUTH_GATE` (skip it regardless of
environment). `LimeStore.init()` itself is also skipped when the gate is
redirecting, so a page about to navigate away doesn't waste time loading
and rendering data for it first.

**A `file://`-specific caveat (LIME-33-fix):** Firefox's real default for
`security.fileuri.strict_origin_policy` (`true`) treats every distinct
`file://` URL as its own storage-isolated origin — including different
HTML files in the same folder — so `signup.html`, `login.html` and
`index.html` each get a **separate** `localStorage` with no sharing at
all when opened directly off disk in Firefox. Confirmed directly against
a copy of a real Firefox profile (see `TEND.md`'s `## LIME-33-fix` for
the full investigation, including how easy this is to miss: even
`puppeteer-core`'s own Firefox launcher silently overrides this exact
preference for "testing convenience," so an automated repro has to
explicitly restore it to see the bug at all). Chrome has no such per-path
isolation, and neither does any `http://`/`https://` origin — this is
`file://`-and-Firefox-specific. Since no app code can bridge two
genuinely separate storage origins, the fix is `LimeAuth.checkStorageWorks()`
(a real write-then-read-back probe) plus `describeGateRedirectReason()`
in `app.js`, which explain the failure in plain words (`login.html?reason=storage`
or `?reason=fileorigin`) instead of a silent bounce — not a workaround.
The real fix for previewing this app in Firefox is to serve it over a
local `http://` server instead of `file://`.

**Local credentials (`lime-auth-v1`, LIME-33):** a separate `localStorage`
key, `{ [email]: { userId, salt, hash } }` — entirely apart from
`lime-demo-session` and from `LimeStore`'s own `lime-state-v1` snapshot.
The hash is PBKDF2-SHA256 via `crypto.subtle`
(`crypto.subtle.importKey` → `crypto.subtle.deriveBits`), a random
16-byte salt, 100,000 iterations, salt/hash stored as base64 (JSON has no
binary type). **Never the plain password, in any form, anywhere.** Local
demo only; Supabase auth replaces this entirely — a real login never
touches `lime-auth-v1`, Supabase's own `auth.users` table replaces it.

**Seed teachers can still sign in**, with no `lime-auth-v1` credential of
their own: `signInWithPassword` falls back to accepting
`window.LIME_DEMO_CREDENTIALS.password` (the existing gitignored
`demo-config.local.js`) when the email matches a seed `profiles` row and
no local credential exists for it yet. If a seed teacher later calls
`changePassword`, that claims the account — a real `lime-auth-v1`
credential is stored, and the shared demo password no longer works for
that email.

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

### `auth.js` — the write half of the auth seam (LIME-31, real accounts LIME-33)

`getCurrentUserId()` above is the *read* half of the auth seam (who am
I); `auth.js` is the *write* half (change who I am, or how I sign in).
Every function returns a Promise and is called directly by the UI —
never through `LimeStore`, since email and password are explicitly **not**
`updateProfile`'s concern (production-ready rule: they belong to the auth
provider, not `profiles`). Shaped like Supabase's own auth client
(`signUp`/`signInWithPassword`/`signOut`/`getSession`) so the switch
checklist below can swap each function's body for its Supabase equivalent
without changing a single call site.

- **`signUp({ email, password, displayName })`**
  - **Local:** validates email format, password ≥ 8 characters, and a
    non-empty display name; rejects if the email is already taken —
    checked against **both** `lime-auth-v1` credentials **and**
    `LimeStore.findProfileByEmail` (a seed teacher's email is taken too,
    even with no local credential yet — signing up with it would
    otherwise create a second, disconnected identity for the same
    person). Generates a `crypto.randomUUID()` id, hashes the password
    (PBKDF2-SHA256, see "The auth seam" above) into `lime-auth-v1`, calls
    `LimeStore.createProfile({ id, email, display_name })`, then writes
    the session and resolves `{ userId, email }`. The UI redirects to
    `index.html` on success.
  - **Supabase:** `supabase.auth.signUp({ email, password })`, with
    `displayName` passed as user metadata a trigger on `auth.users`
    insert reads to create the matching `profiles` row (see
    "Onboarding" above) — `createProfile` itself becomes unnecessary,
    since the trigger does that job.
- **`signInWithPassword({ email, password })`**
  - **Local:** two paths. A `lime-auth-v1` credential for that email
    verifies the password against the stored PBKDF2 hash. With no local
    credential, a matching seed `profiles` row accepts
    `window.LIME_DEMO_CREDENTIALS.password` instead — the "demo
    credentials aren't configured" message only ever applies to this
    seed-teacher path; a local account never needs that file to exist.
    Either path writes `{ userId, email }` to `lime-demo-session` and
    resolves the same shape.
  - **Supabase:** `supabase.auth.signInWithPassword({ email, password })` —
    the seed-teacher demo-password fallback has no Supabase equivalent
    and is dropped entirely; every real account authenticates against
    Supabase's own stored credential.
- **`getSession()`** — resolves the parsed `lime-demo-session` value, or
  `null`. **Supabase:** `supabase.auth.getSession()`.
- **`changeEmail(newEmail)`**
  - **Local:** validates the format, rejects if another profile already
    has that email (`LimeStore.findProfileByEmail`), then writes
    `profiles.email` (via a narrow store method, not `updateProfile` —
    see "Deviations" below), updates the `email` field inside
    `lime-demo-session` so the session still resolves to the same
    profile on the next `LimeStore.init()`, and (LIME-33) renames the
    `lime-auth-v1` credential's own key from the old email to the new
    one — `signInWithPassword` looks credentials up *by* email, so a
    stale key would permanently lock this person out of signing back in
    with the password they already set.
  - **Supabase:** `supabase.auth.updateUser({ email })`, which sends a
    confirmation email and only takes effect once it's clicked —
    `profiles.email` updates via a database trigger on that
    confirmation, not synchronously in this function. The local version's
    "succeeds immediately" behavior is a deliberate simplification for
    the prototype, not a preview of production behavior.
- **`changePassword({ current, next, confirm })`**
  - **Local (LIME-33):** validates `next` is at least 8 characters,
    differs from `current`, and matches `confirm` — then **really
    verifies** `current`: against the stored `lime-auth-v1` hash for a
    local account, or against `window.LIME_DEMO_CREDENTIALS.password` for
    a seed teacher who's never set their own password yet. On success,
    stores a real new PBKDF2 hash. For a seed teacher this **claims the
    account** — from then on they have a real local credential and the
    shared demo password no longer works for their email.
  - **Supabase:** `supabase.auth.updateUser({ password })`, after
    Supabase itself re-authenticates `current` server-side (this module
    would still send `current`, just to Supabase instead of validating it
    locally).
- **`signOut()`** — clears `lime-demo-session` and redirects to
  `login.html`. Called by both `#sign-out-btn`'s own handler and the
  Settings modal's Sign out row (via the same button), so the logic
  exists in exactly one place.
- **`resetCredentials()`** (LIME-33) — clears `lime-auth-v1`. Called
  alongside `LimeStore.reset()` by the "Reset demo data" handler, not
  folded into `LimeStore.reset()` itself — accounts are this module's own
  concern, the same reasoning email/password never go through
  `LimeStore.updateProfile` either. **Local only** — "reset" has no
  Supabase equivalent, same as `LimeStore.reset()` itself.

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
   signup → a profile row with `auth_user_id` set, via a Supabase trigger
   on `auth.users` insert rather than `LimeStore.createProfile` — that
   local-only write drops out entirely here; existing seed teacher →
   linked by email on first login), so `current_profile_id()` actually
   resolves to something for every real login.
5. Run `seed-data/seed.ts` against the new database (it's fixed to use the
   corrected reactor rule in LIME-24b — no longer a blocker by the time
   this checklist is used for real).
6. Swap `auth.js`'s local `signUp`/`signInWithPassword`/`changeEmail`/
   `changePassword` bodies for their Supabase equivalents (listed next to
   each above) — same function names and signatures, so nothing calling
   `LimeAuth.*` needs to change. `signOut()` swaps to
   `supabase.auth.signOut()`. `resetCredentials()` and the seed-teacher
   demo-password fallback in `signInWithPassword` both drop out — neither
   has a Supabase equivalent.
7. `auth.html` (LIME-48; replaces the old separate `login.html`/
   `signup.html` pages, now thin redirects to it) used to load the
   Supabase JS CDN script and `public/js/supabase.js` (an unconfigured
   placeholder client) directly before LIME-33 removed both tags — neither
   is wired into the local flow. Either wire `supabase.js` up as the real
   client this checklist's `SupabaseAdapter`/`auth.js` need, or delete it
   once its logic has been absorbed elsewhere.
8. **Google and Apple sign-in (LIME-48):** the two buttons on `auth.html`
   are disabled with a "Soon" tag today — wire them to
   `supabase.auth.signInWithOAuth({ provider: 'google' | 'apple' })` and
   remove `disabled` (each provider also needs enabling in the Supabase
   dashboard first). No local equivalent exists or is planned; this is a
   Supabase-only capability.
9. **Account enumeration (LIME-48):** `auth.html`'s email-first flow
   calls `LimeAuth.accountExists(email)` to decide whether to show the
   password step or the create step — which means the response itself
   reveals whether an email has an account. That's an acceptable
   simplification for the local demo (there's no real security boundary
   to protect locally), but production should avoid it — either a
   Supabase magic-link/OTP flow (no password step to reveal the
   distinction at all) or a uniform "Continue" response regardless of
   whether the email exists. `accountExists` itself has no Supabase
   equivalent and should be removed, not reimplemented, when this is
   built for real.
10. Flip `LIME_BACKEND` from `'local'` to `'supabase'`.

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

## Real profile photos (LIME-49)

- **The pipeline:** pick (`image/*`, ≤ 5 MB) → decode → centre-crop to a
  square (the shorter side) → resize to 256px on a canvas, once, at
  upload time (never a live/repeated resize) → `LimeStore.uploadAttachment`
  under `profile-photos/<profileId>/…` → the resolved path saved as
  `profiles.avatar_url` via `updateProfile`. A null canvas blob (the
  browser's own memory ceiling, the exact "silently successful, garbage
  result" bug LIME-52-fix3 found in the pattern-upload pipeline)
  rejects with a friendly message instead of resolving with nothing.
- **A second persistent, document-level file input** (`#avatar-upload-input`,
  `index.html`), not the pattern upload's own `#pattern-upload-input` —
  LIME-52-fix3's own hard lesson (a file input rendered inside markup
  that gets replaced loses an in-flight OS picker silently) applies
  here too, so the *shape* is reused (one persistent input, a job
  token, a busy state, never fail silently) — but the two inputs stay
  separate, since the accept type and the entire processing pipeline
  (one square crop, not a Texture/Photo split) are different enough
  that sharing the DOM node would mean branching on "which feature is
  this for" at every step of a shared change listener.
- **The photo is "part of the form"** (saves with Save changes, reverts
  with Cancel) but its own live preview can't wait for Save and can't
  come from a full `renderProfileSection()` re-render either — that
  would discard whatever the user's already typed into every other
  field. A module-level `pendingAvatarPath` (undefined: no pending
  change; `null`: pending removal; a string: a newly processed path)
  tracks the staged change, and a small `updateProfileAvatarPreview()`
  surgically updates just the avatar + Remove-photo affordances,
  leaving the rest of the form untouched. A render (a fresh load, a
  Discard, or a successful Save) resets it, and also bumps the job
  token so a late-arriving upload result from before that reset is
  discarded as stale rather than silently reinstating a change the
  user already walked away from.
- **Avatars everywhere:** every avatar-markup call site in `app.js`
  (lists, the Recent row, the thread, replies, headers, clusters,
  members, the profile detail panel, the sidebar) now goes through one
  shared `avatarAttrsHtml(person)`, which adds `data-avatar-path` next
  to the existing `data-name` whenever `person.avatar_url` is set.
  `paintAvatar` resolves that path the same two-step way every other
  attachment in this app already does (`LimeStore.getAttachmentUrl`,
  async) — an `<img>` placeholder immediately, its real `src` filled in
  once the blob URL resolves. `repaintAvatar` (the live-update path,
  `lime:profile-changed`) takes the same path as a third argument.
- **Verified in the real installed browsers, not just Playwright's
  bundled Firefox** — per the amendment LIME-52-fix5's own findings
  added to this brief: Playwright's `firefox.launch()` runs a patched
  fork with its own Juggler automation branch, confirmed unable to even
  launch the real `/Applications/Firefox.app` binary directly
  (`executablePath` fails immediately — no Juggler pipe in a stock
  build). Verified instead with `puppeteer-core`'s WebDriver BiDi
  support, which drives the real installed Firefox (confirmed via
  `navigator.userAgent`, not assumed) and real Chrome identically. The
  full upload → save → sidebar/topbar/thread propagation → persist →
  remove cycle passed cleanly in both real binaries — this feature does
  **not** hit the pattern-upload's own parked Firefox-specific failure.
- **Production:** a Supabase Storage bucket `avatars`, publicly
  readable (any signed-in teacher can see any other's photo, same as
  `display_name` already works), writable only by the photo's own owner
  — see `docs/schema.sql`'s own policy draft, mirroring the
  `attachments` bucket's existing shape.

## Two tabs, one browser: sessions, merge-on-save and live sync (LIME-69)

Local-only behavior, written down as **the local stand-in for what a server does with concurrent writes**. A real backend replaces it; the rules below are the ones it must keep.

**Sessions are per tab.** `lime-demo-session` lives in `sessionStorage`, so two tabs of one window can be two people. Accounts (`lime-auth-v1`) and data (`lime-state-v1`) stay shared in `localStorage`. A new tab or window starts signed out; a duplicated tab inherits its source's session (the browser copies it); sign-out and sign-in affect only that tab.

**Saving is a merge, never an overwrite** (`store.js`, `persistNow`). Three states are involved: *base* (the stored snapshot this tab last agreed with), *local* (this tab's in-memory tables) and *latest* (the snapshot in storage right now). Rows are matched by key: `id` for profiles, conversations, messages and attachments; `conversation_id + user_id` for members; `message_id + user_id + emoji` for reactions.

1. **Union.** A row in either side survives. Nothing is dropped by a merge, so a stale read can delay a row but never lose it (a tab that finds its row missing from `latest` writes it back).
2. **Removals are soft.** Messages, conversations and attachments are never removed (conversations use `deleted_at`). A reaction removed by its user keeps its row with `removed_at` set (`getReactions` ignores those); reacting again revives the same row. This is what stops a merge from resurrecting something another tab removed.
3. **Per-field merge for rows both sides have.** A field only this tab changed (against base) keeps this tab's value; a field only the other tab changed takes theirs. If both changed the same field, the row with the newer `updated_at` (falling back to `created_at`, then `joined_at`) wins; a tie goes to this tab. Member rows gain `updated_at` on every star/archive/clear/read.
4. **Per-user fields stay per user.** `starred`, `archived_at`, `cleared_at` and `last_read_at` live on the member row and are only ever written by that member's own tab, so they never conflict across people.
5. **Stale reads are expected.** A browser can hand a tab an old copy of storage. Two guards: for 1.5s after each save, a tab detects its own changes against the base from *before* that save (so another tab's stale overwrite cannot revert them); and a stored row older than the one this tab last saw is ignored.
6. **Reset.** The snapshot key disappearing (another tab ran Reset demo data) means "everything is gone": the tab drops any pending save, queues a "Demo data was reset" toast and goes to sign-in. It must never write its own copy back.

**Live updates.** The browser's `storage` event fires in the *other* tabs only, so it means "someone else saved". The store merges the new snapshot into the cache, then emits the same events a local write would (`lime:messages-changed`, `lime:reactions-changed`, `lime:conversations-changed`, `lime:profile-changed`; each with `kind: 'remote'`), then one summary event, `lime:remote-synced` (`detail.changed`: the changed keys per table; `detail.messageConversations`). `LimeStore.isRemoteSyncing()` is true while these fire, so a view can tell a repaint caused by another tab (and keep the reader's place). `lime:remote-reset` is emitted instead when the snapshot was removed. These are additions to the event list above, not changes to it.

**Not covered (known).** Two tabs creating the same direct message at the same instant can make two conversations with the same `dm_key` (the local stand-in has no uniqueness lock; a server's unique constraint fixes it). Reaction rows created before this change have no `removed_at` field and are read as active.

## The client API and sync contract (LIME-71)

How these tables travel between a server and web, iOS and Android clients
(ops, the changes feed, token auth, files, realtime, conflict rules, and the
mapping from every `LimeStore` write to an op) is written down in
[`api.md`](./api.md). It is a contract only; nothing implements it yet
(LIME-72 does). It is built on LIME-69's merge rules above and lists every
place it differs from them.

## The web app on the API: ApiAdapter, outbox and cache (LIME-74)

When a page is served by `server/dev-server.mjs`, `LimeBackend` (in `public/js/api-adapter.js`) sees `GET /api/v1/health` answer and
`LimeStore` uses the **ApiAdapter** instead of `LocalAdapter`. The python server and `file://` get no answer and stay on
`LocalAdapter` exactly as before; the console says which is active (`[Lime] storage backend: ...`). The `LimeStore` contract does not
change; only where its data lives does.

- **Three states:** `confirmed` (everything the server has told us, up to a `cursor`), the **outbox** (this device's ops the
  server has not yet confirmed through the feed) and the **view** = confirmed + outbox applied on top. Every `LimeStore` read
  is from the view, so a write shows at once and the app works offline. The view's rows are copy-on-write, so "changed" simply
  means "a different object".
- **A write is an op** (the mapping table in `api.md` section 11): applied to the view, queued, sent to `POST /ops` in order,
  retried with the same `op_id`s and backoff. A **permanent rejection** removes the op, rebuilds the view (the rollback) and shows an
  error toast. An op leaves the outbox when its own entry comes back in the feed. Mark-as-read replaces an unsent mark-as-read
  instead of stacking another. Changing an email is the one write that waits for the server (up to 10 s), because its outcome ("already
  in use") has to be shown inline.
- **Feed:** `GET /changes?since=cursor`, nudged by realtime `changed` events (a ticket from `POST /events/ticket`, then
  `EventSource`), reconnecting with backoff, plus a 30 s poll. `backfill` entries are merged by key; `alias` entries rewrite the outbox
  and move anyone looking at the dropped conversation to the kept one. `410` or a `log_start` past the cursor means "reset".
- **Stored in the browser:** tokens in `sessionStorage` (`lime-api-session`, per tab, as LIME-69 decided; `lime-demo-session` still
  holds `{userId, email}` for the session gate); `lime-device-id` in `localStorage`; the **cache** `lime-api-cache:<userId>`
  (confirmed rows + cursor) so a reload is instant; the **outbox** one key per op `lime-outbox:<userId>:<op_id>` (so two tabs never
  overwrite each other, and a signed-out device keeps unsent ops for that person); **appearance** `lime-appearance:<userId>`
  (appearance stays on the device). Signing out clears the tokens and keeps the cache and outbox; a dev-server reset clears them all.
- **Not data, but decorated on read:** presence (`profile.status` is derived from realtime: connected is `online`, everyone else
  `offline`) and, for the current person, their device's appearance.
- **Files:** `uploadAttachment` posts to `/files` and returns the file id as `path`; `getAttachmentUrl` fetches with the token and
  caches a `blob:` URL. Appearance backgrounds (`conversationId: 'appearance'`, paths starting `appearance/`) stay in IndexedDB.
- **Message order and time:** thread order is arrival (`created_at` = the server's time); a message the server has not accepted
  yet (`_pending`) is shown last. The time beside a message is the earlier of `client_ts` and `created_at`, with "Sent 10:05 ·
  delivered 10:35" when they differ by more than 5 minutes.
- **Directory:** the New message picker lists the people you chat with, and from 2 typed characters asks `GET /profiles?q=`
  (their email and phone are never in the results). `LimeStore.searchProfiles`, `lookupProfileByEmail` (share-by-email) and
  `rememberProfiles` support it. Other people's `email` is absent unless you share a conversation, and no one else's `phone` is ever present.
- **LIME-69's cross-tab `storage` merge is for `LocalAdapter` only.** On the API, tabs and devices sync through the server.

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

## Finding people and starting conversations (LIME-29)

**The New message picker** searches `LimeStore.listProfiles()` client-side
— every teacher in the local directory, including one who signed up
moments ago in the same browser (`listProfiles()` reads the same live
cache `createProfile` writes into, no extra plumbing needed). Matching is
case- and whitespace-insensitive (so "ps113" finds the seed school name
"PS 113") against `display_name`, `email` and `school`; `phone` matches
separately, comparing **digits only** on both sides, and only once the
query itself has ≥4 digits (fewer would match nearly every phone number
in a small directory, which isn't useful).

**"Both accounts see each other" is a local artifact, not a designed
feature.** Locally, every account lives in the one shared
`lime-state-v1` snapshot in this browser's own `localStorage` — Shem and
a newly-signed-up "Test Teacher" are really just two `currentUserId`
views over the exact same in-memory tables, so a DM one of them starts is
already sitting in the other's own `conversation_members` rows the moment
they next sign in, with no message-passing involved at all. **In
production this is real, not incidental:** the equivalent guarantee comes
from Supabase membership rows (a `conversation_members` insert is what
makes a conversation visible to someone) plus RLS (`is_member()`
enforcing that only actual members can read it) — the local demo's
"shared browser" behavior and production's "shared database plus RLS"
behavior land on the same visible-to-members-only result through
different mechanisms, and neither needed to be built to match the other;
they already do.

**Invites (documented only — not built).** When a picker search for a
valid email address or a ≥7-digit phone number matches no profile, the
row shows "No teacher found with `<query>`" and a disabled **Invite**
button with a "Soon" pill and an accessible "Invites coming soon" label.
The production design, for whenever this is actually built:
- An `invites` table: `id`, `inviter_id` (→ `profiles.id`), `email` or
  `phone` (exactly one set), `conversation_id` (the DM or group waiting
  for them), `status` (`pending` / `accepted` / `expired`), `created_at`.
- Sending one is a server action — a Supabase Edge Function calling the
  Supabase Auth invite API for email, or a provider like Twilio for SMS —
  never a client-side write, since it has to actually deliver something.
- Accepting one (clicking the invite link during sign-up) links the new
  `auth.users` row to the waiting `conversation_id` by inserting the
  matching `conversation_members` row, the same "onboarding linking"
  moment "The auth seam" above already describes for a returning seed
  teacher, just triggered by an invite instead of a matched email.

## Deep links and sharing (LIME-27)

**Format:** `#c=<conversationId>` on the app's own URL — built by one
helper, `conversationLink(id)`, from `location.href` with its own
existing hash stripped first (so calling it while already on a `#c=…`
link replaces that link rather than appending a second one). Locally
this is `file:///…/index.html#c=conv-004` or, over a local server,
`http://localhost:8000/public/index.html#c=conv-004`. **In production
this is the deployed app's own URL** — the `file://` form only ever
makes sense for local preview, and a link copied from a `file://` session
would be meaningless to anyone else (it points at a path on the
copier's own disk) — worth flagging to the user if this ever ships
before the app has a real deployed URL.

**The access rule**, checked both on load (a deep link) and implicitly
by every other read in this app: **a DM or group is only readable by its
own members; a community is readable by any signed-in user.** On load,
after `LimeStore.init()` (the conversation has to actually be in the
loaded store before membership can be checked at all), a `#c=<id>` hash
naming a conversation that exists, isn't soft-deleted
(`conversations.deleted_at`), and passes that rule opens it; otherwise
the default conversation opens instead and a toast reads "That chat
isn't available to you." This is the same rule the commented-out
`conversations_select_member`-style RLS policies in `schema.sql` already
draft for the real backend — the local version is just a JS-side
re-implementation of the identical check (`getMyMembership` standing in
for `is_member()`, `type === 'community'` standing in for the
community-specific `using` clause), not a new design.

**Selecting a conversation calls `history.replaceState`** (not
`pushState`) to keep the hash in sync — a reload keeps your place, but
browsing from conversation to conversation doesn't fill up browser
history with one entry per chat.

**Carrying a deep link through sign-in:** opening a deep link while
signed out hits the session gate, which redirects to `login.html`
*with the current hash appended* (`login.html?reason=…#c=<id>`, or just
`login.html#c=<id>` with no reason); `login.html`'s own redirect forwards
both the query string and the hash to `auth.html`; after a successful
sign-in there, `auth.html` redirects to `index.html?from=auth` *with the
same hash appended*, so the deep-link check above (which runs
unconditionally on every `index.html` load) opens the right conversation
the moment the session actually exists, rather than the link being lost
somewhere in the four-page round trip.

**Toasts (LIME-67):** `public/js/toast.js` (`LimeToast`), restyled in
`lime.css` on top of Seed's `toast.css`; one `#toast-container`
(`role="region"`, bottom-right, top-centre on mobile) on both `index.html`
and `auth.html`. `LimeToast.show({ title, body, tone, action, duration })`;
`LimeToast.queue(...)` carries a toast across a navigation via
`sessionStorage` (`lime-flash-toasts`). `showToast(message)` in `app.js`
remains as a title-only wrapper. When to toast and when not to: see the
rules at the top of `toast.js`. Only the icon carries the tone colour,
never lime on the card (LIME-50-fix).

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

## Deviations from the contract (LIME-33)

- **Added `createProfile({ id, email, display_name })`** to the writes —
  `auth.js`'s `signUp` is its only intended caller. `id` is a
  `crypto.randomUUID()` generated by `signUp` before this is called (so
  the credential and the profile share the same id from the start); every
  other field is `null`, shaped exactly like a seeded profile
  (`normalizeSeed` in `local-adapter.js`) so a brand-new account renders
  identically to a seed teacher everywhere else in the app (presence,
  avatar initials, the directory). Persists synchronously, not through the
  usual 100ms-debounced `scheduleSave()` — `signUp` redirects to
  `index.html` right after this resolves, and a debounced write racing a
  real page navigation can lose the write outright (a browser can drop a
  pending timer on unload). Emits `lime:profile-changed`, same as
  `updateProfile`/`setProfileEmail`.

## Deviations from the contract (LIME-29)

- **Added `listProfiles()`** to the reads — a plain `[...profiles.values()]`,
  same shape as `getMessage(id)`'s own LIME-24b justification. The New
  message picker's own directory search needs every profile to filter
  client-side (name, email, school, phone); excluding the current user and
  sorting are the picker's own concern, not this read's.
- **Added `LimeStore.flush()`** — not really a new capability so much as a
  real bug's fix exposed as one. `scheduleSave()`'s 100ms debounce can race
  a real page navigation (confirmed live, in both real Firefox and real
  Chrome: create a DM via the picker, send a message, sign out quickly —
  the conversation and message were both silently gone on the next
  sign-in, because `signOut()`'s own `window.location.href = 'login.html'`
  navigated away before the pending debounced save ever fired). `flush()`
  immediately runs any pending save and clears the timer; a no-op when
  nothing's pending. `LimeAuth.signOut()` now calls it unconditionally
  before navigating — the general form of the exact race LIME-33's own
  `createProfile` fix (a synchronous `persistNow()` call) addressed for
  one specific write. Every other debounced write (`sendMessage`,
  `createConversation`, `toggleReaction`, etc.) was still exposed to this
  race until this fix; `signOut()` is the one place in the app that
  navigates away on demand, so flushing there covers all of them.

**`flush()` is local-only, no Supabase equivalent** — it exists purely
because `localStorage` writes are debounced and a real navigation can
race them. That problem doesn't exist once Supabase's own persistence
layer replaces `LocalAdapter` (writes go straight to the database, not
through a client-side debounce), so `flush()` should be removed, not
reimplemented, when this checklist is used for real — and `signOut()`'s
own call to it drops out along with it.

**LIME-27 added a `pagehide` listener (`app.js`) that also calls
`LimeStore.flush()`** — the same debounce race, but for "closed the tab
or navigated away some other way," which `signOut()`'s own call can't
reach since no sign-out happens on a plain tab close. Also local-only,
also dropped alongside `flush()` itself on the switch checklist.

## Deviations from the contract (LIME-27)

- **Added `addMembers(conversationId, profileIds)`** to the writes — the
  Share popover's own "Add people by email," for groups only. Owner-only
  (`can('addMembers', conversation)`, which also requires
  `conversation.type === 'group'` — a DM's stored `role: 'owner'` on
  whoever created it is never treated as real ownership anywhere else in
  this app, per LIME-34's own decision, and the popover's UI never shows
  this field for a DM in the first place). A profile already a member is
  silently skipped, not an error, since submitting the same email twice
  should be a no-op. **Maps directly onto the already-drafted
  `conversation_members_insert_creator` RLS policy in `schema.sql`**
  (commented out, not yet enabled) — its third `or is_owner(conversation_id)`
  branch is exactly this write; no new policy is needed when that
  checklist item gets enabled for real, only this function's body
  swapping from a local array push to a real `insert`.
- **The newly added member's own visibility on sign-in is the same local
  artifact LIME-29's own doc note already describes** — one shared
  `lime-state-v1` snapshot, no message-passing involved. **No system
  message ("Shem added Valene") was added** — the brief's own instruction
  was explicit: only build one if a system-message `type` already exists,
  and `messages.type` is constrained to `('text', 'voice', 'location',
  'image', 'file')` in `schema.sql` today (confirmed by reading the
  column definition directly, not assumed) — no `'system'` value. Noted
  here as a real, deliberately-skipped gap rather than quietly worked
  around with, say, a `type: 'text'` message that *looks* like a system
  line; a future brief adding a real system-message type should wire this
  in then.
