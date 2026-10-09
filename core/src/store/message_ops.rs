//! Message actions (LIME-105): edit, delete for everyone, delete for me, and emoji reactions.
//!
//! Each is a small signed, encrypted op sent to the conversation's members over the same channels as a message
//! (`message.edit`, `message.delete`, `reaction.toggle`); the server sees an item like any other. This module is the rules
//! and the storage: who may do what, the 24-hour window, last-writer-wins by clock so devices converge, and what an
//! action that arrives before its message does (it waits).

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{json, Value};

use super::{db_err, StoreError, ME_ID};
use crate::protocol::{Hlc, Op};

/// Edit and delete-for-everyone are allowed this long after a message was sent.
pub(crate) const WINDOW_MS: i64 = 24 * 3600 * 1000;
/// Clocks differ a little between phones.
const SKEW_MS: i64 = 10 * 60 * 1000;
const MAX_REACTION_CHARS: usize = 16;
/// Different emoji on one message.
const MAX_EMOJI_PER_MESSAGE: i64 = 40;

pub(crate) const EDIT: &str = "message.edit";
pub(crate) const DELETE: &str = "message.delete";
pub(crate) const REACT: &str = "reaction.toggle";

pub(crate) fn is_message_op(op_type: &str) -> bool {
    matches!(op_type, EDIT | DELETE | REACT)
}

/// A reaction is one emoji (a few scalars at most, with no letters or digits, so a word cannot pass as one).
pub(crate) fn clean_emoji(text: &str) -> Option<String> {
    let t = text.trim();
    let ok = !t.is_empty()
        && t.chars().count() <= MAX_REACTION_CHARS
        && t.chars().all(|c| !c.is_control() && !c.is_alphanumeric() && !c.is_whitespace())
        && t.chars().any(|c| c as u32 > 0x2000);
    ok.then(|| t.to_owned())
}

/// One emoji on a message: how many people, whether I am one, and who (names, "You" first).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct Reaction {
    pub emoji: String,
    pub count: u32,
    pub mine: bool,
    pub people: Vec<String>,
}

pub(crate) fn reactions_for(conn: &Connection, message_id: &str, me: &str) -> Vec<Reaction> {
    let Ok(mut statement) = conn.prepare(
        "SELECT r.emoji, r.user_id, COALESCE(p.name, r.user_id)
         FROM reactions r LEFT JOIN people p ON p.id = r.user_id
         WHERE r.message_id = ?1 AND r.active = 1 ORDER BY r.hlc, r.user_id",
    ) else {
        return Vec::new();
    };
    let rows: Vec<(String, String, String)> = statement
        .query_map(params![message_id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))
        .map(|rows| rows.filter_map(Result::ok).collect())
        .unwrap_or_default();
    let mut out: Vec<Reaction> = Vec::new();
    for (emoji, user, name) in rows {
        let mine = user == me || user == ME_ID;
        let who = if mine { "You".to_owned() } else { name };
        match out.iter_mut().find(|r| r.emoji == emoji) {
            Some(reaction) => {
                reaction.count += 1;
                reaction.mine |= mine;
                if mine { reaction.people.insert(0, who) } else { reaction.people.push(who) }
            }
            None => out.push(Reaction { emoji, count: 1, mine, people: vec![who] }),
        }
    }
    out
}

fn wall(hlc: &str) -> Option<i64> {
    Hlc::parse(hlc).map(|h| h.wall)
}

fn newer(candidate: &str, existing: Option<&str>) -> bool {
    match existing {
        None => true,
        Some(old) => match (Hlc::parse(candidate), Hlc::parse(old)) {
            (Some(a), Some(b)) => (a.wall, a.counter, candidate) > (b.wall, b.counter, old),
            _ => candidate > old,
        },
    }
}

// ---------------------------------------------------------------- applying (received, and my own at once)

/// Applies one received op from `sender` in `conversation` (a DM or a group). Anything not allowed is ignored without
/// error (a forged or late op changes nothing); an op about a message that is not here yet waits for it.
pub(crate) fn apply(conn: &Connection, sender: &str, conversation: &str, op: &Op) -> Result<(), StoreError> {
    let Some(target) = op.payload.get("target").and_then(Value::as_str).filter(|t| !t.is_empty() && t.len() <= 64) else { return Ok(()) };
    let at = op.payload.get("hlc").and_then(Value::as_str).filter(|h| Hlc::parse(h).is_some()).unwrap_or(&op.hlc);
    /// A stored message's conversation, author, own clock, newest edit's clock, and whether it is deleted.
    type Stored = (String, String, Option<String>, Option<String>, bool);
    let message: Option<Stored> = conn
        .query_row("SELECT conversation_id, sender_id, hlc, edit_hlc, deleted FROM messages WHERE id = ?1", params![target], |r| {
            Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?))
        })
        .optional()
        .map_err(db_err)?;
    let me = super::my_user_id(conn);
    let message = message.map(|(c, a, h, e, d)| (c, if a == ME_ID { me.clone() } else { a }, h, e, d));
    let Some((message_conversation, author, sent_hlc, edit_hlc, deleted)) = message else {
        // Not here yet: keep it (edits and deletes only, a reaction is stored by id anyway).
        if op.op_type == REACT {
            return set_reaction(conn, target, sender, op, at);
        }
        if matches!(op.op_type.as_str(), EDIT | DELETE) {
            conn.execute(
                "INSERT OR IGNORE INTO early_message_ops (target, op_type, sender, hlc, payload) VALUES (?1, ?2, ?3, ?4, ?5)",
                params![target, op.op_type, sender, at, op.payload.to_string()],
            )
            .map_err(db_err)?;
        }
        return Ok(());
    };
    if message_conversation != conversation {
        return Ok(());
    }
    match op.op_type.as_str() {
        REACT => set_reaction(conn, target, sender, op, at),
        EDIT | DELETE => {
            // Only the author, and only within a day of the message's own clock.
            let within = match (sent_hlc.as_deref().and_then(wall), wall(at)) {
                (Some(sent), Some(acted)) => acted - sent <= WINDOW_MS + SKEW_MS,
                _ => false,
            };
            if author != sender || !within || deleted {
                return Ok(());
            }
            if op.op_type == DELETE {
                tombstone(conn, target)
            } else {
                let Some(text) = op.payload.get("text").and_then(Value::as_str) else { return Ok(()) };
                if !newer(at, edit_hlc.as_deref()) {
                    return Ok(());
                }
                set_text(conn, target, text, at)
            }
        }
        _ => Ok(()),
    }
}

fn set_reaction(conn: &Connection, target: &str, user: &str, op: &Op, at: &str) -> Result<(), StoreError> {
    let Some(emoji) = op.payload.get("emoji").and_then(Value::as_str).and_then(clean_emoji) else { return Ok(()) };
    let active = op.payload.get("on").and_then(Value::as_bool).unwrap_or(true);
    let current: Option<String> = conn
        .query_row("SELECT hlc FROM reactions WHERE message_id = ?1 AND user_id = ?2 AND emoji = ?3", params![target, user, emoji], |r| r.get(0))
        .optional()
        .map_err(db_err)?;
    if !newer(at, current.as_deref()) {
        return Ok(());
    }
    if current.is_none() {
        let distinct: i64 = conn
            .query_row("SELECT count(DISTINCT emoji) FROM reactions WHERE message_id = ?1 AND active = 1", params![target], |r| r.get(0))
            .map_err(db_err)?;
        if active && distinct >= MAX_EMOJI_PER_MESSAGE {
            return Ok(());
        }
    }
    conn.execute(
        "INSERT INTO reactions (message_id, user_id, emoji, hlc, active) VALUES (?1, ?2, ?3, ?4, ?5)
         ON CONFLICT (message_id, user_id, emoji) DO UPDATE SET hlc = ?4, active = ?5",
        params![target, user, emoji, at, active],
    )
    .map_err(db_err)?;
    Ok(())
}

/// A message deleted for everyone: its words and files are gone, its place stays ("This message was deleted"), and
/// the search index forgets it (the index follows `plain`).
pub(crate) fn tombstone(conn: &Connection, id: &str) -> Result<(), StoreError> {
    conn.execute("UPDATE messages SET deleted = 1, body = '', plain = '', edited = 0, link_preview = NULL, forwarded = 0 WHERE id = ?1", params![id]).map_err(db_err)?;
    conn.execute("DELETE FROM message_attachments WHERE message_id = ?1", params![id]).map_err(db_err)?;
    conn.execute("DELETE FROM reactions WHERE message_id = ?1", params![id]).map_err(db_err)?;
    Ok(())
}

/// A message deleted for me: gone from every list on this phone, its words and files with it.
pub(crate) fn hide(conn: &Connection, id: &str) -> Result<(), StoreError> {
    conn.execute("UPDATE messages SET hidden = 1, body = '', plain = '', link_preview = NULL WHERE id = ?1", params![id]).map_err(db_err)?;
    conn.execute("DELETE FROM message_attachments WHERE message_id = ?1", params![id]).map_err(db_err)?;
    conn.execute("DELETE FROM reactions WHERE message_id = ?1", params![id]).map_err(db_err)?;
    Ok(())
}

/// The new text of an edited message (in its one written form, with the plain words for search).
pub(crate) fn set_text(conn: &Connection, id: &str, text: &str, at: &str) -> Result<(), StoreError> {
    let body = crate::format::normalise(text);
    let attachments: i64 = conn.query_row("SELECT count(*) FROM message_attachments WHERE message_id = ?1", params![id], |r| r.get(0)).map_err(db_err)?;
    if (body.is_empty() && attachments == 0) || body.len() > 30_000 {
        return Ok(());
    }
    let plain = crate::format::plain_text(&body);
    conn.execute("UPDATE messages SET body = ?2, plain = ?3, edited = 1, edit_hlc = ?4 WHERE id = ?1", params![id, body, plain, at]).map_err(db_err)?;
    Ok(())
}

/// A message just arrived: apply any edit or delete that got here first.
pub(crate) fn apply_waiting(conn: &Connection, message_id: &str, conversation: &str) -> Result<(), StoreError> {
    let mut statement = conn
        .prepare("SELECT op_type, sender, hlc, payload FROM early_message_ops WHERE target = ?1 ORDER BY hlc")
        .map_err(db_err)?;
    let waiting: Vec<(String, String, String, String)> = statement
        .query_map(params![message_id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    conn.execute("DELETE FROM early_message_ops WHERE target = ?1", params![message_id]).map_err(db_err)?;
    for (op_type, sender, hlc, payload) in waiting {
        let payload: Value = serde_json::from_str(&payload).unwrap_or(Value::Null);
        let op = Op { op_id: String::new(), op_type, conversation_id: conversation.to_owned(), hlc, parents: vec![], payload, sig: String::new() };
        apply(conn, &sender, conversation, &op)?;
    }
    Ok(())
}

// ---------------------------------------------------------------- the outbox

pub(crate) fn enqueue(conn: &Connection, id: &str, conversation: &str, op_type: &str, payload: &Value, now_ms: i64) -> Result<(), StoreError> {
    conn.execute(
        "INSERT OR REPLACE INTO message_op_outbox (id, conversation_id, op_type, payload, queued_at) VALUES (?1, ?2, ?3, ?4, ?5)",
        params![id, conversation, op_type, payload.to_string(), now_ms],
    )
    .map_err(db_err)?;
    Ok(())
}

pub(crate) struct Queued {
    pub id: String,
    pub conversation_id: String,
    pub op_type: String,
    pub payload: Value,
}

pub(crate) fn queued(conn: &Connection) -> Result<Vec<Queued>, StoreError> {
    let mut statement = conn.prepare("SELECT id, conversation_id, op_type, payload FROM message_op_outbox ORDER BY queued_at, id").map_err(db_err)?;
    let rows = statement
        .query_map([], |r| {
            let payload: String = r.get(3)?;
            Ok(Queued { id: r.get(0)?, conversation_id: r.get(1)?, op_type: r.get(2)?, payload: serde_json::from_str(&payload).unwrap_or(Value::Null) })
        })
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    Ok(rows)
}

pub(crate) fn dequeue(conn: &Connection, id: &str) -> Result<(), StoreError> {
    conn.execute("DELETE FROM message_op_outbox WHERE id = ?1", params![id]).map_err(db_err)?;
    Ok(())
}

pub(crate) fn payload(target: &str, at: &str, extra: Value) -> Value {
    let mut value = json!({ "target": target, "hlc": at });
    if let (Some(map), Some(extra)) = (value.as_object_mut(), extra.as_object()) {
        map.extend(extra.clone());
    }
    value
}
