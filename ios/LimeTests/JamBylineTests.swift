import XCTest
@testable import Lime

/// LIME-188w: who a post is by, in words.
final class JamBylineTests: XCTestCase {
    func testAnAuthorAlone() {
        XCTAssertEqual(Byline.text(jam: nil, authors: ["Shem Rajoon"]), "Shem Rajoon")
    }

    func testAuthorAndCoauthors() {
        XCTAssertEqual(Byline.text(jam: nil, authors: ["Shem Rajoon", "Jean Chung"]), "Shem Rajoon & Jean Chung")
        XCTAssertEqual(Byline.text(jam: nil, authors: ["Shem Rajoon", "Jean Chung", "Lee Wong"]), "Shem Rajoon, Jean Chung & Lee Wong")
    }

    func testAJamAndItsAuthor() {
        XCTAssertEqual(Byline.text(jam: "Conscious collective", authors: ["Shem Rajoon"]), "Conscious collective \u{00B7} Shem Rajoon")
        XCTAssertEqual(Byline.text(jam: "Conscious collective", authors: ["Shem Rajoon", "Jean Chung"]), "Conscious collective \u{00B7} Shem Rajoon & Jean Chung")
    }

    func testAJamAlone() {
        XCTAssertEqual(Byline.text(jam: "Conscious collective", authors: []), "Conscious collective")
    }
}
