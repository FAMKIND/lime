import SwiftUI

/// Finds where a caret belongs after the text around it was changed by someone else (LIME-233c): the characters just before and after the caret are
/// looked for in the new text, nearest to the old place first, so the caret stays on the same word when another author types earlier in the page.
enum CaretAnchor {
    static func relocate(_ caret: Int, in old: String, to new: String, context: Int = 8) -> Int {
        let oldChars = Array(old.utf16), newChars = Array(new.utf16)
        let caret = min(max(caret, 0), oldChars.count)
        func find(before: Int, after: Int) -> Int? {
            let lo = max(caret - before, 0), hi = min(caret + after, oldChars.count)
            let needle = Array(oldChars[lo..<hi])
            guard !needle.isEmpty, newChars.count >= needle.count else { return nil }
            var best: (distance: Int, at: Int)?
            for start in 0...(newChars.count - needle.count) where Array(newChars[start..<start + needle.count]) == needle {
                let at = start + (caret - lo)
                let distance = abs(at - caret)
                if best == nil || distance < best!.distance { best = (distance, at) }
            }
            return best?.at
        }
        return find(before: context, after: context) ?? find(before: context, after: 0) ?? find(before: 0, after: context) ?? min(caret, newChars.count)
    }
}

/// How a session reaches the sheet's list of files (the article's pictures by index) without owning it.
struct CoEditFiles {
    /// A file by its place in the sheet's list.
    var file: (Int) -> OutgoingAttachment?
    /// Puts a file at the end of the list; returns its place.
    var add: (OutgoingAttachment) -> Int
    /// Replaces the file at a place (the bytes arrived).
    var fill: (Int, OutgoingAttachment) -> Void
    /// The width pictures are drawn at.
    var width: () -> CGFloat
    /// The title and subtitle fields (the sheet's own state).
    var title: () -> String = { "" }
    var subtitle: () -> String = { "" }
    var setTitle: (String) -> Void = { _ in }
    var setSubtitle: (String) -> Void = { _ in }
    /// Where this author's caret is when it is in the title or subtitle: the field, the caret and the other end of a selection, in characters.
    var focusedField: () -> (field: String, caret: Int, end: Int)? = { nil }
}

/// The article editor's link to its shared draft (LIME-233c, DESIGN-22): every change in the editor is handed to LimeCore as the fewest operations, a
/// remote author's changes come back and are drawn without moving the caret. Nothing here is a view.
@MainActor
final class CoEditSession {
    let draftID: String
    private let store: ConversationStore
    private var pending: Task<Void, Never>?
    /// The draft's heads when the editor last showed exactly the draft (before this author's edits since): edits are merged from there, so another author's
    /// words that reached the draft first are kept and shown, never reverted.
    private var baseHeads: [String] = []
    private var pendingMerge = false
    private var sendTask: Task<Void, Never>?
    /// While the editor itself is being rewritten with someone else's words, its changes are not the person's.
    private(set) var applyingRemote = false
    /// The other authors of this draft and where they are (LIME-233d).
    let peers = CoEditPeers()
    private var cursors: PeerCursorLayer?
    private weak var composer: RichComposerModel?
    private var ticker: Task<Void, Never>?
    private var lastTyped = Date.distantPast
    private var lastPresence = Date.distantPast
    private var lastFlush = Date.distantPast
    private var lastStatus = Date.distantPast
    /// The pictures: the editor's own numbers (places in the sheet's list) and the draft's (what every author calls the file).
    var files: CoEditFiles?
    private var draftNumber: [Int: UInt32] = [:]
    private var localIndex: [UInt32: Int] = [:]
    private var previews: [Int: UIImage] = [:]
    private var fetching: Set<UInt32> = []
    #if DEBUG
    var simStatus: DraftStatus?
    #endif

    init(draftID: String, store: ConversationStore) {
        self.draftID = draftID
        self.store = store
        baseHeads = store.coeditHeads(draftID)   // the editor is filled from the draft as it is now
    }

    /// The editor has just been filled from the draft: edits count from here.
    func rebase() { baseHeads = store.coeditHeads(draftID) }

    /// The editor (or the title or subtitle) changed: at once, the change is merged into the draft from the point where the editor last matched it
    /// (nothing to wait for, so no other author's words can be overwritten), and goes out on the instant path within 50 ms.
    func editorChanged(title: String, subtitle: String, composer: RichComposerModel) {
        guard !applyingRemote else { return }
        lastTyped = .now
        merge(composer: composer)
        sendPresence(composer, force: true)
    }

    /// Hands the editor to the draft and takes back what others wrote. `true` when the editor showed something new.
    @discardableResult
    func merge(composer: RichComposerModel) -> Bool {
        guard let view = composer.textView, let host = files else { return false }
        if view.markedTextRange != nil { pendingMerge = true; return false }   // while a letter is being composed, later
        pendingMerge = false
        let title = host.title(), subtitle = host.subtitle()
        let mine = draftMarkdown(from: view.textStorage)
        guard let heads = store.coeditMerge(draftID, base: baseHeads, title: title, subtitle: subtitle, markdown: mine) else { return false }
        let local = heads != baseHeads
        baseHeads = heads
        guard let merged = store.coeditMarkdown(draftID), let meta = store.coeditMeta(draftID) else { return false }
        var changed = false
        if merged != mine {
            applyingRemote = true
            defer { applyingRemote = false }
            harvestPictures(from: view.textStorage)
            CoEditSplice.apply(render(markdown: merged), into: view)
            composer.didEdit()
            changed = true
        }
        if meta.title != title { host.setTitle(meta.title); changed = true }
        if meta.subtitle != subtitle { host.setSubtitle(meta.subtitle); changed = true }
        if local || changed { scheduleSend() }
        return changed
    }

    /// Instant sends are at most one every 50 ms (a burst of typing is one small message).
    private func scheduleSend() {
        guard sendTask == nil else { return }
        sendTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard let self else { return }
            sendTask = nil
            store.sendDraftChangeInstantly(draftID)
        }
    }

    /// Other authors' changes reached the draft (instant message, sync): the editor takes them in place.
    func applyRemote() {
        guard let composer else { return }
        _ = store.coeditTakePatches(draftID)
        merge(composer: composer)
    }

    func syncNow(title: String, subtitle: String, markdown: String) {
        pending?.cancel()
        if let composer { merge(composer: composer) }
    }

    /// The editor's text as the draft knows it: each picture goes by the number every author uses for the file (the file is added to the draft the
    /// first time it is seen), not by its place in this phone's list.
    func draftMarkdown(from storage: NSAttributedString) -> String {
        let copy = NSMutableAttributedString(attributedString: storage)
        copy.enumerateAttribute(.limeImage, in: NSRange(location: 0, length: copy.length)) { value, range, _ in
            guard let local = value as? Int, let number = number(forLocal: local) else { return }
            copy.addAttribute(.limeImage, value: Int(number), range: range)
        }
        return ComposerDocument.markdown(from: copy, post: true)
    }

    private func number(forLocal local: Int) -> UInt32? {
        if let known = draftNumber[local] { return known }
        guard let file = files?.file(local), !file.bytes.isEmpty, let number = store.coeditAddFile(draftID, file) else { return nil }
        draftNumber[local] = number; localIndex[number] = local
        return number
    }

    /// Keeps the pictures that are in the editor now, so a redraw can put them back.
    func harvestPictures(from storage: NSAttributedString) {
        storage.enumerateAttribute(.limeImage, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let local = value as? Int, let attachment = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment, let image = attachment.image else { return }
            previews[local] = image
        }
    }

    func notePicture(local: Int, image: UIImage) { previews[local] = image }

    /// Post Markdown (the draft's) as editor text: pictures by this phone's numbers and drawn; pictures other authors added get a place in the list
    /// and are fetched if this phone does not have them yet.
    func render(markdown: String) -> NSMutableAttributedString {
        let text = ComposerDocument.attributed(fromMarkdown: markdown, post: true)
        var infos: [DraftFileInfo]?
        text.enumerateAttribute(.limeImage, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let number = (value as? Int).flatMap(UInt32.init(exactly:)) else { return }
            if let local = localIndex[number] { text.addAttribute(.limeImage, value: local, range: range); return }
            infos = infos ?? store.coeditFiles(draftID)
            guard let info = infos?.first(where: { $0.number == number }), let files else { return }   // not a shared file: the number stands
            let local = files.add(OutgoingAttachment(bytes: Data(), name: info.name, mime: info.mime, width: info.width, height: info.height, durationMs: info.durationMs, thumb: info.thumb, poster: info.poster))
            draftNumber[local] = number; localIndex[number] = local
            if let thumb = UIImage(data: info.thumb) { previews[local] = thumb }
            fetch(number: number, local: local)
            text.addAttribute(.limeImage, value: local, range: range)
        }
        ComposerDocument.attachImages(in: text, width: files?.width() ?? 300) { previews[$0] ?? Self.placeholder }
        return text
    }

    private static let placeholder: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 360)).image { context in
        UIColor.secondarySystemBackground.setFill()
        UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 600, height: 360), cornerRadius: 24).fill()
    }

    private func fetch(number: UInt32, local: Int) {
        guard !fetching.contains(number) else { return }
        fetching.insert(number)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { fetching.remove(number) }
            guard let data = await store.coeditFileData(draftID, number) else { return }
            let info = store.coeditFiles(draftID).first { $0.number == number }
            files?.fill(local, OutgoingAttachment(bytes: data, name: info?.name ?? "", mime: info?.mime ?? "image/jpeg", width: info?.width, height: info?.height, durationMs: info?.durationMs, thumb: info?.thumb ?? Data(), poster: info?.poster ?? Data()))
            if let image = UIImage(data: data) { previews[local] = image.preparingThumbnail(of: CGSize(width: 900, height: 900)) ?? image }
            redrawPictures()
        }
    }

    /// Draws the pictures again where they are (a file arrived); the text, the caret and the keyboard are not touched.
    private func redrawPictures() {
        guard let view = composer?.textView, view.markedTextRange == nil else { return }
        let width = files?.width() ?? 300
        ComposerDocument.attachImages(in: view.textStorage, width: width) { previews[$0] }
        view.layoutManager.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: view.textStorage.length))
    }

    /// The draft as post Markdown, after the editor's latest state was handed over.
    func exportMarkdown() -> String? { store.coeditMarkdown(draftID) }
}

// MARK: Writing together (LIME-233d)

/// An author's colour in the page (cursor, tag, selection): their avatar tone, darkened (light mode) or lightened (dark mode) until it reads at 3:1
/// against the page, so a pastel never disappears.
enum PeerColor {
    static func color(tone: Int, dark: Bool) -> UIColor {
        let base = Theme.avatarUIColor(tone, dark: dark)
        let page: CGFloat = dark ? 0.0 : 1.0   // black or white page
        var colour = base
        for _ in 0..<40 where contrast(colour, page: page) < 3.0 {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            colour.getRed(&r, green: &g, blue: &b, alpha: &a)
            let step: CGFloat = 0.06
            colour = dark ? UIColor(red: r + (1 - r) * step, green: g + (1 - g) * step, blue: b + (1 - b) * step, alpha: 1)
                          : UIColor(red: r * (1 - step), green: g * (1 - step), blue: b * (1 - step), alpha: 1)
        }
        return colour
    }

    /// WCAG contrast between a colour and a grey page.
    static func contrast(_ colour: UIColor, page: CGFloat) -> CGFloat {
        let a = luminance(colour), b = page
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    static func luminance(_ colour: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// Text on a tag in that colour: white or black, whichever reads better.
    static func ink(on colour: UIColor) -> UIColor { luminance(colour) > 0.4 ? .black : .white }
}

/// Where the draft's blocks sit in the editor's text. The editor shows the blocks as lines (a paragraph may run over several lines, a list item has a
/// marker), so each text block takes the next lines that make up its words.
enum CoEditMap {
    struct Slot { let id: String; let range: NSRange; let words: String; let ordinal: Int }

    private static let textKinds: Set<String> = ["paragraph", "h1", "h2", "h3", "h4", "h5", "h6", "quote", "indent", "item", "code"]

    static func slots(blocks: [DraftBlock], in text: NSAttributedString) -> [Slot] {
        let string = text.string as NSString
        var lines: [(range: NSRange, words: String)] = []
        var at = 0
        while at < string.length {
            let line = string.paragraphRange(for: NSRange(location: at, length: 0))
            at = NSMaxRange(line)
            var content = line
            if content.length > 0, string.substring(with: NSRange(location: NSMaxRange(content) - 1, length: 1)) == "\n" { content.length -= 1 }
            if let marker = ComposerDocument.markerRange(in: text, paragraph: line) { content = NSRange(location: NSMaxRange(marker), length: max(NSMaxRange(content) - NSMaxRange(marker), 0)) }
            let words = string.substring(with: content)
            if words.contains("\u{FFFC}") { lines.append((content, "")); continue }   // pictures take no words
            lines.append((content, words))
        }
        var out: [Slot] = []
        var next = 0
        var ordinal = 0
        for block in blocks where textKinds.contains(block.kind) {
            let target = block.spans.map(\.text).joined()
            guard !target.isEmpty else { continue }
            while next < lines.count, lines[next].words.isEmpty { next += 1 }
            guard next < lines.count else { break }
            let first = next
            var joined = ""
            while next < lines.count {
                joined += (joined.isEmpty ? "" : "\n") + lines[next].words
                next += 1
                if joined.count >= target.count { break }
            }
            let start = lines[first].range.location
            let end = NSMaxRange(lines[next - 1].range)
            ordinal += 1
            out.append(Slot(id: block.id, range: NSRange(location: start, length: end - start), words: target, ordinal: ordinal))
        }
        return out
    }

    /// The editor position of a character offset in a block.
    static func position(blockID: String, offset: Int, in slots: [Slot]) -> Int? {
        guard let slot = slots.first(where: { $0.id == blockID }) else { return nil }
        let prefix = String(slot.words.prefix(offset))
        return min(slot.range.location + prefix.utf16.count, NSMaxRange(slot.range))
    }

    /// The block and character offset of an editor position (nil: the caret is in a picture or a block with no words).
    static func place(_ position: Int, in slots: [Slot]) -> (blockID: String, offset: Int)? {
        guard let slot = slots.first(where: { position >= $0.range.location && position <= NSMaxRange($0.range) }) else { return nil }
        let utf16 = min(position - slot.range.location, slot.words.utf16.count)
        let index = String.Index(utf16Offset: utf16, in: slot.words)
        return (slot.id, slot.words.distance(from: slot.words.startIndex, to: index))
    }

    static func ordinalWords(_ n: Int) -> String {
        let words = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]
        return n >= 1 && n <= words.count ? "the \(words[n - 1]) paragraph" : "paragraph \(n)"
    }
}

/// Who else is in this draft and where their cursors are. Fed by the instant channel (and the durable path's authors list).
@MainActor
@Observable
final class CoEditPeers {
    struct Peer: Identifiable {
        let person: Person
        var presence: DraftPresence?
        var lastSeen: Date
        var lastMoved: Date
        var lastTyped: Date?
        var id: String { person.id }
        var tone: Int { person.tone }
    }

    private(set) var peers: [Peer] = []
    /// Where the draft stands between its authors and the post (nil: nobody else writes it).
    private(set) var status: DraftStatus?
    /// A co-author's own "Ready" (so the button answers at once).
    var iAmReady = false
    func setStatus(_ new: DraftStatus?) { if new != status { status = new } }
    private(set) var tick = 0   // changes whenever something about the peers does, so views redraw

    /// The other authors, from the draft group (they are shown even before they have been seen live).
    func setAuthors(_ people: [Person]) {
        let keep = people.map { person in peers.first(where: { $0.id == person.id }) ?? Peer(person: person, presence: nil, lastSeen: .distantPast, lastMoved: .distantPast, lastTyped: nil) }
        peers = keep
        tick += 1
    }

    func receive(from userID: String, presence: DraftPresence?, now: Date = .now) {
        guard let at = peers.firstIndex(where: { $0.id == userID }) else { return }
        peers[at].lastSeen = now
        if let presence {
            if presence.away { peers[at].presence = nil; peers[at].lastSeen = .distantPast } else {
                let moved = peers[at].presence.map { $0.field != presence.field || $0.blockId != presence.blockId || $0.offset != presence.offset || $0.endOffset != presence.endOffset || $0.endBlockId != presence.endBlockId } ?? true
                if moved { peers[at].lastMoved = now }
                if presence.typing { peers[at].lastTyped = now }
                peers[at].presence = presence
            }
        } else {
            peers[at].lastTyped = now   // their words arrived
        }
        tick += 1
    }

    func isLive(_ peer: Peer, now: Date = .now) -> Bool { now.timeIntervalSince(peer.lastSeen) < 25 }
    func isEditing(_ peer: Peer, now: Date = .now) -> Bool { peer.lastTyped.map { now.timeIntervalSince($0) < 5 } ?? false }
}

/// The other authors' carets, name tags and selections, drawn inside the editor's text view so they scroll with the page. It takes no touches.
@MainActor
final class PeerCursorLayer: UIView {
    private var tags: [String: UIView] = [:]
    private var carets: [String: UIView] = [:]
    private var selections: [String: [UIView]] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Redraws everyone. `slots` says where the draft's blocks are in the text.
    func refresh(peers: [CoEditPeers.Peer], in textView: UITextView, slots: [CoEditMap.Slot], now: Date = .now) {
        frame = CGRect(origin: .zero, size: textView.contentSize)
        let dark = textView.traitCollection.userInterfaceStyle == .dark
        var seen = Set<String>()
        for peer in peers {
            guard let presence = peer.presence, presence.field.isEmpty || presence.field == "body", now.timeIntervalSince(peer.lastSeen) < 25,
                  let at = CoEditMap.position(blockID: presence.blockId, offset: Int(presence.offset), in: slots),
                  let caretPos = textView.position(from: textView.beginningOfDocument, offset: at) else { continue }
            seen.insert(peer.id)
            let colour = PeerColor.color(tone: peer.tone, dark: dark)
            let caretRect = textView.caretRect(for: caretPos)
            let caret = carets[peer.id] ?? { let v = UIView(); v.isUserInteractionEnabled = false; addSubview(v); carets[peer.id] = v; return v }()
            caret.backgroundColor = colour
            caret.frame = CGRect(x: caretRect.minX - 1, y: caretRect.minY, width: 2, height: caretRect.height)
            // The selection: the other end is another place in the text.
            for old in selections[peer.id] ?? [] { old.removeFromSuperview() }
            selections[peer.id] = []
            if !presence.endBlockId.isEmpty, let endAt = CoEditMap.position(blockID: presence.endBlockId, offset: Int(presence.endOffset), in: slots), endAt != at,
               let a = textView.position(from: textView.beginningOfDocument, offset: min(at, endAt)), let b = textView.position(from: textView.beginningOfDocument, offset: max(at, endAt)),
               let range = textView.textRange(from: a, to: b) {
                for rect in textView.selectionRects(for: range) where !rect.rect.isEmpty {
                    let v = UIView(frame: rect.rect)
                    v.backgroundColor = colour.withAlphaComponent(0.28); v.isUserInteractionEnabled = false
                    insertSubview(v, at: 0)
                    selections[peer.id]?.append(v)
                }
            }
            // The tag (their photo and first name) above the caret; after 3 s without a move it fades, and a move brings it back.
            let tag = tags[peer.id] ?? makeTag(for: peer, colour: colour)
            tags[peer.id] = tag
            tag.backgroundColor = colour
            tag.accessibilityIdentifier = "coedit-cursor-\(peer.id)"
            tag.accessibilityLabel = "\(peer.person.name.split(separator: " ").first.map(String.init) ?? peer.person.name)\u{2019}s cursor"
            let size = tag.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            tag.frame = CGRect(x: max(caretRect.minX - 1, 0), y: max(caretRect.minY - size.height - 1, 0), width: size.width, height: size.height)
            let idle = now.timeIntervalSince(peer.lastMoved) > 3
            UIView.animate(withDuration: 0.25) { tag.alpha = idle ? 0 : 1 }
            addSubview(caret); addSubview(tag)
        }
        for (id, view) in tags where !seen.contains(id) { view.removeFromSuperview(); tags[id] = nil; carets[id]?.removeFromSuperview(); carets[id] = nil; selections[id]?.forEach { $0.removeFromSuperview() }; selections[id] = nil }
    }

    private func makeTag(for peer: CoEditPeers.Peer, colour: UIColor) -> UIView {
        let tag = UIView()
        tag.layer.cornerRadius = 6; tag.clipsToBounds = true
        tag.isUserInteractionEnabled = false
        tag.isAccessibilityElement = true
        let ink = PeerColor.ink(on: colour)
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = ink
        label.text = peer.person.name.split(separator: " ").first.map(String.init) ?? peer.person.name
        let face = UIImageView()
        face.layer.cornerRadius = 10; face.clipsToBounds = true; face.contentMode = .scaleAspectFill
        if let photo = AvatarCache.shared.image(for: peer.person.id) { face.image = photo } else {
            face.backgroundColor = ink.withAlphaComponent(0.25)
            let initial = UILabel(); initial.text = String(peer.person.initials.prefix(1)); initial.font = .systemFont(ofSize: 11, weight: .bold); initial.textColor = ink; initial.textAlignment = .center
            initial.frame = CGRect(x: 0, y: 0, width: 20, height: 20); face.addSubview(initial)
        }
        let stack = UIStackView(arrangedSubviews: [face, label])
        stack.axis = .horizontal; stack.spacing = 5; stack.alignment = .center
        stack.layoutMargins = UIEdgeInsets(top: 3, left: 4, bottom: 3, right: 8); stack.isLayoutMarginsRelativeArrangement = true
        face.widthAnchor.constraint(equalToConstant: 20).isActive = true
        face.heightAnchor.constraint(equalToConstant: 20).isActive = true
        tag.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: tag.leadingAnchor), stack.trailingAnchor.constraint(equalTo: tag.trailingAnchor), stack.topAnchor.constraint(equalTo: tag.topAnchor), stack.bottomAnchor.constraint(equalTo: tag.bottomAnchor)])
        return tag
    }
}


// MARK: The session in the editor: presence, cursors, the clock

extension CoEditSession {
    /// The other active authors of the draft, from the draft group.
    func reloadAuthors() {
        let me = store.meProvider().id
        let people = store.coeditAuthors(draftID).filter { $0 != me }.map { store.teacher($0) }
        peers.setAuthors(people)
    }

    /// The other authors as people (for the co-author chips).
    func otherAuthors() -> [Person] {
        let me = store.meProvider().id
        return store.coeditAuthors(draftID).filter { $0 != me }.map { store.teacher($0) }
    }

    /// The editor is on screen: cursors are drawn in it, my place is sent, the durable path is flushed. Safe to call again.
    func start(composer: RichComposerModel) {
        self.composer = composer
        #if DEBUG
        simulateRoleIfAsked()
        #endif
        store.draftEventSink = { [weak self] event in self?.receive(event) }
        if !store.isDemo { reloadAuthors() }
        refreshStatus()
        if let view = composer.textView, cursors == nil {
            let layer = PeerCursorLayer(frame: .zero)
            view.addSubview(layer)
            cursors = layer
        }
        guard ticker == nil else { return }
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                self?.tick()
            }
        }
    }

    /// The editor went away: others see me leave; nothing more is drawn.
    func stop() {
        ticker?.cancel(); ticker = nil
        store.draftEventSink = nil
        if let composer { sendPresence(composer, force: true, away: true) }
        cursors?.removeFromSuperview(); cursors = nil
    }

    private func tick() {
        guard let composer else { return }
        if pendingMerge { merge(composer: composer) }
        redrawCursors()
        let now = Date.now
        if now.timeIntervalSince(lastPresence) > 10 { sendPresence(composer, force: true) }   // a heartbeat: "I am here"
        if now.timeIntervalSince(lastStatus) > 2 { lastStatus = now; refreshStatus() }
        if now.timeIntervalSince(lastFlush) > 5 {
            lastFlush = now
            Task { await store.flushDrafts() }
            if !store.isDemo { reloadAuthors() }
        }
    }

    /// Who publishes, who is ready, whether it was published.
    func refreshStatus() {
        #if DEBUG
        if let sim = simStatus { peers.setStatus(sim); return }
        #endif
        guard store.coeditAuthors(draftID).count > 1 else { peers.setStatus(nil); return }
        peers.setStatus(store.coeditStatus(draftID))
    }

    /// Co-author: "Ready" tells the writer; tapping again takes it back.
    func toggleReady() {
        peers.iAmReady.toggle()
        #if DEBUG
        if simStatus != nil { return }
        #endif
        store.coeditSetReady(draftID, peers.iAmReady)
    }

    /// The draft has more than one author and someone else is the writer: no Post or Update here.
    var isCoAuthorOnly: Bool { peers.status.map { !$0.writer.isEmpty && !$0.isWriter } ?? false }
    var isShared: Bool { peers.status.map { !$0.writer.isEmpty } ?? false }

    /// The writer published or updated the post: the other authors are told.
    func published(postID: String?) {
        guard let postID, isShared else { return }
        store.coeditPublished(draftID, postID: postID)
    }

    func redrawCursors() {
        guard let view = composer?.textView, let cursors else { return }
        let slots = CoEditMap.slots(blocks: store.coeditBlocks(draftID), in: view.textStorage)
        cursors.refresh(peers: peers.peers, in: view, slots: slots)
    }

    /// My caret and selection, as the block and the characters in it. Not more than ten times a second unless forced.
    func sendPresence(_ composer: RichComposerModel, force: Bool = false, away: Bool = false) {
        guard let view = composer.textView else { return }
        let now = Date.now
        guard force || now.timeIntervalSince(lastPresence) > 0.1 else { return }
        lastPresence = now
        let typing = now.timeIntervalSince(lastTyped) < 1.5
        if !away, let field = files?.focusedField(), !view.isFirstResponder {
            store.sendDraftPresence(draftID, DraftPresence(field: field.field, blockId: "", offset: UInt32(field.caret), endBlockId: "", endOffset: UInt32(field.end), typing: typing, away: false))
            return
        }
        let slots = CoEditMap.slots(blocks: store.coeditBlocks(draftID), in: view.textStorage)
        let range = view.selectedRange
        guard away || view.isFirstResponder, let start = CoEditMap.place(range.location, in: slots) ?? (away ? ("", 0) : nil) else { return }
        let end = range.length > 0 ? CoEditMap.place(range.location + range.length, in: slots) : nil
        let presence = DraftPresence(field: "body", blockId: start.0, offset: UInt32(start.1), endBlockId: end?.blockID ?? "", endOffset: UInt32(end?.offset ?? 0), typing: typing, away: away)
        store.sendDraftPresence(draftID, presence)
    }

    /// The caret moved in the title or subtitle.
    func fieldMoved() { if let composer { sendPresence(composer, force: true) } }

    /// An instant message from another author: their place, and (through the revision) their words.
    func receive(_ event: DraftInstantEvent) {
        guard event.draftId == draftID else { return }
        if !event.patches.isEmpty { applyRemote() }   // their words first, then their caret
        peers.receive(from: event.fromUser, presence: event.presence)
        redrawCursors()
    }

    /// "Jean is editing the third paragraph" (spoken) and "Jean is editing\u{2026}" (shown).
    func editingLine(now: Date = .now) -> (shown: String, spoken: String)? {
        let editing = peers.peers.filter { peers.isEditing($0, now: now) }
        guard !editing.isEmpty else { return nil }
        func first(_ p: CoEditPeers.Peer) -> String { p.person.name.split(separator: " ").first.map(String.init) ?? p.person.name }
        let names = editing.map(first)
        let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names.last!
        let verb = editing.count == 1 ? "is" : "are"
        var spoken = "\(list) \(verb) editing"
        if editing.count == 1, let presence = editing[0].presence, let view = composer?.textView,
           let slot = CoEditMap.slots(blocks: store.coeditBlocks(draftID), in: view.textStorage).first(where: { $0.id == presence.blockId }) {
            spoken += " " + CoEditMap.ordinalWords(slot.ordinal)
        }
        return ("\(list) \(verb) editing\u{2026}", spoken)
    }
}


/// The lines about publishing under the byline: who is ready (the writer's view), who published and when, and whether the draft changed since.
struct CoEditBar: View {
    let session: CoEditSession
    @Environment(ConversationStore.self) private var store

    var body: some View {
        publishLine(.now).padding(.bottom, 4)
    }

    /// Who publishes: a co-author sees "Shem publishes this article" and **Ready**; the writer sees who is ready; after a publish, who published and when,
    /// and whether the draft has changed since.
    @ViewBuilder private func publishLine(_ now: Date) -> some View {
        if let status = session.peers.status, !status.writer.isEmpty {
            let writerName = store.teacher(status.writer).name.split(separator: " ").first.map(String.init) ?? "the writer"
            VStack(alignment: .leading, spacing: 4) {
                if let at = status.publishedAt {
                    let by = status.publishedBy.map { $0 == store.meProvider().id ? "you" : (store.teacher($0).name.split(separator: " ").first.map(String.init) ?? "the writer") } ?? writerName
                    Text("Published by \(by) \u{00B7} \(Date(timeIntervalSince1970: Double(at) / 1000).formatted(.dateTime.month(.abbreviated).day().hour().minute()))").font(Theme.caption).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("coedit-published")
                    if status.changedSincePublish {
                        Text("Changes since the last publish").font(Theme.caption.weight(.semibold)).foregroundStyle(Theme.text).accessibilityIdentifier("coedit-changes")
                    }
                } else if status.isWriter {
                    let names = status.ready.map { store.teacher($0).name.split(separator: " ").first.map(String.init) ?? "" }
                    if !names.isEmpty {
                        Text("\(names.joined(separator: " and ")) \(names.count == 1 ? "is" : "are") ready").font(Theme.caption.weight(.semibold)).foregroundStyle(Theme.text).accessibilityIdentifier("coedit-ready-list")
                    }
                }
            }
        }
    }
}

#if DEBUG
extension CoEditSession {
    /// Tests only (demo runs): `-lime-coedit-sim-coauthor` makes the draft Shem's, so this author is a co-author; `-lime-coedit-sim-published` has Shem publish
    /// it a few seconds later.
    func simulateRoleIfAsked() {
        guard store.isDemo, simStatus == nil, ProcessInfo.processInfo.arguments.contains("-lime-coedit-sim-coauthor") else { return }
        simStatus = DraftStatus(writer: "sim-shem", isWriter: false, ready: [], publishedPost: nil, publishedAt: nil, publishedBy: nil, changedSincePublish: false)
        peers.setStatus(simStatus)
        if ProcessInfo.processInfo.arguments.contains("-lime-coedit-sim-published") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(8))
                self?.simStatus = DraftStatus(writer: "sim-shem", isWriter: false, ready: [], publishedPost: "p1", publishedAt: Int64(Date().timeIntervalSince1970 * 1000), publishedBy: "sim-shem", changedSincePublish: false)
                self?.peers.setStatus(self?.simStatus)
                try? await Task.sleep(for: .seconds(8))
                self?.simStatus?.changedSincePublish = true
                self?.peers.setStatus(self?.simStatus)
            }
        }
    }

    /// Tests only (demo runs): another author, "Jean", is in the draft with her caret three letters into the first block, typing.
    func simulatePeer(step: Int = 0) {
        let jean = Person(id: "sim-jean", name: "Jean Park", tone: 4)
        peers.setAuthors([jean])
        guard let first = store.coeditBlocks(draftID).first(where: { !$0.spans.isEmpty }) else { return }
        let inTitle = ProcessInfo.processInfo.arguments.contains("-lime-coedit-sim-peer-title")
        let presence = inTitle ? DraftPresence(field: "title", blockId: "", offset: UInt32(3 + step % 2), endBlockId: "", endOffset: 0, typing: true, away: false)
                               : DraftPresence(field: "body", blockId: first.id, offset: UInt32(3 + step % 2), endBlockId: first.id, endOffset: 7, typing: true, away: false)
        peers.receive(from: jean.id, presence: presence)
        redrawCursors()
    }
}
#endif

// MARK: The top bar, title and subtitle carets (LIME-233g)

/// The authors as overlapping circles for the top bar, like Google Docs: yours first, then the others'; a ring in the author's colour on whoever is in
/// the draft now. Tapping lists them.
struct CoEditAvatars: View {
    let session: CoEditSession
    let action: () -> Void
    @Environment(ConversationStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let peers = session.peers.peers
        if !peers.isEmpty {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Button(action: action) {
                    HStack(spacing: -9) {
                        ForEach(peers.reversed()) { peer in ring(peer.person, live: session.peers.isLive(peer, now: context.date), tone: peer.tone) }
                        ring(store.meProvider(), live: false, tone: nil)
                    }
                    .environment(\.layoutDirection, .rightToLeft)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Authors: you, " + peers.map { $0.person.name + (session.peers.isLive($0, now: context.date) ? " (here now)" : "") }.joined(separator: ", "))
                .accessibilityHint("Shows who is writing this article")
                .accessibilityIdentifier("coedit-authors")
            }
        }
    }

    private func ring(_ person: Person, live: Bool, tone: Int?) -> some View {
        AvatarView(person: person, size: 28)
            .padding(2)
            .background(Circle().fill(live ? Color(uiColor: PeerColor.color(tone: tone ?? person.tone, dark: scheme == .dark)) : Theme.canvas))
            .environment(\.layoutDirection, .leftToRight)
    }
}

/// Who is writing: names, and who is here now.
struct CoEditAuthorsSheet: View {
    let session: CoEditSession
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                row(store.meProvider(), detail: "You", live: true)
                ForEach(session.peers.peers) { peer in
                    row(peer.person, detail: session.peers.isLive(peer) ? "Here now" : "Not here now", live: session.peers.isLive(peer))
                }
            }
            .navigationTitle("Authors").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }

    private func row(_ person: Person, detail: String, live: Bool) -> some View {
        HStack(spacing: 12) {
            AvatarView(person: person, size: 40).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(person.name).font(Theme.body).foregroundStyle(Theme.text)
                Text(detail).font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coedit-author-\(person.id)")
    }
}

/// A title or subtitle field that tells the session where its caret is (iOS 18 and later; before that, the end of the text).
struct CaretTextField: View {
    @Binding var text: String
    let title: String
    let prompt: Text
    let report: (_ caret: Int, _ end: Int) -> Void

    var body: some View {
        if #available(iOS 18, *) {
            Selectable(text: $text, title: title, prompt: prompt, report: report)
        } else {
            TextField(title, text: $text, prompt: prompt, axis: .vertical).onChange(of: text) { _, now in report(now.count, now.count) }
        }
    }

    @available(iOS 18, *)
    private struct Selectable: View {
        @Binding var text: String
        let title: String
        let prompt: Text
        let report: (Int, Int) -> Void
        @State private var selection: TextSelection?

        var body: some View {
            TextField(title, text: $text, selection: $selection, prompt: prompt, axis: .vertical)
                .onChange(of: selection) { _, now in
                    guard let now, case .selection(let range) = now.indices else { return }
                    // The selection's indices belong to the text as it was a moment ago: count by UTF-16 offsets, clamped, never by index distance.
                    let ns = text as NSString
                    func characters(_ index: String.Index) -> Int {
                        guard index <= text.endIndex else { return text.count }
                        return ns.substring(to: min(max(index.utf16Offset(in: text), 0), ns.length)).count
                    }
                    report(characters(range.lowerBound), characters(range.upperBound))
                }
        }
    }
}

/// Where a caret sits in a title or subtitle: laid out the way the field lays its text out.
enum FieldCaret {
    static func point(text: String, offset: Int, font: UIFont, width: CGFloat) -> (point: CGPoint, height: CGFloat) {
        let lineHeight = font.lineHeight
        guard !text.isEmpty, width > 1 else { return (.zero, lineHeight) }
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container); storage.addLayoutManager(manager)
        let characters = Array(text)
        let clamped = min(max(offset, 0), characters.count)
        let utf16 = String(characters[0..<clamped]).utf16.count
        let total = (text as NSString).length
        if utf16 >= total {
            let glyph = max(manager.numberOfGlyphs - 1, 0)
            let rect = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            return (CGPoint(x: rect.maxX, y: rect.minY), rect.height)
        }
        let glyph = manager.glyphIndexForCharacter(at: utf16)
        let rect = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        return (CGPoint(x: rect.minX, y: rect.minY), rect.height)
    }
}

/// The other authors' carets and tags in the title or subtitle (drawn over the field as in the body).
struct PeerFieldCursors: View {
    let peers: CoEditPeers
    let field: String
    let text: String
    let font: UIFont
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            TimelineView(.periodic(from: .now, by: 0.3)) { context in
                ForEach(peers.peers) { peer in
                    if let presence = peer.presence, presence.field == field, context.date.timeIntervalSince(peer.lastSeen) < 25 {
                        let spot = FieldCaret.point(text: text, offset: Int(presence.offset), font: font, width: geo.size.width)
                        let colour = Color(uiColor: PeerColor.color(tone: peer.tone, dark: scheme == .dark))
                        let first = peer.person.name.split(separator: " ").first.map(String.init) ?? peer.person.name
                        ZStack(alignment: .topLeading) {
                            Rectangle().fill(colour).frame(width: 2, height: spot.height)
                            CursorTag(person: peer.person, colour: colour, ink: Color(uiColor: PeerColor.ink(on: PeerColor.color(tone: peer.tone, dark: scheme == .dark))))
                                .opacity(context.date.timeIntervalSince(peer.lastMoved) > 3 ? 0 : 1)
                                .animation(.easeInOut(duration: 0.25), value: context.date.timeIntervalSince(peer.lastMoved) > 3)
                                .alignmentGuide(.top) { $0[.bottom] + 1 }
                                .accessibilityElement(children: .ignore).accessibilityLabel("\(first)\u{2019}s cursor").accessibilityIdentifier("coedit-cursor-\(peer.id)")
                        }
                        .offset(x: spot.point.x - 1, y: spot.point.y)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A 20 pt photo and the first name in 13 pt semibold, on the author's colour.
struct CursorTag: View {
    let person: Person
    let colour: Color
    let ink: Color

    var body: some View {
        HStack(spacing: 5) {
            AvatarView(person: person, size: 20)
            Text(person.name.split(separator: " ").first.map(String.init) ?? person.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(ink).lineLimit(1)
        }
        .padding(.leading, 4).padding(.trailing, 8).padding(.vertical, 3)
        .background(colour, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .fixedSize()
    }
}


/// Puts someone else's change into the editor's text in place.
enum CoEditSplice {
    /// Replaces only the part of the text that differs, in place, and moves this author's caret and selection by the change (never a guess): the text view
    /// is not reset, so focus, scrolling and the keyboard stay as they are.
    static func apply(_ new: NSAttributedString, into view: UITextView) {
        let storage = view.textStorage
        let old = storage.string as NSString, fresh = new.string as NSString
        var prefix = 0
        let limit = min(old.length, fresh.length)
        while prefix < limit, old.character(at: prefix) == fresh.character(at: prefix) { prefix += 1 }
        while prefix > 0, UTF16.isLeadSurrogate(old.character(at: prefix - 1)) { prefix -= 1 }
        var suffix = 0
        while suffix < limit - prefix, old.character(at: old.length - 1 - suffix) == fresh.character(at: fresh.length - 1 - suffix) { suffix += 1 }
        if suffix > 0, UTF16.isTrailSurrogate(old.character(at: old.length - suffix)) { suffix -= 1 }
        var oldMid = NSRange(location: prefix, length: old.length - prefix - suffix)
        var newMid = NSRange(location: prefix, length: fresh.length - prefix - suffix)
        if oldMid.length == 0 && newMid.length == 0 {   // the same words, other styles: the whole text, still in place, and my caret where it was
            let selection = view.selectedRange
            view.textStorage.beginEditing()
            view.textStorage.replaceCharacters(in: NSRange(location: 0, length: old.length), with: new)
            view.textStorage.endEditing()
            view.selectedRange = selection
            return
        }
        let selection = view.selectedRange
        func shifted(_ position: Int) -> Int {
            if position <= oldMid.location { return position }
            if position >= NSMaxRange(oldMid) { return position + newMid.length - oldMid.length }
            return oldMid.location + newMid.length
        }
        let wasFocused = view.isFirstResponder
        storage.beginEditing()
        storage.replaceCharacters(in: oldMid, with: new.attributedSubstring(from: newMid))
        storage.endEditing()
        let start = shifted(selection.location), end = shifted(NSMaxRange(selection))
        view.selectedRange = NSRange(location: min(start, storage.length), length: max(0, min(end, storage.length) - min(start, storage.length)))
        if wasFocused && !view.isFirstResponder { view.becomeFirstResponder() }
    }
}
