import Foundation
import SwiftUI

/// Group chats (LIME-97): making one, its details, adding, removing, renaming and leaving. Every change is
/// made on this phone first (it is a signed op in the core's log) and goes out with the next delivery.
extension ConversationStore {
    /// Makes a group of the chosen people (not counting you) and opens it. `nil` when it could not be made.
    func createGroup(name: String, emoji: String?, members: [String]) async -> Conversation.ID? {
        #if DEBUG
        if isDemo { let id = demoMakeGroup(name: name, emoji: emoji, memberIDs: members, owner: true); path.append(id); return id }
        #endif
        guard let core else { return nil }
        let id = try? await Task.detached(priority: .userInitiated) {
            try core.createGroup(name: name, emoji: emoji, members: members)
        }.value
        await reload()
        if let id { path.append(id) }
        Task { await deliverNow() }
        return id
    }

    /// The group's name, avatar, my role and the people in it.
    func groupDetails(_ id: Conversation.ID) async -> GroupDetails? {
        #if DEBUG
        if isDemo { return demoGroups[id]?.details(id, hasPhoto: AvatarCache.shared.image(for: id) != nil) }
        #endif
        guard let core else { return nil }
        return try? await Task.detached(priority: .userInitiated) { try core.groupDetails(conversationId: id) }.value
    }

    func addToGroup(_ id: Conversation.ID, users: [String]) async {
        #if DEBUG
        if isDemo { demoGroupAdd(id, users); return }
        #endif
        guard let core else { return }
        try? await Task.detached(priority: .userInitiated) { try core.addGroupMembers(conversationId: id, userIds: users) }.value
        await reload()
        Task { await deliverNow() }
    }

    func removeFromGroup(_ id: Conversation.ID, user: String) async {
        #if DEBUG
        if isDemo { demoGroupRemove(id, user); return }
        #endif
        guard let core else { return }
        try? await Task.detached(priority: .userInitiated) { try core.removeGroupMember(conversationId: id, userId: user) }.value
        await reload()
        Task { await deliverNow() }
    }

    /// `false` when the name is not allowed (empty, over 50 characters) or you may not rename.
    func renameGroup(_ id: Conversation.ID, to name: String) async -> Bool {
        #if DEBUG
        if isDemo { return demoGroupRename(id, name) }
        #endif
        guard let core else { return false }
        let renamed = (try? await Task.detached(priority: .userInitiated) { try core.renameGroup(conversationId: id, name: name) }.value) != nil
        await reload()
        Task { await deliverNow() }
        return renamed
    }

    func setGroupEmoji(_ id: Conversation.ID, _ emoji: String?) async {
        #if DEBUG
        if isDemo { demoGroups[id]?.emoji = emoji; if let i = conversations.firstIndex(where: { $0.id == id }) { conversations[i].emoji = emoji }; return }
        #endif
        guard let core else { return }
        try? await Task.detached(priority: .userInitiated) { try core.setGroupEmoji(conversationId: id, emoji: emoji) }.value
        await reload()
        Task { await deliverNow() }
    }

    /// Leaves the group: it disappears from Messages and nothing more is shown from it.
    func leaveGroup(_ id: Conversation.ID) async {
        #if DEBUG
        if isDemo { demoEnd(id, "left"); return }
        #endif
        guard let core else { return }
        try? await Task.detached(priority: .userInitiated) { try core.leaveGroup(conversationId: id) }.value
        await reload()
        Task { await deliverNow() }
    }
}

extension ConversationStore {
    /// The owner deletes the group for everyone: it becomes read-only for all of its members.
    func deleteGroup(_ id: Conversation.ID) async {
        #if DEBUG
        if isDemo { demoEnd(id, "deleted"); return }
        #endif
        guard let core else { return }
        try? await Task.detached(priority: .userInitiated) { try core.deleteGroup(conversationId: id) }.value
        await reload()
        Task { await deliverNow() }
    }

    /// Clears the messages from this phone only; in a group, I stay in it.
    func clearMessages(_ id: Conversation.ID) async {
        #if DEBUG
        if isDemo {
            if let i = conversations.firstIndex(where: { $0.id == id }) { conversations[i].messages.removeAll { !$0.isSystem }; conversations[i].latest = nil; conversations[i].unread = 0 }
            return
        }
        #endif
        guard let core else { return }
        try? await Task.detached(priority: .userInitiated) { try core.clearMessages(conversationId: id) }.value
        await reload()
    }
}

#if DEBUG
extension ConversationStore {
    /// The demo's version of a group ending ("left" or "deleted").
    func demoEnd(_ id: Conversation.ID, _ how: String) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[i].groupEnded = how
        conversations[i].myRole = how == "left" ? nil : conversations[i].myRole
        conversations[i].messages.append(Message(id: "sys-\(UUID().uuidString)", senderID: nil, text: how == "left" ? "You left the group" : "You deleted this group", date: Date(), state: .system))
    }
}
#endif

#if DEBUG
/// A group in the demo store (no core): what the details screen shows and the changes edit.
struct DemoGroup {
    var name: String
    var emoji: String?
    /// user id, name, role
    var people: [(id: String, name: String, role: String)]

    func details(_ conversationID: String, hasPhoto: Bool = false) -> GroupDetails {
        let mine = people.first { $0.id == "me" }?.role ?? "member"
        let manage = mine == "owner" || mine == "admin"
        let members = people.map { person in
            GroupMemberInfo(userId: person.id, name: person.id == "me" ? "You" : person.name, tone: UInt32(AvatarTone.tone(for: person.id)), role: person.role,
                            isMe: person.id == "me",
                            canRemove: person.id != "me" && person.role != "owner" && (mine == "owner" || (mine == "admin" && person.role == "member")),
                            label: nil)
        }
        return GroupDetails(conversationId: conversationID, name: name, emoji: emoji, hasPhoto: hasPhoto,
                            myRole: mine, members: members,
                            canRename: manage, canAdd: manage && people.count < 100, maxMembers: 100)
    }
}

extension ConversationStore {
    /// The demo's known teachers (accepted chats), so the pickers have people to show.
    func loadDemoTeachers() {
        for name in ["Ben Okafor", "Chloe Diaz", "Maya Singh", "Noah Bell", "Priya Nair", "Zoe Adler", "Éloïse Martin", "Lena Ito"] {
            let who = Person(id: name.lowercased().replacingOccurrences(of: " ", with: "."), name: name)
            if !conversations.contains(where: { $0.id == "dm:\(who.id)" }) {
                conversations.append(Conversation(id: "dm:\(who.id)", title: name, members: [who], messages: []))
            }
        }
    }

    @discardableResult
    func demoMakeGroup(name: String, emoji: String?, memberIDs: [String], owner: Bool) -> Conversation.ID {
        let id = "grp:demo\(demoGroups.count + 1)"
        let known = Dictionary(uniqueKeysWithValues: conversations.filter { $0.id.hasPrefix("dm:") }.compactMap { c in c.members.first.map { ($0.id, $0) } })
        var people: [(id: String, name: String, role: String)] = [("me", "You", owner ? "owner" : "member")]
        for user in memberIDs { people.append((user, known[user]?.name ?? user, "member")) }
        demoGroups[id] = DemoGroup(name: name, emoji: emoji, people: people)
        let others = people.filter { $0.id != "me" }.map { Person(id: $0.id, name: $0.name) }
        var conversation = Conversation(id: id, title: name, members: others, messages: [], isGroupChat: true, emoji: emoji)
        conversation.myRole = owner ? "owner" : "member"
        conversation.messages.append(Message(id: "sys-\(id)-1", senderID: nil, text: "You created the group “\(name)”", date: Date(), state: .system))
        conversations.insert(conversation, at: 0)
        return id
    }

    func demoAddMessages(to id: Conversation.ID, _ lines: [(String, String)]) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        for (offset, line) in lines.enumerated() {
            conversations[index].messages.append(Message(id: "g\(offset)-\(id)", senderID: line.0, text: line.1, date: Date().addingTimeInterval(Double(offset - lines.count) * 60), state: .received))
        }
    }

    private func demoSystem(_ id: Conversation.ID, _ text: String) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].messages.append(Message(id: "sys-\(UUID().uuidString)", senderID: nil, text: text, date: Date(), state: .system))
    }

    func demoGroupAdd(_ id: Conversation.ID, _ users: [String]) {
        guard var group = demoGroups[id], let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let known = Dictionary(uniqueKeysWithValues: conversations.filter { $0.id.hasPrefix("dm:") }.compactMap { c in c.members.first.map { ($0.id, $0) } })
        var names: [String] = []
        for user in users where !group.people.contains(where: { $0.id == user }) {
            let name = known[user]?.name ?? user
            group.people.append((user, name, "member"))
            conversations[index].members.append(Person(id: user, name: name))
            names.append(name)
        }
        demoGroups[id] = group
        if !names.isEmpty { demoSystem(id, "You added \(names.joined(separator: ", "))") }
    }

    func demoGroupRemove(_ id: Conversation.ID, _ user: String) {
        guard var group = demoGroups[id], let index = conversations.firstIndex(where: { $0.id == id }),
              let person = group.people.first(where: { $0.id == user }) else { return }
        group.people.removeAll { $0.id == user }
        demoGroups[id] = group
        conversations[index].members.removeAll { $0.id == user }
        demoSystem(id, "You removed \(person.name)")
    }

    func demoGroupRename(_ id: Conversation.ID, _ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 50, demoGroups[id] != nil, let index = conversations.firstIndex(where: { $0.id == id }) else { return false }
        demoGroups[id]?.name = trimmed
        conversations[index] = Conversation(id: id, title: trimmed, members: conversations[index].members, messages: conversations[index].messages,
                                            isPinned: conversations[index].isPinned, unread: conversations[index].unread, isGroupChat: true, emoji: conversations[index].emoji)
        demoSystem(id, "You renamed the group to “\(trimmed)”")
        return true
    }
}
#endif
