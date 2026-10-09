# Lime API v2: the blind mailbox

## 1. Status and scope

**Decided 2026-10-06.** This is the protocol the native apps (iOS first, then Android) use with the backend. It follows from the decisions in [`architecture.md`](./architecture.md), especially D8: a blind-mailbox server with sealed sender, client-managed group state and per-device mailboxes.

- **Scope:** the native apps only. API v1 ([`api.md`](./api.md)) is frozen for the web app and the dev server; it is not extended.
- **Shape only.** This document gives the objects, the endpoints and the rules at the level they were decided. It has no full JSON schemas and no database SQL; those belong to the Supabase and core briefs. Points the decision did not settle are listed in section 11 rather than filled in here.
- **Where it differs from `architecture.md`.** Two places were corrected when this was written: a stranger's first message is sent *identified* (section 4), and the server de-duplicates by a hash of the outer ciphertext, not by `op_id` (section 8). `architecture.md` was updated to match.

## 2. What the server stores, and never stores

The backend is Supabase (Postgres and Storage). It stores:

| Table | What it holds |
|---|---|
| `profiles` | The public directory fields only: display name, username, school, avatar file id, `hide_from_search`. This is the one cleartext social data (D7). |
| `devices` | The device id, the user id, the Curve25519 identity key, the Ed25519 signing key, a **signature by the user's master key** (cross-signing), and the time it was revoked. |
| `master_keys` | The user's public master signing key. |
| `one_time_keys` | A pool per device. Each key is **claimed once**. |
| `mailbox_items` | The recipient device, a `cursor` (a bigserial), the outer ciphertext bytes, the size, and the time received. **Deleted when acknowledged.** **Undelivered items expire 30 days after they are received.** |
| `blobs` | Encrypted attachments and contacts-only profile photos: the id, the size, the uploader (for quota), the time it was committed and an optional expiry. The bytes are in the private `blobs` Storage bucket and are **ciphertext only**. |
| `delivery_keys` | Per user, a **hash** of the current delivery-key material (section 4). Never the key itself. |
| `backups` | Opaque backup blobs, encrypted with the recovery key (D5). |

**The server never stores** conversations, group names, membership, the senders of sealed messages, message text, or reactions.

After 30 days an undelivered message is gone for that device. The recipient's other devices and the recovery backup are unaffected.

## 3. Envelopes

A message travels in two layers, and the signed op is inside the inner one.

**Outer envelope (the server sees it).** `{ to_device, access, ciphertext, size }`. It has **no sender**. `access` is either a **delivery-key proof** (a sealed send) or the sender's own authentication (an *identified* send; section 4).

**Sealed inner (what the recipient gets after decrypting the outer ciphertext with Olm).** `{ sender_user, sender_device, sender_cert, op }`. `sender_cert` is the sender's device key signed by the sender's master key, so the recipient can trust a device it has not seen.

**The op (signed, as in `architecture.md` section 4).** `{ op_id (UUIDv7), type, conversation_id, hlc, parents[], payload, sig }`.

- `payload` is a **Megolm ciphertext** for messages, reactions and edits, or an **encrypted group-state op** (section 6).
- `sig` is the sending device's Ed25519 signature over the canonical op.
- `hlc` and `parents[]` carry the ordering (section 5).

**Fan-out.** One request carries a shared Megolm ciphertext plus a list of `(to_device, access)` pairs. The server stores one mailbox item per recipient device. Honest limit (see section 9): the server sees the recipient set of each request.

**Megolm session keys.** They travel as Olm-encrypted *to-device ops* through the same mailbox. They are not a separate channel.

## 4. Sealed sender, delivery keys, message requests and blocking

- **The delivery key.** Each user has one. It is shared only inside their encrypted conversations, so the people they already talk to have it.
- **A sealed send.** The sender proves knowledge of the recipient's delivery key with an HMAC over the request. The server checks the proof against the stored hash and **learns nothing about the sender**.
- **Strangers.** A stranger does not have the delivery key, so their first message is sent **identified**: the server sees who sent it, and the message lands in the recipient's **Requests**.
- **Accept** shares your delivery key with the sender, so later messages can be sealed.
- **Block rotates your delivery key** and shares the new one with everyone except the blocked person, so their sealed sends fail.
- **Rate limits** apply per access token and per IP.

**How the client does this (LIME-96, live for 1:1 chats).**

- **Making and uploading the key.** On registration a device creates a random 32-byte delivery key (kept in the encrypted store, never shown or logged) and uploads `SHA-256(HKDF-SHA256(key, "lime-access-v1"))` with `delivery-access-set`. An upload that did not get through is repeated before the next send. **A new phone has a new store and so a new delivery key**; a master-key replacement therefore re-keys (the old phone's key stops working, and contacts must be given the new one).
- **Sharing it: the `delivery_key.share` op.** An ordinary signed op, inside the same sealed inner, encrypted over the same Olm sessions: `{ type: "delivery_key.share", conversation_id: <the 1:1 id>, payload: { key: <base64 of the 32-byte key> } }`. It is **not a message**: a receiver verifies it like any op, stores the key, and shows nothing (no conversation is created, nothing counts as unread). It is sent when you **Accept** a request, when you **start a chat** with someone (you are accepting them), when you **Unblock** someone, when you **accept a changed key** of a contact (their new phone has none of what the old one held), and, after a **rotation**, to every accepted contact. It is sent sealed when the recipient has already given you their key, identified otherwise. Someone who already has your current key is not sent it twice.
- **Sending.** With a contact's key, a message goes **sealed**: the request has **no Authorization header** and `access = { sealed: <access_key, base64> }`, so the server records no sender. The inner envelope (`sender_user`, `sender_device`, `sender_cert`, `op`) is encrypted inside. Without a key (a stranger, or someone who has not shared one yet) it goes identified, as before.
- **A sealed send answered 403** means the recipient's key is not the one we hold: they blocked us, or replaced their keys. **The app says nothing** (LIME-96-fix, the same as Signal): it stops using sealed for that contact until they share a new key, **sends the same message identified straight away, once**, and shows **"Sent"**. A person who blocked us learns nothing (the identified item is stored and hidden on their phone, as any blocked person's); a contact who changed phones gets the message, in their Requests if the new phone has no history. **"Not delivered" is only for genuine failures** (the identified send itself failing, network errors). The cost: **the fallback item names its sender to the server**, once per message until the contact shares a new key (the same as any stranger's first message).
- **Receiving sealed.** A sealed item names no sender, so the recipient decrypts with every session it has (a pre-key message starts a new one), then **believes the envelope only if it can check it**: the device certificate must verify, the op's signature must verify, an existing session must belong to the person the envelope names, and the certificate's **master key must be the one already pinned for that person**. A sealed item from someone we have not exchanged messages with, or whose master key differs from the pinned one, is kept in `pending_inbound` as `invalid` and **never shown**, and **never raises a key-change prompt** (otherwise anyone holding your delivery key could forge a "Bob's key changed" warning). A person whose keys really changed writes identified first (their new phone holds nobody's key), which is vouched for by the server and goes through the key-change flow.
- **Block rotates.** Blocking someone who had your key creates a **new delivery key**, uploads its hash, and shares the new key with **every accepted contact except them**; their sealed sends are refused (403), which the app turns into a silent identified send. Their identified sends still reach the server and are hidden on your phone, as before. Blocking a stranger who never had your key rotates nothing. **Unblock** gives them the current key again. The hash is uploaded before any share goes out, so a contact is never given a key the server would refuse.
- **What the server can no longer tell a sender.** The "not delivered" notices of LIME-95-fix work for identified items only (the server records their sender). For a sealed item the server cannot say who to tell: a message waiting for a device that was replaced is simply dropped, and the sender is not told. Their next send is refused (the replaced phone has a new key) and goes identified silently, which reaches the new phone.
- **Temporary policy.** A replaced phone can still take over an account with a verified sign-in (LIME-95-fix); once the recovery key exists, a registration lock will require it.

## 5. Ordering

**This is the answer to [`architecture.md`](./architecture.md) section 11, item 5** (message ordering under the mailbox). It was told to the user on 2026-10-06 with no objection.

- **The server's `cursor` is per mailbox, and for sync only.** It tells a device where it has got to in its own mailbox. It says nothing about the order of a conversation.
- **The order of a conversation comes from the devices:** the **HLC** (a hybrid logical clock) plus `parents[]` (the latest op ids the sender had seen when it made the op).
- **Display order is causal**, with ties broken by HLC, then by `op_id`. It is identical online and over the mesh.
- **The display time** keeps v1's rule: it is never in the future.

## 6. Group state, authority and conflict rules

Group state is managed by the clients. The server holds none of it.

- **The ops:** `group.create`, `group.add`, `group.remove`, `group.leave`, `group.rename`, `group.set_avatar`, `group.set_role`. All are encrypted and signed, and ordered by the rules in section 5.
- **Authority is checked by every client:** only the owner and admins may add, remove or rename; a member may leave. An op that breaks the rules is ignored.
- **Conflict rules:**
  - a concurrent **remove beats an add**;
  - a **rename** or **avatar** change is last-writer-wins by `(hlc, op_id)`;
  - the **owner cannot be removed**, except by leaving; then the oldest admin, else the oldest member, becomes owner.
- **Rotate the Megolm session on any membership change** (`architecture.md` section 5).

## 7. Endpoints (shape only)

All are under `/v2` and are implemented as Supabase Edge Functions. This is a list of what exists and what it carries, not a specification.

**Auth.** Supabase Auth with email and password, plus a device registration that binds a token to a `device_id`.

**Keys.**

- Upload the device keys together with a batch of one-time keys.
- `GET /v2/users/:id/devices`: a user's devices' identity keys and cross-signatures.
- `POST /v2/keys/claim`: claim one-time keys (each is claimed once).
- Publish the master key.

**Mailbox.**

- `POST /v2/send`: the fan-out batch (a shared ciphertext and a list of `(to_device, access)`).
- `GET /v2/mailbox?after=cursor`: the items after a cursor.
- `POST /v2/mailbox/ack`: deletes up to the cursor.

**Realtime.** One Supabase Realtime channel per device. It carries a **"new items" nudge only**, never content.

**Push.** APNs with **no content**. The notification extension fetches the items and decrypts them on the device.

**Blobs and photos (built in LIME-98b).** Two **private** Storage buckets, reached only through Edge Functions that hand out short-lived (5 minute) signed URLs. There are no Storage policies, so the anon and authenticated roles cannot read, write or list either bucket directly.

- `avatar` (one function, `action` in the body): `put {size}` returns a signed upload URL for my photo (a JPEG, at most 1 MiB; the bucket enforces the size and `image/jpeg`), `commit` checks the upload and publishes it (`profiles.avatar_version`), `get {user_id}` returns a signed download URL and the version for **any signed-in user** (404 when there is none, never anonymous), `visibility {everyone|contacts}` and `remove`. Switching to `contacts` **deletes the public object**. **The public photo is visible to the server and to every signed-in user who asks for it.** Bucket `public-avatars`.
- `blob` (`action`): `put {blob_id, size, expires_in_days?}`, `commit`, `get`, `delete`. **Ciphertext only**: AES-256-GCM, the key never reaches the server. The id is chosen by the client; whoever knows an id can download that ciphertext, only the owner can replace or delete it. Limits (configuration, not protocol): 25 MiB per blob, 200 MiB and 500 blobs per user, 60 calls per minute. Bucket `blobs`. Chat attachments will reuse it.
- **Contacts-only photo.** Each account has a random 32-byte **profile key**. It is shared with accepted contacts **inside the same encrypted `delivery_key.share` op** as the delivery key (`"profile_key"`, so the same triggers) and **rotates with the delivery key on a block**. A contacts-only photo is `nonce || AES-256-GCM(jpeg)` under `HKDF(profile key, "lime-photo-enc-v1")`, bound to its blob id, stored as a blob whose **id is `HKDF(profile key, "lime-photo-id-v1")` formatted as a UUID**: a stranger cannot compute it, and a blocked contact (old key) cannot find the re-uploaded copy. When my photo, or who may see it, changes, each accepted contact is sent a small encrypted control op `profile.changed {photo_version}` (a signed op over the existing channel, sealed where we hold their key, never shown as a message); the receiver checks my photo at once. Contacts otherwise re-check a photo at most hourly, and pull-to-refresh or opening a chat checks at most once a minute per person (the server learns that a user fetched a blob id, as it already learns who looks up whose keys).
- **Attachments (LIME-98c).** One `attachment` function (`put`, `commit`, `get`, `delete`) over the same private `blobs` bucket, objects `a/<id>/<n>`. A file is encrypted on the phone in **1 MiB chunks, AES-256-GCM, a random key per file**; each chunk's nonce is its index and its associated data is the attachment id, its index and the chunk count (so chunks cannot be reordered, dropped, added or moved). The **key, the SHA-256 of the plaintext, size, type, name, dimensions and a thumbnail of at most 2 KB travel only inside the encrypted message** (`payload.attachments`, up to 10 per message, with a caption of up to 8 KB). `put {attachment_id, size, chunks, recipients}` returns a signed upload URL for each chunk the server does not hold yet, so an interrupted upload **resumes** by asking again (the phone recomputes the same chunks); `commit` checks every chunk exists and the total is not more than declared. The message is sent only after its files are up. `get` returns signed download URLs and counts the caller as a recipient (the sender declares how many there are: 1 for a chat, the other members for a group). **The server deletes an attachment an hour after the last recipient fetched it, or 30 days after upload, or a day after an upload was never completed.** Limits (configuration): 50 MB per file (51 MB ciphertext), 300 MB and 200 files per user on the server at a time, 240 calls per minute. The sweep is `blob-sweep` (an Edge Function that deletes the Storage objects), called every 15 minutes by `pg_cron` through `pg_net` with a secret kept in `sweep_target` (set per environment by `supabase/schedule-sweep.sh`; refused without it). The server sees ciphertext sizes, chunk counts, who uploaded and how many fetched, and timing; never the contents, the name, the type or the key. **Voice messages and video (LIME-98d) use the same pipeline unchanged**: a voice message is mono AAC at about 24 kbps (`audio/mp4`; its `duration_ms` and a 64-byte loudness waveform ride in the descriptor's `duration_ms` and `thumb`), a video is H.264 720p in an MP4 of at most 3 minutes and about 50 MB (`video/mp4`, with a 2 KB poster thumbnail). A download resumes by chunk (chunks already fetched are kept on the phone until the file is whole, then verified), and each phone can show how many chunks of an upload or download are done.
- **Group photos (LIME-104).** A group's picture is an emoji or a photo, changed or removed any time by the owner or an admin like a rename. A **photo is encrypted on the phone** (`nonce || AES-256-GCM`, a new random key, bound to its blob id) and uploaded as an opaque blob through `blob`; **the blob id and the key travel only inside the group's signed `group.set_avatar` op** (`{"photo": {"id", "key"}}`, or `{"emoji"}`, never both; a malformed photo makes the op invalid rather than clearing the avatar), which is sent to the members' devices like every other group op, so the server never sees the picture, the key or which group it belongs to. Members fetch it by blob id (an id is a capability) and cache the decrypted picture in their encrypted store; a changed or removed photo deletes the old blob (best effort), and someone added later gets the op with the group's history. The timeline says "Rae changed the group photo". **Limit:** a member who was removed still knows the key to the blob that was current when they left; the blob is deleted the next time the photo changes, and it is only a picture.
- **Message actions (LIME-105): edit, delete, reactions.** Three more signed, encrypted ops, sent exactly like a message (over Olm to one person, sealed where possible; over the group's Megolm session to a group), so the server sees an item like any other and never a reaction, an edit or a delete. Each names its `target` (the message's op id) and carries its own clock `hlc`, so devices converge whatever order they arrive in:
  - `reaction.toggle { target, emoji, on }` sets *my* state for one emoji on one message (last clock wins per message, person and emoji; `on: false` removes it). One emoji of at most 16 scalars with no letters or digits; at most 40 different emoji per message. Any member may react, in a chat, group or Replies. A reaction is not a message: no unread, no notification.
  - `message.edit { target, text }` replaces the text (the latest edit wins by clock; only the latest text is kept). **Only the author, and only within 24 hours of the message's own clock** (receivers allow a 10-minute clock skew); a message with files may have an empty caption. The search index follows.
  - **Forwarding and link cards (LIME-106)** are two optional fields of a `message.send` payload, both inside the encryption. `forwarded: true` labels a forward; it never carries who wrote the original. `link_preview: { url, title, site, image? }` is a card the **sender's phone** built (`url` is http or https; `image` is an attachment descriptor of a JPEG of at most 200 KB, uploaded through the attachment pipeline of section 6 and shown as the card's picture, not as an album photo). **Nobody who receives a message visits its link**: they fetch the sender's encrypted picture instead. A malformed preview is dropped and the message still arrives.
  - **Forward shares the file, it does not copy it.** The new message carries the same attachment descriptors (the same id and key), and the forwarder calls `attachment { action: "share", attachment_id, recipients }` so the server keeps the one encrypted file for the extra people: `recipients` grows (to at most 100) and `expires_at` becomes at least a week away, never later than 30 days after the upload. Anyone who knows the id may call it (the id is already a capability for `get`); deleting stays with the owner. A forward goes to at most five chats.
  - **Messaging yourself (LIME-106).** A chat with my own user id (`dm:<my id>`) is stored and "sent" on this phone only: nothing is encrypted for a server, uploaded or queued; its edits, deletes and reactions are local. It syncs to other devices once device linking exists.
  - `message.delete { target }` is **delete for everyone**: the same author and 24-hour rule; the message becomes a tombstone (its place stays, its words, files and reactions go, the search index forgets it) shown as "This message was deleted". For a thread's root the replies stay. **Delete for me** is local only and sends nothing.
  - **Honest limit:** a delete cannot unsee or unsave: Lime says so in the confirmation ("can't guarantee it's gone if someone already saw or saved it").
  - **An edit or delete that arrives before its message waits** and is applied when it arrives; forged ones (not the author, outside the window, wrong conversation) are ignored without error. These ops are retried until sent (a local outbox).
- **Trade-offs.** A person you message first receives your photo key with your delivery key (before they accept), so they can see a contacts-only photo; a blocked person keeps the copy already on their phone; the expiry job for blobs with `expires_at` is not scheduled yet (profile photos never expire).

**Directory.** Search with an exact match on username, email or phone, as in v1. It respects `hide_from_search`.

**Backup.** `PUT /v2/backup` and `GET /v2/backup`, with opaque contents.

**Calls.**

- `POST /v2/turn`: time-limited TURN credentials, rate-limited.
- `POST /v2/calls/token`: a LiveKit token, in exchange for a **per-call capability** taken from the encrypted invite. No server-side membership check is needed.

## 8. The mesh relay and de-duplication

- **Relays carry the outer envelope unchanged:** `to_device`, the ciphertext and `access`. Whoever gets online first posts it to `/v2/send`.
- **The server de-duplicates by a hash of the outer ciphertext, per recipient device.** It cannot see the inner `op_id`.
- **Recipients de-duplicate by `op_id`.**

## 9. Honest limits: what the server can still infer

The server is blind to content, to the sender of a sealed message, and to group membership. It still sees or can infer:

- **Recipient sets.** Each fan-out request shows which devices a message went to, so the server could infer group membership statistically (this limit is already in `architecture.md` section 5).
- **Timing** of sends and fetches, and **sizes**.
- **IP addresses.**
- **The sender of an identified message**, which is a stranger's first message (section 4).
- **The directory.** The `profiles` fields are cleartext by design (section 2).
- **The key directory.** The public device keys, master keys and one-time keys are held by the server, and the key endpoints are authenticated, so the server sees which account asks about whose devices and keys.

Metadata hiding beyond this (private group credentials in the style of zkgroup) is an open question in `architecture.md` section 11.

## 10. Changes from v1

| | v1 ([`api.md`](./api.md)) | v2 |
|---|---|---|
| Who it serves | The web app and the dev server | The native apps only |
| Envelope | A plain op: `op_id`, `type`, `actor_id`, `device_id`, `client_ts`, `payload` | A signed op inside a sealed inner inside an outer envelope with no sender |
| Op signing | None (an open question in v1 section 9) | Every op carries `sig`, an Ed25519 signature by the sending device |
| Payload | Readable JSON | Megolm ciphertext, or an encrypted group-state op |
| Delivery | One op log per user, read from `/changes` | Per-device mailboxes: fetch, then acknowledge (which deletes) |
| Ordering | The server's `seq` is the one order of events | The mailbox `cursor` is for sync only; conversation order is HLC and `parents[]`, decided by the devices |
| Idempotency | The server remembers every `op_id` | The server de-duplicates by a hash of the outer ciphertext per recipient device; recipients de-duplicate by `op_id` |
| Membership and visibility | The server holds memberships and enforces visibility with row-level rules | The server holds no membership; group state is encrypted ops that every client checks |
| Auth | Bearer access token (about 15 minutes) and a rotating refresh token, each bound to a `device_id` | Supabase Auth plus a device registration that binds a token to a `device_id` |
| Realtime | Server-Sent Events carrying changes | A Supabase Realtime channel per device carrying a "new items" nudge only |
| Link previews and notifications | A server endpoint (`GET /link-preview`) unfurls the page | The sender's device makes the preview (the server never fetches URLs); notifications carry no content |
| Messages for a phone that is offline | Kept in the log | Kept up to 30 days, then expired |

## 11. Open items for the Supabase briefs

Things the decision did not settle. Items marked **decided in LIME-92** were settled when the first half of the server was built (`supabase/`); the rest are still open.

1. **Supabase limits.** Realtime and Edge Function limits at scale have not been verified; the first Supabase brief surveys them. (The free plan's limits and its inactivity pause are noted in `supabase/README.md`.)
2. **The delivery-key HMAC construction. Decided in LIME-92 (sealed access).**
   - Each user has a random 32-byte **delivery key**, shared with contacts inside encrypted messages.
   - The sender presents `access_key = HKDF-SHA256(delivery_key, info = "lime-access-v1")`, 16 bytes, per recipient user.
   - The server stores **only SHA-256(access_key)** per user (`delivery_access`) and compares it in constant time. This is Signal's unidentified-access model.
   - **Rotation (block)** is the user uploading a new hash.
   - **Client side decided in LIME-96:** the key is made on registration, shared in the `delivery_key.share` op, rotated by a block, and re-made by a new phone (see section 4).
   - Still open: freshness and replay protection of the proof, and how a second device of the same account obtains the delivery key (today an account has one device, because a new phone replaces the old one).
3. **The one-time-key pool. Decided in LIME-92:** a device uploads **50**; the client tops up when the server reports **fewer than 20** left (every upload and registration response reports the remaining count).
4. **The rate-limit numbers. Decided in LIME-92** (configuration, not constants; set as function secrets):
   - sends: **120 recipient-items per minute** per authenticated user, or per access key for sealed sends;
   - key claims: **60 per minute** per user;
   - device registrations: **10 per hour** per user;
   - still open: the numbers for directory search and `POST /v2/turn`, which are not built yet.
5. **The de-duplication window and the relay rule.** Decided in LIME-92 for the server: it de-duplicates by SHA-256 of the ciphertext **per recipient device, for as long as the item exists** (until it is acknowledged or expires after 30 days). Still open: how a relaying phone (which also cannot see `op_id`) recognises an envelope it already carries.
6. **The `access` of an identified send.** Decided in LIME-92: it is `{ identified: true }` plus the sender's user token; the item records the sender's user id and is marked identified, and the recipient's fetch returns both. Still open: what stops identified sends being used to flood a stranger, which belongs to the message-request work (the per-user send limit in item 4 applies).
7. **The HLC and `parents[]` details:** the clock format, how many parents an op lists, and what a device does with an op whose parents it has not received yet.
8. **Acknowledgement semantics.** `POST /v2/mailbox/ack` deletes up to a cursor; what happens to a device that acknowledges and then loses the items before applying them is not specified.
9. **Device revocation.** `devices` records a revoked time and the server refuses a revoked device (it cannot fetch or acknowledge, is not listed, and cannot be sent to); the flow that revokes a device, rotates Megolm sessions and stops its mailbox is not specified.
10. **The blob expiry rule and quotas.** The cost principles give "for example 30 days after every recipient has fetched them" as an illustration, not a number; the uploader quota is not specified. Blobs are not built yet.
11. **The verified-teacher badge** (D7 says "later") and any change it brings to `profiles`.

**Also decided in LIME-92 (needed to build it, not in the design):**

- **The device cross-signature message.** `devices-register` verifies an Ed25519 signature by the user's master key over the UTF-8 text `lime-device-v1\n<device_id>\n<identity_key>\n<signing_key>` (the key strings as sent, standard base64). The registration also carries the master public key; an account's master key is fixed by its first registration.
- **Function names.** The endpoints are Supabase Edge Functions under `/functions/v1/` (`devices-register`, `keys-upload`, `users-devices`, `keys-claim`, `delivery-access-set`, `send`, `mailbox-fetch`, `mailbox-ack`). The `/v2/...` paths in section 7 are the logical names; a gateway for them is not built.
- **Sealed sends are all or nothing.** A batch is checked before anything is stored: a wrong or missing access key, an unknown device or a revoked device returns `403` for a sealed recipient (the three look the same), `404` for an identified one, and nothing is stored. An item over **64 KB** returns `413`; a rate limit returns `429`.
- **Implementation guards** (configurable): at most 500 recipients per send, 100 keys per upload, 100 items per fetch.

**Also decided in LIME-93 (LimeCore speaks the protocol; identified 1:1 Olm only):**

- **Networking lives in the platform, the protocol in the core.** LimeCore defines a `Transport` callback interface (`request(method, path, headers, body) -> response`); the platform implements it (`URLSession` on iOS, OkHttp on Android later). All protocol logic stays in Rust. Auth tokens are passed in per call; the core never stores passwords or tokens.
- **`users-lookup`.** A minimal slice of the Directory endpoint: an exact, case-insensitive email match, authenticated, 30 a minute per user, returning only the user id (`404` otherwise; it never lists). `devices-register` now also returns the account's `user_id`.
- **Key persistence.** The Olm account, the Olm sessions and the master signing key live inside the device's SQLCipher store; the Olm pickles are encrypted with a key derived from the store key by HKDF-SHA256 (info `lime-pickle-v1`). The master key is made by the account's first device and signs each device (`lime-device-v1\n...`).
- **Signing.** The sending device signs the op with its Olm account's Ed25519 key over the **canonical JSON** of the op without `sig` (object keys sorted, no whitespace). The sealed inner is `{ sender_user, sender_device, sender_cert, op }`, where `sender_cert` is the device's keys, its master public key and the master key's signature. A recipient checks the certificate, the op signature, that `sender_user` matches the server's sender for an identified item, that the certificate's identity key is the Olm session's, and the conversation id; a person's master key is **pinned on first use** and a different one is refused.
- **The wire form.** The outer ciphertext is base64 of one type byte (Olm's message type) followed by the Olm message bytes, one ciphertext per recipient device. For now the op `payload` is `{ "text": ... }` directly inside the Olm ciphertext; it becomes a Megolm ciphertext when Megolm arrives.
- **Ordering fields, as built.** `hlc` is `<wall milliseconds, 13 digits>.<counter, 4 digits>` (a hybrid logical clock that ticks on send and folds in a received clock); `parents[]` holds the id of the most recent op the sender has in that conversation; the display time of a received message is `min(hlc wall, now)`. A 1:1 conversation id is `dm:<lower user id>:<higher user id>`. This partly answers item 7 (HLC and `parents[]`); how many parents and what to do with an op whose parents are missing remain open.
- **Fetching.** `sync` fetches the whole mailbox and acknowledges **everything it fetched**, including an item it could not read (otherwise it would return on every sync). Only identified items are understood yet; sealed items are acknowledged unread. The one-time-key pool is topped up when the device registers.

**Also decided in LIME-94 (sign-up and sign-in on the native apps: a password AND an emailed code):**

- **Why a custom enforcement.** Supabase Auth cannot require both a password and an email code on one session: its email code is a sign-in method of its own, not a second factor (and its MFA factors are TOTP and phone). So the server keeps its own record per Auth session.
- **The proof record** (`auth_proofs`, one row per session id, taken from the JWT's `session_id` claim): `password_ok` is set when an Edge Function itself checked the password (`signin-password`), or set a first password for an account that just proved its email (`signup-set-password`, `reset-verify`); `code_ok` when an Edge Function itself checked the emailed code (`code-verify`, `signup-verify`, `reset-verify`). A session is **verified** only when both are true. **Every function except the sign-in ones requires a verified session** (`requireUser`): a password-only session and a code-only session (including one made straight with Supabase Auth by someone who has the emailed code but not the password, or the password but not the code) can register no device and call nothing else. Because the check is on the session, `register_device` in the core needs no extra argument; a session keeps its verified state across token refreshes (the session id does not change).
- **Both checks are made by the functions, never the phone.** The functions call Supabase Auth's own password and email-code endpoints with the project's public key. Wrong codes are counted per challenge (`code_challenges`): **5 tries, then the code is locked** until a new one is sent; a new code can be asked for **30 seconds** after the last (`code-resend`). Auth's own minimum interval between emails to one address must therefore be **30 seconds or less** (the hosted default is 60 seconds): see `supabase/README.md`.
- **Changing a password ends the account's other sessions**, so `signup-set-password` and `reset-verify` return a **fresh session** that has passed both steps.
- **The flow.** Sign-up: `identify` (a new address) then `signup-start` (emails a code), `signup-verify` (checks it, returns a code-only session), `signup-set-password` (at least 10 characters; only for an account with no profile yet; returns the verified session), `profile-set`. Sign-in: `identify`, `signin-password` (checks the password, emails a code, returns the password-only session and the masked address), `code-verify` (and `code-resend`). Forgot password: `reset-start` (always answers the same, so it does not reveal whether an account exists), `reset-verify` (the code and the new password together; returns the verified session).
- **`identify` (the brief called the username part `username-resolve`).** One unauthenticated function for the first screen's one question. An email answers whether an account exists (new or existing); a username answers with a **masked** email hint (`s•••@famkind.com`) or `404`. The full email of a username is never returned: `signin-password` and `reset-*` accept a username and resolve it on the server. Per-address rate limits (30 a minute for identify and sign-up; 10 per ten minutes for password sign-in, per address and per identifier; 10 emails an hour per address), as configuration. The client address is Cloudflare's `cf-connecting-ip`, else the last `x-forwarded-for` entry (earlier entries can be forged).
- **Profiles** (`profiles`: user id, display name, username, school, `hide_from_search`; the directory fields only): `profile-set` (a name of 1 to 60 characters; an optional username under the web app's rules and unique ignoring case; an optional school) and `profile-get`. Row-level security on, service role only, like every table.
- **`pending_inbound` (core).** Every mailbox item a device fetches is written to `pending_inbound` **before** it is acknowledged, and removed only once it has become a message. An item that cannot be read yet (a normal Olm message with no session, a pre-key message that fails) is retried on every sync and whenever a session appears; a sealed item (not supported yet) is kept until it is; an item that can never become a message (a bad signature or op, a master key that changed) is kept with its reason and not retried. This replaces LIME-93's acknowledge-everything behaviour. Still open: how long invalid items are kept.
- **Still open from this brief:** phone sign-in; production email delivery (a custom SMTP sender with a verified domain); the numbers for the email and sign-in limits in production; revoking a session from another device.

**Also decided in LIME-95 (New message and the first real 1:1 chat; still identified Olm sends only):**

- **Every first message from a new person is a request.** Sealed sends and delivery keys are LIME-96, so until then every send is identified and, per section 4, lands in the recipient's **Requests**. In the core, a conversation has a `request_state`: `pending` (someone else started it), `accepted` (you started it, or you accepted it) or `blocked`. **Accept** is local for now (it will also share the delivery key with the sender once sealed sends exist). **Block** hides the conversation and stops storing that sender's new messages on this device: a blocked sender's items are still read (so the Olm session keeps in step) and acknowledged, never kept or shown. The server-side block (rotating the delivery key) comes with LIME-96.
- **Finding a person: `users-find { query }`.** An **exact** username (with or without `@`) or an **exact** email, case-insensitive; authenticated, 30 a minute per user (the `lookup` limit); never a list or a partial match. It returns **public fields only** (`user_id`, `display_name`, `username`, `school`, `is_self`), never an email or phone. A person who set `hide_from_search`, and an account with no profile yet, get the same `404` as someone who does not exist. (`users-lookup`, email to user id only, stays for the core's own use.)
- **Other people's profiles: `profile-get { user_id }`.** Public fields only; 120 a minute per user (`LIME_RATE_PROFILE_PER_MIN`); `404` for no profile. Someone who hid themselves from search shows **only their display name** (no username, no school), because the person already messaged you and a name is all a request needs. Without `user_id` it is still your own profile.
- **The Realtime nudge is a private channel.** `send` broadcasts `{ type: "new" }` on `device:<id>` with `private: true`, and a policy on `realtime.messages` lets a client **receive** on that topic only if the device is its own, not revoked, and the session has passed **both** sign-in steps (`public.can_receive_device_nudges`). Anyone else (another account, or the public key alone) is refused the join. The nudge still carries no content. A client must set its access token **before** joining (`realtime.setAuth`), or it joins as the anonymous role and is refused.
- **Ordering, as built.** Each op's `parents[]` are the **heads** of the conversation as the sender sees it (ops that no other op names as a parent), newest last, at most three. Display order is causal: an op comes after every parent that is in the conversation; among the ready ops the smallest `(hlc, op_id)` goes first; a parent that never arrived is not waited for, and a malformed cycle falls back to `(hlc, op_id)`. The result is the same whatever order the items arrive in. The clock is moved atomically in the database (a send and a sync running side by side cannot move it backwards). This answers the "how many parents" and "missing parents" parts of item 7.
- **Sending is queued, then delivered.** `queue_text` writes the message as `sending` with its op id, clock and parents fixed; `deliver_queued` sends everything waiting, oldest first, marking each `sent` when the server accepted it (a failure marks it `failed`, stops, and keeps the order; it is retried on the next sync, foreground or tap). A recipient de-duplicates by op id, so a retry never shows twice. There are no read receipts.
- **Names.** A conversation is titled with the other person's display name: from the search result when you start it, else fetched with `profile-get` after the first message arrives (until then it shows the user id).

**Also decided in LIME-95-fix (a phone with new keys replaces the account's keys):**

- **The problem.** `devices-register` fixed an account's master key at its first registration and refused every later one (`409 master_key_mismatch`). Signing out wipes a phone's keys, so after any sign-out and sign-in (or a fresh install) the phone could not register and the account could not message. The app swallowed the refusal, so search and sync just said "Couldn't search".
- **The rule now.** A registration with a **different** master key from a **fully verified** session (a password AND the emailed code, as for every function) **replaces the account's keys**, in one atomic step (`reset_account_keys`): every existing device is **revoked** (it can no longer fetch, be listed or be sent to), their **unfetched mail and unused one-time keys are deleted** (nobody holds the keys to read them), and the master key is replaced. A registration with the **same** master key (a second device that has it) changes nothing. The response says `keys_reset: true`. Rate limit: the existing 10 registrations an hour.
- **The account's owner is emailed** when its keys are replaced: "A new phone signed in and replaced your Lime keys. If this wasn't you, reset your password." It goes through Resend's HTTP API with a key kept as the function secret `LIME_NOTIFY_RESEND_API_KEY` (sender `LIME_NOTIFY_FROM`, default `Lime <no-reply@send.limechat.org>`); without the secret nothing is sent and nothing fails. Best effort: a failed send never blocks the registration.
- **Contacts must accept the change.** A contact that pinned the old master key (trust on first use) refuses the new one. The core records the new key (`peers.new_master_key`) and the chat shows "<Name>'s security key changed. This usually means they signed in on a new phone. Accept it to keep chatting." **Accept new key** (`trust_new_key`) re-pins it, reads any messages held back for it (their plaintext is kept in the encrypted store meanwhile: a message cannot be decrypted twice) and lets queued messages go.
- **"Not delivered".** For each **identified** item deleted at a key replacement (or expired after 30 days), the server keeps a notice `{ sender_user, ciphertext_hash }`. The sender collects its notices once with `undelivered-take`, matches the hashes against the hash of each ciphertext it sent (the core remembers them in `message_deliveries`), and marks the message `undelivered`; the bubble says "Not delivered. Tap to resend" (`retry_message`; the same message goes out again, and the recipient de-duplicates by op id). A **sealed** item has no known sender, so its sender cannot be told. The server learns nothing new: a hash of bytes it already holds.
- **One active phone per account, for now.** Because a new phone replaces the old keys, an account signed in on a second phone revokes the first: the first phone's next call is refused (`403`) and it says "Your session has ended. Please sign in again." Multiple devices come with device linking.
- **Temporary policy.** Letting a verified session replace the master key is a stop-gap, because there is no recovery key yet. **Once the recovery key exists, a registration lock will require the recovery key to replace the master key** (a verified session alone will no longer be enough), and this rule will be removed.
- **Truthful errors in the core.** `check` now separates `401`/`403` (`Unauthorized`: the session ended, was never verified, or the device was replaced), `429` (`RateLimited`), `5xx` (`Unavailable`) and other `4xx` (`Rejected`); `Network` is only for a request that got no answer. The app turns each into its own message and keeps "check your connection" for real connection failures.

**Also decided in LIME-98 (Settings):**

- **About is a public profile field.** `profiles` gained `about_emoji` (one emoji, optional) and `about_text`; together at most **140 characters** as a person sees them (an emoji, even a family emoji with many scalars, counts as one). **The server can see it, like the name and the school**, and shows it to the same people: through `users-find` and `profile-get`, and not at all for a person who hid from search. `profile-set` still replaces the whole profile, so an editor sends every field.
- **The display name is 1 to 40 characters** (it was 60). Longer names saved earlier stay as they are until edited.
- **Hide from search** (`hide_from_search`, already in `profile-set`) is honoured by `users-find` (a hidden person gets the same 404 as nobody) and hides their username, school and About from `profile-get` (their name stays, because a request needs one). You always see your own.
- **Your own masked address.** Your own `profile-get` also returns `masked_email` (`s•••@famkind.com`) for the Account screen; never another person's.
- **Changing the password: `password-change-start` then `password-change-verify`.** The session is verified as for any function. Step one takes `{ current_password }`, checks it with Supabase Auth (10 tries per 10 minutes) and emails a code (5 wrong tries, then locked; the same email limits as sign-in). Step two takes `{ code, new_password }` (at least 10 characters; the new password never travels in step one) and changes the password. Changing a password ends the account's other sessions, so it returns a **fresh verified session** and the phone carries on with it.
- **Local only:** the appearance (System, Light, Dark) is kept on the phone and never sent anywhere. The "Safety numbers" screen is read-only: "Your key was set on <date>" (when this phone's keys were made; for an account older than LIME-98, the day of the upgrade) and a short fingerprint of the account's master key (SHA-256, five groups of four hex digits).
- **Unblocking** (`unblock`) restores a blocked conversation as accepted, with what was stored before the block. Messages that arrived while blocked were read and dropped, so they are not there.

**Also decided in LIME-99 (search):** search is **on the device only** (the server holds no message text, so it cannot search). The phone keeps an FTS5 index of decrypted message text inside its own SQLCipher database, so it is encrypted at rest like the rest of the local store; nothing about a search is sent anywhere. Directory search stays an exact username or email (`users-find`), never a list or a partial match.

**Also decided in LIME-100 (message formatting):** the `text` of a message is **Markdown from a small fixed subset** (bold, italic, underline `__x__`, strikethrough, inline code, fenced code blocks, bulleted and numbered lists with one nesting level, and http/https/mailto links), inside the encrypted payload; there is no HTML on the wire. Anything outside the subset is plain text, and nothing is rejected. LimeCore holds the one grammar (`parse`, `serialize`, `plain_text`, `normalise`); **every message is normalised when sent and when received**, so both phones hold the same written form. The written form is limited to **30,000 bytes** (so the envelope fits 64 KB). Search, list previews and notification previews use the plain words. Old messages are plain text, which is valid Markdown of this subset. Full detail in [`message-format.md`](./message-format.md).

**Also decided in LIME-101 (reply threads):**

- **The payload.** A message's encrypted payload is `{ "text": "<Markdown>", "thread_root": "<message id>" }`; `thread_root` is present only on a reply. It is inside the Olm ciphertext, so **the server never learns which message a reply answers**. The id is the root's op id (the id every device already knows a message by).
- **Replies inherit the root's conversation.** A reply is sent in the same conversation as its root. **A reply to a reply names the same root** (the sender resolves it, and the receiver does too if a client names a reply): a thread is one level, as in Slack. A reply to a message that is not in that conversation is refused when sending.
- **Out of order.** A reply that arrives before its root is stored with its `thread_root` and appears once the root does (nothing waits on the network order). The display order inside a thread is the same causal order as the timeline (`parents[]`, then HLC, then op id); a reply's `parents[]` are the thread's own heads.
- **The timeline.** Replies are **not part of the main conversation timeline**; the root shows "N replies · Last reply <time>" with up to three replier avatars. A conversation's activity (its place in the list) still counts replies.
- **Unread.** Replies from others count in the conversation's unread badge and, separately, in the thread's own unread count (`thread_state`), which clears when the thread is opened.
- **Search.** A search hit in a reply names its thread and opens it; in-chat find steps through the timeline only.
- **Not in this brief:** "also send to chat", quote-reply, thread notifications (LIME-102).

**Also decided in LIME-97 (group chats): the group ops and Megolm, as built.**

- **A group is its create op.** `group.create`'s `op_id` is the **group id**; the conversation id is `grp:<group id>`. Every group op's `conversation_id` is that id. **There is no server-side group**: no table holds a group's name, avatar or members (a test reads every table to check). Limits: **100 members** (the owner included), **name at most 50 characters** (not empty), avatar an emoji of a few characters.
- **State ops** (signed, in the sealed inner, sent over Olm to every member device, sealed where we hold the person's delivery key, identified otherwise; **the people before and after the change are all sent it**, so a removed person hears of it):

  | type | payload | who may |
  |---|---|---|
  | `group.create` | `{ name, emoji?, members: [user ids] }` | the creator becomes owner |
  | `group.add` | `{ users: [...] }` | owner, admins |
  | `group.remove` | `{ user }` | owner (anyone but themselves); an admin (plain members only) |
  | `group.leave` | `{}` | any member |
  | `group.rename` | `{ name }` | owner, admins |
  | `group.set_avatar` | `{ emoji? }` | owner, admins |
  | `group.set_role` | `{ user, role: "admin" \| "member" }` | the owner (no op makes anyone owner) |

  `parents[]` of a state op are the **state ops** the sender had seen (the group's own DAG, not its messages).
- **State is replayed, not synced.** Each phone stores every verified state op with its whole signed envelope and works the members, roles, name and avatar out by **replaying them in `(hlc, op_id)` order**, so every phone reaches the same state whatever order the ops arrived in (a test shuffles them). Authority is checked **at that point of the replay**; an op that breaks the rules is ignored. **A concurrent remove beats an add** (an add is void when a remove of that person exists that neither follows nor precedes it by `parents`; an add that follows the remove is a real re-add); **rename and avatar are last-writer-wins by `(hlc, op_id)`**; **the owner can't be removed, only leave**, and then the **oldest admin, else the oldest member** becomes owner (joining order in the replay).
- **A person added is given the history.** The adder sends them one or more `group.history` ops whose payload is `{ ops: [<the original signed envelopes>] }`. The receiver checks every envelope itself (certificate chain, signature, group id; a master key different from the one pinned is skipped, never a key-change prompt) and replays; if the sender of the history is not in the resulting group, it is undone. **A person who is not told of an add or a removal sees nothing of it** (there is no server to ask).
- **Messages use Megolm.** Each sending **device** has **one outbound session per group**. Its key goes to every member in a **`group.session`** op over Olm: `{ group_id, session_id, key }`; a receiver keeps it tied to the sending device and accepts it only from a member of the group (when the group is known). A message is a signed `message.send` op, wrapped in the sealed inner (so the sender and certificate are inside), **encrypted once with Megolm**, and sent as the wire text **`0x02` followed by `{ "s": <session id>, "c": <Megolm ciphertext, base64> }`** (an Olm message starts with 0 or 1): **one ciphertext, a list of recipient devices** (everyone we hold a delivery key for goes sealed in one request with no token; the rest identified; a sealed request refused is retried person by person and a refused person is sent identified, LIME-96-fix). The `thread_root` and the Markdown are inside, so **threads and formatting work in groups** unchanged.
- **Rotation.** The session is replaced **on any membership change** (the replay marks it), **after 100 messages, and after 7 days**; its key goes to the members who do not have it before the message is sent. A removed member never gets the new key, so **cannot read what follows**; a person added gets only the current session, so **cannot read what came before** (a test hands each of them a copy of the earlier ciphertext). **Honest limits:** a member who has not yet heard of a removal still uses the old session until they do, so the removed person can read that; and a member whose master key changed and who has not been accepted in their own 1:1 chat is **left out of that send** (they must be accepted there).
- **Receiving.** A group message is read with the inbound session it names; **whose message it is comes from the session** (the device that shared it, verified then), and the signed envelope inside must say the same, with a certificate chaining to the master key pinned for that person. One whose session key has not arrived waits in `pending_inbound` as `no_session`; one for a group whose create op has not arrived waits as `no_group`; **both are retried on every sync and read when the missing piece arrives**. A message from before a late joiner's first key is `decrypt_failed` and never shown.
- **Requests.** A group is `pending` (in Requests, with Accept and Block) when the person who made or added us is not an accepted contact, and `accepted` straight away when they are. Leaving, or being removed, marks the conversation `left`: it disappears from Messages, nothing more is stored from it, and being added back brings it back. **System lines** ("Jean added Lee") are written into the timeline from the replayed state (so a late op that changes the outcome changes them) and are not messages (no unread, no notification, not searched).
- **Not in this brief:** invite links and QR (LIME-97b), group calls, group photos (an emoji only), an ownership-transfer screen (the owner can make admins; succession is automatic), push, and a replaced phone rejoining a group by itself (it must be removed and added again).

### 11.x In-person verification (LIME-97b; client only, no server change)

A teacher's QR code is `https://limechat.org/u/<username>?k=<20 hex digits>`: the invite link plus the first ten bytes of SHA-256 of the account's master public key (the same fingerprint Settings shows). The scanning phone looks the username up (`users-find`), fetches the master key the server serves (`users-devices`) and compares fingerprints on the device. On a match the peer is pinned (as for any first contact) and marked `verified_at` in the local `peers` table; accepting a different master key later clears it. The server learns nothing new (the same two calls any chat start makes) and never sees the code.
