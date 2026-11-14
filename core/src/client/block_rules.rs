//! Person-wide block (LIME-329): the pure rules both apps use to treat a blocked person the same everywhere. The store side is `LimeStore::block_person`,
//! `is_blocked` and `blocked_ids` (`store/mod.rs`): a person is blocked by a hidden `dm:<id>` conversation in state `blocked`, whether or not you ever chatted, so
//! the Blocked list, Unblock and the key rotation all work from the one place. What a blocked person sends to a group, a jam post or a reaction is **stored as
//! before** (Unblock brings it back, "Show" can reveal it); the apps only mark it with these rules, given `blocked_ids()`.

use crate::store::message_ops::Reaction;
use crate::store::MessageItem;

/// What something from a person is, for the notification rule.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum NotifyKind {
    DirectMessage,
    GroupMessage,
    Reaction,
    Mention,
    JamComment,
    JamReply,
}

/// Is this sender one of the blocked people? (`sender_id` is a user id, as in `MessageItem.sender_id`, `JamCommentInfo.author`.)
#[uniffi::export]
pub fn from_blocked(sender_id: String, blocked_ids: Vec<String>) -> bool {
    !sender_id.is_empty() && blocked_ids.iter().any(|b| *b == sender_id)
}

/// Is this message from a blocked person? (Mine and system lines have no sender here: never.)
#[uniffi::export]
pub fn message_from_blocked(message: MessageItem, blocked_ids: Vec<String>) -> bool {
    message.sender_id.is_some_and(|sender| from_blocked(sender, blocked_ids))
}

/// The reactions without the blocked people's: not in the faces, not in the count, and an emoji only they used is gone. (Mine is never dropped.)
#[uniffi::export]
pub fn visible_reactions(reactions: Vec<Reaction>, blocked_ids: Vec<String>) -> Vec<Reaction> {
    reactions
        .into_iter()
        .filter_map(|reaction| {
            let mut people = Vec::new();
            let mut person_ids = Vec::new();
            for (index, id) in reaction.person_ids.iter().enumerate() {
                if from_blocked(id.clone(), blocked_ids.clone()) {
                    continue;
                }
                person_ids.push(id.clone());
                if let Some(name) = reaction.people.get(index) {
                    people.push(name.clone());
                }
            }
            // A reaction built without ids (an older caller) cannot be filtered: it is kept as it is.
            if reaction.person_ids.is_empty() {
                return Some(reaction);
            }
            (!person_ids.is_empty()).then(|| Reaction { count: person_ids.len() as u32, people, person_ids, ..reaction })
        })
        .collect()
}

/// Should this get a banner, a badge or a sound? Never for anything from a blocked person, whatever it is (a group message, a reaction, a mention, a jam comment
/// or reply, a direct message). The apps call it where they decide to notify.
#[uniffi::export]
pub fn should_notify(sender_id: String, kind: NotifyKind, blocked_ids: Vec<String>) -> bool {
    let _ = kind; // the rule is the same for every kind; the kind is kept so a later rule can differ
    !from_blocked(sender_id, blocked_ids)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn blocked() -> Vec<String> {
        vec!["cleo".to_owned()]
    }

    fn reaction(emoji: &str, who: &[(&str, &str)], mine: bool) -> Reaction {
        Reaction {
            emoji: emoji.into(),
            count: who.len() as u32,
            mine,
            people: who.iter().map(|w| w.1.to_owned()).collect(),
            person_ids: who.iter().map(|w| w.0.to_owned()).collect(),
        }
    }

    #[test]
    fn a_sender_is_blocked_only_when_listed() {
        assert!(from_blocked("cleo".into(), blocked()));
        assert!(!from_blocked("ben".into(), blocked()));
        assert!(!from_blocked(String::new(), blocked()), "no sender is never blocked");
        assert!(!from_blocked("cleo".into(), Vec::new()));
    }

    #[test]
    fn blocked_reactors_leave_the_faces_and_the_count() {
        let all = vec![
            reaction("👍", &[("ben", "Ben"), ("cleo", "Cleo"), ("me", "You")], true),
            reaction("🎉", &[("cleo", "Cleo")], false),
            reaction("❤️", &[("ben", "Ben")], false),
        ];
        let shown = visible_reactions(all, blocked());
        assert_eq!(shown.len(), 2, "the emoji only Cleo used is gone");
        assert_eq!((shown[0].emoji.as_str(), shown[0].count, shown[0].people.clone(), shown[0].mine), ("👍", 2, vec!["Ben".to_owned(), "You".to_owned()], true));
        assert_eq!(shown[0].person_ids, vec!["ben".to_owned(), "me".to_owned()]);
        assert_eq!((shown[1].emoji.as_str(), shown[1].count), ("❤️", 1));
        assert_eq!(visible_reactions(vec![reaction("👍", &[("ben", "Ben")], false)], Vec::new()).len(), 1, "nobody blocked: nothing changes");
    }

    #[test]
    fn nothing_from_a_blocked_person_notifies_whatever_it_is() {
        for kind in [NotifyKind::DirectMessage, NotifyKind::GroupMessage, NotifyKind::Reaction, NotifyKind::Mention, NotifyKind::JamComment, NotifyKind::JamReply] {
            assert!(!should_notify("cleo".into(), kind, blocked()), "{kind:?}");
            assert!(should_notify("ben".into(), kind, blocked()), "{kind:?}");
            assert!(should_notify("cleo".into(), kind, Vec::new()), "after Unblock, {kind:?}");
        }
    }
}
