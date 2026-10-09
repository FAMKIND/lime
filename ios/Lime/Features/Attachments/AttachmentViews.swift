import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: In a bubble

/// The attachments of one message, above its text: one picture, an album grid, and file cards.
struct AttachmentStack: View {
    let message: Message
    let isOwn: Bool
    @Environment(ConversationStore.self) private var store
    @Environment(\.chatConversationID) private var chatConversationID

    private var images: [AttachmentItem] { message.attachments.filter { $0.kind == .image } }
    private var others: [AttachmentItem] { message.attachments.filter { $0.kind != .image } }
    /// My own message still going up: its pictures, videos and voice messages show a progress ring.
    private var uploading: Bool { isOwn && message.state == .sending }

    var body: some View {
        VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
            if !images.isEmpty { album }
            ForEach(others) { item in
                switch item.kind {
                case .audio: VoiceBubble(item: item, isOwn: isOwn, uploading: uploading)
                case .video: VideoTile(item: item, isOwn: isOwn, uploading: uploading, messageID: message.id, conversationID: chatConversationID)
                default: FileCard(item: item, isOwn: isOwn, uploading: uploading) { if !item.removed { store.openedFile = item } }
                }
            }
        }
    }

    private func pictureLabel(_ item: AttachmentItem) -> String {
        let name = item.name.isEmpty ? "Photo" : item.name
        guard let phrase = store.downloadPhrase(item) else { return name }
        return item.removed ? "\(name), \(phrase)" : "\(name), tap to download, \(phrase)"
    }

    /// Opens the viewer; a picture that was not fetched by itself is fetched by the first tap.
    private func openPicture(_ index: Int) {
        let item = images[index]
        if !item.downloaded && !item.removed && !StorageGuard.shared.mayAutoDownload(item) && !store.downloading.contains(item.id) && AttachmentImages.shared.image(item.id) == nil {
            Task { _ = await store.image(for: item) }
            return
        }
        if item.removed { return }
        store.attachmentViewer = AttachmentViewerRequest(items: images, index: index, messageID: message.id, conversationID: chatConversationID)
    }

    @ViewBuilder
    private var album: some View {
        let width: CGFloat = 248
        if images.count == 1, let only = images.first {
            let aspect = min(max(only.aspect, 0.6), 1.7)
            ImageTile(item: only, uploading: uploading)
                .frame(width: width, height: width / aspect)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .mediaTap { openPicture(0) }
            .accessibilityLabel(pictureLabel(only))
            .accessibilityIdentifier("attachment-image-\(only.id)")
        } else {
            let shown = Array(images.prefix(4))
            let side = (width - 4) / 2
            LazyVGrid(columns: [GridItem(.fixed(side), spacing: 4), GridItem(.fixed(side), spacing: 4)], spacing: 4) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                    ImageTile(item: item, uploading: uploading)
                        .frame(width: side, height: side)
                        .overlay {
                            if index == 3, images.count > 4 {
                                Color.black.opacity(0.5)
                                Text("+\(images.count - 3)").font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .mediaTap { openPicture(index) }
                    .accessibilityLabel(pictureLabel(item))
                    .accessibilityIdentifier("attachment-image-\(item.id)")
                }
            }
            .frame(width: width)
        }
    }
}

/// Which pictures the full-screen viewer shows, and which one first.
struct AttachmentViewerRequest: Identifiable {
    let items: [AttachmentItem]
    let index: Int
    /// The message the pictures belong to (an album is one message): the viewer can react to it.
    var messageID: String?
    var conversationID: Conversation.ID?
    let id = UUID()
}

/// Presents the picture viewer and the file opener for a screen full of messages. They are presented from the screen
/// itself, not from a message row (a lazily built row is not a dependable place to present from).
struct AttachmentPresenting: ViewModifier {
    @Environment(ConversationStore.self) private var store

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: Binding(get: { store.attachmentViewer }, set: { store.attachmentViewer = $0 })) { request in
                AttachmentViewer(items: request.items, start: request.index, messageID: request.messageID, conversationID: request.conversationID)
            }
            .background(Color.clear.fullScreenCover(item: Binding(get: { store.openedFile }, set: { store.openedFile = $0 })) { item in
                FileOpener(item: item)
            })
            .background(Color.clear.fullScreenCover(item: Binding(get: { store.playingVideo }, set: { store.playingVideo = $0 })) { request in
                VideoPlayerScreen(request: request)
            })
    }
}

extension View {
    func attachmentPresenting() -> some View { modifier(AttachmentPresenting()) }
}

/// One picture: its tiny blurred preview straight away, then the real one once it is downloaded and decrypted.
struct ImageTile: View {
    let item: AttachmentItem
    var uploading = false
    @Environment(ConversationStore.self) private var store
    @State private var full: UIImage?
    @State private var failed = false
    /// Not fetched by itself (the settings, or a nearly full phone): a placeholder with its size, to tap.
    @State private var waiting = false

    var body: some View {
        ZStack {
            Theme.surface
            if let full {
                Image(uiImage: full).resizable().scaledToFill()
            } else if let thumb = UIImage(data: item.thumb) {
                Image(uiImage: thumb).resizable().scaledToFill().blur(radius: 8).clipped()
            }
            if item.removed {
                placeholder("photo.slash", "Media removed", detail: nil)
            } else if waiting && !store.downloading.contains(item.id) {
                placeholder("arrow.down.circle", "Tap to download", detail: AttachmentFormat.size(item.size))
            } else if (full == nil && !failed) || uploading {
                TransferRing(attachmentID: item.id, active: true, tint: .white).frame(width: 34, height: 34)
                    .padding(6).background(.black.opacity(0.4), in: Circle())
            }
            if failed {
                Image(systemName: "arrow.clockwise").font(.system(size: 20)).foregroundStyle(Theme.text)
                    .padding(10).background(.ultraThinMaterial, in: Circle())
            }
        }
        .contentShape(Rectangle())
        .task(id: "\(item.id)-\(item.downloaded)-\(item.removed)") { await load() }
        .accessibilityHidden(true)
    }

    private func placeholder(_ symbol: String, _ title: String, detail: String?) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 22))
            Text(title).font(Theme.secondary.weight(.semibold))
            if let detail { Text(detail).font(Theme.caption) }
            if !item.removed { AvailabilityText(item: item).font(Theme.caption) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("download-placeholder-\(item.id)")
    }

    private func load() async {
        failed = false
        waiting = false
        if let cached = AttachmentImages.shared.image(item.id) { full = cached; return }
        if item.removed { return }
        if !item.downloaded && !StorageGuard.shared.mayAutoDownload(item) { waiting = true; return }
        full = await store.image(for: item)
        failed = full == nil
    }
}

/// A file: its icon, name, and kind and size. Tapping it downloads (if needed) and opens it.
struct FileCard: View {
    @Environment(ConversationStore.self) private var store
    let item: AttachmentItem
    let isOwn: Bool
    var uploading = false
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 26)).frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name.isEmpty ? "File" : item.name).font(Theme.body).lineLimit(1).truncationMode(.middle)
                    Text(item.removed ? "Media removed" : item.detail).font(Theme.caption).foregroundStyle(isOwn ? Theme.ownBubbleInk.opacity(0.7) : Theme.textSecondary)
                    if !item.downloaded && !item.removed && !isOwn {
                        AvailabilityText(item: item).font(Theme.caption).foregroundStyle(isOwn ? Theme.ownBubbleInk.opacity(0.7) : Theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if uploading { TransferRing(attachmentID: item.id, active: true, tint: isOwn ? Theme.ownBubbleInk : Theme.text).frame(width: 24, height: 24) }
                else if !item.downloaded && !isOwn { Image(systemName: "arrow.down.circle").font(.system(size: 20)) }
            }
            .foregroundStyle(isOwn ? Theme.ownBubbleInk : Theme.text)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(width: 248, alignment: .leading)
            .background(isOwn ? Theme.ownBubble : Theme.bubbleOther, in: RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous).strokeBorder(isOwn ? Color.clear : Theme.bubbleEdge, lineWidth: 0.5))
        .mediaTap(open)
        .accessibilityLabel(["\(item.name), \(item.detail)", store.downloadPhrase(item).map { $0 == AttachmentFormat.size(item.size) ? "tap to download" : $0.replacingOccurrences(of: AttachmentFormat.size(item.size) + ", ", with: "") }].compactMap { $0 }.joined(separator: ", "))
        .accessibilityIdentifier("attachment-file-\(item.id)")
    }

    private var symbol: String {
        let type = UTType(mimeType: item.mime)
        if type?.conforms(to: .pdf) == true { return "doc.richtext" }
        if type?.conforms(to: .spreadsheet) == true { return "tablecells" }
        if type?.conforms(to: .presentation) == true { return "rectangle.on.rectangle" }
        if type?.conforms(to: .archive) == true { return "doc.zipper" }
        if item.kind == .audio { return "waveform" }
        if item.kind == .video { return "film" }
        return "doc"
    }
}

// MARK: Opening

/// Downloads a file if needed, then shows it with Quick Look (which also offers Share, Print and Save to Files).
struct FileOpener: View {
    let item: AttachmentItem
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var url: URL?
    @State private var failed = false

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            if let url {
                QuickLookView(url: url, onDone: { dismiss() }).ignoresSafeArea()
            } else if failed {
                VStack(spacing: 16) {
                    Text("The file couldn't be downloaded. Check your connection and try again.").font(Theme.body)
                        .foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).padding(.horizontal, 32)
                        .accessibilityIdentifier("attachment-file-failed")
                    Button("Close") { dismiss() }.font(Theme.title)
                }
            } else {
                VStack(spacing: 12) { ProgressView(); Text("Downloading…").font(Theme.secondary).foregroundStyle(Theme.textSecondary) }
            }
        }
        .task {
            url = await store.fileURL(for: item)
            failed = url == nil
        }
    }
}

struct QuickLookView: UIViewControllerRepresentable {
    let url: URL
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.navigationItem.rightBarButtonItem = nil
        let nav = UINavigationController(rootViewController: controller)
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { _ in context.coordinator.done() })
        return nav
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(url: url, onDone: onDone) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        let onDone: () -> Void
        init(url: URL, onDone: @escaping () -> Void) { self.url = url; self.onDone = onDone }
        func done() { onDone() }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
    }
}

/// Full-screen pictures: swipe between them, pinch to zoom, share, or save to Photos (only when asked).
struct AttachmentViewer: View {
    let items: [AttachmentItem]
    @State var start: Int
    /// The message these pictures belong to: reactions go to the message (an album is one message).
    var messageID: String?
    var conversationID: Conversation.ID?
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var saved = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $page) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ZoomablePicture(item: item).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Close").accessibilityIdentifier("attachment-viewer-close")
                Spacer()
                if items.count > 1 {
                    Text("\(page + 1) of \(items.count)").font(Theme.secondary.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6).background(.ultraThinMaterial, in: Capsule())
                        .accessibilityIdentifier("attachment-viewer-count")
                }
                Spacer()
                ViewerReactButton(messageID: messageID, conversationID: conversationID)
                Button { Task { await save() } } label: {
                    Image(systemName: saved ? "checkmark" : "square.and.arrow.down").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(saved ? "Saved to Photos" : "Save to Photos").accessibilityIdentifier("attachment-save")
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .onAppear { page = min(max(start, 0), items.count - 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("attachment-viewer")
    }

    private func save() async {
        guard items.indices.contains(page), let image = await store.image(for: items[page]) else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        saved = true
        try? await Task.sleep(for: .seconds(2))
        saved = false
    }
}

private struct ZoomablePicture: View {
    let item: AttachmentItem
    @Environment(ConversationStore.self) private var store
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .scaleEffect(scale)
                    .gesture(MagnifyGesture().onChanged { scale = min(max(base * $0.magnification, 1), 5) }.onEnded { _ in base = scale; if scale < 1.05 { scale = 1; base = 1 } })
                    .onTapGesture(count: 2) { withAnimation { scale = scale > 1 ? 1 : 2.5; base = scale } }
            } else if let thumb = UIImage(data: item.thumb) {
                Image(uiImage: thumb).resizable().scaledToFit().blur(radius: 10)
                ProgressView().tint(.white)
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: item.id) { image = await store.image(for: item) }
    }
}

// MARK: Choosing

/// The system photo picker for up to ten pictures: Lime receives only the ones chosen, with no library permission.
struct AlbumPicker: UIViewControllerRepresentable {
    let limit: Int
    let onPick: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = limit
        configuration.selection = .ordered
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private nonisolated(unsafe) let onPick: ([UIImage]) -> Void
        private nonisolated(unsafe) let onCancel: () -> Void
        init(onPick: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) { self.onPick = onPick; self.onCancel = onCancel }

        nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else { DispatchQueue.main.async { self.onCancel() }; return }
            nonisolated(unsafe) var images = [UIImage?](repeating: nil, count: results.count)
            let group = DispatchGroup()
            let lock = NSLock()
            for (index, result) in results.enumerated() where result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    lock.lock(); images[index] = object as? UIImage; lock.unlock()
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                let chosen = images.compactMap { $0 }
                if chosen.isEmpty { self.onCancel() } else { self.onPick(chosen) }
            }
        }
    }
}

/// The document picker: any file, copied so it can be read after the picker closes.
struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private nonisolated(unsafe) let onPick: ([URL]) -> Void
        private nonisolated(unsafe) let onCancel: () -> Void
        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) { self.onPick = onPick; self.onCancel = onCancel }
        nonisolated func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { DispatchQueue.main.async { self.onPick(urls) } }
        nonisolated func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { DispatchQueue.main.async { self.onCancel() } }
    }
}

// MARK: In the composer

/// The pictures and files waiting to be sent, with a way to take each one back out.
struct DraftStrip: View {
    let drafts: [DraftAttachment]
    let remove: (DraftAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(drafts) { draft in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let preview = draft.preview {
                                Image(uiImage: preview).resizable().scaledToFill()
                            } else {
                                ZStack {
                                    Theme.surface
                                    VStack(spacing: 4) {
                                        Image(systemName: "doc").font(.system(size: 22))
                                        Text(draft.outgoing.name).font(Theme.caption).lineLimit(1).truncationMode(.middle).padding(.horizontal, 4)
                                    }
                                    .foregroundStyle(Theme.text)
                                }
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Button { remove(draft) } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 20)).symbolRenderingMode(.palette).foregroundStyle(.white, Color.black.opacity(0.6))
                        }
                        .offset(x: 6, y: -6)
                        .accessibilityLabel("Remove").accessibilityIdentifier("draft-remove")
                    }
                    .padding(.top, 6).padding(.trailing, 6)
                }
            }
            .padding(.horizontal, 6)
        }
        .accessibilityIdentifier("draft-strip")
    }
}

// MARK: Taps and long-presses on media

extension EnvironmentValues {
    /// The long-press that opens a message's actions menu (a photo, an album, a video, a voice message or a file card is part of the message).
    @Entry var mediaLongPress: MediaLongPress? = nil
    /// Select mode: media do not react to taps (the row toggles instead).
    @Entry var mediaSelecting = false
    /// The conversation the visible messages are in (so the picture viewer can react to the message).
    @Entry var chatConversationID: Conversation.ID? = nil
}

/// The action a long-press on media runs, comparable (by message) so the environment does not refresh needlessly.
struct MediaLongPress: Equatable {
    let messageID: String
    let action: () -> Void
    static func == (lhs: MediaLongPress, rhs: MediaLongPress) -> Bool { lhs.messageID == rhs.messageID }
}

/// A tap that opens the media and a long-press that opens the message's actions, like the text bubbles. (A plain `Button` would swallow
/// the long-press, so media use a tap gesture; it still reads as a button to VoiceOver and tests.)
struct MediaTap: ViewModifier {
    let action: () -> Void
    @Environment(\.mediaLongPress) private var longPress
    @Environment(\.mediaSelecting) private var selecting

    func body(content: Content) -> some View {
        if selecting {
            content.accessibilityElement(children: .ignore)
        } else {
            content
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
                .onLongPressGesture(minimumDuration: 0.4) { longPress?.action() }
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
        }
    }
}

extension View {
    func mediaTap(_ action: @escaping () -> Void) -> some View { modifier(MediaTap(action: action)) }
}

/// A react button in a full-screen viewer (pictures and video): the six quick emoji, applied to the message the media belong to
/// (an album is one message). Hidden when the viewer was not opened from a message.
struct ViewerReactButton: View {
    let messageID: String?
    let conversationID: Conversation.ID?
    @Environment(ConversationStore.self) private var store

    private var message: Message? {
        guard let messageID, let conversationID, let conversation = store.conversation(conversationID) else { return nil }
        return conversation.messages.first { $0.id == messageID }
            ?? store.threads.values.lazy.flatMap { $0 }.first { $0.id == messageID }
    }

    @State private var open = false
    @State private var picking = false

    var body: some View {
        if let message, let conversationID {
            Button { open.toggle() } label: {
                Image(systemName: "face.smiling").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("React").accessibilityIdentifier("attachment-react")
            // The tapback bar: the six quick emoji and "+", in a row (the same as the long-press menu in the chat).
            .overlay(alignment: .topTrailing) {
                if open {
                    HStack(spacing: 2) {
                        ForEach(ConversationStore.quickReactions, id: \.self) { emoji in
                            let mine = message.reactions.first { $0.emoji == emoji }?.mine ?? false
                            Button {
                                open = false
                                Task { await store.toggleReaction(emoji, on: message, in: conversationID) }
                            } label: {
                                Text(emoji).font(.system(size: 26)).frame(width: 40, height: 40)
                                    .background(mine ? Color.white.opacity(0.25) : Color.clear, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(emoji).accessibilityIdentifier("viewer-react-\(emoji)")
                        }
                        Button { picking = true } label: {
                            Image(systemName: "plus").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 36, height: 36).background(Color.white.opacity(0.2), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("More emoji").accessibilityIdentifier("viewer-react-more")
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .fixedSize()
                    .offset(y: 52)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("viewer-reaction-bar")
                }
            }
            .sheet(isPresented: $picking) {
                EmojiPickerSheet { emoji in
                    picking = false
                    open = false
                    if let emoji { Task { await store.toggleReaction(emoji, on: message, in: conversationID) } }
                }
            }
        }
    }
}

/// "Available until Oct 30" under a file that is not on this phone yet (the server keeps it for 30 days, or an hour after everyone
/// has fetched it), or "No longer available".
struct AvailabilityText: View {
    let item: AttachmentItem
    @Environment(ConversationStore.self) private var store
    @State private var state: Date??

    // Always a Text (even an empty one), so the task below has a view to run on.
    private var words: String {
        switch state {
        case .none: ""
        case .some(.none): "No longer available"
        case .some(.some(let date)): "Available until \(date.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }

    var body: some View {
        Text(words)
            .accessibilityIdentifier("available-until-\(item.id)")
            .task(id: item.id) { state = await store.availableUntil(item) }
    }
}
