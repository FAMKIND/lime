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

// ---------------------------------------------------------------- LIME-95: requests, blocking,
// queued sends, names and ordering

fn conversation(p: &Party, peer: &Party) -> Option<crate::ConversationSummary> {
    p.store
        .list_conversations()
        .unwrap()
        .into_iter()
        .find(|c| c.id == format!("dm:{}", peer.user))
}

fn states(p: &Party, peer: &Party) -> Vec<(String, String)> {
    p.store
        .list_messages(format!("dm:{}", peer.user))
        .unwrap()
        .into_iter()
        .map(|m| (m.text, m.local_state))
        .collect()
}

#[test]
fn a_strangers_first_message_is_a_request_until_accepted() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    server
        .state
        .lock()
        .unwrap()
        .profiles
        .insert("alice".into(), ("Alice A".into(), Some("alice.a".into())));

    // Alice started the chat, so for her it is a normal conversation.
    alice.store.start_dm("bob".into(), "Bob B".into()).unwrap();
    say(&alice, &bob, &transport, "hello");
    let hers = conversation(&alice, &bob).unwrap();
    assert_eq!((hers.request_state.as_str(), hers.title.as_str()), ("accepted", "Bob B"));

    // For Bob it is a request, and it already carries her profile name.
    assert_eq!(sync(&bob, &transport).received, 1);
    let request = conversation(&bob, &alice).unwrap();
    assert_eq!(request.request_state, "pending");
    assert_eq!(request.title, "Alice A", "the name comes from her public profile");
    assert_eq!(request.unread, 1);
    assert_eq!(texts(&bob, &alice), vec!["hello"]);

    // Accepting moves it into Messages; replying works; reading clears the badge.
    bob.store.accept_request(request.id.clone()).unwrap();
    bob.store.mark_read(request.id.clone()).unwrap();
    let accepted = conversation(&bob, &alice).unwrap();
    assert_eq!((accepted.request_state.as_str(), accepted.unread), ("accepted", 0));
    say(&bob, &alice, &transport, "hi Alice");
    assert_eq!(sync(&alice, &transport).received, 1);
    assert_eq!(texts(&alice, &bob), vec!["hello", "hi Alice"]);
    assert_eq!(texts(&bob, &alice), vec!["hello", "hi Alice"]);
}

#[test]
fn a_blocked_senders_new_messages_stay_hidden_and_nothing_is_left_waiting() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    say(&alice, &bob, &transport, "first");
    sync(&bob, &transport);
    let id = conversation(&bob, &alice).unwrap().id;
    bob.store.block_sender(id.clone()).unwrap();
    assert!(conversation(&bob, &alice).is_none(), "a blocked conversation is not listed");

    say(&alice, &bob, &transport, "second");
    let report = sync(&bob, &transport);
    assert_eq!((report.received, report.pending), (0, 0), "read and dropped, not kept");
    assert_eq!(server.mailbox_len(&bob.device), 0);
    assert!(conversation(&bob, &alice).is_none());
    let stored: i64 = bob
        .store
        .lock()
        .query_row("SELECT count(*) FROM messages WHERE body = 'second'", [], |r| r.get(0))
        .unwrap();
    assert_eq!(stored, 0, "never stored");

    // The session stayed in step, so a later (unblocked) message still reads.
    bob.store.accept_request(id).unwrap();
    say(&alice, &bob, &transport, "third");
    assert_eq!(sync(&bob, &transport).received, 1);
    assert_eq!(texts(&bob, &alice), vec!["first", "third"]);
    assert!(bob.store.accept_request("dm:nobody".into()).is_err());
}

#[test]
fn a_queued_message_goes_sending_then_sent_and_a_failure_is_retried_in_order() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    let id = alice.store.start_dm("bob".into(), "Bob".into()).unwrap();

    let one = alice.store.queue_text(id.clone(), "one".into()).unwrap();
    alice.store.queue_text(id.clone(), "two".into()).unwrap();
    assert_eq!(one.local_state, "sending");
    assert_eq!(states(&alice, &bob), vec![("one".into(), "sending".into()), ("two".into(), "sending".into())]);

    // The server is down: the first fails, the second waits behind it, nothing is lost.
    server.state.lock().unwrap().fail_sends = true;
    assert!(alice.store.deliver_queued(transport.clone(), alice.token.clone()).is_err());
    assert_eq!(states(&alice, &bob), vec![("one".into(), "failed".into()), ("two".into(), "sending".into())]);
    assert_eq!(sync(&bob, &transport).received, 0);

    // Back up: both go, in order, and Bob sees each once.
    server.state.lock().unwrap().fail_sends = false;
    assert_eq!(alice.store.deliver_queued(transport.clone(), alice.token.clone()).unwrap(), 2);
    assert_eq!(states(&alice, &bob), vec![("one".into(), "sent".into()), ("two".into(), "sent".into())]);
    assert_eq!(alice.store.deliver_queued(transport.clone(), alice.token.clone()).unwrap(), 0, "nothing is sent twice");
    assert_eq!(sync(&bob, &transport).received, 2);
    assert_eq!(texts(&bob, &alice), vec!["one", "two"]);

    // Blank text and a conversation that is not a DM are refused.
    assert!(alice.store.queue_text(id, "   ".into()).is_err());
    assert!(alice.store.queue_text("nope".into(), "x".into()).is_err());
}

#[test]
fn people_are_found_by_exact_username_or_email_and_named_from_their_profile() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    {
        let mut state = server.state.lock().unwrap();
        state.profiles.insert("bob".into(), ("Bob B".into(), Some("bob.b".into())));
        state.emails.insert("bob@example.com".into(), "bob".into());
    }
    let by_name = crate::find_user(transport.clone(), alice.token.clone(), "@Bob.B".into()).unwrap().unwrap();
    assert_eq!((by_name.user_id.as_str(), by_name.display_name.as_str(), by_name.is_self), ("bob", "Bob B", false));
    let by_email = crate::find_user(transport.clone(), alice.token.clone(), "bob@example.com".into()).unwrap().unwrap();
    assert_eq!(by_email.user_id, "bob");
    assert!(crate::find_user(transport.clone(), alice.token.clone(), "bob".into()).unwrap().is_none(), "no partial match");
}

#[test]
fn a_reply_that_names_a_missing_parent_still_shows_and_the_order_survives_a_restart() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    say(&alice, &bob, &transport, "a1");
    sync(&bob, &transport);
    bob.store.accept_request(format!("dm:{}", alice.user)).unwrap();
    say(&bob, &alice, &transport, "b1");
    say(&bob, &alice, &transport, "b2");
    sync(&alice, &transport);
    say(&alice, &bob, &transport, "a2");
    sync(&bob, &transport);
    let expected = vec!["a1", "b1", "b2", "a2"];
    assert_eq!(texts(&alice, &bob), expected);
    assert_eq!(texts(&bob, &alice), expected);

    // The parents are real: a2 names b2 (the latest op Alice had seen).
    let parents: String = alice
        .store
        .lock()
        .query_row("SELECT parents FROM messages WHERE body = 'a2'", [], |r| r.get(0))
        .unwrap();
    let b2: String = alice
        .store
        .lock()
        .query_row("SELECT op_id FROM messages WHERE body = 'b2'", [], |r| r.get(0))
        .unwrap();
    assert_eq!(parents, format!("[\"{b2}\"]"));

    // Restart: reopen the same encrypted file.
    let path = _path(&alice);
    let reopened = LimeStore::open(path, vec![1; 32]).unwrap();
    let after: Vec<String> = reopened
        .list_messages(format!("dm:{}", bob.user))
        .unwrap()
        .into_iter()
        .map(|m| m.text)
        .collect();
    assert_eq!(after, expected);
}

fn _path(p: &Party) -> String {
    p._dir.path().join("lime.db").to_string_lossy().into_owned()
}

// ---------------------------------------------------------------- LIME-95-fix: a phone with new keys

/// Bob signs in again on a phone whose keys were wiped: same account, brand-new keys.
fn bob_with_new_keys(server: &Arc<FakeServer>) -> (Party, Arc<dyn Transport>) {
    party(server, "bob", 9)
}

#[test]
fn replacing_an_accounts_keys_marks_waiting_messages_not_delivered_and_asks_to_accept_the_new_key() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    say(&alice, &bob, &transport, "first");
    sync(&bob, &transport);
    bob.store.accept_request(format!("dm:{}", alice.user)).unwrap();
    // A second message is still waiting for Bob's old device when his keys are replaced.
    say(&alice, &bob, &transport, "never read");
    assert_eq!(server.mailbox_len(&bob.device), 1);

    let (bob2, _) = bob_with_new_keys(&server);
    assert_ne!(bob2.device, bob.device);
    assert_eq!(server.mailbox_len(&bob.device), 0, "the old device's mail is gone");

    // Alice's next sync learns that message was not delivered; the first one, which Bob read, is untouched.
    sync(&alice, &transport);
    assert_eq!(
        states(&alice, &bob2),
        vec![("first".into(), "sent".into()), ("never read".into(), "undelivered".into())]
    );

    // Sending to Bob now meets a key she has not accepted: nothing moves, and the chat says why.
    let id = format!("dm:{}", bob2.user);
    alice.store.queue_text(id.clone(), "are you there?".into()).unwrap();
    assert!(matches!(
        alice.store.deliver_queued(transport.clone(), alice.token.clone()),
        Err(crate::StoreError::KeyMismatch)
    ));
    assert!(conversation(&alice, &bob2).unwrap().key_change_pending);
    assert_eq!(sync(&bob2, &transport).received, 0);

    // She accepts the new key, resends the undelivered one, and both reach Bob's new phone.
    alice.store.trust_new_key(id.clone()).unwrap();
    assert!(!conversation(&alice, &bob2).unwrap().key_change_pending);
    let undelivered = alice
        .store
        .list_messages(id.clone())
        .unwrap()
        .into_iter()
        .find(|m| m.local_state == "undelivered")
        .unwrap();
    alice.store.retry_message(undelivered.id).unwrap();
    assert_eq!(alice.store.deliver_queued(transport.clone(), alice.token.clone()).unwrap(), 2);
    assert_eq!(sync(&bob2, &transport).received, 2);
    let mut got = texts(&bob2, &alice);
    got.sort();
    assert_eq!(got, vec!["are you there?", "never read"]);
}

#[test]
fn a_message_from_a_changed_key_waits_until_it_is_accepted_and_then_reads() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    say(&alice, &bob, &transport, "hello");
    sync(&bob, &transport);
    bob.store.accept_request(format!("dm:{}", alice.user)).unwrap();
    say(&bob, &alice, &transport, "hi");
    sync(&alice, &transport);

    // Bob's phone is replaced; Alice never heard of the new key, but his first message to her is a pre-key one.
    let (bob2, _) = bob_with_new_keys(&server);
    bob2.store.start_dm(alice.user.clone(), "Alice".into()).unwrap();
    // (Bob's new phone has not pinned Alice's key before, so sending works.)
    say(&bob2, &alice, &transport, "new phone, who dis");
    let report = sync(&alice, &transport);
    assert_eq!((report.received, report.pending), (0, 1), "held back, not lost");
    assert_eq!(texts(&alice, &bob2), vec!["hello".to_string(), "hi".to_string()]);
    assert!(conversation(&alice, &bob2).unwrap().key_change_pending);

    // Accepting the key reads it (the session was kept, so the spent one-time key does not matter).
    alice.store.trust_new_key(format!("dm:{}", bob2.user)).unwrap();
    let after = sync(&alice, &transport);
    assert_eq!((after.received, after.pending), (1, 0));
    assert_eq!(texts(&alice, &bob2), vec!["hello", "hi", "new phone, who dis"]);
    assert!(!conversation(&alice, &bob2).unwrap().key_change_pending);
}

#[test]
fn server_answers_map_to_distinct_errors() {
    use crate::StoreError;
    // The core's own mapping, as the app relies on it to tell the truth.
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let bad_token = "tok-";
    let _ = (&alice, bad_token);
    // No token at all: the fake answers 401, which the core calls Unauthorized, not "network".
    let result = crate::find_user(transport.clone(), String::new(), "bob".into());
    assert!(matches!(result, Err(StoreError::Unauthorized)), "{result:?}");
}

// ---------------------------------------------------------------- LIME-98: blocked people, key info

#[test]
fn blocking_then_unblocking_brings_the_conversation_and_its_messages_back() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    server
        .state
        .lock()
        .unwrap()
        .profiles
        .insert("alice".into(), ("Alice A".into(), None));
    say(&alice, &bob, &transport, "before the block");
    sync(&bob, &transport);
    let id = conversation(&bob, &alice).unwrap().id;
    assert!(bob.store.list_blocked().unwrap().is_empty());

    bob.store.block_sender(id.clone()).unwrap();
    let blocked = bob.store.list_blocked().unwrap();
    assert_eq!(blocked.len(), 1);
    assert_eq!((blocked[0].conversation_id.as_str(), blocked[0].name.as_str()), (id.as_str(), "Alice A"));
    assert!(conversation(&bob, &alice).is_none());
    say(&alice, &bob, &transport, "while blocked");
    sync(&bob, &transport);

    // Unblocked: the earlier message shows again, the one sent meanwhile was never kept, new ones arrive.
    bob.store.unblock(id.clone()).unwrap();
    assert!(bob.store.list_blocked().unwrap().is_empty());
    assert_eq!(texts(&bob, &alice), vec!["before the block"]);
    say(&alice, &bob, &transport, "after");
    sync(&bob, &transport);
    assert_eq!(texts(&bob, &alice), vec!["before the block", "after"]);
    assert!(bob.store.unblock(id).is_err(), "only a blocked conversation can be unblocked");
}

#[test]
fn key_info_gives_a_stable_short_fingerprint_and_the_day_the_keys_were_made() {
    let server = FakeServer::new();
    let (alice, _) = party(&server, "alice", 1);
    let before = crate::store::now_ms();
    let info = alice.store.key_info().unwrap().expect("the account exists once the device registered");
    let again = alice.store.key_info().unwrap().unwrap();
    assert_eq!(info, again, "the same every time");
    let groups: Vec<&str> = info.fingerprint.split(' ').collect();
    assert_eq!(groups.len(), 5);
    assert!(groups.iter().all(|g| g.len() == 4 && g.chars().all(|c| c.is_ascii_hexdigit() && !c.is_ascii_lowercase())));
    assert!(info.created_at > 0 && info.created_at <= before, "made before now, after the epoch");
    let (bob, _) = party(&server, "bob", 2);
    assert_ne!(bob.store.key_info().unwrap().unwrap().fingerprint, info.fingerprint, "each account has its own");
}

// ---------------------------------------------------------------- LIME-99: search stays on the device

#[test]
fn searching_never_calls_the_server() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    server.state.lock().unwrap().profiles.insert("alice".into(), ("Alice A".into(), None));
    say(&alice, &bob, &transport, "the field trip is on friday");
    sync(&bob, &transport);
    say(&alice, &bob, &transport, "friday again");
    sync(&bob, &transport);

    let before = server.state.lock().unwrap().calls;
    let hits = bob.store.search_messages("friday".into(), None, 20).unwrap();
    assert_eq!(hits.len(), 2, "both received messages are searchable");
    assert_eq!(bob.store.search_messages("trip".into(), Some(format!("dm:{}", alice.user)), 20).unwrap().len(), 1);
    assert_eq!(bob.store.search_conversations("alice".into()).unwrap().len(), 1, "found by the name from her profile");
    let mine = alice.store.search_messages("friday".into(), None, 20).unwrap();
    assert_eq!(mine.len(), 2);
    assert!(mine.iter().all(|h| h.from_me));
    assert_eq!(
        server.state.lock().unwrap().calls,
        before,
        "search made no request: it reads only the local database"
    );
}

// ---------------------------------------------------------------- LIME-100: formatted messages

#[test]
fn a_formatted_message_arrives_as_the_same_markdown_and_is_searched_by_its_words() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    let text = "Hello **team**, see [the plan](https://limechat.org/plan)\n\n- bring `forms`\n- bring __snacks__\n\n```\nlet a = **raw**\n```";
    say(&alice, &bob, &transport, text);
    sync(&bob, &transport);

    // Both sides hold the one written form, so it renders the same on both.
    let sent = texts(&alice, &bob);
    let got = texts(&bob, &alice);
    assert_eq!(sent, got);
    assert_eq!(got[0], crate::format::normalise(text));
    assert!(got[0].contains("**team**") && got[0].contains("```"));

    // Search and previews work on the words, not the markup.
    assert_eq!(bob.store.search_messages("team".into(), None, 10).unwrap().len(), 1);
    assert_eq!(bob.store.search_messages("limechat".into(), None, 10).unwrap().len(), 0, "a link's address is not part of the words");
    assert_eq!(bob.store.search_messages("plan".into(), None, 10).unwrap().len(), 1, "but its text is");
    assert_eq!(bob.store.search_messages("raw".into(), None, 10).unwrap().len(), 1, "code is searchable");
    let hit = bob.store.search_messages("snacks".into(), None, 10).unwrap().remove(0);
    assert!(!hit.snippet.contains("__") && !hit.snippet.contains("(https"), "the snippet has no markup (a code block stays as written): {}", hit.snippet);
}

#[test]
fn unknown_syntax_in_a_sent_message_is_downgraded_to_text() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    say(&alice, &bob, &transport, "[click](javascript:alert(1)) and # not a heading");
    sync(&bob, &transport);
    let got = texts(&bob, &alice).remove(0);
    assert!(got.starts_with("\\[click\\]"), "the link is text, not a link: {got}");
    let blocks = crate::format::parse(&got);
    let crate::format::Block::Paragraph { spans } = &blocks[0] else { panic!() };
    assert!(spans.iter().all(|s| s.link.is_none()));
}

#[test]
fn the_size_limit_applies_to_the_written_form() {
    let server = FakeServer::new();
    let (alice, _) = party(&server, "alice", 1);
    let id = alice.store.start_dm("bob".into(), "Bob".into()).unwrap();
    // Escaping can double a message of markup characters: 20,000 stars is 40,000 bytes written.
    assert!(alice.store.queue_text(id.clone(), "*".repeat(20_000)).is_err(), "too big once written");
    assert!(alice.store.queue_text(id.clone(), "a".repeat(29_000)).is_ok());
    assert!(alice.store.queue_text(id, "a".repeat(31_000)).is_err());
}
