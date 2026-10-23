import XCTest
@testable import Lime

/// LIME-188y: the media frame rule and the waveform's bars.
final class JamFrameTests: XCTestCase {
    func testAPortraitPhotoInAPhoneColumnKeepsItsShape() {
        let size = JamMedia.size(ratio: JamMedia.portrait, column: 335, screenHeight: 812)
        XCTAssertEqual(size.width, 335, accuracy: 0.01)
        XCTAssertEqual(size.height, 335 / JamMedia.portrait, accuracy: 0.01, "4:5, taller than wide")
    }

    func testALandscapePhotoIsSixteenByNine() {
        let size = JamMedia.size(ratio: JamMedia.landscape, column: 335, screenHeight: 812)
        XCTAssertEqual(size.width / size.height, JamMedia.landscape, accuracy: 0.001)
    }

    func testSidewaysOnAPhoneTheColumnIsCappedAndNeverTallerThanEightyPercentOfTheScreen() {
        // 13 mini on its side: 812 × 375, the column 772 wide.
        let size = JamMedia.size(ratio: JamMedia.portrait, column: 772, screenHeight: 375)
        XCTAssertLessThanOrEqual(size.width, JamMedia.maxColumn)
        XCTAssertLessThanOrEqual(size.height, 375 * 0.8 + 0.01)
        XCTAssertEqual(size.width / size.height, JamMedia.portrait, accuracy: 0.001, "still 4:5: nothing is stretched")
        let wide = JamMedia.size(ratio: JamMedia.landscape, column: 772, screenHeight: 375)
        XCTAssertLessThanOrEqual(wide.width, JamMedia.maxColumn)
        XCTAssertLessThanOrEqual(wide.height, 375 * 0.8 + 0.01)
    }

    func testTheBarsHaveOneWidthAndTheCountFollowsTheWidth() {
        XCTAssertEqual(WaveformBars.barWidth, 2.5)
        XCTAssertEqual(WaveformBars.gap, 2)
        XCTAssertEqual(WaveformBars.count(forWidth: 90), 20)
        XCTAssertGreaterThan(WaveformBars.count(forWidth: 400), WaveformBars.count(forWidth: 200), "wider, more bars; never wider bars")
        XCTAssertEqual(WaveformBars.count(forWidth: 1), 1)
    }

    func testResamplingKeepsTheLoudestOfEachStretch() {
        XCTAssertEqual(WaveformBars.resample([10, 200, 30, 40], to: 2), [200, 40])
        XCTAssertEqual(WaveformBars.resample([1, 2, 3], to: 3), [1, 2, 3])
        XCTAssertEqual(WaveformBars.resample([5, 9], to: 4).count, 4, "more bars than values repeats them")
        XCTAssertTrue(WaveformBars.resample([], to: 4).isEmpty)
    }
}

/// LIME-196: the sideways row's items never overlap, in portrait or landscape.
final class JamRowTests: XCTestCase {
    func testItemsOfARowNeverIntersectAndStayInsideTheColumnPortraitAndLandscape() {
        // (screen width, screen height) of a phone upright and on its side.
        let screens: [(CGFloat, CGFloat)] = [(320, 568), (375, 812), (430, 932), (667, 320), (844, 375), (932, 430)]
        for (width, height) in screens {
            let column = width - 40
            let size = JamMedia.size(ratio: JamMedia.portrait, column: column - 28, screenHeight: height)
            let rects = (0..<5).map { CGRect(x: CGFloat($0) * (size.width + JamMedia.gap), y: 0, width: size.width, height: size.height) }
            for (a, b) in zip(rects, rects.dropFirst()) { XCTAssertFalse(a.intersects(b), "\(width)×\(height)") }
            XCTAssertLessThanOrEqual(size.width, column - 28 + 0.01)
            XCTAssertLessThanOrEqual(size.height, height * 0.8 + 0.01)
        }
    }
}
