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
            if let url = match.url, url.scheme == "https" || url.scheme == "http", url.host != nil { return url }
        }
        return nil
    }

    /// Visits the page from this phone (as the setting says) and builds the card: its title, the site, and a picture if it has one.
    @MainActor
    static func make(for url: URL, demo: Bool = false) async -> OutgoingPreview? {
        if demo { return demoPreview(for: url) }
        let provider = LPMetadataProvider()
        provider.timeout = 8
        guard let metadata = try? await provider.startFetchingMetadata(for: url) else { return nil }
        let title = metadata.title ?? ""
        let site = host(of: url)
        var jpeg = Data(), size = CGSize.zero
        let source = metadata.imageProvider ?? metadata.iconProvider
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

    @MainActor
    private static func load(_ provider: NSItemProvider) async -> UIImage? {
        await withCheckedContinuation { continuation in
            guard provider.canLoadObject(ofClass: UIImage.self) else { continuation.resume(returning: nil); return }
            provider.loadObject(ofClass: UIImage.self) { object, _ in continuation.resume(returning: object as? UIImage) }
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
                Text(title).font(Theme.secondary.weight(.semibold)).foregroundStyle(isOwn ? Theme.ownBubbleInk : Theme.text).lineLimit(2)
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
