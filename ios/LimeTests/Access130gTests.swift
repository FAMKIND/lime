import XCTest
@testable import Lime

/// LIME-130-5a: the words VoiceOver reads for shared things, group members and crops.
final class Access130gTests: XCTestCase {
    func testASharedPhotoSaysWhoSentItAndWhenAndTheDescriptionWhenThereIsOne() {
        XCTAssertEqual(SharedItemLabel.media(video: false, sender: "Mei Lin", dateText: "Nov 9, 2026", durationMs: nil, alt: ""), "Photo from Mei Lin, Nov 9, 2026")
        XCTAssertEqual(SharedItemLabel.media(video: false, sender: nil, dateText: "Nov 9, 2026", durationMs: nil, alt: "A whiteboard"), "Photo from you, Nov 9, 2026. A whiteboard")
        XCTAssertEqual(SharedItemLabel.media(video: false, sender: "Sam", dateText: "Nov 9, 2026", durationMs: nil, alt: "  \n"), "Photo from Sam, Nov 9, 2026")
    }

    func testASharedVideoHasItsLength() {
        XCTAssertEqual(SharedItemLabel.media(video: true, sender: "Sam", dateText: "Nov 9, 2026", durationMs: 12_000, alt: ""), "Video, 0:12, from Sam, Nov 9, 2026")
        XCTAssertEqual(SharedItemLabel.media(video: true, sender: nil, dateText: "Nov 9, 2026", durationMs: 75_000, alt: ""), "Video, 1:15, from you, Nov 9, 2026")
        XCTAssertEqual(SharedItemLabel.media(video: true, sender: "Sam", dateText: "Nov 9, 2026", durationMs: nil, alt: ""), "Video, from Sam, Nov 9, 2026")
    }

    func testFilesAndLinksAreOneLabelEach() {
        XCTAssertEqual(SharedItemLabel.file(name: "Plan.pdf", size: 1_500_000, dateText: "Nov 9, 2026"), "Plan.pdf, \(ByteCountFormatter.string(fromByteCount: 1_500_000, countStyle: .file)), Nov 9, 2026")
        XCTAssertEqual(SharedItemLabel.file(name: "Plan.pdf", size: nil, dateText: "Nov 9, 2026"), "Plan.pdf, Nov 9, 2026")
        XCTAssertEqual(SharedItemLabel.link(title: "Lesson ideas", host: SharedItemLabel.host(of: "https://example.org/a"), dateText: "Nov 9, 2026"), "Lesson ideas, example.org, Nov 9, 2026")
        XCTAssertEqual(SharedItemLabel.link(title: "example.org", host: "example.org", dateText: "Nov 9, 2026"), "example.org, Nov 9, 2026", "no host twice")
    }

    func testAMemberRowReadsTheKeyWarning() {
        XCTAssertEqual(GroupMemberLabel.text(name: "Sam", role: "admin", keyNotAccepted: true), "Sam, admin, new security key not accepted")
        XCTAssertEqual(GroupMemberLabel.text(name: "Sam", role: nil, keyNotAccepted: false), "Sam")
    }

    func testACropMovesByATenthOfTheFrameAndZoomsInHalfSteps() {
        let frame = CGSize(width: 300, height: 400)
        XCTAssertEqual(CropAccessibility.moved(.zero, .up, frame: frame), CGSize(width: 0, height: -40))
        XCTAssertEqual(CropAccessibility.moved(.zero, .down, frame: frame), CGSize(width: 0, height: 40))
        XCTAssertEqual(CropAccessibility.moved(.zero, .left, frame: frame), CGSize(width: -30, height: 0))
        XCTAssertEqual(CropAccessibility.moved(CGSize(width: 5, height: 5), .right, frame: frame), CGSize(width: 35, height: 5))
        XCTAssertEqual(CropAccessibility.zoomed(1, in: false), 1, "never below 1")
        XCTAssertEqual(CropAccessibility.zoomed(1, in: true), 1.5)
        XCTAssertEqual(CropAccessibility.zoomed(6, in: true), 6, "never above 6")
        XCTAssertEqual(CropAccessibility.value(scale: 1.5), "Zoom 150 percent")
    }
}
