//! The wire protocol of `docs/api-v2.md`: the signed op, the sealed inner, and how they are
//! encoded. Pure functions; no network and no storage.

mod canonical;
pub(crate) mod group;
mod hlc;

pub(crate) use canonical::canonical_bytes;
pub(crate) use hlc::Hlc;

use serde_json::{json, Value};
use vodozemac::{Ed25519PublicKey, Ed25519Signature};

/// The text a master key signs to vouch for a device (`api-v2.md` section 11, decided in LIME-92).
pub(crate) fn device_signing_text(
    device_id: &str,
    identity_key: &str,
    signing_key: &str,
) -> String {
    format!("lime-device-v1\n{device_id}\n{identity_key}\n{signing_key}")
}

/// A device's keys, vouched for by its account's master key.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct SenderCert {
    pub device_id: String,
    pub identity_key: String,
    pub signing_key: String,
    pub master_key: String,
    pub master_signature: String,
}

impl SenderCert {
    pub(crate) fn to_json(&self) -> Value {
        json!({
            "device_id": self.device_id,
            "identity_key": self.identity_key,
            "signing_key": self.signing_key,
            "master_key": self.master_key,
            "master_signature": self.master_signature,
        })
    }

    pub(crate) fn from_json(value: &Value) -> Option<Self> {
        let text = |k: &str| value.get(k).and_then(Value::as_str).map(str::to_owned);
        Some(Self {
            device_id: text("device_id")?,
            identity_key: text("identity_key")?,
            signing_key: text("signing_key")?,
            master_key: text("master_key")?,
            master_signature: text("master_signature")?,
        })
    }

    /// True when the master key really signed this device's keys.
    pub(crate) fn verify(&self) -> bool {
        verify_signature(
            &self.master_key,
            &self.master_signature,
            device_signing_text(&self.device_id, &self.identity_key, &self.signing_key).as_bytes(),
        )
    }
}

/// An op (`api-v2.md` section 3): `{ op_id, type, conversation_id, hlc, parents[], payload, sig }`.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Op {
    pub op_id: String,
    pub op_type: String,
    pub conversation_id: String,
    pub hlc: String,
    pub parents: Vec<String>,
    pub payload: Value,
    pub sig: String,
}

impl Op {
    /// The op without its signature: what is signed.
    fn unsigned_json(&self) -> Value {
        json!({
            "op_id": self.op_id,
            "type": self.op_type,
            "conversation_id": self.conversation_id,
            "hlc": self.hlc,
            "parents": self.parents,
            "payload": self.payload,
        })
    }

    /// The canonical bytes the sending device signs (sorted keys, no whitespace, no `sig`).
    pub(crate) fn signing_bytes(&self) -> Vec<u8> {
        canonical_bytes(&self.unsigned_json())
    }

    pub(crate) fn to_json(&self) -> Value {
        let mut value = self.unsigned_json();
        value["sig"] = Value::String(self.sig.clone());
        value
    }

    pub(crate) fn from_json(value: &Value) -> Option<Self> {
        let text = |k: &str| value.get(k).and_then(Value::as_str).map(str::to_owned);
        let parents = value
            .get("parents")?
            .as_array()?
            .iter()
            .map(|p| p.as_str().map(str::to_owned))
            .collect::<Option<Vec<_>>>()?;
        Some(Self {
            op_id: text("op_id")?,
            op_type: text("type")?,
            conversation_id: text("conversation_id")?,
            hlc: text("hlc")?,
            parents,
            payload: value.get("payload")?.clone(),
            sig: text("sig")?,
        })
    }

    /// True when `signing_key` (the sending device's Ed25519 key, base64) signed this op.
    pub(crate) fn verify(&self, signing_key: &str) -> bool {
        verify_signature(signing_key, &self.sig, &self.signing_bytes())
    }
}

/// What the recipient gets after decrypting the outer ciphertext: `{ sender_user, sender_device,
/// sender_cert, op }`.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct SealedInner {
    pub sender_user: String,
    pub sender_device: String,
    pub sender_cert: SenderCert,
    pub op: Op,
}

impl SealedInner {
    pub(crate) fn to_bytes(&self) -> Vec<u8> {
        canonical_bytes(&json!({
            "sender_user": self.sender_user,
            "sender_device": self.sender_device,
            "sender_cert": self.sender_cert.to_json(),
            "op": self.op.to_json(),
        }))
    }

    pub(crate) fn from_bytes(bytes: &[u8]) -> Option<Self> {
        let value: Value = serde_json::from_slice(bytes).ok()?;
        let text = |k: &str| value.get(k).and_then(Value::as_str).map(str::to_owned);
        Some(Self {
            sender_user: text("sender_user")?,
            sender_device: text("sender_device")?,
            sender_cert: SenderCert::from_json(value.get("sender_cert")?)?,
            op: Op::from_json(value.get("op")?)?,
        })
    }
}

/// The conversation id both people compute for a 1:1 chat: the two user ids, sorted.
pub(crate) fn dm_conversation_id(user_a: &str, user_b: &str) -> String {
    let (low, high) = if user_a <= user_b {
        (user_a, user_b)
    } else {
        (user_b, user_a)
    };
    format!("dm:{low}:{high}")
}

pub(crate) fn verify_signature(public_key_b64: &str, signature_b64: &str, message: &[u8]) -> bool {
    let Ok(key) = Ed25519PublicKey::from_base64(public_key_b64) else {
        return false;
    };
    let Ok(signature) = Ed25519Signature::from_base64(signature_b64) else {
        return false;
    };
    key.verify(message, &signature).is_ok()
}

#[cfg(test)]
mod tests;
