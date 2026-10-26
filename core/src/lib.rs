//! LimeCore: Lime's shared core, linked into the iOS app through UniFFI.
//!
//! This is the skeleton (LIME-89): it proves the toolchain with a real vodozemac encryption
//! round trip. There is no networking, storage or persisted key material yet.
//!
//! The public FFI surface is [`core_version`], [`encryption_self_test`] and the encrypted
//! local store [`LimeStore`] (LIME-90). No secret material crosses the FFI or is logged.

mod call_emoji;
pub mod drafts;
mod captions;
mod client;
mod format;
mod keys;
mod mesh;
mod protocol;
mod selftest;
mod store;
mod transport;

#[cfg(test)]
mod client_tests;
#[cfg(test)]
mod testing;

pub use call_emoji::{call_emoji, group_call_emoji, CallEmoji, GroupCallKey};
pub use format::{Block, ListItem, Span};
pub use mesh::{MeshAction, MeshEngine, MeshFetchJob, MeshStats, MeshUpload};
pub use client::groups::{default_group_name, GroupDetails, GroupMemberInfo};
pub use client::group_calls::{group_call_rings, GroupCallEmojiState, GroupCallEvent, GroupCallInfo, GroupCallJoin, GroupCallParticipant, GroupCallSendReport, LiveKitToken};
pub use client::attachments::{OutgoingAttachment, TransferProgress};
pub use client::{find_user, lookup_user_by_email, DeviceInfo, FoundUser, SyncReport, Verification};
pub use store::search::{ConversationMatch, JamSearchHit, SearchHit};
pub use store::threads::ThreadSummary;
pub use store::link_preview::{LinkPreview, OutgoingPreview};
pub use store::calls::{CallEvent, CallHistoryRecord};
pub use store::shared::SharedKind;
pub use client::emergency::{emergency_alert_policy, emergency_number};
pub use store::emergency::{EmergencyAlert, EmergencyDraft, EmergencyInfo, EmergencyRollup, EmergencySettings, RollupEntry};
pub use client::profile::PublicProfile;
pub use client::jam::{JamAttachmentInfo, JamCommentInfo, JamCountsInfo, JamInfo, JamPageInfo, JamPostInfo, JamSendProgress, JamSubscriberInfo};
pub use client::calls::TurnServers;
pub use store::status::{ContactStatus, StatusInfo};
pub use store::storage::{ChatUsage, MediaEntry, MediaRef, StorageUsage};
pub use store::{AttachmentInfo, BlockedPerson, ConversationSummary, KeyInfo, LimeStore, MemberInfo, MessageItem, StoreError};
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
