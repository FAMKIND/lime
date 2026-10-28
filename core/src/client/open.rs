//! Open posts on the client (LIME-210b, `docs/jam.md` section 13): a post whose audience is **everyone** (or that has a `[[freewall]]`) is also
//! published as a **signed open row** that anyone on lime can read, lime's server included.
//!
//! - **The row** is the exact JSON text of the post (id, author, jam, kind, words, files, topics, series, `preview_of`, `has_rest`, version) signed by
//!   the writer's **device** (`"lime-open-post-v1\n" + text`), with the device certificate (the account's master key signed the device's keys). The
//!   server checks the same before it keeps a row; **a phone checks it again on every read** ([`verify_row`]): the signature, the certificate, that the
//!   row names the author it came from, and (when this phone knows the person) that the certificate's master key is the pinned one.
//! - **The encrypted post is untouched** and stays the subscribers' copy (same post id). The open row is its public sibling: the whole post for
//!   *Everyone*, or only what stands above the marker for a *Preview* (`preview_of` = the post's id, `has_rest` = something stands below).
//! - **Delivery** is a persistent queue (`open_outbox`, the latest job per post): the files go up as the `open-file` class (plain bytes, a public
//!   URL), then the row. A server that does not accept open posts yet (`open_posts_enabled` off) holds the job, which waits with a back-off.
//! - **Changing the audience** later: to *everyone* publishes an open copy of the same post; back to *subscribers* deletes it (the encrypted post
//!   stays). Deleting the post deletes both.

use super::photos::raw;
use super::*;
use crate::store::jam as jam_store;
use crate::store::jam::OpenJob;

use super::jam::SeriesInfo;

/// What the writer's device signs, in front of the row's text.
pub(crate) const OPEN_LABEL: &str = "lime-open-post-v1\n";

/// How many open deliveries one pass makes.
const OPEN_PER_PASS: usize = 5;

/// A file of an open post: its id, its plain public URL (a path on the server) and its type.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct OpenFileRef {
    pub id: String,
    pub url: String,
    pub mime: String,
}

/// An open post, **verified** (its signature, certificate and author checked on this phone).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct OpenPostInfo {
    pub post_id: String,
    pub author_id: String,
    pub jam_id: String,
    pub kind: String,
    pub title: String,
    pub subtitle: String,
    pub markdown: String,
    pub plain: String,
    pub topics: Vec<String>,
    pub files: Vec<OpenFileRef>,
    pub series: Option<SeriesInfo>,
    /// Set on a Preview: the encrypted post this is the public top of.
    pub preview_of: Option<String>,
    /// A Preview with something below the marker: the page ends with "Subscribe to read the rest".
    pub has_rest: bool,
    pub version: u32,
    pub created: i64,
    /// This phone knows the writer's master key and the certificate's matches it. False: no key to compare (the server vouched for the account).
    pub pinned: bool,
}

/// One entry of Discover's index: metadata only (the whole signed row is fetched by id).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct OpenFeedItem {
    pub post_id: String,
    pub author_id: String,
    pub jam_id: String,
    pub kind: String,
    pub title: String,
    pub subtitle: String,
    pub excerpt: String,
    pub topics: Vec<String>,
    pub file_ids: Vec<String>,
    pub series: Option<SeriesInfo>,
    pub preview_of: Option<String>,
    pub has_rest: bool,
    pub version: u32,
    pub created: i64,
    pub seq: i64,
}

/// A page of Discover: what to show or replace, what to forget, and where to continue.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct OpenFeedPage {
    pub items: Vec<OpenFeedItem>,
    /// Posts deleted or taken down since: forget them.
    pub gone: Vec<String>,
    pub cursor: i64,
    /// The server takes open posts (its `open_posts_enabled` flag): the app shows the Everyone choice and Discover only then.
    pub enabled: bool,
}

/// One fetched open post that matches a search (LIME-210h).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct OpenSearchHit {
    pub post_id: String,
    pub author_id: String,
    pub kind: String,
    pub title: String,
    pub created: i64,
    /// A few words around the match; each matched word sits between `\u{E000}` and `\u{E001}`.
    pub snippet: String,
}

/// How the open deliveries stand.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct OpenSendProgress {
    pub pending: u32,
    /// Waiting for a reason (the server does not take open posts yet, or a limit).
    pub held: u32,
}

/// A row that checked out: the signed text parsed, the author named in it.
pub(crate) struct VerifiedRow {
    pub payload: Value,
    pub pinned: bool,
}

/// Checks a signed open row. `row` is the server's answer (`payload` text, `signature`, `cert`); `expect_post` is the id asked for; `pinned_master` is the
/// master key this phone remembers for the author (if any). The certificate must be signed by its master key, the row by the certificate's device, the
/// text must name this post and this author, and a remembered master key must be the certificate's. `None` for anything else.
pub(crate) fn verify_row(row: &Value, expect_post: &str, pinned_master: Option<&str>) -> Option<VerifiedRow> {
    let text = row.get("payload").and_then(Value::as_str)?;
    let signature = row.get("signature").and_then(Value::as_str)?;
    let cert = SenderCert::from_json(row.get("cert")?)?;
    if !cert.verify() || !crate::protocol::verify_signature(&cert.signing_key, signature, format!("{OPEN_LABEL}{text}").as_bytes()) {
        return None;
    }
    let payload: Value = serde_json::from_str(text).ok()?;
    let named = |k: &str| payload.get(k).and_then(Value::as_str);
    let author = row.get("author_id").and_then(Value::as_str)?;
    if named("post_id")? != expect_post || named("author_id")? != author || named("author_kind")? != "person" || row.get("post_id").and_then(Value::as_str)? != expect_post {
        return None;
    }
    if payload.get("version").and_then(Value::as_i64)? != row.get("version").and_then(Value::as_i64)? {
        return None;
    }
    if let Some(master) = pinned_master {
        if master != cert.master_key {
            return None;
        }
    }
    Some(VerifiedRow { payload, pinned: pinned_master.is_some() })
}

fn series_of(value: &Value) -> Option<SeriesInfo> {
    value.get("series").filter(|v| !v.is_null()).and_then(SeriesInfo::from_value)
}

fn topics_of(value: &Value) -> Vec<String> {
    value.get("topics").and_then(Value::as_array).map(|a| a.iter().filter_map(Value::as_str).take(8).map(str::to_owned).collect()).unwrap_or_default()
}

impl LimeStore {
    /// Signs and queues the open copy of one of my posts, or removes it, from the post as it is stored now: *everyone* publishes the whole post, a
    /// `[[freewall]]` publishes the Preview, anything else has no open copy (and one that was there is deleted). Runs inside the caller's savepoint.
    pub(super) fn queue_open_copy(&self, conn: &Connection, state: &AccountState, post_id: &str) -> Result<(), StoreError> {
        let Some(me) = state.user_id.clone() else { return Ok(()) };
        let Some(row) = jam_store::post(conn, post_id)?.filter(|p| !p.deleted && p.author == me) else { return Ok(()) };
        let split = crate::format::preview_split(&row.markdown);
        if split.is_none() && row.audience != jam_store::AUDIENCE_EVERYONE {
            return self.queue_open_delete(conn, post_id);
        }
        let attachments: Vec<Value> = serde_json::from_str(&row.attachments).unwrap_or_default();
        // A Preview of an article keeps only the pictures above the marker; other kinds keep all their files (a recording is its file).
        let kept: Vec<usize> = match (&split, row.kind.as_str()) {
            (Some(s), "article") => s.kept_files.iter().map(|n| *n as usize).collect(),
            _ => (0..attachments.len()).collect(),
        };
        let files: Vec<(String, String, u64)> = kept
            .iter()
            .filter_map(|i| attachments.get(*i))
            .filter_map(|a| Some((a.get("id")?.as_str()?.to_owned(), a.get("mime")?.as_str()?.to_owned(), a.get("size").and_then(Value::as_u64).unwrap_or(0))))
            .collect();
        let markdown = split.as_ref().map(|s| s.markdown.clone()).unwrap_or_else(|| row.markdown.clone());
        let has_rest = split.as_ref().is_some_and(|s| s.has_rest);
        // The chips picked for the post, else the jam's own topics.
        let picked = row.topics.as_deref().and_then(|s| serde_json::from_str::<Vec<String>>(s).ok()).unwrap_or_default();
        let topics = if picked.is_empty() { jam_store::get(conn, &row.jam_id)?.map(|j| j.topics).unwrap_or_default() } else { picked };
        let (open_version, open_live): (i64, i64) = conn
            .query_row("SELECT open_version, open_live FROM jam_posts WHERE post_id = ?1", params![post_id], |r| Ok((r.get(0)?, r.get(1)?)))
            .map_err(db_err)?;
        let pending = pending_job(conn, post_id)?;
        // The version the server will hold: a job not yet delivered is replaced by the new one at its number; otherwise the next number.
        let (action, version) = match pending {
            Some((a, v)) if a == "publish" || a == "edit" => (a, v),
            Some((_, v)) => ("edit".to_owned(), v + 1), // a delete never reached the server: the row is still there
            None => (if open_live == 1 { "edit".to_owned() } else { "publish".to_owned() }, open_version + 1),
        };
        let mut payload = json!({
            "post_id": post_id,
            "author_kind": "person",
            "author_id": me,
            "jam_id": row.jam_id,
            "kind": row.kind,
            "title": row.title,
            "subtitle": row.subtitle,
            "markdown": markdown,
            "attachments": files.iter().map(|(id, mime, size)| json!({ "id": id, "mime": mime, "size": size })).collect::<Vec<_>>(),
            "topics": topics,
            "preview_of": if split.is_some() { json!(post_id) } else { Value::Null },
            "has_rest": has_rest,
            "version": version,
            "created": row.created,
        });
        if let Some(series) = row.series.as_deref().and_then(|s| serde_json::from_str::<Value>(s).ok()) {
            payload["series"] = series;
        }
        let text = payload.to_string();
        let signature = state.account.sign(format!("{OPEN_LABEL}{text}").as_bytes()).to_base64();
        let files_json = json!(files.iter().map(|(id, mime, _)| json!({ "id": id, "mime": mime })).collect::<Vec<_>>()).to_string();
        jam_store::put_open_job(conn, &OpenJob { post_id: post_id.into(), action, version, payload: Some(text), signature: Some(signature), cert: Some(state.cert().to_json().to_string()), files: files_json, attempts: 0 })?;
        conn.execute("UPDATE jam_posts SET open_version = ?2, open_live = 1 WHERE post_id = ?1", params![post_id, version]).map_err(db_err)?;
        Ok(())
    }

    /// Removes the open copy of a post (the audience went back to subscribers, the marker went, or the post was deleted).
    pub(super) fn queue_open_delete(&self, conn: &Connection, post_id: &str) -> Result<(), StoreError> {
        let (open_version, open_live): (i64, i64) = conn
            .query_row("SELECT open_version, open_live FROM jam_posts WHERE post_id = ?1", params![post_id], |r| Ok((r.get(0)?, r.get(1)?)))
            .optional()
            .map_err(db_err)?
            .unwrap_or((0, 0));
        if open_live == 0 {
            return Ok(());
        }
        match pending_job(conn, post_id)? {
            // Never reached the server: nothing to delete there. The server holds one version fewer than the job carried.
            Some((a, v)) if a == "publish" => {
                conn.execute("DELETE FROM open_outbox WHERE post_id = ?1", params![post_id]).map_err(db_err)?;
                conn.execute("UPDATE jam_posts SET open_version = ?2, open_live = 0 WHERE post_id = ?1", params![post_id, v - 1]).map_err(db_err)?;
            }
            other => {
                let held = match other {
                    Some((_, v)) => v - 1, // an edit not delivered yet: the server holds the one before
                    None => open_version,
                };
                jam_store::put_open_job(conn, &OpenJob { post_id: post_id.into(), action: "delete".into(), version: held, payload: None, signature: None, cert: None, files: "[]".into(), attempts: 0 })?;
                conn.execute("UPDATE jam_posts SET open_version = ?2, open_live = 0 WHERE post_id = ?1", params![post_id, held]).map_err(db_err)?;
            }
        }
        Ok(())
    }

    /// Sends the waiting open deliveries (at most [`OPEN_PER_PASS`] a pass): each file as an `open-file` (put, upload, commit), then the signed row. No
    /// internet ends the pass; a server that does not take open posts yet holds the job with a back-off; a limit backs off too.
    pub(super) fn deliver_open(&self, transport: &Arc<dyn Transport>, token: &str) {
        let now = now_ms();
        let Ok(jobs) = self.with_conn(|conn| jam_store::open_jobs(conn, now, OPEN_PER_PASS)) else { return };
        for job in jobs {
            match self.send_open_job(transport, token, &job) {
                Ok(()) => {
                    let _ = self.with_conn(|conn| jam_store::done_open_job(conn, &job.post_id, job.version));
                }
                Err(Outcome::Offline) => return,
                Err(Outcome::Held(reason)) => {
                    let _ = self.with_conn(|conn| jam_store::back_off_open_job(conn, &job.post_id, job.attempts, now, Some(&reason)));
                }
                Err(Outcome::Limited) => {
                    let _ = self.with_conn(|conn| jam_store::back_off_open_job(conn, &job.post_id, job.attempts, now, Some("rate_limited")));
                    return;
                }
            }
        }
    }

    fn send_open_job(&self, transport: &Arc<dyn Transport>, token: &str, job: &OpenJob) -> Result<(), Outcome> {
        if job.action == "delete" {
            let (status, body) = call(transport, Some(token), "open-post", &json!({ "action": "delete", "post_id": job.post_id })).map_err(Outcome::from)?;
            return match status {
                200..=299 | 404 => Ok(()),
                other => Err(Outcome::of(other, &body)),
            };
        }
        let files: Vec<Value> = serde_json::from_str(&job.files).unwrap_or_default();
        for file in &files {
            let (Some(id), Some(mime)) = (file.get("id").and_then(Value::as_str), file.get("mime").and_then(Value::as_str)) else { continue };
            let Some(bytes) = self.with_conn(|conn| jam_store::attachment_data(conn, &job.post_id, id)).ok().flatten() else {
                return Err(Outcome::Held("file_missing".into()));
            };
            let (status, body) = call(transport, Some(token), "open-file", &json!({ "action": "put", "file_id": id, "size": bytes.len(), "mime": mime })).map_err(Outcome::from)?;
            if !(200..300).contains(&status) {
                return Err(Outcome::of(status, &body));
            }
            let url = body.get("url").and_then(Value::as_str).ok_or(Outcome::Held("bad_answer".into()))?;
            let (put, _) = raw(transport, "PUT", url, Some("application/octet-stream"), bytes).map_err(Outcome::from)?;
            if !(200..300).contains(&put) {
                return Err(Outcome::Held(format!("upload_{put}")));
            }
            let (status, body) = call(transport, Some(token), "open-file", &json!({ "action": "commit", "file_id": id })).map_err(Outcome::from)?;
            if !(200..300).contains(&status) {
                return Err(Outcome::of(status, &body));
            }
        }
        let cert: Value = job.cert.as_deref().and_then(|c| serde_json::from_str(c).ok()).unwrap_or(Value::Null);
        let (status, body) = call(transport, Some(token), "open-post", &json!({ "action": job.action, "payload": job.payload, "signature": job.signature, "cert": cert })).map_err(Outcome::from)?;
        match status {
            200..=299 => Ok(()),
            // The server already holds this version (an answer was lost): done.
            409 if matches!(body.get("error").and_then(Value::as_str), Some("id_taken") | Some("version")) => Ok(()),
            other => Err(Outcome::of(other, &body)),
        }
    }
}

impl LimeStore {
    /// Seals a post again, unchanged in its words, as the next version (so the stored audience and series reach the subscribers and the open copy
    /// follows): the same path as an edit.
    fn reseal(&self, row: &jam_store::PostRow) -> Result<(), StoreError> {
        self.edit_jam_post(row.post_id.clone(), row.title.clone(), row.subtitle.clone(), row.markdown.clone(), vec![], row.display_as.clone(), false, None)
    }
}

/// The job waiting for a post: its action and version.
fn pending_job(conn: &Connection, post_id: &str) -> Result<Option<(String, i64)>, StoreError> {
    conn.query_row("SELECT action, version FROM open_outbox WHERE post_id = ?1", params![post_id], |r| Ok((r.get(0)?, r.get(1)?))).optional().map_err(db_err)
}

/// Why a delivery did not finish.
enum Outcome {
    Offline,
    Limited,
    Held(String),
}

impl Outcome {
    fn of(status: u16, body: &Value) -> Self {
        match status {
            429 => Outcome::Limited,
            500..=599 => Outcome::Held(format!("server_{status}")),
            _ => Outcome::Held(body.get("error").and_then(Value::as_str).unwrap_or("refused").to_owned()),
        }
    }
}

impl From<StoreError> for Outcome {
    fn from(_: StoreError) -> Self {
        Outcome::Offline
    }
}

#[uniffi::export]
impl LimeStore {
    /// Changes who can read one of my posts (Edit, LIME-195): `everyone` publishes an open copy of the same post (the encrypted one stays for
    /// subscribers); `subscribers` deletes the open copy from the server (a post with a `[[freewall]]` keeps its Preview). Nothing is sent now; the
    /// delivery pass does it. People may already have read, saved or copied what was open.
    pub fn set_jam_post_audience(&self, post_id: String, audience: String) -> Result<(), StoreError> {
        if !jam_store::valid_audience(&audience) {
            return Err(StoreError::Rejected);
        }
        let state = self.load_or_create_account()?;
        let me = self.registered_user(&state)?;
        let row = self.with_conn(|conn| Ok(jam_store::post(conn, &post_id)?.filter(|p| !p.deleted && p.author == me))).and_then(|r| r.ok_or(StoreError::NotFound))?;
        if row.audience == audience {
            return Ok(());
        }
        self.with_conn(|conn| conn.execute("UPDATE jam_posts SET audience = ?2 WHERE post_id = ?1", params![post_id, audience]).map(|_| ()).map_err(db_err))?;
        self.reseal(&row)
    }

    /// Puts one of my posts in a series, or takes it out (`None`) (LIME-210b/f). The post is sealed again as a new version so subscribers see the
    /// change; its open copy, if any, follows.
    pub fn set_jam_post_series(&self, post_id: String, series: Option<SeriesInfo>) -> Result<(), StoreError> {
        let state = self.load_or_create_account()?;
        let me = self.registered_user(&state)?;
        let series_text = match &series {
            Some(s) => Some(jam_store::clean_series(&s.to_value()).ok_or(StoreError::Rejected)?.to_string()),
            None => None,
        };
        let row = self.with_conn(|conn| Ok(jam_store::post(conn, &post_id)?.filter(|p| !p.deleted && p.author == me))).and_then(|r| r.ok_or(StoreError::NotFound))?;
        if row.series == series_text {
            return Ok(());
        }
        self.with_conn(|conn| conn.execute("UPDATE jam_posts SET series = ?2 WHERE post_id = ?1", params![post_id, series_text]).map(|_| ()).map_err(db_err))?;
        self.reseal(&row)
    }

    /// Sets the subject, grade and topic chips of one of my posts (Edit); an empty list means the jam's topics again. The post is sealed again as the next
    /// version and its open copy follows.
    pub fn set_jam_post_topics(&self, post_id: String, topics: Vec<String>) -> Result<(), StoreError> {
        let state = self.load_or_create_account()?;
        let me = self.registered_user(&state)?;
        let text = if topics.is_empty() { None } else { Some(json!(jam_store::clean_topics(&topics).ok_or(StoreError::Rejected)?).to_string()) };
        let row = self.with_conn(|conn| Ok(jam_store::post(conn, &post_id)?.filter(|p| !p.deleted && p.author == me))).and_then(|r| r.ok_or(StoreError::NotFound))?;
        if row.topics == text {
            return Ok(());
        }
        self.with_conn(|conn| conn.execute("UPDATE jam_posts SET topics = ?2 WHERE post_id = ?1", params![post_id, text]).map(|_| ()).map_err(db_err))?;
        self.reseal(&row)
    }

    /// How many open deliveries wait, and how many are held.
    pub fn open_send_progress(&self) -> Result<OpenSendProgress, StoreError> {
        let (pending, held) = self.with_conn(jam_store::open_progress)?;
        Ok(OpenSendProgress { pending: pending as u32, held: held as u32 })
    }

    /// Discover's index (signed in): the open posts newer than `since` (the last cursor, 0 the first time), oldest first, metadata only, and the ids
    /// of those deleted or taken down since. Filters by subject or grade are the app's, on these items: the server never learns what a person looks for.
    pub fn fetch_open_feed(&self, transport: Arc<dyn Transport>, auth_token: String, since: i64) -> Result<OpenFeedPage, StoreError> {
        let (status, body) = call(&transport, Some(&auth_token), "open-feed", &json!({ "since": since.max(0), "limit": 50 }))?;
        check(status)?;
        let mut items = Vec::new();
        let mut gone = Vec::new();
        for entry in body.get("items").and_then(Value::as_array).ok_or(StoreError::BadMessage)? {
            let text = |k: &str| entry.get(k).and_then(Value::as_str).map(str::to_owned);
            let Some(post_id) = text("post_id") else { continue };
            if entry.get("gone").and_then(Value::as_bool) == Some(true) {
                gone.push(post_id);
                continue;
            }
            let (Some(author_id), Some(jam_id), Some(kind)) = (text("author_id"), text("jam_id"), text("kind")) else { continue };
            items.push(OpenFeedItem {
                post_id,
                author_id,
                jam_id,
                kind,
                title: text("title").unwrap_or_default(),
                subtitle: text("subtitle").unwrap_or_default(),
                excerpt: text("excerpt").unwrap_or_default(),
                topics: topics_of(entry),
                file_ids: entry.get("files").and_then(Value::as_array).map(|a| a.iter().filter_map(Value::as_str).map(str::to_owned).collect()).unwrap_or_default(),
                series: series_of(entry),
                preview_of: text("preview_of"),
                has_rest: entry.get("has_rest").and_then(Value::as_bool).unwrap_or(false),
                version: entry.get("version").and_then(Value::as_u64).unwrap_or(1) as u32,
                created: entry.get("created_at").and_then(Value::as_str).and_then(parse_server_time).unwrap_or(0),
                seq: entry.get("seq").and_then(Value::as_i64).unwrap_or(0),
            });
        }
        self.forget_open_posts(&gone);
        Ok(OpenFeedPage { items, gone, cursor: body.get("cursor").and_then(Value::as_i64).unwrap_or(since), enabled: body.get("enabled").and_then(Value::as_bool).unwrap_or(false) })
    }

    /// One open post, whole, **checked on this phone** (no session needed). `NotFound` when it is gone or taken down; `BadMessage` when the row does
    /// not verify (a changed body, a swapped author, a certificate that does not chain, a master key other than the one remembered for the writer).
    pub fn fetch_open_post(&self, transport: Arc<dyn Transport>, post_id: String) -> Result<OpenPostInfo, StoreError> {
        let (status, body) = call(&transport, None, "open-post-get", &json!({ "post_id": post_id }))?;
        match status {
            200..=299 => {}
            404 | 410 => {
                self.forget_open_posts(std::slice::from_ref(&post_id));
                return Err(StoreError::NotFound);
            }
            other => return Err(if other >= 500 { StoreError::Unavailable } else { StoreError::Rejected }),
        }
        let row = body.get("post").ok_or(StoreError::BadMessage)?;
        let author = row.get("author_id").and_then(Value::as_str).ok_or(StoreError::BadMessage)?.to_owned();
        let pinned: Option<String> = self.with_conn(|conn| conn.query_row("SELECT master_key FROM peers WHERE user_id = ?1", params![author], |r| r.get(0)).optional().map_err(db_err))?;
        let verified = verify_row(row, &post_id, pinned.as_deref()).ok_or(StoreError::BadMessage)?;
        let p = &verified.payload;
        let text = |k: &str| p.get(k).and_then(Value::as_str).map(str::to_owned);
        let urls: Vec<(String, String)> = row
            .get("file_urls")
            .and_then(Value::as_array)
            .map(|a| a.iter().filter_map(|f| Some((f.get("id")?.as_str()?.to_owned(), f.get("url")?.as_str()?.to_owned()))).collect())
            .unwrap_or_default();
        // Only the files the signed text names; their addresses come from the server (the bytes are public, not signed).
        let files: Vec<OpenFileRef> = p
            .get("attachments")
            .and_then(Value::as_array)
            .map(|a| {
                a.iter()
                    .filter_map(|f| {
                        let id = f.get("id")?.as_str()?;
                        let url = urls.iter().find(|(i, _)| i == id)?.1.clone();
                        Some(OpenFileRef { id: id.to_owned(), url, mime: f.get("mime")?.as_str()?.to_owned() })
                    })
                    .collect()
            })
            .unwrap_or_default();
        let markdown = crate::format::normalise_post(&text("markdown").unwrap_or_default());
        let info = OpenPostInfo {
            post_id,
            author_id: author,
            jam_id: text("jam_id").ok_or(StoreError::BadMessage)?,
            kind: text("kind").ok_or(StoreError::BadMessage)?,
            title: text("title").unwrap_or_default(),
            subtitle: text("subtitle").unwrap_or_default(),
            plain: crate::format::plain_text_post(&markdown),
            markdown,
            topics: topics_of(p),
            files,
            series: series_of(p),
            preview_of: text("preview_of"),
            has_rest: p.get("has_rest").and_then(Value::as_bool).unwrap_or(false),
            version: p.get("version").and_then(Value::as_u64).unwrap_or(1) as u32,
            created: p.get("created").and_then(Value::as_i64).unwrap_or(0),
            pinned: verified.pinned,
        };
        self.remember_open_post(&info);
        Ok(info)
    }

    /// The open posts this phone has fetched whose title, subtitle or text match `query` (prefix-matched, case- and diacritic-insensitive), best first.
    /// A post I hold as a subscriber is not repeated here (the jam search finds it). Nothing leaves the phone.
    pub fn search_open_posts(&self, query: String, limit: u32) -> Result<Vec<OpenSearchHit>, StoreError> {
        let Some(fts) = crate::store::search::fts_query(&query) else { return Ok(Vec::new()) };
        self.with_conn(|conn| {
            let sql = format!(
                "SELECT s.post_id, s.author_id, s.kind, s.title, s.created, snippet(open_fts, -1, char({start}), char({end}), '…', 12)
                 FROM open_fts JOIN open_seen s ON s.post_id = open_fts.post_id
                 WHERE open_fts MATCH ?1 AND NOT EXISTS (SELECT 1 FROM jam_posts p WHERE p.post_id = s.post_id AND p.deleted_at IS NULL)
                 ORDER BY rank, s.created DESC, s.post_id DESC LIMIT ?2",
                start = crate::store::search::MATCH_START as u32,
                end = crate::store::search::MATCH_END as u32,
            );
            let mut statement = conn.prepare(&sql).map_err(db_err)?;
            let hits = statement
                .query_map(params![fts, limit.max(1)], |r| Ok(OpenSearchHit { post_id: r.get(0)?, author_id: r.get(1)?, kind: r.get(2)?, title: r.get(3)?, created: r.get(4)?, snippet: r.get(5)? }))
                .map_err(db_err)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(db_err)?;
            Ok(hits)
        })
    }
}

impl LimeStore {
    /// Puts a fetched, verified open post in the phone's search (replacing an older version).
    fn remember_open_post(&self, p: &OpenPostInfo) {
        let _ = self.with_conn(|conn| {
            conn.execute("DELETE FROM open_fts WHERE post_id = ?1", params![p.post_id]).map_err(db_err)?;
            conn.execute("INSERT OR REPLACE INTO open_seen (post_id, author_id, jam_id, kind, title, created) VALUES (?1, ?2, ?3, ?4, ?5, ?6)", params![p.post_id, p.author_id, p.jam_id, p.kind, p.title, p.created]).map_err(db_err)?;
            conn.execute("INSERT INTO open_fts (title, subtitle, plain, post_id) VALUES (?1, ?2, ?3, ?4)", params![p.title, p.subtitle, p.plain, p.post_id]).map_err(db_err)?;
            Ok(())
        });
    }

    /// A post that is gone (deleted, taken down) leaves the search.
    fn forget_open_posts(&self, ids: &[String]) {
        for id in ids {
            let _ = self.with_conn(|conn| {
                conn.execute("DELETE FROM open_fts WHERE post_id = ?1", params![id]).map_err(db_err)?;
                conn.execute("DELETE FROM open_seen WHERE post_id = ?1", params![id]).map_err(db_err)?;
                Ok(())
            });
        }
    }
}

/// `2026-10-27T10:00:00.123+00:00` as milliseconds; `None` when it is not that.
fn parse_server_time(text: &str) -> Option<i64> {
    let (date, rest) = text.split_once('T')?;
    let mut d = date.split('-').map(|n| n.parse::<i64>().ok());
    let (y, m, day) = (d.next()??, d.next()??, d.next()??);
    let clock = rest.split(['+', 'Z', '-']).next()?;
    let mut t = clock.split(':');
    let (h, mi) = (t.next()?.parse::<i64>().ok()?, t.next()?.parse::<i64>().ok()?);
    let secs = t.next().and_then(|s| s.parse::<f64>().ok()).unwrap_or(0.0);
    // days from civil (Howard Hinnant)
    let y2 = if m <= 2 { y - 1 } else { y };
    let era = y2.div_euclid(400);
    let yoe = y2 - era * 400;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146_097 + doe - 719_468;
    Some(((days * 86_400 + h * 3_600 + mi * 60) as f64 * 1000.0 + secs * 1000.0) as i64)
}
