import XCTest

/// LIME-235b: the mini player is as wide as the dock and its title stays on one line (demo).
@MainActor
final class Mini235bUITests: LimeUITestCase {
    func testTheMiniPlayerIsAsWideAsTheDockAndALongTitleStaysOnOneLine() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-podcast"]
        app.launch()
        app.descendants(matching: .any).matching(identifier: "jam-filter-segments").firstMatch.buttons["Podcasts"].tap()
        let pill = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'jam-audio-play-'")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10)); pill.tap()
        XCTAssertTrue(app.buttons["jam-video-close"].waitForExistence(timeout: 8))
        app.buttons["jam-video-close"].tap()
        let mini = app.buttons["audio-mini-open"]
        XCTAssertTrue(mini.waitForExistence(timeout: 8))
        let container = app.descendants(matching: .any).matching(identifier: "audio-mini-player").firstMatch
        XCTAssertTrue(container.waitForExistence(timeout: 3), "the mini player as a whole")
        let window = app.windows.firstMatch.frame
        // The dock's width, as the app measured it (its value says "dock 275"); the mini player is that wide and centred.
        sleep(1)
        let width = Double((container.value as? String)?.replacingOccurrences(of: "dock ", with: "") ?? "0") ?? 0
        XCTAssertGreaterThan(width, 100, "the app found the dock")
        XCTAssertLessThan(width, window.width - 40, "the dock is narrower than the screen")
        XCTAssertEqual(container.frame.width, CGFloat(width), accuracy: 2, "as wide as the dock")
        XCTAssertEqual(container.frame.midX, window.midX, accuracy: 2, "centred")
        // Every tab is inside the mini player's width, so it sits over the dock and is not wider.
        let tabs = app.tabBars.buttons.allElementsBoundByIndex
        XCTAssertTrue(tabs.allSatisfy { $0.frame.minX >= container.frame.minX - 4 && $0.frame.maxX <= container.frame.maxX + 4 }, "every tab is under the mini player's width")
        XCTAssertLessThan(mini.frame.height, 56, "title and subtitle are one line each")
    }
}
