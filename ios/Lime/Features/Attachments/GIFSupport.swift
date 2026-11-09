import ImageIO
import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// LIME-206: animated GIFs are sent as the GIF file itself and play in chats, a frame at a time.
enum GIF {
    static let mime = "image/gif"
    /// What may be sent: at most this large and this many frames.
    static let maxBytes = 10 * 1024 * 1024
    static let maxFrames = 500

    enum Problem: Error, Equatable { case notAGIF, tooBig }

    static let tooBigMessage = "This GIF is too big to send"

    /// True when ImageIO says the bytes are a GIF (not just a name that ends in .gif).
    static func isGIF(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(source) else { return false }
        return UTType(type as String)?.conforms(to: .gif) == true
    }

    static func isGIF(mime: String) -> Bool { mime.lowercased() == "image/gif" }

    static func frameCount(_ data: Data) -> Int {
        CGImageSourceCreateWithData(data as CFData, nil).map { CGImageSourceGetCount($0) } ?? 0
    }

    /// The GIF as an attachment, **the same bytes** (GIFs carry no camera or location data; any text blocks stay as the maker wrote them), with the first
    /// frame as its tiny preview. A big one is refused, never turned into a JPEG.
    static func attachment(_ data: Data, name: String = "GIF.gif") throws -> (OutgoingAttachment, UIImage) {
        guard isGIF(data) else { throw Problem.notAGIF }
        guard data.count <= maxBytes, frameCount(data) <= maxFrames else { throw Problem.tooBig }
        guard let first = firstFrame(data) else { throw Problem.notAGIF }
        let thumb = AttachmentProcessing.thumbnail(first)
        let item = OutgoingAttachment(bytes: data, name: name, mime: mime, width: UInt32(first.size.width * first.scale), height: UInt32(first.size.height * first.scale),
                                      durationMs: nil, thumb: thumb, poster: Data())
        return (item, PhotoProcessing.crop(first, viewport: 128, scale: 1, offset: .zero))
    }

    static func firstFrame(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// The seconds each frame stays (from the file's own delay, never less than a fiftieth: browsers treat 0 and 10 ms as 100 ms).
    static func delays(_ source: CGImageSource) -> [TimeInterval] {
        (0..<CGImageSourceGetCount(source)).map { index in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            return delay < 0.011 ? 0.1 : delay
        }
    }

    /// Saves it to Photos as a GIF (not a still).
    static func saveToPhotos(_ data: Data) async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = UTType.gif.identifier
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: options)
            }) { ok, _ in continuation.resume(returning: ok) }
        }
    }
}

/// At most a few GIFs play at once in a chat (the rest show their first frame until one scrolls away).
@MainActor
final class GIFPlaybackBudget {
    static let shared = GIFPlaybackBudget()
    /// One GIF plays at a time in view (WCAG 2.2.2); the others show their first frame, and the next one starts when this one stops (LIME-130-3a).
    static let limit = 1
    static let freed = Notification.Name("lime.gif.budget.freed")
    private var playing: Set<UUID> = []
    func request(_ id: UUID) -> Bool {
        if playing.contains(id) { return true }
        guard playing.count < Self.limit else { return false }
        playing.insert(id)
        return true
    }
    func release(_ id: UUID) {
        guard playing.remove(id) != nil else { return }
        NotificationCenter.default.post(name: Self.freed, object: nil)
    }
}

/// Plays a GIF: ImageIO decodes one frame at a time as the display needs it (the whole file is never decoded into memory), and it stops when it leaves the screen.
final class GIFPlayerView: UIView {
    private let imageView = UIImageView()
    private var source: CGImageSource?
    private var delays: [TimeInterval] = []
    private var index = 0
    private var link: CADisplayLink?
    private var nextChange: CFTimeInterval = 0
    private let token = UUID()
    var wantsToPlay = true { didSet { refresh() } }
    /// Called when it begins to play (the five seconds count from then).
    var onStart: (() -> Void)?
    private var freedObserver: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(imageView)
        clipsToBounds = true
        // Another GIF stopped: one that was waiting for its turn may go now.
        freedObserver = NotificationCenter.default.addObserver(forName: GIFPlaybackBudget.freed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self, self.link == nil { self.refresh() } }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    func load(_ data: Data, fit: Bool) {
        imageView.contentMode = fit ? .scaleAspectFit : .scaleAspectFill
        let source = CGImageSourceCreateWithData(data as CFData, nil)
        self.source = source
        delays = source.map(GIF.delays) ?? []
        index = 0
        showFrame(0)
        refresh()
    }

    private func showFrame(_ i: Int) {
        guard let source, i < CGImageSourceGetCount(source), let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { return }
        imageView.image = UIImage(cgImage: cg)
    }

    override func didMoveToWindow() { super.didMoveToWindow(); refresh() }

    private func refresh() {
        let shouldRun = wantsToPlay && window != nil && delays.count > 1 && MainActor.assumeIsolated { GIFPlaybackBudget.shared.request(token) }
        if shouldRun, link == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFramesPerSecond = 30
            link.add(to: .main, forMode: .common)
            self.link = link
            nextChange = CACurrentMediaTime() + delays[index]
            onStart?()
        } else if !shouldRun, link != nil {
            link?.invalidate(); link = nil
            MainActor.assumeIsolated { GIFPlaybackBudget.shared.release(token) }
            if window == nil || !wantsToPlay { index = 0; showFrame(0) }
        } else if !shouldRun {
            MainActor.assumeIsolated { GIFPlaybackBudget.shared.release(token) }
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard link.timestamp >= nextChange, delays.count > 1 else { return }
        index = (index + 1) % delays.count
        showFrame(index)
        nextChange = link.timestamp + delays[index]
    }

    deinit {
        // (The display link holds its target, so a view that is playing is never freed: it stops when it leaves the window.)
        let token = token
        Task { @MainActor in GIFPlaybackBudget.shared.release(token) }
    }
}

struct GIFView: UIViewRepresentable {
    let data: Data
    var playing = true
    var fit = false
    var onStart: (() -> Void)?

    func makeUIView(context: Context) -> GIFPlayerView {
        let view = GIFPlayerView()
        view.onStart = onStart
        view.load(data, fit: fit)
        view.wantsToPlay = playing
        return view
    }

    func updateUIView(_ view: GIFPlayerView, context: Context) { view.onStart = onStart; view.wantsToPlay = playing }
}


/// Which GIFs in the chat are playing (LIME-130-3a, WCAG 2.2.2): one that has looped for five seconds pauses, unless the person tapped it to play;
/// with Reduce Motion none starts by itself. "Play GIF" and "Pause GIF" are the same choice as an accessibility action.
@MainActor @Observable
final class GIFPlayback {
    static let shared = GIFPlayback()
    nonisolated static let loopSeconds = 5.0
    private(set) var asked: Set<String> = []     // tapped to play: it keeps playing
    private(set) var paused: Set<String> = []    // five seconds done, or paused by the person

    /// The rule, apart from the state (tested): plays when asked to, or when nothing stopped it and Reduce Motion is off.
    nonisolated static func plays(reduceMotion: Bool, asked: Bool, paused: Bool) -> Bool {
        asked || (!reduceMotion && !paused)
    }

    func isPlaying(_ id: String, reduceMotion: Bool) -> Bool { Self.plays(reduceMotion: reduceMotion, asked: asked.contains(id), paused: paused.contains(id)) }

    func toggle(_ id: String, reduceMotion: Bool) {
        if isPlaying(id, reduceMotion: reduceMotion) { asked.remove(id); paused.insert(id) } else { asked.insert(id); paused.remove(id) }
    }

    /// Five seconds after it began to play: it stops, unless it was tapped.
    func loopedEnough(_ id: String) { if !asked.contains(id) { paused.insert(id) } }
}
