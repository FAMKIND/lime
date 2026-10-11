import XCTest
@testable import Lime

final class TabSymbolsTests: XCTestCase {
    func testTheTabsAreOutlinedAndOnlyTheSelectedOneIsFilled() {
        for symbols in [TabSymbols.link, TabSymbols.call, TabSymbols.jam] {
            XCTAssertEqual(TabSymbols.name(outline: symbols.outline, filled: symbols.filled, selected: false), symbols.outline)
            XCTAssertEqual(TabSymbols.name(outline: symbols.outline, filled: symbols.filled, selected: true), symbols.filled)
            XCTAssertEqual(symbols.filled, symbols.outline + ".fill")
        }
        XCTAssertEqual([TabSymbols.link.outline, TabSymbols.call.outline, TabSymbols.jam.outline], ["message", "phone", "book.pages"])
    }
}
