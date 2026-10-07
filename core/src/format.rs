//! Message formatting (LIME-100): a small, fixed Markdown subset carried inside the encrypted payload.
//!
//! The subset is exactly: **bold** (`**x**`), *italic* (`*x*`), underline (`__x__`, a Lime extension: it works inside words too, so a message typed by hand as snake__case__name would underline; the composer escapes every underscore it writes),
//! strikethrough (`~~x~~`), inline `code`, fenced code blocks, bulleted (`- `) and numbered (`1. `)
//! lists with one nesting level, and links (`[text](url)`, http, https and mailto only). Everything
//! else is plain text: nothing here rejects a message, unknown syntax is just text. A backslash
//! before an ASCII punctuation mark makes it literal.
//!
//! One grammar, here, for every platform: [`parse`] (text to blocks), [`serialize`] (blocks to
//! canonical text), [`plain_text`] (the words without markup, for search and previews) and
//! [`normalise`] (parse then serialize: what is stored and sent). See `docs/message-format.md`.

/// A run of text with one set of styles.
#[derive(Debug, Clone, PartialEq, Eq, Default, uniffi::Record)]
pub struct Span {
    pub text: String,
    pub bold: bool,
    pub italic: bool,
    pub underline: bool,
    pub strike: bool,
    pub code: bool,
    /// An allowed link address (http, https or mailto), or none.
    pub link: Option<String>,
}

/// One item of a list. `level` is 0, or 1 for a nested item.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ListItem {
    pub level: u32,
    pub ordered: bool,
    /// The number written for a numbered item (the renderer counts on from the first of a run).
    pub number: u32,
    pub spans: Vec<Span>,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum Block {
    /// Lines of text; a newline inside is a line break.
    Paragraph { spans: Vec<Span> },
    /// Consecutive list lines.
    List { items: Vec<ListItem> },
    /// A fenced code block: shown verbatim in a monospaced face.
    Code { text: String },
}

const NESTED_INDENT: usize = 2;

fn is_punct(c: char) -> bool {
    c.is_ascii_punctuation()
}

// ---------------------------------------------------------------- parsing

/// Text to blocks. Never fails.
pub fn parse(text: &str) -> Vec<Block> {
    let text = text.replace("\r\n", "\n").replace('\r', "\n");
    let lines: Vec<&str> = text.split('\n').collect();
    let mut blocks = Vec::new();
    let mut i = 0;
    while i < lines.len() {
        let line = lines[i];
        if let Some(fence) = fence_length(line) {
            let mut body: Vec<&str> = Vec::new();
            i += 1;
            while i < lines.len() && !is_fence_close(lines[i], fence) {
                body.push(lines[i]);
                i += 1;
            }
            i += 1; // the closing fence (or the end)
            blocks.push(Block::Code { text: body.join("\n") });
        } else if list_item(line).is_some() {
            let mut items = Vec::new();
            while i < lines.len() {
                let Some((level, ordered, number, rest)) = list_item(lines[i]) else { break };
                items.push(ListItem { level, ordered, number, spans: parse_inline(rest) });
                i += 1;
            }
            blocks.push(Block::List { items });
        } else if line.trim().is_empty() {
            i += 1;
        } else {
            let mut paragraph: Vec<&str> = Vec::new();
            while i < lines.len() && !lines[i].trim().is_empty() && fence_length(lines[i]).is_none() && list_item(lines[i]).is_none() {
                paragraph.push(lines[i]);
                i += 1;
            }
            blocks.push(Block::Paragraph { spans: parse_inline(&paragraph.join("\n")) });
        }
    }
    blocks
}

/// The length of the backtick run that opens a fenced code block on this line, if it does: three or
/// more backticks, then an optional word that has no backtick in it (so a line that starts with a code
/// span is not a fence).
fn fence_length(line: &str) -> Option<usize> {
    let indent = line.len() - line.trim_start_matches(' ').len();
    if indent > 3 {
        return None;
    }
    let rest = &line[indent..];
    let run = rest.chars().take_while(|&c| c == '`').count();
    (run >= 3 && !rest[run..].contains('`')).then_some(run)
}

fn is_fence_close(line: &str, fence: usize) -> bool {
    let trimmed = line.trim();
    trimmed.len() >= fence && trimmed.chars().all(|c| c == '`')
}

/// `(level, ordered, number, text after the marker)` for a list line.
fn list_item(line: &str) -> Option<(u32, bool, u32, &str)> {
    let (indent, rest) = if let Some(rest) = line.strip_prefix('\t') {
        (NESTED_INDENT, rest)
    } else {
        let spaces = line.len() - line.trim_start_matches(' ').len();
        (spaces, &line[spaces..])
    };
    if indent > 4 {
        return None;
    }
    let level = u32::from(indent >= NESTED_INDENT);
    if let Some(after) = rest.strip_prefix("- ").or_else(|| rest.strip_prefix("* ")) {
        let after = after.trim_start();
        return (!after.is_empty()).then_some((level, false, 0, after));
    }
    let digits: String = rest.chars().take_while(char::is_ascii_digit).collect();
    if !digits.is_empty() && digits.len() <= 9 {
        if let Some(after) = rest[digits.len()..].strip_prefix(". ") {
            let after = after.trim_start();
            return (!after.is_empty()).then(|| (level, true, digits.parse().unwrap_or(1), after));
        }
    }
    None
}

/// A piece of the inline stream before styles are resolved.
#[derive(Debug, Clone)]
enum Token {
    Text(String),
    /// A finished span (inline code, or a link with its own inner spans).
    Atom(Vec<Span>),
    Delim(Delim),
}

#[derive(Debug, Clone)]
struct Delim {
    ch: char,
    len: usize,
    can_open: bool,
    can_close: bool,
    /// Characters used up by matches, as a closer (left side of the run) and as an opener (right side).
    closed: usize,
    opened: usize,
}

#[derive(Debug, Clone, Copy)]
struct Wrap {
    open: usize,
    close: usize,
    style: Style,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Style {
    Bold,
    Italic,
    Underline,
    Strike,
}

pub fn parse_inline(text: &str) -> Vec<Span> {
    let chars: Vec<char> = text.chars().collect();
    let mut tokens: Vec<Token> = Vec::new();
    let mut literal = String::new();
    let mut i = 0;
    let flush = |literal: &mut String, tokens: &mut Vec<Token>| {
        if !literal.is_empty() {
            tokens.push(Token::Text(std::mem::take(literal)));
        }
    };
    while i < chars.len() {
        let c = chars[i];
        if c == '\\' && i + 1 < chars.len() && is_punct(chars[i + 1]) {
            literal.push(chars[i + 1]);
            i += 2;
        } else if c == '`' {
            let run = chars[i..].iter().take_while(|&&x| x == '`').count();
            match find_code_close(&chars, i + run, run) {
                Some(end) => {
                    let mut body: String = chars[i + run..end].iter().collect();
                    if body.len() > 1 && body.starts_with(' ') && body.ends_with(' ') && !body.trim().is_empty() {
                        body = body[1..body.len() - 1].to_owned();
                    }
                    flush(&mut literal, &mut tokens);
                    tokens.push(Token::Atom(vec![Span { text: body.replace('\n', " "), code: true, ..Span::default() }]));
                    i = end + run;
                }
                None => {
                    literal.push_str(&"`".repeat(run));
                    i += run;
                }
            }
        } else if c == '[' {
            match parse_link(&chars, i) {
                Some((inner, url, next)) => {
                    flush(&mut literal, &mut tokens);
                    let mut spans = parse_inline(&inner);
                    for span in &mut spans {
                        span.link = Some(url.clone());
                    }
                    tokens.push(Token::Atom(spans));
                    i = next;
                }
                None => {
                    literal.push('[');
                    i += 1;
                }
            }
        } else if c == '*' || c == '_' || c == '~' {
            let run = chars[i..].iter().take_while(|&&x| x == c).count();
            let before = i.checked_sub(1).map(|j| chars[j]);
            let after = chars.get(i + run).copied();
            let space = |x: Option<char>| x.is_none_or(char::is_whitespace);
            let can_open = !space(after);
            let can_close = !space(before);
            if (c == '_' || c == '~') && run < 2 {
                literal.push_str(&c.to_string().repeat(run));
            } else {
                flush(&mut literal, &mut tokens);
                tokens.push(Token::Delim(Delim { ch: c, len: run, can_open, can_close, closed: 0, opened: 0 }));
            }
            i += run;
        } else {
            literal.push(c);
            i += 1;
        }
    }
    flush(&mut literal, &mut tokens);
    resolve(tokens)
}

fn find_code_close(chars: &[char], from: usize, run: usize) -> Option<usize> {
    let mut i = from;
    while i < chars.len() {
        if chars[i] == '`' {
            let n = chars[i..].iter().take_while(|&&x| x == '`').count();
            if n == run {
                return Some(i);
            }
            i += n;
        } else {
            i += 1;
        }
    }
    None
}

/// `[text](url)` at `start` with an allowed scheme: the text, the address and where parsing goes on.
fn parse_link(chars: &[char], start: usize) -> Option<(String, String, usize)> {
    let mut depth = 0;
    let mut close = None;
    let mut i = start;
    while i < chars.len() {
        match chars[i] {
            '\\' => i += 1,
            '`' => {
                // A code span inside the link text hides its brackets.
                let run = chars[i..].iter().take_while(|&&x| x == '`').count();
                match find_code_close(chars, i + run, run) {
                    Some(end) => i = end + run - 1,
                    None => i += run - 1,
                }
            }
            '[' => depth += 1,
            ']' => {
                depth -= 1;
                if depth == 0 {
                    close = Some(i);
                    break;
                }
            }
            _ => {}
        }
        i += 1;
    }
    let close = close?;
    if chars.get(close + 1) != Some(&'(') {
        return None;
    }
    let end = (close + 2..chars.len()).find(|&j| chars[j] == ')')?;
    let url: String = chars[close + 2..end].iter().collect();
    let url = url.trim();
    (allowed_link(url) && !url.chars().any(char::is_whitespace)).then(|| {
        (chars[start + 1..close].iter().collect::<String>(), url.to_owned(), end + 1)
    })
}

/// http, https and mailto only, with something after the scheme.
pub fn allowed_link(url: &str) -> bool {
    let lower = url.to_ascii_lowercase();
    ["http://", "https://", "mailto:"].iter().any(|scheme| lower.starts_with(scheme) && lower.len() > scheme.len())
}

/// Matches closers to openers (nearest first, as CommonMark does) and flattens to spans.
fn resolve(mut tokens: Vec<Token>) -> Vec<Span> {
    let mut wraps: Vec<Wrap> = Vec::new();
    for j in 0..tokens.len() {
        loop {
            let (ch, can_close, close_left, close_len, close_opens) = match &tokens[j] {
                Token::Delim(d) if d.can_close => (d.ch, true, d.len - d.closed - d.opened, d.len, d.can_open),
                _ => break,
            };
            if !can_close || close_left == 0 {
                break;
            }
            // The nearest earlier delimiter of the same kind that can open and has characters left.
            let found = (0..j).rev().find(|&k| {
                matches!(&tokens[k], Token::Delim(d) if d.ch == ch && d.can_open && d.len - d.closed - d.opened > 0
                    // CommonMark's "rule of three": a run that can both open and close does not pair with a run
                    // whose length adds up to a multiple of three (unless both are), so `**a *b***` nests properly.
                    && !(ch == '*' && (d.can_close || close_opens) && (d.len + close_len) % 3 == 0
                        && !(d.len % 3 == 0 && close_len % 3 == 0)))
            });
            let Some(k) = found else { break };
            let open_left = match &tokens[k] {
                Token::Delim(d) => d.len - d.closed - d.opened,
                _ => 0,
            };
            let (use_len, style) = match ch {
                '*' if open_left >= 2 && close_left >= 2 => (2, Style::Bold),
                '*' => (1, Style::Italic),
                '_' if open_left >= 2 && close_left >= 2 => (2, Style::Underline),
                '~' if open_left >= 2 && close_left >= 2 => (2, Style::Strike),
                _ => break,
            };
            if let Token::Delim(d) = &mut tokens[k] {
                d.opened += use_len;
            }
            if let Token::Delim(d) = &mut tokens[j] {
                d.closed += use_len;
            }
            wraps.push(Wrap { open: k, close: j, style });
            // Delimiters strictly between are now plain text.
            for between in tokens.iter_mut().take(j).skip(k + 1) {
                if let Token::Delim(d) = between {
                    d.can_open = false;
                    d.can_close = false;
                }
            }
        }
    }

    // Flatten: walk the tokens keeping the styles that are open at each point.
    let mut spans: Vec<Span> = Vec::new();
    let mut counts = [0i32; 4];
    let slot = |s: Style| match s {
        Style::Bold => 0,
        Style::Italic => 1,
        Style::Underline => 2,
        Style::Strike => 3,
    };
    let push = |spans: &mut Vec<Span>, counts: &[i32; 4], text: &str, base: Option<&Span>| {
        if text.is_empty() {
            return;
        }
        let mut span = base.cloned().unwrap_or_default();
        span.text = text.to_owned();
        span.bold |= counts[0] > 0;
        span.italic |= counts[1] > 0;
        span.underline |= counts[2] > 0;
        span.strike |= counts[3] > 0;
        spans.push(span);
    };
    for (index, token) in tokens.iter().enumerate() {
        match token {
            Token::Text(text) => push(&mut spans, &counts, text, None),
            Token::Atom(parts) => {
                for part in parts {
                    push(&mut spans, &counts, &part.text.clone(), Some(part));
                }
            }
            Token::Delim(d) => {
                // Closers first (they sit on the inner side of the run), then what stayed literal, then openers.
                for w in wraps.iter().filter(|w| w.close == index) {
                    counts[slot(w.style)] -= 1;
                }
                let literal = d.len - d.closed - d.opened;
                push(&mut spans, &counts, &d.ch.to_string().repeat(literal), None);
                for w in wraps.iter().filter(|w| w.open == index) {
                    counts[slot(w.style)] += 1;
                }
            }
        }
    }
    merge(spans)
}

/// Joins neighbours that look the same and drops empty ones.
fn merge(spans: Vec<Span>) -> Vec<Span> {
    let mut out: Vec<Span> = Vec::new();
    for span in spans {
        if span.text.is_empty() {
            continue;
        }
        match out.last_mut() {
            Some(last) if same_look(last, &span) => last.text.push_str(&span.text),
            _ => out.push(span),
        }
    }
    out
}

fn same_look(a: &Span, b: &Span) -> bool {
    (a.bold, a.italic, a.underline, a.strike, a.code, &a.link) == (b.bold, b.italic, b.underline, b.strike, b.code, &b.link)
}

// ---------------------------------------------------------------- the plain words

/// The words without the markup: for search, list previews and notifications.
pub fn plain_text(text: &str) -> String {
    let mut lines: Vec<String> = Vec::new();
    for block in parse(text) {
        match block {
            Block::Paragraph { spans } => lines.push(spans.iter().map(|s| s.text.as_str()).collect()),
            Block::List { items } => {
                let mut counters = [0u32; 2];
                for item in items {
                    let marker = if item.ordered {
                        let level = item.level.min(1) as usize;
                        counters[level] = if counters[level] == 0 { item.number.max(1) } else { counters[level] + 1 };
                        format!("{}. ", counters[level])
                    } else {
                        "• ".to_owned()
                    };
                    let indent = if item.level > 0 { "  " } else { "" };
                    lines.push(format!("{indent}{marker}{}", item.spans.iter().map(|s| s.text.as_str()).collect::<String>()));
                }
            }
            Block::Code { text } => lines.push(text),
        }
    }
    lines.join("\n")
}

// ---------------------------------------------------------------- writing

/// Blocks to canonical text: what is stored and sent.
pub fn serialize(blocks: &[Block]) -> String {
    let mut parts: Vec<String> = Vec::new();
    for block in blocks {
        match block {
            Block::Paragraph { spans } => {
                let text = write_spans(spans);
                // Blank lines at the edges are not part of a paragraph (the reader skips them).
                let lines: Vec<&str> = text.split('\n').collect();
                let first = lines.iter().position(|l| !l.trim().is_empty());
                let last = lines.iter().rposition(|l| !l.trim().is_empty());
                if let (Some(first), Some(last)) = (first, last) {
                    // One blank line between paragraphs is all there is: a longer gap is the same gap.
                    let mut kept: Vec<&str> = Vec::new();
                    for line in &lines[first..=last] {
                        if line.trim().is_empty() {
                            if kept.last().is_some_and(|l| !l.is_empty()) {
                                kept.push("");
                            }
                        } else {
                            kept.push(line);
                        }
                    }
                    let mut text = escape_line_starts(&kept.join("\n"));
                    // The paragraph as a whole must read back to the same words (a link whose text spans a
                    // blank line, say, would not): if not, write the words without their styles.
                    let words = |t: &str| t.split_whitespace().collect::<Vec<_>>().join(" ");
                    let wanted = words(&spans.iter().map(|s| s.text.replace('\n', if s.code { " " } else { "\n" })).collect::<String>());
                    if words(&plain_text(&text)) != wanted {
                        let plain: Vec<Span> = spans.iter().map(|s| Span { text: s.text.clone(), ..Span::default() }).collect();
                        text = escape_line_starts(&write_level(&merge(plain), 0));
                    }
                    parts.push(text);
                }
            }
            Block::List { items } => {
                let mut counters = [0u32; 2];
                let mut lines = Vec::new();
                for item in items {
                    let level = item.level.min(1) as usize;
                    let marker = if item.ordered {
                        counters[level] += 1;
                        format!("{}. ", counters[level])
                    } else {
                        counters[level] = 0;
                        "- ".to_owned()
                    };
                    let indent = " ".repeat(level * NESTED_INDENT);
                    // A line break inside an item would end it: it becomes a space.
                    let body = write_spans(&item.spans).replace('\n', " ");
                    lines.push(format!("{indent}{marker}{body}"));
                }
                parts.push(lines.join("\n"));
            }
            Block::Code { text } => {
                let fence = "`".repeat(longest_backtick_run(text).max(2) + 1);
                parts.push(format!("{fence}\n{text}\n{fence}"));
            }
        }
    }
    parts.join("\n\n")
}

/// Parse then serialize: unknown syntax becomes text, and the result is the one written form.
pub fn normalise(text: &str) -> String {
    // Spaces and blank lines around the whole message are not part of it.
    serialize(&parse(text.trim()))
}

fn longest_backtick_run(text: &str) -> usize {
    let mut best = 0;
    let mut run = 0;
    for c in text.chars() {
        run = if c == '`' { run + 1 } else { 0 };
        best = best.max(run);
    }
    best
}

fn escape_text(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        if matches!(c, '\\' | '*' | '_' | '~' | '`' | '[' | ']') {
            out.push('\\');
        }
        out.push(c);
    }
    out
}

/// A line that would read as a list marker gets its marker escaped.
fn escape_line_starts(text: &str) -> String {
    text.split('\n')
        .map(|line| {
            let indent = line.len() - line.trim_start_matches(' ').len();
            let rest = &line[indent..];
            if rest.starts_with("- ") || rest == "-" {
                format!("{}\\{}", &line[..indent], rest)
            } else {
                let digits = rest.chars().take_while(char::is_ascii_digit).count();
                if digits > 0 && rest[digits..].starts_with(". ") {
                    format!("{}{}\\{}", &line[..indent], &rest[..digits], &rest[digits..])
                } else {
                    line.to_owned()
                }
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

/// Spans to text: styles are nested in a fixed order (link, strike, underline, bold, italic, code), so
/// the markers around a run always close in the reverse order they opened.
fn write_spans(spans: &[Span]) -> String {
    let spans: Vec<Span> = merge(spans.to_vec());
    let written = write_level(&spans, 0);
    // Styles that sit unusually close together (a marker run that could be read two ways) are the one
    // case where reading the text back could show stray markers. Check, and if the words would not
    // survive, write the words without their styles: the message is never garbled.
    let words = |text: &str| text.split_whitespace().collect::<Vec<_>>().join(" ");
    let wanted = words(&spans.iter().map(|s| s.text.replace('\n', if s.code { " " } else { "\n" })).collect::<String>());
    let read = words(&parse_inline(&written).iter().map(|s| s.text.as_str()).collect::<String>());
    if wanted == read {
        written
    } else {
        let plain: Vec<Span> = spans.iter().map(|s| Span { text: s.text.clone(), ..Span::default() }).collect();
        write_level(&merge(plain), 0)
    }
}

fn write_level(spans: &[Span], depth: usize) -> String {
    if spans.is_empty() {
        return String::new();
    }
    if depth == 6 {
        return spans.iter().map(|s| if s.code { write_code(&s.text) } else { escape_text(&s.text) }).collect();
    }
    let has = |s: &Span| match depth {
        0 => s.link.is_some(),
        1 => s.strike,
        2 => s.underline,
        3 => s.bold,
        4 => s.italic,
        _ => s.code,
    };
    if depth == 5 {
        // Code is the innermost style: a run of code spans is written whole.
        let mut out = String::new();
        for span in spans {
            out.push_str(&if span.code { write_code(&span.text) } else { escape_text(&span.text) });
        }
        return out;
    }
    let mut out = String::new();
    let mut i = 0;
    while i < spans.len() {
        let on = has(&spans[i]);
        let same = |s: &Span| has(s) == on && (depth != 0 || s.link == spans[i].link);
        let mut j = i;
        while j < spans.len() && same(&spans[j]) {
            j += 1;
        }
        let mut group: Vec<Span> = spans[i..j].to_vec();
        if on {
            let link = group[0].link.clone();
            for span in &mut group {
                match depth {
                    0 => span.link = None,
                    1 => span.strike = false,
                    2 => span.underline = false,
                    3 => span.bold = false,
                    _ => span.italic = false,
                }
            }
            let inner = write_level(&group, depth + 1);
            out.push_str(&wrap(depth, &inner, link.as_deref()));
        } else {
            out.push_str(&write_level(&group, depth + 1));
        }
        i = j;
    }
    out
}

/// Puts the markers around `inner`, with any spaces at its edges outside them (a marker next to a
/// space would not be read as one).
fn wrap(depth: usize, inner: &str, link: Option<&str>) -> String {
    let trimmed = inner.trim_matches(char::is_whitespace);
    if trimmed.is_empty() {
        return inner.to_owned();
    }
    let start = inner.len() - inner.trim_start_matches(char::is_whitespace).len();
    let end = inner.trim_end_matches(char::is_whitespace).len();
    let (lead, tail) = (&inner[..start], &inner[end..]);
    let body = match depth {
        0 => format!("[{trimmed}]({})", link.unwrap_or("")),
        1 => format!("~~{trimmed}~~"),
        2 => format!("__{trimmed}__"),
        3 => format!("**{trimmed}**"),
        _ => format!("*{trimmed}*"),
    };
    format!("{lead}{body}{tail}")
}

fn write_code(text: &str) -> String {
    // Inline code is one line: a line break in it becomes a space.
    let text = &text.replace('\n', " ");
    let fence = "`".repeat(longest_backtick_run(text) + 1);
    let pad = text.starts_with('`') || text.ends_with('`') || (text.starts_with(' ') && text.ends_with(' ') && !text.trim().is_empty());
    if pad {
        format!("{fence} {text} {fence}")
    } else {
        format!("{fence}{text}{fence}")
    }
}

// ---------------------------------------------------------------- the FFI

/// Text to blocks (the app draws these).
#[uniffi::export]
pub fn parse_message_markdown(text: String) -> Vec<Block> {
    parse(&text)
}

/// Blocks to the canonical text (the composer sends this).
#[uniffi::export]
pub fn message_markdown_from_blocks(blocks: Vec<Block>) -> String {
    serialize(&blocks)
}

/// The words without markup (search, list previews, notification previews).
#[uniffi::export]
pub fn message_plain_text(text: String) -> String {
    plain_text(&text)
}

/// The one written form of a message (unknown syntax downgraded to text).
#[uniffi::export]
pub fn normalise_message_markdown(text: String) -> String {
    normalise(&text)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(text: &str) -> Span {
        Span { text: text.into(), ..Span::default() }
    }
    fn b(text: &str) -> Span {
        Span { bold: true, ..s(text) }
    }
    fn i(text: &str) -> Span {
        Span { italic: true, ..s(text) }
    }
    fn para(spans: Vec<Span>) -> Vec<Block> {
        vec![Block::Paragraph { spans }]
    }

    #[test]
    fn plain_text_is_a_paragraph() {
        assert_eq!(parse("hello there"), para(vec![s("hello there")]));
        assert_eq!(parse("line one\nline two"), para(vec![s("line one\nline two")]), "a newline is a line break");
        assert_eq!(parse("one\n\ntwo").len(), 2, "a blank line separates paragraphs");
        assert!(parse("").is_empty());
        assert!(parse("  \n \n").is_empty());
    }

    #[test]
    fn every_inline_style_parses() {
        assert_eq!(parse("a **bold** b"), para(vec![s("a "), b("bold"), s(" b")]));
        assert_eq!(parse("a *italic* b"), para(vec![s("a "), i("italic"), s(" b")]));
        assert_eq!(parse("__under__"), para(vec![Span { underline: true, ..s("under") }]));
        assert_eq!(parse("~~gone~~"), para(vec![Span { strike: true, ..s("gone") }]));
        assert_eq!(parse("use `x + 1` here"), para(vec![s("use "), Span { code: true, ..s("x + 1") }, s(" here")]));
        assert_eq!(
            parse("see [Lime](https://limechat.org) now"),
            para(vec![s("see "), Span { link: Some("https://limechat.org".into()), ..s("Lime") }, s(" now")])
        );
    }

    #[test]
    fn styles_nest_and_sit_side_by_side() {
        assert_eq!(parse("**bold *and italic***"), para(vec![b("bold "), Span { bold: true, italic: true, ..s("and italic") }]));
        assert_eq!(parse("***both***"), para(vec![Span { bold: true, italic: true, ..s("both") }]));
        assert_eq!(parse("**a***b*"), para(vec![b("a"), i("b")]));
        assert_eq!(parse("*a***b**"), para(vec![i("a"), b("b")]));
        assert_eq!(
            parse("__~~**x**~~__"),
            para(vec![Span { underline: true, strike: true, bold: true, ..s("x") }])
        );
        assert_eq!(
            parse("[**bold link**](https://a.b)"),
            para(vec![Span { bold: true, link: Some("https://a.b".into()), ..s("bold link") }])
        );
    }

    #[test]
    fn markers_that_do_not_close_or_touch_a_space_are_text() {
        assert_eq!(parse("2 * 3 * 4"), para(vec![s("2 * 3 * 4")]));
        assert_eq!(parse("**not closed"), para(vec![s("**not closed")]));
        assert_eq!(parse("a ** b ** c"), para(vec![s("a ** b ** c")]));
        assert_eq!(parse("snake_case_name"), para(vec![s("snake_case_name")]), "a single underscore is just a character");
        assert_eq!(parse("a_b_c and ~one~"), para(vec![s("a_b_c and ~one~")]));
    }

    #[test]
    fn a_backslash_makes_punctuation_literal() {
        assert_eq!(parse(r"\*not italic\*"), para(vec![s("*not italic*")]));
        assert_eq!(parse(r"a \\ b"), para(vec![s(r"a \ b")]));
        assert_eq!(parse(r"back\slash"), para(vec![s(r"back\slash")]), "a backslash before a letter is just a backslash");
        assert_eq!(parse(r"\- not a list"), para(vec![s("- not a list")]));
    }

    #[test]
    fn only_http_https_and_mailto_links_are_links() {
        for url in ["http://a.b/c", "https://a.b/c?d=e", "HTTPS://A.B", "mailto:me@example.com"] {
            let blocks = parse(&format!("[x]({url})"));
            let Block::Paragraph { spans } = &blocks[0] else { panic!() };
            assert_eq!(spans[0].link.as_deref(), Some(url), "{url}");
        }
        for url in ["javascript:alert(1)", "data:text/html,hi", "file:///etc/passwd", "ftp://a.b", "tel:123", "//a.b", "a.b", "https://", "mailto:", "https://a b"] {
            let text = format!("[click]({url})");
            let blocks = parse(&text);
            let Block::Paragraph { spans } = &blocks[0] else { panic!() };
            assert!(spans.iter().all(|sp| sp.link.is_none()), "{url} must not become a link");
            assert_eq!(plain_text(&text).replace('\\', ""), text, "{url} shows as the text it was");
        }
        assert_eq!(parse("[a][b]"), para(vec![s("[a][b]")]));
        assert_eq!(parse("![img](https://a.b/i.png)"), para(vec![s("!"), Span { link: Some("https://a.b/i.png".into()), ..s("img") }]), "images are not in the subset: the bang stays and the rest is just a link");
    }

    #[test]
    fn syntax_outside_the_subset_is_plain_text() {
        for text in ["# Heading", "> quote", "<b>html</b>", "<script>alert(1)</script>", "| a | b |\n|---|---|", "---", "+ plus item"] {
            let blocks = parse(text);
            assert!(blocks.iter().all(|bl| matches!(bl, Block::Paragraph { .. })), "{text}: {blocks:?}");
        }
        assert_eq!(plain_text("# Heading"), "# Heading");
        assert_eq!(plain_text("<b>html</b>"), "<b>html</b>");
        assert_eq!(normalise("> quote"), "> quote");
    }

    #[test]
    fn lists_have_two_levels_and_numbers() {
        let blocks = parse("- one\n- two\n  - nested\n1. first\n2. second");
        let Block::List { items } = &blocks[0] else { panic!("{blocks:?}") };
        assert_eq!(items.len(), 5);
        assert_eq!((items[0].level, items[0].ordered), (0, false));
        assert_eq!((items[2].level, items[2].ordered), (1, false));
        assert_eq!((items[3].ordered, items[3].number, items[4].number), (true, 1, 2));
        assert_eq!(plain_text("- a\n- b\n1. x\n2. y\n  - n"), "• a\n• b\n1. x\n2. y\n  • n");
        assert_eq!(parse("* star item").len(), 1);
        assert!(matches!(parse("-no space")[0], Block::Paragraph { .. }));
        assert!(matches!(parse("- ")[0], Block::Paragraph { .. }), "an empty item is text");
        assert!(matches!(parse("      - too deep")[0], Block::Paragraph { .. }));
        assert_eq!(plain_text("3. start at three\n4. next"), "3. start at three\n4. next");
        // Items carry inline styles.
        let Block::List { items } = &parse("- a **b**")[0] else { panic!() };
        assert_eq!(items[0].spans, vec![s("a "), b("b")]);
    }

    #[test]
    fn code_blocks_are_verbatim_and_a_span_can_hold_backticks() {
        let blocks = parse("before\n```swift\nlet a = **not bold**\n- not a list\n```\nafter");
        assert_eq!(blocks.len(), 3);
        assert_eq!(blocks[1], Block::Code { text: "let a = **not bold**\n- not a list".into() });
        assert_eq!(parse("```\nunclosed"), vec![Block::Code { text: "unclosed".into() }], "an unclosed fence runs to the end");
        assert_eq!(parse("``a ` b``"), para(vec![Span { code: true, ..s("a ` b") }]));
        assert_eq!(parse("`` `x` ``"), para(vec![Span { code: true, ..s("`x`") }]));
        assert_eq!(parse("`unclosed"), para(vec![s("`unclosed")]));
        assert_eq!(plain_text("```\nlet a = 1\n```"), "let a = 1");
    }

    #[test]
    fn plain_text_drops_the_markup() {
        assert_eq!(plain_text("**Hi** *all*, see [the plan](https://a.b) and `code`"), "Hi all, see the plan and code");
        assert_eq!(plain_text("__u__ ~~s~~"), "u s");
        assert_eq!(plain_text(r"\*literal\*"), "*literal*");
        assert_eq!(plain_text("one\n\ntwo"), "one\ntwo");
    }

    #[test]
    fn writing_escapes_what_would_otherwise_be_read_as_markup() {
        assert_eq!(serialize(&para(vec![s("2 * 3 * 4")])), r"2 \* 3 \* 4");
        assert_eq!(serialize(&para(vec![s("a_b and [x](y) and `z` ~~")])), r"a\_b and \[x\](y) and \`z\` \~\~");
        assert_eq!(serialize(&para(vec![s("- not a list")])), r"\- not a list");
        assert_eq!(serialize(&para(vec![s("1. not a list")])), r"1\. not a list");
        assert_eq!(serialize(&para(vec![s("x\n- y")])), "x\n\\- y");
        for text in ["2 * 3 * 4", "a_b and [x](y) and `z` ~~", "- not a list", "1. nope", "back\\slash", "**", "```"] {
            assert_eq!(plain_text(&serialize(&para(vec![s(text)]))), text, "{text}");
        }
    }

    #[test]
    fn spaces_stay_outside_the_markers() {
        assert_eq!(serialize(&para(vec![b(" bold "), s("x")])), " **bold** x");
        assert_eq!(serialize(&para(vec![b("   ")])), "", "an all-space paragraph is empty text");
        assert_eq!(serialize(&para(vec![s("a"), b(" "), s("b")])), "a b");
    }

    #[test]
    fn normalise_downgrades_and_is_stable() {
        for text in [
            "plain", "**b** *i* __u__ ~~s~~ `c`", "[x](javascript:alert(1))", "# h\n> q", "- a\n  - b\n1. c", "```\ncode\n```", "mixed **a *b* c** [l](https://a.b)",
            "2 * 3 * 4", "\\*lit\\*", "a\n\nb", "***", "**", "* ", "- ", "[](https://a.b)", "``", "`` ` ``",
        ] {
            let once = normalise(text);
            assert_eq!(normalise(&once), once, "{text:?} -> {once:?} must be a fixed point");
            assert_eq!(plain_text(&once), plain_text(text).trim(), "{text:?}: the words do not change");
        }
        assert_eq!(normalise("[x](javascript:alert(1))"), r"\[x\](javascript:alert(1))");
    }

    /// A small deterministic generator, so a property test needs no extra crate.
    struct Lcg(u64);
    impl Lcg {
        fn next(&mut self, n: usize) -> usize {
            self.0 = self.0.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            ((self.0 >> 33) as usize) % n
        }
    }

    #[test]
    fn what_is_written_reads_back_the_same() {
        let words = ["hi", "x", " ", "a b", "*", "_", "~", "`", "[", "]", "(", ")", "-", "1.", "\\", "é", "**", "\n", "http://a.b", "__", "~~"];
        let mut rng = Lcg(7);
        let mut style_lost = 0;
        for round in 0..3000 {
            let mut spans = Vec::new();
            for _ in 0..1 + rng.next(5) {
                let mut text = String::new();
                for _ in 0..1 + rng.next(3) {
                    text.push_str(words[rng.next(words.len())]);
                }
                let code = rng.next(8) == 0;
                spans.push(Span {
                    text,
                    bold: !code && rng.next(3) == 0,
                    italic: !code && rng.next(3) == 0,
                    underline: !code && rng.next(4) == 0,
                    strike: !code && rng.next(4) == 0,
                    code,
                    link: (rng.next(6) == 0).then(|| "https://x.y".to_owned()),
                });
            }
            let blocks = vec![Block::Paragraph { spans }];
            let written = serialize(&blocks);
            let read = parse(&written);
            // 1. The words survive.
            let original: String = match &blocks[0] { Block::Paragraph { spans } => spans.iter().map(|sp| sp.text.as_str()).collect(), _ => unreachable!() };
            let back = plain_text(&written);
            assert_eq!(back.replace('\n', " ").split_whitespace().collect::<Vec<_>>(), original.replace('\n', " ").split_whitespace().collect::<Vec<_>>(), "round {round}: {written:?}");
            // 2. Writing what was read gives the same text.
            assert_eq!(serialize(&read), written, "round {round}: {blocks:?} -> {written:?}");
            // 3. The style of every visible character is kept.
            let flags = |blocks: &[Block]| -> Vec<(char, bool, bool, bool, bool, bool, bool)> {
                let mut out = Vec::new();
                for block in blocks {
                    if let Block::Paragraph { spans } = block {
                        for sp in spans {
                            for c in sp.text.chars().filter(|c| !c.is_whitespace()) {
                                out.push((c, sp.bold, sp.italic, sp.underline, sp.strike, sp.code, sp.link.is_some()));
                            }
                        }
                    }
                }
                out
            };
            if flags(&read) != flags(&blocks) {
                style_lost += 1;
            }
        }
        // The words always survive (asserted above). In a rare adjacency of styles the text is written
        // without them rather than risk stray markers: that must stay rare.
        assert!(style_lost <= 30, "styles were dropped in {style_lost} of 3000 random messages");
    }

    #[test]
    fn a_hostile_input_never_panics_or_hangs() {
        let mut rng = Lcg(99);
        let alphabet: Vec<char> = "*_~`[]()\\- 1.\n\t#>aé!<".chars().collect();
        for _ in 0..4000 {
            let text: String = (0..rng.next(40)).map(|_| alphabet[rng.next(alphabet.len())]).collect();
            let _ = plain_text(&text);
            let once = normalise(&text);
            assert_eq!(normalise(&once), once, "{text:?}");
        }
        let long = "*a ".repeat(5000) + &"[x](https://a.b)".repeat(2000) + &"`".repeat(3000);
        let _ = normalise(&long);
    }
}

