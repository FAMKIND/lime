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

    var body: some View {
        let blocks = MessageRender.blocks(markdown)
        if blocks.count == 1, case .paragraph(let spans) = blocks[0] {
            // The common case, one paragraph, is a single piece of text.
            Text(MessageRender.attributed(spans, ink: ink, link: link, pressed: pressed)).font(Theme.body).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .paragraph(let spans):
                        Text(MessageRender.attributed(spans, ink: ink, link: link, pressed: pressed)).font(Theme.body).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
                    case .list(let items):
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(MessageRender.numbered(items).enumerated()), id: \.offset) { _, row in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(row.marker).font(Theme.body).foregroundStyle(ink).frame(minWidth: 14, alignment: .trailing)
                                    Text(MessageRender.attributed(row.item.spans, ink: ink, link: link, pressed: pressed)).font(Theme.body).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.leading, CGFloat(row.item.level) * 18)
                            }
                        }
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

/// The pure parts of drawing (so they can be tested without a screen).
enum MessageRender {
    /// A block, in Swift's own shape (so tests and the views do not depend on the generated type's cases).
    enum DrawnBlock: Equatable {
        case paragraph([Span])
        case list([ListItem])
        case code(String)
    }

    static func blocks(_ markdown: String) -> [DrawnBlock] {
        parseMessageMarkdown(text: markdown).map { block in
            switch block {
            case .paragraph(let spans): .paragraph(spans)
            case .list(let items): .list(items)
            case .code(let text): .code(text)
            }
        }
    }

    /// A list's rows with their markers: a bullet, or the number counting on from the first of a run.
    static func numbered(_ items: [ListItem]) -> [(marker: String, item: ListItem)] {
        var counters = [0, 0]
        return items.map { item in
            let level = Int(min(item.level, 1))
            if item.ordered {
                counters[level] = counters[level] == 0 ? Int(max(item.number, 1)) : counters[level] + 1
                return ("\(counters[level]).", item)
            }
            counters[level] = 0
            return ("•", item)
        }
    }

    /// One run of text with its styles. A link is its own green plus an underline (and a tint while pressed);
    /// `__underline__` is the text colour with a plain underline.
    static func attributed(_ spans: [Span], ink: Color, link linkColor: Color, pressed: String? = nil) -> AttributedString {
        var result = AttributedString()
        for span in spans {
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
        return result
    }

    /// Only these links open without asking (anything else, http and mailto here, asks first).
    static func opensWithoutAsking(_ url: URL) -> Bool { url.scheme?.lowercased() == "https" }
}
