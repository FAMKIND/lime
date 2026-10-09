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
                case .video: VideoTile(item: item, isOwn: isOwn, uploading: uploading)
                default: FileCard(item: item, isOwn: isOwn, uploading: uploading) { store.openedFile = item }
                }
            }
        }
    }

    @ViewBuilder
    private var album: some View {
        let width: CGFloat = 248
        if images.count == 1, let only = images.first {
            let aspect = min(max(only.aspect, 0.6), 1.7)
            Button { store.attachmentViewer = AttachmentViewerRequest(items: images, index: 0) } label: {
                ImageTile(item: only, uploading: uploading)
                    .frame(width: width, height: width / aspect)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(only.name.isEmpty ? "Photo" : only.name)
            .accessibilityIdentifier("attachment-image-\(only.id)")
        } else {
            let shown = Array(images.prefix(4))
            let side = (width - 4) / 2
            LazyVGrid(columns: [GridItem(.fixed(side), spacing: 4), GridItem(.fixed(side), spacing: 4)], spacing: 4) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                    Button { store.attachmentViewer = AttachmentViewerRequest(items: images, index: index) } label: {
                        ImageTile(item: item, uploading: uploading)
                            .frame(width: side, height: side)
                            .overlay {
                                if index == 3, images.count > 4 {
                                    Color.black.opacity(0.5)
                                    Text("+\(images.count - 3)").font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.name.isEmpty ? "Photo" : item.name)
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
    let id = UUID()
}

/// Presents the picture viewer and the file opener for a screen full of messages. They are presented from the screen
/// itself, not from a message row (a lazily built row is not a dependable place to present from).
struct AttachmentPresenting: ViewModifier {
    @Environment(ConversationStore.self) private var store

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: Binding(get: { store.attachmentViewer }, set: { store.attachmentViewer = $0 })) { request in
                AttachmentViewer(items: request.items, start: request.index)
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

    var body: some View {
        ZStack {
            Theme.surface
            if let full {
                Image(uiImage: full).resizable().scaledToFill()
            } else if let thumb = UIImage(data: item.thumb) {
                Image(uiImage: thumb).resizable().scaledToFill().blur(radius: 8).clipped()
            }
            if (full == nil && !failed) || uploading {
                TransferRing(attachmentID: item.id, active: true, tint: .white).frame(width: 34, height: 34)
                    .padding(6).background(.black.opacity(0.4), in: Circle())
            }
            if failed {
                Image(systemName: "arrow.clockwise").font(.system(size: 20)).foregroundStyle(Theme.text)
                    .padding(10).background(.ultraThinMaterial, in: Circle())
            }
        }
        .contentShape(Rectangle())
        .task(id: item.id) { await load() }
        .accessibilityHidden(true)
    }

    private func load() async {
        failed = false
        if let cached = AttachmentImages.shared.image(item.id) { full = cached; return }
        full = await store.image(for: item)
        failed = full == nil
    }
}

/// A file: its icon, name, and kind and size. Tapping it downloads (if needed) and opens it.
struct FileCard: View {
    let item: AttachmentItem
    let isOwn: Bool
    var uploading = false
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 26)).frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name.isEmpty ? "File" : item.name).font(Theme.body).lineLimit(1).truncationMode(.middle)
                    Text(item.detail).font(Theme.caption).foregroundStyle(isOwn ? Theme.ownBubbleInk.opacity(0.7) : Theme.textSecondary)
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name), \(item.detail)")
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
