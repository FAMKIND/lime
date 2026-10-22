import SwiftUI
import UIKit
import LinkPresentation

/// Link cards (LIME-106). The sender's phone builds the preview with Apple's LinkPresentation before sending; the title, the site
/// and a picture then travel inside the encrypted message, so the people who read it never visit the link.
enum LinkPreviewMaker {
    /// The first web address in what is being written.
    static func firstURL(in text: String) -> URL? {
        guard !text.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, options: [], range: range) {
            if let url = match.url, ["https", "http"].contains(url.scheme?.lowercased()), url.host != nil { return url }
        }
        return nil
    }

    /// Visits the page from this phone (as the setting says) and builds the card: its title, the site, and a picture if it has one.
    @MainActor
    static func make(for url: URL, demo: Bool = false) async -> OutgoingPreview? {
        if demo { return demoPreview(for: url) }
        // An address typed without a scheme ("apple.com") is read as http://: iOS refuses to load a plain http page for an app (App Transport
        // Security), so the fetch timed out after eight seconds and no card came. The page is fetched, and the card links, over https.
        var url = url
        if url.scheme?.lowercased() == "http", var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            parts.scheme = "https"
            if let secure = parts.url { url = secure }
        }
        let provider = LPMetadataProvider()
        provider.timeout = 8
        let fetched: LPLinkMetadata?
        do { fetched = try await provider.startFetchingMetadata(for: url) } catch {
            CallDiagnostics.shared.log("link preview failed: \(error.localizedDescription)")
            fetched = nil
        }
        guard let metadata = fetched else { return nil }
        let title = metadata.title ?? ""
        let site = host(of: url)
        var jpeg = Data(), size = CGSize.zero
        let source = metadata.imageProvider ?? metadata.iconProvider
        CallDiagnostics.shared.log("link preview fetched: title \(title.count) chars, image provider \(metadata.imageProvider != nil ? "yes" : "no"), icon provider \(metadata.iconProvider != nil ? "yes" : "no")")
        if let source, let image = await load(source) {
            let scaled = scaled(image, maxWidth: 640)
            size = scaled.size
            jpeg = encode(scaled)
        }
        guard !title.isEmpty || !site.isEmpty else { return nil }
        return OutgoingPreview(url: url.absoluteString, title: title.isEmpty ? site : title, site: site, image: jpeg,
                               imageWidth: jpeg.isEmpty ? nil : UInt32(size.width), imageHeight: jpeg.isEmpty ? nil : UInt32(size.height))
    }

    static func host(of url: URL) -> String {
        let host = url.host ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The page's picture, if it arrives within five seconds: a picture that never comes must not keep the card from showing (the card then has the
    /// title and the site). A provider that never calls back was the likely reason a link in a chat showed no card at all.
    @MainActor
    private static func load(_ provider: NSItemProvider) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let once = Once(continuation)
            guard provider.canLoadObject(ofClass: UIImage.self) else { CallDiagnostics.shared.log("link preview: the picture is not an image"); once.resume(nil); return }
            provider.loadObject(ofClass: UIImage.self) { object, _ in _ = once.resume(object as? UIImage) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if once.resume(nil) { CallDiagnostics.shared.log("link preview: the picture took too long, going without it") }
            }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<UIImage?, Never>?
        init(_ continuation: CheckedContinuation<UIImage?, Never>) { self.continuation = continuation }
        /// True when this call was the one that resumed it.
        @discardableResult
        func resume(_ image: UIImage?) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard let continuation else { return false }
            continuation.resume(returning: image)
            self.continuation = nil
            return true
        }
    }

    private static func scaled(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        guard image.size.width > maxWidth else { return image }
        let ratio = maxWidth / image.size.width
        let size = CGSize(width: maxWidth, height: (image.size.height * ratio).rounded())
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    /// JPEG, small enough to travel (at most 200 KB).
    private static func encode(_ image: UIImage) -> Data {
        var quality: CGFloat = 0.75
        while quality > 0.2 {
            if let data = image.jpegData(compressionQuality: quality), data.count <= 190_000 { return data }
            quality -= 0.15
        }
        return Data()
    }

    /// Screenshots and UI tests (no network): a sample card for any address.
    @MainActor
    static func demoPreview(for url: URL) -> OutgoingPreview {
        let size = CGSize(width: 600, height: 315)
        let picture = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(hue: 0.3, saturation: 0.45, brightness: 0.85, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return OutgoingPreview(url: url.absoluteString, title: "Fractions made visible: a week of lessons", site: host(of: url),
                               image: picture.jpegData(compressionQuality: 0.7) ?? Data(), imageWidth: 600, imageHeight: 315)
    }
}

/// Settings → Privacy → "Generate link previews" (on by default).
enum LinkPreviewSetting {
    static let key = "lime.linkPreviews"
}

/// The card itself: a picture, the page's title, and the site.
struct LinkCardView: View {
    let title: String
    let site: String
    var image: UIImage?
    var isOwn = false
    var width: CGFloat = 248

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: width, height: width / 1.9).clipped()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(isOwn ? Theme.ownBubbleInk : Theme.text).lineLimit(2)
                    .accessibilityIdentifier("link-card-title")
                Text(site).font(Theme.caption).foregroundStyle(isOwn ? Theme.ownBubbleInk.opacity(0.7) : Theme.textSecondary).lineLimit(1)
                    .accessibilityIdentifier("link-card-site")
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(width: width, alignment: .leading)
        }
        .frame(width: width)
        .background(isOwn ? Theme.ownBubble : Theme.bubbleOther, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(isOwn ? Color.clear : Theme.bubbleEdge, lineWidth: 0.5))
    }
}

/// A card in a message bubble: the picture is an encrypted attachment, fetched like a photo. Tapping opens the link (an https link
/// at once; any other asks first).
struct MessageLinkCard: View {
    let messageID: String
    let preview: LinkPreviewItem
    let isOwn: Bool
    @Environment(ConversationStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var picture: UIImage?

    var body: some View {
        LinkCardView(title: preview.title, site: preview.site, image: picture, isOwn: isOwn)
            .contentShape(Rectangle())
            .mediaTap { if let url = URL(string: preview.url) { openURL(url) } }
            .accessibilityLabel("Link: \(preview.title), \(preview.site)")
            .accessibilityIdentifier("link-card-\(messageID)")
            .task(id: preview.image?.id) {
                guard let item = preview.image else { return }
                picture = await store.image(for: item)
            }
    }
}

/// A link card inside a jam post (LIME-188i): built on the writer's phone like a chat's, then carried as one small attachment of the post (the
/// address, title and site as JSON, the picture as the attachment's cover), so the readers never visit the link and the core needs nothing new.
enum JamLink {
    static let mime = "application/vnd.lime.link+json"

    struct Payload: Codable, Equatable {
        let url: String
        let title: String
        let site: String
    }

    static func attachment(_ preview: OutgoingPreview) -> OutgoingAttachment {
        let json = (try? JSONEncoder().encode(Payload(url: preview.url, title: preview.title, site: preview.site))) ?? Data()
        return OutgoingAttachment(bytes: json, name: preview.title, mime: mime, width: preview.imageWidth, height: preview.imageHeight, durationMs: nil, thumb: Data(), poster: preview.image)
    }
}
