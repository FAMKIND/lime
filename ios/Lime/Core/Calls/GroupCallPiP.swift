import AVFoundation
import AVKit
import LiveKit
import UIKit

/// Who the window is about: one person, or (nobody else has spoken, or is there) the group itself, drawn like the chat's own avatar.
enum PiPSubject: Equatable {
    case person(Person)
    case group(id: String, name: String, emoji: String?, members: [Person], me: Person?)

    var key: String {
        switch self {
        case .person(let person): "p:\(person.id)"
        case .group(let id, _, _, _, _): "g:\(id)"
        }
    }

    var name: String {
        switch self {
        case .person(let person): person.name
        case .group(_, let name, _, _, _): name
        }
    }
}

/// What a group call needs from system Picture in Picture (LIME-112c): the active speaker in iOS's floating window, like FaceTime over
/// Messages. The window is never black: when the speaker's camera is off or their key has not arrived it shows their photo. Tests use a fake.
@MainActor
protocol GroupPiP: AnyObject {
    var isPossible: Bool { get }
    /// Why the window cannot start now (for the log): "not prepared", "source off-window", or the system's own "not possible".
    var notPossibleReason: String { get }
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
    /// Waits until the system says the window is possible (KVO on `isPictureInPicturePossible`), up to `timeout`; true when it is.
    func waitUntilPossible(timeout: Duration) async -> Bool
    /// Builds the system controller again on the current anchor (keeping the content, the renderer and the subject): the last resort when the
    /// system keeps saying "not possible" after a return from minimising.
    func rebuild()
    /// LIME-150: the window draws these cells as a grid (live pictures or photos, the speaker ringed); an empty list goes back to the speaker window.
    func showGrid(_ cells: [PiPGridDisplay])
    /// The speaker's window takes over: the grid view goes.
    func clearGrid()
    func gridFrameCounts() -> [String: Int]
    func gridRequestedSizes() -> [String: String]
}

extension GroupPiP {
    /// LIME-150: the minimised grid. Nothing by default (a test fake need not draw).
    func showGrid(_ cells: [PiPGridDisplay]) {}
    func clearGrid() { showGrid([]) }
    /// Frames each grid cell's picture has drawn so far, by participant (for the diagnostics).
    func gridFrameCounts() -> [String: Int] { [:] }
    func gridRequestedSizes() -> [String: String] { [:] }
}

/// What `prepare` does with the call screen's anchor view (LIME-112d). The call screen is rebuilt on every return from minimising, so its
/// anchor is a NEW view each time; a controller left bound to the first one is bound to a view that is gone and can never start again.
enum PiPSourceBinding {
    enum Action: Equatable { case create, keep, rebind }

    static func action(hasController: Bool, sameSource: Bool) -> Action {
        if !hasController { return .create }
        return sameSource ? .keep : .rebind
    }
}

/// Draws a LiveKit video track's frames with an `AVSampleBufferDisplayLayer`, the only kind of content system Picture in Picture can show.
/// (Hardware-decoded frames already are pixel buffers; software-decoded I420 ones are copied into one.) It asks LiveKit to keep the track
/// flowing at a window's size even when no tile is on screen (the full call screen is gone while the window is up).
final class GroupPiPFrameRenderer: NSObject, VideoRenderer, @unchecked Sendable {
    private nonisolated(unsafe) let renderer: AVSampleBufferVideoRenderer
    private let apply: @Sendable (CGSize, Int, @escaping @Sendable () -> Void) -> Void
    private let lock = NSLock()
    private var size = CGSize.zero, rotation = -1, applying = false, frameAt: Date?
    private var frames = 0
    /// The size LiveKit is asked to keep the track flowing at (a window's size; a grid tile is smaller).
    var adaptiveSize = CGSize(width: 360, height: 480)

    @MainActor init(layer: AVSampleBufferDisplayLayer, apply: @escaping @Sendable (CGSize, Int, @escaping @Sendable () -> Void) -> Void) {
        renderer = layer.sampleBufferRenderer
        self.apply = apply
    }

    @MainActor var isAdaptiveStreamEnabled: Bool { true }
    @MainActor var adaptiveStreamSize: CGSize { adaptiveSize }

    /// Frames drawn so far (the spike's fps per tile).
    var frameCount: Int {
        lock.lock(); defer { lock.unlock() }
        return frames
    }

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
        frames += 1
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
    /// The anchor view the controller is bound to now (weak: the call screen owns it).
    private weak var sourceView: UIView?
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

    var notPossibleReason: String {
        guard let controller else { return "not prepared" }
        if sourceView?.window == nil { return "source off-window" }
        return controller.isPictureInPicturePossible ? "possible" : "the system says not possible"
    }

    func prepare(sourceView newSource: UIView, subject: PiPSubject) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        switch PiPSourceBinding.action(hasController: controller != nil, sameSource: sourceView === newSource) {
        case .keep:
            return
        case .rebind:
            // A new call screen: the same controller, content controller, renderer and subject, pointed at the new anchor.
            controller?.contentSource = AVPictureInPictureController.ContentSource(activeVideoCallSourceView: newSource, contentViewController: contentController)
            sourceView = newSource
            CallDiagnostics.shared.log("group pip rebound to the new call screen")
        case .create:
            show(subject: subject, track: nil, pictureShowing: false)
            let source = AVPictureInPictureController.ContentSource(activeVideoCallSourceView: newSource, contentViewController: contentController)
            let controller = AVPictureInPictureController(contentSource: source)
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            controller.delegate = self
            self.controller = controller
            sourceView = newSource
            CallDiagnostics.shared.log("group pip prepared")
        }
    }

    func show(subject: PiPSubject, track newTrack: AnyObject?, pictureShowing: Bool) {
        // The photo: replaced when the subject changes (plain UIKit: nothing here reads the app's environment).
        if avatarKey != subject.key {
            avatarView?.removeFromSuperview()
            let view: UIView
            switch subject {
            case .person(let person): view = PiPAvatarView(person: person)
            case .group(let id, let name, let emoji, let members, let me): view = PiPGroupAvatarView(groupID: id, name: name, emoji: emoji, members: members, me: me)
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

    private var grid: PiPGridView?
    private var lastGridShape = ""

    func gridFrameCounts() -> [String: Int] { grid?.frameCounts() ?? [:] }
    func gridRequestedSizes() -> [String: String] { grid?.requestedSizes() ?? [:] }

    /// Frames from the last size the window was told about: the window's aspect is set once per change of cell count, never per refresh.
    private var aspectCells = 0

    /// Grid mode: the grid view is installed and on show (the speaker's own picture is let go).
    private var gridMode: Bool { grid != nil && grid?.isHidden == false }

    func clearGrid() {
        grid?.stop()
        grid?.removeFromSuperview()
        grid = nil
        aspectCells = 0
    }

    func showGrid(_ cells: [PiPGridDisplay]) {
        guard !cells.isEmpty else {
            // Nobody to draw this second: the grid stays installed, out of sight (it is not torn down and built again).
            grid?.isHidden = true
            return
        }
        // A grid is a square (two side by side: 4:3); the system may still resize it.
        let size = cells.count == 2 ? CGSize(width: 640, height: 480) : (cells.count == 1 ? Self.placeholder : CGSize(width: 480, height: 480))
        if cells.count != aspectCells {
            aspectCells = cells.count
            contentController.preferredContentSize = size
            CallDiagnostics.shared.log("group pip aspect \(Int(size.width))x\(Int(size.height)) for \(cells.count) cells")
        }
        // The window's view has no size until the system presents it, and a subview made at size zero stays zero when the window grows (the
        // grid showed no picture on the first minimise, LIME-162): it starts at the wanted size, and follows the window's real bounds as soon as
        // there are any (checked on every refresh).
        let bounds = contentController.view.bounds
        let wanted = bounds.width > 4 && bounds.height > 4 ? bounds : CGRect(origin: .zero, size: size)
        contentController.view.backgroundColor = .black
        if grid == nil {
            let view = PiPGridView(frame: wanted)
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentController.view.addSubview(view)
            grid = view
        } else if let grid, grid.frame.size != wanted.size {
            grid.frame = wanted
        }
        grid?.isHidden = false
        let shape = "grid \(Int(grid?.frame.width ?? 0))x\(Int(grid?.frame.height ?? 0)) in window \(Int(bounds.width))x\(Int(bounds.height))"
        if shape != lastGridShape { lastGridShape = shape; CallDiagnostics.shared.log("group pip \(shape)") }
        grid?.update(cells)
    }

    func start() {
        guard let controller, controller.isPictureInPicturePossible else { onFailed?(); return }
        // The speaker's window sets its aspect from its last picture; in grid mode the grid already set it (its last size overriding that was the
        // 720 x 1280 flip in the log).
        if !gridMode, let current = renderer?.current { apply(size: current.size, rotation: current.rotation) }
        CallDiagnostics.shared.log("group pip start mode=\(gridMode ? "grid" : "speaker") window=\(Int(contentController.view.bounds.width))x\(Int(contentController.view.bounds.height))")
        controller.startPictureInPicture()
    }

    func waitUntilPossible(timeout: Duration) async -> Bool {
        guard let controller else { return false }
        if controller.isPictureInPicturePossible { return true }
        let box = PossibleWait()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            box.continuation = continuation
            box.observation = controller.observe(\.isPictureInPicturePossible, options: [.new]) { _, change in
                if change.newValue == true { box.finish(true) }
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                box.finish(controller.isPictureInPicturePossible)
            }
        }
    }

    func rebuild() {
        guard let sourceView else { return }
        controller?.delegate = nil
        let source = AVPictureInPictureController.ContentSource(activeVideoCallSourceView: sourceView, contentViewController: contentController)
        let fresh = AVPictureInPictureController(contentSource: source)
        fresh.canStartPictureInPictureAutomaticallyFromInline = true
        fresh.delegate = self
        controller = fresh
        CallDiagnostics.shared.log("group pip rebuilt")
    }

    func stop() {
        clearGrid()
        controller?.stopPictureInPicture()
        if let old = track, let renderer { Self.detach(renderer, from: old) }
        track = nil
        renderer = nil
        controller = nil
        sourceView = nil
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

    @MainActor init(groupID: String, name: String, emoji: String?, members people: [Person], me: Person? = nil) {
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
            if let me {
                // The picture includes me (LIME-150): the same plan as the chat's avatar.
                switch GroupAvatarPlan.make(others: people, me: me) {
                case .single(let person): addMember(person)
                case .pair(let front, let back): addMember(back); addMember(front)
                case .triangle(let people): for person in people { addMember(person) }
                case .ring(let shown, let extra): for person in shown { addMember(person) }; if extra > 0 { addMore(extra) }
                }
            } else {
                let shown = people.count > 4 ? Array(people.prefix(3)) : Array(people.prefix(4))
                for person in shown { addMember(person) }
                if people.count > shown.count { addMore(people.count - shown.count) }
            }
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
        // The same plan as the chat's avatar: overlapping circles with thin rings.
        let spots = GroupAvatarPlan.spots(circles: members.count)
        let d = side * spots.diameter
        for (index, member) in members.enumerated() {
            let at = spots.centres[min(index, spots.centres.count - 1)]
            member.circle.frame = CGRect(x: side / 2 + side * at.x - d / 2, y: side / 2 + side * at.y - d / 2, width: d, height: d)
            member.circle.layer.cornerRadius = d / 2
            member.circle.layer.borderWidth = members.count > 1 ? GroupAvatarPlan.ringWidth(side: side) : 0
            member.circle.layer.borderColor = UIColor(white: 0.08, alpha: 1).cgColor
            member.photo?.frame = member.circle.bounds
            member.label?.frame = member.circle.bounds
            member.label?.font = .systemFont(ofSize: d * 0.38, weight: .medium)
        }
    }
}

/// One wait for "possible": whichever of the observation and the timeout comes first resumes the caller, once.
private final class PossibleWait: @unchecked Sendable {
    private let lock = NSLock()
    var continuation: CheckedContinuation<Bool, Never>?
    var observation: NSKeyValueObservation?

    func finish(_ value: Bool) {
        lock.lock()
        let pending = continuation
        continuation = nil
        let watching = observation
        observation = nil
        lock.unlock()
        watching?.invalidate()
        pending?.resume(returning: value)
    }
}
