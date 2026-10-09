//! Message actions on the client (LIME-105): edit, delete for everyone, delete for me and reactions. Each takes effect on
//! this phone at once and is sent to the conversation's members as a small signed, encrypted op with the next delivery.
//! The rules (who may, the 24-hour window, converging by clock) are in `store::message_ops`.

use super::*;
use crate::store::message_ops::{self as ops, WINDOW_MS};

struct Target {
    sender: String,
    state: String,
    sent_at: i64,
    deleted: bool,
}

impl LimeStore {
    fn target(&self, conversation_id: &str, message_id: &str) -> Result<Target, StoreError> {
        self.with_conn(|conn| {
            conn.query_row(
                "SELECT sender_id, local_state, sent_at, deleted FROM messages WHERE id = ?1 AND conversation_id = ?2 AND hidden = 0",
                params![message_id, conversation_id],
                |r| Ok(Target { sender: r.get(0)?, state: r.get(1)?, sent_at: r.get(2)?, deleted: r.get(3)? }),
            )
            .optional()
            .map_err(db_err)?
            .ok_or(StoreError::NotFound)
        })
    }

    pub(crate) fn my_user_id_registered(&self) -> Result<String, StoreError> {
        self.my_id()
    }

    fn my_id(&self) -> Result<String, StoreError> {
        let state = self.load_or_create_account()?;
        state.user_id.clone().filter(|_| state.registered).ok_or(StoreError::NotRegistered)
    }

    /// Applies an op of mine here and queues it for delivery.
    fn act(&self, conversation_id: &str, op_type: &str, target: &str, extra: Value) -> Result<(), StoreError> {
        let me = self.my_id()?;
        let now = now_ms();
        self.with_conn(|conn| {
            let hlc = tick_hlc(conn, now)?.render();
            let payload = ops::payload(target, &hlc, extra);
            let op = Op { op_id: new_id(), op_type: op_type.into(), conversation_id: conversation_id.into(), hlc, parents: vec![], payload: payload.clone(), sig: String::new() };
            ops::apply(conn, &me, conversation_id, &op)?;
            ops::enqueue(conn, &op.op_id, conversation_id, op_type, &payload, now)
        })
    }
}

#[uniffi::export]
impl LimeStore {
    /// Puts my emoji on a message (`on`) or takes it off. One reaction per emoji per person; it works in chats, groups and
    /// Replies.
    pub fn react(&self, conversation_id: String, message_id: String, emoji: String, on: bool) -> Result<(), StoreError> {
        let emoji = ops::clean_emoji(&emoji).ok_or(StoreError::Rejected)?;
        let target = self.target(&conversation_id, &message_id)?;
        if target.deleted || target.state == "system" {
            return Err(StoreError::Rejected);
        }
        self.act(&conversation_id, ops::REACT, &message_id, json!({ "emoji": emoji, "on": on }))
    }

    /// Replaces the text of one of my messages (within 24 hours of sending). Only the latest text is kept, and the search
    /// index follows. A message not sent yet is simply rewritten.
    pub fn edit_message(&self, conversation_id: String, message_id: String, text: String) -> Result<MessageItem, StoreError> {
        let target = self.target(&conversation_id, &message_id)?;
        if target.sender != ME_ID || target.deleted || target.state == "system" {
            return Err(StoreError::Rejected);
        }
        let body = crate::format::normalise(&text);
        let has_files = self.with_conn(|conn| Ok(!crate::store::attachments::for_message(conn, &message_id)?.is_empty()))?;
        if (body.is_empty() && !has_files) || body.len() > MAX_TEXT_BYTES {
            return Err(StoreError::Rejected);
        }
        if matches!(target.state.as_str(), "sending" | "failed") {
            // Not sent yet: the message that goes out says the new words, and nobody ever saw the old ones.
            let plain = crate::format::plain_text(&body);
            self.with_conn(|conn| {
                conn.execute("UPDATE messages SET body = ?2, plain = ?3 WHERE id = ?1", params![message_id, body, plain]).map_err(db_err)?;
                Ok(())
            })?;
        } else {
            if now_ms() - target.sent_at > WINDOW_MS {
                return Err(StoreError::Rejected);
            }
            self.act(&conversation_id, ops::EDIT, &message_id, json!({ "text": body }))?;
        }
        self.message_item(&message_id)
    }

    /// Deletes one of my messages for everyone (within 24 hours of sending): their phones replace it with "This message was
    /// deleted", and its files and search entry are removed. Lime cannot guarantee it is gone if someone already saw or saved
    /// it. A message not sent yet is just cancelled.
    pub fn delete_message_for_everyone(&self, conversation_id: String, message_id: String) -> Result<(), StoreError> {
        let target = self.target(&conversation_id, &message_id)?;
        if target.sender != ME_ID || target.state == "system" {
            return Err(StoreError::Rejected);
        }
        if matches!(target.state.as_str(), "sending" | "failed") {
            return self.with_conn(|conn| remove_row(conn, &message_id));
        }
        if now_ms() - target.sent_at > WINDOW_MS {
            return Err(StoreError::Rejected);
        }
        if target.deleted {
            return Ok(());
        }
        self.act(&conversation_id, ops::DELETE, &message_id, json!({}))
    }

    /// Deletes a message for me only: it goes from every list on this phone (nothing is sent). One of mine that was not sent
    /// yet is cancelled.
    pub fn delete_message_for_me(&self, conversation_id: String, message_id: String) -> Result<(), StoreError> {
        let target = self.target(&conversation_id, &message_id)?;
        self.with_conn(|conn| {
            if target.sender == ME_ID && matches!(target.state.as_str(), "sending" | "failed") {
                remove_row(conn, &message_id)
            } else {
                ops::hide(conn, &message_id)
            }
        })
    }
}

fn remove_row(conn: &Connection, id: &str) -> Result<(), StoreError> {
    conn.execute("DELETE FROM message_attachments WHERE message_id = ?1", params![id]).map_err(db_err)?;
    conn.execute("DELETE FROM reactions WHERE message_id = ?1", params![id]).map_err(db_err)?;
    conn.execute("DELETE FROM messages WHERE id = ?1", params![id]).map_err(db_err)?;
    Ok(())
}

impl LimeStore {
    fn message_item(&self, id: &str) -> Result<MessageItem, StoreError> {
        let thread = self.with_conn(|conn| {
            conn.query_row("SELECT conversation_id, thread_root FROM messages WHERE id = ?1", params![id], |r| Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?)))
                .optional()
                .map_err(db_err)
        })?;
        let Some((conversation, root)) = thread else { return Err(StoreError::NotFound) };
        let items = match root {
            Some(root) => self.list_thread(root)?,
            None => self.list_messages(conversation)?,
        };
        items.into_iter().find(|m| m.id == id).ok_or(StoreError::NotFound)
    }

    /// Sends the edits, deletes and reactions still waiting. One that cannot go now stays for the next delivery.
    pub(super) fn deliver_message_ops(&self, transport: &Arc<dyn Transport>, token: &str, state: &mut AccountState, me: &str) {
        let Ok(waiting) = self.with_conn(ops::queued) else { return };
        for op in waiting {
            let sent = if op.conversation_id.starts_with("grp:") {
                let hlc = self.with_conn(|conn| Ok(tick_hlc(conn, now_ms())?.render())).unwrap_or_default();
                let signed = Op { op_id: op.id.clone(), op_type: op.op_type.clone(), conversation_id: op.conversation_id.clone(), hlc, parents: vec![], payload: op.payload.clone(), sig: String::new() };
                self.send_group_op(transport, token, state, me, signed).is_ok()
            } else if op.conversation_id == format!("dm:{me}") {
                true   // my own chat: nothing to send
            } else if let Some(peer) = op.conversation_id.strip_prefix("dm:") {
                self.send_control_op(transport, token, state, me, peer, &op.op_type, op.payload.clone()).is_ok()
            } else {
                true
            };
            if sent {
                let _ = self.with_conn(|conn| ops::dequeue(conn, &op.id));
            }
        }
    }
}
