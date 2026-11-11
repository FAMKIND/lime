//! LIME-407: a message with a link preview stays a **sealed** send (`docs/api-v2.md` §3-4). The card (the address, the title, the site) and its picture travel only inside the
//! encrypted inner op; the picture is an encrypted file like a photo; the server still sees only `{to_device, access, ciphertext, size}` and no token. A child of `client_tests`
//! (one registration line there), so it uses that file's fake server and parties.

use super::{befriend, deliver, party, sync};
use crate::testing::FakeServer;

fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    !needle.is_empty() && haystack.windows(needle.len()).any(|w| w == needle)
}

#[test]
fn a_message_with_a_preview_goes_out_sealed_and_the_server_learns_neither_the_address_nor_the_card_nor_the_picture() {
    let server = FakeServer::new();
    let (alice, transport) = party(&server, "alice", 1);
    let (bob, _) = party(&server, "bob", 2);
    befriend(&alice, &bob, &transport);
    let image: Vec<u8> = (0..30_000u32).map(|i| (i * 11 % 251) as u8).collect();
    let url = "https://example.org/private-lesson-plan-9f3a";
    let title = "A very particular lesson title";
    let site = "example.org";
    let chat = format!("dm:{}", bob.user);
    // A plain message first: the shape of an ordinary sealed send is the baseline a card must not change.
    alice.store.queue_text(chat.clone(), "plain, for the shape".into()).unwrap();
    deliver(&alice, &transport);
    let shape = |body: &serde_json::Value| -> (Vec<String>, Vec<Vec<String>>) {
        let mut outer: Vec<String> = body.as_object().expect("an object").keys().cloned().collect();
        outer.sort();
        let recipients = body["recipients"].as_array().expect("recipients").iter().map(|r| {
            let mut keys: Vec<String> = r.as_object().expect("a recipient").keys().cloned().collect();
            keys.sort();
            keys
        });
        (outer, recipients.collect())
    };
    let (plain_shape, identified_before, sent_before) = {
        let state = server.state.lock().unwrap();
        (shape(state.sent.last().expect("the plain send")), state.sends_with_token, state.sent.len())
    };
    let item = alice
        .store
        .queue_text_with_preview(chat.clone(), format!("see {url}"), None, crate::OutgoingPreview { url: url.into(), title: title.into(), site: site.into(), image: image.clone(), image_width: Some(600), image_height: Some(315) })
        .unwrap();
    assert!(item.link_preview.is_some());
    deliver(&alice, &transport);

    let state = server.state.lock().unwrap();
    // (ii) The send path is the sealed one: no token, no identified access, and the outer fields are exactly those of a message with no card. (The request is the fan-out batch of
    // `docs/api-v2.md` section 3: `{ ciphertext, recipients: [{ to_device, access }], expect }`; there is no per-message `size` field in it.)
    assert_eq!(state.sends_with_token, identified_before, "no identified (token-carrying) send was added by a card");
    let new_sends = &state.sent[sent_before..];
    assert!(!new_sends.is_empty(), "the message was sent");
    for body in new_sends {
        assert_eq!(shape(body), plain_shape, "a card adds no field to the outer envelope and none to a recipient entry");
        for r in body["recipients"].as_array().unwrap() {
            assert_ne!(r["access"]["identified"].as_bool(), Some(true), "sealed, not identified");
            assert!(r["access"].get("signed").is_some() || r["access"].get("sealed").is_some(), "the access is a delivery-key proof");
        }
        let ciphertext = vodozemac::base64_decode(body["ciphertext"].as_str().unwrap()).unwrap();
        // (i) Nothing of the card is readable in the envelope, as bytes or as the base64 text that carries them.
        let text = body.to_string();
        for secret in [url.as_bytes(), title.as_bytes(), b"private-lesson-plan-9f3a".as_slice(), &image[2_000..2_064]] {
            assert!(!contains(&ciphertext, secret), "the ciphertext shows part of the card");
            assert!(!contains(text.as_bytes(), secret), "the envelope shows part of the card");
        }
    }
    // The picture is an encrypted attachment (stored under the blob bucket like a photo), never plain.
    let uploaded: Vec<(&String, &Vec<u8>)> = state.objects.iter().filter(|(k, _)| k.starts_with("blobs/")).collect();
    assert!(!uploaded.is_empty(), "the picture was uploaded as an encrypted blob");
    for (key, bytes) in uploaded {
        assert!(!contains(bytes, &image[2_000..2_064]), "{key} holds the picture in the clear");
        assert!(!contains(bytes, url.as_bytes()) && !contains(bytes, title.as_bytes()), "{key} holds the card in the clear");
    }
    // No request of the whole send names the address (the fake server records the function of every request).
    assert!(!state.functions.iter().any(|f| f.contains("preview") || f.contains("unfurl") || f.contains("link")), "no link-preview function was called: {:?}", state.functions);
    drop(state);

    // The other phone reads the card from the message alone.
    sync(&bob, &transport);
    let got = bob.store.list_messages(format!("dm:{}", alice.user)).unwrap().pop().unwrap();
    let card = got.link_preview.expect("a card");
    assert_eq!((card.url.as_str(), card.title.as_str(), card.site.as_str()), (url, title, site));
}
