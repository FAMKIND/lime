import SwiftUI
import UIKit

/// The state of the message actions on one screen (a chat or a Replies screen): the menu that a long-press opens and what it leads to.
@MainActor
@Observable
final class MessageActionsState {
    var menu: Message?
    var editing: Message?
    var editText = ""
    var picking: Message?
    var reactors: Message?
    /// The messages being forwarded: the picker is open.
    var forwarding: [Message]?
    /// The messages a Delete is about (one from the menu, or the selected ones).
    var deleting: [Message] = []
}

/// The long-press menu in this order: an emoji row (six quick ones and "+"), Reply, Forward, Edit (my own, for a day), Copy, Select, Delete.
/// Also the sheets it leads to: Edit, the emoji picker, who reacted, and the Delete confirmation.
struct MessageActionsHost: ViewModifier {
    let state: MessageActionsState
    let conversationID: Conversation.ID
    /// In a Replies screen there is no "Reply" (you are already in the thread).
    let inThread: Bool
    @Binding var selection: Set<Message.ID>?
    var onReply: (Message) -> Void = { _ in }
    @Environment(ConversationStore.self) private var store

    func body(content: Content) -> some View {
        content
            .overlay {
                if let message = state.menu { menu(for: message) }
            }
            .animation(.easeOut(duration: 0.15), value: state.menu?.id)
            .sheet(item: Binding(get: { state.editing }, set: { state.editing = $0 })) { message in
                EditMessageSheet(text: Binding(get: { state.editText }, set: { state.editText = $0 })) { saved in
                    state.editing = nil
                    if saved { Task { _ = await store.editMessage(message, to: state.editText, in: conversationID) } }
                }
            }
            .sheet(item: Binding(get: { state.picking }, set: { state.picking = $0 })) { message in
                EmojiPickerSheet { emoji in
                    state.picking = nil
                    if let emoji { Task { await store.toggleReaction(emoji, on: message, in: conversationID) } }
                }
            }
            .sheet(isPresented: Binding(get: { state.reactors != nil }, set: { if !$0 { state.reactors = nil } })) {
                if let message = state.reactors {
                    // Read the live message, so the list is current if someone reacts while it is open.
                    ReactorsSheet(chips: liveChips(message), mineToggle: { emoji in
                        state.reactors = nil
                        Task { await store.toggleReaction(emoji, on: message, in: conversationID) }
                    }) { state.reactors = nil }
                }
            }
            .sheet(isPresented: Binding(get: { state.forwarding != nil }, set: { if !$0 { state.forwarding = nil } })) {
                if let messages = state.forwarding {
                    ForwardSheet(messageIDs: messages.map(\.id)) { sent in
                        state.forwarding = nil
                        if sent { selection = nil }
                    }
                }
            }
            .confirmationDialog(deleteTitle, isPresented: Binding(get: { !state.deleting.isEmpty }, set: { if !$0 { state.deleting = [] } }), titleVisibility: .visible) {
                Button("Delete for me", role: .destructive) { delete(everyone: false) }
                    .accessibilityIdentifier("delete-for-me")
                if everyoneAllowed {
                    Button("Delete for everyone", role: .destructive) { delete(everyone: true) }
                        .accessibilityIdentifier("delete-for-everyone")
                }
                Button("Cancel", role: .cancel) { state.deleting = [] }
            } message: {
                Text(everyoneAllowed ? "“Delete for everyone” replaces \(state.deleting.count == 1 ? "it" : "them") with “This message was deleted” on their phones. Lime can't guarantee it's gone if someone already saw or saved it."
                                     : "This removes \(state.deleting.count == 1 ? "it" : "them") from this phone only.")
            }
    }

    /// The message's reactions as they are now.
    private func liveChips(_ message: Message) -> [ReactionChip] {
        let live = store.conversation(conversationID)?.messages.first { $0.id == message.id }
            ?? store.threads.values.lazy.flatMap { $0 }.first { $0.id == message.id }
        return (live ?? message).reactions
    }

    /// A single picture with no words: Copy puts the picture on the pasteboard.
    private func copyableImage(_ message: Message) -> AttachmentItem? {
        guard message.text.isEmpty, message.attachments.count == 1, let only = message.attachments.first, only.kind == .image else { return nil }
        return only
    }

    private var everyoneAllowed: Bool { !state.deleting.isEmpty && state.deleting.allSatisfy { $0.canDeleteForEveryone() } }
    private var deleteTitle: String { state.deleting.count > 1 ? "Delete \(state.deleting.count) messages?" : "Delete message?" }

    private func delete(everyone: Bool) {
        let ids = state.deleting.map(\.id)
        state.deleting = []
        selection = nil
        Task { await store.deleteMessages(ids, for: everyone, in: conversationID) }
    }

    // MARK: The menu

    private func menu(for message: Message) -> some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { state.menu = nil }
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                if !message.deleted && message.state != .sending && message.state != .failed {
                    HStack(spacing: 4) {
                        ForEach(ConversationStore.quickReactions, id: \.self) { emoji in
                            let mine = message.reactions.first { $0.emoji == emoji }?.mine ?? false
                            Button {
                                state.menu = nil
                                Task { await store.toggleReaction(emoji, on: message, in: conversationID) }
                            } label: {
                                Text(emoji).font(.system(size: 28)).frame(width: 44, height: 44)
                                    .background(mine ? Theme.pressed : Color.clear, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("React with \(emoji)")
                            .accessibilityIdentifier("react-\(emoji)")
                        }
                        Button {
                            state.menu = nil
                            state.picking = message
                        } label: {
                            Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.text)
                                .frame(width: 36, height: 36).background(Theme.surface, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("More emoji").accessibilityIdentifier("react-more")
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.canvas, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("reaction-row")
                }
                VStack(spacing: 0) {
                    if !message.deleted, !inThread, message.state != .sending, message.state != .failed {
                        row("arrowshape.turn.up.left", "Reply", id: "reply-in-thread") { state.menu = nil; onReply(message) }
                    }
                    if !message.deleted {
                        row("arrowshape.turn.up.right", "Forward", id: "action-forward") { state.menu = nil; state.forwarding = [message] }
                    }
                    // On a photo, album, video, voice message or file, Edit changes the caption only (so it needs one).
                    if message.canEdit(), !message.deleted, message.attachments.isEmpty || !message.text.isEmpty {
                        row("pencil", "Edit", id: "action-edit") {
                            state.menu = nil
                            state.editText = message.text
                            state.editing = message
                        }
                    }
                    // Copy: the words (a caption included), or the picture when it is a single picture without words.
                    if !message.deleted, !message.text.isEmpty || copyableImage(message) != nil {
                        row("doc.on.doc", "Copy", id: "action-copy") {
                            state.menu = nil
                            if let single = copyableImage(message) { Task { if let image = await store.image(for: single) { UIPasteboard.general.image = image } } }
                            else { store.copyToPasteboard(message) }
                        }
                    }
                    row("checkmark.circle", "Select", id: "action-select") { state.menu = nil; selection = [message.id] }
                    row("trash", "Delete", id: "action-delete", destructive: true, last: true) { state.menu = nil; state.deleting = [message] }
                }
                .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
            }
            .frame(maxWidth: 300)
            .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("message-actions")
        }
    }

    private func row(_ symbol: String, _ title: String, id: String, destructive: Bool = false, last: Bool = false, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    Text(title).font(Theme.body)
                    Spacer()
                    Image(systemName: symbol).font(.system(size: 17))
                }
                .foregroundStyle(destructive ? Color.red : Theme.text)
                .padding(.horizontal, 16).frame(minHeight: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityIdentifier(id)
            if !last { Divider().overlay(Theme.hairline) }
        }
    }
}

extension View {
    func messageActions(_ state: MessageActionsState, conversationID: Conversation.ID, inThread: Bool = false, selection: Binding<Set<Message.ID>?>,
                        onReply: @escaping (Message) -> Void = { _ in }) -> some View {
        modifier(MessageActionsHost(state: state, conversationID: conversationID, inThread: inThread, selection: selection, onReply: onReply))
    }
}

// MARK: Sheets

/// Edit: the message's text (as it was written, with its formatting marks), Save and Cancel.
struct EditMessageSheet: View {
    @Binding var text: String
    var finish: (_ saved: Bool) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button("Cancel") { finish(false) }.foregroundStyle(Theme.text).accessibilityIdentifier("edit-cancel")
                Spacer()
                Text("Edit message").font(Theme.title).foregroundStyle(Theme.text)
                Spacer()
                Button("Save") { finish(true) }.font(Theme.title).foregroundStyle(Theme.text)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("edit-save")
            }
            TextEditor(text: $text)
                .font(Theme.body).scrollContentBackground(.hidden).focused($focused)
                .padding(10).frame(minHeight: 140)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityIdentifier("edit-field")
            Text("Everyone in the chat sees the new text, marked Edited. Only the latest text is kept. You can edit for 24 hours.")
                .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Theme.canvas.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .onAppear { focused = true }
    }
}

/// "+": any emoji. A grid of common ones, and "Search all emoji" brings up the system emoji keyboard (which has its own search).
struct EmojiPickerSheet: View {
    var finish: (_ emoji: String?) -> Void
    @State private var systemKeyboard = false

    private static let common = ["😀", "😁", "😂", "🤣", "😊", "😍", "😘", "😎", "🤔", "😅", "😭", "😡", "😮", "😢", "🥳", "🙌", "👏", "🙏", "💪", "👍", "👎", "👌", "✌️", "🤝",
                                 "❤️", "💚", "💙", "💛", "💜", "🧡", "🔥", "✨", "🎉", "🎓", "🍎", "📚", "✏️", "🏫", "🚌", "☕️", "🍕", "🌟", "💯", "✅", "❌", "❓", "👀", "🙈"]

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button("Cancel") { finish(nil) }.foregroundStyle(Theme.text).accessibilityIdentifier("emoji-cancel")
                Spacer()
                Text("React").font(Theme.title).foregroundStyle(Theme.text)
                Spacer()
                Color.clear.frame(width: 60, height: 1)
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 6) {
                    ForEach(Self.common, id: \.self) { emoji in
                        Button { finish(emoji) } label: { Text(emoji).font(.system(size: 28)).frame(height: 44) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(emoji).accessibilityIdentifier("pick-\(emoji)")
                    }
                }
            }
            Button { systemKeyboard = true } label: {
                Label("Search all emoji", systemImage: "magnifyingglass").font(Theme.body.weight(.semibold)).foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 48).background(Theme.surface, in: Capsule())
            }
            .accessibilityIdentifier("emoji-search-all")
            EmojiKeyboardField(isActive: $systemKeyboard) { finish($0) }.frame(width: 1, height: 1).opacity(0.01)
        }
        .padding(20)
        .background(Theme.canvas.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}

/// Every reaction on a message with who reacted; tap your own to remove it.
struct ReactorsSheet: View {
    let chips: [ReactionChip]
    var mineToggle: (String) -> Void
    var finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Reactions").font(Theme.title).foregroundStyle(Theme.text)
                Spacer()
                Button("Done") { finish() }.foregroundStyle(Theme.text).accessibilityIdentifier("reactors-done")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(chips) { chip in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(chip.emoji).font(.system(size: 30))
                                Text("\(chip.count)").font(Theme.title).foregroundStyle(Theme.textSecondary)
                            }
                            .accessibilityIdentifier("reaction-row-\(chip.emoji)")
                            ForEach(chip.people, id: \.self) { name in
                                if chip.mine && name == "You" {
                                    Button { mineToggle(chip.emoji) } label: {
                                        HStack {
                                            Text(name).font(Theme.body).foregroundStyle(Theme.text)
                                            Spacer()
                                            Text("Tap to remove").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                                        }
                                        .frame(minHeight: 36)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("reactor-remove-\(chip.emoji)")
                                } else {
                                    Text(name).font(Theme.body).foregroundStyle(Theme.text).frame(minHeight: 36, alignment: .leading)
                                        .accessibilityIdentifier("reactor-\(name)")
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Theme.canvas.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}

// MARK: Select mode

/// The bottom bar of Select mode: trash on the left, "N Selected" in the middle, Forward on the right.
struct SelectionBar: View {
    let count: Int
    var onDelete: () -> Void
    var onForward: () -> Void

    var body: some View {
        HStack {
            Button(action: onDelete) {
                Image(systemName: "trash").font(.system(size: 20)).foregroundStyle(count == 0 ? Theme.textSecondary : Color.red).frame(width: 48, height: 48)
            }
            .disabled(count == 0)
            .accessibilityLabel("Delete").accessibilityIdentifier("select-trash")
            Spacer()
            Text("\(count) Selected").font(Theme.title).foregroundStyle(Theme.text).accessibilityIdentifier("select-count")
            Spacer()
            Button(action: onForward) {
                Image(systemName: "arrowshape.turn.up.right").font(.system(size: 20)).foregroundStyle(count == 0 ? Theme.textSecondary : Theme.text).frame(width: 48, height: 48)
            }
            .disabled(count == 0)
            .accessibilityLabel("Forward").accessibilityIdentifier("select-forward")
        }
        .padding(.horizontal, 14)
        .limeGlass(in: Capsule())
        .padding(.horizontal, 12).padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("select-bar")
    }
}

// MARK: Forward

/// Forward: pick up to five chats or groups (checkmarks, with the chosen ones as chips) and send. Each forward is a new message
/// labelled "Forwarded"; it never names who first wrote it.
struct ForwardSheet: View {
    let messageIDs: [Message.ID]
    var finish: (_ sent: Bool) -> Void
    @Environment(ConversationStore.self) private var store
    @State private var query = ""
    @State private var chosen: [Conversation.ID] = []
    @State private var sending = false
    @FocusState private var focused: Bool

    private var chats: [Conversation] {
        let all = store.forwardTargets
        let wanted = query.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return all }
        return all.filter { SearchText.matches(([$0.title] + $0.members.map(\.name)).joined(separator: " "), query: wanted) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { finish(false) }.foregroundStyle(Theme.text).accessibilityIdentifier("forward-cancel")
                Spacer()
                Text("Forward").font(Theme.title).foregroundStyle(Theme.text)
                Spacer()
                Button("Send") { send() }
                    .font(Theme.title).foregroundStyle(chosen.isEmpty ? Theme.textSecondary : Theme.text)
                    .disabled(chosen.isEmpty || sending)
                    .accessibilityIdentifier("forward-send")
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 10)
            if !chosen.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chosen, id: \.self) { id in
                            if let chat = store.conversation(id) {
                                Button { toggle(id) } label: {
                                    HStack(spacing: 4) {
                                        Text(chat.title).font(Theme.secondary).lineLimit(1)
                                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                                    }
                                    .foregroundStyle(Theme.text).padding(.horizontal, 10).frame(minHeight: 30)
                                    .background(Theme.pressed, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(chat.title)").accessibilityIdentifier("forward-chip-\(id)")
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 8)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(chats) { chat in
                        let on = chosen.contains(chat.id)
                        Button { toggle(chat.id) } label: {
                            HStack(spacing: 14) {
                                ConversationAvatar(conversation: chat, size: 44)
                                Text(chat.title).font(Theme.body).foregroundStyle(Theme.text).lineLimit(1)
                                Spacer(minLength: 8)
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 24)).foregroundStyle(on ? Theme.text : Theme.textSecondary.opacity(0.7))
                            }
                            .padding(.horizontal, 20).frame(minHeight: 60)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(chat.title)
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                        .accessibilityIdentifier("forward-row-\(chat.id)")
                    }
                    if chosen.count >= ConversationStore.maxForwardChats {
                        Text("You can forward to up to \(ConversationStore.maxForwardChats) chats at a time.")
                            .font(Theme.secondary).foregroundStyle(Theme.textSecondary).padding(20)
                            .accessibilityIdentifier("forward-limit")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField("Search chats", text: $query).font(Theme.body).focused($focused).selectionTint()
                    .accessibilityIdentifier("forward-search")
            }
            .padding(.horizontal, 16).frame(minHeight: 48)
            .limeGlass(in: Capsule())
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .presentationDetents([.large])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("forward-sheet")
    }

    private func toggle(_ id: Conversation.ID) {
        if let at = chosen.firstIndex(of: id) { chosen.remove(at: at) }
        else if chosen.count < ConversationStore.maxForwardChats { chosen.append(id) }
    }

    private func send() {
        sending = true
        let targets = chosen
        Task {
            let done = await store.forward(messageIDs, to: targets)
            sending = false
            if done { store.showBanner(targets.count == 1 ? "Forwarded" : "Forwarded to \(targets.count) chats") }
            finish(done)
        }
    }
}
