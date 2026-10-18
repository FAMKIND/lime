import XCTest
@testable import Lime

/// LIME-152c: a video's sharp cover frame.
@MainActor
final class PosterTests: XCTestCase {
    private func sample(_ width: CGFloat, _ height: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { context in
            for y in stride(from: 0, to: Int(height), by: 8) {
                for x in stride(from: 0, to: Int(width), by: 8) {
                    UIColor(hue: CGFloat((x * 7 + y * 3) % 360) / 360, saturation: 0.7, brightness: 0.9, alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: 8, height: 8))
                }
            }
        }
    }

    func testAPosterIsAboutFourEightyPixelsAndWithinItsSizeBound() throws {
        let data = AttachmentProcessing.poster(sample(1920, 1080))
        XCTAssertFalse(data.isEmpty)
        XCTAssertLessThanOrEqual(data.count, AttachmentProcessing.maxPosterBytes, "within the bound the message budget allows")
        let image = try XCTUnwrap(UIImage(data: data))
        let longSide = max(image.size.width, image.size.height) * image.scale
        XCTAssertLessThanOrEqual(longSide, 480)
        XCTAssertGreaterThanOrEqual(longSide, 240, "sharp enough to be a cover, not a blur")
        XCTAssertGreaterThan(data.count, AttachmentProcessing.thumbnail(sample(1920, 1080)).count * 5, "much more than the 2 KB blur")
    }

    func testTheCoverIsTheFileThenTheVideosPosterThenTheThumbnail() {
        typealias C = AttachmentCover
        XCTAssertEqual(C.pick(kind: .image, hasFull: true, hasPoster: false, hasThumb: true), .full)
        XCTAssertEqual(C.pick(kind: .video, hasFull: false, hasPoster: true, hasThumb: true), .poster)
        XCTAssertEqual(C.pick(kind: .video, hasFull: false, hasPoster: false, hasThumb: true), .thumb, "an older video keeps the blur")
        XCTAssertEqual(C.pick(kind: .image, hasFull: false, hasPoster: true, hasThumb: true), .thumb, "a photo has no poster")
        XCTAssertEqual(C.pick(kind: .file, hasFull: false, hasPoster: false, hasThumb: false), .none)
    }

    func testAnOlderMessageWithoutAPosterStillHasItsThumbnail() {
        let item = AttachmentItem(id: "v", mime: "video/mp4", name: "Video.mp4", size: 1000, thumb: Data([1, 2, 3]))
        XCTAssertTrue(item.poster.isEmpty)
        XCTAssertEqual(item.thumb, Data([1, 2, 3]))
    }
}
