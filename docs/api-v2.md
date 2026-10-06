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
| `blobs` | Encrypted attachments: the id, the size, the uploader (for quota) and the expiry. |
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

**Blobs.** Upload and download of encrypted files through signed URLs, with the expiry rule from the cost principles (`architecture.md` section 10).

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

Things the decision did not settle. They are listed here rather than decided:

1. **Supabase limits.** Realtime and Edge Function limits at scale have not been verified; the first Supabase brief surveys them.
2. **The delivery-key HMAC construction.** The decision says the proof is an HMAC over the request, checked against the stored hash. The key derivation, what exactly is MACed (including freshness and replay protection), which hash the server stores, and how a device other than the first obtains the delivery key are not specified.
3. **The one-time-key pool size**, and when a device replenishes it.
4. **The rate-limit numbers:** per access token and per IP for sends, key claims, directory search, `POST /v2/turn` and the rest.
5. **The de-duplication window and the relay rule.** For how long the server remembers the hash of an outer ciphertext, and how a relaying phone (which also cannot see `op_id`) recognises an envelope it already carries.
6. **The `access` of an identified send.** Section 3 says it is "the sender's auth"; the exact credential, and what stops identified sends being used to flood a stranger, belong to the rate-limit and message-request work.
7. **The HLC and `parents[]` details:** the clock format, how many parents an op lists, and what a device does with an op whose parents it has not received yet.
8. **Acknowledgement semantics.** `POST /v2/mailbox/ack` deletes up to a cursor; what happens to a device that acknowledges and then loses the items before applying them is not specified.
9. **Device revocation.** `devices` records a revoked time; the flow that revokes a device, rotates Megolm sessions and stops its mailbox is not specified.
10. **The blob expiry rule and quotas.** The cost principles give "for example 30 days after every recipient has fetched them" as an illustration, not a number; the uploader quota is not specified.
11. **The verified-teacher badge** (D7 says "later") and any change it brings to `profiles`.
