import XCTest
@testable import Lime

/// LIME-203: which card a post gets, in one place.
final class JamCardChoiceTests: XCTestCase {
    private func style(audio: Bool = false, video: Bool = false, record: Bool = true, ready: Bool = true, _ place: JamCardPlace) -> JamCardStyle {
        JamCardChoice.style(isRecording: record, ready: ready, hasAudio: audio, hasVideo: video, place: place)
    }

    func testAVideoRecordingIsABigCardInTheMainFeedAndASmallOneInTheCompactLists() {
        XCTAssertEqual(style(video: true, .feed(.all)), .videoPodcast)
        XCTAssertEqual(style(video: true, .orgPage(.all)), .videoPodcast)
        XCTAssertEqual(style(video: true, .feed(.podcasts)), .smallPodcast)
        XCTAssertEqual(style(video: true, .profileTab(.podcasts)), .smallPodcast)
    }

    func testAnAudioRecordingIsAlwaysTheSmallCardAndOthersAreRegular() {
        for place in [JamCardPlace.feed(.all), .feed(.podcasts), .profileTab(.podcasts), .orgPage(.all)] { XCTAssertEqual(style(audio: true, place), .smallPodcast) }
        XCTAssertEqual(style(audio: true, video: true, .feed(.all)), .smallPodcast, "a recording with sound and picture files is the audio one")
        XCTAssertEqual(style(video: true, record: false, .feed(.all)), .regular)
        XCTAssertEqual(style(video: true, ready: false, .feed(.all)), .regular)
        XCTAssertEqual(style(.feed(.all)), .regular, "nothing to play")
    }
}
