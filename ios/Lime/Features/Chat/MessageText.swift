import SwiftUI

/// Draws a message's Markdown (the DESIGN-05 subset, parsed by LimeCore) as native text: styled runs,
/// lists, and code blocks that scroll sideways. Anything outside the subset arrives as plain text.
struct FormattedMessageText: View {
    let markdown: String
    /// The bubble's text colour.
    let ink: Color
    /// The colour of links on this bubble: a green of its own, so a link is not mistaken for underlined text.
    let link: Color
    /// The link that was just tapped, shown pressed for a moment.
    var pressed: String? = nil
    /// Words to highlight (in-chat find, or a message opened from search).
    var find: FindStyle? = nil
    /// Who the mentions are (LIME-181); nil outside a chat.
    @Environment(\.mentionContext) private var mentions
    /// A jam post's text (LIME-188e): reads image blocks, drawn by this closure (caption, attachment number). A chat message never has them.
    var postImage: ((String, Int) -> AnyView)? = nil
    @AppStorage(MentionStyle.storageKey) private var mentionStyle = MentionStyle.fullName.rawValue

    var body: some View {
        let blocks = MessageRender.blocks(markdown, post: postImage != nil)
        if blocks.count == 1, case .paragraph(let spans) = blocks[0] {
            // The common case, one paragraph, is a single piece of text.
            Text(MessageRender.attributed(spans, ink: ink, link: link, pressed: pressed, find: find, mentions: mentions, mentionStyle: MentionStyle(rawValue: mentionStyle) ?? .fullName)).font(Theme.body).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .paragraph(let spans):
                        Text(MessageRender.attributed(spans, ink: ink, link: link, pressed: pressed, find: find, mentions: mentions, mentionStyle: MentionStyle(rawValue: mentionStyle) ?? .fullName)).font(Theme.body).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
                    case .list(let items):
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(MessageRender.numbered(items).enumerated()), id: \.offset) { _, row in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(row.marker).font(Theme.body).foregroundStyle(ink).frame(minWidth: 14, alignment: .trailing)
                                    Text(MessageRender.attributed(row.item.spans, ink: ink, link: link, pressed: pressed, find: find, mentions: mentions, mentionStyle: MentionStyle(rawValue: mentionStyle) ?? .fullName)).font(Theme.body).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.leading, CGFloat(min(row.item.level, maxListLevel())) * 18)
                                .accessibilityElement(children: .combine)
                                .accessibilityValue(row.item.level > 0 ? "level \(row.item.level + 1) of \(maxListLevel() + 1)" : "")
                            }
                        }
                    case .image(let caption, let index):
                        if let postImage { postImage(caption, index) }
                    case .code(let text):
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(text)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(ink)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(10)
                        }
                        .background(ink.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}

/// Which words to highlight in a bubble, and whether this is the message find is on.
struct FindStyle: Equatable {
    /// Typed words, folded (see `SearchText.words`).
    let words: [String]
    let current: Bool
}

/// The pure parts of drawing (so they can be tested without a screen).
/// Settings → Customize → Mentions (LIME-181b): how @mentions read on this iPhone. Local only; the message itself carries the person's id.
enum MentionStyle: String, CaseIterable, Identifiable {
    case fullName, username
    var id: String { rawValue }
    static let storageKey = "lime.mentionStyle"
    var title: String { self == .fullName ? "Full name" : "Username" }
    static func stored(in defaults: UserDefaults = .standard) -> MentionStyle {
        defaults.string(forKey: storageKey).flatMap(MentionStyle.init(rawValue:)) ?? .fullName
    }
}

enum MessageRender {
    /// A block, in Swift's own shape (so tests and the views do not depend on the generated type's cases).
    enum DrawnBlock: Equatable {
        case paragraph([Span])
        case list([ListItem])
        case code(String)
        case image(caption: String, index: Int)
    }

    /// `post`: a jam post's text, which can hold image blocks; a chat message cannot.
    static func blocks(_ markdown: String, post: Bool = false) -> [DrawnBlock] {
        (post ? parsePostMarkdown(text: markdown) : parseMessageMarkdown(text: markdown)).map { block in
            switch block {
            case .paragraph(let spans): .paragraph(spans)
            case .itemList(let items): .list(items)
            case .code(let text): .code(text)
            case .image(let caption, let attachment): .image(caption: caption, index: Int(attachment))
            }
        }
    }

    /// A list's rows with their markers, from the core's rule: "•", "◦", "▪" by level, and numbers counted per level.
    static func numbered(_ items: [ListItem]) -> [(marker: String, item: ListItem)] {
        Array(zip(listMarkers(items: items), items)).map { (marker: $0, item: $1) }
    }

    /// One run of text with its styles. A link is its own green plus an underline (and a tint while pressed);
    /// `__underline__` is the text colour with a plain underline.
    /// Splits plain text runs so a bare web address ("https://famkind.com", any case of the scheme) becomes a link. Code and runs that
    /// already have a link are left alone; trailing punctuation stays outside the link.
    static func autoLinked(_ spans: [Span]) -> [Span] {
        guard let regex = try? NSRegularExpression(pattern: #"\bhttps?://[^\s<>"']+"#, options: [.caseInsensitive]) else { return spans }
        var out: [Span] = []
        for span in spans {
            guard span.link == nil, span.mention == nil, !span.code, span.text.range(of: "://") != nil else { out.append(span); continue }
            let text = span.text as NSString
            var cursor = 0
            func piece(_ s: String, link: String? = nil) -> Span {
                Span(text: s, bold: span.bold, italic: span.italic, underline: span.underline, strike: span.strike, code: false, link: link, mention: nil)
            }
            for match in regex.matches(in: span.text, range: NSRange(location: 0, length: text.length)) {
                var range = match.range
                // Closing punctuation after an address belongs to the sentence, not to the link.
                while range.length > 8, let last = text.substring(with: range).last, ".,;:!?)]}".contains(last) { range.length -= 1 }
                let url = text.substring(with: range)
                guard let host = URL(string: url)?.host, host.contains(".") else { continue }
                if range.location > cursor { out.append(piece(text.substring(with: NSRange(location: cursor, length: range.location - cursor)))) }
                // The scheme is case-insensitive: the link is stored with it in lower case.
                let colon = url.range(of: "://")!
                out.append(piece(url, link: url[..<colon.lowerBound].lowercased() + url[colon.lowerBound...]))
                cursor = range.location + range.length
            }
            if cursor < text.length { out.append(piece(text.substring(from: cursor))) }
            else if cursor == 0 { out.append(span) }
        }
        return out
    }

    static func attributed(_ spans: [Span], ink: Color, link linkColor: Color, pressed: String? = nil, find: FindStyle? = nil, mentions: MentionContext? = nil, mentionStyle: MentionStyle = .fullName) -> AttributedString {
        var result = AttributedString()
        for span in autoLinked(spans) {
            if let id = span.mention {
                result.append(mention(span, id: id, ink: ink, link: linkColor, mentions: mentions, style: mentionStyle))
                continue
            }
            var piece = AttributedString(span.text)
            var intent: InlinePresentationIntent = []
            if span.bold { intent.insert(.stronglyEmphasized) }
            if span.italic { intent.insert(.emphasized) }
            if span.code { intent.insert(.code) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            if span.underline { piece.underlineStyle = .single }
            if span.strike { piece.strikethroughStyle = .single }
            if span.code { piece.backgroundColor = ink.opacity(0.12) }
            if let link = span.link, let url = URL(string: link) {
                piece.link = url
                piece.underlineStyle = .single
                piece.foregroundColor = linkColor
                if link == pressed { piece.backgroundColor = linkColor.opacity(0.22) }
            }
            result.append(piece)
        }
        if let find { highlight(&result, find) }
        return result
    }

    /// A mention (LIME-181): "@" and the name this phone knows now (the written words if it does not), bold in the bubble's link colour (the
    /// weight and the @ mean it is not colour alone), not underlined. Tapping a person opens their profile. No bubble puts a highlight behind a mention (LIME-181c).
    static func mention(_ span: Span, id: String, ink: Color, link linkColor: Color, mentions: MentionContext?, style: MentionStyle = .fullName) -> AttributedString {
        let known = id == MentionContext.everyone ? nil : mentions?.shown(id, style: style)
        var piece = AttributedString(known ?? span.text)
        piece.inlinePresentationIntent = .stronglyEmphasized
        piece.foregroundColor = linkColor
        if id != MentionContext.everyone, let url = URL(string: MentionContext.scheme + ":" + id) { piece.link = url }
        return piece
    }

    /// A highlight behind each word that starts with a typed word (the same rule the search uses), the
    /// current match stronger. The ink is fixed so the words read on any bubble, light or dark.
    static func highlight(_ text: inout AttributedString, _ find: FindStyle) {
        let wanted = find.words
        guard !wanted.isEmpty else { return }
        let plain = String(text.characters)
        var start: String.Index?
        var spans: [Range<String.Index>] = []
        for index in plain.indices {
            let isWord = plain[index].isLetter || plain[index].isNumber
            if isWord, start == nil { start = index }
            if !isWord, let from = start { spans.append(from..<index); start = nil }
        }
        if let from = start { spans.append(from..<plain.endIndex) }
        for span in spans {
            let word = plain[span].folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            guard wanted.contains(where: { word.hasPrefix($0) }) else { continue }
            let lower = text.characters.index(text.startIndex, offsetBy: plain.distance(from: plain.startIndex, to: span.lowerBound))
            let upper = text.characters.index(text.startIndex, offsetBy: plain.distance(from: plain.startIndex, to: span.upperBound))
            text[lower..<upper].backgroundColor = find.current ? Theme.findCurrent : Theme.findMatch
            text[lower..<upper].foregroundColor = Theme.findInk
        }
    }

    /// Only these links open without asking (anything else, http and mailto here, asks first).
    static func opensWithoutAsking(_ url: URL) -> Bool { url.scheme?.lowercased() == "https" }
}


/// Who the mentions in a chat are, for drawing and tapping them (LIME-181).
struct MentionContext {
    static let everyone = "everyone"
    /// The scheme a drawn mention's tap link carries (`lime-mention:<user id>`).
    static let scheme = "lime-mention"
    let meID: String
    /// The name this phone knows for a person in this chat now.
    let name: (String) -> String?
    /// The username this phone already knows for a person (their public profile, if it was fetched), or nil.
    var username: (String) -> String? = { _ in nil }
    /// Opens a person's profile.
    let open: @MainActor (String) -> Void

    /// What a mention reads as on this phone: "@Full Name", or "@username" in Username mode when one is known (else the name).
    func shown(_ id: String, style: MentionStyle) -> String? {
        if style == .username, let handle = username(id), !handle.isEmpty { return "@" + handle }
        return name(id).map { "@" + $0 }
    }

    static func userID(from url: URL) -> String? {
        url.scheme == scheme ? String(url.absoluteString.dropFirst(scheme.count + 1)) : nil
    }
}

extension EnvironmentValues {
    @Entry var mentionContext: MentionContext? = nil
}
