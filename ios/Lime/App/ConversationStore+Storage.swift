import Foundation
import SwiftUI

/// Storage (LIME-107): what media take on this phone, removing them, "Keep media", and the low-storage rule.
extension ConversationStore {
    struct ChatStorage: Identifiable, Equatable {
        let id: Conversation.ID
        let title: String
        let bytes: Int64
        let files: Int
    }

    struct StorageSummary: Equatable {
        var databaseBytes: Int64 = 0
        var mediaBytes: Int64 = 0
        var chats: [ChatStorage] = []
    }

    struct MediaFile: Identifiable, Equatable {
        let messageID: String
        let attachmentID: String
        let name: String
        let mime: String
        let size: Int64
        let date: Date
        var id: String { messageID + "/" + attachmentID }
    }

    func storageSummary() async -> StorageSummary {
        #if DEBUG
        if isDemo { return demoStorageSummary() }
        #endif
        guard let core else { return StorageSummary() }
        guard let usage = try? await Task.detached(priority: .userInitiated, operation: { try core.storageUsage() }).value else { return StorageSummary() }
        let chats = usage.chats.map { chat in
            ChatStorage(id: chat.conversationId, title: conversation(chat.conversationId)?.title ?? "Chat", bytes: Int64(chat.bytes), files: Int(chat.files))
        }
        return StorageSummary(databaseBytes: Int64(usage.databaseBytes), mediaBytes: Int64(usage.mediaBytes), chats: chats)
    }

    func mediaFiles(in id: Conversation.ID) async -> [MediaFile] {
        #if DEBUG
        if isDemo { return demoMediaFiles(in: id) }
        #endif
        guard let core else { return [] }
        let entries = (try? await Task.detached(priority: .userInitiated) { try core.listMedia(conversationId: id) }.value) ?? []
        return entries.map { MediaFile(messageID: $0.messageId, attachmentID: $0.attachmentId, name: $0.name, mime: $0.mime, size: Int64($0.size), date: Date(timeIntervalSince1970: Double($0.sentAt) / 1000)) }
    }

    /// Removes files from this phone; the messages stay and read "Media removed". Gives the space back to the phone when it can.
    func removeMedia(_ files: [MediaFile]) async {
        #if DEBUG
        if isDemo { demoRemoveMedia(files); return }
        #endif
        guard let core else { return }
        let refs = files.map { MediaRef(messageId: $0.messageID, attachmentId: $0.attachmentID) }
        _ = try? await Task.detached(priority: .userInitiated) { try core.removeMedia(items: refs) }.value
        for file in files { AttachmentImages.shared.set(nil, file.attachmentID) }
        await reload()
        await compactIfRoom()
    }

    /// "Keep media": removes the files of messages older than the setting. Messages stay.
    func applyKeepMedia() async {
        guard let days = MediaSettings.keep.days else { return }
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core else { return }
        let removed = (try? await Task.detached(priority: .utility) { try core.removeMediaOlderThan(days: days) }.value) ?? 0
        if removed > 0 {
            await reload()
            await compactIfRoom()
        }
    }

    /// Shrinks the database file after media were removed, if there is room to do it safely.
    private func compactIfRoom() async {
        guard let core else { return }
        let size = (try? await Task.detached(priority: .utility) { try core.storageUsage().databaseBytes }.value) ?? 0
        guard StorageGuard.shared.allows(Int64(size)) else { return }
        try? await Task.detached(priority: .utility) { try core.compactStorage() }.value
    }

    /// Refreshes "Your iPhone is almost full".
    func refreshStorageState() {
        lowStorage = StorageGuard.shared.isLow
    }

    // MARK: Whether a file can still be had

    /// Until when the server still has an attachment: `.some(date)`, or `.some(nil)` when it is gone; `nil` while unknown (offline).
    func availableUntil(_ item: AttachmentItem) async -> Date?? {
        if item.downloaded { return .some(nil) }
        if let known = availability[item.id] { return known }
        #if DEBUG
        if isDemo {
            let until: Date? = item.name.hasPrefix("gone") ? nil : Date().addingTimeInterval(20 * 86_400)
            availability[item.id] = .some(until)
            return .some(until)
        }
        #endif
        guard let core, let link, let token = try? await link.token() else { return nil }
        let id = item.id
        // Three outcomes: a date, gone (the server answered "no such file"), or unknown (no network).
        let outcome: Result<Int64?, Error> = await Task.detached(priority: .utility) {
            Result { try core.attachmentAvailableUntil(transport: link.transport, authToken: token, attachmentId: id) }
        }.value
        guard case .success(let millis) = outcome else { return nil }
        let value: Date?? = .some(millis.map { Date(timeIntervalSince1970: Double($0) / 1000) })
        availability[item.id] = value
        return value
    }

    /// What a not-yet-downloaded file says about itself for VoiceOver and tests: "tap to download, 2.4 MB, available until Oct 30".
    func downloadPhrase(_ item: AttachmentItem) -> String? {
        if item.removed { return "Media removed" }
        guard !item.downloaded else { return nil }
        var parts = [AttachmentFormat.size(item.size)]
        if let known = availability[item.id], let answered = known {   // asked, and the server answered
            if let date = answered { parts.append("available until \(date.formatted(.dateTime.month(.abbreviated).day()))") }
            else { parts.append("no longer available") }
        }
        return parts.joined(separator: ", ")
    }

    /// Whether every file of these messages can still be forwarded: held on this phone, or still on the server.
    func canForward(_ messages: [Message]) async -> Bool {
        for item in messages.flatMap(\.attachments) where !item.downloaded {
            if item.removed { return false }
            if let known = await availableUntil(item), known == nil { return false }
        }
        return true
    }
}

#if DEBUG
extension ConversationStore {
    func demoStorageSummary() -> StorageSummary {
        var chats: [ChatStorage] = []
        for c in conversations {
            let held = c.messages.flatMap(\.attachments).filter { $0.downloaded && !$0.removed }
            let bytes = held.reduce(Int64(0)) { total, item in total + (demoAttachmentData[item.id].map { Int64($0.count) } ?? item.size) }
            if bytes > 0 { chats.append(ChatStorage(id: c.id, title: c.title, bytes: bytes, files: held.count)) }
        }
        chats.sort { $0.bytes > $1.bytes }
        return StorageSummary(databaseBytes: 2_400_000, mediaBytes: chats.reduce(0) { $0 + $1.bytes }, chats: chats)
    }

    func demoMediaFiles(in id: Conversation.ID) -> [MediaFile] {
        guard let c = conversation(id) else { return [] }
        return c.messages.flatMap { m in m.attachments.filter { $0.downloaded && !$0.removed }.map { MediaFile(messageID: m.id, attachmentID: $0.id, name: $0.name.isEmpty ? "Attachment" : $0.name, mime: $0.mime, size: demoAttachmentData[$0.id].map { Int64($0.count) } ?? $0.size, date: m.date) } }
            .sorted { $0.size > $1.size }
    }

    func demoRemoveMedia(_ files: [MediaFile]) {
        for file in files {
            for c in conversations.indices {
                for m in conversations[c].messages.indices where conversations[c].messages[m].id == file.messageID {
                    for a in conversations[c].messages[m].attachments.indices where conversations[c].messages[m].attachments[a].id == file.attachmentID {
                        conversations[c].messages[m].attachments[a].downloaded = false
                        conversations[c].messages[m].attachments[a].removed = true
                    }
                }
            }
            demoAttachmentData[file.attachmentID] = nil
            AttachmentImages.shared.set(nil, file.attachmentID)
        }
    }
}
#endif
