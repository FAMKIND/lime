//! Keeping two people able to read each other (LIME-231b).
//!
//! Two things can leave a pair of contacts deaf to each other: their Olm session stopped decrypting (every sealed message after some point sits in
//! the inbound queue as `no_session`, for ever, and nothing re-established it), or one of them never received the other's profile key (so the
//! contacts-only photo, background and links cannot be opened). Both heal themselves here:
//!
//! - **A fresh session.** When sealed items we cannot read keep failing, each accepted contact we have not heard from since they began gets a new
//!   session started with a key share (which carries the profile key too). The new session is preferred for sending from then on and the contact's
//!   phone, reading our pre-key message, prefers it as well. At most once every 6 hours per person.
//! - **Asking.** A contact whose profile key we do not hold is sent a small encrypted `profile_key.request` (at most once a day per person). Their
//!   phone answers with a fresh key share, but only if we are an accepted contact of theirs and not blocked.
//!
//! What each party learns: the server sees two more ordinary sealed messages between two people who already chat, nothing about their kind.

use super::*;

const REPAIR_EVERY_MS: i64 = 6 * 3600 * 1000;
const ASK_EVERY_MS: i64 = 24 * 3600 * 1000;
/// A stuck item must have been tried this often, and be this recent, to count as a broken session (older ones are history).
const STUCK_ATTEMPTS: i64 = 3;
const STUCK_RECENT_MS: i64 = 3 * 24 * 3600 * 1000;
/// Sealed items that never became readable are dropped after this long (they never will).
const STUCK_KEEP_MS: i64 = 7 * 24 * 3600 * 1000;

impl LimeStore {
    /// Runs with the protocol lock held, after the queued shares went out. Best effort: nothing waits on it.
    pub(super) fn heal_contacts(&self, transport: &Arc<dyn Transport>, token: &str, state: &mut AccountState, me: &str) {
        let now = now_ms();
        let _ = self.with_conn(|conn| {
            conn.execute("DELETE FROM pending_inbound WHERE reason = ?1 AND first_seen < ?2", params![pending::NO_SESSION, now - STUCK_KEEP_MS]).map_err(db_err)?;
            Ok(())
        });
        let Ok(peers) = self.with_conn(delivery::accepted_peers) else { return };

        // 1. A broken session: sealed items stuck since `since`; everyone we have not heard from since then gets a fresh session.
        let since: Option<i64> = self
            .with_conn(|conn| {
                conn.query_row(
                    "SELECT MIN(first_seen) FROM pending_inbound WHERE reason = ?1 AND attempts >= ?2 AND first_seen > ?3",
                    params![pending::NO_SESSION, STUCK_ATTEMPTS, now - STUCK_RECENT_MS],
                    |r| r.get::<_, Option<i64>>(0),
                )
                .map_err(db_err)
            })
            .ok()
            .flatten();
        if let Some(since) = since {
            for peer in &peers {
                let heard: Option<i64> = self
                    .with_conn(|conn| {
                        conn.query_row("SELECT MAX(last_received) FROM olm_sessions WHERE peer_user_id = ?1", params![peer], |r| r.get::<_, Option<i64>>(0)).map_err(db_err)
                    })
                    .ok()
                    .flatten();
                let last_repair: i64 = self
                    .with_conn(|conn| {
                        Ok(conn.query_row("SELECT repaired_at FROM session_repairs WHERE peer_user_id = ?1", params![peer], |r| r.get::<_, i64>(0)).optional().map_err(db_err)?.unwrap_or(0))
                    })
                    .unwrap_or(0);
                // No session at all needs no repair (the next send makes one); heard from them since the trouble began: theirs works.
                if heard.is_none_or(|at| at >= since) || now - last_repair < REPAIR_EVERY_MS {
                    continue;
                }
                self.fresh_session_for.lock().unwrap_or_else(|e| e.into_inner()).insert(peer.clone());
                let sent = self.share_key_with(transport, token, state, me, peer);
                self.fresh_session_for.lock().unwrap_or_else(|e| e.into_inner()).remove(peer);
                if sent.is_ok() {
                    let _ = self.with_conn(|conn| {
                        conn.execute("INSERT OR REPLACE INTO session_repairs (peer_user_id, repaired_at) VALUES (?1, ?2)", params![peer, now]).map_err(db_err)?;
                        delivery::mark_shared(conn, peer, now)
                    });
                }
            }
        }

        // 2. Ask for a profile key we do not hold.
        for peer in &peers {
            // Only a contact whose key share DID arrive (we hold their delivery key, for over ten minutes) but carried no profile key: a fresh contact's
            // share is still on its way with both.
            let missing = self
                .with_conn(|conn| {
                    let delivery_at: Option<i64> = conn
                        .query_row("SELECT received_at FROM contact_delivery_keys WHERE user_id = ?1", params![peer], |r| r.get(0))
                        .optional()
                        .map_err(db_err)?;
                    Ok(crate::store::photos::contact_key(conn, peer)?.is_none() && delivery_at.is_some_and(|at| now - at > 10 * 60 * 1000))
                })
                .unwrap_or(false);
            let asked: i64 = self
                .with_conn(|conn| Ok(conn.query_row("SELECT asked_at FROM profile_key_requests WHERE peer_user_id = ?1", params![peer], |r| r.get::<_, i64>(0)).optional().map_err(db_err)?.unwrap_or(0)))
                .unwrap_or(0);
            if !missing || now - asked < ASK_EVERY_MS {
                continue;
            }
            if self.send_control_op(transport, token, state, me, peer, PROFILE_KEY_REQUEST, json!({})).is_ok() {
                let _ = self.with_conn(|conn| {
                    conn.execute("INSERT OR REPLACE INTO profile_key_requests (peer_user_id, asked_at) VALUES (?1, ?2)", params![peer, now]).map_err(db_err)?;
                    Ok(())
                });
            }
        }
    }
}
