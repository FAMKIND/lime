import XCTest
@testable import Lime

/// LIME-130-6a: jam cards read as one stop; the player's controls stay for assistive technology.
final class Access130iTests: XCTestCase {
    func testAnArticleCardReadsAuthorTimeUnreadTitleSeriesSavedAndCounts() {
        let words = JamCardSpeech.label(author: "Mei Lin", time: "Oct 22, 3:04 PM", unread: true, title: "Fractions", subtitle: "A way in", text: "Fractions are parts of a whole.",
                                        series: "Part 2 of the series Math", saved: true, likes: 3, liked: true, comments: 1)
        XCTAssertEqual(words, "Mei Lin, Oct 22, 3:04 PM, Unread, Fractions, A way in, Fractions are parts of a whole., Part 2 of the series Math, Saved, 3 likes, you liked it, 1 comment")
    }

    func testAQuickPostReadsItsWordsOnceAndNoZeroCounts() {
        let words = JamCardSpeech.label(author: "Sam", time: "Nov 9", unread: false, title: "", subtitle: "", text: "Back to school", series: nil, saved: false, likes: 0, liked: false, comments: 0)
        XCTAssertEqual(words, "Sam, Nov 9, Back to school")
        let same = JamCardSpeech.label(author: "Sam", time: "Nov 9", unread: false, title: "Back to school", subtitle: "", text: "Back to school", series: nil, saved: false, likes: 1, liked: false, comments: 0)
        XCTAssertEqual(same, "Sam, Nov 9, Back to school, 1 like")
    }

    func testTheActionNamesFlipWithTheState() {
        XCTAssertEqual(JamCardSpeech.likeAction(liked: false), "Like")
        XCTAssertEqual(JamCardSpeech.likeAction(liked: true), "Unlike")
        XCTAssertEqual(JamCardSpeech.saveAction(saved: true), "Unsave")
    }

    func testPlayerControlsStayWhenAnyAssistiveToolRuns() {
        XCTAssertFalse(PlayerControls.keepsVisible(voiceOver: false, switchControl: false, assistiveTouch: false))
        XCTAssertTrue(PlayerControls.keepsVisible(voiceOver: true, switchControl: false, assistiveTouch: false))
        XCTAssertTrue(PlayerControls.keepsVisible(voiceOver: false, switchControl: true, assistiveTouch: false))
        XCTAssertTrue(PlayerControls.keepsVisible(voiceOver: false, switchControl: false, assistiveTouch: true))
    }
}
