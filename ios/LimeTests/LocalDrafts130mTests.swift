import XCTest
@testable import Lime

/// LIME-130-6b-2: a saved draft keeps each photo's and the cover's description and the recording's transcript; a draft saved before them still opens.
final class LocalDrafts130mTests: XCTestCase {
    private func attachment(_ name: String, mime: String, alt: String = "", transcript: String = "") -> OutgoingAttachment {
        OutgoingAttachment(bytes: Data([1, 2, 3]), name: name, mime: mime, width: nil, height: nil, durationMs: nil, thumb: Data(), poster: Data(), alt: alt, transcript: transcript)
    }

    func testDescriptionsAndTranscriptsSurviveSavingAndRestoring() throws {
        let (photo, _) = LocalDrafts.item(attachment("a.jpg", mime: "image/jpeg", alt: "A red kite"), file: "photo-0")
        let (clip, _) = LocalDrafts.item(attachment("r.m4a", mime: "audio/mp4", transcript: "Hello class."), file: "clip")
        var draft = LocalDraft(id: "d1", kind: "podcast", updated: Date())
        draft.photos = [photo]; draft.clip = clip
        // Through the same JSON the drafts folder holds.
        let decoded = try JSONDecoder().decode(LocalDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(decoded.photos.first?.alt, "A red kite")
        XCTAssertEqual(decoded.clip?.transcript, "Hello class.")
    }

    func testADraftSavedBeforeTheseFieldsStillDecodesWithNone() throws {
        let old = #"{"id":"d0","kind":"post","updated":0,"title":"","subtitle":"","words":"Hi","audience":"subscribers","topics":[],"coauthors":[],"trimStart":0,"trimEnd":0,"photos":[{"file":"photo-0","name":"a.jpg","mime":"image/jpeg"}]}"#
        let decoded = try JSONDecoder().decode(LocalDraft.self, from: Data(old.utf8))
        XCTAssertNil(decoded.photos.first?.alt)
        XCTAssertNil(decoded.photos.first?.transcript)
    }

    func testAnEmptyDescriptionIsNotStored() {
        let (item, _) = LocalDrafts.item(attachment("a.jpg", mime: "image/jpeg"), file: "photo-0")
        XCTAssertNil(item.alt)
        XCTAssertNil(item.transcript)
    }
}
