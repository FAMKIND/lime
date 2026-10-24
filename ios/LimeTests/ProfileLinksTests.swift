import XCTest
@testable import Lime

/// LIME-214: the links on a profile are https only, short, at most five, and read back safely.
final class ProfileLinksTests: XCTestCase {
    func testHttpIsUpgradedAndOtherSchemesAreRefused() {
        XCTAssertEqual(ProfileLinks.normalized("http://example.com/a"), "https://example.com/a")
        XCTAssertEqual(ProfileLinks.normalized("example.com"), "https://example.com")
        XCTAssertEqual(ProfileLinks.normalized(" https://example.com "), "https://example.com")
        XCTAssertNil(ProfileLinks.normalized("javascript:alert(1)"))
        XCTAssertNil(ProfileLinks.normalized("ftp://example.com"))
        XCTAssertNil(ProfileLinks.normalized("tel:+123"))
        XCTAssertNil(ProfileLinks.normalized("not a link"))
        XCTAssertNil(ProfileLinks.normalized("https://nodot"))
    }

    func testTheChecksAndTheCleanedList() {
        let ok = ProfileLink(title: "Class", url: "http://example.com")
        XCTAssertNil(ProfileLinks.problem(in: [ok, ProfileLink(title: "", url: "")]), "a blank row is ignored")
        XCTAssertNotNil(ProfileLinks.problem(in: [ProfileLink(title: "", url: "https://example.com")]))
        XCTAssertNotNil(ProfileLinks.problem(in: [ProfileLink(title: String(repeating: "a", count: 41), url: "https://example.com")]))
        XCTAssertNotNil(ProfileLinks.problem(in: [ProfileLink(title: "x", url: "ftp://example.com")]))
        XCTAssertNotNil(ProfileLinks.problem(in: Array(repeating: ok, count: 6)))
        XCTAssertEqual(ProfileLinks.cleaned([ok, ProfileLink(title: "", url: "")]).map(\.url), ["https://example.com"])
    }

    func testTheJsonRoundTripsInOrderAndRefusesWhatCameInWithAnotherScheme() throws {
        let links = [ProfileLink(title: "One", url: "https://a.example.com"), ProfileLink(title: "Two", url: "https://b.example.com")]
        let data = try XCTUnwrap(ProfileLinks.encode(links))
        XCTAssertEqual(ProfileLinks.decode(data).map(\.title), ["One", "Two"])
        let hostile = Data(#"[{"title":"Evil","url":"javascript:alert(1)"},{"title":"Fine","url":"https://ok.example.com"}]"#.utf8)
        XCTAssertEqual(ProfileLinks.decode(hostile).map(\.title), ["Fine"])
        XCTAssertEqual(ProfileLinks.decode(Data("nonsense".utf8)), [])
        XCTAssertEqual(ProfileLinks.decode(nil), [])
    }

    func testTheAddressIsShownWithoutItsScheme() {
        XCTAssertEqual(ProfileLinks.shown("https://example.com/class/"), "example.com/class")
    }
}
