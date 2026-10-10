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
             DROP TABLE group_ops; DROP TABLE group_members; DROP TABLE group_outbox; DROP TABLE group_outbound_sessions; DROP TABLE group_inbound_sessions; ALTER TABLE conversations DROP COLUMN group_emoji; ALTER TABLE peers DROP COLUMN verified_at; DROP TABLE profile_key; DROP TABLE contact_profile_keys; DROP TABLE my_photo; DROP TABLE photos; DROP TABLE photo_notices; DROP TABLE message_attachments; DROP TABLE attachment_parts; DROP TABLE transfers; DROP TABLE contact_labels; ALTER TABLE conversations DROP COLUMN group_photo; ALTER TABLE conversations DROP COLUMN marked_unread; ALTER TABLE conversations DROP COLUMN hidden; DROP TABLE reactions; DROP TABLE my_status; DROP TABLE status_notices; DROP TABLE contact_status; DROP TABLE message_op_outbox; DROP TABLE early_message_ops; ALTER TABLE messages DROP COLUMN edited; ALTER TABLE messages DROP COLUMN edit_hlc; ALTER TABLE messages DROP COLUMN deleted; ALTER TABLE messages DROP COLUMN hidden; ALTER TABLE messages DROP COLUMN forwarded; ALTER TABLE messages DROP COLUMN link_preview;
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
    assert!(conversation(&alice, &bob).unwrap().verified_at.is_some_and(|at| at > 1_600_000_000_000), "and when it was");
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

// ---------------------------------------------------------------- LIME-98b: profile photos

const PHOTO: &[u8] = b"\xff\xd8\xff\xe0 a very recognisable profile photo body, repeated: ";

fn photo_bytes() -> Vec<u8> {
    PHOTO.repeat(40)
}

fn profile_key_of(p: &Party) -> Vec<u8> {
    crate::store::photos::current_key(&p.store.lock(), crate::store::now_ms()).unwrap()
}

fn refresh(p: &Party, transport: &Arc<dyn Transport>) -> Vec<String> {
    p.store.refresh_photos(transport.clone(), p.token.clone(), true).unwrap()
}

#[test]
fn the_photo_key_travels_with_the_delivery_key_to_contacts_only_and_rotates_on_a_block() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    let (carol, _) = party(&server, "carol", 3);
    befriend(&alice, &bob, &transport);
    befriend(&alice, &carol, &transport);
    let first = profile_key_of(&alice);
    assert_eq!(crate::store::photos::contact_key(&bob.store.lock(), "alice").unwrap(), Some(first.clone()), "Bob holds Alice's key");
    assert_eq!(crate::store::photos::contact_key(&carol.store.lock(), "alice").unwrap(), Some(first.clone()));
    assert_eq!(crate::store::photos::contact_key(&alice.store.lock(), "bob").unwrap().map(|k| k.len()), Some(32), "and Alice holds Bob's");

    // Alice blocks Carol: the key is rotated, and only Bob is given the new one.
    alice.store.block_sender(format!("dm:{}", carol.user)).unwrap();
    let second = profile_key_of(&alice);
    assert_ne!(second, first, "a block rotates the photo key");
    deliver(&alice, &transport);
    sync(&bob, &transport);
    sync(&carol, &transport);
    assert_eq!(crate::store::photos::contact_key(&bob.store.lock(), "alice").unwrap(), Some(second.clone()), "Bob has the new key");
    assert_eq!(crate::store::photos::contact_key(&carol.store.lock(), "alice").unwrap(), Some(first), "Carol is left with the old one");
}

#[test]
fn a_contacts_only_photo_is_ciphertext_on_the_server_and_only_contacts_can_open_it() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    let (carol, _) = party(&server, "carol", 3);
    befriend(&alice, &bob, &transport);
    // Carol only ever got a message from Alice (a request): she has no photo key.
    say(&alice, &carol, &transport, "hello stranger");
    sync(&carol, &transport);
    assert_eq!(crate::store::photos::contact_key(&carol.store.lock(), "alice").unwrap(), None);

    alice.store.set_photo_visibility(transport.clone(), alice.token.clone(), "contacts".into()).unwrap();
    alice.store.set_my_photo(transport.clone(), alice.token.clone(), photo_bytes()).unwrap();

    // What the server holds: one opaque blob, nothing public, and no byte run of the photo.
    {
        let state = server.state.lock().unwrap();
        assert!(!state.objects.keys().any(|k| k.starts_with("public-avatars/")), "no public copy");
        let blobs: Vec<_> = state.objects.iter().filter(|(k, _)| k.starts_with("blobs/")).collect();
        assert_eq!(blobs.len(), 1);
        assert!(!blobs[0].1.windows(32).any(|w| w == &photo_bytes()[..32]), "the stored bytes are not the photo");
        assert_ne!(*blobs[0].1, photo_bytes());
    }

    // Bob (a contact) sees it; Carol (a stranger) and a repeat check see nothing; Alice's own copy is local.
    assert_eq!(refresh(&bob, &transport), vec!["alice".to_string()]);
    assert_eq!(bob.store.peer_photo("alice".into()).unwrap(), Some(photo_bytes()));
    assert!(refresh(&carol, &transport).is_empty());
    assert_eq!(carol.store.peer_photo("alice".into()).unwrap(), None, "a stranger sees initials");
    assert!(refresh(&bob, &transport).is_empty(), "nothing changed the second time");
    assert_eq!(alice.store.my_photo().unwrap().jpeg, Some(photo_bytes()));

    // A stranger who somehow learned a wrong key still opens nothing.
    let wrong = crate::store::delivery::random_key();
    let id = crate::store::photos::blob_id(&profile_key_of(&alice));
    let sealed = server.state.lock().unwrap().objects.get(&format!("blobs/{id}")).cloned().unwrap();
    assert_eq!(crate::store::photos::open(&wrong, &sealed), None);
}

#[test]
fn switching_visibility_moves_the_photo_between_the_public_copy_and_the_encrypted_one() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    let (carol, _) = party(&server, "carol", 3);
    befriend(&alice, &bob, &transport);
    say(&alice, &carol, &transport, "hello stranger");
    sync(&carol, &transport);

    // Everyone (the default): a plain JPEG on the server that a stranger can see.
    alice.store.set_my_photo(transport.clone(), alice.token.clone(), photo_bytes()).unwrap();
    assert_eq!(server.state.lock().unwrap().objects.get("public-avatars/alice.jpg"), Some(&photo_bytes()));
    assert!(!server.state.lock().unwrap().objects.keys().any(|k| k.starts_with("blobs/")));
    refresh(&carol, &transport);
    assert_eq!(carol.store.peer_photo("alice".into()).unwrap(), Some(photo_bytes()));

    // Only my contacts: the public copy is deleted from the server, strangers fall back to initials, Bob still sees it.
    alice.store.set_photo_visibility(transport.clone(), alice.token.clone(), "contacts".into()).unwrap();
    assert!(!server.state.lock().unwrap().objects.keys().any(|k| k.starts_with("public-avatars/")), "the public copy is gone");
    assert_eq!(server.state.lock().unwrap().objects.keys().filter(|k| k.starts_with("blobs/")).count(), 1);
    assert_eq!(refresh(&carol, &transport), vec!["alice".to_string()], "Carol's photo of Alice went away");
    assert_eq!(carol.store.peer_photo("alice".into()).unwrap(), None);
    refresh(&bob, &transport);
    assert_eq!(bob.store.peer_photo("alice".into()).unwrap(), Some(photo_bytes()));

    // Back to everyone: public again, the encrypted blob removed.
    alice.store.set_photo_visibility(transport.clone(), alice.token.clone(), "everyone".into()).unwrap();
    assert!(server.state.lock().unwrap().objects.contains_key("public-avatars/alice.jpg"));
    assert!(!server.state.lock().unwrap().objects.keys().any(|k| k.starts_with("blobs/")), "the encrypted copy is deleted");
    assert_eq!(refresh(&carol, &transport), vec!["alice".to_string()], "the stranger sees it again");

    // Remove: nothing anywhere.
    alice.store.remove_my_photo(transport.clone(), alice.token.clone()).unwrap();
    assert!(server.state.lock().unwrap().objects.is_empty());
    assert_eq!(alice.store.my_photo().unwrap().jpeg, None);
    assert_eq!(refresh(&carol, &transport), vec!["alice".to_string()], "and it is gone for her");
    assert_eq!(carol.store.peer_photo("alice".into()).unwrap(), None);
}

#[test]
fn a_block_re_uploads_the_contacts_only_photo_under_the_new_key_and_the_blocked_person_loses_it() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    let (carol, _) = party(&server, "carol", 3);
    befriend(&alice, &bob, &transport);
    befriend(&alice, &carol, &transport);
    alice.store.set_photo_visibility(transport.clone(), alice.token.clone(), "contacts".into()).unwrap();
    alice.store.set_my_photo(transport.clone(), alice.token.clone(), photo_bytes()).unwrap();
    refresh(&bob, &transport);
    refresh(&carol, &transport);
    assert!(bob.store.peer_photo("alice".into()).unwrap().is_some() && carol.store.peer_photo("alice".into()).unwrap().is_some());
    let old_id = crate::store::photos::blob_id(&profile_key_of(&alice));

    alice.store.block_sender(format!("dm:{}", carol.user)).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    sync(&carol, &transport);
    let new_id = crate::store::photos::blob_id(&profile_key_of(&alice));
    assert_ne!(new_id, old_id);
    {
        let state = server.state.lock().unwrap();
        assert!(state.objects.contains_key(&format!("blobs/{new_id}")), "re-uploaded under the new key");
        assert!(!state.objects.contains_key(&format!("blobs/{old_id}")), "the old copy is deleted");
    }
    refresh(&bob, &transport);
    assert_eq!(bob.store.peer_photo("alice".into()).unwrap(), Some(photo_bytes()), "Bob (given the new key) still sees it");
    refresh(&carol, &transport);
    assert_eq!(carol.store.peer_photo("alice".into()).unwrap(), None, "Carol, blocked, cannot find the new copy");
}

// ---------------------------------------------------------------- LIME-98b-fix: photo changes reach contacts at once

fn refresh_due(p: &Party, transport: &Arc<dyn Transport>) -> Vec<String> {
    // The ordinary refresh after a sync: not forced, so the hourly limit applies unless a notice cleared it.
    p.store.refresh_photos(transport.clone(), p.token.clone(), false).unwrap()
}

#[test]
fn a_photo_change_reaches_a_contact_within_one_sync_without_waiting_for_the_hourly_check() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    // Bob has just checked and found no photo (so the hourly limit now applies to Alice).
    assert!(refresh_due(&bob, &transport).is_empty());
    assert_eq!(bob.store.peer_photo("alice".into()).unwrap(), None);

    // Alice sets a photo: the next delivery tells Bob, and his next sync + refresh shows it.
    alice.store.set_my_photo(transport.clone(), alice.token.clone(), photo_bytes()).unwrap();
    deliver(&alice, &transport);
    let report = sync(&bob, &transport);
    assert_eq!(report.received, 0, "a control op is not a message");
    assert_eq!(refresh_due(&bob, &transport), vec!["alice".to_string()], "checked at once, not in an hour");
    assert_eq!(bob.store.peer_photo("alice".into()).unwrap(), Some(photo_bytes()));
    assert!(refresh_due(&bob, &transport).is_empty(), "and then the limit applies again");

    // Contacts-only, then removed: each change is noticed the same way.
    alice.store.set_photo_visibility(transport.clone(), alice.token.clone(), "contacts".into()).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    assert_eq!(refresh_due(&bob, &transport), vec!["alice".to_string()], "fetched again (now from the encrypted copy)");
    assert_eq!(bob.store.peer_photo("alice".into()).unwrap(), Some(photo_bytes()));
    alice.store.remove_my_photo(transport.clone(), alice.token.clone()).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    assert_eq!(refresh_due(&bob, &transport), vec!["alice".to_string()]);
    assert_eq!(bob.store.peer_photo("alice".into()).unwrap(), None);
}

#[test]
fn a_notice_is_sent_only_to_accepted_contacts_and_a_stranger_gets_none() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    let (carol, _) = party(&server, "carol", 3);
    befriend(&alice, &bob, &transport);
    say(&carol, &alice, &transport, "hello, a stranger");
    sync(&alice, &transport);
    alice.store.set_my_photo(transport.clone(), alice.token.clone(), photo_bytes()).unwrap();
    let queued = crate::store::photos::queued_notices(&alice.store.lock()).unwrap();
    assert_eq!(queued, vec!["bob".to_string()], "only the accepted contact is told");
    deliver(&alice, &transport);
    assert!(crate::store::photos::queued_notices(&alice.store.lock()).unwrap().is_empty(), "delivered, so no longer queued");
}

#[test]
fn pull_to_refresh_checks_the_people_shown_but_at_most_once_a_minute_each() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    let ask = |ids: &[&str]| bob.store.refresh_photos_of(transport.clone(), bob.token.clone(), ids.iter().map(|s| s.to_string()).collect()).unwrap();
    assert!(ask(&["alice"]).is_empty(), "first check: nothing to see yet");
    // A photo appears on the server without a notice (say the notice was lost): a second pull within the minute does not look.
    alice.store.set_my_photo(transport.clone(), alice.token.clone(), photo_bytes()).unwrap();
    let before = server.state.lock().unwrap().calls;
    assert!(ask(&["alice"]).is_empty());
    assert_eq!(server.state.lock().unwrap().calls, before, "no request within a minute of the last check");
    // After a minute it looks again, and finds it.
    bob.store.lock().execute("UPDATE photos SET checked_at = checked_at - 61000", []).unwrap();
    assert_eq!(ask(&["alice"]), vec!["alice".to_string()]);
    assert_eq!(ask(&["someone-else"]), Vec::<String>::new(), "only the people asked about are checked");
}

// ---------------------------------------------------------------- LIME-98c: encrypted attachments

fn pic(seed: u8, size: usize) -> crate::OutgoingAttachment {
    crate::OutgoingAttachment {
        bytes: (0..size).map(|i| (i as u8).wrapping_mul(seed).wrapping_add(seed)).collect(),
        name: format!("file-{seed}.bin"),
        mime: "image/jpeg".into(),
        width: Some(640),
        height: Some(480),
        duration_ms: None,
        thumb: vec![seed; 300],
    }
}

fn attachment_ids(p: &Party, chat: &str) -> Vec<crate::AttachmentInfo> {
    p.store.list_messages(chat.to_owned()).unwrap().into_iter().flat_map(|m| m.attachments).collect()
}

fn download(p: &Party, transport: &Arc<dyn Transport>, id: &str) -> Result<(), crate::StoreError> {
    p.store.download_attachment(transport.clone(), p.token.clone(), id.to_owned())
}

#[test]
fn an_attachment_is_encrypted_uploaded_in_chunks_and_decrypted_and_verified_by_the_recipient() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    let photo = pic(7, 300_000);
    let file = pic(9, 2_500_000);   // three chunks
    let chat = format!("dm:{}", bob.user);
    let sent = alice.store.send_attachments(chat.clone(), "the trip".into(), vec![photo.clone(), file.clone()], None).unwrap();
    assert_eq!(sent.attachments.len(), 2);
    assert!(sent.attachments.iter().all(|a| a.downloaded), "the sender holds their own files");
    deliver(&alice, &transport);
    assert_eq!(sync(&bob, &transport).received, 1);

    // What the server holds: only ciphertext chunks (4 of them), none containing a run of the plaintext.
    {
        let state = server.state.lock().unwrap();
        let stored: Vec<_> = state.objects.iter().filter(|(k, _)| k.starts_with("blobs/a/")).collect();
        assert_eq!(stored.len(), 4);
        for (_, bytes) in &stored {
            for plain in [&photo.bytes, &file.bytes] {
                let sample = &plain[1000..1064];
                assert!(!bytes.windows(64).any(|w| w == sample), "no plaintext run in what the server holds");
            }
        }
    }

    // Bob sees the message with its caption and two attachments he does not hold yet.
    let message = bob.store.list_messages(chat_with(&bob, &alice)).unwrap().into_iter().find(|m| m.text == "the trip").unwrap();
    assert_eq!(message.attachments.len(), 2);
    assert!(message.attachments.iter().all(|a| !a.downloaded));
    assert_eq!((message.attachments[0].mime.as_str(), message.attachments[0].width, message.attachments[0].thumb.len()), ("image/jpeg", Some(640), 300));
    assert_eq!(bob.store.attachment_data(message.attachments[0].id.clone()).unwrap(), None);
    for (info, original) in message.attachments.iter().zip([&photo, &file]) {
        download(&bob, &transport, &info.id).unwrap();
        assert_eq!(bob.store.attachment_data(info.id.clone()).unwrap(), Some(original.bytes.clone()));
    }
    download(&bob, &transport, &message.attachments[0].id).unwrap();   // already held: a no-op
    assert!(bob.store.list_messages(chat_with(&bob, &alice)).unwrap().iter().all(|m| m.attachments.iter().all(|a| a.downloaded)));
}

fn chat_with(_p: &Party, other: &Party) -> String {
    format!("dm:{}", other.user)
}

#[test]
fn a_changed_chunk_or_a_wrong_digest_is_refused_and_nothing_is_kept() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    alice.store.send_attachments(format!("dm:{}", bob.user), "".into(), vec![pic(3, 5000)], None).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    let id = attachment_ids(&bob, &format!("dm:{}", alice.user))[0].id.clone();

    // A flipped byte in the stored chunk.
    let key = format!("blobs/a/{id}/0");
    let original = server.state.lock().unwrap().objects.get(&key).cloned().unwrap();
    let mut tampered = original.clone();
    tampered[10] ^= 1;
    server.state.lock().unwrap().objects.insert(key.clone(), tampered);
    assert_eq!(download(&bob, &transport, &id), Err(crate::StoreError::BadMessage));
    assert_eq!(bob.store.attachment_data(id.clone()).unwrap(), None, "nothing kept");

    // The right ciphertext but a digest in the message that does not match.
    server.state.lock().unwrap().objects.insert(key, original);
    bob.store.lock().execute("UPDATE message_attachments SET digest = ?1 WHERE attachment_id = ?2", rusqlite::params!["0".repeat(64), id]).unwrap();
    assert_eq!(download(&bob, &transport, &id), Err(crate::StoreError::BadMessage));
    assert_eq!(bob.store.attachment_data(id).unwrap(), None);
}

#[test]
fn an_interrupted_upload_resumes_with_only_the_missing_chunks() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    let file = pic(5, 4_200_000);   // five chunks
    let chat = format!("dm:{}", bob.user);
    let sent = alice.store.send_attachments(chat.clone(), "big".into(), vec![file.clone()], None).unwrap();
    server.state.lock().unwrap().chunk_uploads = 0;
    server.state.lock().unwrap().fail_chunk_after = Some(2);   // the third chunk's upload fails

    assert!(alice.store.deliver_queued(transport.clone(), alice.token.clone()).is_err(), "the upload was interrupted");
    let state_of = |p: &Party| p.store.list_messages(chat.clone()).unwrap().into_iter().find(|m| m.id == sent.id).unwrap().local_state;
    assert_eq!(state_of(&alice), "failed", "the message waits, it is not lost");
    assert_eq!(server.state.lock().unwrap().objects.keys().filter(|k| k.starts_with("blobs/a/")).count(), 2);
    assert_eq!(sync(&bob, &transport).received, 0, "the message is not sent before its files are up");

    let uploads_before = server.state.lock().unwrap().chunk_uploads;
    deliver(&alice, &transport);
    assert_eq!(server.state.lock().unwrap().chunk_uploads - uploads_before, 3, "only the three missing chunks go up");
    assert_eq!(state_of(&alice), "sent");
    assert_eq!(sync(&bob, &transport).received, 1);
    let id = attachment_ids(&bob, &format!("dm:{}", alice.user))[0].id.clone();
    download(&bob, &transport, &id).unwrap();
    assert_eq!(bob.store.attachment_data(id).unwrap(), Some(file.bytes));
}

#[test]
fn attachment_limits_and_attachment_only_messages() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    let chat = format!("dm:{}", bob.user);
    let send = |caption: &str, items: Vec<crate::OutgoingAttachment>| alice.store.send_attachments(chat.clone(), caption.into(), items, None);
    assert!(send("", vec![]).is_err(), "nothing to send");
    assert!(send("", (0..11).map(|i| pic(i + 1, 100)).collect()).is_err(), "at most ten");
    assert!(send("", (0..10).map(|i| pic(i + 1, 100)).collect()).is_ok(), "ten is fine");
    let mut bad = pic(1, 100);
    bad.mime = "notamime".into();
    assert!(send("", vec![bad]).is_err());
    let mut empty = pic(1, 100);
    empty.bytes.clear();
    assert!(send("", vec![empty]).is_err());
    let mut fat = pic(1, 100);
    fat.thumb = vec![0; 3000];
    assert!(send("", vec![fat]).is_err(), "a thumbnail over 2 KB");
    assert!(send(&"x".repeat(9000), vec![pic(2, 100)]).is_err(), "a long caption leaves no room");
    // An attachment with no caption is a message like any other; Bob receives all ten.
    deliver(&alice, &transport);
    assert_eq!(sync(&bob, &transport).received, 1);
    let message = bob.store.list_messages(format!("dm:{}", alice.user)).unwrap().into_iter().find(|m| m.attachments.len() == 10).unwrap();
    assert_eq!(message.text, "");
}

#[test]
fn a_group_member_can_send_a_photo_and_every_member_can_download_it() {
    let server = FakeServer::new();
    let (alice, bob, carol, transport, chat) = team(&server);
    for p in [&bob, &carol] {
        p.store.accept_request(chat.clone()).unwrap();
    }
    deliver(&bob, &transport);
    deliver(&carol, &transport);
    sync(&alice, &transport);
    sync(&carol, &transport);
    sync(&bob, &transport);
    let photo = pic(4, 20_000);
    alice.store.send_attachments(chat.clone(), "look".into(), vec![photo.clone()], None).unwrap();
    deliver(&alice, &transport);
    for p in [&bob, &carol] {
        sync(p, &transport);
        let info = attachment_ids(p, &chat);
        assert_eq!(info.len(), 1, "{}", p.user);
        download(p, &transport, &info[0].id).unwrap();
        assert_eq!(p.store.attachment_data(info[0].id.clone()).unwrap(), Some(photo.bytes.clone()));
    }
    let (_, _, recipients, _, fetchers) = server.state.lock().unwrap().attachments.values().next().cloned().unwrap();
    assert_eq!((recipients, fetchers.len()), (2, 2), "two recipients declared, two fetched");
}

// ---------------------------------------------------------------- LIME-98d: resumable downloads, progress, voice and video

#[test]
fn an_interrupted_download_resumes_with_only_the_missing_chunks_and_reports_progress() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    let video = crate::OutgoingAttachment {
        bytes: (0..4_200_000u32).map(|i| (i.wrapping_mul(2654435761) >> 24) as u8).collect(),   // five chunks
        name: "clip.mp4".into(),
        mime: "video/mp4".into(),
        width: Some(1280),
        height: Some(720),
        duration_ms: Some(30_000),
        thumb: vec![9; 400],
    };
    alice.store.send_attachments(format!("dm:{}", bob.user), "".into(), vec![video.clone()], None).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    let info = attachment_ids(&bob, &format!("dm:{}", alice.user)).remove(0);
    assert_eq!((info.mime.as_str(), info.duration_ms, info.width), ("video/mp4", Some(30_000), Some(1280)));

    // The connection drops after two chunks.
    server.state.lock().unwrap().chunk_downloads = 0;
    server.state.lock().unwrap().fail_download_after = Some(2);
    assert!(download(&bob, &transport, &info.id).is_err());
    let progress = bob.store.transfer_progress(info.id.clone()).unwrap().expect("a transfer is in progress");
    assert_eq!((progress.upload, progress.done, progress.total), (false, 2, 5));
    assert_eq!(bob.store.attachment_data(info.id.clone()).unwrap(), None, "nothing is kept until it is whole");

    // Again: only the three missing chunks are fetched.
    let before = server.state.lock().unwrap().chunk_downloads;
    download(&bob, &transport, &info.id).unwrap();
    assert_eq!(server.state.lock().unwrap().chunk_downloads - before, 3);
    assert_eq!(bob.store.attachment_data(info.id.clone()).unwrap(), Some(video.bytes));
    assert_eq!(bob.store.transfer_progress(info.id.clone()).unwrap(), None, "finished: no progress row");
    let parts: i64 = bob.store.lock().query_row("SELECT count(*) FROM attachment_parts", [], |r| r.get(0)).unwrap();
    assert_eq!(parts, 0, "the held chunks are gone once it is assembled");
}

#[test]
fn a_bad_chunk_among_the_held_ones_is_discarded_and_the_retry_starts_over() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    let file = pic(6, 2_500_000);
    alice.store.send_attachments(format!("dm:{}", bob.user), "".into(), vec![file.clone()], None).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    let id = attachment_ids(&bob, &format!("dm:{}", alice.user)).remove(0).id;
    let key = format!("blobs/a/{id}/1");
    let good = server.state.lock().unwrap().objects.get(&key).cloned().unwrap();
    let mut bad = good.clone();
    bad[5] ^= 1;
    server.state.lock().unwrap().objects.insert(key.clone(), bad);
    assert_eq!(download(&bob, &transport, &id), Err(crate::StoreError::BadMessage));
    let parts: i64 = bob.store.lock().query_row("SELECT count(*) FROM attachment_parts", [], |r| r.get(0)).unwrap();
    assert_eq!(parts, 0, "the doubtful chunks are forgotten");
    assert_eq!(bob.store.transfer_progress(id.clone()).unwrap(), None);
    server.state.lock().unwrap().objects.insert(key, good);
    download(&bob, &transport, &id).unwrap();
    assert_eq!(bob.store.attachment_data(id).unwrap(), Some(file.bytes));
}

#[test]
fn an_upload_reports_progress_and_a_voice_note_carries_its_waveform_and_duration() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    let voice = crate::OutgoingAttachment {
        bytes: vec![3; 90_000],
        name: "Voice message.m4a".into(),
        mime: "audio/mp4".into(),
        width: None,
        height: None,
        duration_ms: Some(23_500),
        thumb: (0..64u8).map(|i| i * 2).collect(),   // the waveform: one byte per bar
    };
    let sent = alice.store.send_attachments(format!("dm:{}", bob.user), "".into(), vec![voice.clone()], None).unwrap();
    assert_eq!(sent.text, "");
    deliver(&alice, &transport);
    assert_eq!(alice.store.transfer_progress(sent.attachments[0].id.clone()).unwrap(), None, "the upload is finished");
    sync(&bob, &transport);
    let info = attachment_ids(&bob, &format!("dm:{}", alice.user)).remove(0);
    assert_eq!((info.mime.as_str(), info.duration_ms, info.thumb.len()), ("audio/mp4", Some(23_500), 64));
    assert_eq!(info.thumb, voice.thumb, "the waveform arrives as sent");
    download(&bob, &transport, &info.id).unwrap();
    assert_eq!(bob.store.attachment_data(info.id).unwrap(), Some(voice.bytes));
}

// ---------------------------------------------------------------- LIME-104: the QA round

#[test]
fn a_group_photo_is_set_changed_and_removed_across_accounts_and_the_server_holds_only_ciphertext() {
    let server = FakeServer::new();
    let (alice, bob, carol, transport, chat) = team(&server);
    for p in [&bob, &carol] {
        p.store.accept_request(chat.clone()).unwrap();
    }
    deliver(&bob, &transport);
    deliver(&carol, &transport);
    for p in [&alice, &bob, &carol] {
        sync(p, &transport);
    }
    let photo = |seed: u8| (0..40_000u32).map(|i| (i as u8).wrapping_mul(seed).wrapping_add(seed)).collect::<Vec<u8>>();
    let refresh_groups = |p: &Party| p.store.refresh_group_photos(transport.clone(), p.token.clone()).unwrap();

    // Alice (the owner) sets a photo: members fetch and decrypt it; the server's blob is not the picture.
    let first = photo(3);
    alice.store.set_group_photo(transport.clone(), alice.token.clone(), chat.clone(), first.clone()).unwrap();
    deliver(&alice, &transport);
    for p in [&bob, &carol] {
        sync(p, &transport);
        assert!(p.store.group_details(chat.clone()).unwrap().has_photo);
        assert_eq!(refresh_groups(p), vec![chat.clone()]);
        assert_eq!(p.store.group_photo(chat.clone()).unwrap(), Some(first.clone()), "{}", p.user);
        let lines: Vec<String> = p.store.list_messages(chat.clone()).unwrap().into_iter().filter(|m| m.local_state == "system").map(|m| m.text).collect();
        assert!(lines.last().unwrap().ends_with("changed the group photo"), "{lines:?}");
    }
    assert_eq!(alice.store.group_photo(chat.clone()).unwrap(), Some(first.clone()), "the one who set it has it at once");
    let first_blob: String = {
        let state = server.state.lock().unwrap();
        assert_eq!(state.blob_rows.len(), 1);
        let (id, _) = state.blob_rows.iter().next().unwrap();
        let stored = state.objects.get(&format!("blobs/{id}")).unwrap();
        assert!(!stored.windows(32).any(|w| w == &first[1000..1032]), "the server holds ciphertext");
        id.clone()
    };
    assert!(refresh_groups(&bob).is_empty(), "nothing changed the second time");

    // A plain member may not change it.
    assert!(bob.store.set_group_photo(transport.clone(), bob.token.clone(), chat.clone(), photo(5)).is_err());

    // Changed: the old blob is deleted from the server and members get the new picture.
    let second = photo(7);
    alice.store.set_group_photo(transport.clone(), alice.token.clone(), chat.clone(), second.clone()).unwrap();
    deliver(&alice, &transport);
    {
        let state = server.state.lock().unwrap();
        assert!(!state.blob_rows.contains_key(&first_blob), "the replaced photo is deleted from the server");
        assert_eq!(state.blob_rows.len(), 1);
    }
    sync(&bob, &transport);
    assert_eq!(refresh_groups(&bob), vec![chat.clone()]);
    assert_eq!(bob.store.group_photo(chat.clone()).unwrap(), Some(second));

    // Switched to an emoji: the photo is gone from the server and from the members.
    alice.store.set_group_avatar_emoji(transport.clone(), alice.token.clone(), chat.clone(), Some("🍎".into())).unwrap();
    deliver(&alice, &transport);
    assert!(server.state.lock().unwrap().blob_rows.is_empty(), "no photo blob is left");
    sync(&bob, &transport);
    assert_eq!(refresh_groups(&bob), vec![chat.clone()]);
    assert_eq!(bob.store.group_photo(chat.clone()).unwrap(), None);
    let summary = bob.store.list_conversations().unwrap().into_iter().find(|c| c.id == chat).unwrap();
    assert_eq!(summary.group_emoji.as_deref(), Some("🍎"));

    // And back to a photo, then removed altogether.
    alice.store.set_group_photo(transport.clone(), alice.token.clone(), chat.clone(), photo(9)).unwrap();
    alice.store.remove_group_photo(transport.clone(), alice.token.clone(), chat.clone()).unwrap();
    assert!(server.state.lock().unwrap().blob_rows.is_empty());
    deliver(&alice, &transport);
    sync(&bob, &transport);
    refresh_groups(&bob);
    assert_eq!(bob.store.group_photo(chat.clone()).unwrap(), None);
    assert!(!bob.store.group_details(chat.clone()).unwrap().has_photo);
    assert_eq!(bob.store.list_conversations().unwrap().into_iter().find(|c| c.id == chat).unwrap().group_emoji, None);
}

#[test]
fn a_group_photo_op_with_a_malformed_photo_is_not_read_as_clearing_the_avatar() {
    use crate::protocol::group::Kind;
    let good = serde_json::json!({ "photo": { "id": uuid::Uuid::new_v4().to_string(), "key": vodozemac::base64_encode([7u8; 32]) } });
    assert!(Kind::parse("group.set_avatar", &good).is_some());
    for bad in [
        serde_json::json!({ "photo": { "id": "not-a-uuid", "key": vodozemac::base64_encode([7u8; 32]) } }),
        serde_json::json!({ "photo": { "id": uuid::Uuid::new_v4().to_string(), "key": "AAAA" } }),
        serde_json::json!({ "photo": "x" }),
    ] {
        assert!(Kind::parse("group.set_avatar", &bad).is_none(), "{bad}");
    }
    assert!(Kind::parse("group.set_avatar", &serde_json::json!({ "emoji": "🍎" })).is_some());
}

#[test]
fn the_list_shows_the_latest_activity_replies_included_and_sorts_by_it() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    let (carol, _) = party(&server, "carol", 3);
    befriend(&alice, &bob, &transport);
    befriend(&alice, &carol, &transport);
    let to_bob = format!("dm:{}", bob.user);
    let to_carol = format!("dm:{}", carol.user);
    let root = alice.store.queue_text(to_bob.clone(), "main message".into()).unwrap();
    std::thread::sleep(std::time::Duration::from_millis(5));
    alice.store.queue_text(to_carol.clone(), "hello Carol".into()).unwrap();
    deliver(&alice, &transport);
    let list = |p: &Party| p.store.list_conversations().unwrap();
    assert_eq!(list(&alice)[0].id, to_carol, "newest first");
    assert!(!list(&alice)[0].last_is_reply);

    // A reply in Bob's thread is now the newest thing: the row shows it, and Bob's chat moves to the top.
    std::thread::sleep(std::time::Duration::from_millis(5));
    let reply = alice.store.queue_reply(to_bob.clone(), root.id.clone(), "a reply".into()).unwrap();
    let rows = list(&alice);
    assert_eq!(rows[0].id, to_bob);
    assert_eq!(rows[0].last_message.as_ref().unwrap().id, reply.id);
    assert_eq!(rows[0].last_message.as_ref().unwrap().text, "a reply");
    assert!(rows[0].last_is_reply, "the row says it is a reply");
    assert!(!rows[1].last_is_reply);
}

#[test]
fn pin_mark_unread_and_delete_chat_for_me() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    let (carol, _) = party(&server, "carol", 3);
    befriend(&alice, &bob, &transport);
    befriend(&alice, &carol, &transport);
    let (to_bob, to_carol) = (format!("dm:{}", bob.user), format!("dm:{}", carol.user));
    let ids = |p: &Party| p.store.list_conversations().unwrap().into_iter().map(|c| c.id).collect::<Vec<_>>();

    alice.store.set_pinned(to_bob.clone(), true).unwrap();
    std::thread::sleep(std::time::Duration::from_millis(5));
    say(&carol, &alice, &transport, "newer");
    sync(&alice, &transport);
    assert_eq!(ids(&alice)[0], to_bob, "pinned sorts first even though Carol's is newer");
    alice.store.set_pinned(to_bob.clone(), false).unwrap();
    assert_eq!(ids(&alice)[0], to_carol);
    assert!(alice.store.set_pinned("dm:nobody".into(), true).is_err());

    // Mark unread by hand; opening it (mark_read) clears it.
    let marked = |p: &Party, id: &str| p.store.list_conversations().unwrap().into_iter().find(|c| c.id == id).unwrap().marked_unread;
    alice.store.mark_read(to_bob.clone()).unwrap();
    assert!(!marked(&alice, &to_bob));
    alice.store.set_marked_unread(to_bob.clone(), true).unwrap();
    assert!(marked(&alice, &to_bob));
    alice.store.mark_read(to_bob.clone()).unwrap();
    assert!(!marked(&alice, &to_bob));

    // Delete for me: the chat and its messages go from this phone only; the other person is not told.
    let before = server.state.lock().unwrap().calls;
    alice.store.delete_chat(to_bob.clone()).unwrap();
    assert!(!ids(&alice).contains(&to_bob));
    assert!(alice.store.list_messages(to_bob.clone()).unwrap().is_empty());
    assert_eq!(server.state.lock().unwrap().calls, before, "nothing is sent");
    assert!(bob.store.list_messages(format!("dm:{}", alice.user)).unwrap().len() >= 2, "Bob still has everything");
    assert!(ids(&alice).contains(&to_carol), "other chats are untouched");
    // A new message from Bob brings the chat back, empty but for it.
    say(&bob, &alice, &transport, "back again");
    sync(&alice, &transport);
    assert!(ids(&alice).contains(&to_bob));
    assert_eq!(alice.store.list_messages(to_bob.clone()).unwrap().len(), 1);
    // Starting a chat I deleted shows it again too.
    alice.store.delete_chat(to_carol.clone()).unwrap();
    alice.store.start_dm(carol.user.clone(), "Carol".into()).unwrap();
    assert!(ids(&alice).contains(&to_carol));
}

#[test]
fn a_private_label_shows_beside_the_name_is_searchable_and_never_leaves_the_phone() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    let calls = server.state.lock().unwrap().calls;
    alice.store.set_contact_label(bob.user.clone(), Some("  Grade 4 ·   Lincoln  ".into())).unwrap();
    assert_eq!(alice.store.contact_label(bob.user.clone()).unwrap().as_deref(), Some("Grade 4 · Lincoln"), "whitespace is tidied");
    let summary = alice.store.list_conversations().unwrap().into_iter().find(|c| c.id == format!("dm:{}", bob.user)).unwrap();
    assert_eq!(summary.members[0].label.as_deref(), Some("Grade 4 · Lincoln"));
    assert_eq!(alice.store.search_conversations("lincoln".into()).unwrap().len(), 1, "found by the label");
    assert_eq!(alice.store.search_conversations("grade 4".into()).unwrap().len(), 1);
    assert_eq!(bob.store.search_conversations("lincoln".into()).unwrap().len(), 0, "Bob never learns it");
    assert_eq!(server.state.lock().unwrap().calls, calls, "nothing went to the server");

    let long = "x".repeat(60);
    alice.store.set_contact_label(bob.user.clone(), Some(long)).unwrap();
    assert_eq!(alice.store.contact_label(bob.user.clone()).unwrap().unwrap().chars().count(), 30, "at most 30 characters");
    alice.store.set_contact_label(bob.user.clone(), Some("   ".into())).unwrap();
    assert_eq!(alice.store.contact_label(bob.user.clone()).unwrap(), None, "empty removes it");
    assert_eq!(alice.store.search_conversations("lincoln".into()).unwrap().len(), 0);
}

#[test]
fn find_in_replies_covers_a_chats_threads_and_one_thread() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    let chat = format!("dm:{}", bob.user);
    let a = alice.store.queue_text(chat.clone(), "first root about lunch".into()).unwrap();
    let b = alice.store.queue_text(chat.clone(), "second root".into()).unwrap();
    alice.store.queue_reply(chat.clone(), a.id.clone(), "the zebra word is only in a reply".into()).unwrap();
    alice.store.queue_reply(chat.clone(), b.id.clone(), "another zebra here".into()).unwrap();
    // The chat's own find (main timeline) does not see replies; the replies search sees all of this chat's.
    assert!(alice.store.search_messages("zebra".into(), Some(chat.clone()), 50).unwrap().is_empty());
    let all = alice.store.search_replies("zebra".into(), chat.clone(), None, 50).unwrap();
    assert_eq!(all.len(), 2);
    assert!(all.iter().all(|h| h.thread_root.is_some()), "each hit names its thread");
    let roots: Vec<_> = all.iter().map(|h| h.thread_root.clone().unwrap()).collect();
    assert!(roots.contains(&a.id) && roots.contains(&b.id));
    // One thread only (its root message counts too).
    let one = alice.store.search_replies("zebra".into(), chat.clone(), Some(a.id.clone()), 50).unwrap();
    assert_eq!(one.len(), 1);
    assert_eq!(alice.store.search_replies("lunch".into(), chat.clone(), Some(a.id.clone()), 50).unwrap().len(), 1, "the root message is found inside its own thread");
    assert!(alice.store.search_replies("zebra".into(), format!("dm:{}", "other"), None, 50).unwrap().is_empty());
}

// ---------------------------------------------------------------- LIME-105: reactions, edit, delete

fn item_of(p: &Party, chat: &str, id: &str) -> crate::MessageItem {
    p.store.list_messages(chat.to_owned()).unwrap().into_iter().find(|m| m.id == id).unwrap_or_else(|| panic!("no message {id}"))
}

/// Pretends `ms` have passed since a message was written (its stored clock and display time move back).
fn age(p: &Party, id: &str, ms: i64) {
    let conn = p.store.lock();
    let hlc: String = conn.query_row("SELECT hlc FROM messages WHERE id = ?1", [id], |r| r.get(0)).unwrap();
    let parsed = crate::protocol::Hlc::parse(&hlc).unwrap();
    let older = crate::protocol::Hlc { wall: parsed.wall - ms, counter: parsed.counter }.render();
    conn.execute("UPDATE messages SET hlc = ?2, sent_at = sent_at - ?3 WHERE id = ?1", rusqlite::params![id, older, ms]).unwrap();
}

#[test]
fn reactions_toggle_and_converge_between_two_phones() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    let chat_a = format!("dm:{}", bob.user);
    let chat_b = format!("dm:{}", alice.user);
    let sent = alice.store.queue_text(chat_a.clone(), "lunch at noon?".into()).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);

    // Bob reacts with a quick emoji and another; Alice sees chips with who.
    let unread_before = conversation(&alice, &bob).unwrap().unread;
    bob.store.react(chat_b.clone(), sent.id.clone(), "👍".into(), true).unwrap();
    bob.store.react(chat_b.clone(), sent.id.clone(), "🎉".into(), true).unwrap();
    assert_eq!(item_of(&bob, &chat_b, &sent.id).reactions.len(), 2, "my own show at once");
    assert!(item_of(&bob, &chat_b, &sent.id).reactions.iter().all(|r| r.mine && r.people == vec!["You".to_string()]));
    deliver(&bob, &transport);
    assert_eq!(sync(&alice, &transport).received, 0, "a reaction is not a message");
    let on_alice = item_of(&alice, &chat_a, &sent.id).reactions;
    assert_eq!(on_alice.iter().map(|r| (r.emoji.as_str(), r.count, r.mine)).collect::<Vec<_>>(), vec![("👍", 1, false), ("🎉", 1, false)]);
    assert_eq!(on_alice[0].people.len(), 1);
    assert_eq!(conversation(&alice, &bob).unwrap().unread, unread_before, "no unread for a reaction");

    // Alice adds the same emoji (a count of two) and Bob takes his off: both phones agree.
    alice.store.react(chat_a.clone(), sent.id.clone(), "👍".into(), true).unwrap();
    bob.store.react(chat_b.clone(), sent.id.clone(), "🎉".into(), false).unwrap();
    deliver(&alice, &transport);
    deliver(&bob, &transport);
    sync(&alice, &transport);
    sync(&bob, &transport);
    for (p, chat) in [(&alice, &chat_a), (&bob, &chat_b)] {
        let r = item_of(p, chat, &sent.id).reactions;
        assert_eq!(r.len(), 1, "{}: the removed one is gone", p.user);
        assert_eq!((r[0].emoji.as_str(), r[0].count), ("👍", 2));
    }
    // Words and long text are not reactions.
    assert!(bob.store.react(chat_b.clone(), sent.id.clone(), "thumbs up".into(), true).is_err());
    assert!(bob.store.react(chat_b.clone(), sent.id.clone(), "".into(), true).is_err());
    assert!(bob.store.react(chat_b.clone(), "no-such-message".into(), "👍".into(), true).is_err());
}

#[test]
fn an_edit_replaces_the_text_for_both_phones_and_only_the_author_may_within_a_day() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    let (chat_a, chat_b) = (format!("dm:{}", bob.user), format!("dm:{}", alice.user));
    let sent = alice.store.queue_text(chat_a.clone(), "meet at the gym".into()).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);

    let edited = alice.store.edit_message(chat_a.clone(), sent.id.clone(), "meet at **the library**".into()).unwrap();
    assert!(edited.edited);
    assert_eq!(edited.text, "meet at **the library**");
    deliver(&alice, &transport);
    sync(&bob, &transport);
    let on_bob = item_of(&bob, &chat_b, &sent.id);
    assert_eq!((on_bob.text.as_str(), on_bob.edited), ("meet at **the library**", true));
    // The search index follows the new words, and forgets the old.
    assert_eq!(bob.store.search_messages("library".into(), None, 10).unwrap().len(), 1);
    assert_eq!(bob.store.search_messages("gym".into(), None, 10).unwrap().len(), 0);
    assert_eq!(alice.store.search_messages("gym".into(), None, 10).unwrap().len(), 0);

    // Bob cannot edit Alice's message (here, and a forged op is ignored by Alice).
    assert!(bob.store.edit_message(chat_b.clone(), sent.id.clone(), "hacked".into()).is_err());
    let forged = crate::protocol::Op {
        op_id: "x".into(), op_type: "message.edit".into(), conversation_id: chat_a.clone(), hlc: crate::protocol::Hlc { wall: crate::store::now_ms(), counter: 9 }.render(),
        parents: vec![], payload: serde_json::json!({ "target": sent.id, "text": "forged" }), sig: String::new(),
    };
    crate::store::message_ops::apply(&alice.store.lock(), &bob.user, &chat_a, &forged).unwrap();
    assert_eq!(item_of(&alice, &chat_a, &sent.id).text, "meet at **the library**", "an edit by someone else changes nothing");

    // After 24 hours there is no editing (the sender's own phone refuses).
    age(&alice, &sent.id, 25 * 3600 * 1000);
    assert!(alice.store.edit_message(chat_a.clone(), sent.id.clone(), "too late".into()).is_err());
    // A message not sent yet is simply rewritten and never shows "edited".
    let fresh = alice.store.queue_text(chat_a.clone(), "typo".into()).unwrap();
    let fixed = alice.store.edit_message(chat_a.clone(), fresh.id.clone(), "no typo".into()).unwrap();
    assert_eq!((fixed.text.as_str(), fixed.edited), ("no typo", false));
}

#[test]
fn delete_for_everyone_leaves_a_tombstone_removes_files_and_search_and_respects_the_window_and_the_author() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    let (chat_a, chat_b) = (format!("dm:{}", bob.user), format!("dm:{}", alice.user));
    let with_file = alice.store.send_attachments(chat_a.clone(), "the secret plan".into(), vec![pic(4, 3000)], None).unwrap();
    let plain = alice.store.queue_text(chat_a.clone(), "an old message".into()).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    download(&bob, &transport, &item_of(&bob, &chat_b, &with_file.id).attachments[0].id).unwrap();
    assert_eq!(bob.store.search_messages("secret".into(), None, 5).unwrap().len(), 1);

    // Bob cannot delete Alice's message for everyone.
    assert!(bob.store.delete_message_for_everyone(chat_b.clone(), with_file.id.clone()).is_err());
    // Alice can, within a day.
    alice.store.delete_message_for_everyone(chat_a.clone(), with_file.id.clone()).unwrap();
    let mine = item_of(&alice, &chat_a, &with_file.id);
    assert!(mine.deleted && mine.text.is_empty() && mine.attachments.is_empty(), "gone here at once");
    deliver(&alice, &transport);
    sync(&bob, &transport);
    let theirs = item_of(&bob, &chat_b, &with_file.id);
    assert!(theirs.deleted && theirs.text.is_empty() && theirs.attachments.is_empty(), "a tombstone: its place stays, its words and files go");
    assert_eq!(bob.store.search_messages("secret".into(), None, 5).unwrap().len(), 0, "and the search index forgot it");
    assert_eq!(alice.store.search_messages("secret".into(), None, 5).unwrap().len(), 0);
    assert!(bob.store.list_messages(chat_b.clone()).unwrap().iter().any(|m| m.id == with_file.id), "it is still in the timeline");
    assert!(bob.store.react(chat_b.clone(), with_file.id.clone(), "👍".into(), true).is_err(), "no reacting to a deleted message");
    assert!(alice.store.edit_message(chat_a.clone(), with_file.id.clone(), "x".into()).is_err(), "no editing it");

    // After a day: not allowed on the sender's phone, and a late op from a modified sender is ignored by the receiver.
    age(&alice, &plain.id, 25 * 3600 * 1000);
    assert!(alice.store.delete_message_for_everyone(chat_a.clone(), plain.id.clone()).is_err());
    let late = crate::protocol::Op {
        op_id: "y".into(), op_type: "message.delete".into(), conversation_id: chat_b.clone(),
        hlc: crate::protocol::Hlc { wall: crate::store::now_ms() + 26 * 3600 * 1000, counter: 0 }.render(),
        parents: vec![], payload: serde_json::json!({ "target": plain.id }), sig: String::new(),
    };
    crate::store::message_ops::apply(&bob.store.lock(), &alice.user, &chat_b, &late).unwrap();
    assert!(!item_of(&bob, &chat_b, &plain.id).deleted, "a delete sent more than 24 hours after the message is ignored");
}

#[test]
fn delete_for_me_removes_it_here_only_and_a_deleted_root_keeps_its_replies() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    let (chat_a, chat_b) = (format!("dm:{}", bob.user), format!("dm:{}", alice.user));
    let root = alice.store.queue_text(chat_a.clone(), "who can cover recess?".into()).unwrap();
    let keep = alice.store.queue_text(chat_a.clone(), "keep me".into()).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    reply(&bob, &alice, &transport, &root.id, "I can");
    sync(&alice, &transport);

    let calls = server.state.lock().unwrap().calls;
    bob.store.delete_message_for_me(chat_b.clone(), keep.id.clone()).unwrap();
    assert!(bob.store.list_messages(chat_b.clone()).unwrap().iter().all(|m| m.id != keep.id), "gone from Bob's list");
    assert_eq!(bob.store.search_messages("keep".into(), None, 5).unwrap().len(), 0);
    assert_eq!(server.state.lock().unwrap().calls, calls, "nothing was sent");
    assert!(alice.store.list_messages(chat_a.clone()).unwrap().iter().any(|m| m.id == keep.id), "Alice still has it");

    // Deleting a thread's root for everyone leaves its replies.
    alice.store.delete_message_for_everyone(chat_a.clone(), root.id.clone()).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    let thread = bob.store.list_thread(root.id.clone()).unwrap();
    assert!(thread[0].deleted, "the root says it was deleted");
    assert_eq!(thread.len(), 2);
    assert_eq!(thread[1].text, "I can", "the reply stays");
    // A message not yet sent can be cancelled outright.
    let unsent = alice.store.queue_text(chat_a.clone(), "never mind".into()).unwrap();
    alice.store.delete_message_for_everyone(chat_a.clone(), unsent.id.clone()).unwrap();
    assert!(alice.store.list_messages(chat_a.clone()).unwrap().iter().all(|m| m.id != unsent.id));
    assert_eq!(alice.store.deliver_queued(transport.clone(), alice.token.clone()).unwrap(), 0, "nothing was sent");
}

#[test]
fn deleted_replies_leave_the_thread_summary() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    let (chat_a, chat_b) = (format!("dm:{}", bob.user), format!("dm:{}", alice.user));
    let root = alice.store.queue_text(chat_a.clone(), "who can cover recess?".into()).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    let one = reply(&bob, &alice, &transport, &root.id, "I can");
    let two = reply(&bob, &alice, &transport, &root.id, "or maybe not");
    sync(&alice, &transport);
    let summary = || alice.store.list_thread_summaries(chat_a.clone()).unwrap();
    assert_eq!(summary()[0].reply_count, 2);

    bob.store.delete_message_for_everyone(chat_b.clone(), two.id.clone()).unwrap();
    deliver(&bob, &transport);
    sync(&alice, &transport);
    assert_eq!(summary()[0].reply_count, 1, "a deleted reply is not counted");

    bob.store.delete_message_for_everyone(chat_b.clone(), one.id.clone()).unwrap();
    deliver(&bob, &transport);
    sync(&alice, &transport);
    assert!(summary().is_empty(), "no live replies: no summary under the message");
    assert_eq!(alice.store.list_thread(root.id.clone()).unwrap().len(), 3, "Replies still shows the placeholders for context");
}

// ---------------------------------------------------------------- LIME-106: forward, my own chat, link previews

#[test]
fn a_forward_is_a_new_labelled_message_that_shares_the_files_by_reference() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    let (carol, _) = party(&server, "carol", 3);
    befriend(&alice, &bob, &transport);
    befriend(&alice, &carol, &transport);
    let (to_bob, to_carol) = (format!("dm:{}", bob.user), format!("dm:{}", carol.user));
    let photo = pic(5, 2_500_000);
    let sent = alice.store.send_attachments(to_bob.clone(), "the **trip**".into(), vec![photo.clone()], None).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    let chunks_on_server = server.state.lock().unwrap().objects.keys().filter(|k| k.starts_with("blobs/a/")).count();

    // Bob forwards what he received to Carol (he does not know Carol: his own chats only): forward from Alice's side instead.
    let forwarded = alice.store.forward_messages(vec![sent.id.clone()], vec![to_carol.clone()]).unwrap();
    assert_eq!(forwarded.len(), 1);
    assert!(forwarded[0].forwarded && forwarded[0].local_state == "sending");
    assert_eq!(forwarded[0].text, "the **trip**", "formatting is kept");
    assert_eq!(forwarded[0].attachments.len(), 1);
    assert_eq!(forwarded[0].attachments[0].id, sent.attachments[0].id, "the same file, by reference");
    assert!(forwarded[0].attachments[0].downloaded, "and the bytes are copied here");
    deliver(&alice, &transport);
    assert_eq!(server.state.lock().unwrap().objects.keys().filter(|k| k.starts_with("blobs/a/")).count(), chunks_on_server, "nothing was uploaded again");

    assert_eq!(sync(&carol, &transport).received, 1);
    let got = carol.store.list_messages(format!("dm:{}", alice.user)).unwrap().pop().unwrap();
    assert!(got.forwarded, "labelled forwarded");
    assert_eq!(got.text, "the **trip**");
    download(&carol, &transport, &got.attachments[0].id).unwrap();
    assert_eq!(carol.store.attachment_data(got.attachments[0].id.clone()).unwrap(), Some(photo.bytes.clone()));
    // Bob's original is not marked forwarded.
    assert!(!bob.store.list_messages(format!("dm:{}", alice.user)).unwrap().pop().unwrap().forwarded);

    // Deleting the original for everyone does not take the file from the forward.
    alice.store.delete_message_for_everyone(to_bob.clone(), sent.id.clone()).unwrap();
    assert_eq!(alice.store.attachment_data(sent.attachments[0].id.clone()).unwrap(), Some(photo.bytes.clone()), "the forward still holds the file");

    // At most five chats; nothing to forward is refused; a deleted message is skipped.
    let six: Vec<String> = (0..6).map(|i| format!("dm:x{i}")).collect();
    assert_eq!(alice.store.forward_messages(vec![sent.id.clone()], six), Err(crate::StoreError::Rejected));
    assert_eq!(alice.store.forward_messages(vec![], vec![to_carol.clone()]), Err(crate::StoreError::Rejected));
    assert!(alice.store.forward_messages(vec![sent.id.clone()], vec![to_carol]).unwrap().is_empty(), "a deleted message is not forwarded");
}

#[test]
fn a_link_preview_travels_encrypted_and_the_recipient_never_visits_the_link() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    let image: Vec<u8> = (0..30_000u32).map(|i| (i * 7 % 251) as u8).collect();
    let preview = crate::OutgoingPreview {
        url: "https://example.org/lesson".into(),
        title: "A lesson plan".into(),
        site: "example.org".into(),
        image: image.clone(),
        image_width: Some(600),
        image_height: Some(315),
    };
    let chat = format!("dm:{}", bob.user);
    let item = alice.store.queue_text_with_preview(chat.clone(), "see https://example.org/lesson".into(), None, preview).unwrap();
    let card = item.link_preview.clone().unwrap();
    assert_eq!((card.title.as_str(), card.site.as_str()), ("A lesson plan", "example.org"));
    assert!(item.attachments.is_empty(), "the picture is not an album photo");
    deliver(&alice, &transport);
    {
        let state = server.state.lock().unwrap();
        for (_, bytes) in state.objects.iter().filter(|(k, _)| k.starts_with("blobs/a/")) {
            assert!(!bytes.windows(64).any(|w| w == &image[1000..1064]), "the server holds only ciphertext");
        }
    }
    sync(&bob, &transport);
    let got = bob.store.list_messages(format!("dm:{}", alice.user)).unwrap().pop().unwrap();
    let card = got.link_preview.clone().expect("a card");
    assert_eq!((card.url.as_str(), card.title.as_str()), ("https://example.org/lesson", "A lesson plan"));
    assert!(got.attachments.is_empty());
    let picture = card.image.expect("a picture");
    assert!(!picture.downloaded);
    download(&bob, &transport, &picture.id).unwrap();
    assert_eq!(bob.store.attachment_data(picture.id.clone()).unwrap(), Some(image));
    // A preview with a non-web address is dropped (the message goes as plain text).
    let plain = alice.store.queue_text_with_preview(chat, "hi".into(), None, crate::OutgoingPreview {
        url: "javascript:alert(1)".into(), title: "x".into(), site: "y".into(), image: vec![], image_width: None, image_height: None,
    }).unwrap();
    assert!(plain.link_preview.is_none());
}

#[test]
fn my_own_chat_stays_on_this_phone_and_supports_files_search_and_reactions() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    let own = alice.store.ensure_self_chat("Alice Lee".into()).unwrap();
    assert_eq!(own, format!("dm:{}", alice.user));
    assert_eq!(alice.store.ensure_self_chat("Alice Lee".into()).unwrap(), own, "one chat, however often it is asked for");
    let summary = alice.store.list_conversations().unwrap().into_iter().find(|c| c.id == own).unwrap();
    assert_eq!(summary.title, "Alice Lee");
    assert_eq!(summary.request_state, "accepted");

    let calls = server.state.lock().unwrap().calls;
    let note = alice.store.queue_text(own.clone(), "buy **markers** for Friday".into()).unwrap();
    let with_file = alice.store.send_attachments(own.clone(), "my slides".into(), vec![pic(2, 4000)], None).unwrap();
    let reply = alice.store.queue_reply(own.clone(), note.id.clone(), "and glue".into()).unwrap();
    alice.store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    alice.store.react(own.clone(), note.id.clone(), "👍".into(), true).unwrap();
    alice.store.edit_message(own.clone(), note.id.clone(), "buy markers and tape".into()).unwrap();
    alice.store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    let own_chat_calls_to_bob = server.state.lock().unwrap().calls - calls;
    assert!(own_chat_calls_to_bob <= 6, "only the usual housekeeping (keys, shares), nothing per message: {own_chat_calls_to_bob}");
    let messages = alice.store.list_messages(own.clone()).unwrap();
    assert!(messages.iter().all(|m| m.local_state == "sent"), "sent at once");
    assert_eq!(messages.iter().find(|m| m.id == note.id).unwrap().text, "buy markers and tape");
    assert_eq!(messages.iter().find(|m| m.id == note.id).unwrap().reactions.len(), 1);
    assert!(alice.store.attachment_data(with_file.attachments[0].id.clone()).unwrap().is_some());
    assert_eq!(alice.store.list_thread(note.id.clone()).unwrap().len(), 2);
    let _ = reply;
    // Nothing reached the server or Bob: no mailbox item for him, no upload.
    assert_eq!(sync(&bob, &transport).received, 0, "Bob receives nothing");
    assert_eq!(server.state.lock().unwrap().objects.keys().filter(|k| k.starts_with("blobs/a/")).count(), 0, "no file was uploaded");
    // Searchable, and a message can be forwarded into it.
    assert!(!alice.store.search_messages("tape".into(), None, 5).unwrap().is_empty());
    let into_own = alice.store.forward_messages(vec![with_file.id.clone()], vec![own.clone()]).unwrap();
    alice.store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    assert!(into_own[0].forwarded);
    assert_eq!(server.state.lock().unwrap().objects.keys().filter(|k| k.starts_with("blobs/a/")).count(), 0, "still nothing uploaded");
}

#[test]
fn a_forward_whose_file_is_gone_re_uploads_it_or_fails_alone_and_a_retry_never_duplicates() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    let (carol, _) = party(&server, "carol", 3);
    befriend(&alice, &bob, &transport);
    befriend(&bob, &carol, &transport);
    let (to_bob, bob_to_carol) = (format!("dm:{}", bob.user), format!("dm:{}", carol.user));
    let sent = alice.store.send_attachments(to_bob.clone(), "".into(), vec![pic(4, 5000)], None).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    let at_bob = |id: &str| bob.store.list_messages(format!("dm:{}", alice.user)).unwrap().into_iter().find(|m| m.id == id).unwrap();
    let state = |chat: &str, id: &str| bob.store.list_messages(chat.to_owned()).unwrap().into_iter().find(|m| m.id == id).unwrap().local_state;

    // The server's copy is swept before Bob (who never downloaded the file) forwards it, and a plain text follows it.
    server.state.lock().unwrap().attachments.clear();
    let forwarded = bob.store.forward_messages(vec![at_bob(&sent.id).id], vec![bob_to_carol.clone()]).unwrap();
    let after = bob.store.queue_text(bob_to_carol.clone(), "and this".into()).unwrap();
    bob.store.deliver_queued(transport.clone(), bob.token.clone()).unwrap();
    assert_eq!(state(&bob_to_carol, &forwarded[0].id), "failed", "nothing to send it from: that forward fails");
    assert_eq!(state(&bob_to_carol, &after.id), "sent", "but the message behind it still goes");
    assert_eq!(sync(&carol, &transport).received, 1);

    // Once Bob holds the file, a retry puts it up again and sends it; Carol gets it once, however often it is delivered.
    download_from_alice_copy(&bob, &alice, &transport, &sent.attachments[0].id);
    bob.store.retry_message(forwarded[0].id.clone()).unwrap();
    bob.store.deliver_queued(transport.clone(), bob.token.clone()).unwrap();
    assert_eq!(state(&bob_to_carol, &forwarded[0].id), "sent");
    bob.store.deliver_queued(transport.clone(), bob.token.clone()).unwrap();
    assert_eq!(sync(&carol, &transport).received, 1);
    let got: Vec<_> = carol.store.list_messages(format!("dm:{}", bob.user)).unwrap().into_iter().filter(|m| m.forwarded).collect();
    assert_eq!(got.len(), 1, "once");
    download(&carol, &transport, &got[0].attachments[0].id).unwrap();
}

/// Gives `bob` the bytes of an attachment Alice sent him, as a download would (the stand-in server's copy was cleared).
fn download_from_alice_copy(bob: &Party, alice: &Party, _transport: &Arc<dyn Transport>, id: &str) {
    let bytes = alice.store.attachment_data(id.to_owned()).unwrap().unwrap();
    bob.store.test_set_attachment_data(id, &bytes);
}

// ---------------------------------------------------------------- LIME-107: storage

#[test]
fn storage_is_counted_per_chat_media_can_be_removed_and_keep_media_removes_old_files_but_not_messages() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    let (carol, _) = party(&server, "carol", 3);
    befriend(&alice, &bob, &transport);
    befriend(&alice, &carol, &transport);
    let (to_bob, to_carol) = (format!("dm:{}", bob.user), format!("dm:{}", carol.user));
    let big = alice.store.send_attachments(to_bob.clone(), "big".into(), vec![pic(1, 40_000)], None).unwrap();
    let small = alice.store.send_attachments(to_carol.clone(), "small".into(), vec![pic(2, 5_000)], None).unwrap();
    alice.store.queue_text(to_carol.clone(), "words stay".into()).unwrap();

    let usage = alice.store.storage_usage().unwrap();
    assert_eq!(usage.media_bytes, 45_000);
    assert_eq!((usage.chats[0].conversation_id.as_str(), usage.chats[0].bytes, usage.chats[0].files), (to_bob.as_str(), 40_000, 1), "largest first");
    assert_eq!(usage.chats[1].bytes, 5_000);
    assert!(usage.database_bytes > 0);
    assert_eq!(alice.store.list_media(to_bob.clone()).unwrap().len(), 1);

    // Remove one chat's media by hand: the message stays, its file is gone, it says removed, and it cannot be fetched again.
    let removed = alice.store.remove_media(vec![crate::MediaRef { message_id: big.id.clone(), attachment_id: big.attachments[0].id.clone() }]).unwrap();
    assert_eq!(removed, 1);
    let message = alice.store.list_messages(to_bob.clone()).unwrap().into_iter().find(|m| m.id == big.id).unwrap();
    assert_eq!(message.text, "big");
    assert!(message.attachments[0].removed && !message.attachments[0].downloaded);
    assert_eq!(alice.store.attachment_data(big.attachments[0].id.clone()).unwrap(), None);
    assert_eq!(download(&alice, &transport, &big.attachments[0].id), Err(crate::StoreError::NotFound), "removed on purpose: not downloaded again");
    assert_eq!(alice.store.storage_usage().unwrap().media_bytes, 5_000);

    // Keep media: a file older than the limit goes; a newer one and every message stay.
    assert_eq!(alice.store.remove_media_older_than(30).unwrap(), 0, "nothing is 30 days old yet");
    alice.store.test_age_messages(60 * 86_400_000);
    assert_eq!(alice.store.remove_media_older_than(30).unwrap(), 1);
    let kept = alice.store.list_messages(to_carol.clone()).unwrap();
    assert!(kept.iter().any(|m| m.text == "small" && m.attachments[0].removed), "the message stays with its file removed");
    assert!(kept.iter().any(|m| m.text == "words stay"));
    assert_eq!(alice.store.storage_usage().unwrap().media_bytes, 0);
    alice.store.compact_storage().unwrap();
    // A reply says which message it answers (the Messages list quotes it).
    let reply = alice.store.queue_reply(to_carol.clone(), small.id.clone(), "answer".into()).unwrap();
    assert_eq!(reply.thread_root.as_deref(), Some(small.id.as_str()));
    let latest = alice.store.list_conversations().unwrap().into_iter().find(|c| c.id == to_carol).unwrap().last_message.unwrap();
    assert_eq!(latest.thread_root.as_deref(), Some(small.id.as_str()));
}

#[test]
fn availability_says_until_when_a_file_is_on_the_server_and_none_once_it_is_gone() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    let sent = alice.store.send_attachments(format!("dm:{}", bob.user), "".into(), vec![pic(3, 2000)], None).unwrap();
    deliver(&alice, &transport);
    let id = sent.attachments[0].id.clone();
    assert!(alice.store.attachment_available_until(transport.clone(), alice.token.clone(), id.clone()).unwrap().is_some());
    server.state.lock().unwrap().attachments.clear();
    assert_eq!(alice.store.attachment_available_until(transport.clone(), alice.token.clone(), id).unwrap(), None);
}

#[test]
fn a_reaction_is_the_newest_thing_in_the_chat_list_without_an_unread_or_a_new_message() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    let (carol, _) = party(&server, "carol", 3);
    befriend(&alice, &bob, &transport);
    befriend(&alice, &carol, &transport);
    let (to_bob, to_carol) = (format!("dm:{}", bob.user), format!("dm:{}", carol.user));
    let old = alice.store.queue_text(to_bob.clone(), "True that".into()).unwrap();
    alice.store.queue_text(to_carol.clone(), "newer chat".into()).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    let summary = |chat: &str| alice.store.list_conversations().unwrap().into_iter().find(|c| c.id == chat).unwrap();
    assert!(summary(&to_bob).last_reaction.is_none());
    let unread_before = summary(&to_bob).unread;
    let order: Vec<String> = alice.store.list_conversations().unwrap().into_iter().map(|c| c.id).collect();
    assert_eq!(order[0], to_carol, "the newer chat is first");

    // Bob reacts to the older message: that chat now has the newest activity, and says so; nothing is unread.
    std::thread::sleep(std::time::Duration::from_millis(5));
    bob.store.accept_request(format!("dm:{}", alice.user)).unwrap();
    bob.store.react(format!("dm:{}", alice.user), old.id.clone(), "❤️".into(), true).unwrap();
    bob.store.deliver_queued(transport.clone(), bob.token.clone()).unwrap();
    sync(&alice, &transport);
    let now = summary(&to_bob);
    let reaction = now.last_reaction.clone().expect("a reaction preview");
    assert_eq!((reaction.emoji.as_str(), reaction.text.as_str(), reaction.reactor_id.as_deref()), ("❤️", "True that", Some(bob.user.as_str())));
    assert_eq!(now.unread, unread_before, "a reaction is not unread");
    assert_eq!(now.last_message.as_ref().unwrap().text, "True that", "the last message is unchanged");
    assert!(now.activity_at >= now.last_message.as_ref().unwrap().sent_at);
    let order: Vec<String> = alice.store.list_conversations().unwrap().into_iter().map(|c| c.id).collect();
    assert_eq!(order[0], to_bob, "and its row moves up");

    // My own reaction reads as mine; a newer message takes the preview back.
    alice.store.react(to_carol.clone(), alice.store.list_messages(to_carol.clone()).unwrap()[0].id.clone(), "👍".into(), true).unwrap();
    assert_eq!(summary(&to_carol).last_reaction.unwrap().reactor_id, None);
    std::thread::sleep(std::time::Duration::from_millis(5));
    alice.store.queue_text(to_bob.clone(), "and another thing".into()).unwrap();
    assert!(summary(&to_bob).last_reaction.is_none(), "a newer message is the preview again");
}

#[test]
fn reading_only_the_replies_clears_the_chat_and_a_hand_made_mark_is_cleared_by_reading() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    let to_bob = format!("dm:{}", bob.user);
    let root = alice.store.queue_text(to_bob.clone(), "who can cover recess?".into()).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    let unread = |chat: &str| alice.store.list_conversations().unwrap().into_iter().find(|c| c.id == chat).unwrap();
    alice.store.mark_read(to_bob.clone()).unwrap();
    assert_eq!(unread(&to_bob).unread, 0);

    // A reply arrives and counts; reading only the Replies clears the chat's number too, and the thread's.
    reply(&bob, &alice, &transport, &root.id, "I can");
    sync(&alice, &transport);
    assert_eq!(unread(&to_bob).unread, 1);
    assert_eq!(alice.store.list_thread_summaries(to_bob.clone()).unwrap()[0].unread, 1);
    alice.store.mark_thread_read(root.id.clone()).unwrap();
    assert_eq!(unread(&to_bob).unread, 0, "reading the replies took them off the chat's number");
    assert_eq!(alice.store.list_thread_summaries(to_bob.clone()).unwrap()[0].unread, 0);

    // Marked unread by hand (no number): opening the chat clears the mark.
    alice.store.set_marked_unread(to_bob.clone(), true).unwrap();
    let c = unread(&to_bob);
    assert!(c.marked_unread && c.unread == 0);
    alice.store.mark_read(to_bob.clone()).unwrap();
    assert!(!unread(&to_bob).marked_unread, "reading clears the hand-made mark");
}

#[test]
fn a_status_goes_only_to_accepted_contacts_and_is_kept_only_from_them_and_ends_when_it_says() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    let (carol, _) = party(&server, "carol", 3);
    befriend(&alice, &bob, &transport);
    // Carol wrote to Alice first and Alice has not accepted her: a request.
    say(&carol, &alice, &transport, "hello, it's carol");
    sync(&alice, &transport);
    let now = 1_000_000_i64;
    let dnd = crate::StatusInfo { state: "dnd".into(), until: Some(now + 3_600_000), then_state: Some("available".into()), then_until: None };
    alice.store.set_my_status(dnd.clone()).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    sync(&carol, &transport);
    let of = |p: &Party, at: i64| p.store.contact_statuses(at).unwrap().into_iter().map(|c| (c.user_id, c.state)).collect::<Vec<_>>();
    assert_eq!(of(&bob, now), vec![(alice.user.clone(), "dnd".to_owned())], "an accepted contact sees it");
    assert!(of(&carol, now).is_empty(), "a request is not told");
    // It ends when it says, and what follows takes over; setting the same thing again tells nobody again.
    assert_eq!(of(&bob, now + 3_600_001), vec![(alice.user.clone(), "available".to_owned())]);
    let calls = server.state.lock().unwrap().calls;
    alice.store.set_my_status(dnd).unwrap();
    deliver(&alice, &transport);
    assert_eq!(server.state.lock().unwrap().calls, calls, "the same status is not sent twice");
    assert!(alice.store.set_my_status(crate::StatusInfo { state: "busy".into(), until: None, then_state: None, then_until: None }).is_err(), "only the three states");

    // A status from someone I have not accepted is ignored; once I accept them and they tell me again, it is kept.
    carol.store.set_my_status(crate::StatusInfo { state: "away".into(), until: None, then_state: None, then_until: None }).unwrap();
    deliver(&carol, &transport);
    sync(&alice, &transport);
    assert!(of(&alice, now).is_empty(), "not from a request");
    alice.store.accept_request(format!("dm:{}", carol.user)).unwrap();
    carol.store.set_my_status(crate::StatusInfo { state: "dnd".into(), until: None, then_state: None, then_until: None }).unwrap();
    deliver(&carol, &transport);
    sync(&alice, &transport);
    assert_eq!(of(&alice, now), vec![(carol.user.clone(), "dnd".to_owned())]);
    // And Alice's own status reached Carol once she was accepted.
    deliver(&alice, &transport);
    sync(&carol, &transport);
    assert_eq!(of(&carol, now), vec![(alice.user.clone(), "dnd".to_owned())]);
}

#[test]
fn an_edit_or_delete_that_arrives_before_its_message_waits_for_it() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    let (chat_a, chat_b) = (format!("dm:{}", bob.user), format!("dm:{}", alice.user));
    let sent = alice.store.queue_text(chat_a.clone(), "original".into()).unwrap();
    // Bob gets the edit op before the message (applied directly: the order a flaky network could produce).
    let at = crate::protocol::Hlc { wall: crate::store::now_ms(), counter: 5 }.render();
    let edit = crate::protocol::Op {
        op_id: "e".into(), op_type: "message.edit".into(), conversation_id: chat_b.clone(), hlc: at.clone(), parents: vec![],
        payload: serde_json::json!({ "target": sent.id, "text": "edited early", "hlc": at }), sig: String::new(),
    };
    crate::store::message_ops::apply(&bob.store.lock(), &alice.user, &chat_b, &edit).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    let arrived = item_of(&bob, &chat_b, &sent.id);
    assert_eq!((arrived.text.as_str(), arrived.edited), ("edited early", true), "the edit that got here first was applied when the message came");
}

#[test]
fn reactions_edits_and_deletes_work_in_a_group() {
    let server = FakeServer::new();
    let (alice, bob, carol, transport, chat) = team(&server);
    for p in [&bob, &carol] {
        p.store.accept_request(chat.clone()).unwrap();
    }
    deliver(&bob, &transport);
    deliver(&carol, &transport);
    for p in [&alice, &bob, &carol] {
        sync(p, &transport);
    }
    let sent = alice.store.queue_text(chat.clone(), "field trip friday".into()).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    sync(&carol, &transport);

    bob.store.react(chat.clone(), sent.id.clone(), "❤️".into(), true).unwrap();
    carol.store.react(chat.clone(), sent.id.clone(), "❤️".into(), true).unwrap();
    deliver(&bob, &transport);
    deliver(&carol, &transport);
    sync(&alice, &transport);
    sync(&carol, &transport);
    sync(&bob, &transport);
    for p in [&alice, &bob, &carol] {
        let r = item_of(p, &chat, &sent.id).reactions;
        assert_eq!((r.len(), r[0].count), (1, 2), "{}: both hearts", p.user);
    }
    assert!(item_of(&alice, &chat, &sent.id).reactions[0].people.len() == 2, "who reacted");

    alice.store.edit_message(chat.clone(), sent.id.clone(), "field trip is monday".into()).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    assert_eq!(item_of(&bob, &chat, &sent.id).text, "field trip is monday");
    assert!(bob.store.edit_message(chat.clone(), sent.id.clone(), "mine now".into()).is_err());

    alice.store.delete_message_for_everyone(chat.clone(), sent.id.clone()).unwrap();
    deliver(&alice, &transport);
    sync(&bob, &transport);
    sync(&carol, &transport);
    for p in [&bob, &carol] {
        assert!(item_of(p, &chat, &sent.id).deleted, "{}", p.user);
    }
    // A member cannot delete someone else's message for everyone.
    let other = bob.store.queue_text(chat.clone(), "bob's note".into()).unwrap();
    deliver(&bob, &transport);
    assert!(alice.store.delete_message_for_everyone(chat.clone(), other.id.clone()).is_err());
}
