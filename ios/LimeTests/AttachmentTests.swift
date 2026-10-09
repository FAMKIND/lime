import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Lime

/// Attachments: what the app makes before sending (size limits, no metadata, a tiny preview), and how it describes them.
@MainActor
final class AttachmentTests: XCTestCase {
    private func bigPhotoWithMetadata(width: Int = 4000, height: Int = 3000) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let picture = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        }
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.77, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 122.41, kCGImagePropertyGPSLongitudeRef: "W"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:08 10:00:00"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "iPhone"],
        ]
        CGImageDestinationAddImage(destination, try XCTUnwrap(picture.cgImage), properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertFalse(PhotoProcessing.personalMetadata(in: data as Data).isEmpty, "the test picture really has metadata")
        return try XCTUnwrap(UIImage(data: data as Data))
    }

    func testAPhotoIsShrunkTo2048StrippedOfMetadataAndGetsATinyThumbnail() throws {
        let original = try bigPhotoWithMetadata()
        let made = try XCTUnwrap(AttachmentProcessing.photo(original))
        XCTAssertEqual(made.mime, "image/jpeg")
        XCTAssertEqual(max(made.width ?? 0, made.height ?? 0), 2048, "the long edge is 2048 px")
        XCTAssertEqual(made.width, 2048)
        XCTAssertEqual(made.height, 1536, "the proportions are kept")
        XCTAssertLessThan(made.bytes.count, 2_000_000)
        XCTAssertEqual(AttachmentProcessing.personalMetadata(in: made.bytes), [], "no GPS, camera or date is sent")
        XCTAssertFalse(made.thumb.isEmpty)
        XCTAssertLessThanOrEqual(made.thumb.count, AttachmentProcessing.maxThumbBytes, "the thumbnail fits inside the message")
        XCTAssertNotNil(UIImage(data: made.thumb))
        XCTAssertEqual(AttachmentProcessing.personalMetadata(in: made.thumb), [])
    }

    func testASmallPhotoIsNotEnlarged() throws {
        let made = try XCTUnwrap(AttachmentProcessing.photo(try bigPhotoWithMetadata(width: 600, height: 800)))
        XCTAssertEqual([made.width, made.height], [600, 800])
    }

    private func temporaryFile(_ name: String, bytes: Data) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try bytes.write(to: url)
        return url
    }

    func testAFileKeepsItsNameAndTypeAndOneOverFiftyMegabytesIsRefused() throws {
        let pdf = try temporaryFile("Permission slip.pdf", bytes: Data("%PDF-1.4 hello".utf8))
        let made = try AttachmentProcessing.file(at: pdf)
        XCTAssertEqual(made.name, "Permission slip.pdf")
        XCTAssertEqual(made.mime, "application/pdf")
        XCTAssertNil(made.width)

        let huge = try temporaryFile("movie.bin", bytes: Data(count: AttachmentProcessing.maxFileBytes + 1))
        XCTAssertThrowsError(try AttachmentProcessing.file(at: huge)) { XCTAssertEqual($0 as? AttachmentProcessing.Problem, .tooLarge) }
        let empty = try temporaryFile("empty.txt", bytes: Data())
        XCTAssertThrowsError(try AttachmentProcessing.file(at: empty)) { XCTAssertEqual($0 as? AttachmentProcessing.Problem, .unreadable) }
    }

    func testAPictureSentAsAFileIsStillSentAsAShrunkPhoto() throws {
        let jpeg = try XCTUnwrap(try bigPhotoWithMetadata().jpegData(compressionQuality: 0.9))
        let made = try AttachmentProcessing.file(at: try temporaryFile("Beach.jpg", bytes: jpeg))
        XCTAssertEqual(made.name, "Beach.jpg")
        XCTAssertEqual(made.mime, "image/jpeg")
        XCTAssertEqual(made.width, 2048)
        XCTAssertEqual(AttachmentProcessing.personalMetadata(in: made.bytes), [])
    }

    func testAttachmentsAreDescribedByKindAndSummarisedForTheList() {
        func item(_ mime: String, _ name: String = "x") -> AttachmentItem { AttachmentItem(id: UUID().uuidString, mime: mime, name: name, size: 1_250_000) }
        XCTAssertEqual(item("image/png").kind, .image)
        XCTAssertEqual(item("video/mp4").kind, .video)
        XCTAssertEqual(item("audio/aac").kind, .audio)
        XCTAssertEqual(item("application/pdf").kind, .file)
        XCTAssertEqual(AttachmentFormat.summary([item("image/jpeg")]), "Photo")
        XCTAssertEqual(AttachmentFormat.summary([item("image/jpeg"), item("image/jpeg"), item("image/jpeg")]), "3 Photos")
        XCTAssertEqual(AttachmentFormat.summary([item("application/pdf", "Permission slip.pdf")]), "Permission slip.pdf")
        XCTAssertEqual(AttachmentFormat.summary([item("video/mp4")]), "Video")
        XCTAssertEqual(AttachmentFormat.summary([item("audio/aac")]), "Voice message")
        XCTAssertEqual(AttachmentFormat.summary([AttachmentItem(id: "v", mime: "audio/mp4", name: "v", size: 1, durationMs: 12_000)]), "Voice message (0:12)")
        XCTAssertEqual(AttachmentFormat.summary([item("image/jpeg"), item("application/pdf")]), "2 attachments")
        XCTAssertNil(AttachmentFormat.summary([]))
        XCTAssertTrue(item("application/pdf", "a.pdf").detail.hasPrefix("PDF · "))
    }

    func testTheDemoStoreSendsAnAttachmentAndOpensItsBytes() async throws {
        let store = ConversationStore()
        store.loadDemo(screen: "attachments")
        let photo = try XCTUnwrap(AttachmentProcessing.photo(try bigPhotoWithMetadata(width: 800, height: 600)))
        await store.sendAttachmentsNow([photo], caption: "  look  ", in: "dm:att")
        let sent = try XCTUnwrap(store.conversation("dm:att")?.messages.last)
        XCTAssertEqual(sent.text, "look")
        XCTAssertEqual(sent.attachments.count, 1)
        let bytes = await store.attachmentData(sent.attachments[0])
        XCTAssertEqual(bytes, photo.bytes)
        let image = await store.image(for: sent.attachments[0])
        XCTAssertNotNil(image)
    }
}
