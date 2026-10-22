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
    /// On a numbered item's marker, when the run was started at a number other than 1 ("3. " typed at a line's start).
    static let limeStart = NSAttributedString.Key("lime.start")
    /// On the characters of a list marker ("• ", "2. ") and nowhere else, so a marker that an edit has cut in half can be told from the words.
    static let limeMarker = NSAttributedString.Key("lime.marker")
    /// On the characters of a mention (LIME-181): the mentioned person's user id (or "everyone"). The characters are one unit: an edit takes all or none.
    static let limeMention = NSAttributedString.Key("lime.mention")
    /// On the one character of a picture (or file) put into a jam article (LIME-188e): the index of the file in the post's list.
    static let limeImage = NSAttributedString.Key("lime.image")
    /// On every character of a paragraph of a jam post that is a heading ("h1", "h2", "h3"), a quote, an indented paragraph or a button (LIME-188l).
    /// A separate attribute from `limeBlock`, so the list and code editing never meets one.
    static let limePara = NSAttributedString.Key("lime.para")
    /// On a button paragraph: its https address.
    static let limeButton = NSAttributedString.Key("lime.button")
    /// On a button paragraph: its caption (above it in the reader) and its palette colour name (LIME-188q).
    static let limeButtonCaption = NSAttributedString.Key("lime.button.caption")
    static let limeButtonColour = NSAttributedString.Key("lime.button.colour")
}

enum InlineFormat: CaseIterable {
    case bold, italic, underline, strike, code
}

enum BlockKind: String { case bullet, number, code }

/// What the toolbar shows as pressed for the caret or selection.
struct FormattingState: Equatable {
    var bold = false, italic = false, underline = false, strike = false, code = false
    var link = false, bullets = false, numbers = false
    /// A jam post's paragraph styles at the caret: the heading level (1 to 3, or 0), a quote, an indented paragraph.
    var heading = 0, quote = false, indented = false
    /// The text view's undo and redo have something to do (a jam post's strip shows both).
    var canUndo = false, canRedo = false
    /// The caret or selection touches a list item (the Indent and Outdent buttons show), and whether each can change anything.
    var inList = false, canIndent = false, canOutdent = false
}

enum ComposerDocument {
    static let bulletMarker = "• "
    /// The bullet for a level, from the core's marker rule ("•", "◦", "▪"), with the space after it.
    static func bulletMarker(level: Int) -> String {
        listMarkers(items: [ListItem(level: UInt32(max(0, min(level, 2))), ordered: false, number: 0, spans: [])])[0] + " "
    }
    private static let bulletGlyphs: [String] = (0...2).map { bulletMarker(level: $0) }

    static func listLevel(in text: NSAttributedString, at location: Int) -> Int {
        guard location < text.length else { return 0 }
        return min((text.attribute(.limeLevel, at: location, effectiveRange: nil) as? Int) ?? 0, Int(maxListLevel()))
    }

    // MARK: Fonts

    /// The body font in lime's typeface and text size (LIME-168): scaled with the phone's size, or with lime's own when Settings → Text size
    /// overrides it (UIKit does not see SwiftUI's Dynamic Type override, so the category is passed explicitly).
    static func baseFont() -> UIFont {
        let preferences = TextPreferences.shared
        let traits = preferences.overrideCategory.map { UITraitCollection(preferredContentSizeCategory: $0) }
        let basis = preferences.typeface.postScriptName(for: .regular).flatMap { UIFont(name: $0, size: 17) } ?? UIFont.systemFont(ofSize: 17)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: basis, compatibleWith: traits)
    }

    /// `base` with bold and/or italic; a typeface with no italic gets a slant instead, so italics still show.
    static func styled(_ base: UIFont, traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard !traits.isEmpty else { return base }
        if let descriptor = base.fontDescriptor.withSymbolicTraits(traits) {
            let font = UIFont(descriptor: descriptor, size: base.pointSize)
            if !traits.contains(.traitItalic) || font.fontDescriptor.symbolicTraits.contains(.traitItalic) { return font }
        }
        var slanted = base
        if traits.contains(.traitBold), let bold = base.fontDescriptor.withSymbolicTraits(.traitBold) { slanted = UIFont(descriptor: bold, size: base.pointSize) }
        guard traits.contains(.traitItalic) else { return slanted }
        let slant = CGAffineTransform(a: 1, b: 0, c: CGFloat(tan(14.0 * Double.pi / 180)), d: 1, tx: 0, ty: 0)
        return UIFont(descriptor: slanted.fontDescriptor.withMatrix(slant), size: base.pointSize)
    }

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
            } else if !traits.isEmpty {
                font = styled(base, traits: traits)
            }
            if attributes[.limeMention] != nil {
                font = styled(base, traits: [.traitBold])
                text.addAttribute(.foregroundColor, value: UIColor(Theme.linkOther), range: range)
            }
            var tint: UIColor?
            if let para = attributes[.limePara] as? String {
                switch para {
                case "h1": font = styled(base.withSize(base.pointSize * 1.6), traits: [.traitBold])
                case "h2": font = styled(base.withSize(base.pointSize * 1.35), traits: [.traitBold])
                case "h3": font = styled(base.withSize(base.pointSize * 1.15), traits: [.traitBold])
                case "h4": font = styled(base.withSize(base.pointSize * 1.05), traits: [.traitBold])
                case "h5": font = styled(base.withSize(base.pointSize * 0.98), traits: [.traitBold])
                case "h6": font = styled(base.withSize(base.pointSize * 0.85), traits: [.traitBold]); tint = UIColor(Theme.textSecondary)
                case "quote": font = styled(base, traits: traits.union([.traitItalic])); tint = UIColor(Theme.textSecondary)
                case "button": font = styled(base, traits: traits.union([.traitBold])); tint = UIColor(Theme.linkOther)
                case "divider": font = styled(base.withSize(base.pointSize * 0.8), traits: []); tint = UIColor(Theme.hairline)
                case "freewall": font = styled(base.withSize(base.pointSize * 0.8), traits: []); tint = UIColor(Theme.textSecondary)
                default: break
                }
                if let tint { text.addAttribute(.foregroundColor, value: tint, range: range) }
            }
            text.addAttribute(.font, value: font, range: range)
            if inline || block == .code {
                text.addAttribute(.backgroundColor, value: ink.withAlphaComponent(0.10), range: range)
            } else if (attributes[.limePara] as? String) == "button" {
                text.addAttribute(.backgroundColor, value: ink.withAlphaComponent(0.08), range: range)
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
            } else if paragraph.length > 0, let para = text.attribute(.limePara, at: paragraph.location, effectiveRange: nil) as? String, ["quote", "indent", "button", "divider", "freewall"].contains(para) {
                let style = NSMutableParagraphStyle()
                let inset: CGFloat = para == "indent" ? 24 : para == "quote" ? 16 : 0
                style.firstLineHeadIndent = inset
                style.headIndent = inset
                if ["button", "divider", "freewall"].contains(para) { style.alignment = .center }
                if para == "divider" { style.paragraphSpacingBefore = 12; style.paragraphSpacing = 12 }
                text.addAttribute(.paragraphStyle, value: style, range: paragraph)
            } else {
                text.removeAttribute(.paragraphStyle, range: paragraph)
            }
            location = NSMaxRange(paragraph)
        }
        text.endEditing()
    }

    // MARK: Pictures in an article (LIME-188e)

    /// Puts a picture (or a file's card) at `location` as a paragraph of its own, full width; returns where the caret goes (after it, on a fresh line).
    /// `index` is the file's place in the post's list.
    @discardableResult
    static func insertImage(_ image: UIImage, index: Int, into text: NSMutableAttributedString, at location: Int, width: CGFloat) -> Int {
        let attachment = NSTextAttachment()
        attachment.image = image
        // The picture at its own proportions (left-aligned in the line), never wider than the column or taller than 320 pt.
        let ratio = image.size.height / max(image.size.width, 1)
        var drawnWidth = width, drawnHeight = width * ratio
        if drawnHeight > 320 { drawnHeight = 320; drawnWidth = 320 / max(ratio, 0.01) }
        attachment.bounds = CGRect(x: 0, y: 0, width: drawnWidth, height: drawnHeight)
        let picture = NSMutableAttributedString(attachment: attachment)
        picture.addAttribute(.limeImage, value: index, range: NSRange(location: 0, length: picture.length))
        var at = min(max(location, 0), text.length)
        let string = text.string as NSString
        if at > 0, string.character(at: at - 1) != 0x0A { text.insert(NSAttributedString(string: "\n"), at: at); at += 1 }
        text.insert(picture, at: at)
        at += picture.length
        let nextIsNewline = at < text.length && (text.string as NSString).character(at: at) == 0x0A
        if !nextIsNewline { text.insert(NSAttributedString(string: "\n"), at: at) }
        return at + 1
    }

    /// The pictures of an article in the order they appear, as file indexes; used to keep only the files that are still in the text.
    static func imageIndexes(in text: NSAttributedString) -> [Int] {
        var found: [Int] = []
        text.enumerateAttribute(.limeImage, in: NSRange(location: 0, length: text.length)) { value, _, _ in if let index = value as? Int { found.append(index) } }
        return found
    }

    // MARK: Mentions (LIME-181)

    /// The mention that covers `location` (the whole run of it), if any. A caret at either edge is not inside it.
    static func mentionRange(in text: NSAttributedString, at location: Int) -> NSRange? {
        guard location >= 0, location < text.length else { return nil }
        var range = NSRange(location: 0, length: 0)
        guard let id = text.attribute(.limeMention, at: location, longestEffectiveRange: &range, in: NSRange(location: 0, length: text.length)) as? String, !id.isEmpty else { return nil }
        return range
    }

    /// `range` made to take whole mentions: a mention it touches in part is taken completely.
    static func expandedToMentions(_ range: NSRange, in text: NSAttributedString) -> NSRange {
        guard range.length > 0 else { return range }
        var result = range
        if let first = mentionRange(in: text, at: range.location) { result = NSUnionRange(result, first) }
        if let last = mentionRange(in: text, at: NSMaxRange(range) - 1) { result = NSUnionRange(result, last) }
        return result
    }

    /// The "@word" being typed just before the caret: the "@" must start the text or follow white space, the words after it contain no
    /// line break and are at most 30 characters, and none of it is already a mention. `range` covers the "@" and what follows.
    static func mentionTrigger(in text: NSAttributedString, caret: Int) -> (range: NSRange, query: String)? {
        let string = text.string as NSString
        guard caret > 0, caret <= string.length else { return nil }
        var at = caret - 1
        while at >= 0, caret - at <= 31 {
            let character = string.character(at: at)
            if character == 0x0A || character == 0x0D { return nil }
            if character == 0x40 {   // "@"
                let startsWord = at == 0 || CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(string.character(at: at - 1)) ?? "x")
                guard startsWord, mentionRange(in: text, at: at) == nil else { return nil }
                let range = NSRange(location: at, length: caret - at)
                return (range, string.substring(with: NSRange(location: at + 1, length: caret - at - 1)))
            }
            at -= 1
        }
        return nil
    }

    /// Puts a mention in place of `range`, with a plain space after it; returns where the caret goes.
    @discardableResult
    static func insertMention(_ name: String, id: String, replacing range: NSRange, in text: NSMutableAttributedString) -> Int {
        let mention = NSMutableAttributedString(string: "@" + name, attributes: [.limeMention: id])
        mention.append(NSAttributedString(string: " "))
        text.replaceCharacters(in: range, with: mention)
        return range.location + mention.length
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
            guard let glyph = bulletGlyphs.first(where: { line.hasPrefix($0) }) else { return nil }
            return NSRange(location: paragraph.location, length: glyph.utf16.count)
        }
        var digits = 0
        for scalar in line.unicodeScalars { if scalar.properties.numericType != nil && scalar.isASCII { digits += 1 } else { break } }
        guard digits > 0, (line as NSString).length > digits + 1, (line as NSString).substring(with: NSRange(location: digits, length: 2)) == ". " else { return nil }
        return NSRange(location: paragraph.location, length: digits + 2)
    }

    // MARK: Paragraph styles of a jam post (LIME-188l)

    static func paraStyle(in text: NSAttributedString, at location: Int) -> String? {
        guard location < text.length else { return nil }
        return text.attribute(.limePara, at: location, effectiveRange: nil) as? String
    }

    /// Sets `style` ("h1"… "quote", "indent") on the plain paragraphs the selection touches, or takes it off when they all have it already (a list item
    /// or a code line is left alone). Returns whether it is on now.
    @discardableResult
    static func toggleParagraphStyle(_ style: String, in text: NSMutableAttributedString, selection: NSRange) -> Bool {
        let touched = paragraphs(in: text, covering: selection).filter { $0.length > 0 && blockKind(in: text, at: $0.location) == nil && text.attribute(.limeImage, at: $0.location, effectiveRange: nil) == nil && !isSpecial(paraStyle(in: text, at: $0.location)) }
        let off = !touched.isEmpty && touched.allSatisfy { paraStyle(in: text, at: $0.location) == style }
        for paragraph in touched {
            text.removeAttribute(.limeButton, range: paragraph)
            text.removeAttribute(.limeButtonCaption, range: paragraph)
            text.removeAttribute(.limeButtonColour, range: paragraph)
            if off { text.removeAttribute(.limePara, range: paragraph) } else { text.addAttribute(.limePara, value: style, range: paragraph) }
        }
        restyle(text)
        return !off
    }

    /// Sets a heading level on the plain paragraphs the selection touches (`"h1"` to `"h6"`), or turns them back into normal text (`nil`).
    static func setHeading(_ style: String?, in text: NSMutableAttributedString, selection: NSRange) {
        let touched = paragraphs(in: text, covering: selection).filter { $0.length > 0 && blockKind(in: text, at: $0.location) == nil && text.attribute(.limeImage, at: $0.location, effectiveRange: nil) == nil && !isSpecial(paraStyle(in: text, at: $0.location)) }
        for paragraph in touched {
            let current = paraStyle(in: text, at: paragraph.location)
            if let style { text.addAttribute(.limePara, value: style, range: paragraph) }
            else if current?.hasPrefix("h") == true { text.removeAttribute(.limePara, range: paragraph) }
        }
        restyle(text)
    }

    /// Indent moves a plain paragraph one level in (a list keeps its own levels); outdent takes it back.
    static func shiftParagraphs(indent: Bool, in text: NSMutableAttributedString, selection: NSRange) {
        for paragraph in paragraphs(in: text, covering: selection) where paragraph.length > 0 && blockKind(in: text, at: paragraph.location) == nil && !isSpecial(paraStyle(in: text, at: paragraph.location)) {
            let current = paraStyle(in: text, at: paragraph.location)
            if indent, current == nil { text.addAttribute(.limePara, value: "indent", range: paragraph) }
            if !indent, current == "indent" { text.removeAttribute(.limePara, range: paragraph) }
        }
        restyle(text)
    }

    static let dividerText = "\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}"
    static let freewallText = "Subscribers only below"

    /// Blocks that are not words: a button, a divider and the freewall.
    static func isSpecial(_ style: String?) -> Bool { ["button", "divider", "freewall"].contains(style ?? "") }

    /// Whether the text already has its one freewall.
    static func hasFreewall(in text: NSAttributedString) -> Bool {
        var found = false
        text.enumerateAttribute(.limePara, in: NSRange(location: 0, length: text.length)) { value, _, stop in if (value as? String) == "freewall" { found = true; stop.pointee = true } }
        return found
    }

    /// A divider or the freewall as a paragraph of its own at `location`; returns the caret after it.
    @discardableResult
    static func insertRule(_ style: String, into text: NSMutableAttributedString, at location: Int) -> Int {
        let label = style == "freewall" ? freewallText : dividerText
        let rule = NSAttributedString(string: label, attributes: [.limePara: style])
        var at = min(max(location, 0), text.length)
        let string = text.string as NSString
        if at > 0, string.character(at: at - 1) != 0x0A { text.insert(NSAttributedString(string: "\n"), at: at); at += 1 }
        text.insert(rule, at: at)
        at += rule.length
        let nextIsNewline = at < text.length && (text.string as NSString).character(at: at) == 0x0A
        if !nextIsNewline { text.insert(NSAttributedString(string: "\n"), at: at) }
        restyle(text)
        return at + 1
    }

    /// A button as a paragraph of its own at `location`; returns the caret after it.
    @discardableResult
    static func insertButton(_ title: String, url: String, caption: String = "", colour: String = "", into text: NSMutableAttributedString, at location: Int) -> Int {
        var attributes: [NSAttributedString.Key: Any] = [.limePara: "button", .limeButton: url]
        if !caption.isEmpty { attributes[.limeButtonCaption] = caption }
        if !colour.isEmpty { attributes[.limeButtonColour] = colour }
        let button = NSMutableAttributedString(string: title, attributes: attributes)
        var at = min(max(location, 0), text.length)
        let string = text.string as NSString
        if at > 0, string.character(at: at - 1) != 0x0A { text.insert(NSAttributedString(string: "\n"), at: at); at += 1 }
        text.insert(button, at: at)
        at += button.length
        let nextIsNewline = at < text.length && (text.string as NSString).character(at: at) == 0x0A
        if !nextIsNewline { text.insert(NSAttributedString(string: "\n"), at: at) }
        restyle(text)
        return at + 1
    }

    // MARK: Converting to Markdown

    /// The composer's text as blocks.
    static func blocks(from text: NSAttributedString) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [Span] = []        // the lines of the paragraph being built
        var listItems: [ListItem] = []
        var codeLines: [String] = []
        var quoted: [Span] = []           // the lines of a quote being built (a jam post)
        var indented: [Span] = []         // and of an indented paragraph
        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(spans: paragraph)); paragraph = [] }
            if !quoted.isEmpty { blocks.append(.quote(spans: quoted)); quoted = [] }
            if !indented.isEmpty { blocks.append(.indent(spans: indented)); indented = [] }
        }
        func flushList() {
            if !listItems.isEmpty { blocks.append(.itemList(items: listItems)); listItems = [] }
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
                let level = listLevel(in: text, at: line.location)
                let ordered = kind == .number
                // The number as written; the core counts on from the first of a run, per level.
                let number = marker.flatMap { UInt32((text.string as NSString).substring(with: $0).filter(\.isNumber)) } ?? 1
                let spans = spans(in: text, range: content)
                if !spans.isEmpty { listItems.append(ListItem(level: UInt32(level), ordered: ordered, number: ordered ? max(number, 1) : 0, spans: spans)) }
            case nil:
                flushList(); flushCode()
                if content.length == 1, string.substring(with: content) == "\u{FFFC}", let index = text.attribute(.limeImage, at: content.location, effectiveRange: nil) as? Int {
                    flushParagraph()
                    blocks.append(.image(caption: "", attachment: UInt32(max(0, index))))
                } else if content.length == 0 {
                    flushParagraph() // a blank line ends the paragraph
                } else {
                    let para = text.attribute(.limePara, at: content.location, effectiveRange: nil) as? String
                    let newline = Span(text: "\n", bold: false, italic: false, underline: false, strike: false, code: false, link: nil, mention: nil)
                    var lineSpans = spans(in: text, range: content)
                    switch para {
                    case "h1", "h2", "h3", "h4", "h5", "h6":
                        flushParagraph()
                        blocks.append(.heading(level: UInt32(para!.dropFirst()) ?? 1, spans: lineSpans))
                    case "divider":
                        flushParagraph()
                        blocks.append(.divider)
                    case "freewall":
                        flushParagraph()
                        blocks.append(.freewall)
                    case "button":
                        flushParagraph()
                        if let url = text.attribute(.limeButton, at: content.location, effectiveRange: nil) as? String {
                            let caption = text.attribute(.limeButtonCaption, at: content.location, effectiveRange: nil) as? String ?? ""
                            let colour = text.attribute(.limeButtonColour, at: content.location, effectiveRange: nil) as? String ?? ""
                            blocks.append(.button(text: string.substring(with: content), url: url, caption: caption, colour: colour))
                        }
                    case "quote":
                        if !paragraph.isEmpty || !indented.isEmpty { flushParagraph() }
                        if !quoted.isEmpty { lineSpans.insert(newline, at: 0) }
                        quoted.append(contentsOf: lineSpans)
                    case "indent":
                        if !paragraph.isEmpty || !quoted.isEmpty { flushParagraph() }
                        if !indented.isEmpty { lineSpans.insert(newline, at: 0) }
                        indented.append(contentsOf: lineSpans)
                    default:
                        if !quoted.isEmpty || !indented.isEmpty { flushParagraph() }
                        if !paragraph.isEmpty { lineSpans.insert(newline, at: 0) }
                        paragraph.append(contentsOf: lineSpans)
                    }
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
                text: (text.string as NSString).substring(with: run).replacingOccurrences(of: "\u{FFFC}", with: ""),
                bold: attributes[.limeBold] != nil, italic: attributes[.limeItalic] != nil,
                underline: attributes[.underlineStyle] != nil, strike: attributes[.strikethroughStyle] != nil,
                code: attributes[.limeCode] != nil, link: link, mention: attributes[.limeMention] as? String))
        }
        return result
    }

    /// The text to send.
    static func markdown(from text: NSAttributedString, post: Bool = false) -> String {
        post ? postMarkdownFromBlocks(blocks: blocks(from: text)) : messageMarkdownFromBlocks(blocks: blocks(from: text))
    }

    // MARK: Converting from Markdown

    /// A Markdown message as composer text (used to put a message back for editing, and by the tests).
    static func attributed(fromMarkdown markdown: String, post: Bool = false) -> NSMutableAttributedString {
        attributed(from: post ? parsePostMarkdown(text: markdown) : parseMessageMarkdown(text: markdown))
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
                if let id = span.mention { attributes[.limeMention] = id }
                else if let link = span.link, let url = URL(string: link) { attributes[.link] = url }
                append(span.text, attributes)
            }
        }
        for (index, block) in blocks.enumerated() {
            if index > 0 { append("\n\n") }
            switch block {
            case .paragraph(let spans): appendSpans(spans)
            case .image(_, let attachment):
                append("\u{FFFC}", [.limeImage: Int(attachment)])
            case .heading(let level, let spans): appendSpans(spans, block: [.limePara: "h\(min(max(level, 1), 6))"])
            case .quote(let spans): appendSpans(spans, block: [.limePara: "quote"])
            case .indent(let spans): appendSpans(spans, block: [.limePara: "indent"])
            case .button(let text, let url, let caption, let colour):
                var attributes: [NSAttributedString.Key: Any] = [.limePara: "button", .limeButton: url]
                if !caption.isEmpty { attributes[.limeButtonCaption] = caption }
                if !colour.isEmpty { attributes[.limeButtonColour] = colour }
                append(text, attributes)
            case .divider: append(Self.dividerText, [.limePara: "divider"])
            case .freewall: append(Self.freewallText, [.limePara: "freewall"])
            case .code(let code):
                let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
                for (n, line) in lines.enumerated() {
                    append(String(line) + (n < lines.count - 1 ? "\n" : ""), [.limeBlock: BlockKind.code.rawValue])
                }
            case .itemList(let items):
                let markers = listMarkers(items: items)
                // The same list counted from 1: an item that begins a run at another number remembers it.
                let fromOne = listMarkers(items: items.map { ListItem(level: $0.level, ordered: $0.ordered, number: 1, spans: []) })
                for (n, item) in items.enumerated() {
                    let slot = Int(min(item.level, maxListLevel()))
                    let kind: BlockKind = item.ordered ? .number : .bullet
                    let attributes: [NSAttributedString.Key: Any] = [.limeBlock: kind.rawValue, .limeLevel: slot]
                    var markerAttributes = attributes
                    markerAttributes[.limeMarker] = true
                    if item.ordered, fromOne[n] == "1.", markers[n] != "1." { markerAttributes[.limeStart] = Int(markers[n].dropLast()) }
                    append(markers[n] + " ", markerAttributes)
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
        for key in [NSAttributedString.Key.limeBold, .limeItalic, .limeCode, .limeBlock, .limeLevel, .limePara, .underlineStyle, .strikethroughStyle] {
            if let value = previous[key] { typing[key] = value }
        }
        // The start of a new line is not a list item (a list item's line break does not carry the list on: Return
        // makes the next marker itself); a code line's does, so code goes on being code.
        if (text.string as NSString).substring(with: NSRange(location: caret - 1, length: 1)) == "\n", (previous[.limeBlock] as? String) != BlockKind.code.rawValue {
            typing[.limeBlock] = nil
            typing[.limeLevel] = nil
            // A quote or an indented paragraph goes on with the next line; a heading or a button does not.
            if let para = previous[.limePara] as? String, para != "quote", para != "indent" { typing[.limePara] = nil }
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
        state.inList = touched.contains { $0 == .bullet || $0 == .number }
        let styles = paragraphs(in: text, covering: selection).map { $0.length > 0 ? paraStyle(in: text, at: $0.location) : (typing[.limePara] as? String) }
        if let first = styles.first, styles.allSatisfy({ $0 == first }), let first {
            if first.hasPrefix("h") { state.heading = Int(first.dropFirst()) ?? 0 }
            state.quote = first == "quote"
            state.indented = first == "indent"
        }
        if state.inList {
            state.canIndent = shiftedLevels(in: text, selection: selection, indent: true).contains { $0.from != $0.to }
            state.canOutdent = shiftedLevels(in: text, selection: selection, indent: false).contains { $0.from != $0.to }
        }
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
                // An item switching kind keeps its level.
                let level = blockKind(in: text, at: original.location) == nil ? 0 : listLevel(in: text, at: original.location)
                let marker = kind == .bullet ? bulletMarker(level: level) : "1. "
                let attributes: [NSAttributedString.Key: Any] = [.limeBlock: kind.rawValue, .limeLevel: level]
                text.insert(NSAttributedString(string: marker, attributes: attributes.merging([.limeMarker: true]) { $1 }), at: paragraph.location)
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

    /// Makes every list marker show what the core's rule says: bullets by level, and numbers counting per level
    /// (a run counts from 1, or from the number it was started at). Run after an insert, a delete or a level change.
    static func renumber(_ text: NSMutableAttributedString) {
        let string = text.string as NSString
        var run: [(marker: NSRange, kind: BlockKind, level: Int, start: Int)] = []
        var edits: [(NSRange, String)] = []
        func flush() {
            guard !run.isEmpty else { return }
            let items = run.map { ListItem(level: UInt32($0.level), ordered: $0.kind == .number, number: UInt32(max($0.start, 1)), spans: []) }
            for (entry, marker) in zip(run, listMarkers(items: items)) {
                let wanted = marker + " "
                if string.substring(with: entry.marker) != wanted { edits.append((entry.marker, wanted)) }
            }
            run = []
        }
        var location = 0
        while location < string.length {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            if let kind = blockKind(in: text, at: paragraph.location), kind != .code, let marker = markerRange(in: text, paragraph: paragraph) {
                let start = (text.attribute(.limeStart, at: marker.location, effectiveRange: nil) as? Int) ?? 1
                run.append((marker, kind, listLevel(in: text, at: paragraph.location), start))
            } else {
                flush()
            }
            location = NSMaxRange(paragraph)
        }
        flush()
        // From the end, so the earlier ranges stay valid.
        for (range, wanted) in edits.reversed() {
            text.replaceCharacters(in: range, with: NSAttributedString(string: wanted, attributes: text.attributes(at: range.location, effectiveRange: nil)))
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
        if contentLength <= 0, listLevel(in: text, at: paragraph.location) > 0 {
            // An empty nested item: Return steps back out one level.
            selection = shiftLevel(in: text, selection: selection, indent: false)
            return true
        }
        if contentLength <= 0 {
            // An empty top-level item: Return ends the list.
            text.deleteCharacters(in: marker)
            let rest = NSRange(location: paragraph.location, length: max(paragraph.length - marker.length, 0))
            text.removeAttribute(.limeBlock, range: rest)
            text.removeAttribute(.limeLevel, range: rest)
            selection = NSRange(location: paragraph.location, length: 0)
            renumber(text); restyle(text)
            return true
        }
        let level = listLevel(in: text, at: paragraph.location)
        let attributes: [NSAttributedString.Key: Any] = [.limeBlock: kind.rawValue, .limeLevel: level]
        let next = NSMutableAttributedString(string: "\n", attributes: attributes)
        next.append(NSAttributedString(string: kind == .bullet ? bulletMarker(level: level) : "1. ", attributes: attributes.merging([.limeMarker: true]) { $1 }))
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

    // MARK: Nesting: Indent and Outdent

    private static func allParagraphs(in text: NSAttributedString) -> [NSRange] {
        let string = text.string as NSString
        var result: [NSRange] = []
        var location = 0
        while location < string.length {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            result.append(paragraph)
            location = NSMaxRange(paragraph)
        }
        if string.length == 0 || string.hasSuffix("\n") { result.append(NSRange(location: string.length, length: 0)) }
        return result
    }

    /// The level each list paragraph the selection touches would take, by the core's indent rule (an item is at
    /// most one level deeper than the item above it, and at most level 2).
    static func shiftedLevels(in text: NSAttributedString, selection: NSRange, indent: Bool) -> [(paragraph: NSRange, from: Int, to: Int)] {
        let touched = Set(paragraphs(in: text, covering: selection).map(\.location))
        var previous: Int?
        var result: [(NSRange, Int, Int)] = []
        for paragraph in allParagraphs(in: text) {
            guard let kind = blockKind(in: text, at: paragraph.location), kind == .bullet || kind == .number else { previous = nil; continue }
            let level = listLevel(in: text, at: paragraph.location)
            if touched.contains(paragraph.location) {
                let target = Int(listLevelAfter(previousLevel: previous.map { UInt32($0) }, level: UInt32(level), indent: indent))
                result.append((paragraph, level, target))
                previous = target
            } else {
                previous = level
            }
        }
        return result
    }

    /// Indents or outdents every list item the selection touches. Returns the new selection (the same places in
    /// the same words; the markers may change length).
    static func shiftLevel(in text: NSMutableAttributedString, selection: NSRange, indent: Bool) -> NSRange {
        let changes = shiftedLevels(in: text, selection: selection, indent: indent).filter { $0.from != $0.to }
        guard !changes.isEmpty else { return selection }
        let start = anchor(in: text, at: selection.location)
        let end = anchor(in: text, at: NSMaxRange(selection))
        for change in changes { text.addAttribute(.limeLevel, value: change.to, range: change.paragraph) }
        renumber(text)
        restyle(text)
        let from = location(for: start, in: text)
        return NSRange(location: from, length: max(location(for: end, in: text) - from, 0))
    }

    /// A place in the text as (paragraph number, characters past the marker), so it survives markers changing length.
    private static func anchor(in text: NSAttributedString, at location: Int) -> (index: Int, offset: Int) {
        let paragraphs = allParagraphs(in: text)
        let index = paragraphs.lastIndex { $0.location <= location } ?? 0
        let paragraph = paragraphs[index]
        let contentStart = markerRange(in: text, paragraph: paragraph).map(NSMaxRange) ?? paragraph.location
        return (index, max(location - contentStart, 0))
    }

    private static func location(for anchor: (index: Int, offset: Int), in text: NSAttributedString) -> Int {
        let paragraphs = allParagraphs(in: text)
        let paragraph = paragraphs[min(anchor.index, paragraphs.count - 1)]
        let contentStart = markerRange(in: text, paragraph: paragraph).map(NSMaxRange) ?? paragraph.location
        return min(contentStart + anchor.offset, text.length)
    }

    // MARK: Lists that start as you type

    /// What an automatic list start replaced, so Backspace straight after it can give the typed text back.
    struct AutoStart {
        let paragraphStart: Int
        /// The text the person typed, with its space ("- ", "3. ").
        let typed: String
        /// The marker the item had before (a typed marker inside a list switches the item's kind), or nil for plain text.
        let oldMarker: NSAttributedString?
        /// Where the caret was left (just after the new marker).
        let caret: Int
    }

    /// Called as a space is about to be typed at a caret. When the text before it in the paragraph is exactly a
    /// list marker (the core's `listTrigger`), the typed marker becomes a list item and this returns what it did;
    /// otherwise it does nothing and returns nil. Not in a code block. Inside a list item the item switches kind
    /// and keeps its level.
    static func autoStart(in text: NSMutableAttributedString, selection: inout NSRange) -> AutoStart? {
        guard selection.length == 0 else { return nil }
        let paragraph = paragraphs(in: text, covering: selection)[0]
        let kind = blockKind(in: text, at: paragraph.location)
        guard kind != .code else { return nil }
        let marker = markerRange(in: text, paragraph: paragraph)
        let contentStart = marker.map(NSMaxRange) ?? paragraph.location
        guard selection.location >= contentStart else { return nil }
        let string = text.string as NSString
        let before = string.substring(with: NSRange(location: contentStart, length: selection.location - contentStart))
        guard !before.contains("\n"), let trigger = listTrigger(lineStart: before + " ") else { return nil }
        let level = marker == nil ? Int(trigger.level) : listLevel(in: text, at: paragraph.location)
        let oldMarker = marker.map { text.attributedSubstring(from: $0) }
        let newKind: BlockKind = trigger.ordered ? .number : .bullet
        let markerText = trigger.ordered ? "\(trigger.number). " : bulletMarker(level: level)
        var markerAttributes: [NSAttributedString.Key: Any] = [.limeBlock: newKind.rawValue, .limeLevel: level, .limeMarker: true]
        if trigger.ordered, trigger.number != 1 { markerAttributes[.limeStart] = Int(trigger.number) }
        // The marker and the typed marker go; the new marker comes; the rest of the paragraph becomes the item's text.
        text.replaceCharacters(in: NSRange(location: paragraph.location, length: selection.location - paragraph.location),
                               with: NSAttributedString(string: markerText, attributes: markerAttributes))
        let item = (text.string as NSString).paragraphRange(for: NSRange(location: paragraph.location, length: 0))
        text.addAttributes([.limeBlock: newKind.rawValue, .limeLevel: level], range: item)
        let caret = paragraph.location + markerText.utf16.count
        selection = NSRange(location: caret, length: 0)
        renumber(text)
        restyle(text)
        let after = (text.string as NSString).paragraphRange(for: NSRange(location: paragraph.location, length: 0))
        let newMarker = markerRange(in: text, paragraph: after)
        selection = NSRange(location: newMarker.map(NSMaxRange) ?? caret, length: 0)
        return AutoStart(paragraphStart: paragraph.location, typed: before + " ", oldMarker: oldMarker, caret: selection.location)
    }

    /// Undoes `autoStart` (Backspace straight after it): the typed text comes back, as plain text, and the item
    /// is what it was before. Returns false (and changes nothing) when the text is no longer as it was left.
    static func undoAutoStart(_ auto: AutoStart, in text: NSMutableAttributedString, selection: inout NSRange) -> Bool {
        guard auto.paragraphStart <= text.length else { return false }
        let paragraph = (text.string as NSString).paragraphRange(for: NSRange(location: auto.paragraphStart, length: 0))
        guard let marker = markerRange(in: text, paragraph: paragraph), NSMaxRange(marker) == auto.caret else { return false }
        let literal = NSAttributedString(string: auto.typed)
        if let old = auto.oldMarker {
            let oldAttributes = old.attributes(at: 0, effectiveRange: nil)
            text.replaceCharacters(in: marker, with: old)
            let item = (text.string as NSString).paragraphRange(for: NSRange(location: auto.paragraphStart, length: 0))
            text.addAttributes([.limeBlock: oldAttributes[.limeBlock] as Any, .limeLevel: oldAttributes[.limeLevel] as Any], range: item)
            text.insert(literal, at: auto.paragraphStart + old.length)
            selection = NSRange(location: auto.paragraphStart + old.length + literal.length, length: 0)
        } else {
            text.deleteCharacters(in: marker)
            let item = (text.string as NSString).paragraphRange(for: NSRange(location: auto.paragraphStart, length: 0))
            text.removeAttribute(.limeBlock, range: item)
            text.removeAttribute(.limeLevel, range: item)
            text.insert(literal, at: auto.paragraphStart)
            selection = NSRange(location: auto.paragraphStart + literal.length, length: 0)
        }
        renumber(text)
        restyle(text)
        return true
    }

    // MARK: Deleting

    /// The marker rules for a delete (what the text view's delegate does before UIKit deletes). They apply only to a
    /// delete that lies entirely inside one list marker: a single Backspace at the start of an item's text steps a
    /// nested item out one level, and any other such delete removes the marker (the item becomes plain text).
    /// Returns true when it handled the deletion itself and the text view must not delete. Any wider delete (a
    /// selection, Select All, Cut) is the text view's own, followed by `cleanUpAfterEdit`.
    static func handleMarkerDelete(in storage: NSMutableAttributedString, range: NSRange, selection: inout NSRange) -> Bool {
        guard range.length > 0, storage.length > 0 else { return false }
        let paragraph = paragraphs(in: storage, covering: NSRange(location: range.location, length: 0))[0]
        guard let marker = markerRange(in: storage, paragraph: paragraph), NSIntersectionRange(marker, range) == range else { return false }
        if range.length == 1, range.location == NSMaxRange(marker) - 1, listLevel(in: storage, at: paragraph.location) > 0 {
            selection = shiftLevel(in: storage, selection: NSRange(location: NSMaxRange(marker), length: 0), indent: false)
            return true
        }
        storage.deleteCharacters(in: marker)
        let rest = NSRange(location: paragraph.location, length: max(paragraph.length - marker.length, 0))
        storage.removeAttribute(.limeBlock, range: rest)
        storage.removeAttribute(.limeLevel, range: rest)
        selection = NSRange(location: paragraph.location, length: 0)
        return true
    }

    /// After an edit the text view made itself (a selection deleted, two lines joined): makes the list attributes
    /// consistent. Marker characters that are not a whole marker at the start of their paragraph go (no half "1"
    /// or stray bullet); a paragraph that starts as a list item is one item throughout, at its first part's level and
    /// kind; list attributes left on text that does not start a list item are cleared. Returns the selection,
    /// moved for what was removed.
    static func cleanUpAfterEdit(_ text: NSMutableAttributedString, selection: NSRange) -> NSRange {
        let string = text.string as NSString
        guard string.length > 0 else { return selection }
        var removals: [NSRange] = []
        // Marker characters outside a whole marker at the start of a list paragraph.
        var whole: [NSRange] = []
        var location = 0
        while location < string.length {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            if blockKind(in: text, at: paragraph.location) != .code, let marker = markerRange(in: text, paragraph: paragraph),
               text.attribute(.limeMarker, at: marker.location, effectiveRange: nil) != nil {
                whole.append(marker)
            }
            location = NSMaxRange(paragraph)
        }
        text.enumerateAttribute(.limeMarker, in: NSRange(location: 0, length: string.length)) { value, run, _ in
            guard value != nil else { return }
            var pending = run
            for marker in whole {
                let overlap = NSIntersectionRange(marker, pending)
                guard overlap.length > 0 else { continue }
                if overlap.location > pending.location { removals.append(NSRange(location: pending.location, length: overlap.location - pending.location)) }
                pending = NSRange(location: NSMaxRange(overlap), length: NSMaxRange(pending) - NSMaxRange(overlap))
                if pending.length == 0 { break }
            }
            if pending.length > 0 { removals.append(pending) }
        }
        var moved = selection
        // Only characters a marker is made of are removed; anything else that wrongly carries the marker attribute
        // (typed words never should) keeps its place and just loses the attribute.
        let markerCharacters = CharacterSet(charactersIn: "•◦▪. ").union(CharacterSet(charactersIn: "0123456789"))
        var index = removals.count
        while index > 0 {
            index -= 1
            let range = removals[index]
            let removable = (text.string as NSString).substring(with: range).unicodeScalars.allSatisfy { markerCharacters.contains($0) }
            if removable {
                text.deleteCharacters(in: range)
                if range.location < moved.location { moved.location -= min(range.length, moved.location - range.location) }
            } else {
                text.removeAttribute(.limeMarker, range: range)
            }
        }
        // Every paragraph is plain, code, or one list item.
        let after = text.string as NSString
        location = 0
        while location < after.length {
            let paragraph = after.paragraphRange(for: NSRange(location: location, length: 0))
            let kind = blockKind(in: text, at: paragraph.location)
            if kind == .bullet || kind == .number, markerRange(in: text, paragraph: paragraph) != nil {
                let level = text.attribute(.limeLevel, at: paragraph.location, effectiveRange: nil) as Any
                text.addAttributes([.limeBlock: kind!.rawValue, .limeLevel: level], range: paragraph)
            } else if kind != .code {
                text.removeAttribute(.limeBlock, range: paragraph)
                text.removeAttribute(.limeLevel, range: paragraph)
            }
            location = NSMaxRange(paragraph)
        }
        return moved
    }
}
