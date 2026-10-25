//! My links and background image, and other people's (LIME-214, LIME-217): the photo's scheme again, per slot (`store/extras.rs`).
//! Everyone: a public object through `avatar` with a `slot`; contacts only: an encrypted blob under my profile key. Nothing here is sent in
//! the clear unless the person chose Everyone.

use std::sync::atomic::{AtomicBool, Ordering};

use super::*;
use crate::store::extras::{self as extras, Mine};
use crate::store::photos;

/// Whether this phone may download other people's background videos now (LIME-226b): the app turns it off on cellular and in Low Data Mode. When it is
/// off a contact's video is only noted (`pending`) and fetched when the person asks.
static FETCH_VIDEOS: AtomicBool = AtomicBool::new(true);

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct MyExtra {
    pub data: Option<Vec<u8>>,
    /// `everyone` or `contacts`.
    pub visibility: String,
}

fn content_type(slot: &str) -> &'static str {
    match slot {
        extras::LINKS => "application/json",
        extras::BACKGROUND_VIDEO => "video/mp4",
        _ => "image/jpeg",
    }
}

#[uniffi::export]
impl LimeStore {
    /// What I hold for a slot (`links`: a JSON list; `background`: a JPEG) and who may see it. Contacts only until I choose otherwise.
    pub fn my_extra(&self, slot: String) -> Result<MyExtra, StoreError> {
        if !extras::is_slot(&slot) {
            return Err(StoreError::Rejected);
        }
        let mine = self.with_conn(|conn| extras::mine(conn, &slot))?;
        Ok(MyExtra { data: mine.data, visibility: mine.visibility })
    }

    /// Allows or stops downloading other people's background videos (the app calls it as the network changes).
    pub fn set_background_video_fetching(&self, allowed: bool) {
        FETCH_VIDEOS.store(allowed, Ordering::Relaxed);
    }

    /// True when someone has a background video this phone knows of but has not downloaded (fetching was off): the profile can offer to play it.
    pub fn peer_extra_pending(&self, user_id: String, slot: String) -> Result<bool, StoreError> {
        if !extras::is_slot(&slot) {
            return Err(StoreError::Rejected);
        }
        self.with_conn(|conn| Ok(extras::cached(conn, &user_id, &slot)?.is_some_and(|c| c.source == "pending")))
    }

    /// Downloads a pending video now (the person tapped it), whatever the network. `true` when it was fetched.
    pub fn fetch_peer_extra(&self, transport: Arc<dyn Transport>, auth_token: String, user_id: String, slot: String) -> Result<bool, StoreError> {
        if !extras::is_slot(&slot) {
            return Err(StoreError::Rejected);
        }
        self.refresh_extra(&transport, &auth_token, &user_id, &slot, true)
    }

    /// Another person's links or background, if they have one we can see.
    pub fn peer_extra(&self, user_id: String, slot: String) -> Result<Option<Vec<u8>>, StoreError> {
        if !extras::is_slot(&slot) {
            return Err(StoreError::Rejected);
        }
        self.with_conn(|conn| Ok(extras::cached(conn, &user_id, &slot)?.map(|c| c.bytes).filter(|b| !b.is_empty())))
    }

    /// Sets a slot and puts it on the server in the form chosen by [`LimeStore::set_extra_visibility`]; my contacts are told it changed.
    pub fn set_my_extra(&self, transport: Arc<dyn Transport>, auth_token: String, slot: String, data: Vec<u8>) -> Result<(), StoreError> {
        if !extras::is_slot(&slot) || data.is_empty() || data.len() > extras::max_bytes(&slot) {
            return Err(StoreError::Rejected);
        }
        // A video background always has its still (the poster), so the video cannot be set without one.
        if slot == extras::BACKGROUND_VIDEO && self.with_conn(|conn| extras::mine(conn, extras::BACKGROUND))?.data.is_none() {
            return Err(StoreError::Rejected);
        }
        self.change_my_extra(&transport, &auth_token, &slot, |mine| mine.data = Some(data))
    }

    /// Removes a slot everywhere.
    pub fn remove_my_extra(&self, transport: Arc<dyn Transport>, auth_token: String, slot: String) -> Result<(), StoreError> {
        if !extras::is_slot(&slot) {
            return Err(StoreError::Rejected);
        }
        // Removing the still removes the video with it; removing only the video keeps the still.
        if slot == extras::BACKGROUND {
            self.change_my_extra(&transport, &auth_token, extras::BACKGROUND_VIDEO, |mine| mine.data = None)?;
        }
        self.change_my_extra(&transport, &auth_token, &slot, |mine| mine.data = None)
    }

    /// Who may see a slot: `everyone` (a public copy) or `contacts` (an encrypted copy; the public one is deleted from the server).
    pub fn set_extra_visibility(&self, transport: Arc<dyn Transport>, auth_token: String, slot: String, visibility: String) -> Result<(), StoreError> {
        if !extras::is_slot(&slot) || (visibility != "everyone" && visibility != "contacts") {
            return Err(StoreError::Rejected);
        }
        self.change_my_extra(&transport, &auth_token, &slot, |mine| mine.visibility = visibility)
    }
}

impl LimeStore {
    fn change_my_extra(&self, transport: &Arc<dyn Transport>, token: &str, slot: &str, change: impl FnOnce(&mut Mine)) -> Result<(), StoreError> {
        self.with_conn(|conn| {
            let mut mine = extras::mine(conn, slot)?;
            change(&mut mine);
            extras::save_mine(conn, slot, &mine, now_ms())
        })?;
        self.sync_my_extra(transport, token, slot)?;
        self.with_conn(|conn| {
            let peers = crate::store::delivery::accepted_peers(conn)?;
            photos::queue_notices(conn, &peers, now_ms())
        })
    }

    /// Makes the server match what I hold for a slot.
    pub(super) fn sync_my_extra(&self, transport: &Arc<dyn Transport>, token: &str, slot: &str) -> Result<(), StoreError> {
        let mine = self.with_conn(|conn| extras::mine(conn, slot))?;
        let mut uploaded_key = mine.uploaded_key.clone();
        match (&mine.data, mine.visibility.as_str()) {
            (Some(data), "everyone") => {
                let (status, body) = call(transport, Some(token), "avatar", &json!({ "action": "put", "slot": slot, "size": data.len() }))?;
                check(status)?;
                let url = body.get("url").and_then(Value::as_str).ok_or(StoreError::BadMessage)?;
                let (put, _) = super::photos::raw(transport, "PUT", url, Some(content_type(slot)), data.clone())?;
                check(put)?;
                let (status, _) = call(transport, Some(token), "avatar", &json!({ "action": "commit", "slot": slot }))?;
                check(status)?;
                self.delete_encrypted_extra(transport, token, slot, uploaded_key.take());
            }
            (Some(data), _) => {
                let key = self.with_conn(|conn| photos::current_key(conn, now_ms()))?;
                let id = extras::blob_id(slot, &key);
                let sealed = extras::seal(slot, &key, data);
                let (status, body) = call(transport, Some(token), "blob", &json!({ "action": "put", "blob_id": id, "size": sealed.len() }))?;
                check(status)?;
                let url = body.get("url").and_then(Value::as_str).ok_or(StoreError::BadMessage)?;
                let (put, _) = super::photos::raw(transport, "PUT", url, Some("application/octet-stream"), sealed)?;
                check(put)?;
                let (status, _) = call(transport, Some(token), "blob", &json!({ "action": "commit", "blob_id": id }))?;
                check(status)?;
                // Only now does the public copy go (so there is never a moment with neither).
                let (status, _) = call(transport, Some(token), "avatar", &json!({ "action": "visibility", "slot": slot, "visibility": "contacts" }))?;
                check(status)?;
                let new_key = vodozemac::base64_encode(&key);
                if uploaded_key.as_deref().is_some_and(|old| old != new_key) {
                    self.delete_encrypted_extra(transport, token, slot, uploaded_key.take());
                }
                uploaded_key = Some(new_key);
            }
            (None, visibility) => {
                let (status, _) = call(transport, Some(token), "avatar", &json!({ "action": "remove", "slot": slot }))?;
                check(status)?;
                let (status, _) = call(transport, Some(token), "avatar", &json!({ "action": "visibility", "slot": slot, "visibility": visibility }))?;
                check(status)?;
                self.delete_encrypted_extra(transport, token, slot, uploaded_key.take());
            }
        }
        self.with_conn(|conn| extras::save_mine(conn, slot, &Mine { uploaded_key, ..mine }, now_ms()))
    }

    fn delete_encrypted_extra(&self, transport: &Arc<dyn Transport>, token: &str, slot: &str, key_b64: Option<String>) {
        let Some(key) = key_b64.and_then(|k| vodozemac::base64_decode(k).ok()) else { return };
        let _ = call(transport, Some(token), "blob", &json!({ "action": "delete", "blob_id": extras::blob_id(slot, &key) }));
    }

    /// After a block rotated my profile key, the contacts-only copies are under the old one: upload them again under the new. Best effort.
    pub(super) fn refresh_my_extras_if_stale(&self, transport: &Arc<dyn Transport>, token: &str) {
        for slot in [extras::LINKS, extras::BACKGROUND, extras::BACKGROUND_VIDEO] {
            let stale = self.with_conn(|conn| {
                let mine = extras::mine(conn, slot)?;
                if mine.data.is_none() || mine.visibility != "contacts" {
                    return Ok(false);
                }
                let key = vodozemac::base64_encode(photos::current_key(conn, now_ms())?);
                Ok(mine.uploaded_key.as_deref() != Some(key.as_str()))
            });
            if stale == Ok(true) {
                let _ = self.sync_my_extra(transport, token, slot);
            }
        }
    }

    #[cfg(test)]
    pub(crate) fn refresh_my_extras_if_stale_for_tests(&self, transport: &Arc<dyn Transport>, token: &str) {
        self.refresh_my_extras_if_stale(transport, token);
    }

    /// One person's links and background: public first, then the contacts-only copy if I hold their profile key. `true` when anything changed.
    pub(super) fn refresh_extras_of_one(&self, transport: &Arc<dyn Transport>, token: &str, user: &str) -> Result<bool, StoreError> {
        let mut changed = false;
        for slot in [extras::LINKS, extras::BACKGROUND, extras::BACKGROUND_VIDEO] {
            changed |= self.refresh_extra(transport, token, user, slot, false)?;
        }
        Ok(changed)
    }

    fn refresh_extra(&self, transport: &Arc<dyn Transport>, token: &str, user: &str, slot: &str, force: bool) -> Result<bool, StoreError> {
        let now = now_ms();
        // A video is only noted, not downloaded, while fetching videos is off (cellular, Low Data Mode) unless the person asked for it.
        let hold = slot == extras::BACKGROUND_VIDEO && !force && !FETCH_VIDEOS.load(Ordering::Relaxed);
        let held = self.with_conn(|conn| extras::cached(conn, user, slot))?;
        let had = held.as_ref().is_some_and(|c| !c.bytes.is_empty());

        let (status, body) = call(transport, Some(token), "avatar", &json!({ "action": "get", "user_id": user, "slot": slot }))?;
        if status == 200 {
            let version = body.get("version").and_then(Value::as_i64).unwrap_or(0);
            let url = body.get("url").and_then(Value::as_str).ok_or(StoreError::BadMessage)?;
            if let Some(c) = held.as_ref().filter(|c| c.source == "public" && c.version == version && !c.bytes.is_empty()) {
                self.with_conn(|conn| extras::save_cached(conn, user, slot, &c.bytes, "public", version, now))?;
                return Ok(false);
            }
            if hold {
                self.with_conn(|conn| extras::save_cached(conn, user, slot, &[], "pending", version, now))?;
                return Ok(false);
            }
            let (got, bytes) = super::photos::raw(transport, "GET", url, None, Vec::new())?;
            check(got)?;
            if bytes.len() > extras::max_bytes(slot) {
                return Ok(false);
            }
            self.with_conn(|conn| extras::save_cached(conn, user, slot, &bytes, "public", version, now))?;
            return Ok(true);
        }
        if status != 404 {
            check(status)?;
        }

        if let Some(key) = self.with_conn(|conn| photos::contact_key(conn, user))? {
            let id = extras::blob_id(slot, &key);
            let (status, body) = call(transport, Some(token), "blob", &json!({ "action": "get", "blob_id": id }))?;
            if status == 200 {
                let version = body.get("version").and_then(Value::as_i64).unwrap_or(0);
                let url = body.get("url").and_then(Value::as_str).ok_or(StoreError::BadMessage)?;
                if let Some(c) = held.as_ref().filter(|c| c.source == "encrypted" && c.version == version && !c.bytes.is_empty()) {
                    self.with_conn(|conn| extras::save_cached(conn, user, slot, &c.bytes, "encrypted", version, now))?;
                    return Ok(false);
                }
                if hold {
                    self.with_conn(|conn| extras::save_cached(conn, user, slot, &[], "pending", version, now))?;
                    return Ok(false);
                }
                let (got, bytes) = super::photos::raw(transport, "GET", url, None, Vec::new())?;
                check(got)?;
                if let Some(data) = extras::open(slot, &key, &bytes).filter(|d| d.len() <= extras::max_bytes(slot)) {
                    self.with_conn(|conn| extras::save_cached(conn, user, slot, &data, "encrypted", version, now))?;
                    return Ok(true);
                }
            } else if status != 404 {
                check(status)?;
            }
        }

        self.with_conn(|conn| extras::save_cached(conn, user, slot, &[], "none", 0, now))?;
        Ok(had)
    }
}
