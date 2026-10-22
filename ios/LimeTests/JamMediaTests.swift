import XCTest
@testable import Lime

/// LIME-188j: the standard frames and when a video card may start by itself.
final class JamMediaTests: XCTestCase {
    func testAPictureTakesTheNearerOfThePortraitAndLandscapeFrames() {
        XCTAssertEqual(JamMedia.ratio(width: 1000, height: 1000), JamMedia.portrait, "a square is nearer 4:5")
        XCTAssertEqual(JamMedia.ratio(width: 3000, height: 4000), JamMedia.portrait)
        XCTAssertEqual(JamMedia.ratio(width: 4000, height: 3000), JamMedia.landscape)
        XCTAssertEqual(JamMedia.ratio(width: 1920, height: 1080), JamMedia.landscape)
        XCTAssertEqual(JamMedia.ratio(width: nil, height: nil), JamMedia.landscape)
    }

    func testAVideoStartsByItselfOnlyWhenItIsOnThePhoneOrOnWiFiWithoutLowDataAndMotionAllowsIt() {
        XCTAssertTrue(VideoAutoplay.allows(onPhone: true, wifiWithoutLowData: false, systemAutoplay: true))
        XCTAssertTrue(VideoAutoplay.allows(onPhone: false, wifiWithoutLowData: true, systemAutoplay: true))
        XCTAssertFalse(VideoAutoplay.allows(onPhone: false, wifiWithoutLowData: false, systemAutoplay: true), "cellular or Low Data Mode: a play button")
        XCTAssertFalse(VideoAutoplay.allows(onPhone: true, wifiWithoutLowData: true, systemAutoplay: false), "Auto-Play Video Previews is off")
    }

    func testTheCaptionLineIsTheCueThatIsShowingNow() {
        let cues = [CaptionCue(startMs: 0, endMs: 1000, text: "One"), CaptionCue(startMs: 1000, endMs: 2500, text: "Two")]
        XCTAssertEqual(JamCaptions.line(at: 500, in: cues), "One")
        XCTAssertEqual(JamCaptions.line(at: 1000, in: cues), "Two")
        XCTAssertNil(JamCaptions.line(at: 2500, in: cues))
    }
}
