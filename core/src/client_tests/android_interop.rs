//! LIME-SYNC-1: the interop proof, in Rust. What Android's composer writes (the core's `ComposerDoc` → `composer_to_markdown`, the engine of LIME-404/405) is read back by
//! **the same `parse_message_markdown` the iOS app calls to draw a received message** (`MessageText.swift`, `ComposerDocument.swift`), into the blocks iOS draws, and written out
//! again by `message_markdown_from_blocks` unchanged. A child of `client_tests` (one registration line there).

use crate::client::composer_rules::{
    composer_empty, composer_replace, composer_set_link, composer_to_markdown, composer_toggle_list, composer_toggle_style, ComposerLineKind, ComposerStyle, ComposerStyleKind,
};
use crate::format::{message_markdown_from_blocks, parse_message_markdown, Block};

#[test]
fn what_androids_composer_writes_is_what_ios_parses_and_draws() {
    // Typed the way the Android composer receives it: one document, then the strip's buttons (Bold on a word, a bulleted list, a link).
    let typed = composer_replace(composer_empty(), 0, 0, "bold word\none\ntwo\nsee the plan".to_owned(), ComposerStyle::default()).doc;
    let doc = composer_toggle_style(typed, 0, 4, ComposerStyleKind::Bold);
    let doc = composer_toggle_list(doc, 10, 17, ComposerLineKind::Bullet);
    let doc = composer_set_link(doc, 26, 30, Some("https://limemessenger.com/plan".to_owned()));
    let markdown = composer_to_markdown(doc);
    assert_eq!(markdown, "**bold** word\n\n- one\n- two\n\nsee the [plan](https://limemessenger.com/plan)", "the canonical markdown on the wire (a list is set off by blank lines)");

    // iOS reads it with this very function.
    let blocks = parse_message_markdown(markdown.clone());
    assert_eq!(blocks.len(), 3, "{blocks:?}");
    match &blocks[0] {
        Block::Paragraph { spans } => {
            assert_eq!(spans.iter().map(|s| (s.text.as_str(), s.bold)).collect::<Vec<_>>(), [("bold", true), (" word", false)]);
        }
        other => panic!("a paragraph with a bold word, got {other:?}"),
    }
    match &blocks[1] {
        Block::ItemList { items } => assert_eq!(items.len(), 2, "two list items"),
        other => panic!("a bulleted list, got {other:?}"),
    }
    match &blocks[2] {
        Block::Paragraph { spans } => {
            let link = spans.iter().find(|s| s.link.is_some()).expect("a link span");
            assert_eq!((link.text.as_str(), link.link.as_deref()), ("plan", Some("https://limemessenger.com/plan")));
        }
        other => panic!("a paragraph ending in a link, got {other:?}"),
    }
    // And what iOS would write back for the same blocks is what Android wrote.
    assert_eq!(message_markdown_from_blocks(blocks), markdown);
}
