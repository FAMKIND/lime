//! Two LimeCore instances, as two different accounts, exchange an Olm-encrypted message through a
//! real Supabase stack (the local one, or staging). Run with `./core/run-integration.sh`, which
//! supplies the URL and keys through the environment; nothing secret is in this file or the repo.
//!
//! The test creates throwaway accounts through the admin API and always deletes them.

#![cfg(feature = "integration")]

use std::sync::Arc;

use lime_core::{
    lookup_user_by_email, HeaderPair, LimeStore, Transport, TransportError, TransportResponse,
};
use serde_json::{json, Value};

fn env(name: &str) -> String {
    std::env::var(name)
        .unwrap_or_else(|_| panic!("{name} is not set (use ./core/run-integration.sh)"))
}

/// The platform side of the transport, with a blocking HTTP client (iOS uses URLSession).
struct HttpTransport {
    base: String,
    anon_key: String,
}

impl Transport for HttpTransport {
    fn request(
        &self,
        method: String,
        path: String,
        headers: Vec<HeaderPair>,
        body: Vec<u8>,
    ) -> Result<TransportResponse, TransportError> {
        let mut request =
            ureq::request(&method, &format!("{}{path}", self.base)).set("apikey", &self.anon_key);
        for header in &headers {
            request = request.set(&header.name, &header.value);
        }
        let result = request.send_bytes(&body);
        let response = match result {
            Ok(response) => response,
            Err(ureq::Error::Status(_, response)) => response,
            Err(_) => return Err(TransportError::Failed),
        };
        let status = response.status();
        if status >= 400 {
            eprintln!("integration transport: {method} {path} answered {status}");
        }
        let mut bytes = Vec::new();
        std::io::Read::read_to_end(&mut response.into_reader(), &mut bytes)
            .map_err(|_| TransportError::Failed)?;
        Ok(TransportResponse {
            status,
            body: bytes,
        })
    }
}

struct Admin {
    base: String,
    anon_key: String,
    service_key: String,
}

struct Account {
    id: String,
    email: String,
    token: String,
}

impl Admin {
    /// Authorises a request with the service key. New-style secret keys (`sb_secret_...`) go in the
    /// `apikey` header only; a legacy service-role JWT also goes in `Authorization`.
    fn with_service_key(&self, request: ureq::Request) -> ureq::Request {
        let request = request.set("apikey", &self.service_key);
        if self.service_key.starts_with("eyJ") {
            request.set("authorization", &format!("Bearer {}", self.service_key))
        } else {
            request
        }
    }

    fn from_env() -> Self {
        Self {
            base: env("LIME_API_URL"),
            anon_key: env("LIME_ANON_KEY"),
            service_key: env("LIME_SERVICE_ROLE_KEY"),
        }
    }

    fn transport(&self) -> Arc<dyn Transport> {
        Arc::new(HttpTransport {
            base: self.base.clone(),
            anon_key: self.anon_key.clone(),
        })
    }

    fn json(&self, request: ureq::Request, body: Option<Value>) -> Value {
        let response = match body {
            Some(body) => request.send_json(body),
            None => request.call(),
        };
        match response {
            Ok(r) => r.into_json().unwrap_or(Value::Null),
            Err(ureq::Error::Status(code, r)) => panic!(
                "admin call failed with {code}: {}",
                r.into_string().unwrap_or_default().len()
            ),
            Err(_) => panic!("admin call could not be made"),
        }
    }

    fn create_account(&self) -> Account {
        let suffix = uuid::Uuid::new_v4();
        let email = format!("it-{suffix}@example.invalid");
        let password = uuid::Uuid::new_v4().to_string();
        let created = self.json(
            self.with_service_key(ureq::post(&format!("{}/auth/v1/admin/users", self.base))),
            Some(json!({ "email": email, "password": password, "email_confirm": true })),
        );
        let id = created["id"].as_str().expect("a user id").to_owned();
        let session = self.json(
            ureq::post(&format!("{}/auth/v1/token?grant_type=password", self.base))
                .set("apikey", &self.anon_key),
            Some(json!({ "email": email, "password": password })),
        );
        let token = session["access_token"]
            .as_str()
            .expect("an access token")
            .to_owned();
        // The server only lets a session that passed the password AND the emailed code do anything.
        // The account functions record that after really checking both; a test that is about the
        // messaging, not the sign-in, writes the same record directly (this needs the service key).
        let claims: Value =
            serde_json::from_slice(&base64_url_decode(token.split('.').nth(1).expect("a JWT")))
                .expect("claims");
        let session_id = claims["session_id"].as_str().expect("a session id");
        let marked = self
            .with_service_key(ureq::post(&format!("{}/rest/v1/auth_proofs", self.base)))
            .send_json(json!({
                "session_id": session_id, "user_id": id, "password_ok": true, "code_ok": true
            }));
        assert!(marked.is_ok(), "could not mark the session verified");
        Account { id, email, token }
    }

    /// Gives an account a public profile (the directory fields), as `profile-set` would.
    fn give_profile(&self, account: &Account, name: &str, username: &str) {
        let made = self
            .with_service_key(ureq::post(&format!("{}/rest/v1/profiles", self.base)))
            .send_json(json!({ "user_id": account.id, "display_name": name, "username": username }));
        assert!(made.is_ok(), "could not make the profile");
    }

    fn delete_account(&self, account: &Account) {
        let _ = self
            .with_service_key(ureq::delete(&format!(
                "{}/auth/v1/admin/users/{}",
                self.base, account.id
            )))
            .call();
    }

    /// The names of the server's tables (from the REST API's schema), and every row of each as text (test only: needs
    /// the service key). A table that cannot be read is skipped.
    fn every_table(&self) -> Vec<(String, String)> {
        let schema = self.json(self.with_service_key(ureq::get(&format!("{}/rest/v1/", self.base))), None);
        let mut tables = Vec::new();
        for name in schema["definitions"].as_object().map(|d| d.keys().cloned().collect::<Vec<_>>()).unwrap_or_default() {
            let request = self.with_service_key(ureq::get(&format!("{}/rest/v1/{name}?select=*&limit=5000", self.base)));
            if let Ok(response) = request.call() {
                tables.push((name, response.into_string().unwrap_or_default()));
            }
        }
        tables
    }

    /// What the server stores about each waiting item of a device: whether it is identified, and the sender
    /// it recorded (test only: needs the service key). A sealed item must have none.
    fn mailbox_senders(&self, device_id: &str) -> Vec<(bool, Option<String>)> {
        let rows = self.json(
            self.with_service_key(ureq::get(&format!(
                "{}/rest/v1/mailbox_items?select=identified,sender_user&to_device=eq.{device_id}&order=cursor",
                self.base
            ))),
            None,
        );
        rows.as_array()
            .expect("rows")
            .iter()
            .map(|row| (row["identified"].as_bool().unwrap(), row["sender_user"].as_str().map(str::to_owned)))
            .collect()
    }

    /// The bytes of a Storage object, read with the service key (test only), or `None` when it is not there.
    fn storage_object(&self, bucket: &str, name: &str) -> Option<Vec<u8>> {
        let request = self.with_service_key(ureq::get(&format!("{}/storage/v1/object/{bucket}/{name}", self.base)));
        match request.call() {
            Ok(response) => {
                let mut bytes = Vec::new();
                std::io::Read::read_to_end(&mut response.into_reader(), &mut bytes).unwrap();
                Some(bytes)
            }
            Err(_) => None,
        }
    }

    /// The names of the objects in a bucket under a prefix, from Storage's own listing (not a download, which a
    /// CDN may serve from its cache for a while after a delete).
    fn storage_names(&self, bucket: &str, prefix: &str) -> Vec<String> {
        let request = self.with_service_key(ureq::post(&format!("{}/storage/v1/object/list/{bucket}", self.base)));
        let rows: Value = request.send_json(json!({ "prefix": "", "search": prefix, "limit": 100 })).unwrap().into_json().unwrap();
        rows.as_array().unwrap().iter().filter_map(|r| r["name"].as_str().map(str::to_owned)).collect()
    }

    /// The raw mailbox rows of a device, as the server holds them (test only: needs the service key).
    fn raw_mailbox(&self, device_id: &str) -> Vec<Vec<u8>> {
        let rows = self.json(
            self.with_service_key(ureq::get(&format!(
                "{}/rest/v1/mailbox_items?select=ciphertext&to_device=eq.{device_id}",
                self.base
            ))),
            None,
        );
        rows.as_array()
            .expect("rows")
            .iter()
            .map(|row| {
                let hex = row["ciphertext"]
                    .as_str()
                    .expect("bytea")
                    .trim_start_matches("\\x");
                (0..hex.len() / 2)
                    .map(|i| u8::from_str_radix(&hex[i * 2..i * 2 + 2], 16).unwrap())
                    .collect()
            })
            .collect()
    }
}

/// Deletes the throwaway accounts when the test ends, even if it panics.
struct Cleanup<'a>(&'a Admin, Vec<Account>);

impl Drop for Cleanup<'_> {
    fn drop(&mut self) {
        for account in &self.1 {
            self.0.delete_account(account);
        }
    }
}

fn base64_url_decode(part: &str) -> Vec<u8> {
    let standard = part.replace('-', "+").replace('_', "/");
    vodozemac::base64_decode(standard.trim_end_matches('=')).expect("base64")
}

fn store(dir: &tempfile::TempDir, name: &str, key_byte: u8) -> Arc<LimeStore> {
    LimeStore::open(
        dir.path().join(name).to_string_lossy().into_owned(),
        vec![key_byte; 32],
    )
    .unwrap()
}

#[test]
fn two_accounts_exchange_an_olm_encrypted_message() {
    let admin = Admin::from_env();
    let transport = admin.transport();
    let alice = admin.create_account();
    let bob = admin.create_account();
    let cleanup = Cleanup(&admin, vec![]);
    let mut cleanup = cleanup;
    cleanup.1.push(Account {
        id: alice.id.clone(),
        email: alice.email.clone(),
        token: alice.token.clone(),
    });
    cleanup.1.push(Account {
        id: bob.id.clone(),
        email: bob.email.clone(),
        token: bob.token.clone(),
    });

    let dir = tempfile::tempdir().unwrap();
    let alice_store = store(&dir, "alice.db", 1);
    let bob_store = store(&dir, "bob.db", 2);

    // Register both: the server hands back the account's user id; a fresh pool of 50 keys is up.
    let alice_device = alice_store
        .register_device(transport.clone(), alice.token.clone())
        .unwrap();
    let bob_device = bob_store
        .register_device(transport.clone(), bob.token.clone())
        .unwrap();
    assert_eq!(alice_device.user_id, alice.id);
    assert_eq!(bob_device.user_id, bob.id);
    assert_eq!(bob_device.remaining_one_time_keys, 50);
    // Registering again is idempotent: the same device, no new keys.
    let again = bob_store
        .register_device(transport.clone(), bob.token.clone())
        .unwrap();
    assert_eq!(again.device_id, bob_device.device_id);
    assert_eq!(again.identity_key, bob_device.identity_key);

    // Alice finds Bob by his exact email (any case); an unknown email finds nobody.
    assert_eq!(
        lookup_user_by_email(
            transport.clone(),
            alice.token.clone(),
            bob.email.to_uppercase()
        )
        .unwrap(),
        Some(bob.id.clone())
    );
    assert_eq!(
        lookup_user_by_email(
            transport.clone(),
            alice.token.clone(),
            "nobody@example.invalid".into()
        )
        .unwrap(),
        None
    );

    // Alice sends. The message is stored locally as sent.
    let sent = alice_store
        .send_text_identified(
            transport.clone(),
            alice.token.clone(),
            bob.id.clone(),
            "hello from A".into(),
        )
        .unwrap();
    assert_eq!(sent.text, "hello from A");
    assert_eq!(sent.local_state, "sent");
    assert!(sent.sender_id.is_none());

    // What the server holds is ciphertext: not the plaintext, and not containing it.
    let on_server = admin.raw_mailbox(&bob_device.device_id);
    assert_eq!(on_server.len(), 1);
    let plaintext = b"hello from A";
    assert_ne!(on_server[0], plaintext.to_vec());
    assert!(
        !on_server[0]
            .windows(plaintext.len())
            .any(|w| w == plaintext),
        "the server must not see the text"
    );

    // Bob syncs: one message arrives, decrypted and verified, in a DM with Alice.
    let report = bob_store
        .sync(transport.clone(), bob.token.clone())
        .unwrap();
    assert_eq!(report.received, 1);
    let bob_view = bob_store.list_conversations().unwrap();
    let dm = bob_view
        .iter()
        .find(|c| c.id == format!("dm:{}", alice.id))
        .expect("a DM with Alice");
    assert_eq!(
        dm.title, alice.id,
        "titled with the sender's user id for now"
    );
    assert!(!dm.is_group);
    assert_eq!(dm.unread, 1);
    let messages = bob_store.list_messages(dm.id.clone()).unwrap();
    assert_eq!(messages.len(), 1);
    assert_eq!(messages[0].text, "hello from A");
    assert_eq!(messages[0].sender_id.as_deref(), Some(alice.id.as_str()));
    // A sync again finds nothing, and Bob's mailbox on the server is empty (acknowledged).
    assert_eq!(
        bob_store
            .sync(transport.clone(), bob.token.clone())
            .unwrap()
            .received,
        0
    );
    assert!(admin.raw_mailbox(&bob_device.device_id).is_empty());

    // Bob replies; Alice receives it (the reply rides the session Bob's pre-key message made).
    bob_store
        .send_text_identified(
            transport.clone(),
            bob.token.clone(),
            alice.id.clone(),
            "hi back from B".into(),
        )
        .unwrap();
    assert_eq!(
        alice_store
            .sync(transport.clone(), alice.token.clone())
            .unwrap()
            .received,
        1
    );
    let alice_dm = format!("dm:{}", bob.id);
    let texts: Vec<String> = alice_store
        .list_messages(alice_dm.clone())
        .unwrap()
        .into_iter()
        .map(|m| m.text)
        .collect();
    assert_eq!(texts, vec!["hello from A", "hi back from B"]);
    assert!(admin.raw_mailbox(&alice_device.device_id).is_empty());

    // A second round on the established sessions (normal Olm messages, no new one-time key).
    alice_store
        .send_text_identified(
            transport.clone(),
            alice.token.clone(),
            bob.id.clone(),
            "second from A".into(),
        )
        .unwrap();
    assert_eq!(
        bob_store
            .sync(transport.clone(), bob.token.clone())
            .unwrap()
            .received,
        1
    );
    let bob_texts: Vec<String> = bob_store
        .list_messages(dm.id.clone())
        .unwrap()
        .into_iter()
        .map(|m| m.text)
        .collect();
    assert_eq!(bob_texts.last().map(String::as_str), Some("second from A"));
    let after = bob_store
        .register_device(transport.clone(), bob.token.clone())
        .unwrap();
    assert_eq!(
        after.remaining_one_time_keys, 49,
        "exactly one of Bob's one-time keys was used"
    );

    // Everything survives a restart: reopen Bob's store and read the chat again.
    drop(bob_store);
    let reopened = store(&dir, "bob.db", 2);
    assert_eq!(
        reopened.list_messages(dm.id.clone()).unwrap().len(),
        3,
        "A, B's reply, then A again"
    );
    // ...and the persisted keys still work: Bob can send after the restart.
    reopened
        .send_text_identified(
            transport.clone(),
            bob.token.clone(),
            alice.id.clone(),
            "after a restart".into(),
        )
        .unwrap();
    assert_eq!(
        alice_store
            .sync(transport.clone(), alice.token.clone())
            .unwrap()
            .received,
        1
    );

    drop(cleanup);
}

#[test]
fn a_message_that_was_tampered_with_is_not_stored() {
    let admin = Admin::from_env();
    let transport = admin.transport();
    let alice = admin.create_account();
    let bob = admin.create_account();
    let mut cleanup = Cleanup(&admin, vec![]);
    cleanup.1.push(Account {
        id: alice.id.clone(),
        email: alice.email.clone(),
        token: alice.token.clone(),
    });
    cleanup.1.push(Account {
        id: bob.id.clone(),
        email: bob.email.clone(),
        token: bob.token.clone(),
    });

    let dir = tempfile::tempdir().unwrap();
    let alice_store = store(&dir, "alice.db", 1);
    let bob_store = store(&dir, "bob.db", 2);
    alice_store
        .register_device(transport.clone(), alice.token.clone())
        .unwrap();
    let bob_device = bob_store
        .register_device(transport.clone(), bob.token.clone())
        .unwrap();

    alice_store
        .send_text_identified(
            transport.clone(),
            alice.token.clone(),
            bob.id.clone(),
            "genuine".into(),
        )
        .unwrap();
    // Flip a byte of the stored ciphertext on the server (test only), as a hostile server might.
    let rows = admin.raw_mailbox(&bob_device.device_id);
    assert_eq!(rows.len(), 1);
    let mut tampered = rows[0].clone();
    let middle = tampered.len() / 2;
    tampered[middle] ^= 0x55;
    let hex: String = tampered.iter().map(|b| format!("{b:02x}")).collect();
    let patch = admin
        .with_service_key(ureq::request(
            "PATCH",
            &format!(
                "{}/rest/v1/mailbox_items?to_device=eq.{}",
                admin.base, bob_device.device_id
            ),
        ))
        .send_json(json!({ "ciphertext": format!("\\x{hex}") }));
    assert!(patch.is_ok());

    // Bob's sync does not store it (it fails to decrypt), and it is acknowledged, not retried forever.
    assert_eq!(
        bob_store
            .sync(transport.clone(), bob.token.clone())
            .unwrap()
            .received,
        0
    );
    assert!(bob_store
        .list_messages(format!("dm:{}", alice.id))
        .unwrap_or_default()
        .is_empty());
    assert!(admin.raw_mailbox(&bob_device.device_id).is_empty());
    drop(cleanup);
}

#[test]
fn find_request_accept_reply_and_block_through_the_real_server() {
    let admin = Admin::from_env();
    let transport = admin.transport();
    let alice = admin.create_account();
    let bob = admin.create_account();
    let mut cleanup = Cleanup(&admin, vec![]);
    for a in [&alice, &bob] {
        cleanup.1.push(Account { id: a.id.clone(), email: a.email.clone(), token: a.token.clone() });
    }
    let suffix = uuid::Uuid::new_v4().simple().to_string();
    let (alice_name, bob_name) = (format!("al{}", &suffix[..8]), format!("bo{}", &suffix[..8]));
    admin.give_profile(&alice, "Alice Adams", &alice_name);
    admin.give_profile(&bob, "Bob Brown", &bob_name);
    let dir = tempfile::tempdir().unwrap();
    let (alice_store, bob_store) = (store(&dir, "alice.db", 1), store(&dir, "bob.db", 2));
    alice_store.register_device(transport.clone(), alice.token.clone()).unwrap();
    bob_store.register_device(transport.clone(), bob.token.clone()).unwrap();

    // Alice finds Bob by his exact username, then writes to him.
    let found = lime_core::find_user(transport.clone(), alice.token.clone(), format!("@{}", bob_name.to_uppercase()))
        .unwrap()
        .expect("found");
    assert_eq!((found.display_name.as_str(), found.user_id.as_str()), ("Bob Brown", bob.id.as_str()));
    assert!(lime_core::find_user(transport.clone(), alice.token.clone(), bob_name[..5].to_owned()).unwrap().is_none());
    let chat = alice_store.start_dm(found.user_id.clone(), found.display_name.clone()).unwrap();
    alice_store.queue_text(chat.clone(), "hello Bob".into()).unwrap();
    assert_eq!(alice_store.deliver_queued(transport.clone(), alice.token.clone()).unwrap(), 1);

    // It is a request on Bob's side, named from Alice's public profile.
    assert_eq!(bob_store.sync(transport.clone(), bob.token.clone()).unwrap().received, 1);
    let request = bob_store.list_conversations().unwrap().remove(0);
    assert_eq!((request.request_state.as_str(), request.title.as_str()), ("pending", "Alice Adams"));
    bob_store.accept_request(request.id.clone()).unwrap();
    bob_store.queue_text(request.id.clone(), "hi Alice".into()).unwrap();
    bob_store.deliver_queued(transport.clone(), bob.token.clone()).unwrap();
    assert_eq!(alice_store.sync(transport.clone(), alice.token.clone()).unwrap().received, 1);
    let texts: Vec<String> = alice_store.list_messages(chat.clone()).unwrap().into_iter().map(|m| m.text).collect();
    assert_eq!(texts, vec!["hello Bob", "hi Alice"]);

    // Bob blocks Alice: her next message is read and dropped, never shown.
    bob_store.block_sender(request.id.clone()).unwrap();
    alice_store.queue_text(chat, "are you there?".into()).unwrap();
    alice_store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    let report = bob_store.sync(transport.clone(), bob.token.clone()).unwrap();
    assert_eq!((report.received, report.pending), (0, 0));
    assert!(bob_store.list_conversations().unwrap().is_empty());
}

#[test]
fn a_phone_with_new_keys_replaces_the_account_keys_and_contacts_accept_the_change() {
    let admin = Admin::from_env();
    let transport = admin.transport();
    let alice = admin.create_account();
    let bob = admin.create_account();
    let mut cleanup = Cleanup(&admin, vec![]);
    for a in [&alice, &bob] {
        cleanup.1.push(Account { id: a.id.clone(), email: a.email.clone(), token: a.token.clone() });
    }
    let dir = tempfile::tempdir().unwrap();
    let (alice_store, bob_store) = (store(&dir, "alice.db", 1), store(&dir, "bob.db", 2));
    alice_store.register_device(transport.clone(), alice.token.clone()).unwrap();
    bob_store.register_device(transport.clone(), bob.token.clone()).unwrap();

    // Alice writes to Bob; it waits for his device. Then his keys are replaced (a phone with new keys).
    let chat = alice_store.start_dm(bob.id.clone(), "Bob".into()).unwrap();
    alice_store.queue_text(chat.clone(), "waiting for the old phone".into()).unwrap();
    alice_store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    let bob_new = store(&dir, "bob2.db", 3);
    bob_new.register_device(transport.clone(), bob.token.clone()).expect("a verified session may replace the keys");
    assert!(
        bob_store.sync(transport.clone(), bob.token.clone()).is_err(),
        "the old phone is refused: it was replaced"
    );
    assert!(matches!(
        bob_store.sync(transport.clone(), bob.token.clone()),
        Err(lime_core::StoreError::Unauthorized)
    ));

    // Alice is told the message was not delivered (the server and the core hash the same bytes).
    alice_store.sync(transport.clone(), alice.token.clone()).unwrap();
    let states: Vec<String> = alice_store.list_messages(chat.clone()).unwrap().into_iter().map(|m| m.local_state).collect();
    assert_eq!(states, vec!["undelivered"]);

    // Bob's key changed: she must accept it, then resend, and the new phone receives it.
    alice_store.queue_text(chat.clone(), "hello new phone".into()).unwrap();
    assert!(matches!(
        alice_store.deliver_queued(transport.clone(), alice.token.clone()),
        Err(lime_core::StoreError::KeyMismatch)
    ));
    assert!(alice_store.list_conversations().unwrap()[0].key_change_pending);
    alice_store.trust_new_key(chat.clone()).unwrap();
    let old = alice_store.list_messages(chat.clone()).unwrap().into_iter().find(|m| m.local_state == "undelivered").unwrap();
    alice_store.retry_message(old.id).unwrap();
    assert_eq!(alice_store.deliver_queued(transport.clone(), alice.token.clone()).unwrap(), 2);
    assert_eq!(bob_new.sync(transport.clone(), bob.token.clone()).unwrap().received, 2);
}

#[test]
fn sealed_sender_through_the_real_server_and_a_block_that_rotates_the_key() {
    let admin = Admin::from_env();
    let transport = admin.transport();
    let alice = admin.create_account();
    let bob = admin.create_account();
    let mut cleanup = Cleanup(&admin, vec![]);
    for a in [&alice, &bob] {
        cleanup.1.push(Account { id: a.id.clone(), email: a.email.clone(), token: a.token.clone() });
    }
    let suffix = uuid::Uuid::new_v4().simple().to_string();
    admin.give_profile(&alice, "Alice Adams", &format!("al{}", &suffix[..8]));
    admin.give_profile(&bob, "Bob Brown", &format!("bo{}", &suffix[..8]));
    let dir = tempfile::tempdir().unwrap();
    let (alice_store, bob_store) = (store(&dir, "alice.db", 1), store(&dir, "bob.db", 2));
    let alice_device = alice_store.register_device(transport.clone(), alice.token.clone()).unwrap().device_id;
    let bob_device = bob_store.register_device(transport.clone(), bob.token.clone()).unwrap().device_id;
    let texts = |store: &lime_core::LimeStore, chat: &str| -> Vec<String> {
        store.list_messages(chat.to_owned()).unwrap().into_iter().map(|m| m.text).collect()
    };

    // A stranger's first message is identified: the server records who sent it, and it lands in Requests.
    let chat_with_bob = alice_store.start_dm(bob.id.clone(), "Bob Brown".into()).unwrap();
    alice_store.queue_text(chat_with_bob.clone(), "hello Bob".into()).unwrap();
    alice_store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    assert!(admin.mailbox_senders(&bob_device).iter().all(|(identified, sender)| *identified && sender.as_deref() == Some(alice.id.as_str())));
    assert_eq!(bob_store.sync(transport.clone(), bob.token.clone()).unwrap().received, 1);
    let chat_with_alice = bob_store.list_conversations().unwrap().remove(0).id;
    assert_eq!(bob_store.list_conversations().unwrap()[0].request_state, "pending");

    // Bob accepts: Alice's delivery key and his own are exchanged, so what follows is sealed. The server's
    // copy of a sealed item has no sender at all.
    bob_store.accept_request(chat_with_alice.clone()).unwrap();
    bob_store.queue_text(chat_with_alice.clone(), "hi Alice".into()).unwrap();
    bob_store.deliver_queued(transport.clone(), bob.token.clone()).unwrap();
    let to_alice = admin.mailbox_senders(&alice_device);
    assert!(!to_alice.is_empty());
    assert!(to_alice.iter().all(|(identified, sender)| !identified && sender.is_none()), "sealed: no sender stored");
    assert_eq!(alice_store.sync(transport.clone(), alice.token.clone()).unwrap().received, 1);
    assert_eq!(alice_store.sealed_contact_count().unwrap(), 1);
    assert_eq!(bob_store.sealed_contact_count().unwrap(), 1);
    alice_store.queue_text(chat_with_bob.clone(), "sealed to Bob".into()).unwrap();
    alice_store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    let to_bob = admin.mailbox_senders(&bob_device);
    assert!(to_bob.iter().all(|(identified, sender)| !identified && sender.is_none()), "sealed: no sender stored");
    assert_eq!(bob_store.sync(transport.clone(), bob.token.clone()).unwrap().received, 1);
    assert_eq!(texts(&bob_store, &chat_with_alice), vec!["hello Bob", "hi Alice", "sealed to Bob"]);

    // Bob blocks Alice: his key rotates, so Alice's next sealed send is refused by the server. The app says
    // nothing: it sends the message identified at once and shows "Sent" (a blocked person learns nothing).
    bob_store.block_sender(chat_with_alice.clone()).unwrap();
    bob_store.deliver_queued(transport.clone(), bob.token.clone()).unwrap(); // puts the new key's hash on the server
    alice_store.queue_text(chat_with_bob.clone(), "are you there?".into()).unwrap();
    alice_store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    let state = |text: &str| alice_store.list_messages(chat_with_bob.clone()).unwrap().into_iter().find(|m| m.text == text).unwrap().local_state;
    assert_eq!(state("are you there?"), "sent", "never \"Not delivered\" for a refused sealed send");
    assert_eq!(admin.mailbox_senders(&bob_device), vec![(true, Some(alice.id.clone()))], "stored identified (the fallback names its sender, once)");
    assert_eq!(alice_store.sealed_contact_count().unwrap(), 0, "no more sealed sends until Bob shares a new key");
    // Bob reads and hides it: the blocker never sees it.
    assert_eq!(bob_store.sync(transport.clone(), bob.token.clone()).unwrap().received, 0);
    assert!(bob_store.list_conversations().unwrap().is_empty());

    // Bob unblocks her: she is given the new key and sealed sends work again.
    bob_store.unblock(chat_with_alice.clone()).unwrap();
    bob_store.deliver_queued(transport.clone(), bob.token.clone()).unwrap();
    alice_store.sync(transport.clone(), alice.token.clone()).unwrap();
    alice_store.queue_text(chat_with_bob.clone(), "back again".into()).unwrap();
    alice_store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    assert_eq!(state("back again"), "sent");
    assert!(admin.mailbox_senders(&bob_device).iter().all(|(identified, sender)| !identified && sender.is_none()));
    assert!(bob_store.sync(transport.clone(), bob.token.clone()).unwrap().received >= 1);
}

#[test]
fn a_group_of_three_chats_through_the_real_server_and_the_server_holds_no_group_state() {
    let admin = Admin::from_env();
    let transport = admin.transport();
    let accounts = [admin.create_account(), admin.create_account(), admin.create_account()];
    let mut cleanup = Cleanup(&admin, vec![]);
    for a in &accounts {
        cleanup.1.push(Account { id: a.id.clone(), email: a.email.clone(), token: a.token.clone() });
    }
    let suffix = uuid::Uuid::new_v4().simple().to_string();
    for (i, (account, name)) in accounts.iter().zip(["Ann Adams", "Bo Brown", "Cy Clark"]).enumerate() {
        admin.give_profile(account, name, &format!("g{i}{}", &suffix[..8]));
    }
    let dir = tempfile::tempdir().unwrap();
    let stores: Vec<_> = (0..3).map(|i| store(&dir, &format!("p{i}.db"), 10 + i as u8)).collect();
    for (s, a) in stores.iter().zip(&accounts) {
        s.register_device(transport.clone(), a.token.clone()).unwrap();
    }
    let sync = |i: usize| stores[i].sync(transport.clone(), accounts[i].token.clone()).unwrap();
    let deliver = |i: usize| stores[i].deliver_queued(transport.clone(), accounts[i].token.clone()).unwrap();
    let texts = |i: usize, chat: &str| -> Vec<String> {
        stores[i].list_messages(chat.to_owned()).unwrap().into_iter().filter(|m| m.local_state != "system").map(|m| m.text).collect()
    };

    // Ann makes a group (with a name nothing else would contain) with Bo and Cy; all three receive it.
    let secret_name = format!("Zanzibar{}", &suffix[8..20]);
    let chat = stores[0].create_group(secret_name.clone(), Some("🍎".into()), vec![accounts[1].id.clone(), accounts[2].id.clone()]).unwrap();
    deliver(0);
    sync(1);
    sync(2);
    for store in &stores[1..] {
        let group = store.list_conversations().unwrap().into_iter().find(|c| c.id == chat).expect("the group arrived");
        assert_eq!((group.title.as_str(), group.is_group, group.members.len()), (secret_name.as_str(), true, 2));
    }

    // Megolm through the real mailbox: one message, read by both; Bo answers.
    stores[0].queue_text(chat.clone(), "hello team".into()).unwrap();
    deliver(0);
    assert_eq!(sync(1).received, 1);
    assert_eq!(sync(2).received, 1);
    stores[1].queue_text(chat.clone(), "hi everyone".into()).unwrap();
    deliver(1);
    assert_eq!(sync(0).received, 1);
    assert_eq!(sync(2).received, 1);
    assert_eq!(texts(2, &chat), vec!["hello team", "hi everyone"]);

    // Rename, then remove Cy: what Ann says next reaches Bo only.
    stores[0].rename_group(chat.clone(), format!("{secret_name} Two")).unwrap();
    stores[0].remove_group_member(chat.clone(), accounts[2].id.clone()).unwrap();
    stores[0].queue_text(chat.clone(), "only for Bo".into()).unwrap();
    deliver(0);
    sync(1);
    sync(2);
    assert_eq!(texts(1, &chat), vec!["hello team", "hi everyone", "only for Bo"]);
    assert_eq!(texts(2, &chat), vec!["hello team", "hi everyone"], "Cy was removed and reads nothing more");
    assert!(stores[2].list_conversations().unwrap().iter().all(|c| c.id != chat), "gone from Cy's Messages");

    // The server holds no group state: no table has the group's name, and none is about groups or members.
    let tables = admin.every_table();
    assert!(!tables.is_empty(), "the admin query found the tables");
    for (name, rows) in &tables {
        assert!(!name.contains("group") && !name.contains("member"), "a table about groups: {name}");
        assert!(!rows.contains(&secret_name), "the group's name is in table {name}");
        assert!(!rows.contains("hello team") && !rows.contains("only for Bo"), "message text is in table {name}");
    }
}

#[test]
fn profile_photos_through_the_real_server_public_by_default_and_ciphertext_when_contacts_only() {
    let admin = Admin::from_env();
    let transport = admin.transport();
    let accounts = [admin.create_account(), admin.create_account(), admin.create_account()];
    let mut cleanup = Cleanup(&admin, vec![]);
    for a in &accounts {
        cleanup.1.push(Account { id: a.id.clone(), email: a.email.clone(), token: a.token.clone() });
    }
    let [alice, bob, carol] = &accounts;
    let suffix = uuid::Uuid::new_v4().simple().to_string();
    for (a, name, tag) in [(alice, "Alice Adams", "al"), (bob, "Bob Brown", "bo"), (carol, "Carol Cruz", "ca")] {
        admin.give_profile(a, name, &format!("{tag}{}", &suffix[..8]));
    }
    let dir = tempfile::tempdir().unwrap();
    let stores: Vec<_> = (0..3).map(|i| store(&dir, &format!("p{i}.db"), i as u8 + 1)).collect();
    for (store, account) in stores.iter().zip(&accounts) {
        store.register_device(transport.clone(), account.token.clone()).unwrap();
    }
    let (alice_store, bob_store, carol_store) = (&stores[0], &stores[1], &stores[2]);
    let photo: Vec<u8> = b"\xff\xd8\xff\xe0 integration photo body, easy to spot: ".repeat(60);

    // Alice and Bob are contacts; Carol is a stranger who wrote to Alice (a request Alice has not accepted, so
    // Alice has given her neither key).
    let chat_bob = alice_store.start_dm(bob.id.clone(), "Bob Brown".into()).unwrap();
    alice_store.queue_text(chat_bob, "hello Bob".into()).unwrap();
    alice_store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    bob_store.sync(transport.clone(), bob.token.clone()).unwrap();
    bob_store.accept_request(format!("dm:{}", alice.id)).unwrap();
    bob_store.deliver_queued(transport.clone(), bob.token.clone()).unwrap();
    alice_store.sync(transport.clone(), alice.token.clone()).unwrap();
    let chat_alice = carol_store.start_dm(alice.id.clone(), "Alice Adams".into()).unwrap();
    carol_store.queue_text(chat_alice, "hello Alice".into()).unwrap();
    carol_store.deliver_queued(transport.clone(), carol.token.clone()).unwrap();
    alice_store.sync(transport.clone(), alice.token.clone()).unwrap();

    // Public by default: a plain JPEG any signed-in user can fetch; the server holds it as is.
    alice_store.set_my_photo(transport.clone(), alice.token.clone(), photo.clone()).unwrap();
    assert_eq!(admin.storage_names("public-avatars", &alice.id), vec![format!("{}.jpg", alice.id)]);
    assert_eq!(admin.storage_object("public-avatars", &format!("{}.jpg", alice.id)), Some(photo.clone()));
    assert_eq!(carol_store.refresh_photos(transport.clone(), carol.token.clone(), true).unwrap(), vec![alice.id.clone()]);
    assert_eq!(carol_store.peer_photo(alice.id.clone()).unwrap(), Some(photo.clone()), "a signed-in stranger sees a public photo");

    // Contacts only: the public object is deleted, and what the server keeps is ciphertext.
    alice_store.set_photo_visibility(transport.clone(), alice.token.clone(), "contacts".into()).unwrap();
    assert!(admin.storage_names("public-avatars", &alice.id).is_empty(), "the public copy is deleted from the server");
    let blobs = admin.json(
        admin.with_service_key(ureq::get(&format!("{}/rest/v1/blobs?select=id,owner,size", admin.base))),
        None,
    );
    let rows: Vec<&Value> = blobs.as_array().unwrap().iter().filter(|r| r["owner"] == alice.id.as_str()).collect();
    assert_eq!(rows.len(), 1);
    let stored = admin.storage_object("blobs", rows[0]["id"].as_str().unwrap()).expect("the encrypted blob");
    assert_ne!(stored, photo);
    assert!(!stored.windows(40).any(|w| w == &photo[..40]), "the stored bytes do not contain the photo");
    assert!(stored.len() > photo.len(), "nonce and tag on top of the same length");

    assert_eq!(bob_store.refresh_photos(transport.clone(), bob.token.clone(), true).unwrap(), vec![alice.id.clone()]);
    assert_eq!(bob_store.peer_photo(alice.id.clone()).unwrap(), Some(photo.clone()), "a contact decrypts it");
    assert_eq!(carol_store.refresh_photos(transport.clone(), carol.token.clone(), true).unwrap(), vec![alice.id.clone()]);
    assert_eq!(carol_store.peer_photo(alice.id.clone()).unwrap(), None, "a stranger sees initials");

    // A change reaches a contact within one sync, with no hourly wait: Alice switches back to everyone, Bob is told
    // (a control op, not a message) and his next ordinary refresh shows the change at once.
    alice_store.set_photo_visibility(transport.clone(), alice.token.clone(), "everyone".into()).unwrap();
    alice_store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    assert_eq!(bob_store.sync(transport.clone(), bob.token.clone()).unwrap().received, 0, "a notice is not a message");
    assert_eq!(bob_store.refresh_photos(transport.clone(), bob.token.clone(), false).unwrap(), vec![alice.id.clone()], "checked at once, not hourly");
    alice_store.remove_my_photo(transport.clone(), alice.token.clone()).unwrap();
    alice_store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    bob_store.sync(transport.clone(), bob.token.clone()).unwrap();
    assert_eq!(bob_store.refresh_photos(transport.clone(), bob.token.clone(), false).unwrap(), vec![alice.id.clone()]);
    assert_eq!(bob_store.peer_photo(alice.id.clone()).unwrap(), None, "the removal reached Bob too");
    alice_store.set_my_photo(transport.clone(), alice.token.clone(), photo.clone()).unwrap();

    // Remove: gone everywhere.
    alice_store.remove_my_photo(transport.clone(), alice.token.clone()).unwrap();
    let left = admin.json(admin.with_service_key(ureq::get(&format!("{}/rest/v1/blobs?select=id,owner", admin.base))), None);
    assert!(left.as_array().unwrap().iter().all(|r| r["owner"] != alice.id.as_str()), "no blob row left");
}

#[test]
fn attachments_through_the_real_server_are_ciphertext_delete_after_the_last_fetch_and_swept_when_expired() {
    let admin = Admin::from_env();
    let transport = admin.transport();
    let accounts = [admin.create_account(), admin.create_account()];
    let mut cleanup = Cleanup(&admin, vec![]);
    for a in &accounts {
        cleanup.1.push(Account { id: a.id.clone(), email: a.email.clone(), token: a.token.clone() });
    }
    let [alice, bob] = &accounts;
    let suffix = uuid::Uuid::new_v4().simple().to_string();
    admin.give_profile(alice, "Alice Adams", &format!("al{}", &suffix[..8]));
    admin.give_profile(bob, "Bob Brown", &format!("bo{}", &suffix[..8]));
    let dir = tempfile::tempdir().unwrap();
    let (alice_store, bob_store) = (store(&dir, "a.db", 1), store(&dir, "b.db", 2));
    alice_store.register_device(transport.clone(), alice.token.clone()).unwrap();
    bob_store.register_device(transport.clone(), bob.token.clone()).unwrap();

    let photo: Vec<u8> = b"\xff\xd8\xff\xe0 a photo that must not be readable on the server ".repeat(400);
    let document: Vec<u8> = (0..2_300_000u32).map(|i| (i.wrapping_mul(2654435761) >> 24) as u8).collect();   // three chunks
    let chat = alice_store.start_dm(bob.id.clone(), "Bob Brown".into()).unwrap();
    alice_store
        .send_attachments(
            chat.clone(),
            "the files".into(),
            vec![
                lime_core::OutgoingAttachment { bytes: photo.clone(), name: "photo.jpg".into(), mime: "image/jpeg".into(), width: Some(10), height: Some(10), duration_ms: None, thumb: vec![1; 200] },
                lime_core::OutgoingAttachment { bytes: document.clone(), name: "plan.pdf".into(), mime: "application/pdf".into(), width: None, height: None, duration_ms: None, thumb: vec![] },
            ],
            None,
        )
        .unwrap();
    alice_store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    assert_eq!(bob_store.sync(transport.clone(), bob.token.clone()).unwrap().received, 1);

    // Ciphertext on the server: four chunks, none of them readable, none containing the photo.
    let rows = admin.json(admin.with_service_key(ureq::get(&format!("{}/rest/v1/attachments?select=id,chunks,size,owner,recipients,expires_at", admin.base))), None);
    let mine: Vec<&Value> = rows.as_array().unwrap().iter().filter(|r| r["owner"] == alice.id.as_str()).collect();
    assert_eq!(mine.len(), 2);
    assert!(mine.iter().all(|r| r["recipients"] == 1));
    for row in &mine {
        let id = row["id"].as_str().unwrap();
        for n in 0..row["chunks"].as_u64().unwrap() {
            let stored = admin.storage_object("blobs", &format!("a/{id}/{n}")).expect("a chunk");
            assert!(!stored.windows(32).any(|w| w == &photo[..32]), "the server's bytes are not the photo");
            assert!(!stored.windows(32).any(|w| w == &document[1000..1032]), "nor the document");
        }
    }

    // Bob downloads, decrypts and verifies both.
    let message = bob_store.list_messages(format!("dm:{}", alice.id)).unwrap().into_iter().find(|m| m.text == "the files").unwrap();
    assert_eq!(message.attachments.len(), 2);
    for (info, original) in message.attachments.iter().zip([&photo, &document]) {
        bob_store.download_attachment(transport.clone(), bob.token.clone(), info.id.clone()).unwrap();
        assert_eq!(bob_store.attachment_data(info.id.clone()).unwrap().as_ref(), Some(original));
    }

    // Everyone (the one recipient) has fetched: the server now deletes it within the hour.
    let rows = admin.json(admin.with_service_key(ureq::get(&format!("{}/rest/v1/attachments?select=id,owner,expires_at", admin.base))), None);
    for row in rows.as_array().unwrap().iter().filter(|r| r["owner"] == alice.id.as_str()) {
        let expires = chrono_like_ms(row["expires_at"].as_str().unwrap());
        assert!(expires < now_ms() + 3_700_000, "due within the hour once every recipient fetched it");
    }

    // The sweep (which pg_cron runs every 15 minutes) removes it once it has expired.
    let secret = admin.json(admin.with_service_key(ureq::get(&format!("{}/rest/v1/sweep_target?select=secret", admin.base))), None)[0]["secret"].as_str().expect("the sweep is scheduled (supabase/schedule-sweep.sh)").to_owned();
    let past = "2000-01-01T00:00:00Z";
    let ids: Vec<String> = mine.iter().map(|r| r["id"].as_str().unwrap().to_owned()).collect();
    for id in &ids {
        let request = admin.with_service_key(ureq::request("PATCH", &format!("{}/rest/v1/attachments?id=eq.{id}", admin.base)));
        request.send_json(json!({ "expires_at": past })).unwrap();
    }
    let sweep = ureq::post(&format!("{}/functions/v1/blob-sweep", admin.base)).set("apikey", &admin.anon_key).set("x-sweep-secret", &secret).send_json(json!({})).unwrap();
    let swept: Value = sweep.into_json().unwrap();
    assert!(swept["attachments"].as_u64().unwrap() >= 2, "{swept}");
    for id in &ids {
        assert!(admin.storage_names("blobs", id).is_empty() || admin.storage_object("blobs", &format!("a/{id}/0")).is_none(), "its chunks are gone");
    }
    assert!(bob_store.download_attachment(transport.clone(), bob.token.clone(), message.attachments[0].id.clone()).is_ok(), "Bob keeps his own decrypted copy");
}

fn now_ms() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_millis() as i64
}

/// Milliseconds since the epoch of a Postgres `timestamptz` like `2026-10-08T22:11:03.123+00:00`.
fn chrono_like_ms(text: &str) -> i64 {
    let date = &text[..19];
    let (y, mo, d) = (date[0..4].parse::<i64>().unwrap(), date[5..7].parse::<i64>().unwrap(), date[8..10].parse::<i64>().unwrap());
    let (h, mi, s) = (date[11..13].parse::<i64>().unwrap(), date[14..16].parse::<i64>().unwrap(), date[17..19].parse::<i64>().unwrap());
    // Days from civil (Howard Hinnant's algorithm).
    let y2 = if mo <= 2 { y - 1 } else { y };
    let era = y2.div_euclid(400);
    let yoe = y2 - era * 400;
    let doy = (153 * (mo + if mo > 2 { -3 } else { 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146097 + doe - 719468;
    ((days * 24 + h) * 60 + mi) * 60_000 + s * 1000
}

#[test]
fn a_voice_note_and_a_video_travel_as_ciphertext_and_a_download_survives_an_interruption() {
    let admin = Admin::from_env();
    let transport = admin.transport();
    let accounts = [admin.create_account(), admin.create_account()];
    let mut cleanup = Cleanup(&admin, vec![]);
    for a in &accounts {
        cleanup.1.push(Account { id: a.id.clone(), email: a.email.clone(), token: a.token.clone() });
    }
    let [alice, bob] = &accounts;
    let suffix = uuid::Uuid::new_v4().simple().to_string();
    admin.give_profile(alice, "Alice Adams", &format!("al{}", &suffix[..8]));
    admin.give_profile(bob, "Bob Brown", &format!("bo{}", &suffix[..8]));
    let dir = tempfile::tempdir().unwrap();
    let (alice_store, bob_store) = (store(&dir, "a.db", 1), store(&dir, "b.db", 2));
    alice_store.register_device(transport.clone(), alice.token.clone()).unwrap();
    bob_store.register_device(transport.clone(), bob.token.clone()).unwrap();

    let voice: Vec<u8> = b"ftypM4A  a voice note that must not be readable on the server ".repeat(900);
    let video: Vec<u8> = (0..3_200_000u32).map(|i| (i.wrapping_mul(2246822519) >> 24) as u8).collect();   // four chunks
    let chat = alice_store.start_dm(bob.id.clone(), "Bob Brown".into()).unwrap();
    let make = |bytes: &Vec<u8>, name: &str, mime: &str, duration: u32, thumb: Vec<u8>| lime_core::OutgoingAttachment {
        bytes: bytes.clone(), name: name.into(), mime: mime.into(), width: None, height: None, duration_ms: Some(duration), thumb,
    };
    alice_store.send_attachments(chat.clone(), "".into(), vec![make(&voice, "Voice message.m4a", "audio/mp4", 12_000, (0..64).collect())], None).unwrap();
    alice_store.send_attachments(chat.clone(), "".into(), vec![make(&video, "clip.mp4", "video/mp4", 30_000, vec![7; 300])], None).unwrap();
    alice_store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    assert_eq!(bob_store.sync(transport.clone(), bob.token.clone()).unwrap().received, 2);

    let rows = admin.json(admin.with_service_key(ureq::get(&format!("{}/rest/v1/attachments?select=id,chunks,owner", admin.base))), None);
    let mine: Vec<&Value> = rows.as_array().unwrap().iter().filter(|r| r["owner"] == alice.id.as_str()).collect();
    assert_eq!(mine.len(), 2);
    for row in &mine {
        let id = row["id"].as_str().unwrap();
        for n in 0..row["chunks"].as_u64().unwrap() {
            let stored = admin.storage_object("blobs", &format!("a/{id}/{n}")).expect("a chunk");
            assert!(!stored.windows(32).any(|w| w == &voice[..32]), "the server's bytes are not the voice note");
            assert!(!stored.windows(32).any(|w| w == &video[2000..2032]), "nor the video");
        }
    }

    let messages = bob_store.list_messages(format!("dm:{}", alice.id)).unwrap();
    let infos: Vec<_> = messages.iter().flat_map(|m| m.attachments.clone()).collect();
    assert_eq!(infos.len(), 2);
    let (voice_info, video_info) = (infos.iter().find(|i| i.mime == "audio/mp4").unwrap(), infos.iter().find(|i| i.mime == "video/mp4").unwrap());
    assert_eq!((voice_info.duration_ms, voice_info.thumb.len()), (Some(12_000), 64), "duration and waveform arrive");
    assert_eq!(video_info.duration_ms, Some(30_000));
    bob_store.download_attachment(transport.clone(), bob.token.clone(), voice_info.id.clone()).unwrap();
    assert_eq!(bob_store.attachment_data(voice_info.id.clone()).unwrap(), Some(voice));
    bob_store.download_attachment(transport.clone(), bob.token.clone(), video_info.id.clone()).unwrap();
    assert_eq!(bob_store.attachment_data(video_info.id.clone()).unwrap(), Some(video));
    assert_eq!(bob_store.transfer_progress(video_info.id.clone()).unwrap(), None);
}

#[test]
fn a_group_photo_is_set_changed_and_removed_through_the_real_server_and_only_ciphertext_is_stored() {
    let admin = Admin::from_env();
    let transport = admin.transport();
    let accounts = [admin.create_account(), admin.create_account()];
    let mut cleanup = Cleanup(&admin, vec![]);
    for a in &accounts {
        cleanup.1.push(Account { id: a.id.clone(), email: a.email.clone(), token: a.token.clone() });
    }
    let [alice, bob] = &accounts;
    let suffix = uuid::Uuid::new_v4().simple().to_string();
    admin.give_profile(alice, "Alice Adams", &format!("al{}", &suffix[..8]));
    admin.give_profile(bob, "Bob Brown", &format!("bo{}", &suffix[..8]));
    let dir = tempfile::tempdir().unwrap();
    let (alice_store, bob_store) = (store(&dir, "a.db", 1), store(&dir, "b.db", 2));
    alice_store.register_device(transport.clone(), alice.token.clone()).unwrap();
    bob_store.register_device(transport.clone(), bob.token.clone()).unwrap();

    let chat = alice_store.create_group("Grade 4 Team".into(), None, vec![bob.id.clone()]).unwrap();
    alice_store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    bob_store.sync(transport.clone(), bob.token.clone()).unwrap();
    bob_store.accept_request(chat.clone()).unwrap();

    let picture = |seed: u8| -> Vec<u8> { (0..30_000u32).map(|i| (i as u8).wrapping_mul(seed).wrapping_add(seed)).collect() };
    let blobs_of = |owner: &str| -> Vec<String> {
        let rows = admin.json(admin.with_service_key(ureq::get(&format!("{}/rest/v1/blobs?select=id,owner", admin.base))), None);
        rows.as_array().unwrap().iter().filter(|r| r["owner"] == owner).map(|r| r["id"].as_str().unwrap().to_owned()).collect()
    };

    let first = picture(3);
    alice_store.set_group_photo(transport.clone(), alice.token.clone(), chat.clone(), first.clone()).unwrap();
    alice_store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    bob_store.sync(transport.clone(), bob.token.clone()).unwrap();
    assert_eq!(bob_store.refresh_group_photos(transport.clone(), bob.token.clone()).unwrap(), vec![chat.clone()]);
    assert_eq!(bob_store.group_photo(chat.clone()).unwrap(), Some(first.clone()), "a member decrypts it");
    let held = blobs_of(&alice.id);
    assert_eq!(held.len(), 1);
    let stored = admin.storage_object("blobs", &held[0]).expect("the encrypted photo");
    assert_ne!(stored, first);
    assert!(!stored.windows(32).any(|w| w == &first[500..532]), "the server's bytes are not the picture");

    // Changed: the old blob is deleted and the new one is again ciphertext.
    let second = picture(7);
    alice_store.set_group_photo(transport.clone(), alice.token.clone(), chat.clone(), second.clone()).unwrap();
    alice_store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    let after = blobs_of(&alice.id);
    assert_eq!(after.len(), 1);
    assert_ne!(after[0], held[0], "the first photo's blob was deleted");
    assert!(!admin.storage_object("blobs", &after[0]).unwrap().windows(32).any(|w| w == &second[500..532]));
    bob_store.sync(transport.clone(), bob.token.clone()).unwrap();
    bob_store.refresh_group_photos(transport.clone(), bob.token.clone()).unwrap();
    assert_eq!(bob_store.group_photo(chat.clone()).unwrap(), Some(second));

    // Switched to an emoji, then nothing is left on the server.
    alice_store.set_group_avatar_emoji(transport.clone(), alice.token.clone(), chat.clone(), Some("🍎".into())).unwrap();
    alice_store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    assert!(blobs_of(&alice.id).is_empty(), "no group photo blob is left on the server");
    bob_store.sync(transport.clone(), bob.token.clone()).unwrap();
    bob_store.refresh_group_photos(transport.clone(), bob.token.clone()).unwrap();
    assert_eq!(bob_store.group_photo(chat.clone()).unwrap(), None);
    assert_eq!(bob_store.list_conversations().unwrap().into_iter().find(|c| c.id == chat).unwrap().group_emoji.as_deref(), Some("🍎"));
}

#[test]
fn reactions_edit_and_delete_for_everyone_through_the_real_server_with_two_accounts() {
    let admin = Admin::from_env();
    let transport = admin.transport();
    let accounts = [admin.create_account(), admin.create_account()];
    let mut cleanup = Cleanup(&admin, vec![]);
    for a in &accounts {
        cleanup.1.push(Account { id: a.id.clone(), email: a.email.clone(), token: a.token.clone() });
    }
    let [alice, bob] = &accounts;
    let suffix = uuid::Uuid::new_v4().simple().to_string();
    admin.give_profile(alice, "Alice Adams", &format!("al{}", &suffix[..8]));
    admin.give_profile(bob, "Bob Brown", &format!("bo{}", &suffix[..8]));
    let dir = tempfile::tempdir().unwrap();
    let (alice_store, bob_store) = (store(&dir, "a.db", 1), store(&dir, "b.db", 2));
    alice_store.register_device(transport.clone(), alice.token.clone()).unwrap();
    bob_store.register_device(transport.clone(), bob.token.clone()).unwrap();

    let chat_a = alice_store.start_dm(bob.id.clone(), "Bob Brown".into()).unwrap();
    let sent = alice_store.queue_text(chat_a.clone(), "the original words".into()).unwrap();
    let attached = alice_store
        .send_attachments(chat_a.clone(), "with a file".into(), vec![lime_core::OutgoingAttachment { bytes: vec![5u8; 4000], name: "f.bin".into(), mime: "application/octet-stream".into(), width: None, height: None, duration_ms: None, thumb: vec![] }], None)
        .unwrap();
    alice_store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    bob_store.sync(transport.clone(), bob.token.clone()).unwrap();
    let chat_b = format!("dm:{}", alice.id);
    bob_store.accept_request(chat_b.clone()).unwrap();
    bob_store.deliver_queued(transport.clone(), bob.token.clone()).unwrap();
    alice_store.sync(transport.clone(), alice.token.clone()).unwrap();
    let of = |store: &lime_core::LimeStore, chat: &str, id: &str| store.list_messages(chat.to_owned()).unwrap().into_iter().find(|m| m.id == id).unwrap();

    // A reaction from Bob reaches Alice through the real server and is not a message.
    bob_store.react(chat_b.clone(), sent.id.clone(), "👍".into(), true).unwrap();
    bob_store.deliver_queued(transport.clone(), bob.token.clone()).unwrap();
    assert_eq!(alice_store.sync(transport.clone(), alice.token.clone()).unwrap().received, 0);
    assert_eq!(of(&alice_store, &chat_a, &sent.id).reactions.iter().map(|r| r.emoji.as_str()).collect::<Vec<_>>(), vec!["👍"]);

    // An edit, then a delete for everyone (of the message with the file).
    alice_store.edit_message(chat_a.clone(), sent.id.clone(), "the **edited** words".into()).unwrap();
    alice_store.delete_message_for_everyone(chat_a.clone(), attached.id.clone()).unwrap();
    alice_store.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    bob_store.sync(transport.clone(), bob.token.clone()).unwrap();
    let edited = of(&bob_store, &chat_b, &sent.id);
    assert_eq!((edited.text.as_str(), edited.edited, edited.reactions.len()), ("the **edited** words", true, 1));
    let gone = of(&bob_store, &chat_b, &attached.id);
    assert!(gone.deleted && gone.text.is_empty() && gone.attachments.is_empty(), "a tombstone on the other phone");
    assert_eq!(bob_store.search_messages("original".into(), None, 5).unwrap().len(), 0);
    // The server holds no reaction, edit or delete in the clear: its tables have no such rows.
    let tables = admin.every_table();
    assert!(tables.iter().all(|(table, _)| !table.contains("reaction")), "no table of reactions on the server");
}

#[test]
fn forward_link_card_and_my_own_chat_through_the_real_server() {
    let admin = Admin::from_env();
    let transport = admin.transport();
    let accounts = [admin.create_account(), admin.create_account(), admin.create_account()];
    let mut cleanup = Cleanup(&admin, vec![]);
    for a in &accounts {
        cleanup.1.push(Account { id: a.id.clone(), email: a.email.clone(), token: a.token.clone() });
    }
    let [alice, bob, carol] = &accounts;
    let suffix = uuid::Uuid::new_v4().simple().to_string();
    admin.give_profile(alice, "Alice Adams", &format!("al{}", &suffix[..8]));
    admin.give_profile(bob, "Bob Brown", &format!("bo{}", &suffix[..8]));
    admin.give_profile(carol, "Carol Cruz", &format!("ca{}", &suffix[..8]));
    let dir = tempfile::tempdir().unwrap();
    let (a, b, c) = (store(&dir, "a.db", 1), store(&dir, "b.db", 2), store(&dir, "c.db", 3));
    a.register_device(transport.clone(), alice.token.clone()).unwrap();
    b.register_device(transport.clone(), bob.token.clone()).unwrap();
    c.register_device(transport.clone(), carol.token.clone()).unwrap();
    let to_bob = a.start_dm(bob.id.clone(), "Bob Brown".into()).unwrap();
    let to_carol = a.start_dm(carol.id.clone(), "Carol Cruz".into()).unwrap();

    // A photo to Bob, then forwarded to Carol: the same file on the server, shared (no second upload).
    let file = lime_core::OutgoingAttachment { bytes: (0..5000u32).map(|i| (i % 253) as u8).collect(), name: "p.jpg".into(), mime: "image/jpeg".into(), width: Some(10), height: Some(10), duration_ms: None, thumb: vec![] };
    let sent = a.send_attachments(to_bob.clone(), "look".into(), vec![file.clone()], None).unwrap();
    a.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    let attachment_rows = || admin.every_table().into_iter().find(|(t, _)| t == "attachments").map(|(_, rows)| serde_json::from_str::<serde_json::Value>(&rows).map(|v| v.as_array().map_or(0, Vec::len)).unwrap_or(0));
    let before = attachment_rows();
    a.forward_messages(vec![sent.id.clone()], vec![to_carol.clone()]).unwrap();
    a.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    assert_eq!(attachment_rows(), before, "no second attachment row");
    c.sync(transport.clone(), carol.token.clone()).unwrap();
    let got = c.list_messages(format!("dm:{}", alice.id)).unwrap().pop().unwrap();
    assert!(got.forwarded);
    c.download_attachment(transport.clone(), carol.token.clone(), got.attachments[0].id.clone()).unwrap();
    assert_eq!(c.attachment_data(got.attachments[0].id.clone()).unwrap(), Some(file.bytes.clone()));

    // A link card: the picture is an encrypted attachment that Bob downloads; he never contacts the site.
    let card = lime_core::OutgoingPreview { url: "https://example.org/x".into(), title: "A page".into(), site: "example.org".into(), image: vec![9u8; 6000], image_width: Some(60), image_height: Some(30) };
    a.queue_text_with_preview(to_bob.clone(), "https://example.org/x".into(), None, card).unwrap();
    a.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    b.sync(transport.clone(), bob.token.clone()).unwrap();
    let message = b.list_messages(format!("dm:{}", alice.id)).unwrap().into_iter().find(|m| m.link_preview.is_some()).unwrap();
    let picture = message.link_preview.unwrap().image.unwrap();
    b.download_attachment(transport.clone(), bob.token.clone(), picture.id.clone()).unwrap();
    assert_eq!(b.attachment_data(picture.id).unwrap(), Some(vec![9u8; 6000]));

    // My own chat: written and "sent" with nothing going to the server.
    let own = a.ensure_self_chat("Alice Adams".into()).unwrap();
    let mine = a.queue_text(own.clone(), "remember the field trip forms".into()).unwrap();
    a.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    assert_eq!(a.list_messages(own).unwrap().iter().find(|m| m.id == mine.id).unwrap().local_state, "sent");
    assert_eq!(b.sync(transport.clone(), bob.token.clone()).unwrap().received, 0);
}

#[test]
fn a_forward_of_files_through_the_real_server_is_sent_on_the_senders_phone_and_arrives_once() {
    let admin = Admin::from_env();
    let transport = admin.transport();
    let accounts = [admin.create_account(), admin.create_account(), admin.create_account()];
    let mut cleanup = Cleanup(&admin, vec![]);
    for a in &accounts {
        cleanup.1.push(Account { id: a.id.clone(), email: a.email.clone(), token: a.token.clone() });
    }
    let suffix = uuid::Uuid::new_v4().simple().to_string();
    for (i, (account, name)) in accounts.iter().zip(["Ann Adams", "Bo Brown", "Cy Clark"]).enumerate() {
        admin.give_profile(account, name, &format!("f{i}{}", &suffix[..8]));
    }
    let dir = tempfile::tempdir().unwrap();
    let stores: Vec<_> = (0..3).map(|i| store(&dir, &format!("p{i}.db"), 20 + i as u8)).collect();
    for (s, a) in stores.iter().zip(&accounts) {
        s.register_device(transport.clone(), a.token.clone()).unwrap();
    }
    let sync = |i: usize| stores[i].sync(transport.clone(), accounts[i].token.clone()).unwrap();
    let deliver = |i: usize| stores[i].deliver_queued(transport.clone(), accounts[i].token.clone());

    // Ann, Bo and Cy are in a group; Ann writes to Bo with a PDF and an album, and Bo downloads only the PDF.
    let group = stores[0].create_group("Forward team".into(), None, vec![accounts[1].id.clone(), accounts[2].id.clone()]).unwrap();
    deliver(0).unwrap();
    sync(1);
    sync(2);
    let to_bo = stores[0].start_dm(accounts[1].id.clone(), "Bo Brown".into()).unwrap();
    let pdf: Vec<u8> = (0..1_300_000u32).map(|i| (i.wrapping_mul(2654435761) >> 24) as u8).collect();
    let pic = |seed: u8| lime_core::OutgoingAttachment { bytes: vec![seed; 3000], name: format!("{seed}.jpg"), mime: "image/jpeg".into(), width: Some(10), height: Some(10), duration_ms: None, thumb: vec![] };
    let file = stores[0].send_attachments(to_bo.clone(), "".into(), vec![lime_core::OutgoingAttachment { bytes: pdf.clone(), name: "plan.pdf".into(), mime: "application/pdf".into(), width: None, height: None, duration_ms: None, thumb: vec![] }], None).unwrap();
    let album = stores[0].send_attachments(to_bo.clone(), "trip".into(), vec![pic(1), pic(2), pic(3)], None).unwrap();
    deliver(0).unwrap();
    sync(1);
    let from_ann = format!("dm:{}", accounts[0].id);
    stores[1].accept_request(from_ann.clone()).unwrap();
    let received: Vec<_> = stores[1].list_messages(from_ann.clone()).unwrap();
    let (got_file, got_album) = (received.iter().find(|m| m.id == file.id).unwrap(), received.iter().find(|m| m.id == album.id).unwrap());
    stores[1].download_attachment(transport.clone(), accounts[1].token.clone(), got_file.attachments[0].id.clone()).unwrap();

    // Bo forwards both to Cy (a chat) and to the group in one go.
    let to_cy = stores[1].start_dm(accounts[2].id.clone(), "Cy Clark".into()).unwrap();
    let forwarded = stores[1].forward_messages(vec![got_file.id.clone(), got_album.id.clone()], vec![to_cy.clone(), group.clone()]).unwrap();
    assert_eq!(forwarded.len(), 4);
    deliver(1).unwrap();
    let states = |ids: &[String], chat: &str| -> Vec<String> {
        stores[1].list_messages(chat.to_owned()).unwrap().into_iter().filter(|m| ids.contains(&m.id)).map(|m| m.local_state).collect()
    };
    let ids: Vec<String> = forwarded.iter().map(|m| m.id.clone()).collect();
    assert_eq!(states(&ids, &to_cy), vec!["sent", "sent"], "Bo's phone says Sent for the chat forwards");
    assert_eq!(states(&ids, &group), vec!["sent", "sent"], "and for the group forwards");

    // Cy gets each once, labelled, and can open the file; a second delivery or sync adds nothing.
    sync(2);
    let in_chat: Vec<_> = stores[2].list_messages(format!("dm:{}", accounts[1].id)).unwrap();
    assert_eq!(in_chat.iter().filter(|m| m.forwarded).count(), 2);
    let in_group: Vec<_> = stores[2].list_messages(group.clone()).unwrap();
    assert_eq!(in_group.iter().filter(|m| m.forwarded).count(), 2);
    let one = in_chat.iter().find(|m| m.forwarded && m.attachments.len() == 1).unwrap();
    stores[2].download_attachment(transport.clone(), accounts[2].token.clone(), one.attachments[0].id.clone()).unwrap();
    assert_eq!(stores[2].attachment_data(one.attachments[0].id.clone()).unwrap(), Some(pdf.clone()));
    deliver(1).unwrap();
    sync(2);
    assert_eq!(stores[2].list_messages(format!("dm:{}", accounts[1].id)).unwrap().iter().filter(|m| m.forwarded).count(), 2, "nothing twice");

    assert!(stores[1].attachment_available_until(transport.clone(), accounts[1].token.clone(), got_file.attachments[0].id.clone()).unwrap().is_some(), "still on the server, and until when");
    // The original file has been swept from the server (everyone fetched it and an hour passed): forwarding it again still works,
    // from the sender's own decrypted copy, and shows Sent.
    let rows = admin.json(admin.with_service_key(ureq::get(&format!("{}/rest/v1/attachments?select=id,owner", admin.base))), None);
    for row in rows.as_array().unwrap().iter().filter(|r| r["owner"] == accounts[0].id.as_str()) {
        let id = row["id"].as_str().unwrap();
        admin.with_service_key(ureq::request("PATCH", &format!("{}/rest/v1/attachments?id=eq.{id}", admin.base))).send_json(json!({ "expires_at": "2000-01-01T00:00:00Z" })).unwrap();
    }
    let secret = admin.json(admin.with_service_key(ureq::get(&format!("{}/rest/v1/sweep_target?select=secret", admin.base))), None)[0]["secret"].as_str().expect("the sweep is scheduled").to_owned();
    ureq::post(&format!("{}/functions/v1/blob-sweep", admin.base)).set("apikey", &admin.anon_key).set("x-sweep-secret", &secret).send_json(json!({})).unwrap();
    let file_id = got_file.attachments[0].id.clone();
    assert_eq!(stores[1].attachment_available_until(transport.clone(), accounts[1].token.clone(), file_id).unwrap(), None, "the server no longer has it");
    let again = stores[1].forward_messages(vec![got_file.id.clone()], vec![to_cy.clone()]).unwrap();
    deliver(1).unwrap();
    assert_eq!(states(&[again[0].id.clone()], &to_cy), vec!["sent"], "a forward of a swept file is re-uploaded from Bo's copy and sent");
    sync(2);
    let last = stores[2].list_messages(format!("dm:{}", accounts[1].id)).unwrap().into_iter().rfind(|m| m.forwarded).unwrap();
    stores[2].download_attachment(transport.clone(), accounts[2].token.clone(), last.attachments[0].id.clone()).unwrap();
}

#[test]
fn a_status_reaches_an_accepted_contact_through_the_real_server_and_the_server_holds_no_status() {
    let admin = Admin::from_env();
    let transport = admin.transport();
    let accounts = [admin.create_account(), admin.create_account()];
    let mut cleanup = Cleanup(&admin, vec![]);
    for a in &accounts {
        cleanup.1.push(Account { id: a.id.clone(), email: a.email.clone(), token: a.token.clone() });
    }
    let [alice, bob] = &accounts;
    let suffix = uuid::Uuid::new_v4().simple().to_string();
    admin.give_profile(alice, "Alice Adams", &format!("al{}", &suffix[..8]));
    admin.give_profile(bob, "Bob Brown", &format!("bo{}", &suffix[..8]));
    let dir = tempfile::tempdir().unwrap();
    let (a, b) = (store(&dir, "a.db", 1), store(&dir, "b.db", 2));
    a.register_device(transport.clone(), alice.token.clone()).unwrap();
    b.register_device(transport.clone(), bob.token.clone()).unwrap();
    let chat = a.start_dm(bob.id.clone(), "Bob Brown".into()).unwrap();
    a.queue_text(chat, "hello".into()).unwrap();
    a.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    b.sync(transport.clone(), bob.token.clone()).unwrap();
    b.accept_request(format!("dm:{}", alice.id)).unwrap();
    b.deliver_queued(transport.clone(), bob.token.clone()).unwrap();
    a.sync(transport.clone(), alice.token.clone()).unwrap();

    a.set_my_status(lime_core::StatusInfo { state: "dnd".into(), until: None, then_state: None, then_until: None }).unwrap();
    a.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    assert_eq!(b.sync(transport.clone(), bob.token.clone()).unwrap().received, 0, "a status is not a message");
    let seen = b.contact_statuses(now_ms()).unwrap();
    assert_eq!((seen[0].user_id.as_str(), seen[0].state.as_str()), (alice.id.as_str(), "dnd"));
    for (name, rows) in admin.every_table() {
        assert!(!name.contains("status") || !rows.contains("dnd"), "no status in table {name}");
    }
}

#[test]
fn an_owner_deletes_a_group_for_everyone_and_a_member_clears_messages_and_stays_through_the_real_server() {
    let admin = Admin::from_env();
    let transport = admin.transport();
    let accounts = [admin.create_account(), admin.create_account(), admin.create_account()];
    let mut cleanup = Cleanup(&admin, vec![]);
    for a in &accounts {
        cleanup.1.push(Account { id: a.id.clone(), email: a.email.clone(), token: a.token.clone() });
    }
    let suffix = uuid::Uuid::new_v4().simple().to_string();
    for (i, (account, name)) in accounts.iter().zip(["Ann Adams", "Bo Brown", "Cy Clark"]).enumerate() {
        admin.give_profile(account, name, &format!("d{i}{}", &suffix[..8]));
    }
    let dir = tempfile::tempdir().unwrap();
    let stores: Vec<_> = (0..3).map(|i| store(&dir, &format!("d{i}.db"), 30 + i as u8)).collect();
    for (s, a) in stores.iter().zip(&accounts) {
        s.register_device(transport.clone(), a.token.clone()).unwrap();
    }
    let sync = |i: usize| stores[i].sync(transport.clone(), accounts[i].token.clone()).unwrap();
    let deliver = |i: usize| stores[i].deliver_queued(transport.clone(), accounts[i].token.clone()).unwrap();
    let chat = stores[0].create_group("Doomed".into(), None, vec![accounts[1].id.clone(), accounts[2].id.clone()]).unwrap();
    deliver(0);
    sync(1);
    sync(2);
    stores[0].queue_text(chat.clone(), "before".into()).unwrap();
    deliver(0);
    sync(1);
    sync(2);

    // Cy clears the messages and is still in the group; Bo, not the owner, cannot delete it.
    stores[2].clear_messages(chat.clone()).unwrap();
    assert!(stores[2].list_messages(chat.clone()).unwrap().iter().all(|m| m.local_state == "system"));
    assert!(stores[1].delete_group(chat.clone()).is_err());
    let summary = |i: usize| stores[i].list_conversations().unwrap().into_iter().find(|c| c.id == chat).unwrap();
    assert_eq!(summary(2).group_ended, None);

    // Ann deletes it: Bo and Cy see it end, and a message sent to it afterwards is refused.
    stores[0].delete_group(chat.clone()).unwrap();
    deliver(0);
    sync(1);
    sync(2);
    for i in 0..3 {
        assert_eq!(summary(i).group_ended.as_deref(), Some("deleted"), "phone {i}");
    }
    assert!(stores[1].list_messages(chat.clone()).unwrap().iter().any(|m| m.text.contains("deleted this group")));
    assert!(stores[1].queue_text(chat.clone(), "anyone?".into()).is_err());
    stores[1].delete_chat(chat.clone()).unwrap();
    assert!(stores[1].list_conversations().unwrap().iter().all(|c| c.id != chat), "Bo removes it from his own list");
}

#[test]
fn call_signalling_goes_through_the_real_mailbox_as_sealed_control_ops_and_is_not_a_message() {
    let admin = Admin::from_env();
    let transport = admin.transport();
    let accounts = [admin.create_account(), admin.create_account()];
    let mut cleanup = Cleanup(&admin, vec![]);
    for a in &accounts {
        cleanup.1.push(Account { id: a.id.clone(), email: a.email.clone(), token: a.token.clone() });
    }
    let [alice, bob] = &accounts;
    let suffix = uuid::Uuid::new_v4().simple().to_string();
    admin.give_profile(alice, "Alice Adams", &format!("al{}", &suffix[..8]));
    admin.give_profile(bob, "Bob Brown", &format!("bo{}", &suffix[..8]));
    let dir = tempfile::tempdir().unwrap();
    let (a, b) = (store(&dir, "a.db", 1), store(&dir, "b.db", 2));
    a.register_device(transport.clone(), alice.token.clone()).unwrap();
    b.register_device(transport.clone(), bob.token.clone()).unwrap();
    let chat = a.start_dm(bob.id.clone(), "Bob Brown".into()).unwrap();
    a.queue_text(chat, "hello".into()).unwrap();
    a.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    b.sync(transport.clone(), bob.token.clone()).unwrap();
    b.accept_request(format!("dm:{}", alice.id)).unwrap();
    b.deliver_queued(transport.clone(), bob.token.clone()).unwrap();
    a.sync(transport.clone(), alice.token.clone()).unwrap();

    let sdp = |fp: &str| format!("v=0\r\na=fingerprint:sha-256 {fp}\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n");
    let send = |from: &LimeStore, token: &str, to: &str, op: &str, payload: Value| from.send_call_signal(transport.clone(), token.to_owned(), to.to_owned(), op.to_owned(), payload.to_string()).unwrap();
    send(&a, &alice.token, &bob.id, "call.offer", json!({ "call_id": "c1", "video": true, "sdp": sdp("AA:BB"), "fingerprint": "AA:BB" }));
    assert_eq!(b.sync(transport.clone(), bob.token.clone()).unwrap().received, 0, "not a message");
    let events = b.take_call_events().unwrap();
    assert_eq!((events[0].op.as_str(), events[0].call_id.as_str(), events[0].peer.as_str()), ("call.offer", "c1", alice.id.as_str()));
    send(&b, &bob.token, &alice.id, "call.answer", json!({ "call_id": "c1", "sdp": sdp("CC:DD"), "fingerprint": "CC:DD" }));
    send(&b, &bob.token, &alice.id, "call.ice", json!({ "call_id": "c1", "candidate": "candidate:1 1 udp 2 1.2.3.4 5 typ host", "sdpMid": "0", "sdpMLineIndex": 0 }));
    a.sync(transport.clone(), alice.token.clone()).unwrap();
    let back: Vec<String> = a.take_call_events().unwrap().into_iter().map(|e| e.op).collect();
    assert_eq!(back, vec!["call.answer", "call.ice"]);
    // The relay's credentials: some while the secret is set on that server, none (not an error) before.
    let turn = a.fetch_turn_servers(transport.clone(), alice.token.clone()).unwrap();
    eprintln!("TURN credentials from the server: {}", if turn.is_some() { "200 (configured)" } else { "503 not_configured" });
    if let Some(t) = &turn {
        assert!(t.urls.iter().any(|u| u.starts_with("turn:")) && !t.username.is_empty() && !t.credential.is_empty());
    }
    send(&a, &alice.token, &bob.id, "call.end", json!({ "call_id": "c1" }));
    b.sync(transport.clone(), bob.token.clone()).unwrap();
    assert_eq!(b.take_call_events().unwrap()[0].op, "call.end");
}

/// LIME-111-fix2, Phase 1: what a call's signalling flood does. A fires `LIME_FLOOD` (default 30) candidate ops at B on parallel
/// threads while B fetches in a loop. Prints the time to B's first fetched op, the total time and any refused send. Always passes
/// unless a send is refused, so it can run before and after a fix; the numbers go to stderr (`--nocapture`).
#[test]
fn call_signalling_flood_does_not_starve_the_fetch() {
    let admin = Admin::from_env();
    let transport = admin.transport();
    let accounts = [admin.create_account(), admin.create_account()];
    let mut cleanup = Cleanup(&admin, vec![]);
    for a in &accounts {
        cleanup.1.push(Account { id: a.id.clone(), email: a.email.clone(), token: a.token.clone() });
    }
    let [alice, bob] = &accounts;
    let suffix = uuid::Uuid::new_v4().simple().to_string();
    admin.give_profile(alice, "Alice Adams", &format!("al{}", &suffix[..8]));
    admin.give_profile(bob, "Bob Brown", &format!("bo{}", &suffix[..8]));
    let dir = tempfile::tempdir().unwrap();
    let (a, b) = (store(&dir, "a.db", 1), store(&dir, "b.db", 2));
    a.register_device(transport.clone(), alice.token.clone()).unwrap();
    b.register_device(transport.clone(), bob.token.clone()).unwrap();
    let chat = a.start_dm(bob.id.clone(), "Bob Brown".into()).unwrap();
    a.queue_text(chat, "hello".into()).unwrap();
    a.deliver_queued(transport.clone(), alice.token.clone()).unwrap();
    b.sync(transport.clone(), bob.token.clone()).unwrap();
    b.accept_request(format!("dm:{}", alice.id)).unwrap();
    b.deliver_queued(transport.clone(), bob.token.clone()).unwrap();
    a.sync(transport.clone(), alice.token.clone()).unwrap();

    let flood: usize = std::env::var("LIME_FLOOD").ok().and_then(|v| v.parse().ok()).unwrap_or(30);
    let sdp = "v=0\r\na=fingerprint:sha-256 AA:BB\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n";
    let started = std::time::Instant::now();
    let offer_at = std::sync::Mutex::new(None::<std::time::Duration>);
    let first_fetched = std::sync::Mutex::new(None::<std::time::Duration>);
    let refused = std::sync::atomic::AtomicUsize::new(0);
    let send_ms = std::sync::Mutex::new(Vec::<u128>::new());
    let done = std::sync::atomic::AtomicBool::new(false);
    std::thread::scope(|scope| {
        scope.spawn(|| {
            // The offer goes first, then the candidates follow on parallel threads, as the app does.
            let t = std::time::Instant::now();
            a.send_call_signal(transport.clone(), alice.token.clone(), bob.id.clone(), "call.offer".into(), json!({ "call_id": "f1", "video": false, "sdp": sdp, "fingerprint": "AA:BB" }).to_string()).unwrap();
            *offer_at.lock().unwrap() = Some(started.elapsed());
            send_ms.lock().unwrap().push(t.elapsed().as_millis());
            std::thread::scope(|inner| {
                for i in 0..flood {
                    let (a, transport, token, peer) = (&a, transport.clone(), alice.token.clone(), bob.id.clone());
                    let (refused, send_ms) = (&refused, &send_ms);
                    inner.spawn(move || {
                        let t = std::time::Instant::now();
                        let payload = json!({ "call_id": "f1", "candidate": format!("candidate:{i} 1 udp 2 10.0.0.{i} 5 typ host"), "sdpMid": "0", "sdpMLineIndex": 0 });
                        if a.send_call_signal(transport, token, peer, "call.ice".into(), payload.to_string()).is_err() {
                            refused.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                        }
                        send_ms.lock().unwrap().push(t.elapsed().as_millis());
                    });
                }
            });
            done.store(true, std::sync::atomic::Ordering::SeqCst);
        });
        scope.spawn(|| {
            // B fetches in a loop, as the app's one-second poll does.
            while !done.load(std::sync::atomic::Ordering::SeqCst) || first_fetched.lock().unwrap().is_none() {
                let _ = b.fetch_call_ops(transport.clone(), bob.token.clone());
                if first_fetched.lock().unwrap().is_none() && !b.take_call_events().unwrap().is_empty() {
                    *first_fetched.lock().unwrap() = Some(started.elapsed());
                }
                if started.elapsed().as_secs() > 240 {
                    break;
                }
                std::thread::sleep(std::time::Duration::from_millis(1000));
            }
        });
    });
    let total = started.elapsed();
    let mut ms = send_ms.lock().unwrap().clone();
    ms.sort_unstable();
    eprintln!(
        "FLOOD {flood}: offer sent after {:?}; B's first fetched op after {:?}; all sends done after {:?}; refused {}; per-send ms median {} max {}",
        offer_at.lock().unwrap().unwrap(),
        first_fetched.lock().unwrap().unwrap_or_default(),
        total,
        refused.load(std::sync::atomic::Ordering::SeqCst),
        ms[ms.len() / 2],
        ms.last().unwrap()
    );
    assert_eq!(refused.load(std::sync::atomic::Ordering::SeqCst), 0, "a send was refused (rate limit?)");
}
