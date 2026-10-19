import SwiftUI
import UIKit

/// A link the person is adding: whether text is selected (so only the address is needed) and what to start with.
struct LinkRequest: Identifiable {
    let id = UUID()
    let hasSelection: Bool
    var initialURL = ""
}

/// The composer's state and actions, shared by the text view, the toolbar above the keyboard, the composer
/// row and the link sheet.
@MainActor
@Observable
final class RichComposerModel {
    var hasText = false
    /// What is written, as plain text (the link card looks for an address in it).
    private(set) var plainText = ""
    var hasSelection = false
    var format = FormattingState()
    /// Opened with Aa: stays until ✕ or send.
    private(set) var pinned = false
    var linkRequest: LinkRequest?
    weak var textView: ComposerTextView?

    /// The formatting toolbar shows while text is selected, or after Aa.
    var toolbarVisible: Bool { pinned || hasSelection }

    func markdown() -> String {
        guard let textView else { return "" }
        return ComposerDocument.markdown(from: textView.attributedText)
    }

    /// Anything to send? (Markup around nothing is nothing.)
    var canSend: Bool { hasText && !markdown().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func clear() {
        guard let textView else { return }
        textView.attributedText = NSAttributedString()
        textView.typingAttributes = ComposerTextView.plainTypingAttributes
        pinned = false
        hasText = false
        plainText = ""
        hasSelection = false
        textView.setToolbar(visible: false, model: self) // do not wait for the next view update
        refresh()
    }

    func focus() { textView?.becomeFirstResponder() }

    // MARK: The toolbar

    func toggleToolbar() {
        if toolbarVisible && pinned { closeToolbar() } else { pinned = true; focus() }
    }

    /// ✕: the toolbar goes, and so does a selection that brought it up.
    func closeToolbar() {
        pinned = false
        if let textView, textView.selectedRange.length > 0 {
            textView.selectedRange = NSRange(location: NSMaxRange(textView.selectedRange), length: 0)
        }
        hasSelection = false
        refresh()
    }

    func refresh() {
        guard let textView else { return }
        format = ComposerDocument.state(in: textView.attributedText, selection: textView.selectedRange, typing: textView.typingAttributes)
        #if DEBUG
        // UI tests read the Markdown the composer would send.
        textView.accessibilityValue = textView.text.isEmpty ? "" : markdown()
        #endif
    }

    // MARK: Editing

    func apply(_ inline: InlineFormat) {
        guard let textView else { return }
        let range = textView.selectedRange
        if range.length > 0 {
            ComposerDocument.toggle(inline, in: textView.textStorage, range: range)
            textView.selectedRange = range
        } else {
            // A caret: what is typed next gets (or loses) the style.
            var typing = textView.typingAttributes
            let key = ComposerDocument.attributeKey(for: inline)
            if typing[key] != nil { typing[key] = nil } else { typing[key] = ComposerDocument.attributeValue(for: inline) }
            textView.typingAttributes = typing
        }
        refresh()
    }

    func toggleList(_ kind: BlockKind) {
        guard let textView else { return }
        let selection = ComposerDocument.toggleList(kind, in: textView.textStorage, selection: textView.selectedRange)
        textView.selectedRange = selection
        didEdit()
    }

    /// Indent or Outdent (the toolbar and Tab / Shift-Tab): every list item the selection touches.
    func shiftList(indent: Bool) {
        guard let textView else { return }
        textView.selectedRange = ComposerDocument.shiftLevel(in: textView.textStorage, selection: textView.selectedRange, indent: indent)
        ComposerDocument.restyle(textView.textStorage)
        textView.typingAttributes = ComposerDocument.typingAttributes(in: textView.textStorage, caret: textView.selectedRange.location)
        didEdit()
    }

    func toggleCode() {
        guard let textView else { return }
        textView.selectedRange = ComposerDocument.toggleCode(in: textView.textStorage, selection: textView.selectedRange)
        didEdit()
    }

    func insertEmoji(_ emoji: String) {
        textView?.insertText(emoji)
        focus()
        didEdit()
    }

    func didEdit() {
        hasText = !(textView?.text.isEmpty ?? true)
        plainText = textView?.text ?? ""
        refresh()
        textView?.invalidateIntrinsicContentSize()
    }

    // MARK: Links

    func requestLink() {
        guard let textView else { return }
        linkRequest = LinkRequest(hasSelection: textView.selectedRange.length > 0)
    }

    /// Adds the link. Returns why it cannot be added, or nil.
    func applyLink(address: String, text: String) -> String? {
        guard let textView, let url = LinkInput.url(from: address) else { return "Use an http, https or mailto link." }
        let range = textView.selectedRange
        if range.length > 0 {
            ComposerDocument.setLink(url, in: textView.textStorage, range: range)
            textView.selectedRange = NSRange(location: NSMaxRange(range), length: 0)
        } else {
            let shown = text.trimmingCharacters(in: .whitespaces).isEmpty ? url.absoluteString : text
            let inserted = NSMutableAttributedString(string: shown, attributes: textView.typingAttributes)
            inserted.addAttribute(.link, value: url, range: NSRange(location: 0, length: inserted.length))
            textView.textStorage.replaceCharacters(in: range, with: inserted)
            textView.selectedRange = NSRange(location: range.location + inserted.length, length: 0)
        }
        // What is typed after a link is not part of it.
        var typing = textView.typingAttributes
        typing[.link] = nil
        textView.typingAttributes = typing
        ComposerDocument.restyle(textView.textStorage)
        didEdit()
        return nil
    }
}

/// What a person types as a link, made into an address (or refused).
enum LinkInput {
    static func url(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if !text.contains("://") && !text.lowercased().hasPrefix("mailto:") {
            text = text.contains("@") && !text.contains("/") ? "mailto:\(text)" : "https://\(text)"
        }
        // The core decides what is a link: only http, https and mailto, with something after the scheme.
        guard case .paragraph(let spans)? = parseMessageMarkdown(text: "[x](\(text))").first,
              spans.first?.link == text, let url = URL(string: text) else { return nil }
        return url
    }
}

// MARK: The text view

/// The composer's text: an ordinary text view, except that a paste is plain text and its input accessory
/// is the formatting toolbar.
final class ComposerTextView: UITextView {
    static var plainTypingAttributes: [NSAttributedString.Key: Any] { [.font: ComposerDocument.baseFont(), .foregroundColor: UIColor.label] }
    private var accessory: UIView?
    #if DEBUG
    private var keyboardObservers: [NSObjectProtocol] = []
    #endif
    weak var model: RichComposerModel?

    /// Tab and Shift-Tab on a hardware keyboard indent and outdent inside a list; elsewhere Tab does what it did.
    override var keyCommands: [UIKeyCommand]? {
        let inherited = super.keyCommands ?? []
        guard ComposerDocument.state(in: textStorage, selection: selectedRange, typing: [:]).inList else { return inherited }
        let indent = UIKeyCommand(title: "Indent", action: #selector(indentList), input: "\t", modifierFlags: [])
        let outdent = UIKeyCommand(title: "Outdent", action: #selector(outdentList), input: "\t", modifierFlags: .shift)
        indent.wantsPriorityOverSystemBehavior = true
        outdent.wantsPriorityOverSystemBehavior = true
        return [indent, outdent] + inherited
    }

    @objc private func indentList() { model?.shiftList(indent: true) }
    @objc private func outdentList() { model?.shiftList(indent: false) }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        #if DEBUG
        // What the keyboard, the accessory and the field each say, on every keyboard frame change (LIME-152a-fix: the first focus came out wrong).
        let center = NotificationCenter.default
        for name in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardDidShowNotification, UIResponder.keyboardDidHideNotification] {
            keyboardObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
                let what = note.name.rawValue.replacingOccurrences(of: "UIKeyboard", with: "").replacingOccurrences(of: "Notification", with: "")
                MainActor.assumeIsolated {
                    guard let self, self.window != nil else { return }
                    let field = self.convert(self.bounds, to: nil)
                    CallDiagnostics.shared.log("composer keyboard \(what) end=\(Int(end.minY))-\(Int(end.maxY)) accessory=\(Int(self.inputAccessoryView?.frame.height ?? -1)) field=\(Int(field.minY))-\(Int(field.maxY)) screen=\(Int(UIScreen.main.bounds.height))")
                }
            })
        }
        #endif
        // The caret, the selection and its handles are the system's blue, never the accent.
        tintColor = Theme.selectionUIColor
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func paste(_ sender: Any?) {
        guard let string = UIPasteboard.general.string else { return }
        insertText(string) // plain text only: no one else's styling comes along
    }

    /// When all the text fits, the text view shows it from the top (a stale scroll offset after a delete left it scrolled by lines that are gone).
    func settleScroll() {
        let room = bounds.height - adjustedContentInset.top - adjustedContentInset.bottom
        if contentSize.height <= room + 0.5, contentOffset.y != -adjustedContentInset.top { setContentOffset(CGPoint(x: 0, y: -adjustedContentInset.top), animated: false) }
    }

    /// Shows or hides the toolbar that sits above the keyboard. The strip it lives in is installed once, at height 0, and only changes its height
    /// (LIME-152a): swapping the accessory in and out and reloading the input views made the keyboard drop and come back every time the selection
    /// started or ended, and the composer, following it, could end up half under the keyboard.
    func setToolbar(visible: Bool, model: RichComposerModel) {
        if accessory == nil {
            let view = FormattingAccessory(model: model)
            accessory = view
            inputAccessoryView = view
        }
        (accessory as? FormattingAccessory)?.setShown(visible)
    }
}

/// The toolbar's home: a clear strip the keyboard carries, holding the SwiftUI capsule.
final class FormattingAccessory: UIView {
    private let host: UIHostingController<FormattingToolbar>
    static let shownHeight: CGFloat = 60
    private var shown = false

    init(model: RichComposerModel) {
        host = UIHostingController(rootView: FormattingToolbar(model: model))
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 0))
        // The pattern UIKit documents for an accessory that changes height: the autoresizing mask and an intrinsic size, no constraints on
        // the view itself (a constraint-sized accessory fights the "encapsulated layout height" the keyboard adds, and the keyboard's frame, and
        // so the composer's place above it, came out wrong the first time, LIME-152a-fix).
        autoresizingMask = .flexibleHeight
        backgroundColor = .clear
        clipsToBounds = true
        host.view.backgroundColor = .clear
        host.view.alpha = 0
        host.safeAreaRegions = []
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor), host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor), host.view.heightAnchor.constraint(equalToConstant: Self.shownHeight),
        ])
    }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: shown ? Self.shownHeight : 0) }

    /// The strip is as tall as the toolbar while it shows and nothing while it does not; only the height changes.
    func setShown(_ on: Bool) {
        guard shown != on else { return }
        shown = on
        host.view.alpha = on ? 1 : 0
        invalidateIntrinsicContentSize()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

}

struct RichComposerField: UIViewRepresentable {
    let model: RichComposerModel

    func makeUIView(context: Context) -> ComposerTextView {
        let view = ComposerTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.isScrollEnabled = true
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.lineFragmentPadding = 4
        view.font = ComposerDocument.baseFont()
        view.adjustsFontForContentSizeCategory = true
        view.typingAttributes = ComposerTextView.plainTypingAttributes
        view.linkTextAttributes = [.foregroundColor: UIColor(Theme.linkOther), .underlineStyle: NSUnderlineStyle.single.rawValue]
        view.accessibilityIdentifier = "composer-field"
        view.accessibilityLabel = "Message"
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        model.textView = view
        view.model = model
        return view
    }

    func updateUIView(_ view: ComposerTextView, context: Context) {
        context.coordinator.model = model
        view.setToolbar(visible: model.toolbarVisible, model: model)
        // A change of lime's text size or typeface (Settings → Customize → Text size) restyles what is typed.
        _ = context.environment.dynamicTypeSize
        let base = ComposerDocument.baseFont()
        if view.font?.fontName != base.fontName || view.font?.pointSize != base.pointSize {
            view.font = base
            ComposerDocument.restyle(view.textStorage)
            view.typingAttributes = ComposerDocument.typingAttributes(in: view.textStorage, caret: view.selectedRange.location)
        }
    }

    /// Grows with the text, up to five lines.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ComposerTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 280
        let line = uiView.font?.lineHeight ?? 20
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: min(max(fitted, line + 16), line * 5 + 16))
    }

    func makeCoordinator() -> Coordinator { Coordinator(model) }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var model: RichComposerModel
        /// Setting the typing attributes or the selection ourselves must not run the handlers again.
        private var updating = false
        /// An automatic list start that Backspace can still undo (any other edit or caret move clears it).
        private var autoStart: ComposerDocument.AutoStart?
        init(_ model: RichComposerModel) { self.model = model }

        private func setTyping(_ textView: UITextView, caret: Int) {
            updating = true
            textView.typingAttributes = ComposerDocument.typingAttributes(in: textView.textStorage, caret: caret)
            updating = false
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            let storage = textView.textStorage
            let pending = autoStart
            autoStart = nil
            // Tab typed as text (an external keyboard, or a test) indents inside a list; elsewhere it is a tab.
            if text == "\t", ComposerDocument.state(in: storage, selection: range, typing: [:]).inList {
                model.shiftList(indent: true)
                return false
            }
            // A space that completes "- ", "* ", "• " or "1. " at the start of a paragraph starts a list.
            if text == " ", range.length == 0 {
                var selection = range
                if let started = ComposerDocument.autoStart(in: storage, selection: &selection) {
                    autoStart = started
                    textView.selectedRange = selection
                    changed(textView)
                    return false
                }
            }
            // Backspace straight after an automatic start gives back what was typed.
            if let pending, text.isEmpty, range.length == 1, range.location == pending.caret - 1 {
                var selection = range
                if ComposerDocument.undoAutoStart(pending, in: storage, selection: &selection) {
                    textView.selectedRange = selection
                    changed(textView)
                    return false
                }
            }
            // Return inside a list starts the next item (or, on an empty item, ends the list).
            if text == "\n", range.length == 0 {
                var selection = range
                if ComposerDocument.handleReturn(in: storage, selection: &selection) {
                    textView.selectedRange = selection
                    changed(textView)
                    return false
                }
            }
            // Deleting into a list marker takes the whole marker (the item becomes plain text).
            if text.isEmpty, range.length > 0 {
                var selection = range
                if ComposerDocument.handleMarkerDelete(in: storage, range: range, selection: &selection) {
                    textView.selectedRange = selection
                    changed(textView)
                    return false
                }
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) { changed(textView) }

        private func changed(_ textView: UITextView) {
            // An edit UIKit made itself (a selection deleted or cut, two lines joined) may leave half a marker or
            // list attributes on plain words: tidy them first.
            let selection = ComposerDocument.cleanUpAfterEdit(textView.textStorage, selection: textView.selectedRange)
            ComposerDocument.renumber(textView.textStorage)
            ComposerDocument.restyle(textView.textStorage)
            if textView.selectedRange != selection { textView.selectedRange = selection }
            if selection.length == 0 { setTyping(textView, caret: selection.location) }
            model.didEdit()
            // After a delete the text may fit again: the text view's own content goes back to the top (it scrolls itself, never its container).
            DispatchQueue.main.async { [weak textView] in (textView as? ComposerTextView)?.settleScroll() }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !updating else { return }
            if let started = autoStart, textView.selectedRange != NSRange(location: started.caret, length: 0) { autoStart = nil }
            // The caret never sits inside a list marker.
            let selection = textView.selectedRange
            if selection.length == 0 {
                for paragraph in ComposerDocument.paragraphs(in: textView.textStorage, covering: selection) {
                    if let marker = ComposerDocument.markerRange(in: textView.textStorage, paragraph: paragraph), selection.location < NSMaxRange(marker) {
                        updating = true
                        textView.selectedRange = NSRange(location: NSMaxRange(marker), length: 0)
                        updating = false
                        setTyping(textView, caret: NSMaxRange(marker))
                        model.hasSelection = false
                        model.refresh()
                        return
                    }
                }
            }
            if selection.length == 0 { setTyping(textView, caret: selection.location) } else {
                // What replaces a selection is typed words, never a marker.
                updating = true
                var typing = textView.typingAttributes
                typing[.limeMarker] = nil
                typing[.limeStart] = nil
                textView.typingAttributes = typing
                updating = false
            }
            model.hasSelection = selection.length > 0
            model.refresh()
        }
    }
}
