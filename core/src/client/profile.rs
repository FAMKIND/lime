//! Another person's public profile (LIME-122a).

use super::*;

/// What `profile-get { user_id }` returns about someone else: the public fields only. Someone who hides from search has only a name.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct PublicProfile {
    pub user_id: String,
    pub display_name: String,
    pub username: Option<String>,
    pub school: Option<String>,
    pub about_emoji: Option<String>,
    pub about_text: Option<String>,
    /// When the account was made (milliseconds since the Unix epoch); none for someone who hid from search (LIME-214: "On lime since").
    pub since: Option<i64>,
    /// They have a live jam (LIME-210e).
    pub has_jam: bool,
}

#[uniffi::export]
impl LimeStore {
    /// Asks the server for a person's public profile. `None` when they have no profile yet; a busy server is `RateLimited`.
    pub fn fetch_profile(&self, transport: Arc<dyn Transport>, auth_token: String, user_id: String) -> Result<Option<PublicProfile>, StoreError> {
        let (status, body) = call(&transport, Some(&auth_token), "profile-get", &json!({ "user_id": user_id }))?;
        if status == 404 {
            return Ok(None);
        }
        check(status)?;
        let profile = body.get("profile").filter(|p| p.is_object()).ok_or(StoreError::BadMessage)?;
        let text = |key: &str| profile.get(key).and_then(Value::as_str).map(str::trim).filter(|s| !s.is_empty()).map(str::to_owned);
        Ok(Some(PublicProfile {
            user_id: text("user_id").unwrap_or(user_id),
            display_name: text("display_name").unwrap_or_default(),
            username: text("username"),
            school: text("school"),
            about_emoji: text("about_emoji"),
            about_text: text("about_text"),
            since: profile.get("since").and_then(Value::as_i64).filter(|n| *n > 0),
            has_jam: profile.get("has_jam").and_then(Value::as_bool).unwrap_or(false),
        }))
    }
}
