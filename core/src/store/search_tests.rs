//! On-device search: ranking, prefixes, diacritics, the back-fill, deletes, blocked chats, and that the
//! index lives only inside the encrypted file.

use rusqlite::Connection;

use super::search::{fts_query, MATCH_END, MATCH_START};
use super::*;

fn open(dir: &tempfile::TempDir) -> LimeStore {
    LimeStore::open_inner(&dir.path().join("lime.db").to_string_lossy(), &[9u8; 32]).unwrap()
}

fn chat(store: &LimeStore, id: &str, title: &str, people: &[&str]) {
    let conn = store.lock();
    conn.execute(
        "INSERT INTO conversations (id, title, is_group, is_pinned, unread) VALUES (?1, ?2, ?3, 0, 0)",
        params![id, title, people.len() > 1],
    )
    .unwrap();
    for (position, name) in people.iter().enumerate() {
        let person = format!("{id}-{position}");
        conn.execute("INSERT INTO people (id, name, tone) VALUES (?1, ?2, 1)", params![person, name]).unwrap();
        conn.execute(
            "INSERT INTO members (conversation_id, person_id, position) VALUES (?1, ?2, ?3)",
            params![id, person, position as i64],
        )
        .unwrap();
    }
    conn.execute("INSERT OR IGNORE INTO people (id, name, tone) VALUES ('me', 'Me', 4)", []).unwrap();
}

fn say(store: &LimeStore, chat: &str, id: &str, body: &str, at: i64) {
    store
        .lock()
        .execute(
            "INSERT INTO messages (id, conversation_id, sender_id, body, sent_at, local_state) VALUES (?1, ?2, 'me', ?3, ?4, 'sent')",
            params![id, chat, body, at],
        )
        .unwrap();
}

fn ids(hits: Vec<search::SearchHit>) -> Vec<String> {
    hits.into_iter().map(|h| h.message_id).collect()
}

fn find(store: &LimeStore, query: &str) -> Vec<String> {
    ids(store.search_messages(query.into(), None, 50).unwrap())
}

#[test]
fn fts5_is_compiled_into_the_encrypted_build() {
    let dir = tempfile::tempdir().unwrap();
    let store = open(&dir);
    let version: String = store.lock().query_row("SELECT sqlite_version()", [], |r| r.get(0)).unwrap();
    assert!(!version.is_empty());
    let found: i64 = store
        .lock()
        .query_row("SELECT count(*) FROM sqlite_master WHERE name = 'message_fts'", [], |r| r.get(0))
        .unwrap();
    assert_eq!(found, 1, "the FTS5 table was created by the migration");
}

#[test]
fn words_match_by_prefix_ignoring_case_and_diacritics() {
    let dir = tempfile::tempdir().unwrap();
    let store = open(&dir);
    chat(&store, "c1", "Élodie Martin", &["Élodie Martin"]);
    say(&store, "c1", "m1", "Café planning for Élodie's lesson", 1);
    say(&store, "c1", "m2", "Unrelated note", 2);

    for query in ["cafe", "CAFÉ", "café", "caf", "plan", "elodie", "ÉLODIE", "lesson planning", "les pl", "  cafe!!  "] {
        assert_eq!(find(&store, query), vec!["m1"], "{query}");
    }
    assert!(find(&store, "cafe zebra").is_empty(), "every word must match");
    assert!(find(&store, "xyz").is_empty());
    assert!(find(&store, "").is_empty());
    assert!(find(&store, "   ").is_empty());
    assert!(find(&store, "!!!").is_empty());
}

#[test]
fn typed_punctuation_is_never_read_as_search_syntax() {
    let dir = tempfile::tempdir().unwrap();
    let store = open(&dir);
    chat(&store, "c1", "Sam", &["Sam"]);
    say(&store, "c1", "m1", "this OR that, near NEAR(a b) and \"quotes\" * stars", 1);
    for query in ["\"", "*", "OR", "(", ")", "a OR", "NEAR(", "\"unterminated", "col:", "-x", "^y", "a*b"] {
        assert!(store.search_messages(query.into(), None, 10).is_ok(), "{query}");
    }
    assert_eq!(find(&store, "quotes stars"), vec!["m1"]);
    assert_eq!(fts_query("a OR b").unwrap(), "\"a\"* \"OR\"* \"b\"*");
}

#[test]
fn a_better_match_ranks_first_then_the_newest() {
    let dir = tempfile::tempdir().unwrap();
    let store = open(&dir);
    chat(&store, "c1", "Sam", &["Sam"]);
    say(&store, "c1", "long", "We should really talk about the lesson at some point during the next staff meeting this week", 10);
    say(&store, "c1", "short", "lesson", 5);
    assert_eq!(find(&store, "lesson"), vec!["short", "long"], "the tighter match first, even though it is older");
    // Equal matches: the newest first.
    say(&store, "c1", "old-same", "planning", 1);
    say(&store, "c1", "new-same", "planning", 99);
    assert_eq!(find(&store, "planning"), vec!["new-same", "old-same"]);
}

#[test]
fn a_conversation_search_is_oldest_first_and_only_that_chat() {
    let dir = tempfile::tempdir().unwrap();
    let store = open(&dir);
    chat(&store, "c1", "Sam", &["Sam"]);
    chat(&store, "c2", "Ada", &["Ada"]);
    say(&store, "c1", "b", "lesson two", 20);
    say(&store, "c1", "a", "lesson one", 10);
    say(&store, "c1", "c", "lesson three", 30);
    say(&store, "c2", "z", "lesson elsewhere", 15);
    let hits = store.search_messages("lesson".into(), Some("c1".into()), 50).unwrap();
    assert_eq!(ids(hits.clone()), vec!["a", "b", "c"], "oldest first, so a person can step through them");
    assert!(hits.iter().all(|h| h.conversation_id == "c1" && h.from_me));
    assert_eq!(find(&store, "lesson").len(), 4, "everywhere finds all four");
    assert_eq!(store.search_messages("lesson".into(), None, 2).unwrap().len(), 2, "the limit holds");
}

#[test]
fn the_snippet_marks_the_matched_words() {
    let dir = tempfile::tempdir().unwrap();
    let store = open(&dir);
    chat(&store, "c1", "Sam", &["Sam"]);
    say(&store, "c1", "m1", "Please bring the field trip forms on Friday", 1);
    let hit = store.search_messages("trip".into(), None, 5).unwrap().remove(0);
    assert!(hit.snippet.contains(&format!("{MATCH_START}trip{MATCH_END}")), "{:?}", hit.snippet);
    assert_eq!(hit.time, 1);
    let long = "word ".repeat(80) + "needle " + &"after ".repeat(80);
    say(&store, "c1", "m2", &long, 2);
    let hit = store.search_messages("needle".into(), None, 5).unwrap().remove(0);
    assert!(hit.snippet.chars().count() < 160, "a long message is cut around the match: {}", hit.snippet.len());
    assert!(hit.snippet.contains(&format!("{MATCH_START}needle{MATCH_END}")));
}

#[test]
fn deleting_or_editing_a_message_updates_the_index() {
    let dir = tempfile::tempdir().unwrap();
    let store = open(&dir);
    chat(&store, "c1", "Sam", &["Sam"]);
    say(&store, "c1", "m1", "remove me", 1);
    say(&store, "c1", "m2", "edit me", 2);
    assert_eq!(find(&store, "remove"), vec!["m1"]);
    store.lock().execute("DELETE FROM messages WHERE id = 'm1'", []).unwrap();
    assert!(find(&store, "remove").is_empty(), "a deleted message is gone from the index");
    store.lock().execute("UPDATE messages SET body = 'changed words' WHERE id = 'm2'", []).unwrap();
    assert!(find(&store, "edit").is_empty());
    assert_eq!(find(&store, "changed"), vec!["m2"]);
}

#[test]
fn blocked_conversations_are_not_searched() {
    let dir = tempfile::tempdir().unwrap();
    let store = open(&dir);
    chat(&store, "dm:u1", "Pat Doe", &["Pat Doe"]);
    say(&store, "dm:u1", "m1", "secret lesson", 1);
    assert_eq!(find(&store, "secret"), vec!["m1"]);
    assert_eq!(store.search_conversations("pat".into()).unwrap().len(), 1);
    store.block_sender("dm:u1".into()).unwrap();
    assert!(find(&store, "secret").is_empty());
    assert!(store.search_conversations("pat".into()).unwrap().is_empty());
    store.unblock("dm:u1".into()).unwrap();
    assert_eq!(find(&store, "secret"), vec!["m1"]);
}

#[test]
fn conversations_are_found_by_title_or_by_anyones_name() {
    let dir = tempfile::tempdir().unwrap();
    let store = open(&dir);
    chat(&store, "c1", "Zoë Müller", &["Zoë Müller"]);
    chat(&store, "c2", "Grade 4 Team", &["Ada Lovelace", "Sam Park", "Josefina Núñez"]);
    chat(&store, "c3", "Staff room", &["Lee Wong"]);
    let titles = |q: &str| -> Vec<String> { store.search_conversations(q.into()).unwrap().into_iter().map(|c| c.conversation_id).collect() };
    assert_eq!(titles("zoe"), vec!["c1"], "diacritics ignored");
    assert_eq!(titles("MULLER"), vec!["c1"]);
    assert_eq!(titles("grade"), vec!["c2"], "by title");
    assert_eq!(titles("jose"), vec!["c2"], "by a member's name, as a prefix");
    assert_eq!(titles("nunez"), vec!["c2"]);
    assert_eq!(titles("lee"), vec!["c3"]);
    assert!(titles("zzz").is_empty());
    assert!(titles("").is_empty());
    assert_eq!(titles("park lovelace"), vec!["c2"], "all words must match");
}

#[test]
fn existing_messages_are_indexed_by_the_migration() {
    let dir = tempfile::tempdir().unwrap();
    {
        let store = open(&dir);
        chat(&store, "c1", "Sam", &["Sam"]);
        say(&store, "c1", "old1", "an old message about fractions", 1);
        // Put the database back as an earlier version left it: no index, no triggers, version 6.
        store
            .lock()
            .execute_batch(
                "DROP TRIGGER messages_fts_insert; DROP TRIGGER messages_fts_delete; DROP TRIGGER messages_fts_update;
                 DROP TABLE message_fts; DROP INDEX messages_by_thread; DROP TABLE thread_state; DROP TABLE group_ops; DROP TABLE group_members; DROP TABLE group_outbox; DROP TABLE group_outbound_sessions; DROP TABLE group_inbound_sessions; ALTER TABLE conversations DROP COLUMN group_emoji; ALTER TABLE peers DROP COLUMN verified_at; DROP TABLE profile_key; DROP TABLE contact_profile_keys; DROP TABLE my_photo; DROP TABLE photos; DROP TABLE photo_notices; DROP TABLE message_attachments; DROP TABLE attachment_parts; DROP TABLE transfers; DROP TABLE contact_labels; ALTER TABLE conversations DROP COLUMN group_photo; ALTER TABLE conversations DROP COLUMN group_ended; ALTER TABLE conversations DROP COLUMN marked_unread; ALTER TABLE conversations DROP COLUMN hidden; DROP TABLE reactions; DROP TABLE my_status; DROP TABLE status_notices; DROP TABLE contact_status; DROP TABLE message_op_outbox; DROP TABLE early_message_ops; ALTER TABLE messages DROP COLUMN edited; ALTER TABLE messages DROP COLUMN edit_hlc; ALTER TABLE messages DROP COLUMN deleted; ALTER TABLE messages DROP COLUMN hidden; ALTER TABLE messages DROP COLUMN forwarded; ALTER TABLE messages DROP COLUMN link_preview; DROP TABLE delivery_state; DROP TABLE contact_delivery_keys; DROP TABLE share_queue; DROP TABLE key_shared; ALTER TABLE messages DROP COLUMN thread_root; ALTER TABLE messages DROP COLUMN plain; PRAGMA user_version = 6;",
            )
            .unwrap();
        say(&store, "c1", "old2", "another about fractions and decimals", 2);
    }
    let store = open(&dir);
    let mut found = find(&store, "fractions");
    found.sort();
    assert_eq!(found, vec!["old1", "old2"], "both are found, the one added before and the one after the index was dropped");
    assert_eq!(find(&store, "decimals"), vec!["old2"]);
    // And the triggers are back: a new message is indexed.
    say(&store, "c1", "new", "fractions again", 3);
    assert_eq!(find(&store, "again"), vec!["new"]);
}

#[test]
fn the_encrypted_file_holds_no_plaintext_of_an_indexed_word() {
    let dir = tempfile::tempdir().unwrap();
    let word = "zanzibarquokka";
    {
        let store = open(&dir);
        chat(&store, "c1", "Sam", &["Sam"]);
        say(&store, "c1", "m1", &format!("the {word} is indexed for search"), 1);
        assert_eq!(find(&store, word), vec!["m1"]);
        store.lock().execute_batch("PRAGMA wal_checkpoint(TRUNCATE);").ok();
    }
    // Every file the database left behind: the main file and any journal or WAL.
    let mut found_files = 0;
    for entry in std::fs::read_dir(dir.path()).unwrap() {
        let bytes = std::fs::read(entry.unwrap().path()).unwrap();
        found_files += 1;
        let text = String::from_utf8_lossy(&bytes).to_lowercase();
        assert!(!text.contains(word), "plaintext of an indexed word was written to disk");
        assert!(!text.contains("sqlite format 3"), "the file has no plain SQLite header");
    }
    assert!(found_files >= 1);

    // The check itself works: the same content in an UNencrypted database is plainly there.
    let plain = dir.path().join("plain.sqlite");
    {
        let conn = Connection::open(&plain).unwrap();
        conn.execute_batch(&format!(
            "CREATE VIRTUAL TABLE t USING fts5(body); INSERT INTO t (body) VALUES ('the {word} is indexed');"
        ))
        .unwrap();
    }
    let bytes = std::fs::read(&plain).unwrap();
    assert!(String::from_utf8_lossy(&bytes).to_lowercase().contains(word), "an unencrypted file would show it");
}
