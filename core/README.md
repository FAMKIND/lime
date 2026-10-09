# LimeCore

Lime's shared core, written in Rust. The iOS app links it through [UniFFI](https://mozilla.github.io/uniffi-rs/); Android and desktop follow later (see [`docs/architecture.md`](../docs/architecture.md), section 3).

It speaks Lime's API v2 ([`docs/api-v2.md`](../docs/api-v2.md)) and wraps [vodozemac](https://github.com/matrix-org/vodozemac) (Olm and Megolm) and, since LIME-90, owns the app's **encrypted local store**: SQLite encrypted at rest with SQLCipher. The network is the platform's (see Transport below), and the Olm keys are persisted inside the store.

## FFI surface

Two functions and one object. No secret material crosses the FFI or is logged.

- `core_version() -> String`: the crate version.
- `encryption_self_test() -> SelfTestReport { olm_ok, megolm_ok, detail }`: two in-memory Olm accounts and a session round-tripping a message both ways, then a Megolm group session round-tripping a message. `detail` is a short line with no key material.

- `LimeStore`, the encrypted store (thread-safe):
  - `LimeStore.open(path, key)` opens (creating if needed) the database with a raw 32-byte key and migrates it. A wrong key fails with `StoreError::WrongKeyOrNotADatabase`.
  - `seed_sample_data_if_empty()` inserts the made-up teachers, groups and messages (`src/store/sample.rs`) into an empty store.
  - `list_conversations()`, `list_messages(conversation_id)`, `send_local_message(conversation_id, text)`.
  - `StoreError` is a small enum; no key material is ever in an error or a log.

In Swift these are `coreVersion()`, `encryptionSelfTest()` and `LimeStore`. In the app, long-press the logo on Messages to see "About Lime" run the test.

## The protocol (LIME-93)

Two LimeCore instances, as two different accounts, exchange an Olm-encrypted message through the server. Scope: 1:1 chats over Olm: message requests, key changes, threads, and (LIME-96) **sealed sender** for contacts who shared their delivery key. No Megolm or groups yet.

FFI additions (on `LimeStore`, plus one function):

- `register_device(transport, auth_token) -> DeviceInfo`: creates this device's keys on first use, registers the device (idempotent), and tops up its one-time keys (upload 50; top up below 20).
- `queue_text(conversation_id, text)` writes a message as `sending` (its op id, clock and parents fixed) and returns it at once; `deliver_queued(transport, auth_token)` sends everything waiting, oldest first, marking each `sent` (a failure marks it `failed` and stops, keeping the order); `start_dm(user_id, display_name)`, `accept_request`, `block_sender`, `mark_read`; `trust_new_key(conversation_id)` and `retry_message(message_id)` (a changed contact key, and a message that was not delivered); `find_user(transport, auth_token, query)` (an exact username or email, public fields only). Conversations carry a `request_state` (`pending`, `accepted`, `blocked`); a stranger's first message is `pending`, and a blocked sender's new messages are read and dropped. Messages are listed in causal order (`parents`, then clock, then op id).
- `send_text_identified(transport, auth_token, recipient_user_id, text) -> MessageItem` (queue plus deliver in one call): looks up the recipient's devices and verifies their cross-signatures (pinning their master key on first use), claims one-time keys, starts or reuses an Olm session per device, and sends the signed op.
- `sync(transport, auth_token) -> SyncReport { received, pending }`: fetches the mailbox and writes **every item to `pending_inbound` before acknowledging it**, then decrypts and verifies what it can and stores each message in a DM with the sender (titled with their user id for now). An item that cannot be read yet (no session for a normal Olm message), a sealed item that cannot be checked (see below), or one that is invalid stays in `pending_inbound` with its reason and attempt count; the readable ones are retried on every sync and when a new session appears, and nothing is dropped silently.
- `lookup_user_by_email(transport, auth_token, email) -> Option<String>`: an exact, case-insensitive email match; the user id only.

**Sealed sender (LIME-96).** `store/delivery.rs`: each account has a random 32-byte delivery key (in the encrypted store), uploaded as `SHA-256(HKDF-SHA256(key, "lime-access-v1"))` with `delivery-access-set` at registration (and again when a block rotated it). It is given to a contact in a `delivery_key.share` control op (a signed op over the same Olm session, never shown as a message) when you Accept, start a chat, Unblock, accept their changed key, and after a rotation. A message to someone whose key you hold is sent **sealed** (no Authorization header; `access = { sealed: access_key }`); otherwise identified. A sealed send refused with 403 is sent identified at once, silently (it reads "Sent"), and no sealed send to that contact is tried until they share a new key. **Block** rotates the key (if the blocked person had it) and re-shares with every accepted contact but them. A sealed item is believed only if its certificate chains to the master key already pinned for the person it names (otherwise it is kept as `invalid`, never shown, and never a key-change prompt). `sealed_contact_count()` is for a Debug-only row in About. Keys never appear in an error or a log.

**Profile photos (LIME-98b, LIME-98b-fix).** `store/photos.rs` and `client/photos.rs`: my photo is public (a plain JPEG) or contacts-only (AES-256-GCM under a key from my *profile key*, stored under an id derived from it); the profile key travels with the delivery key and rotates on a block. When my photo changes, each accepted contact is sent a small encrypted `profile.changed { photo_version }` control op (sealed where possible); their next `sync` marks my photo due and the next refresh fetches it at once, bypassing the hourly limit. `refresh_photos(force)` is the hourly pass; `refresh_photos_of(ids)` (pull-to-refresh, opening a chat) checks the given people but never one more than once a minute.

> **Never sign out to refresh data: sign-out deletes keys.** To see a change on another phone, sync (pull to refresh); to test, use two accounts on two devices and leave them signed in.

**Attachments (LIME-98c).** `store/attachments.rs` (the descriptor, chunked AES-256-GCM, storage in `message_attachments`) and `client/attachments.rs`: `send_attachments(conversation, caption, items, reply_to)` keeps the files in the encrypted store and queues the message; `deliver_queued` first uploads each file chunk by chunk (resuming, because the same chunks are computed again and the server says which it holds), then sends the message that carries the keys. `download_attachment` fetches, decrypts, checks the SHA-256 and keeps the file; `attachment_data` reads it. A received message with a malformed attachment is invalid; a tampered chunk or a wrong digest is refused and nothing is kept.

**Group chats (LIME-97).** `protocol/group.rs` is the pure rules (the ops `group.create / add / remove / leave / rename / set_avatar / set_role`, authority, the concurrent-remove-beats-add rule, owner succession, a 100-member cap, a 50-character name), replayed from the log of signed ops in `(hlc, op_id)` order so every device reaches the same state; `store/groups.rs` is the storage around it (the op log, the derived members and conversation, system lines, the outbox, and the Megolm sessions); `client/groups.rs` is the client: `create_group`, `group_details`, `add_group_members`, `remove_group_member`, `rename_group`, `set_group_emoji`, `set_group_admin`, `leave_group` (all local; the next delivery sends them), the delivery of state ops and `group.session` key shares over Olm (sealed where we hold the person's key), one Megolm ciphertext per group message to every member device, rotation on any membership change / 100 messages / 7 days, and the receiving side (a message waits as `no_session` or `no_group` until its key or its group arrives). The server holds no group state. See `docs/api-v2.md` section 11.

Modules: `keys` (the Olm account and master key), `protocol` (the signed op and sealed inner, canonical bytes, the hybrid logical clock), `client` (the calls above), `transport` (the callback), `store/account.rs` (the persisted state).

**Keys are persisted inside the SQLCipher store.** The Olm account and the Olm sessions are vodozemac pickles encrypted with a key derived from the store key (HKDF-SHA256, info `lime-pickle-v1`). The account's master signing key is stored in the same encrypted database as base64 (vodozemac has no pickle format for a bare Ed25519 key). Nothing is logged, and no key leaves the device.

**Transport.** The platform's network is a UniFFI callback interface, so the protocol (what to call, signing, encrypting, state) stays in Rust while Swift (`URLSession`) and later Kotlin (OkHttp) make the requests. `request(method, path, headers, body)` is blocking and returns a status and a body; a network failure is a `TransportError`. The platform adds the base URL and the public `apikey` header; the user's token is passed in by the platform per call and the core never stores passwords or tokens. See `ios/Lime/Core/Network/URLSessionTransport.swift`.

## Integration tests

`tests/integration.rs` runs against a real Supabase stack with two throwaway accounts (created and deleted through the admin API): register both, look up by email, send, check that the server's copy is ciphertext, sync, decrypt, reply, acknowledge, send again on the established sessions, and survive a restart; plus a test that a ciphertext tampered with on the server is not stored.

```bash
./core/run-integration.sh            # the local stack (starts it if needed)
./core/run-integration.sh staging    # the staging project (needs `supabase login` and ~/.lime/staging.env)
```

It uses the `integration` cargo feature and reads the URL and keys from the environment only; nothing secret is written down.

## The store

`src/store/` has the schema (`migrations.rs`, versioned with `PRAGMA user_version`, forward-only), the sample content and the tests. Tables are the local view only: `people`, `conversations`, `members`, `messages` (a UUIDv7 id made by the core, the display time, and `local_state`, `sent_local` for now). The v2 fields that come later (signature, hybrid logical clock, parents) are noted in a comment in `store/mod.rs` and are deliberately not columns yet. On iOS the app generates the key, keeps it in the Keychain and puts the file in Application Support; see `ios/README.md`.

SQLCipher is compiled in by `libsqlite3-sys` (feature `bundled-sqlcipher`), using Apple's CommonCrypto on Apple targets; leave `OPENSSL_DIR` unset.

## Prerequisites

Rust through rustup (user-level, no `sudo`):

```bash
brew install rustup
rustup-init -y --no-modify-path
```

The toolchain (1.99.0) and the iOS targets are pinned in `rust-toolchain.toml`; rustup installs them the first time `cargo` runs in this folder. Xcode is needed for the iOS build.

## Commands

```bash
cd core
cargo test                           # Olm, Megolm, the store, the protocol (signatures, canonical bytes, persistence)
cargo clippy --all-targets -- -D warnings
./build-ios.sh                       # static libs for iOS and the simulator, Swift bindings, xcframework
```

`build-ios.sh` writes `ios/Frameworks/LimeCoreFFI.xcframework` and `ios/Lime/Core/Generated/lime_core.swift`. Both, and `core/target/`, are gitignored and rebuilt from source. `ios/generate.sh` runs the script first, so normally you just run that. The project links the xcframework and compiles the generated Swift; there is no Xcode build-phase script.

The simulator build is Apple-silicon only (`aarch64-apple-ios-sim`); the iOS project excludes `x86_64` simulators.

## Licences

See [`THIRD_PARTY.md`](./THIRD_PARTY.md).

## Search (LIME-99)

`search_messages(query, conversation_id?, limit)` and `search_conversations(query)` read only the local database; neither takes a transport. Messages are indexed in an **FTS5** table (`message_fts`, migration 7) inside the SQLCipher file, kept in step by triggers on insert, edit and delete and filled from existing messages by the migration. The tokenizer is `unicode61` with `remove_diacritics 2`, so matching is case- and accent-insensitive; every typed word is a prefix and all must match; punctuation is dropped before the query is built, so typing cannot produce FTS syntax. Results across chats are best match first, then newest; inside one chat they are oldest first (for stepping). A snippet marks matched words with U+E000 and U+E001. Blocked conversations are never searched. FTS5 was already compiled into the bundled SQLCipher (`libsqlite3-sys` sets `SQLITE_ENABLE_FTS5`), so nothing was added to the build; `PRAGMA temp_store = MEMORY` keeps temporary tables off disk. Conversations are found through a throwaway in-memory FTS table of titles and people's names.

## Message formatting (LIME-100)

`format.rs` holds the one grammar of the message Markdown subset (`docs/message-format.md`): `parse_message_markdown(text) -> [Block]` (paragraphs of styled spans, lists with one nesting level, code blocks), `message_markdown_from_blocks(blocks) -> String` (the one written form), `message_plain_text(text)` (the words without markup) and `normalise_message_markdown(text)`. `queue_text` and an incoming message are both normalised, the size limit (30,000 bytes) applies to the written form, and each message keeps its `plain` words (migration 8) for the search index and previews.

## Reply threads (LIME-101)

A reply carries `thread_root` inside the encrypted payload (`queue_reply(conversation_id, root_id, text)`; replying to a reply answers the same root). Replies are kept out of `list_messages` (the main timeline); `list_thread(root_id)` returns the root then its replies in causal order; `list_thread_summaries(conversation_id)` gives each thread's reply count, newest reply time, up to three repliers and unread count; `mark_thread_read(root_id)` clears it. A reply's `parents[]` are the thread's heads. Migration 9 adds `messages.thread_root` and `thread_state`. A search hit in a reply carries `thread_root`.
