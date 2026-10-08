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
fn a_sealed_item_that_cannot_be_read_is_kept_and_never_shown() {
    let server = FakeServer::new();
    let (bob, transport) = party(&server, "bob", 2);
    server.inject(&bob.device, "c2VhbGVkIGl0ZW0", false, None);
    let report = sync(&bob, &transport);
    assert_eq!((report.received, report.pending), (0, 1));
    assert_eq!(server.mailbox_len(&bob.device), 0);
    assert_eq!(pending_rows(&bob), vec![("invalid".to_string(), 1, false)]);
    // It stays across syncs, and nothing was made of it.
    assert_eq!(sync(&bob, &transport).pending, 1);
    assert!(bob.store.list_conversations().unwrap().is_empty());
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
    // Two items wait: the message, and the delivery-key share the new phone sent when it started the chat.
    assert_eq!((report.received, report.pending), (0, 2), "held back, not lost");
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

// ---------------------------------------------------------------- LIME-101: reply threads

fn reply(from: &Party, to: &Party, transport: &Arc<dyn Transport>, root: &str, text: &str) -> crate::MessageItem {
    let item = from
        .store
        .queue_reply(format!("dm:{}", to.user), root.into(), text.into())
        .unwrap();
    from.store.deliver_queued(transport.clone(), from.token.clone()).unwrap();
    item
}

fn first_message_id(p: &Party, peer: &Party) -> String {
    p.store.list_messages(format!("dm:{}", peer.user)).unwrap().remove(0).id
}

#[test]
fn a_reply_stays_out_of_the_timeline_and_hangs_from_its_root_on_both_phones() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    server.state.lock().unwrap().profiles.insert("alice".into(), ("Alice A".into(), None));
    server.state.lock().unwrap().profiles.insert("bob".into(), ("Bob B".into(), None));
    say(&alice, &bob, &transport, "who has the field trip forms?");
    sync(&bob, &transport);
    bob.store.accept_request(format!("dm:{}", alice.user)).unwrap();
    let root = first_message_id(&alice, &bob);

    // Bob replies in the thread; Alice replies back; a third message is an ordinary one.
    reply(&bob, &alice, &transport, &root, "I do, in the staff room");
    sync(&alice, &transport);
    reply(&alice, &bob, &transport, &root, "thanks, I'll pick them up");
    say(&alice, &bob, &transport, "also: lunch?");
    sync(&bob, &transport);

    for (me, peer) in [(&alice, &bob), (&bob, &alice)] {
        assert_eq!(texts(me, peer), vec!["who has the field trip forms?", "also: lunch?"], "replies are not in the main timeline");
        let thread = me.store.list_thread(root.clone()).unwrap();
        assert_eq!(
            thread.iter().map(|m| m.text.as_str()).collect::<Vec<_>>(),
            vec!["who has the field trip forms?", "I do, in the staff room", "thanks, I'll pick them up"],
            "the root first, then the replies in order"
        );
        let summaries = me.store.list_thread_summaries(format!("dm:{}", peer.user)).unwrap();
        assert_eq!(summaries.len(), 1);
        assert_eq!(summaries[0].root_id, root);
        assert_eq!(summaries[0].reply_count, 2);
        assert_eq!(summaries[0].repliers.len(), 2, "both people replied");
        assert_eq!(summaries[0].last_reply_at, thread[2].sent_at);
    }
    // Most recent replier first: on Alice's phone that is Alice herself ("me"), on Bob's it is Alice too (by id).
    let alice_view = alice.store.list_thread_summaries(format!("dm:{}", bob.user)).unwrap().remove(0);
    assert_eq!(alice_view.repliers[0].id, "me");
}

#[test]
fn replying_to_a_reply_answers_the_same_root_and_a_wrong_root_is_refused() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    say(&alice, &bob, &transport, "root question");
    sync(&bob, &transport);
    bob.store.accept_request(format!("dm:{}", alice.user)).unwrap();
    let root = first_message_id(&alice, &bob);
    let first = reply(&bob, &alice, &transport, &root, "first reply");
    sync(&alice, &transport);

    // Alice answers Bob's REPLY: it still hangs from the root.
    let second = reply(&alice, &bob, &transport, &first.id, "reply to the reply");
    sync(&bob, &transport);
    let thread: Vec<String> = bob.store.list_thread(root.clone()).unwrap().into_iter().map(|m| m.id).collect();
    assert_eq!(thread, vec![root.clone(), first.id.clone(), second.id.clone()]);
    assert_eq!(bob.store.list_thread_summaries(format!("dm:{}", alice.user)).unwrap().len(), 1, "one thread, not two");

    // A message that is not here, or is in another conversation, cannot be replied to.
    assert!(alice.store.queue_reply(format!("dm:{}", bob.user), "no-such-message".into(), "x".into()).is_err());
    let (carol, ctransport) = party(&server, "carol", 3);
    let _ = (&carol, &ctransport);
    alice.store.start_dm(carol.user.clone(), "Carol".into()).unwrap();
    assert!(alice.store.queue_reply(format!("dm:{}", carol.user), root, "wrong chat".into()).is_err(), "the root must be in this conversation");
}

#[test]
fn unread_counts_are_per_thread_and_clear_when_the_thread_is_read() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    say(&alice, &bob, &transport, "root");
    sync(&bob, &transport);
    bob.store.accept_request(format!("dm:{}", alice.user)).unwrap();
    let root = first_message_id(&alice, &bob);
    say(&alice, &bob, &transport, "another top-level message");
    reply(&alice, &bob, &transport, &root, "reply 1");
    reply(&alice, &bob, &transport, &root, "reply 2");
    sync(&bob, &transport);
    let summary = |p: &Party, peer: &Party| p.store.list_thread_summaries(format!("dm:{}", peer.user)).unwrap().remove(0);
    assert_eq!(summary(&bob, &alice).unread, 2, "two replies not yet seen");
    assert_eq!(summary(&alice, &bob).unread, 0, "my own replies are not unread to me");
    bob.store.mark_thread_read(root.clone()).unwrap();
    assert_eq!(summary(&bob, &alice).unread, 0);
    reply(&alice, &bob, &transport, &root, "reply 3");
    sync(&bob, &transport);
    assert_eq!(summary(&bob, &alice).unread, 1, "only what is new since");
}

#[test]
fn replies_arrive_in_any_order_and_the_thread_is_still_right() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    let (alice_msg, _) = ("x", 0);
    let _ = alice_msg;
    // Establish the sessions both ways first, so the next two are ordinary Olm messages.
    say(&alice, &bob, &transport, "hello");
    sync(&bob, &transport);
    bob.store.accept_request(format!("dm:{}", alice.user)).unwrap();
    say(&bob, &alice, &transport, "hi");
    sync(&alice, &transport);
    let root = alice.store.queue_text(format!("dm:{}", bob.user), "the root".into()).unwrap();
    let r1 = alice.store.queue_reply(format!("dm:{}", bob.user), root.id.clone(), "reply one".into()).unwrap();
    let r2 = alice.store.queue_reply(format!("dm:{}", bob.user), root.id.clone(), "reply two".into()).unwrap();
    alice.store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    // The network swaps them: the replies and the root arrive newest first.
    server.state.lock().unwrap().mailbox.reverse();
    sync(&bob, &transport);
    sync(&bob, &transport);
    let thread: Vec<String> = bob.store.list_thread(root.id.clone()).unwrap().into_iter().map(|m| m.id).collect();
    assert_eq!(thread, vec![root.id.clone(), r1.id, r2.id], "the order is the sender's, not the arrival order");
    assert_eq!(bob.store.list_thread_summaries(format!("dm:{}", alice.user)).unwrap()[0].reply_count, 2);
    let timeline = texts(&bob, &alice);
    assert_eq!(timeline, vec!["hello", "hi", "the root"]);
}

#[test]
fn a_reply_names_its_root_only_inside_the_encrypted_payload_and_its_parents_are_the_threads() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    say(&alice, &bob, &transport, "root");
    sync(&bob, &transport);
    let root = first_message_id(&alice, &bob);
    let first = alice.store.queue_reply(format!("dm:{}", bob.user), root.clone(), "one".into()).unwrap();
    let second = alice.store.queue_reply(format!("dm:{}", bob.user), root.clone(), "two".into()).unwrap();
    alice.store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    // What the server holds is ciphertext: the root's id is nowhere in it.
    for item in server.state.lock().unwrap().mailbox.iter() {
        assert!(!item.2.contains(&root), "the server's copy does not name the root");
    }
    // The first reply's parent is the root; the second's is the first reply (the thread's own heads).
    let parents = |id: &str| -> String {
        alice.store.lock().query_row("SELECT parents FROM messages WHERE id = ?1", params![id], |r| r.get(0)).unwrap()
    };
    assert_eq!(parents(&first.id), format!("[\"{root}\"]"));
    assert_eq!(parents(&second.id), format!("[\"{}\"]", first.id));
}

#[test]
fn a_search_hit_in_a_reply_names_its_thread_and_in_chat_find_skips_replies() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    say(&alice, &bob, &transport, "the fractions lesson plan");
    sync(&bob, &transport);
    bob.store.accept_request(format!("dm:{}", alice.user)).unwrap();
    let root = first_message_id(&alice, &bob);
    reply(&bob, &alice, &transport, &root, "I will review the fractions tonight");
    sync(&alice, &transport);

    let hits = alice.store.search_messages("fractions".into(), None, 10).unwrap();
    assert_eq!(hits.len(), 2);
    let in_thread: Vec<_> = hits.iter().filter(|h| h.thread_root.is_some()).collect();
    assert_eq!(in_thread.len(), 1);
    assert_eq!(in_thread[0].thread_root.as_deref(), Some(root.as_str()), "the hit opens that thread");
    let in_chat = alice.store.search_messages("fractions".into(), Some(format!("dm:{}", bob.user)), 10).unwrap();
    assert_eq!(in_chat.len(), 1, "in-chat find steps through the timeline, where replies are not");
    assert!(in_chat[0].thread_root.is_none());
}

// ---------------------------------------------------------------- sealed sender (LIME-96)

use sha2::{Digest, Sha256};

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// What the fake server should hold for a user whose delivery key is `key`: SHA-256(HKDF access key), hex.
fn expected_hash(key: &[u8]) -> String {
    hex(&Sha256::digest(crate::store::delivery::access_key(key)))
}

/// Alice starts the chat, Bob accepts: both hold each other's delivery keys afterwards.
fn befriend(alice: &Party, bob: &Party, transport: &Arc<dyn Transport>) {
    alice.store.start_dm(bob.user.clone(), bob.user.clone()).unwrap();
    say(alice, bob, transport, "hello");
    sync(bob, transport);
    bob.store.accept_request(format!("dm:{}", alice.user)).unwrap();
    say(bob, alice, transport, "hi, I accepted");
    sync(alice, transport);
}

fn mailbox_of(server: &Arc<FakeServer>, device: &str) -> Vec<(bool, Option<String>)> {
    server.state.lock().unwrap().mailbox.iter().filter(|m| m.1 == device).map(|m| (m.3, m.4.clone())).collect()
}

#[test]
fn the_delivery_key_is_made_once_and_only_its_hash_goes_to_the_server() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let key = alice.store.test_delivery_key();
    assert_eq!(key.len(), 32);
    let held = server.state.lock().unwrap().delivery_access.get("alice").cloned();
    assert_eq!(held, Some(expected_hash(&key)), "the server holds SHA-256(HKDF(key)), not the key");
    assert_ne!(held, Some(hex(&key)));
    // Registering again changes nothing.
    alice.store.register_device(transport, alice.token.clone()).unwrap();
    assert_eq!(alice.store.test_delivery_key(), key);
    assert_eq!(server.state.lock().unwrap().delivery_access.get("alice").cloned(), held);
}

#[test]
fn a_strangers_first_message_stays_identified_and_lands_in_requests() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    say(&alice, &bob, &transport, "hello, we have not met");
    let items = mailbox_of(&server, &bob.device);
    assert_eq!(items, vec![(true, Some("alice".to_string()))], "identified: the server sees who sent it");
    assert_eq!(sync(&bob, &transport).received, 1);
    assert!(conversation(&bob, &alice).unwrap().request_state == "pending");
}

#[test]
fn after_accept_both_sides_hold_each_others_keys_and_later_sends_are_sealed() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    assert_eq!(alice.store.sealed_contact_count().unwrap(), 1, "Alice holds Bob's key");
    assert_eq!(bob.store.sealed_contact_count().unwrap(), 1, "Bob holds Alice's key");

    let before = server.state.lock().unwrap().sends_without_token;
    say(&alice, &bob, &transport, "now this is sealed");
    say(&bob, &alice, &transport, "and so is this");
    assert!(server.state.lock().unwrap().sends_without_token >= before + 2, "sent with no token");
    // The server's copy of a sealed item has no sender at all.
    for device in [&alice.device, &bob.device] {
        for (identified, sender) in mailbox_of(&server, device) {
            assert!(!identified && sender.is_none(), "a sealed item stores no sender");
        }
    }
    assert_eq!(sync(&bob, &transport).received, 1);
    assert_eq!(sync(&alice, &transport).received, 1);
    assert!(texts(&bob, &alice).contains(&"now this is sealed".to_string()));
    assert!(texts(&alice, &bob).contains(&"and so is this".to_string()));
    // The delivery-key shares were not messages: nothing extra is shown.
    assert_eq!(texts(&bob, &alice), vec!["hello", "hi, I accepted", "now this is sealed", "and so is this"], "only the messages are shown");
    assert_eq!(conversation(&bob, &alice).unwrap().unread, 2, "the share did not count as unread");
}

#[test]
fn a_tampered_sender_certificate_is_not_shown() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    let shown_before = texts(&bob, &alice);
    // Alice's device key no longer chains to her master key.
    let wire = alice.store.test_forge_sealed(&bob.user, "forged", |inner| {
        let mut signature = inner.sender_cert.master_signature.clone().into_bytes();
        signature[3] = if signature[3] == b'A' { b'B' } else { b'A' };
        inner.sender_cert.master_signature = String::from_utf8(signature).unwrap();
    });
    server.inject(&bob.device, &wire, false, None);
    let report = sync(&bob, &transport);
    assert_eq!(report.received, 0);
    assert_eq!(texts(&bob, &alice), shown_before, "never shown");
    assert_eq!(pending_rows(&bob).last().map(|r| r.0.clone()), Some("invalid".to_string()), "kept, with its reason");
}

#[test]
fn a_sealed_item_that_claims_to_be_someone_else_is_not_shown_and_is_no_key_change() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    let (mallory, _) = party(&server, "mallory", 3);
    befriend(&alice, &bob, &transport);
    // Mallory writes to Bob (identified; a stranger), so she has a session with him; then she forges a sealed
    // message that says it is from Alice, with her own certificate.
    say(&mallory, &bob, &transport, "hello, a stranger");
    sync(&bob, &transport);
    let shown_before = texts(&bob, &alice);
    let wire = mallory.store.test_forge_sealed(&bob.user, "I am Alice", |inner| {
        inner.sender_user = "alice".into();
        inner.op.conversation_id = crate::protocol::dm_conversation_id("alice", "bob");
    });
    server.inject(&bob.device, &wire, false, None);
    sync(&bob, &transport);
    assert_eq!(texts(&bob, &alice), shown_before, "Alice's chat is untouched");
    assert!(!conversation(&bob, &alice).unwrap().key_change_pending, "a forgery cannot raise a false key-change prompt");
    // And a sealed message from someone Bob has no pinned key for is never shown either (here Bob forgets
    // Mallory's key, so she is unknown to him).
    bob.store.lock().execute("DELETE FROM peers WHERE user_id = 'mallory'", []).unwrap();
    let stranger = mallory.store.test_forge_sealed(&bob.user, "sealed from a stranger", |_| {});
    server.inject(&bob.device, &stranger, false, None);
    sync(&bob, &transport);
    assert!(texts(&bob, &mallory).iter().all(|t| t != "sealed from a stranger"));
    assert!(pending_rows(&bob).iter().any(|r| r.0 == "invalid"));
}

#[test]
fn a_block_rotates_the_key_the_blocked_send_falls_back_silently_and_the_others_still_deliver() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    let (carol, _) = party(&server, "carol", 3);
    let (dave, _) = party(&server, "dave", 4);
    befriend(&alice, &bob, &transport);
    befriend(&alice, &carol, &transport);
    // Dave is a stranger who wrote to Alice: a pending request.
    say(&dave, &alice, &transport, "hello from a stranger");
    sync(&alice, &transport);
    let old_hash = server.state.lock().unwrap().delivery_access.get("alice").cloned();

    // Alice blocks Bob: a new key, for everyone but Bob (and not for the stranger).
    alice.store.block_sender(format!("dm:{}", bob.user)).unwrap();
    assert_eq!(alice.store.test_queued_shares(), vec!["carol".to_string()], "the accepted contacts except Bob");
    alice.store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    let new_hash = server.state.lock().unwrap().delivery_access.get("alice").cloned();
    assert_ne!(new_hash, old_hash, "the server now holds the hash of the new key");
    assert_eq!(new_hash, Some(expected_hash(&alice.store.test_delivery_key())));
    assert_eq!(sync(&carol, &transport).received, 0, "the share is not a message");

    // Bob (holding the old key) is refused by the server, and the app says nothing: his message goes identified
    // straight away and reads "Sent". A blocked person learns nothing.
    let sent = bob.store.send_text_identified(transport.clone(), bob.token.clone(), alice.user.clone(), "are you there?".to_string());
    assert!(sent.is_ok());
    let state_of = |p: &Party, text: &str| p.store.list_messages(format!("dm:{}", alice.user)).unwrap().into_iter().find(|m| m.text == text).unwrap().local_state;
    assert_eq!(state_of(&bob, "are you there?"), "sent", "never \"Not delivered\" for this");
    assert_eq!(mailbox_of(&server, &alice.device), vec![(true, Some("bob".to_string()))], "stored identified");
    assert_eq!(bob.store.sealed_contact_count().unwrap(), 0, "no more sealed sends to Alice until she shares a new key");
    // No sealed attempt is repeated: the next message is simply sent identified.
    let _ = bob.store.send_text_identified(transport.clone(), bob.token.clone(), alice.user.clone(), "second".to_string());
    assert_eq!(state_of(&bob, "second"), "sent");
    assert!(mailbox_of(&server, &alice.device).iter().all(|m| m.0), "both identified");

    // Carol holds the new key: her sealed message still delivers.
    say(&carol, &alice, &transport, "still here");
    assert_eq!(sync(&alice, &transport).received, 1);
    assert_eq!(texts(&alice, &carol).last().unwrap(), "still here");

    // Alice (who blocked him) reads and hides what Bob sent.
    sync(&alice, &transport);
    assert!(alice.store.list_conversations().unwrap().iter().all(|c| c.id != format!("dm:{}", bob.user)), "hidden for the blocker");

    // Alice unblocks Bob: he is given the current key, and sealed sends resume.
    alice.store.unblock(format!("dm:{}", bob.user)).unwrap();
    alice.store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    sync(&bob, &transport);
    assert_eq!(bob.store.sealed_contact_count().unwrap(), 1, "Bob holds Alice's new key");
    say(&bob, &alice, &transport, "third");
    let item = mailbox_of(&server, &alice.device);
    assert!(item.iter().any(|m| !m.0 && m.1.is_none()), "sealed again after the unblock");
    assert_eq!(sync(&alice, &transport).received, 1, "the sealed one");
    assert!(texts(&alice, &bob).contains(&"third".to_string()));
}

#[test]
fn a_new_phone_gets_a_new_delivery_key_and_the_old_key_falls_back_to_identified() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    let old = server.state.lock().unwrap().delivery_access.get("bob").cloned();

    let (bob2, _) = bob_with_new_keys(&server);
    let new = server.state.lock().unwrap().delivery_access.get("bob").cloned();
    assert_ne!(old, new, "a new phone means a new delivery key");
    assert_eq!(new, Some(expected_hash(&bob2.store.test_delivery_key())));
    assert_eq!(bob2.store.sealed_contact_count().unwrap(), 0, "the new phone holds nobody's key yet");

    // Alice accepts Bob's new key; the key she held for Bob is no longer his, so the server refuses her sealed send,
    // and the app silently sends it identified: it reads "Sent" and reaches his new phone.
    // (Her first try meets the new key and waits for her to accept it, as in LIME-95-fix.)
    let first = alice.store.send_text_identified(transport.clone(), alice.token.clone(), bob2.user.clone(), "welcome back".to_string());
    assert!(first.is_err());
    alice.store.trust_new_key(format!("dm:{}", bob2.user)).unwrap();
    assert_eq!(alice.store.test_queued_shares(), vec!["bob".to_string()], "Bob's new phone is given her key");
    let mine = alice.store.list_messages(format!("dm:{}", bob2.user)).unwrap().into_iter().find(|m| m.text == "welcome back").unwrap();
    alice.store.retry_message(mine.id.clone()).unwrap();
    alice.store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    let mine = alice.store.list_messages(format!("dm:{}", bob2.user)).unwrap().into_iter().find(|m| m.text == "welcome back").unwrap();
    assert_eq!(mine.local_state, "sent", "no \"Not delivered\": the fallback is silent");
    let report = sync(&bob2, &transport);
    assert!(report.received >= 1);
    assert!(texts(&bob2, &alice).contains(&"welcome back".to_string()), "the new phone gets it (in Requests: it has no history)");
    assert_eq!(bob2.store.sealed_contact_count().unwrap(), 1, "Alice's share reached the new phone");
}

#[test]
fn chats_accepted_before_this_version_are_given_the_delivery_key_after_the_upgrade() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    // An old chat: accepted, with messages, and no delivery keys either way (as the database was at version 9).
    say(&alice, &bob, &transport, "from before");
    sync(&bob, &transport);
    bob.store.accept_request("dm:alice".into()).unwrap();
    {
        let conn = alice.store.lock();
        conn.execute_batch(
            "DELETE FROM share_queue; DELETE FROM key_shared; DELETE FROM contact_delivery_keys;
             DROP TABLE group_ops; DROP TABLE group_members; DROP TABLE group_outbox; DROP TABLE group_outbound_sessions; DROP TABLE group_inbound_sessions; ALTER TABLE conversations DROP COLUMN group_emoji; ALTER TABLE peers DROP COLUMN verified_at;
             DROP TABLE delivery_state; DROP TABLE contact_delivery_keys; DROP TABLE share_queue; DROP TABLE key_shared;
             PRAGMA user_version = 9;",
        )
        .unwrap();
    }
    let path = alice._dir.path().join("lime.db").to_string_lossy().into_owned();
    drop(alice.store);
    let reopened = LimeStore::open(path, vec![1u8; 32]).unwrap();
    assert_eq!(reopened.test_queued_shares(), vec!["bob".to_string()], "the accepted chat is queued to be given the key");
}

// ---------------------------------------------------------------- group chats (LIME-97)

use crate::protocol::group::Kind;

fn deliver(p: &Party, transport: &Arc<dyn Transport>) {
    p.store.deliver_queued(transport.clone(), p.token.clone()).unwrap();
}

fn group_chat(p: &Party) -> Option<crate::ConversationSummary> {
    p.store.list_conversations().unwrap().into_iter().find(|c| c.id.starts_with("grp:"))
}

fn say_in(p: &Party, transport: &Arc<dyn Transport>, chat: &str, text: &str) {
    p.store.queue_text(chat.to_owned(), text.to_owned()).unwrap();
    deliver(p, transport);
}

fn group_texts(p: &Party, chat: &str) -> Vec<String> {
    p.store.list_messages(chat.to_owned()).unwrap().into_iter().filter(|m| m.local_state != "system").map(|m| m.text).collect()
}

fn names_in(p: &Party, chat: &str) -> Vec<(String, String)> {
    p.store.group_details(chat.to_owned()).unwrap().members.into_iter().map(|m| (m.user_id, m.role)).collect()
}

/// Puts a device's waiting items in the reverse order (the cursor numbers stay ascending): out-of-order arrival.
fn reverse_mailbox(server: &Arc<FakeServer>, device: &str) {
    let mut state = server.state.lock().unwrap();
    let slots: Vec<usize> = state.mailbox.iter().enumerate().filter(|(_, m)| m.1 == device).map(|(i, _)| i).collect();
    let cursors: Vec<i64> = slots.iter().map(|i| state.mailbox[*i].0).collect();
    let mut items: Vec<_> = slots.iter().map(|i| state.mailbox[*i].clone()).collect();
    items.reverse();
    for ((slot, item), cursor) in slots.iter().zip(items).zip(cursors) {
        state.mailbox[*slot] = (cursor, item.1, item.2, item.3, item.4);
    }
}

/// The Megolm items (group messages) waiting for a device.
fn group_items(server: &Arc<FakeServer>, device: &str) -> Vec<String> {
    let state = server.state.lock().unwrap();
    state.mailbox.iter().filter(|m| m.1 == device).map(|m| m.2.clone()).filter(|w| vodozemac::base64_decode(w).map(|b| b[0] == 2).unwrap_or(false)).collect()
}

/// Alice makes "Grade 4 Team" with Bob and Carol; everyone syncs.
fn team(server: &Arc<FakeServer>) -> (Party, Party, Party, Arc<dyn Transport>, String) {
    let (alice, transport) = party(server, "alice", 1);
    let (bob, _) = party(server, "bob", 2);
    let (carol, _) = party(server, "carol", 3);
    let chat = alice.store.create_group("Grade 4 Team".into(), Some("🍎".into()), vec!["bob".into(), "carol".into()]).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    sync(&carol, &transport);
    (alice, bob, carol, transport, chat)
}

#[test]
fn a_group_of_three_is_created_and_everyone_receives_it() {
    let server = FakeServer::new();
    let (alice, bob, carol, _transport, chat) = team(&server);
    for p in [&bob, &carol] {
        let group = group_chat(p).expect("the group arrived");
        assert_eq!((group.id.as_str(), group.title.as_str(), group.is_group), (chat.as_str(), "Grade 4 Team", true));
        assert_eq!(group.group_emoji.as_deref(), Some("🍎"));
        assert_eq!(group.members.len(), 2, "the other two (never me)");
        // Nobody has met Alice: it waits in Requests (a person you do not know made it).
        assert_eq!(group.request_state, "pending");
    }
    let details = alice.store.group_details(chat.clone()).unwrap();
    assert_eq!((details.name.as_str(), details.my_role.as_str(), details.members.len()), ("Grade 4 Team", "owner", 3));
    assert!(details.can_rename && details.can_add);
    assert_eq!(names_in(&bob, &chat), names_in(&alice, &chat), "the same people and roles on every phone");
    // The timeline says so.
    let lines: Vec<String> = bob.store.list_messages(chat.clone()).unwrap().into_iter().filter(|m| m.local_state == "system").map(|m| m.text).collect();
    assert_eq!(lines.len(), 1);
    assert!(lines[0].ends_with("created the group “Grade 4 Team”"), "{}", lines[0]);
    assert_eq!(alice.store.list_messages(chat.clone()).unwrap()[0].text, "You created the group “Grade 4 Team”");
    assert_eq!(bob.store.list_conversations().unwrap()[0].unread, 0, "a system line is not unread");
}

#[test]
fn an_invite_from_a_contact_goes_straight_into_messages() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    let (carol, _) = party(&server, "carol", 3);
    befriend(&alice, &bob, &transport);
    alice.store.create_group("Staff".into(), None, vec!["bob".into(), "carol".into()]).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    sync(&carol, &transport);
    assert_eq!(group_chat(&bob).unwrap().request_state, "accepted", "Alice is Bob's contact");
    assert_eq!(group_chat(&carol).unwrap().request_state, "pending", "Carol does not know Alice");
    // Accepting moves it into Messages.
    carol.store.accept_request(group_chat(&carol).unwrap().id).unwrap();
    assert_eq!(group_chat(&carol).unwrap().request_state, "accepted");
}

#[test]
fn megolm_messages_decrypt_for_every_member_and_share_one_ciphertext() {
    let server = FakeServer::new();
    let (alice, bob, carol, transport, chat) = team(&server);
    say_in(&alice, &transport, &chat, "hello team");
    // One ciphertext, sent to both devices (the server's batch shape).
    let items: Vec<String> = {
        let state = server.state.lock().unwrap();
        state.mailbox.iter().filter(|m| m.1 == bob.device || m.1 == carol.device).filter(|m| vodozemac::base64_decode(&m.2).map(|w| w[0] == 2).unwrap_or(false)).map(|m| m.2.clone()).collect()
    };
    assert_eq!(items.len(), 2);
    assert_eq!(items[0], items[1], "the same Megolm ciphertext for both devices");
    assert_eq!(sync(&bob, &transport).received, 1);
    assert_eq!(sync(&carol, &transport).received, 1);
    assert_eq!(group_texts(&bob, &chat), vec!["hello team"]);
    assert_eq!(group_texts(&carol, &chat), vec!["hello team"]);
    let from = bob.store.list_messages(chat.clone()).unwrap().into_iter().find(|m| m.text == "hello team").unwrap();
    assert_eq!(from.sender_id.as_deref(), Some("alice"));
    // Bob answers; Alice and Carol read it, and unread counts.
    say_in(&bob, &transport, &chat, "hi all");
    sync(&alice, &transport);
    sync(&carol, &transport);
    assert_eq!(group_texts(&alice, &chat), vec!["hello team", "hi all"]);
    assert_eq!(group_texts(&carol, &chat), vec!["hello team", "hi all"]);
    assert_eq!(group_chat(&alice).unwrap().unread, 1);
}

#[test]
fn a_removed_member_cannot_read_what_follows() {
    let server = FakeServer::new();
    let (alice, bob, carol, transport, chat) = team(&server);
    say_in(&alice, &transport, &chat, "before");
    sync(&bob, &transport);
    sync(&carol, &transport);
    assert_eq!(group_texts(&carol, &chat), vec!["before"]);

    alice.store.remove_group_member(chat.clone(), "carol".into()).unwrap();
    say_in(&alice, &transport, &chat, "after the removal"); // delivers the remove op first, then a new session
    // The message after the removal goes to Bob only, under a session Carol was never given.
    let for_bob = group_items(&server, &bob.device);
    assert_eq!(for_bob.len(), 1, "one new group message waits for Bob");
    assert!(group_items(&server, &carol.device).is_empty(), "nothing of it is sent to Carol");
    sync(&bob, &transport);
    sync(&carol, &transport);
    assert_eq!(group_texts(&bob, &chat), vec!["before", "after the removal"]);
    assert!(group_chat(&carol).is_none(), "Carol was removed: the group is gone from her Messages");
    // Even a copy of that ciphertext in Carol's hands is useless.
    server.inject(&carol.device, &for_bob[0], false, None);
    sync(&carol, &transport);
    assert_eq!(group_texts(&carol, &chat), vec!["before"], "she cannot read the message sent after her removal");
    assert!(pending_rows(&carol).iter().any(|r| r.0 == "no_session"), "kept unread, for lack of a key");
    assert_eq!(names_in(&alice, &chat).len(), 2);
    let lines: Vec<String> = alice.store.list_messages(chat.clone()).unwrap().into_iter().filter(|m| m.local_state == "system").map(|m| m.text).collect();
    assert!(lines.iter().any(|l| l == "You removed Carol" || l.contains("removed")), "{lines:?}");
}

#[test]
fn a_late_joiner_cannot_read_what_was_said_before_joining() {
    let server = FakeServer::new();
    let (alice, bob, _carol, transport, chat) = team(&server);
    let (dave, _) = party(&server, "dave", 4);
    say_in(&alice, &transport, &chat, "before dave");
    // Keep a copy of that ciphertext, as an eavesdropper (or the server) could.
    let old = group_items(&server, &bob.device).pop().expect("the message waiting for Bob");
    sync(&bob, &transport);
    alice.store.add_group_members(chat.clone(), vec!["dave".into()]).unwrap();
    say_in(&alice, &transport, &chat, "after dave");
    sync(&bob, &transport);
    sync(&dave, &transport);
    // Dave has the group (from the history he was given) and reads the new message...
    assert_eq!(group_chat(&dave).unwrap().title, "Grade 4 Team");
    assert_eq!(names_in(&dave, &chat), names_in(&alice, &chat), "his state, replayed from the history, is the same");
    assert_eq!(group_texts(&dave, &chat), vec!["after dave"]);
    // ...but not the one from before, even given its ciphertext.
    server.inject(&dave.device, &old, false, None);
    sync(&dave, &transport);
    assert_eq!(group_texts(&dave, &chat), vec!["after dave"]);
    assert_eq!(group_texts(&bob, &chat), vec!["before dave", "after dave"]);
}

#[test]
fn every_phone_reaches_the_same_state_whatever_order_the_ops_arrive_in() {
    let server = FakeServer::new();
    let (alice, bob, carol, transport, chat) = team(&server);
    let (dave, _) = party(&server, "dave", 4);
    // Alice makes several changes before anyone hears of them.
    alice.store.add_group_members(chat.clone(), vec!["dave".into()]).unwrap();
    alice.store.rename_group(chat.clone(), "Fourth Grade".into()).unwrap();
    alice.store.set_group_admin(chat.clone(), "bob".into(), true).unwrap();
    alice.store.remove_group_member(chat.clone(), "dave".into()).unwrap();
    deliver(&alice, &transport);
    // Bob gets them in the order sent; Carol in the reverse order.
    reverse_mailbox(&server, &carol.device);
    sync(&bob, &transport);
    sync(&carol, &transport);
    let reference = alice.store.group_details(chat.clone()).unwrap();
    assert_eq!(reference.name, "Fourth Grade");
    for p in [&bob, &carol] {
        let details = p.store.group_details(chat.clone()).unwrap();
        assert_eq!((details.name.clone(), names_in(p, &chat)), (reference.name.clone(), names_in(&alice, &chat)), "{}", p.user);
    }
    assert_eq!(names_in(&carol, &chat).iter().map(|m| m.0.clone()).collect::<Vec<_>>(), vec!["alice", "bob", "carol"], "Dave was added and removed again");
    let _ = dave;
}

#[test]
fn only_admins_rename_and_a_forged_rename_from_a_member_is_ignored_everywhere() {
    let server = FakeServer::new();
    let (alice, bob, carol, transport, chat) = team(&server);
    assert!(bob.store.rename_group(chat.clone(), "Mine".into()).is_err(), "a member may not rename");
    assert!(!bob.store.group_details(chat.clone()).unwrap().can_rename);
    // Bob forges one anyway (skipping the check on his own phone): nobody applies it, including Bob's own replay.
    let state = bob.store.load_or_create_account().unwrap();
    bob.store.make_group_op(&state, "bob", crate::store::groups::group_id_of(&chat).unwrap(), None, Kind::Rename { name: "Bob's group".into() }).unwrap();
    deliver(&bob, &transport);
    sync(&alice, &transport);
    sync(&carol, &transport);
    for p in [&alice, &bob, &carol] {
        assert_eq!(p.store.group_details(chat.clone()).unwrap().name, "Grade 4 Team", "{}", p.user);
    }
    // The owner makes Bob an admin: now his rename counts, last writer by clock.
    alice.store.set_group_admin(chat.clone(), "bob".into(), true).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    bob.store.rename_group(chat.clone(), "Fourth Grade".into()).unwrap();
    deliver(&bob, &transport);
    sync(&alice, &transport);
    sync(&carol, &transport);
    for p in [&alice, &bob, &carol] {
        assert_eq!(p.store.group_details(chat.clone()).unwrap().name, "Fourth Grade", "{}", p.user);
    }
    assert_eq!(group_chat(&carol).unwrap().title, "Fourth Grade", "the conversation's title follows");
}

#[test]
fn leaving_ends_a_persons_part_in_the_group() {
    let server = FakeServer::new();
    let (alice, bob, carol, transport, chat) = team(&server);
    carol.store.leave_group(chat.clone()).unwrap();
    deliver(&carol, &transport);
    sync(&alice, &transport);
    sync(&bob, &transport);
    assert!(group_chat(&carol).is_none(), "gone from Carol's Messages");
    assert_eq!(names_in(&alice, &chat).len(), 2);
    assert!(alice.store.list_messages(chat.clone()).unwrap().iter().any(|m| m.local_state == "system" && m.text.contains("left")));
    // What is said afterwards never reaches her, and nothing is shown if a copy does.
    say_in(&alice, &transport, &chat, "after Carol left");
    assert_eq!(server.mailbox_len(&carol.device), 0, "nothing is sent to a person who left");
    sync(&bob, &transport);
    assert_eq!(group_texts(&bob, &chat), vec!["after Carol left"]);
    assert!(carol.store.list_conversations().unwrap().is_empty());
    // The owner leaving hands the group to the oldest member.
    alice.store.leave_group(chat.clone()).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    assert_eq!(bob.store.group_details(chat.clone()).unwrap().my_role, "owner");
}

#[test]
fn a_message_that_arrives_before_its_key_waits_and_reads_when_the_key_arrives() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    let chat = alice.store.create_group("Early".into(), None, vec!["bob".into()]).unwrap();
    say_in(&alice, &transport, &chat, "ahead of its key"); // delivers the create op, the key, then the message
    // Put the message first in Bob's mailbox.
    assert_eq!(server.mailbox_len(&bob.device), 3, "the create op, the session key, the message");
    reverse_mailbox(&server, &bob.device);
    let report = sync(&bob, &transport);
    assert_eq!(report.pending, 0, "everything was read in the end");
    assert_eq!(group_texts(&bob, &chat), vec!["ahead of its key"]);
}

#[test]
fn threads_and_formatting_work_in_a_group() {
    let server = FakeServer::new();
    let (alice, bob, _carol, transport, chat) = team(&server);
    say_in(&alice, &transport, &chat, "Plan for **Friday**");
    sync(&bob, &transport);
    let root = bob.store.list_messages(chat.clone()).unwrap().into_iter().find(|m| m.text.contains("Friday")).unwrap();
    assert_eq!(root.text, "Plan for **Friday**", "the Markdown arrives as written");
    bob.store.queue_reply(chat.clone(), root.id.clone(), "I can bring the forms".into()).unwrap();
    deliver(&bob, &transport);
    sync(&alice, &transport);
    let summaries = alice.store.list_thread_summaries(chat.clone()).unwrap();
    assert_eq!(summaries.len(), 1);
    assert_eq!((summaries[0].root_id.as_str(), summaries[0].reply_count), (root.id.as_str(), 1));
    assert_eq!(group_texts(&alice, &chat), vec!["Plan for **Friday**"], "the reply stays out of the timeline");
}

#[test]
fn a_group_is_limited_to_a_hundred_people_and_a_name_to_fifty_characters() {
    let server = FakeServer::new();
    let (alice, _) = party(&server, "alice", 1);
    let many: Vec<String> = (0..100).map(|i| format!("u{i}")).collect();
    assert!(alice.store.create_group("Big".into(), None, many).is_err(), "100 others plus me is 101");
    assert!(alice.store.create_group("x".repeat(51), None, vec!["u1".into()]).is_err());
    assert!(alice.store.create_group("  ".into(), None, vec!["u1".into()]).is_err());
    assert!(alice.store.create_group("Fine".into(), None, vec![]).is_err(), "a group needs another person");
}

// ---------------------------------------------------------------- LIME-97b: verified in person

#[test]
fn a_scanned_fingerprint_that_matches_marks_the_person_verified_and_a_wrong_one_does_not() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    let theirs = bob.store.key_info().unwrap().unwrap().fingerprint;
    let ask = |fingerprint: &str| {
        alice.store.verify_in_person(transport.clone(), alice.token.clone(), bob.user.clone(), fingerprint.to_owned()).unwrap()
    };

    // Someone else's code, a short one and nonsense never verify.
    let others = alice.store.key_info().unwrap().unwrap().fingerprint;
    assert_eq!(ask(&others), crate::Verification::Mismatch);
    assert_eq!(ask("A1B2"), crate::Verification::Mismatch);
    assert_eq!(ask(""), crate::Verification::Mismatch);
    assert!(!alice.store.is_verified(bob.user.clone()).unwrap());

    // Bob's own code does, however it was typed or scanned (spacing and case do not matter).
    assert_eq!(ask(&theirs.to_lowercase().replace(' ', "")), crate::Verification::Verified);
    assert!(alice.store.is_verified(bob.user.clone()).unwrap());

    // The chat shows it, and it survives more messages.
    say(&alice, &bob, &transport, "hello");
    assert!(conversation(&alice, &bob).unwrap().verified);
}

#[test]
fn a_new_key_for_a_verified_person_must_be_accepted_and_is_no_longer_verified() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    say(&alice, &bob, &transport, "hi");
    let theirs = bob.store.key_info().unwrap().unwrap().fingerprint;
    assert_eq!(
        alice.store.verify_in_person(transport.clone(), alice.token.clone(), bob.user.clone(), theirs).unwrap(),
        crate::Verification::Verified
    );

    let (bob2, _) = bob_with_new_keys(&server);
    let new_code = bob2.store.key_info().unwrap().unwrap().fingerprint;
    // Scanning the new phone's code does not skip the key-change check.
    assert_eq!(
        alice.store.verify_in_person(transport.clone(), alice.token.clone(), bob2.user.clone(), new_code).unwrap(),
        crate::Verification::KeyChanged
    );
    assert!(!conversation(&alice, &bob2).unwrap().verified, "not verified while the key change waits");
    alice.store.trust_new_key(format!("dm:{}", bob2.user)).unwrap();
    assert!(!conversation(&alice, &bob2).unwrap().verified, "accepting a new key clears the old verification");
}
