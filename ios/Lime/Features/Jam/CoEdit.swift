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

/// The article editor's link to its shared draft (LIME-233c, DESIGN-22): every change in the editor is handed to LimeCore as the fewest operations, a
/// remote author's changes come back and are drawn without moving the caret. Nothing here is a view.
@MainActor
final class CoEditSession {
    let draftID: String
    private let store: ConversationStore
    private var pending: Task<Void, Never>?
    /// While the editor itself is being rewritten with someone else's words, its changes are not the person's.
    private(set) var applyingRemote = false

    init(draftID: String, store: ConversationStore) {
        self.draftID = draftID
        self.store = store
    }

    /// The editor changed: after a moment (so a burst of typing is a few calls), the draft says what the editor shows.
    func editorChanged(title: String, subtitle: String, composer: RichComposerModel) {
        guard !applyingRemote else { return }
        pending?.cancel()
        pending = Task { @MainActor [weak self, weak composer] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self, let view = composer?.textView else { return }
            self.syncNow(title: title, subtitle: subtitle, markdown: ComposerDocument.markdown(from: view.textStorage, post: true))
        }
    }

    func syncNow(title: String, subtitle: String, markdown: String) {
        pending?.cancel()
        guard store.coeditReconcile(draftID, title: title, subtitle: subtitle, markdown: markdown) else { return }
        store.sendDraftChangeInstantly(draftID)
    }

    /// The draft as post Markdown, after the editor's latest state was handed over.
    func exportMarkdown() -> String? { store.coeditMarkdown(draftID) }

    /// Other authors' changes that arrived: the editor's text becomes the draft's, the caret stays where it was (by what surrounds it).
    func applyRemote(to composer: RichComposerModel, title: inout String, subtitle: inout String) {
        guard let view = composer.textView, view.markedTextRange == nil else { return }
        _ = store.coeditTakePatches(draftID)   // the editor is redrawn from the draft below; the patches only say it changed
        guard let markdown = store.coeditMarkdown(draftID), let meta = store.coeditMeta(draftID) else { return }
        // Nothing to draw when the editor already shows the draft (our own change coming back, a no-op).
        guard markdown != ComposerDocument.markdown(from: view.textStorage, post: true) || meta.title != title || meta.subtitle != subtitle else { return }
        applyingRemote = true
        defer { applyingRemote = false }
        let before = view.text ?? ""
        let range = view.selectedRange
        let isFocused = view.isFirstResponder
        view.attributedText = ComposerDocument.attributed(fromMarkdown: markdown, post: true)
        let after = view.text ?? ""
        let start = CaretAnchor.relocate(range.location, in: before, to: after)
        let end = range.length > 0 ? CaretAnchor.relocate(range.location + range.length, in: before, to: after) : start
        view.selectedRange = NSRange(location: min(start, after.utf16.count), length: max(0, min(end, after.utf16.count) - min(start, after.utf16.count)))
        if isFocused && !view.isFirstResponder { view.becomeFirstResponder() }
        if title != meta.title { title = meta.title }
        if subtitle != meta.subtitle { subtitle = meta.subtitle }
        composer.didEdit()
    }
}
