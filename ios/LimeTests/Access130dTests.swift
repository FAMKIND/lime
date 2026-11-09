import Speech
import XCTest
@testable import Lime

/// LIME-130-3b: photo descriptions and on-device transcripts.
final class Access130dTests: XCTestCase {
    func testTheOnDeviceRuleDecidesBeforeAnyAudioIsRead() {
        typealias C = Transcriber.Capability
        XCTAssertEqual(Transcriber.plan(C(hasAnalyzer: true, supportsOnDevice: false), seconds: 900), .analyzer, "iOS 26's analyzer has no 300 s limit")
        XCTAssertEqual(Transcriber.plan(C(hasAnalyzer: false, supportsOnDevice: true), seconds: 120), .recogniser)
        XCTAssertEqual(Transcriber.plan(C(hasAnalyzer: false, supportsOnDevice: true), seconds: 301), .tooLong, "the older recogniser stops at 300 s")
        XCTAssertEqual(Transcriber.plan(C(hasAnalyzer: false, supportsOnDevice: true), seconds: nil), .recogniser)
        XCTAssertEqual(Transcriber.plan(C(hasAnalyzer: false, supportsOnDevice: false), seconds: 10), .unavailable,
                       "a phone that cannot do the language on its own gets no transcript, never a server's")
    }

    func testTheRequestIsOnDeviceWhateverElseIsSet() {
        let request = Transcriber.request(url: URL(fileURLWithPath: "/tmp/x.m4a"))
        XCTAssertTrue(request.requiresOnDeviceRecognition, "the recogniser may not send audio to Apple")
        XCTAssertFalse(request.shouldReportPartialResults)
    }

    func testTheFileExtensionIsRightForVoiceAndVideo() {
        XCTAssertEqual(Transcriber.fileExtension(forMime: "video/mp4"), "mp4")
        XCTAssertEqual(Transcriber.fileExtension(forMime: "audio/mp4"), "m4a")
        XCTAssertEqual(Transcriber.fileExtension(forMime: "audio/unknown-thing"), "m4a")
    }

    func testAPhotoCarriesItsDescriptionAndAVoiceMessageItsTranscript() {
        let info = AttachmentInfo(id: "a", mime: "image/jpeg", name: "IMG_0042.jpg", size: 10, width: 1, height: 1, durationMs: nil, thumb: Data(), poster: Data(),
                                  alt: "A red kite over the school field", transcript: "Hello class", downloaded: true, removed: false)
        let item = AttachmentItem(info)
        XCTAssertEqual(item.alt, "A red kite over the school field")
        XCTAssertEqual(item.transcript, "Hello class")
    }

    @MainActor
    func testATranscriptThePhoneAlreadyHasIsShownWithoutMakingAnother() {
        var item = AttachmentItem(id: "t1", mime: "audio/mp4", name: "Voice message.m4a", size: 10, durationMs: 4000, downloaded: true)
        XCTAssertEqual(Transcripts.shared.state(for: item), .idle)
        item.transcript = "Thank you all"
        XCTAssertEqual(Transcripts.shared.state(for: item), .text("Thank you all"), "one made earlier and kept with the message")
        XCTAssertFalse(Transcripts.shared.isShown(item), "but it opens only on request")
    }

    func testTheDescriptionSheetStopsAtTwoHundredAndFiftyCharacters() {
        XCTAssertEqual(PhotoDescriptionSheet.limit, 250)
    }
}
