//! Emergency mode (LIME-143): sending a status, ending an emergency, the roll-up and this phone's choices. The rules are in
//! `store::emergency`; a status is an ordinary text message with an `emergency` object in its payload, so it is sent (and parked for the
//! mesh when there is no internet) like any message.

use super::*;
use crate::store::emergency::{self, EmergencyDraft, EmergencyInfo, EmergencyRollup, EmergencySettings};

#[uniffi::export]
impl LimeStore {
    /// Sends an emergency status to a conversation (a group, usually). The status joins the conversation's active emergency or starts one. Remembers the students and the place for next time.
    pub fn send_emergency(&self, conversation_id: String, draft: EmergencyDraft) -> Result<MessageItem, StoreError> {
        let draft = draft.validated()?;
        let text = draft.text();
        let session = self.with_conn(|conn| emergency::session_for(conn, &conversation_id, &new_id()))?;
        let info = EmergencyInfo {
            session_id: session,
            kind: "status".into(),
            status: draft.status.clone(),
            situation: draft.situation.clone(),
            students: draft.students,
            place: draft.place.clone(),
            note: draft.note.clone(),
        };
        let item = self.queue_with(conversation_id, text, None, Vec::new(), QueueExtras { emergency: Some(info), ..Default::default() })?;
        self.with_conn(|conn| {
            let mut settings = emergency::load_settings(conn);
            settings.last_students = draft.students;
            settings.last_place = draft.place.clone();
            emergency::save_settings(conn, &settings)
        })?;
        Ok(item)
    }

    /// Ends the conversation's active emergency Anyone in the group can.
    pub fn end_emergency(&self, conversation_id: String) -> Result<MessageItem, StoreError> {
        let session = self.with_conn(|conn| emergency::rollup(conn, &conversation_id)?.map(|r| r.session_id).ok_or(StoreError::NotFound))?;
        let info = EmergencyInfo {
            session_id: session, kind: "end".into(), status: String::new(), situation: String::new(), students: 0, place: String::new(), note: String::new(),
        };
        let text = "Emergency ended";
        self.queue_with(conversation_id, text.to_owned(), None, Vec::new(), QueueExtras { emergency: Some(info), ..Default::default() })
    }

    /// The live overview of the conversation's active emergency, or `None` when there is none.
    pub fn emergency_rollup(&self, conversation_id: String) -> Result<Option<EmergencyRollup>, StoreError> {
        self.with_conn(|conn| emergency::rollup(conn, &conversation_id))
    }

    pub fn emergency_settings(&self) -> Result<EmergencySettings, StoreError> {
        self.with_conn(|conn| Ok(emergency::load_settings(conn)))
    }

    pub fn set_emergency_settings(&self, settings: EmergencySettings) -> Result<(), StoreError> {
        self.with_conn(|conn| emergency::save_settings(conn, &settings))
    }
}

/// How an arriving emergency message is announced (silent by default).
#[uniffi::export]
pub fn emergency_alert_policy(sound_enabled: bool) -> emergency::EmergencyAlert {
    emergency::alert_policy(sound_enabled)
}

/// The number to call first for a region code (`US` → `911`).
#[uniffi::export]
pub fn emergency_number(region: String) -> String {
    emergency::emergency_number(&region).to_owned()
}
