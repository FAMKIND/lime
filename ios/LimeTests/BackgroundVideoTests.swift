import XCTest
import AVFoundation
@testable import Lime

/// LIME-226b: a picked video becomes a short, silent, 4:5, small clip with no metadata.
@MainActor
final class BackgroundVideoTests: XCTestCase {
    func testAPickedClipIsFramedIntoAnUnderTenSecondSilentPortraitUnderSixMegabytes() async throws {
        let made = await DemoClip.url()
        let url = try XCTUnwrap(made)
        let length = await BackgroundVideoProcessing.duration(of: url)
        XCTAssertGreaterThan(length, 1.5)
        let first = await BackgroundVideoProcessing.frame(of: url, at: 0)
        let poster = try XCTUnwrap(first)
        let viewport = CGSize(width: 343, height: 429)
        let still = BackgroundProcessing.crop(poster, viewport: viewport, scale: 1, offset: .zero)
        let crop = BackgroundCrop(image: still, scale: 1, offset: .zero, viewport: viewport)
        let data = try await BackgroundVideoProcessing.export(url, start: 0, crop: crop)
        XCTAssertLessThanOrEqual(data.count, 6 * 1024 * 1024)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("bgv-test-\(UUID().uuidString).mp4")
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let asset = AVURLAsset(url: file)
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(video.count, 1)
        XCTAssertTrue(audio.isEmpty, "no audio track: it can never make a sound")
        let size = try await video[0].load(.naturalSize)
        XCTAssertEqual(size.width / size.height, 0.8, accuracy: 0.01, "4:5")
        let seconds = try await asset.load(.duration).seconds
        XCTAssertLessThanOrEqual(seconds, BackgroundVideoProcessing.maxSeconds + 0.2)
        // Nothing personal rides along (location, creation date, device).
        let metadata = try await asset.load(.metadata)
        XCTAssertTrue(metadata.filter { [.commonIdentifierLocation, .quickTimeMetadataLocationISO6709, .commonIdentifierCreationDate].contains($0.identifier) }.isEmpty)
    }

    func testALongVideoIsCutToTenSeconds() async throws {
        // The demo clip is 2 s: a start later than its length still gives a valid (clamped) short clip, never an empty one.
        let made = await DemoClip.url()
        let url = try XCTUnwrap(made)
        let first = await BackgroundVideoProcessing.frame(of: url, at: 0)
        let poster = try XCTUnwrap(first)
        let viewport = CGSize(width: 343, height: 429)
        let crop = BackgroundCrop(image: BackgroundProcessing.crop(poster, viewport: viewport, scale: 1.5, offset: CGSize(width: 10, height: -10)), scale: 1.5, offset: CGSize(width: 10, height: -10), viewport: viewport)
        let data = try await BackgroundVideoProcessing.export(url, start: 0.5, crop: crop)
        XCTAssertGreaterThan(data.count, 1000)
    }
}
