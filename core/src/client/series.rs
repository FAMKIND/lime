//! A series of its own (LIME-260a): a description and a cover for a series, kept in the jam's signed state beside its title and about. Today a series is only fields
//! on each post (`series` id, title, part, total); this is what describes the series itself, for the series page (260b).
//!
//! - **Writer only.** Only the jam's writer sets it (a co-author or a subscriber cannot); it travels to subscribers inside the same `jam.update` op that carries the
//!   jam's title and about (and in the welcome of a new subscriber), so the server sees one more encrypted state update, exactly as for a title change.
//! - **The cover is small.** It rides in the state as a JPEG of at most 24 KB (the app frames and shrinks it), not as a blob, so it needs no upload pass and
//!   arrives with the state. Open (Everyone) parts carry the series title only, as before.
//! - **Defaults** when unset: no description, and the cover of the newest part (its `cover.jpg` preview, else its first picture's).

use super::jam::{queue_op, signed_op};
use super::*;
use crate::store::jam as jam_store;

/// The longest description, in characters; the largest cover, in bytes; the most series described per jam.
const MAX_DESCRIPTION: usize = 1_000;
const MAX_COVER_BYTES: usize = 24 * 1024;
const MAX_SERIES_PER_JAM: usize = 24;

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct SeriesMeta {
    pub series_id: String,
    pub title: String,
    pub description: String,
    /// A small JPEG, if the writer chose one.
    pub cover: Option<Vec<u8>>,
}

pub(crate) fn metas(conn: &Connection, jam_id: &str) -> Result<Vec<SeriesMeta>, StoreError> {
    let mut statement = conn.prepare("SELECT series_id, title, description, cover FROM series_meta WHERE jam_id = ?1 ORDER BY series_id").map_err(db_err)?;
    let rows = statement
        .query_map(params![jam_id], |r| Ok(SeriesMeta { series_id: r.get(0)?, title: r.get(1)?, description: r.get(2)?, cover: r.get::<_, Option<Vec<u8>>>(3)?.filter(|c| !c.is_empty()) }))
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    Ok(rows)
}

/// The metas as they travel in the jam's state.
pub(crate) fn metas_json(conn: &Connection, jam_id: &str) -> Result<Value, StoreError> {
    Ok(Value::Array(
        metas(conn, jam_id)?
            .into_iter()
            .map(|m| json!({ "id": m.series_id, "title": m.title, "description": m.description, "cover": m.cover.map(|c| vodozemac::base64_encode(&c)) }))
            .collect(),
    ))
}

/// What the state says (`series`), applied: each entry is kept when its op is newer than what is held (or always, for a welcome).
pub(crate) fn apply_metas(conn: &Connection, jam_id: &str, value: &Value, hlc: &str, force: bool) -> Result<(), StoreError> {
    let Some(list) = value.get("series").and_then(Value::as_array) else { return Ok(()) };
    for entry in list.iter().take(MAX_SERIES_PER_JAM) {
        let text = |k: &str| entry.get(k).and_then(Value::as_str);
        let (Some(id), Some(title)) = (text("id").filter(|i| !i.is_empty() && i.len() <= 64), text("title").and_then(|t| jam_store::clean_line(t, 100))) else { continue };
        let description: String = text("description").unwrap_or_default().trim().chars().take(MAX_DESCRIPTION).collect();
        let cover = text("cover").and_then(|c| vodozemac::base64_decode(c).ok()).filter(|c| !c.is_empty() && c.len() <= MAX_COVER_BYTES);
        let held: Option<String> = conn.query_row("SELECT hlc FROM series_meta WHERE jam_id = ?1 AND series_id = ?2", params![jam_id, id], |r| r.get(0)).optional().map_err(db_err)?;
        if !force && held.as_deref().is_some_and(|h| h >= hlc) {
            continue;
        }
        conn.execute(
            "INSERT INTO series_meta (jam_id, series_id, title, description, cover, hlc) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
             ON CONFLICT (jam_id, series_id) DO UPDATE SET title = ?3, description = ?4, cover = ?5, hlc = ?6",
            params![jam_id, id, title, description, cover, hlc],
        )
        .map_err(db_err)?;
    }
    Ok(())
}

#[uniffi::export]
impl LimeStore {
    /// The writer describes a series: a title, a description (at most 1,000 characters) and optionally a cover (a JPEG of at most 24 KB). Subscribers are told with the
    /// jam's state. A co-author or a subscriber cannot.
    pub fn set_series_meta(&self, jam_id: String, series_id: String, title: String, description: String, cover: Option<Vec<u8>>) -> Result<(), StoreError> {
        let state = self.load_or_create_account()?;
        self.registered_user(&state)?;
        let title = jam_store::clean_line(&title, 100).ok_or(StoreError::Rejected)?;
        let description = description.trim().to_owned();
        if series_id.is_empty() || series_id.len() > 64 || description.chars().count() > MAX_DESCRIPTION || cover.as_ref().is_some_and(|c| c.is_empty() || c.len() > MAX_COVER_BYTES) {
            return Err(StoreError::Rejected);
        }
        let now = now_ms();
        self.with_conn(|conn| {
            let jam = jam_store::get(conn, &jam_id)?.filter(|j| j.mine && !j.ended).ok_or(StoreError::NotFound)?;
            let known = metas(conn, &jam_id)?;
            if known.len() >= MAX_SERIES_PER_JAM && !known.iter().any(|m| m.series_id == series_id) {
                return Err(StoreError::Rejected);
            }
            let hlc = super::tick_hlc(conn, now)?.render();
            conn.execute(
                "INSERT INTO series_meta (jam_id, series_id, title, description, cover, hlc) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
                 ON CONFLICT (jam_id, series_id) DO UPDATE SET title = ?3, description = ?4, cover = ?5, hlc = ?6",
                params![jam_id, series_id, title, description, cover, hlc],
            )
            .map_err(db_err)?;
            let payload = json!({ "jam_id": jam_id, "title": jam.title, "about": jam.about, "topics": jam.topics, "tiers": jam.tiers, "community": jam.community, "series": metas_json(conn, &jam_id)? });
            let op = signed_op(conn, &state, "jam.update", &jam_id, None, payload, now)?;
            // The same clock for the entry and the op that carries it, so a late copy of an older op cannot undo it.
            conn.execute("UPDATE series_meta SET hlc = ?3 WHERE jam_id = ?1 AND series_id = ?2", params![jam_id, series_id, op.hlc]).map_err(db_err)?;
            conn.execute("UPDATE jams SET state_hlc = ?2 WHERE jam_id = ?1", params![jam_id, op.hlc]).map_err(db_err)?;
            for user in jam_store::audience(conn, &jam_id, jam_store::TIER_FREE)? {
                queue_op(conn, &jam_id, &user, &op)?;
            }
            Ok(())
        })
    }

    /// What the writer said about one series, if anything.
    pub fn series_meta(&self, jam_id: String, series_id: String) -> Result<Option<SeriesMeta>, StoreError> {
        self.with_conn(|conn| Ok(metas(conn, &jam_id)?.into_iter().find(|m| m.series_id == series_id)))
    }

    /// Every series the writer described.
    pub fn list_series_meta(&self, jam_id: String) -> Result<Vec<SeriesMeta>, StoreError> {
        self.with_conn(|conn| metas(conn, &jam_id))
    }

    /// The series' cover: the one the writer chose, else the newest part's (its `cover.jpg` preview, else its first picture's).
    pub fn series_cover(&self, jam_id: String, series_id: String) -> Result<Option<Vec<u8>>, StoreError> {
        self.with_conn(|conn| {
            if let Some(cover) = metas(conn, &jam_id)?.into_iter().find(|m| m.series_id == series_id).and_then(|m| m.cover) {
                return Ok(Some(cover));
            }
            let mut parts: Vec<jam_store::PostRow> = jam_store::posts(conn, &jam_id)?
                .into_iter()
                .filter(|p| p.series.as_deref().and_then(|s| serde_json::from_str::<Value>(s).ok()).and_then(|v| v.get("id").and_then(Value::as_str).map(str::to_owned)).as_deref() == Some(series_id.as_str()))
                .collect();
            parts.sort_by_key(|p| std::cmp::Reverse(p.created));
            for part in parts {
                let files: Vec<Value> = serde_json::from_str::<Value>(&part.attachments).ok().and_then(|v| v.as_array().cloned()).unwrap_or_default();
                let thumb_of = |value: &Value| value.get("thumb").and_then(Value::as_str).and_then(|t| vodozemac::base64_decode(t).ok()).filter(|t| !t.is_empty());
                let mut found = files.iter().find(|f| f.get("name").and_then(Value::as_str) == Some("cover.jpg")).and_then(thumb_of);
                if found.is_none() {
                    found = files.iter().filter(|f| f.get("mime").and_then(Value::as_str).is_some_and(|m| m.starts_with("image/"))).find_map(thumb_of);
                }
                if found.is_some() {
                    return Ok(found);
                }
            }
            Ok(None)
        })
    }
}
