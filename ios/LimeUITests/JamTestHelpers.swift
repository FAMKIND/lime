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

    /// Opens the demo video recording's own page from its podcast card (LIME-200): the card's title.
    func openDemoVideoPost() {
        let title = buttons.matching(NSPredicate(format: "identifier == 'jam-podcast-title' AND label CONTAINS 'fraction walls'")).firstMatch
        for _ in 0..<5 where !title.exists || !title.isHittable { swipeUp() }
        if title.waitForExistence(timeout: 8) { title.tap() }
    }
}
