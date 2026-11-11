//! The rich-text composer's engine (LIME-404): what Bold, Italic, Underline, Strike, Code, Link, bulleted and numbered lists, and the Return, Backspace and "- "
//! typing rules do to a message being written, and the Markdown in and out. Mirrors `ios/Lime/Features/Chat/Composer/ComposerDocument.swift` (the pure text and
//! range logic; its `NSAttributedString` and font glue stays with each platform) and its tests (`ComposerDocumentTests.swift`).
//!
//! **The document.** `text` is only what the person wrote: **no list marker is a character of it**. Each line of `text` (split at `\n`) has a [`ComposerLine`]
//! (paragraph, bullet, number or code, a level 0 to 2, and the number a numbered run was started at); the marker a line shows ("•", "◦", "▪", "1.") is worked out
//! from the lines by [`composer_markers`] with the core's own marker rule, so a marker can never be cut in half (iOS keeps markers as characters and needs
//! `cleanUpAfterEdit` to repair that; none of that exists here). `runs` cover the whole text with the style and link of each stretch. **All offsets are UTF-16
//! code units** (what Kotlin and Swift index by). A document is a value: every operation returns a new one (and, for edits, where the selection goes).
//!
//! Only what a **chat** message can say is here: heading, quote, indent, button and divider are jam-post paragraph styles (the core's `Block` docs: "in a chat the
//! line stays text"), so the chat formatting strip has none of them, as on iOS. Mentions and pictures are not here either. iOS keeps its Swift until LIME-133b.

use crate::format::{self, Block, ListItem, Span};

/// The inline styles of a stretch of text.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, uniffi::Record)]
pub struct ComposerStyle {
    pub bold: bool,
    pub italic: bool,
    pub underline: bool,
    pub strike: bool,
    pub code: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ComposerStyleKind {
    Bold,
    Italic,
    Underline,
    Strike,
    Code,
}

/// One stretch of the text, `start` to `end` (UTF-16, end exclusive), with its style and an allowed link address.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ComposerRun {
    pub start: u32,
    pub end: u32,
    pub style: ComposerStyle,
    pub link: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ComposerLineKind {
    Paragraph,
    Bullet,
    Number,
    /// A line of a fenced code block: shown and sent verbatim.
    Code,
}

/// What one line of the text is.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct ComposerLine {
    pub kind: ComposerLineKind,
    /// 0 to 2 for a list item, else 0.
    pub level: u32,
    /// For a numbered item that begins a run: the number it was started at ("3. " typed), else 1. Later items count on from it.
    pub start: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ComposerDoc {
    pub text: String,
    pub runs: Vec<ComposerRun>,
    /// One per line of `text` (`text` split at `\n`: an empty text has one line).
    pub lines: Vec<ComposerLine>,
}

/// The result of an edit: the new document and where the selection goes (UTF-16).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ComposerEdit {
    pub doc: ComposerDoc,
    pub selection_start: u32,
    pub selection_end: u32,
}

/// What the formatting strip shows as pressed for a caret or selection.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, uniffi::Record)]
pub struct ComposerFormatState {
    pub bold: bool,
    pub italic: bool,
    pub underline: bool,
    pub strike: bool,
    pub code: bool,
    pub link: bool,
    pub bullets: bool,
    pub numbers: bool,
    /// The selection touches a list item (Indent and Outdent show), and whether each can change anything.
    pub in_list: bool,
    pub can_indent: bool,
    pub can_outdent: bool,
}

/// What an automatic list start replaced, so Backspace straight after it can give the typed text back.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ComposerAutoStart {
    /// Where the line starts (UTF-16).
    pub line_start: u32,
    /// What the person typed, with its space ("- ", "3. ").
    pub typed: String,
    /// What the line was before.
    pub old: ComposerLine,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ComposerAutoResult {
    pub edit: ComposerEdit,
    pub undo: ComposerAutoStart,
}

// ---------------------------------------------------------------- the working form

#[derive(Debug, Clone, PartialEq, Eq)]
struct Cell {
    ch: char,
    style: ComposerStyle,
    link: Option<String>,
}

const PLAIN_LINE: ComposerLine = ComposerLine { kind: ComposerLineKind::Paragraph, level: 0, start: 1 };

/// The document as one cell per character, to edit; offsets here are character indexes.
#[derive(Debug, Clone)]
struct Work {
    cells: Vec<Cell>,
    lines: Vec<ComposerLine>,
}

fn is_list(line: &ComposerLine) -> bool {
    matches!(line.kind, ComposerLineKind::Bullet | ComposerLineKind::Number)
}

impl Work {
    fn from_doc(doc: &ComposerDoc) -> Work {
        let mut cells = Vec::new();
        let mut unit = 0u32;
        let mut run = 0usize;
        for ch in doc.text.chars() {
            while run < doc.runs.len() && doc.runs[run].end <= unit {
                run += 1;
            }
            let (style, link) = doc.runs.get(run).filter(|r| r.start <= unit).map(|r| (r.style, r.link.clone())).unwrap_or_default();
            cells.push(Cell { ch, style, link });
            unit += ch.len_utf16() as u32;
        }
        let mut work = Work { cells, lines: doc.lines.clone() };
        work.fix_lines();
        work
    }

    /// One line record per line of text.
    fn fix_lines(&mut self) {
        let wanted = self.cells.iter().filter(|c| c.ch == '\n').count() + 1;
        self.lines.truncate(wanted);
        while self.lines.len() < wanted {
            self.lines.push(PLAIN_LINE);
        }
        for line in &mut self.lines {
            if !is_list(line) {
                line.level = 0;
                if line.kind != ComposerLineKind::Number {
                    line.start = 1;
                }
            }
            line.level = line.level.min(format::MAX_LIST_LEVEL);
        }
    }

    fn to_doc(&self) -> ComposerDoc {
        let mut text = String::new();
        let mut runs: Vec<ComposerRun> = Vec::new();
        let mut unit = 0u32;
        for cell in &self.cells {
            text.push(cell.ch);
            let end = unit + cell.ch.len_utf16() as u32;
            match runs.last_mut() {
                Some(last) if last.style == cell.style && last.link == cell.link => last.end = end,
                _ => runs.push(ComposerRun { start: unit, end, style: cell.style, link: cell.link.clone() }),
            }
            unit = end;
        }
        ComposerDoc { text, runs, lines: self.lines.clone() }
    }

    fn units(&self, upto: usize) -> u32 {
        self.cells[..upto.min(self.cells.len())].iter().map(|c| c.ch.len_utf16() as u32).sum()
    }

    /// A UTF-16 offset as a character index (an offset inside a surrogate pair goes to the character's start).
    fn index(&self, offset: u32) -> usize {
        let mut unit = 0u32;
        for (i, cell) in self.cells.iter().enumerate() {
            let next = unit + cell.ch.len_utf16() as u32;
            if offset < next {
                return i;
            }
            unit = next;
        }
        self.cells.len()
    }

    /// The content range of each line (characters, the newline not included).
    fn line_ranges(&self) -> Vec<(usize, usize)> {
        let mut out = Vec::new();
        let mut start = 0;
        for (i, cell) in self.cells.iter().enumerate() {
            if cell.ch == '\n' {
                out.push((start, i));
                start = i + 1;
            }
        }
        out.push((start, self.cells.len()));
        out
    }

    /// The line a character index is in (an index at a line's end is in that line).
    fn line_of(&self, at: usize) -> usize {
        let ranges = self.line_ranges();
        ranges.iter().position(|&(_, end)| at <= end).unwrap_or(ranges.len() - 1)
    }

    /// The lines a selection touches.
    fn touched(&self, from: usize, to: usize) -> std::ops::RangeInclusive<usize> {
        let first = self.line_of(from);
        let last = if to > from { self.line_of(to) } else { first };
        // A selection that ends right after a newline does not touch the next line.
        let last = if to > from && last > first && self.line_ranges()[last].0 == to { last - 1 } else { last };
        first..=last
    }

    fn edit(&self, from: usize, to: usize) -> ComposerEdit {
        ComposerEdit { doc: self.to_doc(), selection_start: self.units(from), selection_end: self.units(to) }
    }

    /// Replaces `from..to` with `text` in `style`: the line the range starts in keeps its kind (a list item stays one item through a delete that joins lines);
    /// a newline typed or pasted splits the line and both halves keep its kind and level.
    fn replace(&mut self, from: usize, to: usize, text: &str, style: ComposerStyle) -> usize {
        let (from, to) = (from.min(self.cells.len()), to.min(self.cells.len()));
        let (first, last) = (self.line_of(from), self.line_of(to));
        if to > from {
            self.cells.drain(from..to);
            self.lines.drain(first + 1..=last);
        }
        let mut at = from;
        let mut line = first;
        for ch in text.chars() {
            if ch == '\n' {
                self.cells.insert(at, Cell { ch, style: ComposerStyle::default(), link: None });
                let current = self.lines[line];
                let next = match current.kind {
                    ComposerLineKind::Paragraph => PLAIN_LINE,
                    ComposerLineKind::Code => ComposerLine { kind: ComposerLineKind::Code, level: 0, start: 1 },
                    _ => ComposerLine { start: 1, ..current },
                };
                self.lines.insert(line + 1, next);
                line += 1;
            } else {
                self.cells.insert(at, Cell { ch, style, link: None });
            }
            at += 1;
        }
        self.fix_lines();
        at
    }
}

// ---------------------------------------------------------------- markdown

fn spans_of(cells: &[Cell]) -> Vec<Span> {
    let mut spans: Vec<Span> = Vec::new();
    for cell in cells {
        match spans.last_mut() {
            Some(last) if last.bold == cell.style.bold && last.italic == cell.style.italic && last.underline == cell.style.underline && last.strike == cell.style.strike && last.code == cell.style.code && last.link == cell.link => {
                last.text.push(cell.ch)
            }
            _ => spans.push(Span {
                text: cell.ch.to_string(),
                bold: cell.style.bold,
                italic: cell.style.italic,
                underline: cell.style.underline,
                strike: cell.style.strike,
                code: cell.style.code,
                link: cell.link.clone(),
                mention: None,
            }),
        }
    }
    spans
}

fn blocks_of(work: &Work) -> Vec<Block> {
    let mut blocks: Vec<Block> = Vec::new();
    let mut paragraph: Vec<Span> = Vec::new();
    let mut items: Vec<ListItem> = Vec::new();
    let mut code: Vec<String> = Vec::new();
    let flush_paragraph = |blocks: &mut Vec<Block>, paragraph: &mut Vec<Span>| {
        if !paragraph.is_empty() {
            blocks.push(Block::Paragraph { spans: std::mem::take(paragraph) });
        }
    };
    let flush_list = |blocks: &mut Vec<Block>, items: &mut Vec<ListItem>| {
        if !items.is_empty() {
            blocks.push(Block::ItemList { items: std::mem::take(items) });
        }
    };
    let flush_code = |blocks: &mut Vec<Block>, code: &mut Vec<String>| {
        if !code.is_empty() {
            blocks.push(Block::Code { text: code.join("\n") });
            code.clear();
        }
    };
    for (line, (start, end)) in work.lines.iter().zip(work.line_ranges()) {
        let content = &work.cells[start..end];
        match line.kind {
            ComposerLineKind::Code => {
                flush_paragraph(&mut blocks, &mut paragraph);
                flush_list(&mut blocks, &mut items);
                code.push(content.iter().map(|c| c.ch).collect());
            }
            ComposerLineKind::Bullet | ComposerLineKind::Number => {
                flush_paragraph(&mut blocks, &mut paragraph);
                flush_code(&mut blocks, &mut code);
                let spans = spans_of(content);
                if !spans.is_empty() {
                    let ordered = line.kind == ComposerLineKind::Number;
                    items.push(ListItem { level: line.level.min(format::MAX_LIST_LEVEL), ordered, number: if ordered { line.start.max(1) } else { 0 }, spans });
                }
            }
            ComposerLineKind::Paragraph => {
                flush_list(&mut blocks, &mut items);
                flush_code(&mut blocks, &mut code);
                if content.is_empty() {
                    flush_paragraph(&mut blocks, &mut paragraph); // a blank line ends the paragraph
                } else {
                    let mut line_spans = spans_of(content);
                    if !paragraph.is_empty() {
                        line_spans.insert(0, Span { text: "\n".to_owned(), ..Span::default() });
                    }
                    paragraph.extend(line_spans);
                }
            }
        }
    }
    flush_paragraph(&mut blocks, &mut paragraph);
    flush_list(&mut blocks, &mut items);
    flush_code(&mut blocks, &mut code);
    blocks
}

fn push_spans(cells: &mut Vec<Cell>, lines_out: &mut Vec<ComposerLine>, spans: &[Span], line: ComposerLine) {
    // A span's text may hold line breaks (a paragraph's lines): each makes a new line of the same kind.
    for span in spans {
        let style = ComposerStyle { bold: span.bold, italic: span.italic, underline: span.underline, strike: span.strike, code: span.code };
        for ch in span.text.chars() {
            if ch == '\n' {
                cells.push(Cell { ch, style: ComposerStyle::default(), link: None });
                lines_out.push(line);
            } else {
                cells.push(Cell { ch, style, link: span.link.clone() });
            }
        }
    }
}

fn work_from_markdown(markdown: &str) -> Work {
    let blocks = format::parse(markdown);
    let mut cells: Vec<Cell> = Vec::new();
    let mut lines: Vec<ComposerLine> = Vec::new();
    for (index, block) in blocks.iter().enumerate() {
        if index > 0 {
            // The blank line between blocks: the line that ended, a newline, and an empty paragraph line, a newline.
            cells.push(Cell { ch: '\n', style: ComposerStyle::default(), link: None });
            cells.push(Cell { ch: '\n', style: ComposerStyle::default(), link: None });
            if lines.is_empty() {
                lines.push(PLAIN_LINE);
            }
            lines.push(PLAIN_LINE);
        }
        match block {
            Block::Paragraph { spans } => {
                lines.push(PLAIN_LINE);
                push_spans(&mut cells, &mut lines, spans, PLAIN_LINE);
            }
            Block::Code { text } => {
                let code = ComposerLine { kind: ComposerLineKind::Code, level: 0, start: 1 };
                lines.push(code);
                for ch in text.chars() {
                    if ch == '\n' {
                        cells.push(Cell { ch, style: ComposerStyle::default(), link: None });
                        lines.push(code);
                    } else {
                        cells.push(Cell { ch, style: ComposerStyle::default(), link: None });
                    }
                }
            }
            Block::ItemList { items } => {
                let markers = format::list_markers(items.clone());
                let from_one = format::list_markers(items.iter().map(|i| ListItem { number: 1, spans: Vec::new(), ..i.clone() }).collect());
                for (n, item) in items.iter().enumerate() {
                    if n > 0 {
                        cells.push(Cell { ch: '\n', style: ComposerStyle::default(), link: None });
                    }
                    let start = if item.ordered && from_one[n] == "1." && markers[n] != "1." { markers[n].trim_end_matches('.').parse().unwrap_or(1) } else { 1 };
                    let line = ComposerLine { kind: if item.ordered { ComposerLineKind::Number } else { ComposerLineKind::Bullet }, level: item.level.min(format::MAX_LIST_LEVEL), start };
                    lines.push(line);
                    push_spans(&mut cells, &mut lines, &item.spans, line);
                }
            }
            // A chat parse makes no other block (they are jam-post only).
            _ => {}
        }
    }
    let mut work = Work { cells, lines };
    work.fix_lines();
    work
}

/// A new, empty document.
#[uniffi::export]
pub fn composer_empty() -> ComposerDoc {
    Work { cells: Vec::new(), lines: vec![PLAIN_LINE] }.to_doc()
}

/// A message's Markdown as a document (to edit a sent message, or a draft).
#[uniffi::export]
pub fn composer_from_markdown(markdown: String) -> ComposerDoc {
    work_from_markdown(&markdown).to_doc()
}

/// The text to send: the canonical Markdown (empty when there is nothing but spaces).
#[uniffi::export]
pub fn composer_to_markdown(doc: ComposerDoc) -> String {
    format::serialize(&blocks_of(&Work::from_doc(&doc)))
}

/// The words without markup (what a list preview or a notification shows).
#[uniffi::export]
pub fn composer_plain_text(doc: ComposerDoc) -> String {
    format::plain_text(&composer_to_markdown(doc))
}

/// The marker each line shows: "•", "◦" or "▪" for a bullet by level, "1." for a number counted per level (from the number the run was started at), and "" for any
/// other line.
#[uniffi::export]
pub fn composer_markers(doc: ComposerDoc) -> Vec<String> {
    let mut out = vec![String::new(); doc.lines.len()];
    let mut at = 0;
    while at < doc.lines.len() {
        if !is_list(&doc.lines[at]) {
            at += 1;
            continue;
        }
        let mut end = at;
        while end < doc.lines.len() && is_list(&doc.lines[end]) {
            end += 1;
        }
        let items: Vec<ListItem> = doc.lines[at..end]
            .iter()
            .map(|l| ListItem { level: l.level, ordered: l.kind == ComposerLineKind::Number, number: l.start.max(1), spans: Vec::new() })
            .collect();
        for (i, marker) in format::list_markers(items).into_iter().enumerate() {
            out[at + i] = marker;
        }
        at = end;
    }
    out
}

// ---------------------------------------------------------------- editing

/// Replaces the selection with `text` written in `style` (typing, a paste, a delete when `text` is empty). A newline splits the line and both halves keep its
/// kind. The caret ends after the new text.
#[uniffi::export]
pub fn composer_replace(doc: ComposerDoc, start: u32, end: u32, text: String, style: ComposerStyle) -> ComposerEdit {
    let mut work = Work::from_doc(&doc);
    let (from, to) = (work.index(start.min(end)), work.index(start.max(end)));
    let at = work.replace(from, to, &text, style);
    work.edit(at, at)
}

/// What Return does. Inside a list it starts the next item at the same level and kind; on an empty item it steps out one level, or at the top level ends the list.
/// Anywhere else (a code line included) it is an ordinary new line.
#[uniffi::export]
pub fn composer_enter(doc: ComposerDoc, start: u32, end: u32, style: ComposerStyle) -> ComposerEdit {
    let mut work = Work::from_doc(&doc);
    let (from, to) = (work.index(start.min(end)), work.index(start.max(end)));
    if from == to {
        let line = work.line_of(from);
        let (ls, le) = work.line_ranges()[line];
        if is_list(&work.lines[line]) && ls == le {
            if work.lines[line].level > 0 {
                work.lines[line].level -= 1;
            } else {
                work.lines[line] = PLAIN_LINE;
            }
            return work.edit(from, from);
        }
    }
    let at = work.replace(from, to, "\n", style);
    work.edit(at, at)
}

/// What a single Backspace does at the very start of a list item's text: a nested item steps out one level, a top-level one becomes plain text. None when
/// the caret is anywhere else (the app deletes a character with `composer_replace`).
#[uniffi::export]
pub fn composer_backspace(doc: ComposerDoc, caret: u32) -> Option<ComposerEdit> {
    let mut work = Work::from_doc(&doc);
    let at = work.index(caret);
    let line = work.line_of(at);
    let (ls, _) = work.line_ranges()[line];
    if at != ls || !is_list(&work.lines[line]) {
        return None;
    }
    if work.lines[line].level > 0 {
        work.lines[line].level -= 1;
    } else {
        work.lines[line] = PLAIN_LINE;
    }
    Some(work.edit(at, at))
}

fn all_have(cells: &[Cell], test: impl Fn(&Cell) -> bool) -> bool {
    let words: Vec<&Cell> = cells.iter().filter(|c| c.ch != '\n').collect();
    !words.is_empty() && words.iter().all(|c| test(c))
}

fn has_style(cell: &Cell, kind: ComposerStyleKind) -> bool {
    match kind {
        ComposerStyleKind::Bold => cell.style.bold,
        ComposerStyleKind::Italic => cell.style.italic,
        ComposerStyleKind::Underline => cell.style.underline,
        ComposerStyleKind::Strike => cell.style.strike,
        ComposerStyleKind::Code => cell.style.code,
    }
}

fn set_style(cell: &mut Cell, kind: ComposerStyleKind, on: bool) {
    match kind {
        ComposerStyleKind::Bold => cell.style.bold = on,
        ComposerStyleKind::Italic => cell.style.italic = on,
        ComposerStyleKind::Underline => cell.style.underline = on,
        ComposerStyleKind::Strike => cell.style.strike = on,
        ComposerStyleKind::Code => cell.style.code = on,
    }
}

/// Turns a style on for the selection, or off when every character already has it. A caret changes nothing (the app keeps the style to type with).
#[uniffi::export]
pub fn composer_toggle_style(doc: ComposerDoc, start: u32, end: u32, kind: ComposerStyleKind) -> ComposerDoc {
    let mut work = Work::from_doc(&doc);
    let (from, to) = (work.index(start.min(end)), work.index(start.max(end)));
    if from == to {
        return doc;
    }
    let on = !all_have(&work.cells[from..to], |c| has_style(c, kind));
    for cell in &mut work.cells[from..to] {
        set_style(cell, kind, on);
    }
    work.to_doc()
}

/// Sets a link on the selection (only an allowed address: http, https or mailto), or takes it off with None. A refused address changes nothing.
#[uniffi::export]
pub fn composer_set_link(doc: ComposerDoc, start: u32, end: u32, url: Option<String>) -> ComposerDoc {
    let mut work = Work::from_doc(&doc);
    let (from, to) = (work.index(start.min(end)), work.index(start.max(end)));
    if from == to {
        return doc;
    }
    if let Some(url) = &url {
        if !format::allowed_link(url) {
            return doc;
        }
    }
    for cell in &mut work.cells[from..to] {
        cell.link = url.clone();
    }
    work.to_doc()
}

/// What a person typed for a link, as the address it will be (iOS `LinkInput.url`): no scheme gets https://, an address with an @ and no slash gets mailto:, and the
/// core decides what is a link (http, https and mailto only). None when it is not one. http stays http.
#[uniffi::export]
pub fn composer_link_url(input: String) -> Option<String> {
    let mut text = input.trim().to_owned();
    if text.is_empty() || text.contains(' ') || text.chars().any(char::is_whitespace) {
        return None;
    }
    if !text.contains("://") && !text.to_lowercase().starts_with("mailto:") {
        text = if text.contains('@') && !text.contains('/') { format!("mailto:{text}") } else { format!("https://{text}") };
    }
    // A web address needs a usable host and, when it names a port, a number (as Swift's `URL(string:)` insists).
    let lower = text.to_lowercase();
    if let Some(rest) = lower.strip_prefix("https://").or_else(|| lower.strip_prefix("http://")) {
        let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
        let host_port = authority.rsplit('@').next().unwrap_or("");
        let port_ok = match host_port.rsplit_once(':') {
            Some((host, port)) if !host_port.starts_with('[') => !host.is_empty() && !port.is_empty() && port.chars().all(|c| c.is_ascii_digit()),
            _ => true,
        };
        if host_port.is_empty() || !port_ok {
            return None;
        }
    }
    match format::parse(&format!("[x]({text})")).first() {
        Some(Block::Paragraph { spans }) if spans.first().and_then(|s| s.link.as_deref()) == Some(text.as_str()) => Some(text),
        _ => None,
    }
}

/// The style the next typed character gets: the style of the character before the caret (so a bold run goes on while typing and ends when turned off).
#[uniffi::export]
pub fn composer_style_at(doc: ComposerDoc, caret: u32) -> ComposerStyle {
    let work = Work::from_doc(&doc);
    let at = work.index(caret);
    if at == 0 {
        return ComposerStyle::default();
    }
    let cell = &work.cells[at - 1];
    if cell.ch == '\n' { ComposerStyle::default() } else { cell.style }
}

/// Makes the touched lines a list of `kind` (Bullet or Number), or plain again when they all already are. An item switching kind keeps its level.
#[uniffi::export]
pub fn composer_toggle_list(doc: ComposerDoc, start: u32, end: u32, kind: ComposerLineKind) -> ComposerDoc {
    if !matches!(kind, ComposerLineKind::Bullet | ComposerLineKind::Number) {
        return doc;
    }
    let mut work = Work::from_doc(&doc);
    let (from, to) = (work.index(start.min(end)), work.index(start.max(end)));
    let touched = work.touched(from, to);
    let all_same = touched.clone().all(|i| work.lines[i].kind == kind);
    for i in touched {
        let old = work.lines[i];
        work.lines[i] = if all_same { PLAIN_LINE } else { ComposerLine { kind, level: if is_list(&old) { old.level } else { 0 }, start: 1 } };
    }
    work.to_doc()
}

/// Code: over several lines it makes (or unmakes) a code block; a caret in a code block unmakes it; otherwise it toggles inline code on the selection.
#[uniffi::export]
pub fn composer_toggle_code(doc: ComposerDoc, start: u32, end: u32) -> ComposerDoc {
    let mut work = Work::from_doc(&doc);
    let (from, to) = (work.index(start.min(end)), work.index(start.max(end)));
    let multi_line = to > from && work.cells[from..to].iter().any(|c| c.ch == '\n');
    let touched = work.touched(from, to);
    let in_block = !work.cells.is_empty() && touched.clone().all(|i| work.lines[i].kind == ComposerLineKind::Code);
    if multi_line || (in_block && from == to) {
        for i in touched {
            work.lines[i] = if in_block { PLAIN_LINE } else { ComposerLine { kind: ComposerLineKind::Code, level: 0, start: 1 } };
        }
        return work.to_doc();
    }
    drop(work);
    if to > from { composer_toggle_style(doc, start, end, ComposerStyleKind::Code) } else { doc }
}

/// The level each touched list item takes when indented or outdented: an item goes at most one level deeper than the item above it (and not past level 2); outdent stops at 0.
fn shifted(work: &Work, from: usize, to: usize, indent: bool) -> Vec<(usize, u32, u32)> {
    let touched = work.touched(from, to);
    let mut previous: Option<u32> = None;
    let mut out = Vec::new();
    for (i, line) in work.lines.iter().enumerate() {
        if !is_list(line) {
            previous = None;
            continue;
        }
        if touched.contains(&i) {
            let target = format::list_level_after(previous, line.level, indent);
            out.push((i, line.level, target));
            previous = Some(target);
        } else {
            previous = Some(line.level);
        }
    }
    out
}

/// Indents or outdents every list item the selection touches.
#[uniffi::export]
pub fn composer_shift_list(doc: ComposerDoc, start: u32, end: u32, indent: bool) -> ComposerDoc {
    let mut work = Work::from_doc(&doc);
    let (from, to) = (work.index(start.min(end)), work.index(start.max(end)));
    for (i, _, target) in shifted(&work, from, to, indent) {
        work.lines[i].level = target;
    }
    work.to_doc()
}

/// Called after a space was typed at the caret: when the text before it in the line is exactly a list marker (the core's `list_trigger`: "- ", "* ", "• ", "3. "), the
/// line becomes a list item and the typed marker goes. Inside a list item the item switches kind and keeps its level. Never in a code line.
#[uniffi::export]
pub fn composer_auto_start(doc: ComposerDoc, caret: u32) -> Option<ComposerAutoResult> {
    let mut work = Work::from_doc(&doc);
    let at = work.index(caret);
    if at == 0 || work.cells[at - 1].ch != ' ' {
        return None;
    }
    let line = work.line_of(at);
    let (ls, _) = work.line_ranges()[line];
    let old = work.lines[line];
    if old.kind == ComposerLineKind::Code || at <= ls {
        return None;
    }
    let typed: String = work.cells[ls..at].iter().map(|c| c.ch).collect();
    let trigger = format::list_trigger(typed.clone())?;
    let level = if is_list(&old) { old.level } else { trigger.level };
    let undo = ComposerAutoStart { line_start: work.units(ls), typed, old };
    work.cells.drain(ls..at);
    work.lines[line] = ComposerLine {
        kind: if trigger.ordered { ComposerLineKind::Number } else { ComposerLineKind::Bullet },
        level,
        start: if trigger.ordered && trigger.number != 1 { trigger.number } else { 1 },
    };
    Some(ComposerAutoResult { edit: work.edit(ls, ls), undo })
}

/// Undoes `composer_auto_start` (Backspace straight after it): the typed marker comes back as plain text and the line is what it was. None when the text is no longer as it
/// was left (the caret moved, or the line is not the item it made).
#[uniffi::export]
pub fn composer_undo_auto_start(doc: ComposerDoc, undo: ComposerAutoStart, caret: u32) -> Option<ComposerEdit> {
    let mut work = Work::from_doc(&doc);
    let ls = work.index(undo.line_start);
    if work.index(caret) != ls || ls > work.cells.len() {
        return None;
    }
    let line = work.line_of(ls);
    if work.line_ranges()[line].0 != ls || !is_list(&work.lines[line]) {
        return None;
    }
    work.lines[line] = undo.old;
    let at = work.replace(ls, ls, &undo.typed, ComposerStyle::default());
    work.lines[line] = undo.old;
    Some(work.edit(at, at))
}

/// What the strip shows pressed for a caret or selection: a style is pressed only when every character of a selection has it (for a caret, when the character before it
/// does); the lines touched say lists, and whether Indent and Outdent can change anything.
#[uniffi::export]
pub fn composer_format_state(doc: ComposerDoc, start: u32, end: u32) -> ComposerFormatState {
    let work = Work::from_doc(&doc);
    let (from, to) = (work.index(start.min(end)), work.index(start.max(end)));
    let mut state = ComposerFormatState::default();
    if to > from {
        let cells = &work.cells[from..to];
        state.bold = all_have(cells, |c| c.style.bold);
        state.italic = all_have(cells, |c| c.style.italic);
        state.underline = all_have(cells, |c| c.style.underline);
        state.strike = all_have(cells, |c| c.style.strike);
        state.code = all_have(cells, |c| c.style.code);
        state.link = all_have(cells, |c| c.link.is_some());
    } else if from > 0 && work.cells[from - 1].ch != '\n' {
        let before = &work.cells[from - 1];
        state.bold = before.style.bold;
        state.italic = before.style.italic;
        state.underline = before.style.underline;
        state.strike = before.style.strike;
        state.code = before.style.code;
        state.link = before.link.is_some() && work.cells.get(from).is_some_and(|c| c.link == before.link);
    }
    let touched: Vec<usize> = work.touched(from, to).collect();
    state.bullets = touched.iter().all(|&i| work.lines[i].kind == ComposerLineKind::Bullet);
    state.numbers = touched.iter().all(|&i| work.lines[i].kind == ComposerLineKind::Number);
    state.in_list = touched.iter().any(|&i| is_list(&work.lines[i]));
    if state.in_list {
        state.can_indent = shifted(&work, from, to, true).iter().any(|&(_, a, b)| a != b);
        state.can_outdent = shifted(&work, from, to, false).iter().any(|&(_, a, b)| a != b);
    }
    state
}

#[cfg(test)]
mod tests {
    use super::*;
    use ComposerLineKind::{Bullet, Code, Number, Paragraph};
    use ComposerStyleKind::{Bold, Code as InlineCode, Italic, Strike, Underline};

    const PLAIN: ComposerStyle = ComposerStyle { bold: false, italic: false, underline: false, strike: false, code: false };

    fn typed(text: &str) -> ComposerDoc {
        composer_replace(composer_empty(), 0, 0, text.to_owned(), PLAIN).doc
    }
    fn md(doc: &ComposerDoc) -> String {
        composer_to_markdown(doc.clone())
    }
    fn len(doc: &ComposerDoc) -> u32 {
        doc.text.encode_utf16().count() as u32
    }
    fn at(doc: &ComposerDoc, needle: &str) -> (u32, u32) {
        let byte = doc.text.find(needle).unwrap();
        let start = doc.text[..byte].encode_utf16().count() as u32;
        (start, start + needle.encode_utf16().count() as u32)
    }
    fn kinds(doc: &ComposerDoc) -> Vec<ComposerLineKind> {
        doc.lines.iter().map(|l| l.kind).collect()
    }

    /// Plays the keystrokes the text field would give: the app calls these same functions (ComposerNestedListTests' `Typist`).
    struct Typist {
        doc: ComposerDoc,
        caret: u32,
        started: Option<ComposerAutoStart>,
    }
    impl Typist {
        fn new() -> Typist {
            Typist { doc: composer_empty(), caret: 0, started: None }
        }
        fn from_markdown(markdown: &str) -> Typist {
            let doc = composer_from_markdown(markdown.to_owned());
            let caret = len(&doc);
            Typist { doc, caret, started: None }
        }
        fn type_text(&mut self, text: &str) {
            for ch in text.chars() {
                self.key(ch);
            }
        }
        fn key(&mut self, ch: char) {
            self.started = None;
            if ch == '\n' {
                let edit = composer_enter(self.doc.clone(), self.caret, self.caret, composer_style_at(self.doc.clone(), self.caret));
                self.doc = edit.doc;
                self.caret = edit.selection_end;
                return;
            }
            let style = composer_style_at(self.doc.clone(), self.caret);
            let edit = composer_replace(self.doc.clone(), self.caret, self.caret, ch.to_string(), style);
            self.doc = edit.doc;
            self.caret = edit.selection_end;
            if ch == ' ' {
                if let Some(auto) = composer_auto_start(self.doc.clone(), self.caret) {
                    self.doc = auto.edit.doc;
                    self.caret = auto.edit.selection_end;
                    self.started = Some(auto.undo);
                }
            }
        }
        fn backspace(&mut self) {
            if let Some(undo) = self.started.take() {
                if let Some(edit) = composer_undo_auto_start(self.doc.clone(), undo, self.caret) {
                    self.doc = edit.doc;
                    self.caret = edit.selection_end;
                    return;
                }
            }
            if let Some(edit) = composer_backspace(self.doc.clone(), self.caret) {
                self.doc = edit.doc;
                self.caret = edit.selection_end;
                return;
            }
            if self.caret > 0 {
                let edit = composer_replace(self.doc.clone(), self.caret - 1, self.caret, String::new(), PLAIN);
                self.doc = edit.doc;
                self.caret = edit.selection_end;
            }
        }
        fn indent(&mut self, indent: bool) {
            self.doc = composer_shift_list(self.doc.clone(), self.caret, self.caret, indent);
        }
        /// What the document shows: each line with its marker, as iOS's attributed string reads.
        fn shown(&self) -> String {
            let markers = composer_markers(self.doc.clone());
            self.doc.text.split('\n').zip(markers).map(|(line, marker)| if marker.is_empty() { line.to_owned() } else { format!("{marker} {line}") }).collect::<Vec<_>>().join("\n")
        }
        fn markdown(&self) -> String {
            md(&self.doc)
        }
    }

    fn round_trip(markdown: &str) {
        let doc = composer_from_markdown(markdown.to_owned());
        assert_eq!(md(&doc), format::normalise(markdown), "{markdown:?}");
    }

    // ComposerDocumentTests.testEveryInlineStyleSurvivesTheRoundTrip
    #[test]
    fn every_inline_style_survives_the_round_trip() {
        for m in [
            "plain words", "a **bold** word", "an *italic* word", "an __underlined__ word", "a ~~struck~~ word", "some `code` here",
            "a [link](https://limemessenger.com/x?y=1) here", "mailto [me](mailto:a@b.co) and [web](http://a.b)", "**bold *and italic* together** ~~__all__~~", "[**bold link**](https://a.b)",
        ] {
            round_trip(m);
        }
    }

    // testBlocksSurviveTheRoundTrip
    #[test]
    fn blocks_survive_the_round_trip() {
        for m in [
            "- one\n- two\n- three", "1. first\n2. second\n3. third", "- parent\n  - child\n- next", "1. a\n  1. b\n2. c", "```\nlet a = 1\nlet b = **raw**\n```", "before\n\n```\ncode\n```\n\nafter",
            "intro **bold**\n\n- item with `code` and *italics*\n- [link](https://a.b)\n\n```\nblock\n```", "line one\nline two\n\nnew paragraph",
        ] {
            round_trip(m);
        }
    }

    // testTextThatLooksLikeMarkupIsKeptAsTyped
    #[test]
    fn text_that_looks_like_markup_is_kept_as_typed() {
        for text in ["2 * 3 * 4", "snake_case_name", "a ~ b", "[not a link](nowhere)", "1. not a list", "- not a list", "use ``` fences", "# not a heading", "a\\b"] {
            let doc = typed(text);
            let markdown = md(&doc);
            assert_eq!(format::plain_text(&markdown), text, "what was typed is what is read back: {text}");
            assert!(format::parse(&markdown).iter().all(|b| matches!(b, Block::Paragraph { .. })), "{text}");
        }
        assert_eq!(md(&typed("2 * 3")), "2 \\* 3");
    }

    // testSpacesAreKeptOutsideTheMarkers
    #[test]
    fn spaces_are_kept_outside_the_markers() {
        let doc = composer_from_markdown("a **b** c".to_owned());
        let (s, e) = at(&doc, "b ");
        assert_eq!(md(&composer_toggle_style(doc, s, e, Bold)), "a **b** c", "the trailing space of the selection stays outside the markers");
    }

    // testBoldTogglesOnAndOffForASelection
    #[test]
    fn bold_toggles_on_and_off_for_a_selection() {
        let doc = typed("make this bold now");
        let (s, e) = at(&doc, "this");
        let bold = composer_toggle_style(doc, s, e, Bold);
        assert_eq!(md(&bold), "make **this** bold now");
        assert!(composer_format_state(bold.clone(), s, e).bold);
        assert!(!composer_format_state(bold.clone(), 0, 6).bold, "pressed only when every character has it");
        assert_eq!(md(&composer_toggle_style(bold, s, e, Bold)), "make this bold now");
    }

    // testAMixedSelectionTurnsTheStyleOnForAll
    #[test]
    fn a_mixed_selection_turns_the_style_on_for_all() {
        let doc = composer_from_markdown("one **two** three".to_owned());
        let all = len(&doc);
        let on = composer_toggle_style(doc, 0, all, Bold);
        assert_eq!(md(&on), "**one two three**", "partly bold: bold for all");
        assert_eq!(md(&composer_toggle_style(on, 0, all, Bold)), "one two three", "now all bold: off");
    }

    // testEveryStyleAppliesAndStacks
    #[test]
    fn every_style_applies_and_stacks() {
        let mut doc = typed("styled");
        for kind in [Bold, Italic, Underline, Strike] {
            doc = composer_toggle_style(doc, 0, 6, kind);
        }
        assert_eq!(md(&doc), "~~__***styled***__~~");
        let state = composer_format_state(doc, 0, 6);
        assert!(state.bold && state.italic && state.underline && state.strike);
        assert!(!(state.code || state.link || state.bullets || state.numbers));
    }

    // testCaretStateComesFromTheTypingAttributes
    #[test]
    fn the_caret_state_comes_from_the_character_before_it() {
        let doc = composer_replace(typed("ab"), 2, 2, "c".to_owned(), ComposerStyle { italic: true, ..PLAIN }).doc;
        let state = composer_format_state(doc.clone(), 3, 3);
        assert!(state.italic && !state.bold);
        assert_eq!(composer_style_at(doc, 3), ComposerStyle { italic: true, ..PLAIN });
        assert_eq!(composer_style_at(composer_empty(), 0), PLAIN);
    }

    // testALinkIsAddedAndCleared
    #[test]
    fn a_link_is_added_and_cleared() {
        let doc = typed("see the plan today");
        let (s, e) = at(&doc, "the plan");
        let linked = composer_set_link(doc.clone(), s, e, Some("https://limemessenger.com/plan".to_owned()));
        assert_eq!(md(&linked), "see [the plan](https://limemessenger.com/plan) today");
        assert!(composer_format_state(linked.clone(), s, e).link);
        assert_eq!(md(&composer_set_link(linked, s, e, None)), "see the plan today");
        assert_eq!(md(&composer_set_link(doc, s, e, Some("javascript:alert(1)".to_owned()))), "see the plan today", "a refused address changes nothing");
    }

    // ComposerTypingTests.testLinkInputIsCheckedByTheCore
    #[test]
    fn link_input_is_checked_by_the_core() {
        assert_eq!(composer_link_url("limemessenger.com/plan".into()).as_deref(), Some("https://limemessenger.com/plan"));
        assert_eq!(composer_link_url("http://a.b".into()).as_deref(), Some("http://a.b"), "http stays http in a chat");
        assert_eq!(composer_link_url("me@example.com".into()).as_deref(), Some("mailto:me@example.com"));
        assert_eq!(composer_link_url("mailto:me@example.com".into()).as_deref(), Some("mailto:me@example.com"));
        for refused in ["javascript:alert(1)", "data:text/html,x", "ftp://a.b", "file:///etc/passwd", "", "   ", "two words", "https://"] {
            assert_eq!(composer_link_url(refused.into()), None, "{refused}");
        }
    }

    // testABulletedListFromTwoLinesAndBackToPlain
    #[test]
    fn a_bulleted_list_from_two_lines_and_back_to_plain() {
        let doc = typed("apples\nbananas");
        let all = len(&doc);
        let list = composer_toggle_list(doc, 0, all, Bullet);
        assert_eq!(list.text, "apples\nbananas", "the markers are not in the text");
        assert_eq!(composer_markers(list.clone()), ["•", "•"]);
        assert_eq!(md(&list), "- apples\n- bananas");
        assert!(composer_format_state(list.clone(), 0, all).bullets);
        let plain = composer_toggle_list(list, 0, all, Bullet);
        assert_eq!(md(&plain), "apples\nbananas");
        assert_eq!(kinds(&plain), [Paragraph, Paragraph]);
    }

    // testANumberedListCountsAndSwitchingKindsReplacesTheMarker
    #[test]
    fn a_numbered_list_counts_and_switching_kinds_replaces_the_marker() {
        let doc = typed("one\ntwo\nthree");
        let all = len(&doc);
        let numbered = composer_toggle_list(doc, 0, all, Number);
        assert_eq!(composer_markers(numbered.clone()), ["1.", "2.", "3."]);
        assert_eq!(md(&numbered), "1. one\n2. two\n3. three");
        let bullets = composer_toggle_list(numbered, 0, all, Bullet);
        assert_eq!(composer_markers(bullets), ["•", "•", "•"], "a numbered list becomes a bulleted one");
    }

    // testReturnInAListContinuesItAndOnAnEmptyItemEndsIt
    #[test]
    fn return_in_a_list_continues_it_and_on_an_empty_item_ends_it() {
        let mut t = Typist::new();
        t.type_text("first");
        t.doc = composer_toggle_list(t.doc.clone(), 5, 5, Number);
        t.key('\n');
        assert_eq!(t.shown(), "1. first\n2. ", "the next item starts with the next number");
        t.type_text("second");
        assert_eq!(t.markdown(), "1. first\n2. second");
        t.key('\n');
        assert_eq!(t.shown(), "1. first\n2. second\n3. ");
        t.key('\n'); // Return on the empty third item ends the list
        assert_eq!(t.shown(), "1. first\n2. second\n");
        assert_eq!(t.markdown(), "1. first\n2. second");
        // Return outside a list is an ordinary new line.
        let mut plain = Typist::new();
        plain.type_text("plain\n");
        assert_eq!(plain.doc.text, "plain\n");
    }

    // testRemovingAnItemRenumbers
    #[test]
    fn removing_an_item_renumbers() {
        let doc = composer_from_markdown("1. a\n2. b\n3. c".to_owned());
        let (s, e) = at(&doc, "b\n");
        let after = composer_replace(doc, s, e, String::new(), PLAIN).doc;
        assert_eq!(after.text, "a\nc");
        assert_eq!(composer_markers(after), ["1.", "2."]);
    }

    // testACodeBlockAcrossLinesAndInlineCodeForAWord
    #[test]
    fn a_code_block_across_lines_and_inline_code_for_a_word() {
        let doc = typed("let a = 1\nlet b = 2");
        let all = len(&doc);
        let block = composer_toggle_code(doc, 0, all);
        assert_eq!(md(&block), "```\nlet a = 1\nlet b = 2\n```");
        assert_eq!(kinds(&block), [Code, Code]);
        let plain = composer_toggle_code(block, 0, all);
        assert_eq!(md(&plain), "let a = 1\nlet b = 2", "the same selection again turns it back to plain lines");
        let inline = typed("call run() now");
        let (s, e) = at(&inline, "run()");
        let code = composer_toggle_code(inline, s, e);
        assert_eq!(md(&code), "call `run()` now");
        assert!(composer_format_state(code, s, e).code);
        assert_eq!(composer_toggle_style(typed("x"), 0, 1, InlineCode).runs[0].style.code, true);
    }

    // testACodeBlockInTheMiddleOfAMessage
    #[test]
    fn a_code_block_in_the_middle_of_a_message() {
        let doc = composer_from_markdown("Here is the fix:\n\n```\nx = 1\n```\n\nThanks".to_owned());
        assert_eq!(md(&doc), "Here is the fix:\n\n```\nx = 1\n```\n\nThanks");
        let blocks = blocks_of(&Work::from_doc(&doc));
        assert_eq!(blocks.len(), 3);
        assert!(matches!(&blocks[1], Block::Code { text } if text == "x = 1"));
    }

    // testBlankLinesSeparateParagraphsAndNewlinesAreLineBreaks
    #[test]
    fn blank_lines_separate_paragraphs_and_newlines_are_line_breaks() {
        assert_eq!(md(&typed("line one\nline two\n\nsecond paragraph")), "line one\nline two\n\nsecond paragraph");
        assert_eq!(md(&typed("  \n")), "");
    }

    // testThePlainTextOfAComposedMessageHasNoMarkup
    #[test]
    fn the_plain_text_of_a_composed_message_has_no_markup() {
        let doc = composer_from_markdown("**Hi** [team](https://a.b)\n\n- one\n- two".to_owned());
        assert_eq!(composer_plain_text(doc), "Hi team\n• one\n• two");
    }

    // ComposerNestedListTests.testTypingAMarkerAndASpaceStartsAList
    #[test]
    fn typing_a_marker_and_a_space_starts_a_list() {
        for (text, shown, markdown) in [("- ", "• x", "- x"), ("* ", "• x", "- x"), ("• ", "• x", "- x"), ("1. ", "1. x", "1. x"), ("3. ", "3. x", "3. x"), ("  - ", "◦ x", "  - x")] {
            let mut t = Typist::new();
            t.type_text(&format!("{text}x"));
            assert_eq!(t.shown(), shown, "{text:?}");
            assert_eq!(t.markdown(), markdown, "{text:?}");
            assert_ne!(t.doc.lines[0].kind, Paragraph, "{text:?}");
        }
    }

    // testANumberedListStartsAtTheTypedNumberAndCountsOn
    #[test]
    fn a_numbered_list_starts_at_the_typed_number_and_counts_on() {
        let mut t = Typist::new();
        t.type_text("3. one\ntwo");
        assert_eq!(t.shown(), "3. one\n4. two");
        assert_eq!(t.markdown(), "3. one\n4. two");
    }

    // testThingsThatLookLikeAMarkerStayText
    #[test]
    fn things_that_look_like_a_marker_stay_text() {
        for text in ["-5", "1.5 x", "a - b", "text 1. more", "-- x", "1234567890. x"] {
            let mut t = Typist::new();
            t.type_text(text);
            assert_eq!(t.shown(), text, "{text}");
            assert_eq!(t.doc.lines[0].kind, Paragraph, "{text}");
        }
    }

    // testNothingStartsInsideACodeBlock
    #[test]
    fn nothing_starts_inside_a_code_block() {
        let mut code = Typist { doc: composer_from_markdown("```\ncode\n```".to_owned()), caret: 4, started: None };
        code.type_text(" - ");
        assert_eq!(code.doc.text, "code - ");
        assert_eq!(code.doc.lines[0].kind, Code);
    }

    // testBackspaceRightAfterTheConversionGivesBackWhatWasTyped
    #[test]
    fn backspace_right_after_the_conversion_gives_back_what_was_typed() {
        let mut t = Typist::new();
        t.type_text("- ");
        assert_eq!(t.shown(), "• ");
        t.backspace();
        assert_eq!(t.shown(), "- ");
        assert_eq!(t.doc.lines[0].kind, Paragraph, "the paragraph is plain again");
        assert_eq!(t.caret, 2);
        // Any other keystroke first commits the list.
        let mut u = Typist::new();
        u.type_text("1. a");
        u.caret = 0;
        u.backspace();
        assert_eq!(u.shown(), "a", "after other typing, Backspace at the start removes the marker as before");
    }

    // testATypedMarkerInsideAListSwitchesTheKindAndBackspaceRestoresIt
    #[test]
    fn a_typed_marker_inside_a_list_switches_the_kind_and_backspace_restores_it() {
        let mut t = Typist::new();
        t.type_text("- one\n1. ");
        assert_eq!(t.shown(), "• one\n1. ", "a numbered marker typed in a bulleted list switches that item");
        assert_eq!(t.doc.lines[1].kind, Number);
        t.backspace();
        assert_eq!(t.shown(), "• one\n• 1. ", "undo returns the item and the typed text");
        assert_eq!(t.doc.lines[1].kind, Bullet);
    }

    // testAThreeLevelOutlineByTyping
    #[test]
    fn a_three_level_outline_by_typing() {
        let mut t = Typist::new();
        t.type_text("- a\n");
        t.indent(true);
        t.type_text("b\n");
        t.indent(true);
        t.type_text("c");
        assert_eq!(t.shown(), "• a\n◦ b\n▪ c");
        assert_eq!(t.markdown(), "- a\n  - b\n    - c");
        t.indent(true);
        assert_eq!(t.markdown(), "- a\n  - b\n    - c", "the level 2 item cannot go deeper");
        assert_eq!(md(&composer_from_markdown(t.markdown())), t.markdown());
    }

    // testIndentIsLimitedByTheItemAbove
    #[test]
    fn indent_is_limited_by_the_item_above() {
        let mut t = Typist::new();
        t.type_text("- a");
        t.indent(true);
        assert_eq!(t.markdown(), "- a", "the first item cannot be indented");
        t.type_text("\nb");
        t.indent(true);
        t.indent(true);
        assert_eq!(t.markdown(), "- a\n  - b", "one deeper than the item above, at most");
        t.indent(false);
        assert_eq!(t.markdown(), "- a\n- b");
        t.indent(false);
        assert_eq!(t.markdown(), "- a\n- b", "outdent stops at level 0");
        let state = composer_format_state(t.doc.clone(), t.caret, t.caret);
        assert!(state.in_list && state.can_indent && !state.can_outdent);
    }

    // testIndentAppliesToEveryItemInTheSelection
    #[test]
    fn indent_applies_to_every_item_in_the_selection() {
        let doc = composer_from_markdown("- a\n- b\n- c".to_owned());
        let all = len(&doc);
        assert_eq!(md(&composer_shift_list(doc, 0, all, true)), "- a\n  - b\n  - c", "the first item has nothing above; the others go one in");
        assert!(!composer_format_state(typed("plain"), 0, 0).in_list);
    }

    // testReturnContinuesTheLevelAndAnEmptyNestedItemStepsOut
    #[test]
    fn return_continues_the_level_and_an_empty_nested_item_steps_out() {
        let mut t = Typist::new();
        t.type_text("1. a\n");
        t.indent(true);
        t.type_text("b\n");
        assert_eq!(t.shown(), "1. a\n1. b\n2. ", "the next item has the same level and kind, counted per level");
        assert_eq!(t.doc.lines[2].level, 1);
        t.key('\n'); // Return on the empty nested item
        assert_eq!(t.doc.lines[2].level, 0, "steps back out one level");
        assert_eq!(t.shown(), "1. a\n1. b\n2. ");
        t.key('\n'); // Return on the empty top item ends the list
        assert_eq!(t.shown(), "1. a\n1. b\n");
        assert_eq!(t.doc.lines[2].kind, Paragraph, "the next line is plain text again");
        assert_eq!(t.markdown(), "1. a\n  1. b");
    }

    // testBackspaceAtTheStartOfANestedItemOutdentsThenRemovesTheMarker
    #[test]
    fn backspace_at_the_start_of_a_nested_item_outdents_then_removes_the_marker() {
        let mut t = Typist::from_markdown("- a\n  - b\n    - c");
        t.caret = at(&t.doc, "c").0;
        t.backspace();
        assert_eq!(t.markdown(), "- a\n  - b\n  - c", "level 3 steps out to level 2");
        t.backspace();
        assert_eq!(t.markdown(), "- a\n  - b\n- c");
        t.backspace();
        assert_eq!(t.shown(), "• a\n◦ b\nc", "at level 0 the marker goes (as before)");
    }

    // testMarkersAndNumbersAcrossThreeLevelsSurviveMarkdown
    #[test]
    fn markers_and_numbers_across_three_levels_survive_markdown() {
        let markdown = "1. a\n  1. b\n    1. c\n    2. d\n  2. e\n2. f\n  1. g";
        let doc = composer_from_markdown(markdown.to_owned());
        assert_eq!(composer_markers(doc.clone()), ["1.", "1.", "1.", "2.", "2.", "2.", "1."]);
        assert_eq!(md(&doc), markdown);
        assert_eq!(composer_markers(composer_from_markdown("- a\n  - b\n    - c".to_owned())), ["•", "◦", "▪"]);
        assert_eq!(composer_markers(composer_from_markdown("3. a\n4. b".to_owned())), ["3.", "4."], "a run started at another number keeps it");
    }

    // ComposerDeletionTests: select all and delete leaves nothing; a selection from the middle of one item to the middle of another leaves one item at the first item's kind.
    #[test]
    fn deleting_a_selection_removes_exactly_the_selection_and_leaves_one_item_at_the_first_items_kind() {
        let doc = composer_from_markdown("- a\n  - b\n    - c".to_owned());
        let all = len(&doc);
        let cleared = composer_replace(doc, 0, all, String::new(), PLAIN).doc;
        assert_eq!((cleared.text.as_str(), cleared.lines.len()), ("", 1));
        let mixed = composer_from_markdown("- apple\n  - banana\n1. one".to_owned());
        let (s, _) = at(&mixed, "pple");
        let (_, e) = at(&mixed, "ban");
        let joined = composer_replace(mixed, s, e, String::new(), PLAIN).doc;
        assert_eq!(joined.text, "aana\none");
        assert_eq!((joined.lines[0].kind, joined.lines[0].level), (Bullet, 0), "the first item's level and kind");
        assert_eq!(joined.lines.len(), 2);
        // A selection from plain text into a list leaves plain text and no stray marker.
        let from_plain = composer_from_markdown("plain\n\n- item".to_owned());
        let (a, _) = at(&from_plain, "ain");
        let (_, b) = at(&from_plain, "it");
        let merged = composer_replace(from_plain, a, b, String::new(), PLAIN).doc;
        assert_eq!(merged.text, "plem");
        assert_eq!(kinds(&merged), [Paragraph]);
        // Backspace over the line break joins two items without a stray marker.
        let two = composer_from_markdown("- a\n- b".to_owned());
        let nl = at(&two, "\n").0;
        let one = composer_replace(two, nl, nl + 1, String::new(), PLAIN).doc;
        assert_eq!((one.text.as_str(), kinds(&one)), ("ab", vec![Bullet]));
    }

    #[test]
    fn a_paste_with_lines_inside_a_list_makes_items_and_text_with_marks_is_plain() {
        let list = composer_toggle_list(typed("x"), 0, 1, Bullet);
        let pasted = composer_replace(list, 1, 1, "\ny\nz".to_owned(), PLAIN).doc;
        assert_eq!(md(&pasted), "- x\n- y\n- z");
        // Offsets are UTF-16: an emoji is two units.
        let emoji = composer_replace(typed("a"), 1, 1, "😀b".to_owned(), PLAIN);
        assert_eq!((emoji.doc.text.as_str(), emoji.selection_end), ("a😀b", 4));
        let bold = composer_toggle_style(emoji.doc, 1, 3, Bold);
        assert_eq!(md(&bold), "a**😀**b");
    }
}
