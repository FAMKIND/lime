import SwiftUI
import UIKit

/// The panel behind 😊 (LIME-279): Emoji · GIFs · Stickers, in the place of the keyboard.
enum ComposerPanelTab: String, CaseIterable, Identifiable {
    case emoji = "Emoji", gifs = "GIFs", stickers = "Stickers"
    var id: String { rawValue }

    /// The tab used last, kept on this phone.
    static let rememberedKey = "lime.composerPanelTab"
    static var remembered: ComposerPanelTab {
        #if DEBUG
        // The demo always starts on Emoji (a UI test must not inherit the tab an earlier one left), unless it asks for another.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-lime-demo-chat"), !arguments.contains("-lime.composerPanelTab") { return .emoji }
        #endif
        return UserDefaults.standard.string(forKey: rememberedKey).flatMap(ComposerPanelTab.init(rawValue:)) ?? .emoji
    }
}

/// The height of the tab row, so the GIFs and Stickers panel (which carries the tabs inside it) stands exactly where the emoji keyboard and this row stood.
let composerPanelTopHeight: CGFloat = 52

/// The segmented Emoji · GIFs · Stickers (and, on GIFs and Stickers, a 🔍): one piece, shown as the top of the panel.
struct ComposerPanelTop: View {
    let model: RichComposerModel
    var onSearch: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Theme.textSecondary.opacity(0.4)).frame(width: 36, height: 4).padding(.top, 6).accessibilityHidden(true)
            HStack(spacing: 8) {
                Picker("Panel", selection: Binding(get: { model.panelTab }, set: { model.selectPanelTab($0) })) {
                    ForEach(ComposerPanelTab.allCases) { tab in Text(tab.rawValue).tag(tab) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Emoji, GIFs and stickers")
                .accessibilityIdentifier("panel-tabs")
                if let onSearch {
                    Button(action: onSearch) {
                        Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.text).frame(width: 44, height: 40)
                    }
                    .accessibilityLabel("Search GIFs and stickers").accessibilityIdentifier("panel-search")
                }
            }
            .padding(.horizontal, 16).frame(height: composerPanelTopHeight - 10)
        }
        .frame(height: composerPanelTopHeight)
    }
}

/// The tab row over the system emoji keyboard (the Emoji tab): in the keyboard's own material with rounded top corners, so row and keyboard read as one piece.
struct ComposerPanelTabs: View {
    let model: RichComposerModel

    var body: some View {
        ComposerPanelTop(model: model, onSearch: nil)
            .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
    }
}

/// Search inside the panel's place (🔍 on GIFs or Stickers): a field and its matches, above the keyboard it brings up. Cancel goes back to the panel.
struct ComposerPanelSearch: View {
    let model: RichComposerModel
    let tab: ComposerPanelTab
    let onSend: (OutgoingAttachment) -> Void
    @Environment(ConversationStore.self) private var store
    @State private var query = ""
    @State private var gifs: [MyGif] = []
    @FocusState private var focused: Bool

    private var stickers: [LimeSticker] { tab == .stickers ? StickerPack.matching(query.trimmingCharacters(in: .whitespacesAndNewlines)) : [] }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                    TextField(tab == .stickers ? "Search stickers" : "Search GIFs", text: $query)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search).focused($focused)
                        .accessibilityIdentifier("panel-search-field")
                }
                .padding(.horizontal, 12).frame(height: 40).background(Theme.surface, in: Capsule())
                Button("Cancel") { model.endSearch(reopen: true) }.foregroundStyle(Theme.text).frame(minHeight: 44).accessibilityIdentifier("panel-search-cancel")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(stickers) { sticker in
                        Button { if let item = StickerPack.attachment(sticker) { onSend(item) } } label: {
                            StickerThumb(sticker: sticker).frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain).accessibilityLabel(sticker.label).accessibilityHint("Sends it").accessibilityIdentifier("panel-found-sticker-\(sticker.id)")
                    }
                    ForEach(gifs, id: \.id) { gif in
                        Button { Task { await send(gif) } } label: {
                            GIFThumb(id: gif.id).frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel([gif.words, gif.frameText, gif.messageText].first { !$0.isEmpty }.map { "GIF, \($0)" } ?? "GIF").accessibilityHint("Sends it")
                        .accessibilityIdentifier("panel-found-gif-\(gif.id)")
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 88)
            .overlay {
                if stickers.isEmpty && gifs.isEmpty {
                    Text(query.isEmpty ? "Type to search." : "Nothing matches \u{2018}\(query)\u{2019}.").font(Theme.secondary).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("panel-search-empty")
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
        .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
        .task(id: "\(query)|\(tab.rawValue)") { gifs = tab == .gifs ? await store.myGIFs(matching: query.trimmingCharacters(in: .whitespacesAndNewlines)) : [] }
        .onAppear { focused = true }
    }

    private func send(_ gif: MyGif) async {
        guard let data = await store.myGIFData(gif.id), let made = try? GIF.attachment(data, name: "GIF.gif") else { return }
        await store.touchMyGIF(gif.id)
        onSend(made.0)
    }
}

/// What the GIFs and Stickers tabs show where the keyboard would be: a grid, one tap sends. Search and managing are the sheet's (the magnifier).
struct ComposerPanelContent: View {
    let tab: ComposerPanelTab
    let model: RichComposerModel
    let onSend: (OutgoingAttachment) -> Void
    var onManage: () -> Void = {}
    @Environment(ConversationStore.self) private var store
    @State private var gifs: [MyGif] = []
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            ComposerPanelTop(model: model) { model.beginSearch() }
            ScrollView {
                switch tab {
                case .gifs: gifGrid
                case .stickers: stickerGrid
                case .emoji: EmptyView()
                }
            }
        }
    }

    private var gifGrid: some View {
        Group {
            if gifs.isEmpty && loaded {
                Text("Save a GIF from a chat (touch and hold it) and it is here.")
                    .font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).padding(.horizontal, 40).padding(.top, 40)
                    .accessibilityIdentifier("panel-gifs-empty")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 80), spacing: 6), count: 3), spacing: 6) {
                ForEach(gifs, id: \.id) { gif in
                    let label = [gif.words, gif.frameText, gif.messageText].first { !$0.isEmpty }.map { "GIF, \($0)" } ?? "GIF"
                    Button { Task { await send(gif) } } label: {
                        GIFThumb(id: gif.id).aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label).accessibilityHint("Sends it")
                    .accessibilityIdentifier("panel-gif-\(gif.id)")
                }
            }
            .padding(12)
            Button(action: onManage) {
                Label("Add or manage GIFs", systemImage: "plus.circle").font(Theme.secondary).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("panel-manage")
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
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: height), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        host.view.backgroundColor = .clear
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
