//! A band's writers send posts for review; an owner publishes (LIME-273, DESIGN: writers draft as the band, no band keys on a writer's phone).
//!
//! A writer's article is an ordinary shared draft (LIME-233). *Send for review* names the band, invites the band's owners (no contact needed: they
//! are in the band) and tells them it is waiting. The owner whose phone holds the band's jam publishes it as the band, crediting the writer;
//! *Send back* returns it to the writer with a note. Nothing new reaches the server: the draft's traffic is the draft's own.

use super::draft_publish::review_jam;
use super::draft_sync::{active_authors, enqueue, MAX_AUTHORS};
use super::org::{org_owner_ids, org_role_of};
use super::*;

/// Where a draft stands with a band's review.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct DraftReview {
    /// The band it was sent to (empty: not a review draft).
    pub jam_id: String,
    /// `waiting`, `sent_back` or `published` (empty: not a review draft).
    pub state: String,
    /// The owner's note when it was sent back.
    pub note: String,
    /// I am an owner of that band: I can publish it or send it back.
    pub i_review: bool,
    /// The one who wrote it and sent it.
    pub writer: String,
}

/// A draft waiting for the band's owners.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ReviewItem {
    pub draft_id: String,
    pub title: String,
    pub writer: String,
    pub updated_at: i64,
}

#[uniffi::export]
impl LimeStore {
    /// A writer of the band sends a draft for review: the band's owners (up to four) are invited to it and told it waits. Sending it again after it
    /// came back does the same. An owner posts directly, so this is refused for one.
    pub fn send_draft_for_review(&self, draft_id: String, jam_id: String) -> Result<(), StoreError> {
        let state = self.load_or_create_account()?;
        let me = state.user_id.clone().filter(|_| state.registered).ok_or(StoreError::NotRegistered)?;
        let now = now_ms();
        self.with_conn(|conn| {
            if org_role_of(conn, &jam_id, &me) != Some("writer") {
                return Err(StoreError::Rejected);
            }
            let owners: Vec<String> = org_owner_ids(conn, &jam_id).into_iter().filter(|u| *u != me).take(MAX_AUTHORS - 1).collect();
            if owners.is_empty() {
                return Err(StoreError::Rejected);
            }
            if let Some(known) = review_jam(conn, &draft_id) {
                if known != jam_id {
                    return Err(StoreError::Rejected);
                }
            }
            self.share_draft_in(conn, &me, &draft_id, owners, false, Some(&jam_id))?;
            conn.execute("UPDATE drafts SET for_jam = ?2, review = 'waiting', review_note = '' WHERE draft_id = ?1", params![draft_id, jam_id]).map_err(db_err)?;
            // Owners who were invited earlier (it came back, and is sent again) are told it waits.
            for who in active_authors(conn, &draft_id)?.iter().filter(|u| **u != me) {
                enqueue(conn, &draft_id, who, "draft.review", json!({ "draft_id": draft_id, "jam_id": jam_id, "state": "waiting" }), now)?;
            }
            Ok(())
        })
    }

    /// A draft's place in a review (empty for an ordinary draft).
    pub fn draft_review(&self, draft_id: String) -> Result<DraftReview, StoreError> {
        let me = self.load_or_create_account()?.user_id;
        self.with_conn(|conn| {
            let row: Option<(Option<String>, Option<String>, String, Option<String>)> = conn
                .query_row("SELECT for_jam, review, review_note, writer FROM drafts WHERE draft_id = ?1", params![draft_id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))
                .optional()
                .map_err(db_err)?;
            let Some((jam, state, note, writer)) = row else { return Err(StoreError::NotFound) };
            let jam = jam.unwrap_or_default();
            let i_review = !jam.is_empty() && me.as_deref().is_some_and(|me| org_role_of(conn, &jam, me) == Some("owner") && writer.as_deref() != Some(me));
            Ok(DraftReview { jam_id: jam, state: state.unwrap_or_default(), note, i_review, writer: writer.unwrap_or_default() })
        })
    }

    /// The drafts waiting for this band's owners (mine to review, never my own).
    pub fn drafts_waiting_for_review(&self, jam_id: String) -> Result<Vec<ReviewItem>, StoreError> {
        let Some(me) = self.load_or_create_account()?.user_id else { return Ok(vec![]) };
        let ids: Vec<(String, Option<String>, i64)> = self.with_conn(|conn| {
            if org_role_of(conn, &jam_id, &me) != Some("owner") {
                return Ok(vec![]);
            }
            let mut st = conn
                .prepare("SELECT draft_id, writer, updated_at FROM drafts WHERE for_jam = ?1 AND review = 'waiting' AND deleted = 0 ORDER BY updated_at DESC")
                .map_err(db_err)?;
            let rows = st.query_map(params![jam_id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).map_err(db_err)?;
            rows.collect::<Result<_, _>>().map_err(db_err)
        })?;
        let mut out = Vec::new();
        for (draft_id, writer, updated_at) in ids {
            if writer.as_deref() == Some(me.as_str()) {
                continue;
            }
            let title = self.with_conn(|conn| self.with_draft_conn(conn, &draft_id, false, |d| Ok(d.meta().title)))?;
            out.push(ReviewItem { draft_id, title, writer: writer.unwrap_or_default(), updated_at });
        }
        Ok(out)
    }

    /// An owner returns a draft to its writer with a note (at most 500 characters): the writer's Drafts says "Sent back".
    pub fn send_draft_back(&self, draft_id: String, note: String) -> Result<(), StoreError> {
        let me = self.load_or_create_account()?.user_id.ok_or(StoreError::NotRegistered)?;
        let note: String = note.trim().chars().take(500).collect();
        let now = now_ms();
        self.with_conn(|conn| {
            let jam = review_jam(conn, &draft_id).ok_or(StoreError::Rejected)?;
            let writer: Option<String> = conn.query_row("SELECT writer FROM drafts WHERE draft_id = ?1", params![draft_id], |r| r.get(0)).optional().map_err(db_err)?.flatten();
            if org_role_of(conn, &jam, &me) != Some("owner") || writer.as_deref() == Some(me.as_str()) {
                return Err(StoreError::Rejected);
            }
            conn.execute("UPDATE drafts SET review = 'sent_back', review_note = ?2 WHERE draft_id = ?1", params![draft_id, note]).map_err(db_err)?;
            for who in active_authors(conn, &draft_id)?.iter().filter(|u| **u != me) {
                enqueue(conn, &draft_id, who, "draft.review", json!({ "draft_id": draft_id, "jam_id": jam, "state": "sent_back", "note": note }), now)?;
            }
            Ok(())
        })
    }
}
