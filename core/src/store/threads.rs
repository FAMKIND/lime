//! Reply threads (LIME-101): the queries behind "3 replies, last reply 8:20 am" and the thread screen.
//! A reply carries `thread_root`, the id of the message it answers, inside the encrypted payload (the
//! server never sees it). Replies stay out of the main timeline (`list_messages`).

use rusqlite::params;

use super::order;
use super::{db_err, initials_of, item_from_row, LimeStore, MemberInfo, MessageItem, StoreError};

/// What a message with replies shows under its bubble.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ThreadSummary {
    /// The message the replies hang from.
    pub root_id: String,
    pub reply_count: u32,
    /// The display time of the newest reply, in milliseconds since the Unix epoch.
    pub last_reply_at: i64,
    /// Up to three people who replied, the most recent first (me is `id == "me"`).
    pub repliers: Vec<MemberInfo>,
    /// Replies from others not yet seen in the thread.
    pub unread: u32,
}

#[uniffi::export]
impl LimeStore {
    /// Every thread in a conversation that has at least one reply (and whose root message is here).
    pub fn list_thread_summaries(&self, conversation_id: String) -> Result<Vec<ThreadSummary>, StoreError> {
        let conn = self.lock();
        let mut statement = conn
            .prepare(
                "SELECT r.thread_root, count(*), max(r.sent_at)
                 FROM messages r JOIN messages root ON root.id = r.thread_root AND root.conversation_id = r.conversation_id
                 WHERE r.conversation_id = ?1 AND r.thread_root IS NOT NULL
                 GROUP BY r.thread_root",
            )
            .map_err(db_err)?;
        let threads = statement
            .query_map(params![conversation_id], |r| Ok((r.get::<_, String>(0)?, r.get::<_, u32>(1)?, r.get::<_, i64>(2)?)))
            .map_err(db_err)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(db_err)?;
        let mut out = Vec::with_capacity(threads.len());
        for (root_id, reply_count, last_reply_at) in threads {
            let mut who = conn
                .prepare(
                    "SELECT m.sender_id, COALESCE(p.name, m.sender_id), COALESCE(p.tone, 0)
                     FROM messages m LEFT JOIN people p ON p.id = m.sender_id
                     WHERE m.thread_root = ?1 ORDER BY m.sent_at DESC, m.id DESC",
                )
                .map_err(db_err)?;
            let mut repliers: Vec<MemberInfo> = Vec::new();
            for row in who
                .query_map(params![root_id], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, u32>(2)?)))
                .map_err(db_err)?
            {
                let (id, name, tone) = row.map_err(db_err)?;
                if repliers.len() < 3 && !repliers.iter().any(|m| m.id == id) {
                    repliers.push(MemberInfo { initials: initials_of(&name), id, name, tone });
                }
            }
            let unread: u32 = conn
                .query_row("SELECT COALESCE((SELECT unread FROM thread_state WHERE root_id = ?1), 0)", params![root_id], |r| r.get(0))
                .map_err(db_err)?;
            out.push(ThreadSummary { root_id, reply_count, last_reply_at, repliers, unread });
        }
        Ok(out)
    }

    /// A thread: the message it hangs from first, then its replies in display order.
    pub fn list_thread(&self, root_id: String) -> Result<Vec<MessageItem>, StoreError> {
        let conn = self.lock();
        let rows = order::load_thread(&conn, &root_id)?;
        if rows.is_empty() {
            return Err(StoreError::NotFound);
        }
        let (root, mut replies): (Vec<_>, Vec<_>) = rows.into_iter().partition(|r| r.id == root_id);
        let with_files = |row| {
            let mut item = item_from_row(row);
            item.attachments = super::attachment_infos(&conn, &item.id);
            item
        };
        let mut items: Vec<MessageItem> = root.into_iter().map(with_files).collect();
        items.extend(replies.drain(..).map(with_files));
        Ok(items)
    }

    /// The thread has been looked at: its unread count goes to zero.
    pub fn mark_thread_read(&self, root_id: String) -> Result<(), StoreError> {
        let conn = self.lock();
        conn.execute("UPDATE thread_state SET unread = 0 WHERE root_id = ?1 AND unread != 0", params![root_id])
            .map_err(db_err)?;
        Ok(())
    }
}

