import AVFoundation
import XCTest
@testable import Lime

/// LIME-280: the Effects menu offers only what the camera can do.
final class CallEffects280Tests: XCTestCase {
    func testACameraThatCanReactOffersTheReactionsItListsAndTheVideoEffectsPanel() {
        let all = Set(CallReaction.allCases.map(\.type))
        let full = CallEffects.support(canReact: true, available: all, cameraOn: true)
        XCTAssertEqual(full.reactions, CallReaction.allCases)
        XCTAssertTrue(full.videoEffectsPanel)
        let some = CallEffects.support(canReact: true, available: [.heart, .confetti], cameraOn: true)
        XCTAssertEqual(some.reactions, [.hearts, .confetti], "only the ones the camera lists")
    }

    func testACameraThatCannotReactOffersOnlyThePanelAndNoCameraOffersNothing() {
        let panelOnly = CallEffects.support(canReact: false, available: Set(CallReaction.allCases.map(\.type)), cameraOn: true)
        XCTAssertTrue(panelOnly.reactions.isEmpty)
        XCTAssertTrue(panelOnly.videoEffectsPanel)
        XCTAssertTrue(CallEffects.support(canReact: true, available: [.heart], cameraOn: false).isEmpty, "camera off: no button")
        XCTAssertTrue(CallEffects.support(for: nil, cameraOn: true).isEmpty, "no camera yet: no button")
    }

    func testEveryReactionHasAnAccessibleNameAndASymbol() {
        XCTAssertEqual(CallReaction.allCases.count, 8)
        for reaction in CallReaction.allCases {
            XCTAssertFalse(reaction.title.isEmpty)
            XCTAssertNotNil(UIImage(systemName: reaction.symbol), "\(reaction) has a symbol")
        }
        XCTAssertEqual(Set(CallReaction.allCases.map(\.type)).count, 8, "each is its own reaction")
    }
}
