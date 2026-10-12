import AVFoundation
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: What the sheet offers

/// A photo or video from the library, shown as a thumbnail in the add sheet's strip.
struct RecentItem: Identifiable, Equatable {
    let id: String
    let isVideo: Bool
    let duration: TimeInterval
    /// `nil` in the demo, where the picture is drawn instead.
    var asset: PHAsset?
    var demoColor: Color?
    static func == (a: RecentItem, b: RecentItem) -> Bool { a.id == b.id }
}

/// The most recent photos and videos for the add sheet (LIME-127). Reading the library needs permission, asked only when the sheet
/// first opens; with limited access only the allowed items show (and "Manage" changes them); when it is denied the strip is hidden.
@Observable @MainActor
final class RecentMedia {
    enum Access { case unknown, granted, limited, denied }

    private(set) var access: Access = .unknown
    private(set) var items: [RecentItem] = []
    private(set) var thumbnails: [String: UIImage] = [:]
    private let manager = PHCachingImageManager()
    static let count = 20

    /// `demo`: made-up items (or none when `denied`), so the UI tests need no library and no permission prompt.
    func load(demo: String?) async {
        if let demo {
            if demo == "denied" { access = .denied; items = []; return }
            access = demo == "limited" ? .limited : .granted
            let colors: [Color] = [.orange, .teal, .pink, .indigo, .mint, .brown]
            items = colors.enumerated().map { RecentItem(id: "demo-\($0.offset)", isVideo: $0.offset == 3, duration: 12, asset: nil, demoColor: $0.element) }
            return
        }
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        switch status {
        case .authorized: access = .granted
        case .limited: access = .limited
        default: access = .denied; items = []; return
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        options.fetchLimit = Self.count
        let result = PHAsset.fetchAssets(with: options)
        var found: [RecentItem] = []
        result.enumerateObjects { asset, _, _ in
            found.append(RecentItem(id: asset.localIdentifier, isVideo: asset.mediaType == .video, duration: asset.duration, asset: asset))
        }
        items = found
    }

    func thumbnail(for item: RecentItem) async -> UIImage? {
        if let cached = thumbnails[item.id] { return cached }
        guard let asset = item.asset else { return nil }
        let size = CGSize(width: 240, height: 240)
        let image: UIImage? = await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
        if let image { thumbnails[item.id] = image }
        return image
    }

    /// The chosen items as pictures and video files (the video copied to a temporary file the pipeline then removes).
    func resolve(_ chosen: [RecentItem]) async -> (images: [UIImage], videos: [URL]) {
        var images: [UIImage] = []
        var videos: [URL] = []
        for item in chosen {
            guard let asset = item.asset else {
                if item.isVideo { videos.append(FileManager.default.temporaryDirectory.appendingPathComponent("lime-demo-\(UUID().uuidString).mov")) }
                else if let color = item.demoColor { images.append(Self.solid(UIColor(color))) }
                continue
            }
            if item.isVideo {
                if let url = await Self.exportVideo(asset) { videos.append(url) }
            } else if let image = await Self.fullImage(asset) {
                images.append(image)
            }
        }
        return (images, videos)
    }

    private static func solid(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600)).image { context in
            color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
        }
    }

    private static func fullImage(_ asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.version = .current
            PHImageManager.default().requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private static func exportVideo(_ asset: PHAsset) async -> URL? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .fullSizeVideo }) ?? resources.first(where: { $0.type == .video }) else { return nil }
        let ext = URL(fileURLWithPath: resource.originalFilename).pathExtension
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lime-pick-\(UUID().uuidString).\(ext.isEmpty ? "mov" : ext)")
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
                continuation.resume(returning: error == nil ? url : nil)
            }
        }
    }

    /// Limited access: the system's own screen to choose which photos Lime can see.
    func manageLimited() {
        guard let top = Self.topViewController() else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top) { [weak self] _ in
            Task { @MainActor in await self?.load(demo: nil) }
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}

// MARK: The sheet

/// "Add to your message": one compact sheet. A strip with a Camera tile and the latest photos and videos (tap to select, then Add),
/// a Photos button for the whole library, and a Files row.
struct AddToMessageSheet: View {
    @Environment(ConversationStore.self) private var store
    let media: RecentMedia
    /// How many more things this message can hold.
    let room: Int
    let onClose: () -> Void
    let onCamera: () -> Void
    let onPhotos: () -> Void
    let onFiles: () -> Void
    let onAdd: ([RecentItem]) -> Void

    @State private var selected: [String] = []
    @State private var height: CGFloat = 360
    private static let tile: CGFloat = 96

    private var showsCamera: Bool {
        #if DEBUG
        if store.isDemo { return true }
        #endif
        return CameraPicker.isAvailable
    }

    private func manage() {
        #if DEBUG
        if store.isDemo { return }
        #endif
        media.manageLimited()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            strip
            if media.access == .limited {
                Button("Manage") { manage() }
                    .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    .padding(.top, 10).accessibilityIdentifier("add-manage")
            }
            if !selected.isEmpty {
                Button { onAdd(media.items.filter { selected.contains($0.id) }) } label: {
                    Text("Add (\(selected.count))").font(Theme.title).foregroundStyle(Theme.accentInk)
                        .frame(maxWidth: .infinity, minHeight: 52).background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain).padding(.horizontal, 20).padding(.top, 14)
                .accessibilityIdentifier("add-selected")
            }
            Button(action: onFiles) {
                HStack(spacing: 14) {
                    Image(systemName: "doc").font(.system(size: 20)).frame(width: 28)
                    Text("Files").font(Theme.body)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                }
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 18).frame(minHeight: 56)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain).padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
            .accessibilityIdentifier("composer-files")
        }
        .background(GeometryReader { geo in Color.clear.preference(key: AddSheetHeightKey.self, value: geo.size.height) })
        .onPreferenceChange(AddSheetHeightKey.self) { height = $0 }
        .presentationDetents([.height(height + 8)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.canvas)
        .task {
            #if DEBUG
            // `-lime-demo-photos real` reads the simulator's own library (with the permission prompt) in the demo chat.
            let argument = ProcessInfo.processInfo.arguments.drop { $0 != "-lime-demo-photos" }.dropFirst().first ?? "granted"
            let demo: String? = store.isDemo && argument != "real" ? argument : nil
            #else
            let demo: String? = nil
            #endif
            await media.load(demo: demo)
        }
    }

    private var header: some View {
        ZStack {
            Text("Add to your message").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.75).padding(.horizontal, 96)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                        .frame(width: 44, height: 44).limeGlass(in: Circle())
                }
                .accessibilityLabel("Close").accessibilityIdentifier("add-close")
                Spacer()
                Button(action: onPhotos) {
                    Text("Photos").font(Theme.body.weight(.semibold)).foregroundStyle(Theme.text)
                        .padding(.horizontal, 16).frame(height: 44).limeGlass(in: Capsule())
                }
                .accessibilityIdentifier("composer-photo-library")
            }
        }
        .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 14)
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if showsCamera {
                    Button(action: onCamera) {
                        VStack(spacing: 6) {
                            Image(systemName: "camera").font(.system(size: 26))
                            Text("Camera").font(Theme.secondary)
                        }
                        .foregroundStyle(Theme.text)
                        .frame(width: Self.tile, height: Self.tile)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("composer-take-photo")
                }
                ForEach(Array(media.items.enumerated()), id: \.element.id) { index, item in
                    RecentTile(media: media, item: item, side: Self.tile, isSelected: selected.contains(item.id)) {
                        if let at = selected.firstIndex(of: item.id) { selected.remove(at: at) }
                        else if selected.count < room { selected.append(item.id) }
                    }
                    .accessibilityIdentifier("add-recent-\(index)")
                }
            }
            .padding(.horizontal, 20)
        }
        .accessibilityIdentifier("add-strip")
    }
}

private struct RecentTile: View {
    let media: RecentMedia
    let item: RecentItem
    let side: CGFloat
    let isSelected: Bool
    let toggle: () -> Void
    @State private var image: UIImage?

    var body: some View {
        Button(action: toggle) {
            ZStack {
                Rectangle().fill(item.demoColor ?? Theme.surface)
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if item.isVideo {
                    Label(Self.clock(item.duration), systemImage: "video.fill").font(.caption2.weight(.semibold)).foregroundStyle(.white)
                        .shadow(radius: 2).padding(6)
                }
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(isSelected ? Theme.accent : Color.white.opacity(0.9))
                    .shadow(radius: 2).padding(6)
            }
            .overlay { if isSelected { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.accent, lineWidth: 3) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.isVideo ? "Video, \(Self.clock(item.duration))" : "Photo")
        .accessibilityValue(isSelected ? "Selected" : "")
        .task(id: item.id) { image = await media.thumbnail(for: item) }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct AddSheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: Pickers

/// The system picker for photos and videos together, several at once. Lime receives only what is chosen, with no library permission.
struct MediaLibraryPicker: UIViewControllerRepresentable {
    let limit: Int
    let onPick: ([UIImage], [URL]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = limit
        configuration.selection = .ordered
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private nonisolated(unsafe) let onPick: ([UIImage], [URL]) -> Void
        private nonisolated(unsafe) let onCancel: () -> Void
        init(onPick: @escaping ([UIImage], [URL]) -> Void, onCancel: @escaping () -> Void) { self.onPick = onPick; self.onCancel = onCancel }

        nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else { DispatchQueue.main.async { self.onCancel() }; return }
            nonisolated(unsafe) var images = [UIImage?](repeating: nil, count: results.count)
            nonisolated(unsafe) var videos = [URL?](repeating: nil, count: results.count)
            let group = DispatchGroup()
            let lock = NSLock()
            for (index, result) in results.enumerated() {
                let provider = result.itemProvider
                if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    group.enter()
                    provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                        // The picker's own copy is deleted when it returns, so it is copied out.
                        if let url {
                            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("lime-pick-\(UUID().uuidString).\(url.pathExtension)")
                            if (try? FileManager.default.copyItem(at: url, to: copy)) != nil { lock.lock(); videos[index] = copy; lock.unlock() }
                        }
                        group.leave()
                    }
                } else if provider.canLoadObject(ofClass: UIImage.self) {
                    group.enter()
                    provider.loadObject(ofClass: UIImage.self) { object, _ in
                        lock.lock(); images[index] = object as? UIImage; lock.unlock()
                        group.leave()
                    }
                }
            }
            group.notify(queue: .main) {
                let pictures = images.compactMap { $0 }, clips = videos.compactMap { $0 }
                if pictures.isEmpty && clips.isEmpty { self.onCancel() } else { self.onPick(pictures, clips) }
            }
        }
    }
}

/// The camera, for a photo or a video (up to 3 minutes) in one capture screen.
struct CameraCapturePicker: UIViewControllerRepresentable {
    let onPhoto: (UIImage) -> Void
    let onVideo: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoMaximumDuration = VideoProcessing.maxSeconds
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPhoto: onPhoto, onVideo: onVideo, onCancel: onCancel) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private nonisolated(unsafe) let onPhoto: (UIImage) -> Void
        private nonisolated(unsafe) let onVideo: (URL) -> Void
        private nonisolated(unsafe) let onCancel: () -> Void
        init(onPhoto: @escaping (UIImage) -> Void, onVideo: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPhoto = onPhoto; self.onVideo = onVideo; self.onCancel = onCancel
        }

        nonisolated func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let url = info[.mediaURL] as? URL
            let image = info[.originalImage] as? UIImage
            DispatchQueue.main.async {
                if let url { self.onVideo(url) } else if let image { self.onPhoto(image) } else { self.onCancel() }
            }
        }

        nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { DispatchQueue.main.async { self.onCancel() } }
    }
}
