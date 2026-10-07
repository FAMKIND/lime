import SwiftUI

/// A thread (design 04): the message it hangs from at the top, then its replies, then its own composer
/// (with formatting). New replies arrive live. Replies are not in the main chat.
struct ThreadView: View {
    let target: ThreadTarget
    @Environment(ConversationStore.self) private var store
    @State private var composerModel = RichComposerModel()
    @State private var highlightedID: String?
    @State private var scrollRequest: UUID?

    private var messages: [Message] { store.threads[target.rootID] ?? [] }
    private var conversation: Conversation? { store.conversation(target.conversationID) }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let root = messages.first {
                            bubble(root, isRoot: true)
                            HStack(spacing: 10) {
                                Text(replyCountText).font(Theme.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                                    .accessibilityIdentifier("thread-count")
                                Rectangle().fill(Theme.hairline).frame(height: 0.5)
                            }
                            .padding(.vertical, 10)
                            .accessibilityElement(children: .combine)
                            ForEach(messages.dropFirst()) { reply in bubble(reply, isRoot: false).id(reply.id) }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
                }
                .accessibilityIdentifier("thread-scroll")
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                .linkOpening()
                .onChange(of: messages.count) {
                    withAnimation { proxy.scrollTo("bottom") }
                    Task { await store.markThreadRead(target.rootID, in: target.conversationID) }
                }
                .onChange(of: scrollRequest) { _, _ in
                    guard let id = target.focusMessageID else { return }
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            ChatComposer(model: composerModel) { markdown in
                Task { await store.sendReply(markdown, root: target.rootID, in: target.conversationID) }
            }
        }
        .navigationTitle("Thread")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            await store.openThread(target.rootID)
            await store.markThreadRead(target.rootID, in: target.conversationID)
            // Opened from a search hit: land on that reply and outline it for a moment.
            if let focus = target.focusMessageID {
                try? await Task.sleep(for: .milliseconds(300))
                highlightedID = focus
                scrollRequest = UUID()
                try? await Task.sleep(for: .seconds(4))
                if highlightedID == focus { withAnimation { highlightedID = nil } }
            }
        }
        .onDisappear { store.closeThread(target.rootID) }
    }

    private var replyCountText: String {
        let n = max(messages.count - 1, 0)
        return n == 0 ? "No replies yet" : "\(n) \(n == 1 ? "reply" : "replies")"
    }

    private func bubble(_ message: Message, isRoot: Bool) -> some View {
        MessageBubble(message: message,
                      sender: conversation.flatMap { store.person(message.senderID, in: $0) },
                      showAvatar: !message.isOwn,
                      showName: false,
                      showState: message.isOwn && message.state != .sent,
                      highlighted: highlightedID == message.id,
                      onRetry: { Task { await store.resend(message.id) } })
            .padding(.bottom, 8)
    }
}
