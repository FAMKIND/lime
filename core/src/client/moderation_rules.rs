//! What a report is made of (LIME-401): the reasons and their words, and for each thing a person can report (a message, a person, a group, a jam post, a comment, a jam)
//! the ids the moderators need, the line shown to the reporter, and the item as this phone holds it (what "Include" sends). Mirrors the `reportTarget(...)` functions of
//! `ios/Lime/App/ConversationStore+Moderation.swift`, `ReportReason`, and `GroupReportDraft.payload` (the group report's choices and its size cap). Pure; the sealing and
//! sending are `LimeStore::send_report` (`moderation.rs`). iOS keeps its Swift until LIME-133b.

use crate::client::jam::{JamCommentInfo, JamPageInfo, JamPostInfo};
use serde_json::{json, Map, Value};

/// What a report is about, ready for the sheet and for `send_report`.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ReportTargetInfo {
    /// message, person, group, jam_post, comment, jam.
    pub kind: String,
    pub ids: Vec<String>,
    /// "message", "post", "comment", "profile", "group", "jam": the word in "Include this …".
    pub noun: String,
    pub person_name: Option<String>,
    /// The chat to block with "Also block", when the reported person has one.
    pub block_conversation_id: Option<String>,
    /// The item as held, JSON text (sorted keys); what "Include" sends. Empty for a group (its choices build it).
    pub included: String,
    /// What the sheet shows the reporter will be sent.
    pub preview: String,
}

/// The reasons a person can give, in the order the sheet lists them.
#[uniffi::export]
pub fn report_reasons() -> Vec<String> {
    ["harassment", "spam", "impersonation", "inappropriate", "child_safety", "hate_violence", "other"].map(String::from).to_vec()
}

#[uniffi::export]
pub fn report_reason_title(reason: String) -> String {
    match reason.as_str() {
        "harassment" => "Harassment or bullying",
        "spam" => "Spam or scam",
        "impersonation" => "Impersonation",
        "inappropriate" => "Inappropriate or sexual content",
        "child_safety" => "A child\u{2019}s safety",
        "hate_violence" => "Hate or violence",
        _ => "Something else",
    }
    .to_owned()
}

/// The words under "Include this …" for what the reporter's team will see.
#[uniffi::export]
pub fn report_include_words(noun: String, person_name: Option<String>, include: bool) -> String {
    let who = person_name.unwrap_or_else(|| "They".to_owned());
    if include {
        format!("lime\u{2019}s team sees this {noun} and your report. {who} won\u{2019}t know it was you.")
    } else {
        format!("lime\u{2019}s team sees your report only. {who} won\u{2019}t know it was you.")
    }
}

fn text(value: Value) -> String {
    value.to_string()
}

fn first(s: &str, n: usize) -> String {
    s.chars().take(n).collect()
}

fn block_chat(user_id: &str, has_chat: bool) -> Option<String> {
    (has_chat && !user_id.is_empty()).then(|| format!("dm:{user_id}"))
}

/// A message: its id, the chat and the sender. `attachments` is only counted (the files are never sent).
#[uniffi::export]
pub fn report_target_message(message_id: String, conversation_id: String, sender_id: String, sender_name: Option<String>, message_text: String, sent_ms: i64, attachments: u32) -> ReportTargetInfo {
    let preview = first(&message_text, 160);
    ReportTargetInfo {
        kind: "message".to_owned(),
        ids: vec![message_id.clone(), conversation_id.clone(), sender_id.clone()],
        noun: "message".to_owned(),
        person_name: sender_name,
        block_conversation_id: if conversation_id.starts_with("dm:") { Some(conversation_id.clone()) } else { block_chat(&sender_id, true) },   // a group sender is blocked as a person (LIME-329)
        included: text(json!({ "message_id": message_id, "conversation": conversation_id, "sender": sender_id, "text": message_text, "sent": sent_ms, "attachments": attachments })),
        preview,
    }
}

#[uniffi::export]
pub fn report_target_person(user_id: String, name: String, has_chat: bool) -> ReportTargetInfo {
    ReportTargetInfo {
        kind: "person".to_owned(),
        ids: vec![user_id.clone()],
        noun: "profile".to_owned(),
        person_name: Some(name.clone()),
        block_conversation_id: block_chat(&user_id, has_chat),
        included: text(json!({ "user_id": user_id, "name": name })),
        preview: name,
    }
}

#[uniffi::export]
pub fn report_target_comment(comment: JamCommentInfo, person_name: String, has_chat: bool) -> ReportTargetInfo {
    ReportTargetInfo {
        kind: "comment".to_owned(),
        ids: vec![comment.comment_id.clone(), comment.post_id.clone(), comment.author.clone()],
        noun: "comment".to_owned(),
        person_name: Some(person_name),
        block_conversation_id: block_chat(&comment.author, has_chat),
        included: text(json!({ "comment_id": comment.comment_id, "post_id": comment.post_id, "author": comment.author, "text": comment.text, "created": comment.created })),
        preview: first(&comment.text, 160),
    }
}

/// A jam post. `blob_id` is the server blob that holds the post now (`jam_post_blob_id`; empty when none): "Hide post" hides that blob. A post open to everyone (or with a
/// Preview) also has a public copy: "open" in the ids lets the moderators hide that too.
#[uniffi::export]
pub fn report_target_post(post: JamPostInfo, person_name: String, blob_id: String, has_chat: bool) -> ReportTargetInfo {
    let words = [post.title.as_str(), post.subtitle.as_str(), post.plain.as_str()].into_iter().filter(|s| !s.is_empty()).collect::<Vec<_>>().join("\n");
    let has_open_copy = post.audience == "everyone" || post.markdown.contains("[[freewall]]");
    let mut ids = vec![post.post_id.clone(), post.jam_id.clone(), post.author.clone()];
    if !blob_id.is_empty() {
        ids.push(blob_id.clone());
    }
    if has_open_copy {
        ids.push("open".to_owned());
    }
    ReportTargetInfo {
        kind: "jam_post".to_owned(),
        ids,
        noun: "post".to_owned(),
        person_name: Some(person_name),
        block_conversation_id: block_chat(&post.author, has_chat),
        included: text(json!({
            "post_id": post.post_id, "blob_id": blob_id, "jam_id": post.jam_id, "author": post.author, "title": post.title, "subtitle": post.subtitle,
            "text": post.markdown, "created": post.created, "kind": post.kind,
        })),
        preview: first(&words, 160),
    }
}

#[uniffi::export]
pub fn report_target_jam(page: JamPageInfo, person_name: String, has_chat: bool) -> ReportTargetInfo {
    ReportTargetInfo {
        kind: "jam".to_owned(),
        ids: vec![page.jam_id.clone(), page.writer_id.clone()],
        noun: "jam".to_owned(),
        person_name: Some(person_name),
        block_conversation_id: block_chat(&page.writer_id, has_chat),
        included: text(json!({ "jam_id": page.jam_id, "writer": page.writer_id, "title": page.title, "about": page.about })),
        preview: page.title,
    }
}

/// One message of a group, as the report sheet lists it.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ReportGroupMessage {
    pub id: String,
    pub sender_id: String,
    pub sender_name: String,
    pub text: String,
    pub sent_ms: i64,
    pub attachments: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ReportGroupMember {
    pub user_id: String,
    pub name: String,
    pub role: String,
}

/// A group report's `ids` and `included` for the choices made.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ReportGroupPayload {
    pub ids: Vec<String>,
    pub included: String,
}

/// The target of a group report: the sheet adds the message choices (`report_group_payload`).
#[uniffi::export]
pub fn report_target_group(conversation_id: String, name: String) -> ReportTargetInfo {
    ReportTargetInfo { kind: "group".to_owned(), ids: vec![conversation_id], noun: "group".to_owned(), person_name: None, block_conversation_id: None, included: String::new(), preview: name }
}

const GROUP_REPORT_CAP: usize = 90_000;

/// What a group report carries (LIME-256, DESIGN-24): the ticked messages (the last 20 are offered), the group's name and photo, and, only if asked, who is in it. The
/// sealed report stays under the server's 96 KB cap: when the messages are too long the oldest are cut short and the report says `trimmed`. The ids are the group and its first
/// seven senders (the core takes at most 8; all of them are in the included text).
#[uniffi::export]
pub fn report_group_payload(
    conversation_id: String,
    name: String,
    has_photo: bool,
    messages: Vec<ReportGroupMessage>,
    members: Vec<ReportGroupMember>,
    ticked: Vec<String>,
    name_and_photo: bool,
    with_members: bool,
) -> ReportGroupPayload {
    let chosen: Vec<&ReportGroupMessage> = messages.iter().filter(|m| ticked.contains(&m.id)).collect();
    let mut limit = 2_000usize;
    let mut trimmed = false;
    let mut included: String;
    loop {
        let rows: Vec<Value> = chosen
            .iter()
            .map(|m| {
                let cut = m.text.chars().count() > limit;
                if cut {
                    trimmed = true;
                }
                json!({ "id": m.id, "sender": m.sender_id, "sender_name": m.sender_name, "text": if cut { first(&m.text, limit) } else { m.text.clone() }, "sent": m.sent_ms, "attachments": m.attachments })
            })
            .collect();
        let mut object = Map::new();
        object.insert("conversation".to_owned(), json!(conversation_id));
        object.insert("messages".to_owned(), Value::Array(rows));
        if name_and_photo {
            object.insert("name".to_owned(), json!(name));
            object.insert("photo".to_owned(), json!(if has_photo { "has a photo" } else { "none" }));
        }
        if with_members {
            object.insert("members".to_owned(), Value::Array(members.iter().map(|m| json!({ "user_id": m.user_id, "name": m.name, "role": m.role })).collect()));
        }
        if trimmed {
            object.insert("trimmed".to_owned(), json!(true));
        }
        included = Value::Object(object).to_string();
        if included.len() <= GROUP_REPORT_CAP {
            break;
        }
        limit /= 2;
        if limit < 50 {
            break;
        }
    }
    let mut senders: Vec<String> = Vec::new();
    for m in &chosen {
        if !m.sender_id.is_empty() && !senders.contains(&m.sender_id) {
            senders.push(m.sender_id.clone());
        }
    }
    let mut ids = vec![conversation_id];
    ids.extend(senders.into_iter().take(7));
    ReportGroupPayload { ids, included }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn msg(id: &str, from: &str, body: &str) -> ReportGroupMessage {
        ReportGroupMessage { id: id.into(), sender_id: from.into(), sender_name: format!("N-{from}"), text: body.into(), sent_ms: 5, attachments: 0 }
    }

    #[test]
    fn the_reasons_and_their_words() {
        assert_eq!(report_reasons().len(), 7);
        assert_eq!(report_reasons()[0], "harassment");
        assert_eq!(report_reason_title("child_safety".into()), "A child\u{2019}s safety");
        assert_eq!(report_reason_title("anything else".into()), "Something else");
        assert_eq!(
            report_include_words("message".into(), Some("Ben".into()), true),
            "lime\u{2019}s team sees this message and your report. Ben won\u{2019}t know it was you."
        );
        assert_eq!(report_include_words("message".into(), None, false), "lime\u{2019}s team sees your report only. They won\u{2019}t know it was you.");
    }

    #[test]
    fn a_message_and_a_person_name_what_the_moderators_need() {
        let m = report_target_message("m1".into(), "dm:ben".into(), "ben".into(), Some("Ben".into()), "Hello there".into(), 1_700_000_000_000, 2);
        assert_eq!((m.kind.as_str(), m.noun.as_str(), m.ids.as_slice()), ("message", "message", ["m1".to_owned(), "dm:ben".to_owned(), "ben".to_owned()].as_slice()));
        assert_eq!(m.block_conversation_id.as_deref(), Some("dm:ben"));
        assert_eq!(m.included, r#"{"attachments":2,"conversation":"dm:ben","message_id":"m1","sender":"ben","sent":1700000000000,"text":"Hello there"}"#);
        let in_group = report_target_message("m2".into(), "grp:x".into(), "cleo".into(), None, "x".repeat(300), 1, 0);
        assert_eq!(in_group.block_conversation_id.as_deref(), Some("dm:cleo"), "a group sender is blocked as a person: Report → Also block works in a group (LIME-329)");
        assert_eq!(in_group.preview.chars().count(), 160);
        let p = report_target_person("ben".into(), "Ben Android".into(), false);
        assert_eq!((p.kind.as_str(), p.noun.as_str(), p.block_conversation_id), ("person", "profile", None));
        assert_eq!(report_target_person("ben".into(), "Ben".into(), true).block_conversation_id.as_deref(), Some("dm:ben"));
    }

    fn post(audience: &str, markdown: &str) -> JamPostInfo {
        JamPostInfo {
            post_id: "p1".into(), jam_id: "j1".into(), author: "ben".into(), tier: "free".into(), kind: "article".into(), title: "Bridges".into(), subtitle: "A week".into(),
            markdown: markdown.into(), plain: "We built bridges.".into(), attachments_json: "[]".into(), created: 9, coauthors: vec![], display_as: String::new(), edited_at: 0,
            audience: audience.into(), series: None, topics: vec![], state: "ready".into(),
        }
    }

    #[test]
    fn a_post_carries_its_blob_and_says_when_it_has_an_open_copy() {
        let plain = report_target_post(post("subscribers", "text"), "Ben".into(), "blob9".into(), true);
        assert_eq!(plain.ids, ["p1", "j1", "ben", "blob9"]);
        assert_eq!(plain.preview, "Bridges\nA week\nWe built bridges.");
        let open = report_target_post(post("everyone", "text"), "Ben".into(), String::new(), false);
        assert_eq!(open.ids, ["p1", "j1", "ben", "open"]);
        assert_eq!(report_target_post(post("subscribers", "a [[freewall]] b"), "Ben".into(), "b".into(), false).ids.last().map(String::as_str), Some("open"));
    }

    #[test]
    fn a_group_report_carries_only_what_is_ticked_and_stays_under_the_cap() {
        let messages = vec![msg("a", "ada", "one"), msg("b", "cleo", "two"), msg("c", "ada", "three")];
        let members = vec![ReportGroupMember { user_id: "ada".into(), name: "Ada".into(), role: "owner".into() }];
        let some = report_group_payload("grp:x".into(), "Class".into(), false, messages.clone(), members.clone(), vec!["a".into(), "c".into()], true, false);
        assert_eq!(some.ids, ["grp:x", "ada"]);
        let v: Value = serde_json::from_str(&some.included).unwrap();
        assert_eq!(v["messages"].as_array().unwrap().len(), 2);
        assert_eq!((v["name"].as_str(), v["photo"].as_str()), (Some("Class"), Some("none")));
        assert!(v.get("members").is_none() && v.get("trimmed").is_none());
        let all = report_group_payload("grp:x".into(), "Class".into(), true, messages, members, vec!["a".into(), "b".into(), "c".into()], false, true);
        assert_eq!(all.ids, ["grp:x", "ada", "cleo"]);
        let v: Value = serde_json::from_str(&all.included).unwrap();
        assert!(v.get("name").is_none() && v["members"].as_array().unwrap().len() == 1);
        // Twenty long messages are cut short, oldest included, and the report says so.
        let long: Vec<ReportGroupMessage> = (0..20).map(|i| msg(&format!("m{i}"), "ada", &"x".repeat(9_000))).collect();
        let ticked: Vec<String> = long.iter().map(|m| m.id.clone()).collect();
        let big = report_group_payload("grp:x".into(), "Class".into(), false, long, vec![], ticked, false, false);
        assert!(big.included.len() <= GROUP_REPORT_CAP, "{}", big.included.len());
        assert_eq!(serde_json::from_str::<Value>(&big.included).unwrap()["trimmed"], json!(true));
    }
}
