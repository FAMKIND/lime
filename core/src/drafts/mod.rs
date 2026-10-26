//! Co-editing: the draft document (LIME-233a, DESIGN-22).
//!
//! A draft of an article is an Automerge document, so several people can write it at once and every phone ends with the same text. This module is
//! the document itself and has no store, no network and no UI: [`DraftDoc`] holds one document, applies local edits, exports to and imports from the
//! Markdown the posts already use (so **publishing is unchanged**), and turns what a merge changed into [`DraftPatch`]es the editor can apply.
//!
//! The shape (one document per draft):
//! ```text
//! root { title: Text, subtitle: Text, cover: str, blocks: List<Map> }
//! block { id, kind, level, ordered, number, attachment, caption, url, colour, text: Text with marks }
//! kind: paragraph | h1..h6 | quote | indent | item | code | image | button | divider | freewall
//! marks on text: bold, italic, underline, strike, code (true), link (the address), mention (the person's id)
//! ```
//! Positions in this API are **characters** (Unicode scalars), never bytes or UTF-16 units; the app converts.

use automerge::marks::{ExpandMark, Mark};
use automerge::transaction::Transactable;
use automerge::{AutoCommit, ChangeHash, ObjId, ObjType, ReadDoc, ScalarValue, Value, ROOT};

use crate::format::{self, Block, ListItem, Span};
use crate::store::StoreError;

/// The most text a draft may hold (DESIGN-22 §9: about 200 KB per article; pictures are separate).
pub const MAX_DRAFT_BYTES: usize = 200_000;
/// A draft is saved as one document again after this many changes since its last full save.
pub const COMPACT_AFTER_CHANGES: u32 = 200;
const MAX_BLOCKS: usize = 2_000;

/// One block of a draft, as the editor sees it.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct DraftBlock {
    pub id: String,
    /// `paragraph`, `h1` to `h6`, `quote`, `indent`, `item`, `code`, `image`, `button`, `divider`, `freewall`.
    pub kind: String,
    /// A list item's nesting (0 to 2).
    pub level: u32,
    /// A list item is numbered.
    pub ordered: bool,
    /// The number written for a numbered item.
    pub number: u32,
    /// An image, video or audio block: the post's n-th attachment.
    pub attachment: u32,
    /// An image's caption, or a button's line above it.
    pub caption: String,
    /// A button's address.
    pub url: String,
    /// A button's palette colour name.
    pub colour: String,
    /// The block's words with their styles (a button's text, a code block's text, an image has none).
    pub spans: Vec<Span>,
}

/// The draft's own fields.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct DraftMeta {
    pub title: String,
    pub subtitle: String,
    /// The cover's file id, or empty.
    pub cover: String,
}

/// What changed in the document, for the editor to apply in order. Text positions are characters within the block.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum DraftPatch {
    /// A block appeared at `index`.
    Inserted { index: u32, block: DraftBlock },
    Removed { id: String },
    /// After the removals and insertions above, the block is at `index`.
    Moved { id: String, index: u32 },
    /// `deleted` characters at `start` were replaced by `inserted`.
    Text { block_id: String, start: u32, deleted: u32, inserted: String },
    /// The block's styles or settings changed (the whole block, to redraw).
    Changed { block: DraftBlock },
    Meta { meta: DraftMeta },
}

/// A block to put into a draft.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct DraftBlockInput {
    pub kind: String,
    pub level: u32,
    pub ordered: bool,
    pub number: u32,
    pub attachment: u32,
    pub caption: String,
    pub url: String,
    pub colour: String,
    pub spans: Vec<Span>,
}

const KINDS: &[&str] = &["paragraph", "h1", "h2", "h3", "h4", "h5", "h6", "quote", "indent", "item", "code", "image", "button", "divider", "freewall"];

fn bad<T>(_: T) -> StoreError {
    StoreError::BadMessage
}

pub struct DraftDoc {
    doc: AutoCommit,
    blocks: ObjId,
    title: ObjId,
    subtitle: ObjId,
    /// An upper bound on the bytes of text, kept up to date cheaply; the exact count is worked out only when this says the limit may be near.
    approx_bytes: usize,
    /// What the editor has already drawn (set by [`DraftDoc::mark_seen`]); [`DraftDoc::take_patches`] is what changed since.
    ui_seen: Option<(Vec<DraftBlock>, DraftMeta)>,
}

impl DraftDoc {
    /// An empty draft: no blocks yet (the editor shows one empty paragraph).
    pub fn new() -> Result<Self, StoreError> {
        let mut doc = AutoCommit::new();
        let title = doc.put_object(ROOT, "title", ObjType::Text).map_err(bad)?;
        let subtitle = doc.put_object(ROOT, "subtitle", ObjType::Text).map_err(bad)?;
        let blocks = doc.put_object(ROOT, "blocks", ObjType::List).map_err(bad)?;
        doc.put(ROOT, "cover", "").map_err(bad)?;
        Ok(Self { doc, blocks, title, subtitle, approx_bytes: 0, ui_seen: None })
    }

    /// A draft from a post's Markdown (an existing article being edited together, or a new one with text already in it).
    pub fn from_markdown(title: &str, subtitle: &str, markdown: &str) -> Result<Self, StoreError> {
        let mut d = Self::new()?;
        d.set_text(&d.title.clone(), title)?;
        d.set_text(&d.subtitle.clone(), subtitle)?;
        d.import_markdown(markdown)?;
        Ok(d)
    }

    pub fn load(bytes: &[u8]) -> Result<Self, StoreError> {
        let doc = AutoCommit::load(bytes).map_err(bad)?;
        Self::attach(doc)
    }

    fn attach(doc: AutoCommit) -> Result<Self, StoreError> {
        let obj = |name: &str| -> Result<ObjId, StoreError> {
            match doc.get(ROOT, name).map_err(bad)? {
                Some((Value::Object(_), id)) => Ok(id),
                _ => Err(StoreError::BadMessage),
            }
        };
        let (blocks, title, subtitle) = (obj("blocks")?, obj("title")?, obj("subtitle")?);
        let mut me = Self { doc, blocks, title, subtitle, approx_bytes: 0, ui_seen: None };
        me.approx_bytes = me.text_bytes();
        Ok(me)
    }

    /// The editor now shows the document as it is (after its own edit, or after applying patches).
    pub fn mark_seen(&mut self) {
        self.ui_seen = Some((self.blocks(), self.meta()));
    }

    /// What changed since the editor last saw the document (remote changes that arrived meanwhile), and marks it seen.
    pub fn take_patches(&mut self) -> Vec<DraftPatch> {
        let now = (self.blocks(), self.meta());
        let patches = match &self.ui_seen {
            Some((blocks, meta)) => diff(blocks, meta, &now.0, &now.1),
            None => Vec::new(),
        };
        self.ui_seen = Some(now);
        patches
    }

    /// The whole document as one compact byte string.
    pub fn save(&mut self) -> Vec<u8> {
        self.doc.save()
    }

    /// What changed since the last save (or load), as bytes to append to what is stored; empty when nothing did.
    pub fn save_incremental(&mut self) -> Vec<u8> {
        self.doc.save_incremental()
    }

    /// A copy that evolves apart (a second author's replica).
    pub fn fork(&mut self) -> Result<Self, StoreError> {
        let doc = self.doc.fork();
        Self::attach(doc)
    }

    // ------------------------------------------------------------------------------------------- reading

    fn get_str(&self, obj: &ObjId, key: &str) -> String {
        match self.doc.get(obj, key) {
            Ok(Some((Value::Scalar(s), _))) => match s.as_ref() {
                ScalarValue::Str(s) => s.to_string(),
                _ => String::new(),
            },
            _ => String::new(),
        }
    }

    fn get_u32(&self, obj: &ObjId, key: &str) -> u32 {
        match self.doc.get(obj, key) {
            Ok(Some((Value::Scalar(s), _))) => match s.as_ref() {
                ScalarValue::Uint(n) => *n as u32,
                ScalarValue::Int(n) => (*n).max(0) as u32,
                _ => 0,
            },
            _ => 0,
        }
    }

    fn get_bool(&self, obj: &ObjId, key: &str) -> bool {
        matches!(self.doc.get(obj, key), Ok(Some((Value::Scalar(s), _))) if matches!(s.as_ref(), ScalarValue::Boolean(true)))
    }

    fn block_obj(&self, index: usize) -> Option<ObjId> {
        match self.doc.get(&self.blocks, index) {
            Ok(Some((Value::Object(_), id))) => Some(id),
            _ => None,
        }
    }

    fn text_obj(&self, block: &ObjId) -> Option<ObjId> {
        match self.doc.get(block, "text") {
            Ok(Some((Value::Object(_), id))) => Some(id),
            _ => None,
        }
    }

    pub fn block_count(&self) -> usize {
        self.doc.length(&self.blocks)
    }

    /// The index of the block with this id.
    pub fn index_of(&self, id: &str) -> Option<usize> {
        (0..self.block_count()).find(|i| self.block_obj(*i).is_some_and(|b| self.get_str(&b, "id") == id))
    }

    fn spans_of(&self, text: &ObjId) -> Vec<Span> {
        let plain: Vec<char> = self.doc.text(text).unwrap_or_default().chars().collect();
        if plain.is_empty() {
            return Vec::new();
        }
        let marks = self.doc.marks(text).unwrap_or_default();
        // Every place a mark starts or ends cuts the text.
        let mut cuts: Vec<usize> = vec![0, plain.len()];
        for m in &marks {
            cuts.push(m.start.min(plain.len()));
            cuts.push(m.end.min(plain.len()));
        }
        cuts.sort_unstable();
        cuts.dedup();
        let mut spans: Vec<Span> = Vec::new();
        for pair in cuts.windows(2) {
            let (start, end) = (pair[0], pair[1]);
            if start == end {
                continue;
            }
            let mut span = Span { text: plain[start..end].iter().collect(), ..Span::default() };
            for m in marks.iter().filter(|m| m.start <= start && m.end >= end) {
                match (m.name(), m.value()) {
                    ("bold", ScalarValue::Boolean(true)) => span.bold = true,
                    ("italic", ScalarValue::Boolean(true)) => span.italic = true,
                    ("underline", ScalarValue::Boolean(true)) => span.underline = true,
                    ("strike", ScalarValue::Boolean(true)) => span.strike = true,
                    ("code", ScalarValue::Boolean(true)) => span.code = true,
                    ("link", ScalarValue::Str(url)) => span.link = Some(url.to_string()),
                    ("mention", ScalarValue::Str(id)) => span.mention = Some(id.to_string()),
                    _ => {}
                }
            }
            // Adjacent runs with the same styles are one span.
            match spans.last_mut() {
                Some(last) if same_style(last, &span) => last.text.push_str(&span.text),
                _ => spans.push(span),
            }
        }
        spans
    }

    fn read_block(&self, block: &ObjId) -> DraftBlock {
        DraftBlock {
            id: self.get_str(block, "id"),
            kind: self.get_str(block, "kind"),
            level: self.get_u32(block, "level"),
            ordered: self.get_bool(block, "ordered"),
            number: self.get_u32(block, "number"),
            attachment: self.get_u32(block, "attachment"),
            caption: self.get_str(block, "caption"),
            url: self.get_str(block, "url"),
            colour: self.get_str(block, "colour"),
            spans: self.text_obj(block).map(|t| self.spans_of(&t)).unwrap_or_default(),
        }
    }

    pub fn blocks(&self) -> Vec<DraftBlock> {
        (0..self.block_count()).filter_map(|i| self.block_obj(i)).map(|b| self.read_block(&b)).collect()
    }

    pub fn meta(&self) -> DraftMeta {
        DraftMeta { title: self.doc.text(&self.title).unwrap_or_default(), subtitle: self.doc.text(&self.subtitle).unwrap_or_default(), cover: self.get_str(&ROOT, "cover") }
    }

    /// The plain text of a block (its characters).
    pub fn block_text(&self, id: &str) -> Option<String> {
        let block = self.block_obj(self.index_of(id)?)?;
        Some(self.text_obj(&block).map(|t| self.doc.text(&t).unwrap_or_default()).unwrap_or_default())
    }

    /// How many bytes of text the draft holds (every block, the title and the subtitle).
    pub fn text_bytes(&self) -> usize {
        let blocks: usize = (0..self.block_count()).filter_map(|i| self.block_obj(i)).filter_map(|b| self.text_obj(&b)).map(|t| self.doc.text(&t).map(|s| s.len()).unwrap_or(0)).sum();
        blocks + self.doc.text(&self.title).map(|s| s.len()).unwrap_or(0) + self.doc.text(&self.subtitle).map(|s| s.len()).unwrap_or(0)
    }

    // ------------------------------------------------------------------------------------------- writing

    fn set_text(&mut self, text: &ObjId, to: &str) -> Result<(), StoreError> {
        self.approx_bytes += to.len();
        let len = self.doc.text(text).map_err(bad)?.chars().count();
        self.doc.splice_text(text, 0, len as isize, to).map_err(bad)
    }

    fn check_room(&mut self, adding: usize) -> Result<(), StoreError> {
        if self.block_count() >= MAX_BLOCKS && adding == 0 {
            return Err(StoreError::Rejected);
        }
        if self.approx_bytes + adding > MAX_DRAFT_BYTES {
            self.approx_bytes = self.text_bytes();
            if self.approx_bytes + adding > MAX_DRAFT_BYTES {
                return Err(StoreError::Rejected);
            }
        }
        self.approx_bytes += adding;
        Ok(())
    }

    pub fn set_title(&mut self, title: &str) -> Result<(), StoreError> {
        self.check_room(title.len())?;
        let t = self.title.clone();
        self.set_text(&t, title)
    }

    pub fn set_subtitle(&mut self, subtitle: &str) -> Result<(), StoreError> {
        self.check_room(subtitle.len())?;
        let t = self.subtitle.clone();
        self.set_text(&t, subtitle)
    }

    pub fn set_cover(&mut self, file_id: &str) -> Result<(), StoreError> {
        self.doc.put(ROOT, "cover", file_id).map_err(bad)
    }

    fn write_block(&mut self, index: usize, id: &str, input: &DraftBlockInput, list_start: bool) -> Result<(), StoreError> {
        if !KINDS.contains(&input.kind.as_str()) {
            return Err(StoreError::Rejected);
        }
        let block = self.doc.insert_object(&self.blocks, index, ObjType::Map).map_err(bad)?;
        self.doc.put(&block, "id", id).map_err(bad)?;
        self.doc.put(&block, "kind", input.kind.as_str()).map_err(bad)?;
        self.doc.put(&block, "level", input.level as u64).map_err(bad)?;
        self.doc.put(&block, "ordered", input.ordered).map_err(bad)?;
        self.doc.put(&block, "number", input.number as u64).map_err(bad)?;
        self.doc.put(&block, "attachment", input.attachment as u64).map_err(bad)?;
        self.doc.put(&block, "caption", input.caption.as_str()).map_err(bad)?;
        self.doc.put(&block, "url", input.url.as_str()).map_err(bad)?;
        self.doc.put(&block, "colour", input.colour.as_str()).map_err(bad)?;
        self.doc.put(&block, "list_start", list_start).map_err(bad)?;
        let text = self.doc.put_object(&block, "text", ObjType::Text).map_err(bad)?;
        let mut at = 0usize;
        for span in &input.spans {
            if span.text.is_empty() {
                continue;
            }
            self.doc.splice_text(&text, at, 0, &span.text).map_err(bad)?;
            let end = at + span.text.chars().count();
            for (name, on) in [("bold", span.bold), ("italic", span.italic), ("underline", span.underline), ("strike", span.strike), ("code", span.code)] {
                if on {
                    self.doc.mark(&text, Mark::new(name.to_string(), true, at, end), ExpandMark::None).map_err(bad)?;
                }
            }
            if let Some(url) = &span.link {
                self.doc.mark(&text, Mark::new("link".to_string(), url.as_str(), at, end), ExpandMark::None).map_err(bad)?;
            }
            if let Some(who) = &span.mention {
                self.doc.mark(&text, Mark::new("mention".to_string(), who.as_str(), at, end), ExpandMark::None).map_err(bad)?;
            }
            at = end;
        }
        Ok(())
    }

    /// Puts a block at `index` (clamped to the end) and returns its id.
    pub fn insert_block(&mut self, index: usize, input: &DraftBlockInput) -> Result<String, StoreError> {
        let adding: usize = input.spans.iter().map(|s| s.text.len()).sum();
        self.check_room(adding)?;
        let id = uuid::Uuid::new_v4().simple().to_string();
        let index = index.min(self.block_count());
        self.write_block(index, &id, input, false)?;
        Ok(id)
    }

    pub fn delete_block(&mut self, id: &str) -> Result<(), StoreError> {
        let index = self.index_of(id).ok_or(StoreError::NotFound)?;
        self.doc.delete(&self.blocks, index).map_err(bad)
    }

    /// Moves a block to `to` (an index in the list as it is after the move). Done as a delete and a re-insert with the same id and content.
    pub fn move_block(&mut self, id: &str, to: usize) -> Result<(), StoreError> {
        let from = self.index_of(id).ok_or(StoreError::NotFound)?;
        let block = self.block_obj(from).ok_or(StoreError::NotFound)?;
        let read = self.read_block(&block);
        let input = DraftBlockInput { kind: read.kind, level: read.level, ordered: read.ordered, number: read.number, attachment: read.attachment, caption: read.caption, url: read.url, colour: read.colour, spans: read.spans };
        self.doc.delete(&self.blocks, from).map_err(bad)?;
        let to = to.min(self.block_count());
        let list_start = self.get_bool(&block, "list_start");
        self.write_block(to, id, &input, list_start)
    }

    fn block_for(&self, id: &str) -> Result<ObjId, StoreError> {
        self.block_obj(self.index_of(id).ok_or(StoreError::NotFound)?).ok_or(StoreError::NotFound)
    }

    /// Changes a block's kind (and a list item's level, order and number).
    pub fn set_block_kind(&mut self, id: &str, kind: &str, level: u32, ordered: bool, number: u32) -> Result<(), StoreError> {
        if !KINDS.contains(&kind) {
            return Err(StoreError::Rejected);
        }
        let block = self.block_for(id)?;
        self.doc.put(&block, "kind", kind).map_err(bad)?;
        self.doc.put(&block, "level", level.min(format::MAX_LIST_LEVEL) as u64).map_err(bad)?;
        self.doc.put(&block, "ordered", ordered).map_err(bad)?;
        self.doc.put(&block, "number", number as u64).map_err(bad)
    }

    /// A button's address, caption and colour, or an image's caption and attachment.
    pub fn set_block_attrs(&mut self, id: &str, url: &str, caption: &str, colour: &str, attachment: u32) -> Result<(), StoreError> {
        let block = self.block_for(id)?;
        self.doc.put(&block, "url", url).map_err(bad)?;
        self.doc.put(&block, "caption", caption).map_err(bad)?;
        self.doc.put(&block, "colour", colour).map_err(bad)?;
        self.doc.put(&block, "attachment", attachment as u64).map_err(bad)
    }

    pub fn insert_text(&mut self, id: &str, at: usize, text: &str) -> Result<(), StoreError> {
        self.check_room(text.len())?;
        let block = self.block_for(id)?;
        let t = self.text_obj(&block).ok_or(StoreError::NotFound)?;
        let len = self.doc.text(&t).map_err(bad)?.chars().count();
        self.doc.splice_text(&t, at.min(len), 0, text).map_err(bad)
    }

    pub fn delete_text(&mut self, id: &str, at: usize, count: usize) -> Result<(), StoreError> {
        let block = self.block_for(id)?;
        let t = self.text_obj(&block).ok_or(StoreError::NotFound)?;
        let len = self.doc.text(&t).map_err(bad)?.chars().count();
        let at = at.min(len);
        self.doc.splice_text(&t, at, count.min(len - at) as isize, "").map_err(bad)
    }

    /// Styles `start..end` of a block: `bold`, `italic`, `underline`, `strike`, `code` (value ignored), `link` or `mention` (the value).
    pub fn mark(&mut self, id: &str, start: usize, end: usize, name: &str, value: Option<&str>) -> Result<(), StoreError> {
        let block = self.block_for(id)?;
        let t = self.text_obj(&block).ok_or(StoreError::NotFound)?;
        let len = self.doc.text(&t).map_err(bad)?.chars().count();
        let (start, end) = (start.min(len), end.min(len));
        if start >= end {
            return Ok(());
        }
        let mark = match (name, value) {
            ("bold" | "italic" | "underline" | "strike" | "code", _) => Mark::new(name.to_string(), true, start, end),
            ("link", Some(url)) if format::allowed_link(url) => Mark::new(name.to_string(), url, start, end),
            ("mention", Some(who)) if format::valid_mention_id(who) => Mark::new(name.to_string(), who, start, end),
            _ => return Err(StoreError::Rejected),
        };
        self.doc.mark(&t, mark, ExpandMark::None).map_err(bad)
    }

    pub fn unmark(&mut self, id: &str, start: usize, end: usize, name: &str) -> Result<(), StoreError> {
        let block = self.block_for(id)?;
        let t = self.text_obj(&block).ok_or(StoreError::NotFound)?;
        let len = self.doc.text(&t).map_err(bad)?.chars().count();
        let (start, end) = (start.min(len), end.min(len));
        if start >= end {
            return Ok(());
        }
        self.doc.unmark(&t, name, start, end, ExpandMark::None).map_err(bad)
    }

    // ------------------------------------------------------------------------------------------- Markdown

    /// Replaces the blocks with a post's Markdown (the title and subtitle stay).
    pub fn import_markdown(&mut self, markdown: &str) -> Result<(), StoreError> {
        if markdown.len() > MAX_DRAFT_BYTES {
            return Err(StoreError::Rejected);
        }
        while self.block_count() > 0 {
            self.doc.delete(&self.blocks, 0).map_err(bad)?;
        }
        let mut index = 0;
        for block in format::parse_post(markdown) {
            for (n, input) in inputs_of(block).into_iter().enumerate() {
                let id = uuid::Uuid::new_v4().simple().to_string();
                // The first item of each list starts it, so two lists in a row stay two lists.
                self.write_block(index, &id, &input, n == 0)?;
                index += 1;
            }
        }
        self.approx_bytes = self.text_bytes();
        Ok(())
    }

    /// The post's Markdown: the same text the editor makes today (consecutive list items are one list).
    pub fn export_markdown(&self) -> String {
        self.export_markdown_numbered(&|n| n)
    }

    /// The attachment numbers of the image blocks, in the order they appear (a number once).
    pub fn image_numbers(&self) -> Vec<u32> {
        let mut out: Vec<u32> = Vec::new();
        for b in self.blocks() {
            if b.kind == "image" && !out.contains(&b.attachment) {
                out.push(b.attachment);
            }
        }
        out
    }

    /// `export_markdown`, with each picture's number run through `number` (a post numbers its files from 0).
    pub fn export_markdown_numbered(&self, number: &dyn Fn(u32) -> u32) -> String {
        let mut blocks: Vec<Block> = Vec::new();
        for b in self.blocks() {
            match b.kind.as_str() {
                "item" => {
                    let starts = self.index_of(&b.id).and_then(|i| self.block_obj(i)).is_some_and(|o| self.get_bool(&o, "list_start"));
                    let item = ListItem { level: b.level, ordered: b.ordered, number: b.number, spans: b.spans };
                    match blocks.last_mut() {
                        Some(Block::ItemList { items }) if !starts => items.push(item),
                        _ => blocks.push(Block::ItemList { items: vec![item] }),
                    }
                }
                "paragraph" => blocks.push(Block::Paragraph { spans: b.spans }),
                "code" => blocks.push(Block::Code { text: b.spans.iter().map(|s| s.text.as_str()).collect() }),
                "image" => blocks.push(Block::Image { caption: b.caption, attachment: number(b.attachment) }),
                "quote" => blocks.push(Block::Quote { spans: b.spans }),
                "indent" => blocks.push(Block::Indent { spans: b.spans }),
                "divider" => blocks.push(Block::Divider),
                "freewall" => blocks.push(Block::Freewall),
                "button" => blocks.push(Block::Button { text: b.spans.iter().map(|s| s.text.as_str()).collect(), url: b.url, caption: b.caption, colour: b.colour }),
                heading if heading.starts_with('h') => blocks.push(Block::Heading { level: heading[1..].parse().unwrap_or(1), spans: b.spans }),
                _ => {}
            }
        }
        format::serialize_post(&blocks)
    }


    // ------------------------------------------------------------------------------------------- the editor's view

    fn list_start_of(&self, id: &str) -> bool {
        self.index_of(id).and_then(|i| self.block_obj(i)).is_some_and(|o| self.get_bool(&o, "list_start"))
    }

    /// Makes the draft say what the editor now shows (as post Markdown), with the **fewest operations**: blocks that did not change are left alone, a
    /// changed block gets only the characters, styles and settings that differ. This is how the article editor, which still works on its own text,
    /// feeds the shared draft: one typed letter is one small insert, so other authors' edits to the same paragraph merge instead of being replaced.
    pub fn reconcile(&mut self, markdown: &str) -> Result<(), StoreError> {
        if markdown.len() > MAX_DRAFT_BYTES {
            return Err(StoreError::Rejected);
        }
        let mut wanted: Vec<(DraftBlockInput, bool)> = Vec::new();
        for block in format::parse_post(markdown) {
            for (n, mut input) in inputs_of(block).into_iter().enumerate() {
                input.spans = merge_spans(input.spans);
                wanted.push((input, n == 0));
            }
        }
        let old: Vec<(DraftBlock, bool)> = self.blocks().into_iter().map(|b| { let start = self.list_start_of(&b.id); (b, start) }).collect();
        let same = |o: &(DraftBlock, bool), w: &(DraftBlockInput, bool)| {
            let (ob, os, wb, ws) = (&o.0, o.1, &w.0, w.1);
            (ob.kind.as_str(), ob.level, ob.ordered, ob.number, ob.attachment, ob.caption.as_str(), ob.url.as_str(), ob.colour.as_str(), &ob.spans)
                == (wb.kind.as_str(), wb.level, wb.ordered, wb.number, wb.attachment, wb.caption.as_str(), wb.url.as_str(), wb.colour.as_str(), &wb.spans)
                && (ob.kind != "item" || os == ws)
        };
        let mut prefix = 0;
        while prefix < old.len() && prefix < wanted.len() && same(&old[prefix], &wanted[prefix]) {
            prefix += 1;
        }
        let mut suffix = 0;
        while suffix < old.len() - prefix && suffix < wanted.len() - prefix && same(&old[old.len() - 1 - suffix], &wanted[wanted.len() - 1 - suffix]) {
            suffix += 1;
        }
        let old_mid: Vec<&(DraftBlock, bool)> = old[prefix..old.len() - suffix].iter().collect();
        let new_mid: Vec<&(DraftBlockInput, bool)> = wanted[prefix..wanted.len() - suffix].iter().collect();
        let paired = old_mid.len().min(new_mid.len());
        for i in 0..paired {
            self.update_block(&old_mid[i].0, old_mid[i].1, new_mid[i])?;
        }
        for extra in &old_mid[paired..] {
            self.delete_block(&extra.0.id)?;
        }
        for (i, extra) in new_mid[paired..].iter().enumerate() {
            let adding: usize = extra.0.spans.iter().map(|s| s.text.len()).sum();
            self.check_room(adding)?;
            let id = uuid::Uuid::new_v4().simple().to_string();
            self.write_block(prefix + paired + i, &id, &extra.0, extra.1)?;
        }
        Ok(())
    }

    fn update_block(&mut self, old: &DraftBlock, old_start: bool, new: &(DraftBlockInput, bool)) -> Result<(), StoreError> {
        let (input, start) = (&new.0, new.1);
        let block = self.block_for(&old.id)?;
        // Settings.
        if (old.kind.as_str(), old.level, old.ordered, old.number) != (input.kind.as_str(), input.level, input.ordered, input.number) {
            self.set_block_kind(&old.id, &input.kind, input.level, input.ordered, input.number)?;
        }
        if (old.attachment, old.caption.as_str(), old.url.as_str(), old.colour.as_str()) != (input.attachment, input.caption.as_str(), input.url.as_str(), input.colour.as_str()) {
            self.set_block_attrs(&old.id, &input.url, &input.caption, &input.colour, input.attachment)?;
        }
        if old_start != start {
            self.doc.put(&block, "list_start", start).map_err(bad)?;
        }
        // Characters: only the middle that differs.
        let a: Vec<char> = old.spans.iter().flat_map(|s| s.text.chars()).collect();
        let z: Vec<char> = input.spans.iter().flat_map(|s| s.text.chars()).collect();
        if a != z {
            let prefix = a.iter().zip(&z).take_while(|(x, y)| x == y).count();
            let suffix = a[prefix..].iter().rev().zip(z[prefix..].iter().rev()).take_while(|(x, y)| x == y).count();
            let removed = a.len() - prefix - suffix;
            if removed > 0 {
                self.delete_text(&old.id, prefix, removed)?;
            }
            let added: String = z[prefix..z.len() - suffix].iter().collect();
            if !added.is_empty() {
                self.insert_text(&old.id, prefix, &added)?;
            }
        }
        // Styles: compare per character after the text is right, and fix only the runs that differ.
        let now = self.block_for(&old.id).map(|b| self.read_block(&b)).map(|b| b.spans).unwrap_or_default();
        if now != input.spans {
            let have = per_char(&now);
            let want = per_char(&input.spans);
            for name in ["bold", "italic", "underline", "strike", "code", "link", "mention"] {
                let mut i = 0;
                while i < want.len().min(have.len()) {
                    let (w, h) = (style_of(&want[i], name), style_of(&have[i], name));
                    if w == h {
                        i += 1;
                        continue;
                    }
                    let mut j = i;
                    while j < want.len().min(have.len()) && style_of(&want[j], name) != style_of(&have[j], name) && style_of(&want[j], name) == w {
                        j += 1;
                    }
                    if h.is_some() {
                        self.unmark(&old.id, i, j, name)?;
                    }
                    if let Some(value) = w {
                        self.mark(&old.id, i, j, name, if value.is_empty() { None } else { Some(value.as_str()) })?;
                    }
                    i = j;
                }
            }
        }
        Ok(())
    }

    // ------------------------------------------------------------------------------------------- sync

    /// The document's heads (the newest changes), as hex.
    pub fn heads(&mut self) -> Vec<String> {
        self.doc.get_heads().iter().map(|h| h.to_string()).collect()
    }

    fn parse_heads(&mut self, heads: &[String]) -> Vec<ChangeHash> {
        // Only heads this replica knows can be a starting point; anything else is ignored (then more is sent, never less).
        heads.iter().filter_map(|h| h.parse::<ChangeHash>().ok()).filter(|h| self.doc.get_change_by_hash(h).is_some()).collect()
    }

    /// The changes made since `heads` (what the other replica lacks), or the whole document when none of its heads is known here.
    pub fn changes_since(&mut self, heads: &[String]) -> Vec<u8> {
        let known = self.parse_heads(heads);
        if known.is_empty() {
            self.doc.save()
        } else {
            self.doc.save_after(&known)
        }
    }

    /// Applies changes (or a whole saved document) from another replica and says what that changed.
    pub fn apply_changes(&mut self, bytes: &[u8]) -> Result<Vec<DraftPatch>, StoreError> {
        let before = (self.blocks(), self.meta());
        self.doc.load_incremental(bytes).map_err(bad)?;
        let after = (self.blocks(), self.meta());
        self.approx_bytes = self.text_bytes();
        Ok(diff(&before.0, &before.1, &after.0, &after.1))
    }
}

/// Adjacent runs with the same styles are one run.
fn merge_spans(spans: Vec<Span>) -> Vec<Span> {
    let mut out: Vec<Span> = Vec::new();
    for span in spans.into_iter().filter(|s| !s.text.is_empty()) {
        match out.last_mut() {
            Some(last) if same_style(last, &span) => last.text.push_str(&span.text),
            _ => out.push(span),
        }
    }
    out
}

/// One style set per character.
fn per_char(spans: &[Span]) -> Vec<Span> {
    spans.iter().flat_map(|s| s.text.chars().map(move |c| Span { text: c.to_string(), ..s.clone() })).collect()
}

/// The value of one style on a span: `Some("")` for an on/off style that is on, `Some(value)` for a link or mention, `None` when off.
fn style_of(span: &Span, name: &str) -> Option<String> {
    match name {
        "bold" => span.bold.then(String::new),
        "italic" => span.italic.then(String::new),
        "underline" => span.underline.then(String::new),
        "strike" => span.strike.then(String::new),
        "code" => span.code.then(String::new),
        "link" => span.link.clone(),
        "mention" => span.mention.clone(),
        _ => None,
    }
}

fn same_style(a: &Span, b: &Span) -> bool {
    (a.bold, a.italic, a.underline, a.strike, a.code, &a.link, &a.mention) == (b.bold, b.italic, b.underline, b.strike, b.code, &b.link, &b.mention)
}

fn plain(kind: &str) -> DraftBlockInput {
    DraftBlockInput { kind: kind.to_string(), level: 0, ordered: false, number: 0, attachment: 0, caption: String::new(), url: String::new(), colour: String::new(), spans: Vec::new() }
}

/// A parsed Markdown block as draft blocks (a list becomes one block per item).
fn inputs_of(block: Block) -> Vec<DraftBlockInput> {
    match block {
        Block::Paragraph { spans } => vec![DraftBlockInput { spans, ..plain("paragraph") }],
        Block::ItemList { items } => items.into_iter().map(|i| DraftBlockInput { level: i.level, ordered: i.ordered, number: i.number, spans: i.spans, ..plain("item") }).collect(),
        Block::Code { text } => vec![DraftBlockInput { spans: vec![Span { text, ..Span::default() }], ..plain("code") }],
        Block::Image { caption, attachment } => vec![DraftBlockInput { caption, attachment, ..plain("image") }],
        Block::Heading { level, spans } => vec![DraftBlockInput { spans, ..plain(&format!("h{}", level.clamp(1, 6))) }],
        Block::Quote { spans } => vec![DraftBlockInput { spans, ..plain("quote") }],
        Block::Indent { spans } => vec![DraftBlockInput { spans, ..plain("indent") }],
        Block::Divider => vec![plain("divider")],
        Block::Freewall => vec![plain("freewall")],
        Block::Button { text, url, caption, colour } => vec![DraftBlockInput { url, caption, colour, spans: vec![Span { text, ..Span::default() }], ..plain("button") }],
    }
}

fn text_of(block: &DraftBlock) -> Vec<char> {
    block.spans.iter().flat_map(|s| s.text.chars()).collect()
}

/// What changed between two readings of the document, in the order an editor applies it.
pub fn diff(before: &[DraftBlock], before_meta: &DraftMeta, after: &[DraftBlock], after_meta: &DraftMeta) -> Vec<DraftPatch> {
    let mut out = Vec::new();
    let in_after: std::collections::HashSet<&str> = after.iter().map(|b| b.id.as_str()).collect();
    let in_before: std::collections::HashSet<&str> = before.iter().map(|b| b.id.as_str()).collect();
    let mut current: Vec<String> = Vec::new();
    for b in before {
        if in_after.contains(b.id.as_str()) {
            current.push(b.id.clone());
        } else {
            out.push(DraftPatch::Removed { id: b.id.clone() });
        }
    }
    for (index, b) in after.iter().enumerate() {
        if !in_before.contains(b.id.as_str()) {
            current.insert(index.min(current.len()), b.id.clone());
            out.push(DraftPatch::Inserted { index: index as u32, block: b.clone() });
        }
    }
    for (index, b) in after.iter().enumerate() {
        if current.get(index) != Some(&b.id) {
            if let Some(from) = current.iter().position(|id| *id == b.id) {
                current.remove(from);
                current.insert(index.min(current.len()), b.id.clone());
                out.push(DraftPatch::Moved { id: b.id.clone(), index: index as u32 });
            }
        }
    }
    for b in after {
        let Some(old) = before.iter().find(|o| o.id == b.id) else { continue };
        if old == b {
            continue;
        }
        let (a, z) = (text_of(old), text_of(b));
        if a != z {
            let prefix = a.iter().zip(&z).take_while(|(x, y)| x == y).count();
            let suffix = a[prefix..].iter().rev().zip(z[prefix..].iter().rev()).take_while(|(x, y)| x == y).count();
            out.push(DraftPatch::Text {
                block_id: b.id.clone(),
                start: prefix as u32,
                deleted: (a.len() - prefix - suffix) as u32,
                inserted: z[prefix..z.len() - suffix].iter().collect(),
            });
        }
        let mut restyled = old.clone();
        restyled.spans = b.spans.clone();
        if restyled != *old || old.spans != b.spans {
            out.push(DraftPatch::Changed { block: b.clone() });
        }
    }
    if before_meta != after_meta {
        out.push(DraftPatch::Meta { meta: after_meta.clone() });
    }
    out
}

#[cfg(test)]
mod tests;
