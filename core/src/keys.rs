//! A device's long-term keys: the Olm account (the device's Curve25519 identity key and Ed25519
//! signing key) and the account's master signing key. They are persisted in the SQLCipher store
//! (see `store/account.rs`), never leave the device, and are never logged.
//!
//! The Olm account and sessions are saved as vodozemac pickles encrypted with a key derived from
//! the store key (HKDF-SHA256). The master signing key's secret is stored in the same encrypted
//! database as base64 text, because vodozemac has no pickle format for a bare Ed25519 key.

use hkdf::Hkdf;
use sha2::Sha256;
use vodozemac::olm::Account;
use vodozemac::Ed25519SecretKey;

use crate::protocol::{device_signing_text, Hlc, SenderCert};

/// The key that encrypts the pickles, derived from the store key so nothing extra has to be kept.
pub(crate) fn derive_pickle_key(store_key: &[u8]) -> [u8; 32] {
    let hkdf = Hkdf::<Sha256>::new(None, store_key);
    let mut out = [0u8; 32];
    hkdf.expand(b"lime-pickle-v1", &mut out)
        .expect("32 bytes is a valid HKDF length");
    out
}

pub(crate) struct AccountState {
    pub account: Account,
    pub master: Ed25519SecretKey,
    pub device_id: String,
    /// Learned from the server at registration.
    pub user_id: Option<String>,
    pub registered: bool,
    pub hlc: Hlc,
}

impl AccountState {
    /// A brand new device: a fresh Olm account, a fresh master key (this is the account's first
    /// device) and a random device id.
    pub(crate) fn create() -> Self {
        Self {
            account: Account::new(),
            master: Ed25519SecretKey::new(),
            device_id: uuid::Uuid::new_v4().to_string(),
            user_id: None,
            registered: false,
            hlc: Hlc::default(),
        }
    }

    pub(crate) fn identity_key(&self) -> String {
        self.account.curve25519_key().to_base64()
    }

    pub(crate) fn signing_key(&self) -> String {
        self.account.ed25519_key().to_base64()
    }

    pub(crate) fn master_key(&self) -> String {
        self.master.public_key().to_base64()
    }

    /// The master key's signature over this device's keys.
    pub(crate) fn cert(&self) -> SenderCert {
        let identity_key = self.identity_key();
        let signing_key = self.signing_key();
        let text = device_signing_text(&self.device_id, &identity_key, &signing_key);
        SenderCert {
            device_id: self.device_id.clone(),
            master_signature: self.master.sign(text.as_bytes()).to_base64(),
            identity_key,
            signing_key,
            master_key: self.master_key(),
        }
    }
}
