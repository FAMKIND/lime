//! The account on a second device (LIME-341a, DESIGN-M1 D6 = K2).
//!
//! An account has one master key. **Phones and tablets** hold its secret and make a new device of their own from it (`set_up_linked_device`); **computers never
//! hold it**: a computer makes its own device keys (`device_only_request`), a phone signs them (`certify_device`: the master key's word that these keys are mine),
//! and the computer keeps the certificate (`finish_device_only`). Either way the new device is **registered through the ordinary `register_device`**, and the account's
//! **one delivery key is installed, never made**: a second key would overwrite the account's single row on the server and every contact's sealed send would be
//! refused (403) and fall back to identified, showing the sender to the server.
//!
//! What this does not carry: contacts, chats, groups, keys or history (the link package, LIME-341b/c), the five-device limit and unlinking (342). With the
//! certificate a computer is accepted by my other devices (`own.copy`, LIME-340: the master-signature check) and by my contacts (their cache of my devices).
//! A device without the master secret answers anything that needs it with `MasterKeyNotOnDevice`, never a panic.
//!
//! What each party learns: the server sees one more device row for the account (it already knows how many devices an account has); nothing new is stored there.

use super::*;
use crate::keys::{DeviceCertificate, DeviceRequest};

#[uniffi::export]
impl LimeStore {
    /// **A phone or tablet** linking to an existing account: this store (which must be empty) becomes a new device of `user_id` from the account's master secret
    /// (32 bytes) and its delivery key (32 bytes). The device is not registered yet: call `register_device` next.
    pub fn set_up_linked_device(&self, user_id: String, master_secret: Vec<u8>, delivery_key: Vec<u8>) -> Result<(), StoreError> {
        if user_id.trim().is_empty() || self.with_conn(|conn| Ok(load_account(conn, &self.pickle_key)?.is_some()))? {
            return Err(StoreError::Rejected);
        }
        let state = AccountState::from_master(&master_secret, &user_id)?;
        self.with_conn(|conn| {
            delivery::install_key(conn, &delivery_key, now_ms())?;
            save_account(conn, &self.pickle_key, &state)
        })
    }

    /// **A computer**, step 1: this store (which must be empty) makes its own device keys, holding no master secret, and returns the public half for a phone to certify.
    pub fn device_only_request(&self, user_id: String) -> Result<DeviceRequest, StoreError> {
        if user_id.trim().is_empty() || self.with_conn(|conn| Ok(load_account(conn, &self.pickle_key)?.is_some()))? {
            return Err(StoreError::Rejected);
        }
        let state = AccountState::device_only(&user_id);
        let request = state.request();
        self.save(&state)?;
        Ok(request)
    }

    /// **A phone or tablet** certifies another device's keys with the master key (what a computer is given to finish linking). A device that does not hold the master
    /// secret answers `MasterKeyNotOnDevice`.
    pub fn certify_device(&self, request: DeviceRequest) -> Result<DeviceCertificate, StoreError> {
        let state = self.with_conn(|conn| load_account(conn, &self.pickle_key))?.ok_or(StoreError::NotRegistered)?;
        state.certify(&request)
    }

    /// **A computer**, step 2: keeps the certificate a phone made for this device's keys (checked against them) and the account's delivery key. Then `register_device`.
    pub fn finish_device_only(&self, certificate: DeviceCertificate, delivery_key: Vec<u8>) -> Result<(), StoreError> {
        let mut state = self.with_conn(|conn| load_account(conn, &self.pickle_key))?.ok_or(StoreError::NotFound)?;
        state.accept_certificate(&certificate)?;
        self.with_conn(|conn| {
            delivery::install_key(conn, &delivery_key, now_ms())?;
            save_account(conn, &self.pickle_key, &state)
        })
    }
}
