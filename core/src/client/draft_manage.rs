//! Managing drafts from jam's Drafts list (LIME-237): copy, delete for everyone, leave.

use super::draft_sync::{active_authors, enqueue};
use super::*;

#[uniffi::export]
impl LimeStore {
    /// A new private draft with the same title and words (only the caller is an author). The pictures this phone holds are copied too.
    pub fn copy_draft(&self, draft_id: String) -> Result<String, StoreError> {
        let (meta, markdown) = self.with_conn(|conn| self.with_draft_conn(conn, &draft_id, false, |d| Ok((d.meta(), d.export_markdown()))))?;
        let copy = self.create_draft(meta.title, meta.subtitle, markdown)?;
        let me = self.load_or_create_account()?.user_id.unwrap_or_default();
        self.with_conn(|conn| {
            conn.execute(
                "INSERT INTO draft_files (draft_id, number, file_id, adder, key, digest, size, mime, name, width, height, duration_ms, thumb, poster, bytes, uploaded, announced)
                 SELECT ?2, number, file_id, ?3, key, digest, size, mime, name, width, height, duration_ms, thumb, poster, bytes, 0, '[]' FROM draft_files WHERE draft_id = ?1 AND bytes IS NOT NULL",
                params![draft_id, copy, me],
            )
            .map(|_| ())
            .map_err(db_err)
        })?;
        Ok(copy)
    }

    /// The writer deletes a draft for everyone (each other author is sent `draft.delete`); a draft nobody else writes in just goes. A co-author is
    /// refused (they `leave_and_delete_draft`). A published post is never touched.
    pub fn delete_draft_for_everyone(&self, draft_id: String) -> Result<(), StoreError> {
        let me = self.load_or_create_account()?.user_id.unwrap_or_default();
        let now = now_ms();
        let others = self.with_conn(|conn| {
            let writer: Option<String> = conn.query_row("SELECT writer FROM drafts WHERE draft_id = ?1", params![draft_id], |r| r.get(0)).optional().map_err(db_err)?.ok_or(StoreError::NotFound)?;
            if writer.as_deref().is_some_and(|w| w != me) {
                return Err(StoreError::Rejected);
            }
            let others: Vec<String> = if writer.is_some() { active_authors(conn, &draft_id)?.into_iter().filter(|u| *u != me).collect() } else { Vec::new() };
            for who in &others {
                enqueue(conn, &draft_id, who, "draft.delete", json!({ "draft_id": draft_id }), now)?;
            }
            if !others.is_empty() {
                conn.execute("UPDATE drafts SET deleted = 1 WHERE draft_id = ?1", params![draft_id]).map_err(db_err)?;
            }
            Ok(others)
        })?;
        if others.is_empty() {
            self.delete_draft(draft_id)?;
        }
        Ok(())
    }

    /// A co-author takes their copy away and leaves the draft group (the others keep writing).
    pub fn leave_and_delete_draft(&self, draft_id: String) -> Result<(), StoreError> {
        self.leave_draft(draft_id.clone())?;
        self.with_conn(|conn| conn.execute("UPDATE drafts SET deleted = 1 WHERE draft_id = ?1", params![draft_id]).map(|_| ()).map_err(db_err))
    }
}

impl LimeStore {
    /// Drafts being removed whose goodbyes have all gone are now removed for good.
    pub(crate) fn purge_sent_deleted_drafts(&self) {
        let Ok(ids) = self.with_conn(|conn| {
            let mut st = conn.prepare("SELECT draft_id FROM drafts WHERE deleted = 1 AND draft_id NOT IN (SELECT draft_id FROM draft_outbox)").map_err(db_err)?;
            let rows = st.query_map([], |r| r.get::<_, String>(0)).map_err(db_err)?;
            rows.collect::<Result<Vec<_>, _>>().map_err(db_err)
        }) else {
            return;
        };
        for id in ids {
            let _ = self.delete_draft(id);
        }
    }
}
