//! Group chats on the client (LIME-97, `docs/api-v2.md` sections 3, 5 and 6).
//!
//! - **State** is client-managed: signed `group.*` ops, sent to every member device over Olm (sealed where we hold the
//!   person's delivery key), stored in a log and replayed (`protocol::group`) so every device reaches the same
//!   members, roles and name. The server holds none of it.
//! - **Messages** use Megolm: each sending device has one outbound session per group and gives its key to every
//!   member device in a `group.session` op over Olm. A message is encrypted once and the same ciphertext goes to
//!   every member device (a shared ciphertext plus a list of recipients). The session is replaced on any
//!   membership change, after 100 messages and after 7 days, so a removed member cannot read what follows.
//! - **Someone added** is sent the whole op log (a `group.history` op carrying the original signed envelopes) so they
//!   can replay it; a message from before they joined cannot be read, because it used an older session.

use vodozemac::megolm::{GroupSession, InboundGroupSession, MegolmMessage, SessionConfig as MegolmConfig, SessionKey};

use super::*;
use crate::protocol::group::{clean_emoji, clean_name, GroupPhoto, Kind, Role, MAX_MEMBERS};
use crate::protocol::SenderCert;
use crate::store::groups;

/// The first byte of a group message's wire text (an Olm message starts with 0 or 1).
pub(super) const GROUP_WIRE: u8 = 2;
/// A session is replaced after this many messages, or this long.
const ROTATE_AFTER_MESSAGES: i64 = 100;
const ROTATE_AFTER_MS: i64 = 7 * 24 * 3_600 * 1000;
/// State ops per `group.history` item (an item may not exceed 64 KB).
const HISTORY_CHUNK: usize = 12;
/// Recipients per `send` request.
const SEND_CHUNK: usize = 100;

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct GroupMemberInfo {
    pub user_id: String,
    pub name: String,
    pub tone: u32,
    /// `owner`, `admin` or `member`.
    pub role: String,
    pub is_me: bool,
    /// I may remove this person.
    pub can_remove: bool,
    /// My private label for this person (shown only to me).
    pub label: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct GroupDetails {
    pub conversation_id: String,
    pub name: String,
    pub emoji: Option<String>,
    /// The group has an (encrypted) photo.
    pub has_photo: bool,
    pub my_role: String,
    pub members: Vec<GroupMemberInfo>,
    pub can_rename: bool,
    pub can_add: bool,
    pub max_members: u32,
}

#[uniffi::export]
impl LimeStore {
    /// Makes a group with the people listed (not counting me; I am the owner) and queues the news to each of them.
    /// Returns the conversation id. Nothing is sent yet: the next delivery does that.
    pub fn create_group(&self, name: String, emoji: Option<String>, members: Vec<String>) -> Result<String, StoreError> {
        let name = clean_name(&name).ok_or(StoreError::Rejected)?;
        let state = self.load_or_create_account()?;
        let me = state.user_id.clone().filter(|_| state.registered).ok_or(StoreError::NotRegistered)?;
        let mut people: Vec<String> = Vec::new();
        for user in members {
            if user != me && !user.is_empty() && !people.contains(&user) {
                people.push(user);
            }
        }
        if people.is_empty() || people.len() + 1 > MAX_MEMBERS {
            return Err(StoreError::Rejected);
        }
        let group_id = new_id();
        self.make_group_op(&state, &me, &group_id, Some(group_id.clone()), Kind::Create { name, emoji: clean_emoji(&emoji), members: people })?;
        Ok(groups::conversation_id(&group_id))
    }

    /// The group's name, avatar, my role and the people in it, with what I may do.
    pub fn group_details(&self, conversation_id: String) -> Result<GroupDetails, StoreError> {
        let group_id = groups::group_id_of(&conversation_id).ok_or(StoreError::NotFound)?.to_owned();
        let state = self.load_or_create_account()?;
        let me = state.user_id.clone().ok_or(StoreError::NotRegistered)?;
        self.with_conn(|conn| {
            let group = groups::state_of(conn, &group_id)?;
            if !group.created {
                return Err(StoreError::NotFound);
            }
            let my_role = group.role_of(&me).map(Role::as_str).unwrap_or("none").to_owned();
            let members = groups::members_with_names(conn, &group_id)?
                .into_iter()
                .map(|(user_id, role, name, tone)| GroupMemberInfo {
                    is_me: user_id == me,
                    can_remove: group.may_remove(&me, &user_id),
                    name: if user_id == me { "You".to_owned() } else { name },
                    label: crate::store::labels::get(conn, &user_id).ok().flatten(),
                    user_id,
                    tone,
                    role,
                })
                .collect();
            Ok(GroupDetails {
                conversation_id: conversation_id.clone(),
                name: group.name.clone(),
                emoji: group.emoji.clone(),
                has_photo: group.photo.is_some(),
                my_role,
                members,
                can_rename: group.may_manage(&me),
                can_add: group.may_manage(&me) && group.members.len() < MAX_MEMBERS,
                max_members: MAX_MEMBERS as u32,
            })
        })
    }

    /// Adds people (the owner and admins may). They are sent the group's history and, with the next message, a new key.
    pub fn add_group_members(&self, conversation_id: String, user_ids: Vec<String>) -> Result<(), StoreError> {
        let (group_id, state, me) = self.group_context(&conversation_id)?;
        let before = self.with_conn(|conn| groups::state_of(conn, &group_id))?;
        let mut users: Vec<String> = Vec::new();
        for user in user_ids {
            if !before.is_member(&user) && !users.contains(&user) && user != me {
                users.push(user);
            }
        }
        if users.is_empty() {
            return Ok(());
        }
        if !before.may_manage(&me) || before.members.len() + users.len() > MAX_MEMBERS {
            return Err(StoreError::Rejected);
        }
        self.make_group_op(&state, &me, &group_id, None, Kind::Add { users })
    }

    /// Removes a person (the owner removes anyone but themselves; an admin removes plain members).
    pub fn remove_group_member(&self, conversation_id: String, user_id: String) -> Result<(), StoreError> {
        let (group_id, state, me) = self.group_context(&conversation_id)?;
        let before = self.with_conn(|conn| groups::state_of(conn, &group_id))?;
        if !before.may_remove(&me, &user_id) {
            return Err(StoreError::Rejected);
        }
        self.make_group_op(&state, &me, &group_id, None, Kind::Remove { user: user_id })
    }

    /// Renames the group (the owner and admins may).
    pub fn rename_group(&self, conversation_id: String, name: String) -> Result<(), StoreError> {
        let (group_id, state, me) = self.group_context(&conversation_id)?;
        let name = clean_name(&name).ok_or(StoreError::Rejected)?;
        let before = self.with_conn(|conn| groups::state_of(conn, &group_id))?;
        if !before.may_manage(&me) {
            return Err(StoreError::Rejected);
        }
        self.make_group_op(&state, &me, &group_id, None, Kind::Rename { name })
    }

    /// Sets (or clears) the group's emoji avatar (the owner and admins may).
    pub fn set_group_emoji(&self, conversation_id: String, emoji: Option<String>) -> Result<(), StoreError> {
        let (group_id, state, me) = self.group_context(&conversation_id)?;
        let before = self.with_conn(|conn| groups::state_of(conn, &group_id))?;
        if !before.may_manage(&me) {
            return Err(StoreError::Rejected);
        }
        self.make_group_op(&state, &me, &group_id, None, Kind::SetAvatar { emoji: clean_emoji(&emoji), photo: None })
    }

    /// Sets the group's emoji avatar and deletes the group's encrypted photo from the server if it had one (the owner and
    /// admins may).
    pub fn set_group_avatar_emoji(&self, transport: Arc<dyn Transport>, auth_token: String, conversation_id: String, emoji: Option<String>) -> Result<(), StoreError> {
        let (group_id, _, _) = self.group_context(&conversation_id)?;
        let old = self.with_conn(|conn| groups::state_of(conn, &group_id))?.photo;
        self.set_group_emoji(conversation_id.clone(), emoji)?;
        self.drop_group_photo(&transport, &auth_token, &conversation_id, old);
        Ok(())
    }

    /// Sets the group's photo (a JPEG already cropped and shrunk by the app; the owner and admins may). It is encrypted on this
    /// phone with a new random key and uploaded as an opaque blob; the blob's id and the key go only inside the group's signed,
    /// encrypted state op, so the server never sees the picture. The group's members fetch and decrypt it.
    pub fn set_group_photo(&self, transport: Arc<dyn Transport>, auth_token: String, conversation_id: String, jpeg: Vec<u8>) -> Result<(), StoreError> {
        if jpeg.is_empty() || jpeg.len() > 1024 * 1024 {
            return Err(StoreError::Rejected);
        }
        let (group_id, state, me) = self.group_context(&conversation_id)?;
        let before = self.with_conn(|conn| groups::state_of(conn, &group_id))?;
        if !before.may_manage(&me) {
            return Err(StoreError::Rejected);
        }
        let photo = GroupPhoto { blob_id: uuid::Uuid::new_v4().to_string(), key: crate::store::attachments::new_key() };
        let sealed = crate::store::attachments::seal(&photo.key, &photo.blob_id, &jpeg).remove(0);
        let (status, body) = call(&transport, Some(&auth_token), "blob", &json!({ "action": "put", "blob_id": photo.blob_id, "size": sealed.len() }))?;
        check(status)?;
        let url = body.get("url").and_then(Value::as_str).ok_or(StoreError::BadMessage)?;
        let response = transport
            .request("PUT".into(), url.into(), vec![HeaderPair { name: "content-type".into(), value: "application/octet-stream".into() }], sealed)
            .map_err(|_: TransportError| StoreError::Network)?;
        check(response.status)?;
        let (status, _) = call(&transport, Some(&auth_token), "blob", &json!({ "action": "commit", "blob_id": photo.blob_id }))?;
        check(status)?;
        self.make_group_op(&state, &me, &group_id, None, Kind::SetAvatar { emoji: None, photo: Some(photo.clone()) })?;
        // My own copy is the picture I just chose.
        self.with_conn(|conn| crate::store::photos::save_cached(conn, &conversation_id, &jpeg, &photo.blob_id, 1, now_ms()))?;
        self.drop_group_photo(&transport, &auth_token, &conversation_id, before.photo);
        Ok(())
    }

    /// Removes the group's photo (and its emoji): back to the people's pictures.
    pub fn remove_group_photo(&self, transport: Arc<dyn Transport>, auth_token: String, conversation_id: String) -> Result<(), StoreError> {
        self.set_group_avatar_emoji(transport, auth_token, conversation_id.clone(), None)?;
        self.with_conn(|conn| crate::store::photos::save_cached(conn, &conversation_id, &[], "none", 0, now_ms()))
    }

    /// The group's photo, once this phone has it.
    pub fn group_photo(&self, conversation_id: String) -> Result<Option<Vec<u8>>, StoreError> {
        self.with_conn(|conn| {
            let current: Option<String> = conn
                .query_row("SELECT group_photo FROM conversations WHERE id = ?1", params![conversation_id], |r| r.get(0))
                .optional()
                .map_err(db_err)?
                .flatten();
            let Some(photo) = current.as_deref().and_then(GroupPhoto::from_stored) else { return Ok(None) };
            Ok(crate::store::photos::cached(conn, &conversation_id)?.filter(|c| c.source == photo.blob_id && !c.bytes.is_empty()).map(|c| c.bytes))
        })
    }

    /// Fetches and decrypts the photos of groups whose photo this phone does not have yet (a new photo, a changed one, a group I
    /// was just added to), and forgets the ones that were removed. Returns the conversations that changed.
    pub fn refresh_group_photos(&self, transport: Arc<dyn Transport>, auth_token: String) -> Result<Vec<String>, StoreError> {
        let groups: Vec<(String, Option<String>)> = self.with_conn(|conn| {
            let mut statement = conn
                .prepare("SELECT id, group_photo FROM conversations WHERE is_group = 1 AND id LIKE 'grp:%' AND request_state != 'blocked'")
                .map_err(db_err)?;
            let rows = statement.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?))).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
            Ok(rows)
        })?;
        let mut changed = Vec::new();
        for (conversation, stored) in groups {
            let wanted = stored.as_deref().and_then(GroupPhoto::from_stored);
            let held = self.with_conn(|conn| crate::store::photos::cached(conn, &conversation))?;
            let Some(photo) = wanted else {
                if held.as_ref().is_some_and(|c| !c.bytes.is_empty()) {
                    self.with_conn(|conn| crate::store::photos::save_cached(conn, &conversation, &[], "none", 0, now_ms()))?;
                    changed.push(conversation);
                }
                continue;
            };
            if held.as_ref().is_some_and(|c| c.source == photo.blob_id && !c.bytes.is_empty()) {
                continue;
            }
            let Ok((200, body)) = call(&transport, Some(&auth_token), "blob", &json!({ "action": "get", "blob_id": photo.blob_id })) else { continue };
            let Some(url) = body.get("url").and_then(Value::as_str) else { continue };
            let Ok(response) = transport.request("GET".into(), url.into(), Vec::new(), Vec::new()) else { continue };
            if check(response.status).is_err() {
                continue;
            }
            if let Some(jpeg) = crate::store::attachments::open(&photo.key, &photo.blob_id, &[response.body]) {
                self.with_conn(|conn| crate::store::photos::save_cached(conn, &conversation, &jpeg, &photo.blob_id, 1, now_ms()))?;
                changed.push(conversation);
            }
        }
        Ok(changed)
    }

    /// Makes someone an admin, or a plain member again (only the owner may).
    pub fn set_group_admin(&self, conversation_id: String, user_id: String, admin: bool) -> Result<(), StoreError> {
        let (group_id, state, me) = self.group_context(&conversation_id)?;
        let before = self.with_conn(|conn| groups::state_of(conn, &group_id))?;
        if before.role_of(&me) != Some(Role::Owner) || !before.is_member(&user_id) || user_id == me {
            return Err(StoreError::Rejected);
        }
        self.make_group_op(&state, &me, &group_id, None, Kind::SetRole { user: user_id, role: if admin { Role::Admin } else { Role::Member } })
    }

    /// Leaves the group. The conversation disappears from Messages and nothing more is shown from it.
    pub fn leave_group(&self, conversation_id: String) -> Result<(), StoreError> {
        let (group_id, state, me) = self.group_context(&conversation_id)?;
        let before = self.with_conn(|conn| groups::state_of(conn, &group_id))?;
        if !before.is_member(&me) {
            return Err(StoreError::Rejected);
        }
        self.make_group_op(&state, &me, &group_id, None, Kind::Leave)?;
        self.with_conn(|conn| groups::delete_outbound(conn, &group_id))
    }
}

// ---------------------------------------------------------------- making state ops

impl LimeStore {
    pub(crate) fn group_context(&self, conversation_id: &str) -> Result<(String, AccountState, String), StoreError> {
        let group_id = groups::group_id_of(conversation_id).ok_or(StoreError::NotFound)?.to_owned();
        let state = self.load_or_create_account()?;
        let me = state.user_id.clone().filter(|_| state.registered).ok_or(StoreError::NotRegistered)?;
        Ok((group_id, state, me))
    }

    /// Signs a state op, applies it here, and queues it for everyone it concerns (the people before and after);
    /// a person it adds is also queued the group's whole history. `op_id`: given for a create (it is the group's id).
    pub(crate) fn make_group_op(&self, state: &AccountState, me: &str, group_id: &str, op_id: Option<String>, kind: Kind) -> Result<(), StoreError> {
        let now = now_ms();
        self.with_conn(|conn| {
            let before = groups::state_of(conn, group_id)?;
            let hlc = tick_hlc(conn, now)?;
            let parents = groups::heads(conn, group_id)?;
            let mut op = Op {
                op_id: op_id.unwrap_or_else(new_id),
                op_type: kind.op_type().into(),
                conversation_id: groups::conversation_id(group_id),
                hlc: hlc.render(),
                parents,
                payload: kind.payload(),
                sig: String::new(),
            };
            op.sig = state.account.sign(op.signing_bytes()).to_base64();
            let inner = SealedInner { sender_user: me.to_owned(), sender_device: state.device_id.clone(), sender_cert: state.cert(), op: op.clone() };
            let inner_text = String::from_utf8(inner.to_bytes()).map_err(|_| StoreError::BadMessage)?;
            groups::insert_op(conn, group_id, &op.op_id, &op.op_type, me, &op.hlc, &op.parents, &op.payload, &inner_text, now)?;
            let after = groups::rebuild(conn, group_id, me, now)?.state;
            // Everyone who was in the group, and everyone who is: the removed person needs to hear it too.
            let mut audience: Vec<String> = before.users();
            for user in after.users() {
                if !audience.contains(&user) {
                    audience.push(user);
                }
            }
            audience.retain(|user| user != me);
            for user in &audience {
                groups::enqueue(conn, group_id, user, &op.to_json().to_string())?;
            }
            // A person just added gets the history (the original signed envelopes, oldest first), to replay it.
            let newly: Vec<String> = after.users().into_iter().filter(|u| u != me && !before.is_member(u)).collect();
            if !newly.is_empty() && !matches!(kind, Kind::Create { .. }) {
                let inners = groups::load_inners(conn, group_id)?;
                for chunk in inners.chunks(HISTORY_CHUNK) {
                    let envelopes: Vec<Value> = chunk.iter().filter_map(|text| serde_json::from_str(text).ok()).collect();
                    let history = self.history_op(state, group_id, envelopes, conn, now)?;
                    for user in &newly {
                        groups::enqueue(conn, group_id, user, &history.to_json().to_string())?;
                    }
                }
            }
            Ok(())
        })
    }

    fn history_op(&self, state: &AccountState, group_id: &str, envelopes: Vec<Value>, conn: &Connection, now: i64) -> Result<Op, StoreError> {
        let hlc = tick_hlc(conn, now)?;
        let mut op = Op {
            op_id: new_id(),
            op_type: "group.history".into(),
            conversation_id: groups::conversation_id(group_id),
            hlc: hlc.render(),
            parents: vec![],
            payload: json!({ "ops": envelopes }),
            sig: String::new(),
        };
        op.sig = state.account.sign(op.signing_bytes()).to_base64();
        Ok(op)
    }
}

// ---------------------------------------------------------------- sending

impl LimeStore {
    /// Sends one op to one person: sealed when they gave us their key and it has not been refused, identified
    /// otherwise; a refused sealed send is sent identified at once (LIME-96-fix).
    pub(super) fn send_to_user(
        &self,
        transport: &Arc<dyn Transport>,
        token: &str,
        state: &mut AccountState,
        me: &str,
        peer: &str,
        op: Op,
    ) -> Result<(), StoreError> {
        let contact = self.with_conn(|conn| delivery::contact_key(conn, peer))?;
        let sealed = contact.and_then(|(key, denied)| (!denied).then_some(key));
        match self.send_op(transport, token, state, me, peer, op.clone(), sealed.as_deref()) {
            Ok(_) => Ok(()),
            Err(SendError::Denied) => {
                self.with_conn(|conn| delivery::mark_denied(conn, peer))?;
                self.send_op(transport, token, state, me, peer, op, None).map(|_| ()).map_err(SendError::into_store)
            }
            Err(SendError::Store(error)) => Err(error),
        }
    }

    /// Sends what is waiting in the group outbox. A person whose key changed waits (kept); one with no devices is
    /// dropped; a network failure stops the pass. Never holds up the messages.
    pub(super) fn deliver_group_outbox(&self, transport: &Arc<dyn Transport>, token: &str, state: &mut AccountState, me: &str) {
        let Ok(rows) = self.with_conn(groups::outbox) else { return };
        for (id, _group, recipient, op_json) in rows {
            let Some(op) = serde_json::from_str::<Value>(&op_json).ok().and_then(|v| Op::from_json(&v)) else {
                let _ = self.with_conn(|conn| groups::dequeue(conn, id));
                continue;
            };
            match self.send_to_user(transport, token, state, me, &recipient, op) {
                Ok(()) | Err(StoreError::NoRecipientKeys) => {
                    let _ = self.with_conn(|conn| groups::dequeue(conn, id));
                }
                Err(StoreError::KeyMismatch) => continue,
                Err(_) => return,
            }
        }
    }

    /// Sends one group message: makes sure this device's Megolm session for the group is current and that every
    /// member has its key, encrypts the message once, and sends the same ciphertext to every member device.
    pub(super) fn deliver_group_message(
        &self,
        transport: &Arc<dyn Transport>,
        token: &str,
        state: &mut AccountState,
        me: &str,
        message: &Queued,
    ) -> Result<(), StoreError> {
        let op = Op {
            op_id: message.id.clone(),
            op_type: "message.send".into(),
            conversation_id: message.conversation_id.clone(),
            hlc: message.hlc.clone(),
            parents: message.parents.clone(),
            payload: message.payload(),
            sig: String::new(),
        };
        self.send_group_op(transport, token, state, me, op)
    }

    /// Sends one signed op (a message, an edit, a delete or a reaction) to a group's members under the current Megolm session.
    pub(super) fn send_group_op(
        &self,
        transport: &Arc<dyn Transport>,
        token: &str,
        state: &mut AccountState,
        me: &str,
        mut op: Op,
    ) -> Result<(), StoreError> {
        let group_id = groups::group_id_of(&op.conversation_id).ok_or(StoreError::NotFound)?.to_owned();
        let group = self.with_conn(|conn| groups::state_of(conn, &group_id))?;
        if !group.is_member(me) {
            return Err(StoreError::NotFound);
        }
        let others: Vec<String> = group.users().into_iter().filter(|u| u != me).collect();

        // Everyone's devices (a person whose key changed, or with no devices, is left out of this send).
        let mut audience: Vec<(String, Vec<String>)> = Vec::new();
        for user in &others {
            match self.recipient_devices(transport, token, user) {
                Ok(devices) => audience.push((user.clone(), devices.into_iter().map(|d| d.device_id).collect())),
                Err(StoreError::KeyMismatch | StoreError::NoRecipientKeys) => continue,
                Err(error) => return Err(error),
            }
        }
        let mut outbound = self.ensure_group_session(transport, token, state, me, &group_id, &others)?;

        op.sig = state.account.sign(op.signing_bytes()).to_base64();
        let inner = SealedInner { sender_user: me.to_owned(), sender_device: state.device_id.clone(), sender_cert: state.cert(), op }.to_bytes();
        let megolm = outbound.session.encrypt(&inner);
        outbound.messages += 1;
        let mut wire = vec![GROUP_WIRE];
        wire.extend_from_slice(json!({ "s": outbound.session.session_id(), "c": megolm.to_base64() }).to_string().as_bytes());
        self.with_conn(|conn| groups::save_outbound(conn, &self.pickle_key, &group_id, &outbound))?;
        self.send_group_wire(transport, token, &vodozemac::base64_encode(&wire), audience)
    }

    /// The current outbound session, replaced first when it is time (a membership change, 100 messages, 7 days),
    /// with its key given to every member who does not have it yet.
    fn ensure_group_session(
        &self,
        transport: &Arc<dyn Transport>,
        token: &str,
        state: &mut AccountState,
        me: &str,
        group_id: &str,
        others: &[String],
    ) -> Result<groups::Outbound, StoreError> {
        let now = now_ms();
        let mut sorted: Vec<&String> = others.iter().collect();
        sorted.sort();
        let fingerprint = hex_sha256(sorted.iter().map(|u| u.as_str()).collect::<Vec<_>>().join(",").as_bytes());
        let existing = self.with_conn(|conn| groups::load_outbound(conn, &self.pickle_key, group_id))?;
        let mut outbound = match existing {
            Some(o) if !o.rotate && o.messages < ROTATE_AFTER_MESSAGES && now - o.created_at < ROTATE_AFTER_MS && o.fingerprint == fingerprint => o,
            _ => groups::Outbound {
                session: GroupSession::new(MegolmConfig::version_1()),
                created_at: now,
                messages: 0,
                fingerprint,
                rotate: false,
                shared_with: vec![],
            },
        };
        self.with_conn(|conn| groups::save_outbound(conn, &self.pickle_key, group_id, &outbound))?;
        for user in others {
            if outbound.shared_with.contains(user) {
                continue;
            }
            let hlc = self.with_conn(|conn| tick_hlc(conn, now))?;
            let mut op = Op {
                op_id: new_id(),
                op_type: "group.session".into(),
                conversation_id: groups::conversation_id(group_id),
                hlc: hlc.render(),
                parents: vec![],
                payload: json!({
                    "group_id": group_id,
                    "session_id": outbound.session.session_id(),
                    "key": outbound.session.session_key().to_base64(),
                }),
                sig: String::new(),
            };
            op.sig = state.account.sign(op.signing_bytes()).to_base64();
            match self.send_to_user(transport, token, state, me, user, op) {
                // Delivered, or nobody to give it to: either way this person is done.
                Ok(()) | Err(StoreError::NoRecipientKeys) => {
                    outbound.shared_with.push(user.clone());
                    self.with_conn(|conn| groups::save_outbound(conn, &self.pickle_key, group_id, &outbound))?;
                }
                // Their key changed and is not accepted yet: they miss this session (and its messages) until it is.
                Err(StoreError::KeyMismatch) => continue,
                Err(error) => return Err(error),
            }
        }
        Ok(outbound)
    }

    /// One ciphertext, many recipients: everyone we hold a delivery key for goes sealed (no token), everyone else
    /// identified. A sealed request the server refuses is retried person by person, and a refused person is sent
    /// identified (LIME-96-fix).
    fn send_group_wire(
        &self,
        transport: &Arc<dyn Transport>,
        token: &str,
        wire_b64: &str,
        audience: Vec<(String, Vec<String>)>,
    ) -> Result<(), StoreError> {
        let mut sealed: Vec<(String, Vec<u8>, Vec<String>)> = Vec::new();
        let mut identified: Vec<(String, Vec<String>)> = Vec::new();
        for (user, devices) in audience {
            match self.with_conn(|conn| delivery::contact_key(conn, &user))? {
                Some((key, false)) => sealed.push((user, key, devices)),
                _ => identified.push((user, devices)),
            }
        }
        let sealed_recipients = |part: &[(String, Vec<u8>, Vec<String>)]| -> Vec<Value> {
            part.iter()
                .flat_map(|(_, key, devices)| {
                    devices.iter().map(move |d| json!({ "to_device": d, "access": { "sealed": delivery::access_key_b64(key) } }))
                })
                .collect()
        };
        for chunk in sealed.chunks(SEND_CHUNK / 4 + 1) {
            let (status, _) = call(transport, None, "send", &json!({ "ciphertext": wire_b64, "recipients": sealed_recipients(chunk) }))?;
            if status == 403 {
                for one in chunk {
                    let (status, _) = call(transport, None, "send", &json!({ "ciphertext": wire_b64, "recipients": sealed_recipients(std::slice::from_ref(one)) }))?;
                    if status == 403 {
                        self.with_conn(|conn| delivery::mark_denied(conn, &one.0))?;
                        identified.push((one.0.clone(), one.2.clone()));
                    } else {
                        check(status)?;
                    }
                }
            } else {
                check(status)?;
            }
        }
        let recipients: Vec<Value> = identified
            .iter()
            .flat_map(|(_, devices)| devices.iter().map(|d| json!({ "to_device": d, "access": { "identified": true } })))
            .collect();
        for chunk in recipients.chunks(SEND_CHUNK) {
            let (status, _) = call(transport, Some(token), "send", &json!({ "ciphertext": wire_b64, "recipients": chunk }))?;
            check(status)?;
        }
        Ok(())
    }
}

// ---------------------------------------------------------------- receiving

impl LimeStore {
    /// A group op that came through a verified Olm item (its sender is known and its certificate checked): a state
    /// op (stored, then the state is worked out again), a group's history (several signed envelopes, each checked
    /// again), or a Megolm session key.
    pub(super) fn apply_group_op(
        &self,
        conn: &Connection,
        me: &str,
        sender: &str,
        inner: &SealedInner,
        cert: &SenderCert,
        now: i64,
    ) -> Result<(), StoreError> {
        let op = &inner.op;
        let Some(group_id) = groups::group_id_of(&op.conversation_id) else { return Ok(()) };
        match op.op_type.as_str() {
            "group.session" => self.store_group_session(conn, group_id, sender, &cert.device_id, &op.payload),
            "group.history" => self.apply_group_history(conn, me, sender, group_id, &op.payload, now),
            other => {
                let Some(kind) = Kind::parse(other, &op.payload) else { return Ok(()) };
                if matches!(kind, Kind::Create { .. }) && op.op_id != group_id {
                    return Ok(());
                }
                let text = String::from_utf8(inner.to_bytes()).map_err(|_| StoreError::BadMessage)?;
                groups::insert_op(conn, group_id, &op.op_id, &op.op_type, sender, &op.hlc, &op.parents, &op.payload, &text, now)?;
                groups::rebuild(conn, group_id, me, now)?;
                Ok(())
            }
        }
    }

    /// A Megolm session key from `sender`'s device: kept, tied to that device (a message in it counts as theirs only).
    fn store_group_session(&self, conn: &Connection, group_id: &str, sender: &str, device: &str, payload: &Value) -> Result<(), StoreError> {
        let text = |k: &str| payload.get(k).and_then(Value::as_str);
        let (Some(claimed_group), Some(session_id), Some(key)) = (text("group_id"), text("session_id"), text("key")) else { return Ok(()) };
        if claimed_group != group_id {
            return Ok(());
        }
        // Only a member may give a group's key (when we already know the group; otherwise it is checked on use).
        let group = groups::state_of(conn, group_id)?;
        if group.created && !group.is_member(sender) {
            return Ok(());
        }
        if groups::load_inbound(conn, &self.pickle_key, session_id)?.is_some() {
            return Ok(()); // never replace a session that has moved on
        }
        let Ok(key) = SessionKey::from_base64(key) else { return Ok(()) };
        let session = InboundGroupSession::new(&key, MegolmConfig::version_1());
        if session.session_id() != session_id {
            return Ok(());
        }
        groups::save_inbound(
            conn,
            &self.pickle_key,
            session_id,
            &groups::Inbound { session, group_id: group_id.to_owned(), owner_user: sender.to_owned(), owner_device: device.to_owned() },
        )
    }

    /// The original signed state ops of a group, handed over by whoever added us. Each is checked on its own (the
    /// certificate chain and the signature); who may do what is decided by the replay, not by who delivered it.
    /// If, after all that, the person who sent the history is not in the group, it is undone.
    fn apply_group_history(&self, conn: &Connection, me: &str, sender: &str, group_id: &str, payload: &Value, now: i64) -> Result<(), StoreError> {
        let Some(envelopes) = payload.get("ops").and_then(Value::as_array) else { return Ok(()) };
        let mut inserted: Vec<String> = Vec::new();
        for envelope in envelopes.iter().take(HISTORY_CHUNK * 4) {
            let Ok(bytes) = serde_json::to_vec(envelope) else { continue };
            let Some(inner) = SealedInner::from_bytes(&bytes) else { continue };
            let cert = &inner.sender_cert;
            let op = &inner.op;
            let well_formed = inner.sender_device == cert.device_id
                && cert.verify()
                && op.verify(&cert.signing_key)
                && groups::group_id_of(&op.conversation_id) == Some(group_id)
                && Kind::parse(&op.op_type, &op.payload).is_some();
            if !well_formed {
                continue;
            }
            // The people in the history are pinned the first time they are seen; a different key than the one we
            // hold is left out (never a key-change prompt from a forwarded envelope).
            if pin_master_key(conn, &inner.sender_user, &cert.master_key).is_err() {
                continue;
            }
            let text = String::from_utf8(inner.to_bytes()).map_err(|_| StoreError::BadMessage)?;
            if groups::insert_op(conn, group_id, &op.op_id, &op.op_type, &inner.sender_user, &op.hlc, &op.parents, &op.payload, &text, now)? {
                inserted.push(op.op_id.clone());
            }
        }
        let rebuilt = groups::rebuild(conn, group_id, me, now)?;
        if !inserted.is_empty() && !rebuilt.state.is_member(sender) {
            for id in &inserted {
                groups::delete_op(conn, id)?;
            }
            groups::rebuild(conn, group_id, me, now)?;
        }
        Ok(())
    }

    /// Decrypts and stores one group message. `rest` is the wire text after the marker byte: `{ "s": session id,
    /// "c": Megolm ciphertext }`. A message whose session key has not arrived yet waits (`no_session`); one in a
    /// group we do not know yet waits too (`no_group`). Whose message it is comes from the session (the device that
    /// shared it and was verified then), and the signed envelope inside must agree.
    pub(super) fn process_group_message(&self, me: &str, rest: &[u8], now: i64) -> Result<Outcome, StoreError> {
        let Ok(value) = serde_json::from_slice::<Value>(rest) else { return Ok(Outcome::Keep(pending::INVALID)) };
        let (Some(session_id), Some(cipher)) = (value.get("s").and_then(Value::as_str), value.get("c").and_then(Value::as_str)) else {
            return Ok(Outcome::Keep(pending::INVALID));
        };
        let Ok(message) = MegolmMessage::from_base64(cipher) else { return Ok(Outcome::Keep(pending::INVALID)) };
        let Some(mut inbound) = self.with_conn(|conn| groups::load_inbound(conn, &self.pickle_key, session_id))? else {
            return Ok(Outcome::Keep(pending::NO_SESSION));
        };
        let Ok(decrypted) = inbound.session.decrypt(&message) else {
            // Before the first message index this device was given (a message from before it joined).
            return Ok(Outcome::Keep(pending::DECRYPT_FAILED));
        };
        let Some(inner) = SealedInner::from_bytes(&decrypted.plaintext) else { return Ok(Outcome::Keep(pending::INVALID)) };
        let cert = &inner.sender_cert;
        let conversation = groups::conversation_id(&inbound.group_id);
        let valid = inner.sender_user == inbound.owner_user
            && inner.sender_device == inbound.owner_device
            && inner.sender_device == cert.device_id
            && inner.sender_user != me
            && cert.verify()
            && inner.op.verify(&cert.signing_key)
            && (inner.op.op_type == "message.send" || crate::store::message_ops::is_message_op(&inner.op.op_type))
            && inner.op.conversation_id == conversation;
        if valid && crate::store::message_ops::is_message_op(&inner.op.op_type) {
            // An edit, a delete or a reaction: checked and applied, never a new message. Only a member of the group may.
            let Some(remote_hlc) = Hlc::parse(&inner.op.hlc) else { return Ok(Outcome::Keep(pending::INVALID)) };
            let sender = inner.sender_user.clone();
            let done = self.with_conn(|conn| {
                let pinned: Option<String> = conn
                    .query_row("SELECT master_key FROM peers WHERE user_id = ?1", params![sender], |r| r.get(0))
                    .optional()
                    .map_err(db_err)?;
                if pinned.as_deref() != Some(cert.master_key.as_str()) {
                    return Ok(false);
                }
                let known: Option<String> = conn
                    .query_row("SELECT request_state FROM conversations WHERE id = ?1", params![conversation], |r| r.get(0))
                    .optional()
                    .map_err(db_err)?;
                let Some(state) = known else { return Ok(false) };
                if !groups::state_of(conn, &inbound.group_id)?.ever.contains(&sender) {
                    return Ok(false);
                }
                groups::save_inbound(conn, &self.pickle_key, session_id, &inbound)?;
                if state != "blocked" && state != "left" {
                    crate::store::message_ops::apply(conn, &sender, &conversation, &inner.op)?;
                }
                Ok(true)
            })?;
            if !done {
                return Ok(Outcome::Keep(pending::NO_GROUP));
            }
            self.with_conn(|conn| observe_hlc(conn, remote_hlc, now).map(|_| ()))?;
            return Ok(Outcome::Duplicate);
        }
        let text = inner.op.payload.get("text").and_then(Value::as_str).map(crate::format::normalise);
        let attachments = crate::store::attachments::parse_payload(&inner.op.payload);
        let (true, Some(text), Some(attachments), Some(remote_hlc)) = (
            valid,
            text.filter(|t| !t.is_empty() || attachments.as_ref().is_some_and(|a| !a.is_empty())),
            attachments,
            Hlc::parse(&inner.op.hlc),
        ) else {
            return Ok(Outcome::Keep(pending::INVALID));
        };
        let plain = crate::format::plain_text(&text);
        let claimed_root = inner
            .op
            .payload
            .get("thread_root")
            .and_then(Value::as_str)
            .filter(|id| !id.is_empty() && id.len() <= 64 && *id != inner.op.op_id)
            .map(str::to_owned);
        let parents = json!(inner.op.parents).to_string();
        let sender = inner.sender_user.clone();
        let outcome = self.with_conn(|conn| {
            // The sender's master key must be the one pinned when their session key arrived.
            let pinned: Option<String> = conn
                .query_row("SELECT master_key FROM peers WHERE user_id = ?1", params![sender], |r| r.get(0))
                .optional()
                .map_err(db_err)?;
            if pinned.as_deref() != Some(cert.master_key.as_str()) {
                return Ok(Outcome::Keep(pending::INVALID));
            }
            let state: Option<String> = conn
                .query_row("SELECT request_state FROM conversations WHERE id = ?1", params![conversation], |r| r.get(0))
                .optional()
                .map_err(db_err)?;
            let Some(state) = state else {
                // The group's creation has not arrived (or I am not in it): wait for it.
                return Ok(Outcome::Keep(pending::NO_GROUP));
            };
            if !groups::state_of(conn, &inbound.group_id)?.ever.contains(&sender) {
                return Ok(Outcome::Keep(pending::INVALID));
            }
            groups::save_inbound(conn, &self.pickle_key, session_id, &inbound)?;
            if state == "blocked" || state == "left" {
                // Read (so the session keeps in step) but never stored or shown.
                return Ok(Outcome::Duplicate);
            }
            let inserted = insert_received_message(
                conn, &conversation, &sender, &inner.op.op_id, &inner.op.hlc, &parents, &text, &plain, claimed_root.as_deref(), now, remote_hlc.wall,
            )?;
            if inserted {
                for (position, descriptor) in attachments.iter().enumerate() {
                    crate::store::attachments::insert(conn, &inner.op.op_id, position, descriptor, None)?;
                }
            }
            Ok(if inserted { Outcome::Stored } else { Outcome::Duplicate })
        })?;
        if matches!(outcome, Outcome::Stored | Outcome::Duplicate) {
            self.with_conn(|conn| observe_hlc(conn, remote_hlc, now).map(|_| ()))?;
        }
        Ok(outcome)
    }
}

impl LimeStore {
    /// Deletes a replaced or removed group photo from the server (best effort: an orphan only costs ciphertext storage).
    fn drop_group_photo(&self, transport: &Arc<dyn Transport>, token: &str, _conversation_id: &str, old: Option<GroupPhoto>) {
        if let Some(old) = old {
            let _ = call(transport, Some(token), "blob", &json!({ "action": "delete", "blob_id": old.blob_id }));
        }
    }
}
