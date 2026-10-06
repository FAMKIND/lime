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

    fn delete_account(&self, account: &Account) {
        let _ = self
            .with_service_key(ureq::delete(&format!(
                "{}/auth/v1/admin/users/{}",
                self.base, account.id
            )))
            .call();
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
