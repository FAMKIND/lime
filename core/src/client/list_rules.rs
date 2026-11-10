//! Chat list rules that lived only in Swift (LIME-305): when a chat counts as unread and how many, how long a mute lasts and when it ends, and the
//! list filters. Mirrors `Conversation.isUnread` / `unreadCount` (`ios/Lime/Model/Models.swift`), `MuteDuration` and `NotificationSettings.isMuted` /
//! `activeMutes` (`ios/Lime/Core/Notifications/NotificationSettings.swift`) and `ChatFilter` (`ios/Lime/Model/ListFilters.swift`).
//! Pure functions. Where a mute is *kept* is the app's choice (iOS: UserDefaults; Android: its private preferences): the core has no settings store.
//! iOS keeps its Swift until LIME-133b.

use crate::store::ConversationSummary;

// ---------------------------------------------------------------- unread

/// A chat is unread when something in it is unread or I marked it unread by hand.
#[uniffi::export]
pub fn conversation_is_unread(unread: u32, marked_unread: bool) -> bool {
    unread > 0 || marked_unread
}

/// The number on the unread badge: the unread messages, or 1 for a chat I marked unread.
#[uniffi::export]
pub fn conversation_unread_count(unread: u32, marked_unread: bool) -> u32 {
    unread.max(u32::from(marked_unread))
}

// ---------------------------------------------------------------- mute

/// How long a chat stays muted.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum MuteDuration {
    Hour,
    EightHours,
    Week,
    Always,
}

/// The words of a duration, as the iOS menu says them.
#[uniffi::export]
pub fn mute_duration_title(duration: MuteDuration) -> String {
    match duration {
        MuteDuration::Hour => "For 1 hour",
        MuteDuration::EightHours => "For 8 hours",
        MuteDuration::Week => "For 1 week",
        MuteDuration::Always => "Always",
    }
    .to_owned()
}

/// Every duration, in the order the menu lists them.
#[uniffi::export]
pub fn mute_durations() -> Vec<MuteDuration> {
    vec![MuteDuration::Hour, MuteDuration::EightHours, MuteDuration::Week, MuteDuration::Always]
}

/// When a mute started at `now_ms` ends (milliseconds); `Always` never does.
#[uniffi::export]
pub fn mute_end_ms(duration: MuteDuration, now_ms: i64) -> i64 {
    const HOUR: i64 = 3_600_000;
    match duration {
        MuteDuration::Hour => now_ms.saturating_add(HOUR),
        MuteDuration::EightHours => now_ms.saturating_add(8 * HOUR),
        MuteDuration::Week => now_ms.saturating_add(7 * 24 * HOUR),
        MuteDuration::Always => i64::MAX,
    }
}

/// A chat is muted while its mute has not ended (the end is after `now_ms`).
#[uniffi::export]
pub fn is_muted_until(until_ms: Option<i64>, now_ms: i64) -> bool {
    until_ms.is_some_and(|end| end > now_ms)
}

/// One chat's mute and when it ends.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct MuteEntry {
    pub conversation_id: String,
    pub until_ms: i64,
}

/// The mutes still on at `now_ms`, soonest end first ("Always" last); ended ones are left out.
#[uniffi::export]
pub fn active_mutes(muted: Vec<MuteEntry>, now_ms: i64) -> Vec<MuteEntry> {
    let mut on: Vec<MuteEntry> = muted.into_iter().filter(|m| m.until_ms > now_ms).collect();
    on.sort_by(|a, b| a.until_ms.cmp(&b.until_ms).then_with(|| a.conversation_id.cmp(&b.conversation_id)));
    on
}

// ---------------------------------------------------------------- filters

/// What kind of chat a filter keeps.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ChatKind {
    Direct,
    Group,
}

/// The filters on the list: what kind of chat, pinned, muted, a private label. All that are on apply together, and with the All | Unread segment.
#[derive(Debug, Clone, PartialEq, Eq, Default, uniffi::Record)]
pub struct ChatFilter {
    pub kind: Option<ChatKind>,
    pub pinned: bool,
    pub muted: bool,
    pub label: Option<String>,
}

/// How many filters are on (the number on the filter button).
#[uniffi::export]
pub fn chat_filter_active_count(filter: ChatFilter) -> u32 {
    u32::from(filter.kind.is_some()) + u32::from(filter.pinned) + u32::from(filter.muted) + u32::from(filter.label.is_some())
}

/// The chats that pass the filter (and the Unread segment when `unread_only`), in their order. `muted_ids` are the chats muted now.
#[uniffi::export]
pub fn chat_filter_apply(filter: ChatFilter, chats: Vec<ConversationSummary>, unread_only: bool, muted_ids: Vec<String>) -> Vec<ConversationSummary> {
    chats
        .into_iter()
        .filter(|chat| {
            if unread_only && !conversation_is_unread(chat.unread, chat.marked_unread) {
                return false;
            }
            match filter.kind {
                Some(ChatKind::Direct) if chat.is_group => return false,
                Some(ChatKind::Group) if !chat.is_group => return false,
                _ => {}
            }
            if filter.pinned && !chat.is_pinned {
                return false;
            }
            if filter.muted && !muted_ids.contains(&chat.id) {
                return false;
            }
            if let Some(label) = &filter.label {
                if chat.is_group || chat.members.first().and_then(|m| m.label.as_ref()) != Some(label) {
                    return false;
                }
            }
            true
        })
        .collect()
}

/// The private labels in use on direct chats, sorted.
#[uniffi::export]
pub fn chat_labels(chats: Vec<ConversationSummary>) -> Vec<String> {
    let mut labels: Vec<String> = chats
        .iter()
        .filter(|c| !c.is_group)
        .filter_map(|c| c.members.first().and_then(|m| m.label.clone()))
        .filter(|l| !l.is_empty())
        .collect();
    labels.sort();
    labels.dedup();
    labels
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::MemberInfo;

    fn person(id: &str, label: Option<&str>) -> MemberInfo {
        MemberInfo { id: id.into(), name: id.into(), initials: String::new(), tone: 0, label: label.map(Into::into), username: None }
    }

    fn chat(id: &str, group: bool, pinned: bool, unread: u32, label: Option<&str>) -> ConversationSummary {
        let mut members = vec![person(id, label)];
        if group {
            members.push(person(&format!("{id}2"), None));
        }
        ConversationSummary {
            activity_at: 0,
            last_reaction: None,
            id: id.into(),
            title: id.into(),
            is_group: group,
            is_pinned: pinned,
            unread,
            request_state: "accepted".into(),
            key_change_pending: false,
            last_message: None,
            members,
            group_emoji: None,
            verified: false,
            verified_at: None,
            group_ended: None,
            my_role: None,
            marked_unread: false,
            last_is_reply: false,
        }
    }

    // The same chats as ios/LimeTests/ListFilterTests.swift.
    fn chats() -> Vec<ConversationSummary> {
        vec![
            chat("a", false, true, 2, Some("Grade 4")),
            chat("b", false, false, 0, Some("Grade 5")),
            chat("g1", true, true, 0, None),
            chat("g2", true, false, 1, None),
            chat("c", false, false, 0, None),
        ]
    }

    fn ids(list: Vec<ConversationSummary>) -> Vec<String> {
        list.into_iter().map(|c| c.id).collect()
    }

    fn filter(f: ChatFilter, unread_only: bool, muted: &[&str]) -> Vec<String> {
        ids(chat_filter_apply(f, chats(), unread_only, muted.iter().map(|s| (*s).to_owned()).collect()))
    }

    #[test]
    fn each_filter_narrows_the_list_and_none_shows_everything() {
        assert_eq!(filter(ChatFilter::default(), false, &[]), ["a", "b", "g1", "g2", "c"]);
        assert_eq!(filter(ChatFilter { kind: Some(ChatKind::Direct), ..Default::default() }, false, &[]), ["a", "b", "c"]);
        assert_eq!(filter(ChatFilter { kind: Some(ChatKind::Group), ..Default::default() }, false, &[]), ["g1", "g2"]);
        assert_eq!(filter(ChatFilter { pinned: true, ..Default::default() }, false, &[]), ["a", "g1"]);
        assert_eq!(filter(ChatFilter { muted: true, ..Default::default() }, false, &["b", "g2"]), ["b", "g2"]);
        assert_eq!(filter(ChatFilter { label: Some("Grade 5".into()), ..Default::default() }, false, &[]), ["b"]);
        assert_eq!(filter(ChatFilter::default(), true, &[]), ["a", "g2"], "Unread = chats with something unread");
    }

    #[test]
    fn filters_combine_with_and_and_the_count_is_how_many_are_on() {
        let both = ChatFilter { kind: Some(ChatKind::Group), pinned: true, ..Default::default() };
        assert_eq!(filter(both.clone(), false, &[]), ["g1"], "Groups and Pinned: only pinned groups");
        assert_eq!(chat_filter_active_count(both), 2);
        assert_eq!(filter(ChatFilter { kind: Some(ChatKind::Direct), pinned: true, ..Default::default() }, true, &[]), ["a"], "with the Unread segment too");
        assert_eq!(chat_filter_active_count(ChatFilter { kind: Some(ChatKind::Direct), pinned: true, muted: true, label: Some("x".into()) }), 4);
        assert_eq!(chat_filter_active_count(ChatFilter::default()), 0);
    }

    #[test]
    fn labels_in_use_are_the_sorted_private_labels_of_direct_chats() {
        assert_eq!(chat_labels(chats()), ["Grade 4", "Grade 5"]);
        assert_eq!(chat_labels(vec![chat("x", false, false, 0, None)]), Vec::<String>::new());
    }

    // ios/LimeTests/NotificationTests.swift: testMuteDurationsEndAndAlwaysNeverDoes.
    #[test]
    fn mute_durations_end_and_always_never_does() {
        let now = 1_700_000_000_000;
        let until = |d| Some(mute_end_ms(d, now));
        assert!(is_muted_until(until(MuteDuration::Hour), now + 3_599_000));
        assert!(!is_muted_until(until(MuteDuration::Hour), now + 3_601_000), "1 hour is over");
        assert!(is_muted_until(until(MuteDuration::EightHours), now + 7 * 3_600_000));
        assert!(!is_muted_until(until(MuteDuration::EightHours), now + 8 * 3_600_000 + 1_000));
        assert!(is_muted_until(until(MuteDuration::Week), now + 6 * 86_400_000));
        assert!(!is_muted_until(until(MuteDuration::Week), now + 7 * 86_400_000 + 1_000));
        assert!(is_muted_until(until(MuteDuration::Always), now + 10 * 365 * 86_400_000));
        assert!(!is_muted_until(None, now));
        let entries = vec![
            MuteEntry { conversation_id: "d".into(), until_ms: mute_end_ms(MuteDuration::Always, now) },
            MuteEntry { conversation_id: "a".into(), until_ms: mute_end_ms(MuteDuration::Hour, now) },
            MuteEntry { conversation_id: "c".into(), until_ms: mute_end_ms(MuteDuration::Week, now) },
            MuteEntry { conversation_id: "b".into(), until_ms: mute_end_ms(MuteDuration::EightHours, now) },
        ];
        let order = |at| active_mutes(entries.clone(), at).into_iter().map(|m| m.conversation_id).collect::<Vec<_>>();
        assert_eq!(order(now + 3_601_000), ["b", "c", "d"], "soonest end first, always last");
        assert_eq!(order(now + 9 * 86_400_000), ["d"]);
    }

    #[test]
    fn the_duration_menu_and_its_words() {
        assert_eq!(mute_durations().into_iter().map(mute_duration_title).collect::<Vec<_>>(), ["For 1 hour", "For 8 hours", "For 1 week", "Always"]);
    }

    #[test]
    fn unread_is_something_unread_or_marked_and_the_badge_is_at_least_one_when_marked() {
        assert!(!conversation_is_unread(0, false));
        assert!(conversation_is_unread(3, false));
        assert!(conversation_is_unread(0, true));
        assert_eq!(conversation_unread_count(0, true), 1);
        assert_eq!(conversation_unread_count(4, true), 4);
        assert_eq!(conversation_unread_count(0, false), 0);
    }
}
