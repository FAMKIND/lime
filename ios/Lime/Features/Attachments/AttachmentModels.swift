import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// One attachment of a message, as the screens use it (the key and digest stay in LimeCore).
struct AttachmentItem: Identifiable, Hashable, Sendable {
    let id: String
    let mime: String
    let name: String
    let size: Int64
    let width: Int?
    let height: Int?
    let durationMs: Int?
    /// A tiny blurred preview, shown until the picture itself is here.
    let thumb: Data
    var downloaded: Bool
    /// Removed from this phone on purpose ("Media removed"); it is not fetched again.
    var removed = false

    enum Kind: Sendable { case image, video, audio, file }

    var kind: Kind {
        if mime.hasPrefix("image/") { return .image }
        if mime.hasPrefix("video/") { return .video }
        if mime.hasPrefix("audio/") { return .audio }
        return .file
    }

    var aspect: CGFloat {
        guard let width, let height, width > 0, height > 0 else { return 1 }
        return CGFloat(width) / CGFloat(height)
    }

    /// "PDF · 1.2 MB" under a file's name.
    var detail: String {
        let kind = UTType(mimeType: mime)?.preferredFilenameExtension?.uppercased() ?? (name.split(separator: ".").last.map { $0.uppercased() } ?? "File")
        return "\(kind) · \(AttachmentFormat.size(size))"
    }

    init(id: String, mime: String, name: String, size: Int64, width: Int? = nil, height: Int? = nil, durationMs: Int? = nil, thumb: Data = Data(), downloaded: Bool = false) {
        self.id = id; self.mime = mime; self.name = name; self.size = size; self.width = width; self.height = height
        self.durationMs = durationMs; self.thumb = thumb; self.downloaded = downloaded
    }

    init(_ info: AttachmentInfo) {
        self.init(id: info.id, mime: info.mime, name: info.name, size: Int64(info.size), width: info.width.map(Int.init), height: info.height.map(Int.init),
                  durationMs: info.durationMs.map(Int.init), thumb: info.thumb, downloaded: info.downloaded)
        removed = info.removed
    }
}

enum AttachmentFormat {
    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// What a chat list or a notification says for a message that is only attachments: "Photo", "3 Photos", "Video",
    /// "Voice message (0:12)", the file's name, or "3 attachments".
    static func summary(_ items: [AttachmentItem]) -> String? {
        guard let first = items.first else { return nil }
        if items.allSatisfy({ $0.kind == .image }) { return items.count == 1 ? "Photo" : "\(items.count) Photos" }
        if items.count == 1 {
            switch first.kind {
            case .video: return "Video"
            case .audio: return first.durationMs.map { "Voice message (\(VoiceFormat.clock(Double($0) / 1000)))" } ?? "Voice message"
            default: return first.name.isEmpty ? "File" : first.name
            }
        }
        return "\(items.count) attachments"
    }

    /// The small symbol for a list row's preview of attachments.
    static func symbol(_ items: [AttachmentItem]) -> String? {
        guard let first = items.first else { return nil }
        if items.count > 1 && !items.allSatisfy({ $0.kind == .image }) { return "paperclip" }
        switch first.kind {
        case .image: return "camera.fill"
        case .video: return "video.fill"
        case .audio: return "mic.fill"
        case .file: return "doc.fill"
        }
    }
}

/// A file waiting in the composer to be sent, with a picture to show.
struct DraftAttachment: Identifiable {
    let id = UUID()
    let outgoing: OutgoingAttachment
    let preview: UIImage?
}

/// Makes the files Lime sends: photos shrunk and stripped of metadata, files checked against the size limit.
enum AttachmentProcessing {
    static let maxPhotoEdge: CGFloat = 2048
    static let maxFileBytes = 50 * 1024 * 1024
    static let maxThumbBytes = 2048
    static let maxPerMessage = 10

    enum Problem: Error, Equatable { case tooLarge, unreadable }

    /// A photo: at most 2048 px on its long edge, upright, redrawn so EXIF, GPS and camera details are gone, as JPEG;
    /// plus a tiny preview for the message.
    static func photo(_ image: UIImage, name: String = "Photo.jpg") -> OutgoingAttachment? {
        let upright = redraw(image, maxEdge: maxPhotoEdge)
        guard let jpeg = upright.jpegData(compressionQuality: 0.8), jpeg.count <= maxFileBytes else { return nil }
        return OutgoingAttachment(bytes: jpeg, name: name, mime: "image/jpeg", width: UInt32(upright.size.width * upright.scale), height: UInt32(upright.size.height * upright.scale),
                                  durationMs: nil, thumb: thumbnail(image))
    }

    /// At most `maxEdge` pixels on the long edge, orientation applied, no metadata.
    static func redraw(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let factor = min(1, maxEdge / max(pixels.width, pixels.height))
        let target = CGSize(width: max(1, (pixels.width * factor).rounded()), height: max(1, (pixels.height * factor).rounded()))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// A very small JPEG (at most 2 KB), shown blurred until the real picture arrives.
    static func thumbnail(_ image: UIImage) -> Data {
        var edge: CGFloat = 40
        while edge >= 8 {
            let small = redraw(image, maxEdge: edge)
            for quality in [0.5, 0.3, 0.15] as [CGFloat] {
                if let data = small.jpegData(compressionQuality: quality), data.count <= maxThumbBytes { return data }
            }
            edge -= 8
        }
        return Data()
    }

    /// A file from the document picker (already copied into the app's reach by the picker).
    static func file(at url: URL) throws -> OutgoingAttachment {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values?.fileSize, size > maxFileBytes { throw Problem.tooLarge }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { throw Problem.unreadable }
        if data.count > maxFileBytes { throw Problem.tooLarge }
        if data.isEmpty { throw Problem.unreadable }
        let type = UTType(filenameExtension: url.pathExtension)
        let mime = type?.preferredMIMEType ?? "application/octet-stream"
        // A picture sent as a file is still sent as a picture.
        if type?.conforms(to: .image) == true, let image = UIImage(data: data), let photo = photo(image, name: url.lastPathComponent) { return photo }
        return OutgoingAttachment(bytes: data, name: url.lastPathComponent, mime: mime, width: nil, height: nil, durationMs: nil, thumb: Data())
    }

    /// Metadata kinds found in encoded image data (a processed photo has none of the personal ones).
    static func personalMetadata(in data: Data) -> [String] { PhotoProcessing.personalMetadata(in: data) }
}
