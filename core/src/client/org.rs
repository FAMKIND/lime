//! A band's members (LIME-246a, DESIGN-23 = A: private membership). A band is a teacher's jam; its members are a private group (`grp:`, marked with the jam in its
//! signed state, never shown in the chat list) whose people **are** the band's members:
//!
//! - **Roles.** *owner* = the group's owner (the jam's writer) and its admins (they edit the band, invite, remove and set roles); *writer* = a member the signed state
//!   lists as one (they may post as the band; today's co-authors become writers); *member*. Cap 100, the group's.
//! - **Joining** by invite code: the code carries the jam, its writer and a random token that lives only in the members group's state. The joiner sends
//!   `jam.org.join` (Olm) to the writer; the writer's phone checks the token and adds the person **by itself** when it next runs (the community pattern),
//!   answering `jam.org.reply` (`joined`, `full` or `refused`). The code also names the other owners (LIME-246d: `jam.writer.token[.owner,owner…]`, at most 4), and the
//!   request goes to each of them as well; whichever owner's phone runs first adds the person, and the others find them already in (no double add). The server sees an ordinary group and ordinary Olm items, nothing of the band.
//! - **Members follow the band's jam** on their own phones, paced (a member who leaves, or has unfollowed by hand, is not followed again).

use super::jam::{queue_op, signed_op};
use super::*;
use crate::protocol::group::{Kind, OrgChange, Role, MAX_MEMBERS};
use crate::store::groups;
use crate::store::jam as jam_store;

/// Joins answered in one pass.
const ORG_JOINS_PER_PASS: usize = 5;
/// Owners besides the writer that a code names.
const MAX_INVITE_OWNERS: usize = 4;

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct OrgMemberInfo {
    pub user_id: String,
    pub name: String,
    pub tone: u32,
    /// `owner`, `writer` or `member`.
    pub role: String,
    pub is_me: bool,
    /// I may change this person's role or remove them.
    pub can_manage: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct OrgInfo {
    pub jam_id: String,
    /// The conversation id of the members group (never shown in the chat list).
    pub conversation_id: String,
    pub writer_id: String,
    pub name: String,
    /// `owner`, `writer` or `member`.
    pub my_role: String,
    pub member_count: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct OrgInvite {
    pub jam_id: String,
    pub writer_id: String,
    pub token: String,
    /// The other owners (admins) when the code was made, so a join reaches every owner and not only the writer (LIME-246d).
    pub owners: Vec<String>,
}

fn role_name(state: &crate::protocol::group::GroupState, user: &str) -> &'static str {
    match state.role_of(user) {
        Some(Role::Owner | Role::Admin) => "owner",
        Some(Role::Member) if state.writers.contains(user) => "writer",
        _ => "member",
    }
}

/// This person's role in the band's members group on this phone (`owner`, `writer` or `member`); none if they are not in it or I have no such group.
pub(crate) fn org_role_of(conn: &Connection, jam_id: &str, user: &str) -> Option<&'static str> {
    let conversation = org_conversation(conn, jam_id).ok()??;
    let group_id = groups::group_id_of(&conversation)?;
    let group = groups::state_of(conn, group_id).ok()?;
    group.is_member(user).then(|| role_name(&group, user))
}

/// The band's owners (its owner and admins) on this phone.
pub(crate) fn org_owner_ids(conn: &Connection, jam_id: &str) -> Vec<String> {
    let Ok(Some(conversation)) = org_conversation(conn, jam_id) else { return vec![] };
    let Some(group_id) = groups::group_id_of(&conversation) else { return vec![] };
    let Ok(group) = groups::state_of(conn, group_id) else { return vec![] };
    let mut owners: Vec<String> = group.users().into_iter().filter(|u| role_name(&group, u) == "owner").collect();
    owners.sort();
    owners
}

/// The jam's members group, if there is one I am in.
fn org_conversation(conn: &Connection, jam_id: &str) -> Result<Option<String>, StoreError> {
    conn.query_row(
        "SELECT id FROM conversations WHERE group_org = ?1 AND request_state NOT IN ('blocked', 'left') ORDER BY id LIMIT 1",
        params![jam_id],
        |r| r.get(0),
    )
    .optional()
    .map_err(db_err)
}

#[uniffi::export]
impl LimeStore {
    /// The people in the band, owners first, then writers, then members. Only a member can see them (the group is private).
    pub fn org_members(&self, jam_id: String) -> Result<Vec<OrgMemberInfo>, StoreError> {
        let state = self.load_or_create_account()?;
        let me = state.user_id.clone().ok_or(StoreError::NotRegistered)?;
        self.with_conn(|conn| {
            let conversation = org_conversation(conn, &jam_id)?.ok_or(StoreError::NotFound)?;
            let group_id = groups::group_id_of(&conversation).ok_or(StoreError::NotFound)?;
            let group = groups::state_of(conn, group_id)?;
            if !group.is_member(&me) {
                return Err(StoreError::NotFound);
            }
            let i_manage = group.may_manage(&me);
            let mut out: Vec<OrgMemberInfo> = groups::members_with_names(conn, group_id)?
                .into_iter()
                .map(|(user_id, _, name, tone)| OrgMemberInfo {
                    is_me: user_id == me,
                    can_manage: user_id != me && i_manage && group.role_of(&user_id) != Some(Role::Owner),
                    name: if user_id == me { "You".to_owned() } else { name },
                    role: role_name(&group, &user_id).to_owned(),
                    user_id,
                    tone,
                })
                .collect();
            out.sort_by_key(|m| match m.role.as_str() { "owner" => 0, "writer" => 1, _ => 2 });
            Ok(out)
        })
    }

    /// The bands I belong to (as a member of their private group), with my role. Not the ones I only follow.
    pub fn my_orgs(&self) -> Result<Vec<OrgInfo>, StoreError> {
        let state = self.load_or_create_account()?;
        let me = state.user_id.clone().ok_or(StoreError::NotRegistered)?;
        self.with_conn(|conn| {
            let mut statement = conn
                .prepare("SELECT id, group_org FROM conversations WHERE group_org IS NOT NULL AND request_state NOT IN ('blocked', 'left') ORDER BY id")
                .map_err(db_err)?;
            let rows = statement.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
            let mut out = Vec::new();
            for (conversation, jam_id) in rows {
                let Some(group_id) = groups::group_id_of(&conversation) else { continue };
                let group = groups::state_of(conn, group_id)?;
                if !group.is_member(&me) || group.deleted {
                    continue;
                }
                let writer_id = group.members.iter().find(|m| m.role == Role::Owner).map(|m| m.user.clone()).unwrap_or_default();
                out.push(OrgInfo { jam_id, conversation_id: conversation, writer_id, name: group.name.clone(), my_role: role_name(&group, &me).to_owned(), member_count: group.members.len() as u32 });
            }
            Ok(out)
        })
    }

    /// Whether `user` may post as the band: an owner or a writer. (A member may not.)
    pub fn org_can_post_as(&self, jam_id: String, user_id: String) -> Result<bool, StoreError> {
        self.with_conn(|conn| {
            let Some(conversation) = org_conversation(conn, &jam_id)? else { return Ok(false) };
            let Some(group_id) = groups::group_id_of(&conversation) else { return Ok(false) };
            let group = groups::state_of(conn, group_id)?;
            Ok(group.is_member(&user_id) && role_name(&group, &user_id) != "member")
        })
    }

    /// The band's owner opens its members group (the first time; nothing happens after). The app calls it when the owner first looks at Members.
    pub fn org_start(&self, jam_id: String) -> Result<(), StoreError> {
        self.ensure_org(&jam_id).map(|_| ())
    }

    /// Adds people to the band (owners may; from contacts). The 101st is refused. They are sent the group and follow the band's jam on their own phones.
    pub fn add_org_members(&self, jam_id: String, user_ids: Vec<String>) -> Result<(), StoreError> {
        let conversation = self.ensure_org(&jam_id)?;
        self.add_group_members(conversation, user_ids)
    }

    /// Removes a member (owners may; an owner removes writers and members). They stop being followed on their phone only by their own choice.
    pub fn remove_org_member(&self, jam_id: String, user_id: String) -> Result<(), StoreError> {
        let conversation = self.with_conn(|conn| org_conversation(conn, &jam_id))?.ok_or(StoreError::NotFound)?;
        self.remove_group_member(conversation, user_id.clone())?;
        self.remove_from_org_groups(&jam_id, &user_id);
        Ok(())
    }

    /// Sets a person's role: `owner` (only the band's owner may), `writer` or `member` (owners may).
    pub fn set_org_role(&self, jam_id: String, user_id: String, role: String) -> Result<(), StoreError> {
        if !matches!(role.as_str(), "owner" | "writer" | "member") {
            return Err(StoreError::Rejected);
        }
        let conversation = self.with_conn(|conn| org_conversation(conn, &jam_id))?.ok_or(StoreError::NotFound)?;
        let (group_id, state, me) = self.group_context(&conversation)?;
        let before = self.with_conn(|conn| groups::state_of(conn, &group_id))?;
        if !before.may_manage(&me) || !before.is_member(&user_id) || before.role_of(&user_id) == Some(Role::Owner) {
            return Err(StoreError::Rejected);
        }
        let is_admin = before.role_of(&user_id) == Some(Role::Admin);
        if (role == "owner") != is_admin {
            // Becoming or ceasing to be an owner changes the group role: only the group's owner does that.
            self.set_group_admin(conversation.clone(), user_id.clone(), role == "owner")?;
        }
        let writer = role == "writer";
        if before.writers.contains(&user_id) != writer {
            self.make_group_op(&state, &me, &group_id, None, Kind::Org(OrgChange::Writer { user: user_id, on: writer }))?;
        }
        Ok(())
    }

    /// Leaves the band: out of its members group, its groups, and no longer following its jam.
    pub fn leave_org(&self, jam_id: String) -> Result<(), StoreError> {
        let conversation = self.with_conn(|conn| org_conversation(conn, &jam_id))?.ok_or(StoreError::NotFound)?;
        self.leave_org_groups(&jam_id);
        self.leave_group(conversation)?;
        let _ = self.unsubscribe_from_jam(jam_id);
        Ok(())
    }

    /// The code that joins the band: the jam, its writer and the invite token (made the first time; owners only).
    pub fn org_invite_code(&self, jam_id: String) -> Result<String, StoreError> {
        let conversation = self.ensure_org(&jam_id)?;
        let (group_id, state, me) = self.group_context(&conversation)?;
        let group = self.with_conn(|conn| groups::state_of(conn, &group_id))?;
        if !group.may_manage(&me) {
            return Err(StoreError::Rejected);
        }
        let writer = group.members.iter().find(|m| m.role == Role::Owner).map(|m| m.user.clone()).unwrap_or(me.clone());
        let owners: Vec<String> = group.members.iter().filter(|m| m.role == Role::Admin && m.user != writer).map(|m| m.user.clone()).take(MAX_INVITE_OWNERS).collect();
        let token = match group.invite {
            Some(token) => token,
            None => {
                let token = new_token();
                self.make_group_op(&state, &me, &group_id, None, Kind::Org(OrgChange::Invite { token: Some(token.clone()) }))?;
                token
            }
        };
        Ok(if owners.is_empty() { format!("{jam_id}.{writer}.{token}") } else { format!("{jam_id}.{writer}.{token}.{}", owners.join(",")) })
    }

    /// Turns the invite link off (`false`) or makes a new one that replaces the old (`true`; owners only). Returns the new code when on.
    pub fn reset_org_invite(&self, jam_id: String, on: bool) -> Result<Option<String>, StoreError> {
        let conversation = self.ensure_org(&jam_id)?;
        let (group_id, state, me) = self.group_context(&conversation)?;
        if !self.with_conn(|conn| groups::state_of(conn, &group_id))?.may_manage(&me) {
            return Err(StoreError::Rejected);
        }
        let token = on.then(new_token);
        self.make_group_op(&state, &me, &group_id, None, Kind::Org(OrgChange::Invite { token }))?;
        if on { self.org_invite_code(jam_id).map(Some) } else { Ok(None) }
    }

    /// Reads an invite code (`jam.writer.token`); `None` when it is not one.
    pub fn parse_org_invite(&self, code: String) -> Option<OrgInvite> {
        let parts: Vec<&str> = code.trim().split('.').collect();
        if !(parts.len() == 3 || parts.len() == 4) || !parts.iter().all(|p| !p.is_empty() && p.len() <= 64 * (MAX_INVITE_OWNERS + 1)) {
            return None;
        }
        let owners: Vec<String> = parts.get(3).map(|o| o.split(',').filter(|u| !u.is_empty() && u.len() <= 64).take(MAX_INVITE_OWNERS).map(str::to_owned).collect()).unwrap_or_default();
        Some(OrgInvite { jam_id: parts[0].to_owned(), writer_id: parts[1].to_owned(), token: parts[2].to_owned(), owners })
    }

    /// Asks to join with an invite code. Nothing is shown to the owner to approve; their phone adds me when it next runs.
    pub fn join_org(&self, code: String) -> Result<(), StoreError> {
        let invite = self.parse_org_invite(code).ok_or(StoreError::Rejected)?;
        let state = self.load_or_create_account()?;
        let me = self.registered_user(&state)?;
        if invite.writer_id == me {
            return Err(StoreError::Rejected);
        }
        let now = now_ms();
        self.with_conn(|conn| {
            if org_conversation(conn, &invite.jam_id)?.is_some() {
                return Ok(());
            }
            conn.execute(
                "INSERT OR REPLACE INTO org_joins (jam_id, user_id, token, target, state, at) VALUES (?1, '', '', '', 'asked', ?2)",
                params![invite.jam_id, now],
            )
            .map_err(db_err)?;
            // To the writer and to every other owner the code names: any of their phones may add me.
            let mut targets = vec![invite.writer_id.clone()];
            targets.extend(invite.owners.iter().filter(|o| **o != me && **o != invite.writer_id).cloned());
            for target in targets {
                let op = signed_op(conn, &state, "jam.org.join", &invite.jam_id, None, json!({ "jam_id": invite.jam_id, "token": invite.token }), now)?;
                queue_op(conn, &invite.jam_id, &target, &op)?;
            }
            Ok(())
        })
    }

    /// My own join: `asked` (waiting for an owner's phone), `joined`, `full` or `refused`; none if I have not asked.
    pub fn org_join_state(&self, jam_id: String) -> Result<Option<String>, StoreError> {
        self.with_conn(|conn| {
            if org_conversation(conn, &jam_id)?.is_some() {
                return Ok(Some("joined".to_owned()));
            }
            conn.query_row("SELECT state FROM org_joins WHERE jam_id = ?1 AND user_id = '' AND target = ''", params![jam_id], |r| r.get(0)).optional().map_err(db_err)
        })
    }
}

fn new_token() -> String {
    uuid::Uuid::new_v4().simple().to_string()
}

impl LimeStore {
    /// The band's members group on this phone, made now if it does not exist and the jam is mine (the first time: the existing co-authors of its posts become writers).
    pub(crate) fn ensure_org(&self, jam_id: &str) -> Result<String, StoreError> {
        if let Some(existing) = self.with_conn(|conn| org_conversation(conn, jam_id))? {
            return Ok(existing);
        }
        let state = self.load_or_create_account()?;
        let me = state.user_id.clone().filter(|_| state.registered).ok_or(StoreError::NotRegistered)?;
        let (title, coauthors) = self.with_conn(|conn| {
            let jam = jam_store::get(conn, jam_id)?.filter(|j| j.mine && !j.ended).ok_or(StoreError::NotFound)?;
            let mut statement = conn
                .prepare("SELECT DISTINCT c.user_id FROM jam_credits c JOIN jam_posts p ON p.post_id = c.post_id WHERE p.jam_id = ?1 AND c.state = 'accepted' ORDER BY c.user_id")
                .map_err(db_err)?;
            let users = statement.query_map(params![jam_id], |r| r.get::<_, String>(0)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
            Ok((jam.title, users))
        })?;
        // Members-only posts need the tier (LIME-246b).
        self.with_conn(|conn| {
            let jam = jam_store::get(conn, jam_id)?.ok_or(StoreError::NotFound)?;
            if !jam.tiers.iter().any(|t| t == jam_store::TIER_MEMBERS) {
                let mut tiers = jam.tiers.clone();
                tiers.push(jam_store::TIER_MEMBERS.to_owned());
                conn.execute("UPDATE jams SET tiers = ?2 WHERE jam_id = ?1", params![jam_id, json!(tiers).to_string()]).map_err(db_err)?;
            }
            Ok(())
        })?;
        let name = crate::protocol::group::clean_name(&title.chars().take(50).collect::<String>()).unwrap_or_else(|| "Band".to_owned());
        let group_id = new_id();
        let people: Vec<String> = coauthors.into_iter().filter(|u| *u != me).collect();
        self.make_group_op(&state, &me, &group_id, Some(group_id.clone()), Kind::Create { name, emoji: None, members: people.clone() })?;
        self.make_group_op(&state, &me, &group_id, None, Kind::Org(OrgChange::Mark { jam_id: jam_id.to_owned() }))?;
        for user in people {
            self.make_group_op(&state, &me, &group_id, None, Kind::Org(OrgChange::Writer { user, on: true }))?;
        }
        Ok(groups::conversation_id(&group_id))
    }

    /// The owner's phone, once per pass: a jam of mine with accepted co-authors and no members group yet gets one, the co-authors as its writers (a one-time migration),
    /// then the people who asked to join are added, and I follow the bands I belong to.
    pub(super) fn process_orgs(&self) {
        let _ = self.migrate_coauthors_to_writers();
        self.process_org_joins();
        self.process_org_group_joins();
        self.sync_member_tiers();
        self.follow_my_orgs();
    }

    fn migrate_coauthors_to_writers(&self) -> Result<(), StoreError> {
        let jams: Vec<String> = self.with_conn(|conn| {
            let mut statement = conn
                .prepare(
                    "SELECT j.jam_id FROM jams j WHERE j.mine = 1 AND j.ended = 0
                       AND NOT EXISTS (SELECT 1 FROM conversations c WHERE c.group_org = j.jam_id)
                       AND EXISTS (SELECT 1 FROM jam_credits c JOIN jam_posts p ON p.post_id = c.post_id WHERE p.jam_id = j.jam_id AND c.state = 'accepted')",
                )
                .map_err(db_err)?;
            let rows = statement.query_map([], |r| r.get::<_, String>(0)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
            Ok(rows)
        })?;
        for jam in jams {
            let _ = self.ensure_org(&jam);
        }
        Ok(())
    }

    fn process_org_joins(&self) {
        let Ok(pending) = self.with_conn(|conn| {
            let mut statement = conn.prepare("SELECT jam_id, user_id, token FROM org_joins WHERE state = 'pending' AND user_id <> '' ORDER BY at LIMIT ?1").map_err(db_err)?;
            let rows = statement.query_map(params![ORG_JOINS_PER_PASS as i64], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, String>(2)?))).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
            Ok(rows)
        }) else {
            return;
        };
        for (jam_id, user, token) in pending {
            let Ok(answer) = self.make_org_join(&jam_id, &user, &token) else { continue };
            let Ok(state) = self.load_or_create_account() else { return };
            let now = now_ms();
            let _ = self.with_conn(|conn| {
                conn.execute("DELETE FROM org_joins WHERE jam_id = ?1 AND user_id = ?2 AND target = ''", params![jam_id, user]).map_err(db_err)?;
                let op = signed_op(conn, &state, "jam.org.reply", &jam_id, None, json!({ "jam_id": jam_id, "state": answer }), now)?;
                queue_op(conn, &jam_id, &user, &op)
            });
        }
    }

    /// `joined`, `full` or `refused` for one pending join; an error to try again later.
    fn make_org_join(&self, jam_id: &str, user: &str, token: &str) -> Result<&'static str, StoreError> {
        let Some(conversation) = self.with_conn(|conn| org_conversation(conn, jam_id))? else { return Ok("refused") };
        let (group_id, state, me) = self.group_context(&conversation)?;
        let group = self.with_conn(|conn| groups::state_of(conn, &group_id))?;
        if !group.may_manage(&me) || group.invite.as_deref() != Some(token) {
            return Ok("refused");
        }
        if group.is_member(user) {
            return Ok("joined");
        }
        if group.members.len() >= MAX_MEMBERS {
            return Ok("full");
        }
        let _ = state;
        self.add_group_members(conversation, vec![user.to_owned()])?;
        Ok("joined")
    }

    /// Follows the bands I belong to (their jams), paced: one per pass; not a band I left or unfollowed by hand.
    fn follow_my_orgs(&self) {
        let Ok(orgs) = self.my_orgs() else { return };
        let Ok(state) = self.load_or_create_account() else { return };
        let Some(me) = state.user_id.clone() else { return };
        for org in orgs {
            if org.writer_id == me || org.writer_id.is_empty() {
                continue;
            }
            let wanted = self
                .with_conn(|conn| {
                    let off: bool = conn.query_row("SELECT EXISTS (SELECT 1 FROM jam_follow_off WHERE jam_id = ?1)", params![org.jam_id], |r| r.get(0)).map_err(db_err)?;
                    Ok(!off && jam_store::get(conn, &org.jam_id)?.is_none_or(|j| !j.mine && j.status != "active" && j.status != "requested"))
                })
                .unwrap_or(false);
            if wanted && self.subscribe_to_jam(org.jam_id.clone(), org.writer_id.clone()).is_ok() {
                return;
            }
        }
    }

    /// Whether I am an owner (the band's owner or an admin) of this band's members group on this phone.
    pub(super) fn is_org_owner(&self, conn: &Connection, jam_id: &str, me: &str) -> bool {
        let Ok(Some(conversation)) = org_conversation(conn, jam_id) else { return false };
        let Some(group_id) = groups::group_id_of(&conversation) else { return false };
        groups::state_of(conn, group_id).is_ok_and(|g| g.may_manage(me))
    }

    /// An owner's phone receives a join request (`jam.org.join`), checked later against the token.
    pub(super) fn note_org_join(&self, conn: &Connection, jam_id: &str, sender: &str, token: &str, now: i64) -> Result<(), StoreError> {
        conn.execute(
            "INSERT OR REPLACE INTO org_joins (jam_id, user_id, token, target, state, at) VALUES (?1, ?2, ?3, '', 'pending', ?4)",
            params![jam_id, sender, token, now],
        )
        .map_err(db_err)?;
        Ok(())
    }

    /// The writer's answer to my join.
    pub(super) fn note_org_reply(&self, conn: &Connection, jam_id: &str, answer: &str, now: i64) -> Result<(), StoreError> {
        conn.execute(
            "INSERT OR REPLACE INTO org_joins (jam_id, user_id, token, target, state, at) VALUES (?1, '', '', '', ?2, ?3)",
            params![jam_id, answer, now],
        )
        .map_err(db_err)?;
        Ok(())
    }

    /// A member removed from the band goes from its groups as well: the groups I run take them out (best effort).
    pub(crate) fn remove_from_org_groups(&self, jam_id: &str, user_id: &str) {
        let Ok(groups_here) = self.org_group_entries(jam_id) else { return };
        for (conversation, _, _, _) in groups_here {
            let _ = self.remove_group_member(conversation, user_id.to_owned());
        }
    }

    /// Leaving the band leaves its groups.
    pub(crate) fn leave_org_groups(&self, jam_id: &str) {
        let Ok(groups_here) = self.org_group_entries(jam_id) else { return };
        for (conversation, _, _, _) in groups_here {
            let _ = self.leave_group(conversation);
        }
    }

    /// The band's groups as its members group lists them: (conversation id, name, open, owner).
    fn org_group_entries(&self, jam_id: &str) -> Result<Vec<(String, String, bool, String)>, StoreError> {
        self.with_conn(|conn| {
            let Some(conversation) = org_conversation(conn, jam_id)? else { return Ok(Vec::new()) };
            let Some(group_id) = groups::group_id_of(&conversation) else { return Ok(Vec::new()) };
            Ok(groups::state_of(conn, group_id)?.org_groups.into_iter().map(|g| (g.id, g.name, g.open, g.owner)).collect())
        })
    }

    /// Members of my bands are subscribers of the members tier (so a members-only post goes to them and no one else); someone no longer a member goes back to free,
    /// and the members session is replaced so they read nothing that follows. Run by the band's owner's phone each pass.
    fn sync_member_tiers(&self) {
        let Ok(state) = self.load_or_create_account() else { return };
        let Some(me) = state.user_id.clone() else { return };
        let now = now_ms();
        let jams: Vec<(String, String)> = self
            .with_conn(|conn| {
                let mut statement = conn
                    .prepare("SELECT j.jam_id, c.id FROM jams j JOIN conversations c ON c.group_org = j.jam_id WHERE j.mine = 1 AND j.ended = 0 AND c.request_state NOT IN ('blocked', 'left')")
                    .map_err(db_err)?;
                let rows = statement.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
                Ok(rows)
            })
            .unwrap_or_default();
        for (jam_id, conversation) in jams {
            let _ = self.with_conn(|conn| {
                let Some(group_id) = groups::group_id_of(&conversation) else { return Ok(()) };
                let group = groups::state_of(conn, group_id)?;
                let Some(jam) = jam_store::get(conn, &jam_id)?.filter(|j| j.mine) else { return Ok(()) };
                for user in group.users().into_iter().filter(|u| *u != me) {
                    if let Some((status, tier)) = jam_store::subscriber(conn, &jam_id, &user)? {
                        if status == "active" && tier != jam_store::TIER_MEMBERS {
                            conn.execute("UPDATE jam_subscribers SET tier = 'members' WHERE jam_id = ?1 AND user_id = ?2", params![jam_id, user]).map_err(db_err)?;
                            // Again as a welcome: the sessions and the archive of what a member may now read.
                            self.accept_subscriber(conn, &state, &jam, &user, now)?;
                        }
                    }
                }
                let mut statement = conn.prepare("SELECT user_id FROM jam_subscribers WHERE jam_id = ?1 AND tier = 'members'").map_err(db_err)?;
                let held = statement.query_map(params![jam_id], |r| r.get::<_, String>(0)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
                for user in held.into_iter().filter(|u| !group.is_member(u)) {
                    conn.execute("UPDATE jam_subscribers SET tier = 'free' WHERE jam_id = ?1 AND user_id = ?2", params![jam_id, user]).map_err(db_err)?;
                    jam_store::mark_rotate(conn, &jam_id)?;
                }
                Ok(())
            });
        }
    }

    fn process_org_group_joins(&self) {
        let Ok(pending) = self.with_conn(|conn| {
            let mut statement = conn
                .prepare("SELECT jam_id, user_id, target FROM org_joins WHERE state = 'pending' AND user_id <> '' AND target <> '' ORDER BY at LIMIT ?1")
                .map_err(db_err)?;
            let rows = statement
                .query_map(params![ORG_JOINS_PER_PASS as i64], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, String>(2)?)))
                .map_err(db_err)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(db_err)?;
            Ok(rows)
        }) else {
            return;
        };
        for (jam_id, user, target) in pending {
            let Ok(answer) = self.make_org_group_join(&jam_id, &user, &target) else { continue };
            let Ok(state) = self.load_or_create_account() else { return };
            let now = now_ms();
            let _ = self.with_conn(|conn| {
                conn.execute("DELETE FROM org_joins WHERE jam_id = ?1 AND user_id = ?2 AND target = ?3", params![jam_id, user, target]).map_err(db_err)?;
                let op = signed_op(conn, &state, "jam.org.group_reply", &jam_id, None, json!({ "jam_id": jam_id, "group": target, "state": answer }), now)?;
                queue_op(conn, &jam_id, &user, &op)
            });
        }
    }

    /// `joined`, `full` or `refused` for a member's request to join one of the band's groups, which I run. An invite-only group refuses every request, and so
    /// does anyone who is not a member of the band.
    fn make_org_group_join(&self, jam_id: &str, user: &str, target: &str) -> Result<&'static str, StoreError> {
        let (group_id, _, me) = self.group_context(target)?;
        let group = self.with_conn(|conn| groups::state_of(conn, &group_id))?;
        let open = group.parent.as_ref().is_some_and(|(jam, open)| jam == jam_id && *open);
        if !group.may_manage(&me) || !open {
            return Ok("refused");
        }
        let in_band = self.with_conn(|conn| {
            let Some(conversation) = org_conversation(conn, jam_id)? else { return Ok(false) };
            let Some(band) = groups::group_id_of(&conversation) else { return Ok(false) };
            Ok(groups::state_of(conn, band)?.is_member(user))
        })?;
        if !in_band {
            return Ok("refused");
        }
        if group.is_member(user) {
            return Ok("joined");
        }
        if group.members.len() >= MAX_MEMBERS {
            return Ok("full");
        }
        self.add_group_members(target.to_owned(), vec![user.to_owned()])?;
        Ok("joined")
    }

    pub(super) fn note_org_group_join(&self, conn: &Connection, jam_id: &str, sender: &str, group: &str, now: i64) -> Result<(), StoreError> {
        conn.execute(
            "INSERT OR REPLACE INTO org_joins (jam_id, user_id, token, target, state, at) VALUES (?1, ?2, '', ?3, 'pending', ?4)",
            params![jam_id, sender, group, now],
        )
        .map_err(db_err)?;
        Ok(())
    }

    pub(super) fn note_org_group_reply(&self, conn: &Connection, jam_id: &str, group: &str, answer: &str, now: i64) -> Result<(), StoreError> {
        conn.execute(
            "INSERT OR REPLACE INTO org_joins (jam_id, user_id, token, target, state, at) VALUES (?1, '', '', ?2, ?3, ?4)",
            params![jam_id, group, answer, now],
        )
        .map_err(db_err)?;
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct OrgGroupInfo {
    pub conversation_id: String,
    pub name: String,
    /// Any member of the band may join (otherwise by invitation only).
    pub open: bool,
    /// I am in it.
    pub joined: bool,
    /// I made it (and so run it).
    pub mine: bool,
}

#[uniffi::export]
impl LimeStore {
    /// The groups of a band, as its members group lists them (only a member sees them).
    pub fn org_groups(&self, jam_id: String) -> Result<Vec<OrgGroupInfo>, StoreError> {
        let state = self.load_or_create_account()?;
        let me = state.user_id.clone().ok_or(StoreError::NotRegistered)?;
        self.with_conn(|conn| {
            let conversation = org_conversation(conn, &jam_id)?.ok_or(StoreError::NotFound)?;
            let band = groups::group_id_of(&conversation).ok_or(StoreError::NotFound)?;
            let band_state = groups::state_of(conn, band)?;
            if !band_state.is_member(&me) {
                return Err(StoreError::NotFound);
            }
            let mut out = Vec::new();
            for entry in band_state.org_groups {
                let joined = groups::group_id_of(&entry.id).is_some_and(|g| groups::state_of(conn, g).map(|s| s.is_member(&me)).unwrap_or(false));
                out.push(OrgGroupInfo { mine: entry.owner == me, conversation_id: entry.id, name: entry.name, open: entry.open, joined });
            }
            Ok(out)
        })
    }

    /// Which band a group belongs to, if it was made inside one (so the chat list can show the band's picture on it).
    pub fn org_group_parent(&self, conversation_id: String) -> Result<Option<String>, StoreError> {
        self.with_conn(|conn| {
            Ok(conn
                .query_row("SELECT group_parent FROM conversations WHERE id = ?1", params![conversation_id], |r| r.get::<_, Option<String>>(0))
                .optional()
                .map_err(db_err)?
                .flatten())
        })
    }

    /// An owner makes a group inside the band (`open`: any member may join; otherwise by invitation only), with people from the band. Returns its conversation id.
    pub fn create_org_group(&self, jam_id: String, name: String, emoji: Option<String>, open: bool, members: Vec<String>) -> Result<String, StoreError> {
        let name = crate::protocol::group::clean_name(&name).ok_or(StoreError::Rejected)?;
        let band_conversation = self.with_conn(|conn| org_conversation(conn, &jam_id))?.ok_or(StoreError::NotFound)?;
        let (band_id, state, me) = self.group_context(&band_conversation)?;
        let band = self.with_conn(|conn| groups::state_of(conn, &band_id))?;
        if !band.may_manage(&me) {
            return Err(StoreError::Rejected);
        }
        let mut people: Vec<String> = Vec::new();
        for user in members {
            if user != me && band.is_member(&user) && !people.contains(&user) {
                people.push(user);
            }
        }
        if people.len() + 1 > MAX_MEMBERS {
            return Err(StoreError::Rejected);
        }
        let group_id = new_id();
        self.make_group_op(&state, &me, &group_id, Some(group_id.clone()), Kind::Create { name: name.clone(), emoji: crate::protocol::group::clean_emoji(&emoji), members: people })?;
        self.make_group_op(&state, &me, &group_id, None, Kind::Org(OrgChange::Parent { jam_id: jam_id.clone(), open }))?;
        let conversation = groups::conversation_id(&group_id);
        self.make_group_op(&state, &me, &band_id, None, Kind::Org(OrgChange::Group { id: conversation.clone(), name, open, on: true, owner: me.clone() }))?;
        Ok(conversation)
    }

    /// Asks to join one of the band's groups. Open ones only: the group's owner's phone adds me when it next runs. An invitation-only group is refused here.
    pub fn join_org_group(&self, jam_id: String, conversation_id: String) -> Result<(), StoreError> {
        let entry = self.org_group_entries(&jam_id)?.into_iter().find(|(id, ..)| *id == conversation_id).ok_or(StoreError::NotFound)?;
        if !entry.2 {
            return Err(StoreError::Rejected);
        }
        let state = self.load_or_create_account()?;
        let me = self.registered_user(&state)?;
        if entry.3 == me {
            return Ok(());
        }
        let now = now_ms();
        self.with_conn(|conn| {
            conn.execute("INSERT OR REPLACE INTO org_joins (jam_id, user_id, token, target, state, at) VALUES (?1, '', '', ?2, 'asked', ?3)", params![jam_id, conversation_id, now]).map_err(db_err)?;
            let op = signed_op(conn, &state, "jam.org.group_join", &jam_id, None, json!({ "jam_id": jam_id, "group": conversation_id }), now)?;
            queue_op(conn, &jam_id, &entry.3, &op)
        })
    }

    /// My own request to join a band's group: `asked`, `joined`, `full` or `refused`; none if I have not asked.
    pub fn org_group_join_state(&self, jam_id: String, conversation_id: String) -> Result<Option<String>, StoreError> {
        let state = self.load_or_create_account()?;
        let me = state.user_id.clone().ok_or(StoreError::NotRegistered)?;
        self.with_conn(|conn| {
            if let Some(group_id) = groups::group_id_of(&conversation_id) {
                if groups::state_of(conn, group_id)?.is_member(&me) {
                    return Ok(Some("joined".to_owned()));
                }
            }
            conn.query_row("SELECT state FROM org_joins WHERE jam_id = ?1 AND user_id = '' AND target = ?2", params![jam_id, conversation_id], |r| r.get(0)).optional().map_err(db_err)
        })
    }
}
