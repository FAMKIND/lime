//! A jam's community chat (LIME-210g, `docs/jam.md` 13.8): a group (`grp:`) the writer makes for their jam's subscribers.
//!
//! - **Turning it on** is the writer's: the jam's state carries `community: true` to subscribers, and the public page the one bit `has_community`
//!   (so a Preview can offer "Join <writer>'s community"). The group itself, its members and messages are as private as any group.
//! - **Joining** needs no approval: a subscriber sends `jam.community.join` (Olm, to the writer); the writer's phone checks the sender is an
//!   **active subscriber** and then does today's group add **by itself**, the first time making the group. It needs the writer's phone online (the app
//!   says "You will be added when <writer>'s phone is next online"). The writer answers with `jam.community.reply` (`joined` or `full`).
//! - **Leaving** is the group's ordinary leave; **removing a subscriber** also removes them from the community.
//! - **The cap** is the group's 100 members (the writer included): the 101st is answered "full". (The announcement-channel mode that was meant to take
//!   over from there is LIME-193c, which is not built yet.)

use super::jam::{queue_op, signed_op};
use super::*;
use crate::store::jam as jam_store;

/// Jams' community joins handled in one pass (each is a group op).
const JOINS_PER_PASS: usize = 5;

#[uniffi::export]
impl LimeStore {
    /// The writer turns the community chat on or off. Subscribers are told with the jam's state and the public page says `has_community`.
    pub fn set_jam_community(&self, jam_id: String, on: bool) -> Result<(), StoreError> {
        let state = self.load_or_create_account()?;
        self.registered_user(&state)?;
        let now = now_ms();
        self.with_conn(|conn| {
            let jam = jam_store::get(conn, &jam_id)?.filter(|j| j.mine && !j.ended).ok_or(StoreError::NotFound)?;
            if jam.community == on {
                return Ok(());
            }
            let op = signed_op(conn, &state, "jam.update", &jam_id, None, json!({ "jam_id": jam_id, "title": jam.title, "about": jam.about, "topics": jam.topics, "tiers": jam.tiers, "community": on }), now)?;
            conn.execute("UPDATE jams SET community = ?2, state_hlc = ?3, page_state = 'dirty' WHERE jam_id = ?1", params![jam_id, on, op.hlc]).map_err(db_err)?;
            for user in jam_store::audience(conn, &jam_id, crate::store::jam::TIER_FREE)? {
                queue_op(conn, &jam_id, &user, &op)?;
            }
            Ok(())
        })
    }

    /// A subscriber asks to join the jam's community. Nothing is shown to the writer to approve; their phone adds me when it next runs.
    pub fn join_jam_community(&self, jam_id: String) -> Result<(), StoreError> {
        let state = self.load_or_create_account()?;
        self.registered_user(&state)?;
        let now = now_ms();
        self.with_conn(|conn| {
            let jam = jam_store::get(conn, &jam_id)?.filter(|j| !j.mine && j.community && j.status == "active").ok_or(StoreError::NotFound)?;
            if jam_store::join_state(conn, &jam_id, "")?.as_deref() == Some("joined") {
                return Ok(());
            }
            jam_store::set_join(conn, &jam_id, "", "asked", now)?;
            let op = signed_op(conn, &state, "jam.community.join", &jam_id, None, json!({ "jam_id": jam_id }), now)?;
            queue_op(conn, &jam_id, &jam.writer, &op)
        })
    }
}

impl LimeStore {
    /// The writer's phone: a subscriber's join (checked when it arrived) is made real, a few at a time. The first one makes the group; the rest are
    /// added to it. Runs outside the connection lock, as the group calls take it themselves.
    pub(super) fn process_community_joins(&self) {
        let Ok(pending) = self.with_conn(|conn| {
            let mut statement = conn.prepare("SELECT jam_id, user_id FROM community_joins WHERE state = 'pending' AND user_id <> '' ORDER BY at LIMIT ?1").map_err(db_err)?;
            let rows = statement.query_map(params![JOINS_PER_PASS as i64], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
            Ok(rows)
        }) else {
            return;
        };
        for (jam_id, user) in pending {
            let outcome = self.make_community_join(&jam_id, &user);
            let _ = match outcome {
                Ok(answer) => self.finish_community_join(&jam_id, &user, answer),
                // Not now (no account yet, a group call failed): leave it pending for the next pass.
                Err(_) => Ok(()),
            };
        }
    }

    /// `joined` or `full` for one pending join, or an error to try again; a person who is no longer a subscriber is dropped (`gone`).
    fn make_community_join(&self, jam_id: &str, user: &str) -> Result<&'static str, StoreError> {
        let (jam, active) = self.with_conn(|conn| {
            let jam = jam_store::get(conn, jam_id)?;
            let active = jam_store::subscriber(conn, jam_id, user)?.is_some_and(|(status, _)| status == "active");
            Ok((jam, active))
        })?;
        let Some(jam) = jam.filter(|j| j.mine && j.community) else { return Ok("gone") };
        if !active {
            return Ok("gone");
        }
        match jam.community_group {
            None => {
                let name = format!("{} community", jam.title);
                let group = self.create_group(name.chars().take(50).collect(), None, vec![user.to_owned()]).or_else(|_| self.create_group("Community".into(), None, vec![user.to_owned()]))?;
                self.with_conn(|conn| conn.execute("UPDATE jams SET community_group = ?2 WHERE jam_id = ?1", params![jam_id, group]).map(|_| ()).map_err(db_err))?;
                Ok("joined")
            }
            Some(group) => {
                let details = self.group_details(group.clone())?;
                if details.members.iter().any(|m| m.user_id == user) {
                    return Ok("joined");
                }
                if jam_store::community_is_full(details.members.len()) {
                    return Ok("full");
                }
                self.add_group_members(group, vec![user.to_owned()])?;
                Ok("joined")
            }
        }
    }

    /// Records the answer and tells the subscriber.
    fn finish_community_join(&self, jam_id: &str, user: &str, answer: &str) -> Result<(), StoreError> {
        let state = self.load_or_create_account()?;
        let now = now_ms();
        self.with_conn(|conn| {
            if answer == "gone" {
                conn.execute("DELETE FROM community_joins WHERE jam_id = ?1 AND user_id = ?2", params![jam_id, user]).map_err(db_err)?;
                return Ok(());
            }
            jam_store::set_join(conn, jam_id, user, answer, now)?;
            let op = signed_op(conn, &state, "jam.community.reply", jam_id, None, json!({ "jam_id": jam_id, "state": answer }), now)?;
            queue_op(conn, jam_id, user, &op)
        })
    }

    /// A subscriber was removed or left: they go from the community as well (the group's own remove).
    pub(super) fn leave_community_of(&self, jam_id: &str, user: &str) {
        let group = self.with_conn(|conn| Ok(jam_store::get(conn, jam_id)?.and_then(|j| if j.mine { j.community_group } else { None }))).ok().flatten();
        let _ = self.with_conn(|conn| conn.execute("DELETE FROM community_joins WHERE jam_id = ?1 AND user_id = ?2", params![jam_id, user]).map(|_| ()).map_err(db_err));
        if let Some(group) = group {
            let _ = self.remove_group_member(group, user.to_owned());
        }
    }
}
