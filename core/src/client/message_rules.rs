//! Message action rules that lived only in Swift (LIME-304): who may edit or delete for everyone, which actions a message's menu offers and in
//! what order, and the six quick reactions. Mirrors `Message.canEdit` / `canDeleteForEveryone` (`ios/Lime/Model/Models.swift`) and `MessageActionPlan`
//! (`ios/Lime/Features/Chat/MessageActions.swift`). Pure functions of the message the core already returns. iOS keeps its Swift until LIME-133b.

use crate::store::MessageItem;

/// Edit and Delete for everyone are offered on my own sent messages for a day.
const EDIT_WINDOW_MS: i64 = 24 * 3600 * 1000;

/// A call shown as a message has the id `call:<call id>` on both phones; it is never sent as a message, so it cannot be edited or deleted for everyone.
fn is_call(message: &MessageItem) -> bool {
    message.id.starts_with("call:")
}

fn is_own(message: &MessageItem) -> bool {
    message.sender_id.is_none()
}

fn is_system(message: &MessageItem) -> bool {
    message.local_state == "system"
}

/// Still on its way, with nothing wrong: sending, or waiting for a nearby phone or internet.
fn in_flight(state: &str) -> bool {
    matches!(state, "sending" | "waiting" | "passed" | "offline")
}

/// Sent, sending or failed: the states a message of mine can still be changed in.
fn changeable(state: &str) -> bool {
    matches!(state, "sent" | "sending" | "failed")
}

/// I may edit this message: mine, not deleted, not a call, sent / sending / failed, not a system line, and no older than a day.
#[uniffi::export]
pub fn can_edit(message: MessageItem, now_ms: i64) -> bool {
    is_own(&message) && !message.deleted && !is_call(&message) && changeable(&message.local_state) && !is_system(&message) && now_ms - message.sent_at <= EDIT_WINDOW_MS
}

/// I may delete this message for everyone: mine, not a system line or call, sent / sending / failed, and no older than a day.
#[uniffi::export]
pub fn can_delete_for_everyone(message: MessageItem, now_ms: i64) -> bool {
    is_own(&message) && !is_system(&message) && !is_call(&message) && now_ms - message.sent_at <= EDIT_WINDOW_MS && changeable(&message.local_state)
}

/// One thing a message's menu can do, in the menu's order.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum MessageAction {
    React,
    Reply,
    Forward,
    Edit,
    Copy,
    SaveGif,
    Select,
    Report,
    Delete,
}

/// The actions a message offers, in the menu's order: React, Reply, Forward, Edit, Copy, Save to my GIFs, Select, Report, Delete.
/// `in_thread`: in a Replies screen there is no Reply. A screen leaves out the actions it does not have yet (Android: Report, Save to my GIFs).
#[uniffi::export]
pub fn message_actions(message: MessageItem, in_thread: bool, now_ms: i64) -> Vec<MessageAction> {
    let settled = !in_flight(&message.local_state) && message.local_state != "failed";
    let call = is_call(&message);
    let mut list = Vec::new();
    if !message.deleted && settled {
        list.push(MessageAction::React);
    }
    if !message.deleted && !in_thread && settled {
        list.push(MessageAction::Reply);
    }
    if !message.deleted && !call && message.emergency.is_none() {
        list.push(MessageAction::Forward);
    }
    // On a photo, album, video, voice message or file, Edit changes the caption only (so it needs one).
    if can_edit(message.clone(), now_ms) && !message.deleted && (message.attachments.is_empty() || !message.text.is_empty()) {
        list.push(MessageAction::Edit);
    }
    let copyable_image = message.text.is_empty() && message.attachments.len() == 1 && message.attachments[0].mime.starts_with("image/");
    if !message.deleted && !call && (!message.text.is_empty() || copyable_image) {
        list.push(MessageAction::Copy);
    }
    if !message.deleted && message.attachments.iter().any(|a| a.mime == "image/gif" && !a.removed) {
        list.push(MessageAction::SaveGif);
    }
    if !call {
        list.push(MessageAction::Select);
    }
    if !is_own(&message) && !message.deleted && !is_system(&message) && !call {
        list.push(MessageAction::Report);
    }
    list.push(MessageAction::Delete);
    list
}

/// The six emoji of the quick reaction row (the "+" opens every emoji).
#[uniffi::export]
pub fn quick_reactions() -> Vec<String> {
    ["👍", "❤️", "😂", "😮", "😢", "🙏"].iter().map(|s| (*s).to_owned()).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::AttachmentInfo;

    const NOW: i64 = 1_000_000_000_000;

    fn message(own: bool, age_s: f64, state: &str, deleted: bool) -> MessageItem {
        MessageItem {
            id: "m".into(),
            conversation_id: "dm:x".into(),
            sender_id: if own { None } else { Some("x".into()) },
            text: "hello **there**".into(),
            sent_at: NOW - (age_s * 1000.0) as i64,
            local_state: if own { state.into() } else { "received".into() },
            attachments: vec![],
            edited: false,
            deleted,
            reactions: vec![],
            forwarded: false,
            link_preview: None,
            thread_root: None,
            emergency: None,
        }
    }

    fn sent(own: bool, age_s: f64) -> MessageItem {
        message(own, age_s, "sent", false)
    }

    // The same cases as ios/LimeTests/MessageActionsTests.swift (testEditAndDeleteForEveryoneAreOnlyForMyOwnMessagesForADay).
    #[test]
    fn edit_and_delete_for_everyone_are_only_for_my_own_messages_for_a_day() {
        assert!(can_edit(sent(true, 60.0), NOW));
        assert!(can_edit(sent(true, 23.9 * 3600.0), NOW));
        assert!(!can_edit(sent(true, 24.1 * 3600.0), NOW), "after 24 hours");
        assert!(!can_edit(sent(false, 60.0), NOW), "someone else's");
        assert!(!can_edit(message(true, 60.0, "sent", true), NOW), "already deleted");
        assert!(can_delete_for_everyone(sent(true, 60.0), NOW));
        assert!(!can_delete_for_everyone(sent(true, 25.0 * 3600.0), NOW));
        assert!(!can_delete_for_everyone(sent(false, 60.0), NOW));
    }

    // ios/LimeTests/CallBubbleTests.swift: a call is never sent, so it can only be deleted for me.
    #[test]
    fn a_call_can_be_neither_edited_nor_deleted_for_everyone() {
        let mut call = sent(true, 60.0);
        call.id = "call:abc".into();
        assert!(!can_delete_for_everyone(call.clone(), NOW));
        assert!(!can_edit(call, NOW));
    }

    #[test]
    fn only_sent_sending_or_failed_messages_can_still_be_changed() {
        for state in ["sent", "sending", "failed"] {
            assert!(can_edit(message(true, 5.0, state, false), NOW), "{state}");
            assert!(can_delete_for_everyone(message(true, 5.0, state, false), NOW), "{state}");
        }
        for state in ["undelivered", "waiting", "passed", "offline", "system"] {
            assert!(!can_edit(message(true, 5.0, state, false), NOW), "{state}");
            assert!(!can_delete_for_everyone(message(true, 5.0, state, false), NOW), "{state}");
        }
    }

    #[test]
    fn the_menu_order_for_my_own_sent_message() {
        use MessageAction::*;
        assert_eq!(message_actions(sent(true, 60.0), false, NOW), vec![React, Reply, Forward, Edit, Copy, Select, Delete]);
    }

    #[test]
    fn someone_elses_message_can_be_reported_not_edited_and_a_thread_has_no_reply() {
        use MessageAction::*;
        assert_eq!(message_actions(sent(false, 60.0), false, NOW), vec![React, Reply, Forward, Copy, Select, Report, Delete]);
        assert_eq!(message_actions(sent(false, 60.0), true, NOW), vec![React, Forward, Copy, Select, Report, Delete]);
    }

    #[test]
    fn a_message_still_sending_cannot_be_reacted_to_or_replied_to_and_a_deleted_one_only_selected_or_deleted() {
        use MessageAction::*;
        assert_eq!(message_actions(message(true, 5.0, "sending", false), false, NOW), vec![Forward, Edit, Copy, Select, Delete]);
        assert_eq!(message_actions(message(false, 5.0, "received", true), false, NOW), vec![Select, Delete]);
    }

    #[test]
    fn a_photo_with_no_words_is_copyable_but_not_editable_and_a_gif_can_be_saved() {
        use MessageAction::*;
        let photo = AttachmentInfo { id: "a".into(), mime: "image/jpeg".into(), name: "p.jpg".into(), size: 1, width: None, height: None, duration_ms: None, thumb: vec![], poster: vec![], alt: String::new(), transcript: String::new(), downloaded: true, removed: false };
        let mut m = sent(true, 60.0);
        m.text = String::new();
        m.attachments = vec![photo.clone()];
        assert_eq!(message_actions(m.clone(), false, NOW), vec![React, Reply, Forward, Copy, Select, Delete]);
        m.attachments = vec![AttachmentInfo { mime: "image/gif".into(), ..photo }];
        assert!(message_actions(m, false, NOW).contains(&SaveGif));
    }

    #[test]
    fn the_quick_row_is_six_emoji() {
        assert_eq!(quick_reactions(), vec!["👍", "❤️", "😂", "😮", "😢", "🙏"]);
    }
}
