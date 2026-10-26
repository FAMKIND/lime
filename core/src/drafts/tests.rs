use super::*;

const EVERYTHING: &str = "# The big idea\n\nA **bold** and *italic* and ~~struck~~ word, `code`, a [link](https://example.com) and a mention [@Jean](mention:jean).\n\n## Steps\n\n- first\n  - nested\n- second\n\n1. one\n2. two\n\n> A quotation\n\n  An indented paragraph\n\n```\nlet x = 1;\n```\n\n![A photo](attachment:0)\n\n![A video](attachment:1)\n\n[[Subscribe]](https://example.com/s)\n\n---\n\n[[freewall]]\n\nThe subscribers' part.";

fn input(kind: &str, text: &str) -> DraftBlockInput {
    DraftBlockInput { kind: kind.into(), level: 0, ordered: false, number: 0, attachment: 0, caption: String::new(), url: String::new(), colour: String::new(), spans: vec![Span { text: text.into(), ..Span::default() }] }
}

#[test]
fn the_markdown_of_every_block_kind_round_trips() {
    let draft = DraftDoc::from_markdown("T", "S", EVERYTHING).unwrap();
    assert_eq!(draft.export_markdown(), format::normalise_post(EVERYTHING));
    let kinds: Vec<String> = draft.blocks().into_iter().map(|b| b.kind).collect();
    for wanted in ["h1", "h2", "paragraph", "item", "quote", "indent", "code", "image", "button", "divider", "freewall"] {
        assert!(kinds.iter().any(|k| k == wanted), "a {wanted} block exists: {kinds:?}");
    }
    // Styles survive as marks, not as text.
    let blocks = draft.blocks();
    let first = &blocks[1];
    assert!(first.spans.iter().any(|s| s.bold && s.text == "bold"));
    assert!(first.spans.iter().any(|s| s.italic) && first.spans.iter().any(|s| s.strike) && first.spans.iter().any(|s| s.code));
    assert!(first.spans.iter().any(|s| s.link.as_deref() == Some("https://example.com")));
    assert!(first.spans.iter().any(|s| s.mention.as_deref() == Some("jean")));
    // The title and subtitle are the draft's own.
    assert_eq!(draft.meta(), DraftMeta { title: "T".into(), subtitle: "S".into(), cover: String::new() });
    // And it survives being saved and loaded.
    let mut draft = draft;
    let bytes = draft.save();
    assert_eq!(DraftDoc::load(&bytes).unwrap().export_markdown(), format::normalise_post(EVERYTHING));
}

#[test]
fn two_documents_edited_apart_and_merged_are_equal_and_concurrent_typing_in_one_paragraph_loses_nothing() {
    let mut shem = DraftDoc::from_markdown("Fractions", "", "The lesson starts here.\n\nSecond paragraph.").unwrap();
    let mut jean = DraftDoc::load(&shem.save()).unwrap();
    let first = shem.blocks()[0].id.clone();
    // Both type at the very same place; Shem also edits the title, Jean adds a block and styles a word.
    shem.insert_text(&first, 3, "SHEM-WORDS ").unwrap();
    jean.insert_text(&first, 3, "JEAN-WORDS ").unwrap();
    shem.set_title("Fractions that stick").unwrap();
    let new_id = jean.insert_block(1, &input("h2", "A heading")).unwrap();
    jean.mark(&first, 0, 3, "bold", None).unwrap();
    let to_jean = shem.changes_since(&jean.heads());
    let to_shem = jean.changes_since(&shem.heads());
    let patches = shem.apply_changes(&to_shem).unwrap();
    jean.apply_changes(&to_jean).unwrap();
    assert_eq!(shem.export_markdown(), jean.export_markdown(), "equal after the merge");
    assert_eq!(shem.meta(), jean.meta());
    let text = shem.block_text(&first).unwrap();
    assert!(text.contains("SHEM-WORDS ") && text.contains("JEAN-WORDS "), "nothing lost: {text:?}");
    assert_eq!(text.chars().count(), "The lesson starts here.".chars().count() + "SHEM-WORDS ".len() + "JEAN-WORDS ".len());
    assert_eq!(shem.blocks()[1].id, new_id, "the new block is where Jean put it");
    // What Shem's editor is told: Jean's words (a splice of just those characters), the new block, the styled word.
    assert!(patches.iter().any(|p| matches!(p, DraftPatch::Text { block_id, inserted, deleted: 0, .. } if *block_id == first && inserted == "JEAN-WORDS ")), "{patches:?}");
    assert!(patches.iter().any(|p| matches!(p, DraftPatch::Inserted { index: 1, block } if block.id == new_id)));
    assert!(patches.iter().any(|p| matches!(p, DraftPatch::Changed { block } if block.id == first)));
    // Applying the same changes again changes nothing.
    assert!(shem.apply_changes(&to_shem).unwrap().is_empty());
}

#[test]
fn blocks_move_change_kind_and_go_and_every_replica_agrees() {
    let mut a = DraftDoc::from_markdown("", "", "One\n\nTwo\n\nThree").unwrap();
    let mut b = DraftDoc::load(&a.save()).unwrap();
    let ids: Vec<String> = a.blocks().into_iter().map(|b| b.id).collect();
    a.move_block(&ids[2], 0).unwrap();
    a.set_block_kind(&ids[1], "h3", 0, false, 0).unwrap();
    a.delete_block(&ids[0]).unwrap();
    let bh = b.heads();
    let patches = b.apply_changes(&a.changes_since(&bh)).unwrap();
    assert_eq!(b.export_markdown(), a.export_markdown());
    assert_eq!(a.export_markdown(), "Three\n\n### Two");
    assert!(patches.iter().any(|p| matches!(p, DraftPatch::Removed { id } if *id == ids[0])));
    assert_eq!(b.blocks().iter().map(|x| x.id.clone()).collect::<Vec<_>>(), vec![ids[2].clone(), ids[1].clone()]);
}

#[test]
fn an_author_who_was_offline_catches_up_from_a_snapshot_or_from_changes() {
    let mut a = DraftDoc::from_markdown("T", "", "Start.").unwrap();
    // A late joiner starts from the whole document (a snapshot), never from a document of their own.
    let mut late = DraftDoc::load(&a.changes_since(&[])).unwrap();
    let id = a.blocks()[0].id.clone();
    for i in 0..50 {
        a.insert_text(&id, 6, &format!(" w{i}")).unwrap();
    }
    let lh = late.heads();
    late.apply_changes(&a.changes_since(&lh)).unwrap();
    assert_eq!(late.export_markdown(), a.export_markdown());
    // Unknown heads are ignored (more is sent, never less).
    assert!(!a.changes_since(&["0000000000000000000000000000000000000000000000000000000000000000".into()]).is_empty());
}

#[test]
fn size_limits_are_refused() {
    let mut d = DraftDoc::from_markdown("", "", "Short").unwrap();
    let id = d.blocks()[0].id.clone();
    assert_eq!(d.insert_text(&id, 0, &"x".repeat(MAX_DRAFT_BYTES)).unwrap_err(), StoreError::Rejected);
    assert_eq!(DraftDoc::from_markdown("", "", &"y".repeat(MAX_DRAFT_BYTES + 1)).err(), Some(StoreError::Rejected));
    assert_eq!(d.block_text(&id).unwrap(), "Short", "a refused edit changes nothing");
    assert_eq!(d.insert_block(0, &input("bogus", "x")).unwrap_err(), StoreError::Rejected);
    assert_eq!(d.mark(&id, 0, 2, "link", Some("javascript:alert(1)")).unwrap_err(), StoreError::Rejected);
    let mut many = DraftDoc::new().unwrap();
    for _ in 0..MAX_BLOCKS {
        many.insert_block(0, &input("paragraph", "")).unwrap();
    }
    assert_eq!(many.insert_block(0, &input("paragraph", "")).unwrap_err(), StoreError::Rejected);
}

#[test]
fn random_concurrent_edits_on_three_replicas_always_converge() {
    // A small deterministic generator, so a failure can be replayed.
    let mut seed = 0x9E3779B97F4A7C15u64;
    let mut next = move |n: usize| { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; (seed % n as u64) as usize };
    for round in 0..20 {
        let mut a = DraftDoc::from_markdown("", "", "alpha\n\nbeta\n\ngamma").unwrap();
        let base = a.save();
        let mut replicas = vec![a, DraftDoc::load(&base).unwrap(), DraftDoc::load(&base).unwrap()];
        for _ in 0..30 {
            let r = next(3);
            let blocks = replicas[r].blocks();
            let b = &blocks[next(blocks.len())];
            match next(6) {
                0 | 1 | 2 => { let at = next(8); replicas[r].insert_text(&b.id, at, &format!("<{r}>")).unwrap() }
                3 => { let at = next(6); replicas[r].delete_text(&b.id, at, 2).unwrap() }
                4 => { replicas[r].insert_block(next(blocks.len() + 1), &input("paragraph", &format!("new{r}"))).unwrap(); }
                _ => { let (s, e) = (next(3), 3 + next(3)); replicas[r].mark(&b.id, s, e, "bold", None).unwrap() }
            }
            if next(4) == 0 {
                let (x, y) = (next(3), next(3));
                if x != y {
                    let yh = replicas[y].heads();
                    let bytes = replicas[x].changes_since(&yh);
                    replicas[y].apply_changes(&bytes).unwrap();
                }
            }
        }
        for x in 0..3 {
            for y in 0..3 {
                if x != y {
                    let yh = replicas[y].heads();
                    let bytes = replicas[x].changes_since(&yh);
                    replicas[y].apply_changes(&bytes).unwrap();
                }
            }
        }
        let (m0, m1, m2) = (replicas[0].export_markdown(), replicas[1].export_markdown(), replicas[2].export_markdown());
        assert!(m0 == m1 && m1 == m2, "round {round} converged");
        assert_eq!(replicas[0].blocks(), replicas[1].blocks());
    }
}

#[test]
fn a_draft_is_saved_as_it_is_edited_survives_a_restart_and_is_folded_after_200_changes() {
    use crate::store::LimeStore;
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("lime.db").to_string_lossy().into_owned();
    let (id, expected) = {
        let store = LimeStore::open(path.clone(), vec![9; 32]).unwrap();
        let id = store.create_draft("Plans".into(), "for the term".into(), "First paragraph.\n\n## Heading".into()).unwrap();
        let first = store.draft_blocks(id.clone()).unwrap()[0].id.clone();
        for i in 0..250 {
            store.draft_insert_text(id.clone(), first.clone(), 5, format!("{}", i % 10)).unwrap();
        }
        store.draft_set_title(id.clone(), "Plans for the year".into()).unwrap();
        let chunks: i64 = store.lock().query_row("SELECT COUNT(*) FROM draft_chunks WHERE draft_id = ?1", rusqlite::params![id], |r| r.get(0)).unwrap();
        assert!(chunks < 200, "folded into a snapshot: {chunks} chunks left");
        assert_eq!(store.list_drafts().unwrap().len(), 1);
        (id.clone(), store.draft_markdown(id).unwrap())
    };
    let store = LimeStore::open(path, vec![9; 32]).unwrap();
    assert_eq!(store.draft_markdown(id.clone()).unwrap(), expected, "the same after a restart");
    assert_eq!(store.draft_meta(id.clone()).unwrap().title, "Plans for the year");
    // Two stores: a snapshot joins another author, and their changes come back as patches.
    let other_dir = tempfile::tempdir().unwrap();
    let other = LimeStore::open(other_dir.path().join("lime.db").to_string_lossy().into_owned(), vec![8; 32]).unwrap();
    other.join_draft(id.clone(), store.draft_snapshot(id.clone()).unwrap()).unwrap();
    let block = other.draft_blocks(id.clone()).unwrap()[1].id.clone();
    other.draft_insert_text(id.clone(), block.clone(), 0, "Big ".into()).unwrap();
    let patches = store.draft_apply_changes(id.clone(), other.draft_changes_since(id.clone(), store.draft_heads(id.clone()).unwrap()).unwrap()).unwrap();
    assert!(patches.iter().any(|p| matches!(p, DraftPatch::Text { inserted, .. } if inserted == "Big ")), "{patches:?}");
    assert_eq!(store.draft_markdown(id.clone()).unwrap(), other.draft_markdown(id.clone()).unwrap());
    store.delete_draft(id.clone()).unwrap();
    assert!(store.list_drafts().unwrap().is_empty());
    assert!(store.draft_blocks(id).is_err());
}

#[test]
fn reconcile_feeds_the_editor_into_the_draft_with_the_fewest_operations_and_other_authors_still_merge() {
    let start = "# Plan\n\nFirst paragraph with **bold** words.\n\n- one\n- two\n\nLast paragraph.";
    let mut shem = DraftDoc::from_markdown("T", "", start).unwrap();
    let mut jean = DraftDoc::load(&shem.save()).unwrap();
    let _ = shem.save_incremental();
    // The editor says the document is the same: nothing changes.
    shem.reconcile(&shem.export_markdown()).unwrap();
    assert!(shem.save_incremental().is_empty(), "no operations for no change");
    // One typed letter is a small change.
    let typed = start.replace("First paragraph", "First paragraphs");
    shem.reconcile(&typed).unwrap();
    let small = shem.save_incremental();
    assert!(!small.is_empty() && small.len() < 120, "one letter is a small change: {} bytes", small.len());
    assert_eq!(shem.export_markdown(), format::normalise_post(&typed));
    // Jean meanwhile typed in the same paragraph and added a block; Shem reconciles a further edit: both survive.
    let first = jean.blocks()[1].id.clone();
    jean.insert_text(&first, 0, "JEAN ").unwrap();
    jean.insert_block(2, &input("quote", "Jean's quote")).unwrap();
    let theirs = jean.save_incremental();
    let more = typed.replace("Last paragraph.", "Last paragraph, edited.");
    shem.reconcile(&more).unwrap();
    shem.apply_changes(&theirs).unwrap();
    let mine = shem.save_incremental();
    jean.apply_changes(&small).unwrap();
    jean.apply_changes(&mine).unwrap();
    let (a, b) = (shem.export_markdown(), jean.export_markdown());
    assert_eq!(a, b);
    assert!(a.contains("JEAN First paragraphs") && a.contains("> Jean's quote") && a.contains("Last paragraph, edited."), "{a}");
    // Styles: bold removed from a word, a link added, a list item turned into a paragraph, a block deleted, a block added.
    let edited = "# Plan\n\nJEAN First paragraphs with bold [words](https://example.com).\n\n> Jean's quote\n\n- one\n\nA new paragraph.\n\nLast paragraph, edited.";
    shem.reconcile(edited).unwrap();
    assert_eq!(shem.export_markdown(), format::normalise_post(edited));
    // Anything the editor can write comes back the same, and a refused size changes nothing.
    shem.reconcile(EVERYTHING).unwrap();
    assert_eq!(shem.export_markdown(), format::normalise_post(EVERYTHING));
    assert_eq!(shem.reconcile(&"z".repeat(MAX_DRAFT_BYTES + 1)).unwrap_err(), StoreError::Rejected);
    assert_eq!(shem.export_markdown(), format::normalise_post(EVERYTHING));
}

#[test]
fn an_editor_that_has_not_seen_the_other_authors_words_yet_merges_instead_of_reverting_them() {
    let start = "First paragraph here.\n\nSecond one.";
    let mut shem = DraftDoc::from_markdown("Plan", "", start).unwrap();
    let mut jean = DraftDoc::load(&shem.save()).unwrap();
    let base = shem.heads();
    // Jean types at the start of the paragraph and in the title; it reaches Shem's draft before Shem's editor shows it.
    let first = jean.blocks()[0].id.clone();
    jean.insert_text(&first, 0, "JEAN ").unwrap();
    jean.set_title("Plan B").unwrap();
    let theirs = jean.changes_since(&base);
    shem.apply_changes(&theirs).unwrap();
    // Shem's editor (still the old text) has a letter typed in the same paragraph and in the title.
    let mine = "First paragraphs here.\n\nSecond one.";
    shem.reconcile_from(&base, "Plan 1", "", mine).unwrap();
    let merged = shem.export_markdown();
    assert_eq!(merged, "JEAN First paragraphs here.\n\nSecond one.", "both survive, nothing reverted");
    assert!(shem.meta().title.contains("B") && shem.meta().title.contains('1'), "{:?}", shem.meta().title);
    // With the base equal to now it is an ordinary reconcile.
    let now = shem.heads();
    shem.reconcile_from(&now, "Plan 1", "", &format!("{merged}\n\nAdded.")).unwrap();
    assert!(shem.export_markdown().ends_with("Added."));
}
