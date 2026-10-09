import SwiftUI

/// The formatting toolbar that sits above the keyboard (Notion and Gmail's pattern): a floating glass
/// capsule that scrolls sideways when the items do not fit, and a separate round ✕ at the right end.
/// Items: B, I, U, S, link, code, bulleted list, numbered list. Each shows whether it is on for the
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

    private func symbol(_ name: String, on: Bool, id: String, label: String, action: @escaping () -> Void) -> some View {
        item(on: on, id: id, label: label, action: action) {
            Image(systemName: name).font(.system(size: 17)).foregroundStyle(Theme.text)
        }
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
                Text("Only http, https and mailto links are supported.").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
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
