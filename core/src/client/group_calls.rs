//! Group calls on the client (LIME-112b; the rules are in `store::group_calls`, the ops in `docs/api-v2.md`). The core decides who may
//! start, join, receive a key and when keys change; the app (a thin adapter over the LiveKit SDK and CallKit) asks and obeys.

use super::*;
use crate::store::group_calls as rules;
use crate::store::groups;

/// A group call, for the chat line, the "Join" pill and the call screen.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct GroupCallInfo {
    pub call_id: String,
    pub conversation_id: String,
    /// The LiveKit room (64 hex characters; holding it is the capability to ask for a token).
    pub room: String,
    pub video: bool,
    pub started_by: String,
    pub started_by_name: String,
    pub started_at_ms: i64,
    pub participant_count: u32,
    /// This phone is in the call now.
    pub joined: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct GroupCallParticipant {
    pub participant: String,
    pub user_id: String,
    pub name: String,
}

/// What the app needs to connect after `join_group_call`.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct GroupCallJoin {
    pub call: GroupCallInfo,
    /// This phone's random LiveKit identity.
    pub participant: String,
    /// This phone's first sender key (32 raw bytes, not text, so no encoding can go wrong on any platform) and its index: the only key material that crosses to the app, for the frame encryption.
    pub key: Vec<u8>,
    pub key_index: u32,
    /// Who is in the call already (their keys arrive as `key` events).
    pub participants: Vec<GroupCallParticipant>,
}

/// Something the app must act on. `kind`: `started` (a call began: `ring` says whether to ring, `video`), `joined` and `left`
/// (`participant`, `user_id`), `key` (`participant`'s sender key as raw bytes and its index: set it in the frame encryption), `key_rejected` (`reason`: a key was refused, for the diagnostics), `ended`.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct GroupCallEvent {
    pub kind: String,
    pub call_id: String,
    pub conversation_id: String,
    pub user_id: String,
    pub name: String,
    pub participant: String,
    pub video: bool,
    pub ring: bool,
    pub key: Option<Vec<u8>>,
    pub key_index: u32,
    pub duration_ms: i64,
    /// For `key_rejected`: why the core refused a key (`unknown_call`, `not_in_call`, `bad_key`, `not_owner`, `participant_left`, ...). No key material.
    pub reason: String,
}

/// The four-emoji check of a group call (LIME-147). `ready` is false (and `emoji` empty) while any person's key has not arrived (`waiting` of
/// them): no emoji until everyone's key is in. Recomputed by the app after every key, join and leave event.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct GroupCallEmojiState {
    pub ready: bool,
    pub waiting: u32,
    pub emoji: Vec<crate::CallEmoji>,
}

/// What one pass of `deliver_group_call_ops` did (for the call diagnostics): how many ops went, how many of them were keys (and the index of the
/// last), and how many wait because a person's key changed.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct GroupCallSendReport {
    pub sent: u32,
    pub keys_sent: u32,
    pub waiting: u32,
    pub last_key_index: u32,
}

/// A short-lived token for the LiveKit server (see `supabase/functions/livekit-token`).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct LiveKitToken {
    pub url: String,
    pub token: String,
    pub ttl_seconds: u32,
}

/// Whether a group of this many people (counting me) rings: up to 10 do, bigger ones get a chat line and a notification.
#[uniffi::export]
pub fn group_call_rings(member_count: u32) -> bool {
    member_count <= rules::RING_MAX_MEMBERS
}

fn info(conn: &Connection, me: &str, call: &rules::CallRow) -> Result<GroupCallInfo, StoreError> {
    let count = rules::active_participants(conn, &call.call_id)?.len() as u32;
    Ok(GroupCallInfo {
        call_id: call.call_id.clone(),
        conversation_id: groups::conversation_id(&call.group_id),
        room: call.room.clone(),
        video: call.video,
        started_by: call.started_by.clone(),
        started_by_name: rules::display_name(conn, me, &call.started_by),
        started_at_ms: call.started_at,
        participant_count: count,
        joined: call.joined,
    })
}

#[uniffi::export]
impl LimeStore {
    /// Starts a call in a group (a member, in a group that has not ended, one call at a time on this phone), or returns the one already on.
    /// Queues the `group.call.start` for everyone else (`deliver_group_call_ops` sends it) and writes "<Name> started a call" in the chat.
    pub fn start_group_call(&self, conversation_id: String, video: bool) -> Result<GroupCallInfo, StoreError> {
        let _guard = self.lock_protocol();
        let (group_id, _state, me) = self.group_context(&conversation_id)?;
        self.with_conn(|conn| {
            let call = rules::local_start(conn, &me, &group_id, video, now_ms())?;
            info(conn, &me, &call)
        })
    }

    /// Joins a call: this phone's identity and first sender key. The people in the call get this phone's join and key once
    /// `deliver_group_call_ops` has run; theirs arrive as events.
    pub fn join_group_call(&self, call_id: String) -> Result<GroupCallJoin, StoreError> {
        let _guard = self.lock_protocol();
        let state = self.load_or_create_account()?;
        let me = state.user_id.clone().filter(|_| state.registered).ok_or(StoreError::NotRegistered)?;
        self.with_conn(|conn| {
            let joined = rules::local_join(conn, &me, &state.device_id, &call_id, now_ms())?;
            let call = rules::call_row(conn, &call_id)?.ok_or(StoreError::NotFound)?;
            let participants = joined
                .others
                .iter()
                .map(|(participant, user)| GroupCallParticipant { participant: participant.clone(), user_id: user.clone(), name: rules::display_name(conn, &me, user) })
                .collect();
            Ok(GroupCallJoin {
                call: info(conn, &me, &call)?,
                participant: joined.participant,
                key: joined.key.clone(),
                key_index: joined.index,
                participants,
            })
        })
    }

    /// The app hung up: everyone else gets a leave and makes a new key.
    pub fn leave_group_call(&self, call_id: String) -> Result<(), StoreError> {
        let _guard = self.lock_protocol();
        let state = self.load_or_create_account()?;
        let me = state.user_id.clone().filter(|_| state.registered).ok_or(StoreError::NotRegistered)?;
        self.with_conn(|conn| rules::local_leave(conn, &me, &call_id, now_ms()))
    }

    /// The media server says this participant is gone without a leave (their phone dropped): treated as having left, and the people still
    /// in the call get a new key.
    pub fn group_call_participant_gone(&self, call_id: String, participant: String) -> Result<(), StoreError> {
        let _guard = self.lock_protocol();
        let state = self.load_or_create_account()?;
        let me = state.user_id.clone().filter(|_| state.registered).ok_or(StoreError::NotRegistered)?;
        self.with_conn(|conn| rules::local_participant_gone(conn, &me, &call_id, &participant, now_ms()))
    }

    /// The call that is on in this group (for the chat's "Join" pill), or none.
    pub fn active_group_call(&self, conversation_id: String) -> Result<Option<GroupCallInfo>, StoreError> {
        let Some(group_id) = groups::group_id_of(&conversation_id).map(str::to_owned) else { return Ok(None) };
        let state = self.load_or_create_account()?;
        let me = state.user_id.clone().unwrap_or_default();
        self.with_conn(|conn| match rules::live_call(conn, &group_id, now_ms())? {
            Some(call) => Ok(Some(info(conn, &me, &call)?)),
            None => Ok(None),
        })
    }

    /// Everything the app has not acted on yet, oldest first; removed as returned.
    pub fn take_group_call_events(&self) -> Result<Vec<GroupCallEvent>, StoreError> {
        let state = self.load_or_create_account()?;
        let me = state.user_id.clone().unwrap_or_default();
        let conn = self.lock();
        let rows: Vec<(i64, String, String, String, String, String, String)> = {
            let mut statement = conn.prepare("SELECT id, kind, call_id, conversation_id, user_id, participant, payload FROM group_call_events ORDER BY id").map_err(db_err)?;
            let rows = statement
                .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?, r.get(6)?)))
                .map_err(db_err)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(db_err)?;
            rows
        };
        if let Some(last) = rows.last() {
            conn.execute("DELETE FROM group_call_events WHERE id <= ?1", params![last.0]).map_err(db_err)?;
        }
        Ok(rows
            .into_iter()
            .map(|(_, kind, call_id, conversation_id, user_id, participant, payload)| {
                let payload: Value = serde_json::from_str(&payload).unwrap_or(Value::Null);
                GroupCallEvent {
                    name: if user_id.is_empty() { String::new() } else { rules::display_name(&conn, &me, &user_id) },
                    kind,
                    call_id,
                    conversation_id,
                    user_id,
                    participant,
                    video: payload.get("video").and_then(Value::as_bool).unwrap_or(false),
                    ring: payload.get("ring").and_then(Value::as_bool).unwrap_or(false),
                    key: payload.get("key").and_then(Value::as_str).and_then(|k| vodozemac::base64_decode(k).ok()),
                    key_index: payload.get("index").and_then(Value::as_u64).unwrap_or(0) as u32,
                    duration_ms: payload.get("duration_ms").and_then(Value::as_i64).unwrap_or(0),
                    reason: payload.get("reason").and_then(Value::as_str).unwrap_or_default().to_owned(),
                }
            })
            .collect())
    }

    /// Sends what this phone owes the others (starts, joins, keys, leaves), oldest first. A person whose key changed waits; one with no
    /// devices is dropped; a network failure stops the pass and the rest stays queued. Call it after every action and after `sync`.
    pub fn deliver_group_call_ops(&self, transport: Arc<dyn Transport>, auth_token: String) -> Result<GroupCallSendReport, StoreError> {
        let _guard = self.lock_protocol();
        let mut state = self.load_or_create_account()?;
        let me = state.user_id.clone().filter(|_| state.registered).ok_or(StoreError::NotRegistered)?;
        let rows = self.with_conn(rules::outbox)?;
        let mut report = GroupCallSendReport { sent: 0, keys_sent: 0, waiting: 0, last_key_index: 0 };
        for (id, call_id, recipient, op_type, payload) in rows {
            let group_id = self.with_conn(|conn| Ok(rules::call_row(conn, &call_id)?.map(|c| c.group_id)))?;
            let (Some(group_id), Ok(payload)) = (group_id, serde_json::from_str::<Value>(&payload)) else {
                let _ = self.with_conn(|conn| rules::dequeue(conn, id));
                continue;
            };
            // Never to someone who is no longer in the group (a member removed, or who left, gets no new keys).
            let member = self.with_conn(|conn| Ok(groups::state_of(conn, &group_id)?.is_member(&recipient)))?;
            if !member {
                let _ = self.with_conn(|conn| rules::dequeue(conn, id));
                continue;
            }
            let hlc = self.with_conn(|conn| tick_hlc(conn, now_ms()))?;
            let mut op = Op {
                op_id: new_id(),
                op_type,
                conversation_id: groups::conversation_id(&group_id),
                hlc: hlc.render(),
                parents: vec![],
                payload,
                sig: String::new(),
            };
            op.sig = state.account.sign(op.signing_bytes()).to_base64();
            let is_key = op.op_type == "group.call.key";
            let index = op.payload.get("index").and_then(Value::as_u64).unwrap_or(0) as u32;
            match self.send_to_user(&transport, &auth_token, &mut state, &me, &recipient, op) {
                Ok(()) | Err(StoreError::NoRecipientKeys) => {
                    let _ = self.with_conn(|conn| rules::dequeue(conn, id));
                    report.sent += 1;
                    if is_key {
                        report.keys_sent += 1;
                        report.last_key_index = index;
                    }
                }
                Err(StoreError::KeyMismatch) => report.waiting += 1,
                Err(error) => return Err(error),
            }
        }
        Ok(report)
    }

    /// The call's four-emoji check from everyone's current keys, all held by the core (the app never assembles the input): empty and not
    /// `ready` until every person in the call has sent their key. See `call_emoji::group_emoji_for`.
    pub fn group_call_emoji_state(&self, call_id: String) -> Result<GroupCallEmojiState, StoreError> {
        self.with_conn(|conn| {
            let (waiting, indexes) = rules::emoji_state(conn, &call_id)?;
            Ok(match indexes {
                Some(indexes) => GroupCallEmojiState { ready: true, waiting: 0, emoji: crate::call_emoji::emoji_records(indexes) },
                None => GroupCallEmojiState { ready: false, waiting, emoji: Vec::new() },
            })
        })
    }

    /// A tile has been stuck without a key: asks the owner of `participant` to send their current key again (queued; `deliver_group_call_ops` sends it).
    pub fn request_group_call_key(&self, call_id: String, participant: String) -> Result<(), StoreError> {
        let _guard = self.lock_protocol();
        let state = self.load_or_create_account()?;
        let me = state.user_id.clone().filter(|_| state.registered).ok_or(StoreError::NotRegistered)?;
        self.with_conn(|conn| rules::local_request_key(conn, &me, &call_id, &participant))
    }

    /// Asks the server for a join token for a call's room (a signed-in session only). `None` when group calls are not set up there yet.
    pub fn fetch_livekit_token(&self, transport: Arc<dyn Transport>, auth_token: String, room: String, participant: String) -> Result<Option<LiveKitToken>, StoreError> {
        let (status, body) = call(&transport, Some(&auth_token), "livekit-token", &json!({ "room": room, "participant": participant }))?;
        if status == 503 {
            return Ok(None);
        }
        check(status)?;
        let text = |k: &str| body.get(k).and_then(Value::as_str).map(str::to_owned);
        let (Some(url), Some(token)) = (text("url"), text("token")) else { return Err(StoreError::BadMessage) };
        Ok(Some(LiveKitToken { url, token, ttl_seconds: body.get("ttl").and_then(Value::as_u64).unwrap_or(600) as u32 }))
    }
}
