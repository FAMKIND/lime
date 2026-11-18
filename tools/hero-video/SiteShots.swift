import XCTest

/// LIME-286r: captures the app's real screens for limemessenger.com's feature phones (the states of the link workflows) into /tmp/286r/shots/.
/// Copy into ios/LimeUITests/ to run (see tools/hero-video/site-shots.sh); not part of the suite.
@MainActor
final class SiteShots: XCTestCase {
    private let avatars = ["-lime-demo-avatars", "/tmp/286r/avatars", "-lime-demo-covers", "/tmp/286r/covers"]
    private func app(_ screen: String, extra: [String] = [], theme: (String, String) = ("plain", "5")) -> XCUIApplication {
        let a = XCUIApplication()
        a.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", screen, "-lime-theme-background", theme.0, "-lime-theme-accent", theme.1, "-lime-demo-me-name", "Maya Ortiz"] + avatars + extra
        XCUIApplication(bundleIdentifier: "com.apple.mobilesafari").terminate()
        a.launch(); sleep(4); return a
    }
    private func snap(_ name: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/286r/shots/\(name).png")) }
    private func row(_ a: XCUIApplication, _ id: String) { let r = a.buttons["conversation-row-\(id)"]; XCTAssertTrue(r.waitForExistence(timeout: 10)); r.tap(); sleep(2) }

    func testChats() {
        let a = app("site-link")
        snap("link-list")
        row(a, "dm:talia"); snap("link-chat")
        let field = a.textViews["composer-field"]; XCTAssertTrue(field.waitForExistence(timeout: 8)); field.tap(); sleep(1)
        field.typeText("That’s the whole trick."); sleep(1); snap("link-typing-1")
        field.typeText(" Want my lab sheet for tomorrow?"); sleep(1); snap("link-typing")
        a.terminate()
        // LIME-349b: "sent" and "reply" are seeded (the seed's `-lime-demo-thread`), not sent for real: a real send stamps the shoot's own clock and catches "Sending…".
        let b = app("site-chat", extra: ["-lime-demo-thread", "sent"])
        let f2 = b.textViews["composer-field"]; if f2.waitForExistence(timeout: 8) { f2.tap(); sleep(1) }; snap("link-sent")
        b.terminate()
        let c = app("site-chat", extra: ["-lime-demo-thread", "reply"])
        let f3 = c.textViews["composer-field"]; if f3.waitForExistence(timeout: 8) { f3.tap(); sleep(1) }; snap("link-reply")
        let reply = c.staticTexts["YES. I’ll trade you my poem-of-the-week list 😄"]; if reply.waitForExistence(timeout: 5) { reply.press(forDuration: 0.9); sleep(2); snap("link-bar"); let heart = c.buttons["react-❤️"]; if heart.waitForExistence(timeout: 3) { heart.tap(); sleep(1); snap("link-reacted") } }
    }
    func testGroup() {
        let a = app("site-link", extra: [])
        row(a, "grp:demo1"); snap("link-group")
        let title = a.staticTexts["Robotics regional"].firstMatch; if title.exists { title.tap(); sleep(2); snap("link-group-info") }
    }
    func testCall() { _ = app("site-call"); sleep(3); snap("link-call") }
    func testCallMini() { _ = app("site-call-mini"); sleep(4); snap("link-call-mini") }
    /// LIME-349c: the offline story is told by the status bar (Wi-Fi off, no service: site-shots.sh sets it for this test) and the bubble's own status line.
    func testOfflineNoSignal() {
        for s in ["waiting", "passed"] { _ = app("site-offline-\(s)"); sleep(2); snap("link-offline-\(s)"); XCUIApplication().terminate() }
    }
    func testOfflineSent() { _ = app("site-offline-sent"); sleep(2); snap("link-offline-sent"); XCUIApplication().terminate() }
    func testThemes() {
        for (name, bg, acc) in [("paper-pink", "paper", "0"), ("chalkboard-lime", "chalkboard", "5"), ("bulletin-blue", "bulletin", "4"), ("living-lavender", "living", "6"), ("dots-orange", "dots", "2")] {
            let a = app("site-chat", theme: (bg, acc)); sleep(2); snap("yours-\(name)"); a.terminate()
        }
    }
    private func ids(_ a: XCUIApplication, _ n: String) { try? a.debugDescription.write(toFile: "/tmp/286r/\(n).txt", atomically: true, encoding: .utf8) }
    private func tap(_ a: XCUIApplication, _ id: String, wait: Double = 6) { let e = a.descendants(matching: .any).matching(identifier: id).firstMatch; XCTAssertTrue(e.waitForExistence(timeout: wait), id); e.tap(); sleep(2) }
    /// Scrolls the feed until the element is on screen (the feed is lazy: a card below the fold does not exist yet), then taps it.
    private func reveal(_ a: XCUIApplication, _ id: String) {
        let e = a.descendants(matching: .any).matching(identifier: id).firstMatch
        for _ in 0..<8 { if e.exists && e.isHittable { break }; a.swipeUp(); sleep(1) }
        XCTAssertTrue(e.exists, id); e.tap(); sleep(2)
    }

    private func tapLabel(_ a: XCUIApplication, _ label: String) { let e = a.buttons[label].firstMatch; if e.waitForExistence(timeout: 6) { e.tap() } else { a.staticTexts[label].firstMatch.tap() }; sleep(2) }

    func testJamFeed() {
        let a = app("site-jam"); sleep(2); snap("jam-feed")
        a.swipeUp(); sleep(1); snap("jam-feed2")
        a.swipeUp(); sleep(1); snap("jam-feed3")
        a.swipeUp(); sleep(1); snap("jam-feed4")
        a.swipeUp(); sleep(1); snap("jam-feed5")
    }
    func testJamArticle() {
        let a = app("site-jam"); sleep(2)
        tap(a, "jam-post-site-sci-1"); snap("jam-article")
        // LIME-349d: the whole article as frames, scrolled by a fixed drag; `tools/hero-video/stitch.py` joins them into one tall picture.
        for n in 1...5 {
            let from = a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78)), to = a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34))
            from.press(forDuration: 0.1, thenDragTo: to); sleep(2); snap("jam-article-s\(n)")
        }
        a.swipeUp(); sleep(1); snap("jam-article2")
    }
    func testJamPodcasts() {
        let a = app("site-jam"); sleep(2)
        tap(a, "jam-segment-Podcasts"); snap("jam-podcasts"); ids(a, "ids-podcasts")
        // Walt's is a video podcast (LIME-349d): tapping its video opens the full-screen video player.
        let video = a.descendants(matching: .any).matching(identifier: "jam-video").firstMatch
        if video.waitForExistence(timeout: 8) { video.tap() }
        sleep(4); snap("jam-podcast-video"); ids(a, "ids-video")
        a.terminate()
        // Kofi's is audio: its own player.
        let b = app("site-jam"); sleep(2)
        tap(b, "jam-segment-Podcasts")
        tap(b, "jam-audio-play-site-kofi-pod-audio"); sleep(1); snap("jam-podcast-playing"); ids(b, "ids-playing")
    }
    func testJamSeries() {
        let a = app("site-jam"); sleep(2)
        reveal(a, "jam-card-series-site-walt-1"); snap("jam-series"); ids(a, "ids-series")
    }
    func testJamBand() {
        let a = app("site-jam"); sleep(2)
        tap(a, "jam-post-site-sci-1"); a.swipeUp(); sleep(1)
        tap(a, "jam-article-jam-card"); snap("jam-band-open")
    }
    func testJamBandPage() {
        let a = app("site-jam-band"); sleep(2); snap("jam-band"); ids(a, "ids-bandinfo")
        tap(a, "profile-tab-Articles"); snap("jam-band-posts")
        a.swipeUp(); sleep(1); snap("jam-band-posts2")
        a.swipeDown(); sleep(1)
        tap(a, "profile-tab-Members"); snap("jam-band-members"); ids(a, "ids-bandpage")
    }
    /// LIME-349d: what someone who has not subscribed sees: the band's page with Subscribe, and the Posts tab saying so.
    func testJamLocked() {
        let a = app("site-jam-locked"); sleep(2)
        tap(a, "profile-tab-Posts"); snap("jam-members-locked"); ids(a, "ids-locked")
    }
    func testJamMembers() {
        let a = app("site-jam"); sleep(2)
        reveal(a, "jam-post-site-sci-2"); snap("jam-members-post")
    }
}
