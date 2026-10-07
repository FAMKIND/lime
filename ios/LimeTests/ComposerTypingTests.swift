import XCTest
@testable import Lime

/// Typing in the real text view (without a screen): a style at the caret lasts for what is typed.
@MainActor
final class ComposerTypingTests: XCTestCase {
    /// A text view with no window does not call its delegate for programmatic edits, so these helpers play the
    /// part of the keyboard: the key goes through `shouldChangeTextIn`, then the text, then `didChange`.
    private func type(_ text: String, in view: ComposerTextView, _ coordinator: RichComposerField.Coordinator) {
        for character in text {
            let string = String(character)
            if coordinator.textView(view, shouldChangeTextIn: view.selectedRange, replacementText: string) {
                view.insertText(string)
                coordinator.textViewDidChange(view)
            }
        }
    }

    private func select(_ range: NSRange, in view: ComposerTextView, _ coordinator: RichComposerField.Coordinator) {
        view.selectedRange = range
        coordinator.textViewDidChangeSelection(view)
    }

    private func makeField() -> (ComposerTextView, RichComposerModel, RichComposerField.Coordinator) {
        let view = ComposerTextView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        let model = RichComposerModel()
        model.textView = view
        let coordinator = RichComposerField(model: model).makeCoordinator()
        view.delegate = coordinator
        return (view, model, coordinator)
    }

    func testBoldAtTheCaretLastsForWhatIsTypedAndEndsWhenTurnedOff() {
        let (view, model, coordinator) = makeField()
        model.apply(.bold)
        type("Important", in: view, coordinator)
        XCTAssertEqual(model.markdown(), "**Important**")
        model.apply(.bold)
        type(" news", in: view, coordinator)
        XCTAssertEqual(model.markdown(), "**Important** news")
        XCTAssertTrue(model.hasText)
    }

    func testAListContinuesWhileTypingAndReturnEndsIt() {
        let (view, model, coordinator) = makeField()
        model.toggleList(.bullet)
        type("one\ntwo", in: view, coordinator)
        XCTAssertEqual(model.markdown(), "- one\n- two")
        type("\n\nafter", in: view, coordinator)
        XCTAssertEqual(model.markdown(), "- one\n- two\n\nafter")
    }

    func testTheCaretNeverSitsInsideAMarkerAndDeletingTheMarkerEndsTheItem() {
        let (view, model, coordinator) = makeField()
        model.toggleList(.number)
        type("first", in: view, coordinator)
        select(NSRange(location: 1, length: 0), in: view, coordinator)   // inside "1. "
        XCTAssertGreaterThanOrEqual(view.selectedRange.location, 3, "moved past the marker")
        // Backspace at the start of the item: the keyboard asks to delete the marker's last character.
        XCTAssertFalse(coordinator.textView(view, shouldChangeTextIn: NSRange(location: 2, length: 1), replacementText: ""), "handled: the whole marker goes")
        XCTAssertEqual(view.text, "first", "the marker went, the words stayed")
        XCTAssertEqual(model.markdown(), "first")
    }

    func testAPasteIsPlainText() {
        let (view, model, _) = makeField()
        let rich = NSMutableAttributedString(string: "styled", attributes: [.font: UIFont.boldSystemFont(ofSize: 30), .foregroundColor: UIColor.red])
        UIPasteboard.general.string = rich.string
        view.paste(nil)
        XCTAssertEqual(model.markdown(), "styled")
        XCTAssertEqual(view.textStorage.attribute(.limeBold, at: 0, effectiveRange: nil) as? Bool, nil)
    }

    func testClearingEmptiesTheComposerAndClosesTheToolbar() {
        let (view, model, coordinator) = makeField()
        model.toggleToolbar()
        XCTAssertTrue(model.toolbarVisible)
        type("hello", in: view, coordinator)
        model.clear()
        XCTAssertFalse(model.hasText)
        XCTAssertEqual(view.text, "")
        XCTAssertFalse(model.toolbarVisible, "sending closes the toolbar")
    }

    func testTheSelectionShowsTheToolbarAndCloseHidesIt() {
        let (view, model, coordinator) = makeField()
        type("hello world", in: view, coordinator)
        select(NSRange(location: 0, length: 5), in: view, coordinator)
        XCTAssertTrue(model.toolbarVisible, "selected text brings up the toolbar")
        model.closeToolbar()
        XCTAssertFalse(model.toolbarVisible)
        XCTAssertEqual(view.selectedRange.length, 0)
    }

    func testLinkInputIsCheckedByTheCore() {
        XCTAssertEqual(LinkInput.url(from: "limechat.org/plan")?.absoluteString, "https://limechat.org/plan")
        XCTAssertEqual(LinkInput.url(from: "http://a.b")?.absoluteString, "http://a.b")
        XCTAssertEqual(LinkInput.url(from: "me@example.com")?.absoluteString, "mailto:me@example.com")
        XCTAssertEqual(LinkInput.url(from: "mailto:me@example.com")?.absoluteString, "mailto:me@example.com")
        for refused in ["javascript:alert(1)", "data:text/html,x", "ftp://a.b", "file:///etc/passwd", "", "   ", "two words", "https://"] {
            XCTAssertNil(LinkInput.url(from: refused), refused)
        }
    }
}
