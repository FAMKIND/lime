import SwiftUI

struct MessagesView: View {
    @Environment(ConversationStore.self) private var store
    @State private var showAbout = false

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                nativeBody
            } else {
                legacyBody
            }
        }
        .sheet(isPresented: $showAbout) { AboutView() }
    }

    // MARK: iOS 26+: the system toolbar and scroll edge effect (as in Apple Messages)

    @available(iOS 26, *)
    private var nativeBody: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            list(top: 8, bottom: 24)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
        .safeAreaBar(edge: .bottom) { DockBar().padding(.bottom, 8) }
        .overlay(alignment: .bottomTrailing) { newMessageButton.padding(.trailing, 20).padding(.bottom, 92) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { store.comingSoon() } label: {
                    Image("LimeLogo").renderingMode(.original).resizable().scaledToFit()
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.6) { showAbout = true }
                }
                .accessibilityLabel("Lime menu")
                .accessibilityHint("Press and hold for About Lime")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { store.comingSoon("Search") } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Search")
                Button { store.comingSoon("Your profile") } label: { AvatarView(person: SampleData.me, size: 30) }
                    .accessibilityLabel("Your profile")
            }
        }
    }

    // MARK: iOS 17-25: custom glass pills and a subtle top veil

    private var legacyBody: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            list(top: 76, bottom: 170)
        }
        .overlay(alignment: .top) { TopFade() }
        .overlay(alignment: .top) { TopControls(onAbout: { showAbout = true }) }
        .overlay(alignment: .bottomTrailing) { newMessageButton.padding(.trailing, 20).padding(.bottom, 92) }
        .overlay(alignment: .bottom) { DockBar().padding(.bottom, 8) }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Shared

    private func list(top: CGFloat, bottom: CGFloat) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.conversations) { conversation in
                    NavigationLink(value: conversation.id) {
                        ConversationRow(conversation: conversation)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("conversation-row-\(conversation.id)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, top)
            .padding(.bottom, bottom)
        }
        .accessibilityIdentifier("messages-list")
    }

    private var newMessageButton: some View {
        Button { store.comingSoon("New message") } label: {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Theme.accentInk)
                .frame(width: 64, height: 64)
                .background(Theme.accent, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
        .accessibilityLabel("New message")
    }
}

private struct TopControls: View {
    @Environment(ConversationStore.self) private var store
    let onAbout: () -> Void

    var body: some View {
        HStack {
            Button { store.comingSoon() } label: {
                Image("LimeLogo")
                    .resizable().scaledToFit()
                    .frame(width: 34, height: 34)
                    .frame(width: 48, height: 48)
                    .limeGlass()
            }
            .accessibilityLabel("Lime menu")
            .accessibilityHint("Press and hold for About Lime")
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in onAbout() })
            Spacer()
            HStack(spacing: 12) {
                Button { store.comingSoon("Search") } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Theme.text)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Search")
                Button { store.comingSoon("Your profile") } label: {
                    AvatarView(person: SampleData.me, size: 36)
                }
                .accessibilityLabel("Your profile")
            }
            .padding(.horizontal, 8).padding(.vertical, 2)
            .limeGlass()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 52

    private var preview: String {
        guard let last = conversation.lastMessage else { return "" }
        if conversation.isGroup, let sender = conversation.members.first(where: { $0.id == last.senderID }) {
            return "\(sender.name.split(separator: " ").first ?? ""): \(last.text)"
        }
        return last.text
    }

    private var time: String { MessageFormat.listTime(conversation.lastMessage?.date) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ConversationAvatar(conversation: conversation, size: avatarSize)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(conversation.title)
                        .font(Theme.title)
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                    if conversation.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 4)
                    Text(time)
                        .font(Theme.secondary)
                        .foregroundStyle(Theme.textSecondary)
                }
                HStack(alignment: .top, spacing: 8) {
                    Text(preview)
                        .font(Theme.secondary)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if conversation.unread > 0 {
                        Text("\(conversation.unread)")
                            .font(Theme.caption.weight(.semibold))
                            .foregroundStyle(Theme.accentInk)
                            .frame(minWidth: 22)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.accent, in: Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(conversation.title)\(conversation.isPinned ? ", pinned" : ""), \(preview), \(time)\(conversation.unread > 0 ? ", \(conversation.unread) unread" : "")")
        .accessibilityAddTraits(.isButton)
    }
}
