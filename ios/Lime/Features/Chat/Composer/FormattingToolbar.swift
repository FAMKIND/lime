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
                    if model.isPost {
                        shift("arrow.uturn.backward", id: "fmt-undo", label: "Undo", enabled: model.format.canUndo) { model.undo() }
                        shift("arrow.uturn.forward", id: "fmt-redo", label: "Redo", enabled: model.format.canRedo) { model.redo() }
                    }
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

/// The Add button sheet (LIME-188q): ready buttons first (Standard, or With caption), then Custom button\u{2026}, with a colour row. Presets do something
/// inside lime and need no web address; "Comment" waits for LIME-189 and is not offered yet.
struct ButtonSheet: View {
    let composer: RichComposerModel
    /// Offered once comments exist (LIME-189).
    static let commentsExist = false
    @Environment(\.dismiss) private var dismiss
    @State private var captioned = false
    @State private var colour = ButtonPalette.lime
    @State private var step = Step.grid
    @State private var caption = ""
    @State private var title = ""
    @State private var address = ""
    @State private var problem: String?
    @FocusState private var focused: Field?

    private enum Field { case caption, title, address }
    private enum Step: Equatable { case grid, caption(Preset), custom }
    private enum Preset: String, CaseIterable {
        case subscribe, share, message
        var label: String { switch self { case .subscribe: "Subscribe"; case .share: "Share"; case .message: "Message me" } }
        var address: String { "lime:\(rawValue)" }
        var sample: String { switch self { case .subscribe: "Never miss a post"; case .share: "Pass it on to a colleague"; case .message: "Questions? Ask me" } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch step {
                    case .grid: grid
                    case .caption(let preset): captionStep(preset)
                    case .custom: custom
                    }
                    colours
                }
                .padding(20)
            }
            .background(Theme.canvas)
            .navigationTitle("Add button").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(step == .grid ? "Cancel" : "Back") { if step == .grid { dismiss() } else { step = .grid; problem = nil } }.accessibilityIdentifier("button-cancel") }
                if step == .custom {
                    ToolbarItem(placement: .confirmationAction) { Button("Add") { addCustom() }.fontWeight(.semibold).disabled(!customValid).accessibilityIdentifier("button-apply") }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Steps

    private var grid: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Style", selection: $captioned) {
                Text("Standard").tag(false)
                Text("With caption").tag(true)
            }
            .pickerStyle(.segmented).accessibilityIdentifier("button-segment")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                ForEach(Preset.allCases, id: \.self) { preset in
                    Button { choose(preset) } label: {
                        VStack(spacing: 6) {
                            if captioned { Text(preset.sample).font(Theme.caption).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).lineLimit(2) }
                            Text(preset.label).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(colour.labelColor).frame(maxWidth: .infinity, minHeight: 46)
                                .background(colour.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .buttonStyle(.plain).accessibilityLabel(preset.label).accessibilityHint("Adds the \(preset.label) button").accessibilityIdentifier("button-preset-\(preset.rawValue)")
                }
            }
            Button { step = .custom } label: {
                HStack { Text("Custom button\u{2026}").font(Theme.body).foregroundStyle(Theme.text); Spacer(); Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary) }
                    .padding(.horizontal, 16).frame(minHeight: 52).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain).accessibilityIdentifier("button-custom")
        }
    }

    private func captionStep(_ preset: Preset) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A short line above the button").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            TextField("Caption", text: $caption, prompt: Text(preset.sample)).focused($focused, equals: .caption)
                .onChange(of: caption) { _, now in if now.count > 120 { caption = String(now.prefix(120)) } }
                .padding(.horizontal, 16).frame(minHeight: 52).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous)).accessibilityIdentifier("button-caption-field")
            VStack(spacing: 8) {
                Text(caption.isEmpty ? preset.sample : caption).font(Theme.secondary).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                Text(preset.label).font(Theme.font(.body, weight: .semibold)).foregroundStyle(colour.labelColor).frame(maxWidth: .infinity, minHeight: 50).background(colour.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Button { insert(preset.label, preset.address, caption: caption) } label: {
                Text("Add button").font(Theme.title).foregroundStyle(Theme.accentInk).frame(maxWidth: .infinity, minHeight: 52).background(Theme.accent, in: Capsule())
            }
            .accessibilityIdentifier("button-caption-add")
        }
        .onAppear { focused = .caption }
    }

    private var custom: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                HStack { Text("Text").font(Theme.body).foregroundStyle(Theme.textSecondary).frame(width: 60, alignment: .leading)
                    TextField("Button text", text: $title).focused($focused, equals: .title).selectionTint().accessibilityIdentifier("button-text") }
                    .padding(.horizontal, 16).frame(minHeight: 52)
                Divider().overlay(Theme.hairline).padding(.leading, 16)
                HStack { Text("Link").font(Theme.body).foregroundStyle(Theme.textSecondary).frame(width: 60, alignment: .leading)
                    TextField("limemessenger.com", text: $address).focused($focused, equals: .address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().selectionTint()
                        .onChange(of: address) { problem = nil }
                        .onSubmit { if let shown = LinkInput.https(from: address) { address = shown } }
                        .accessibilityIdentifier("button-url") }
                    .padding(.horizontal, 16).frame(minHeight: 52)
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if let problem {
                Text(problem).font(Theme.secondary).foregroundStyle(Color.red).accessibilityIdentifier("button-error")
            } else if let shown = LinkInput.https(from: address) {
                Text("Opens \(shown)").font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(2).accessibilityIdentifier("button-shown")
            } else {
                Text("A button opens a web address.").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            }
        }
        .onAppear { focused = .title }
    }

    /// Lime green first, then five more; each label reads at 4.5:1 on its fill in light and dark.
    private var colours: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Colour").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 10) {
                ForEach(ButtonPalette.allCases) { palette in
                    Button { colour = palette } label: {
                        Circle().fill(palette.fill).frame(width: 36, height: 36)
                            .overlay(Circle().strokeBorder(Theme.text, lineWidth: colour == palette ? 3 : 0.5).opacity(colour == palette ? 1 : 0.3))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(palette.title).accessibilityAddTraits(colour == palette ? .isSelected : []).accessibilityIdentifier("button-colour-\(palette.rawValue)")
                }
            }
        }
    }

    // MARK: Doing

    private var customValid: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && LinkInput.https(from: address) != nil }

    private func choose(_ preset: Preset) {
        if captioned { caption = ""; step = .caption(preset) } else { insert(preset.label, preset.address, caption: "") }
    }

    private func addCustom() {
        guard let shown = LinkInput.https(from: address) else { problem = "That doesn\u{2019}t look like a web address."; return }
        address = shown
        insert(title, shown, caption: "")
    }

    private func insert(_ text: String, _ target: String, caption: String) {
        if let message = composer.applyButton(title: text, address: target, caption: caption, colour: colour.rawValue) { problem = message } else { dismiss() }
    }
}
