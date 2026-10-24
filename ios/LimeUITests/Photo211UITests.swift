import XCTest

/// LIME-211: the photo viewer's gestures (demo).
@MainActor
final class Photo211UITests: LimeUITestCase {
    func testPinchZoomsAndSwipeDownCloses() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-following"]
        app.launch()
        app.showJamArticles()
        let card = app.buttons["jam-post-demo-post-1"]
        XCTAssertTrue(card.waitForExistence(timeout: 10)); card.tap()
        let photo = app.descendants(matching: .any)["jam-row-photo-0"]
        for _ in 0..<4 where !photo.exists { app.swipeUp() }
        XCTAssertTrue(photo.waitForExistence(timeout: 8)); photo.tap()
        let zoom = app.descendants(matching: .any)["photo-zoom"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 8))
        XCTAssertFalse((zoom.value as? String ?? "").hasPrefix("Zoomed"), "not zoomed at first")
        zoom.pinch(withScale: 2.5, velocity: 2)
        expectation(for: NSPredicate(format: "value BEGINSWITH 'Zoomed'"), evaluatedWith: zoom)
        waitForExpectations(timeout: 5)
        zoom.doubleTap()   // zooms back out
        expectation(for: NSPredicate(format: "NOT (value BEGINSWITH 'Zoomed')"), evaluatedWith: zoom)
        waitForExpectations(timeout: 5)
        zoom.swipeDown(velocity: .fast)
        XCTAssertTrue(app.descendants(matching: .any)["attachment-viewer"].waitForNonExistence(timeout: 5), "swipe down closes")
    }
}
