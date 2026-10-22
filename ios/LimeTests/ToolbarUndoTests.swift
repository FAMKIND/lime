import XCTest
@testable import Lime

@MainActor
/// LIME-188r: the toolbar's edits undo one step at a time (the text view clears its own undo when its storage is changed from code).
final class ToolbarUndoTests: XCTestCase {
    func testTwoToolbarEditsUndoAndRedoOneAtATime() {
        let model = RichComposerModel()
        model.isPost = true
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let view = ComposerTextView(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        window.addSubview(view)
        window.makeKeyAndVisible()
        model.textView = view
        view.model = model
        view.textStorage.append(NSAttributedString(string: "0"))
        model.undoable("A") { view.textStorage.append(NSAttributedString(string: "A")) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        model.undoable("B") { view.textStorage.append(NSAttributedString(string: "B")) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(view.text, "0AB")
        XCTAssertTrue(model.canUndo)
        model.undo()
        XCTAssertEqual(view.text, "0A")
        XCTAssertTrue(model.canUndo, "a second step is there")
        model.undo()
        XCTAssertEqual(view.text, "0")
        model.redo()
        XCTAssertEqual(view.text, "0A")
    }
}
