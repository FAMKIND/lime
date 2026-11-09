import ImageIO
import Observation
import SwiftUI
import UIKit

/// LIME-277d: a chat's own look: wallpaper, the colour of my bubbles, a text size. Only I see it: it is kept on this phone, per account space, and never sent.
struct ChatLook: Codable, Equatable {
    enum Wallpaper: Codable, Equatable {
        /// The global background (277b).
        case none
        /// One of the eight backgrounds, for this chat alone.
        case background(String)
        /// A generated preset: `soft-0`…`soft-7`, `dusk`, `meadow`, `waves`, `confetti`.
        case preset(String)
        /// My own photo, kept in this account's space.
        case photo

        /// A short name for tests and logs.
        var key: String {
            switch self {
            case .none: "default"
            case .background(let id): id
            case .preset(let id): id
            case .photo: "photo"
            }
        }
    }

    var wallpaper: Wallpaper = .none
    /// The tone of my bubbles in this chat (nil: they follow the global accent), and whether it is the deep shade (white ink) or the pastel (dark ink).
    var bubbleTone: Int?
    var bubbleDeep = false
    /// The text step of this chat (nil: the same as everywhere).
    var textStep: Int?

    var isDefault: Bool { self == ChatLook() }

    /// The names the pickers and VoiceOver use for the presets.
    static let presets: [(id: String, name: String)] =
        (0..<8).map { ("soft-\($0)", "Soft \(LimeColours.name($0).lowercased())") } + [("dusk", "Dusk"), ("meadow", "Meadow"), ("waves", "Waves"), ("confetti", "Confetti")]

    /// My bubble in this chat, when it has its own colour: the deep or pastel shade of a tone, with the ink the guard picks (and links in the ink's colour).
    var ownBubble: OwnBubbleStyle? {
        guard let tone = bubbleTone else { return nil }
        let (fill, ink) = Self.bubbleColours(tone: tone, deep: bubbleDeep)
        let soft = ContrastGuard.nudge(ContrastGuard.blend(ink, fill, 0.3), against: [fill], minimum: ContrastGuard.text)
        return OwnBubbleStyle(fill: Color(fill), ink: Color(ink), link: Color(ink), secondary: Color(soft))
    }

    /// The fill of a tone's deep or pastel shade, and the ink that reads on it (WCAG AA by `ContrastGuard`).
    static func bubbleColours(tone: Int, deep: Bool) -> (fill: UIColor, ink: UIColor) {
        let base = UIColor(hex: LimeColours.accentHex[((tone % 8) + 8) % 8])
        let fill = deep ? ContrastGuard.blend(base, .black, 0.5) : ContrastGuard.blend(base, .white, 0.55)
        return (fill, ContrastGuard.ink(on: fill))
    }
}

/// My bubble's colours in a chat that has its own.
struct OwnBubbleStyle {
    let fill: Color
    let ink: Color
    let link: Color
    /// Captions: the ink a little softer, still 4.5:1 on the fill.
    let secondary: Color
}

extension EnvironmentValues {
    /// A chat's own colour for my bubbles; nil means the theme's (which follows the accent).
    @Entry var ownBubbleStyle: OwnBubbleStyle? = nil
    /// The chat has its own wallpaper: text outside the bubbles sits on a small chip so it reads on any picture.
    @Entry var chatWallpaperActive = false
}

/// The looks of every chat on this phone for the open account.
@Observable
final class ChatLooks: @unchecked Sendable {
    static let shared = ChatLooks()

    private(set) var chats: [String: ChatLook] = [:]
    /// "Use for all chats": the look every chat without its own has.
    private(set) var all: ChatLook?
    /// Bumped when a wallpaper photo changes, so views reload it.
    private(set) var photoRevision = 0
    private var account: String?

    private func key(_ suffix: String) -> String { "lime.chatlooks.\(account ?? "none").\(suffix)" }

    func load(for account: String?, defaults: UserDefaults = .standard) {
        self.account = account
        chats = [:]; all = nil
        guard account != nil else { return }
        if let data = defaults.data(forKey: key("chats")), let decoded = try? JSONDecoder().decode([String: ChatLook].self, from: data) { chats = decoded }
        if let data = defaults.data(forKey: key("all")) { all = try? JSONDecoder().decode(ChatLook.self, from: data) }
        #if DEBUG
        // `-lime-demo-photo-wallpaper` (LIME-277k): Sam's chat has a big photo as its wallpaper, 1600 x 1200 like one chosen from Photos.
        if ProcessInfo.processInfo.arguments.contains("-lime-demo-photo-wallpaper") {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 1200), format: { let f = UIGraphicsImageRendererFormat.default(); f.scale = 1; return f }()).image { c in
                let colours = [UIColor.systemOrange.cgColor, UIColor.systemPink.cgColor, UIColor.systemIndigo.cgColor] as CFArray
                c.cgContext.drawLinearGradient(CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 0.5, 1])!, start: .zero, end: CGPoint(x: 1600, y: 1200), options: [])
            }
            setPhoto(image, for: "dm:sam")
        }
        #endif
        #if DEBUG
        // Screenshots and tests: `-lime-demo-chatlook <bubbleTone> <deep|pastel> <wallpaper id>` styles Sam's chat.
        let arguments = ProcessInfo.processInfo.arguments
        if let at = arguments.firstIndex(of: "-lime-demo-chatlook"), at + 3 < arguments.count {
            var look = ChatLook()
            look.bubbleTone = Int(arguments[at + 1]); look.bubbleDeep = arguments[at + 2] == "deep"
            let id = arguments[at + 3]
            if ThemeBackground(rawValue: id) != nil { look.wallpaper = .background(id) } else if ChatLook.presets.contains(where: { $0.id == id }) { look.wallpaper = .preset(id) }
            chats["dm:sam"] = look
        }
        #endif
    }

    func look(for chat: String) -> ChatLook { chats[chat] ?? all ?? ChatLook() }

    func set(_ look: ChatLook, for chat: String) {
        chats[chat] = look
        save()
    }

    /// Resets one chat to the global look (and drops its photo).
    func reset(_ chat: String) {
        chats[chat] = nil
        removePhoto(chat)
        save()
    }

    /// This chat's look for every chat without its own (a photo is copied for the chats that follow, so it is shared by name: kept once).
    func useForAll(_ chat: String) {
        var look = look(for: chat)
        if look.wallpaper == .photo { look.wallpaper = .none }   // a photo belongs to the chat it was chosen in
        all = look.isDefault ? nil : look
        chats = chats.filter { $0.key == chat }   // other chats' own looks are replaced
        chats[chat] = nil
        save()
    }

    /// A deleted chat takes its look and photo with it.
    func remove(_ chat: String) {
        chats[chat] = nil
        removePhoto(chat)
        save()
    }

    private func save(defaults: UserDefaults = .standard) {
        guard account != nil else { return }
        defaults.set(try? JSONEncoder().encode(chats), forKey: key("chats"))
        if let all { defaults.set(try? JSONEncoder().encode(all), forKey: key("all")) } else { defaults.removeObject(forKey: key("all")) }
    }

    // MARK: The wallpaper photo (in this account's space; `lime-wallpapers` so "Remove everything" deletes it with the rest)

    /// The folder of wallpaper pictures (for a move to a new phone: LIME-272c).
    var wallpaperFolder: URL? { photoFolder }

    private var photoFolder: URL? {
        guard let account, let location = try? StorageBootstrap.Location.live(for: account) else { return nil }
        return location.directory.appendingPathComponent("lime-wallpapers", isDirectory: true)
    }

    func photoURL(_ chat: String) -> URL? {
        photoFolder?.appendingPathComponent(chat.replacingOccurrences(of: ":", with: "-") + ".jpg")
    }

    /// Keeps `image` (shrunk to at most 1600 px) as the wallpaper of `chat`.
    func setPhoto(_ image: UIImage, for chat: String) {
        guard let url = photoURL(chat), let folder = photoFolder else { return }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 1600 / max(longest, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat.default(); f.scale = 1; return f }())
        guard let data = renderer.jpegData(withCompressionQuality: 0.8, actions: { _ in image.draw(in: CGRect(origin: .zero, size: size)) }) as Data? else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var look = look(for: chat)
        look.wallpaper = .photo
        chats[chat] = look
        photoRevision += 1
        save()
    }

    func removePhoto(_ chat: String) {
        if let url = photoURL(chat) { try? FileManager.default.removeItem(at: url) }
        photoRevision += 1
    }

    // The decoded wallpaper, once per chat and revision (LIME-277k): downsampled with ImageIO to about the screen's pixels and kept in memory, loaded off the main
    // thread. It used to be read from disk and decoded on every pass of a view body, so typing with the keyboard up churned the main thread.
    private let decoded = NSCache<NSString, UIImage>()

    /// The cached picture, if it is already decoded (never reads the disk).
    func cachedPhoto(_ chat: String) -> UIImage? { decoded.object(forKey: cacheKey(chat)) }

    private func cacheKey(_ chat: String) -> NSString { "\(chat)|\(photoRevision)" as NSString }

    func photo(_ chat: String) async -> UIImage? {
        let key = cacheKey(chat)
        if let hit = decoded.object(forKey: key) { return hit }
        guard let url = photoURL(chat) else { return nil }
        let longest = await MainActor.run { max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * UIScreen.main.scale }
        let image = await Task.detached(priority: .userInitiated) { Self.downsample(url, maxPixel: min(longest, 2000)) }.value
        if let image { decoded.setObject(image, forKey: key) }
        return image
    }

    nonisolated static func downsample(_ url: URL, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceShouldCacheImmediately: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
    }
}

// MARK: Drawing a wallpaper

/// One wallpaper, filling its frame. Used for a chat's page and for the small samples in the picker.
struct WallpaperLayer: View {
    let wallpaper: ChatLook.Wallpaper
    var photo: UIImage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch wallpaper {
        case .none:
            ThemeBackgroundView()
        case .background(let raw):
            ThemeBackgroundView(override: ThemeBackground(rawValue: raw))
        case .preset(let id):
            PresetWallpaper(id: id)
        case .photo:
            if let photo {
                // The size comes from the container, never from the picture (LIME-277k): a clear box takes whatever it is given and the picture fills it from inside a
                // clip. A `scaledToFill` image on its own reports its whole size and widened the chat's layout, pushing its buttons and composer off the screen.
                Color.clear
                    .overlay {
                        Image(uiImage: photo).resizable().scaledToFill()
                        // Dimmed in the dark, and a little veil in the light, so bubbles and the words around them stay readable.
                        Color.black.opacity(scheme == .dark ? 0.38 : 0.06)
                    }
                    .clipped()
                    .allowsHitTesting(false)
            } else { ThemeBackgroundView() }
        }
    }
}

private struct PresetWallpaper: View {
    let id: String
    @Environment(\.colorScheme) private var scheme

    private func tint(_ tone: Int) -> Color {
        let base = Theme.avatarUIColor(tone, dark: scheme == .dark)
        return Color(ContrastGuard.blend(base, scheme == .dark ? .black : .white, scheme == .dark ? 0.6 : 0.55))
    }

    var body: some View {
        if id.hasPrefix("soft-"), let tone = Int(id.dropFirst(5)) {
            tint(tone)
        } else if id == "dusk" {
            LinearGradient(colors: [tint(6), tint(0)], startPoint: .top, endPoint: .bottom)
        } else if id == "meadow" {
            LinearGradient(colors: [tint(5), tint(7)], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if id == "waves" {
            Canvas { context, size in
                let line = Color(Theme.avatarUIColor(7, dark: scheme == .dark)).opacity(scheme == .dark ? 0.35 : 0.5)
                var y: CGFloat = 20
                while y < size.height + 20 {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    var x: CGFloat = 0
                    while x <= size.width { path.addLine(to: CGPoint(x: x, y: y + sin(x / 28) * 6)); x += 4 }
                    context.stroke(path, with: .color(line), lineWidth: 1.2)
                    y += 22
                }
            }
            .background(tint(7))
        } else {
            Canvas { context, size in
                var state: UInt64 = 91
                func next() -> Double { state = state &* 6364136223846793005 &+ 1442695040888963407; return Double(state >> 33) / Double(UInt64(1) << 31) }
                for _ in 0..<Int(size.width * size.height / 2600) {
                    let x = next() * size.width, y = next() * size.height, r = 3 + next() * 4
                    let colour = Color(Theme.avatarUIColor(Int(next() * 8) % 8, dark: scheme == .dark)).opacity(0.55)
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(colour))
                }
            }
            .background(tint(3))
        }
    }
}

/// A chat's page background.
struct ChatWallpaperView: View {
    let chatID: String
    @State private var photo: UIImage?
    var body: some View {
        let look = ChatLooks.shared.look(for: chatID)
        let usesPhoto = look.wallpaper == .photo
        WallpaperLayer(wallpaper: look.wallpaper, photo: usesPhoto ? (photo ?? ChatLooks.shared.cachedPhoto(chatID)) : nil)
            .task(id: "\(chatID)|\(usesPhoto)|\(ChatLooks.shared.photoRevision)") { photo = usesPhoto ? await ChatLooks.shared.photo(chatID) : nil }
            #if DEBUG
            // UI tests: which look this chat has (`chat-look-<wallpaper>-<bubble>`).
            .overlay(alignment: .topLeading) { Color.clear.frame(width: 1, height: 1).accessibilityElement().accessibilityIdentifier("chat-look-\(look.wallpaper.key)-\(look.bubbleTone.map { "\($0)-\(look.bubbleDeep ? "deep" : "pastel")" } ?? "follow")") }
            #endif
    }
}

extension View {
    /// Text outside the bubbles (day lines, names, times) on a chat with its own wallpaper: a small chip, so it reads on any picture.
    func wallpaperChip() -> some View { modifier(WallpaperChip()) }
}

private struct WallpaperChip: ViewModifier {
    @Environment(\.chatWallpaperActive) private var active
    func body(content: Content) -> some View {
        if active {
            content.padding(.horizontal, 8).padding(.vertical, 2).background(Theme.surface.opacity(0.9), in: Capsule())
        } else { content }
    }
}
