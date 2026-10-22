import SwiftUI

/// The formatting toolbar that sits above the keyboard (Notion and Gmail's pattern): a floating glass
/// capsule that scrolls sideways when the items do not fit, and a separate round ✕ at the right end.
/// Items: B, I, U, S, link, code, bulleted list, numbered list, and (inside a list) Outdent and Indent. Each shows whether it is on for the
/// selection or the caret.
struct FormattingToolbar: View {
    let model: RichComposerModel

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    letter("B", on: model.format.bold, id: "fmt-bold", label: "Bold") { model.apply(.bold) }
                    letter("I", Font.body.italic(), on: model.format.italic, id: "fmt-italic", label: "Italic") { model.apply(.italic) }
                    letter("U", .body, underline: true, on: model.format.underline, id: "fmt-underline", label: "Underline") { model.apply(.underline) }
                    letter("S", .body, strike: true, on: model.format.strike, id: "fmt-strike", label: "Strikethrough") { model.apply(.strike) }
                    symbol("link", on: model.format.link, id: "fmt-link", label: "Link") { model.requestLink() }
                    symbol("chevron.left.forwardslash.chevron.right", on: model.format.code, id: "fmt-code", label: "Code") { model.toggleCode() }
                    symbol("list.bullet", on: model.format.bullets, id: "fmt-bullets", label: "Bulleted list") { model.toggleList(.bullet) }
                    symbol("list.number", on: model.format.numbers, id: "fmt-numbers", label: "Numbered list") { model.toggleList(.number) }
                    if model.isPost {
                        // A jam post (LIME-188l): headings, quote, indent for a plain paragraph, and a button.
                        heading(1); heading(2); heading(3)
                        symbol("text.quote", on: model.format.quote, id: "fmt-quote", label: "Quote") { model.toggleParagraph("quote") }
                        if !model.format.inList {
                            shift("decrease.indent", id: "fmt-para-outdent", label: "Outdent paragraph", enabled: model.format.indented) { model.shiftParagraph(indent: false) }
                            shift("increase.indent", id: "fmt-para-indent", label: "Indent paragraph", enabled: !model.format.indented) { model.shiftParagraph(indent: true) }
                        }
                        symbol("rectangle.and.hand.point.up.left", on: false, id: "fmt-button", label: "Button") { model.buttonRequest = ButtonRequest() }
                    }
                    if model.format.inList {
                        shift("decrease.indent", id: "fmt-outdent", label: "Outdent", enabled: model.format.canOutdent) { model.shiftList(indent: false) }
                        shift("increase.indent", id: "fmt-indent", label: "Indent", enabled: model.format.canIndent) { model.shiftList(indent: true) }
                    }
                }
                .padding(.horizontal, 6)
            }
            .accessibilityIdentifier("fmt-scroll")
            .frame(height: 46)
            .limeGlass(in: Capsule())
            Button { model.closeToolbar() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    .frame(width: 46, height: 46).limeGlass(in: Circle())
            }
            .accessibilityLabel("Close formatting").accessibilityIdentifier("fmt-close")
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func letter(_ text: String, _ font: Font = .body, bold: Bool = false, underline: Bool = false, strike: Bool = false,
                        on: Bool, id: String, label: String, action: @escaping () -> Void) -> some View {
        item(on: on, id: id, label: label, action: action) {
            Text(text)
                .font(id == "fmt-bold" ? .system(size: 18, weight: .bold) : font)
                .underline(underline).strikethrough(strike)
                .foregroundStyle(Theme.text)
        }
    }

    private func heading(_ level: Int) -> some View {
        item(on: model.format.heading == level, id: "fmt-h\(level)", label: "Heading \(level)", action: { model.toggleParagraph("h\(level)") }) {
            Text("H\(level)").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
        }
    }

    private func symbol(_ name: String, on: Bool, id: String, label: String, action: @escaping () -> Void) -> some View {
        item(on: on, id: id, label: label, action: action) {
            Image(systemName: name).font(.system(size: 17)).foregroundStyle(Theme.text)
        }
    }

    /// Indent and Outdent: shown only inside a list, dimmed (not hidden) when they cannot change anything.
    private func shift(_ name: String, id: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 17)).foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func item<Content: View>(on: Bool, id: String, label: String, action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            // Active is a faint fill and the icon in heavier ink, so it reads without a strong circle.
            content()
                .fontWeight(on ? .bold : .regular)
                .frame(width: 42, height: 38)
                .background(on ? Theme.pressed : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// The link sheet: an address, and the words to show when nothing is selected.
struct LinkSheet: View {
    let request: LinkRequest
    let composer: RichComposerModel
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var text = ""
    @State private var problem: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("Cancel") { dismiss() }.foregroundStyle(Theme.text).accessibilityIdentifier("link-cancel")
                Spacer()
                Text("Add link").font(Theme.title).foregroundStyle(Theme.text)
                Spacer()
                Button("Add") { add() }.font(Theme.title).foregroundStyle(Theme.text)
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("link-apply")
            }
            TextField("Address (https://…)", text: $address)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focused)
                .selectionTint()
                .padding(.horizontal, 16).frame(minHeight: 52)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityIdentifier("link-url")
            if !request.hasSelection {
                TextField("Text to show (optional)", text: $text)
                    .selectionTint()
                    .padding(.horizontal, 16).frame(minHeight: 52)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("link-text")
            }
            if let problem {
                Text(problem).font(Theme.secondary).foregroundStyle(Color.red).accessibilityIdentifier("link-error")
            } else {
                Text(LinkInput.url(from: address).map { "Opens \($0.absoluteString)" } ?? "Only http, https and mailto links are supported.").font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Theme.canvas.ignoresSafeArea())
        .presentationDetents([.medium])
        .onAppear { address = request.initialURL; focused = true }
    }

    private func add() {
        if let message = composer.applyLink(address: address, text: text) { problem = message } else { dismiss() }
    }
}

/// The button sheet (a jam post): the words on the button and its https address.
struct ButtonSheet: View {
    let composer: RichComposerModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var address = ""
    @State private var problem: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("Cancel") { dismiss() }.foregroundStyle(Theme.text).accessibilityIdentifier("button-cancel")
                Spacer()
                Text("Add button").font(Theme.title).foregroundStyle(Theme.text)
                Spacer()
                Button("Add") { add() }.font(Theme.title).foregroundStyle(Theme.text)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || address.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("button-apply")
            }
            TextField("Button text", text: $title).focused($focused).selectionTint()
                .padding(.horizontal, 16).frame(minHeight: 52)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityIdentifier("button-text")
            TextField("Address (https://\u{2026})", text: $address)
                .onChange(of: address) { problem = nil }
                .onSubmit { if let shown = LinkInput.https(from: address) { address = shown } }
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().selectionTint()
                .padding(.horizontal, 16).frame(minHeight: 52)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityIdentifier("button-url")
            if let problem {
                Text(problem).font(Theme.secondary).foregroundStyle(Color.red).accessibilityIdentifier("button-error")
            } else if let shown = LinkInput.https(from: address) {
                Text("Opens \(shown)").font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(2).accessibilityIdentifier("button-shown")
            } else {
                Text("A button opens a web address.").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Theme.canvas.ignoresSafeArea())
        .presentationDetents([.medium])
        .onAppear { focused = true }
    }

    private func add() {
        if let message = composer.applyButton(title: title, address: address) { problem = message } else { dismiss() }
    }
}
