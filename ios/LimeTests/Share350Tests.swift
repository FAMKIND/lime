import XCTest
@testable import Lime

/// LIME-350: what may be shared from a jam card.
final class Share350Tests: XCTestCase {
    private func post(tier: String, state: String = "ready") -> JamPostInfo {
        JamPostInfo(postId: "p", jamId: "j", author: "a", tier: tier, kind: "article", title: "T", subtitle: "", markdown: "Words", plain: "Words", attachmentsJson: "[]", created: 0,
                    coauthors: [], displayAs: "person", editedAt: 0, audience: "subscribers", series: nil, topics: [], state: state)
    }

    func testAFreePostMayBeShared() { XCTAssertTrue(JamShare.allowed(post(tier: "free"))) }
    func testAMembersOnlyPostIsNeverShared() { XCTAssertFalse(JamShare.allowed(post(tier: "members"))) }
    func testAPostThatIsNotReadyIsNotShared() { XCTAssertFalse(JamShare.allowed(post(tier: "free", state: "pending"))) }
}
