import XCTest

extension XCUIApplication {
    /// The jam feed's Posts | Articles control (LIME-188t): an article is under Articles.
    func showJamArticles() {
        let control = descendants(matching: .any).matching(identifier: "jam-filter-segments").firstMatch
        if control.waitForExistence(timeout: 8) { control.buttons["Articles"].tap() }
    }

    /// A profile's Articles tab (LIME-188x).
    func showProfileArticles() {
        let tab = buttons["profile-tab-Articles"]
        if tab.waitForExistence(timeout: 8) { tab.tap() }
    }

    /// Scrolls the demo video recording's big card into view in the main feed (LIME-203: a video podcast is a video card there).
    func openDemoVideoPost() {
        let card = descendants(matching: .any)["jam-video"]
        for _ in 0..<6 where !card.exists || !card.isHittable { swipeUp() }
    }
}
