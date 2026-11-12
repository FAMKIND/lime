//! Undo and redo for the rich-text composer (LIME-414), through the core's document so the field, its styles, its list levels and the caret always agree.
//!
//! What iOS does (`RichComposer.swift`, "Undo (a jam post's strip)"): a toolbar edit (a style on a selection, a list, a link, a paste, Return, a mention) is one **step** (a snapshot taken before
//! it; the caps is **50** steps, the oldest dropped; a new step **clears redo**); a run of typing is **one** step (iOS leaves that to UIKit's own undo manager, which groups what is typed
//! without a pause); Undo and Redo move one step at a time. Android mirrors that here, with the clock injected: **typing within 1 second of the previous typing is the same step**
//! (iOS has no number of its own: UIKit's grouping decides; 1000 ms is this core's choice, `TYPING_PAUSE_MS`). The core holds no clock: the app passes `now_ms`.

use super::composer_rules::ComposerDoc;

/// Most steps kept (iOS `history.count > 50`).
pub const HISTORY_CAP: usize = 50;
/// Typing after a longer pause than this starts a new step.
pub const TYPING_PAUSE_MS: i64 = 1_000;

/// What the document and the selection were at one moment (the selection in UTF-16, like the document's offsets).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ComposerSnapshot {
    pub doc: ComposerDoc,
    pub selection_start: u32,
    pub selection_end: u32,
}

/// Why a step was made: typing (a character at a time) joins the step before it while the pauses are short; anything else is a step of its own.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ComposerStepKind {
    Typing,
    Other,
}

/// The steps taken back by Undo (`past`, the oldest first: each is the state BEFORE its step) and the ones Redo can bring back (`future`, the next one last).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ComposerHistory {
    pub past: Vec<ComposerSnapshot>,
    pub future: Vec<ComposerSnapshot>,
    /// What the last recorded step was, and when (ms): typing joins it.
    pub last_kind: ComposerStepKind,
    pub last_ms: i64,
}

/// Undo or Redo: the history afterwards and the state to put in the field.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ComposerHistoryStep {
    pub history: ComposerHistory,
    pub snapshot: ComposerSnapshot,
}

/// Nothing to undo, nothing to redo.
#[uniffi::export]
pub fn composer_history_empty() -> ComposerHistory {
    ComposerHistory { past: Vec::new(), future: Vec::new(), last_kind: ComposerStepKind::Other, last_ms: 0 }
}

/// What kind of step an edit of the text is: a single character typed (or one deleted) is **typing**; a paste (more than one character), Return, a replaced selection or a longer deletion is **other**.
#[uniffi::export]
pub fn composer_step_kind(removed: String, inserted: String) -> ComposerStepKind {
    let (r, i) = (removed.chars().count(), inserted.chars().count());
    let typed = (r == 0 && i == 1 && inserted != "\n") || (i == 0 && r == 1 && removed != "\n");
    if typed { ComposerStepKind::Typing } else { ComposerStepKind::Other }
}

/// Records that an edit is about to be made: `before` is the state it starts from. Typing within `TYPING_PAUSE_MS` of the previous typing joins that step (nothing new is kept, but the time moves
/// on); anything else keeps `before` as a new step, drops the oldest past the cap, and **clears redo**.
#[uniffi::export]
pub fn composer_history_push(history: ComposerHistory, before: ComposerSnapshot, kind: ComposerStepKind, now_ms: i64) -> ComposerHistory {
    let mut next = history;
    let joins = kind == ComposerStepKind::Typing && next.last_kind == ComposerStepKind::Typing && !next.past.is_empty() && now_ms - next.last_ms <= TYPING_PAUSE_MS && now_ms >= next.last_ms;
    next.last_kind = kind;
    next.last_ms = now_ms;
    if joins {
        return next;
    }
    next.past.push(before);
    if next.past.len() > HISTORY_CAP {
        next.past.remove(0);
    }
    next.future.clear();
    next
}

#[uniffi::export]
pub fn composer_history_can_undo(history: ComposerHistory) -> bool {
    !history.past.is_empty()
}

#[uniffi::export]
pub fn composer_history_can_redo(history: ComposerHistory) -> bool {
    !history.future.is_empty()
}

/// Takes one step back: the state before it goes to the field, `current` is kept for Redo. None when there is nothing to undo. The next typing starts a new step.
#[uniffi::export]
pub fn composer_history_undo(history: ComposerHistory, current: ComposerSnapshot) -> Option<ComposerHistoryStep> {
    let mut next = history;
    let snapshot = next.past.pop()?;
    next.future.push(current);
    next.last_kind = ComposerStepKind::Other;
    Some(ComposerHistoryStep { history: next, snapshot })
}

/// Takes the step back again. None when there is nothing to redo.
#[uniffi::export]
pub fn composer_history_redo(history: ComposerHistory, current: ComposerSnapshot) -> Option<ComposerHistoryStep> {
    let mut next = history;
    let snapshot = next.future.pop()?;
    next.past.push(current);
    next.last_kind = ComposerStepKind::Other;
    Some(ComposerHistoryStep { history: next, snapshot })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::client::composer_rules::{composer_empty, composer_replace, composer_toggle_style, ComposerStyle, ComposerStyleKind};

    fn doc(text: &str) -> ComposerDoc {
        composer_replace(composer_empty(), 0, 0, text.to_owned(), ComposerStyle::default()).doc
    }
    fn snap(text: &str) -> ComposerSnapshot {
        ComposerSnapshot { doc: doc(text), selection_start: text.len() as u32, selection_end: text.len() as u32 }
    }

    #[test]
    fn typing_in_a_run_is_one_step_and_a_pause_starts_another() {
        let mut h = composer_history_empty();
        h = composer_history_push(h, snap(""), ComposerStepKind::Typing, 1_000);
        h = composer_history_push(h, snap("h"), ComposerStepKind::Typing, 1_200);
        h = composer_history_push(h, snap("he"), ComposerStepKind::Typing, 1_900);
        assert_eq!(h.past, vec![snap("")], "one step for the whole run");
        h = composer_history_push(h, snap("hel"), ComposerStepKind::Typing, 3_500);
        assert_eq!(h.past, vec![snap(""), snap("hel")], "a pause of more than a second starts a new step");
    }

    #[test]
    fn anything_but_typing_is_a_step_of_its_own_and_ends_the_run() {
        let mut h = composer_history_empty();
        h = composer_history_push(h, snap(""), ComposerStepKind::Typing, 0);
        h = composer_history_push(h, snap("hello"), ComposerStepKind::Other, 100);
        h = composer_history_push(h, snap("hello"), ComposerStepKind::Other, 150);
        h = composer_history_push(h, snap("hello"), ComposerStepKind::Typing, 200);
        h = composer_history_push(h, snap("hello!"), ComposerStepKind::Typing, 300);
        assert_eq!(h.past.len(), 4, "typing, two actions, then a new run of typing");
    }

    #[test]
    fn the_kind_of_an_edit() {
        assert_eq!(composer_step_kind(String::new(), "a".into()), ComposerStepKind::Typing);
        assert_eq!(composer_step_kind("a".into(), String::new()), ComposerStepKind::Typing, "one character deleted");
        assert_eq!(composer_step_kind(String::new(), "\n".into()), ComposerStepKind::Other, "Return");
        assert_eq!(composer_step_kind(String::new(), "pasted words".into()), ComposerStepKind::Other, "a paste");
        assert_eq!(composer_step_kind("ab".into(), "c".into()), ComposerStepKind::Other, "a replaced selection");
        assert_eq!(composer_step_kind("abc".into(), String::new()), ComposerStepKind::Other, "a selection deleted");
    }

    #[test]
    fn undo_and_redo_round_trip_one_step_at_a_time_with_styles() {
        let plain = snap("hello world");
        let bold = ComposerSnapshot { doc: composer_toggle_style(plain.doc.clone(), 0, 5, ComposerStyleKind::Bold), selection_start: 0, selection_end: 5 };
        let mut h = composer_history_empty();
        h = composer_history_push(h, plain.clone(), ComposerStepKind::Other, 0);   // the Bold action
        assert!(composer_history_can_undo(h.clone()) && !composer_history_can_redo(h.clone()));
        let undone = composer_history_undo(h, bold.clone()).expect("a step to undo");
        assert_eq!(undone.snapshot, plain, "text and styles back together");
        assert!(composer_history_can_redo(undone.history.clone()) && !composer_history_can_undo(undone.history.clone()));
        let redone = composer_history_redo(undone.history, plain).expect("a step to redo");
        assert_eq!(redone.snapshot, bold, "the bold is back");
        assert!(composer_history_undo(composer_history_empty(), bold).is_none(), "nothing to undo");
    }

    #[test]
    fn a_new_edit_clears_redo_and_the_next_typing_after_undo_is_a_new_step() {
        let mut h = composer_history_empty();
        h = composer_history_push(h, snap("a"), ComposerStepKind::Other, 0);
        let back = composer_history_undo(h, snap("ab")).unwrap();
        assert!(composer_history_can_redo(back.history.clone()));
        let after = composer_history_push(back.history, snap("a"), ComposerStepKind::Typing, 10);
        assert!(!composer_history_can_redo(after.clone()), "a new edit clears redo");
        assert_eq!(after.last_kind, ComposerStepKind::Typing);
        let again = composer_history_undo(after, snap("ac")).unwrap();
        let typed = composer_history_push(again.history, snap("a"), ComposerStepKind::Typing, 20);
        assert_eq!(typed.past.len(), 1, "typing right after an undo is a step of its own, not joined to the old run");
    }

    #[test]
    fn the_history_keeps_at_most_fifty_steps() {
        let mut h = composer_history_empty();
        for i in 0..60 {
            h = composer_history_push(h, snap(&format!("{i}")), ComposerStepKind::Other, i);
        }
        assert_eq!(h.past.len(), HISTORY_CAP);
        assert_eq!(h.past[0], snap("10"), "the oldest are dropped");
        assert_eq!(h.past[HISTORY_CAP - 1], snap("59"));
    }
}
