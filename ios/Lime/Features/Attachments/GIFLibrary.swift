import PhotosUI
import SwiftUI
import UIKit
import Vision

/// LIME-207: My GIFs. The library itself lives in LimeCore's encrypted store (its rows, words and search); this is the app's side: saving, the words read from a
/// GIF's pictures with Apple's on-device text recognition, the GIF button's sheet and Settings' count.

/// Reads the text in a few frames of a GIF on this phone (Vision, nothing leaves the phone).
enum GIFTextReader {
    static func read(_ data: Data) async -> String {
        await Task.detached(priority: .utility) { () -> String in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return "" }
            let count = CGImageSourceGetCount(source)
            guard count > 0 else { return "" }
            // The first, a few in the middle and the last: enough to catch a caption, cheap enough to do at once.
            let wanted = Set([0, count / 4, count / 2, (count * 3) / 4, count - 1]).sorted()
            var seen: [String] = []
            for index in wanted {
                guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .fast
                request.usesLanguageCorrection = true
                try? VNImageRequestHandler(cgImage: frame, options: [:]).perform([request])
                for observation in request.results ?? [] {
                    if let text = observation.topCandidates(1).first?.string, !seen.contains(text) { seen.append(text) }
                }
            }
            return seen.joined(separator: " ")
        }.value
    }
}

extension ConversationStore {
    enum SavedGIF: Equatable { case saved(String), full, failed }

    /// Saves a GIF to my GIFs and, in the background, reads the words in its pictures for search. `.full` when the library has no room.
    @discardableResult
    func saveMyGIF(_ data: Data, words: String = "", messageText: String = "") async -> SavedGIF {
        let size = GIF.firstFrame(data).map { (UInt32($0.size.width * $0.scale), UInt32($0.size.height * $0.scale)) }
        #if DEBUG
        if isDemo {
            let id = demoMyGIFs.first { $0.data == data }?.gif.id ?? UUID().uuidString
            demoMyGIFs.removeAll { $0.gif.id == id }
            demoMyGIFs.insert((MyGif(id: id, words: words, messageText: messageText, frameText: "", width: size?.0, height: size?.1, size: UInt64(data.count), addedAt: 0, lastUsed: Int64(Date().timeIntervalSince1970 * 1000)), data), at: 0)
            myGIFRevision += 1
            return .saved(id)
        }
        #endif
        guard let core else { return .failed }
        let id: String? = try? await Task.detached(priority: .userInitiated) {
            try core.addMyGif(bytes: data, words: words, messageText: messageText, frameText: "", width: size?.0, height: size?.1)
        }.value
        guard let id else {
            let usage = await myGIFsUsage()
            return usage.map { $0.count >= $0.maxCount || $0.bytes + UInt64(data.count) > $0.maxBytes } == true ? .full : .failed
        }
        myGIFRevision += 1
        Task { [weak self] in
            let text = await GIFTextReader.read(data)
            guard !text.isEmpty, let core = self?.core else { return }
            try? await Task.detached { try core.setMyGifFrameText(id: id, text: text) }.value
            self?.myGIFRevision += 1
        }
        return .saved(id)
    }

    /// My GIFs, recent first, or the ones that match `query` (my words, the message it came with, text in its pictures).
    func myGIFs(matching query: String = "") async -> [MyGif] {
        #if DEBUG
        if isDemo {
            let q = query.lowercased().split(separator: " ").map(String.init)
            return demoMyGIFs.map(\.gif).filter { gif in q.allSatisfy { "\(gif.words) \(gif.messageText) \(gif.frameText)".lowercased().contains($0) } }
        }
        #endif
        guard let core else { return [] }
        return (try? await Task.detached(priority: .userInitiated) { try core.searchMyGifs(query: query, limit: 200) }.value) ?? []
    }

    func myGIFData(_ id: String) async -> Data? {
        #if DEBUG
        if isDemo { return demoMyGIFs.first { $0.gif.id == id }?.data }
        #endif
        guard let core else { return nil }
        return (try? await Task.detached { try core.myGifBytes(id: id) }.value) ?? nil
    }

    func removeMyGIF(_ id: String) async {
        #if DEBUG
        if isDemo { demoMyGIFs.removeAll { $0.gif.id == id }; myGIFRevision += 1; return }
        #endif
        guard let core else { return }
        try? await Task.detached { try core.removeMyGif(id: id) }.value
        myGIFRevision += 1
    }

    func setMyGIFWords(_ id: String, _ words: String) async {
        #if DEBUG
        if isDemo, let i = demoMyGIFs.firstIndex(where: { $0.gif.id == id }) { demoMyGIFs[i].gif.words = words; myGIFRevision += 1; return }
        #endif
        guard let core else { return }
        try? await Task.detached { try core.setMyGifWords(id: id, words: words) }.value
        myGIFRevision += 1
    }

    func touchMyGIF(_ id: String) async {
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core else { return }
        try? await Task.detached { try core.touchMyGif(id: id) }.value
    }

    func myGIFsUsage() async -> MyGifUsage? {
        #if DEBUG
        if isDemo { return MyGifUsage(count: UInt32(demoMyGIFs.count), bytes: demoMyGIFs.reduce(0) { $0 + UInt64($1.data.count) }, maxCount: 500, maxBytes: 500 * 1024 * 1024) }
        #endif
        guard let core else { return nil }
        return try? await Task.detached { try core.myGifsUsage() }.value
    }

    func removeAllMyGIFs() async {
        #if DEBUG
        if isDemo { demoMyGIFs = []; myGIFRevision += 1; return }
        #endif
        guard let core else { return }
        try? await Task.detached { try core.removeAllMyGifs() }.value
        myGIFRevision += 1
    }
}

// MARK: The GIF button's sheet

/// My GIFs as a grid with a search field (the GIF button in a chat): tap one and it is sent; long-press for Add words or Remove; + adds from Photos or Files.
struct MyGIFsSheet: View {
    let onSend: (OutgoingAttachment, String) -> Void
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var gifs: [MyGif] = []
    @State private var loaded = false
    @State private var adding = false
    @State private var choosing = false
    @State private var wordsFor: MyGif?
    @State private var wordsText = ""
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                    TextField("Search my GIFs", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                        .accessibilityIdentifier("gif-search")
                }
                .padding(.horizontal, 14).frame(minHeight: 44).background(Theme.surface, in: Capsule()).padding(.horizontal, 16).padding(.top, 8)
                if let notice { Text(notice).font(Theme.caption).foregroundStyle(Theme.textSecondary).padding(.top, 8).accessibilityIdentifier("gif-notice") }
                ScrollView {
                    if gifs.isEmpty && loaded {
                        Text(query.isEmpty ? "Save a GIF from a chat (touch and hold it), or tap + to add one." : "No GIFs match “\(query)”.")
                            .font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).padding(.horizontal, 40).padding(.top, 50)
                            .accessibilityIdentifier("gif-empty")
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 90), spacing: 6), count: 3), spacing: 6) {
                        ForEach(gifs, id: \.id) { gif in cell(gif) }
                    }
                    .padding(16)
                }
            }
            .background(Theme.canvas)
            .navigationTitle("My GIFs").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.accessibilityIdentifier("gif-close") }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { adding = true } label: { Label("From Photos", systemImage: "photo.on.rectangle") }.accessibilityIdentifier("gif-add-photos")
                        Button { choosing = true } label: { Label("From Files", systemImage: "folder") }.accessibilityIdentifier("gif-add-files")
                    } label: { Image(systemName: "plus").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Add a GIF").accessibilityIdentifier("gif-add")
                }
            }
        }
        .presentationDetents([.large])
        .task(id: "\(query)|\(store.myGIFRevision)") { gifs = await store.myGIFs(matching: query); loaded = true }
        .fullScreenCover(isPresented: $adding) {
            MediaLibraryPicker(limit: 10, keepsGIFs: true, onPick: { _, urls in adding = false; Task { await add(urls: urls) } }, onCancel: { adding = false }).ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $choosing) {
            DocumentPicker(onPick: { urls in choosing = false; Task { await add(urls: urls) } }, onCancel: { choosing = false }).ignoresSafeArea()
        }
        .alert("Words for this GIF", isPresented: Binding(get: { wordsFor != nil }, set: { if !$0 { wordsFor = nil } })) {
            TextField("birthday, cake", text: $wordsText).accessibilityIdentifier("gif-words-field")
            Button("Save") { if let gif = wordsFor { Task { await store.setMyGIFWords(gif.id, wordsText) } } }.accessibilityIdentifier("gif-words-save")
            Button("Cancel", role: .cancel) {}
        } message: { Text("They help you find it when you search.") }
    }

    private func cell(_ gif: MyGif) -> some View {
        let label = [gif.words, gif.frameText, gif.messageText].first { !$0.isEmpty }.map { "GIF, \($0)" } ?? "GIF"
        return Button { Task { await send(gif) } } label: {
            GIFThumb(id: gif.id)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label).accessibilityHint("Sends it")
        .accessibilityIdentifier("gif-cell-\(gif.id)")
        .contextMenu {
            Button { wordsText = gif.words; wordsFor = gif } label: { Label("Add words", systemImage: "text.badge.plus") }.accessibilityIdentifier("gif-menu-words")
            Button(role: .destructive) { Task { await store.removeMyGIF(gif.id) } } label: { Label("Remove", systemImage: "trash") }.accessibilityIdentifier("gif-menu-remove")
        }
        .accessibilityAction(named: "Add words") { wordsText = gif.words; wordsFor = gif }
        .accessibilityAction(named: "Remove") { Task { await store.removeMyGIF(gif.id) } }
    }

    private func send(_ gif: MyGif) async {
        guard let data = await store.myGIFData(gif.id), let made = try? GIF.attachment(data, name: "GIF.gif") else { notice = GIF.tooBigMessage; return }
        await store.touchMyGIF(gif.id)
        dismiss()
        onSend(made.0, "")
    }

    private func add(urls: [URL]) async {
        notice = nil
        for url in urls {
            defer { try? FileManager.default.removeItem(at: url) }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), GIF.isGIF(data) else { notice = "That isn’t a GIF."; continue }
            guard data.count <= GIF.maxBytes, GIF.frameCount(data) <= GIF.maxFrames else { notice = GIF.tooBigMessage; continue }
            if await store.saveMyGIF(data) == .full { notice = "My GIFs is full (500 GIFs or 500 MB). Remove some to add more." }
        }
    }
}

/// A still frame of a saved GIF (the grid does not animate: it follows Reduce Motion and stays light).
private struct GIFThumb: View {
    let id: String
    @Environment(ConversationStore.self) private var store
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            Theme.surface
            if let image { Image(uiImage: image).resizable().scaledToFill() }
        }
        .task(id: id) {
            if let data = await store.myGIFData(id) { image = GIF.firstFrame(data) }
        }
        .accessibilityHidden(true)
    }
}

// MARK: Settings

/// Settings → My GIFs: how many, how much space, and Remove all.
struct MyGIFsSettingsScreen: View {
    @Environment(ConversationStore.self) private var store
    @State private var usage: MyGifUsage?
    @State private var confirming = false

    var body: some View {
        SettingsPage(title: "My GIFs") {
            SettingsCard {
                HStack {
                    Text("GIFs").font(Theme.body).foregroundStyle(Theme.text)
                    Spacer()
                    Text("\(usage?.count ?? 0)").font(Theme.secondary).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("my-gifs-count")
                }
                .padding(.horizontal, 18).frame(minHeight: 58)
                Divider().overlay(Theme.hairline).padding(.leading, 18)
                HStack {
                    Text("Space used").font(Theme.body).foregroundStyle(Theme.text)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(usage?.bytes ?? 0), countStyle: .file)).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("my-gifs-space")
                }
                .padding(.horizontal, 18).frame(minHeight: 58)
            }
            SettingsCard {
                Button { confirming = true } label: { SettingsRowLabel(symbol: "trash", title: "Remove all GIFs", showsDivider: false, destructive: true) }
                    .buttonStyle(.plain).disabled((usage?.count ?? 0) == 0).accessibilityIdentifier("my-gifs-remove-all")
            }
            SettingsFootnote(text: "GIFs you send are saved here automatically, and you can save any GIF in a chat (touch and hold it). They stay on this iPhone, up to 500 GIFs or 500 MB, and are never sent anywhere.")
        }
        .task(id: store.myGIFRevision) { usage = await store.myGIFsUsage() }
        .confirmSheet("Remove all your GIFs?", isPresented: $confirming) {
            Button("Remove all", role: .destructive) { Task { await store.removeAllMyGIFs() } }.accessibilityIdentifier("my-gifs-remove-all-confirm")
            Button("Cancel", role: .cancel) {}
        } message: { Text("They are deleted from this iPhone. GIFs already sent stay in their chats.") }
    }
}
