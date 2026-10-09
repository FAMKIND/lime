//! Encrypted attachments on the client (LIME-98c, `docs/api-v2.md` section 6): sending, the chunked and resumable upload,
//! and the download. The file is encrypted on this phone (`store::attachments`); the server stores ciphertext chunks and
//! learns their sizes and timing. The key, digest, type, size, name and a tiny thumbnail travel only inside the
//! encrypted message.

use super::*;
use crate::store::attachments::{self as files, Descriptor};

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
        self.queue_with(conversation_id, caption, reply_to, prepared)
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
        let (status, body) = call(&transport, Some(&auth_token), "attachment", &json!({ "action": "get", "attachment_id": descriptor.id }))?;
        if status == 404 {
            return Err(StoreError::NotFound);
        }
        check(status)?;
        let urls: Vec<&str> = body.get("urls").and_then(Value::as_array).ok_or(StoreError::BadMessage)?.iter().filter_map(Value::as_str).collect();
        if urls.is_empty() || urls.len() > 60 {
            return Err(StoreError::BadMessage);
        }
        let mut chunks = Vec::with_capacity(urls.len());
        for url in urls {
            let response = transport.request("GET".into(), url.into(), Vec::new(), Vec::new()).map_err(|_: TransportError| StoreError::Network)?;
            check(response.status)?;
            chunks.push(response.body);
        }
        let plaintext = files::open(&descriptor.key, &descriptor.id, &chunks).ok_or(StoreError::BadMessage)?;
        if plaintext.len() as u64 != descriptor.size || files::digest_hex(&plaintext) != descriptor.digest {
            return Err(StoreError::BadMessage);
        }
        self.with_conn(|conn| files::set_data(conn, &descriptor.id, &plaintext))
    }
}

impl LimeStore {
    /// Encrypts and uploads every attachment of a queued message, chunk by chunk. Safe to repeat: the server says
    /// which chunks it already has, and the same chunks are computed again, so an interrupted upload resumes.
    pub(super) fn upload_message_attachments(&self, transport: &Arc<dyn Transport>, token: &str, message: &Queued, recipients: u32) -> Result<(), StoreError> {
        for descriptor in &message.attachments {
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
            for (index, url) in urls {
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
            }
            let (status, _) = call(transport, Some(token), "attachment", &json!({ "action": "commit", "attachment_id": descriptor.id }))?;
            check(status)?;
        }
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
