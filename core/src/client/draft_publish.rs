//! Publishing a shared draft, "Ready", and pictures from any author (LIME-233e, DESIGN-22 section 5).
//!
//! Only the writer (the jam's owner) publishes; a co-author tells the writer they are done with `draft.ready`. A picture or video any author adds is
//! encrypted on their phone and uploaded once; its key and details go to the other authors inside the sealed `draft.file` op, so each author's editor
//! shows it and the writer's publish includes it. The server sees an encrypted blob and its size, like any attachment.

use super::draft_sync::{active_authors, enqueue, row_keys};
use super::*;
use crate::store::attachments::{self as files, Descriptor};
use crate::OutgoingAttachment;

/// A picture or video in a draft.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct DraftFileInfo {
    /// What the draft's image blocks call it.
    pub number: u32,
    pub mime: String,
    pub name: String,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub duration_ms: Option<u32>,
    pub thumb: Vec<u8>,
    pub poster: Vec<u8>,
    /// Who added it.
    pub adder: String,
    /// This phone has the file itself (otherwise `draft_file_data` fetches it).
    pub held: bool,
}

/// Where a draft stands between its authors and the published post.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct DraftStatus {
    /// The one who publishes (empty for a draft nobody shares).
    pub writer: String,
    pub is_writer: bool,
    /// The co-authors who said they are ready (the writer's view; everyone else sees their own).
    pub ready: Vec<String>,
    pub published_post: Option<String>,
    pub published_at: Option<i64>,
    pub published_by: Option<String>,
    /// The draft has changed since the last publish.
    pub changed_since_publish: bool,
}

fn heads_text(heads: &[String]) -> String {
    json!(heads).to_string()
}

const MAX_POSTER: usize = 30 * 1024;

#[uniffi::export]
impl LimeStore {
    /// The writer's phone has published (or updated) the post made from this draft by its own means (the article editor): the draft is linked to the
    /// post, and every author is told, with the draft's state at this moment, so "changes since the last publish" counts from here.
    pub fn draft_mark_published(&self, draft_id: String, post_id: String) -> Result<(), StoreError> {
        let me = self.load_or_create_account()?.user_id.ok_or(StoreError::NotRegistered)?;
        let now = now_ms();
        self.with_conn(|conn| {
            let writer: Option<String> = conn.query_row("SELECT writer FROM drafts WHERE draft_id = ?1", params![draft_id], |r| r.get(0)).optional().map_err(db_err)?.ok_or(StoreError::NotFound)?;
            if writer.as_deref().is_some_and(|w| w != me) || post_id.is_empty() || post_id.len() > 64 {
                return Err(StoreError::Rejected);
            }
            let heads = self.with_draft_conn(conn, &draft_id, false, |d| Ok(d.heads()))?;
            conn.execute(
                "UPDATE drafts SET post_id = ?2, published_post = ?2, published_at = ?3, published_by = ?4, published_heads = ?5 WHERE draft_id = ?1",
                params![draft_id, post_id, now, me, heads_text(&heads)],
            )
            .map_err(db_err)?;
            conn.execute("UPDATE draft_authors SET ready = 0 WHERE draft_id = ?1", params![draft_id]).map_err(db_err)?;
            for who in active_authors(conn, &draft_id)?.iter().filter(|u| **u != me) {
                enqueue(conn, &draft_id, who, "draft.published", json!({ "draft_id": draft_id, "post_id": post_id, "at": now, "heads": heads }), now)?;
            }
            Ok(())
        })
    }

    pub fn draft_status(&self, draft_id: String) -> Result<DraftStatus, StoreError> {
        let me = self.load_or_create_account()?.user_id;
        let (writer, post, at, by, published_heads, ready) = self.with_conn(|conn| {
            let row: Option<(Option<String>, Option<String>, Option<i64>, Option<String>, String)> = conn
                .query_row("SELECT writer, published_post, published_at, published_by, published_heads FROM drafts WHERE draft_id = ?1", params![draft_id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?)))
                .optional()
                .map_err(db_err)?;
            let Some((writer, post, at, by, heads)) = row else { return Err(StoreError::NotFound) };
            let mut st = conn.prepare("SELECT user_id FROM draft_authors WHERE draft_id = ?1 AND status = 'active' AND ready = 1 ORDER BY user_id").map_err(db_err)?;
            let ready: Vec<String> = st.query_map(params![draft_id], |r| r.get(0)).map_err(db_err)?.collect::<Result<_, _>>().map_err(db_err)?;
            Ok((writer, post, at, by, heads, ready))
        })?;
        let changed = if at.is_some() {
            let heads = self.with_conn(|conn| self.with_draft_conn(conn, &draft_id, false, |d| Ok(d.heads())))?;
            serde_json::from_str::<Vec<String>>(&published_heads).unwrap_or_default() != heads
        } else {
            false
        };
        Ok(DraftStatus { is_writer: writer.is_none() || writer == me, writer: writer.unwrap_or_default(), ready, published_post: post, published_at: at, published_by: by, changed_since_publish: changed })
    }

    /// A co-author tells the writer they are done (or takes it back). The writer's `draft_status` lists them under `ready`.
    pub fn draft_set_ready(&self, draft_id: String, ready: bool) -> Result<(), StoreError> {
        let me = self.load_or_create_account()?.user_id.ok_or(StoreError::NotRegistered)?;
        let now = now_ms();
        self.with_conn(|conn| {
            let writer: Option<String> = conn.query_row("SELECT writer FROM drafts WHERE draft_id = ?1", params![draft_id], |r| r.get(0)).optional().map_err(db_err)?.ok_or(StoreError::NotFound)?;
            let Some(writer) = writer.filter(|w| *w != me) else { return Err(StoreError::Rejected) };
            if !active_authors(conn, &draft_id)?.contains(&me) {
                return Err(StoreError::Rejected);
            }
            conn.execute("UPDATE draft_authors SET ready = ?3 WHERE draft_id = ?1 AND user_id = ?2", params![draft_id, me, ready]).map_err(db_err)?;
            enqueue(conn, &draft_id, &writer, "draft.ready", json!({ "draft_id": draft_id, "ready": ready }), now)
        })
    }

    // ------------------------------------------------------------------------------------------------------ files

    /// Adds a picture or video to the draft (any author). It is kept here, encrypted and uploaded once the draft is shared (the next flush), and its
    /// key goes to the other authors. Returns the number an image block uses (`draft_insert_block` with `attachment` set to it).
    pub fn draft_add_file(&self, draft_id: String, file: OutgoingAttachment) -> Result<u32, StoreError> {
        if file.bytes.is_empty() || file.bytes.len() > files::MAX_BYTES || !file.mime.contains('/') || file.mime.len() > 100 || file.thumb.len() > 2048 || file.poster.len() > MAX_POSTER {
            return Err(StoreError::Rejected);
        }
        let me = self.load_or_create_account()?.user_id.unwrap_or_default();
        self.with_conn(|conn| {
            let exists: bool = conn.query_row("SELECT EXISTS (SELECT 1 FROM drafts WHERE draft_id = ?1)", params![draft_id], |r| r.get(0)).map_err(db_err)?;
            if !exists {
                return Err(StoreError::NotFound);
            }
            let count: i64 = conn.query_row("SELECT COUNT(*) FROM draft_files WHERE draft_id = ?1", params![draft_id], |r| r.get(0)).map_err(db_err)?;
            if count as usize >= files::MAX_PER_MESSAGE {
                return Err(StoreError::Rejected);
            }
            // A number no other author is likely to pick at the same time.
            let mut number;
            loop {
                let mut random = [0u8; 4];
                getrandom::getrandom(&mut random).map_err(|_| StoreError::BadMessage)?;
                number = 1000 + u32::from_le_bytes(random) % 1_000_000;
                let taken: bool = conn.query_row("SELECT EXISTS (SELECT 1 FROM draft_files WHERE draft_id = ?1 AND number = ?2)", params![draft_id, number], |r| r.get(0)).map_err(db_err)?;
                if !taken {
                    break;
                }
            }
            let key = files::new_key();
            conn.execute(
                "INSERT INTO draft_files (draft_id, number, file_id, adder, key, digest, size, mime, name, width, height, duration_ms, thumb, poster, bytes, uploaded, announced)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, 0, '[]')",
                params![draft_id, number, new_id(), me, key, files::digest_hex(&file.bytes), file.bytes.len() as i64, file.mime, file.name, file.width, file.height, file.duration_ms, file.thumb, file.poster, file.bytes],
            )
            .map_err(db_err)?;
            Ok(number)
        })
    }

    /// The pictures and videos of a draft.
    pub fn draft_files(&self, draft_id: String) -> Result<Vec<DraftFileInfo>, StoreError> {
        self.with_conn(|conn| {
            let mut st = conn
                .prepare("SELECT number, mime, name, width, height, duration_ms, thumb, poster, adder, bytes IS NOT NULL FROM draft_files WHERE draft_id = ?1 ORDER BY rowid")
                .map_err(db_err)?;
            let rows = st
                .query_map(params![draft_id], |r| {
                    Ok(DraftFileInfo { number: r.get(0)?, mime: r.get(1)?, name: r.get(2)?, width: r.get(3)?, height: r.get(4)?, duration_ms: r.get(5)?, thumb: r.get(6)?, poster: r.get(7)?, adder: r.get(8)?, held: r.get(9)? })
                })
                .map_err(db_err)?;
            rows.collect::<Result<_, _>>().map_err(db_err)
        })
    }

    /// The file's bytes, fetched and decrypted if this phone does not have them yet.
    pub fn draft_file_data(&self, transport: Arc<dyn Transport>, auth_token: String, draft_id: String, number: u32) -> Result<Vec<u8>, StoreError> {
        let row: Option<(Vec<u8>, String, String, i64, String, String, Option<u32>, Option<u32>, Option<u32>, Vec<u8>, Vec<u8>, Option<Vec<u8>>)> = self.with_conn(|conn| {
            conn.query_row(
                "SELECT key, file_id, digest, size, mime, name, width, height, duration_ms, thumb, poster, bytes FROM draft_files WHERE draft_id = ?1 AND number = ?2",
                params![draft_id, number],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?, r.get(6)?, r.get(7)?, r.get(8)?, r.get(9)?, r.get(10)?, r.get(11)?)),
            )
            .optional()
            .map_err(db_err)
        })?;
        let Some((key, id, digest, size, mime, name, width, height, duration_ms, thumb, poster, bytes)) = row else { return Err(StoreError::NotFound) };
        if let Some(bytes) = bytes {
            return Ok(bytes);
        }
        let descriptor = Descriptor { id, key, digest, size: size as u64, mime, name, width, height, duration_ms, thumb, poster };
        let plain = self.download_blob(&transport, &auth_token, &descriptor)?;
        self.with_conn(|conn| conn.execute("UPDATE draft_files SET bytes = ?3 WHERE draft_id = ?1 AND number = ?2", params![draft_id, number, plain]).map(|_| ()).map_err(db_err))?;
        Ok(plain)
    }

    /// The writer publishes the draft as an article of their jam: its words as they are now, its pictures (any author's) as the post's files numbered
    /// from 0 in the order they appear. Files this phone does not have yet are fetched first. The draft is linked to the post, and every author is told.
    #[allow(clippy::too_many_arguments)]
    pub fn publish_draft(&self, transport: Arc<dyn Transport>, auth_token: String, draft_id: String, jam_id: String, coauthors: Vec<String>, display_as: String) -> Result<String, StoreError> {
        self.publish_draft_with(transport, auth_token, draft_id, jam_id, coauthors, display_as, super::jam::PostOptions { audience: "subscribers".into(), series: None, topics: vec![] })
    }

    /// `publish_draft` with the post's audience and series (LIME-210b): a co-written article goes out through the same path as any other post, so
    /// *Everyone* and a `[[freewall]]` Preview work for it too. Only the writer publishes, so the open copy is signed by the writer's device.
    #[allow(clippy::too_many_arguments)]
    pub fn publish_draft_with(&self, transport: Arc<dyn Transport>, auth_token: String, draft_id: String, jam_id: String, coauthors: Vec<String>, display_as: String, options: super::jam::PostOptions) -> Result<String, StoreError> {
        let state = self.load_or_create_account()?;
        let me = state.user_id.clone().filter(|_| state.registered).ok_or(StoreError::NotRegistered)?;
        let writer: Option<String> = self.with_conn(|conn| conn.query_row("SELECT writer FROM drafts WHERE draft_id = ?1", params![draft_id], |r| r.get(0)).optional().map_err(db_err)?.ok_or(StoreError::NotFound))?;
        if writer.as_deref().is_some_and(|w| w != me) {
            return Err(StoreError::Rejected);
        }
        let (meta, numbers) = self.with_conn(|conn| self.with_draft_conn(conn, &draft_id, false, |d| Ok((d.meta(), d.image_numbers()))))?;
        let mut attachments = Vec::new();
        for number in &numbers {
            let info = self.draft_files(draft_id.clone())?.into_iter().find(|f| f.number == *number).ok_or(StoreError::Rejected)?;
            let bytes = self.draft_file_data(transport.clone(), auth_token.clone(), draft_id.clone(), *number)?;
            attachments.push(OutgoingAttachment { bytes, name: info.name, mime: info.mime, width: info.width, height: info.height, duration_ms: info.duration_ms, thumb: info.thumb, poster: info.poster });
        }
        let markdown = self.with_conn(|conn| self.with_draft_conn(conn, &draft_id, false, |d| Ok(d.export_markdown_numbered(&|n| numbers.iter().position(|x| *x == n).unwrap_or(0) as u32))))?;
        let post_id = self.publish_jam_post_with(jam_id, "article".into(), meta.title, meta.subtitle, markdown, "free".into(), attachments, coauthors, display_as, options)?;
        self.draft_mark_published(draft_id, post_id.clone())?;
        Ok(post_id)
    }
}

impl LimeStore {
    /// Uploads the files I added to shared drafts and tells each author about them once. Called with the rest of the draft delivery.
    pub(crate) fn upload_draft_files(&self, transport: &Arc<dyn Transport>, token: &str, me: &str, now: i64) {
        type Row = (String, u32, String, Vec<u8>, String, i64, String, String, Option<u32>, Option<u32>, Option<u32>, Vec<u8>, Vec<u8>, Option<Vec<u8>>, bool, String);
        let Ok(rows) = self.with_conn(|conn| {
            let mut st = conn
                .prepare(
                    "SELECT draft_id, number, file_id, key, digest, size, mime, name, width, height, duration_ms, thumb, poster, bytes, uploaded, announced FROM draft_files WHERE adder = ?1",
                )
                .map_err(db_err)?;
            let rows = st
                .query_map(params![me], |r| {
                    Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?, r.get(6)?, r.get(7)?, r.get(8)?, r.get(9)?, r.get(10)?, r.get(11)?, r.get(12)?, r.get(13)?, r.get(14)?, r.get(15)?))
                })
                .map_err(db_err)?;
            rows.collect::<Result<Vec<Row>, _>>().map_err(db_err)
        }) else {
            return;
        };
        for (draft_id, number, id, key, digest, size, mime, name, width, height, duration_ms, thumb, poster, bytes, uploaded, announced) in rows {
            // Only drafts that are shared (a channel exists) with someone besides me.
            let Ok((others, shared)) = self.with_conn(|conn| {
                let others: Vec<String> = active_authors(conn, &draft_id)?.into_iter().filter(|u| u != me).collect();
                Ok((others, row_keys(conn, &draft_id)?.is_some()))
            }) else {
                continue;
            };
            if !shared || others.is_empty() {
                continue;
            }
            let descriptor = Descriptor { id, key, digest, size: size as u64, mime, name, width, height, duration_ms, thumb, poster };
            if !uploaded {
                let Some(bytes) = bytes else { continue };
                if self.upload_blob(transport, token, &descriptor, &bytes, others.len() as u32).is_err() {
                    continue;
                }
                let _ = self.with_conn(|conn| conn.execute("UPDATE draft_files SET uploaded = 1 WHERE draft_id = ?1 AND number = ?2", params![draft_id, number]).map(|_| ()).map_err(db_err));
            }
            let mut told: Vec<String> = serde_json::from_str(&announced).unwrap_or_default();
            let fresh: Vec<&String> = others.iter().filter(|u| !told.contains(u)).collect();
            if fresh.is_empty() {
                continue;
            }
            let _ = self.with_conn(|conn| {
                for who in &fresh {
                    enqueue(conn, &draft_id, who, "draft.file", json!({ "draft_id": draft_id, "number": number, "file": descriptor.to_json() }), now)?;
                }
                Ok(())
            });
            told.extend(fresh.into_iter().cloned());
            let _ = self.with_conn(|conn| conn.execute("UPDATE draft_files SET announced = ?3 WHERE draft_id = ?1 AND number = ?2", params![draft_id, number, json!(told).to_string()]).map(|_| ()).map_err(db_err));
        }
    }

    /// The `draft.ready`, `draft.published` and `draft.file` ops (the others are in `draft_sync`). Runs inside the receive transaction.
    pub(crate) fn apply_draft_publish_op(&self, conn: &Connection, me: &str, sender: &str, op_type: &str, payload: &Value) -> Result<(), StoreError> {
        let Some(draft_id) = payload.get("draft_id").and_then(Value::as_str).filter(|d| !d.is_empty() && d.len() <= 64) else { return Ok(()) };
        let writer: Option<String> = conn.query_row("SELECT writer FROM drafts WHERE draft_id = ?1", params![draft_id], |r| r.get(0)).optional().map_err(db_err)?.flatten();
        let authors = active_authors(conn, draft_id)?;
        match op_type {
            "draft.ready" => {
                if writer.as_deref() == Some(me) && authors.iter().any(|u| u == sender) && sender != me {
                    let ready = payload.get("ready").and_then(Value::as_bool).unwrap_or(false);
                    conn.execute("UPDATE draft_authors SET ready = ?3 WHERE draft_id = ?1 AND user_id = ?2", params![draft_id, sender, ready]).map_err(db_err)?;
                }
            }
            "draft.published" => {
                if writer.as_deref() == Some(sender) {
                    let post = payload.get("post_id").and_then(Value::as_str).unwrap_or_default();
                    let at = payload.get("at").and_then(Value::as_i64).unwrap_or(0);
                    let heads: Vec<String> = payload.get("heads").and_then(Value::as_array).map(|a| a.iter().filter_map(|h| h.as_str().map(str::to_owned)).collect()).unwrap_or_default();
                    if !post.is_empty() && post.len() <= 64 {
                        conn.execute(
                            "UPDATE drafts SET published_post = ?2, published_at = ?3, published_by = ?4, published_heads = ?5 WHERE draft_id = ?1",
                            params![draft_id, post, at, sender, heads_text(&heads)],
                        )
                        .map_err(db_err)?;
                        conn.execute("UPDATE draft_authors SET ready = 0 WHERE draft_id = ?1", params![draft_id]).map_err(db_err)?;
                    }
                }
            }
            "draft.file" => {
                if !authors.iter().any(|u| u == sender) || sender == me {
                    return Ok(());
                }
                let Some(number) = payload.get("number").and_then(Value::as_u64).and_then(|n| u32::try_from(n).ok()) else { return Ok(()) };
                let Some(d) = payload.get("file").and_then(Descriptor::parse) else { return Ok(()) };
                let count: i64 = conn.query_row("SELECT COUNT(*) FROM draft_files WHERE draft_id = ?1", params![draft_id], |r| r.get(0)).map_err(db_err)?;
                if count as usize >= files::MAX_PER_MESSAGE {
                    return Ok(());
                }
                conn.execute(
                    "INSERT OR IGNORE INTO draft_files (draft_id, number, file_id, adder, key, digest, size, mime, name, width, height, duration_ms, thumb, poster, bytes, uploaded, announced)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, NULL, 1, '[]')",
                    params![draft_id, number, d.id, sender, d.key, d.digest, d.size as i64, d.mime, d.name, d.width, d.height, d.duration_ms, d.thumb, d.poster],
                )
                .map_err(db_err)?;
            }
            "draft.delete" => {
                // The writer removed the draft for everyone: it goes from this phone (a published post is not touched).
                if writer.as_deref() == Some(sender) && sender != me {
                    self.draft_cache.lock().unwrap_or_else(|e| e.into_inner()).remove(draft_id);
                    super::drafts::purge_draft_rows(conn, draft_id)?;
                }
            }
            _ => {}
        }
        Ok(())
    }
}
