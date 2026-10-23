import XCTest

extension XCUIApplication {
    /// The jam feed's Posts | Articles control (LIME-188t): an article is under Articles.
    func showJamArticles() {
        let control = segmentedControls["jam-filter-segments"]
        if control.waitForExistence(timeout: 8) { control.buttons["Articles"].tap() }
    }

    /// A profile's Articles tab (LIME-188x).
    func showProfileArticles() {
        let tab = buttons["profile-tab-Articles"]
        if tab.waitForExistence(timeout: 8) { tab.tap() }
    }
}
