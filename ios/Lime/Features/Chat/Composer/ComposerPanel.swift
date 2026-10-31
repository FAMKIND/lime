import SwiftUI
import UIKit

/// The panel behind 😊 (LIME-279): Emoji · GIFs · Stickers, in the place of the keyboard.
enum ComposerPanelTab: String, CaseIterable, Identifiable {
    case emoji = "Emoji", gifs = "GIFs", stickers = "Stickers"
    var id: String { rawValue }

    /// The tab used last, kept on this phone.
    static let rememberedKey = "lime.composerPanelTab"
    static var remembered: ComposerPanelTab { UserDefaults.standard.string(forKey: rememberedKey).flatMap(ComposerPanelTab.init(rawValue:)) ?? .emoji }
}

/// The tabs, in the composer's stack just above the panel (as the formatting strip is above the keyboard), with Search for the GIFs and stickers.
struct ComposerPanelTabs: View {
    let model: RichComposerModel
    let onSearch: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("Panel", selection: Binding(get: { model.panelTab }, set: { model.selectPanelTab($0) })) {
                ForEach(ComposerPanelTab.allCases) { tab in Text(tab.rawValue).tag(tab) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Emoji, GIFs and stickers")
            .accessibilityIdentifier("panel-tabs")
            if model.panelTab != .emoji {
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.text).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Search GIFs and stickers").accessibilityIdentifier("panel-search")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 6)
    }
}

/// What the GIFs and Stickers tabs show where the keyboard would be: a grid, one tap sends. Search and managing are the sheet's (the magnifier).
struct ComposerPanelContent: View {
    let tab: ComposerPanelTab
    let onSend: (OutgoingAttachment) -> Void
    @Environment(ConversationStore.self) private var store
    @State private var gifs: [MyGif] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            switch tab {
            case .gifs: gifGrid
            case .stickers: stickerGrid
            case .emoji: EmptyView()
            }
        }
        .background(Theme.canvas)
    }

    private var gifGrid: some View {
        Group {
            if gifs.isEmpty && loaded {
                Text("Save a GIF from a chat (touch and hold it), or add one with Search.")
                    .font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).padding(.horizontal, 40).padding(.top, 40)
                    .accessibilityIdentifier("panel-gifs-empty")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 80), spacing: 6), count: 3), spacing: 6) {
                ForEach(gifs, id: \.id) { gif in
                    let label = [gif.words, gif.frameText, gif.messageText].first { !$0.isEmpty }.map { "GIF, \($0)" } ?? "GIF"
                    Button { Task { await send(gif) } } label: {
                        GIFThumb(id: gif.id).aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label).accessibilityHint("Sends it")
                    .accessibilityIdentifier("panel-gif-\(gif.id)")
                }
            }
            .padding(12)
        }
        .task(id: store.myGIFRevision) { gifs = await store.myGIFs(matching: ""); loaded = true }
    }

    private var stickerGrid: some View {
        Group {
            if StickerPack.isShown {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 64), spacing: 6), count: 4), spacing: 6) {
                    ForEach(StickerPack.all) { sticker in
                        Button { if let item = StickerPack.attachment(sticker) { onSend(item) } } label: {
                            StickerThumb(sticker: sticker).aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(sticker.label).accessibilityHint("Sends it")
                        .accessibilityIdentifier("panel-sticker-\(sticker.id)")
                    }
                }
                .padding(12)
            } else {
                Text("lime\u{2019}s stickers are off. Turn them on in Settings, My GIFs.")
                    .font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).padding(.horizontal, 40).padding(.top, 40)
                    .accessibilityIdentifier("panel-stickers-off")
            }
        }
    }

    private func send(_ gif: MyGif) async {
        guard let data = await store.myGIFData(gif.id), let made = try? GIF.attachment(data, name: "GIF.gif") else { return }
        await store.touchMyGIF(gif.id)
        onSend(made.0)
    }
}

/// The input view that stands where the keyboard stands: the SwiftUI panel, the height the emoji keyboard had.
final class ComposerPanelInputView: UIInputView {
    private let host: UIHostingController<AnyView>

    init(content: AnyView, height: CGFloat) {
        host = UIHostingController(rootView: content)
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: height), inputViewStyle: .default)
        allowsSelfSizing = true
        host.view.backgroundColor = UIColor(Theme.canvas)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor), host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor), host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: height),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

/// Genmoji and Memoji stickers (iOS 18): the text view takes them as adaptive image glyphs; lime sends them as pictures, so every phone shows them. The glyphs
/// are taken out of the text and come back as PNG pictures (their transparency kept) for the message's attachments.
enum AdaptiveGlyphs {
    /// Takes every adaptive image glyph out of `storage` and returns each as PNG data. The text around them is untouched.
    @discardableResult
    static func take(from storage: NSTextStorage) -> [Data] {
        guard #available(iOS 18.0, *) else { return [] }
        var found: [(NSRange, Data)] = []
        storage.enumerateAttribute(.adaptiveImageGlyph, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let glyph = value as? NSAdaptiveImageGlyph, let png = UIImage(data: glyph.imageContent)?.pngData() else { return }
            found.append((range, png))
        }
        for (range, _) in found.reversed() { storage.replaceCharacters(in: range, with: "") }
        return found.map(\.1)
    }
}
