import XCTest
@testable import Lime

/// LIME-130-6c: join states, recorder speech, co-edit announcements.
final class Access130jTests: XCTestCase {
    func testJoinStatesAreSpoken() {
        XCTAssertEqual(JoinSpeech.words(state: "asked", name: "Math Club"), "Asked to join Math Club")
        XCTAssertEqual(JoinSpeech.words(state: "joined", name: "Math Club"), "Joined Math Club")
        XCTAssertEqual(JoinSpeech.words(state: "full", name: "Math Club"), "Math Club is full")
        XCTAssertNil(JoinSpeech.words(state: nil, name: "Math Club"))
    }

    func testTheRecorderSaysRecordingPausedAndStoppedWithTheLength() {
        XCTAssertEqual(RecorderSpeech.change(wasRecording: false, isRecording: true, wasPaused: false, isPaused: false, elapsed: 0), "Recording")
        XCTAssertEqual(RecorderSpeech.change(wasRecording: true, isRecording: true, wasPaused: false, isPaused: true, elapsed: 5), "Paused")
        XCTAssertEqual(RecorderSpeech.change(wasRecording: true, isRecording: true, wasPaused: true, isPaused: false, elapsed: 5), "Recording")
        XCTAssertEqual(RecorderSpeech.change(wasRecording: true, isRecording: false, wasPaused: false, isPaused: false, elapsed: 130), "Stopped, 2 minutes 10 seconds")
        XCTAssertNil(RecorderSpeech.change(wasRecording: true, isRecording: true, wasPaused: false, isPaused: false, elapsed: 6))
    }

    func testEditingIsSaidOnceEveryFiveSecondsPerPerson() {
        var announcer = EditingAnnouncer()
        let t = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(announcer.shouldSay(person: "jean", now: t))
        XCTAssertFalse(announcer.shouldSay(person: "jean", now: t.addingTimeInterval(4.9)))
        XCTAssertTrue(announcer.shouldSay(person: "sam", now: t.addingTimeInterval(1)), "each person has their own clock")
        XCTAssertTrue(announcer.shouldSay(person: "jean", now: t.addingTimeInterval(5.1)))
    }
}
