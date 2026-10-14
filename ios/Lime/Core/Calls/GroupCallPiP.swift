import AVFoundation
import AVKit
import LiveKit
import UIKit

/// Who the window is about: one person, or (nobody else has spoken, or is there) the group itself, drawn like the chat's own avatar.
enum PiPSubject: Equatable {
    case person(Person)
    case group(id: String, name: String, emoji: String?, members: [Person])

    var key: String {
        switch self {
        case .person(let person): "p:\(person.id)"
        case .group(let id, _, _, _): "g:\(id)"
        }
    }

    var name: String {
        switch self {
        case .person(let person): person.name
        case .group(_, let name, _, _): name
        }
    }
}

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
    func prepare(sourceView: UIView, subject: PiPSubject)
    /// What the window shows now: `track` (the speaker's picture) when `pictureShowing`, else the subject's photo (or initials; a group's
    /// photo, emoji or cluster of members' photos).
    func show(subject: PiPSubject, track: AnyObject?, pictureShowing: Bool)
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
    private var avatarView: UIView?
    private var avatarKey: String?
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

    func prepare(sourceView: UIView, subject: PiPSubject) {
        guard controller == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        show(subject: subject, track: nil, pictureShowing: false)
        let source = AVPictureInPictureController.ContentSource(activeVideoCallSourceView: sourceView, contentViewController: contentController)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.delegate = self
        self.controller = controller
        CallDiagnostics.shared.log("group pip prepared")
    }

    func show(subject: PiPSubject, track newTrack: AnyObject?, pictureShowing: Bool) {
        // The photo: replaced when the subject changes (plain UIKit: nothing here reads the app's environment).
        if avatarKey != subject.key {
            avatarView?.removeFromSuperview()
            let view: UIView
            switch subject {
            case .person(let person): view = PiPAvatarView(person: person)
            case .group(let id, let name, let emoji, let members): view = PiPGroupAvatarView(groupID: id, name: name, emoji: emoji, members: members)
            }
            view.frame = contentController.view.bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.alpha = avatarShown ? 1 : 0
            contentController.view.addSubview(view)
            avatarView = view
            avatarKey = subject.key
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
        CallDiagnostics.shared.log("group pip \(showAvatar ? "photo" : "picture")")
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

/// A group's picture for the window when nobody else is there or has spoken: the group's photo, else its emoji, else the same cluster of up
/// to four members' photos the chat and Messages show (initials only for a member with no photo). Plain UIKit, like `PiPAvatarView`: the system
/// moves this view into its own window, where a SwiftUI view that reads the app's environment would trap.
final class PiPGroupAvatarView: UIView {
    private let circle = UIView()
    private var members: [(circle: UIView, photo: UIImageView?, label: UILabel?)] = []
    private let photo = UIImageView()
    private let emojiLabel = UILabel()

    @MainActor init(groupID: String, name: String, emoji: String?, members people: [Person]) {
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0.08, alpha: 1)
        circle.clipsToBounds = true
        addSubview(circle)
        if let image = AvatarCache.shared.image(for: groupID) {
            photo.image = image
            photo.contentMode = .scaleAspectFill
            circle.addSubview(photo)
        } else if let emoji {
            circle.backgroundColor = UIColor(white: 1, alpha: 0.12)
            emojiLabel.text = emoji
            emojiLabel.textAlignment = .center
            circle.addSubview(emojiLabel)
        } else {
            circle.clipsToBounds = false
            let shown = people.count > 4 ? Array(people.prefix(3)) : Array(people.prefix(4))
            for person in shown { addMember(person) }
            if people.count > shown.count { addMore(people.count - shown.count) }
        }
        isAccessibilityElement = true
        accessibilityLabel = name
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// How many member circles are drawn (a test reads it): photos or initials for each, plus "+N".
    var clusterCount: Int { members.count }
    var showsGroupPhoto: Bool { photo.superview != nil }
    var showsEmoji: Bool { emojiLabel.superview != nil }

    @MainActor private func addMember(_ person: Person) {
        let holder = UIView()
        holder.clipsToBounds = true
        if let image = AvatarCache.shared.image(for: person.id) {
            let view = UIImageView(image: image)
            view.contentMode = .scaleAspectFill
            holder.addSubview(view)
            members.append((holder, view, nil))
        } else {
            holder.backgroundColor = UIColor(Theme.avatar(person.tone))
            let label = UILabel()
            label.text = person.initials
            label.textAlignment = .center
            label.textColor = UIColor(red: 0.075, green: 0.106, blue: 0.09, alpha: 1)
            label.adjustsFontSizeToFitWidth = true
            holder.addSubview(label)
            members.append((holder, nil, label))
        }
        circle.addSubview(holder)
    }

    @MainActor private func addMore(_ extra: Int) {
        let holder = UIView()
        holder.clipsToBounds = true
        holder.backgroundColor = UIColor(white: 1, alpha: 0.18)
        let label = UILabel()
        label.text = "+\(extra)"
        label.textAlignment = .center
        label.textColor = .white
        label.adjustsFontSizeToFitWidth = true
        holder.addSubview(label)
        members.append((holder, nil, label))
        circle.addSubview(holder)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = max(60, min(bounds.width, bounds.height) * 0.6)
        circle.frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        circle.layer.cornerRadius = photo.superview != nil || emojiLabel.superview != nil ? side / 2 : 0
        photo.frame = circle.bounds
        emojiLabel.frame = circle.bounds
        emojiLabel.font = .systemFont(ofSize: side * 0.5)
        let d = side * 0.52, o = side * 0.24
        for (index, member) in members.enumerated() {
            let cx = side / 2 + (index % 2 == 0 ? -o : o), cy = side / 2 + (index < 2 ? -o : o)
            member.circle.frame = CGRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d)
            member.circle.layer.cornerRadius = d / 2
            member.photo?.frame = member.circle.bounds
            member.label?.frame = member.circle.bounds
            member.label?.font = .systemFont(ofSize: d * 0.38, weight: .medium)
        }
    }
}
