//! LimeCore: Lime's shared core, linked into the iOS app through UniFFI.
//!
//! This is the skeleton (LIME-89): it proves the toolchain with a real vodozemac encryption
//! round trip. There is no networking, storage or persisted key material yet.
//!
//! The public FFI surface is [`core_version`], [`encryption_self_test`] and the encrypted
//! local store [`LimeStore`] (LIME-90). No secret material crosses the FFI or is logged.

mod client;
mod format;
mod keys;
mod protocol;
mod selftest;
mod store;
mod transport;

#[cfg(test)]
mod client_tests;
#[cfg(test)]
mod testing;

pub use format::{Block, ListItem, Span};
pub use client::{find_user, lookup_user_by_email, DeviceInfo, FoundUser, SyncReport};
pub use store::search::{ConversationMatch, SearchHit};
pub use store::threads::ThreadSummary;
pub use store::{BlockedPerson, ConversationSummary, KeyInfo, LimeStore, MemberInfo, MessageItem, StoreError};
pub use transport::{HeaderPair, Transport, TransportError, TransportResponse};

uniffi::setup_scaffolding!();

/// The outcome of [`encryption_self_test`]. `detail` is a short human-readable line that never
/// contains key material.
#[derive(Debug, Clone, uniffi::Record)]
pub struct SelfTestReport {
    pub olm_ok: bool,
    pub megolm_ok: bool,
    pub detail: String,
}

/// The crate version.
#[uniffi::export]
pub fn core_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// Creates two in-memory Olm accounts and round-trips a message both ways, then a Megolm group
/// session shared into an inbound session and round-tripped. Nothing is stored.
#[uniffi::export]
pub fn encryption_self_test() -> SelfTestReport {
    let olm = selftest::olm_round_trip();
    let megolm = selftest::megolm_round_trip();
    let detail = match (&olm, &megolm) {
        (Ok(()), Ok(())) => "Olm and Megolm round trips succeeded".to_string(),
        (Err(e), _) => format!("Olm failed: {e}"),
        (_, Err(e)) => format!("Megolm failed: {e}"),
    };
    SelfTestReport {
        olm_ok: olm.is_ok(),
        megolm_ok: megolm.is_ok(),
        detail,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_is_the_crate_version() {
        assert_eq!(core_version(), env!("CARGO_PKG_VERSION"));
    }

    #[test]
    fn self_test_passes() {
        let report = encryption_self_test();
        assert!(report.olm_ok, "{}", report.detail);
        assert!(report.megolm_ok, "{}", report.detail);
    }
}
