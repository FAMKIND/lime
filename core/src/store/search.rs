//! On-device search (LIME-99). Everything here reads the encrypted local database; nothing touches the
//! network, and no function takes a transport. Messages are searched through the FTS5 index
//! (`message_fts`, kept in step by triggers); conversations through a throwaway in-memory index of
//! their titles and the names of their people.

use rusqlite::params;

use super::{db_err, LimeStore, StoreError, ME_ID};

/// Marks the start and end of a matched word in a [`SearchHit`] snippet (Unicode private-use
/// characters, so they cannot appear in a message the way `<b>` could).
pub const MATCH_START: char = '\u{E000}';
pub const MATCH_END: char = '\u{E001}';

/// One message that matches a search.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct SearchHit {
    pub conversation_id: String,
    pub message_id: String,
    /// A few words around the match; each matched word sits between `\u{E000}` and `\u{E001}`.
    pub snippet: String,
    /// The message's display time, in milliseconds since the Unix epoch.
    pub time: i64,
    /// True when the message is mine.
    pub from_me: bool,
    /// The message this one replies to, when it is a reply in a thread (the hit opens that thread).
    pub thread_root: Option<String>,
}

/// One conversation whose title or people match a search.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ConversationMatch {
    pub conversation_id: String,
    pub title: String,
}

/// The words of what was typed, as an FTS5 query: every word must match, and the last one as a
/// prefix (so "plan" finds "planning"). Only letters and numbers are kept, so nothing typed can be
/// read as FTS syntax.
pub(crate) fn fts_query(text: &str) -> Option<String> {
    let words: Vec<String> = text
        .split(|c: char| !c.is_alphanumeric())
        .filter(|w| !w.is_empty())
        .map(str::to_owned)
        .collect();
    if words.is_empty() {
        return None;
    }
    // Every word is a prefix: results appear as you type, and "les pl" finds "lesson planning".
    Some(
        words
            .iter()
            .map(|w| format!("\"{w}\"*"))
            .collect::<Vec<_>>()
            .join(" "),
    )
}

#[uniffi::export]
impl LimeStore {
    /// Messages matching `query`, prefix-matched and case- and diacritic-insensitive. In every
    /// conversation (best match first, then newest; a reply in a thread says which thread) or, with
    /// `conversation_id`, in that chat's main timeline (oldest first, so a person can step through
    /// them; replies are in their threads). Blocked conversations are never searched.
    pub fn search_messages(
        &self,
        query: String,
        conversation_id: Option<String>,
        limit: u32,
    ) -> Result<Vec<SearchHit>, StoreError> {
        let Some(fts) = fts_query(&query) else {
            return Ok(Vec::new());
        };
        let conn = self.lock();
        let order = if conversation_id.is_some() {
            "m.sent_at ASC, m.id ASC"
        } else {
            "rank, m.sent_at DESC, m.id DESC"
        };
        let sql = format!(
            "SELECT message_fts.message_id, message_fts.conversation_id,
                    snippet(message_fts, 0, char({start}), char({end}), '…', 12),
                    m.sent_at, m.sender_id, m.thread_root
             FROM message_fts
             JOIN messages m ON m.id = message_fts.message_id
             JOIN conversations c ON c.id = message_fts.conversation_id
             WHERE message_fts MATCH ?1 AND c.request_state != 'blocked'
               AND (?2 IS NULL OR (message_fts.conversation_id = ?2 AND m.thread_root IS NULL))
             ORDER BY {order} LIMIT ?3",
            start = MATCH_START as u32,
            end = MATCH_END as u32,
        );
        let mut statement = conn.prepare(&sql).map_err(db_err)?;
        let hits = statement
            .query_map(params![fts, conversation_id, limit.max(1)], |r| {
                Ok(SearchHit {
                    message_id: r.get(0)?,
                    conversation_id: r.get(1)?,
                    snippet: r.get(2)?,
                    time: r.get(3)?,
                    from_me: r.get::<_, String>(4)? == ME_ID,
                    thread_root: r.get(5)?,
                })
            })
            .map_err(db_err)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(db_err)?;
        Ok(hits)
    }

    /// Conversations whose title, or whose people's names, match `query` (the same matching).
    pub fn search_conversations(&self, query: String) -> Result<Vec<ConversationMatch>, StoreError> {
        let Some(fts) = fts_query(&query) else {
            return Ok(Vec::new());
        };
        let conn = self.lock();
        conn.execute_batch(
            "CREATE VIRTUAL TABLE IF NOT EXISTS temp.conversation_fts USING fts5(
                 conversation_id UNINDEXED, title UNINDEXED, text,
                 tokenize = 'unicode61 remove_diacritics 2');
             DELETE FROM temp.conversation_fts;
             INSERT INTO temp.conversation_fts (conversation_id, title, text)
                 SELECT c.id, c.title,
                        c.title || ' ' || COALESCE((SELECT group_concat(p.name, ' ')
                                                    FROM members m JOIN people p ON p.id = m.person_id
                                                    WHERE m.conversation_id = c.id AND p.id != 'me'), '')
                 FROM conversations c WHERE c.request_state != 'blocked';",
        )
        .map_err(db_err)?;
        let mut statement = conn
            .prepare(
                "SELECT conversation_id, title FROM temp.conversation_fts
                 WHERE conversation_fts MATCH ?1 ORDER BY rank, title",
            )
            .map_err(db_err)?;
        let found = statement
            .query_map(params![format!("text : ({fts})")], |r| {
                Ok(ConversationMatch {
                    conversation_id: r.get(0)?,
                    title: r.get(1)?,
                })
            })
            .map_err(db_err)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(db_err)?;
        Ok(found)
    }
}
