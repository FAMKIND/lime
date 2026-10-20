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
    /// The emoji keyboard is up (LIME-174): the composer's own text view shows it, so there is one keyboard owner and the keyboard, its accessory and
    /// the composer's place always agree. 😊 toggles it; the icon becomes a keyboard while it shows.
    private(set) var showsEmojiKeyboard = false
    /// Whether the keyboard was up (the person was writing) when 😊 was tapped: the second tap returns to that, text keyboard or none.
    private var returnsToWriting = true

    /// The formatting toolbar shows while text is selected, or after Aa.
    var toolbarVisible: Bool { pinned || hasSelection }
    /// The composer has the keyboard (set by the text view's delegate).
    var editing = false
    /// The strip is laid out under the composer, above the keyboard, in the composer's own stack (LIME-174: as the keyboard's accessory its height was
    /// left out of the composer's place with the emoji keyboard, and it covered the tool row). It shows while the keyboard does.
    var showsStrip: Bool { toolbarVisible && editing }

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
        refresh()
    }

    func focus() { textView?.becomeFirstResponder() }

    // MARK: The emoji keyboard

    /// 😊: the emoji keyboard on the composer's own text view; the same button again goes back to the text keyboard.
    func toggleEmojiKeyboard() {
        if showsEmojiKeyboard, !returnsToWriting {
            // Reading (the keyboard was down): back to that, the keyboard closes and the whole chat shows.
            textView?.resignFirstResponder()
            UIAccessibility.post(notification: .announcement, argument: "Keyboard closed")
            return
        }
        if !showsEmojiKeyboard { returnsToWriting = textView?.isFirstResponder ?? false }
        setEmojiKeyboard(!showsEmojiKeyboard)
    }

    func setEmojiKeyboard(_ on: Bool) {
        guard let textView, on != showsEmojiKeyboard else { return }
        if on {
            // Remember the text keyboard that is up, to come back to it (the person's own language or layout).
            textView.textModeToReturnTo = nil
            textView.textModeToReturnTo = textView.textInputMode ?? UITextInputMode.activeInputModes.first { $0.primaryLanguage != "emoji" }
        }
        showsEmojiKeyboard = on
        textView.showsEmoji = on
        if textView.isFirstResponder { textView.reloadInputViews() } else { _ = textView.becomeFirstResponder() }
        #if DEBUG
        CallDiagnostics.shared.log("composer keyboard switch to \(on ? "emoji" : "text"): input mode now \(textView.textInputMode?.primaryLanguage ?? "?")")
        #endif
        UIAccessibility.post(notification: .announcement, argument: on ? "Emoji keyboard" : "Text keyboard")
        if !on {
            // The way back is named only for the reload: afterwards the system's own choice (a language switch with the globe key) is respected again.
            DispatchQueue.main.async { [weak textView] in textView?.textModeToReturnTo = nil }
        }
    }

    /// The keyboard let go (a sheet, send, the person tapped away): the next focus starts on the text keyboard.
    func keyboardEnded() {
        showsEmojiKeyboard = false
        textView?.showsEmoji = false
        textView?.textModeToReturnTo = nil
    }

    /// Aa while the emoji keyboard is up: back to the text keyboard, with the formatting strip (no emoji needs picking first).
    func formattingTapped() {
        if showsEmojiKeyboard {
            setEmojiKeyboard(false)
            if !pinned { pinned = true }
            focus()
        } else {
            toggleToolbar()
        }
    }

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
    #if DEBUG
    private var keyboardObservers: [NSObjectProtocol] = []
    #endif
    weak var model: RichComposerModel?

    /// Shows the emoji keyboard instead of the text one (the model flips it, then reloads the input views).
    var showsEmoji = false
    /// The text keyboard that was up before the emoji one, and the one to return to: iOS answers `super.textInputMode` with the mode in use, which
    /// while emoji shows is emoji itself, so going back needs this one named (it was the bug in the first build: only the icon changed back).
    var textModeToReturnTo: UITextInputMode?
    override var textInputMode: UITextInputMode? {
        if showsEmoji, let emoji = UITextInputMode.activeInputModes.first(where: { $0.primaryLanguage == "emoji" }) { return emoji }
        if let textModeToReturnTo { return textModeToReturnTo }
        return super.textInputMode
    }

    @discardableResult override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { model?.keyboardEnded() }
        return resigned
    }

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
                    CallDiagnostics.shared.log("composer keyboard \(what) responder=\(self.isFirstResponder ? "composer" : (EmojiKeyboardField.isFirstResponder ? "emoji" : "none")) end=\(Int(end.minY))-\(Int(end.maxY)) strip=\(self.model?.showsStrip == true ? 1 : 0) field=\(Int(field.minY))-\(Int(field.maxY)) screen=\(Int(UIScreen.main.bounds.height))")
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

        func textViewDidBeginEditing(_ textView: UITextView) { model.editing = true }
        func textViewDidEndEditing(_ textView: UITextView) { model.editing = false }

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
