//! Profile photos on the client (LIME-98b, `docs/api-v2.md` section 6).
//!
//! My photo is kept on this phone and mirrored to the server in the form I chose: **everyone** (a plain JPEG
//! any signed-in user can fetch through `avatar`) or **contacts only** (AES-256-GCM ciphertext in the `blobs`
//! bucket whose id and key come from my profile key, which only my accepted contacts hold). Other people's
//! photos are fetched, checked at most hourly, and cached in the encrypted store. The network bytes (signed
//! URLs from Storage) go through the platform's [`Transport`], so the core never opens a socket itself.

use super::*;
use crate::store::photos::{self, Mine, MIN_GAP_MS, RECHECK_MS};

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct MyPhoto {
    pub jpeg: Option<Vec<u8>>,
    /// `everyone` or `contacts`.
    pub visibility: String,
}

/// A raw (non-JSON) request: a signed Storage URL, which carries its own token.
fn raw(transport: &Arc<dyn Transport>, method: &str, path: &str, content_type: Option<&str>, body: Vec<u8>) -> Result<(u16, Vec<u8>), StoreError> {
    // Uploads ask Storage's CDN to cache for a minute at most, so a deleted photo does not linger in a cache.
    let headers = content_type
        .map(|t| {
            vec![
                HeaderPair { name: "content-type".into(), value: t.into() },
                HeaderPair { name: "cache-control".into(), value: "max-age=60".into() },
            ]
        })
        .unwrap_or_default();
    let response = transport.request(method.into(), path.into(), headers, body).map_err(|_: TransportError| StoreError::Network)?;
    Ok((response.status, response.body))
}

fn version_of(body: &Value) -> i64 {
    body.get("version").and_then(Value::as_i64).unwrap_or(0)
}

#[uniffi::export]
impl LimeStore {
    /// My photo as stored on this phone, and who may see it.
    pub fn my_photo(&self) -> Result<MyPhoto, StoreError> {
        let mine = self.with_conn(photos::mine)?;
        Ok(MyPhoto { jpeg: mine.jpeg, visibility: mine.visibility })
    }

    /// A cached photo of another person, if they have one we can see.
    pub fn peer_photo(&self, user_id: String) -> Result<Option<Vec<u8>>, StoreError> {
        self.with_conn(|conn| Ok(photos::cached(conn, &user_id)?.map(|c| c.bytes).filter(|b| !b.is_empty())))
    }

    /// Sets my photo (a JPEG already cropped, resized and stripped of its metadata) and puts it on the server in
    /// the form chosen by [`LimeStore::set_photo_visibility`].
    pub fn set_my_photo(&self, transport: Arc<dyn Transport>, auth_token: String, jpeg: Vec<u8>) -> Result<(), StoreError> {
        if jpeg.is_empty() || jpeg.len() > 1024 * 1024 {
            return Err(StoreError::Rejected);
        }
        self.with_conn(|conn| {
            let mut mine = photos::mine(conn)?;
            mine.jpeg = Some(jpeg);
            photos::save_mine(conn, &mine, now_ms())
        })?;
        self.sync_my_photo(&transport, &auth_token)?;
        self.notify_contacts_of_photo_change()
    }

    /// Removes my photo everywhere (the server's copy, whichever form it is in, and this phone's).
    pub fn remove_my_photo(&self, transport: Arc<dyn Transport>, auth_token: String) -> Result<(), StoreError> {
        self.with_conn(|conn| {
            let mut mine = photos::mine(conn)?;
            mine.jpeg = None;
            photos::save_mine(conn, &mine, now_ms())
        })?;
        self.sync_my_photo(&transport, &auth_token)?;
        self.notify_contacts_of_photo_change()
    }

    /// Who may see my photo: `everyone` (a public copy) or `contacts` (an encrypted copy; the public one is
    /// deleted from the server).
    pub fn set_photo_visibility(&self, transport: Arc<dyn Transport>, auth_token: String, visibility: String) -> Result<(), StoreError> {
        if visibility != "everyone" && visibility != "contacts" {
            return Err(StoreError::Rejected);
        }
        self.with_conn(|conn| {
            let mut mine = photos::mine(conn)?;
            mine.visibility = visibility;
            photos::save_mine(conn, &mine, now_ms())
        })?;
        self.sync_my_photo(&transport, &auth_token)?;
        self.notify_contacts_of_photo_change()
    }

    /// Fetches the photos of the people in my conversations (each at most hourly unless `force`), and returns
    /// the ids whose photo changed (appeared, changed or went away).
    pub fn refresh_photos(&self, transport: Arc<dyn Transport>, auth_token: String, force: bool) -> Result<Vec<String>, StoreError> {
        self.refresh_photos_inner(&transport, &auth_token, None, if force { 0 } else { RECHECK_MS })
    }

    /// Checks these people's photos now (pull-to-refresh, opening a chat), but never one more than once a minute.
    pub fn refresh_photos_of(&self, transport: Arc<dyn Transport>, auth_token: String, user_ids: Vec<String>) -> Result<Vec<String>, StoreError> {
        self.refresh_photos_inner(&transport, &auth_token, Some(user_ids), MIN_GAP_MS)
    }
}

impl LimeStore {
    fn refresh_photos_inner(&self, transport: &Arc<dyn Transport>, auth_token: &str, only: Option<Vec<String>>, gap_ms: i64) -> Result<Vec<String>, StoreError> {
        let transport = transport.clone();
        let auth_token = auth_token.to_owned();
        let me = self.with_conn(|conn| Ok(crate::store::account::load_account(conn, &self.pickle_key)?.and_then(|s| s.user_id)))?.ok_or(StoreError::NotRegistered)?;
        let mut people = self.with_conn(|conn| photos::people_to_check(conn, &me))?;
        if let Some(only) = only {
            people.retain(|p| only.contains(p));
        }
        let mut changed = Vec::new();
        for person in people {
            let recent = self.with_conn(|conn| photos::cached(conn, &person))?.is_some_and(|c| now_ms() - c.checked_at < gap_ms);
            if recent {
                continue;
            }
            match self.refresh_one(&transport, &auth_token, &person) {
                Ok(true) => changed.push(person),
                Ok(false) => {}
                // Offline or rate-limited: leave it, the next refresh tries again.
                Err(StoreError::Network | StoreError::RateLimited | StoreError::Unavailable) => break,
                Err(_) => continue,
            }
        }
        Ok(changed)
    }
}

impl LimeStore {
    /// Queues "my photo changed" for every accepted contact: their phones refresh it on the next sync.
    fn notify_contacts_of_photo_change(&self) -> Result<(), StoreError> {
        self.with_conn(|conn| {
            let peers = crate::store::delivery::accepted_peers(conn)?;
            photos::queue_notices(conn, &peers, now_ms())
        })
    }

    /// Makes the server match my local photo and visibility.
    pub(super) fn sync_my_photo(&self, transport: &Arc<dyn Transport>, token: &str) -> Result<(), StoreError> {
        let mine = self.with_conn(photos::mine)?;
        let mut uploaded_key = mine.uploaded_key.clone();
        match (&mine.jpeg, mine.visibility.as_str()) {
            (Some(jpeg), "everyone") => {
                let (status, body) = call(transport, Some(token), "avatar", &json!({ "action": "put", "size": jpeg.len() }))?;
                check(status)?;
                let url = body.get("url").and_then(Value::as_str).ok_or(StoreError::BadMessage)?;
                let (put, _) = raw(transport, "PUT", url, Some("image/jpeg"), jpeg.clone())?;
                check(put)?;
                let (status, _) = call(transport, Some(token), "avatar", &json!({ "action": "commit" }))?;
                check(status)?;
                self.delete_encrypted_copy(transport, token, uploaded_key.take());
            }
            (Some(jpeg), _) => {
                let key = self.with_conn(|conn| photos::current_key(conn, now_ms()))?;
                let id = photos::blob_id(&key);
                let sealed = photos::seal(&key, jpeg);
                let (status, body) = call(transport, Some(token), "blob", &json!({ "action": "put", "blob_id": id, "size": sealed.len() }))?;
                check(status)?;
                let url = body.get("url").and_then(Value::as_str).ok_or(StoreError::BadMessage)?;
                let (put, _) = raw(transport, "PUT", url, Some("application/octet-stream"), sealed)?;
                check(put)?;
                let (status, _) = call(transport, Some(token), "blob", &json!({ "action": "commit", "blob_id": id }))?;
                check(status)?;
                // Only now does the public copy go (so there is never a moment with neither).
                let (status, _) = call(transport, Some(token), "avatar", &json!({ "action": "visibility", "visibility": "contacts" }))?;
                check(status)?;
                let new_key = vodozemac::base64_encode(&key);
                if uploaded_key.as_deref().is_some_and(|old| old != new_key) {
                    self.delete_encrypted_copy(transport, token, uploaded_key.take());
                }
                uploaded_key = Some(new_key);
            }
            (None, visibility) => {
                let (status, _) = call(transport, Some(token), "avatar", &json!({ "action": "remove" }))?;
                check(status)?;
                let (status, _) = call(transport, Some(token), "avatar", &json!({ "action": "visibility", "visibility": visibility }))?;
                check(status)?;
                self.delete_encrypted_copy(transport, token, uploaded_key.take());
            }
        }
        self.with_conn(|conn| photos::save_mine(conn, &Mine { uploaded_key, ..mine }, now_ms()))
    }

    /// Removes the contacts-only blob made with `key` (best effort: an orphan only costs storage).
    fn delete_encrypted_copy(&self, transport: &Arc<dyn Transport>, token: &str, key_b64: Option<String>) {
        let Some(key) = key_b64.and_then(|k| vodozemac::base64_decode(k).ok()) else { return };
        let _ = call(transport, Some(token), "blob", &json!({ "action": "delete", "blob_id": photos::blob_id(&key) }));
    }

    /// After a block rotated my photo key, the contacts-only copy is under a key the remaining contacts will be
    /// given: upload it again under the new one. Best effort.
    pub(super) fn refresh_my_photo_if_stale(&self, transport: &Arc<dyn Transport>, token: &str) {
        let stale = self.with_conn(|conn| {
            let mine = photos::mine(conn)?;
            if mine.jpeg.is_none() || mine.visibility != "contacts" {
                return Ok(false);
            }
            let key = vodozemac::base64_encode(photos::current_key(conn, now_ms())?);
            Ok(mine.uploaded_key.as_deref() != Some(key.as_str()))
        });
        if stale == Ok(true) {
            let _ = self.sync_my_photo(transport, token);
        }
    }

    /// One person's photo: public first, then the contacts-only copy if they gave us their photo key.
    /// `true` when what we hold changed.
    fn refresh_one(&self, transport: &Arc<dyn Transport>, token: &str, user: &str) -> Result<bool, StoreError> {
        let now = now_ms();
        let held = self.with_conn(|conn| photos::cached(conn, user))?;
        let had = held.as_ref().is_some_and(|c| !c.bytes.is_empty());

        let (status, body) = call(transport, Some(token), "avatar", &json!({ "action": "get", "user_id": user }))?;
        if status == 200 {
            let version = version_of(&body);
            let url = body.get("url").and_then(Value::as_str).ok_or(StoreError::BadMessage)?;
            if held.as_ref().is_some_and(|c| c.source == "public" && c.version == version && !c.bytes.is_empty()) {
                self.with_conn(|conn| photos::save_cached(conn, user, &held.as_ref().unwrap().bytes, "public", version, now))?;
                return Ok(false);
            }
            let (got, bytes) = raw(transport, "GET", url, None, Vec::new())?;
            check(got)?;
            self.with_conn(|conn| photos::save_cached(conn, user, &bytes, "public", version, now))?;
            return Ok(true);
        }
        if status != 404 {
            check(status)?;
        }

        // No public copy: the contacts-only one, if I hold their photo key.
        if let Some(key) = self.with_conn(|conn| photos::contact_key(conn, user))? {
            let id = photos::blob_id(&key);
            let (status, body) = call(transport, Some(token), "blob", &json!({ "action": "get", "blob_id": id }))?;
            if status == 200 {
                let version = version_of(&body);
                let url = body.get("url").and_then(Value::as_str).ok_or(StoreError::BadMessage)?;
                if held.as_ref().is_some_and(|c| c.source == "encrypted" && c.version == version && !c.bytes.is_empty()) {
                    self.with_conn(|conn| photos::save_cached(conn, user, &held.as_ref().unwrap().bytes, "encrypted", version, now))?;
                    return Ok(false);
                }
                let (got, bytes) = raw(transport, "GET", url, None, Vec::new())?;
                check(got)?;
                if let Some(jpeg) = photos::open(&key, &bytes) {
                    self.with_conn(|conn| photos::save_cached(conn, user, &jpeg, "encrypted", version, now))?;
                    return Ok(true);
                }
            } else if status != 404 {
                check(status)?;
            }
        }

        // Nothing we can see: initials.
        self.with_conn(|conn| photos::save_cached(conn, user, &[], "none", 0, now))?;
        Ok(had)
    }
}
