//! Encrypted attachments on the client (LIME-98c, `docs/api-v2.md` section 6): sending, the chunked and resumable upload,
//! and the download. The file is encrypted on this phone (`store::attachments`); the server stores ciphertext chunks and
//! learns their sizes and timing. The key, digest, type, size, name and a tiny thumbnail travel only inside the
//! encrypted message.

use super::*;
use crate::store::attachments::{self as files, Descriptor};
use crate::store::link_preview::OutgoingPreview;

/// A file the app wants to send (already compressed, resized and stripped of metadata by the app).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct OutgoingAttachment {
    pub bytes: Vec<u8>,
    pub name: String,
    pub mime: String,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub duration_ms: Option<u32>,
    /// A tiny preview (JPEG, at most 2 KB), or empty.
    pub thumb: Vec<u8>,
}

/// How far a transfer has got.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct TransferProgress {
    /// An upload (otherwise a download).
    pub upload: bool,
    pub done: u32,
    pub total: u32,
}

/// Text that goes with attachments is shorter, so the whole message stays within one mailbox item.
const MAX_CAPTION_BYTES: usize = 8_000;
/// All descriptors together, as JSON, stay under this.
const MAX_DESCRIPTOR_BYTES: usize = 30_000;

#[uniffi::export]
impl LimeStore {
    /// Queues a message with 1 to 10 attachments and an optional caption. The files are kept here (the sender's own
    /// copy) and encrypted and uploaded at delivery, resuming if interrupted; the message follows once they are up.
    pub fn send_attachments(
        &self,
        conversation_id: String,
        caption: String,
        items: Vec<OutgoingAttachment>,
        reply_to: Option<String>,
    ) -> Result<MessageItem, StoreError> {
        if items.is_empty() || items.len() > files::MAX_PER_MESSAGE || caption.len() > MAX_CAPTION_BYTES {
            return Err(StoreError::Rejected);
        }
        let mut prepared = Vec::with_capacity(items.len());
        for item in items {
            if item.bytes.is_empty()
                || item.bytes.len() > files::MAX_BYTES
                || item.mime.is_empty()
                || item.mime.len() > 100
                || !item.mime.contains('/')
                || item.thumb.len() > 2048
            {
                return Err(StoreError::Rejected);
            }
            let descriptor = Descriptor {
                id: new_id(),
                key: files::new_key(),
                digest: files::digest_hex(&item.bytes),
                size: item.bytes.len() as u64,
                mime: item.mime,
                name: item.name.chars().filter(|c| !c.is_control() && *c != '/' && *c != '\\').take(255).collect(),
                width: item.width,
                height: item.height,
                duration_ms: item.duration_ms,
                thumb: item.thumb,
            };
            prepared.push((descriptor, item.bytes));
        }
        let descriptors: Vec<Descriptor> = prepared.iter().map(|(d, _)| d.clone()).collect();
        if files::payload_value(&descriptors).to_string().len() > MAX_DESCRIPTOR_BYTES {
            return Err(StoreError::Rejected);
        }
        self.queue_with(conversation_id, caption, reply_to, prepared, QueueExtras::default())
    }

    /// Whether the server still has an attachment, and until when (milliseconds since the Unix epoch). `None` means it is gone:
    /// a file nobody downloaded yet that cannot be had any more, so it cannot be fetched or forwarded.
    pub fn attachment_available_until(&self, transport: Arc<dyn Transport>, auth_token: String, attachment_id: String) -> Result<Option<i64>, StoreError> {
        let (status, body) = call(&transport, Some(&auth_token), "attachment", &json!({ "action": "info", "attachment_id": attachment_id }))?;
        if status == 404 {
            return Ok(None);
        }
        check(status)?;
        Ok(body.get("expires_at").and_then(Value::as_i64))
    }

    /// How far the upload or download of an attachment has got (chunks done and in all), while one is running.
    pub fn transfer_progress(&self, attachment_id: String) -> Result<Option<TransferProgress>, StoreError> {
        Ok(self.with_conn(|conn| files::progress(conn, &attachment_id))?.map(|(direction, done, total)| TransferProgress {
            upload: direction == "up",
            done: done as u32,
            total: total as u32,
        }))
    }

    /// The decrypted file, once this phone has it.
    pub fn attachment_data(&self, attachment_id: String) -> Result<Option<Vec<u8>>, StoreError> {
        self.with_conn(|conn| files::data(conn, &attachment_id))
    }

    /// Downloads, decrypts and verifies one attachment and keeps it (a no-op if this phone already has it). The file is
    /// refused, and nothing is kept, if a chunk was altered or its SHA-256 is not the one in the message.
    pub fn download_attachment(&self, transport: Arc<dyn Transport>, auth_token: String, attachment_id: String) -> Result<(), StoreError> {
        let Some((descriptor, held)) = self.with_conn(|conn| files::get(conn, &attachment_id))? else {
            return Err(StoreError::NotFound);
        };
        if held {
            return Ok(());
        }
        if self.with_conn(|conn| Ok(files::is_removed_everywhere(conn, &attachment_id)))? {
            return Err(StoreError::NotFound);
        }
        let (status, body) = call(&transport, Some(&auth_token), "attachment", &json!({ "action": "get", "attachment_id": descriptor.id }))?;
        if status == 404 {
            return Err(StoreError::NotFound);
        }
        check(status)?;
        let urls: Vec<&str> = body.get("urls").and_then(Value::as_array).ok_or(StoreError::BadMessage)?.iter().filter_map(Value::as_str).collect();
        if urls.is_empty() || urls.len() > 60 {
            return Err(StoreError::BadMessage);
        }
        // Chunks already fetched by an interrupted attempt are not fetched again.
        let total = urls.len();
        let mut have: std::collections::HashSet<usize> = self.with_conn(|conn| files::held_parts(conn, &descriptor.id))?.into_iter().collect();
        self.with_conn(|conn| files::set_progress(conn, &descriptor.id, "down", have.len().min(total), total))?;
        for (index, url) in urls.iter().enumerate() {
            if have.contains(&index) {
                continue;
            }
            let response = transport.request("GET".into(), (*url).into(), Vec::new(), Vec::new()).map_err(|_: TransportError| StoreError::Network)?;
            check(response.status)?;
            have.insert(index);
            self.with_conn(|conn| {
                files::save_part(conn, &descriptor.id, index, &response.body)?;
                files::set_progress(conn, &descriptor.id, "down", have.len(), total)
            })?;
        }
        let chunks = self.with_conn(|conn| files::parts(conn, &descriptor.id, total))?.ok_or(StoreError::BadMessage)?;
        let plaintext = files::open(&descriptor.key, &descriptor.id, &chunks);
        let verified = plaintext.as_ref().filter(|p| p.len() as u64 == descriptor.size && files::digest_hex(p) == descriptor.digest);
        let Some(plaintext) = verified else {
            // Something fetched is wrong: forget it all, so a retry starts from the server's copy, and keep nothing.
            self.with_conn(|conn| {
                files::drop_parts(conn, &descriptor.id)?;
                files::clear_progress(conn, &descriptor.id)
            })?;
            return Err(StoreError::BadMessage);
        };
        self.with_conn(|conn| {
            files::drop_parts(conn, &descriptor.id)?;
            files::clear_progress(conn, &descriptor.id)
        })?;
        self.with_conn(|conn| files::set_data(conn, &descriptor.id, plaintext))
    }
}

impl LimeStore {
    /// Encrypts and uploads every attachment of a queued message, chunk by chunk. Safe to repeat: the server says
    /// which chunks it already has, and the same chunks are computed again, so an interrupted upload resumes.
    pub(super) fn upload_message_attachments(&self, transport: &Arc<dyn Transport>, token: &str, message: &Queued, recipients: u32) -> Result<(), StoreError> {
        let preview_image = message.preview.as_ref().and_then(|(_, image)| image.as_ref());
        for descriptor in message.attachments.iter().chain(preview_image) {
            if message.forwarded {
                // A forward shares the file already on the server (the same encrypted chunks and key) with the new recipients.
                let (status, _) = call(transport, Some(token), "attachment", &json!({ "action": "share", "attachment_id": descriptor.id, "recipients": recipients.max(1) }))?;
                if status == 404 {
                    // The server's copy is gone (everyone had fetched it and an hour passed, or it expired): put it up again from the
                    // copy this phone holds, under the same id and key, so the forward goes ahead. Without a copy it cannot be forwarded.
                    self.upload_one(transport, token, descriptor, recipients)?;
                    continue;
                }
                check(status)?;
                continue;
            }
            self.upload_one(transport, token, descriptor, recipients)?;
        }
        Ok(())
    }

    /// Encrypts and uploads one attachment from the copy this phone holds (resuming if an earlier try was interrupted).
    fn upload_one(&self, transport: &Arc<dyn Transport>, token: &str, descriptor: &Descriptor, recipients: u32) -> Result<(), StoreError> {
        let Some(plaintext) = self.with_conn(|conn| files::data(conn, &descriptor.id))? else { return Err(StoreError::NotFound) };
        let chunks = files::seal(&descriptor.key, &descriptor.id, &plaintext);
        let total: usize = chunks.iter().map(Vec::len).sum();
        let (status, body) = call(
            transport,
            Some(token),
            "attachment",
            &json!({ "action": "put", "attachment_id": descriptor.id, "size": total, "chunks": chunks.len(), "recipients": recipients.max(1) }),
        )?;
        check(status)?;
        let urls = body.get("urls").and_then(Value::as_object).ok_or(StoreError::BadMessage)?;
        let already = chunks.len().saturating_sub(urls.len());
        self.with_conn(|conn| files::set_progress(conn, &descriptor.id, "up", already, chunks.len()))?;
        for (sent, (index, url)) in urls.iter().enumerate() {
            let n: usize = index.parse().map_err(|_| StoreError::BadMessage)?;
            let (url, chunk) = (url.as_str().ok_or(StoreError::BadMessage)?, chunks.get(n).ok_or(StoreError::BadMessage)?);
            let response = transport
                .request(
                    "PUT".into(),
                    url.into(),
                    vec![
                        HeaderPair { name: "content-type".into(), value: "application/octet-stream".into() },
                        HeaderPair { name: "cache-control".into(), value: "max-age=60".into() },
                    ],
                    chunk.clone(),
                )
                .map_err(|_: TransportError| StoreError::Network)?;
            check(response.status)?;
            self.with_conn(|conn| files::set_progress(conn, &descriptor.id, "up", already + sent + 1, chunks.len()))?;
        }
        let (status, _) = call(transport, Some(token), "attachment", &json!({ "action": "commit", "attachment_id": descriptor.id }))?;
        check(status)?;
        self.with_conn(|conn| files::clear_progress(conn, &descriptor.id))?;
        Ok(())
    }

    /// How many people will download a message's attachments: the other person of a chat, or the other members of a group.
    pub(super) fn attachment_recipients(&self, conversation_id: &str) -> u32 {
        self.with_conn(|conn| {
            let count: i64 = conn
                .query_row("SELECT count(*) FROM members WHERE conversation_id = ?1 AND person_id != ?2", params![conversation_id, ME_ID], |r| r.get(0))
                .map_err(db_err)?;
            Ok(count.max(1) as u32)
        })
        .unwrap_or(1)
    }
}

/// How many chats one forward may go to (anti-spam).
pub const MAX_FORWARD_TARGETS: usize = 5;

#[uniffi::export]
impl LimeStore {
    /// Forwards messages (oldest first) to up to five chats or groups. Each forward is a new message labelled forwarded, with no
    /// sign of who first wrote it; formatting is kept; files are shared by reference (the same encrypted file), so nothing is
    /// uploaded again. Deleted, unsent and system messages are skipped. Returns the new messages.
    pub fn forward_messages(&self, message_ids: Vec<String>, to_conversations: Vec<String>) -> Result<Vec<MessageItem>, StoreError> {
        if to_conversations.is_empty() || to_conversations.len() > MAX_FORWARD_TARGETS || message_ids.is_empty() || message_ids.len() > 50 {
            return Err(StoreError::Rejected);
        }
        let mut sources = Vec::new();
        for id in &message_ids {
            let source = self.with_conn(|conn| {
                conn.query_row(
                    "SELECT body, local_state, deleted, hidden, sent_at FROM messages WHERE id = ?1",
                    params![id],
                    |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, bool>(2)?, r.get::<_, bool>(3)?, r.get::<_, i64>(4)?)),
                )
                .optional()
                .map_err(db_err)
            })?;
            let Some((body, state, deleted, hidden, sent_at)) = source else { continue };
            if deleted || hidden || matches!(state.as_str(), "system" | "sending" | "failed") {
                continue;
            }
            let (files, preview) = self.with_conn(|conn| {
                let files = files::for_message(conn, id)?;
                let preview = crate::store::link_preview::meta_of(conn, id)
                    .map(|meta| (meta, files::preview_of(conn, id).ok().flatten().map(|(d, _)| d)));
                Ok((files, preview))
            })?;
            sources.push((sent_at, id.clone(), body, files, preview));
        }
        sources.sort_by_key(|(sent_at, id, ..)| (*sent_at, id.clone()));
        let mut out = Vec::new();
        for target in &to_conversations {
            for (_, _, body, files, preview) in &sources {
                let extras = QueueExtras {
                    forwarded: true,
                    shared: files.iter().map(|(d, _)| d.clone()).collect(),
                    // The picture is shared like a file: the bytes are copied from the original here.
                    preview: preview.clone().map(|(meta, image)| (meta, image.map(|d| (d, None)))),
                };
                out.push(self.queue_with(target.clone(), body.clone(), None, Vec::new(), extras)?);
            }
        }
        Ok(out)
    }
}

#[uniffi::export]
impl LimeStore {
    /// Queues a text message with a link card: the sender's phone built the preview (`preview`); its picture is encrypted and
    /// uploaded like an attachment, so nobody who reads the message visits the link.
    pub fn queue_text_with_preview(
        &self,
        conversation_id: String,
        text: String,
        reply_to: Option<String>,
        preview: OutgoingPreview,
    ) -> Result<MessageItem, StoreError> {
        let Some(meta) = crate::store::link_preview::Meta::new(&preview.url, &preview.title, &preview.site) else {
            return self.queue_with(conversation_id, text, reply_to, Vec::new(), QueueExtras::default());
        };
        if preview.image.len() > 200 * 1024 {
            return Err(StoreError::Rejected);
        }
        let image = (!preview.image.is_empty()).then(|| {
            let descriptor = Descriptor {
                id: new_id(),
                key: files::new_key(),
                digest: files::digest_hex(&preview.image),
                size: preview.image.len() as u64,
                mime: "image/jpeg".into(),
                name: String::new(),
                width: preview.image_width,
                height: preview.image_height,
                duration_ms: None,
                thumb: Vec::new(),
            };
            (descriptor, Some(preview.image.clone()))
        });
        self.queue_with(conversation_id, text, reply_to, Vec::new(), QueueExtras { forwarded: false, shared: Vec::new(), preview: Some((meta, image)) })
    }

    /// Makes sure my own chat exists (it is just a chat with myself, named with my name, kept on this phone only) and returns
    /// its id. Nothing is sent to the server for it.
    pub fn ensure_self_chat(&self, name: String) -> Result<String, StoreError> {
        let me = self.my_user_id_registered()?;
        self.with_conn(|conn| {
            let id = crate::client::ensure_dm(conn, &me, Some(&name))?;
            // A chat I deleted for myself comes back; and never a request.
            conn.execute("UPDATE conversations SET hidden = 0, request_state = 'accepted' WHERE id = ?1", params![id]).map_err(db_err)?;
            Ok(id)
        })
    }
}
