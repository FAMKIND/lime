import UIKit

/// How the composer keeps a message while it is being written: an attributed string in which a run's
/// style is a handful of attributes, and a list item or code line is a paragraph that carries a block
/// attribute. This file converts that to and from the Markdown subset (through LimeCore, the one place
/// the grammar lives) and edits it. It has no views, so it can be tested directly.
extension NSAttributedString.Key {
    static let limeBold = NSAttributedString.Key("lime.bold")
    static let limeItalic = NSAttributedString.Key("lime.italic")
    static let limeCode = NSAttributedString.Key("lime.code")
    /// On every character of a paragraph that is a list item or a code line: "bullet", "number" or "code".
    static let limeBlock = NSAttributedString.Key("lime.block")
    static let limeLevel = NSAttributedString.Key("lime.level")
}

enum InlineFormat: CaseIterable {
    case bold, italic, underline, strike, code
}

enum BlockKind: String { case bullet, number, code }

/// What the toolbar shows as pressed for the caret or selection.
struct FormattingState: Equatable {
    var bold = false, italic = false, underline = false, strike = false, code = false
    var link = false, bullets = false, numbers = false
}

enum ComposerDocument {
    static let bulletMarker = "• "

    // MARK: Fonts

    static func baseFont() -> UIFont { UIFont.preferredFont(forTextStyle: .body) }

    /// Applies what the attributes mean to the characters: fonts, indents and the code background. Run after
    /// any edit; it only sets visuals, never the attributes that carry meaning.
    static func restyle(_ text: NSMutableAttributedString, ink: UIColor = .label) {
        let whole = NSRange(location: 0, length: text.length)
        let base = baseFont()
        text.beginEditing()
        text.addAttribute(.foregroundColor, value: ink, range: whole)
        text.enumerateAttributes(in: whole) { attributes, range, _ in
            var traits: UIFontDescriptor.SymbolicTraits = []
            if attributes[.limeBold] != nil { traits.insert(.traitBold) }
            if attributes[.limeItalic] != nil { traits.insert(.traitItalic) }
            let inline = attributes[.limeCode] != nil
            let block = (attributes[.limeBlock] as? String).flatMap(BlockKind.init(rawValue:))
            var font = base
            if inline || block == .code {
                font = UIFont.monospacedSystemFont(ofSize: base.pointSize * 0.92, weight: traits.contains(.traitBold) ? .bold : .regular)
            } else if !traits.isEmpty, let descriptor = base.fontDescriptor.withSymbolicTraits(traits) {
                font = UIFont(descriptor: descriptor, size: base.pointSize)
            }
            text.addAttribute(.font, value: font, range: range)
            if inline || block == .code {
                text.addAttribute(.backgroundColor, value: ink.withAlphaComponent(0.10), range: range)
            } else {
                text.removeAttribute(.backgroundColor, range: range)
            }
        }
        // Lists hang their text past the marker.
        let string = text.string as NSString
        var location = 0
        while location < string.length {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            if let kind = blockKind(in: text, at: paragraph.location), kind != .code {
                let level = (text.attribute(.limeLevel, at: paragraph.location, effectiveRange: nil) as? Int) ?? 0
                let style = NSMutableParagraphStyle()
                let indent = CGFloat(level) * 18
                style.firstLineHeadIndent = indent
                style.headIndent = indent + 20
                text.addAttribute(.paragraphStyle, value: style, range: paragraph)
            } else {
                text.removeAttribute(.paragraphStyle, range: paragraph)
            }
            location = NSMaxRange(paragraph)
        }
        text.endEditing()
    }

    // MARK: Paragraphs

    static func blockKind(in text: NSAttributedString, at location: Int) -> BlockKind? {
        guard location < text.length else { return nil }
        return (text.attribute(.limeBlock, at: location, effectiveRange: nil) as? String).flatMap(BlockKind.init(rawValue:))
    }

    /// The paragraphs (lines) a range touches.
    static func paragraphs(in text: NSAttributedString, covering range: NSRange) -> [NSRange] {
        let string = text.string as NSString
        if string.length == 0 { return [NSRange(location: 0, length: 0)] }
        var result: [NSRange] = []
        var location = min(range.location, string.length)
        let end = max(min(NSMaxRange(range), string.length), location)
        repeat {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            result.append(paragraph)
            location = NSMaxRange(paragraph)
        } while location < end && location < string.length
        // A caret at the very end, after a final newline, is in an empty last paragraph.
        if range.location >= string.length, string.hasSuffix("\n") { return [NSRange(location: string.length, length: 0)] }
        return result
    }

    /// The marker at the start of a list paragraph ("• " or "3. "), as a range, or nil.
    static func markerRange(in text: NSAttributedString, paragraph: NSRange) -> NSRange? {
        guard let kind = blockKind(in: text, at: paragraph.location), kind == .bullet || kind == .number else { return nil }
        let string = text.string as NSString
        let line = string.substring(with: paragraph)
        if kind == .bullet {
            return line.hasPrefix(bulletMarker) ? NSRange(location: paragraph.location, length: bulletMarker.utf16.count) : nil
        }
        var digits = 0
        for scalar in line.unicodeScalars { if scalar.properties.numericType != nil && scalar.isASCII { digits += 1 } else { break } }
        guard digits > 0, (line as NSString).length > digits + 1, (line as NSString).substring(with: NSRange(location: digits, length: 2)) == ". " else { return nil }
        return NSRange(location: paragraph.location, length: digits + 2)
    }

    // MARK: Converting to Markdown

    /// The composer's text as blocks.
    static func blocks(from text: NSAttributedString) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [Span] = []        // the lines of the paragraph being built
        var listItems: [ListItem] = []
        var codeLines: [String] = []
        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(spans: paragraph)); paragraph = [] }
        }
        func flushList() {
            if !listItems.isEmpty { blocks.append(.list(items: listItems)); listItems = [] }
        }
        func flushCode() {
            if !codeLines.isEmpty { blocks.append(.code(text: codeLines.joined(separator: "\n"))); codeLines = [] }
        }
        let string = text.string as NSString
        var location = 0
        var lines: [NSRange] = []
        while location < string.length {
            let line = string.paragraphRange(for: NSRange(location: location, length: 0))
            lines.append(line)
            location = NSMaxRange(line)
        }
        if string.hasSuffix("\n") { lines.append(NSRange(location: string.length, length: 0)) }
        var counters = [0, 0]
        for line in lines {
            var content = line
            if content.length > 0, string.substring(with: NSRange(location: NSMaxRange(content) - 1, length: 1)) == "\n" { content.length -= 1 }
            switch blockKind(in: text, at: line.location) {
            case .code:
                flushParagraph(); flushList()
                codeLines.append(string.substring(with: content))
            case .bullet, .number:
                flushParagraph(); flushCode()
                let kind = blockKind(in: text, at: line.location)!
                let marker = markerRange(in: text, paragraph: line)
                if let marker { content = NSRange(location: NSMaxRange(marker), length: max(NSMaxRange(content) - NSMaxRange(marker), 0)) }
                let level = (text.attribute(.limeLevel, at: line.location, effectiveRange: nil) as? Int) ?? 0
                let ordered = kind == .number
                let slot = min(level, 1)
                counters[slot] = ordered ? counters[slot] + 1 : 0
                let spans = spans(in: text, range: content)
                if !spans.isEmpty { listItems.append(ListItem(level: UInt32(min(level, 1)), ordered: ordered, number: UInt32(max(counters[slot], 1)), spans: spans)) }
            case nil:
                flushList(); flushCode()
                if content.length == 0 {
                    flushParagraph() // a blank line ends the paragraph
                } else {
                    var lineSpans = spans(in: text, range: content)
                    if !paragraph.isEmpty { lineSpans.insert(Span(text: "\n", bold: false, italic: false, underline: false, strike: false, code: false, link: nil), at: 0) }
                    paragraph.append(contentsOf: lineSpans)
                }
            }
        }
        flushParagraph(); flushList(); flushCode()
        return blocks
    }

    /// The runs of a line as spans.
    static func spans(in text: NSAttributedString, range: NSRange) -> [Span] {
        var result: [Span] = []
        guard range.length > 0 else { return result }
        text.enumerateAttributes(in: range) { attributes, run, _ in
            let link = (attributes[.link] as? URL)?.absoluteString ?? (attributes[.link] as? String)
            result.append(Span(
                text: (text.string as NSString).substring(with: run),
                bold: attributes[.limeBold] != nil, italic: attributes[.limeItalic] != nil,
                underline: attributes[.underlineStyle] != nil, strike: attributes[.strikethroughStyle] != nil,
                code: attributes[.limeCode] != nil, link: link))
        }
        return result
    }

    /// The text to send.
    static func markdown(from text: NSAttributedString) -> String {
        messageMarkdownFromBlocks(blocks: blocks(from: text))
    }

    // MARK: Converting from Markdown

    /// A Markdown message as composer text (used to put a message back for editing, and by the tests).
    static func attributed(fromMarkdown markdown: String) -> NSMutableAttributedString {
        attributed(from: parseMessageMarkdown(text: markdown))
    }

    static func attributed(from blocks: [Block]) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        func append(_ string: String, _ attributes: [NSAttributedString.Key: Any] = [:]) {
            result.append(NSAttributedString(string: string, attributes: attributes))
        }
        func appendSpans(_ spans: [Span], block: [NSAttributedString.Key: Any] = [:]) {
            for span in spans {
                var attributes = block
                if span.bold { attributes[.limeBold] = true }
                if span.italic { attributes[.limeItalic] = true }
                if span.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                if span.strike { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                if span.code { attributes[.limeCode] = true }
                if let link = span.link, let url = URL(string: link) { attributes[.link] = url }
                append(span.text, attributes)
            }
        }
        for (index, block) in blocks.enumerated() {
            if index > 0 { append("\n\n") }
            switch block {
            case .paragraph(let spans): appendSpans(spans)
            case .code(let code):
                let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
                for (n, line) in lines.enumerated() {
                    append(String(line) + (n < lines.count - 1 ? "\n" : ""), [.limeBlock: BlockKind.code.rawValue])
                }
            case .list(let items):
                var counters = [0, 0]
                for (n, item) in items.enumerated() {
                    let slot = Int(min(item.level, 1))
                    let kind: BlockKind = item.ordered ? .number : .bullet
                    counters[slot] = item.ordered ? (counters[slot] == 0 ? Int(max(item.number, 1)) : counters[slot] + 1) : 0
                    let attributes: [NSAttributedString.Key: Any] = [.limeBlock: kind.rawValue, .limeLevel: slot]
                    append(item.ordered ? "\(counters[slot]). " : bulletMarker, attributes)
                    appendSpans(item.spans, block: attributes)
                    if n < items.count - 1 { append("\n", attributes) }
                }
            }
        }
        restyle(result)
        return result
    }

    // MARK: State and editing

    /// What the next typed character gets: the semantic styles of the character before the caret (the text
    /// view itself forgets custom attributes between keystrokes, so a bold run would end after one letter).
    static func typingAttributes(in text: NSAttributedString, caret: Int) -> [NSAttributedString.Key: Any] {
        var typing: [NSAttributedString.Key: Any] = [.font: baseFont(), .foregroundColor: UIColor.label]
        guard caret > 0, caret <= text.length else { return typing }
        let previous = text.attributes(at: caret - 1, effectiveRange: nil)
        for key in [NSAttributedString.Key.limeBold, .limeItalic, .limeCode, .limeBlock, .limeLevel, .underlineStyle, .strikethroughStyle] {
            if let value = previous[key] { typing[key] = value }
        }
        // The start of a new line is not a list item (a list item's line break does not carry the list on: Return
        // makes the next marker itself); a code line's does, so code goes on being code.
        if (text.string as NSString).substring(with: NSRange(location: caret - 1, length: 1)) == "\n", (previous[.limeBlock] as? String) != BlockKind.code.rawValue {
            typing[.limeBlock] = nil
            typing[.limeLevel] = nil
        }
        return typing
    }

    /// What is pressed for a selection (every character has it) or, with a caret, for what would be typed.
    static func state(in text: NSAttributedString, selection: NSRange, typing: [NSAttributedString.Key: Any]) -> FormattingState {
        var state = FormattingState()
        func has(_ key: NSAttributedString.Key) -> Bool {
            if selection.length > 0 { return allCharacters(in: text, range: selection) { $0[key] != nil } }
            return typing[key] != nil
        }
        state.bold = has(.limeBold)
        state.italic = has(.limeItalic)
        state.underline = has(.underlineStyle)
        state.strike = has(.strikethroughStyle)
        state.code = has(.limeCode)
        state.link = has(.link)
        let touched = paragraphs(in: text, covering: selection).map { blockKind(in: text, at: $0.location) }
        state.bullets = !touched.isEmpty && touched.allSatisfy { $0 == .bullet }
        state.numbers = !touched.isEmpty && touched.allSatisfy { $0 == .number }
        return state
    }

    private static func allCharacters(in text: NSAttributedString, range: NSRange, where test: ([NSAttributedString.Key: Any]) -> Bool) -> Bool {
        var all = true
        text.enumerateAttributes(in: range) { attributes, _, stop in
            if !test(attributes) { all = false; stop.pointee = true }
        }
        return all
    }

    static func attributeKey(for format: InlineFormat) -> NSAttributedString.Key {
        switch format {
        case .bold: .limeBold
        case .italic: .limeItalic
        case .underline: .underlineStyle
        case .strike: .strikethroughStyle
        case .code: .limeCode
        }
    }

    static func attributeValue(for format: InlineFormat) -> Any {
        switch format {
        case .underline, .strike: NSUnderlineStyle.single.rawValue
        default: true
        }
    }

    /// Turns a style on for the selection, or off when every character already has it. Returns whether it is now on.
    @discardableResult
    static func toggle(_ format: InlineFormat, in text: NSMutableAttributedString, range: NSRange) -> Bool {
        let key = attributeKey(for: format)
        let on = !allCharacters(in: text, range: range) { $0[key] != nil }
        if on { text.addAttribute(key, value: attributeValue(for: format), range: range) } else { text.removeAttribute(key, range: range) }
        restyle(text)
        return on
    }

    /// Sets or clears a link on a range.
    static func setLink(_ url: URL?, in text: NSMutableAttributedString, range: NSRange) {
        if let url { text.addAttribute(.link, value: url, range: range) } else { text.removeAttribute(.link, range: range) }
    }

    /// Makes the touched paragraphs a list of `kind`, or plain again when they all already are. Returns the new selection.
    static func toggleList(_ kind: BlockKind, in text: NSMutableAttributedString, selection: NSRange) -> NSRange {
        precondition(kind != .code)
        let touched = paragraphs(in: text, covering: selection)
        let allSame = touched.allSatisfy { blockKind(in: text, at: $0.location) == kind }
        var delta = 0
        var selectionStart = selection.location
        var selectionEnd = NSMaxRange(selection)
        for original in touched.reversed() {
            var paragraph = original
            if let existing = markerRange(in: text, paragraph: paragraph) {
                text.deleteCharacters(in: existing)
                paragraph.length -= existing.length
                if existing.location < selectionStart { selectionStart -= min(existing.length, selectionStart - existing.location) }
                if existing.location < selectionEnd { selectionEnd -= min(existing.length, selectionEnd - existing.location) }
                delta -= existing.length
            }
            if allSame {
                text.removeAttribute(.limeBlock, range: paragraph)
                text.removeAttribute(.limeLevel, range: paragraph)
            } else {
                let marker = kind == .bullet ? bulletMarker : "1. "
                let attributes: [NSAttributedString.Key: Any] = [.limeBlock: kind.rawValue, .limeLevel: 0]
                text.insert(NSAttributedString(string: marker, attributes: attributes), at: paragraph.location)
                text.addAttributes(attributes, range: NSRange(location: paragraph.location, length: paragraph.length + marker.utf16.count))
                if paragraph.location <= selectionStart { selectionStart += marker.utf16.count }
                if paragraph.location < selectionEnd || selection.length == 0 { selectionEnd += marker.utf16.count }
                delta += marker.utf16.count
            }
        }
        renumber(text)
        restyle(text)
        let length = text.length
        selectionStart = max(0, min(selectionStart, length))
        selectionEnd = max(selectionStart, min(selectionEnd, length))
        return NSRange(location: selectionStart, length: selectionEnd - selectionStart)
    }

    /// Makes the numbers of every numbered run count 1, 2, 3 (after an insert or a delete).
    static func renumber(_ text: NSMutableAttributedString) {
        var counters = [0, 0]
        var location = 0
        var changed = true
        while changed {
            changed = false
            counters = [0, 0]
            location = 0
            while location < text.length {
                let paragraph = (text.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
                let kind = blockKind(in: text, at: paragraph.location)
                let level = min((text.attribute(.limeLevel, at: paragraph.location, effectiveRange: nil) as? Int) ?? 0, 1)
                if kind == .number, let marker = markerRange(in: text, paragraph: paragraph) {
                    counters[level] += 1
                    let wanted = "\(counters[level]). "
                    if (text.string as NSString).substring(with: marker) != wanted {
                        text.replaceCharacters(in: marker, with: NSAttributedString(string: wanted, attributes: text.attributes(at: marker.location, effectiveRange: nil)))
                        changed = true
                        break
                    }
                } else if kind != .number {
                    counters[level] = 0
                }
                location = NSMaxRange(paragraph)
            }
        }
    }

    /// Makes the touched lines a code block (when the selection spans lines) or toggles inline code.
    static func toggleCode(in text: NSMutableAttributedString, selection: NSRange) -> NSRange {
        let string = text.string as NSString
        let multiLine = selection.length > 0 && string.substring(with: selection).contains("\n")
        let inCodeBlock = paragraphs(in: text, covering: selection).allSatisfy { blockKind(in: text, at: $0.location) == .code }
            && string.length > 0
        if multiLine || (inCodeBlock && selection.length == 0) {
            for paragraph in paragraphs(in: text, covering: selection) {
                if let marker = markerRange(in: text, paragraph: paragraph) {
                    text.deleteCharacters(in: marker)
                }
            }
            let touched = paragraphs(in: text, covering: selection)
            let allCode = touched.allSatisfy { blockKind(in: text, at: $0.location) == .code }
            for paragraph in touched {
                if allCode { text.removeAttribute(.limeBlock, range: paragraph) } else {
                    text.removeAttribute(.limeLevel, range: paragraph)
                    text.addAttribute(.limeBlock, value: BlockKind.code.rawValue, range: paragraph)
                }
            }
            renumber(text)
            restyle(text)
            return NSRange(location: min(selection.location, text.length), length: 0)
        }
        if selection.length > 0 { toggle(.code, in: text, range: selection) }
        return selection
    }

    /// What Return does at `range`: inside a list it starts the next item (or, on an empty item, ends the list).
    /// Returns true when it handled the key.
    static func handleReturn(in text: NSMutableAttributedString, selection: inout NSRange) -> Bool {
        guard selection.length == 0 else { return false }
        let paragraph = paragraphs(in: text, covering: selection)[0]
        guard let kind = blockKind(in: text, at: min(paragraph.location, max(text.length - 1, 0))) ?? blockKindForEmptyTail(text, selection), kind != .code
        else { return false }
        guard let marker = markerRange(in: text, paragraph: paragraph) else { return false }
        let contentLength = paragraph.length - marker.length - (text.string.hasSuffix("\n") && NSMaxRange(paragraph) == text.length ? 0 : (hasNewline(text, paragraph) ? 1 : 0))
        if contentLength <= 0 {
            // An empty item: Return ends the list.
            text.deleteCharacters(in: marker)
            let rest = NSRange(location: paragraph.location, length: max(paragraph.length - marker.length, 0))
            text.removeAttribute(.limeBlock, range: rest)
            text.removeAttribute(.limeLevel, range: rest)
            selection = NSRange(location: paragraph.location, length: 0)
            renumber(text); restyle(text)
            return true
        }
        let level = (text.attribute(.limeLevel, at: paragraph.location, effectiveRange: nil) as? Int) ?? 0
        let attributes: [NSAttributedString.Key: Any] = [.limeBlock: kind.rawValue, .limeLevel: level]
        let next = NSMutableAttributedString(string: "\n", attributes: attributes)
        next.append(NSAttributedString(string: kind == .bullet ? bulletMarker : "1. ", attributes: attributes))
        text.replaceCharacters(in: selection, with: next)
        selection = NSRange(location: selection.location + next.length, length: 0)
        renumber(text); restyle(text)
        return true
    }

    private static func hasNewline(_ text: NSAttributedString, _ paragraph: NSRange) -> Bool {
        paragraph.length > 0 && (text.string as NSString).substring(with: NSRange(location: NSMaxRange(paragraph) - 1, length: 1)) == "\n"
    }

    private static func blockKindForEmptyTail(_ text: NSAttributedString, _ selection: NSRange) -> BlockKind? {
        guard text.length > 0, selection.location == text.length else { return nil }
        return blockKind(in: text, at: text.length - 1)
    }
}
