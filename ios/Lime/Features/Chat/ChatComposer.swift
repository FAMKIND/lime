import SwiftUI

/// The composer (design 04): the text above, and under it `+`, emoji and Aa on the left, mic or send on
/// the right. Select text, or tap Aa, and the formatting toolbar appears above the keyboard. The chat and
/// a thread both use it; `onSend` gets the message as Markdown.
struct ChatComposer: View {
    @Environment(ConversationStore.self) private var store
    @Bindable var model: RichComposerModel
    let onSend: (String) -> Void
    @State private var pickingEmoji = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RichComposerField(model: model)
                    .onAppear { model.hasText = false }
                if !model.hasText {
                    Text("Send message…").font(Theme.body).foregroundStyle(Theme.textSecondary)
                        .padding(.leading, 4).padding(.top, 8).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            HStack(spacing: 2) {
                button("plus", label: "Add attachment", id: "composer-plus") { store.comingSoon("Attachments") }
                button("face.smiling", label: "Emoji", id: "composer-emoji") { pickingEmoji = true }
                Button { model.toggleToolbar() } label: {
                    Text("Aa").font(.system(size: 17, weight: .medium)).foregroundStyle(model.toolbarVisible ? Theme.accentInk : Theme.text)
                        .frame(width: 44, height: 40)
                        .background(model.toolbarVisible ? Theme.accent : Color.clear, in: Capsule())
                }
                .accessibilityLabel("Formatting").accessibilityIdentifier("composer-aa")
                .accessibilityAddTraits(model.toolbarVisible ? [.isSelected] : [])
                Spacer(minLength: 0)
                if model.canSend {
                    Button { send() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.primaryInk)
                            .frame(width: 36, height: 36)
                            .background(Theme.primary, in: Circle())
                            .frame(width: 44, height: 40)
                    }
                    .accessibilityLabel("Send")
                    .accessibilityIdentifier("send-button")
                } else {
                    button("mic", label: "Voice message", id: "composer-mic") { store.comingSoon("Voice messages") }
                }
            }
        }
        .padding(.horizontal, 12).padding(.top, 2).padding(.bottom, 4)
        .limeGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .overlay { EmojiKeyboardField(isActive: $pickingEmoji) { model.insertEmoji($0) }.frame(width: 1, height: 1).opacity(0.01) }
        .sheet(item: $model.linkRequest) { request in LinkSheet(request: request, composer: model) }
    }

    private func button(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(Theme.text).frame(width: 44, height: 40)
        }
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }

    /// Sends what is written, as Markdown (LimeCore writes it the one way), and empties the composer.
    private func send() {
        let markdown = model.markdown()
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSend(markdown)
        model.clear()
    }
}

/// Opens links from the messages inside it: a tapped link shows pressed for a moment, an https link opens
/// at once, any other (http, mailto) asks first.
struct LinkOpening: ViewModifier {
    @State private var pending: URL?
    @State private var pressed: URL?

    func body(content: Content) -> some View {
        content
            .environment(\.pressedLink, pressed)
            .environment(\.openURL, OpenURLAction { url in
                pressed = url
                Task { try? await Task.sleep(for: .milliseconds(350)); if pressed == url { pressed = nil } }
                if MessageRender.opensWithoutAsking(url) { return .systemAction }
                pending = url
                return .handled
            })
            .confirmationDialog("Open this link?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible, presenting: pending) { url in
                Button("Open \(url.scheme == "mailto" ? "mail" : "link")") { UIApplication.shared.open(url) }
                    .accessibilityIdentifier("link-open")
                Button("Cancel", role: .cancel) {}.accessibilityIdentifier("link-dialog-cancel")
            } message: { url in
                Text(url.absoluteString)
            }
    }
}

extension View {
    func linkOpening() -> some View { modifier(LinkOpening()) }
}

/// "3 replies · Last reply 8:20 AM" with up to three replier avatars, under a message that has a thread.
struct ThreadSummaryRow: View {
    let messageID: String
    let thread: ThreadInfo
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                HStack(spacing: -6) {
                    ForEach(thread.repliers) { person in
                        AvatarView(person: person, size: 22)
                            .overlay(Circle().strokeBorder(Theme.canvas, lineWidth: 2))
                    }
                }
                Text(thread.summaryText)
                    .font(Theme.caption.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.75)
                if thread.unread > 0 {
                    // New replies: an accent dot (the count is in the accessibility label).
                    Circle().fill(Theme.accent).frame(width: 9, height: 9)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.surface, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(thread.summaryText)\(thread.unread > 0 ? ", \(thread.unread) new" : "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("thread-summary-\(messageID)")
    }
}
