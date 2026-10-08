//! Group chats on this device (LIME-97): the log of signed state ops, the state worked out from it, the
//! conversation, its members and its system lines, and the Megolm sessions. The rules themselves are in
//! `protocol::group`; this is the storage around them. Nothing here talks to a server.

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{json, Value};
use vodozemac::megolm::{GroupSession, GroupSessionPickle, InboundGroupSession, InboundGroupSessionPickle};

use super::{db_err, StoreError, ME_ID};
use crate::protocol::group::{self as rules, Event, GroupOp, GroupState, Kind};
use crate::protocol::Hlc;

pub(crate) fn conversation_id(group_id: &str) -> String {
    format!("grp:{group_id}")
}

/// The group id of a `grp:` conversation id, if it is one.
pub(crate) fn group_id_of(conversation_id: &str) -> Option<&str> {
    conversation_id.strip_prefix("grp:").filter(|id| !id.is_empty() && id.len() <= 64)
}

fn tone_of(user: &str) -> u32 {
    user.bytes().fold(0u32, |acc, b| acc.wrapping_mul(31).wrapping_add(u32::from(b))) % 8
}

fn ensure_person(conn: &Connection, user: &str) -> Result<(), StoreError> {
    conn.execute("INSERT OR IGNORE INTO people (id, name, tone) VALUES (?1, ?1, ?2)", params![user, tone_of(user)]).map_err(db_err)?;
    Ok(())
}

// ---------------------------------------------------------------- the op log

/// Stores a verified state op (with its whole signed envelope, `inner`). `true` when it was new.
#[allow(clippy::too_many_arguments)] // one column each
pub(crate) fn insert_op(
    conn: &Connection,
    group_id: &str,
    op_id: &str,
    op_type: &str,
    sender: &str,
    hlc: &str,
    parents: &[String],
    payload: &Value,
    inner: &str,
    now: i64,
) -> Result<bool, StoreError> {
    let changed = conn
        .execute(
            "INSERT OR IGNORE INTO group_ops (op_id, group_id, op_type, sender_user, hlc, parents, payload, inner, received_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            params![op_id, group_id, op_type, sender, hlc, json!(parents).to_string(), payload.to_string(), inner, now],
        )
        .map_err(db_err)?;
    Ok(changed > 0)
}

pub(crate) fn delete_op(conn: &Connection, op_id: &str) -> Result<(), StoreError> {
    conn.execute("DELETE FROM group_ops WHERE op_id = ?1", params![op_id]).map_err(db_err)?;
    Ok(())
}

/// The state ops of a group, as the replay reads them (ops that are not well-formed are left out).
pub(crate) fn load_ops(conn: &Connection, group_id: &str) -> Result<Vec<GroupOp>, StoreError> {
    let mut statement = conn
        .prepare("SELECT op_id, op_type, sender_user, hlc, parents, payload FROM group_ops WHERE group_id = ?1")
        .map_err(db_err)?;
    let rows = statement
        .query_map(params![group_id], |r| {
            Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, String>(2)?, r.get::<_, String>(3)?, r.get::<_, String>(4)?, r.get::<_, String>(5)?))
        })
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    Ok(rows
        .into_iter()
        .filter_map(|(op_id, op_type, sender, hlc, parents, payload)| {
            Some(GroupOp {
                op_id,
                sender,
                hlc: Hlc::parse(&hlc)?,
                parents: serde_json::from_str(&parents).ok()?,
                kind: Kind::parse(&op_type, &serde_json::from_str(&payload).ok()?)?,
            })
        })
        .collect())
}

/// The signed envelopes of every state op, oldest first: what a newly added person is given.
pub(crate) fn load_inners(conn: &Connection, group_id: &str) -> Result<Vec<String>, StoreError> {
    let mut statement = conn
        .prepare("SELECT inner FROM group_ops WHERE group_id = ?1 ORDER BY hlc, op_id")
        .map_err(db_err)?;
    let rows = statement.query_map(params![group_id], |r| r.get::<_, String>(0)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(rows)
}

/// The latest state ops nothing else lists as a parent (at most three): what a new state op names as its parents.
pub(crate) fn heads(conn: &Connection, group_id: &str) -> Result<Vec<String>, StoreError> {
    let ops = load_ops(conn, group_id)?;
    let referenced: std::collections::HashSet<&String> = ops.iter().flat_map(|o| o.parents.iter()).collect();
    let mut heads: Vec<&GroupOp> = ops.iter().filter(|o| !referenced.contains(&o.op_id)).collect();
    heads.sort_by(|a, b| (a.hlc, &a.op_id).cmp(&(b.hlc, &b.op_id)));
    let start = heads.len().saturating_sub(3);
    Ok(heads[start..].iter().map(|o| o.op_id.clone()).collect())
}

pub(crate) fn state_of(conn: &Connection, group_id: &str) -> Result<GroupState, StoreError> {
    Ok(rules::replay(group_id, &load_ops(conn, group_id)?))
}

// ---------------------------------------------------------------- rebuilding the conversation

/// The state worked out again. (When someone joined or left, this device's outbound session for the group is marked
/// to be replaced: see `rebuild`.)
pub(crate) struct Rebuilt {
    pub state: GroupState,
}

/// Works the state out from the log and writes it: the members, the conversation (made when I first become a
/// member; hidden when I am no longer one), its name and avatar, and the system lines of the timeline.
pub(crate) fn rebuild(conn: &Connection, group_id: &str, me: &str, now: i64) -> Result<Rebuilt, StoreError> {
    let state = state_of(conn, group_id)?;
    if !state.created {
        return Ok(Rebuilt { state });
    }
    let conv = conversation_id(group_id);
    let before: Vec<String> = {
        let mut statement = conn.prepare("SELECT user_id FROM group_members WHERE group_id = ?1 ORDER BY user_id").map_err(db_err)?;
        let rows = statement.query_map(params![group_id], |r| r.get::<_, String>(0)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
        rows
    };
    let mut after = state.users();
    after.sort();
    let membership_changed = before != after;
    conn.execute("DELETE FROM group_members WHERE group_id = ?1", params![group_id]).map_err(db_err)?;
    for member in &state.members {
        conn.execute(
            "INSERT INTO group_members (group_id, user_id, role, seq) VALUES (?1, ?2, ?3, ?4)",
            params![group_id, member.user, member.role.as_str(), member.seq as i64],
        )
        .map_err(db_err)?;
    }
    if membership_changed {
        conn.execute("UPDATE group_outbound_sessions SET rotate = 1 WHERE group_id = ?1", params![group_id]).map_err(db_err)?;
    }
    conn.execute("INSERT OR IGNORE INTO people (id, name, tone) VALUES (?1, 'Me', 4)", params![ME_ID]).map_err(db_err)?;

    let existing: Option<String> = conn
        .query_row("SELECT request_state FROM conversations WHERE id = ?1", params![conv], |r| r.get(0))
        .optional()
        .map_err(db_err)?;
    let i_am_member = state.is_member(me);
    match (existing, i_am_member) {
        (None, true) => {
            // Who brought me in decides whether it waits in Requests: a contact does not.
            let inviter = state
                .effects
                .iter()
                .find_map(|e| match &e.event {
                    Event::Created { .. } => Some(e.actor.clone()),
                    Event::Added(users) if users.iter().any(|u| u == me) => Some(e.actor.clone()),
                    _ => None,
                })
                .unwrap_or_default();
            let known: bool = inviter == me
                || conn
                    .query_row(
                        "SELECT EXISTS (SELECT 1 FROM conversations WHERE id = ?1 AND request_state = 'accepted')",
                        params![format!("dm:{inviter}")],
                        |r| r.get(0),
                    )
                    .map_err(db_err)?;
            conn.execute(
                "INSERT INTO conversations (id, title, is_group, is_pinned, unread, request_state, group_emoji) VALUES (?1, ?2, 1, 0, 0, ?3, ?4)",
                params![conv, state.name, if known { "accepted" } else { "pending" }, state.emoji],
            )
            .map_err(db_err)?;
        }
        (Some(current), true) => {
            // Added back after leaving or being removed: it is a group of mine again.
            let next = if current == "left" { "accepted" } else { current.as_str() };
            conn.execute(
                "UPDATE conversations SET title = ?2, group_emoji = ?3, request_state = ?4 WHERE id = ?1",
                params![conv, state.name, state.emoji, next],
            )
            .map_err(db_err)?;
        }
        (Some(current), false) if current != "blocked" => {
            conn.execute(
                "UPDATE conversations SET title = ?2, group_emoji = ?3, request_state = 'left' WHERE id = ?1",
                params![conv, state.name, state.emoji],
            )
            .map_err(db_err)?;
        }
        _ => {}
    }

    if existing_conversation(conn, &conv)? {
        // The people, in the order they joined (me last).
        conn.execute("DELETE FROM members WHERE conversation_id = ?1", params![conv]).map_err(db_err)?;
        let mut position = 0i64;
        for member in &state.members {
            if member.user == me {
                continue;
            }
            ensure_person(conn, &member.user)?;
            conn.execute(
                "INSERT INTO members (conversation_id, person_id, position) VALUES (?1, ?2, ?3)",
                params![conv, member.user, position],
            )
            .map_err(db_err)?;
            position += 1;
        }
        if i_am_member {
            conn.execute("INSERT INTO members (conversation_id, person_id, position) VALUES (?1, ?2, ?3)", params![conv, ME_ID, position]).map_err(db_err)?;
        }
        write_system_lines(conn, &conv, &state, me)?;
    }
    let _ = now;
    Ok(Rebuilt { state })
}

fn existing_conversation(conn: &Connection, conv: &str) -> Result<bool, StoreError> {
    conn.query_row("SELECT EXISTS (SELECT 1 FROM conversations WHERE id = ?1)", params![conv], |r| r.get(0)).map_err(db_err)
}

/// The timeline's system lines ("Jean added Lee"), one per thing that really happened, regenerated from the state
/// so that a late op that changes the outcome changes them too.
fn write_system_lines(conn: &Connection, conv: &str, state: &GroupState, me: &str) -> Result<(), StoreError> {
    conn.execute("DELETE FROM messages WHERE conversation_id = ?1 AND id LIKE 'sys:%'", params![conv]).map_err(db_err)?;
    for (index, effect) in state.effects.iter().enumerate() {
        ensure_person(conn, &effect.actor)?;
        let body = match &effect.event {
            Event::Created { name } => json!({ "e": "created", "by": effect.actor, "name": name }),
            Event::Added(users) => json!({ "e": "added", "by": effect.actor, "users": users }),
            Event::Removed(user) => json!({ "e": "removed", "by": effect.actor, "user": user }),
            Event::Left => json!({ "e": "left", "by": effect.actor }),
            Event::Renamed(name) => json!({ "e": "renamed", "by": effect.actor, "name": name }),
            Event::Avatar => json!({ "e": "avatar", "by": effect.actor }),
            Event::Role(user, role) => json!({ "e": "role", "by": effect.actor, "user": user, "role": role.as_str() }),
            Event::NewOwner(user) => json!({ "e": "owner", "by": effect.actor, "user": user }),
        };
        for user in referenced_users(&effect.event) {
            ensure_person(conn, &user)?;
        }
        let sender = if effect.actor == me { ME_ID.to_owned() } else { effect.actor.clone() };
        conn.execute(
            "INSERT OR REPLACE INTO messages (id, conversation_id, sender_id, body, sent_at, local_state, op_id, hlc, parents, plain)
             VALUES (?1, ?2, ?3, ?4, ?5, 'system', NULL, ?6, '[]', '')",
            params![format!("sys:{}:{index}", effect.op_id), conv, sender, body.to_string(), effect.hlc.wall, effect.hlc.render()],
        )
        .map_err(db_err)?;
    }
    Ok(())
}

fn referenced_users(event: &Event) -> Vec<String> {
    match event {
        Event::Added(users) => users.clone(),
        Event::Removed(user) | Event::Role(user, _) | Event::NewOwner(user) => vec![user.clone()],
        _ => vec![],
    }
}

/// A system line's words, from its stored description, for the person at this phone (`me` is "You").
pub(crate) fn render_system(conn: &Connection, body: &str, me_is: &str) -> String {
    let Ok(value) = serde_json::from_str::<Value>(body) else { return String::new() };
    let name_of = |id: &str| -> String {
        if id == me_is || id == ME_ID {
            return "You".to_owned();
        }
        conn.query_row("SELECT name FROM people WHERE id = ?1", params![id], |r| r.get::<_, String>(0))
            .ok()
            .filter(|n| n != id)
            .unwrap_or_else(|| "Someone".to_owned())
    };
    let text = |k: &str| value.get(k).and_then(Value::as_str).unwrap_or_default().to_owned();
    let by = name_of(&text("by"));
    let object = |id: &str| if id == me_is { "you".to_owned() } else { name_of(id) };
    let you = by == "You";
    match text("e").as_str() {
        "created" => format!("{by} created the group “{}”", text("name")),
        "added" => {
            let users: Vec<String> = value["users"].as_array().map(|u| u.iter().filter_map(Value::as_str).map(object).collect()).unwrap_or_default();
            format!("{by} added {}", join_names(&users))
        }
        "removed" => format!("{by} removed {}", object(&text("user"))),
        "left" => format!("{by} {}", if you { "left the group" } else { "left" }),
        "renamed" => format!("{by} renamed the group to “{}”", text("name")),
        "avatar" => format!("{by} changed the group picture"),
        "role" => {
            let who = object(&text("user"));
            if text("role") == "admin" { format!("{by} made {who} an admin") } else { format!("{by} removed {who} as an admin") }
        }
        "owner" => format!("{} {} now the group owner", name_of(&text("user")), if text("user") == me_is { "are" } else { "is" }),
        _ => String::new(),
    }
}

fn join_names(names: &[String]) -> String {
    match names {
        [] => String::new(),
        [one] => one.clone(),
        [a, b] => format!("{a} and {b}"),
        [rest @ .., last] => format!("{}, and {last}", rest.join(", ")),
    }
}

// ---------------------------------------------------------------- the group list for the app

/// The people of a group with their roles and names (me included), in the order they joined.
pub(crate) fn members_with_names(conn: &Connection, group_id: &str) -> Result<Vec<(String, String, String, u32)>, StoreError> {
    let mut statement = conn
        .prepare(
            "SELECT g.user_id, g.role, COALESCE(p.name, g.user_id), COALESCE(p.tone, 0)
             FROM group_members g LEFT JOIN people p ON p.id = g.user_id WHERE g.group_id = ?1 ORDER BY g.seq",
        )
        .map_err(db_err)?;
    let rows = statement
        .query_map(params![group_id], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, String>(2)?, r.get::<_, u32>(3)?)))
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    Ok(rows)
}

// ---------------------------------------------------------------- the outbox

pub(crate) fn enqueue(conn: &Connection, group_id: &str, recipient: &str, op_json: &str) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO group_outbox (group_id, recipient_user, op_json) VALUES (?1, ?2, ?3)",
        params![group_id, recipient, op_json],
    )
    .map_err(db_err)?;
    Ok(())
}

pub(crate) fn outbox(conn: &Connection) -> Result<Vec<(i64, String, String, String)>, StoreError> {
    let mut statement = conn.prepare("SELECT id, group_id, recipient_user, op_json FROM group_outbox ORDER BY id").map_err(db_err)?;
    let rows = statement
        .query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?, r.get::<_, String>(2)?, r.get::<_, String>(3)?)))
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    Ok(rows)
}

pub(crate) fn dequeue(conn: &Connection, id: i64) -> Result<(), StoreError> {
    conn.execute("DELETE FROM group_outbox WHERE id = ?1", params![id]).map_err(db_err)?;
    Ok(())
}

// ---------------------------------------------------------------- Megolm sessions

/// This device's outbound session for a group, and what is known about it.
pub(crate) struct Outbound {
    pub session: GroupSession,
    pub created_at: i64,
    pub messages: i64,
    pub fingerprint: String,
    pub rotate: bool,
    /// People whose devices already have this session's key.
    pub shared_with: Vec<String>,
}

pub(crate) fn load_outbound(conn: &Connection, pickle_key: &[u8; 32], group_id: &str) -> Result<Option<Outbound>, StoreError> {
    let row: Option<(String, i64, i64, String, bool, String)> = conn
        .query_row(
            "SELECT pickle, created_at, messages, fingerprint, rotate, shared_with FROM group_outbound_sessions WHERE group_id = ?1",
            params![group_id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?)),
        )
        .optional()
        .map_err(db_err)?;
    let Some((pickle, created_at, messages, fingerprint, rotate, shared)) = row else { return Ok(None) };
    let session = GroupSession::from_pickle(GroupSessionPickle::from_encrypted(&pickle, pickle_key).map_err(|_| StoreError::BadMessage)?);
    Ok(Some(Outbound { session, created_at, messages, fingerprint, rotate, shared_with: serde_json::from_str(&shared).unwrap_or_default() }))
}

pub(crate) fn save_outbound(conn: &Connection, pickle_key: &[u8; 32], group_id: &str, o: &Outbound) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO group_outbound_sessions (group_id, pickle, session_id, created_at, messages, fingerprint, rotate, shared_with)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
         ON CONFLICT (group_id) DO UPDATE SET pickle = ?2, session_id = ?3, created_at = ?4, messages = ?5, fingerprint = ?6, rotate = ?7, shared_with = ?8",
        params![
            group_id,
            o.session.pickle().encrypt(pickle_key),
            o.session.session_id(),
            o.created_at,
            o.messages,
            o.fingerprint,
            o.rotate,
            json!(o.shared_with).to_string()
        ],
    )
    .map_err(db_err)?;
    Ok(())
}

pub(crate) fn delete_outbound(conn: &Connection, group_id: &str) -> Result<(), StoreError> {
    conn.execute("DELETE FROM group_outbound_sessions WHERE group_id = ?1", params![group_id]).map_err(db_err)?;
    Ok(())
}

/// An inbound session and the device that owns it.
pub(crate) struct Inbound {
    pub session: InboundGroupSession,
    pub group_id: String,
    pub owner_user: String,
    pub owner_device: String,
}

pub(crate) fn load_inbound(conn: &Connection, pickle_key: &[u8; 32], session_id: &str) -> Result<Option<Inbound>, StoreError> {
    let row: Option<(String, String, String, String)> = conn
        .query_row(
            "SELECT pickle, group_id, owner_user, owner_device FROM group_inbound_sessions WHERE session_id = ?1",
            params![session_id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
        )
        .optional()
        .map_err(db_err)?;
    let Some((pickle, group_id, owner_user, owner_device)) = row else { return Ok(None) };
    let session = InboundGroupSession::from_pickle(InboundGroupSessionPickle::from_encrypted(&pickle, pickle_key).map_err(|_| StoreError::BadMessage)?);
    Ok(Some(Inbound { session, group_id, owner_user, owner_device }))
}

pub(crate) fn save_inbound(conn: &Connection, pickle_key: &[u8; 32], session_id: &str, i: &Inbound) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO group_inbound_sessions (session_id, group_id, owner_user, owner_device, pickle) VALUES (?1, ?2, ?3, ?4, ?5)
         ON CONFLICT (session_id) DO UPDATE SET pickle = ?5",
        params![session_id, i.group_id, i.owner_user, i.owner_device, i.session.pickle().encrypt(pickle_key)],
    )
    .map_err(db_err)?;
    Ok(())
}
