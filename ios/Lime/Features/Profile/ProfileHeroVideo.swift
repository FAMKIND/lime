import SwiftUI
import AVFoundation
import Network
import UIKit

/// Whether this phone may download other people's background videos right now (LIME-226b): on Wi-Fi yes; on cellular or in Low Data Mode no (the profile
/// offers a tap instead). The core is told as the network changes.
final class VideoFetchPolicy: @unchecked Sendable {
    static let shared = VideoFetchPolicy()
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var allowedNow = true

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock(); self.allowedNow = !(path.isExpensive || path.isConstrained); self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "lime.video-policy"))
    }

    var allowed: Bool { lock.lock(); defer { lock.unlock() }; return allowedNow }
}

/// Where a profile's background video lives on this phone while it plays (a small file in the caches folder, named by the person and the version).
enum HeroVideoCache {
    static func url(for data: Data, key: String) -> URL? {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("hero-video", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safe = key.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        let file = folder.appendingPathComponent("\(safe)-\(data.count).mp4")
        if FileManager.default.fileExists(atPath: file.path) { return file }
        do { try data.write(to: file, options: .atomic); return file } catch { return nil }
    }
}

/// A silent looping player filling its frame (aspect fill). It never makes a sound and takes no audio focus.
struct HeroVideoView: UIViewRepresentable {
    let url: URL
    var playing: Bool
    var onReady: @MainActor @Sendable () -> Void

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var observation: NSKeyValueObservation?
        var url: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.isUserInteractionEnabled = false
        configure(view, context.coordinator)
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        if context.coordinator.url != url { configure(view, context.coordinator) }
        if playing { context.coordinator.player?.play() } else { context.coordinator.player?.pause() }
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: Coordinator) {
        coordinator.player?.pause()
        coordinator.observation = nil
        coordinator.looper = nil
        coordinator.player = nil
    }

    private func configure(_ view: PlayerView, _ coordinator: Coordinator) {
        coordinator.url = url
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.allowsExternalPlayback = false
        coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
        coordinator.player = player
        view.playerLayer.player = player
        let ready = onReady
        coordinator.observation = view.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { layer, _ in
            if layer.isReadyForDisplay { Task { @MainActor in ready() } }
        }
    }
}

/// Make a background video from a picked one (LIME-226b): the part chosen (at most 10 s), framed into the 4:5 crop the person made, no audio, no
/// metadata, about 720 × 900, at most 6 MB.
enum BackgroundVideoProcessing {
    static let maxSeconds = 10.0
    static let size = CGSize(width: 720, height: 900)
    /// A little under the server's 6 MiB, so the container's overhead never tips it over.
    static let maxBytes = 5_800_000

    enum Problem: Error { case noVideo, tooLong, failed, tooBig }

    static func duration(of url: URL) async -> Double {
        let seconds = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
        return seconds.isFinite ? seconds : 0
    }

    /// A frame (upright) at `seconds`, for the framing screen and as the still that goes with the video.
    static func frame(of url: URL, at seconds: Double) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        guard let cg = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image else { return nil }
        return UIImage(cgImage: cg)
    }

    /// The framing geometry (what `BackgroundCropScreen` reports) applied to the video.
    static func export(_ url: URL, start: Double, crop: BackgroundCrop) async throws -> Data {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Problem.noVideo }
        let natural = try await track.load(.naturalSize)
        let oriented = try await track.load(.preferredTransform)
        let total = try await asset.load(.duration).seconds
        let length = min(maxSeconds, max(0.1, total - start))
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw Problem.failed }
        try videoTrack.insertTimeRange(CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: length, preferredTimescale: 600)), of: track, at: .zero)

        // Where the picture sits in the 4:5 frame (in the framing screen's points), then in output pixels.
        let upright = natural.applying(oriented)
        let width = abs(upright.width), height = abs(upright.height)
        let cover = max(crop.viewport.width / width, crop.viewport.height / height) * max(crop.scale, 1)
        let factor = size.width / crop.viewport.width
        let originX = (crop.viewport.width - width * cover) / 2 + crop.offset.width
        let originY = (crop.viewport.height - height * cover) / 2 + crop.offset.height
        let transform = oriented
            .concatenating(CGAffineTransform(scaleX: cover * factor, y: cover * factor))
            .concatenating(CGAffineTransform(translationX: originX * factor, y: originY * factor))

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layer.setTransform(transform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        instruction.layerInstructions = [layer]
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = size
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { throw Problem.failed }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("hero-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: out) }
        session.videoComposition = videoComposition
        session.outputFileType = .mp4
        session.fileLengthLimit = Int64(maxBytes)
        session.shouldOptimizeForNetworkUse = true
        session.metadata = []
        session.metadataItemFilter = AVMetadataItemFilter.forSharing()
        if #available(iOS 18, *) {
            try await session.export(to: out, as: .mp4)
        } else {
            session.outputURL = out
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in session.exportAsynchronously { done.resume() } }
            if session.status != .completed { throw Problem.failed }
        }
        let data = try Data(contentsOf: out)
        guard data.count <= maxBytes + 150_000, data.count <= 6 * 1024 * 1024 else { throw Problem.tooBig }
        return data
    }
}

#if DEBUG
/// A tiny made-up clip for the demo and the UI tests (the simulator's library is empty).
enum DemoClip {
    static func url() async -> URL? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("demo-hero-clip.mp4")
        if FileManager.default.fileExists(atPath: file.path) { return file }
        try? FileManager.default.removeItem(at: file)
        guard let writer = try? AVAssetWriter(outputURL: file, fileType: .mp4) else { return nil }
        let width = 120, height = 150
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData { try? await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let pixels = buffer else { continue }
            CVPixelBufferLockBaseAddress(pixels, [])
            if let base = CVPixelBufferGetBaseAddress(pixels) {
                let bytes = base.assumingMemoryBound(to: UInt8.self)
                let stride = CVPixelBufferGetBytesPerRow(pixels)
                for y in 0..<height { for x in 0..<width {
                    let o = y * stride + x * 4
                    bytes[o] = UInt8((x + frame * 8) % 256); bytes[o + 1] = UInt8(120 + y % 100); bytes[o + 2] = UInt8(60 + frame * 6); bytes[o + 3] = 255
                } }
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 15))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed ? file : nil
    }

    static func data() async -> Data? {
        guard let url = await url() else { return nil }
        return try? Data(contentsOf: url)
    }
}
#endif
