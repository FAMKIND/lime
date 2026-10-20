//! Forward-only schema migrations, versioned with `PRAGMA user_version`.
//! Never edit a released migration; append a new one.

use rusqlite::Connection;

use super::StoreError;

const MIGRATIONS: &[&str] = &[
    // 1: the local view.
    "CREATE TABLE people (
         id   TEXT PRIMARY KEY NOT NULL,
         name TEXT NOT NULL,
         tone INTEGER NOT NULL
     );
     CREATE TABLE conversations (
         id        TEXT PRIMARY KEY NOT NULL,
         title     TEXT NOT NULL,
         is_group  INTEGER NOT NULL,
         is_pinned INTEGER NOT NULL DEFAULT 0,
         unread    INTEGER NOT NULL DEFAULT 0
     );
     CREATE TABLE members (
         conversation_id TEXT NOT NULL REFERENCES conversations(id),
         person_id       TEXT NOT NULL REFERENCES people(id),
         position        INTEGER NOT NULL,
         PRIMARY KEY (conversation_id, person_id)
     );
     CREATE TABLE messages (
         id              TEXT PRIMARY KEY NOT NULL,
         conversation_id TEXT NOT NULL REFERENCES conversations(id),
         sender_id       TEXT NOT NULL REFERENCES people(id),
         body            TEXT NOT NULL,
         sent_at         INTEGER NOT NULL,
         local_state     TEXT NOT NULL
     );
     CREATE INDEX messages_by_conversation ON messages (conversation_id, sent_at);",
    // 2: the protocol state (LIME-93): this device's keys, its Olm sessions, pinned master keys,
    // and the op id and hybrid logical clock of messages that came through the protocol.
    "CREATE TABLE account (
         id            INTEGER PRIMARY KEY CHECK (id = 1),
         olm_pickle    TEXT NOT NULL,      -- vodozemac pickle, encrypted with a key derived from the store key
         master_secret TEXT NOT NULL,      -- the master signing key (base64), inside the encrypted database
         device_id     TEXT NOT NULL,
         user_id       TEXT,
         registered    INTEGER NOT NULL DEFAULT 0,
         hlc_wall      INTEGER NOT NULL DEFAULT 0,
         hlc_counter   INTEGER NOT NULL DEFAULT 0
     );
     CREATE TABLE olm_sessions (
         peer_user_id      TEXT NOT NULL,
         peer_device_id    TEXT NOT NULL,
         peer_identity_key TEXT NOT NULL,
         session_pickle    TEXT NOT NULL,  -- vodozemac pickle, encrypted as above
         created_at        INTEGER NOT NULL,
         updated_at        INTEGER NOT NULL,
         PRIMARY KEY (peer_user_id, peer_identity_key)
     );
     CREATE TABLE peers (
         user_id    TEXT PRIMARY KEY NOT NULL,
         master_key TEXT NOT NULL          -- trust on first use
     );
     ALTER TABLE messages ADD COLUMN op_id TEXT;
     ALTER TABLE messages ADD COLUMN hlc TEXT;
     CREATE UNIQUE INDEX messages_by_op_id ON messages (op_id) WHERE op_id IS NOT NULL;",
    // 3: every fetched mailbox item is kept here BEFORE it is acknowledged, and removed only once it
    // has been turned into a message. Nothing the server delivered is ever dropped silently.
    "CREATE TABLE pending_inbound (
         id           INTEGER PRIMARY KEY AUTOINCREMENT,
         cursor       INTEGER NOT NULL UNIQUE,   -- the server's cursor for this device's mailbox
         sender_user  TEXT,                      -- only for an identified item
         identified   INTEGER NOT NULL,
         ciphertext   TEXT NOT NULL,             -- base64, exactly as fetched
         received_at  TEXT,
         reason       TEXT NOT NULL,             -- new, no_session, decrypt_failed, sealed_unsupported, invalid, key_mismatch
         attempts     INTEGER NOT NULL DEFAULT 0,
         first_seen   INTEGER NOT NULL,
         last_attempt INTEGER
     );",
    // 4: message requests and causal ordering (LIME-95). A conversation is `pending` (a stranger's
    // first message: it waits in Requests), `accepted`, or `blocked` (hidden; its new messages are
    // not stored). `parents` is the JSON list of op ids the sender had seen (api-v2.md section 5).
    "ALTER TABLE conversations ADD COLUMN request_state TEXT NOT NULL DEFAULT 'accepted';
     ALTER TABLE messages ADD COLUMN parents TEXT;",
    // 5: key changes and delivery notices (LIME-95-fix). `new_master_key` is a different master key
    // a person has been seen with since we pinned theirs: nothing from or to them moves until the
    // person accepts it. `message_deliveries` remembers the hash of each ciphertext we sent, so a
    // later \"not delivered\" notice from the server can be matched to the message.
    "ALTER TABLE peers ADD COLUMN new_master_key TEXT;
     -- An item held back for a changed key was already decrypted (a message cannot be decrypted
     -- twice), so its plaintext waits here, inside the encrypted database, until the key is accepted.
     ALTER TABLE pending_inbound ADD COLUMN plaintext BLOB;
     ALTER TABLE pending_inbound ADD COLUMN peer_identity TEXT;
     CREATE TABLE message_deliveries (
         hash       TEXT PRIMARY KEY NOT NULL,   -- hex SHA-256 of the outer ciphertext, as the server hashes it
         message_id TEXT NOT NULL
     );
     CREATE INDEX message_deliveries_by_message ON message_deliveries (message_id);",
    // 6: when this device's keys were made (Settings shows it). An account made before this version
    // gets the day it was upgraded: the exact earlier time was never recorded.
    "ALTER TABLE account ADD COLUMN created_at INTEGER;
     UPDATE account SET created_at = CAST(strftime('%s', 'now') AS INTEGER) * 1000;",
    // 7: on-device search (LIME-99). An FTS5 index over message text, inside this encrypted database
    // (so it is encrypted at rest like everything else), kept in step by triggers on insert, edit and
    // delete, and filled from the messages already here. unicode61 with remove_diacritics makes it
    // case- and diacritic-insensitive. The text is stored twice (here and in `messages`): a few
    // kilobytes per hundred messages, for a search that never leaves the phone.
    "CREATE VIRTUAL TABLE message_fts USING fts5(
         body,
         message_id UNINDEXED,
         conversation_id UNINDEXED,
         tokenize = 'unicode61 remove_diacritics 2'
     );
     INSERT INTO message_fts (body, message_id, conversation_id) SELECT body, id, conversation_id FROM messages;
     CREATE TRIGGER messages_fts_insert AFTER INSERT ON messages BEGIN
         INSERT INTO message_fts (body, message_id, conversation_id) VALUES (new.body, new.id, new.conversation_id);
     END;
     CREATE TRIGGER messages_fts_delete AFTER DELETE ON messages BEGIN
         DELETE FROM message_fts WHERE message_id = old.id;
     END;
     CREATE TRIGGER messages_fts_update AFTER UPDATE OF body, conversation_id ON messages BEGIN
         UPDATE message_fts SET body = new.body, conversation_id = new.conversation_id WHERE message_id = old.id;
     END;",
    // 8: formatted messages (LIME-100). `body` is the message as Markdown (what is shown and sent);
    // `plain` is the same words without the markup, which is what search indexes and previews show.
    // Messages from before have no `plain` and are indexed by their `body`, which was plain text.
    "ALTER TABLE messages ADD COLUMN plain TEXT;
     DROP TRIGGER messages_fts_insert;
     DROP TRIGGER messages_fts_update;
     CREATE TRIGGER messages_fts_insert AFTER INSERT ON messages BEGIN
         INSERT INTO message_fts (body, message_id, conversation_id) VALUES (COALESCE(new.plain, new.body), new.id, new.conversation_id);
     END;
     CREATE TRIGGER messages_fts_update AFTER UPDATE OF body, plain, conversation_id ON messages BEGIN
         UPDATE message_fts SET body = COALESCE(new.plain, new.body), conversation_id = new.conversation_id WHERE message_id = old.id;
     END;",
    // 9: reply threads (LIME-101). A reply carries `thread_root`, the id of the message it answers
    // (never itself a reply: replying to a reply answers the same root). Replies are kept out of the
    // main timeline. `thread_state` counts the replies in each thread not yet read.
    "ALTER TABLE messages ADD COLUMN thread_root TEXT;
     CREATE INDEX messages_by_thread ON messages (thread_root) WHERE thread_root IS NOT NULL;
     CREATE TABLE thread_state (
         root_id TEXT PRIMARY KEY NOT NULL,
         unread  INTEGER NOT NULL DEFAULT 0
     );",
    // 10: sealed sender (LIME-96). `delivery_state` is this account's own delivery key (kept inside the
    // encrypted database) and whether its hash is on the server; `contact_delivery_keys` are the keys
    // people shared with us (`denied`: a sealed send to them was refused, so none is tried until they
    // share a new key); `share_queue` is who still has to be sent my current key; `key_shared` is who
    // already has it. A message refused sealed becomes \"Not delivered\" (`sealed_denied`), and one tap
    // on it sends it identified once (`identified_once`).
    "CREATE TABLE delivery_state (
         id         INTEGER PRIMARY KEY CHECK (id = 1),
         key        TEXT NOT NULL,
         uploaded   INTEGER NOT NULL DEFAULT 0,
         rotated_at INTEGER NOT NULL
     );
     CREATE TABLE contact_delivery_keys (
         user_id     TEXT PRIMARY KEY NOT NULL,
         key         TEXT NOT NULL,
         denied      INTEGER NOT NULL DEFAULT 0,
         received_at INTEGER NOT NULL
     );
     CREATE TABLE share_queue (
         peer_user_id TEXT PRIMARY KEY NOT NULL,
         queued_at    INTEGER NOT NULL
     );
     CREATE TABLE key_shared (
         peer_user_id TEXT PRIMARY KEY NOT NULL,
         shared_at    INTEGER NOT NULL
     );
     ALTER TABLE messages ADD COLUMN sealed_denied INTEGER NOT NULL DEFAULT 0;
     ALTER TABLE messages ADD COLUMN identified_once INTEGER NOT NULL DEFAULT 0;
     -- Chats that were accepted before this version have not been given my delivery key: queue them all.
     INSERT OR IGNORE INTO share_queue (peer_user_id, queued_at)
         SELECT substr(id, 4), 0 FROM conversations WHERE id LIKE 'dm:%' AND request_state = 'accepted';",
    // 11: LIME-96-fix. A sealed send the server refuses is now sent identified at once, silently (and shows
    // \"Sent\"), so the two columns migration 10 added for a one-tap resend are not needed.
    "ALTER TABLE messages DROP COLUMN sealed_denied;
     ALTER TABLE messages DROP COLUMN identified_once;",
    // 12: group chats (LIME-97). `group_ops` is the log of signed group state ops (with the whole signed envelope,
    // so the log can be handed to someone newly added); a group's members, name and roles are worked out by
    // replaying it. `group_members` is that result, kept for quick reads. `group_outbox` is what still has to be
    // sent to each person. A group message is encrypted with a Megolm session: one outbound session per group
    // for this device (`group_outbound_sessions`, with who already has its key), and the inbound sessions other
    // members' devices shared with us (`group_inbound_sessions`, each tied to the device that made it).
    "CREATE TABLE group_ops (
         op_id       TEXT PRIMARY KEY NOT NULL,
         group_id    TEXT NOT NULL,
         op_type     TEXT NOT NULL,
         sender_user TEXT NOT NULL,
         hlc         TEXT NOT NULL,
         parents     TEXT NOT NULL,
         payload     TEXT NOT NULL,
         inner       TEXT NOT NULL,
         received_at INTEGER NOT NULL
     );
     CREATE INDEX group_ops_by_group ON group_ops (group_id);
     CREATE TABLE group_members (
         group_id TEXT NOT NULL,
         user_id  TEXT NOT NULL,
         role     TEXT NOT NULL,
         seq      INTEGER NOT NULL,
         PRIMARY KEY (group_id, user_id)
     );
     CREATE TABLE group_outbox (
         id             INTEGER PRIMARY KEY AUTOINCREMENT,
         group_id       TEXT NOT NULL,
         recipient_user TEXT NOT NULL,
         op_json        TEXT NOT NULL
     );
     CREATE TABLE group_outbound_sessions (
         group_id    TEXT PRIMARY KEY NOT NULL,
         pickle      TEXT NOT NULL,
         session_id  TEXT NOT NULL,
         created_at  INTEGER NOT NULL,
         messages    INTEGER NOT NULL DEFAULT 0,
         fingerprint TEXT NOT NULL,
         rotate      INTEGER NOT NULL DEFAULT 0,
         shared_with TEXT NOT NULL DEFAULT '[]'
     );
     CREATE TABLE group_inbound_sessions (
         session_id   TEXT PRIMARY KEY NOT NULL,
         group_id     TEXT NOT NULL,
         owner_user   TEXT NOT NULL,
         owner_device TEXT NOT NULL,
         pickle       TEXT NOT NULL
     );
     ALTER TABLE conversations ADD COLUMN group_emoji TEXT;",
    // 13: \"verified in person\" (LIME-97b): when this person's pinned master key was confirmed against a
    // QR code scanned in person. Cleared when a different key is accepted.
    "ALTER TABLE peers ADD COLUMN verified_at INTEGER;",
    // 14: profile photos (LIME-98b). `profile_key` is my random photo key, shared with accepted contacts
    // inside their encrypted chats (with the delivery key) and rotated on a block. `my_photo` is my own
    // photo (the JPEG, who may see it, and the key the contacts-only copy on the server was made with).
    // `photos` caches other people's photos in this encrypted file; an empty `bytes` means \"checked, none\".
    "CREATE TABLE profile_key (
         id         INTEGER PRIMARY KEY CHECK (id = 1),
         key        TEXT NOT NULL,
         rotated_at INTEGER NOT NULL
     );
     CREATE TABLE contact_profile_keys (
         user_id     TEXT PRIMARY KEY NOT NULL,
         key         TEXT NOT NULL,
         received_at INTEGER NOT NULL
     );
     CREATE TABLE my_photo (
         id           INTEGER PRIMARY KEY CHECK (id = 1),
         jpeg         BLOB,
         visibility   TEXT NOT NULL DEFAULT 'everyone',
         uploaded_key TEXT,
         updated_at   INTEGER NOT NULL
     );
     CREATE TABLE photos (
         user_id    TEXT PRIMARY KEY NOT NULL,
         bytes      BLOB NOT NULL,
         source     TEXT NOT NULL,
         version    INTEGER NOT NULL,
         checked_at INTEGER NOT NULL
     );",
    // 15: "my photo changed" notices (LIME-98b-fix): who still has to be told, so their phone refreshes it at once.
    "CREATE TABLE photo_notices (
         peer_user_id TEXT PRIMARY KEY NOT NULL,
         queued_at    INTEGER NOT NULL
     );",
    // 16: encrypted attachments (LIME-98c). One row per attachment of a message: the key and digest (they travel only
    // inside the encrypted message), the facts the bubble shows, a tiny thumbnail, and the decrypted bytes once this
    // phone has them (my own sends hold them from the start). The bytes live in this encrypted file.
    "CREATE TABLE message_attachments (
         attachment_id TEXT PRIMARY KEY NOT NULL,
         message_id    TEXT NOT NULL,
         position      INTEGER NOT NULL,
         key           TEXT NOT NULL,
         digest        TEXT NOT NULL,
         size          INTEGER NOT NULL,
         mime          TEXT NOT NULL,
         name          TEXT NOT NULL,
         width         INTEGER,
         height        INTEGER,
         duration_ms   INTEGER,
         thumb         BLOB,
         bytes         BLOB
     );
     CREATE INDEX message_attachments_by_message ON message_attachments (message_id, position);",
    // 17: resumable downloads and progress (LIME-98d). `attachment_parts` holds the ciphertext chunks already fetched of a
    // download that was interrupted (each is checked when the file is assembled), and `transfers` how far an upload or
    // download has got, for the progress ring.
    "CREATE TABLE attachment_parts (
         attachment_id TEXT NOT NULL,
         idx           INTEGER NOT NULL,
         bytes         BLOB NOT NULL,
         PRIMARY KEY (attachment_id, idx)
     );
     CREATE TABLE transfers (
         attachment_id TEXT PRIMARY KEY NOT NULL,
         direction     TEXT NOT NULL,
         done          INTEGER NOT NULL,
         total         INTEGER NOT NULL
     );",
    // 18: the QA round (LIME-104). A group's encrypted photo (blob id and key, from its signed `group.set_avatar` op), a manual
    // \"mark unread\", \"delete chat for me\" (the chat is hidden and its messages gone here; a new message brings it back), and
    // my private label for a contact (never sent anywhere).
    "ALTER TABLE conversations ADD COLUMN group_photo TEXT;
     ALTER TABLE conversations ADD COLUMN marked_unread INTEGER NOT NULL DEFAULT 0;
     ALTER TABLE conversations ADD COLUMN hidden INTEGER NOT NULL DEFAULT 0;
     CREATE TABLE contact_labels (
         user_id TEXT PRIMARY KEY NOT NULL,
         label   TEXT NOT NULL
     );",
    // 19: message actions (LIME-105). `edited` and `edit_hlc` (the clock of the newest edit), `deleted` (1: deleted for everyone,
    // a tombstone that keeps its place), `hidden` (1: deleted for me, gone from every list). `reactions` holds each person's
    // state per emoji (last writer wins by clock). `message_op_outbox` is the edits, deletes and reactions still to be sent;
    // `early_message_ops` those that arrived before the message they are about.
    "ALTER TABLE messages ADD COLUMN edited INTEGER NOT NULL DEFAULT 0;
     ALTER TABLE messages ADD COLUMN edit_hlc TEXT;
     ALTER TABLE messages ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0;
     ALTER TABLE messages ADD COLUMN hidden INTEGER NOT NULL DEFAULT 0;
     CREATE TABLE reactions (
         message_id TEXT NOT NULL,
         user_id    TEXT NOT NULL,
         emoji      TEXT NOT NULL,
         hlc        TEXT NOT NULL,
         active     INTEGER NOT NULL,
         PRIMARY KEY (message_id, user_id, emoji)
     );
     CREATE INDEX reactions_by_message ON reactions (message_id);
     CREATE TABLE message_op_outbox (
         id              TEXT PRIMARY KEY NOT NULL,
         conversation_id TEXT NOT NULL,
         op_type         TEXT NOT NULL,
         payload         TEXT NOT NULL,
         queued_at       INTEGER NOT NULL
     );
     CREATE TABLE early_message_ops (
         target  TEXT NOT NULL,
         op_type TEXT NOT NULL,
         sender  TEXT NOT NULL,
         hlc     TEXT NOT NULL,
         payload TEXT NOT NULL,
         PRIMARY KEY (target, op_type, sender, hlc)
     );",
    // 20: forwarding and link previews (LIME-106). A forwarded message says so (`forwarded`); a link preview's words are kept
    // as JSON (its picture is an attachment of role 'preview'). The same attachment can now be in several messages (a forward
    // shares the encrypted file by reference), so an attachment row is keyed by message and attachment.
    "ALTER TABLE messages ADD COLUMN forwarded INTEGER NOT NULL DEFAULT 0;
     ALTER TABLE messages ADD COLUMN link_preview TEXT;
     CREATE TABLE message_attachments_new (
         attachment_id TEXT NOT NULL,
         message_id    TEXT NOT NULL,
         position      INTEGER NOT NULL,
         key           TEXT NOT NULL,
         digest        TEXT NOT NULL,
         size          INTEGER NOT NULL,
         mime          TEXT NOT NULL,
         name          TEXT NOT NULL,
         width         INTEGER,
         height        INTEGER,
         duration_ms   INTEGER,
         thumb         BLOB,
         bytes         BLOB,
         role          TEXT NOT NULL DEFAULT 'file',
         PRIMARY KEY (message_id, attachment_id)
     );
     INSERT INTO message_attachments_new (attachment_id, message_id, position, key, digest, size, mime, name, width, height, duration_ms, thumb, bytes)
         SELECT attachment_id, message_id, position, key, digest, size, mime, name, width, height, duration_ms, thumb, bytes FROM message_attachments;
     DROP TABLE message_attachments;
     ALTER TABLE message_attachments_new RENAME TO message_attachments;
     CREATE INDEX message_attachments_by_message ON message_attachments (message_id, position);
     CREATE INDEX message_attachments_by_id ON message_attachments (attachment_id);",
    // 21: storage management (LIME-107). A file removed on this phone (by hand or by "Keep media") keeps its row, so the bubble can say
    // "Media removed" instead of offering a download that can no longer be had.
    "ALTER TABLE message_attachments ADD COLUMN removed INTEGER NOT NULL DEFAULT 0;",
    // 22: status (LIME-108). Mine, the notices still to send, and what each accepted contact last told this phone.
    "CREATE TABLE my_status (
         id          INTEGER PRIMARY KEY CHECK (id = 1),
         state       TEXT NOT NULL,
         until       INTEGER,
         then_state  TEXT,
         then_until  INTEGER,
         updated_at  INTEGER NOT NULL
     );
     CREATE TABLE status_notices (peer_user_id TEXT PRIMARY KEY NOT NULL, queued_at INTEGER NOT NULL);
     CREATE TABLE contact_status (
         user_id     TEXT PRIMARY KEY NOT NULL,
         state       TEXT NOT NULL,
         until       INTEGER,
         then_state  TEXT,
         then_until  INTEGER,
         sent_at     INTEGER NOT NULL
     );",
    // 23: a group can end (LIME-115): I left it ('left'), or its owner deleted it ('deleted'). Read-only either way.
    "ALTER TABLE conversations ADD COLUMN group_ended TEXT;",
    // 24: incoming call signalling waits here for the app to take it (LIME-111).
    "CREATE TABLE call_events (
         id      INTEGER PRIMARY KEY AUTOINCREMENT,
         peer    TEXT NOT NULL,
         op      TEXT NOT NULL,
         call_id TEXT NOT NULL,
         payload TEXT NOT NULL,
         at      INTEGER NOT NULL
     );",
    // 25: the calls on this phone (LIME-116b), newest first in the app; `seen` is for the call tab's missed-call badge.
    "CREATE TABLE call_history (
         id        TEXT PRIMARY KEY,
         peer      TEXT NOT NULL,
         peer_name TEXT NOT NULL,
         video     INTEGER NOT NULL,
         outgoing  INTEGER NOT NULL,
         at_ms     INTEGER NOT NULL,
         duration_ms INTEGER NOT NULL,
         outcome   TEXT NOT NULL,
         seen      INTEGER NOT NULL DEFAULT 0
     );
     CREATE INDEX call_history_by_time ON call_history (at_ms);",
    // 26 (LIME-120): each contact's devices as last served by the server, so a send needs no lookup. The master key they were
    // verified under is the pinned one in `peers`. A send says what it holds (`expect`) and the server corrects it when it is stale.
    "CREATE TABLE peer_devices (
         user_id          TEXT NOT NULL,
         device_id        TEXT NOT NULL,
         identity_key     TEXT NOT NULL,
         signing_key      TEXT NOT NULL,
         master_signature TEXT NOT NULL,
         updated_at       INTEGER NOT NULL,
         PRIMARY KEY (user_id, device_id)
     );",
    // 27 (LIME-112b): group calls. A call (`call_id`, in a group), who is in it, what I still owe the others (keys and call ops, sent
    // over Olm), and what the app has not taken yet. My own sender key lives here (the store is encrypted); other people's keys are
    // only ever in `group_call_events`, until the app takes them.
    "CREATE TABLE group_calls (
         call_id        TEXT PRIMARY KEY,
         group_id       TEXT NOT NULL,
         room           TEXT NOT NULL,
         video          INTEGER NOT NULL,
         started_by     TEXT NOT NULL,
         started_at     INTEGER NOT NULL,
         ended_at       INTEGER,
         rang           INTEGER NOT NULL DEFAULT 0,
         joined         INTEGER NOT NULL DEFAULT 0,
         joined_at      INTEGER,
         my_participant TEXT,
         my_key         BLOB,
         my_key_index   INTEGER NOT NULL DEFAULT 0
     );
     CREATE INDEX group_calls_by_group ON group_calls (group_id);
     CREATE TABLE group_call_participants (
         call_id     TEXT NOT NULL,
         participant TEXT NOT NULL,
         user_id     TEXT NOT NULL,
         device_id   TEXT NOT NULL,
         joined_at   INTEGER NOT NULL,
         left_at     INTEGER,
         PRIMARY KEY (call_id, participant)
     );
     CREATE TABLE group_call_outbox (
         id      INTEGER PRIMARY KEY AUTOINCREMENT,
         call_id TEXT NOT NULL,
         to_user TEXT NOT NULL,
         op_type TEXT NOT NULL,
         payload TEXT NOT NULL
     );
     CREATE TABLE group_call_events (
         id              INTEGER PRIMARY KEY AUTOINCREMENT,
         kind            TEXT NOT NULL,
         call_id         TEXT NOT NULL,
         conversation_id TEXT NOT NULL,
         user_id         TEXT NOT NULL,
         participant     TEXT NOT NULL,
         payload         TEXT NOT NULL,
         at              INTEGER NOT NULL
     );",
    // 28 (LIME-145): every Olm session is kept (one row per session, not one per peer), so two phones that start a session with each other at
    // the same moment do not lose each other's messages. `session_id` is vodozemac's id of the session: an older row has '' until it is first
    // read (its pickle is encrypted, so only the app can compute it) and is filled in then. `last_received` is when the session last decrypted
    // something: a send uses the session that most recently did, which makes both phones settle on one session after a crossing.
    "CREATE TABLE olm_sessions_v2 (
         peer_user_id      TEXT NOT NULL,
         peer_device_id    TEXT NOT NULL,
         peer_identity_key TEXT NOT NULL,
         session_id        TEXT NOT NULL DEFAULT '',
         session_pickle    TEXT NOT NULL,
         created_at        INTEGER NOT NULL,
         updated_at        INTEGER NOT NULL,
         last_received     INTEGER NOT NULL DEFAULT 0,
         PRIMARY KEY (peer_user_id, peer_identity_key, session_id)
     );
     INSERT INTO olm_sessions_v2 (peer_user_id, peer_device_id, peer_identity_key, session_id, session_pickle, created_at, updated_at, last_received)
         SELECT peer_user_id, peer_device_id, peer_identity_key, '', session_pickle, created_at, updated_at, updated_at FROM olm_sessions;
     DROP TABLE olm_sessions;
     ALTER TABLE olm_sessions_v2 RENAME TO olm_sessions;
     CREATE INDEX olm_sessions_by_peer ON olm_sessions (peer_user_id, peer_identity_key);",
    // 29 (LIME-147): the four-emoji check for group calls. For each person in a call, the SHA-256 of their CURRENT sender key and its index
    // (never the key itself: other people's keys stay only in `group_call_events` until the app takes them). The emoji are computed from these
    // hashes and from my own key's hash.
    "ALTER TABLE group_call_participants ADD COLUMN key_hash BLOB;
     ALTER TABLE group_call_participants ADD COLUMN key_index INTEGER;",
    // 30 (LIME-147b): no mismatched emoji during a rekey. `rekeys_at_join` is how many times I had renewed my own key when I first saw this
    // person (a renewal happens once per person who leaves, on every phone), so the renewals since then are `my_key_index - rekeys_at_join`
    // and their key must have been renewed as many times; `last_rekey_at` (when I last renewed mine) bounds the wait.
    "ALTER TABLE group_call_participants ADD COLUMN rekeys_at_join INTEGER NOT NULL DEFAULT 0;
     ALTER TABLE group_calls ADD COLUMN last_rekey_at INTEGER NOT NULL DEFAULT 0;",
    // 31 (LIME-139): signed access. Every phone uploaded only the hash of its delivery key before; the server now also needs the PUBLIC key of
    // the signing pair derived from it. Marking the key "not uploaded" makes the first launch after updating upload both again (before the
    // next send), as an upload that did not get through always is.
    "UPDATE delivery_state SET uploaded = 0;",
    // 32 (LIME-140): the mesh. What this phone carries for others (the encoded packet as it is now, how many copies it holds, its trust tier),
    // and the digests it has seen recently (so a packet it forwarded and dropped is not taken again at once). The store is encrypted.
    "CREATE TABLE mesh_packets (
         digest      BLOB PRIMARY KEY,
         bytes       BLOB NOT NULL,
         copies      INTEGER NOT NULL,
         tier        INTEGER NOT NULL,
         received_at INTEGER NOT NULL
     );
     CREATE TABLE mesh_seen (
         digest BLOB PRIMARY KEY,
         at     INTEGER NOT NULL
     );",
    // 33 (LIME-142): sealed sends that could not reach the server (no internet) and were handed to the mesh. The ciphertext is kept, so the
    // retry when the internet returns sends exactly these bytes (a re-encryption would burn another ratchet step and the recipient would
    // see two different ciphertexts for one message). `packet_digest` is set once the mesh engine carries it; `passed` once another phone took
    // a copy (the "Passed to a nearby phone" status).
    "CREATE TABLE mesh_outbox (
         op_id         TEXT NOT NULL,
         to_user       TEXT NOT NULL,
         to_device     TEXT NOT NULL,
         ciphertext    BLOB NOT NULL,
         created_at    INTEGER NOT NULL,
         packet_digest BLOB,
         passed        INTEGER NOT NULL DEFAULT 0,
         PRIMARY KEY (op_id, to_device)
     );",
    // 34 (LIME-143): emergency statuses. A status is an ordinary message whose payload also carries an `emergency` object; this keeps its fields
    // (and the end of an emergency) next to the message, and `emergency_settings` holds this phone's choices.
    "CREATE TABLE emergency_messages (
         message_id      TEXT PRIMARY KEY,
         conversation_id TEXT NOT NULL,
         sender_id       TEXT NOT NULL,
         session_id      TEXT NOT NULL,
         kind            TEXT NOT NULL,
         status          TEXT NOT NULL,
         situation       TEXT NOT NULL,
         students        INTEGER NOT NULL,
         place           TEXT NOT NULL,
         note            TEXT NOT NULL,
         drill           INTEGER NOT NULL
     );
     CREATE INDEX emergency_by_conversation ON emergency_messages (conversation_id, session_id);
     CREATE TABLE emergency_settings (
         key   TEXT PRIMARY KEY,
         value TEXT NOT NULL
     );",
    // 35 (LIME-143-fix): drills were removed; the flag goes (an older build's `drill` field is ignored when read).
    "ALTER TABLE emergency_messages DROP COLUMN drill;",
    // 36 (LIME-141-fix6): the SHA-256 of every ciphertext this phone has turned into a message (or recognised as one it already had). A message can
    // arrive twice (the mesh, then the server, or the other way round) and an Olm message cannot be decrypted twice, so the second copy used to sit in
    // `pending_inbound` for ever. It is now recognised by its hash and dropped.
    "CREATE TABLE received_ciphertexts (
         hash BLOB PRIMARY KEY,
         at   INTEGER NOT NULL
     );",
    // 37 (LIME-156): a copy of mail the server already has, parked for offline neighbours only (never sent to the server again, never makes a
    // message "waiting"); and the digests of packets this phone uploaded, kept 48 hours so a neighbour's copy is not taken and uploaded twice.
    "ALTER TABLE mesh_outbox ADD COLUMN copy INTEGER NOT NULL DEFAULT 0;
     CREATE TABLE mesh_uploaded (
         digest BLOB PRIMARY KEY,
         at     INTEGER NOT NULL
     );",
    // 38 (LIME-152c): a video's sharp poster frame, inside the encrypted message like the thumbnail (older rows have none).
    "ALTER TABLE message_attachments ADD COLUMN poster BLOB;",
    // 39 (LIME-184): usernames shared inside the encryption. `people.username` is what a person last told this phone (`username_at`: their clock);
    // `my_username` is what this phone shares, with a version that grows on every change; `username_sent` is the version each person was last told.
    "ALTER TABLE people ADD COLUMN username TEXT;
     ALTER TABLE people ADD COLUMN username_at INTEGER NOT NULL DEFAULT 0;
     CREATE TABLE my_username (id INTEGER PRIMARY KEY CHECK (id = 1), username TEXT, version INTEGER NOT NULL);
     CREATE TABLE username_sent (peer_user_id TEXT PRIMARY KEY NOT NULL, version INTEGER NOT NULL);",
];

/// The schema version this build writes.
pub(crate) const LATEST: u32 = MIGRATIONS.len() as u32;

pub(crate) fn run(conn: &Connection) -> Result<(), StoreError> {
    let current: u32 = conn
        .query_row("PRAGMA user_version", [], |r| r.get(0))
        .map_err(|_| StoreError::Migration)?;
    if current > LATEST {
        // Written by a newer Lime: never downgrade or guess.
        return Err(StoreError::Migration);
    }
    for (index, sql) in MIGRATIONS.iter().enumerate().skip(current as usize) {
        let version = index as u32 + 1;
        conn.execute_batch(&format!(
            "BEGIN; {sql} PRAGMA user_version = {version}; COMMIT;"
        ))
        .map_err(|_| {
            let _ = conn.execute_batch("ROLLBACK;");
            StoreError::Migration
        })?;
    }
    Ok(())
}
