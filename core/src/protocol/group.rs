//! Group state (`docs/api-v2.md` section 6): who is in a group, their roles, its name and avatar, worked out
//! **from the log of signed state ops**, never from a server. Every device replays the same ops in the same
//! order, so every device reaches the same state, whatever order the ops arrived in. Pure functions: no
//! network, no storage.
//!
//! The order is `(hlc, op_id)`: an op that causally follows another always has a larger HLC, so this is a
//! linear extension of the causal order. Authority is checked against the state at that point of the replay:
//! only the owner and admins add, remove, rename or change the avatar; only the owner changes roles; a member
//! may leave. An op that breaks the rules is ignored. Two rules need more than the order:
//!
//! - **A concurrent remove beats an add.** An add of someone is void when a remove of them exists that is
//!   *concurrent* with it (neither is an ancestor of the other, following `parents`). An add that causally
//!   follows the remove is a legitimate re-add. Whether a remove is effective depends on the adds, so the
//!   replay is repeated until the set of effective removes stops changing (a few passes at most).
//! - **The owner cannot be removed, except by leaving.** Then the oldest admin, else the oldest member (by
//!   when they joined, in replay order), becomes owner.

use std::collections::{HashMap, HashSet};

use serde_json::{json, Value};

use super::Hlc;

/// The most people in a group (the call target).
pub(crate) const MAX_MEMBERS: usize = 100;
/// The longest group name, in characters.
pub(crate) const MAX_NAME_CHARS: usize = 50;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Role {
    Owner,
    Admin,
    Member,
}

impl Role {
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Role::Owner => "owner",
            Role::Admin => "admin",
            Role::Member => "member",
        }
    }

    pub(crate) fn parse(text: &str) -> Option<Role> {
        match text {
            "owner" => Some(Role::Owner),
            "admin" => Some(Role::Admin),
            "member" => Some(Role::Member),
            _ => None,
        }
    }

    fn can_manage(self) -> bool {
        matches!(self, Role::Owner | Role::Admin)
    }
}

/// A group's photo: an encrypted blob in the `blobs` bucket and the key that opens it. Both travel only inside the group's
/// signed, encrypted state ops, so the server never sees the picture, the key or which group it belongs to.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct GroupPhoto {
    pub blob_id: String,
    pub key: Vec<u8>,
}

impl GroupPhoto {
    fn to_json(&self) -> Value {
        json!({ "id": self.blob_id, "key": vodozemac::base64_encode(&self.key) })
    }

    fn parse(value: &Value) -> Option<GroupPhoto> {
        let id = value.get("id")?.as_str()?;
        let key = vodozemac::base64_decode(value.get("key")?.as_str()?).ok().filter(|k| k.len() == 32)?;
        let uuid = id.len() == 36 && id.bytes().enumerate().all(|(i, b)| if [8, 13, 18, 23].contains(&i) { b == b'-' } else { b.is_ascii_hexdigit() });
        uuid.then(|| GroupPhoto { blob_id: id.to_ascii_lowercase(), key })
    }

    /// The stored form (in the conversation row).
    pub(crate) fn to_stored(&self) -> String {
        self.to_json().to_string()
    }

    pub(crate) fn from_stored(text: &str) -> Option<GroupPhoto> {
        serde_json::from_str::<Value>(text).ok().and_then(|v| Self::parse(&v))
    }
}

/// What a state op does.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Kind {
    Create { name: String, emoji: Option<String>, members: Vec<String> },
    Add { users: Vec<String> },
    Remove { user: String },
    Leave,
    Rename { name: String },
    /// An emoji or an encrypted photo (never both); neither clears the avatar.
    SetAvatar { emoji: Option<String>, photo: Option<GroupPhoto> },
    /// `role` is `Admin` or `Member`.
    SetRole { user: String, role: Role },
}

impl Kind {
    pub(crate) fn op_type(&self) -> &'static str {
        match self {
            Kind::Create { .. } => "group.create",
            Kind::Add { .. } => "group.add",
            Kind::Remove { .. } => "group.remove",
            Kind::Leave => "group.leave",
            Kind::Rename { .. } => "group.rename",
            Kind::SetAvatar { .. } => "group.set_avatar",
            Kind::SetRole { .. } => "group.set_role",
        }
    }

    pub(crate) fn payload(&self) -> Value {
        match self {
            Kind::Create { name, emoji, members } => json!({ "name": name, "emoji": emoji, "members": members }),
            Kind::Add { users } => json!({ "users": users }),
            Kind::Remove { user } => json!({ "user": user }),
            Kind::Leave => json!({}),
            Kind::Rename { name } => json!({ "name": name }),
            Kind::SetAvatar { emoji, photo } => match photo {
                Some(photo) => json!({ "photo": photo.to_json() }),
                None => json!({ "emoji": emoji }),
            },
            Kind::SetRole { user, role } => json!({ "user": user, "role": role.as_str() }),
        }
    }

    /// Reads an op's type and payload; `None` when it is not a well-formed group state op.
    pub(crate) fn parse(op_type: &str, payload: &Value) -> Option<Kind> {
        let text = |k: &str| payload.get(k).and_then(Value::as_str).map(str::to_owned);
        let users = |k: &str| -> Option<Vec<String>> {
            payload.get(k)?.as_array()?.iter().map(|u| u.as_str().filter(|u| !u.is_empty() && u.len() <= 64).map(str::to_owned)).collect()
        };
        Some(match op_type {
            "group.create" => Kind::Create { name: text("name")?, emoji: text("emoji"), members: users("members")? },
            "group.add" => Kind::Add { users: users("users")? },
            "group.remove" => Kind::Remove { user: text("user")? },
            "group.leave" => Kind::Leave,
            "group.rename" => Kind::Rename { name: text("name")? },
            "group.set_avatar" => {
                // A photo present but malformed makes the op invalid (it is not quietly read as "no avatar").
                let photo = match payload.get("photo") {
                    None | Some(Value::Null) => None,
                    Some(value) => Some(GroupPhoto::parse(value)?),
                };
                Kind::SetAvatar { emoji: if photo.is_some() { None } else { text("emoji") }, photo }
            }
            "group.set_role" => {
                let role = Role::parse(&text("role")?).filter(|r| *r != Role::Owner)?;
                Kind::SetRole { user: text("user")?, role }
            }
            _ => return None,
        })
    }
}

/// A group state op as the replay sees it.
#[derive(Debug, Clone)]
pub(crate) struct GroupOp {
    pub op_id: String,
    pub sender: String,
    pub hlc: Hlc,
    pub parents: Vec<String>,
    pub kind: Kind,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Member {
    pub user: String,
    pub role: Role,
    /// Order of joining in the replay (the oldest first): who becomes owner when the owner leaves.
    pub seq: usize,
}

/// Something that really happened, for the timeline's system lines.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Event {
    Created { name: String },
    Added(Vec<String>),
    Removed(String),
    Left,
    Renamed(String),
    Avatar,
    /// The group's photo was set or changed.
    Photo,
    Role(String, Role),
    NewOwner(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Effect {
    pub op_id: String,
    pub hlc: Hlc,
    pub actor: String,
    pub event: Event,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub(crate) struct GroupState {
    pub created: bool,
    pub name: String,
    pub emoji: Option<String>,
    pub photo: Option<GroupPhoto>,
    pub members: Vec<Member>,
    pub effects: Vec<Effect>,
    /// Everyone who has ever been a member (a message from someone since removed still shows).
    pub ever: HashSet<String>,
}

impl GroupState {
    pub(crate) fn role_of(&self, user: &str) -> Option<Role> {
        self.members.iter().find(|m| m.user == user).map(|m| m.role)
    }

    pub(crate) fn is_member(&self, user: &str) -> bool {
        self.role_of(user).is_some()
    }

    pub(crate) fn users(&self) -> Vec<String> {
        self.members.iter().map(|m| m.user.clone()).collect()
    }

    /// Whether `actor` may remove `target` (the owner removes anyone else; an admin removes plain members).
    pub(crate) fn may_remove(&self, actor: &str, target: &str) -> bool {
        let (Some(actor_role), Some(target_role)) = (self.role_of(actor), self.role_of(target)) else { return false };
        actor != target
            && match actor_role {
                Role::Owner => target_role != Role::Owner,
                Role::Admin => target_role == Role::Member,
                Role::Member => false,
            }
    }

    pub(crate) fn may_manage(&self, actor: &str) -> bool {
        self.role_of(actor).is_some_and(Role::can_manage)
    }
}

/// A valid group name: not empty after trimming, at most [`MAX_NAME_CHARS`] characters.
pub(crate) fn clean_name(name: &str) -> Option<String> {
    let trimmed = name.trim();
    (!trimmed.is_empty() && trimmed.chars().count() <= MAX_NAME_CHARS).then(|| trimmed.to_owned())
}

/// A valid avatar emoji: a few characters at most.
pub(crate) fn clean_emoji(emoji: &Option<String>) -> Option<String> {
    emoji.as_deref().map(str::trim).filter(|e| !e.is_empty() && e.chars().count() <= 8).map(str::to_owned)
}

// ---------------------------------------------------------------- ancestry

struct Ancestry {
    parents: HashMap<String, Vec<String>>,
    closure: std::cell::RefCell<HashMap<String, HashSet<String>>>,
}

impl Ancestry {
    fn new(ops: &[GroupOp]) -> Self {
        Self { parents: ops.iter().map(|o| (o.op_id.clone(), o.parents.clone())).collect(), closure: Default::default() }
    }

    /// Every op that `id` causally follows (known ones).
    fn ancestors(&self, id: &str) -> HashSet<String> {
        if let Some(found) = self.closure.borrow().get(id) {
            return found.clone();
        }
        let mut seen = HashSet::new();
        let mut stack: Vec<&String> = self.parents.get(id).map(|p| p.iter().collect()).unwrap_or_default();
        while let Some(next) = stack.pop() {
            if seen.insert(next.clone()) {
                if let Some(more) = self.parents.get(next) {
                    stack.extend(more.iter());
                }
            }
        }
        self.closure.borrow_mut().insert(id.to_owned(), seen.clone());
        seen
    }

    /// Neither op follows the other.
    fn concurrent(&self, a: &str, b: &str) -> bool {
        a != b && !self.ancestors(a).contains(b) && !self.ancestors(b).contains(a)
    }
}

// ---------------------------------------------------------------- replay

/// The state after replaying `ops` (any order, duplicates ignored) for the group named `group_id` (its create op's id).
pub(crate) fn replay(group_id: &str, ops: &[GroupOp]) -> GroupState {
    let mut sorted: Vec<GroupOp> = Vec::with_capacity(ops.len());
    let mut seen = HashSet::new();
    for op in ops {
        if seen.insert(op.op_id.clone()) {
            sorted.push(op.clone());
        }
    }
    sorted.sort_by(|a, b| (a.hlc, &a.op_id).cmp(&(b.hlc, &b.op_id)));
    let ancestry = Ancestry::new(&sorted);
    let mut removes: HashSet<String> = HashSet::new();
    let mut state = GroupState::default();
    for _ in 0..6 {
        let (next, effective) = pass(group_id, &sorted, &ancestry, &removes);
        state = next;
        if effective == removes {
            break;
        }
        removes = effective;
    }
    state
}

fn pass(group_id: &str, sorted: &[GroupOp], ancestry: &Ancestry, voiding_removes: &HashSet<String>) -> (GroupState, HashSet<String>) {
    let mut state = GroupState::default();
    let mut effective_removes = HashSet::new();
    let mut next_seq = 0usize;
    // The removes that can void an add, by the person they remove.
    let mut removes_of: HashMap<&str, Vec<&str>> = HashMap::new();
    for op in sorted {
        if let Kind::Remove { user } = &op.kind {
            if voiding_removes.contains(&op.op_id) {
                removes_of.entry(user.as_str()).or_default().push(op.op_id.as_str());
            }
        }
    }
    let join = |state: &mut GroupState, user: &str, role: Role, seq: &mut usize| {
        state.members.push(Member { user: user.to_owned(), role, seq: *seq });
        state.ever.insert(user.to_owned());
        *seq += 1;
    };
    for op in sorted {
        if let Kind::Create { name, emoji, members } = &op.kind {
            if state.created || op.op_id != group_id {
                continue;
            }
            let Some(name) = clean_name(name) else { continue };
            state.created = true;
            state.name = name.clone();
            state.emoji = clean_emoji(emoji);
            join(&mut state, &op.sender, Role::Owner, &mut next_seq);
            for user in members {
                if !state.is_member(user) && state.members.len() < MAX_MEMBERS {
                    join(&mut state, user, Role::Member, &mut next_seq);
                }
            }
            state.effects.push(Effect { op_id: op.op_id.clone(), hlc: op.hlc, actor: op.sender.clone(), event: Event::Created { name } });
            continue;
        }
        if !state.created {
            continue;
        }
        let actor_role = state.role_of(&op.sender);
        let event = match &op.kind {
            Kind::Create { .. } => None,
            Kind::Add { users } if actor_role.is_some_and(Role::can_manage) => {
                let mut added = Vec::new();
                for user in users {
                    let voided = removes_of.get(user.as_str()).is_some_and(|ids| ids.iter().any(|r| ancestry.concurrent(&op.op_id, r)));
                    if !voided && !state.is_member(user) && state.members.len() < MAX_MEMBERS {
                        join(&mut state, user, Role::Member, &mut next_seq);
                        added.push(user.clone());
                    }
                }
                (!added.is_empty()).then_some(Event::Added(added))
            }
            Kind::Remove { user } if state.may_remove(&op.sender, user) => {
                state.members.retain(|m| m.user != *user);
                effective_removes.insert(op.op_id.clone());
                Some(Event::Removed(user.clone()))
            }
            Kind::Leave if actor_role.is_some() => {
                let was_owner = actor_role == Some(Role::Owner);
                state.members.retain(|m| m.user != op.sender);
                if was_owner {
                    // The oldest admin, else the oldest member.
                    let successor = state
                        .members
                        .iter()
                        .filter(|m| m.role == Role::Admin)
                        .min_by_key(|m| m.seq)
                        .or_else(|| state.members.iter().min_by_key(|m| m.seq))
                        .map(|m| m.user.clone());
                    if let Some(user) = successor {
                        if let Some(member) = state.members.iter_mut().find(|m| m.user == user) {
                            member.role = Role::Owner;
                        }
                        state.effects.push(Effect { op_id: op.op_id.clone(), hlc: op.hlc, actor: op.sender.clone(), event: Event::Left });
                        state.effects.push(Effect { op_id: op.op_id.clone(), hlc: op.hlc, actor: user.clone(), event: Event::NewOwner(user) });
                        continue;
                    }
                }
                Some(Event::Left)
            }
            Kind::Rename { name } if actor_role.is_some_and(Role::can_manage) => clean_name(name).map(|name| {
                state.name = name.clone();
                Event::Renamed(name)
            }),
            Kind::SetAvatar { emoji, photo } if actor_role.is_some_and(Role::can_manage) => {
                state.emoji = if photo.is_some() { None } else { clean_emoji(emoji) };
                state.photo = photo.clone();
                Some(if photo.is_some() { Event::Photo } else { Event::Avatar })
            }
            Kind::SetRole { user, role } if actor_role == Some(Role::Owner) => {
                match state.members.iter_mut().find(|m| m.user == *user && m.role != Role::Owner) {
                    Some(member) => {
                        member.role = *role;
                        Some(Event::Role(user.clone(), *role))
                    }
                    None => None,
                }
            }
            _ => None,
        };
        if let Some(event) = event {
            state.effects.push(Effect { op_id: op.op_id.clone(), hlc: op.hlc, actor: op.sender.clone(), event });
        }
    }
    (state, effective_removes)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn op(id: &str, sender: &str, wall: i64, parents: &[&str], kind: Kind) -> GroupOp {
        GroupOp {
            op_id: id.to_owned(),
            sender: sender.to_owned(),
            hlc: Hlc { wall, counter: 0 },
            parents: parents.iter().map(|p| (*p).to_owned()).collect(),
            kind,
        }
    }

    fn create(owner: &str, members: &[&str]) -> GroupOp {
        op("g", owner, 1, &[], Kind::Create { name: "Grade 4 Team".into(), emoji: None, members: members.iter().map(|m| (*m).to_owned()).collect() })
    }

    fn users(state: &GroupState) -> Vec<String> {
        state.users()
    }

    #[test]
    fn create_makes_the_creator_owner_and_the_listed_people_members() {
        let state = replay("g", &[create("ann", &["bo", "cy", "bo"])]);
        assert!(state.created);
        assert_eq!(state.name, "Grade 4 Team");
        assert_eq!(users(&state), vec!["ann", "bo", "cy"], "no duplicates, the creator first");
        assert_eq!(state.role_of("ann"), Some(Role::Owner));
        assert_eq!(state.role_of("bo"), Some(Role::Member));
    }

    #[test]
    fn only_the_first_create_with_the_groups_own_id_counts_and_a_bad_name_makes_no_group() {
        let forged = op("x", "eve", 2, &[], Kind::Create { name: "Mine".into(), emoji: None, members: vec![] });
        let second = op("g2", "eve", 3, &[], Kind::Create { name: "Again".into(), emoji: None, members: vec![] });
        let state = replay("g", &[forged, create("ann", &["bo"]), second]);
        assert_eq!((state.name.as_str(), users(&state)), ("Grade 4 Team", vec!["ann".to_owned(), "bo".to_owned()]));
        let empty_name = op("g", "ann", 1, &[], Kind::Create { name: "   ".into(), emoji: None, members: vec![] });
        assert!(!replay("g", &[empty_name]).created);
        let long = op("g", "ann", 1, &[], Kind::Create { name: "x".repeat(51), emoji: None, members: vec![] });
        assert!(!replay("g", &[long]).created, "more than 50 characters");
    }

    #[test]
    fn the_owner_and_admins_add_and_a_plain_member_cannot() {
        let ops = [
            create("ann", &["bo"]),
            op("a1", "bo", 2, &["g"], Kind::Add { users: vec!["dee".into()] }), // a member: ignored
            op("a2", "ann", 3, &["g"], Kind::Add { users: vec!["cy".into()] }),
            op("r1", "ann", 4, &["a2"], Kind::SetRole { user: "bo".into(), role: Role::Admin }),
            op("a3", "bo", 5, &["r1"], Kind::Add { users: vec!["dee".into()] }), // now an admin
        ];
        let state = replay("g", &ops);
        assert_eq!(users(&state), vec!["ann", "bo", "cy", "dee"]);
    }

    #[test]
    fn a_concurrent_remove_beats_an_add_in_either_order_and_a_later_readd_works() {
        // Ann removes Cy while Bo (an admin) adds Cy back, neither having seen the other.
        let base = [
            create("ann", &["bo", "cy"]),
            op("p", "ann", 2, &["g"], Kind::SetRole { user: "bo".into(), role: Role::Admin }),
        ];
        let remove = op("rm", "ann", 5, &["p"], Kind::Remove { user: "cy".into() });
        let readd = op("ad", "bo", 6, &["p"], Kind::Add { users: vec!["cy".into()] }); // later clock, concurrent
        let mut a = base.to_vec();
        a.extend([remove.clone(), readd.clone()]);
        let mut b = base.to_vec();
        b.extend([readd.clone(), remove.clone()]);
        assert_eq!(users(&replay("g", &a)), vec!["ann", "bo"], "the remove wins");
        assert_eq!(replay("g", &a), replay("g", &b), "the arrival order does not matter");
        // The same pair, but the add comes first by clock: the remove still wins.
        let early_add = op("ad", "bo", 4, &["p"], Kind::Add { users: vec!["cy".into()] });
        assert_eq!(users(&replay("g", &[base[0].clone(), base[1].clone(), early_add, remove.clone()])), vec!["ann", "bo"]);
        // An add that follows the remove (it lists it as a parent) is a real re-add.
        let after = op("ad2", "bo", 9, &["rm"], Kind::Add { users: vec!["cy".into()] });
        a.push(after);
        assert_eq!(users(&replay("g", &a)), vec!["ann", "bo", "cy"]);
    }

    #[test]
    fn rename_is_last_writer_wins_by_clock_then_op_id_and_only_admins_rename() {
        let ops = [
            create("ann", &["bo"]),
            op("n1", "ann", 5, &["g"], Kind::Rename { name: "One".into() }),
            op("n2", "ann", 5, &["g"], Kind::Rename { name: "Two".into() }), // the same clock: the larger op id wins
            op("n3", "bo", 9, &["g"], Kind::Rename { name: "Mine".into() }),  // a member: ignored
        ];
        assert_eq!(replay("g", &ops).name, "Two");
        let mut reversed = ops.to_vec();
        reversed.reverse();
        assert_eq!(replay("g", &reversed).name, "Two");
        let empty = [create("ann", &[]), op("n", "ann", 2, &["g"], Kind::Rename { name: " ".into() })];
        assert_eq!(replay("g", &empty).name, "Grade 4 Team", "an empty name is ignored");
    }

    #[test]
    fn the_owner_cannot_be_removed_and_an_admin_cannot_remove_an_admin() {
        let ops = [
            create("ann", &["bo", "cy"]),
            op("r1", "ann", 2, &["g"], Kind::SetRole { user: "bo".into(), role: Role::Admin }),
            op("r2", "ann", 3, &["r1"], Kind::SetRole { user: "cy".into(), role: Role::Admin }),
            op("x1", "bo", 4, &["r2"], Kind::Remove { user: "ann".into() }), // the owner: no
            op("x2", "bo", 5, &["r2"], Kind::Remove { user: "cy".into() }),  // an admin removing an admin: no
            op("x3", "cy", 6, &["r2"], Kind::Remove { user: "cy".into() }),  // yourself: use leave
        ];
        assert_eq!(users(&replay("g", &ops)), vec!["ann", "bo", "cy"]);
    }

    #[test]
    fn a_member_may_leave_and_the_owner_leaving_hands_over_to_the_oldest_admin_else_the_oldest_member() {
        let leave_member = [create("ann", &["bo", "cy"]), op("l", "cy", 2, &["g"], Kind::Leave)];
        assert_eq!(users(&replay("g", &leave_member)), vec!["ann", "bo"]);
        // The owner leaves: Cy is an admin, so Cy (not the older Bo) becomes owner.
        let with_admin = [
            create("ann", &["bo", "cy"]),
            op("r", "ann", 2, &["g"], Kind::SetRole { user: "cy".into(), role: Role::Admin }),
            op("l", "ann", 3, &["r"], Kind::Leave),
        ];
        let state = replay("g", &with_admin);
        assert_eq!(state.role_of("cy"), Some(Role::Owner));
        assert_eq!(state.role_of("bo"), Some(Role::Member));
        // No admin: the oldest member, Bo.
        let none = [create("ann", &["bo", "cy"]), op("l", "ann", 2, &["g"], Kind::Leave)];
        assert_eq!(replay("g", &none).role_of("bo"), Some(Role::Owner));
        // The last person leaves: an empty group.
        let alone = [create("ann", &[]), op("l", "ann", 2, &["g"], Kind::Leave)];
        assert!(replay("g", &alone).members.is_empty());
    }

    #[test]
    fn a_group_is_capped_at_a_hundred_members() {
        let many: Vec<String> = (0..120).map(|i| format!("u{i}")).collect();
        let refs: Vec<&str> = many.iter().map(String::as_str).collect();
        assert_eq!(replay("g", &[create("ann", &refs)]).members.len(), MAX_MEMBERS);
    }

    #[test]
    fn every_arrival_order_gives_the_same_state() {
        let ops = vec![
            create("ann", &["bo", "cy"]),
            op("r", "ann", 2, &["g"], Kind::SetRole { user: "bo".into(), role: Role::Admin }),
            op("a", "bo", 3, &["r"], Kind::Add { users: vec!["dee".into()] }),
            op("x", "ann", 3, &["r"], Kind::Remove { user: "dee".into() }),
            op("n", "bo", 4, &["a"], Kind::Rename { name: "Renamed".into() }),
            op("l", "cy", 5, &["g"], Kind::Leave),
            op("s", "ann", 6, &["n"], Kind::SetAvatar { emoji: Some("🍎".into()), photo: None }),
        ];
        let reference = replay("g", &ops);
        // Every rotation and the reverse (a sample of orders, enough to catch an order dependence).
        for shift in 0..ops.len() {
            let mut shuffled = ops.clone();
            shuffled.rotate_left(shift);
            assert_eq!(replay("g", &shuffled), reference, "rotation {shift}");
            shuffled.reverse();
            assert_eq!(replay("g", &shuffled), reference, "reversed rotation {shift}");
        }
        assert_eq!(reference.name, "Renamed");
        assert_eq!(reference.emoji.as_deref(), Some("🍎"));
        assert!(reference.ever.contains("cy") && !reference.is_member("cy"));
    }

    #[test]
    fn kinds_round_trip_through_their_payload() {
        for kind in [
            Kind::Create { name: "N".into(), emoji: Some("🍎".into()), members: vec!["a".into()] },
            Kind::Add { users: vec!["a".into(), "b".into()] },
            Kind::Remove { user: "a".into() },
            Kind::Leave,
            Kind::Rename { name: "N".into() },
            Kind::SetAvatar { emoji: None, photo: None },
            Kind::SetRole { user: "a".into(), role: Role::Admin },
        ] {
            assert_eq!(Kind::parse(kind.op_type(), &kind.payload()), Some(kind.clone()), "{}", kind.op_type());
        }
        assert!(Kind::parse("group.set_role", &json!({ "user": "a", "role": "owner" })).is_none(), "no one is made owner by an op");
        assert!(Kind::parse("group.nope", &json!({})).is_none());
    }
}
