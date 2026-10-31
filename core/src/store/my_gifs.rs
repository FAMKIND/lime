//! My GIFs (LIME-207): GIFs I saved, kept in this encrypted store with the words that find them. Nothing here is sent anywhere, and it goes with the account.
//! A GIF is found by words I gave it, the message text it came with, and the text read from its frames on this phone (`my_gifs_fts`, FTS5, as messages are).

use rusqlite::{params, OptionalExtension};
use sha2::{Digest, Sha256};

use super::search::fts_query;
use super::{db_err, now_ms, new_id, LimeStore, StoreError};

/// At most this many GIFs and this many bytes (the app says so when it is full).
pub(crate) const MAX_COUNT: u32 = 500;
pub(crate) const MAX_BYTES: u64 = 500 * 1024 * 1024;
/// One GIF: the app sends no more than 10 MB (LIME-206); a little room for the same file saved from elsewhere.
const MAX_ONE: usize = 12 * 1024 * 1024;
/// Words, message text and frame text are kept short.
const MAX_TEXT: usize = 1000;

/// One saved GIF, without its bytes.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct MyGif {
    pub id: String,
    /// Words I added (or none).
    pub words: String,
    /// The text of the message it came with.
    pub message_text: String,
    /// Text read from its pictures on this phone.
    pub frame_text: String,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub size: u64,
    pub added_at: i64,
    pub last_used: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct MyGifUsage {
    pub count: u32,
    pub bytes: u64,
    pub max_count: u32,
    pub max_bytes: u64,
}

fn clean(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ").chars().filter(|c| !c.is_control()).take(MAX_TEXT).collect()
}

fn digest(bytes: &[u8]) -> String {
    Sha256::digest(bytes).iter().map(|b| format!("{b:02x}")).collect()
}

const COLUMNS: &str = "id, words, message_text, frame_text, width, height, size, added_at, last_used";

fn row(r: &rusqlite::Row<'_>) -> rusqlite::Result<MyGif> {
    Ok(MyGif {
        id: r.get(0)?,
        words: r.get(1)?,
        message_text: r.get(2)?,
        frame_text: r.get(3)?,
        width: r.get::<_, Option<i64>>(4)?.map(|v| v as u32),
        height: r.get::<_, Option<i64>>(5)?.map(|v| v as u32),
        size: r.get::<_, i64>(6)? as u64,
        added_at: r.get(7)?,
        last_used: r.get(8)?,
    })
}

#[uniffi::export]
impl LimeStore {
    /// Saves a GIF (the same bytes saved twice is one GIF: it comes to the front and gains any words that are new). `Rejected` when it is not a GIF, too big,
    /// or the library is full (500 GIFs or 500 MB).
    pub fn add_my_gif(&self, bytes: Vec<u8>, words: String, message_text: String, frame_text: String, width: Option<u32>, height: Option<u32>) -> Result<String, StoreError> {
        if bytes.is_empty() || bytes.len() > MAX_ONE || !(bytes.starts_with(b"GIF87a") || bytes.starts_with(b"GIF89a")) {
            return Err(StoreError::Rejected);
        }
        let (words, message_text, frame_text) = (clean(&words), clean(&message_text), clean(&frame_text));
        let sum = digest(&bytes);
        let now = now_ms();
        let mut conn = self.lock();
        let tx = conn.transaction().map_err(db_err)?;
        let existing: Option<(String, String, String, String)> = tx
            .query_row("SELECT id, words, message_text, frame_text FROM my_gifs WHERE digest = ?1", params![sum], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))
            .optional()
            .map_err(db_err)?;
        if let Some((id, old_words, old_message, old_frames)) = existing {
            let merge = |old: &str, new: &str| if new.is_empty() || old.contains(new) { old.to_owned() } else if old.is_empty() { new.to_owned() } else { format!("{old} {new}") };
            tx.execute(
                "UPDATE my_gifs SET words = ?2, message_text = ?3, frame_text = ?4, last_used = ?5 WHERE id = ?1",
                params![id, clean(&merge(&old_words, &words)), clean(&merge(&old_message, &message_text)), clean(&merge(&old_frames, &frame_text)), now],
            )
            .map_err(db_err)?;
            tx.commit().map_err(db_err)?;
            return Ok(id);
        }
        let (count, used): (i64, i64) = tx.query_row("SELECT count(*), coalesce(sum(size), 0) FROM my_gifs", [], |r| Ok((r.get(0)?, r.get(1)?))).map_err(db_err)?;
        if count as u32 >= MAX_COUNT || used as u64 + bytes.len() as u64 > MAX_BYTES {
            return Err(StoreError::Rejected);
        }
        let id = new_id();
        tx.execute(
            "INSERT INTO my_gifs (id, bytes, words, message_text, frame_text, width, height, size, digest, added_at, last_used) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?10)",
            params![id, bytes, words, message_text, frame_text, width.map(i64::from), height.map(i64::from), bytes.len() as i64, sum, now],
        )
        .map_err(db_err)?;
        tx.commit().map_err(db_err)?;
        Ok(id)
    }

    pub fn remove_my_gif(&self, id: String) -> Result<(), StoreError> {
        self.lock().execute("DELETE FROM my_gifs WHERE id = ?1", params![id]).map_err(db_err)?;
        Ok(())
    }

    pub fn remove_all_my_gifs(&self) -> Result<(), StoreError> {
        self.lock().execute("DELETE FROM my_gifs", []).map_err(db_err)?;
        Ok(())
    }

    /// Replaces the words I gave a GIF.
    pub fn set_my_gif_words(&self, id: String, words: String) -> Result<(), StoreError> {
        let changed = self.lock().execute("UPDATE my_gifs SET words = ?2 WHERE id = ?1", params![id, clean(&words)]).map_err(db_err)?;
        if changed == 0 { Err(StoreError::NotFound) } else { Ok(()) }
    }

    /// The text the phone read from a GIF's pictures (it can arrive after the GIF was saved).
    pub fn set_my_gif_frame_text(&self, id: String, text: String) -> Result<(), StoreError> {
        self.lock().execute("UPDATE my_gifs SET frame_text = ?2 WHERE id = ?1", params![id, clean(&text)]).map_err(db_err)?;
        Ok(())
    }

    /// Sending one brings it to the front.
    pub fn touch_my_gif(&self, id: String) -> Result<(), StoreError> {
        self.lock().execute("UPDATE my_gifs SET last_used = ?2 WHERE id = ?1", params![id, now_ms()]).map_err(db_err)?;
        Ok(())
    }

    /// Recent first (last used, then added).
    pub fn list_my_gifs(&self, limit: u32) -> Result<Vec<MyGif>, StoreError> {
        let conn = self.lock();
        let mut statement = conn.prepare(&format!("SELECT {COLUMNS} FROM my_gifs ORDER BY last_used DESC, added_at DESC LIMIT ?1")).map_err(db_err)?;
        let rows = statement.query_map(params![limit.max(1)], row).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
        Ok(rows)
    }

    /// GIFs whose words, message text or frame text match what was typed (every word must; the last as a prefix), best match first, then recent.
    pub fn search_my_gifs(&self, query: String, limit: u32) -> Result<Vec<MyGif>, StoreError> {
        let Some(fts) = fts_query(&query) else { return self.list_my_gifs(limit) };
        let conn = self.lock();
        let mut statement = conn
            .prepare(&format!(
                "SELECT {} FROM my_gifs g JOIN my_gifs_fts f ON f.id = g.id WHERE my_gifs_fts MATCH ?1 ORDER BY f.rank, g.last_used DESC LIMIT ?2",
                COLUMNS.split(", ").map(|c| format!("g.{c}")).collect::<Vec<_>>().join(", ")
            ))
            .map_err(db_err)?;
        let rows = statement.query_map(params![fts, limit.max(1)], row).map_err(db_err)?.collect::<Result<Vec<_>, _>>().map_err(db_err)?;
        Ok(rows)
    }

    pub fn my_gif_bytes(&self, id: String) -> Result<Option<Vec<u8>>, StoreError> {
        self.lock().query_row("SELECT bytes FROM my_gifs WHERE id = ?1", params![id], |r| r.get(0)).optional().map_err(db_err)
    }

    pub fn my_gifs_usage(&self) -> Result<MyGifUsage, StoreError> {
        let (count, bytes): (i64, i64) = self.lock().query_row("SELECT count(*), coalesce(sum(size), 0) FROM my_gifs", [], |r| Ok((r.get(0)?, r.get(1)?))).map_err(db_err)?;
        Ok(MyGifUsage { count: count as u32, bytes: bytes as u64, max_count: MAX_COUNT, max_bytes: MAX_BYTES })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn store() -> (tempfile::TempDir, std::sync::Arc<LimeStore>) {
        let dir = tempfile::tempdir().unwrap();
        let store = LimeStore::open(dir.path().join("lime.db").to_string_lossy().into_owned(), vec![9; 32]).unwrap();
        (dir, store)
    }

    fn gif(seed: u8) -> Vec<u8> {
        let mut bytes = b"GIF89a".to_vec();
        bytes.extend(std::iter::repeat(seed).take(200));
        bytes
    }

    #[test]
    fn a_gif_is_found_by_my_words_by_its_message_and_by_the_text_in_its_pictures() {
        let (_dir, store) = store();
        let a = store.add_my_gif(gif(1), "birthday cake".into(), "".into(), "".into(), Some(200), Some(100)).unwrap();
        let b = store.add_my_gif(gif(2), "".into(), "see you at the staff meeting".into(), "".into(), None, None).unwrap();
        let c = store.add_my_gif(gif(3), "".into(), "".into(), "Happy Birthday!".into(), None, None).unwrap();
        let ids = |q: &str| store.search_my_gifs(q.into(), 10).unwrap().into_iter().map(|g| g.id).collect::<Vec<_>>();
        let birthday = ids("birthday");
        assert!(birthday.contains(&a) && birthday.contains(&c) && !birthday.contains(&b), "my words and the picture's own text: {birthday:?}");
        assert_eq!(ids("meeting"), vec![b.clone()], "the message it came with");
        assert_eq!(ids("birth"), birthday, "a prefix finds it as you type");
        assert_eq!(ids("birthday cake"), vec![a.clone()], "every word must match");
        assert!(ids("zzz").is_empty());
        assert_eq!(ids("").len(), 3, "nothing typed: everything, recent first");
        // Words can be added later, and text can arrive after the save.
        store.set_my_gif_words(b.clone(), "farewell".into()).unwrap();
        assert_eq!(ids("farewell"), vec![b.clone()]);
        store.set_my_gif_frame_text(a.clone(), "congratulations".into()).unwrap();
        assert!(ids("congrat").contains(&a));
        // Bytes come back, a missing one is None.
        assert_eq!(store.my_gif_bytes(a.clone()).unwrap(), Some(gif(1)));
        assert_eq!(store.my_gif_bytes("nope".into()).unwrap(), None);
    }

    #[test]
    fn saving_the_same_gif_twice_is_one_gif_that_comes_to_the_front_and_remove_works() {
        let (_dir, store) = store();
        let first = store.add_my_gif(gif(1), "party".into(), "".into(), "".into(), None, None).unwrap();
        let _other = store.add_my_gif(gif(2), "".into(), "".into(), "".into(), None, None).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(5));
        let again = store.add_my_gif(gif(1), "balloons".into(), "".into(), "".into(), None, None).unwrap();
        assert_eq!(first, again, "one GIF");
        let list = store.list_my_gifs(10).unwrap();
        assert_eq!(list.len(), 2);
        assert_eq!(list[0].id, first, "recent first");
        assert_eq!(list[0].words, "party balloons", "the new word is kept");
        store.remove_my_gif(first.clone()).unwrap();
        assert_eq!(store.my_gifs_usage().unwrap().count, 1);
        assert!(store.search_my_gifs("party".into(), 10).unwrap().is_empty(), "the index follows");
        store.remove_all_my_gifs().unwrap();
        assert_eq!(store.my_gifs_usage().unwrap(), MyGifUsage { count: 0, bytes: 0, max_count: MAX_COUNT, max_bytes: MAX_BYTES });
    }

    #[test]
    fn only_gifs_that_fit_are_kept_and_a_full_library_says_so() {
        let (_dir, store) = store();
        assert!(store.add_my_gif(vec![1, 2, 3], "".into(), "".into(), "".into(), None, None).is_err(), "not a GIF");
        assert!(store.add_my_gif(Vec::new(), "".into(), "".into(), "".into(), None, None).is_err());
        let mut huge = b"GIF89a".to_vec();
        huge.resize(MAX_ONE + 1, 0);
        assert!(store.add_my_gif(huge, "".into(), "".into(), "".into(), None, None).is_err(), "too big for one");
        // The cap: 500 GIFs.
        for i in 0..MAX_COUNT {
            let mut bytes = b"GIF89a".to_vec();
            bytes.extend(i.to_be_bytes());
            store.add_my_gif(bytes, "".into(), "".into(), "".into(), None, None).unwrap();
        }
        assert_eq!(store.my_gifs_usage().unwrap().count, MAX_COUNT);
        assert_eq!(store.add_my_gif(gif(77), "".into(), "".into(), "".into(), None, None), Err(StoreError::Rejected), "full");
        // The same GIF again is still fine (it is already there).
        let mut known = b"GIF89a".to_vec();
        known.extend(3u32.to_be_bytes());
        assert!(store.add_my_gif(known, "again".into(), "".into(), "".into(), None, None).is_ok());
    }

    #[test]
    fn the_library_lives_in_the_encrypted_file_and_survives_a_reopen() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("lime.db").to_string_lossy().into_owned();
        let id = {
            let store = LimeStore::open(path.clone(), vec![9; 32]).unwrap();
            store.add_my_gif(gif(5), "kept".into(), "".into(), "".into(), None, None).unwrap()
        };
        let again = LimeStore::open(path, vec![9; 32]).unwrap();
        assert_eq!(again.search_my_gifs("kept".into(), 5).unwrap()[0].id, id);
    }
}
