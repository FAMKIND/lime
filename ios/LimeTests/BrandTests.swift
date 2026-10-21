import XCTest
@testable import Lime

final class BrandTests: XCTestCase {
    func testTheLegalLineStaysHiddenUntilTheUserTurnsItOn() {
        XCTAssertFalse(Brand.showLegalLine, "LIME-178: written but hidden until both companies exist")
    }

    func testTheLegalLineNeverClaimsTaxExemptStatus() {
        XCTAssertFalse(Brand.legalLine.contains("501"), "no 501(c)(3) until the IRS grants it")
        XCTAssertTrue(Brand.legalLine.hasPrefix("lime "), "lowercase")
    }
}
