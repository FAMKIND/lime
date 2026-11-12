//! @mentions in the composer (LIME-406): who "@" offers and in what order, the "@word" being typed, putting a mention into the document, taking a mention out whole, and the
//! Markdown in and out with mentions kept. Mirrors `ios/Lime/Features/Chat/Composer/Mentions.swift` (`MentionCandidate.matches`) and `ComposerDocument.swift`
//! (`mentionRange`, `expandedToMentions`, `mentionTrigger`, `insertMention`). Pure; iOS keeps its Swift until LIME-133b.
//!
//! **A mention in a [`ComposerDoc`]** is a run whose `link` is `mention:<user id>` over the text `@Name` (the engine's own record, so `composer_rules.rs` is untouched; the engine
//! never makes such a run and treats it as a link it keeps). It is one atomic unit: [`composer_expand_to_mentions`] widens any edit that touches it. Sent, it is
//! `[@Name](mention:<id>)` (the core's grammar, `format::serialize`); read back for editing, [`composer_from_markdown_with_mentions`] puts it back.

use crate::client::composer_rules::{composer_from_markdown, composer_replace, composer_to_markdown, ComposerDoc, ComposerEdit, ComposerRun, ComposerStyle};
use crate::format::{self, Block, Span};

/// A person "@" can offer (a member of the chat) as this phone knows them.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct MentionPerson {
    pub id: String,
    pub name: String,
    /// My private label for them (only I see it), which also finds them.
    pub label: Option<String>,
    /// The username they told this phone inside the encryption; none if they did not, or hid it.
    pub username: Option<String>,
}

/// One row of the suggestion list.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct MentionSuggestion {
    /// The user id, or `everyone`.
    pub id: String,
    pub name: String,
    /// "Notify the group" for @everyone, else my label for them.
    pub detail: Option<String>,
    pub username: Option<String>,
    pub is_everyone: bool,
}

/// The reserved id of "@everyone" (the core's `format::EVERYONE`).
#[uniffi::export]
pub fn mention_everyone_id() -> String {
    format::EVERYONE.to_owned()
}

fn fold(text: &str) -> String {
    text.to_lowercase()
}

/// The best matches for what was typed after the "@": people whose name starts with it, or has a word that does, or whose username starts with it, then those that contain it
/// (in the name, the private label or the username). An empty query offers everyone in order. At most `limit`. `@everyone` comes first when `everyone` (the person is a group's owner or
/// admin) and the query is empty or starts "everyone". Accents are not folded (iOS also folds diacritics).
#[uniffi::export]
pub fn mention_suggestions(query: String, people: Vec<MentionPerson>, everyone: bool, limit: u32) -> Vec<MentionSuggestion> {
    let wanted = fold(query.trim());
    let mut starts: Vec<MentionSuggestion> = Vec::new();
    let mut contains: Vec<MentionSuggestion> = Vec::new();
    for person in &people {
        let suggestion = MentionSuggestion { id: person.id.clone(), name: person.name.clone(), detail: person.label.clone(), username: person.username.clone(), is_everyone: false };
        if wanted.is_empty() {
            starts.push(suggestion);
            continue;
        }
        let name = fold(&person.name);
        let handle = person.username.as_deref().map(fold);
        if name.starts_with(&wanted) || name.split(' ').any(|w| w.starts_with(&wanted)) || name.contains(&format!(" {wanted}")) || handle.as_deref().is_some_and(|h| h.starts_with(&wanted)) {
            starts.push(suggestion);
        } else if name.contains(&wanted) || person.label.as_deref().map(fold).is_some_and(|l| l.contains(&wanted)) || handle.as_deref().is_some_and(|h| h.contains(&wanted)) {
            contains.push(suggestion);
        }
    }
    starts.extend(contains);
    starts.truncate(limit as usize);
    if everyone && (wanted.is_empty() || "everyone".starts_with(&wanted)) {
        starts.insert(0, MentionSuggestion { id: format::EVERYONE.to_owned(), name: "everyone".to_owned(), detail: Some("Notify the group".to_owned()), username: None, is_everyone: true });
    }
    starts
}

/// A range of the text, UTF-16.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct MentionRange {
    pub start: u32,
    pub end: u32,
}

/// The "@word" being typed just before the caret.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct MentionTrigger {
    /// Covers the "@" and what follows it.
    pub start: u32,
    pub end: u32,
    /// What was typed after the "@".
    pub query: String,
}

fn is_mention(run: &ComposerRun) -> bool {
    run.link.as_deref().is_some_and(|l| l.starts_with("mention:"))
}

/// The "@word" before the caret: the "@" must start the text or follow white space, what follows has no line break and is at most 30 characters, and none of it is already a mention.
#[uniffi::export]
pub fn composer_mention_trigger(doc: ComposerDoc, caret: u32) -> Option<MentionTrigger> {
    let units: Vec<u16> = doc.text.encode_utf16().collect();
    let caret = caret as usize;
    if caret == 0 || caret > units.len() {
        return None;
    }
    let mut at = caret - 1;
    loop {
        if caret - at > 31 {
            return None;
        }
        let unit = units[at];
        if unit == 0x0A || unit == 0x0D {
            return None;
        }
        if unit == 0x40 {
            let starts_word = at == 0 || char::from_u32(units[at - 1] as u32).is_some_and(char::is_whitespace);
            let inside = doc.runs.iter().any(|r| is_mention(r) && (r.start as usize) <= at && at < r.end as usize);
            if !starts_word || inside {
                return None;
            }
            let query = String::from_utf16_lossy(&units[at + 1..caret]);
            return Some(MentionTrigger { start: at as u32, end: caret as u32, query });
        }
        if at == 0 {
            return None;
        }
        at -= 1;
    }
}

/// `start..end` made to take whole mentions: a mention it touches in part is taken completely, and a point strictly inside a mention is the whole mention (so typing or deleting there
/// replaces it, never splits it).
#[uniffi::export]
pub fn composer_expand_to_mentions(doc: ComposerDoc, start: u32, end: u32) -> MentionRange {
    let (mut s, mut e) = (start.min(end), start.max(end));
    for run in doc.runs.iter().filter(|r| is_mention(r)) {
        let touches = if s == e { run.start < s && s < run.end } else { run.start < e && s < run.end };
        if touches {
            s = s.min(run.start);
            e = e.max(run.end);
        }
    }
    MentionRange { start: s, end: e }
}

/// Gives `start..end` of the text the link `link` (or none), splitting runs where needed.
fn set_link(doc: &mut ComposerDoc, start: u32, end: u32, link: Option<String>) {
    let mut runs: Vec<ComposerRun> = Vec::new();
    for run in &doc.runs {
        if run.end <= start || run.start >= end {
            runs.push(run.clone());
            continue;
        }
        if run.start < start {
            runs.push(ComposerRun { end: start, ..run.clone() });
        }
        runs.push(ComposerRun { start: run.start.max(start), end: run.end.min(end), style: ComposerStyle::default(), link: link.clone() });
        if run.end > end {
            runs.push(ComposerRun { start: end, ..run.clone() });
        }
    }
    doc.runs = runs;
}

/// Puts a mention in place of `start..end` (the "@word" typed), with a plain space after it; the caret goes after the space. `name` is what is shown after the "@".
#[uniffi::export]
pub fn composer_insert_mention(doc: ComposerDoc, start: u32, end: u32, name: String, id: String) -> ComposerEdit {
    let shown = format!("@{name}");
    let units = shown.encode_utf16().count() as u32;
    let mut edit = composer_replace(doc, start, end, format!("{shown} "), ComposerStyle::default());
    set_link(&mut edit.doc, start, start + units, Some(format!("mention:{id}")));
    edit
}

/// The Markdown to send: the core's canonical text, with every mention written `[@Name](mention:id)`.
#[uniffi::export]
pub fn composer_mentions_to_markdown(doc: ComposerDoc) -> String {
    let mentions: Vec<ComposerRun> = doc.runs.iter().filter(|r| is_mention(r)).cloned().collect();
    if mentions.is_empty() {
        return composer_to_markdown(doc);
    }
    // Each mention's text is swapped for a private-use marker the Markdown writer passes through, then the marker becomes the mention.
    let units: Vec<u16> = doc.text.encode_utf16().collect();
    let mut text = String::new();
    let mut shifted: Vec<ComposerRun> = Vec::new();
    let mut marks: Vec<(char, String)> = Vec::new();
    let mut offset = 0u32;
    for run in &doc.runs {
        let words = String::from_utf16_lossy(&units[run.start as usize..run.end as usize]);
        if is_mention(run) {
            let id = run.link.as_deref().unwrap_or("mention:").trim_start_matches("mention:").to_owned();
            let name = words.strip_prefix('@').unwrap_or(&words).to_owned();
            let mark = char::from_u32(0xE000 + marks.len() as u32).unwrap_or('\u{E000}');
            marks.push((mark, render_mention(&name, &id)));
            text.push(mark);
            shifted.push(ComposerRun { start: offset, end: offset + 1, style: run.style, link: None });
            offset += 1;
        } else {
            text.push_str(&words);
            let len = words.encode_utf16().count() as u32;
            shifted.push(ComposerRun { start: offset, end: offset + len, style: run.style, link: run.link.clone() });
            offset += len;
        }
    }
    let swapped = ComposerDoc { text, runs: shifted, lines: doc.lines };
    let mut markdown = composer_to_markdown(swapped);
    for (mark, mention) in marks {
        markdown = markdown.replace(mark, &mention);
    }
    markdown
}

/// `[@Name](mention:id)` as the core writes it.
fn render_mention(name: &str, id: &str) -> String {
    let span = Span { text: format!("@{name}"), mention: Some(id.to_owned()), ..Span::default() };
    format::serialize(&[Block::Paragraph { spans: vec![span] }])
}

/// The place each mention takes in the document `composer_from_markdown` makes of `markdown` (UTF-16 offsets, the text `@Name`, and the id), worked out from the blocks the same
/// way the engine lays them out: blocks a blank line apart, list items and code lines a line apart.
fn mention_places(blocks: &[Block]) -> Vec<(u32, u32, String)> {
    let mut places = Vec::new();
    let mut offset = 0u32;
    let walk = |spans: &[Span], offset: &mut u32, places: &mut Vec<(u32, u32, String)>| {
        for span in spans {
            let len = span.text.encode_utf16().count() as u32;
            if let Some(id) = &span.mention {
                places.push((*offset, *offset + len, id.clone()));
            }
            *offset += len;
        }
    };
    for (index, block) in blocks.iter().enumerate() {
        if index > 0 {
            offset += 2;
        }
        match block {
            Block::Paragraph { spans } => walk(spans, &mut offset, &mut places),
            Block::ItemList { items } => {
                for (n, item) in items.iter().enumerate() {
                    if n > 0 {
                        offset += 1;
                    }
                    walk(&item.spans, &mut offset, &mut places);
                }
            }
            Block::Code { text } => offset += text.encode_utf16().count() as u32,
            _ => {}
        }
    }
    places
}

/// A message's Markdown as a document with its mentions kept (to edit a sent message): the engine's `composer_from_markdown`, then each mention marked.
#[uniffi::export]
pub fn composer_from_markdown_with_mentions(markdown: String) -> ComposerDoc {
    let mut doc = composer_from_markdown(markdown.clone());
    let units: Vec<u16> = doc.text.encode_utf16().collect();
    for (start, end, id) in mention_places(&format::parse(&markdown)) {
        if (end as usize) <= units.len() && units[start as usize..end as usize].first() == Some(&0x40) {
            set_link(&mut doc, start, end, Some(format!("mention:{id}")));
        }
    }
    doc
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::client::composer_rules::{composer_empty, composer_toggle_style, ComposerStyleKind};

    fn person(id: &str, name: &str, label: Option<&str>, username: Option<&str>) -> MentionPerson {
        MentionPerson { id: id.into(), name: name.into(), label: label.map(Into::into), username: username.map(Into::into) }
    }
    fn class() -> Vec<MentionPerson> {
        vec![
            person("a", "Ada Android", None, Some("ada_android")),
            person("b", "Ben Android", Some("Mr Ben"), Some("ben_android")),
            person("c", "Cleo Chung", None, None),
            person("d", "Dana Bennett", None, None),
        ]
    }
    fn ids(list: &[MentionSuggestion]) -> Vec<&str> {
        list.iter().map(|s| s.id.as_str()).collect()
    }
    fn typed(text: &str) -> ComposerDoc {
        composer_replace(composer_empty(), 0, 0, text.to_owned(), ComposerStyle::default()).doc
    }

    // MentionTests (Mentions.swift's `matches`)
    #[test]
    fn the_best_matches_come_first_and_everyone_only_for_an_owner_or_admin() {
        assert_eq!(ids(&mention_suggestions("".into(), class(), false, 30)), ["a", "b", "c", "d"], "nothing typed: everyone in order");
        assert_eq!(ids(&mention_suggestions("ben".into(), class(), false, 30)), ["b", "d"], "a word that starts with it first (Ben), then the name that contains it (Bennett starts a word too)");
        assert_eq!(ids(&mention_suggestions("chung".into(), class(), false, 30)), ["c"], "a later word of the name");
        assert_eq!(ids(&mention_suggestions("mr".into(), class(), false, 30)), ["b"], "the private label finds them");
        assert_eq!(ids(&mention_suggestions("ada_".into(), class(), false, 30)), ["a"], "the username");
        assert_eq!(ids(&mention_suggestions("droid".into(), class(), false, 30)), ["a", "b"], "a name that only contains it");
        assert_eq!(ids(&mention_suggestions("zzz".into(), class(), false, 30)), Vec::<&str>::new());
        let admin = mention_suggestions("".into(), class(), true, 30);
        assert_eq!(admin[0].id, "everyone");
        assert_eq!((admin[0].is_everyone, admin[0].detail.as_deref()), (true, Some("Notify the group")));
        assert_eq!(ids(&mention_suggestions("ever".into(), class(), true, 30)), ["everyone"]);
        assert_eq!(ids(&mention_suggestions("ben".into(), class(), true, 30)), ["b", "d"], "@everyone is not offered for a word that does not start it");
        assert_eq!(mention_suggestions("".into(), class(), false, 2).len(), 2, "capped");
        let many: Vec<MentionPerson> = (0..60).map(|i| person(&format!("u{i}"), &format!("Teacher {i}"), None, None)).collect();
        assert_eq!(mention_suggestions("".into(), many, false, 30).len(), 30, "a group of 500 shows the best 30, not all");
    }

    // LIME-408: iOS offers a 1:1 chat's one other person (`conversation.members`), and "@everyone" only to a group's owner or admin (the app passes false in a 1:1).
    #[test]
    fn a_one_to_one_chat_offers_the_other_person_and_never_everyone() {
        let other = vec![person("b", "Ben Android", None, Some("ben_android"))];
        assert_eq!(ids(&mention_suggestions("".into(), other.clone(), false, 30)), ["b"]);
        assert_eq!(ids(&mention_suggestions("be".into(), other.clone(), false, 30)), ["b"]);
        assert_eq!(ids(&mention_suggestions("ever".into(), other.clone(), false, 30)), Vec::<&str>::new(), "no @everyone without the flag");
        assert_eq!(ids(&mention_suggestions("zz".into(), other, false, 30)), Vec::<&str>::new());
    }

    #[test]
    fn the_at_word_before_the_caret_is_a_trigger_only_at_a_word_start() {
        let doc = typed("hello @be");
        assert_eq!(composer_mention_trigger(doc.clone(), 9), Some(MentionTrigger { start: 6, end: 9, query: "be".into() }));
        assert_eq!(composer_mention_trigger(typed("@"), 1), Some(MentionTrigger { start: 0, end: 1, query: String::new() }));
        assert_eq!(composer_mention_trigger(typed("mail me@x"), 9), None, "an @ inside a word is an address");
        assert_eq!(composer_mention_trigger(typed("hi @be\nnext"), 11), None, "a line break ends it");
        assert_eq!(composer_mention_trigger(typed(&format!("@{}", "x".repeat(40))), 41), None, "at most 30 characters");
        assert_eq!(composer_mention_trigger(typed("no at here"), 5), None);
        assert_eq!(composer_mention_trigger(composer_empty(), 0), None);
    }

    // testAMentionIsOneUnit / expandedToMentions
    #[test]
    fn a_mention_goes_in_whole_comes_out_whole_and_is_sent_as_markup() {
        let doc = typed("hi @be");
        let edit = composer_insert_mention(doc, 3, 6, "Ben Android".into(), "u-1".into());
        assert_eq!(edit.doc.text, "hi @Ben Android ");
        assert_eq!((edit.selection_start, edit.selection_end), (16, 16), "the caret after the space");
        assert_eq!(composer_mentions_to_markdown(edit.doc.clone()).trim(), "hi [@Ben Android](mention:u-1)");
        // Touching it anywhere takes all of it; a point inside it is the whole of it.
        assert_eq!(composer_expand_to_mentions(edit.doc.clone(), 14, 15), MentionRange { start: 3, end: 15 });
        assert_eq!(composer_expand_to_mentions(edit.doc.clone(), 9, 9), MentionRange { start: 3, end: 15 });
        assert_eq!(composer_expand_to_mentions(edit.doc.clone(), 3, 3), MentionRange { start: 3, end: 3 }, "at its edge nothing is inside");
        assert_eq!(composer_expand_to_mentions(edit.doc.clone(), 15, 16), MentionRange { start: 15, end: 16 }, "the space after it is not part of it");
        // An "@" inside a mention is not a trigger.
        assert_eq!(composer_mention_trigger(edit.doc.clone(), 4), None);
        // Deleting the whole of it leaves the text around it.
        let gone = composer_replace(edit.doc, 3, 15, String::new(), ComposerStyle::default()).doc;
        assert_eq!((gone.text.as_str(), composer_mentions_to_markdown(gone.clone()).trim()), ("hi  ", "hi"));
    }

    #[test]
    fn mentions_survive_the_markdown_round_trip_and_the_styles_around_them() {
        for markdown in ["hi [@Ben Android](mention:u-1) there", "[@Ada](mention:a) and [@Cleo](mention:c)", "- [@Ben](mention:b) first\n- second", "**bold [@Ben](mention:b) too**", "[@everyone](mention:everyone) lunch"] {
            let doc = composer_from_markdown_with_mentions(markdown.to_owned());
            assert!(doc.runs.iter().any(|r| is_mention(r)), "{markdown}");
            assert_eq!(composer_mentions_to_markdown(doc), format::normalise(markdown), "{markdown}");
        }
        // Without the mention-aware reader the name stays plain words (what the engine alone does).
        assert!(!composer_from_markdown("hi [@Ben](mention:b)".to_owned()).runs.iter().any(|r| is_mention(r)));
        // Bold over text that includes a mention keeps the mention.
        let doc = composer_insert_mention(typed("a @b"), 2, 4, "Ben".into(), "b".into()).doc;
        let all = doc.text.encode_utf16().count() as u32;
        let bold = composer_toggle_style(doc, 0, all, ComposerStyleKind::Bold);
        assert!(composer_mentions_to_markdown(bold).contains("(mention:b)"));
    }

    #[test]
    fn a_name_with_markup_characters_is_escaped_inside_the_mention() {
        let doc = composer_insert_mention(typed("@x"), 0, 2, "A_B *C*".into(), "u".into()).doc;
        let markdown = composer_mentions_to_markdown(doc);
        let back = format::parse(&markdown);
        match &back[0] {
            Block::Paragraph { spans } => assert_eq!((spans[0].text.as_str(), spans[0].mention.as_deref()), ("@A_B *C*", Some("u"))),
            other => panic!("{other:?}"),
        }
    }
}
