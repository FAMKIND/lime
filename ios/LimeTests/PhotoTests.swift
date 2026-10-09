import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Lime

/// Profile photos: the crop, the 512 px JPEG, metadata stripped, and the demo store.
@MainActor
final class PhotoTests: XCTestCase {
    /// A JPEG that carries a GPS position, a camera and a date, as a phone photo does.
    private func photoWithMetadata() throws -> Data {
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        }
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.77, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 122.41, kCGImagePropertyGPSLongitudeRef: "W"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:08 10:00:00", kCGImagePropertyExifUserComment: "private note"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone"],
        ]
        CGImageDestinationAddImage(destination, try XCTUnwrap(picture.cgImage), properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testTheTestPhotoReallyCarriesPersonalMetadata() throws {
        let found = PhotoProcessing.personalMetadata(in: try photoWithMetadata())
        XCTAssertTrue(found.contains("GPS"), "\(found)")
        XCTAssertTrue(found.count >= 3, "\(found)")
    }

    func testAProcessedPhotoIs512SquareSmallAndHasNoMetadata() throws {
        let original = try XCTUnwrap(UIImage(data: try photoWithMetadata()))
        let cropped = PhotoProcessing.crop(original, viewport: 300, scale: 1, offset: .zero)
        XCTAssertEqual(cropped.size.width * cropped.scale, 512)
        XCTAssertEqual(cropped.size.height * cropped.scale, 512)
        let jpeg = try XCTUnwrap(PhotoProcessing.jpeg(cropped))
        XCTAssertLessThan(jpeg.count, PhotoProcessing.maxBytes)
        XCTAssertEqual(PhotoProcessing.personalMetadata(in: jpeg), [], "no GPS, camera, date or comment survives")
        let decoded = try XCTUnwrap(UIImage(data: jpeg))
        XCTAssertEqual(decoded.size.width * decoded.scale, 512)
    }

    func testTheCropFollowsTheZoomAndTheOffset() throws {
        // A picture that is red on the left half and blue on the right half.
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 200, height: 400))
            UIColor.blue.setFill(); context.fill(CGRect(x: 200, y: 0, width: 200, height: 400))
        }
        func colour(_ image: UIImage, x: Int) throws -> (r: CGFloat, b: CGFloat) {
            let cg = try XCTUnwrap(image.cgImage)
            let data = try XCTUnwrap(cg.dataProvider?.data)
            let bytes = CFDataGetBytePtr(data)!
            let offset = (cg.height / 2) * cg.bytesPerRow + x * (cg.bitsPerPixel / 8)
            // Little-endian 32-bit pixels are stored B, G, R, A; big-endian ones R, G, B, A.
            let little = cg.bitmapInfo.contains(.byteOrder32Little)
            return little ? (CGFloat(bytes[offset + 2]), CGFloat(bytes[offset])) : (CGFloat(bytes[offset]), CGFloat(bytes[offset + 2]))
        }
        // Whole picture: left red, right blue.
        let whole = PhotoProcessing.crop(picture, viewport: 200, scale: 1, offset: .zero)
        XCTAssertGreaterThan(try colour(whole, x: 20).r, 200)
        XCTAssertGreaterThan(try colour(whole, x: 490).b, 200)
        // Zoomed to 2x and pushed so the right half fills the viewport: all blue.
        let zoomed = PhotoProcessing.crop(picture, viewport: 200, scale: 2, offset: CGSize(width: -100, height: 0))
        XCTAssertGreaterThan(try colour(zoomed, x: 20).b, 200)
        XCTAssertGreaterThan(try colour(zoomed, x: 490).b, 200)
        // The limit keeps the picture covering the viewport.
        XCTAssertEqual(PhotoProcessing.limit(imageSize: CGSize(width: 400, height: 400), viewport: 200, scale: 1), .zero)
        XCTAssertEqual(PhotoProcessing.limit(imageSize: CGSize(width: 400, height: 400), viewport: 200, scale: 2).width, 100)
    }

    func testTheDemoStoreKeepsMyPhotoAndShowsItAsMyAvatar() async throws {
        AvatarCache.shared.reset()
        let store = ConversationStore()
        store.loadDemo(screen: "settings/profile")
        let jpeg = try XCTUnwrap(PhotoProcessing.jpeg(PhotoProcessing.crop(try XCTUnwrap(UIImage(data: try photoWithMetadata())), viewport: 300, scale: 1, offset: .zero)))
        let me = store.meProvider().id
        XCTAssertNil(AvatarCache.shared.image(for: me))
        let saved = await store.setMyPhoto(jpeg)
        XCTAssertTrue(saved)
        XCTAssertNotNil(AvatarCache.shared.image(for: me))
        let visible = await store.setPhotoVisibility(.contacts)
        XCTAssertTrue(visible)
        let mine = await store.myPhoto()
        XCTAssertEqual(mine.visibility, .contacts)
        XCTAssertEqual(mine.jpeg, jpeg)
        let removed = await store.removeMyPhoto()
        XCTAssertTrue(removed)
        XCTAssertNil(AvatarCache.shared.image(for: me))
        AvatarCache.shared.reset()
    }
}
