import SwiftUI

/// One of lime's own stickers (LIME-209b): an animated GIF drawn by lime, shipped inside the app.
struct LimeSticker: Identifiable, Equatable {
    let file: String          // "thank-you"
    let words: String         // "Thank you!"
    let find: [String]        // other words that find it
    var id: String { file }
    var url: URL? { Bundle.main.url(forResource: file, withExtension: "gif") }
    /// VoiceOver: "lime sticker: Thank you!"
    var label: String { "lime sticker: \(words)" }
}

/// lime's starter pack of 24 stickers (`pack.json`, written by tools/stickers/make-stickers.swift). They are files in the app: nothing is downloaded, and
/// sending one sends the GIF like any other (LIME-206).
enum StickerPack {
    /// "Show lime's stickers" in Settings → My GIFs; on by default, kept on this phone.
    static let shownKey = "lime.showStickers"
    static var isShown: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: shownKey) == nil ? true : defaults.bool(forKey: shownKey)
    }

    static let all: [LimeSticker] = load()

    private static func load() -> [LimeSticker] {
        guard let url = Bundle.main.url(forResource: "pack", withExtension: "json"), let data = try? Data(contentsOf: url) else { return [] }
        return parse(data)
    }

    static func parse(_ data: Data) -> [LimeSticker] {
        struct Entry: Decodable { let file: String; let words: String; let find: [String] }
        struct Pack: Decodable { let stickers: [Entry] }
        guard let pack = try? JSONDecoder().decode(Pack.self, from: data) else { return [] }
        return pack.stickers.map { LimeSticker(file: ($0.file as NSString).deletingPathExtension, words: $0.words, find: $0.find) }
    }

    /// The stickers whose words (or other finding words) start with every word typed; all of them for nothing typed. Nothing when the pack is hidden.
    static func matching(_ query: String, in pack: [LimeSticker] = all, shown: Bool = isShown) -> [LimeSticker] {
        guard shown else { return [] }
        let typed = tokens(query)
        guard !typed.isEmpty else { return pack }
        return pack.filter { sticker in
            let have = tokens(sticker.words) + sticker.find.flatMap(tokens)
            return typed.allSatisfy { word in have.contains { $0.hasPrefix(word) } }
        }
    }

    private static func tokens(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// The sticker as an attachment, named so My GIFs does not save a copy of it.
    static func attachment(_ sticker: LimeSticker) -> OutgoingAttachment? {
        guard let url = sticker.url, let data = try? Data(contentsOf: url), let made = try? GIF.attachment(data, name: "\(namePrefix)\(sticker.file).gif") else { return nil }
        return made.0
    }

    static let namePrefix = "lime-sticker-"
}

/// A still frame of a sticker (the grid and the strip do not animate: they follow Reduce Motion and stay light).
struct StickerThumb: View {
    let sticker: LimeSticker
    @State private var image: UIImage?
    var body: some View {
        Color.clear.overlay {
            Theme.surface
            if let image { Image(uiImage: image).resizable().scaledToFill() }
        }
        .clipped()
        .task(id: sticker.id) {
            if let url = sticker.url, let data = try? Data(contentsOf: url) { image = GIF.firstFrame(data) }
        }
        .accessibilityHidden(true)
    }
}
