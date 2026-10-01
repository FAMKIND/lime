# Lime client API and sync contract (LIME-71)

Draft contract, written before any server exists (same pattern as
[`data-model.md`](./data-model.md) in LIME-24a: contract first, review, then
build). One API serves the web app now, iOS and Android apps next, and a
Bluetooth relay later. The implementation (a local dev server and a web
`ApiAdapter`) is LIME-72, not this document.

This is **a contract, not code**. Nothing here is built. Where this document
makes a choice the earlier docs did not, it says so under **Open points**
(the end), so a person can overrule it before LIME-72 starts.

## Terms

- **Op** (operation): one small, self-contained change a user made, such as
  "send this message". Every write in the app is an op.
- **Outbox**: the list of ops a client has made but the server has not yet
  accepted. It is kept on the device.
- **Op log**: the server's ordered, append-only list of accepted ops.
- **`seq`**: a whole number the server gives each accepted op. It only goes
  up. It is the one true order of events.
- **Cursor**: the last `seq` a client has seen. "Everything since my cursor"
  is how a client catches up.
- **Feed** (changes feed): the ops a given user is allowed to see, in `seq`
  order, from a cursor onward.
- **Device**: one install of a client (a browser tab's storage, a phone). It
  has a `device_id` (a UUID the client makes once and keeps).
- **Actor**: the user an op is performed as.
- **Tombstone**: a row that is marked removed (`removed_at` / `deleted_at`)
  instead of being deleted, so a later merge cannot bring it back.
- **RLS** (row-level security): the database rules, drafted in `schema.sql`,
  that decide which rows a signed-in user may read or change.
- **Local store**: the client's own copy of the data (today `LimeStore` plus
  `LocalAdapter`). Reads come from it.

## 1. Principles

1. **One versioned HTTP + JSON API, `/api/v1`, for every client.** No client
   gets a private endpoint. Breaking changes mean `/api/v2`; additions
   (new fields, new op types) do not. A client ignores fields and op types
   it does not know.
2. **The server is the authority for ordering.** `seq` decides what came
   first, who wins a conflict, and the order messages appear in. A client's
   clock is never trusted for ordering.
3. **Clients are local-first.** A client has a local store and an outbox.
   A write updates the local store at once (so the UI is instant and works
   offline), is queued as an op, and is sent when there is a connection.
4. **Every write is an op.** There is no "update this row" endpoint. This is
   what makes offline use, retries and relaying possible.
5. **Reads come from the local store.** The local store is kept current by
   the feed. The UI never waits on the network to read. (This is the shape
   `LimeStore` already has: synchronous reads from an in-memory cache,
   async writes.)
6. **Ops are idempotent.** Sending the same op twice has the same effect as
   sending it once. This is what makes "retry until it works" safe.
7. **All ids are made by the client.** Message, conversation, attachment and
   op ids are UUIDs the client generates (the local store already does:
   `crypto.randomUUID()`). A client can therefore create things offline and
   refer to them in later ops before the server has seen them.
8. **Transport-neutral.** The data formats here do not depend on being in a
   browser. Realtime (section 4, Realtime) is defined as messages, with Server-Sent
   Events as the web transport.

## 2. The op envelope

Every op, in a request or in the feed, has this shape:

```json
{
  "op_id": "0192f8a4-7c1e-7b3a-9d52-3f6a1c0e8b21",
  "type": "message.send",
  "actor_id": "teacher-002",
  "device_id": "5b0f4e0e-1d0b-4f55-9a43-0c6b2f7e91aa",
  "client_ts": "2026-10-01T16:09:14.449Z",
  "payload": { }
}
```

| Field | Set by | Meaning |
|---|---|---|
| `op_id` | client | A UUIDv7 (time-ordered UUID). The **idempotency key**: the server remembers every `op_id` it has accepted, and replaying one is a no-op that returns the original result. |
| `type` | client | One of the catalogue in section 3. |
| `actor_id` | client | The profile id acting. The server **checks it equals the token's user**; a mismatch is rejected `forbidden`. It is in the envelope (not only the token) so a relayed op stays self-describing. |
| `device_id` | client | The device that made it: a **UUID, optionally with a short prefix** (`web-<uuid>`). The server refuses anything else with `bad_request` (and an op with a bad one `invalid_op`), because two devices sharing an id would share one session and the refresh-token reuse check would sign one out. A client makes one per install and must never fall back to a constant. Ids that need randomness (`device_id`, message and conversation ids) must not depend on `crypto.randomUUID`, which does not exist on plain `http://192.168.x.x` addresses. |
| `client_ts` | client | When the client made it. **Informational only** (shown as "sent from a device clock", used for debugging). Never used for ordering or conflicts. |
| `payload` | client | The type's own fields (section 3). |
| `seq` | **server** | The op's place in the log. Present in the feed and in `/ops` results. |
| `server_ts` | **server** | When the server accepted it. |

A **batch** is a list of envelopes sent together (section 4, `POST /ops`).
The server applies a batch **in order**, each op judged on its own: one
rejected op does not stop the ones after it.

## 3. The op catalogue

One op per write function in `public/js/store.js`. "Payload" lists the
fields; every id is client-made. "May perform" mirrors `LimeStore.can` /
`canReason` and the RLS draft in `schema.sql`.

### Messages

**`message.send`** (store: `sendMessage`)
- Payload: `message_id`, `conversation_id`, `content` (text or null),
  `type` (`'text'`; `'image'`/`'file'` are legacy and never sent),
  `metadata` (object or null), `reply_to` (a `message_id` or null),
  `attachments`: a list of `{ attachment_id, file_id, name, size, mime,
  width, height, duration_seconds, position }`, each `file_id` already
  uploaded through `POST /files`.
- May perform: a **member** of `conversation_id`, with `actor_id` as the
  sender (`schema.sql`: `messages_insert_member`). `reply_to` must be a
  message in the **same** conversation. A message must have `content` or at
  least one attachment. Attachments are part of the same op, so a message
  with an album never appears half-sent (see Open points 1).
- Effect: the server stores the message (`sender_id = actor_id`) with
  **both times**: `client_ts` (when it was **written**, from the envelope)
  and `created_at` = `server_ts` (when it was **delivered**), plus its
  attachment rows. The time a client **displays** is `min(client_ts,
  created_at)`, so a wrong device clock can never show a future time; and
  when the two differ by **more than 5 minutes** it also shows the delivery
  time ("Sent 10:05 · delivered 10:35"; exact copy is the client's). Thread
  order is `seq` (arrival), never the displayed time (section 6, rule 8). If a
  member had "deleted for me" (`cleared_at`), this message makes the
  conversation reappear for them, with only what is after `cleared_at`, as
  today.

### Reactions

**`reaction.toggle`** (store: `toggleReaction`)
- Payload: `message_id`, `emoji`, **`present`** (true to react, false to
  remove). The client works out `present` from its own local state, rather
  than sending a bare "flip", because a flip replayed or applied twice would
  undo itself. With `present`, the op is idempotent and two devices of one
  user converge.
- May perform: a member of the message's conversation, on their **own**
  reaction only (`message_reactions_insert_self`, `_delete_self`).
- Effect: the reaction row `(message_id, actor_id, emoji)` is created or
  has `removed_at` set or cleared (a tombstone; section 6).

### Conversations

**`conversation.create`** (store: `createConversation`)
- Payload: `conversation_id`, `type` (`'direct'` or `'group'`; `'community'`
  is not creatable until communities go live), `name` (groups; may be
  null), `description`, `member_ids` (other people; the actor is added as
  owner automatically).
- May perform: any signed-in user, naming themselves as creator
  (`conversations_insert_creator`). A `direct` conversation must have
  exactly one other member and no name.
- Effect: creates the conversation, the owner membership for the actor and
  a `member` membership for each other person. For a `direct` conversation
  the server computes `dm_key` (the two ids, sorted, joined with `:`) and
  **deduplicates** (section 6, rule 3).

**`conversation.rename`** (store: `renameConversation`)
- Payload: `conversation_id`, `name`.
- May perform: the **owner** of a **group**. A direct conversation cannot
  be renamed (its title is the other person). (`can('rename')`;
  `conversations_update_owner`.)

**`conversation.delete`** (store: `deleteConversation`)
- Payload: `conversation_id`.
- May perform: the **owner** of a **group**. Sets `deleted_at` (a
  tombstone). It is delete-for-everyone and cannot be undone through the
  API. A **direct** conversation is never deleted this way: its "delete" is
  `conversation.deleteForMe` below (see the difference noted in section 6,
  table row 11).

**`conversation.deleteForMe`** (store: `deleteForMe`)
- Payload: `conversation_id`.
- May perform: any member, **for themselves only**. Sets the actor's own
  membership `cleared_at` to the op's `server_ts`. Messages at or before
  that point are hidden from the actor's reads; nobody else is affected.
  (Per-user op.)

### Memberships

**`membership.add`** (store: `addMembers`)
- Payload: `conversation_id`, `user_ids` (a list).
- May perform: the **owner** of a **group** (`can('addMembers')`). People
  who are already members are skipped silently, not an error.
- Effect: creates `member` rows. The server also gives each **new** member
  the conversation's history (section 7, "backfill").

**`membership.setStarred`** (store: `setStarred`)
- Payload: `conversation_id`, `starred` (boolean).
- May perform: a member, **their own** membership only
  (`conversation_members_update_self`). Per-user op.

**`membership.setArchived`** (store: `setArchived`)
- Payload: `conversation_id`, `archived` (boolean). The server sets
  `archived_at` to `server_ts` or null.
- May perform: a member, their own membership only. Per-user op.

**`membership.markRead`** (store: `markRead`)
- Payload: `conversation_id`, `read_through_seq` (optional; the newest
  message `seq` the client had on screen). The server sets `last_read_at`
  to `server_ts` (or the time of that message if given and later than the
  current value; `last_read_at` never moves backwards).
- May perform: a member, their own membership only. Per-user op.

### Profiles

**`profile.update`** (store: `updateProfile`)
- Payload: a `patch` containing **only the fields being changed**, from the
  allowed set `display_name`, `pronouns`, `role`, `school`, `grade_levels`,
  `subjects`, `bio`, `timezone`, `phone`, `avatar_url` (`avatar_url` holds a
  `file_id`; photos upload through `POST /files` first). `display_name`,
  if present, must not be blank.
- May perform: the user, **their own** profile only
  (`profiles_update_self`). Email is not in this list (next op).

**`profile.setEmail`** (store: `setProfileEmail`, called by
`LimeAuth.changeEmail`)
- Payload: `email`.
- May perform: the user, their own profile only. The email must be valid
  and unique. The server also renames the sign-in identity (today
  `changeEmail` renames the stored credential key); on the server this is
  one transaction with the profile change.

### Not ops

- **Create profile** (store: `createProfile`) is not an op: it happens as
  part of `POST /auth/signup` (section 4), because an actor must exist
  before it can send ops.
- **Appearance** (store: `setAppearance`: theme, canvas, pattern). **Stays
  device-local and is not synced** in this contract. `schema.sql` has a
  `user_settings` table that would hold it if the user decides appearance
  should follow them between devices; the op would be `appearance.set` with
  a `patch`, per-user. Decision flagged in Open points 3.
- **Attachment upload / delete / URL** (`uploadAttachment`,
  `deleteAttachment`, `getAttachmentUrl`) are file operations, not ops:
  `POST /files` and `GET /files/:id`. There is no `attachment.attach` op;
  attachments are recorded by `message.send` (Open points 1).
- **Link previews** (`getLinkPreview`) are a read, not a write.
- **Reads** (`list*`, `get*`, `can`, `canReason`) are local.

## 4. Endpoints

All paths are under `/api/v1`. Bodies are JSON unless stated. Every
endpoint except `/auth/signup`, `/auth/signin`, `/auth/refresh` and
`/health` needs `Authorization: Bearer <access_token>`.

### Auth

`POST /auth/signup`
- Body: `{ email, password, display_name, device_id }`.
- The server validates (valid email, password at least 8 characters, name
  not blank, email not taken), creates the profile (`id` is server-made at
  signup, the one id a client does not make), and signs the device in.
- Returns `{ user: <profile>, access_token, expires_in, refresh_token,
  seq }` (`seq` is the log position at that moment).

`POST /auth/signin`
- Body: `{ email, password, device_id }`. Returns the same shape as signup.
- Wrong email or password gives the same error either way
  (`invalid_credentials`).

`POST /auth/refresh`
- Body: `{ refresh_token, device_id }`. Returns a new `access_token` **and a
  new `refresh_token`** (rotation: the old refresh token stops working).
  A refresh token used twice revokes that device's session.

`POST /auth/signout`
- Revokes the calling device's refresh token. Returns `204`.

`POST /auth/password` (LIME-74)
- Body: `{ current_password, new_password }`. Verifies the current password, stores a new salted hash, and **revokes every
  other device's refresh token** (other devices are signed out at once); the calling device stays signed in. Returns
  `{ ok: true }`.
- `403 forbidden` ("Current password is incorrect."), `400 bad_request` for a new password under 8 characters or equal to
  the current one. A seed teacher who still uses the shared demo password gets their own credential from this point.
- Attempts count towards the same per-email rate limit as sign-in.

`POST /auth/lookup` (LIME-74, **development phase only**)
- Body: `{ email }`. Returns `{ exists: boolean }`. The email-first sign-in page uses it to choose between "sign in" and
  "create account". It tells anyone whether an email has an account (rate limited to 60 a minute per address), which is the
  account-enumeration trade-off the otherwise generic sign-in errors avoid. **A production deployment should remove it**
  (for example one combined sign-in/sign-up form, or an emailed link) and the web app's flow with it.

### Ops

`POST /ops`
- Body: `{ device_id, ops: [ <envelope>, ... ] }`, at most 100 ops.
- Idempotent per op (section 2). Returns `{ results: [ ... ] }`, one entry
  per op, in order:
  - `{ op_id, status: 'applied', seq, server_ts }`
  - `{ op_id, status: 'duplicate', seq, server_ts }` (already had it; same
    result as the first time)
  - `{ op_id, status: 'rejected', error: { code, message } }`
- For a `conversation.create` that was deduplicated into an existing
  conversation (section 6, rule 3) the result also carries
  `canonical_conversation_id`.
- The request as a whole fails (`400`/`401`/`413`/`429`) only when the
  request itself is bad; a bad op is a per-op `rejected`.

### Changes (the feed)

`GET /changes?since=<seq>&limit=<n>`
- Returns `{ changes: [ ... ], next, has_more }`.
- Each entry is `{ seq, server_ts, op: <envelope> }` for an op the caller is
  allowed to see (section 8), **including the caller's own ops** (so a
  second device of the same user sees them), or a **backfill** entry (section
  7). Entries are in `seq` order.
- `next` is the cursor to send next time. It can be **larger than the last
  `seq` returned**: the feed is filtered per user, so there are gaps, and
  `next` skips past the ones the caller may not see. `limit` defaults to 200,
  at most 1000.
- If `since` is older than the server keeps (or the server was reset), it
  returns `410 cursor_expired` and the client must call `/snapshot` and
  start over.

`GET /snapshot`
- A cold-start bootstrap, scoped to the caller: the caller's profile and
  per-user rows, every conversation they are a member of with its members,
  messages, reactions and attachment rows, and the public profiles of
  everyone they share a conversation with (section 8).
- Returns `{ seq, profile, profiles, conversations, conversation_members,
  messages, message_reactions, message_attachments }` (the same six tables as
  `docs/data-model.md`) and the `seq` it is correct as of. A client then
  continues with `GET /changes?since=<that seq>`.
- Large histories are paged: `GET /snapshot?cursor=<opaque>` continues, and
  the final page carries `seq`. (A client must not start applying
  `/changes` until the last page.)

### Files

`POST /files` (multipart/form-data, one `file` field)
- Returns `{ file_id, size, mime, name }`. Limit **10 MB** per file (the
  app's existing limit; `413 file_too_large` above it).
- A file belongs to its uploader until a `message.send` or `profile.update`
  refers to it. An unreferenced file is deleted after 24 hours.

`GET /files/:id`
- An **authorised download** (section 8, "files"). Supports `Range` (audio
  and video seek) and returns the right `Content-Type`. Never public.

### Realtime

`GET /events`
- A stream of small messages. The message format is **transport-neutral**:
  `{ "type": "changed", "seq": 1234 }` means "the log has reached 1234;
  fetch `/changes`". Other types are ignored if unknown. The message carries
  **no data**, so it cannot leak anything; the client fetches through
  `/changes`, which does the permission filtering.
- **Web transport: Server-Sent Events** (`text/event-stream`), with each
  message as an event `data:`, a periodic comment as a keep-alive, and
  `Last-Event-ID` honoured (the id is the `seq`).
- A browser `EventSource` cannot send an `Authorization` header, so a web
  client first calls `POST /events/ticket` (Bearer-authenticated) and gets a
  single-use, 60-second `{ ticket }`, then opens `GET /events?ticket=...`.
  (This is the one endpoint beyond the original list; see Open points 4.)
- **Native transport:** an iOS or Android client may use a WebSocket instead
  and carry the same messages. Defining that transport is part of the mobile
  work, not this contract.
- Realtime is an optimisation: a client that is not connected still
  converges by polling `/changes`.

#### Presence (active, busy, away)

Presence is **ephemeral**, so it is **not an op** and is never in the log or
the feed. It travels over realtime only, as `{ "type": "presence",
"user_id": "...", "status": "active" | "busy" | "away" }`.
- **`away` is inferred**: a user with no open realtime connection is `away`;
  with at least one, `active` (or `busy`, once a client can set it).
- A client receives `presence` messages for **people it shares a
  conversation with** (never for strangers), when someone's state changes
  and, right after connecting, once for each such person who is currently
  not `away`.
- **Setting `busy` is not defined yet** (there is no client control for it
  today); the status field is reserved. The seed profiles' stored `status`
  values are display data only and are not presence.
- The dev server (LIME-73) implements the minimal version: connected is
  `active`, disconnected is `away`. People who become chat-mates **after** both connected (a new chat, someone added) are
  sent each other's presence at that moment (LIME-74), not only at connection time.

### Directory

`GET /profiles?q=<text>`
- Finds people, for the new-message picker. `q` must be at least **2
  characters** (otherwise `400 bad_request`).
- Matches: **partial, case-insensitive text** in `display_name` and `school`;
  **exact** (case-insensitive) `email`; **exact digits-only** `phone` (the
  query is stripped to digits; it must be at least 7 digits to count as a
  phone). Email and phone are **only** ever matched exactly, so the
  directory cannot be used to browse or guess them.
- Returns `{ profiles: [ ... ] }`, at most **50**, excluding the caller. Each
  result has only the **public fields**: `id`, `display_name`, `school`,
  `role`, `pronouns`, `grade_levels`, `subjects`, `bio`, `timezone`,
  `avatar_url`. **It never reveals the email or phone** of a match, even
  when that is what matched.

### Link previews

`GET /link-preview?url=<absolute http(s) URL>`
- A read. The server unfurls the page and returns `{ url, minimal, title,
  description, site_name, image_url }`. Never fails for a well-formed URL: an
  unreachable or unknown page returns the minimal card (`minimal: true`,
  the domain as `title`, the rest null). A malformed URL is `400`.
- The dev server returns LIME-44's fixtures for a few known URLs and the
  minimal card for everything else, and makes **no outbound requests**. A real
  server must fetch with timeouts, a size cap, and **must refuse private
  addresses** (an unfurler is a classic request-forgery hole).

### Health

`GET /health` returns `{ ok: true, api: 'v1', seq, log_start }` with no auth. `log_start` is the oldest `seq` the server can still serve a feed from; a client whose cursor is below it knows the server was reset (dev server) or compacted, and must start over. The web app also uses `GET /health` on the same origin to decide whether to use the API at all.

### Dev server only (outside the contract)

A development server may offer `POST /dev/reset` (clears everything, ends
sessions; connected clients then get `410 cursor_expired`). It is **not** part
of this API and must not exist in production. It corresponds to the app's
"Reset demo data".

## 5. Errors

Every failure is `{ "error": { "code": "...", "message": "..." } }`, with
`message` fit to show a person. For a rejected op in a batch, the same object
appears under `error` in that op's result.

| HTTP | `code` | Meaning |
|---|---|---|
| 400 | `bad_request` | Malformed body or a missing/invalid field (`message` names it). |
| 400 | `invalid_op` | An op has an unknown `type` or a bad payload. (An unknown type from a **newer** client is `unsupported_op` instead, so a client can tell.) |
| 401 | `unauthenticated` | No token, or an expired or invalid one. The client refreshes and retries. |
| 401 | `invalid_credentials` | Wrong email or password. |
| 403 | `forbidden` | Signed in but not allowed (not a member, not the owner, `actor_id` mismatch). Permanent: do not retry. |
| 404 | `not_found` | The thing the op refers to does not exist (or the caller may not know it exists; the two look the same). |
| 409 | `conflict` | A uniqueness rule failed (for example the email is taken). |
| 410 | `cursor_expired` | The `since` cursor is no longer valid; re-snapshot. |
| 413 | `file_too_large` | Over 10 MB. |
| 422 | `unsupported_op` | See above. |
| 429 | `rate_limited` | Slow down; `Retry-After` says how long. |
| 5xx | `server_error` | Transient: retry with the same `op_id`s (safe, section 1.6). |

**What a client does with a per-op `rejected`:** a **permanent** code
(`forbidden`, `invalid_op`, `not_found`, `conflict`, `unsupported_op`)
means drop the op from the outbox and tell the person (and roll back the
optimistic change in the local store). A **transient** code keeps it in the
outbox for a retry. Ops are sent **in outbox order**; if an op is rejected
permanently, later ops that depended on it (for example a message into a
conversation that was never created) will be rejected `not_found`, and are
dropped the same way.

## 6. Conflict rules

Two devices can change things at the same time, or a device can be offline
for a long while. These rules decide the result. **They must give the same
answers as the local merge LIME-69 built (commit `3bb437b`, `store.js`,
documented in `docs/data-model.md` "Two tabs, one browser").** The two
differ only where a server can do better than a browser; every difference is
listed in the table at the end.

1. **Order is `seq`.** When two ops conflict, the one with the higher `seq`
   (accepted later by the server) wins. No ties exist, because `seq` is
   unique. (LIME-69 uses `updated_at` and gives ties to the saving tab.)
2. **Append-only and union.** Messages, attachment rows and reactions are
   never overwritten or removed by an op: new ones are added, and a set of
   them from several devices is the union.
3. **DMs are deduplicated by `dm_key`.** If two clients create a direct
   conversation between the same two people at once, they converge on **one**
   conversation: the server keeps the **first** (lowest `seq`) and returns
   `canonical_conversation_id` for the second. The server remembers an alias
   (`loser id -> canonical id`), so later ops from the second client that
   name its own id (a `message.send` made offline, say) are **applied to the
   canonical conversation**, and the second client replaces its local id
   when it sees the alias in the feed (an `alias` entry; section 7). This is
   the rule LIME-69's local merge cannot enforce (it can create two
   conversations with one `dm_key`; `docs/data-model.md` lists it as "not
   covered") and is backed by `schema.sql`'s unique index on `dm_key`.
4. **Deletes are tombstones, and a tombstone is never undone by a merge.**
   - A reaction removed has `removed_at` set (and `updated_at`); reacting
     again with the same `(message, user, emoji)` clears it and sets a new
     `updated_at`. This matches LIME-69's reaction rows exactly
     (`removed_at`, `updated_at`).
   - A group deleted by its owner has `deleted_at` set; nothing clears it.
   - **Messages are never deleted** (the app has no delete-message). The
     `messages_delete_self` policy in `schema.sql` is not used; if
     delete-message is ever added it must be a tombstone (`deleted_at`), not
     a real delete.
5. **Scalar fields are last-writer-wins by `seq`, field by field.** Because an
   op carries **only the fields it changes** (`profile.update` sends a patch;
   `conversation.rename` sends `name`), two ops that change *different*
   fields of one row both keep their change, and two ops that change the
   *same* field resolve to the later `seq`. This is LIME-69's per-field merge
   (only-mine stays mine, only-theirs is taken, both changed means newer
   wins), with `seq` as the clock.
6. **Membership rows are per user.** A membership's `starred`,
   `archived_at`, `cleared_at` and `last_read_at` are written only by that
   user's own ops, so they never conflict between people (only between one
   person's own devices, resolved by rule 5). Server sets the timestamps
   (`server_ts`); `membership` rows carry `updated_at`, as LIME-69 added.
   `last_read_at` never moves backwards.
7. **Membership is additive.** There is no leave-group or remove-member op
   in the app. `membership.add` of an existing member is a no-op.
8. **Ordering and time of messages.** Thread order is **`seq`** (arrival). A
   message a client has made but the server has not yet accepted is shown
   **last**, in outbox order, until it is accepted and takes its `seq` place.
   The **displayed time** is `min(client_ts, created_at)` (the written time,
   never in the future), with the delivery time added when more than 5
   minutes later. Both times are stored (`client_ts`, `created_at`).
   Reason: in offline and emergency use, *when it was written* is the
   important fact, but a message must still land where the conversation
   actually was when it arrived.

### Differences from LIME-69's local merge (all of them)

| # | LIME-69 local merge | This contract | Why |
|---|---|---|---|
| 1 | Newer `updated_at` wins; ties go to the saving tab | Higher `seq` wins; no ties | A server has one clock; browsers have many. |
| 2 | Row-level merge of whole rows against a base | Ops carry only changed fields; no base needed | Ops are the unit of change; avoids merge-by-comparison. |
| 3 | Two DMs for one pair can exist | Exactly one, by `dm_key`; alias for the loser | The server can enforce uniqueness (`schema.sql` index). |
| 4 | Stale-read guards (1.5 s recent-base window, "older row is stale") | None needed | A server read is never stale relative to its own log. |
| 5 | Reaction toggle flips the stored row | `reaction.toggle` carries explicit `present` | A flip replayed twice undoes itself; `present` is idempotent. |
| 6 | Union never drops rows; a stale tab writes missing rows back | Server never loses rows; clients resend un-acked ops from the outbox | Same goal (never lose a write), different mechanism. |
| 7 | `created_at` = the sending tab's clock | `created_at` = `server_ts`, and the written time is kept as `client_ts` (displayed time = the earlier of the two) | The server is the authority for ordering; the written time is still shown. |
| 8 | Another tab's Reset sends tabs to sign-in | `410 cursor_expired` forces a re-snapshot (dev server only) | There is no reset in production. |
| 9 | Sessions per tab (`sessionStorage`) | Tokens per device; the web client keeps them in `sessionStorage` (so still per tab) | Matches LIME-69 on web; native uses secure storage. |
| 10 | Scroll/draft/menu handling | Not a data rule; client concern | |
| 11 | `can('delete')` is true for a DM (the UI maps it to `deleteForMe`); the RLS draft lets a DM's creator (`is_owner`) update `deleted_at` | `conversation.delete` is **groups only**; a DM only gets `deleteForMe` | A DM has no real owner (LIME-34); deleting it for the other person is never wanted. The RLS draft is looser than the app and should be tightened when it is enabled. |

There are no other differences. A client that follows rules 1 to 8 reaches the
same state LIME-69's merge reaches for any case the local merge handles.

## 7. How a client stays current

- **Cold start** (no local data, or `410 cursor_expired`): `GET /snapshot`
  (paged), store the tables and `seq`, then follow the feed.
- **Catching up:** `GET /changes?since=<cursor>` until `has_more` is false.
  Apply entries in `seq` order, then save `next` as the cursor.
- **Applying an entry:** run the op against the local store the same way the
  author's device did. An op the client made itself (same `op_id` as one in
  its outbox) just confirms it: remove it from the outbox and take its `seq`
  and `server_ts`. This is what keeps optimistic local changes from being
  applied twice.
- **Partial backfill entries (LIME-74).** An op does not carry the profiles of the people it mentions, so the server also
  sends **`backfill` entries with only some tables**: every member of a **new conversation** gets `conversation`,
  `conversation_members` and `profiles` (no messages yet); when people are **added** to a conversation, each *existing* member
  gets just the new people's `conversation_members` rows and `profiles`. A client merges whichever keys are present, by key
  (`mergeBackfill`). Without this a member could not show who else was in the conversation.
- **Backfill entries.** When someone is added to a conversation they have
  never seen, the ops that built it are before their cursor and are not in
  their feed. So at the moment `membership.add` takes effect the server puts
  one **`conversation.backfill`** entry into that new member's feed:
  `{ seq, server_ts, backfill: { conversation, conversation_members,
  messages, message_reactions, message_attachments, profiles } }`, the
  conversation's current rows (honouring nothing but membership; the new
  member sees the full history, matching `messages_select_member`).
- **Alias entries.** `{ seq, alias: { from: <id>, to: <id> } }` tells a
  client that a conversation id it made was deduplicated (section 6.3). The
  client rewrites local references to `from`.
- **Realtime:** keep a `/events` connection open. On `changed`, fetch
  `/changes`. On a dropped connection, reconnect with `Last-Event-ID` and
  fetch anyway. Polling `/changes` every 30 seconds is the fallback.
- **Sending:** the outbox is flushed to `POST /ops` whenever there is
  anything in it and a connection (after each write, on reconnect, on app
  foreground), in order, a batch at a time, retrying transient failures with
  the **same** `op_id`s and backoff.

## 8. Auth model, visibility, files

### Auth

- **Bearer tokens.** A short-lived **access token** (about 15 minutes) goes in
  `Authorization: Bearer ...`; a long-lived **refresh token** (30 days,
  rotating, section 4) gets new ones. Each is bound to a `device_id`: signing
  out or being revoked on one device does not sign out the others.
- **Passwords are verified on the server** (PBKDF2-SHA256 with a per-user
  random salt and at least 600,000 iterations, or a stronger algorithm; a
  production backend uses its own auth). The client never stores or sends a
  password after signin. (Today `auth.js` verifies in the browser with
  100,000 iterations because there is no server; that is a local-demo
  stand-in only.)
- **Where tokens live.** **Web:** `sessionStorage` (per tab, matching LIME-69;
  a new tab is signed out until the person signs in; the refresh token is
  not kept longer than the tab). **iOS:** the Keychain. **Android:** the
  Keystore (with encrypted preferences). This is a note, not a mobile design.
- **Web sign-in persistence (note).** Per-tab `sessionStorage` is right for
  the development phase (two people testing in two tabs of one window).
  Production web will want an **optional persistent sign-in** ("keep me
  signed in": the refresh token in a long-lived, secure, same-site cookie or
  `localStorage`). That is a later decision, and nothing in the API prevents
  it.
- **Rate limits** apply to `/auth/*` per email and per address.

### Visibility (what a user receives through `/changes` and `/snapshot`)

Matches the RLS draft in `schema.sql`:

- Ops and rows of **conversations the user is a member of**: the
  conversation, its memberships (who is in it), its messages, reactions and
  attachment rows (`conversations_select_member`,
  `conversation_members_select_member`, `messages_select_member`, and the
  reaction and attachment select policies). Communities are readable by any
  signed-in user in the draft; they are not live yet, so they are **not**
  covered here (add with LIME-28).
- The user's **own** profile and **own per-user rows** (memberships).
  Other members' per-user fields (`starred`, `archived_at`, `cleared_at`,
  `last_read_at`) are **not** sent to someone else: a feed entry for
  `membership.setStarred` / `setArchived` / `deleteForMe` / `markRead` goes
  only to its actor. (Today's local snapshot holds everyone's; a server must
  not.) Read receipts ("Seen by Jean") would need `last_read_at` of others;
  **deferred**, since the LIME-43 receipts were removed from the app. If they
  return, they need an explicit decision that members can see each other's
  `last_read_at`.
- **Other people's profiles (decided by the user, 2026-10-01):**
  - **Email** is visible only to people who **share a conversation** with
    you (and to you). A user receives the profiles of **people they share a
    conversation with** in `/snapshot` and the feed, with `email`.
  - **Phone is never displayed to others**: the server never sends a user's
    `phone` to anyone but that user (not in the snapshot, the feed, a
    backfill, or the directory). A later opt-in "show my phone" setting would
    change this; there is none now.
  - **Finding people** goes through `GET /profiles?q=` (section 4,
    Directory): partial match on name and school, **exact** match only on
    email or phone, and results never contain the email or phone.
  - Everyone else (no shared conversation) is visible only as a directory
    result, with the public fields. This replaces the RLS draft's
    `profiles_select_authenticated` (`using (true)`), which exposes every
    column of every profile to any signed-in user; tighten it to match when it
    is enabled.
  - The feed carries a `profile.update` to the person themselves and to
    people they share a conversation with **at that moment**, with `phone`
    removed from the patch for everyone but the owner (a patch that changes
    only `phone` is not delivered to others). `profile.setEmail` goes to the
    same audience.

### Files

**Images cannot send a bearer header** (`<img src>`), so the web app fetches `GET /files/:id` with the token, turns the bytes
into a `blob:` URL, and caches it for the session (`getAttachmentUrl`). **Production alternative:** short-lived signed URLs
(`GET /files/:id/url` returning a URL valid for a few minutes), which also let the browser cache and stream media and let a
CDN serve it; not built.

`GET /files/:id` is allowed to: the **uploader**; any **member** of the
conversation of a message whose attachment refers to the file; and, for a
file used as an `avatar_url`, **any signed-in user** (profile photos are
public inside the app). Appearance patterns are device-local and never
uploaded. `attachments.path` in today's rows becomes the `file_id`; the
client keeps treating it as opaque (`LimeStore.getAttachmentUrl` is unchanged
for callers).

## 9. Offline and mesh (forward-looking; no commitment)

Nothing in this section is a design. It records what the contract already
makes possible and what is open, so the later planning pass starts from the
right place. (The product reason is the planned offline Bluetooth messaging
on the future iOS and Android apps.)

- **Offline:** a client keeps working with no connection (reads are local,
  writes go to the outbox, ordering becomes final when synced). Nothing in
  the API requires a connection except sending and fetching.
- **Ordering after sync:** local ordering is provisional (outbox order) and
  becomes `seq` order once accepted; a client re-sorts and must tolerate a
  message it showed last moving earlier or later.
- **Bluetooth relay:** the unit a device would carry for another is an
  **op** (a self-contained, idempotent envelope with a client-made id). A
  relayed op is applied locally and enters the real outbox of whoever
  eventually has a connection; the server de-duplicates by `op_id`.
- **Open questions** (a future planning pass, not decided here):
  1. **Op signing**: how does the server (and a peer) know an op relayed by
     a stranger's phone really came from `actor_id`? Likely a per-device key
     signing each envelope.
  2. **End-to-end encryption**: should `payload` be encrypted for the
     conversation's members? It conflicts with server-side validation
     (membership, ownership) and with search; relayed ops may need it.
  3. **Dedup by `op_id` across relays**: how long the server remembers
     `op_id`s.
  4. **Clock and ordering in a mesh**: messages exchanged phone-to-phone
     before reaching the server have no `seq` yet.
  5. **Which ops may be relayed at all** (all of them, or only
     `message.send` and `reaction.toggle`?).

## 10. Push notifications (later; note only)

Push is not part of this contract. The hook: when the server accepts a
`message.send`, it can notify each member who is **not** currently connected
to `/events` and has registered a device push token, through APNs (iOS) or
FCM (Android). A later addition would be `POST /devices` to register a token
and per-conversation mute settings. Payloads should carry no message text
unless the person opts in (the lock screen).

## 11. Mapping table

Every write in `public/js/store.js` (or its adapter) to its op, the tables it
touches in `schema.sql`, and the policy that governs it. "RLS" names the
policy in the schema draft (`-- create policy ...`).

| `store.js` write | Op / endpoint | Tables touched | RLS policy |
|---|---|---|---|
| `sendMessage` | `message.send` | `messages`, `message_attachments` | `messages_insert_member`, `message_attachments_insert_self` |
| `toggleReaction` | `reaction.toggle` | `message_reactions` (needs `removed_at`, `updated_at`; see below) | `message_reactions_insert_self`, `message_reactions_delete_self` (the delete policy would not be used: removal is an update) |
| `createConversation` | `conversation.create` | `conversations`, `conversation_members` | `conversations_insert_creator`, `conversation_members_insert_creator` |
| `addMembers` | `membership.add` | `conversation_members`, `conversations.updated_at` | `conversation_members_insert_creator` (owner clause) |
| `renameConversation` | `conversation.rename` | `conversations` | `conversations_update_owner` |
| `setStarred` | `membership.setStarred` | `conversation_members` | `conversation_members_update_self` |
| `setArchived` | `membership.setArchived` | `conversation_members` | `conversation_members_update_self` |
| `deleteConversation` | `conversation.delete` | `conversations` (`deleted_at`) | `conversations_update_owner` (group-only is stricter, section 6) |
| `deleteForMe` | `conversation.deleteForMe` | `conversation_members` (`cleared_at`) | `conversation_members_update_self` |
| `markRead` | `membership.markRead` | `conversation_members` (`last_read_at`) | `conversation_members_update_self` |
| `updateProfile` | `profile.update` | `profiles` | `profiles_update_self` |
| `setProfileEmail` | `profile.setEmail` | `profiles` (and the auth identity) | `profiles_update_self` (plus auth) |
| `createProfile` | `POST /auth/signup` (not an op) | `profiles` | n/a (server creates it) |
| `setAppearance` | none: device-local (or `appearance.set` if the user decides) | `user_settings` (if synced) | `user_settings_update_self` |
| `uploadAttachment` | `POST /files` | storage (`attachments` bucket) | `attachments_write` |
| `deleteAttachment` | server cleanup of unreferenced files (no client call yet) | storage | n/a |
| `getAttachmentUrl` | `GET /files/:id` | storage | `attachments_read` |
| (reads: `listConversations`, `listMessages`, ...) | local store; fed by `/snapshot` and `/changes` | | `*_select_*` policies decide visibility (section 8) |
| `init` / `reset` | local lifecycle; `reset` has no API (dev only) | | |

### Schema changes this contract needs (not made here; LIME-72 or later)

`schema.sql` is not edited by this brief. The contract implies these
additions, listed so they are not lost:

- `message_reactions`: add `updated_at timestamptz not null default now()`
  and `removed_at timestamptz` (LIME-69's local rows already have them).
- `conversation_members`: add `updated_at timestamptz not null default now()`
  (LIME-69's local rows have it).
- An **op log** table (`ops`: `seq bigserial`, `op_id uuid unique`,
  `actor_id`, `device_id`, `type`, `payload jsonb`, `client_ts`,
  `server_ts`), an **aliases** table for deduplicated DMs, a **devices /
  sessions** table (refresh tokens), and a **files** table.
- The RLS clean-up in section 6 (table row 11).

## 12. Mobile client options (a note, not a recommendation)

The user will face a choice later. Nothing in this API depends on it. One
line each on how the Bluetooth mesh bears on every option: **all of them
need a native Bluetooth module**, because a web view or JavaScript runtime
alone cannot do background Bluetooth relay on iOS or Android.

- **Fully native (Swift for iOS, Kotlin for Android):** direct access to the
  platform's Bluetooth stack and background modes, at the cost of two
  codebases.
- **React Native / Expo:** one JavaScript codebase; Bluetooth through a
  native module (and Expo needs a development build, not Expo Go, for it).
- **Capacitor (wrapping the web app):** the least new code, reusing this
  web app; Bluetooth through a native plugin, and background relaying is
  the part most limited by the web view.

## Demo emails and delivery (LIME-75)

Every demo teacher's email is `<first name, lowercase>@famkind.com`. Lime is a FAM project and these addresses **could be real
mailboxes**. **Local and staging environments must never send real email or SMS.** Anything the API grows that delivers a message to a
person outside the app (an invite, a notification, push, a password-reset or sign-in link, section 10) must **stub delivery everywhere
except production**: write the message to a log or a dev inbox instead. The dev server sends nothing.

## Open points

### Decided (plot's review of this document, 2026-10-01, and the user)

1. **Attachments inside `message.send`** (no separate `attachment.attach`): agreed.
2. **Message time:** the user chose to show the **written** time. Both
   `client_ts` and `created_at` are stored; displayed time is the earlier of
   the two, with the delivery time added past 5 minutes; thread order stays
   `seq` (section 3 `message.send`, section 6 rule 8).
3. **Appearance stays device-local:** agreed (revisit if the user asks).
4. **`POST /events/ticket`:** agreed.
5. **Privacy:** decided by the user (section 8, Visibility). Read receipts are
   deferred.
6. **The directory endpoint** `GET /profiles?q=` is part of the contract now
   (section 4).
7. Line-number drift in the brief: noted, no action.
8. **Added by the review:** presence (section 4, Presence), link previews
   (section 4), and the web sign-in persistence note (section 8).

### Added by LIME-74 (the web app on the API)

13. **`POST /auth/lookup`** exists for the email-first sign-in page and is development-phase only (section 4). It reveals
    whether an email has an account. The first name on the "Welcome back, Jean" heading is not returned, so that heading is
    just "Welcome back" on the API backend.
14. **Partial backfill entries** (section 7) deliver the profiles of the people a new or changed conversation involves.
15. **`log_start` on `/health`** lets a client tell "the dev server was reset" from "I was signed out".

### Still open

9. ~~Changing a password~~ **Done in LIME-74:** `POST /auth/password` (section 4).
10. **Error code for an unknown op `type`.** Section 5 lists `invalid_op` for
    a bad op and `unsupported_op` for an op type from a newer client. The dev
    server returns `unsupported_op` for any `type` it does not know, and
    `invalid_op` for a known type with a bad payload.
11. **Snapshot paging.** Section 4 allows a paged snapshot. The dev server
    returns the whole snapshot in one response (no `cursor`), which is fine at
    demo size and not at production size.
12. **Setting `busy`.** Presence reserves it but nothing sets it yet.
