use std::path::PathBuf;

use rusqlite::Connection;

use super::*;

fn key(byte: u8) -> Vec<u8> {
    vec![byte; 32]
}

fn path_in(dir: &tempfile::TempDir) -> String {
    dir.path().join("lime.db").to_string_lossy().into_owned()
}

fn seeded(dir: &tempfile::TempDir) -> LimeStore {
    let store = LimeStore::open_inner(&path_in(dir), &key(7)).unwrap();
    store.seed_sample_data_if_empty().unwrap();
    store
}

#[test]
fn open_seed_list_send_round_trip() {
    let dir = tempfile::tempdir().unwrap();
    let store = seeded(&dir);

    let conversations = store.list_conversations().unwrap();
    assert_eq!(conversations.len(), 5);
    assert_eq!(
        conversations[0].id, "c1",
        "the pinned conversation comes first"
    );
    assert!(conversations[0].is_pinned);
    assert_eq!(conversations[0].unread, 1);
    assert!(!conversations[0].is_group);
    assert_eq!(conversations[0].members.len(), 1);
    assert_eq!(conversations[0].members[0].initials, "JP");
    assert!(conversations[3].is_group, "Grade 4 Team is a group");
    assert_eq!(
        conversations[3].members.len(),
        4,
        "members never include me"
    );

    let messages = store.list_messages("c2".into()).unwrap();
    assert_eq!(messages.len(), 3);
    assert!(
        messages[1].sender_id.is_none(),
        "my messages have no sender id"
    );
    assert!(messages.windows(2).all(|w| w[0].sent_at <= w[1].sent_at));
    assert_eq!(
        conversations
            .iter()
            .find(|c| c.id == "c2")
            .and_then(|c| c.last_message.clone())
            .map(|m| m.text),
        Some(messages.last().unwrap().text.clone())
    );

    let sent = store
        .send_local_message("c2".into(), "  see you then  ".into())
        .unwrap();
    assert_eq!(sent.text, "see you then");
    assert_eq!(sent.local_state, "sent_local");
    assert!(sent.sender_id.is_none());
    assert_eq!(Uuid::parse_str(&sent.id).unwrap().get_version_num(), 7);
    let messages = store.list_messages("c2".into()).unwrap();
    assert_eq!(messages.len(), 4);
    assert_eq!(messages.last().unwrap().id, sent.id);
}

#[test]
fn seeding_runs_once_and_only_into_an_empty_store() {
    let dir = tempfile::tempdir().unwrap();
    let store = seeded(&dir);
    store
        .send_local_message("c1".into(), "hello".into())
        .unwrap();
    store.seed_sample_data_if_empty().unwrap();
    assert_eq!(store.list_conversations().unwrap().len(), 5);
    assert_eq!(store.list_messages("c1".into()).unwrap().len(), 4);
}

#[test]
fn sending_validates_its_input() {
    let dir = tempfile::tempdir().unwrap();
    let store = seeded(&dir);
    assert_eq!(
        store
            .send_local_message("c1".into(), "   \n ".into())
            .unwrap_err(),
        StoreError::EmptyMessage
    );
    assert_eq!(
        store
            .send_local_message("nope".into(), "hi".into())
            .unwrap_err(),
        StoreError::NotFound
    );
}

#[test]
fn messages_persist_across_reopen() {
    let dir = tempfile::tempdir().unwrap();
    {
        let store = seeded(&dir);
        store
            .send_local_message("c3".into(), "persist me".into())
            .unwrap();
    }
    let reopened = LimeStore::open_inner(&path_in(&dir), &key(7)).unwrap();
    reopened.seed_sample_data_if_empty().unwrap();
    let messages = reopened.list_messages("c3".into()).unwrap();
    assert_eq!(messages.last().unwrap().text, "persist me");
    assert_eq!(reopened.list_conversations().unwrap().len(), 5);
}

#[test]
fn reopening_with_the_wrong_key_fails() {
    let dir = tempfile::tempdir().unwrap();
    drop(seeded(&dir));
    let wrong = LimeStore::open_inner(&path_in(&dir), &key(8));
    assert!(matches!(wrong, Err(StoreError::WrongKeyOrNotADatabase)));
    // The right key still works afterwards.
    assert!(LimeStore::open_inner(&path_in(&dir), &key(7)).is_ok());
}

#[test]
fn the_key_must_be_32_bytes() {
    let dir = tempfile::tempdir().unwrap();
    assert!(matches!(
        LimeStore::open_inner(&path_in(&dir), &[1, 2, 3]),
        Err(StoreError::InvalidKey)
    ));
}

#[test]
fn errors_carry_no_key_material() {
    let dir = tempfile::tempdir().unwrap();
    drop(seeded(&dir));
    let secret = key(0xAB);
    let hex: String = secret.iter().map(|b| format!("{b:02x}")).collect();
    let error = LimeStore::open_inner(&path_in(&dir), &secret)
        .err()
        .unwrap();
    let text = format!("{error} {error:?}");
    assert!(!text.contains(&hex) && !text.to_lowercase().contains("abab"));
}

#[test]
fn the_file_holds_no_plaintext() {
    let dir = tempfile::tempdir().unwrap();
    let store = seeded(&dir);
    store
        .send_local_message("c1".into(), "a distinctive plaintext marker".into())
        .unwrap();
    drop(store);
    let bytes = std::fs::read(PathBuf::from(path_in(&dir))).unwrap();
    assert!(bytes.len() > 4096, "the database file should not be empty");
    for needle in [
        "bakery",
        "Journey Park",
        "Grade 4 Team",
        "a distinctive plaintext marker",
        "SQLite format 3",
    ] {
        assert!(
            !bytes.windows(needle.len()).any(|w| w == needle.as_bytes()),
            "found {needle:?} in the encrypted file"
        );
    }
}

#[test]
fn the_file_is_not_readable_by_plain_sqlite() {
    let dir = tempfile::tempdir().unwrap();
    drop(seeded(&dir));
    // No key at all: the content must be unreadable.
    let plain = Connection::open(path_in(&dir)).unwrap();
    assert!(plain
        .query_row("SELECT count(*) FROM sqlite_master", [], |r| r
            .get::<_, i64>(0))
        .is_err());
}

#[test]
fn migrations_start_from_an_empty_database() {
    let dir = tempfile::tempdir().unwrap();
    let store = LimeStore::open_inner(&path_in(&dir), &key(7)).unwrap();
    {
        let conn = store.lock();
        let version: u32 = conn
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .unwrap();
        assert_eq!(version, migrations::LATEST);
        for table in ["people", "conversations", "members", "messages"] {
            let n: i64 = conn
                .query_row(
                    "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = ?1",
                    [table],
                    |r| r.get(0),
                )
                .unwrap();
            assert_eq!(n, 1, "missing table {table}");
        }
    }
    assert!(store.list_conversations().unwrap().is_empty());
}

#[test]
fn a_newer_database_is_refused_not_downgraded() {
    let dir = tempfile::tempdir().unwrap();
    {
        let store = LimeStore::open_inner(&path_in(&dir), &key(7)).unwrap();
        store
            .lock()
            .execute_batch(&format!(
                "PRAGMA user_version = {};",
                migrations::LATEST + 1
            ))
            .unwrap();
    }
    assert!(matches!(
        LimeStore::open_inner(&path_in(&dir), &key(7)),
        Err(StoreError::Migration)
    ));
}

#[test]
fn the_linked_sqlite_is_sqlcipher() {
    let dir = tempfile::tempdir().unwrap();
    let store = LimeStore::open_inner(&path_in(&dir), &key(7)).unwrap();
    let version: String = store
        .lock()
        .query_row("PRAGMA cipher_version", [], |r| r.get(0))
        .unwrap();
    assert!(!version.is_empty());
}

#[test]
fn initials_follow_the_app_rule() {
    assert_eq!(initials_of("Jean Chung"), "JC");
    assert_eq!(initials_of("madonna"), "M");
    assert_eq!(initials_of("Ana Maria de la Cruz"), "AM");
}

mod protocol_state {
    use super::*;
    use crate::keys::{derive_pickle_key, AccountState};
    use crate::store::account::{
        load_account, load_sessions, pin_master_key, save_account, save_session,
    };
    use vodozemac::olm::{Account, AccountPickle, SessionConfig};

    #[test]
    fn the_account_and_sessions_survive_a_reopen() {
        let dir = tempfile::tempdir().unwrap();
        let (identity, signing, master, device_id, session_id);
        {
            let store = LimeStore::open_inner(&path_in(&dir), &key(7)).unwrap();
            let mut state = AccountState::create();
            state.user_id = Some("user-1".into());
            state.registered = true;
            state.hlc = crate::protocol::Hlc {
                wall: 42,
                counter: 3,
            };
            identity = state.identity_key();
            signing = state.signing_key();
            master = state.master_key();
            device_id = state.device_id.clone();

            // A session with some other account.
            let mut other = Account::new();
            other.generate_one_time_keys(1);
            let otk = *other.one_time_keys().values().next().unwrap();
            let session = state
                .account
                .create_outbound_session(SessionConfig::version_1(), other.curve25519_key(), otk)
                .unwrap();
            session_id = session.session_id();

            let conn = store.lock();
            save_account(&conn, &store.pickle_key, &state).unwrap();
            save_session(
                &conn,
                &store.pickle_key,
                "peer",
                "peer-device",
                "peer-identity",
                &session,
                false,
                1,
            )
            .unwrap();
            pin_master_key(&conn, "peer", "master-1").unwrap();
        }
        let store = LimeStore::open_inner(&path_in(&dir), &key(7)).unwrap();
        let conn = store.lock();
        let state = load_account(&conn, &store.pickle_key)
            .unwrap()
            .expect("the account was saved");
        assert_eq!(state.identity_key(), identity);
        assert_eq!(state.signing_key(), signing);
        assert_eq!(
            state.master_key(),
            master,
            "the master signing key survives too"
        );
        assert_eq!(state.device_id, device_id);
        assert_eq!(state.user_id.as_deref(), Some("user-1"));
        assert!(state.registered);
        assert_eq!((state.hlc.wall, state.hlc.counter), (42, 3));
        let sessions = load_sessions(&conn, &store.pickle_key, "peer").unwrap();
        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0].session.session_id(), session_id);
        // The pinned master key is remembered; a different one is refused.
        pin_master_key(&conn, "peer", "master-1").unwrap();
        assert_eq!(
            pin_master_key(&conn, "peer", "master-2"),
            Err(StoreError::KeyMismatch)
        );
    }

    #[test]
    fn a_wrong_store_key_cannot_read_the_pickles() {
        let dir = tempfile::tempdir().unwrap();
        let encrypted_pickle;
        {
            let store = LimeStore::open_inner(&path_in(&dir), &key(7)).unwrap();
            let state = AccountState::create();
            save_account(&store.lock(), &store.pickle_key, &state).unwrap();
            encrypted_pickle = store
                .lock()
                .query_row("SELECT olm_pickle FROM account WHERE id = 1", [], |r| {
                    r.get::<_, String>(0)
                })
                .unwrap();
        }
        // The file itself is not readable with another key...
        assert!(matches!(
            LimeStore::open_inner(&path_in(&dir), &key(8)),
            Err(StoreError::WrongKeyOrNotADatabase)
        ));
        // ...and even the pickle text alone does not decrypt under another store key's derived key.
        assert!(
            AccountPickle::from_encrypted(&encrypted_pickle, &derive_pickle_key(&key(8))).is_err()
        );
        assert!(
            AccountPickle::from_encrypted(&encrypted_pickle, &derive_pickle_key(&key(7))).is_ok()
        );
        // The derived key is not the store key.
        assert_ne!(derive_pickle_key(&key(7)).to_vec(), key(7));
    }

    #[test]
    fn the_pickle_text_holds_no_key_material_in_the_clear() {
        let dir = tempfile::tempdir().unwrap();
        let store = LimeStore::open_inner(&path_in(&dir), &key(7)).unwrap();
        let state = AccountState::create();
        let signing = state.signing_key();
        save_account(&store.lock(), &store.pickle_key, &state).unwrap();
        let pickle: String = store
            .lock()
            .query_row("SELECT olm_pickle FROM account WHERE id = 1", [], |r| {
                r.get(0)
            })
            .unwrap();
        assert!(!pickle.contains(&signing));
    }

    #[test]
    fn migration_two_applies_to_a_database_that_has_version_one() {
        let dir = tempfile::tempdir().unwrap();
        {
            let store = LimeStore::open_inner(&path_in(&dir), &key(7)).unwrap();
            store.seed_sample_data_if_empty().unwrap();
        }
        let store = LimeStore::open_inner(&path_in(&dir), &key(7)).unwrap();
        let conn = store.lock();
        let version: u32 = conn
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .unwrap();
        assert_eq!(version, migrations::LATEST);
        assert!(version >= 2);
        let columns: i64 = conn
            .query_row(
                "SELECT count(*) FROM pragma_table_info('messages') WHERE name IN ('op_id', 'hlc')",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(columns, 2);
    }

    /// A session with a stranger, for the session storage tests.
    fn some_session(account: &mut Account, peer: &Account) -> vodozemac::olm::Session {
        let mut other = Account::new();
        other.generate_one_time_keys(1);
        let _ = peer;
        let otk = *other.one_time_keys().values().next().unwrap();
        account.create_outbound_session(SessionConfig::version_1(), other.curve25519_key(), otk).unwrap()
    }

    #[test]
    fn two_sessions_with_one_peer_are_both_kept_and_the_one_that_last_decrypted_goes_first() {
        let dir = tempfile::tempdir().unwrap();
        let store = LimeStore::open_inner(&path_in(&dir), &key(7)).unwrap();
        let mut mine = Account::new();
        let stranger = Account::new();
        let (first, second) = (some_session(&mut mine, &stranger), some_session(&mut mine, &stranger));
        assert_ne!(first.session_id(), second.session_id());
        let conn = store.lock();
        // The same peer key: before LIME-145 the second save replaced the first.
        save_session(&conn, &store.pickle_key, "peer", "dev", "peer-key", &first, false, 10).unwrap();
        save_session(&conn, &store.pickle_key, "peer", "dev", "peer-key", &second, false, 20).unwrap();
        let held = load_sessions(&conn, &store.pickle_key, "peer").unwrap();
        assert_eq!(held.iter().map(|s| s.session.session_id()).collect::<Vec<_>>(), vec![second.session_id(), first.session_id()], "both kept, the newest first");
        // The first one decrypts something: it goes first now (the rule that makes both phones settle on one session).
        save_session(&conn, &store.pickle_key, "peer", "dev", "peer-key", &first, true, 30).unwrap();
        let held = load_sessions(&conn, &store.pickle_key, "peer").unwrap();
        assert_eq!(held[0].session.session_id(), first.session_id());
        assert_eq!(held.len(), 2, "saving a session again updates it, never adds a copy");
        assert_eq!(crate::store::account::load_all_sessions(&conn, &store.pickle_key).unwrap().len(), 2);
    }

    #[test]
    fn at_most_five_sessions_are_kept_per_peer_and_the_least_recently_used_go_first() {
        let dir = tempfile::tempdir().unwrap();
        let store = LimeStore::open_inner(&path_in(&dir), &key(7)).unwrap();
        let mut mine = Account::new();
        let stranger = Account::new();
        let sessions: Vec<_> = (0..7).map(|_| some_session(&mut mine, &stranger)).collect();
        let conn = store.lock();
        for (i, session) in sessions.iter().enumerate() {
            save_session(&conn, &store.pickle_key, "peer", "dev", "peer-key", session, i == 0, 10 + i as i64).unwrap();
        }
        let ids: Vec<String> = load_sessions(&conn, &store.pickle_key, "peer").unwrap().iter().map(|s| s.session.session_id()).collect();
        assert_eq!(ids.len(), 5);
        assert_eq!(ids[0], sessions[0].session_id(), "the one that decrypted is never the one evicted");
        assert!(ids.contains(&sessions[6].session_id()), "the newest is kept");
        assert!(!ids.contains(&sessions[1].session_id()) && !ids.contains(&sessions[2].session_id()), "the oldest unused went");
        // Another peer's sessions are separate.
        let other = some_session(&mut mine, &stranger);
        save_session(&conn, &store.pickle_key, "someone-else", "dev", "else-key", &other, false, 99).unwrap();
        assert_eq!(load_sessions(&conn, &store.pickle_key, "peer").unwrap().len(), 5);
        assert_eq!(load_sessions(&conn, &store.pickle_key, "someone-else").unwrap().len(), 1);
    }

    #[test]
    fn a_store_from_before_migration_28_keeps_its_session_and_names_it_when_first_read() {
        let dir = tempfile::tempdir().unwrap();
        let path = path_in(&dir);
        let session_id;
        let pickle;
        {
            let store = LimeStore::open_inner(&path, &key(7)).unwrap();
            let mut mine = Account::new();
            let stranger = Account::new();
            let session = some_session(&mut mine, &stranger);
            session_id = session.session_id();
            pickle = session.pickle().encrypt(&store.pickle_key);
            let conn = store.lock();
            // Put the store back to the schema before migration 28: one row per peer key, no session id.
            conn.execute_batch(
                "DROP INDEX olm_sessions_by_peer; DROP TABLE olm_sessions;
                 CREATE TABLE olm_sessions (peer_user_id TEXT NOT NULL, peer_device_id TEXT NOT NULL, peer_identity_key TEXT NOT NULL,
                     session_pickle TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, PRIMARY KEY (peer_user_id, peer_identity_key));
                 ALTER TABLE group_call_participants DROP COLUMN key_hash; ALTER TABLE group_call_participants DROP COLUMN key_index; ALTER TABLE group_call_participants DROP COLUMN rekeys_at_join; ALTER TABLE group_calls DROP COLUMN last_rekey_at; DROP TABLE received_ciphertexts; DROP TABLE emergency_messages; DROP TABLE emergency_settings; DROP TABLE mesh_outbox; DROP TABLE mesh_packets; DROP TABLE mesh_seen; DROP TABLE mesh_uploaded; ALTER TABLE message_attachments DROP COLUMN poster;
                 DROP TABLE draft_files; DROP TABLE draft_outbox; DROP TABLE draft_authors; DROP TABLE draft_chunks; DROP TABLE drafts; DROP TABLE deleted_peers; DROP TABLE session_repairs; DROP TABLE profile_key_requests; DROP TABLE my_extra; DROP TABLE extras; DROP TRIGGER jam_posts_fts_insert; DROP TRIGGER jam_posts_fts_update; DROP TRIGGER jam_posts_fts_delete; DROP TABLE jam_fts; DROP TABLE my_username; DROP TABLE username_sent; ALTER TABLE people DROP COLUMN username; ALTER TABLE people DROP COLUMN username_at; DROP TABLE jams; DROP TABLE jam_subscribers; DROP TABLE jam_op_outbox; DROP TABLE jam_attachments; DROP TABLE jam_credits; DROP TABLE jam_credit_requests; DROP TABLE jam_credit_wires; DROP TABLE jam_outbound; DROP TABLE jam_inbound; DROP TABLE jam_blob_deletes; DROP TABLE jam_reactions; DROP TABLE jam_my_reactions; DROP TABLE jam_comments; DROP TABLE jam_counts; DROP TABLE jam_counts_out; DROP TABLE jam_posts; DROP TABLE jam_wire_outbox; PRAGMA user_version = 27;",
            )
            .unwrap();
            conn.execute(
                "INSERT INTO olm_sessions (peer_user_id, peer_device_id, peer_identity_key, session_pickle, created_at, updated_at) VALUES ('peer', 'dev', 'peer-key', ?1, 5, 6)",
                params![pickle],
            )
            .unwrap();
        }
        let store = LimeStore::open_inner(&path, &key(7)).unwrap();
        let conn = store.lock();
        let stored: String = conn.query_row("SELECT session_id FROM olm_sessions", [], |r| r.get(0)).unwrap();
        assert_eq!(stored, "", "the pickle is encrypted: its id cannot be known inside the migration");
        let held = load_sessions(&conn, &store.pickle_key, "peer").unwrap();
        assert_eq!(held.len(), 1);
        assert_eq!(held[0].session.session_id(), session_id);
        let named: String = conn.query_row("SELECT session_id FROM olm_sessions", [], |r| r.get(0)).unwrap();
        assert_eq!(named, session_id, "named the first time it is read");
        // Saving it again updates that row rather than adding a copy.
        save_session(&conn, &store.pickle_key, "peer", "dev", "peer-key", &held[0].session, true, 50).unwrap();
        assert_eq!(load_sessions(&conn, &store.pickle_key, "peer").unwrap().len(), 1);
    }
}
