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
    /// The account's master secret: on its first device and on phones and tablets linked to it (DESIGN-M1 K2); **never on a computer** (`None`).
    pub master: Option<Ed25519SecretKey>,
    /// A device that does not hold the master secret (a computer): the master's public key and its signature over this device's keys, made on a phone
    /// (`certify`). `None` on a device that holds the secret, and on a computer that has not been certified yet.
    pub vouched: Option<(String, String)>,
    pub device_id: String,
    /// Learned from the server at registration (known at once on a linked device).
    pub user_id: Option<String>,
    pub registered: bool,
    pub hlc: Hlc,
}

/// A new device's public keys, handed to a phone to certify (LIME-341a).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct DeviceRequest {
    pub device_id: String,
    pub identity_key: String,
    pub signing_key: String,
}

/// The master key's word for a device: its keys and the master's signature over them (LIME-341a). Made on a phone for a computer.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct DeviceCertificate {
    pub device_id: String,
    pub identity_key: String,
    pub signing_key: String,
    pub master_key: String,
    pub master_signature: String,
}

impl AccountState {
    /// A brand new device: a fresh Olm account, a fresh master key (this is the account's first
    /// device) and a random device id.
    pub(crate) fn create() -> Self {
        Self {
            account: Account::new(),
            master: Some(Ed25519SecretKey::new()),
            vouched: None,
            device_id: uuid::Uuid::new_v4().to_string(),
            user_id: None,
            registered: false,
            hlc: Hlc::default(),
        }
    }

    /// A phone or tablet linked to an existing account (K2): new device keys, certified by the account's master secret it is given. The device registers
    /// itself afterwards (`register_device`); the delivery key is installed beside it, never made.
    pub(crate) fn from_master(master_secret: &[u8], user_id: &str) -> Result<Self, crate::store::StoreError> {
        let secret: [u8; 32] = master_secret.try_into().map_err(|_| crate::store::StoreError::BadMessage)?;
        Ok(Self {
            account: Account::new(),
            master: Some(Ed25519SecretKey::from_slice(&secret)),
            vouched: None,
            device_id: uuid::Uuid::new_v4().to_string(),
            user_id: Some(user_id.to_owned()),
            registered: false,
            hlc: Hlc::default(),
        })
    }

    /// A computer: new device keys and **no master secret**; it cannot register until a phone has certified its keys (`finish_device_only`).
    pub(crate) fn device_only(user_id: &str) -> Self {
        Self {
            account: Account::new(),
            master: None,
            vouched: None,
            device_id: uuid::Uuid::new_v4().to_string(),
            user_id: Some(user_id.to_owned()),
            registered: false,
            hlc: Hlc::default(),
        }
    }

    /// Takes the master's certificate for this device's keys (checked: it must be for these keys and verify under its own master key).
    pub(crate) fn accept_certificate(&mut self, certificate: &DeviceCertificate) -> Result<(), crate::store::StoreError> {
        let cert = SenderCert {
            device_id: certificate.device_id.clone(),
            identity_key: certificate.identity_key.clone(),
            signing_key: certificate.signing_key.clone(),
            master_key: certificate.master_key.clone(),
            master_signature: certificate.master_signature.clone(),
        };
        if self.master.is_some() || cert.device_id != self.device_id || cert.identity_key != self.identity_key() || cert.signing_key != self.signing_key() || !cert.verify() {
            return Err(crate::store::StoreError::BadMessage);
        }
        self.vouched = Some((cert.master_key, cert.master_signature));
        Ok(())
    }

    /// This device's public keys, for a phone to certify.
    pub(crate) fn request(&self) -> DeviceRequest {
        DeviceRequest { device_id: self.device_id.clone(), identity_key: self.identity_key(), signing_key: self.signing_key() }
    }

    /// Signs another device's keys with the master secret: only a device that holds it can (`MasterKeyNotOnDevice` otherwise).
    pub(crate) fn certify(&self, request: &DeviceRequest) -> Result<DeviceCertificate, crate::store::StoreError> {
        let master = self.master.as_ref().ok_or(crate::store::StoreError::MasterKeyNotOnDevice)?;
        let text = device_signing_text(&request.device_id, &request.identity_key, &request.signing_key);
        Ok(DeviceCertificate {
            device_id: request.device_id.clone(),
            identity_key: request.identity_key.clone(),
            signing_key: request.signing_key.clone(),
            master_key: master.public_key().to_base64(),
            master_signature: master.sign(text.as_bytes()).to_base64(),
        })
    }

    pub(crate) fn identity_key(&self) -> String {
        self.account.curve25519_key().to_base64()
    }

    pub(crate) fn signing_key(&self) -> String {
        self.account.ed25519_key().to_base64()
    }

    /// The account's master public key ("" on a computer not yet certified).
    pub(crate) fn master_key(&self) -> String {
        match (&self.master, &self.vouched) {
            (Some(master), _) => master.public_key().to_base64(),
            (None, Some((key, _))) => key.clone(),
            (None, None) => String::new(),
        }
    }

    /// Can this device vouch for itself (it holds the master secret, or a phone certified it)?
    pub(crate) fn is_certified(&self) -> bool {
        self.master.is_some() || self.vouched.is_some()
    }

    /// The master key's signature over this device's keys.
    pub(crate) fn cert(&self) -> SenderCert {
        let identity_key = self.identity_key();
        let signing_key = self.signing_key();
        let text = device_signing_text(&self.device_id, &identity_key, &signing_key);
        let master_signature = match (&self.master, &self.vouched) {
            (Some(master), _) => master.sign(text.as_bytes()).to_base64(),
            (None, Some((_, signature))) => signature.clone(),
            (None, None) => String::new(),
        };
        SenderCert { device_id: self.device_id.clone(), master_signature, identity_key, signing_key, master_key: self.master_key() }
    }
}

/// A short, comparable fingerprint of a master public key (base64): the first ten bytes of its
/// SHA-256, as five groups of four hex digits (`A1B2 C3D4 E5F6 0718 293A`).
pub(crate) fn fingerprint_of(master_key_b64: &str) -> Option<String> {
    use sha2::{Digest, Sha256};
    let master = vodozemac::base64_decode(master_key_b64).ok()?;
    let digest = Sha256::digest(&master);
    let hex: Vec<String> = digest[..10].iter().map(|b| format!("{b:02X}")).collect();
    Some(hex.chunks(2).map(|pair| pair.concat()).collect::<Vec<_>>().join(" "))
}

/// Digits only, upper case: how two fingerprints are compared (spaces and case do not matter).
pub(crate) fn normalize_fingerprint(text: &str) -> String {
    text.chars().filter(char::is_ascii_hexdigit).map(|c| c.to_ascii_uppercase()).collect()
}
