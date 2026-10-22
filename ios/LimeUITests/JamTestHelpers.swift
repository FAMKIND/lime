import XCTest

extension XCUIApplication {
    /// The jam feed's Posts | Articles control (LIME-188t): an article is under Articles.
    func showJamArticles() {
        let control = segmentedControls["jam-filter-segments"]
        if control.waitForExistence(timeout: 8) { control.buttons["Articles"].tap() }
    }

    /// The same control in a profile's Posts section.
    func showProfileArticles() {
        let control = segmentedControls["profile-posts-filter-segments"]
        if control.waitForExistence(timeout: 8) { control.buttons["Articles"].tap() }
    }
}
