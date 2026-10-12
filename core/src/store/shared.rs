//! What was shared in a chat (LIME-122a): the photos and videos, the files and the links, optionally from one sender, newest first.
//! It reads what is already on this phone; nothing is fetched.

use super::{item_in, my_user_id, order, LimeStore, MessageItem, StoreError, ME_ID};

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum SharedKind {
    /// Pictures and videos.
    Media,
    /// Every other attachment.
    Files,
    /// Messages with a web address in their text.
    Links,
}

/// Whether the text has an `http://` or `https://` address.
pub(crate) fn has_link(text: &str) -> bool {
    let lower = text.to_ascii_lowercase();
    lower.contains("http://") || lower.contains("https://")
}

fn is_media(mime: &str) -> bool {
    mime.starts_with("image/") || mime.starts_with("video/")
}

#[uniffi::export]
impl LimeStore {
    /// The messages of a conversation that carry `kind`, newest first. `sender_id` narrows them to one person (`Some("me")` is mine,
    /// `None` is everyone). Deleted and hidden messages, calls and notices are left out.
    pub fn list_shared(&self, conversation_id: String, sender_id: Option<String>, kind: SharedKind) -> Result<Vec<MessageItem>, StoreError> {
        let conn = self.lock();
        let me = my_user_id(&conn);
        let mut rows = order::load(&conn, "conversation_id = ?1", &conversation_id)?;
        rows.retain(|r| !r.deleted && r.local_state != "system" && !r.id.starts_with("call:"));
        if let Some(wanted) = &sender_id {
            let wanted = if wanted == "me" || *wanted == me { ME_ID } else { wanted.as_str() };
            rows.retain(|r| r.sender_id == wanted);
        }
        let mut items: Vec<MessageItem> = rows.into_iter().map(|row| item_in(&conn, row, &me)).collect();
        items.retain(|item| match kind {
            SharedKind::Media => item.attachments.iter().any(|a| is_media(&a.mime) && !a.removed),
            SharedKind::Files => item.attachments.iter().any(|a| !is_media(&a.mime) && !a.removed),
            SharedKind::Links => item.link_preview.is_some() || has_link(&item.text),
        });
        items.sort_by(|a, b| b.sent_at.cmp(&a.sent_at).then_with(|| b.id.cmp(&a.id)));
        Ok(items)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn say(store: &LimeStore, chat: &str, id: &str, sender: &str, body: &str, at: i64) {
        store.lock().execute("INSERT INTO messages (id, conversation_id, sender_id, body, sent_at, local_state) VALUES (?1, ?2, ?3, ?4, ?5, 'sent')", rusqlite::params![id, chat, sender, body, at]).unwrap();
    }

    #[test]
    fn links_are_listed_newest_first_by_sender_with_deleted_calls_and_files_left_out() {
        let dir = tempfile::tempdir().unwrap();
        let store = LimeStore::open(dir.path().join("s.db").to_string_lossy().into_owned(), vec![5u8; 32]).unwrap();
        store.start_dm("jean".into(), "Jean".into()).unwrap();
        say(&store, "dm:jean", "m1", "jean", "look https://example.org/a", 100);
        say(&store, "dm:jean", "m2", super::ME_ID, "and mine https://example.org/b", 200);
        say(&store, "dm:jean", "m3", "jean", "no address", 300);
        say(&store, "dm:jean", "m4", "jean", "later http://example.org/c", 400);
        say(&store, "dm:jean", "call:x", "jean", "https://not-a-message", 500);
        store.lock().execute("UPDATE messages SET deleted = 1 WHERE id = 'm4'", []).unwrap();
        let ids = |sender: Option<&str>| store.list_shared("dm:jean".into(), sender.map(str::to_owned), SharedKind::Links).unwrap().into_iter().map(|m| m.id).collect::<Vec<_>>();
        assert_eq!(ids(None), ["m2", "m1"], "everyone, newest first; the deleted one and the call are left out");
        assert_eq!(ids(Some("jean")), ["m1"], "one sender");
        assert_eq!(ids(Some("me")), ["m2"], "mine");
        assert!(store.list_shared("dm:jean".into(), None, SharedKind::Media).unwrap().is_empty());
        assert!(store.list_shared("dm:jean".into(), None, SharedKind::Files).unwrap().is_empty());
    }

    #[test]
    fn links_are_found_by_their_scheme_anywhere_in_the_words() {
        assert!(has_link("see https://limechat.org/u/jean now"));
        assert!(has_link("(http://example.com)"));
        assert!(has_link("HTTPS://FAMKIND.COM"));
        assert!(!has_link("no address here, just limechat.org"));
        assert!(!has_link(""));
    }
}
