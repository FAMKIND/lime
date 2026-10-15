//! Group calls (LIME-112b): the rules and the storage. A group call is a LiveKit room (the SFU forwards each person's media once to
//! everyone), but **everything about who may be in it, whose key is whose, when keys change and when the call is over is decided
//! here**, so Android gets it for free. The phones' media is end-to-end encrypted with a key per sender; the keys travel only inside
//! Olm-encrypted group ops, so the SFU and the server only ever see ciphertext.
//!
//! Five signed ops ride the group conversation (`grp:<id>`), like `group.session`: `group.call.start` (a call id, a room, video or
//! not), `group.call.join` (the random LiveKit identity this phone uses), `group.call.key` (that participant's sender key and its
//! index; sent only to the people in the call), `group.call.key_request` (a safety net: "send me your current key again", from a person
//! in the call to the owner of one participant) and `group.call.leave`. Rules, all enforced on receive:
//!
//! - only a **current member** of the group (and only while this phone is in the group, and the group has not ended for me) can start,
//!   join, send a key or leave;
//! - a key is accepted only for a **known call in that group**, **from the person who owns that participant** (a participant id is
//!   claimed by the first signed op that names it, and is theirs from then on), and only while I am in the call myself;
//! - **when anyone leaves** (a `group.call.leave`, the SFU reporting them gone, or the group removing them) every phone still in the
//!   call makes a new key with the next index and sends it only to the people still in it, so someone who left cannot read on;
//! - a **member who is removed from the group, or who leaves it, gets no new keys** and is treated as having left the call;
//! - one active call at a time on this phone; the call **ends when nobody is in it**, which writes "Call ended" in the chat.
//!
//! Nothing here talks to a network: the ops this phone owes are queued in `group_call_outbox` and sent by
//! `LimeStore::deliver_group_call_ops`; what the app must act on waits in `group_call_events`.

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{json, Value};

use super::{db_err, groups, StoreError, ME_ID};
use crate::protocol::{Hlc, Op};

/// A group of up to this many people rings (through CallKit); a bigger one gets the chat line and a notification only.
pub(crate) const RING_MAX_MEMBERS: u32 = 10;
/// A start older than this is not rung (the call is probably over).
const STALE_START_MS: i64 = 60_000;
/// A call nobody has joined yet is still live for this long (the starter is on the way in).
const LIVE_WITHOUT_PEOPLE_MS: i64 = 120_000;
const MAX_PARTICIPANTS: i64 = 100;
const KEY_INDEX_MAX: u64 = 1_000_000;

pub(crate) const OPS: [&str; 5] = ["group.call.start", "group.call.join", "group.call.key", "group.call.key_request", "group.call.leave"];

pub(crate) fn is_group_call_op(op_type: &str) -> bool {
    OPS.contains(&op_type)
}

fn is_hex(text: &str, min: usize, max: usize) -> bool {
    (min..=max).contains(&text.len()) && text.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

pub(crate) fn random_bytes32() -> [u8; 32] {
    let mut out = [0u8; 32];
    out[..16].copy_from_slice(uuid::Uuid::new_v4().as_bytes());
    out[16..].copy_from_slice(uuid::Uuid::new_v4().as_bytes());
    out
}

pub(crate) fn random_hex(bytes: usize) -> String {
    let raw = random_bytes32();
    raw[..bytes.min(32)].iter().map(|b| format!("{b:02x}")).collect()
}

#[derive(Debug, Clone)]
pub(crate) struct CallRow {
    pub call_id: String,
    pub group_id: String,
    pub room: String,
    pub video: bool,
    pub started_by: String,
    pub started_at: i64,
    pub ended_at: Option<i64>,
    pub rang: bool,
    pub joined: bool,
    pub joined_at: Option<i64>,
    pub my_participant: Option<String>,
    pub my_key: Option<Vec<u8>>,
    pub my_key_index: u32,
}

const CALL_COLUMNS: &str = "call_id, group_id, room, video, started_by, started_at, ended_at, rang, joined, joined_at, my_participant, my_key, my_key_index";

fn read_call(r: &rusqlite::Row<'_>) -> rusqlite::Result<CallRow> {
    Ok(CallRow {
        call_id: r.get(0)?,
        group_id: r.get(1)?,
        room: r.get(2)?,
        video: r.get(3)?,
        started_by: r.get(4)?,
        started_at: r.get(5)?,
        ended_at: r.get(6)?,
        rang: r.get(7)?,
        joined: r.get(8)?,
        joined_at: r.get(9)?,
        my_participant: r.get(10)?,
        my_key: r.get(11)?,
        my_key_index: r.get::<_, i64>(12)? as u32,
    })
}

pub(crate) fn call_row(conn: &Connection, call_id: &str) -> Result<Option<CallRow>, StoreError> {
    conn.query_row(&format!("SELECT {CALL_COLUMNS} FROM group_calls WHERE call_id = ?1"), params![call_id], read_call).optional().map_err(db_err)
}

/// The call that is on in a group (not ended, and either someone is in it or it only just started), newest first.
pub(crate) fn live_call(conn: &Connection, group_id: &str, now: i64) -> Result<Option<CallRow>, StoreError> {
    let rows: Vec<CallRow> = {
        let mut statement = conn
            .prepare(&format!("SELECT {CALL_COLUMNS} FROM group_calls WHERE group_id = ?1 AND ended_at IS NULL ORDER BY started_at DESC"))
            .map_err(db_err)?;
        let rows = statement.query_map(params![group_id], read_call).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
        rows
    };
    for row in rows {
        if active_participants(conn, &row.call_id)?.is_empty() && now - row.started_at > LIVE_WITHOUT_PEOPLE_MS {
            continue;
        }
        return Ok(Some(row));
    }
    Ok(None)
}

/// The call this phone is in right now, if any.
pub(crate) fn my_current_call(conn: &Connection) -> Result<Option<CallRow>, StoreError> {
    conn.query_row(&format!("SELECT {CALL_COLUMNS} FROM group_calls WHERE joined = 1 AND ended_at IS NULL LIMIT 1"), [], read_call).optional().map_err(db_err)
}

/// `(participant, user)` for everyone in the call now.
pub(crate) fn active_participants(conn: &Connection, call_id: &str) -> Result<Vec<(String, String)>, StoreError> {
    let mut statement = conn
        .prepare("SELECT participant, user_id FROM group_call_participants WHERE call_id = ?1 AND left_at IS NULL ORDER BY joined_at, participant")
        .map_err(db_err)?;
    let rows = statement.query_map(params![call_id], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(rows)
}

/// How long after I renew my key the emoji wait for the others' renewed keys (a person's phone that never renews, for a leave it never saw,
/// must not keep the chip waiting for ever): after this the emoji show whatever keys are held.
const REKEY_SETTLE_MS: i64 = 15_000;

/// The call's four-emoji check (LIME-147, LIME-147b): `(how many people's keys I am still waiting for, the four indexes once I hold everyone's)`.
/// Everyone in the call counts, me included (my own current key is the one in the call row). I wait for a person's key when it has not arrived,
/// and, after someone left, when it has not been renewed as many times as mine has since I first saw them (every phone renews once per leave;
/// without this the phones would briefly show different emoji while the new keys travel). With nothing missing, the four come from
/// `call_emoji::group_emoji_for`.
pub(crate) fn emoji_state(conn: &Connection, call_id: &str, now: i64) -> Result<(u32, Option<[usize; 4]>), StoreError> {
    let Some(call) = call_row(conn, call_id)?.filter(|c| c.joined && c.ended_at.is_none()) else { return Ok((0, None)) };
    let (Some(mine), Some(my_key)) = (call.my_participant.as_deref(), call.my_key.as_deref()) else { return Ok((0, None)) };
    let last_rekey_at: i64 = conn.query_row("SELECT last_rekey_at FROM group_calls WHERE call_id = ?1", params![call_id], |r| r.get(0)).map_err(db_err)?;
    let settling = last_rekey_at > 0 && now - last_rekey_at <= REKEY_SETTLE_MS;
    let mut statement = conn
        .prepare("SELECT participant, key_hash, key_index, rekeys_at_join FROM group_call_participants WHERE call_id = ?1 AND left_at IS NULL")
        .map_err(db_err)?;
    let rows = statement
        .query_map(params![call_id], |r| Ok((r.get::<_, String>(0)?, r.get::<_, Option<Vec<u8>>>(1)?, r.get::<_, Option<i64>>(2)?, r.get::<_, i64>(3)?)))
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    let mut people: Vec<(String, [u8; 32])> = Vec::new();
    let mut waiting = 0u32;
    for (participant, hash, index, rekeys_at_join) in rows {
        if participant == mine {
            people.push((participant, crate::call_emoji::key_hash(my_key)));
            continue;
        }
        let Some(hash) = hash.and_then(|h| <[u8; 32]>::try_from(h.as_slice()).ok()) else {
            waiting += 1;
            continue;
        };
        let renewals_due = (call.my_key_index as i64 - rekeys_at_join).max(0);
        if settling && index.unwrap_or(0) < renewals_due {
            waiting += 1;
            continue;
        }
        people.push((participant, hash));
    }
    if waiting > 0 || people.is_empty() {
        return Ok((waiting, None));
    }
    Ok((0, Some(crate::call_emoji::group_emoji_for(call_id, people))))
}

fn person_name(conn: &Connection, user: &str) -> String {
    conn.query_row("SELECT name FROM people WHERE id = ?1", params![user], |r| r.get::<_, String>(0)).unwrap_or_else(|_| user.to_owned())
}

pub(crate) fn display_name(conn: &Connection, me: &str, user: &str) -> String {
    if user == me {
        "You".to_owned()
    } else {
        person_name(conn, user)
    }
}

fn push_event(conn: &Connection, kind: &str, call: &CallRow, user: &str, participant: &str, payload: Value, now: i64) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO group_call_events (kind, call_id, conversation_id, user_id, participant, payload, at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        params![kind, call.call_id, groups::conversation_id(&call.group_id), user, participant, payload.to_string(), now],
    )
    .map_err(db_err)?;
    Ok(())
}

/// Something the app should know that is not a state change: a key that was refused and why (for the call diagnostics; no key material).
#[allow(clippy::too_many_arguments)]
fn push_note(conn: &Connection, kind: &str, call_id: &str, group_id: &str, user: &str, participant: &str, payload: Value, now: i64) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO group_call_events (kind, call_id, conversation_id, user_id, participant, payload, at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        params![kind, call_id, groups::conversation_id(group_id), user, participant, payload.to_string(), now],
    )
    .map_err(db_err)?;
    Ok(())
}

fn enqueue(conn: &Connection, call_id: &str, to_user: &str, op_type: &str, payload: &Value) -> Result<(), StoreError> {
    conn.execute(
        "INSERT INTO group_call_outbox (call_id, to_user, op_type, payload) VALUES (?1, ?2, ?3, ?4)",
        params![call_id, to_user, op_type, payload.to_string()],
    )
    .map_err(db_err)?;
    Ok(())
}

/// Everyone in the group but me.
fn others(conn: &Connection, group_id: &str, me: &str) -> Result<Vec<String>, StoreError> {
    Ok(groups::state_of(conn, group_id)?.users().into_iter().filter(|u| u != me).collect())
}

fn key_payload(call: &CallRow) -> Option<Value> {
    let key = call.my_key.as_ref()?;
    Some(json!({ "call_id": call.call_id, "participant": call.my_participant, "key": vodozemac::base64_encode(key), "index": call.my_key_index }))
}

/// Sends this phone's current sender key to one person.
fn enqueue_my_key_to(conn: &Connection, call: &CallRow, user: &str) -> Result<(), StoreError> {
    if let Some(payload) = key_payload(call) {
        enqueue(conn, &call.call_id, user, "group.call.key", &payload)?;
    }
    Ok(())
}

/// Someone left: a new sender key with the next index, sent only to the people still in the call (and still in the group).
fn rotate_my_key(conn: &Connection, call: &CallRow, me: &str, now: i64) -> Result<(), StoreError> {
    if !call.joined || call.ended_at.is_some() {
        return Ok(());
    }
    let key = random_bytes32();
    let index = call.my_key_index + 1;
    conn.execute("UPDATE group_calls SET my_key = ?2, my_key_index = ?3, last_rekey_at = ?4 WHERE call_id = ?1", params![call.call_id, key.to_vec(), index, now]).map_err(db_err)?;
    // This phone must start sending with the new key too (the app sets it first, then the others get theirs): an event with MY participant,
    // the new key (raw bytes) and its index. Without it the phone would go on encrypting with the key everyone who left still holds.
    if let Some(mine) = call.my_participant.as_deref() {
        push_event(conn, "my_key", call, me, mine, json!({ "key": vodozemac::base64_encode(&key), "index": index }), now)?;
    }
    let members = groups::state_of(conn, &call.group_id)?;
    let updated = CallRow { my_key: Some(key.to_vec()), my_key_index: index, ..call.clone() };
    // Drop anything still queued with the old key for someone who has not received it: only the new one matters.
    conn.execute("DELETE FROM group_call_outbox WHERE call_id = ?1 AND op_type = 'group.call.key'", params![call.call_id]).map_err(db_err)?;
    let mut sent: Vec<String> = Vec::new();
    for (participant, user) in active_participants(conn, &call.call_id)? {
        if Some(&participant) == call.my_participant.as_ref() || user == me || !members.is_member(&user) || sent.contains(&user) {
            continue;
        }
        enqueue_my_key_to(conn, &updated, &user)?;
        sent.push(user);
    }
    Ok(())
}

/// The call ends when nobody is in it: the chat line says so and the call joins the call history.
fn finish_if_empty(conn: &Connection, call: &CallRow, me: &str, now: i64) -> Result<(), StoreError> {
    let anyone: i64 = conn.query_row("SELECT COUNT(*) FROM group_call_participants WHERE call_id = ?1", params![call.call_id], |r| r.get(0)).map_err(db_err)?;
    if anyone == 0 || !active_participants(conn, &call.call_id)?.is_empty() {
        return Ok(());
    }
    let Some(fresh) = call_row(conn, &call.call_id)? else { return Ok(()) };
    if fresh.ended_at.is_some() {
        return Ok(());
    }
    conn.execute("UPDATE group_calls SET ended_at = ?2, joined = 0 WHERE call_id = ?1", params![call.call_id, now]).map_err(db_err)?;
    conn.execute("DELETE FROM group_call_outbox WHERE call_id = ?1 AND op_type = 'group.call.key'", params![call.call_id]).map_err(db_err)?;
    let duration = (now - fresh.started_at).max(0);
    update_call_message(conn, &fresh, me, "completed", duration)?;
    // The call history: a call I was in, or a rung one I missed.
    let name: String = conn
        .query_row("SELECT title FROM conversations WHERE id = ?1", params![groups::conversation_id(&fresh.group_id)], |r| r.get(0))
        .unwrap_or_else(|_| "Group".to_owned());
    let outcome = if fresh.joined_at.is_some() {
        Some(("completed", now - fresh.joined_at.unwrap_or(now)))
    } else if fresh.rang {
        Some(("missed", 0))
    } else {
        None
    };
    if let Some((outcome, ms)) = outcome {
        conn.execute(
            "INSERT OR REPLACE INTO call_history (id, peer, peer_name, video, outgoing, at_ms, duration_ms, outcome, seen) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, COALESCE((SELECT seen FROM call_history WHERE id = ?1), 0))",
            params![fresh.call_id, groups::conversation_id(&fresh.group_id), name, fresh.video, fresh.started_by == me, fresh.started_at, ms.max(0), outcome],
        )
        .map_err(db_err)?;
    }
    push_event(conn, "ended", &fresh, "", "", json!({ "duration_ms": duration }), now)?;
    Ok(())
}

fn message_body(call: &CallRow, me: &str, outcome: &str, duration_ms: i64) -> String {
    json!({ "video": call.video, "duration_ms": duration_ms, "outcome": outcome, "outgoing": call.started_by == me, "group": true, "started_by": call.started_by }).to_string()
}

/// The call as a chat line (the same kind of message as a 1:1 call, id `call:<call_id>`): never sent, made on each phone.
fn insert_call_message(conn: &Connection, call: &CallRow, me: &str) -> Result<(), StoreError> {
    let conversation = groups::conversation_id(&call.group_id);
    let mine = call.started_by == me;
    conn.execute(
        "INSERT OR IGNORE INTO messages (id, conversation_id, sender_id, body, sent_at, local_state) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![super::calls::call_message_id(&call.call_id), conversation, if mine { ME_ID } else { call.started_by.as_str() }, message_body(call, me, "live", 0), call.started_at, if mine { "sent" } else { "received" }],
    )
    .map_err(db_err)?;
    Ok(())
}

fn update_call_message(conn: &Connection, call: &CallRow, me: &str, outcome: &str, duration_ms: i64) -> Result<(), StoreError> {
    conn.execute("UPDATE messages SET body = ?2 WHERE id = ?1", params![super::calls::call_message_id(&call.call_id), message_body(call, me, outcome, duration_ms)]).map_err(db_err)?;
    Ok(())
}

/// A group still waiting in Requests (a person I do not know made it) does not ring and cannot be joined until it is accepted.
fn accepted(conn: &Connection, group_id: &str) -> bool {
    conn.query_row("SELECT request_state = 'accepted' FROM conversations WHERE id = ?1", params![groups::conversation_id(group_id)], |r| r.get::<_, bool>(0)).unwrap_or(false)
}

fn conversation_ended(conn: &Connection, group_id: &str) -> bool {
    conn.query_row("SELECT group_ended IS NOT NULL FROM conversations WHERE id = ?1", params![groups::conversation_id(group_id)], |r| r.get::<_, bool>(0)).unwrap_or(true)
}

/// May `user` take part in this group's calls on this phone: a current member, while I am one too and the group has not ended for me.
fn allowed(conn: &Connection, group_id: &str, me: &str, user: &str) -> Result<bool, StoreError> {
    let state = groups::state_of(conn, group_id)?;
    Ok(state.created && !state.deleted && state.is_member(me) && state.is_member(user) && !conversation_ended(conn, group_id))
}

fn add_participant(conn: &Connection, call: &CallRow, participant: &str, user: &str, device: &str, now: i64) -> Result<bool, StoreError> {
    let count: i64 = conn.query_row("SELECT COUNT(*) FROM group_call_participants WHERE call_id = ?1", params![call.call_id], |r| r.get(0)).map_err(db_err)?;
    if count >= MAX_PARTICIPANTS {
        return Ok(false);
    }
    let added = conn
        .execute(
            "INSERT OR IGNORE INTO group_call_participants (call_id, participant, user_id, device_id, joined_at, rekeys_at_join) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![call.call_id, participant, user, device, now, call.my_key_index as i64],
        )
        .map_err(db_err)?;
    Ok(added > 0)
}

// ---------------------------------------------------------------- what other people's ops do here

/// A verified `group.call.*` op from `sender` (a group member's device `device`), applied if the rules allow it.
pub(crate) fn apply(conn: &Connection, me: &str, sender: &str, device: &str, group_id: &str, op: &Op, now: i64) -> Result<(), StoreError> {
    if !allowed(conn, group_id, me, sender)? {
        return Ok(());
    }
    let text = |key: &str| op.payload.get(key).and_then(Value::as_str).map(str::to_owned);
    let Some(call_id) = text("call_id").filter(|id| is_hex(id, 64, 64)) else { return Ok(()) };
    match op.op_type.as_str() {
        "group.call.start" => {
            let Some(room) = text("room").filter(|r| is_hex(r, 64, 64)) else { return Ok(()) };
            if call_row(conn, &call_id)?.is_some() {
                return Ok(());
            }
            let members = groups::state_of(conn, group_id)?.users().len() as u32;
            let fresh = Hlc::parse(&op.hlc).is_some_and(|h| now - h.wall <= STALE_START_MS);
            let video = op.payload.get("video").and_then(Value::as_bool).unwrap_or(false);
            let rang = fresh && members <= RING_MAX_MEMBERS && accepted(conn, group_id);
            conn.execute(
                "INSERT INTO group_calls (call_id, group_id, room, video, started_by, started_at, rang) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                params![call_id, group_id, room, video, sender, now, rang],
            )
            .map_err(db_err)?;
            let call = call_row(conn, &call_id)?.ok_or(StoreError::Database)?;
            insert_call_message(conn, &call, me)?;
            push_event(conn, "started", &call, sender, "", json!({ "video": video, "ring": rang, "members": members }), now)?;
        }
        "group.call.join" => {
            let Some(call) = call_row(conn, &call_id)?.filter(|c| c.group_id == group_id && c.ended_at.is_none()) else { return Ok(()) };
            let Some(participant) = text("participant").filter(|p| is_hex(p, 16, 64)) else { return Ok(()) };
            if add_participant(conn, &call, &participant, sender, device, now)? {
                push_event(conn, "joined", &call, sender, &participant, json!({}), now)?;
                // Someone arrived: they get my current sender key.
                if call.joined {
                    enqueue_my_key_to(conn, &call, sender)?;
                }
            }
        }
        "group.call.key" => {
            let reject = |reason: &str, participant: &str| push_note(conn, "key_rejected", &call_id, group_id, sender, participant, json!({ "reason": reason }), now);
            let Some(call) = call_row(conn, &call_id)?.filter(|c| c.group_id == group_id && c.ended_at.is_none()) else { return reject("unknown_call", "") };
            let Some(participant) = text("participant").filter(|p| is_hex(p, 16, 64)) else { return reject("bad_participant", "") };
            if !call.joined {
                return reject("not_in_call", &participant);
            }
            let key = text("key").and_then(|k| vodozemac::base64_decode(k).ok()).filter(|k| k.len() == 32);
            let index = op.payload.get("index").and_then(Value::as_u64).filter(|i| *i <= KEY_INDEX_MAX);
            let (Some(key), Some(index)) = (key, index) else { return reject("bad_key", &participant) };
            // The participant must be this sender's: known and theirs, or claimed now by this first signed op that names it.
            let owner: Option<(String, String, Option<i64>)> = conn
                .query_row("SELECT user_id, device_id, left_at FROM group_call_participants WHERE call_id = ?1 AND participant = ?2", params![call_id, participant], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))
                .optional()
                .map_err(db_err)?;
            match owner {
                Some((user, dev, left)) if user == sender && dev == device && left.is_none() => {}
                Some((_, _, Some(_))) => return reject("participant_left", &participant),
                Some(_) => return reject("not_owner", &participant),
                None => {
                    if !add_participant(conn, &call, &participant, sender, device, now)? {
                        return reject("call_full", &participant);
                    }
                    push_event(conn, "joined", &call, sender, &participant, json!({}), now)?;
                    // First sighting of this person (their key overtook their join): they get my key too, as a join would have sent it.
                    enqueue_my_key_to(conn, &call, sender)?;
                }
            }
            // Only the hash of their current key is kept (for the emoji check): the newest index wins.
            conn.execute(
                "UPDATE group_call_participants SET key_hash = ?3, key_index = ?4 WHERE call_id = ?1 AND participant = ?2 AND (key_index IS NULL OR key_index <= ?4)",
                params![call_id, participant, crate::call_emoji::key_hash(&key).to_vec(), index as i64],
            )
            .map_err(db_err)?;
            push_event(conn, "key", &call, sender, &participant, json!({ "key": vodozemac::base64_encode(&key), "index": index }), now)?;
        }
        "group.call.key_request" => {
            // "Send me your current key again": from a person in the call, for the participant that is mine.
            let Some(call) = call_row(conn, &call_id)?.filter(|c| c.group_id == group_id && c.ended_at.is_none() && c.joined) else { return Ok(()) };
            let Some(wanted) = text("participant").filter(|p| is_hex(p, 16, 64)) else { return Ok(()) };
            if call.my_participant.as_deref() != Some(wanted.as_str()) {
                return Ok(());
            }
            if active_participants(conn, &call_id)?.iter().any(|(_, user)| user == sender) {
                enqueue_my_key_to(conn, &call, sender)?;
            }
        }
        "group.call.leave" => {
            let Some(call) = call_row(conn, &call_id)?.filter(|c| c.group_id == group_id && c.ended_at.is_none()) else { return Ok(()) };
            let Some(participant) = text("participant").filter(|p| is_hex(p, 16, 64)) else { return Ok(()) };
            let changed = conn
                .execute(
                    "UPDATE group_call_participants SET left_at = ?4 WHERE call_id = ?1 AND participant = ?2 AND user_id = ?3 AND left_at IS NULL",
                    params![call_id, participant, sender, now],
                )
                .map_err(db_err)?;
            if changed > 0 {
                push_event(conn, "left", &call, sender, &participant, json!({}), now)?;
                rotate_my_key(conn, &call, me, now)?;
                finish_if_empty(conn, &call, me, now)?;
            }
        }
        _ => {}
    }
    Ok(())
}

/// The group's membership changed (someone removed, someone left, or I was): anyone in a call who is no longer a member is treated as
/// having left it, and the people still in it get a new key.
pub(crate) fn on_membership_changed(conn: &Connection, group_id: &str, me: &str, now: i64) -> Result<(), StoreError> {
    let state = groups::state_of(conn, group_id)?;
    if !state.is_member(me) {
        // I am out of the group: out of its calls too (nobody is told: I can no longer send to them).
        conn.execute("UPDATE group_call_participants SET left_at = ?2 WHERE user_id = ?3 AND left_at IS NULL AND call_id IN (SELECT call_id FROM group_calls WHERE group_id = ?1 AND ended_at IS NULL)", params![group_id, now, me]).map_err(db_err)?;
        conn.execute("UPDATE group_calls SET joined = 0, my_key = NULL WHERE group_id = ?1 AND joined = 1", params![group_id]).map_err(db_err)?;
        conn.execute("DELETE FROM group_call_outbox WHERE call_id IN (SELECT call_id FROM group_calls WHERE group_id = ?1)", params![group_id]).map_err(db_err)?;
        return Ok(());
    }
    let calls: Vec<CallRow> = {
        let mut statement = conn.prepare(&format!("SELECT {CALL_COLUMNS} FROM group_calls WHERE group_id = ?1 AND ended_at IS NULL")).map_err(db_err)?;
        let rows = statement.query_map(params![group_id], read_call).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
        rows
    };
    for call in calls {
        let mut removed = false;
        for (participant, user) in active_participants(conn, &call.call_id)? {
            if user != me && !state.is_member(&user) {
                conn.execute("UPDATE group_call_participants SET left_at = ?3 WHERE call_id = ?1 AND participant = ?2", params![call.call_id, participant, now]).map_err(db_err)?;
                push_event(conn, "left", &call, &user, &participant, json!({}), now)?;
                removed = true;
            }
        }
        if removed {
            rotate_my_key(conn, &call, me, now)?;
            finish_if_empty(conn, &call, me, now)?;
        }
    }
    Ok(())
}

// ---------------------------------------------------------------- what this phone does

/// What the app needs to join a call.
pub(crate) struct Joined {
    pub participant: String,
    pub key: Vec<u8>,
    pub index: u32,
    pub others: Vec<(String, String)>,
}

/// Starts a call in a group: the call, its chat line, and a `group.call.start` for everyone else. Returns the live call if there already is
/// one (a second tap joins rather than starting another).
pub(crate) fn local_start(conn: &Connection, me: &str, group_id: &str, video: bool, now: i64) -> Result<CallRow, StoreError> {
    let state = groups::state_of(conn, group_id)?;
    if !state.created || state.deleted || !state.is_member(me) || conversation_ended(conn, group_id) || !accepted(conn, group_id) {
        return Err(StoreError::Rejected);
    }
    if let Some(live) = live_call(conn, group_id, now)? {
        return Ok(live);
    }
    if my_current_call(conn)?.is_some() {
        return Err(StoreError::Rejected);
    }
    let call_id = random_hex(32);
    let room = random_hex(32);
    conn.execute(
        "INSERT INTO group_calls (call_id, group_id, room, video, started_by, started_at, rang) VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0)",
        params![call_id, group_id, room, video, me, now],
    )
    .map_err(db_err)?;
    let call = call_row(conn, &call_id)?.ok_or(StoreError::Database)?;
    insert_call_message(conn, &call, me)?;
    let payload = json!({ "call_id": call_id, "room": room, "video": video });
    for user in others(conn, group_id, me)? {
        enqueue(conn, &call_id, &user, "group.call.start", &payload)?;
    }
    Ok(call)
}

/// Joins a live call: this phone's random participant id and first sender key, a `group.call.join` for everyone in the group, and the key
/// for everyone already in the call.
pub(crate) fn local_join(conn: &Connection, me: &str, device: &str, call_id: &str, now: i64) -> Result<Joined, StoreError> {
    let call = call_row(conn, call_id)?.ok_or(StoreError::NotFound)?;
    if call.ended_at.is_some() || !allowed(conn, &call.group_id, me, me)? || !accepted(conn, &call.group_id) {
        return Err(StoreError::Rejected);
    }
    if call.joined {
        return Err(StoreError::Rejected);
    }
    if my_current_call(conn)?.is_some() {
        return Err(StoreError::Rejected);
    }
    let participant = random_hex(16);
    let key = random_bytes32();
    conn.execute(
        "UPDATE group_calls SET joined = 1, joined_at = ?2, my_participant = ?3, my_key = ?4, my_key_index = 0 WHERE call_id = ?1",
        params![call_id, now, participant, key.to_vec()],
    )
    .map_err(db_err)?;
    let call = call_row(conn, call_id)?.ok_or(StoreError::Database)?;
    // Who is in already (before me), so I can send each their key and the app can wait for theirs.
    let present = active_participants(conn, call_id)?;
    if !add_participant(conn, &call, &participant, me, device, now)? {
        conn.execute("UPDATE group_calls SET joined = 0, joined_at = NULL, my_participant = NULL, my_key = NULL WHERE call_id = ?1", params![call_id]).map_err(db_err)?;
        return Err(StoreError::Rejected);
    }
    let members = others(conn, &call.group_id, me)?;
    let join = json!({ "call_id": call_id, "participant": participant });
    for user in &members {
        enqueue(conn, call_id, user, "group.call.join", &join)?;
    }
    let mut sent: Vec<&String> = Vec::new();
    for (_, user) in &present {
        if user != me && members.contains(user) && !sent.contains(&user) {
            enqueue_my_key_to(conn, &call, user)?;
            sent.push(user);
        }
    }
    Ok(Joined { participant, key: key.to_vec(), index: 0, others: present })
}

/// Leaves the call (the app hung up): a `group.call.leave` for everyone; the others make new keys.
pub(crate) fn local_leave(conn: &Connection, me: &str, call_id: &str, now: i64) -> Result<(), StoreError> {
    let call = call_row(conn, call_id)?.ok_or(StoreError::NotFound)?;
    let Some(participant) = call.my_participant.clone().filter(|_| call.joined) else { return Ok(()) };
    conn.execute("UPDATE group_call_participants SET left_at = ?3 WHERE call_id = ?1 AND participant = ?2 AND left_at IS NULL", params![call_id, participant, now]).map_err(db_err)?;
    conn.execute("UPDATE group_calls SET joined = 0, my_key = NULL WHERE call_id = ?1", params![call_id]).map_err(db_err)?;
    // My own pending keys are moot.
    conn.execute("DELETE FROM group_call_outbox WHERE call_id = ?1 AND op_type = 'group.call.key'", params![call_id]).map_err(db_err)?;
    let leave = json!({ "call_id": call_id, "participant": participant });
    for user in others(conn, &call.group_id, me)? {
        enqueue(conn, call_id, &user, "group.call.leave", &leave)?;
    }
    finish_if_empty(conn, &call, me, now)?;
    Ok(())
}

/// The SFU reports a participant gone without a leave (their phone dropped): treated as having left.
pub(crate) fn local_participant_gone(conn: &Connection, me: &str, call_id: &str, participant: &str, now: i64) -> Result<(), StoreError> {
    let Some(call) = call_row(conn, call_id)?.filter(|c| c.ended_at.is_none()) else { return Ok(()) };
    if call.my_participant.as_deref() == Some(participant) {
        return Ok(());
    }
    let who: Option<String> = conn
        .query_row("SELECT user_id FROM group_call_participants WHERE call_id = ?1 AND participant = ?2 AND left_at IS NULL", params![call_id, participant], |r| r.get(0))
        .optional()
        .map_err(db_err)?;
    let Some(user) = who else { return Ok(()) };
    conn.execute("UPDATE group_call_participants SET left_at = ?3 WHERE call_id = ?1 AND participant = ?2", params![call_id, participant, now]).map_err(db_err)?;
    push_event(conn, "left", &call, &user, participant, json!({}), now)?;
    rotate_my_key(conn, &call, me, now)?;
    finish_if_empty(conn, &call, me, now)?;
    Ok(())
}

/// Asks the owner of `participant` to send me their current key again (a tile stuck without one): queued for them only.
pub(crate) fn local_request_key(conn: &Connection, me: &str, call_id: &str, participant: &str) -> Result<(), StoreError> {
    let call = call_row(conn, call_id)?.filter(|c| c.ended_at.is_none() && c.joined).ok_or(StoreError::Rejected)?;
    let owner: Option<String> = conn
        .query_row("SELECT user_id FROM group_call_participants WHERE call_id = ?1 AND participant = ?2 AND left_at IS NULL", params![call_id, participant], |r| r.get(0))
        .optional()
        .map_err(db_err)?;
    let state = groups::state_of(conn, &call.group_id)?;
    let Some(owner) = owner.filter(|u| u != me && state.is_member(u)) else { return Ok(()) };
    enqueue(conn, call_id, &owner, "group.call.key_request", &json!({ "call_id": call_id, "participant": participant }))
}

/// `(id, call_id, to_user, op_type, payload)` for each op still owed.
pub(crate) type Owed = (i64, String, String, String, String);

pub(crate) fn outbox(conn: &Connection) -> Result<Vec<Owed>, StoreError> {
    let mut statement = conn.prepare("SELECT id, call_id, to_user, op_type, payload FROM group_call_outbox ORDER BY id").map_err(db_err)?;
    let rows = statement.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?))).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(rows)
}

pub(crate) fn dequeue(conn: &Connection, id: i64) -> Result<(), StoreError> {
    conn.execute("DELETE FROM group_call_outbox WHERE id = ?1", params![id]).map_err(db_err)?;
    Ok(())
}
