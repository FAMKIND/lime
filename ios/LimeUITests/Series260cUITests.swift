import XCTest

/// LIME-260c: the series page fits the screen, a small cover is centred artwork, no dock, the counts agree (demo).
@MainActor
final class Series260cUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func openSeries(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-series"] + extra
        app.launch()
        let line = any(app, "jam-card-series-demo-post-1")
        for _ in 0..<5 where !line.exists { app.swipeUp() }
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        line.tap()
        XCTAssertTrue(any(app, "series-page").waitForExistence(timeout: 8))
        return app
    }

    private func assertFits(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch.frame
        for id in ["series-page-title", "series-play", "series-meta", "series-progress"] {
            let f = any(app, id).frame
            XCTAssertGreaterThanOrEqual(f.minX, 0, "\(id) is not cut off at the left", file: file, line: line)
            XCTAssertLessThanOrEqual(f.maxX, window.maxX + 1, "\(id) is not cut off at the right", file: file, line: line)
        }
        XCTAssertFalse(app.tabBars.firstMatch.exists && app.tabBars.firstMatch.isHittable, "the dock is hidden on the series page", file: file, line: line)
    }

    func testABigCoverFillsTheTopAndNothingIsCutOff() {
        let app = openSeries()
        XCTAssertTrue(any(app, "series-play").waitForExistence(timeout: 5))
        assertFits(app)
        XCTAssertFalse(any(app, "series-cover-art").exists, "a big enough cover is the full-width top")
        XCTAssertEqual(any(app, "series-progress").label, "1 of 3 read")
    }

    func testASmallCoverIsCentredArtworkNotAStretchedFullWidthPicture() {
        let app = openSeries(["-lime-demo-series-small-cover"])
        XCTAssertTrue(any(app, "series-cover-art").waitForExistence(timeout: 8), "centred artwork")
        assertFits(app)
        let art = any(app, "series-cover-art").frame, window = app.windows.firstMatch.frame
        XCTAssertLessThan(art.width, window.width - 100, "narrower than the screen: it is not stretched across it")
        XCTAssertEqual(art.midX, window.midX, accuracy: 3, "centred")
    }
}
