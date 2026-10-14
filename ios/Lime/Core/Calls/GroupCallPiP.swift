import AVFoundation
import AVKit
import LiveKit
import UIKit

/// What a group call needs from system Picture in Picture (LIME-112c): the active speaker in iOS's floating window, like FaceTime over
/// Messages. The window is never black: when the speaker's camera is off or their key has not arrived it shows their photo. Tests use a fake.
@MainActor
protocol GroupPiP: AnyObject {
    var isPossible: Bool { get }
    var onStarted: (() -> Void)? { get set }
    var onStopped: (() -> Void)? { get set }
    /// The person tapped the window to come back to lime's full call screen.
    var onRestore: (() -> Void)? { get set }
    var onFailed: (() -> Void)? { get set }
    /// Makes it ready (also automatically when lime is left): `sourceView` is on the call screen and must be on screen.
    func prepare(sourceView: UIView, person: Person)
    /// What the window shows now: `track` (the speaker's picture) when `pictureShowing`, else `person`'s photo (or initials).
    func show(person: Person, track: AnyObject?, pictureShowing: Bool)
    func start()
    func stop()
}

/// Draws a LiveKit video track's frames with an `AVSampleBufferDisplayLayer`, the only kind of content system Picture in Picture can show.
/// (Hardware-decoded frames already are pixel buffers; software-decoded I420 ones are copied into one.) It asks LiveKit to keep the track
/// flowing at a window's size even when no tile is on screen (the full call screen is gone while the window is up).
final class GroupPiPFrameRenderer: NSObject, VideoRenderer, @unchecked Sendable {
    private nonisolated(unsafe) let renderer: AVSampleBufferVideoRenderer
    private let apply: @Sendable (CGSize, Int, @escaping @Sendable () -> Void) -> Void
    private let lock = NSLock()
    private var size = CGSize.zero, rotation = -1, applying = false, frameAt: Date?

    @MainActor init(layer: AVSampleBufferDisplayLayer, apply: @escaping @Sendable (CGSize, Int, @escaping @Sendable () -> Void) -> Void) {
        renderer = layer.sampleBufferRenderer
        self.apply = apply
    }

    @MainActor var isAdaptiveStreamEnabled: Bool { true }
    @MainActor var adaptiveStreamSize: CGSize { CGSize(width: 360, height: 480) }

    var current: (size: CGSize, rotation: Int)? {
        lock.lock(); defer { lock.unlock() }
        return rotation >= 0 ? (size, rotation) : nil
    }

    var lastFrameAt: Date? {
        lock.lock(); defer { lock.unlock() }
        return frameAt
    }

    nonisolated func render(frame: VideoFrame) {
        let newSize = CGSize(width: Int(frame.dimensions.width), height: Int(frame.dimensions.height))
        let newRotation = frame.rotation.rawValue
        lock.lock()
        frameAt = Date()
        if applying { lock.unlock(); return }
        let changed = newSize != size || newRotation != rotation
        if changed { applying = true }
        lock.unlock()
        if changed {
            apply(newSize, newRotation) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                self.size = newSize; self.rotation = newRotation; self.applying = false
                self.lock.unlock()
            }
            return
        }
        guard let pixels = Self.pixelBuffer(of: frame), let sample = PiPFrameRenderer.sampleBuffer(pixels, timestampNs: frame.timeStampNs) else { return }
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(sample)
    }

    /// Clears the picture on screen (the speaker changed or their camera went off: a frozen last frame must not show).
    func clear() { renderer.flush(removingDisplayedImage: true, completionHandler: nil) }

    static func pixelBuffer(of frame: VideoFrame) -> CVPixelBuffer? {
        if let native = frame.buffer as? CVPixelVideoBuffer { return native.pixelBuffer }
        return (frame.buffer as? I420VideoBuffer)?.toPixelBuffer()
    }
}

/// System Picture in Picture for a group video call: lime stays in front when it starts, as FaceTime does over Messages, and it also
/// starts by itself when lime is left. The window follows the active speaker (the app decides who, with a short hold) and has only the
/// system's own controls (return, close); mute and leave stay on the call screen.
@MainActor
final class GroupCallPictureInPicture: NSObject, GroupPiP, AVPictureInPictureControllerDelegate {
    var onStarted: (() -> Void)?
    var onStopped: (() -> Void)?
    var onRestore: (() -> Void)?
    var onFailed: (() -> Void)?

    private let display = PiPDisplayView()
    private let contentController = AVPictureInPictureVideoCallViewController()
    private var controller: AVPictureInPictureController?
    private var renderer: GroupPiPFrameRenderer?
    private var avatarView: PiPAvatarView?
    private var avatarPerson: Person?
    private var track: (any VideoTrack)?
    private var avatarShown = false
    private static let placeholder = CGSize(width: 360, height: 480)

    override init() {
        super.init()
        contentController.view.addSubview(display)
        display.frame = contentController.view.bounds
        display.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentController.preferredContentSize = Self.placeholder
        renderer = GroupPiPFrameRenderer(layer: display.displayLayer) { [weak self] size, rotation, done in
            Task { @MainActor in
                self?.apply(size: size, rotation: rotation)
                done()
            }
        }
    }

    var isPossible: Bool { AVPictureInPictureController.isPictureInPictureSupported() && (controller?.isPictureInPicturePossible ?? false) }

    func prepare(sourceView: UIView, person: Person) {
        guard controller == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        show(person: person, track: nil, pictureShowing: false)
        let source = AVPictureInPictureController.ContentSource(activeVideoCallSourceView: sourceView, contentViewController: contentController)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.delegate = self
        self.controller = controller
        CallDiagnostics.shared.log("group pip prepared")
    }

    func show(person: Person, track newTrack: AnyObject?, pictureShowing: Bool) {
        // The photo: replaced when the person changes (plain UIKit: nothing here reads the app's environment).
        if avatarPerson?.id != person.id {
            avatarView?.removeFromSuperview()
            let view = PiPAvatarView(person: person)
            view.frame = contentController.view.bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.alpha = avatarShown ? 1 : 0
            contentController.view.addSubview(view)
            avatarView = view
            avatarPerson = person
        }
        // The picture: attached to the speaker's track, and taken off the previous one.
        let wanted = pictureShowing ? (newTrack as? any VideoTrack) : nil
        if wanted?.sid != track?.sid {
            if let old = track, let renderer { Self.detach(renderer, from: old) }
            renderer?.clear()
            track = wanted
            if let wanted, let renderer { Self.attach(renderer, to: wanted) }
        }
        let showAvatar = !pictureShowing || wanted == nil
        guard showAvatar != avatarShown, let view = avatarView else { return }
        avatarShown = showAvatar
        CallDiagnostics.shared.log("group pip \(showAvatar ? "photo" : "picture") for \(person.id.prefix(4))…")
        let animate = !UIAccessibility.isReduceMotionEnabled
        UIView.animate(withDuration: animate ? 0.2 : 0) { view.alpha = showAvatar ? 1 : 0 }
    }

    func start() {
        guard let controller, controller.isPictureInPicturePossible else { onFailed?(); return }
        if let current = renderer?.current { apply(size: current.size, rotation: current.rotation) }
        controller.startPictureInPicture()
    }

    func stop() {
        controller?.stopPictureInPicture()
        if let old = track, let renderer { Self.detach(renderer, from: old) }
        track = nil
        renderer = nil
        controller = nil
    }

    // Attaching blocks the calling thread until WebRTC's worker accepts the sink, so it is done off the main thread.
    private nonisolated static func attach(_ renderer: GroupPiPFrameRenderer, to track: any VideoTrack) {
        DispatchQueue.global(qos: .userInitiated).async { track.add(videoRenderer: renderer) }
    }

    private nonisolated static func detach(_ renderer: GroupPiPFrameRenderer, from track: any VideoTrack) {
        DispatchQueue.global(qos: .userInitiated).async { track.remove(videoRenderer: renderer) }
    }

    private func apply(size: CGSize, rotation: Int) {
        display.rotation = rotation
        display.layoutIfNeeded()
        let sideways = rotation == 90 || rotation == 270
        contentController.preferredContentSize = sideways ? CGSize(width: size.height, height: size.width) : size
        CallDiagnostics.shared.log("group pip content size \(Int(size.width))x\(Int(size.height)) rotation \(rotation)")
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in CallDiagnostics.shared.log("group pip started"); self.onStarted?() }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in CallDiagnostics.shared.log("group pip failed: \(error.localizedDescription)"); self.onFailed?() }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in CallDiagnostics.shared.log("group pip stopped"); self.onStopped?() }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        nonisolated(unsafe) let done = completionHandler
        Task { @MainActor in self.onRestore?(); done(true) }
    }
}
