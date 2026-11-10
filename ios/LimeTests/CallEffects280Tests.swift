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

    @MainActor func testACameraThatCannotReactOffersOnlyThePanelAndNoCameraOffersNothing() {
        let panelOnly = CallEffects.support(canReact: false, available: Set(CallReaction.allCases.map(\.type)), cameraOn: true)
        XCTAssertTrue(panelOnly.reactions.isEmpty)
        XCTAssertTrue(panelOnly.videoEffectsPanel)
        XCTAssertTrue(CallEffects.support(canReact: true, available: [.heart], cameraOn: false).isEmpty, "camera off: no button")
        XCTAssertTrue(CallEffects.support(for: nil, cameraOn: true).isEmpty, "no camera yet: no button")
    }

    func testEveryReactionHasAnAccessibleNameAndASymbol() {
        XCTAssertEqual(CallReaction.allCases.count, 6)
        for reaction in CallReaction.allCases {
            XCTAssertFalse(reaction.title.isEmpty)
            XCTAssertNotNil(UIImage(systemName: reaction.symbol), "\(reaction) has a symbol")
        }
        XCTAssertEqual(Set(CallReaction.allCases.map(\.type)).count, 6, "each is its own reaction")
    }

    /// LIME-130-4c: Apple draws these into the sent video, so the two that flash are never offered, and none are with Reduce Motion on.
    func testFireworksAndLasersAreNeverOfferedEvenWhenTheCameraListsThem() {
        XCTAssertEqual(CallReaction.allCases.map(\.type).filter { $0 == .fireworks || $0 == .lasers }, [])
        let everything: Set<AVCaptureReactionType> = [.heart, .thumbsUp, .thumbsDown, .balloons, .confetti, .fireworks, .rain, .lasers]
        let offered = CallEffects.support(canReact: true, available: everything, cameraOn: true)
        XCTAssertEqual(Set(offered.reactions.map(\.title)), ["Hearts", "Thumbs up", "Thumbs down", "Balloons", "Confetti", "Rain"])
    }

    func testReduceMotionOffersNoReactionsButKeepsTheVideoEffectsPanel() {
        let all = Set(CallReaction.allCases.map(\.type))
        let calm = CallEffects.support(canReact: true, available: all, cameraOn: true, reduceMotion: true)
        XCTAssertTrue(calm.reactions.isEmpty)
        XCTAssertTrue(calm.videoEffectsPanel, "portrait and Studio Light are not motion")
        XCTAssertFalse(calm.isEmpty)
        XCTAssertTrue(CallEffects.support(canReact: true, available: all, cameraOn: false, reduceMotion: true).isEmpty, "camera off: still nothing")
        XCTAssertEqual(CallEffects.support(canReact: true, available: all, cameraOn: true, reduceMotion: false).reactions.count, 6)
    }
}
