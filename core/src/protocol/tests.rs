use serde_json::json;
use vodozemac::Ed25519SecretKey;

use super::*;

fn signed_op(signer: &Ed25519SecretKey) -> Op {
    let mut op = Op {
        op_id: "0192f8a4-7c1e-7b3a-9d52-3f6a1c0e8b21".into(),
        op_type: "message.send".into(),
        conversation_id: dm_conversation_id("u-b", "u-a"),
        hlc: Hlc {
            wall: 1_800_000_000_000,
            counter: 2,
        }
        .render(),
        parents: vec!["parent-1".into()],
        payload: json!({ "text": "hello" }),
        sig: String::new(),
    };
    op.sig = signer.sign(&op.signing_bytes()).to_base64();
    op
}

#[test]
fn canonical_bytes_sort_keys_and_do_not_depend_on_input_order() {
    let a = canonical_bytes(&json!({ "b": 1, "a": { "y": [1, 2], "x": "t" } }));
    let b = canonical_bytes(&json!({ "a": { "x": "t", "y": [1, 2] }, "b": 1 }));
    assert_eq!(a, b);
    assert_eq!(
        String::from_utf8(a).unwrap(),
        r#"{"a":{"x":"t","y":[1,2]},"b":1}"#
    );
}

#[test]
fn a_signed_op_verifies_and_a_tampered_one_is_rejected() {
    let key = Ed25519SecretKey::new();
    let public = key.public_key().to_base64();
    let op = signed_op(&key);
    assert!(op.verify(&public));

    for tamper in [
        |o: &mut Op| o.payload = json!({ "text": "hullo" }),
        |o: &mut Op| o.conversation_id = "dm:x:y".into(),
        |o: &mut Op| o.hlc = "0000000000001.0000".into(),
        |o: &mut Op| o.parents.clear(),
        |o: &mut Op| o.op_id = "other".into(),
        |o: &mut Op| o.op_type = "message.edit".into(),
    ] {
        let mut changed = op.clone();
        tamper(&mut changed);
        assert!(!changed.verify(&public), "a tampered op must not verify");
    }
    // Another device's key does not verify it either.
    assert!(!op.verify(&Ed25519SecretKey::new().public_key().to_base64()));
    // Garbage keys and signatures are refused, not panicked on.
    assert!(!op.verify("not a key"));
    let mut bad_sig = op.clone();
    bad_sig.sig = "AAAA".into();
    assert!(!bad_sig.verify(&public));
}

#[test]
fn the_signature_covers_the_canonical_bytes_not_the_json_text() {
    let key = Ed25519SecretKey::new();
    let op = signed_op(&key);
    // Round-trip through JSON text (which may reorder or reformat) and it still verifies.
    let text = serde_json::to_string_pretty(&op.to_json()).unwrap();
    let back = Op::from_json(&serde_json::from_str(&text).unwrap()).unwrap();
    assert_eq!(back, op);
    assert!(back.verify(&key.public_key().to_base64()));
}

#[test]
fn a_device_certificate_verifies_only_for_its_master_key() {
    let master = Ed25519SecretKey::new();
    let identity = vodozemac::Curve25519PublicKey::from_bytes([7; 32]).to_base64();
    let signing = Ed25519SecretKey::new().public_key().to_base64();
    let text = device_signing_text("device-1", &identity, &signing);
    let cert = SenderCert {
        device_id: "device-1".into(),
        identity_key: identity.clone(),
        signing_key: signing.clone(),
        master_key: master.public_key().to_base64(),
        master_signature: master.sign(text.as_bytes()).to_base64(),
    };
    assert!(cert.verify());
    assert_eq!(SenderCert::from_json(&cert.to_json()), Some(cert.clone()));

    let mut other_device = cert.clone();
    other_device.device_id = "device-2".into();
    assert!(!other_device.verify());
    let mut other_master = cert.clone();
    other_master.master_key = Ed25519SecretKey::new().public_key().to_base64();
    assert!(!other_master.verify());
}

#[test]
fn the_sealed_inner_round_trips_and_rejects_garbage() {
    let key = Ed25519SecretKey::new();
    let inner = SealedInner {
        sender_user: "u-a".into(),
        sender_device: "device-1".into(),
        sender_cert: SenderCert {
            device_id: "device-1".into(),
            identity_key: "i".into(),
            signing_key: "s".into(),
            master_key: "m".into(),
            master_signature: "g".into(),
        },
        op: signed_op(&key),
    };
    assert_eq!(SealedInner::from_bytes(&inner.to_bytes()), Some(inner));
    assert_eq!(SealedInner::from_bytes(b"not json"), None);
    assert_eq!(SealedInner::from_bytes(br#"{"sender_user":"u"}"#), None);
}

#[test]
fn both_people_compute_the_same_dm_conversation_id() {
    assert_eq!(
        dm_conversation_id("u-a", "u-b"),
        dm_conversation_id("u-b", "u-a")
    );
    assert_ne!(
        dm_conversation_id("u-a", "u-b"),
        dm_conversation_id("u-a", "u-c")
    );
}

#[test]
fn the_hlc_increases_even_when_the_clock_stalls_or_goes_back() {
    let start = Hlc::default().tick(1_000);
    assert_eq!(
        start,
        Hlc {
            wall: 1_000,
            counter: 0
        }
    );
    let same_ms = start.tick(1_000);
    assert!(same_ms > start && same_ms.counter == 1);
    let clock_went_back = same_ms.tick(900);
    assert!(clock_went_back > same_ms);
    let later = clock_went_back.tick(2_000);
    assert_eq!(
        later,
        Hlc {
            wall: 2_000,
            counter: 0
        }
    );

    // Observing a remote clock ahead of ours moves past it.
    let merged = later.observe(
        Hlc {
            wall: 5_000,
            counter: 3,
        },
        2_100,
    );
    assert!(
        merged
            > Hlc {
                wall: 5_000,
                counter: 3
            }
    );
    // And the text form sorts the same way as the value.
    let a = Hlc {
        wall: 999,
        counter: 9,
    };
    let b = Hlc {
        wall: 1_000,
        counter: 0,
    };
    assert!(a.render() < b.render());
    assert_eq!(Hlc::parse(&b.render()), Some(b));
    assert_eq!(Hlc::parse("garbage"), None);
}
