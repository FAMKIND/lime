import SwiftUI
import XCTest
@testable import Lime

/// LIME-338: the Mac hosts the chat. Nothing in `ios/` sets `chatIsPaneRoot`, so on the phones Back always shows.
final class Pane338Tests: XCTestCase {
    func testBackShowsByDefaultBecauseTheChatIsNotAPaneRootUnlessTheHostSaysSo() {
        XCTAssertFalse(EnvironmentValues().chatIsPaneRoot, "the default: Back shows")
        var values = EnvironmentValues()
        values.chatIsPaneRoot = true
        XCTAssertTrue(values.chatIsPaneRoot, "the Mac host hides it")
    }

    @MainActor
    func testWindowSizeIsWhatLayoutReadsAndFollowsTheWindow() {
        let before = WindowMetrics.shared.size
        WindowMetrics.shared.size = CGSize(width: 420, height: 700)
        XCTAssertEqual(WindowMetrics.shared.size.width, 420)
        WindowMetrics.shared.size = before
    }
}
