//! The client against the in-memory fake server: out-of-order, unreadable, sealed and invalid items.

use std::sync::Arc;

use rusqlite::params;

use crate::store::LimeStore;
use crate::testing::FakeServer;
use crate::transport::Transport;

struct Party {
    store: Arc<LimeStore>,
    user: String,
    token: String,
    device: String,
    _dir: tempfile::TempDir,
}

fn party(server: &Arc<FakeServer>, user: &str, key: u8) -> (Party, Arc<dyn Transport>) {
    let dir = tempfile::tempdir().unwrap();
    let store = LimeStore::open(
        dir.path().join("lime.db").to_string_lossy().into_owned(),
        vec![key; 32],
    )
    .unwrap();
    let transport: Arc<dyn Transport> = server.clone();
    let token = FakeServer::token(user);
    let info = store
        .register_device(transport.clone(), token.clone())
        .unwrap();
    (
        Party {
            store,
            user: user.to_owned(),
            token,
            device: info.device_id,
            _dir: dir,
        },
        transport,
    )
}

fn say(from: &Party, to: &Party, transport: &Arc<dyn Transport>, text: &str) {
    from.store
        .send_text_identified(
            transport.clone(),
            from.token.clone(),
            to.user.clone(),
            text.into(),
        )
        .unwrap();
}

fn sync(p: &Party, transport: &Arc<dyn Transport>) -> crate::SyncReport {
    p.store.sync(transport.clone(), p.token.clone()).unwrap()
}

fn texts(p: &Party, peer: &Party) -> Vec<String> {
    p.store
        .list_messages(format!("dm:{}", peer.user))
        .unwrap()
        .into_iter()
        .map(|m| m.text)
        .collect()
}

fn pending_rows(p: &Party) -> Vec<(String, i64, bool)> {
    let conn = p.store.lock();
    let mut statement = conn
        .prepare("SELECT reason, attempts, identified FROM pending_inbound ORDER BY cursor")
        .unwrap();
    statement
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))
        .unwrap()
        .map(Result::unwrap)
        .collect()
}

#[test]
fn the_fake_server_carries_a_conversation_both_ways() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    say(&alice, &bob, &transport, "one");
    assert_eq!(sync(&bob, &transport).received, 1);
    say(&bob, &alice, &transport, "two");
    assert_eq!(sync(&alice, &transport).received, 1);
    say(&alice, &bob, &transport, "three");
    assert_eq!(sync(&bob, &transport).received, 1);
    assert_eq!(texts(&bob, &alice), vec!["one", "two", "three"]);
    assert_eq!(server.mailbox_len(&bob.device), 0);
}

#[test]
fn an_unreadable_item_is_kept_and_read_once_the_session_exists() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    // Establish both directions, so Alice's next message is a normal Olm message (not a pre-key one).
    say(&alice, &bob, &transport, "one");
    sync(&bob, &transport);
    say(&bob, &alice, &transport, "two");
    sync(&alice, &transport);

    // Bob loses the session (as if its keys were not there yet): remember its row, then remove it.
    let saved: (String, String, String, String, i64, i64) = {
        let conn = bob.store.lock();
        conn.query_row(
            "SELECT peer_user_id, peer_device_id, peer_identity_key, session_pickle, created_at, updated_at FROM olm_sessions",
            [],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?)),
        )
        .unwrap()
    };
    bob.store
        .lock()
        .execute("DELETE FROM olm_sessions", [])
        .unwrap();

    say(&alice, &bob, &transport, "three");
    let first = sync(&bob, &transport);
    assert_eq!(
        (first.received, first.pending),
        (0, 1),
        "unreadable for now, but not lost"
    );
    assert_eq!(
        server.mailbox_len(&bob.device),
        0,
        "the server was told to delete it: the copy is here"
    );
    assert_eq!(
        pending_rows(&bob),
        vec![("no_session".to_string(), 1, true)]
    );
    // Still waiting on the next sync (and tried again).
    let second = sync(&bob, &transport);
    assert_eq!((second.received, second.pending), (0, 1));
    assert_eq!(pending_rows(&bob)[0].1, 2, "it was retried");

    // The session comes back: the next sync reads it.
    bob.store
        .lock()
        .execute(
            "INSERT INTO olm_sessions (peer_user_id, peer_device_id, peer_identity_key, session_pickle, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![saved.0, saved.1, saved.2, saved.3, saved.4, saved.5],
        )
        .unwrap();
    let third = sync(&bob, &transport);
    assert_eq!((third.received, third.pending), (1, 0));
    assert_eq!(texts(&bob, &alice), vec!["one", "two", "three"]);
    assert!(pending_rows(&bob).is_empty());
}

#[test]
fn a_sealed_item_is_kept_not_lost() {
    let server = FakeServer::new();
    let (bob, transport) = party(&server, "bob", 2);
    server.inject(&bob.device, "c2VhbGVkIGl0ZW0", false, None);
    let report = sync(&bob, &transport);
    assert_eq!((report.received, report.pending), (0, 1));
    assert_eq!(server.mailbox_len(&bob.device), 0);
    assert_eq!(
        pending_rows(&bob),
        vec![("sealed_unsupported".to_string(), 1, false)]
    );
    // It stays across syncs (until sealed messages can be read).
    assert_eq!(sync(&bob, &transport).pending, 1);
}

#[test]
fn a_garbled_item_is_kept_as_invalid_and_not_retried() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    server.inject(&bob.device, "!!! not base64 !!!", true, Some(&alice.user));
    server.inject(&bob.device, "AAAAAAAAAAAA", true, Some(&alice.user));
    let report = sync(&bob, &transport);
    assert_eq!((report.received, report.pending), (0, 2));
    let rows = pending_rows(&bob);
    assert!(
        rows.iter().all(|r| r.0 == "invalid" && r.1 == 1),
        "tried once, then recorded as invalid: {rows:?}"
    );
    sync(&bob, &transport);
    assert!(
        pending_rows(&bob).iter().all(|r| r.1 == 1),
        "an invalid item is not tried again"
    );
    // A good message still gets through next to the bad ones.
    say(&alice, &bob, &transport, "hello");
    assert_eq!(sync(&bob, &transport).received, 1);
    assert_eq!(texts(&bob, &alice), vec!["hello"]);
}

#[test]
fn a_failed_acknowledgement_loses_nothing_and_does_not_duplicate() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    say(&alice, &bob, &transport, "once");

    server.state.lock().unwrap().fail_next_ack = true;
    assert!(
        bob.store
            .sync(transport.clone(), bob.token.clone())
            .is_err(),
        "the acknowledgement failed"
    );
    assert_eq!(
        server.mailbox_len(&bob.device),
        1,
        "the server still has it"
    );
    assert_eq!(
        pending_rows(&bob).len(),
        1,
        "and so do we: it was kept before the ack"
    );

    // The next sync fetches it again: no duplicate row, and the message is stored once.
    let report = sync(&bob, &transport);
    assert_eq!((report.received, report.pending), (1, 0));
    assert_eq!(texts(&bob, &alice), vec!["once"]);
    assert_eq!(server.mailbox_len(&bob.device), 0);
}

#[test]
fn an_item_from_a_changed_master_key_is_kept_not_stored() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    say(&alice, &bob, &transport, "first");
    sync(&bob, &transport);
    // Bob already trusts a different master key for Alice.
    bob.store
        .lock()
        .execute(
            "UPDATE peers SET master_key = 'some other key' WHERE user_id = ?1",
            params![alice.user],
        )
        .unwrap();
    say(&alice, &bob, &transport, "second");
    let report = sync(&bob, &transport);
    assert_eq!((report.received, report.pending), (0, 1));
    assert_eq!(pending_rows(&bob)[0].0, "key_mismatch");
    assert_eq!(texts(&bob, &alice), vec!["first"]);
}
