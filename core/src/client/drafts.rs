//! Drafts written with others (LIME-233a): the document in the store, and the calls the editor makes. The rules of the document itself are in
//! [`crate::drafts`]; this is persistence (a snapshot plus incremental chunks, folded after 200 changes) and the UniFFI surface.

use super::*;
use crate::drafts::{DraftBlock, DraftBlockInput, DraftDoc, DraftMeta, DraftPatch, COMPACT_AFTER_CHANGES};

/// One draft in a list.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct DraftInfo {
    pub draft_id: String,
    pub title: String,
    /// The published post this draft is the draft of, if any.
    pub post_id: Option<String>,
    pub updated_at: i64,
}

fn load_draft_conn(conn: &Connection, draft_id: &str) -> Result<DraftDoc, StoreError> {
    let snapshot: Vec<u8> = conn.query_row("SELECT snapshot FROM drafts WHERE draft_id = ?1", params![draft_id], |r| r.get(0)).optional().map_err(db_err)?.ok_or(StoreError::NotFound)?;
    let mut st = conn.prepare("SELECT bytes FROM draft_chunks WHERE draft_id = ?1 ORDER BY seq").map_err(db_err)?;
    let chunks: Vec<Vec<u8>> = st.query_map(params![draft_id], |r| r.get::<_, Vec<u8>>(0)).map_err(db_err)?.collect::<Result<_, _>>().map_err(db_err)?;
    let mut doc = DraftDoc::load(&snapshot)?;
    for chunk in chunks {
        doc.apply_changes(&chunk)?;
    }
    doc.mark_seen();
    Ok(doc)
}

impl LimeStore {
    /// Runs `work` on the open draft (loaded on first use); what it changed is saved before this returns. `local`: the edit came from the editor, which
    /// has drawn it already (so it is not a patch to apply); remote changes stay patches until [`draft_take_patches`] hands them over.
    pub(crate) fn with_draft_conn<T>(&self, conn: &Connection, draft_id: &str, local: bool, work: impl FnOnce(&mut DraftDoc) -> Result<T, StoreError>) -> Result<T, StoreError> {
        let mut cache = self.draft_cache.lock().unwrap_or_else(|e| e.into_inner());
        if !cache.contains_key(draft_id) {
            let doc = load_draft_conn(conn, draft_id)?;
            cache.insert(draft_id.to_owned(), doc);
        }
        let doc = cache.get_mut(draft_id).expect("just inserted");
        let result = work(doc);
        let bytes = doc.save_incremental();
        if !bytes.is_empty() {
            if local {
                doc.mark_seen();
            }
            let now = now_ms();
            let changes: u32 = conn.query_row("SELECT changes FROM drafts WHERE draft_id = ?1", params![draft_id], |r| r.get(0)).map_err(db_err)?;
            if changes + 1 >= COMPACT_AFTER_CHANGES {
                let whole = doc.save();
                let tx = conn.unchecked_transaction().map_err(db_err)?;
                tx.execute("UPDATE drafts SET snapshot = ?2, changes = 0, updated_at = ?3 WHERE draft_id = ?1", params![draft_id, whole, now]).map_err(db_err)?;
                tx.execute("DELETE FROM draft_chunks WHERE draft_id = ?1", params![draft_id]).map_err(db_err)?;
                tx.commit().map_err(db_err)?;
            } else {
                let tx = conn.unchecked_transaction().map_err(db_err)?;
                let seq: i64 = tx.query_row("SELECT COALESCE(MAX(seq), 0) + 1 FROM draft_chunks WHERE draft_id = ?1", params![draft_id], |r| r.get(0)).map_err(db_err)?;
                tx.execute("INSERT INTO draft_chunks (draft_id, seq, bytes) VALUES (?1, ?2, ?3)", params![draft_id, seq, bytes]).map_err(db_err)?;
                tx.execute("UPDATE drafts SET changes = changes + 1, updated_at = ?2 WHERE draft_id = ?1", params![draft_id, now]).map_err(db_err)?;
                tx.commit().map_err(db_err)?;
            }
        }
        result
    }

    /// A local edit.
    pub(crate) fn with_draft<T>(&self, draft_id: &str, work: impl FnOnce(&mut DraftDoc) -> Result<T, StoreError>) -> Result<T, StoreError> {
        self.with_conn(|conn| self.with_draft_conn(conn, draft_id, true, work))
    }

    fn insert_draft(&self, draft_id: &str, doc: &mut DraftDoc) -> Result<(), StoreError> {
        let now = now_ms();
        let snapshot = doc.save();
        doc.mark_seen();
        self.with_conn(|conn| {
            conn.execute("INSERT OR REPLACE INTO drafts (draft_id, snapshot, post_id, changes, created_at, updated_at) VALUES (?1, ?2, NULL, 0, ?3, ?3)", params![draft_id, snapshot, now]).map_err(db_err)?;
            conn.execute("DELETE FROM draft_chunks WHERE draft_id = ?1", params![draft_id]).map_err(db_err)?;
            Ok(())
        })
    }
}

#[uniffi::export]
impl LimeStore {
    /// Starts a draft, from nothing or from a post's Markdown.
    pub fn create_draft(&self, title: String, subtitle: String, markdown: String) -> Result<String, StoreError> {
        let mut doc = DraftDoc::from_markdown(&title, &subtitle, &markdown)?;
        let id = new_id();
        self.insert_draft(&id, &mut doc)?;
        self.draft_cache.lock().unwrap_or_else(|e| e.into_inner()).insert(id.clone(), doc);
        Ok(id)
    }

    /// A draft joined from another author's snapshot (an invitation, or a late joiner).
    pub fn join_draft(&self, draft_id: String, snapshot: Vec<u8>) -> Result<(), StoreError> {
        let mut doc = DraftDoc::load(&snapshot)?;
        self.insert_draft(&draft_id, &mut doc)?;
        self.draft_cache.lock().unwrap_or_else(|e| e.into_inner()).insert(draft_id, doc);
        Ok(())
    }

    pub fn delete_draft(&self, draft_id: String) -> Result<(), StoreError> {
        self.draft_cache.lock().unwrap_or_else(|e| e.into_inner()).remove(&draft_id);
        self.with_conn(|conn| {
            conn.execute("DELETE FROM draft_chunks WHERE draft_id = ?1", params![draft_id]).map_err(db_err)?;
            conn.execute("DELETE FROM draft_files WHERE draft_id = ?1", params![draft_id]).map_err(db_err)?;
            conn.execute("DELETE FROM draft_authors WHERE draft_id = ?1", params![draft_id]).map_err(db_err)?;
            conn.execute("DELETE FROM draft_outbox WHERE draft_id = ?1", params![draft_id]).map_err(db_err)?;
            conn.execute("DELETE FROM drafts WHERE draft_id = ?1", params![draft_id]).map_err(db_err)?;
            Ok(())
        })
    }

    pub fn list_drafts(&self) -> Result<Vec<DraftInfo>, StoreError> {
        let rows: Vec<(String, Option<String>, i64)> = self.with_conn(|conn| {
            let mut st = conn.prepare("SELECT draft_id, post_id, updated_at FROM drafts ORDER BY updated_at DESC").map_err(db_err)?;
            let rows = st.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).map_err(db_err)?;
            rows.collect::<Result<_, _>>().map_err(db_err)
        })?;
        rows.into_iter().map(|(draft_id, post_id, updated_at)| Ok(DraftInfo { title: self.with_draft(&draft_id, |d| Ok(d.meta().title))?, draft_id, post_id, updated_at })).collect()
    }

    /// Marks a draft as the draft of a published post.
    pub fn draft_link_post(&self, draft_id: String, post_id: String) -> Result<(), StoreError> {
        self.with_conn(|conn| conn.execute("UPDATE drafts SET post_id = ?2 WHERE draft_id = ?1", params![draft_id, post_id]).map(|_| ()).map_err(db_err))
    }

    pub fn draft_blocks(&self, draft_id: String) -> Result<Vec<DraftBlock>, StoreError> {
        self.with_draft(&draft_id, |d| Ok(d.blocks()))
    }

    pub fn draft_meta(&self, draft_id: String) -> Result<DraftMeta, StoreError> {
        self.with_draft(&draft_id, |d| Ok(d.meta()))
    }

    pub fn draft_markdown(&self, draft_id: String) -> Result<String, StoreError> {
        self.with_draft(&draft_id, |d| Ok(d.export_markdown()))
    }

    pub fn draft_import_markdown(&self, draft_id: String, markdown: String) -> Result<(), StoreError> {
        self.with_draft(&draft_id, |d| d.import_markdown(&markdown))
    }

    /// Makes the draft say what the editor shows (post Markdown) with the fewest operations: a typed letter is one small insert.
    pub fn draft_reconcile(&self, draft_id: String, title: String, subtitle: String, markdown: String) -> Result<(), StoreError> {
        self.with_draft(&draft_id, |d| {
            let meta = d.meta();
            if meta.title != title {
                d.set_title(&title)?;
            }
            if meta.subtitle != subtitle {
                d.set_subtitle(&subtitle)?;
            }
            d.reconcile(&markdown)
        })
    }

    /// The editor changed from the draft as it was at `base` (the heads returned last time): its edits are merged with whatever other authors wrote since,
    /// and the draft's heads now are returned. The editor then shows the merged draft.
    pub fn draft_merge_editor(&self, draft_id: String, base: Vec<String>, title: String, subtitle: String, markdown: String) -> Result<Vec<String>, StoreError> {
        self.with_draft(&draft_id, |d| {
            d.reconcile_from(&base, &title, &subtitle, &markdown)?;
            Ok(d.heads())
        })
    }

    pub fn draft_set_title(&self, draft_id: String, title: String) -> Result<(), StoreError> {
        self.with_draft(&draft_id, |d| d.set_title(&title))
    }

    pub fn draft_set_subtitle(&self, draft_id: String, subtitle: String) -> Result<(), StoreError> {
        self.with_draft(&draft_id, |d| d.set_subtitle(&subtitle))
    }

    pub fn draft_set_cover(&self, draft_id: String, file_id: String) -> Result<(), StoreError> {
        self.with_draft(&draft_id, |d| d.set_cover(&file_id))
    }

    pub fn draft_insert_text(&self, draft_id: String, block_id: String, at: u32, text: String) -> Result<(), StoreError> {
        self.with_draft(&draft_id, |d| d.insert_text(&block_id, at as usize, &text))
    }

    pub fn draft_delete_text(&self, draft_id: String, block_id: String, at: u32, count: u32) -> Result<(), StoreError> {
        self.with_draft(&draft_id, |d| d.delete_text(&block_id, at as usize, count as usize))
    }

    /// Styles part of a block: `bold`, `italic`, `underline`, `strike`, `code`, or `link` / `mention` with a value.
    pub fn draft_mark(&self, draft_id: String, block_id: String, start: u32, end: u32, name: String, value: Option<String>) -> Result<(), StoreError> {
        self.with_draft(&draft_id, |d| d.mark(&block_id, start as usize, end as usize, &name, value.as_deref()))
    }

    pub fn draft_unmark(&self, draft_id: String, block_id: String, start: u32, end: u32, name: String) -> Result<(), StoreError> {
        self.with_draft(&draft_id, |d| d.unmark(&block_id, start as usize, end as usize, &name))
    }

    pub fn draft_set_block_kind(&self, draft_id: String, block_id: String, kind: String, level: u32, ordered: bool, number: u32) -> Result<(), StoreError> {
        self.with_draft(&draft_id, |d| d.set_block_kind(&block_id, &kind, level, ordered, number))
    }

    pub fn draft_set_block_attrs(&self, draft_id: String, block_id: String, url: String, caption: String, colour: String, attachment: u32) -> Result<(), StoreError> {
        self.with_draft(&draft_id, |d| d.set_block_attrs(&block_id, &url, &caption, &colour, attachment))
    }

    /// Puts a block at `index`; returns its id.
    pub fn draft_insert_block(&self, draft_id: String, index: u32, block: DraftBlockInput) -> Result<String, StoreError> {
        self.with_draft(&draft_id, |d| d.insert_block(index as usize, &block))
    }

    pub fn draft_move_block(&self, draft_id: String, block_id: String, to: u32) -> Result<(), StoreError> {
        self.with_draft(&draft_id, |d| d.move_block(&block_id, to as usize))
    }

    pub fn draft_delete_block(&self, draft_id: String, block_id: String) -> Result<(), StoreError> {
        self.with_draft(&draft_id, |d| d.delete_block(&block_id))
    }

    /// The draft's heads (hex), to say what this replica has.
    pub fn draft_heads(&self, draft_id: String) -> Result<Vec<String>, StoreError> {
        self.with_draft(&draft_id, |d| Ok(d.heads()))
    }

    /// What a replica with `heads` lacks (everything when none of them is known here).
    pub fn draft_changes_since(&self, draft_id: String, heads: Vec<String>) -> Result<Vec<u8>, StoreError> {
        self.with_draft(&draft_id, |d| Ok(d.changes_since(&heads)))
    }

    /// Applies another author's changes (or a snapshot) and returns what the editor must apply.
    pub fn draft_apply_changes(&self, draft_id: String, bytes: Vec<u8>) -> Result<Vec<DraftPatch>, StoreError> {
        self.with_conn(|conn| self.with_draft_conn(conn, &draft_id, false, |d| { d.apply_changes(&bytes)?; Ok(d.take_patches()) }))
    }

    /// What changed in the draft since the editor last looked (changes that arrived from other authors meanwhile), in the order to apply.
    pub fn draft_take_patches(&self, draft_id: String) -> Result<Vec<DraftPatch>, StoreError> {
        self.with_conn(|conn| self.with_draft_conn(conn, &draft_id, false, |d| Ok(d.take_patches())))
    }

    /// The whole draft as one document.
    pub fn draft_snapshot(&self, draft_id: String) -> Result<Vec<u8>, StoreError> {
        self.with_draft(&draft_id, |d| Ok(d.save()))
    }
}
