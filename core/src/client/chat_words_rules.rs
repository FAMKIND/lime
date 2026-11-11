//! The words of the Messages list and the chat that lived only in Swift (LIME-400): what a message that is only attachments says, the symbol of a list preview,
//! the whole list-row preview, the offline banner, the badge and a person's avatar colour. Moved out of Android's `ChatFormat.kt` (the Kotlin twins of
//! `AttachmentFormat` and `AvatarTone` in `ios/Lime/Model/Models.swift` + `ios/Lime/Features/Attachments/AttachmentModels.swift`, `ListPreview` in
//! `ios/Lime/Features/Messages/MessagesView.swift`, `OfflineCopy`). Pure functions of values the core already returns. iOS keeps its Swift until LIME-133b.

use crate::client::attachment_rules::voice_clock;
use crate::format::message_plain_text;
use crate::store::{AttachmentInfo, ConversationSummary, MessageItem};

/// The one place a person's avatar colour is worked out: from their user id (`hash = hash * 31 + byte` over the id's UTF-8, as a UInt32, mod 8), the same rule
/// the core uses when it names a conversation's people.
#[uniffi::export]
pub fn avatar_tone_of(id: String) -> u32 {
    let mut hash: u32 = 0;
    for byte in id.as_bytes() {
        hash = hash.wrapping_mul(31).wrapping_add(u32::from(*byte));
    }
    hash % 8
}

/// The small symbol of a list row's preview of attachments.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum AttachmentSymbol {
    Camera,
    Video,
    Mic,
    Document,
    Paperclip,
}

fn is_image(a: &AttachmentInfo) -> bool {
    a.mime.starts_with("image/")
}

/// What a chat list or a notification says for a message that is only attachments: "Photo", "3 Photos", "Video", "Voice message (0:12)", the file's name,
/// "File", or "3 attachments".
#[uniffi::export]
pub fn attachment_summary(items: Vec<AttachmentInfo>) -> Option<String> {
    let first = items.first()?;
    if items.iter().all(is_image) {
        return Some(if items.len() == 1 { "Photo".to_owned() } else { format!("{} Photos", items.len()) });
    }
    if items.len() == 1 {
        return Some(if first.mime.starts_with("video/") {
            "Video".to_owned()
        } else if first.mime.starts_with("audio/") {
            match first.duration_ms {
                Some(ms) => format!("Voice message ({})", voice_clock(f64::from(ms) / 1000.0)),
                None => "Voice message".to_owned(),
            }
        } else if first.name.is_empty() {
            "File".to_owned()
        } else {
            first.name.clone()
        });
    }
    Some(format!("{} attachments", items.len()))
}

/// The symbol for the attachments of a message (none when there are none).
#[uniffi::export]
pub fn attachment_symbol(items: Vec<AttachmentInfo>) -> Option<AttachmentSymbol> {
    let first = items.first()?;
    if items.len() > 1 && !items.iter().all(is_image) {
        return Some(AttachmentSymbol::Paperclip);
    }
    Some(if is_image(first) {
        AttachmentSymbol::Camera
    } else if first.mime.starts_with("video/") {
        AttachmentSymbol::Video
    } else if first.mime.starts_with("audio/") {
        AttachmentSymbol::Mic
    } else {
        AttachmentSymbol::Document
    })
}

/// The offline banner on Messages and what it promises (LIME-142).
#[uniffi::export]
pub fn offline_banner_words(mesh_on: bool) -> String {
    if mesh_on { "Offline · sending through nearby phones" } else { "Offline · will send when you’re online" }.to_owned()
}

/// The title of the offline sheet.
#[uniffi::export]
pub fn offline_sheet_title() -> String {
    "No internet".to_owned()
}

/// An unread count: "99+" past 99.
#[uniffi::export]
pub fn badge_words(count: u32) -> String {
    if count > 99 { "99+".to_owned() } else { count.to_string() }
}

/// What a row of the Messages list says about the newest thing in a conversation (a reply included), in parts so it can be drawn with a small symbol.
#[derive(Debug, Clone, PartialEq, Eq, Default, uniffi::Record)]
pub struct ListPreviewParts {
    /// "Jean: " (a group message, or a reply in a group), "You: " (mine in a reply or a group), or nothing.
    pub prefix: String,
    pub symbol: Option<AttachmentSymbol>,
    pub text: String,
    /// For reply activity: what it answers, "Reply to Jean · Who can cover recess duty?" (shown above the reply, with a quote bar).
    pub quote: Option<String>,
    pub is_reaction: bool,
}

fn first_name(name: &str) -> String {
    name.split_whitespace().next().unwrap_or("").to_owned()
}

fn name_of(message: &MessageItem, conversation: &ConversationSummary) -> Option<String> {
    match &message.sender_id {
        None => Some("You".to_owned()),
        Some(id) => conversation.members.iter().find(|m| &m.id == id).map(|m| first_name(&m.name)),
    }
}

fn gist(message: &MessageItem) -> String {
    if message.deleted {
        return "This message was deleted".to_owned();
    }
    let words = message_plain_text(message.text.clone()).replace('\n', " ");
    let words = words.trim();
    if !words.is_empty() {
        return words.to_owned();
    }
    attachment_summary(message.attachments.clone()).unwrap_or_default()
}

/// The preview of a conversation's row. `root` is the message the newest reply answers (the app looks it up when `last_is_reply`).
#[uniffi::export]
pub fn list_preview_parts(conversation: ConversationSummary, root: Option<MessageItem>) -> ListPreviewParts {
    // A reaction newer than the last message is the newest thing: "Jean reacted ❤️ to “True that”".
    if let Some(reaction) = &conversation.last_reaction {
        let who = if reaction.reactor_id.is_none() { "You".to_owned() } else { first_name(&reaction.reactor_name) };
        let gist = reaction.text.trim();
        let tail = if gist.is_empty() { "a message".to_owned() } else { format!("“{gist}”") };
        return ListPreviewParts { text: format!("{who} reacted {} to {tail}", reaction.emoji), is_reaction: true, ..Default::default() };
    }
    let Some(last) = &conversation.last_message else { return ListPreviewParts::default() };
    if last.local_state == "system" {
        return ListPreviewParts { text: last.text.clone(), ..Default::default() };
    }
    if last.deleted {
        return ListPreviewParts { text: "This message was deleted".to_owned(), ..Default::default() };
    }
    let mut prefix = String::new();
    let mut quote = None;
    let sender = name_of(last, &conversation);
    if conversation.last_is_reply {
        // Reply activity reads like a quote: what it answers, then the reply.
        let author = root.as_ref().and_then(|r| name_of(r, &conversation));
        quote = Some(match (&root, author) {
            (Some(r), Some(author)) => {
                let gist = gist(r);
                let who = if author == "You" { "you".to_owned() } else { author };
                if gist.is_empty() { format!("Reply to {who}") } else { format!("Reply to {who} · {gist}") }
            }
            _ => "Reply in a thread".to_owned(),
        });
        if (last.sender_id.is_none() || conversation.is_group) && sender.is_some() {
            prefix = format!("{}: ", sender.clone().unwrap_or_default());
        }
    } else if conversation.is_group && last.sender_id.is_some() && sender.is_some() {
        prefix = format!("{}: ", sender.clone().unwrap_or_default());
    }
    // The words, without the markup (a list reads as its items).
    let words = message_plain_text(last.text.clone()).replace('\n', " ");
    match attachment_summary(last.attachments.clone()) {
        Some(summary) => {
            let text = if words.is_empty() { summary } else { format!("{summary} · {words}") };
            ListPreviewParts { prefix, symbol: attachment_symbol(last.attachments.clone()), text, quote, is_reaction: false }
        }
        None => ListPreviewParts { prefix, symbol: None, text: words, quote, is_reaction: false },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::message_ops::ReactionActivity;
    use crate::store::MemberInfo;

    fn attachment(mime: &str, name: &str, duration_ms: Option<u32>) -> AttachmentInfo {
        AttachmentInfo { id: "a".into(), mime: mime.into(), name: name.into(), size: 1, width: None, height: None, duration_ms, thumb: vec![], poster: vec![], alt: String::new(), transcript: String::new(), downloaded: true, removed: false }
    }

    fn message(id: &str, text: &str, from: Option<&str>) -> MessageItem {
        MessageItem {
            id: id.into(),
            conversation_id: "dm:x".into(),
            sender_id: from.map(Into::into),
            text: text.into(),
            sent_at: 1_000,
            local_state: "sent".into(),
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

    fn member(id: &str, name: &str) -> MemberInfo {
        MemberInfo { id: id.into(), name: name.into(), initials: String::new(), tone: 0, label: None, username: None }
    }

    fn conversation(group: bool, members: Vec<MemberInfo>, last: Option<MessageItem>) -> ConversationSummary {
        ConversationSummary {
            activity_at: 0,
            last_reaction: None,
            id: "c".into(),
            title: "T".into(),
            is_group: group,
            is_pinned: false,
            unread: 0,
            request_state: "accepted".into(),
            key_change_pending: false,
            last_message: last,
            members: if members.is_empty() { vec![member("ben", "Ben Android")] } else { members },
            group_emoji: None,
            verified: false,
            verified_at: None,
            group_ended: None,
            my_role: None,
            marked_unread: false,
            last_is_reply: false,
        }
    }

    // ChatFormatTest.attachmentSummaries (the cases of iOS's AttachmentFormat).
    #[test]
    fn attachment_summaries() {
        let photo = attachment("image/jpeg", "", None);
        assert_eq!(attachment_summary(vec![]), None);
        assert_eq!(attachment_summary(vec![photo.clone()]).as_deref(), Some("Photo"));
        assert_eq!(attachment_summary(vec![photo.clone(), photo.clone(), photo.clone()]).as_deref(), Some("3 Photos"));
        assert_eq!(attachment_summary(vec![attachment("video/mp4", "", None)]).as_deref(), Some("Video"));
        assert_eq!(attachment_summary(vec![attachment("audio/mp4", "", Some(12_400))]).as_deref(), Some("Voice message (0:12)"));
        assert_eq!(attachment_summary(vec![attachment("audio/mp4", "", None)]).as_deref(), Some("Voice message"));
        assert_eq!(attachment_summary(vec![attachment("application/pdf", "Plan.pdf", None)]).as_deref(), Some("Plan.pdf"));
        assert_eq!(attachment_summary(vec![attachment("application/pdf", "", None)]).as_deref(), Some("File"));
        assert_eq!(attachment_summary(vec![photo.clone(), attachment("video/mp4", "", None)]).as_deref(), Some("2 attachments"));
        assert_eq!(attachment_symbol(vec![photo.clone()]), Some(AttachmentSymbol::Camera));
        assert_eq!(attachment_symbol(vec![photo, attachment("video/mp4", "", None)]), Some(AttachmentSymbol::Paperclip));
        assert_eq!(attachment_symbol(vec![attachment("audio/mp4", "", None)]), Some(AttachmentSymbol::Mic));
        assert_eq!(attachment_symbol(vec![attachment("application/pdf", "", None)]), Some(AttachmentSymbol::Document));
        assert_eq!(attachment_symbol(vec![]), None);
    }

    #[test]
    fn a_plain_message_is_its_words_and_a_group_names_the_sender_by_first_name() {
        let c = conversation(false, vec![], Some(message("1", "See you **Friday**", Some("ben"))));
        assert_eq!(list_preview_parts(c, None).text, "See you Friday");
        let g = conversation(true, vec![member("jean", "Jean Park")], Some(message("1", "Hello", Some("jean"))));
        let p = list_preview_parts(g, None);
        assert_eq!(format!("{}{}", p.prefix, p.text), "Jean: Hello");
        let mine = conversation(true, vec![member("jean", "Jean Park")], Some(message("2", "Hi all", None)));
        let p = list_preview_parts(mine, None);
        assert_eq!(format!("{}{}", p.prefix, p.text), "Hi all", "my own plain message in a group has no prefix");
    }

    #[test]
    fn deleted_and_system_messages() {
        let mut deleted = message("1", "x", Some("ben"));
        deleted.deleted = true;
        assert_eq!(list_preview_parts(conversation(false, vec![], Some(deleted)), None).text, "This message was deleted");
        let mut system = message("1", "Jean added Lee", None);
        system.local_state = "system".into();
        assert_eq!(list_preview_parts(conversation(false, vec![], Some(system)), None).text, "Jean added Lee");
    }

    #[test]
    fn attachments_show_their_summary_then_the_words() {
        let mut m = message("1", "Look", Some("ben"));
        m.attachments = vec![attachment("image/jpeg", "", None)];
        let p = list_preview_parts(conversation(false, vec![], Some(m)), None);
        assert_eq!((p.text.as_str(), p.symbol), ("Photo · Look", Some(AttachmentSymbol::Camera)));
        let mut only = message("2", "", Some("ben"));
        only.attachments = vec![attachment("image/jpeg", "", None), attachment("image/png", "", None)];
        assert_eq!(list_preview_parts(conversation(false, vec![], Some(only)), None).text, "2 Photos");
    }

    #[test]
    fn a_reply_reads_like_a_quote() {
        let root = message("root", "Who can cover recess duty?", Some("ben"));
        let mut reply = message("r1", "I can", None);
        reply.thread_root = Some("root".into());
        let mut c = conversation(false, vec![], Some(reply));
        c.last_is_reply = true;
        let p = list_preview_parts(c.clone(), Some(root));
        assert_eq!(p.quote.as_deref(), Some("Reply to Ben · Who can cover recess duty?"));
        assert_eq!(format!("{}{}", p.prefix, p.text), "You: I can");
        assert_eq!(list_preview_parts(c, None).quote.as_deref(), Some("Reply in a thread"));
    }

    #[test]
    fn a_reaction_newer_than_the_last_message() {
        let theirs = ReactionActivity { emoji: "❤️".into(), reactor_id: Some("ben".into()), reactor_name: "Ben Android".into(), message_id: "m1".into(), text: "True that".into(), at: 5 };
        let mut c = conversation(false, vec![], Some(message("m1", "True that", Some("ben"))));
        c.last_reaction = Some(theirs);
        assert_eq!(list_preview_parts(c, None).text, "Ben reacted ❤️ to “True that”");
        let mine = ReactionActivity { emoji: "👍".into(), reactor_id: None, reactor_name: "Ada".into(), message_id: "m1".into(), text: String::new(), at: 5 };
        let mut c = conversation(false, vec![], None);
        c.last_reaction = Some(mine);
        let p = list_preview_parts(c, None);
        assert_eq!(p.text, "You reacted 👍 to a message");
        assert!(p.is_reaction);
    }

    #[test]
    fn no_messages_is_an_empty_preview() {
        assert_eq!(list_preview_parts(conversation(false, vec![], None), None), ListPreviewParts::default());
    }

    // ChatFormatTest.avatarToneIsTheSameOnEveryPhone.
    #[test]
    fn avatar_tone_is_the_same_on_every_phone() {
        assert_eq!(avatar_tone_of(String::new()), 0);
        assert_eq!(avatar_tone_of("a".into()), 97 % 8);
        assert_eq!(avatar_tone_of("ab".into()), (97 * 31 + 98) % 8);
        let long = "df2546ac-69d5-4074-8ff8-7c5125976a17";
        let mut h: u32 = 0;
        for b in long.bytes() {
            h = h.wrapping_mul(31).wrapping_add(u32::from(b));
        }
        assert_eq!(avatar_tone_of(long.into()), h % 8);
    }

    #[test]
    fn the_offline_words_and_the_badge() {
        assert_eq!(offline_banner_words(true), "Offline · sending through nearby phones");
        assert_eq!(offline_banner_words(false), "Offline · will send when you’re online");
        assert_eq!(offline_sheet_title(), "No internet");
        assert_eq!(badge_words(7), "7");
        assert_eq!(badge_words(99), "99");
        assert_eq!(badge_words(100), "99+");
    }
}
