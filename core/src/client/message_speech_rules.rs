//! What a screen reader says for one message as one element (LIME-130-3a; LIME-400): "<Sender or You>, <text or kind>, <time>, <edited>, <delivery state>,
//! <reactions>, <replies>", and the words of a message's delivery state. Moved out of Android's `ChatRows.kt` (the Kotlin twins of `MessageSpeech` in
//! `ios/Lime/Features/Chat/MessageSpeech.swift` and of the delivery words of `DeliveryState` in `ios/Lime/Model/Models.swift`). Pure. iOS keeps its Swift until LIME-133b.

use crate::client::chat_words_rules::attachment_summary;
use crate::format::message_plain_text;
use crate::store::{AttachmentInfo, MessageItem};

/// The core's `local_state`, normalised: an unknown (older local-only) state counts as sent.
#[uniffi::export]
pub fn delivery_state_kind(local_state: String) -> String {
    const KNOWN: [&str; 9] = ["sending", "sent", "failed", "undelivered", "received", "waiting", "passed", "offline", "system"];
    if KNOWN.contains(&local_state.as_str()) { local_state } else { "sent".to_owned() }
}

/// Not sent to the server yet, and nothing wrong: the message is on its way by itself.
#[uniffi::export]
pub fn delivery_state_in_flight(local_state: String) -> bool {
    matches!(delivery_state_kind(local_state).as_str(), "sending" | "waiting" | "passed" | "offline")
}

/// The words under the bubble for the nearby-phone states (colour is never the only signal); none for the others.
#[uniffi::export]
pub fn delivery_state_status_words(local_state: String) -> Option<String> {
    match delivery_state_kind(local_state).as_str() {
        "waiting" => Some("Waiting for a phone nearby".to_owned()),
        "passed" => Some("Passed to a nearby phone".to_owned()),
        "offline" => Some("Waiting for internet".to_owned()),
        _ => None,
    }
}

/// The delivery state as words for a screen reader (none when it says nothing).
#[uniffi::export]
pub fn delivery_state_spoken(local_state: String) -> Option<String> {
    match delivery_state_kind(local_state.clone()).as_str() {
        "sending" => Some("sending".to_owned()),
        "sent" => Some("sent".to_owned()),
        "failed" => Some("not sent, retry available".to_owned()),
        "undelivered" => Some("not delivered, resend available".to_owned()),
        "waiting" | "passed" | "offline" => delivery_state_status_words(local_state).map(|w| w.to_lowercase()),
        _ => None,
    }
}

/// "Photo", "3 photos", "Voice message", "File: report.pdf" … for a message's attachments.
fn attachments_words(items: &[AttachmentInfo]) -> String {
    let images: Vec<&AttachmentInfo> = items.iter().filter(|a| a.mime.starts_with("image/")).collect();
    let mut out: Vec<String> = Vec::new();
    if images.len() == 1 {
        out.push(if images[0].mime == "image/gif" {
            "GIF".to_owned()
        } else if !images[0].alt.is_empty() {
            format!("Photo: {}", images[0].alt)
        } else {
            "Photo".to_owned()
        });
    } else if images.len() > 1 {
        out.push(format!("{} photos", images.len()));
    }
    for item in items.iter().filter(|a| !a.mime.starts_with("image/")) {
        out.push(if item.mime.starts_with("audio/") {
            "Voice message".to_owned()
        } else if item.mime.starts_with("video/") {
            "Video".to_owned()
        } else if item.name.is_empty() {
            "File".to_owned()
        } else {
            format!("File: {}", item.name)
        });
    }
    out.join(", ")
}

/// "Photo", "Photo: <description>", "3 photos", "Voice message", "File: report.pdf" … for a message's attachments only (a photo reads with its description).
#[uniffi::export]
pub fn message_speech_attachments(message: MessageItem) -> String {
    attachments_words(&message.attachments)
}

/// The words of the message, or what kind of thing it is.
#[uniffi::export]
pub fn message_speech_body(message: MessageItem) -> String {
    if message.deleted {
        return "This message was deleted".to_owned();
    }
    if message.emergency.is_some() {
        return "Emergency status".to_owned();
    }
    let mut pieces: Vec<String> = Vec::new();
    if message.forwarded {
        pieces.push("Forwarded".to_owned());
    }
    let text = message_plain_text(message.text.clone());
    if !text.is_empty() {
        pieces.push(text);
    }
    if !message.attachments.is_empty() {
        pieces.push(attachments_words(&message.attachments));
    }
    if let Some(preview) = &message.link_preview {
        pieces.push(format!("Link: {}", preview.title));
    }
    if pieces.is_empty() { "Message".to_owned() } else { pieces.join(", ") }
}

/// What a screen reader says for one message as one element. `sender_name` is the other person's name (none for my own messages, who read as "You");
/// `clock` is the message's time as the phone writes it ("9:05 AM").
#[uniffi::export]
pub fn message_speech_label(message: MessageItem, sender_name: Option<String>, reply_count: u32, unreplied: u32, clock: String) -> String {
    let own = message.sender_id.is_none();
    let mut parts = vec![if own { "You".to_owned() } else { sender_name.unwrap_or_else(|| "Someone".to_owned()) }];
    parts.push(message_speech_body(message.clone()));
    if !message.deleted {
        parts.push(clock);
        if message.edited {
            parts.push("edited".to_owned());
        }
        if own {
            if let Some(words) = delivery_state_spoken(message.local_state.clone()) {
                parts.push(words);
            }
        }
        if !message.reactions.is_empty() {
            let total: u32 = message.reactions.iter().map(|r| r.count).sum();
            let list: Vec<String> = message.reactions.iter().map(|r| format!("{} {}{}", r.emoji, r.count, if r.mine { " (you)" } else { "" })).collect();
            parts.push(format!("{total} {}: {}", if total == 1 { "reaction" } else { "reactions" }, list.join(", ")));
        }
        if reply_count > 0 {
            let unread = if unreplied > 0 { format!(", {unreplied} unread") } else { String::new() };
            parts.push(format!("{reply_count} {}{unread}", if reply_count == 1 { "reply" } else { "replies" }));
        }
    }
    parts.join(", ")
}

/// The words of a message that is only attachments for a list row or a notification (the same rule as `attachment_summary`).
#[uniffi::export]
pub fn message_attachment_gist(message: MessageItem) -> Option<String> {
    attachment_summary(message.attachments)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::message_ops::Reaction;

    fn message(id: &str, text: &str, from: Option<&str>, state: &str) -> MessageItem {
        MessageItem {
            id: id.into(),
            conversation_id: "dm:x".into(),
            sender_id: from.map(Into::into),
            text: text.into(),
            sent_at: 1_000,
            local_state: state.into(),
            attachments: vec![],
            edited: false,
            deleted: false,
            reactions: vec![],
            forwarded: false,
            link_preview: None,
            thread_root: None,
            emergency: None,
        }
    }

    fn photo() -> AttachmentInfo {
        AttachmentInfo { id: "a".into(), mime: "image/jpeg".into(), name: String::new(), size: 1, width: None, height: None, duration_ms: None, thumb: vec![], poster: vec![], alt: String::new(), transcript: String::new(), downloaded: true, removed: false }
    }

    fn label(m: MessageItem, who: Option<&str>) -> String {
        message_speech_label(m, who.map(Into::into), 0, 0, "9:05 AM".into())
    }

    // ChatRowsTest.deliveryStatesMapFromTheCoresWords.
    #[test]
    fn delivery_states_map_from_the_cores_words() {
        assert_eq!(delivery_state_kind("sending".into()), "sending");
        assert_eq!(delivery_state_kind("local".into()), "sent", "the older local-only states count as sent");
        assert!(delivery_state_in_flight("offline".into()));
        assert!(!delivery_state_in_flight("failed".into()));
        assert_eq!(delivery_state_status_words("offline".into()).as_deref(), Some("Waiting for internet"));
        assert_eq!(delivery_state_status_words("sent".into()), None);
    }

    // ChatRowsTest.talkBackReadsOneStopPerMessage (the cases of iOS's MessageSpeech).
    #[test]
    fn talkback_reads_one_stop_per_message() {
        assert_eq!(label(message("1", "Hello there", Some("ben"), "received"), Some("Ben Android")), "Ben Android, Hello there, 9:05 AM");
        assert_eq!(label(message("2", "Hi", None, "sending"), None), "You, Hi, 9:05 AM, sending");
        assert_eq!(label(message("3", "Hi", None, "failed"), None), "You, Hi, 9:05 AM, not sent, retry available");
        let mut deleted = message("4", "x", Some("ben"), "received");
        deleted.deleted = true;
        assert_eq!(label(deleted, Some("Ben")), "Ben, This message was deleted");
        let mut photo_only = message("5", "", Some("x"), "received");
        photo_only.attachments = vec![photo()];
        assert_eq!(label(photo_only, None), "Someone, Photo, 9:05 AM");
        assert_eq!(message_speech_label(message("6", "Hello", Some("ben"), "received"), Some("Ben".into()), 2, 1, "9:05 AM".into()), "Ben, Hello, 9:05 AM, 2 replies, 1 unread");
        let mut reacted = message("7", "Hello", Some("ben"), "received");
        reacted.reactions = vec![Reaction { emoji: "❤️".into(), person_ids: Vec::new(), count: 2, mine: true, people: vec![] }];
        assert_eq!(label(reacted, Some("Ben")), "Ben, Hello, 9:05 AM, 2 reactions: ❤️ 2 (you)");
        let mut edited = message("8", "Hello", Some("ben"), "received");
        edited.edited = true;
        assert_eq!(label(edited, Some("Ben")), "Ben, Hello, 9:05 AM, edited");
    }

    #[test]
    fn the_kinds_of_attachment_are_named_and_the_nearby_states_are_lowercased() {
        let mut m = message("1", "", None, "waiting");
        let mut gif = photo();
        gif.mime = "image/gif".into();
        let mut described = photo();
        described.alt = "A green circle".into();
        m.attachments = vec![gif];
        assert_eq!(label(m.clone(), None), "You, GIF, 9:05 AM, waiting for a phone nearby");
        m.attachments = vec![described];
        assert_eq!(message_speech_body(m.clone()), "Photo: A green circle");
        m.attachments = vec![photo(), photo(), AttachmentInfo { mime: "application/pdf".into(), name: "Plan.pdf".into(), ..photo() }];
        assert_eq!(message_speech_body(m.clone()), "2 photos, File: Plan.pdf");
        m.attachments = vec![AttachmentInfo { mime: "audio/mp4".into(), ..photo() }];
        assert_eq!(message_speech_body(m), "Voice message");
        assert_eq!(message_speech_body(message("2", "", Some("x"), "received")), "Message");
        let mut twin = message("4", "", Some("x"), "received");
        twin.attachments = vec![AttachmentInfo { alt: "Students building a bridge".into(), ..photo() }];
        assert_eq!(message_speech_attachments(twin.clone()), "Photo: Students building a bridge");
        twin.attachments = vec![photo(), AttachmentInfo { mime: "image/png".into(), ..photo() }];
        assert_eq!(message_speech_attachments(twin), "2 photos");
        let mut forwarded = message("3", "Hi", Some("x"), "received");
        forwarded.forwarded = true;
        assert_eq!(message_speech_body(forwarded), "Forwarded, Hi");
    }
}
