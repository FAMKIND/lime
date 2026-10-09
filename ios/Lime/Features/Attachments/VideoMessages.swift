import AVFoundation
import AVKit
import PhotosUI
import UniformTypeIdentifiers
import SwiftUI
import UIKit

/// Makes the video Lime sends: 720p H.264 in an MP4, at most 3 minutes and about 50 MB, with a poster frame.
enum VideoProcessing {
    static let maxSeconds: Double = 180
    static let maxBytes = 50 * 1024 * 1024 - 256 * 1024   // a little under the file limit, so chunks and tags fit

    enum Problem: Error, Equatable { case tooLong(seconds: Int), tooLarge, unreadable }

    static func message(for problem: Problem) -> String {
        switch problem {
        case .tooLong(let seconds): "That video is \(VoiceFormat.clock(Double(seconds))) long. Videos can be up to 3 minutes."
        case .tooLarge: "That video is too large to send (the limit is 50 MB). Try a shorter one."
        case .unreadable: "That video couldn't be read."
        }
    }

    /// The length of a video, in seconds.
    static func duration(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        return ((try? await asset.load(.duration)).map(CMTimeGetSeconds)) ?? 0
    }

    /// Re-encodes `url` for sending. `progress` reports 0...1. The picture's metadata (place, camera) is not kept.
    static func prepare(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> (item: OutgoingAttachment, poster: UIImage?) {
        let asset = AVURLAsset(url: url)
        let seconds = ((try? await asset.load(.duration)).map(CMTimeGetSeconds)) ?? 0
        guard seconds.isFinite, seconds > 0 else { throw Problem.unreadable }
        if seconds > maxSeconds + 0.5 { throw Problem.tooLong(seconds: Int(seconds.rounded())) }

        let output = FileManager.default.temporaryDirectory.appendingPathComponent("lime-video-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: output) }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else { throw Problem.unreadable }
        session.outputURL = output
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.fileLengthLimit = Int64(maxBytes)
        session.metadataItemFilter = AVMetadataItemFilter.forSharing()
        nonisolated(unsafe) let exporter = session
        let watcher = Task {
            while !Task.isCancelled {
                progress(Double(exporter.progress))
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { continuation.resume() }
        }
        watcher.cancel()
        progress(1)
        guard session.status == .completed else { throw Problem.unreadable }
        let data = try Data(contentsOf: output, options: .mappedIfSafe)
        guard data.count <= maxBytes else { throw Problem.tooLarge }

        let poster = await posterFrame(asset)
        let size = await displaySize(of: asset)
        let thumb = poster.map(AttachmentProcessing.thumbnail) ?? Data()
        let item = OutgoingAttachment(bytes: data, name: "Video.mp4", mime: "video/mp4", width: UInt32(size.width), height: UInt32(size.height),
                                      durationMs: UInt32(seconds * 1000), thumb: thumb)
        return (item, poster)
    }

    /// A frame from near the start, upright.
    static func posterFrame(_ asset: AVAsset) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        guard let image = try? await generator.image(at: time).image else { return nil }
        return UIImage(cgImage: image)
    }

    private static func displaySize(of asset: AVAsset) async -> CGSize {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let natural = try? await track.load(.naturalSize), let transform = try? await track.load(.preferredTransform) else { return CGSize(width: 1280, height: 720) }
        let size = natural.applying(transform)
        return CGSize(width: abs(size.width), height: abs(size.height))
    }
}

// MARK: In a bubble

/// A video: its poster (blurred until the real frame is known), a play button and the length. Tapping downloads it (with a
/// progress ring) and opens the player.
struct VideoTile: View {
    let item: AttachmentItem
    let isOwn: Bool
    var uploading = false
    var messageID: String?
    var conversationID: Conversation.ID?
    @Environment(ConversationStore.self) private var store
    @State private var opening = false
    @State private var poster: UIImage?

    var body: some View {
        ZStack {
                Theme.surface
                if let poster {
                    Image(uiImage: poster).resizable().scaledToFill()
                } else if let thumb = UIImage(data: item.thumb) {
                    Image(uiImage: thumb).resizable().scaledToFill().blur(radius: 8).clipped()
                }
                if opening || uploading {
                    TransferRing(attachmentID: item.id, active: true, tint: .white).frame(width: 44, height: 44)
                        .padding(8).background(.black.opacity(0.45), in: Circle())
                } else {
                    Image(systemName: "play.fill").font(.system(size: 22)).foregroundStyle(.white)
                        .frame(width: 52, height: 52).background(.black.opacity(0.45), in: Circle())
                }
            }
            .frame(width: 248, height: 248 / min(max(item.aspect, 0.6), 1.8))
            .overlay(alignment: .bottomTrailing) {
                Text(VoiceFormat.clock(Double(item.durationMs ?? 0) / 1000)).font(Theme.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3).background(.black.opacity(0.5), in: Capsule()).padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .mediaTap { Task { await open() } }
        .accessibilityLabel("Video, \(VoiceFormat.clock(Double(item.durationMs ?? 0) / 1000))")
        .accessibilityIdentifier("attachment-video-\(item.id)")
    }

    private func open() async {
        opening = !item.downloaded
        defer { opening = false }
        guard let url = await store.fileURL(for: item) else { store.report(.offline); return }
        store.playingVideo = VideoRequest(url: url, messageID: messageID, conversationID: conversationID)
    }
}

struct VideoRequest: Identifiable {
    let url: URL
    var messageID: String?
    var conversationID: Conversation.ID?
    let id = UUID()
}

/// The full-screen player.
struct VideoPlayerScreen: View {
    let request: VideoRequest
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let player { VideoPlayer(player: player).ignoresSafeArea() }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
            }
            .padding(.leading, 16).padding(.top, 8)
            .accessibilityLabel("Close").accessibilityIdentifier("video-player-close")
            HStack {
                Spacer()
                ViewerReactButton(messageID: request.messageID, conversationID: request.conversationID)
            }
            .padding(.trailing, 16).padding(.top, 8)
        }
        .onAppear {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            player = AVPlayer(url: request.url)
            player?.play()
        }
        .onDisappear { player?.pause(); player = nil }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("video-player")
    }
}

// MARK: Progress

/// A ring that fills as an upload or download gets on, read from LimeCore while it is showing.
struct TransferRing: View {
    let attachmentID: String
    let active: Bool
    var tint: Color = Theme.text
    @Environment(ConversationStore.self) private var store
    @State private var fraction: Double?

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: 3)
            if let fraction {
                Circle().trim(from: 0, to: max(0.04, fraction)).stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
            } else {
                ProgressView().tint(tint)
            }
        }
        .task(id: attachmentID) {
            while !Task.isCancelled && active {
                if let progress = await store.transferProgress(attachmentID), progress.total > 0 {
                    fraction = Double(progress.done) / Double(progress.total)
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fraction.map { "\(Int($0 * 100)) percent" } ?? "Working")
        .accessibilityIdentifier("transfer-ring-\(attachmentID)")
    }
}

// MARK: Choosing a video

/// The system picker for one video: Lime receives only that one, with no library permission. The file is copied out, because the
/// picker's own copy is deleted when it returns.
struct VideoLibraryPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .videos
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private nonisolated(unsafe) let onPick: (URL) -> Void
        private nonisolated(unsafe) let onCancel: () -> Void
        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) { self.onPick = onPick; self.onCancel = onCancel }

        nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider, provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
                DispatchQueue.main.async { self.onCancel() }
                return
            }
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                guard let url else { DispatchQueue.main.async { self.onCancel() }; return }
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent("lime-pick-\(UUID().uuidString).\(url.pathExtension)")
                do { try FileManager.default.copyItem(at: url, to: copy) } catch { DispatchQueue.main.async { self.onCancel() }; return }
                DispatchQueue.main.async { self.onPick(copy) }
            }
        }
    }
}

/// The camera, recording a video of up to 3 minutes.
struct VideoCameraPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.videoMaximumDuration = VideoProcessing.maxSeconds
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private nonisolated(unsafe) let onPick: (URL) -> Void
        private nonisolated(unsafe) let onCancel: () -> Void
        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) { self.onPick = onPick; self.onCancel = onCancel }

        nonisolated func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let url = info[.mediaURL] as? URL
            DispatchQueue.main.async { if let url { self.onPick(url) } else { self.onCancel() } }
        }

        nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { DispatchQueue.main.async { self.onCancel() } }
    }
}

/// A small tap of feedback (when recording locks or is cancelled).
enum Haptics {
    @MainActor static func tick() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}
