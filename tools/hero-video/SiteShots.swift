import XCTest

/// LIME-286r: captures the app's real screens for limemessenger.com's feature phones (the states of the link workflows) into /tmp/286r/shots/.
/// Copy into ios/LimeUITests/ to run (see tools/hero-video/site-shots.sh); not part of the suite.
@MainActor
final class SiteShots: XCTestCase {
    private let avatars = ["-lime-demo-avatars", "/tmp/286r/avatars"]
    private func app(_ screen: String, extra: [String] = [], theme: (String, String) = ("plain", "5")) -> XCUIApplication {
        let a = XCUIApplication()
        a.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", screen, "-lime-theme-background", theme.0, "-lime-theme-accent", theme.1] + avatars + extra
        a.launch(); sleep(4); return a
    }
    private func snap(_ name: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/286r/shots/\(name).png")) }
    private func row(_ a: XCUIApplication, _ id: String) { let r = a.buttons["conversation-row-\(id)"]; XCTAssertTrue(r.waitForExistence(timeout: 10)); r.tap(); sleep(2) }

    func testChats() {
        let a = app("site-link", extra: ["-lime-demo-autoreply", "Sending it now. Thanks for asking!"])
        snap("link-list")
        row(a, "dm:mei"); snap("link-chat")
        let field = a.textViews["composer-field"]; XCTAssertTrue(field.waitForExistence(timeout: 8)); field.tap(); sleep(1)
        field.typeText("Can you share the fraction"); sleep(1); snap("link-typing-1")
        field.typeText(" wall?"); sleep(1); snap("link-typing")
        a.buttons["send-button"].tap(); sleep(1); snap("link-sent")
        sleep(3); snap("link-reply")
        let reply = a.staticTexts["Sending it now. Thanks for asking!"]; if reply.waitForExistence(timeout: 5) { reply.press(forDuration: 0.9); sleep(2); snap("link-bar"); let heart = a.buttons["react-❤️"]; if heart.waitForExistence(timeout: 3) { heart.tap(); sleep(1); snap("link-reacted") } }
    }
    func testGroup() {
        let a = app("site-link", extra: [])
        row(a, "grp:demo1"); snap("link-group")
        let title = a.staticTexts["Grade 4 Team"].firstMatch; if title.exists { title.tap(); sleep(2); snap("link-group-info") }
    }
    func testCall() { _ = app("site-call"); sleep(3); snap("link-call") }
    func testOffline() {
        for s in ["waiting", "passed", "sent"] { _ = app("site-offline-\(s)"); sleep(2); snap("link-offline-\(s)"); XCUIApplication().terminate() }
    }
    func testThemes() {
        for (name, bg, acc) in [("paper-pink", "paper", "0"), ("chalkboard-lime", "chalkboard", "5"), ("bulletin-blue", "bulletin", "4"), ("living-lavender", "living", "6"), ("dots-orange", "dots", "2")] {
            let a = app("site-chat", theme: (bg, acc)); sleep(2); snap("yours-\(name)"); a.terminate()
        }
    }
}
