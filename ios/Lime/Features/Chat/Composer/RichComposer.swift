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
    static let plainTypingAttributes: [NSAttributedString.Key: Any] = [.font: ComposerDocument.baseFont(), .foregroundColor: UIColor.label]
    private var accessory: UIView?

    override func paste(_ sender: Any?) {
        guard let string = UIPasteboard.general.string else { return }
        insertText(string) // plain text only: no one else's styling comes along
    }

    /// Shows or hides the toolbar that sits above the keyboard.
    func setToolbar(visible: Bool, model: RichComposerModel) {
        if visible, inputAccessoryView == nil {
            let view = FormattingAccessory(model: model)
            accessory = view
            inputAccessoryView = view
            reloadInputViews()
        } else if !visible, inputAccessoryView != nil {
            inputAccessoryView = nil
            accessory = nil
            reloadInputViews()
        }
    }
}

/// The toolbar's home: a clear strip the keyboard carries, holding the SwiftUI capsule.
final class FormattingAccessory: UIView {
    private let host: UIHostingController<FormattingToolbar>

    init(model: RichComposerModel) {
        host = UIHostingController(rootView: FormattingToolbar(model: model))
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 60))
        autoresizingMask = .flexibleHeight
        backgroundColor = .clear
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor), host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor), host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 60) }
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
        return view
    }

    func updateUIView(_ view: ComposerTextView, context: Context) {
        context.coordinator.model = model
        view.setToolbar(visible: model.toolbarVisible, model: model)
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
        init(_ model: RichComposerModel) { self.model = model }

        private func setTyping(_ textView: UITextView, caret: Int) {
            updating = true
            textView.typingAttributes = ComposerDocument.typingAttributes(in: textView.textStorage, caret: caret)
            updating = false
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            let storage = textView.textStorage
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
                for paragraph in ComposerDocument.paragraphs(in: storage, covering: range) {
                    if let marker = ComposerDocument.markerRange(in: storage, paragraph: paragraph),
                       NSIntersectionRange(marker, range).length > 0, range.location < NSMaxRange(marker) {
                        storage.deleteCharacters(in: marker)
                        let rest = NSRange(location: paragraph.location, length: max(paragraph.length - marker.length, 0))
                        storage.removeAttribute(.limeBlock, range: rest)
                        storage.removeAttribute(.limeLevel, range: rest)
                        textView.selectedRange = NSRange(location: paragraph.location, length: 0)
                        changed(textView)
                        return false
                    }
                }
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) { changed(textView) }

        private func changed(_ textView: UITextView) {
            let selection = textView.selectedRange
            ComposerDocument.renumber(textView.textStorage)
            ComposerDocument.restyle(textView.textStorage)
            if textView.selectedRange != selection { textView.selectedRange = selection }
            if selection.length == 0 { setTyping(textView, caret: selection.location) }
            model.didEdit()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !updating else { return }
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
            if selection.length == 0 { setTyping(textView, caret: selection.location) }
            model.hasSelection = selection.length > 0
            model.refresh()
        }
    }
}
