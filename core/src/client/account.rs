//! Deleting my account (LIME-113, LIME-113c): a deleted account goes quietly.
//!
//! The order is the server's: it marks the account "deleting" first (sign-in and sends refused) and only deletes after the phone has sent the quiet
//! notices. A server refusal before that sends no notices. The notice is one signed op, `account.deleted`, to contacts, group members and jam
//! subscribers. Nothing is shown anywhere on receipt: the person just goes (`purge_deleted_person`). What each party learns: contacts and
//! members learn that this person's account is gone, which they would see anyway as the person stopped existing; the server sees ordinary sealed
//! messages.

use super::*;

#[uniffi::export]
impl LimeStore {
    /// Leaves groups (handing over ownership as for Leave), then sends the quiet notice to everyone who has a copy of me: accepted contacts, the
    /// members of my groups, my jams' subscribers. Best effort: returns how many could not be reached now. Their phones that are offline get it at
    /// their next sync.
    pub fn send_account_deleted_notices(&self, transport: Arc<dyn Transport>, auth_token: String) -> Result<u32, StoreError> {
        let mut failed = 0u32;
        let mut audience: std::collections::BTreeSet<String> = self.with_conn(delivery::accepted_peers)?.into_iter().collect();
        for conversation in self.list_conversations()? {
            if conversation.is_group && conversation.group_ended.is_none() && conversation.my_role.is_some() {
                for member in &conversation.members {
                    audience.insert(member.id.clone());
                }
                if self.leave_group(conversation.id).is_err() {
                    failed += 1;
                }
            }
        }
        for jam in self.list_my_jams()? {
            let subscribers = self.with_conn(|conn| {
                let mut st = conn.prepare("SELECT user_id FROM jam_subscribers WHERE jam_id = ?1 AND removed_at IS NULL").map_err(db_err)?;
                let rows = st.query_map(params![jam.jam_id], |r| r.get::<_, String>(0)).map_err(db_err)?;
                rows.collect::<Result<Vec<_>, _>>().map_err(db_err)
            })?;
            audience.extend(subscribers);
        }
        // Queued group ops (the leaves) go first.
        if self.deliver_queued(transport.clone(), auth_token.clone()).is_err() {
            failed += 1;
        }
        let _guard = self.lock_protocol();
        let mut state = self.load_or_create_account()?;
        let me = state.user_id.clone().filter(|_| state.registered).ok_or(StoreError::NotRegistered)?;
        for peer in audience.into_iter().filter(|p| *p != me) {
            if self.send_control_op(&transport, &auth_token, &mut state, &me, &peer, ACCOUNT_DELETED, json!({})).is_err() {
                failed += 1;
            }
        }
        Ok(failed)
    }

    /// People who deleted their account (a send to them is refused quietly).
    pub fn deleted_peers(&self) -> Result<Vec<String>, StoreError> {
        self.with_conn(|conn| {
            let mut st = conn.prepare("SELECT user_id FROM deleted_peers").map_err(db_err)?;
            let rows = st.query_map([], |r| r.get::<_, String>(0)).map_err(db_err)?;
            rows.collect::<Result<_, _>>().map_err(db_err)
        })
    }
}

/// What this phone drops when it learns that `user` deleted their account: nothing is shown, nothing is announced.
/// - the one-to-one chat stays as it is (messages kept); the person's picture, background, links and username go, and so do their keys and sessions;
/// - they are removed from groups without a line (and the "left" line their leaving made);
/// - their jam, its posts (and org posts they wrote), their credits on others' posts (the other author shows alone), their comments and likes go.
pub(crate) fn purge_deleted_person(conn: &Connection, user: &str, now: i64) -> Result<(), StoreError> {
    let run = |sql: &str| conn.execute(sql, params![user]).map_err(db_err);
    conn.execute("INSERT OR REPLACE INTO deleted_peers (user_id, deleted_at) VALUES (?1, ?2)", params![user, now]).map_err(db_err)?;
    // Keys, sessions, pictures, username.
    for sql in [
        "DELETE FROM contact_delivery_keys WHERE user_id = ?1",
        "DELETE FROM contact_profile_keys WHERE user_id = ?1",
        "DELETE FROM peer_devices WHERE user_id = ?1",
        "DELETE FROM olm_sessions WHERE peer_user_id = ?1",
        "DELETE FROM share_queue WHERE peer_user_id = ?1",
        "DELETE FROM key_shared WHERE peer_user_id = ?1",
        "DELETE FROM photos WHERE user_id = ?1",
        "DELETE FROM extras WHERE user_id = ?1",
        "DELETE FROM photo_notices WHERE peer_user_id = ?1",
        "DELETE FROM session_repairs WHERE peer_user_id = ?1",
        "DELETE FROM profile_key_requests WHERE peer_user_id = ?1",
        "UPDATE people SET username = NULL WHERE id = ?1",
    ] {
        let _ = run(sql);
    }
    // Groups: no line.
    run("DELETE FROM group_members WHERE user_id = ?1")?;
    run("DELETE FROM members WHERE person_id = ?1 AND conversation_id LIKE 'grp:%'")?;
    conn.execute(
        "DELETE FROM messages WHERE local_state = 'system' AND conversation_id LIKE 'grp:%' AND body LIKE '%\"e\":\"left\"%' AND body LIKE ?1",
        params![format!("%\"by\":\"{user}\"%")],
    )
    .map_err(db_err)?;
    // Jam: their jam and posts (and org posts), their credit on others' posts, their comments and likes.
    let posts: Vec<String> = {
        let mut st = conn.prepare("SELECT post_id FROM jam_posts WHERE author = ?1 OR jam_id IN (SELECT jam_id FROM jams WHERE writer = ?1 AND mine = 0)").map_err(db_err)?;
        let rows = st.query_map(params![user], |r| r.get::<_, String>(0)).map_err(db_err)?;
        rows.collect::<Result<_, _>>().map_err(db_err)?
    };
    for post in &posts {
        for sql in [
            "DELETE FROM jam_attachments WHERE post_id = ?1",
            "DELETE FROM jam_credits WHERE post_id = ?1",
            "DELETE FROM jam_reactions WHERE post_id = ?1",
            "DELETE FROM jam_my_reactions WHERE post_id = ?1",
            "DELETE FROM jam_comments WHERE post_id = ?1",
            "DELETE FROM jam_counts WHERE post_id = ?1",
            "DELETE FROM jam_posts WHERE post_id = ?1",
        ] {
            let _ = conn.execute(sql, params![post]);
        }
    }
    for sql in [
        "DELETE FROM jam_inbound WHERE jam_id IN (SELECT jam_id FROM jams WHERE writer = ?1 AND mine = 0)",
        "DELETE FROM jam_subscribers WHERE jam_id IN (SELECT jam_id FROM jams WHERE writer = ?1 AND mine = 0)",
        "DELETE FROM jams WHERE writer = ?1 AND mine = 0",
        "DELETE FROM jam_credits WHERE user_id = ?1",
        "DELETE FROM jam_comments WHERE author = ?1",
        "DELETE FROM jam_reactions WHERE user_id = ?1",
        "DELETE FROM jam_subscribers WHERE user_id = ?1",
    ] {
        let _ = run(sql);
    }
    Ok(())
}
