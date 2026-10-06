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
