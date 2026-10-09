//! Link preview cards (LIME-106): the sender's phone builds one (title, site and a picture) before sending; the words travel
//! inside the encrypted message and the picture as an encrypted attachment (`docs/api-v2.md` section 6), so a recipient never
//! visits the link to show it.

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{json, Value};

use super::attachments::{self, Descriptor};
use super::{db_err, AttachmentInfo, StoreError};

const MAX_URL: usize = 2000;
const MAX_TITLE: usize = 300;
const MAX_SITE: usize = 100;

/// What the app builds for a link in a message it is about to send.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct OutgoingPreview {
    pub url: String,
    pub title: String,
    /// The site's name or domain, shown under the title.
    pub site: String,
    /// A JPEG picture (at most 200 KB), or empty.
    pub image: Vec<u8>,
    pub image_width: Option<u32>,
    pub image_height: Option<u32>,
}

/// A link preview as the app shows it.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct LinkPreview {
    pub url: String,
    pub title: String,
    pub site: String,
    pub image: Option<AttachmentInfo>,
}

/// The words of a preview (the picture is an attachment).
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Meta {
    pub url: String,
    pub title: String,
    pub site: String,
}

fn clean(text: &str, max: usize) -> String {
    text.chars().filter(|c| !c.is_control()).take(max).collect::<String>().trim().to_owned()
}

impl Meta {
    pub(crate) fn new(url: &str, title: &str, site: &str) -> Option<Meta> {
        let url = url.trim();
        let web = url.starts_with("https://") || url.starts_with("http://");
        if !web || url.len() > MAX_URL || url.chars().any(|c| c.is_control() || c.is_whitespace()) {
            return None;
        }
        let (title, site) = (clean(title, MAX_TITLE), clean(site, MAX_SITE));
        (!title.is_empty() || !site.is_empty()).then(|| Meta { url: url.to_owned(), title, site })
    }

    /// The payload entry: the words, and the picture's descriptor if there is one.
    pub(crate) fn to_json(&self, image: Option<&Descriptor>) -> Value {
        let mut value = json!({ "url": self.url, "title": self.title, "site": self.site });
        if let Some(image) = image {
            value["image"] = image.to_json();
        }
        value
    }

    /// Reads a received payload entry; a malformed preview is dropped (the message itself is still fine).
    pub(crate) fn parse(value: &Value) -> Option<(Meta, Option<Descriptor>)> {
        let text = |k: &str| value.get(k).and_then(Value::as_str).unwrap_or("");
        let meta = Meta::new(text("url"), text("title"), text("site"))?;
        let image = match value.get("image") {
            None | Some(Value::Null) => None,
            Some(v) => Some(Descriptor::parse(v).filter(|d| d.mime.starts_with("image/") && d.size <= 512 * 1024)?),
        };
        Some((meta, image))
    }
}

/// Keeps a message's preview words.
pub(crate) fn store(conn: &Connection, message_id: &str, meta: &Meta) -> Result<(), StoreError> {
    conn.execute(
        "UPDATE messages SET link_preview = ?2 WHERE id = ?1",
        params![message_id, json!({ "url": meta.url, "title": meta.title, "site": meta.site }).to_string()],
    )
    .map_err(db_err)?;
    Ok(())
}

pub(crate) fn meta_of(conn: &Connection, message_id: &str) -> Option<Meta> {
    let text: Option<String> = conn
        .query_row("SELECT link_preview FROM messages WHERE id = ?1", params![message_id], |r| r.get(0))
        .optional()
        .ok()
        .flatten()
        .flatten();
    let value: Value = serde_json::from_str(&text?).ok()?;
    let field = |k: &str| value.get(k).and_then(Value::as_str).unwrap_or("").to_owned();
    Some(Meta { url: field("url"), title: field("title"), site: field("site") })
}

/// A message's preview for the app.
pub(crate) fn info(conn: &Connection, message_id: &str) -> Option<LinkPreview> {
    let meta = meta_of(conn, message_id)?;
    let image = attachments::preview_of(conn, message_id).ok().flatten().map(|(d, downloaded)| AttachmentInfo {
        id: d.id, mime: d.mime, name: d.name, size: d.size, width: d.width, height: d.height, duration_ms: d.duration_ms, thumb: d.thumb, downloaded,
    });
    Some(LinkPreview { url: meta.url, title: meta.title, site: meta.site, image })
}

/// Marks a message as forwarded.
pub(crate) fn set_forwarded(conn: &Connection, message_id: &str) -> Result<(), StoreError> {
    conn.execute("UPDATE messages SET forwarded = 1 WHERE id = ?1", params![message_id]).map_err(db_err)?;
    Ok(())
}

pub(crate) fn is_forwarded(conn: &Connection, message_id: &str) -> bool {
    conn.query_row("SELECT forwarded FROM messages WHERE id = ?1", params![message_id], |r| r.get::<_, bool>(0)).unwrap_or(false)
}

/// What a received payload says besides its text: forwarded, and a link preview. Applied once the message is stored.
pub(crate) struct Extras {
    pub forwarded: bool,
    pub preview: Option<(Meta, Option<Descriptor>)>,
}

impl Extras {
    pub(crate) fn parse(payload: &Value) -> Extras {
        Extras {
            forwarded: payload.get("forwarded").and_then(Value::as_bool).unwrap_or(false),
            preview: payload.get("link_preview").and_then(Meta::parse),
        }
    }

    pub(crate) fn apply(&self, conn: &Connection, message_id: &str) -> Result<(), StoreError> {
        if self.forwarded {
            set_forwarded(conn, message_id)?;
        }
        if let Some((meta, image)) = &self.preview {
            store(conn, message_id, meta)?;
            if let Some(image) = image {
                attachments::insert_preview(conn, message_id, image, None)?;
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_preview_needs_a_web_address_and_a_title_or_site_and_is_trimmed() {
        assert!(Meta::new("https://example.org/a", "Title", "example.org").is_some());
        assert!(Meta::new("javascript:alert(1)", "x", "y").is_none(), "only web addresses");
        assert!(Meta::new("https://example.org/a b", "x", "y").is_none(), "no spaces in the address");
        assert!(Meta::new("https://example.org", "", "").is_none(), "something to show");
        let long = "x".repeat(500);
        assert_eq!(Meta::new("https://example.org", &long, "s").unwrap().title.chars().count(), MAX_TITLE);
        assert_eq!(Meta::new("https://example.org", "A\u{0}B\nC", "s").unwrap().title, "ABC");
    }

    #[test]
    fn a_received_preview_with_a_bad_picture_is_dropped() {
        let good = json!({ "url": "https://example.org", "title": "T", "site": "S" });
        assert!(Meta::parse(&good).is_some());
        let bad = json!({ "url": "https://example.org", "title": "T", "image": { "id": "nope" } });
        assert!(Meta::parse(&bad).is_none());
    }
}
