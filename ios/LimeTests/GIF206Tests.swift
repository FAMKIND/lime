import XCTest
@testable import Lime

/// LIME-206: a GIF stays a GIF; a too-big one is refused (never a JPEG); a JPEG is still a JPEG.
final class GIF206Tests: XCTestCase {
    func testAGIFIsSentAsTheSameBytesWithItsFirstFrameAsThePreview() throws {
        let data = GIFFixtures.make(frames: 4, size: CGSize(width: 90, height: 60))
        XCTAssertTrue(GIF.isGIF(data))
        let (item, preview) = try GIF.attachment(data, name: "party.gif")
        XCTAssertEqual(item.mime, "image/gif")
        XCTAssertEqual(item.bytes, data, "the file itself, not redrawn")
        XCTAssertEqual(item.name, "party.gif")
        XCTAssertEqual(item.width, 90); XCTAssertEqual(item.height, 60)
        XCTAssertFalse(item.thumb.isEmpty)
        XCTAssertGreaterThan(preview.size.width, 0)
        XCTAssertEqual(GIF.frameCount(data), 4)
    }

    func testTooManyFramesOrTooManyBytesIsRefusedWithoutAFallback() throws {
        let many = GIFFixtures.make(frames: GIF.maxFrames + 1, size: CGSize(width: 4, height: 4))
        XCTAssertThrowsError(try GIF.attachment(many)) { XCTAssertEqual($0 as? GIF.Problem, .tooBig) }
        XCTAssertEqual(GIF.tooBigMessage, "This GIF is too big to send")
        var big = GIFFixtures.make(frames: 2, size: CGSize(width: 8, height: 8))
        big.append(Data(count: GIF.maxBytes))   // trailing bytes after the GIF's end still count
        XCTAssertThrowsError(try GIF.attachment(big)) { XCTAssertEqual($0 as? GIF.Problem, .tooBig) }
    }

    func testAFileNamedGifThatIsNotAGIFIsNotTreatedAsOne() {
        let png = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }.pngData() ?? Data()
        XCTAssertFalse(GIF.isGIF(png))
        XCTAssertThrowsError(try GIF.attachment(png)) { XCTAssertEqual($0 as? GIF.Problem, .notAGIF) }
    }

    func testAGIFFileIsStillAGIFThroughTheFilesPathAndAJPEGIsStillAJPEG() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gif206-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let gif = GIFFixtures.make(frames: 3, size: CGSize(width: 32, height: 32))
        let gifURL = dir.appendingPathComponent("wave.gif")
        try gif.write(to: gifURL)
        let sent = try AttachmentProcessing.file(at: gifURL)
        XCTAssertEqual(sent.mime, "image/gif"); XCTAssertEqual(sent.bytes, gif)
        let jpeg = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { c in UIColor.red.setFill(); c.fill(CGRect(x: 0, y: 0, width: 40, height: 40)) }.jpegData(compressionQuality: 0.9)!
        let jpegURL = dir.appendingPathComponent("photo.jpg")
        try jpeg.write(to: jpegURL)
        XCTAssertEqual(try AttachmentProcessing.file(at: jpegURL).mime, "image/jpeg")
        // Too big through the files path: its own refusal, not a silent still.
        let bigURL = dir.appendingPathComponent("huge.gif")
        try (GIFFixtures.make(frames: 2, size: CGSize(width: 8, height: 8)) + Data(count: GIF.maxBytes)).write(to: bigURL)
        XCTAssertThrowsError(try AttachmentProcessing.file(at: bigURL)) { XCTAssertEqual($0 as? AttachmentProcessing.Problem, .gifTooBig) }
    }

    func testFrameDelaysComeFromTheFileAndATinyOneBecomesAHundredthMilliseconds() throws {
        let slow = GIFFixtures.make(frames: 2, size: CGSize(width: 8, height: 8), delay: 0.4)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(slow as CFData, nil))
        XCTAssertEqual(GIF.delays(source), [0.4, 0.4])
        let instant = GIFFixtures.make(frames: 2, size: CGSize(width: 8, height: 8), delay: 0)
        let instantSource = try XCTUnwrap(CGImageSourceCreateWithData(instant as CFData, nil))
        XCTAssertEqual(GIF.delays(instantSource), [0.1, 0.1], "browsers treat 0 as 100 ms")
    }
}
