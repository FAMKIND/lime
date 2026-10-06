//! The encryption self-test: real vodozemac Olm and Megolm round trips, all in memory.
//! Nothing here is persisted, logged, or returned except pass/fail and a fixed description.

use vodozemac::megolm::{GroupSession, InboundGroupSession, SessionConfig as MegolmConfig};
use vodozemac::olm::{Account, OlmMessage, SessionConfig as OlmConfig};

/// Two accounts, an Olm session, one message each way. Returns the number of one-way
/// messages that decrypted correctly (2 on success).
pub(crate) fn olm_round_trip() -> Result<(), String> {
    let alice = Account::new();
    let mut bob = Account::new();

    bob.generate_one_time_keys(1);
    let bob_one_time_key = *bob
        .one_time_keys()
        .values()
        .next()
        .ok_or("no one-time key")?;
    bob.mark_keys_as_published();

    let mut alice_session = alice
        .create_outbound_session(
            OlmConfig::version_1(),
            bob.curve25519_key(),
            bob_one_time_key,
        )
        .map_err(|e| format!("outbound session: {e}"))?;

    // Alice to Bob (the first message is a pre-key message that creates Bob's session).
    let hello = b"hello from alice";
    let first = alice_session
        .encrypt(hello)
        .map_err(|e| format!("Olm encrypt: {e}"))?;
    let OlmMessage::PreKey(pre_key) = first else {
        return Err("first Olm message was not a pre-key message".into());
    };
    let created = bob
        .create_inbound_session(OlmConfig::version_1(), alice.curve25519_key(), &pre_key)
        .map_err(|e| format!("inbound session: {e}"))?;
    if created.plaintext != hello {
        return Err("Olm: Bob read the wrong text".into());
    }
    let mut bob_session = created.session;

    // Bob to Alice.
    let reply = b"hello from bob";
    let reply_message = bob_session
        .encrypt(reply)
        .map_err(|e| format!("Olm encrypt: {e}"))?;
    let decrypted = alice_session
        .decrypt(&reply_message)
        .map_err(|e| format!("Olm decrypt: {e}"))?;
    if decrypted != reply {
        return Err("Olm: Alice read the wrong text".into());
    }
    Ok(())
}

/// A Megolm outbound group session, its key shared into an inbound session, one message.
pub(crate) fn megolm_round_trip() -> Result<(), String> {
    let mut outbound = GroupSession::new(MegolmConfig::version_1());
    let mut inbound = InboundGroupSession::new(&outbound.session_key(), MegolmConfig::version_1());

    let text = b"hello, group";
    let message = outbound.encrypt(text);
    let decrypted = inbound
        .decrypt(&message)
        .map_err(|e| format!("Megolm decrypt: {e}"))?;
    if decrypted.plaintext != text {
        return Err("Megolm: wrong text".into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use vodozemac::megolm::MegolmMessage;

    #[test]
    fn olm_round_trips_both_ways() {
        olm_round_trip().unwrap();
    }

    #[test]
    fn megolm_round_trips() {
        megolm_round_trip().unwrap();
    }

    #[test]
    fn tampered_megolm_ciphertext_fails_to_decrypt() {
        let mut outbound = GroupSession::new(MegolmConfig::version_1());
        let mut inbound =
            InboundGroupSession::new(&outbound.session_key(), MegolmConfig::version_1());
        let mut bytes = outbound.encrypt(b"do not touch").to_bytes();
        let middle = bytes.len() / 2;
        bytes[middle] ^= 0x55;
        // Tampering is caught either when the message is parsed or when it is decrypted.
        let failed = match MegolmMessage::from_bytes(&bytes) {
            Err(_) => true,
            Ok(message) => inbound.decrypt(&message).is_err(),
        };
        assert!(failed, "a tampered Megolm message must not decrypt");
    }

    #[test]
    fn tampered_olm_ciphertext_fails_to_decrypt() {
        let alice = Account::new();
        let mut bob = Account::new();
        bob.generate_one_time_keys(1);
        let one_time_key = *bob.one_time_keys().values().next().unwrap();
        let mut alice_session = alice
            .create_outbound_session(OlmConfig::version_1(), bob.curve25519_key(), one_time_key)
            .unwrap();
        let OlmMessage::PreKey(first) = alice_session.encrypt(b"first").unwrap() else {
            panic!("expected a pre-key message");
        };
        let mut bob_session = bob
            .create_inbound_session(OlmConfig::version_1(), alice.curve25519_key(), &first)
            .unwrap()
            .session;
        // Bob answers, so Alice's session is established and Bob's next message is a normal one.
        let answer = bob_session.encrypt(b"second").unwrap();
        alice_session.decrypt(&answer).unwrap();
        let (kind, mut bytes) = bob_session.encrypt(b"third").unwrap().to_parts();
        let middle = bytes.len() / 2;
        bytes[middle] ^= 0x55;
        let failed = match OlmMessage::from_parts(kind, &bytes) {
            Err(_) => true,
            Ok(message) => alice_session.decrypt(&message).is_err(),
        };
        assert!(failed, "a tampered Olm message must not decrypt");
    }
}
