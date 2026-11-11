//! Which new message gets a banner while the app is open (LIME-400): the presentation half of `NotificationPolicy` and its `ArrivalDetector`
//! (`ios/Lime/Core/Notifications/NotificationPolicy.swift`), moved out of Android's `ArrivalBanner.kt`. The words themselves are `notification_words`
//! (`settings_rules.rs`). The first look only learns what is already there, so opening the app never announces old history. Pure: the app keeps the state
//! between looks and gives it back. iOS keeps its Swift until LIME-133b.

use crate::client::settings_rules::{notification_words, IncomingWords, NotificationPreview};
use crate::format::message_plain_text;
use crate::store::ConversationSummary;

/// What the detector has seen so far.
#[derive(Debug, Clone, PartialEq, Eq, Default, uniffi::Record)]
pub struct ArrivalState {
    pub primed: bool,
    pub seen: Vec<String>,
}

/// A banner to show and where tapping it goes.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct BannerPick {
    pub conversation_id: String,
    pub title: String,
    pub body: String,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ArrivalResult {
    pub pick: Option<BannerPick>,
    pub state: ArrivalState,
}

/// Looks at the chats after a read. A banner is for the newest new message from someone else, unless notifications are off, the chat is muted, or it is the chat on
/// screen (`viewing`: it only ticks). `hide_text` (the lock hides it) counts as No preview; a request never shows its words.
#[uniffi::export]
pub fn arrival_check(
    conversations: Vec<ConversationSummary>,
    state: ArrivalState,
    enabled: bool,
    preview: NotificationPreview,
    muted_ids: Vec<String>,
    hide_text: bool,
    viewing: Option<String>,
) -> ArrivalResult {
    let newest: Vec<(&ConversationSummary, &crate::store::MessageItem)> = conversations
        .iter()
        .filter_map(|c| c.last_message.as_ref().filter(|m| m.sender_id.is_some() && m.local_state != "system" && !m.deleted).map(|m| (c, m)))
        .collect();
    let fresh: Vec<&(&ConversationSummary, &crate::store::MessageItem)> = if state.primed { newest.iter().filter(|(_, m)| !state.seen.contains(&m.id)).collect() } else { Vec::new() };
    let mut seen = state.seen.clone();
    for (_, m) in &newest {
        if !seen.contains(&m.id) {
            seen.push(m.id.clone());
        }
    }
    let next = ArrivalState { primed: true, seen };
    let Some((chat, message)) = fresh.into_iter().max_by_key(|(_, m)| m.sent_at).map(|p| (p.0, p.1)) else {
        return ArrivalResult { pick: None, state: next };
    };
    if !enabled || muted_ids.contains(&chat.id) || viewing.as_deref() == Some(chat.id.as_str()) {
        return ArrivalResult { pick: None, state: next };
    }
    let sender = chat.members.iter().find(|m| Some(&m.id) == message.sender_id.as_ref()).map(|m| m.name.clone()).unwrap_or_else(|| chat.title.clone());
    let words = notification_words(
        IncomingWords {
            conversation_title: chat.title.clone(),
            sender_name: sender,
            text: message_plain_text(message.text.clone()),
            is_reply: message.thread_root.is_some(),
            is_group: chat.is_group,
            is_request: chat.request_state == "pending",
        },
        preview,
        hide_text,
    );
    ArrivalResult { pick: Some(BannerPick { conversation_id: chat.id.clone(), title: words.title, body: words.body }), state: next }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::{MemberInfo, MessageItem};

    fn message(id: &str, text: &str, from: Option<&str>, at: i64) -> MessageItem {
        MessageItem {
            id: id.into(),
            conversation_id: "dm:lee".into(),
            sender_id: from.map(Into::into),
            text: text.into(),
            sent_at: at,
            local_state: "received".into(),
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

    fn summary(id: &str, title: &str, request: bool, last: MessageItem) -> ConversationSummary {
        ConversationSummary {
            activity_at: 0,
            last_reaction: None,
            id: id.into(),
            title: title.into(),
            is_group: false,
            is_pinned: false,
            unread: 0,
            request_state: if request { "pending" } else { "accepted" }.into(),
            key_change_pending: false,
            last_message: Some(last),
            members: vec![MemberInfo { id: "lee".into(), name: "Lee Wong".into(), initials: "LW".into(), tone: 0, label: None, username: None }],
            group_emoji: None,
            verified: false,
            verified_at: None,
            group_ended: None,
            my_role: None,
            marked_unread: false,
            last_is_reply: false,
        }
    }

    struct Setup {
        enabled: bool,
        preview: NotificationPreview,
        muted: Vec<String>,
        hide: bool,
        viewing: Option<String>,
    }

    fn look(chats: Vec<ConversationSummary>, state: ArrivalState, s: &Setup) -> ArrivalResult {
        arrival_check(chats, state, s.enabled, s.preview, s.muted.clone(), s.hide, s.viewing.clone())
    }

    fn setup() -> Setup {
        Setup { enabled: true, preview: NotificationPreview::NameAndMessage, muted: vec![], hide: false, viewing: None }
    }

    // NotificationTests.testTheFirstLookOnlyLearnsAndLaterLooksFindWhatIsNew + AccountSettingsUiTest's banner cases.
    #[test]
    fn the_first_look_only_learns_and_later_looks_find_what_is_new() {
        let s = setup();
        let first = look(vec![summary("dm:lee", "Lee Wong", false, message("m1", "old", Some("lee"), 1_000))], ArrivalState::default(), &s);
        assert_eq!(first.pick, None, "opening the app announces no history");
        assert!(first.state.primed);
        let fresh = look(vec![summary("dm:lee", "Lee Wong", false, message("m2", "Can we plan the lesson?", Some("lee"), 2_000))], first.state.clone(), &s);
        let pick = fresh.pick.clone().unwrap();
        assert_eq!((pick.conversation_id.as_str(), pick.title.as_str(), pick.body.as_str()), ("dm:lee", "Lee Wong", "Can we plan the lesson?"));
        let again = look(vec![summary("dm:lee", "Lee Wong", false, message("m2", "Can we plan the lesson?", Some("lee"), 2_000))], fresh.state, &s);
        assert_eq!(again.pick, None, "announced once");
    }

    #[test]
    fn the_lock_the_preview_and_the_screen_decide_what_it_says_or_that_it_stays_quiet() {
        let primed = ArrivalState { primed: true, seen: vec!["m1".into()] };
        let chat = |id: &str, text: &str, at: i64| vec![summary("dm:lee", "Lee Wong", false, message(id, text, Some("lee"), at))];
        let mut s = setup();
        s.hide = true;
        let hidden = look(chat("m3", "secret", 3_000), primed.clone(), &s).pick.unwrap();
        assert_eq!((hidden.title.as_str(), hidden.body.as_str()), ("lime", "New message"));
        s.hide = false;
        s.preview = NotificationPreview::NameOnly;
        let name_only = look(chat("m4", "secret", 4_000), primed.clone(), &s).pick.unwrap();
        assert_eq!((name_only.title.as_str(), name_only.body.as_str()), ("Lee Wong", "New message"));
        s.preview = NotificationPreview::NameAndMessage;
        s.viewing = Some("dm:lee".into());
        assert_eq!(look(chat("m5", "x", 5_000), primed.clone(), &s).pick, None, "the chat on screen only ticks");
        s.viewing = None;
        s.muted = vec!["dm:lee".into()];
        assert_eq!(look(chat("m6", "x", 6_000), primed.clone(), &s).pick, None, "a muted chat is silent");
        s.muted = vec![];
        s.enabled = false;
        assert_eq!(look(chat("m7", "x", 7_000), primed.clone(), &s).pick, None, "notifications off");
        s.enabled = true;
        let request = look(vec![summary("dm:new", "Someone", true, message("m8", "secret words", Some("lee"), 8_000))], primed.clone(), &s).pick.unwrap();
        assert_eq!(request.body, "Wants to message you", "a request never shows its words");
        let mine = look(vec![summary("dm:lee", "Lee Wong", false, message("m9", "mine", None, 9_000))], primed, &s);
        assert_eq!(mine.pick, None, "my own messages never announce");
    }
}
