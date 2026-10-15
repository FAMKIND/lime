import XCTest

/// The 1:1 call screen (LIME-118), with no media: `-lime-demo-call voice|video` shows it in a made-up active call.
@MainActor
final class CallScreenUITests: XCTestCase {
    private func app(_ kind: String, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-call", kind] + extra
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testAVoiceCallHasOneRowOfControlsAndAVideoCallHasTheStack() {
        let voice = app("voice")
        XCTAssertTrue(any(voice, "call-screen").waitForExistence(timeout: 10))
        XCTAssertTrue(any(voice, "call-controls-voice").exists, "voice: one row")
        XCTAssertFalse(any(voice, "call-controls-video").exists)
        XCTAssertTrue(voice.buttons["call-end"].exists)
        XCTAssertTrue(voice.buttons["call-mute"].exists && voice.buttons["call-speaker"].exists)
        XCTAssertFalse(any(voice, "call-self-view").exists, "no self-view on a voice call")
        XCTAssertTrue(any(voice, "call-avatar").exists, "a large avatar until there is video")
        XCTAssertTrue(voice.staticTexts["call-status"].label.contains(":"), "the timer runs: \(voice.staticTexts["call-status"].label)")
        voice.terminate()

        let video = app("video")
        XCTAssertTrue(any(video, "call-controls-video").waitForExistence(timeout: 10), "video: the stack")
        XCTAssertFalse(any(video, "call-controls-voice").exists)
        XCTAssertTrue(video.buttons["call-flip"].exists && video.buttons["call-video"].exists && video.buttons["call-end"].exists)
        XCTAssertTrue(any(video, "call-self-view").exists, "my own picture in a tile")
    }

    func testVideoControlsFadeAfterFiveSecondsAndATapBringsThemBack() {
        let video = app("video")
        let end = video.buttons["call-end"]
        XCTAssertTrue(end.waitForExistence(timeout: 10))
        XCTAssertTrue(end.isHittable, "shown at first")
        // They fade after 5 s without a touch: no longer hittable (and invisible).
        let faded = NSPredicate { _, _ in !end.isHittable }
        expectation(for: faded, evaluatedWith: nil)
        waitForExpectations(timeout: 12)
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        let back = NSPredicate { _, _ in end.isHittable }
        expectation(for: back, evaluatedWith: nil)
        waitForExpectations(timeout: 3)
    }

    func testTheSelfViewDragsToAnotherCornerAndSwapsOnTap() {
        let video = app("video")
        let tile = any(video, "call-self-view")
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        let before = tile.frame
        let handle = any(video, "call-tile-handle")
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: video.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.8)))
        let moved = NSPredicate { _, _ in tile.frame.minX < before.minX - 100 && tile.frame.minY > before.minY + 100 }
        expectation(for: moved, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        XCTAssertLessThan(tile.frame.width, 200, "still a tile in the new corner")
        // A tap swaps the big and small pictures: my own picture becomes the big one.
        any(video, "call-tile-handle").tap()
        let big = NSPredicate { _, _ in tile.frame.width > 300 }
        expectation(for: big, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
    }

    func testTheNamePillOpensTheSmallSheetWithMessage() {
        let voice = app("voice")
        XCTAssertTrue(voice.buttons["call-name-pill"].waitForExistence(timeout: 10))
        voice.buttons["call-name-pill"].tap()
        XCTAssertTrue(any(voice, "call-person-sheet").waitForExistence(timeout: 5))
        XCTAssertTrue(voice.buttons["call-person-message"].exists)
    }

    // MARK: LIME-118b

    func testTheOtherSidesMutedStateShowsAsABadgeAndTheirCameraOffShowsTheAvatar() {
        let muted = app("video", ["-lime-demo-call-remote-muted"])
        XCTAssertTrue(any(muted, "call-remote-muted").waitForExistence(timeout: 10), "a muted badge by their name")
        XCTAssertEqual(any(muted, "call-remote-muted").label, "Sam Rivera is muted")
        muted.terminate()
        let off = app("video", ["-lime-demo-call-remote-camera-off"])
        XCTAssertTrue(any(off, "call-avatar").waitForExistence(timeout: 10), "their avatar, not black")
        XCTAssertFalse(any(off, "call-remote-muted").exists)
    }

    func testAVoiceCallHasAVideoButtonThatTurnsItIntoAVideoCall() {
        let voice = app("voice")
        XCTAssertTrue(voice.buttons["call-start-video"].waitForExistence(timeout: 10))
        voice.buttons["call-start-video"].tap()
        XCTAssertTrue(any(voice, "call-controls-video").waitForExistence(timeout: 5), "the screen switches to the video layout")
        XCTAssertFalse(any(voice, "call-controls-voice").exists)
    }

    func testTheVoiceRowFitsEveryScreenWithSixteenPointMargins() {
        let voice = app("voice")
        XCTAssertTrue(voice.buttons["call-start-video"].waitForExistence(timeout: 10))
        let width = voice.windows.firstMatch.frame.width
        let ids = ["call-start-video", "call-mute", "call-speaker", "call-route", "call-end"]
        let frames = ids.map { any(voice, $0).frame }
        XCTAssertGreaterThanOrEqual(frames.first!.minX, 16, "\(frames)")
        XCTAssertLessThanOrEqual(frames.last!.maxX, width - 16, "\(frames)")
        for (left, right) in zip(frames, frames.dropFirst()) { XCTAssertLessThanOrEqual(left.maxX, right.minX, "no overlap: \(left) \(right)") }
    }

    func testTheCallScreenFitsInLandscape() {
        let video = app("video")
        XCTAssertTrue(video.buttons["call-end"].waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        sleep(2)
        let bounds = video.windows.firstMatch.frame
        for id in ["call-end", "call-mute", "call-video", "call-flip", "call-name-pill"] {
            let frame = any(video, id).frame
            XCTAssertTrue(bounds.insetBy(dx: 0, dy: 0).contains(frame), "\(id) \(frame) is inside \(bounds)")
        }
        for id in ["call-minimize", "call-flip", "call-route"] { XCTAssertTrue(bounds.contains(any(video, id).frame), "\(id) is inside in landscape") }
        let ids = ["call-flip", "call-video", "call-mute", "call-minimize", "call-route", "call-end"]
        let frames = ids.map { any(video, $0).frame }
        for (left, right) in zip(frames, frames.dropFirst()) { XCTAssertFalse(left.intersects(right), "no overlap in landscape: \(left) \(right)") }
        XCTAssertFalse(any(video, "call-name-pill").frame.intersects(frames[0]), "the name pill is clear of the controls")
    }

    // MARK: LIME-118c

    func testAVideoCallsMinimiseButtonIsUnderMuteAndAVoiceCallsIsTopRight() {
        let video = app("video")
        XCTAssertTrue(video.buttons["call-minimize"].waitForExistence(timeout: 10))
        let order = ["call-video", "call-mute", "call-minimize", "call-route", "call-end"].map { any(video, $0).frame }
        for (above, below) in zip(order, order.dropFirst()) { XCTAssertLessThanOrEqual(above.maxY, below.minY, "one column, in order: \(order)") }
        XCTAssertEqual(order[1].midX, order[2].midX, accuracy: 1, "directly under Mute")
        video.terminate()

        let voice = app("voice")
        XCTAssertTrue(voice.buttons["call-minimize"].waitForExistence(timeout: 10))
        let frame = any(voice, "call-minimize").frame
        let pill = any(voice, "call-name-pill").frame
        XCTAssertGreaterThan(frame.midX, voice.windows.firstMatch.frame.width / 2, "top right")
        XCTAssertLessThan(abs(frame.midY - pill.midY), 30, "on the name pill's row")
        XCTAssertGreaterThanOrEqual(frame.width, 44)
    }

    func testMinimisingLeavesTheMiniPlayerAndTappingItReturnsToTheCall() {
        let voice = app("voice")
        XCTAssertTrue(voice.buttons["call-minimize"].waitForExistence(timeout: 10))
        voice.buttons["call-minimize"].tap()
        let bar = voice.buttons["call-mini-return"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "the mini player (no floating window in a voice call)")
        XCTAssertTrue(bar.label.hasSuffix("Double-tap to return"), bar.label)
        bar.tap()
        XCTAssertTrue(voice.buttons["call-end"].waitForExistence(timeout: 5), "back on the full call screen")
    }

    // MARK: LIME-119

    func testTheEmojiChipShowsFourEmojiAndOpensTheExplanation() {
        let call = app("video")
        let chip = any(call, "call-emoji")
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        XCTAssertTrue(chip.label.hasPrefix("Encrypted call. Emoji: "), chip.label)
        XCTAssertEqual(chip.label.dropFirst("Encrypted call. Emoji: ".count).split(separator: ",").count, 4, "four names for VoiceOver: \(chip.label)")
        XCTAssertGreaterThanOrEqual(chip.frame.height, 44, "a big enough target")
        chip.tap()
        XCTAssertTrue(any(call, "call-emoji-sheet").waitForExistence(timeout: 5))
        XCTAssertTrue(any(call, "call-emoji-explanation").label.contains("same 4 emoji"))
        XCTAssertTrue(any(call, "call-emoji-explanation").label.contains("end-to-end encrypted"))
        XCTAssertTrue(any(call, "call-emoji-large").label.hasPrefix("Emoji: "))
    }

    func testTheEmojiChipFitsBesideTheTimerAndMutedBadgeOnEveryScreen() {
        let call = app("voice", ["-lime-demo-call-remote-muted"])
        XCTAssertTrue(any(call, "call-emoji").waitForExistence(timeout: 10))
        let width = call.windows.firstMatch.frame.width
        let chip = any(call, "call-emoji").frame, badge = any(call, "call-remote-muted").frame, status = any(call, "call-status").frame
        XCTAssertFalse(chip.intersects(badge) || chip.intersects(status), "chip \(chip) badge \(badge) status \(status)")
        XCTAssertLessThanOrEqual(badge.maxX, width - 16, "nothing runs off the right edge")
    }
}
