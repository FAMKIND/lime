import AVFoundation
import LiveKit
import UIKit

/// One cell as the window draws it: the plan's cell, who it is (for their photo) and their picture.
struct PiPGridDisplay {
    var cell: PiPGridPlan.Cell
    var person: Person?
    var track: AnyObject?
}

/// The minimised group call's grid (LIME-150): up to four cells in the system window, each a live picture (its own sample-buffer layer, the same
/// mechanism as the speaker window) or the person's photo, with a small name label; the person speaking has a lime ring and a bold label (the
/// ring and the weight, not colour alone). Plain UIKit like the other window views: the system moves this into its own window.
@MainActor
final class PiPGridView: UIView {
    @MainActor private final class Slot {
        let container = UIView()
        let video = PiPDisplayView()
        var photo: UIView?
        var photoKey: String?
        let label = UILabel()
        let pill = UIView()
        let ring = CALayer()
        var renderer: GroupPiPFrameRenderer!
        var track: (any VideoTrack)?
        var shownLive = false
    }

    static let maxCells = 4
    private var slots: [Slot] = []
    private var displays: [PiPGridDisplay] = []
    private var timer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // No backdrop of its own (LIME-150-fix3): the gaps show whatever the system's window draws behind the content.
        backgroundColor = .clear
        for _ in 0..<Self.maxCells {
            let slot = Slot()
            slot.container.clipsToBounds = true
            slot.container.addSubview(slot.video)
            slot.pill.backgroundColor = UIColor(white: 0, alpha: 0.55)
            slot.pill.layer.cornerRadius = 8
            slot.label.textColor = .white
            slot.label.adjustsFontSizeToFitWidth = true
            slot.label.minimumScaleFactor = 0.7
            slot.pill.addSubview(slot.label)
            slot.container.addSubview(slot.pill)
            slot.ring.borderColor = UIColor(red: 0.64, green: 0.88, blue: 0.54, alpha: 1).cgColor
            slot.ring.borderWidth = 0
            slot.container.layer.addSublayer(slot.ring)
            let video = slot.video
            slot.renderer = GroupPiPFrameRenderer(layer: video.displayLayer) { _, rotation, done in
                Task { @MainActor in video.rotation = rotation; video.setNeedsLayout(); done() }
            }
            slot.container.isHidden = true
            addSubview(slot.container)
            slots.append(slot)
        }
        // Until the first frame of a live picture arrives its photo stays up (never black).
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.settlePhotos() } }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// How many cells are drawn.
    var cellCount: Int { displays.count }
    /// Frames each cell has drawn so far, by participant id (the diagnostics).
    func frameCounts() -> [String: Int] {
        var out: [String: Int] = [:]
        for (index, item) in displays.enumerated() where index < slots.count { out[item.cell.id] = slots[index].renderer.frameCount }
        return out
    }

    /// Which cells draw a live picture (a test reads it).
    var liveFlags: [Bool] { displays.map(\.cell.live) }

    func update(_ new: [PiPGridDisplay]) {
        displays = Array(new.prefix(Self.maxCells))
        for (index, slot) in slots.enumerated() {
            guard index < displays.count else {
                slot.container.isHidden = true
                detach(slot)
                continue
            }
            let item = displays[index]
            slot.container.isHidden = false
            // Photo (or the "+N" cell).
            let key: String
            switch item.cell.kind {
            case .more(let extra): key = "more\(extra)"
            case .person: key = "p:\(item.cell.id)"
            }
            if slot.photoKey != key {
                slot.photo?.removeFromSuperview()
                let view: UIView
                if case .more(let extra) = item.cell.kind {
                    let holder = UIView()
                    holder.backgroundColor = UIColor(white: 0.14, alpha: 1)
                    let label = UILabel()
                    label.text = "+\(extra)"
                    label.textColor = .white
                    label.textAlignment = .center
                    label.font = .systemFont(ofSize: 34, weight: .semibold)
                    label.frame = holder.bounds
                    label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    holder.addSubview(label)
                    holder.isAccessibilityElement = true
                    holder.accessibilityLabel = "\(extra) more people"
                    view = holder
                } else if let person = item.person {
                    view = PiPAvatarView(person: person)
                } else {
                    view = UIView()
                }
                slot.container.insertSubview(view, aboveSubview: slot.video)
                slot.photo = view
                slot.photoKey = key
            }
            // The picture.
            let wanted = item.cell.live ? (item.track as? any VideoTrack) : nil
            slot.renderer.adaptiveSize = item.cell.speaking || displays.count == 1 ? CGSize(width: 360, height: 480) : CGSize(width: 240, height: 240)
            if wanted?.sid != slot.track?.sid {
                detach(slot)
                slot.video.displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
                slot.track = wanted
                if let wanted { let renderer = slot.renderer!; DispatchQueue.global(qos: .userInitiated).async { wanted.add(videoRenderer: renderer) } }
            }
            // The name and the speaking ring.
            slot.label.text = item.cell.isMe ? "You" : item.cell.name
            slot.label.font = .systemFont(ofSize: 11, weight: item.cell.speaking ? .bold : .regular)
            slot.pill.isHidden = { if case .more = item.cell.kind { return true } else { return false } }()
            slot.ring.borderWidth = item.cell.speaking ? 3 : 0
            slot.container.isAccessibilityElement = true
            slot.container.accessibilityLabel = [item.cell.isMe ? "You" : item.cell.name, item.cell.speaking ? "speaking" : nil].compactMap { $0 }.joined(separator: ", ")
            // Reorder the stacking so the photo is above the picture only while there is no live frame yet.
        }
        settlePhotos()
        setNeedsLayout()
    }

    func stop() {
        timer?.invalidate()
        for slot in slots { detach(slot) }
    }

    private func detach(_ slot: Slot) {
        if let old = slot.track { let renderer = slot.renderer!; DispatchQueue.global(qos: .userInitiated).async { old.remove(videoRenderer: renderer) } }
        slot.track = nil
        slot.shownLive = false
    }

    /// A live cell hides its photo once frames are arriving; a cell with no live picture shows its photo.
    private func settlePhotos() {
        for slot in slots where !slot.container.isHidden {
            let fresh = slot.track != nil && (slot.renderer.lastFrameAt.map { Date().timeIntervalSince($0) < 1.5 } ?? false)
            if fresh != slot.shownLive {
                slot.shownLive = fresh
                UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.15) { slot.photo?.alpha = fresh ? 0 : 1 }
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let frames = GroupCallLayout.pipGrid(count: displays.count, in: bounds.size)
        for (index, frame) in frames.enumerated() where index < slots.count {
            let slot = slots[index]
            slot.container.frame = frame
            let radius = GroupCallLayout.pipCornerRadius(for: frame.size)
            slot.container.layer.cornerRadius = radius
            slot.container.layer.cornerCurve = .continuous
            slot.ring.cornerRadius = radius
            slot.ring.cornerCurve = .continuous
            slot.video.frame = slot.container.bounds
            slot.photo?.frame = slot.container.bounds
            slot.ring.frame = slot.container.bounds
            let text = (slot.label.text ?? "") as NSString
            let width = min(frame.width - 8, text.size(withAttributes: [.font: slot.label.font as Any]).width + 14)
            slot.pill.frame = CGRect(x: 4, y: frame.height - 22, width: max(28, width), height: 18)
            slot.label.frame = slot.pill.bounds.insetBy(dx: 6, dy: 0)
        }
    }
}
