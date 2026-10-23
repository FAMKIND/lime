import XCTest
@testable import Lime

/// LIME-199: the "Up next" queue's order.
@MainActor
final class JamQueueTests: XCTestCase {
    private func item(_ id: String) -> NowPlaying.Item {
        let file = JamAttachmentInfo(attachmentId: id, name: "a.m4a", mime: "audio/mp4", kind: "audio", size: 1, width: nil, height: nil, durationMs: 1000, thumb: Data(), poster: Data(), available: true)
        return NowPlaying.Item(postID: id, file: file, controller: PodcastController(duration: 1, title: id, artist: ""), title: id, subtitle: "")
    }

    func testPlayNextGoesFirstAddToQueueLastAndNoRepeats() {
        let now = NowPlaying()
        now.start(item("now"))
        now.enqueue(item("b")); now.enqueue(item("c")); now.enqueue(item("b"))
        XCTAssertEqual(now.queue.map(\.postID), ["b", "c"], "no repeat")
        now.playNext(item("c"))
        XCTAssertEqual(now.queue.map(\.postID), ["c", "b"], "play next goes first")
        now.enqueue(item("now"))
        XCTAssertEqual(now.queue.count, 2, "what is playing is not queued")
        now.advance()
        XCTAssertEqual(now.item?.postID, "c")
        XCTAssertEqual(now.queue.map(\.postID), ["b"])
    }
}
