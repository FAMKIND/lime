import XCTest
@testable import Lime

/// LIME-130-6b: photo labels, the caption plan by iOS version and model, caption limits, cue grouping, the card's cover description.
final class Access130lTests: XCTestCase {
    func testAPhotoIsReadByItsDescriptionOrJustPhotoNeverTheFileName() {
        XCTAssertEqual(JamPhotoLabel.label(alt: "A red kite over the field"), "A red kite over the field")
        XCTAssertEqual(JamPhotoLabel.label(alt: "  \n "), "Photo")
        XCTAssertEqual(JamPhotoLabel.label(alt: ""), "Photo")
        XCTAssertEqual(JamPhotoLabel.value(index: 1, count: 5), "2 of 5")
        XCTAssertEqual(JamPhotoLabel.value(index: 0, count: 1), "")
    }

    func testTheCaptionPlanByModelAndLength() {
        // iOS 26 with the language model installed: no cap, however long.
        XCTAssertEqual(CaptionMaker.plan(analyzerInstalled: true, supportsOnDevice: true, seconds: 3600), .analyzer)
        XCTAssertEqual(CaptionMaker.plan(analyzerInstalled: true, supportsOnDevice: false, seconds: 900), .analyzer)
        // No analyzer model (iOS 17-25, or iOS 26 without the model): the older recogniser, five minutes at most.
        XCTAssertEqual(CaptionMaker.plan(analyzerInstalled: false, supportsOnDevice: true, seconds: 299), .recogniser)
        XCTAssertEqual(CaptionMaker.plan(analyzerInstalled: false, supportsOnDevice: true, seconds: 301), .tooLong)
        XCTAssertEqual(CaptionMaker.plan(analyzerInstalled: false, supportsOnDevice: true, seconds: nil), .recogniser)
        // Nothing on this phone can do it on its own: no captions, and lime never downloads a model.
        XCTAssertEqual(CaptionMaker.plan(analyzerInstalled: false, supportsOnDevice: false, seconds: 10), .unavailable)
    }

    func testALongRecordingsCaptionsStopAtTheCoresLimitsAndSayWhere() {
        let few = (0..<10).map { CaptionCue(startMs: UInt64($0) * 1000, endMs: UInt64($0) * 1000 + 900, text: "Line \($0)") }
        XCTAssertEqual(CaptionMaker.limited(few).cues.count, 10)
        XCTAssertNil(CaptionMaker.limited(few).stoppedAtMs)
        let many = (0..<7000).map { CaptionCue(startMs: UInt64($0) * 1000, endMs: UInt64($0) * 1000 + 900, text: "Line") }
        let cut = CaptionMaker.limited(many)
        XCTAssertEqual(cut.cues.count, CaptionMaker.maxCues)
        XCTAssertEqual(cut.stoppedAtMs, cut.cues.last?.endMs, "told where they stop")
        let big = (0..<3000).map { CaptionCue(startMs: UInt64($0) * 1000, endMs: UInt64($0) * 1000 + 900, text: String(repeating: "word ", count: 40)) }
        let bytes = CaptionMaker.limited(big)
        XCTAssertLessThan(bytes.cues.count, 3000, "cut by size")
        XCTAssertNotNil(bytes.stoppedAtMs)
    }

    func testWordsBecomeLinesAfterSevenWordsAPauseOrFourSeconds() {
        let words = (0..<10).map { (text: "w\($0)", start: Double($0) * 0.3, duration: 0.25) }
        let cues = CaptionMaker.cues(fromWords: words)
        XCTAssertEqual(cues?.count, 2)
        XCTAssertEqual(cues?.first?.text, "w0 w1 w2 w3 w4 w5 w6")
        let paused = CaptionMaker.cues(fromWords: [("Hello", 0, 0.4), ("there", 0.5, 0.4), ("Next", 5, 0.4)])
        XCTAssertEqual(paused?.map(\.text), ["Hello there", "Next"])
        XCTAssertNil(CaptionMaker.cues(fromWords: []))
    }

    func testACardReadsTheCoversDescription() {
        let words = JamCardSpeech.label(author: "Mei", time: "Oct 22", unread: false, title: "Fractions", subtitle: "", text: "", series: nil, saved: false, likes: 0, liked: false, comments: 0, coverAlt: "A lime on a desk")
        XCTAssertEqual(words, "Mei, Oct 22, Fractions, Cover: A lime on a desk")
    }
}
