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
    /// Sends photos, files, a voice message or a video with an optional caption. In a chat or a group, or (with `replyTo`, the
    /// root message) as a reply in its thread.
    func sendAttachments(_ items: [OutgoingAttachment], caption: String, in id: Conversation.ID, replyTo root: String? = nil) {
        Task { await sendAttachmentsNow(items, caption: caption, in: id, replyTo: root) }
    }

    func sendAttachmentsNow(_ items: [OutgoingAttachment], caption: String, in id: Conversation.ID, replyTo root: String? = nil) async {
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        #if DEBUG
        if isDemo { demoSendAttachments(items, caption: text, in: id, replyTo: root); return }
        #endif
        guard let core, link != nil else { report(.offline); return }
        guard StorageGuard.shared.allows(items.reduce(0) { $0 + Int64($1.bytes.count) }) else {
            lowStorage = true
            showBanner("Not enough space on your iPhone to send this.")
            return
        }
        let item = try? await Task.detached(priority: .userInitiated) {
            try core.sendAttachments(conversationId: id, caption: text, items: items, replyTo: root)
        }.value
        guard let item else { return }
        if let root {
            threads[root, default: []].append(Message(item))
        } else if let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].messages.append(Message(item))
        }
        await deliverNow()
    }

    /// How far an upload or download of an attachment has got (a fraction of its chunks), while one is running.
    func transferProgress(_ id: String) async -> TransferProgress? {
        #if DEBUG
        if isDemo { return demoTransfer[id] }
        #endif
        guard let core else { return nil }
        return (try? await Task.detached(priority: .utility) { try core.transferProgress(attachmentId: id) }.value) ?? nil
    }

    /// The voice message that follows `id` in its chat and was not sent by me, to play on after it.
    func nextVoiceMessage(after id: String) -> AttachmentItem? {
        for conversation in conversations {
            let voices = conversation.messages.flatMap { message in message.attachments.filter { $0.kind == .audio }.map { (message, $0) } }
            guard let index = voices.firstIndex(where: { $0.1.id == id }) else { continue }
            return voices.dropFirst(index + 1).first { !$0.0.isOwn }?.1
        }
        return nil
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
        if isDemo {
            guard !item.removed, let data = demoAttachmentData[item.id] else { return nil }
            if !item.downloaded && !StorageGuard.shared.allows(item.size) {
                lowStorage = true
                showBanner("Not enough space on your iPhone to download this.")
                return nil
            }
            markDownloaded(item.id)
            return data
        }
        #endif
        guard let core else { return nil }
        if let held = try? await Task.detached(priority: .userInitiated, operation: { try core.attachmentData(attachmentId: item.id) }).value { return held }
        if item.removed { return nil }
        // Not enough room: say so and stop before writing anything; nothing is lost and it can be tried again.
        guard StorageGuard.shared.allows(item.size) else {
            lowStorage = true
            showBanner("Not enough space on your iPhone to download this.")
            return nil
        }
        guard let link, let token = try? await link.token() else { return nil }
        let id = item.id
        downloading.insert(id)
        defer { downloading.remove(id) }
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
        refreshStorageState()
        await applyKeepMedia()
        // Only what the settings allow (pictures, video and files by their own choices, voice always), and nothing when the phone is nearly full.
        let guardrail = StorageGuard.shared
        let wanted = conversations.flatMap { $0.messages.suffix(30) }.flatMap(\.attachments)
            .filter { !$0.downloaded && !$0.removed && guardrail.mayAutoDownload($0) }
            .filter { $0.kind == .image && $0.size < 6_000_000 || $0.kind == .audio && $0.size < 1_000_000 || ($0.kind == .video || $0.kind == .file) && $0.size < 25_000_000 }
            .prefix(12)
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

    func demoVoice(seconds: Int) -> AttachmentItem {
        let id = UUID().uuidString.lowercased()
        demoAttachmentData[id] = Data(count: 3_000)
        let wave = Data((0..<64).map { UInt8(40 + 150 * abs(sin(Double($0) / 5))) })
        return AttachmentItem(id: id, mime: "audio/mp4", name: "Voice message.m4a", size: 3_000, durationMs: seconds * 1000, thumb: wave, downloaded: true)
    }

    func demoVideo() -> AttachmentItem {
        let picture = Self.demoPicture(0.5, size: CGSize(width: 640, height: 360))
        let id = UUID().uuidString.lowercased()
        demoAttachmentData[id] = Data(count: 3_000)
        return AttachmentItem(id: id, mime: "video/mp4", name: "Video.mp4", size: 3_000, width: 1280, height: 720, durationMs: 31_000,
                              thumb: AttachmentProcessing.thumbnail(picture), downloaded: true)
    }

    func loadDemoAttachments(draft: Bool, screen: String = "attachments") {
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
        let media = screen == "attachments-media"
        var voiceOne = Message(id: "a4", senderID: "pat", text: "", date: now.addingTimeInterval(-500))
        voiceOne.attachments = [demoVoice(seconds: 6)]
        var voiceTwo = Message(id: "a5", senderID: "pat", text: "", date: now.addingTimeInterval(-400))
        voiceTwo.attachments = [demoVoice(seconds: 9)]
        var clip = Message(id: "a6", senderID: "pat", text: "Our class rehearsal", date: now.addingTimeInterval(-300))
        clip.attachments = [demoVideo()]
        // One of mine still going up, three fifths of the way.
        var going = Message(id: "a7", senderID: nil, text: "", date: now.addingTimeInterval(-60), state: .sending)
        going.attachments = [demoAttachment(hue: 0.9, name: "Banner.jpg")]
        demoTransfer[going.attachments[0].id] = TransferProgress(upload: true, done: 3, total: 5)
        // "attachments" is pictures and a file; "attachments-media" is voice, video and an upload in progress.
        // "attachments-remote": nothing has been downloaded yet (the settings or a full phone), one file is gone, one was removed.
        var remote = Message(id: "r1", senderID: "pat", text: "Photos from the trip", date: now.addingTimeInterval(-900))
        var far = demoAttachment(hue: 0.15, name: "Trip far.jpg")
        far.downloaded = false
        remote.attachments = [far]
        var gonePDF = Message(id: "r2", senderID: "pat", text: "", date: now.addingTimeInterval(-800))
        gonePDF.attachments = [AttachmentItem(id: UUID().uuidString.lowercased(), mime: "application/pdf", name: "gone-slip.pdf", size: 900_000, downloaded: false)]
        var removedPhoto = Message(id: "r3", senderID: "pat", text: "", date: now.addingTimeInterval(-700))
        var oldPic = demoAttachment(hue: 0.75, name: "Old.jpg")
        oldPic.downloaded = false; oldPic.removed = true
        removedPhoto.attachments = [oldPic]
        var farPDF = Message(id: "r4", senderID: "pat", text: "", date: now.addingTimeInterval(-600))
        let farPDFID = UUID().uuidString.lowercased()
        demoAttachmentData[farPDFID] = Data("%PDF-1.4 remote".utf8)
        farPDF.attachments = [AttachmentItem(id: farPDFID, mime: "application/pdf", name: "Schedule.pdf", size: 1_250_000, downloaded: false)]
        let messages = screen == "attachments-remote" ? [remote, gonePDF, removedPhoto, farPDF] : (media ? [voiceOne, voiceTwo, clip, going] : [album, file, mine])
        conversations = [Conversation(id: "dm:att", title: pat.name, members: [pat], messages: messages)]
        VoicePlayer.shared.stop()
        VoicePlayer.shared.simulated = true
        demoDrafts = draft
    }

    func demoSendAttachments(_ items: [OutgoingAttachment], caption: String, in id: Conversation.ID, replyTo root: String? = nil) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        var message = Message(id: UUID().uuidString, senderID: nil, text: caption, date: Date(), state: .sending)
        message.attachments = items.map { item in
            let attachmentID = UUID().uuidString.lowercased()
            demoAttachmentData[attachmentID] = Data(item.bytes)
            return AttachmentItem(id: attachmentID, mime: item.mime, name: item.name, size: Int64(item.bytes.count), width: item.width.map(Int.init), height: item.height.map(Int.init),
                                  thumb: item.thumb, downloaded: true)
        }
        if let root {
            demoThreads[root, default: []].append(message)
            threads[root] = demoThreads[root]
        } else {
            conversations[index].messages.append(message)
        }
    }
}

extension ChatComposer {
    /// A prepared video waiting in the composer (the demo has no camera).
    static var demoVideoDraft: DraftAttachment {
        let picture = ConversationStore.demoPicture(0.75, size: CGSize(width: 640, height: 360))
        let item = OutgoingAttachment(bytes: Data(count: 3_000), name: "Video.mp4", mime: "video/mp4", width: 640, height: 360, durationMs: 31_000,
                                      thumb: AttachmentProcessing.thumbnail(picture))
        return DraftAttachment(outgoing: item, preview: picture)
    }

    /// Two waiting pictures, for screenshots of the composer with attachments.
    static var demoDrafts: [DraftAttachment] {
        [0.1, 0.45].compactMap { hue in
            let picture = ConversationStore.demoPicture(hue, size: CGSize(width: 400, height: 400))
            return AttachmentProcessing.photo(picture).map { DraftAttachment(outgoing: $0, preview: picture) }
        }
    }
}
#endif
