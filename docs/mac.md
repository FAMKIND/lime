# lime for Mac

The Mac app: lime's chat list and conversation side by side, with a Mac menu bar.

Status: LIME-603: one window with the Messages list on the left and the selected chat on the right, a Mac menu bar, signed in as Ada Mac (Debug test account only).

Build entry points: `mac/build-core.sh` (LimeCore), `mac/generate.sh` (project), `mac/run.sh` (build + sign in as Ada Mac + open), `mac/test.sh` (UI test).

## Building the core

```
mac/build-core.sh              # builds LimeCore for the Mac
mac/tools/selftest/build.sh    # builds and runs the self-test on this Mac
```

Outputs (all gitignored): `mac/Frameworks/LimeCoreFFI.xcframework` with two slices, `macos-arm64` (deployment target macOS 14.0) and `ios-arm64-maccatalyst` (iOS 17.0 equivalent); the Swift bindings in `mac/Lime/Generated/`. The module is `LimeCoreFFI`, as on iOS. Apple silicon only. The script adds the two Rust targets locally with `rustup target add` (the pinned `core/rust-toolchain.toml` is not edited). The self-test prints `lime core <version>` and `Encryption self-test: passed`, and exits 0 (1 on failure).

Linking to your phone: waiting for DESIGN-M1; until then the Mac app signs in only as the Mac staging test accounts.

## Test accounts and the partner

Three throwaway staging accounts: `mac-a/b/c@example.invalid` = Ada Mac (`ada_mac`), Ben Mac (`ben_mac`), Cleo Mac (`cleo_mac`). Never the real account, never Android's.

```
mac/tools/staging-test-accounts.sh            # create/reuse all three; fresh sessions in ~/.lime/mac-test-accounts.json (chmod 600)
mac/tools/staging-test-accounts.sh --rotate-passwords   # NEW passwords: ends every session of the three accounts (the app's and the partner's)
mac/tools/staging-test-accounts.sh --delete   # delete them and the file
mac/tools/partner/build.sh                    # build the partner (needs mac/build-core.sh first)

P=mac/tools/partner/build/partner
$P --as c send --to ben_mac "hello from Cleo"   # --as b|c
$P --as b echo                                  # until stopped: accepts requests, replies: Ben here: got "<first 40 chars>"
$P --as c inbox --from ben_mac                  # sync once, accept requests, print what arrived
$P --as b status                                # short device-id prefix: the same each run = no new registration
$P --as b reset                                 # forget the store (when Ada's app signs in on a new Mac)
```

The partner's encrypted store and its key live in `~/.lime/mac-partner/<a|b|c>/` (outside the repo, key chmod 600; test tooling only). The first message to someone is a chat request on their side: `echo` and `inbox` accept it. Mind the staging limit of 10 device registrations per account per hour.

**Sessions and order (LIME-606).** Each account's password is kept in `~/.lime/mac-test-accounts.json` (chmod 600, outside the repo) and reused, so running the script, `run.sh` or `test.sh` again signs in again with the same password. On staging that does **not** end the sessions already open (probe: two password sign-ins, the first one still refreshes); only a password change does. So the order no longer matters: start the partner before or after `run.sh`. `--rotate-passwords` (or an account whose stored password stopped working) makes a new password and **ends every session**: the script says so, and a running partner prints `echo: sync failed: Unauthorized` and exits non-zero with "Ben's session ended: run mac/tools/staging-test-accounts.sh, then restart the partner". Any other failed sync, accept, queue or deliver prints one line (`echo: sync failed: <error>`; the same line twice in a row once).

## The app (LIME-603)

Mac Catalyst, "Optimize Interface for Mac" (macOS 14+, Apple silicon, App Sandbox on), compiling `ios/Lime` by reference plus `mac/Lime/` (Mac-only Swift).

```
mac/run.sh     # build Debug, hand Ada Mac's tokens to the app, open it  (then, in a second tab: mac/tools/partner/build/partner --as b echo)
mac/test.sh    # the UI test (LimeMacUITests) against staging, as Ada Mac, with the partner answering as Ben Mac
```

- **No real sign-in.** Signed out, the window says "lime on your Mac links to your phone. Coming soon." A Debug build also has "Use a test account"; `mac/run.sh` hands Ada Mac's tokens (no password) over in a file in the app's container, and the app signs in through the same session code iOS uses and deletes the file. Any account that is not one of the three Mac test accounts is refused. Each `run.sh` signs the test accounts in again with their stored passwords, which ends no session; the order of `run.sh` and the partner does not matter.
- **Idiom.** `Config/Info.plist` sets `UIUserInterfaceIdiomMac` and `UIGlobalUserInterfaceIdiomMac`; `TARGETED_DEVICE_FAMILY "2,6"` alone gave the scaled iPad idiom (the window drew at 77%).
- **Signing.** Automatic, with the team from the gitignored `mac/Local.xcconfig` (a copy of `ios/Local.xcconfig`). The Keychain under the sandbox needs `keychain-access-groups` (without it: error -34018).
- **Generate-time patches.** `mac/generate.sh` writes patched copies of two `ios/` files (see TEND-MAC.md "Stand-ins") into the gitignored `mac/Lime/Generated/`.
- **Menu bar.** lime (About, Hide, Hide Others, Show All, Quit; no Settings), File (Close), Edit (system), View (Hide Sidebar ⌃⌘S, Enter Full Screen), Chat (Next Chat ⌘], Previous Chat ⌘[), Window (system), Help (system).
- **Shown:** the Messages list (pinned and unread numbers, as on the phone), a Requests entry when there are requests, the chat beside it, threads, group details and profiles pushed in the chat pane. **Hidden for now:** new message, search, filters, swipe actions, Calls, Jam, bands, Settings and Lock lime, calls UI, the mesh.
- Screenshots: `docs/design/mac/first-window-light.png`, `first-window-dark.png`.

## Linked devices: what exists and what's missing (LIME-604)

A read-only survey (2026-11-15) of `core/src/`, `supabase/functions/`, `supabase/migrations/`, `docs/api-v2.md` for DESIGN-M1 (up to 5 devices per account, master key on every device (K2), 45 days of history, a linked device stays signed in). Nothing was run against staging; `cargo test` was run. Paths are from the repo root; "not checked" means not traced or not readable without secrets.

**What a device is today:** one device id + one Olm account + (the first device) the account's master key, made together by `AccountState::create` (`core/src/keys.rs:38`) and registered by `register_device` (`core/src/client.rs:138`). The server already holds many devices per user (`devices`, indexed by user: `supabase/migrations/20261006120000_api_v2_core.sql:30`) and every sender already fans out to all of a recipient's non-revoked devices. What is missing is almost entirely on the account's own side.

### 1. Sending to my own other devices: **no**
- A message to myself is marked sent and never leaves the phone (`core/src/client.rs:288-289`). A 1:1 send goes to the *recipient's* devices only (`send_op_counted`, `core/src/client.rs:825`); a group send excludes me (`core/src/client/groups.rs:635`, and the audience at `:506`).
- Receiving refuses anything whose sender is me (`sender != me`, `core/src/client.rs:1632`), so even a copy that arrived would be dropped.
- Edits, deletes and reactions (`is_message_op`, `core/src/store/message_ops.rs:26`) are ops sent to the other party only. Read state, chat settings, blocks, Notes to self, drafts you did not share: local to the device (nothing sends them anywhere). Co-written drafts (`core/src/client/draft_sync.rs`) go to *authors*, up to five, pairwise: not to my other devices.
- Gap: **core (existing file)** `client.rs`/`groups.rs`: also encrypt each outgoing op to my own other devices (a "sync" fan-out) and accept sender == me from my own device; **core (new file)** `client/own_devices.rs`: the rules for which ops echo (messages, edits, deletes, reactions, read marks, blocks, chat settings, Notes to self).

### 2. Receiving on every device: **yes** for 1:1 and groups, **partly** for jam and bands
- 1:1: `recipient_devices` asks `users-devices` for every non-revoked device and `send_op_counted` makes one Olm ciphertext per device (`core/src/client.rs:1403`, `:825`; server list `supabase/functions/users-devices/index.ts:18-22`). `send` checks the sender's `expect` list and answers 409 `devices_changed` when a device appeared, after which the sender retries with the new device (`supabase/functions/send/index.ts:9-16`, `:151`; `core/src/client.rs:1087`).
- Groups (Megolm): the member key in `ensure_group_session` includes the device list, "a new device is a change: the session is replaced and given to it" (`core/src/client/groups.rs:681`, LIME-270). So a device that appears later gets the next session. **It does not get the history** of earlier messages (`queue_group_history`, `:528`, is queued per *user* for a new member or a key reset, not for a new device).
- Jam and bands: a post notice is one Megolm ciphertext fanned out to every subscriber *device* (`docs/api-v2.md:132`); a band's members are a private group (`core/src/client/org.rs:1`), so groups apply. A subscriber's second device gets the notices but the tier session keys arrive in `jam.welcome`, an answer to a `jam.subscribe` that the first device made: not traced further, **not checked** whether a second device would hold the key. The writer rotates tier sessions on removal, 100 posts and 7 days, "never on a join" (`docs/api-v2.md:132`).
- Gap: **core (existing file)** `jam.rs`: welcome (state, session keys) for a new device of an existing subscriber; **core (new file)** group history for a new device of an existing member.

### 3. The delivery key: **breaks for a second device**
- What it is: one random 32-byte key per *account*, made on first use (`core/src/store/delivery.rs:75`), shared with contacts inside encrypted chats (`share_key_with`, `core/src/client.rs:1221`). From it both sides derive an Ed25519 pair; the server stores *one row per user*: the hash and the public key (`delivery_access`, `user_id` is the primary key, `supabase/migrations/20261006120000_api_v2_core.sql:66-67`; upload `supabase/functions/delivery-access-set/index.ts:30-35`).
- What breaks: a second device that has no key makes its **own** at `register_device` (`core/src/client.rs:179`, `ensure_delivery_access` `:1181`) and **overwrites the account's row**. Every contact still holds the first key, so every sealed send is signed wrongly, gets 403 (`core/src/client.rs:939`), is marked denied and falls back to an identified send (the sender is then visible to the server); the new device holds no contact's key either, so it also sends identified. It stays that way until each contact re-shares.
- Gap: the delivery key and the contacts' delivery keys (`contact_delivery_keys`) must travel in the link package, and `register_device` must not make a key on a linked device: **core (existing file)** `client.rs`/`store/delivery.rs`. A block rotates the key (`delivery.rs:97`): after that, the new key must reach every linked device (**core (new file)**: a "key changed" op to my own devices, or the sync fan-out of item 1).

### 4. Registering a second device with the same master key: **works server-side; a phone may register it for the new device**
- `devices-register` (`supabase/functions/devices-register/index.ts`): needs a *verified* session (`requireUser`: password and emailed code, `_shared/db.ts:55`); checks the master-key signature over `lime-device-v1\n<device_id>\n<identity_key>\n<signing_key>` (`:51-55`); inserts the master key if none (ignore-duplicates, `:60`); **the same master key = "changes nothing"**: it only inserts the new device row (`:84-92`); a **different** master key replaces the account's keys and revokes every device (`:64-74`, `reset_account_keys`, `supabase/migrations/20261007000000_key_reset.sql:32-50`).
- Nothing ties the request to the device being registered: any verified session of the account plus a master-key signature is enough, and `device_id`/keys come from the body. So a phone *can* register another device's keys on its behalf (it must hold the master key: K2), or the new device registers itself with its own session. The new device's own signature is not required: **the master key vouches** (the Olm keys are only bound by it).
- One-time keys: `keys-upload` uses `requireUser` + `requireDevice(userId, body.device_id)` (`supabase/functions/keys-upload/index.ts:10-12`), which checks only that the device belongs to the *user*, not to the *session*: any verified session of the account can upload keys for any of its non-revoked devices. The private halves exist only in the new device's Olm account, so the new device must make them: it needs *a* verified session of its own anyway, and the 10 registrations per hour limit applies per user (`_shared/config.ts:41`).
- Gap: **core (new file)** `client/link.rs`: `AccountState::create_linked(master_secret, ...)` (item 6), the link package, the new device's registration; **server**: none needed for the happy path (but see item 9).

### 5. Revoking one device: **no path** (only "revoke all")
- The only code that sets `devices.revoked_at` is `reset_account_keys` (all devices, and it deletes their mailbox items and one-time keys: `supabase/migrations/20261007000000_key_reset.sql:36-47`). `docs/api-v2.md:218` item 9 says the flow "is not specified". The server already *honours* a revocation everywhere: not listed (`users-devices`), 403 on `requireDevice` (`_shared/db.ts:80-91`), 404/410 on `send` (`send/index.ts:94-111`), and a sender drops it on 410.
- A `devices-revoke` function would need: a verified session and a proof from the master key (a signature over `lime-revoke-v1\n<device_id>`, so a stolen session alone cannot revoke), then `update devices set revoked_at`, `delete from mailbox_items where to_device`, `delete from one_time_keys where device_id`, and a nudge. It must not allow the last device to be revoked.
- Core on a revoke: groups rotate by themselves (the device list is part of the session fingerprint, `groups.rs:681`), but **jam tier sessions rotate only on a subscriber removal**, not on a device revoke; the revoked device itself needs to see its 403 and wipe (the app's handling of `forbidden` from the mailbox is **not checked**); the remaining devices must stop encrypting to it (the 409/410 path already does).
- Gap: **server** `devices-revoke` function + migration; **core (existing file)** `jam.rs`: rotate on a device revoke; **core (new file)** `client/link.rs`: `revoke_device`, "this device was removed" state; **iOS UI / Android UI / Mac UI**: the device list.

### 6. The master key on more than one device (K2): **core assumes one holder**
- `AccountState::create` makes a *new master key for every fresh device* (`core/src/keys.rs:38-49`, "this is the account's first device"); `load_or_create_account` (`core/src/client.rs:750`) calls it for an empty store; the secret is stored as base64 in the `account` table (`core/src/store/account.rs:58`) and signs each device cert (`keys.rs:62`). There is no way to create a device with an *existing* master secret, and nothing else in core uses the master secret.
- A device that registers with a different master key resets the account (`devices-register/index.ts:64`) and contacts get the "keys replaced" notice; contacts' pinned master (`pin_master_key`, `core/src/store/account.rs:224`) stays valid when the master is shared, so sharing it causes **no** key-change prompts for anyone.
- `Move` (`core/src/client/transfer.rs`) copies the whole store, master secret and device id included: a move *is* the same device on a new phone and the old phone then deletes itself (`transfer_confirm`, `:340`). A link is a *new device with the same master*, so it cannot reuse a move unchanged.
- Sharing the master touches: `keys.rs` (a constructor from a secret), `store/account.rs` (persist), the link package (the secret must travel only inside the encrypted link channel, like the store key in `transfer.rs`'s manifest), and the safety-number screen (the fingerprint is of the master and so is the same on all devices: good, `core/src/store/mod.rs:638`).
- Gap: **core (existing file)** `keys.rs`, `store/account.rs`, `client.rs`; **core (new file)** the link channel (X25519 + check code, reusing the pairing in `transfer.rs`).

### 7. History export (45 days): **whole store only; a cut is possible but not as is**
- `TransferOld::make_snapshot` copies the whole SQLCipher file with `sqlcipher_export` (`core/src/client/transfer.rs:374-386`): conversations, messages, attachments, sessions, keys, extras. No date filter.
- A partial export needs: a copy first (as now), then on the *copy* delete messages (and their attachments, reactions, threads, search rows, thread summaries) older than 45 days, drop empty conversations only if intended, `VACUUM`, then stream it. **It must also drop the Olm sessions and Megolm outbound sessions and the one-time/pickled account** (ratchets cannot be shared between two devices: both would use the same ratchet state), and keep the peers' pinned master keys, contacts' delivery keys and the user's settings.
- The history can also travel through the server (D4: one encrypted file): the same filtered copy, uploaded as a blob; not built (no function for it).
- Gap: **core (new file)** `client/link_export.rs`: filtered snapshot; **core (existing file)** `store/` helpers to delete by age; **server**: a blob class for it (D4); **Mac UI / iOS UI / Android UI**: "last 45 days" progress.

### 8. Sessions: **refresh works; what ends a session is partly not checked**
- Refresh: the app refreshes at launch if the token is expiring and one refresh is shared by calls that arrive together because "a refresh token is single-use" (`ios/Lime/Core/Auth/AccountSession.swift:104-109`, `:352-372`). A refresh that fails for any reason other than network/unavailable clears the saved session and signs out (`:114-118`). Offline, it carries on.
- What else signs a device out: a password change ends all sessions (`supabase/functions/_shared/auth.ts:73-75`), suspension and account deletion (403 `suspended`, `_shared/db.ts:68-77`), and a key reset (devices revoked; the revoked phone gets 403 from the mailbox). Whether the app signs out on a mailbox 403 `forbidden`: **not checked**.
- Settings: local `supabase/config.toml` has `jwt_expiry = 3600`, refresh-token rotation on with a 10 s reuse window (`:168`, `:174-177`), and `[auth.sessions]` (`timebox`, `inactivity_timeout`) **commented out** (`:285-289`), so no forced sign-out. **Staging's and production's settings: not checked** (dashboard, not in the repo).
- **Observed on staging in this lane (not read from the repo):** a fresh password sign-in for a test account ended the account's older sessions (`TEND-MAC.md`, LIME-603 "Debug test sign-in"). If production does the same, **linking a device would sign out the others**, which breaks "stays signed in". The cause (a Supabase "single session per user" setting, or something in the sign-in functions: `signin-password`/`code-verify` contain no sign-out call) is **not checked**.
- Gap: **server** (config): verify and, if needed, turn off single-session on staging and production; **core / iOS UI**: a clear "this device was removed" state on a 403 revoke.

### 9. The 5-device limit: **nowhere today; enforce at registration**
- Today: only a rate limit, 10 registrations per hour per user (`supabase/functions/_shared/config.ts:41`, `devices-register/index.ts:46`), and a sender accepts up to 100 devices in `expect` (`send/index.ts:39`).
- Enforce in `devices-register`, in the "new device" branch (`:84-92`): count the user's non-revoked devices and answer 409 `too_many_devices` for the sixth (a retry of an already-registered device stays 200). A row in a transaction (or a `devices` trigger) avoids two registrations racing past the limit.
- What the server learns: nothing new. It already stores every device and answers the list to anyone (`users-devices`), so the number is already known; the limit adds one refusal code.
- Gap: **server** (`devices-register` + migration), **iOS UI / Android UI / Mac UI**: the "5 devices" screen text.

### The three biggest gaps
1. **No own-device fan-out (items 1, 2):** nothing copies my sent messages, edits, deletes, reactions, read state or blocks to my other devices, and a message from my own device is dropped on receipt. Without it a linked device shows a different history from the phone.
2. **No "new device, same account" in core (items 3, 6, 7):** a device always makes its own master key and delivery key (a second one would overwrite the delivery key and push every contact to identified sends), and the only history copy is `Move`, which clones the device and its Olm sessions.
3. **No single-device revoke and no sign-in guarantee (items 5, 8):** the only revoke is "reset everything", and whether a new sign-in ends the other devices' sessions is unverified (it did on staging).

`cargo test` (core/): 564 passed, 0 failed.
