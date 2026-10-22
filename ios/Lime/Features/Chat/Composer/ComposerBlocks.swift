import UIKit

/// Arranging an article's blocks (LIME-188r). In the editor a block is a paragraph of its own: a picture, video or audio card (one object-replacement
/// character carrying `lime.image`) or a button, divider or freewall (a styled line carrying `lime.para`). Words are never blocks. This file finds the
/// blocks, moves and deletes them, and handles the long-press drag; the page's menu and VoiceOver actions use the same moves.
extension ComposerDocument {
    enum BlockKindName: Equatable {
        case picture, button(String), divider, freewall

        var label: String {
            switch self {
            case .picture: "Picture block"
            case .button(let text): "Button block, \(text)"
            case .divider: "Divider block"
            case .freewall: "Freewall block"
            }
        }

        /// What a lifted block is called while it moves.
        var short: String {
            switch self {
            case .picture: "Picture"
            case .button: "Button"
            case .divider: "Divider"
            case .freewall: "Freewall"
            }
        }
    }

    /// The paragraphs of the text, each as its range with the line break (the last one has none).
    static func paragraphRanges(of text: NSAttributedString) -> [NSRange] {
        let string = text.string as NSString
        guard string.length > 0 else { return [NSRange(location: 0, length: 0)] }
        var ranges: [NSRange] = []
        var location = 0
        while location < string.length {
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            ranges.append(range)
            location = NSMaxRange(range)
        }
        if string.hasSuffix("\n") { ranges.append(NSRange(location: string.length, length: 0)) }
        return ranges
    }

    /// What block, if any, paragraph `index` is.
    static func blockKind(ofParagraph index: Int, in text: NSAttributedString) -> BlockKindName? {
        let ranges = paragraphRanges(of: text)
        guard ranges.indices.contains(index), ranges[index].length > 0 else { return nil }
        let at = ranges[index].location
        if text.attribute(.limeImage, at: at, effectiveRange: nil) != nil { return .picture }
        switch paraStyle(in: text, at: at) {
        case "button":
            let string = (text.string as NSString).substring(with: ranges[index]).trimmingCharacters(in: .newlines)
            return .button(string)
        case "divider": return .divider
        case "freewall": return .freewall
        default: return nil
        }
    }

    /// The indexes of the blocks, in order.
    static func blockIndexes(in text: NSAttributedString) -> [Int] {
        paragraphRanges(of: text).indices.filter { blockKind(ofParagraph: $0, in: text) != nil }
    }

    /// The index of the paragraph the character offset is in.
    static func paragraphIndex(at location: Int, in text: NSAttributedString) -> Int {
        let ranges = paragraphRanges(of: text)
        for (index, range) in ranges.enumerated() where location >= range.location && location < NSMaxRange(range) { return index }
        return max(ranges.count - 1, 0)
    }

    /// Moves paragraph `index` so that it stands before the paragraph that is now at `boundary` (0 to the paragraph count; the count means the end).
    /// Returns the new index of the moved paragraph, or nil when nothing moved (it was dropped where it already is).
    @discardableResult
    static func moveParagraph(_ index: Int, toBoundary boundary: Int, in text: NSMutableAttributedString) -> Int? {
        let ranges = paragraphRanges(of: text)
        guard ranges.indices.contains(index), boundary >= 0, boundary <= ranges.count, boundary != index, boundary != index + 1 else { return nil }
        let range = ranges[index]
        let isLast = index == ranges.count - 1
        let hasBreak = range.length > 0 && (text.string as NSString).character(at: NSMaxRange(range) - 1) == 0x0A
        let contentRange = hasBreak ? NSRange(location: range.location, length: range.length - 1) : range
        let content = text.attributedSubstring(from: contentRange)
        // Take it out together with one line break.
        var removed = range
        if isLast || !hasBreak, range.location > 0 { removed = NSRange(location: range.location - 1, length: range.length + 1) }
        let startOfTarget = boundary < ranges.count ? ranges[boundary].location : text.length
        text.deleteCharacters(in: removed)
        var position = startOfTarget > range.location ? startOfTarget - removed.length : startOfTarget
        // Where it goes: before the paragraph at the boundary (its own line break after it), or at the end after a line break.
        let breakText = NSAttributedString(string: "\n", attributes: [.font: baseFont()])
        let insert = NSMutableAttributedString()
        if position >= text.length && text.length > 0 && !text.string.hasSuffix("\n") {
            insert.append(breakText); insert.append(content)
            position = text.length
        } else {
            insert.append(content); insert.append(breakText)
        }
        position = min(max(position, 0), text.length)
        text.insert(insert, at: position)
        restyle(text)
        return paragraphIndex(at: position + (insert.string.hasPrefix("\n") ? 1 : 0), in: text)
    }

    /// Takes paragraph `index` out, with its line break.
    static func deleteParagraph(_ index: Int, in text: NSMutableAttributedString) {
        let ranges = paragraphRanges(of: text)
        guard ranges.indices.contains(index) else { return }
        var range = ranges[index]
        let hasBreak = range.length > 0 && (text.string as NSString).character(at: NSMaxRange(range) - 1) == 0x0A
        if !hasBreak, range.location > 0 { range = NSRange(location: range.location - 1, length: range.length + 1) }
        text.deleteCharacters(in: range)
        restyle(text)
    }
}

// MARK: The model's side

/// A tap on a block asks for this menu.
struct BlockMenuRequest: Identifiable, Equatable {
    let id = UUID()
    let index: Int
    let kind: ComposerDocument.BlockKindName
}

extension RichComposerModel {
    /// Moves a block one place up or down among the paragraphs (one undo step).
    func moveBlock(_ index: Int, by step: Int) {
        guard let textView else { return }
        let count = ComposerDocument.paragraphRanges(of: textView.textStorage).count
        // Past the neighbouring paragraph: "up" goes before the previous one, "down" before the one after the next.
        let boundary = step < 0 ? index - 1 : index + 2
        guard boundary >= 0, boundary <= count else { return }
        arrangeBlock(index, toBoundary: boundary)
    }

    func arrangeBlock(_ index: Int, toBoundary boundary: Int) {
        guard let textView else { return }
        var moved: Int?
        undoable("Move") { moved = ComposerDocument.moveParagraph(index, toBoundary: boundary, in: textView.textStorage) }
        if let moved, let start = ComposerDocument.paragraphRanges(of: textView.textStorage)[safe: moved]?.location { textView.selectedRange = NSRange(location: start, length: 0) }
        didEdit()
        UIAccessibility.post(notification: .announcement, argument: moved == nil ? "Not moved" : "Moved")
    }

    func deleteBlock(_ index: Int) {
        guard let textView else { return }
        undoable("Delete") { ComposerDocument.deleteParagraph(index, in: textView.textStorage) }
        didEdit()
        UIAccessibility.post(notification: .announcement, argument: "Deleted")
    }

    /// The block's own button, as its parts, to edit.
    func buttonParts(at index: Int) -> (text: String, url: String, caption: String, colour: String)? {
        guard let textView, let range = ComposerDocument.paragraphRanges(of: textView.textStorage)[safe: index], range.length > 0,
              let url = textView.textStorage.attribute(.limeButton, at: range.location, effectiveRange: nil) as? String else { return nil }
        let text = (textView.text as NSString).substring(with: range).trimmingCharacters(in: .newlines)
        return (text, url, textView.textStorage.attribute(.limeButtonCaption, at: range.location, effectiveRange: nil) as? String ?? "",
                textView.textStorage.attribute(.limeButtonColour, at: range.location, effectiveRange: nil) as? String ?? "")
    }

    /// Changes a button in place (its words, caption and colour; its address too when it is a web address).
    func replaceButton(at index: Int, text: String, url: String, caption: String, colour: String) {
        guard let textView, let range = ComposerDocument.paragraphRanges(of: textView.textStorage)[safe: index], range.length > 0 else { return }
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        guard !words.isEmpty else { return }
        undoable("Edit button") {
            var content = range
            if (textView.text as NSString).character(at: NSMaxRange(range) - 1) == 0x0A { content.length -= 1 }
            var attributes: [NSAttributedString.Key: Any] = [.limePara: "button", .limeButton: url]
            let line = caption.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { attributes[.limeButtonCaption] = String(line.prefix(120)) }
            if !colour.isEmpty, colour != ButtonPalette.lime.rawValue { attributes[.limeButtonColour] = colour }
            textView.textStorage.replaceCharacters(in: content, with: NSAttributedString(string: words, attributes: attributes))
            ComposerDocument.restyle(textView.textStorage)
        }
        didEdit()
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: The page's interaction

/// On an article's text view: a marker over each block (the accessible way to move it, and a target for a tap), a tap that asks for the block's menu, and
/// a long press that lifts a block and drags it to a new place between paragraphs, with a drop line, auto-scroll near the edges and a haptic.
@MainActor
final class BlockInteraction: NSObject, UIGestureRecognizerDelegate {
    weak var view: ComposerTextView?
    weak var model: RichComposerModel?
    private var markers: [BlockMarker] = []
    private var lifted: Int?
    private var boundary: Int?
    private var snapshot: UIView?
    private let dropLine = UIView()
    private var scrollTimer: CADisplayLink?
    private var lastPoint: CGPoint = .zero
    private var lastWindowPoint: CGPoint = .zero

    init(view: ComposerTextView, model: RichComposerModel) {
        self.view = view
        self.model = model
        super.init()
        let press = UILongPressGestureRecognizer(target: self, action: #selector(longPress(_:)))
        press.minimumPressDuration = 0.4
        press.allowableMovement = 30
        press.delegate = self
        view.addGestureRecognizer(press)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        dropLine.backgroundColor = UIColor(Theme.accent)
        dropLine.layer.cornerRadius = 1.5
        dropLine.isHidden = true
        dropLine.isUserInteractionEnabled = false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    /// The text view's own long presses (the loupe, a text drag) wait for this one: on a block it takes the press; on words it gives up at once.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        gestureRecognizer is UILongPressGestureRecognizer && other is UILongPressGestureRecognizer && other !== gestureRecognizer
    }

    /// Only a press on a block lifts it: words keep the text view's own press (the loupe, selection and the system's text drag).
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let view else { return false }
        return block(at: gestureRecognizer.location(in: view)) != nil
    }

    // MARK: Finding blocks

    private func rect(ofParagraph index: Int) -> CGRect? {
        guard let view else { return nil }
        let ranges = ComposerDocument.paragraphRanges(of: view.textStorage)
        guard ranges.indices.contains(index) else { return nil }
        var range = ranges[index]
        if range.length == 0 { return view.caretRect(for: view.position(from: view.beginningOfDocument, offset: range.location) ?? view.endOfDocument) }
        if (view.text as NSString).character(at: NSMaxRange(range) - 1) == 0x0A, range.length > 1 { range.length -= 1 }
        guard let start = view.position(from: view.beginningOfDocument, offset: range.location), let end = view.position(from: start, offset: range.length), let text = view.textRange(from: start, to: end) else { return nil }
        let rects = view.selectionRects(for: text).map(\.rect).filter { !$0.isEmpty }
        guard var union = rects.first else { return view.firstRect(for: text) }
        for r in rects.dropFirst() { union = union.union(r) }
        return union
    }

    private func block(at point: CGPoint) -> (index: Int, kind: ComposerDocument.BlockKindName)? {
        guard let view else { return nil }
        for index in ComposerDocument.blockIndexes(in: view.textStorage) {
            guard let rect = rect(ofParagraph: index)?.insetBy(dx: -view.bounds.width, dy: -4) else { continue }
            if point.y >= rect.minY, point.y <= rect.maxY, let kind = ComposerDocument.blockKind(ofParagraph: index, in: view.textStorage) { return (index, kind) }
        }
        return nil
    }

    // MARK: Markers

    /// One accessible marker over each block: "Picture", "Button, Get the worksheet", with Move up, Move down and Delete as custom actions.
    func refreshMarkers() {
        guard let view, let model else { return }
        let indexes = ComposerDocument.blockIndexes(in: view.textStorage)
        while markers.count < indexes.count {
            let marker = BlockMarker()
            marker.isUserInteractionEnabled = false
            view.addSubview(marker)
            markers.append(marker)
        }
        for (number, marker) in markers.enumerated() {
            guard number < indexes.count, let rect = rect(ofParagraph: indexes[number]), let kind = ComposerDocument.blockKind(ofParagraph: indexes[number], in: view.textStorage) else { marker.isHidden = true; marker.isAccessibilityElement = false; continue }
            let index = indexes[number]
            marker.isHidden = false
            marker.frame = CGRect(x: view.textContainerInset.left, y: rect.minY, width: max(view.bounds.width - view.textContainerInset.left - view.textContainerInset.right, 44), height: max(rect.height, 44))
            marker.isAccessibilityElement = true
            marker.accessibilityLabel = kind.label
            marker.accessibilityValue = "Block \(number + 1) of \(indexes.count)"
            marker.accessibilityTraits = .button
            marker.accessibilityHint = "Opens the block's menu. Actions: move up, move down, delete."
            marker.accessibilityIdentifier = "block-\(number)"
            marker.activate = { [weak model] in model?.blockMenu = BlockMenuRequest(index: index, kind: kind) }
            marker.accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: "Move up") { [weak model] _ in model?.moveBlock(index, by: -1); return true },
                UIAccessibilityCustomAction(name: "Move down") { [weak model] _ in model?.moveBlock(index, by: 1); return true },
                UIAccessibilityCustomAction(name: "Delete") { [weak model] _ in model?.deleteBlock(index); return true },
            ]
        }
    }

    // MARK: Tap

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, let view, lifted == nil, let (index, kind) = block(at: gesture.location(in: view)) else { return }
        model?.blockMenu = BlockMenuRequest(index: index, kind: kind)
    }

    // MARK: Drag

    @objc private func longPress(_ gesture: UILongPressGestureRecognizer) {
        guard let view else { return }
        let point = gesture.location(in: view)
        lastWindowPoint = gesture.location(in: nil)
        switch gesture.state {
        case .began:
            guard let (index, kind) = block(at: point), let rect = rect(ofParagraph: index) else { return }
            lifted = index
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            let frame = CGRect(x: 0, y: rect.minY, width: view.bounds.width, height: max(rect.height, 30))
            let lift = view.resizableSnapshotView(from: frame, afterScreenUpdates: false, withCapInsets: .zero) ?? UIView(frame: frame)
            lift.frame = frame
            lift.layer.shadowColor = UIColor.black.cgColor
            lift.layer.shadowOpacity = 0.25
            lift.layer.shadowRadius = 10
            lift.layer.shadowOffset = CGSize(width: 0, height: 4)
            lift.alpha = 0.92
            lift.isUserInteractionEnabled = false
            view.addSubview(lift)
            view.addSubview(dropLine)
            if !UIAccessibility.isReduceMotionEnabled { UIView.animate(withDuration: 0.15) { lift.transform = CGAffineTransform(scaleX: 1.03, y: 1.03) } }
            snapshot = lift
            UIAccessibility.post(notification: .announcement, argument: "\(kind.short) lifted")
            startScrolling()
            update(point)
        case .changed:
            update(point)
        case .ended:
            if let from = lifted, let to = boundary { model?.arrangeBlock(from, toBoundary: to) }
            finish()
        default:
            finish()
        }
    }

    private func update(_ point: CGPoint) {
        guard let view else { return }
        lastPoint = point
        snapshot?.center.y = point.y
        // The drop line goes between paragraphs: before the first one whose middle is below the finger, else after the last.
        let ranges = ComposerDocument.paragraphRanges(of: view.textStorage)
        var target = ranges.count
        var y: CGFloat = rect(ofParagraph: ranges.count - 1)?.maxY ?? 0
        for index in ranges.indices {
            guard let r = rect(ofParagraph: index) else { continue }
            if point.y < r.midY { target = index; y = r.minY - 2; break }
        }
        boundary = target
        dropLine.frame = CGRect(x: view.textContainerInset.left, y: y - 1, width: max(view.bounds.width - view.textContainerInset.left - view.textContainerInset.right, 40), height: 3)
        dropLine.isHidden = (target == lifted || target == (lifted ?? -9) + 1)
    }

    private func startScrolling() {
        scrollTimer?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(scrollTick))
        link.add(to: .main, forMode: .common)
        scrollTimer = link
    }

    /// Near the top or bottom of what is showing, the page scrolls on its own so a block can be carried a long way.
    @objc private func scrollTick() {
        guard let view, lifted != nil else { return }
        var ancestor = view.superview
        while let candidate = ancestor, !(candidate is UIScrollView) { ancestor = candidate.superview }
        guard let scroll = ancestor as? UIScrollView else { return }
        let inScroll = view.convert(lastPoint, to: scroll)
        let visibleTop = scroll.contentOffset.y + scroll.adjustedContentInset.top
        let visibleBottom = scroll.contentOffset.y + scroll.bounds.height - scroll.adjustedContentInset.bottom
        var delta: CGFloat = 0
        if inScroll.y < visibleTop + 80 { delta = -8 } else if inScroll.y > visibleBottom - 80 { delta = 8 }
        guard delta != 0 else { return }
        let maxOffset = max(scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom, -scroll.adjustedContentInset.top)
        let next = min(max(scroll.contentOffset.y + delta, -scroll.adjustedContentInset.top), maxOffset)
        guard next != scroll.contentOffset.y else { return }
        scroll.contentOffset.y = next
        update(view.convert(lastWindowPoint, from: nil))
    }

    private func finish() {
        scrollTimer?.invalidate()
        scrollTimer = nil
        snapshot?.removeFromSuperview()
        snapshot = nil
        dropLine.isHidden = true
        dropLine.removeFromSuperview()
        lifted = nil
        boundary = nil
    }
}

/// The accessible stand-in over a block: it can be activated, and offers the move and delete actions.
final class BlockMarker: UIView {
    var activate: (() -> Void)?
    override func accessibilityActivate() -> Bool { activate?(); return activate != nil }
}
