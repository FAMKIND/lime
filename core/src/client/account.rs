//! Deleting my account (LIME-113): what the phone does before the server step, and what it knows afterwards about people who deleted theirs.
//!
//! Before the server deletes anything the phone tells the people it can still reach, encrypted: contacts get `account.deleted` (their chat turns
//! read-only and says "This account was deleted"), groups are left (the owner's role passes on as for Leave), my jams are ended (subscribers keep
//! what they have). What each party learns: contacts and members learn that I deleted my account, which they would learn anyway; the server sees
//! ordinary sealed messages.

use super::*;

#[uniffi::export]
impl LimeStore {
    /// Tells contacts, leaves groups, ends my jams, and sends what is queued. Best effort: returns how many of these could not be done now (offline,
    /// a contact unreachable). The server step follows whatever the number: a person who deletes their account is not held up by a failed notice.
    pub fn wind_down_account(&self, transport: Arc<dyn Transport>, auth_token: String) -> Result<u32, StoreError> {
        let mut failed = 0u32;
        // Groups I am in, then my jams.
        for conversation in self.list_conversations()? {
            if conversation.is_group && conversation.group_ended.is_none() && conversation.my_role.is_some() && self.leave_group(conversation.id).is_err() {
                failed += 1;
            }
        }
        for jam in self.list_my_jams()? {
            if !jam.ended && self.end_jam(jam.jam_id).is_err() {
                failed += 1;
            }
        }
        // What is queued (group and jam ops) goes now.
        if self.deliver_queued(transport.clone(), auth_token.clone()).is_err() {
            failed += 1;
        }
        // Then the contacts.
        let _guard = self.lock_protocol();
        let mut state = self.load_or_create_account()?;
        let me = state.user_id.clone().filter(|_| state.registered).ok_or(StoreError::NotRegistered)?;
        for peer in self.with_conn(delivery::accepted_peers)? {
            if self.send_control_op(&transport, &auth_token, &mut state, &me, &peer, ACCOUNT_DELETED, json!({})).is_err() {
                failed += 1;
            }
        }
        Ok(failed)
    }

    /// People who told me they deleted their account (their chats are read-only).
    pub fn deleted_peers(&self) -> Result<Vec<String>, StoreError> {
        self.with_conn(|conn| {
            let mut st = conn.prepare("SELECT user_id FROM deleted_peers").map_err(db_err)?;
            let rows = st.query_map([], |r| r.get::<_, String>(0)).map_err(db_err)?;
            rows.collect::<Result<_, _>>().map_err(db_err)
        })
    }
}
