//! Emergency mode (LIME-143): a one-tap status ("Safe · 24 students · Room 204" / "Need help") sent to an emergency group.
//!
//! It is an ordinary `message.send` whose encrypted payload also carries an `emergency` object, so it travels, is parked for the mesh and is
//! delivered exactly like any text message (`docs/api-v2.md` section 9). The rules live here, for every platform: what a status holds, which
//! status counts for a person (the latest), the roll-up's order and totals, and how an arrival is announced (silent by default, a drill
//! never breaks through Do Not Disturb).

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{json, Value};

use super::{db_err, StoreError, ME_ID};

pub const MAX_PLACE: usize = 60;
pub const MAX_NOTE: usize = 200;
pub const MAX_STUDENTS: u32 = 9999;

/// The SRP's five actions (the "situation" line), when the school uses them.
pub const SITUATIONS: [&str; 5] = ["hold", "secure", "lockdown", "evacuate", "shelter"];

/// What the person fills in on the status sheet.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct EmergencyDraft {
    /// `safe` or `need_help`.
    pub status: String,
    /// One of `hold`, `secure`, `lockdown`, `evacuate`, `shelter`, or empty.
    pub situation: String,
    pub students: u32,
    pub place: String,
    pub note: String,
    /// A drill: every card and notification says so, and it never breaks through Do Not Disturb.
    pub drill: bool,
}

/// An emergency status or its end, as a message carries it.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct EmergencyInfo {
    /// The emergency this belongs to (the id of its first status).
    pub session_id: String,
    /// `status` or `end`.
    pub kind: String,
    /// `safe` or `need_help` (empty for an end).
    pub status: String,
    pub situation: String,
    pub students: u32,
    pub place: String,
    pub note: String,
    pub drill: bool,
}

/// One person's line in the roll-up. `user_id` is `None` for me.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct RollupEntry {
    pub user_id: Option<String>,
    /// `need_help`, `no_response` or `safe`.
    pub status: String,
    pub situation: String,
    pub students: u32,
    pub place: String,
    pub note: String,
    /// When their latest status was sent (milliseconds); 0 for no response.
    pub at: i64,
    pub message_id: Option<String>,
}

/// The live overview of an active emergency in a group.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct EmergencyRollup {
    pub session_id: String,
    pub conversation_id: String,
    pub drill: bool,
    /// Need help first, then no response yet, then safe; newest first within each.
    pub entries: Vec<RollupEntry>,
    /// Students with the people who have answered (safe or not).
    pub students_total: u32,
    pub safe: u32,
    pub need_help: u32,
    pub no_response: u32,
}

/// How an arriving emergency message is announced.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct EmergencyAlert {
    /// A notification is shown.
    pub show: bool,
    pub sound: bool,
    pub vibrate: bool,
    /// It is shown even in Do Not Disturb / work hours / quiet hours.
    pub breaks_quiet: bool,
    /// The label word on the card and the notification.
    pub label: String,
}

/// This phone's emergency choices.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct EmergencySettings {
    /// The conversation (a group) alerts go to; empty until chosen.
    pub group_id: String,
    /// Offer the SRP actions (Hold, Secure, Lockdown, Evacuate, Shelter).
    pub school_actions: bool,
    /// "Emergency alerts make a sound": off by default (a sound can reveal where people hide).
    pub sound: bool,
    pub last_students: u32,
    pub last_place: String,
}

impl Default for EmergencySettings {
    fn default() -> Self {
        EmergencySettings { group_id: String::new(), school_actions: true, sound: false, last_students: 0, last_place: String::new() }
    }
}

/// The announcement rule, in one place: a real emergency shows even when quiet, **silent** (no sound, no vibration) unless the person turned
/// sound on; a drill is a plain, silent notification that never breaks through quiet.
pub fn alert_policy(drill: bool, sound_enabled: bool) -> EmergencyAlert {
    if drill {
        EmergencyAlert { show: true, sound: false, vibrate: false, breaks_quiet: false, label: "DRILL".into() }
    } else {
        EmergencyAlert { show: true, sound: sound_enabled, vibrate: sound_enabled, breaks_quiet: true, label: "EMERGENCY".into() }
    }
}

/// The number to call first, for a region code (the phone's region). Unknown regions get 112, which most mobile networks route.
pub fn emergency_number(region: &str) -> &'static str {
    match region.to_ascii_uppercase().as_str() {
        "US" | "CA" | "MX" | "PH" | "DO" | "PR" | "GU" | "VI" | "AS" | "MP" | "BS" | "JM" | "TT" | "BB" => "911",
        "GB" | "HK" | "SG" | "MY" | "GH" | "KE" | "NG" | "ZW" | "UG" | "TZ" | "BD" => "999",
        "AU" => "000",
        "NZ" => "111",
        "JP" => "110",
        "KR" => "112",
        "CN" => "110",
        "TW" => "110",
        "NP" => "100",
        "IN" | "PK" | "LK" => "112",
        "BR" => "190",
        "AR" => "911",
        "CL" => "133",
        "CO" => "123",
        "PE" => "105",
        "ZA" => "10111",
        "EG" => "122",
        "TR" | "RU" | "UA" => "112",
        "IL" => "100",
        "SA" => "999",
        "AE" => "999",
        "TH" => "191",
        "VN" => "113",
        "ID" => "110",
        // The European Union, the UK's neighbours and other places where 112 is the number.
        "AT" | "BE" | "BG" | "HR" | "CY" | "CZ" | "DK" | "EE" | "FI" | "FR" | "DE" | "GR" | "HU" | "IE" | "IT" | "LV" | "LT" | "LU" | "MT" | "NL"
        | "PL" | "PT" | "RO" | "SK" | "SI" | "ES" | "SE" | "NO" | "IS" | "CH" => "112",
        _ => "112",
    }
}

fn text_of(status: &str, situation: &str, students: u32, place: &str, note: &str, drill: bool) -> String {
    let mut parts = Vec::new();
    parts.push(match status {
        "need_help" => "Need help".to_owned(),
        _ => "Safe".to_owned(),
    });
    if !situation.is_empty() {
        let mut s = situation.to_owned();
        if let Some(first) = s.get_mut(0..1) {
            first.make_ascii_uppercase();
        }
        parts.push(s);
    }
    parts.push(format!("{students} student{}", if students == 1 { "" } else { "s" }));
    if !place.is_empty() {
        parts.push(place.to_owned());
    }
    let mut text = format!("{}: {}", if drill { "DRILL" } else { "Emergency" }, parts.join(" \u{00B7} "));
    if !note.is_empty() {
        text.push_str(&format!(". {note}"));
    }
    text
}

impl EmergencyDraft {
    /// The words an older client shows (and the chat list's last line).
    pub(crate) fn text(&self) -> String {
        text_of(&self.status, &self.situation, self.students, self.place.trim(), self.note.trim(), self.drill)
    }

    pub(crate) fn validated(&self) -> Result<EmergencyDraft, StoreError> {
        let status = self.status.as_str();
        if status != "safe" && status != "need_help" {
            return Err(StoreError::Rejected);
        }
        if !self.situation.is_empty() && !SITUATIONS.contains(&self.situation.as_str()) {
            return Err(StoreError::Rejected);
        }
        let place = self.place.trim().to_owned();
        let note = self.note.trim().to_owned();
        if self.students > MAX_STUDENTS || place.chars().count() > MAX_PLACE || note.chars().count() > MAX_NOTE {
            return Err(StoreError::Rejected);
        }
        Ok(EmergencyDraft { place, note, ..self.clone() })
    }
}

impl EmergencyInfo {
    pub(crate) fn to_json(&self) -> Value {
        json!({
            "v": 1, "session": self.session_id, "kind": self.kind, "status": self.status, "situation": self.situation,
            "students": self.students, "place": self.place, "note": self.note, "drill": self.drill,
        })
    }

    /// What a received payload says, with every field bounded (a hostile sender cannot overflow the screen or the totals).
    pub(crate) fn parse(payload: &Value) -> Option<EmergencyInfo> {
        let e = payload.get("emergency")?.as_object()?;
        let text = |key: &str, max: usize| e.get(key).and_then(Value::as_str).map(|s| s.chars().take(max).collect::<String>()).unwrap_or_default();
        let session_id = text("session", 64);
        let kind = text("kind", 10);
        if session_id.is_empty() || (kind != "status" && kind != "end") {
            return None;
        }
        let status = text("status", 10);
        if kind == "status" && status != "safe" && status != "need_help" {
            return None;
        }
        let situation = text("situation", 12);
        let situation = if SITUATIONS.contains(&situation.as_str()) { situation } else { String::new() };
        Some(EmergencyInfo {
            session_id,
            kind,
            status,
            situation,
            students: e.get("students").and_then(Value::as_u64).map(|n| n.min(MAX_STUDENTS as u64) as u32).unwrap_or(0),
            place: text("place", MAX_PLACE),
            note: text("note", MAX_NOTE),
            drill: e.get("drill").and_then(Value::as_bool).unwrap_or(false),
        })
    }
}

pub(crate) fn store(conn: &Connection, message_id: &str, conversation: &str, sender: &str, info: &EmergencyInfo) -> Result<(), StoreError> {
    conn.execute(
        "INSERT OR REPLACE INTO emergency_messages
           (message_id, conversation_id, sender_id, session_id, kind, status, situation, students, place, note, drill)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
        params![message_id, conversation, sender, info.session_id, info.kind, info.status, info.situation, info.students, info.place, info.note, info.drill],
    )
    .map_err(db_err)?;
    Ok(())
}

/// A received message's emergency fields, kept once the message is stored.
pub(crate) fn apply_received(conn: &Connection, message_id: &str, conversation: &str, sender: &str, payload: &Value) -> Result<(), StoreError> {
    if let Some(info) = EmergencyInfo::parse(payload) {
        store(conn, message_id, conversation, sender, &info)?;
    }
    Ok(())
}

pub(crate) fn info(conn: &Connection, message_id: &str) -> Option<EmergencyInfo> {
    conn.query_row(
        "SELECT session_id, kind, status, situation, students, place, note, drill FROM emergency_messages WHERE message_id = ?1",
        params![message_id],
        |r| {
            Ok(EmergencyInfo {
                session_id: r.get(0)?, kind: r.get(1)?, status: r.get(2)?, situation: r.get(3)?, students: r.get(4)?, place: r.get(5)?, note: r.get(6)?, drill: r.get(7)?,
            })
        },
    )
    .optional()
    .ok()
    .flatten()
}

/// The emergencies of a conversation that have not ended: (session, drill), newest first. Real ones before drills.
fn active_sessions(conn: &Connection, conversation: &str) -> Result<Vec<(String, bool)>, StoreError> {
    let mut statement = conn
        .prepare(
            "SELECT e.session_id, MAX(e.drill), MAX(m.sent_at) AS last
             FROM emergency_messages e JOIN messages m ON m.id = e.message_id
             WHERE e.conversation_id = ?1 AND m.deleted = 0
               AND e.session_id NOT IN (SELECT session_id FROM emergency_messages WHERE conversation_id = ?1 AND kind = 'end')
             GROUP BY e.session_id ORDER BY MAX(e.drill) ASC, last DESC",
        )
        .map_err(db_err)?;
    let rows = statement
        .query_map(params![conversation], |r| Ok((r.get::<_, String>(0)?, r.get::<_, bool>(1)?)))
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    Ok(rows)
}

/// The session a new status joins: the conversation's active one with the same real/drill kind, else a new one.
pub(crate) fn session_for(conn: &Connection, conversation: &str, drill: bool, new_id: &str) -> Result<String, StoreError> {
    Ok(active_sessions(conn, conversation)?.into_iter().find(|(_, d)| *d == drill).map(|(s, _)| s).unwrap_or_else(|| new_id.to_owned()))
}

/// The roll-up of the conversation's active emergency (a real one before a drill), or `None`.
pub(crate) fn rollup(conn: &Connection, conversation: &str) -> Result<Option<EmergencyRollup>, StoreError> {
    let Some((session, drill)) = active_sessions(conn, conversation)?.into_iter().next() else { return Ok(None) };
    // The latest status of each sender in this session (by the time it was sent, then by id).
    let mut statement = conn
        .prepare(
            "SELECT e.sender_id, e.status, e.situation, e.students, e.place, e.note, m.sent_at, e.message_id
             FROM emergency_messages e JOIN messages m ON m.id = e.message_id
             WHERE e.conversation_id = ?1 AND e.session_id = ?2 AND e.kind = 'status' AND m.deleted = 0
             ORDER BY m.sent_at, e.message_id",
        )
        .map_err(db_err)?;
    let rows = statement
        .query_map(params![conversation, session], |r| {
            Ok((r.get::<_, String>(0)?, RollupEntry {
                user_id: None, status: r.get(1)?, situation: r.get(2)?, students: r.get(3)?, place: r.get(4)?, note: r.get(5)?, at: r.get(6)?, message_id: Some(r.get(7)?),
            }))
        })
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    let mut latest: Vec<(String, RollupEntry)> = Vec::new();
    for (sender, entry) in rows {
        match latest.iter_mut().find(|(s, _)| *s == sender) {
            Some(slot) => slot.1 = entry,
            None => latest.push((sender, entry)),
        }
    }
    // Everyone else in the conversation has not answered yet.
    let mut members = conn
        .prepare("SELECT person_id FROM members WHERE conversation_id = ?1 AND person_id != ?2 ORDER BY position")
        .map_err(db_err)?;
    let others = members
        .query_map(params![conversation, ME_ID], |r| r.get::<_, String>(0))
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    let mut entries: Vec<RollupEntry> = latest
        .iter()
        .map(|(sender, entry)| RollupEntry { user_id: if sender == ME_ID { None } else { Some(sender.clone()) }, ..entry.clone() })
        .collect();
    let mut waiting = Vec::new();
    for person in others {
        if !latest.iter().any(|(s, _)| *s == person) {
            waiting.push(RollupEntry { user_id: Some(person), status: "no_response".into(), situation: String::new(), students: 0, place: String::new(), note: String::new(), at: 0, message_id: None });
        }
    }
    if !latest.iter().any(|(s, _)| s == ME_ID) {
        // I have not answered either, if I am in the conversation: shown first among the waiting.
        waiting.insert(0, RollupEntry { user_id: None, status: "no_response".into(), situation: String::new(), students: 0, place: String::new(), note: String::new(), at: 0, message_id: None });
    }
    entries.extend(waiting);
    let rank = |s: &str| match s {
        "need_help" => 0,
        "no_response" => 1,
        _ => 2,
    };
    // Stable: no-response keep the order of the members; the others newest first.
    entries.sort_by(|a, b| rank(&a.status).cmp(&rank(&b.status)).then_with(|| if a.status == "no_response" { std::cmp::Ordering::Equal } else { b.at.cmp(&a.at) }));
    let count = |s: &str| entries.iter().filter(|e| e.status == s).count() as u32;
    Ok(Some(EmergencyRollup {
        session_id: session,
        conversation_id: conversation.to_owned(),
        drill,
        students_total: entries.iter().map(|e| e.students).sum(),
        safe: count("safe"),
        need_help: count("need_help"),
        no_response: count("no_response"),
        entries,
    }))
}

pub(crate) fn load_settings(conn: &Connection) -> EmergencySettings {
    let get = |key: &str| conn.query_row("SELECT value FROM emergency_settings WHERE key = ?1", params![key], |r| r.get::<_, String>(0)).optional().ok().flatten();
    let d = EmergencySettings::default();
    EmergencySettings {
        group_id: get("group_id").unwrap_or(d.group_id),
        school_actions: get("school_actions").map(|v| v == "1").unwrap_or(d.school_actions),
        sound: get("sound").map(|v| v == "1").unwrap_or(d.sound),
        last_students: get("last_students").and_then(|v| v.parse().ok()).unwrap_or(0),
        last_place: get("last_place").unwrap_or_default(),
    }
}

pub(crate) fn save_settings(conn: &Connection, s: &EmergencySettings) -> Result<(), StoreError> {
    let put = |key: &str, value: String| conn.execute("INSERT OR REPLACE INTO emergency_settings (key, value) VALUES (?1, ?2)", params![key, value]).map(|_| ()).map_err(db_err);
    put("group_id", s.group_id.clone())?;
    put("school_actions", if s.school_actions { "1" } else { "0" }.into())?;
    put("sound", if s.sound { "1" } else { "0" }.into())?;
    put("last_students", s.last_students.to_string())?;
    put("last_place", s.last_place.chars().take(MAX_PLACE).collect())?;
    Ok(())
}
