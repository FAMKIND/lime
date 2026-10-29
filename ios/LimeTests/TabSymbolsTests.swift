import XCTest
@testable import Lime

final class TabSymbolsTests: XCTestCase {
    func testTheTabSymbolsAreTheOutlineOnesAndNeverFilled() {
        XCTAssertEqual(TabSymbols.all, ["message", "phone", "pencil.and.outline"])
        for name in TabSymbols.all { XCTAssertFalse(name.hasSuffix(".fill"), "\(name) must be the outline symbol in every state") }
    }
}
