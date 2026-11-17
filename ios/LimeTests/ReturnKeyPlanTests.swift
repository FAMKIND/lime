import UIKit
import XCTest
@testable import Lime

/// LIME-339: Return sends on the Mac and on an iPad with a hardware keyboard; Shift-Return and Option-Return make a new line; an input method mid-composition
/// and an empty draft never send; an iPhone, and an iPad without a hardware keyboard, are unchanged (Return is a new line).
final class ReturnKeyPlanTests: XCTestCase {
    private func sends(_ idiom: UIUserInterfaceIdiom, keyboard: Bool = true, _ modifiers: UIKeyModifierFlags = [], marked: Bool = false, empty: Bool = false) -> Bool {
        ReturnKeyPlan.sends(idiom: idiom, hasHardwareKeyboard: keyboard, modifiers: modifiers, hasMarkedText: marked, draftIsEmpty: empty)
    }

    func testReturnSendsOnTheMacAndOnAnIPadWithAHardwareKeyboard() {
        XCTAssertTrue(sends(.mac))
        XCTAssertTrue(sends(.mac, keyboard: false), "a Mac always has one")
        XCTAssertTrue(sends(.pad))
    }

    func testAnIPhoneAndAnIPadWithoutAHardwareKeyboardAreUnchanged() {
        XCTAssertFalse(sends(.phone))
        XCTAssertFalse(sends(.phone, keyboard: true), "an iPhone with a keyboard attached: still a new line")
        XCTAssertFalse(sends(.pad, keyboard: false))
    }

    func testShiftAndOptionReturnMakeANewLine() {
        for idiom in [UIUserInterfaceIdiom.mac, .pad] {
            XCTAssertFalse(sends(idiom, .shift))
            XCTAssertFalse(sends(idiom, .alternate))
            XCTAssertFalse(sends(idiom, [.shift, .alternate]))
            XCTAssertFalse(sends(idiom, .command))
            XCTAssertFalse(sends(idiom, .control))
            XCTAssertTrue(sends(idiom, .alphaShift), "Caps Lock is not a modifier")
        }
    }

    func testMarkedTextAndAnEmptyDraftNeverSend() {
        for idiom in [UIUserInterfaceIdiom.mac, .pad] {
            XCTAssertFalse(sends(idiom, marked: true), "Return accepts the input method's text")
            XCTAssertFalse(sends(idiom, empty: true))
            XCTAssertFalse(sends(idiom, marked: true, empty: true))
        }
    }

    func testTheHintIsShortAndOnlyNamesReturn() {
        XCTAssertEqual(ReturnKeyPlan.hint, "Return sends; Shift-Return for a new line")
    }
}
