//! Contacts follow each other's jams (LIME-210e, `docs/jam.md` 13.6): when a 1:1 chat is accepted, each phone quietly subscribes to the other person's
//! jam, if they have one (free, the ordinary `jam.subscribe`, no prompt); when a contact starts a jam later the phone notices and does the same.
//!
//! - **Unsubscribing sticks:** a jam the person unsubscribed from by hand is in `jam_follow_off` and is never followed again, also if the contact is
//!   added again. A jam the writer removed me from (`removed`), or one that is `full`, is left as it is: any row for a jam means "decided".
//! - **Paced:** one batch of at most [`BATCH`] contacts a minute, each contact looked at again after a day. The look is the profile fetch the phone
//!   already makes, which now says `has_jam`; only a contact with a jam costs a second request (the jam's page).
//! - **What the server learns:** nothing it did not: a profile fetch and a page lookup by a signed-in account for someone in their chats, and a
//!   `jam.subscribe` which is an Olm message between two people who already chat.

use super::*;
use crate::store::jam as jam_store;

/// Contacts looked at in one minute.
const BATCH: usize = 20;
/// How long before a contact is looked at again.
const RECHECK_MS: i64 = 24 * 60 * 60 * 1000;
/// The shortest time between two batches.
const MIN_GAP_MS: i64 = 60 * 1000;

impl LimeStore {
    /// One paced batch of the follow pass; called from the delivery pass, quiet and safe to call often.
    pub(super) fn follow_contacts_jams(&self, transport: &Arc<dyn Transport>, token: &str, me: &str) {
        let now = now_ms();
        let Ok(due) = self.with_conn(|conn| due_contacts(conn, now)) else { return };
        for user in due {
            // Mark first: a failure does not make the next pass retry the same contact at once.
            let _ = self.with_conn(|conn| conn.execute("INSERT OR REPLACE INTO contact_jam_checks (user_id, checked_at) VALUES (?1, ?2)", params![user, now]).map(|_| ()).map_err(db_err));
            let Ok((200, body)) = call(transport, Some(token), "profile-get", &json!({ "user_id": user })) else { continue };
            if body.pointer("/profile/has_jam").and_then(Value::as_bool) != Some(true) {
                continue;
            }
            let Ok(Some(page)) = self.fetch_jam_page(transport.clone(), token.to_owned(), user.clone()) else { continue };
            let decided = self.with_conn(|conn| {
                let off: bool = conn.query_row("SELECT EXISTS (SELECT 1 FROM jam_follow_off WHERE jam_id = ?1)", params![page.jam_id], |r| r.get(0)).map_err(db_err)?;
                Ok(off || jam_store::get(conn, &page.jam_id)?.is_some())
            });
            if decided == Ok(false) && page.writer_id != me {
                let _ = self.subscribe_to_jam(page.jam_id, user);
            }
        }
    }
}

/// Accepted 1:1 chats not looked at for a day, oldest look first, at most [`BATCH`], and none before a minute has passed since the last batch.
pub(crate) fn due_contacts(conn: &Connection, now: i64) -> Result<Vec<String>, StoreError> {
    let last: i64 = conn.query_row("SELECT COALESCE(MAX(checked_at), 0) FROM contact_jam_checks", [], |r| r.get(0)).map_err(db_err)?;
    if now - last < MIN_GAP_MS {
        return Ok(vec![]);
    }
    let mut statement = conn
        .prepare(
            "SELECT substr(c.id, 4) FROM conversations c LEFT JOIN contact_jam_checks k ON k.user_id = substr(c.id, 4)
             WHERE c.id LIKE 'dm:%' AND c.request_state = 'accepted' AND COALESCE(k.checked_at, 0) < ?1
             ORDER BY COALESCE(k.checked_at, 0) LIMIT ?2",
        )
        .map_err(db_err)?;
    let rows = statement.query_map(params![now - RECHECK_MS, BATCH as i64], |r| r.get::<_, String>(0)).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
    Ok(rows)
}
