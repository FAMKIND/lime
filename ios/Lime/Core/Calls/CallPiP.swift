import AVFoundation
import AVKit
import SwiftUI
import UIKit
@preconcurrency import WebRTC

/// What a call needs from system Picture in Picture (LIME-118c): the other person's video in iOS's floating window, like FaceTime over
/// Messages. Tests use a fake.
@MainActor
protocol CallPiP: AnyObject {
    var isPossible: Bool { get }
    /// The window came up (lime is still in front, or was left).
    var onStarted: (() -> Void)? { get set }
    /// The window is gone (closed by the person, or restored).
    var onStopped: (() -> Void)? { get set }
    /// The person tapped the window to come back to lime's full call screen.
    var onRestore: (() -> Void)? { get set }
    /// The system could not start it.
    var onFailed: (() -> Void)? { get set }
    /// Makes it ready to start (also automatically when lime is left): `sourceView` is the call screen's picture, which must be on screen.
    func prepare(sourceView: UIView, person: Person)
    /// The other person's camera is off (told over `lime-ctl`): the window shows their photo, never a black or frozen picture.
    func setRemoteCameraOff(_ off: Bool)
    func start()
    func stop()
}

/// Draws the other side's frames with an `AVSampleBufferDisplayLayer`, the only kind of content system Picture in Picture can show for a call.
final class PiPDisplayView: UIView {
    let displayLayer = AVSampleBufferDisplayLayer()
    /// The frames' rotation in degrees (0, 90, 180, 270): the layer is turned to match.
    var rotation = 0 { didSet { if rotation != oldValue { setNeedsLayout() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        // The same fill as the call screen picture, so the system zoom into the window has nothing to jump between.
        displayLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(displayLayer)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let sideways = rotation == 90 || rotation == 270
        let size = sideways ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.bounds = CGRect(origin: .zero, size: size)
        displayLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        displayLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(rotation) * .pi / 180))
        CATransaction.commit()
    }
}

/// Receives the remote WebRTC frames and hands them to the display layer as sample buffers (hardware-decoded frames already are pixel
/// buffers; software-decoded I420 ones are copied into an NV12 buffer).
final class PiPFrameRenderer: NSObject, RTCVideoRenderer, @unchecked Sendable {
    /// The layer's own renderer (iOS 17): unlike the layer it may be fed from the WebRTC thread.
    private nonisolated(unsafe) let renderer: AVSampleBufferVideoRenderer
    /// Called (async, on the main actor) when the frames' size or rotation changed: it applies them, then calls `done`. Frames wait
    /// (are dropped) until then, so a frame is never drawn with the previous rotation.
    private let apply: @Sendable (CGSize, Int, @escaping @Sendable () -> Void) -> Void
    private let lock = NSLock()
    private var size = CGSize.zero, rotation = -1, applying = false, frameAt: Date?

    @MainActor init(layer: AVSampleBufferDisplayLayer, apply: @escaping @Sendable (CGSize, Int, @escaping @Sendable () -> Void) -> Void) {
        self.renderer = layer.sampleBufferRenderer
        self.apply = apply
    }

    /// The last frame's size and rotation, readable at once (so the window is sized before it starts).
    var current: (size: CGSize, rotation: Int)? {
        lock.lock(); defer { lock.unlock() }
        return rotation >= 0 ? (size, rotation) : nil
    }

    /// When the last frame arrived (nil: none yet).
    var lastFrameAt: Date? {
        lock.lock(); defer { lock.unlock() }
        return frameAt
    }

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        let newSize = CGSize(width: Int(frame.width), height: Int(frame.height))
        let newRotation = frame.rotation.rawValue
        lock.lock()
        frameAt = Date()
        if applying { lock.unlock(); return }
        let changed = newSize != size || newRotation != rotation
        if changed { applying = true }
        lock.unlock()
        if changed {
            // Held until the layer and the window have the new size and rotation; the next frame draws with them.
            apply(newSize, newRotation) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                self.size = newSize; self.rotation = newRotation; self.applying = false
                self.lock.unlock()
            }
            return
        }
        guard let pixels = Self.pixelBuffer(of: frame), let sample = Self.sampleBuffer(pixels, timestampNs: frame.timeStampNs) else { return }
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(sample)
    }

    /// Clears the picture on screen (the camera went off: a frozen last frame must not show).
    func clear() { renderer.flush(removingDisplayedImage: true, completionHandler: nil) }

    static func pixelBuffer(of frame: RTCVideoFrame) -> CVPixelBuffer? {
        if let native = frame.buffer as? RTCCVPixelBuffer { return native.pixelBuffer }
        let i420 = frame.buffer.toI420()
        let width = Int(i420.width), height = Int(i420.height)
        var made: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attributes, &made) == kCVReturnSuccess, let buffer = made else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let yBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0), let uvBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) else { return nil }
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0), uvStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        for row in 0..<height { memcpy(yBase + row * yStride, i420.dataY + row * Int(i420.strideY), width) }
        let chromaWidth = (width + 1) / 2, chromaHeight = (height + 1) / 2
        for row in 0..<chromaHeight {
            let u = i420.dataU + row * Int(i420.strideU), v = i420.dataV + row * Int(i420.strideV)
            let out = (uvBase + row * uvStride).assumingMemoryBound(to: UInt8.self)
            for column in 0..<chromaWidth { out[2 * column] = u[column]; out[2 * column + 1] = v[column] }
        }
        return buffer
    }

    static func sampleBuffer(_ pixels: CVPixelBuffer, timestampNs: Int64) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixels, formatDescriptionOut: &format) == noErr, let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(value: timestampNs, timescale: 1_000_000_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixels, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}

/// System Picture in Picture for a video call: lime stays in front when it starts, as FaceTime does over Messages, and it also starts
/// by itself when lime is left. The window has only the system's own controls (return, close); mute and end stay on the call screen.
@MainActor
final class CallPictureInPicture: NSObject, CallPiP, AVPictureInPictureControllerDelegate {
    var onStarted: (() -> Void)?
    var onStopped: (() -> Void)?
    var onRestore: (() -> Void)?
    var onFailed: (() -> Void)?

    private let media: WebRTCMedia
    private let display = PiPDisplayView()
    private let contentController = AVPictureInPictureVideoCallViewController()
    private var controller: AVPictureInPictureController?
    private var renderer: PiPFrameRenderer?
    /// Their photo (or initials), over the picture, for when the camera is off or no frame is coming.
    private var avatarView: PiPAvatarView?
    private var cameraOff = false
    private var framesStopped = false
    private var avatarShown = false
    private var watch: Timer?
    private static let placeholder = CGSize(width: 360, height: 480)

    init(media: WebRTCMedia) {
        self.media = media
        super.init()
        contentController.view.addSubview(display)
        display.frame = contentController.view.bounds
        display.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentController.preferredContentSize = Self.placeholder
        let renderer = PiPFrameRenderer(layer: display.displayLayer) { [weak self] size, rotation, done in
            Task { @MainActor in
                self?.apply(size: size, rotation: rotation)
                done()
            }
        }
        self.renderer = renderer
        media.setPictureInPictureRenderer(renderer)
    }

    var isPossible: Bool { AVPictureInPictureController.isPictureInPictureSupported() && (controller?.isPictureInPicturePossible ?? false) }

    func prepare(sourceView: UIView, person: Person) {
        guard controller == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        installAvatar(person)
        applyCurrent()
        let source = AVPictureInPictureController.ContentSource(activeVideoCallSourceView: sourceView, contentViewController: contentController)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.delegate = self
        self.controller = controller
        // No frame for a second (a camera that stopped, a stalled network): the photo, not a frozen or black window.
        watch = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let renderer = self.renderer else { return }
                let last = renderer.lastFrameAt
                self.framesStopped = last.map { Date().timeIntervalSince($0) > 1.0 } ?? false
                self.refreshAvatar()
            }
        }
        CallDiagnostics.shared.log("pip prepared")
    }

    func setRemoteCameraOff(_ off: Bool) {
        cameraOff = off
        refreshAvatar()
    }

    func start() {
        guard let controller, controller.isPictureInPicturePossible else { onFailed?(); return }
        // Size and turn the window from the last frame before it opens (not a placeholder that snaps when the next frame arrives).
        applyCurrent()
        controller.startPictureInPicture()
    }

    func stop() {
        watch?.invalidate(); watch = nil
        controller?.stopPictureInPicture()
        media.setPictureInPictureRenderer(nil)
        renderer = nil
        controller = nil
    }

    // MARK: Size, rotation and the photo

    private func apply(size: CGSize, rotation: Int) {
        display.rotation = rotation
        display.layoutIfNeeded()
        let sideways = rotation == 90 || rotation == 270
        let content = sideways ? CGSize(width: size.height, height: size.width) : size
        contentController.preferredContentSize = content
        let diagnostics = CallDiagnostics.shared
        diagnostics.log("pip content size \(Int(content.width))x\(Int(content.height))")
        diagnostics.log("pip rotation applied \(rotation)")
    }

    /// From the last known frame, if there is one.
    private func applyCurrent() {
        if let current = renderer?.current { apply(size: current.size, rotation: current.rotation) }
    }

    private func installAvatar(_ person: Person) {
        guard avatarView == nil else { return }
        let view = PiPAvatarView(person: person)
        view.frame = contentController.view.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.alpha = 0
        contentController.view.addSubview(view)
        avatarView = view
    }

    /// Their photo shows while their camera is off or no frame is arriving, and the video while it is: a short cross-fade (none with
    /// Reduce Motion).
    private func refreshAvatar() {
        let show = cameraOff || framesStopped
        guard show != avatarShown, let view = avatarView else { return }
        avatarShown = show
        if show { renderer?.clear() }
        CallDiagnostics.shared.log("pip avatar \(show ? "shown" : "hidden")")
        let animate = !UIAccessibility.isReduceMotionEnabled
        UIView.animate(withDuration: animate ? 0.2 : 0) { view.alpha = show ? 1 : 0 }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in CallDiagnostics.shared.log("pip started"); self.onStarted?() }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in CallDiagnostics.shared.log("pip failed: \(error.localizedDescription)"); self.onFailed?() }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in CallDiagnostics.shared.log("pip stopped"); self.onStopped?() }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        nonisolated(unsafe) let done = completionHandler
        Task { @MainActor in self.onRestore?(); done(true) }
    }
}

/// What the window shows while their camera is off: their photo (or initials on their colour), centred on the call screen's dark.
/// Plain UIKit on purpose: the system moves this view into its own window, where a SwiftUI view that reads the app's environment
/// (the status badge in `AvatarView` needs the `ConversationStore`) has none and traps ("No Observable object of type
/// ConversationStore found": the crash LIME-135-fix found when minimising).
final class PiPAvatarView: UIView {
    private let circle = UIView()
    private let photo = UIImageView()
    private let initials = UILabel()

    @MainActor init(person: Person) {
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0.08, alpha: 1)
        circle.clipsToBounds = true
        addSubview(circle)
        if let image = AvatarCache.shared.image(for: person.id) {
            photo.image = image
            photo.contentMode = .scaleAspectFill
            circle.addSubview(photo)
        } else {
            circle.backgroundColor = UIColor(Theme.avatar(person.tone))
            initials.text = person.initials
            initials.textAlignment = .center
            initials.textColor = UIColor(red: 0.075, green: 0.106, blue: 0.09, alpha: 1)
            initials.adjustsFontSizeToFitWidth = true
            initials.minimumScaleFactor = 0.6
            circle.addSubview(initials)
        }
        isAccessibilityElement = true
        accessibilityLabel = "\(person.name), camera off"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = max(40, min(bounds.width, bounds.height) * 0.5)
        circle.frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        circle.layer.cornerRadius = side / 2
        photo.frame = circle.bounds
        initials.frame = circle.bounds
        initials.font = .systemFont(ofSize: side * 0.36, weight: .medium)
    }
}
