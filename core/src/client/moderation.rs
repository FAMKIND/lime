//! Reports and the moderators' tool (LIME-191, docs/moderation.md).
//!
//! A report is built on the reporter's phone, **sealed to the server's moderation key** (a key pair of its own, not the mesh key: only the moderation
//! functions can open it) and sent to `report`. What each party learns: lime's moderators, exactly what the reporter chose to include (the item as the phone
//! holds it, a note, the ids of what is reported) with who reported; the server's `report` function, only the reporter, the kind of subject and the reason
//! (it cannot open the payload); the reported person and every other member, nothing. Nobody else's encryption changes: only the reporter's own copy leaves.

use super::*;
use crate::mesh::{seal_to_server, ServerKey};
use vodozemac::Curve25519SecretKey;

const REPORT_INFO: &[u8] = b"lime-report-v1";

/// The server's moderation public keys by id, pinned in the app (the newest is sealed to). Id 1 is the staging project's pair, made 2026-10-25; the
/// secret is only in Supabase's secrets. A new key is added with the next id when it rotates.
pub(crate) const MODERATION_KEYS: &[ServerKey] = &[ServerKey { id: 1, public: [0x05, 0x8d, 0x63, 0x71, 0x20, 0x7b, 0xc5, 0x96, 0xe0, 0x13, 0x09, 0x4b, 0x56, 0x7b, 0x60, 0x47, 0xa2, 0x05, 0xcd, 0x30, 0x88, 0x88, 0x89, 0x8d, 0xd3, 0x0e, 0xc0, 0x5e, 0xeb, 0xd8, 0x26, 0x7d] }];

/// The local test stack's moderation key (its secret is in `supabase/functions/.env`; public on purpose): what the server tests seal to.
#[cfg(test)]
pub(crate) const LOCAL_TEST_KEY: ServerKey = ServerKey { id: 1, public: [0xba, 0x98, 0xde, 0xe7, 0x00, 0xeb, 0xd3, 0x9f, 0xbb, 0x24, 0xb3, 0x4a, 0xeb, 0x0c, 0x3a, 0x4f, 0x67, 0xa0, 0xdb, 0xfa, 0x12, 0xe4, 0x85, 0xf7, 0xb6, 0xce, 0x01, 0x60, 0x07, 0x6e, 0x2b, 0x23] };

/// What a person chose to send about something.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ReportInput {
    /// message, person, group, jam_post, comment, jam, org or profile_item.
    pub subject_kind: String,
    /// The ids of what is reported (a message id, a post id, a comment id, a jam id, an org id, a user id), in the order the moderators need them.
    pub subject_ids: Vec<String>,
    /// harassment, spam, impersonation, inappropriate, child_safety, hate_violence or other.
    pub reason: String,
    /// The reporter's own words, at most 500 characters.
    pub note: String,
    /// The item as this phone holds it (a JSON text the app builds); empty when the reporter left it out.
    pub included: String,
}

/// A moderation function's answer: the HTTP status and the JSON body as text.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ModerationAnswer {
    pub status: u16,
    pub body: String,
}

const KINDS: &[&str] = &["message", "person", "group", "jam_post", "comment", "jam", "org", "profile_item"];
const REASONS: &[&str] = &["harassment", "spam", "impersonation", "inappropriate", "child_safety", "hate_violence", "other"];
const MAX_NOTE_CHARS: usize = 500;
const MAX_INCLUDED_BYTES: usize = 64 * 1024;

/// The sealed form of a report for `reporter`: only the chosen parts, sealed to `server` with the given ephemeral key.
pub(crate) fn seal_report_with(ephemeral: &Curve25519SecretKey, server: &ServerKey, id: &str, reporter: &str, created: i64, input: &ReportInput) -> Result<Vec<u8>, StoreError> {
    if !KINDS.contains(&input.subject_kind.as_str()) || !REASONS.contains(&input.reason.as_str()) || input.subject_ids.is_empty() || input.subject_ids.len() > 8 {
        return Err(StoreError::Rejected);
    }
    if input.note.chars().count() > MAX_NOTE_CHARS || input.included.len() > MAX_INCLUDED_BYTES {
        return Err(StoreError::Rejected);
    }
    let included: Value = if input.included.is_empty() { Value::Null } else { serde_json::from_str(&input.included).unwrap_or_else(|_| Value::String(input.included.clone())) };
    let payload = json!({
        "v": 1, "id": id, "subject_kind": input.subject_kind, "subject_ids": input.subject_ids, "reason": input.reason,
        "note": input.note, "included": included, "reporter": reporter, "created": created,
    });
    seal_to_server(ephemeral, server, REPORT_INFO, &serde_json::to_vec(&payload).map_err(|_| StoreError::BadMessage)?)
}

#[uniffi::export]
impl LimeStore {
    /// Sends a report: sealed on this phone to the moderation key, then to the `report` function. Ten a day (the server says 429 after that).
    pub fn send_report(&self, transport: Arc<dyn Transport>, auth_token: String, report: ReportInput) -> Result<(), StoreError> {
        let state = self.load_or_create_account()?;
        let me = state.user_id.clone().filter(|_| state.registered).ok_or(StoreError::NotRegistered)?;
        let server = MODERATION_KEYS.last().copied().ok_or(StoreError::Rejected)?;
        let sealed = seal_report_with(&Curve25519SecretKey::new(), &server, &new_id(), &me, now_ms(), &report)?;
        let (status, _) = call(
            &transport,
            Some(&auth_token),
            "report",
            &json!({ "kind": report.subject_kind, "reason": report.reason, "sealed": vodozemac::base64_encode(&sealed) }),
        )?;
        check(status)
    }

    /// The server blob that holds a post right now (what a report of it must carry: "hide this post" hides that blob; an edit makes a new one).
    pub fn jam_post_blob_id(&self, post_id: String) -> Result<Option<String>, StoreError> {
        self.with_conn(|conn| {
            use rusqlite::OptionalExtension;
            conn.query_row("SELECT blob_id FROM jam_posts WHERE post_id = ?1", params![post_id], |r| r.get::<_, Option<String>>(0)).optional().map(Option::flatten).map_err(db_err)
        })
    }

    /// One call to the moderators' functions (`moderation-list`, `moderation-open`, `moderation-act`): the body is JSON text; anyone not on the server's
    /// allow-list gets a 403. The answer's body is the JSON text the function returned.
    pub fn moderation_request(&self, transport: Arc<dyn Transport>, auth_token: String, function: String, body: String) -> Result<ModerationAnswer, StoreError> {
        if !["moderation-list", "moderation-open", "moderation-act"].contains(&function.as_str()) {
            return Err(StoreError::Rejected);
        }
        let value: Value = serde_json::from_str(&body).map_err(|_| StoreError::BadMessage)?;
        let (status, answer) = call(&transport, Some(&auth_token), &function, &value)?;
        Ok(ModerationAnswer { status, body: answer.to_string() })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn input() -> ReportInput {
        ReportInput {
            subject_kind: "jam_post".into(),
            subject_ids: vec!["post-1".into()],
            reason: "spam".into(),
            note: "buy my stuff".into(),
            included: r#"{"text":"hello"}"#.into(),
        }
    }

    #[test]
    fn a_report_seals_only_what_was_chosen_and_nothing_else() {
        let ephemeral = Curve25519SecretKey::new();
        let mut left_out = input();
        left_out.included = String::new();
        let with = seal_report_with(&ephemeral, &LOCAL_TEST_KEY, "r1", "u1", 5, &input()).unwrap();
        let without = seal_report_with(&ephemeral, &LOCAL_TEST_KEY, "r1", "u1", 5, &left_out).unwrap();
        assert!(with.len() > without.len(), "the included item travels only when chosen");
        assert_eq!(with[0], 1, "key id first");
        assert!(!String::from_utf8_lossy(&with).contains("buy my stuff"), "sealed, not readable");
    }

    #[test]
    fn a_bad_kind_reason_note_or_empty_subject_is_refused_before_anything_is_sealed() {
        let e = Curve25519SecretKey::new();
        for bad in [
            ReportInput { subject_kind: "wat".into(), ..input() },
            ReportInput { reason: "wat".into(), ..input() },
            ReportInput { subject_ids: vec![], ..input() },
            ReportInput { note: "x".repeat(501), ..input() },
            ReportInput { included: "y".repeat(70_000), ..input() },
        ] {
            assert!(seal_report_with(&e, &LOCAL_TEST_KEY, "r", "u", 1, &bad).is_err());
        }
    }

    #[test]
    fn the_moderation_key_is_not_the_mesh_key() {
        assert_ne!(MODERATION_KEYS.last().unwrap().public, crate::mesh::SERVER_KEYS.last().unwrap().public);
    }
}
