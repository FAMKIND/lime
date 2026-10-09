import Foundation
import SwiftUI
import UIKit

/// Decoded pictures of attachments, so a chat scrolls without reading and decrypting them again.
@MainActor
final class AttachmentImages {
    static let shared = AttachmentImages()
    private let cache = NSCache<NSString, UIImage>()
    init() { cache.countLimit = 80 }
    func image(_ id: String) -> UIImage? { cache.object(forKey: id as NSString) }
    func set(_ image: UIImage?, _ id: String) { if let image { cache.setObject(image, forKey: id as NSString) } else { cache.removeObject(forKey: id as NSString) } }
    func reset() { cache.removeAllObjects() }
}

/// Encrypted attachments (LIME-98c): sending, downloading and opening photos and files.
extension ConversationStore {
    /// Sends photos or files with an optional caption. In a chat or a group.
    func sendAttachments(_ items: [OutgoingAttachment], caption: String, in id: Conversation.ID) {
        Task { await sendAttachmentsNow(items, caption: caption, in: id) }
    }

    func sendAttachmentsNow(_ items: [OutgoingAttachment], caption: String, in id: Conversation.ID) async {
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        #if DEBUG
        if isDemo { demoSendAttachments(items, caption: text, in: id); return }
        #endif
        guard let core, link != nil else { report(.offline); return }
        let item = try? await Task.detached(priority: .userInitiated) {
            try core.sendAttachments(conversationId: id, caption: text, items: items, replyTo: nil)
        }.value
        guard let item, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].messages.append(Message(item))
        await deliverNow()
    }

    /// The decoded picture of an image attachment, downloading and decrypting it first if this phone does not have it yet.
    func image(for item: AttachmentItem) async -> UIImage? {
        if let cached = AttachmentImages.shared.image(item.id) { return cached }
        guard let data = await attachmentData(item) else { return nil }
        let image = await Task.detached(priority: .userInitiated) { UIImage(data: data) }.value
        AttachmentImages.shared.set(image, item.id)
        return image
    }

    /// The decrypted bytes of an attachment, downloading them if needed (`nil` when it cannot be had, for example offline).
    func attachmentData(_ item: AttachmentItem) async -> Data? {
        #if DEBUG
        if isDemo { return demoAttachmentData[item.id] }
        #endif
        guard let core else { return nil }
        if let held = try? await Task.detached(priority: .userInitiated, operation: { try core.attachmentData(attachmentId: item.id) }).value { return held }
        guard let link, let token = try? await link.token() else { return nil }
        let id = item.id
        let fetched: Bool = await Task.detached(priority: .userInitiated) {
            (try? core.downloadAttachment(transport: link.transport, authToken: token, attachmentId: id)) != nil
        }.value
        guard fetched else { return nil }
        markDownloaded(id)
        return (try? await Task.detached(priority: .userInitiated) { try core.attachmentData(attachmentId: id) }.value) ?? nil
    }

    /// A file written where Quick Look and the share sheet can read it (in the temporary folder, under its own name).
    func fileURL(for item: AttachmentItem) async -> URL? {
        guard let data = await attachmentData(item) else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lime-open-\(item.id)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = item.name.isEmpty ? "File" : item.name
        let url = folder.appendingPathComponent(name)
        do { try data.write(to: url, options: [.atomic, .completeFileProtection]) } catch { return nil }
        return url
    }

    /// Downloads the pictures of recent messages in the background so they are there when a chat opens (files wait for a tap).
    func downloadRecentImages() async {
        #if DEBUG
        if isDemo { return }
        #endif
        guard core != nil, link != nil else { return }
        let wanted = conversations.flatMap { $0.messages.suffix(30) }.flatMap(\.attachments).filter { $0.kind == .image && !$0.downloaded && $0.size < 6_000_000 }.prefix(12)
        for item in wanted { _ = await attachmentData(item) }
    }

    private func markDownloaded(_ id: String) {
        for c in conversations.indices {
            for m in conversations[c].messages.indices {
                if let a = conversations[c].messages[m].attachments.firstIndex(where: { $0.id == id }) { conversations[c].messages[m].attachments[a].downloaded = true }
            }
        }
    }
}

#if DEBUG
// MARK: Debug demo (screenshots and UI tests)

extension ConversationStore {
    /// A picture made up in memory: a colour wash with a shape, so tiles and the viewer have something to show.
    static func demoPicture(_ hue: CGFloat, size: CGSize = CGSize(width: 1200, height: 900)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor(hue: hue, saturation: 0.5, brightness: 0.9, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(hue: hue, saturation: 0.7, brightness: 0.55, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: size.width * 0.25, y: size.height * 0.2, width: size.height * 0.6, height: size.height * 0.6))
        }
    }

    func demoAttachment(hue: CGFloat, name: String) -> AttachmentItem {
        let picture = Self.demoPicture(hue)
        let data = picture.jpegData(compressionQuality: 0.8) ?? Data()
        let id = UUID().uuidString.lowercased()
        demoAttachmentData[id] = data
        return AttachmentItem(id: id, mime: "image/jpeg", name: name, size: Int64(data.count), width: 1200, height: 900, thumb: AttachmentProcessing.thumbnail(picture), downloaded: true)
    }

    func loadDemoAttachments(draft: Bool) {
        let pat = Person(id: "pat", name: "Pat Rivera")
        let now = Date()
        var album = Message(id: "a1", senderID: "pat", text: "Field trip photos 🎉", date: now.addingTimeInterval(-1_800))
        album.attachments = [0.3, 0.55, 0.08].enumerated().map { demoAttachment(hue: $0.element, name: "Trip \($0.offset + 1).jpg") }
        let pdfID = UUID().uuidString.lowercased()
        demoAttachmentData[pdfID] = Data("%PDF-1.4 demo".utf8)
        var file = Message(id: "a2", senderID: "pat", text: "", date: now.addingTimeInterval(-1_200))
        file.attachments = [AttachmentItem(id: pdfID, mime: "application/pdf", name: "Permission slip.pdf", size: 1_250_000, downloaded: true)]
        var mine = Message(id: "a3", senderID: nil, text: "", date: now.addingTimeInterval(-600), state: .sent)
        mine.attachments = [demoAttachment(hue: 0.62, name: "Poster.jpg")]
        conversations = [Conversation(id: "dm:att", title: pat.name, members: [pat], messages: [album, file, mine])]
        demoDrafts = draft
    }

    func demoSendAttachments(_ items: [OutgoingAttachment], caption: String, in id: Conversation.ID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        var message = Message(id: UUID().uuidString, senderID: nil, text: caption, date: Date(), state: .sending)
        message.attachments = items.map { item in
            let attachmentID = UUID().uuidString.lowercased()
            demoAttachmentData[attachmentID] = Data(item.bytes)
            return AttachmentItem(id: attachmentID, mime: item.mime, name: item.name, size: Int64(item.bytes.count), width: item.width.map(Int.init), height: item.height.map(Int.init),
                                  thumb: item.thumb, downloaded: true)
        }
        conversations[index].messages.append(message)
    }
}

extension ChatComposer {
    /// Two waiting pictures, for screenshots of the composer with attachments.
    static var demoDrafts: [DraftAttachment] {
        [0.1, 0.45].compactMap { hue in
            let picture = ConversationStore.demoPicture(hue, size: CGSize(width: 400, height: 400))
            return AttachmentProcessing.photo(picture).map { DraftAttachment(outgoing: $0, preview: picture) }
        }
    }
}
#endif
