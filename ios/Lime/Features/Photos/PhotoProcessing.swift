import ImageIO
import SwiftUI
import UIKit

/// Everyone's profile photos for display, by user id. Filled from LimeCore's encrypted cache; a person with no photo
/// (or one you may not see) is simply absent, and their initials show instead.
@MainActor
@Observable
final class AvatarCache {
    static let shared = AvatarCache()
    private(set) var images: [String: UIImage] = [:]
    /// Ids already looked up (with or without a photo), so each is read from the store once.
    private(set) var known: Set<String> = []

    func image(for id: String) -> UIImage? { images[id] }

    func set(_ data: Data?, for id: String) {
        known.insert(id)
        if let data, let image = UIImage(data: data) { images[id] = image } else { images[id] = nil }
    }

    func reset() { images = [:]; known = [] }
}

/// Turns a picked picture into the profile photo that is stored and uploaded: a 512 px square JPEG, redrawn from
/// the pixels alone, so no EXIF, GPS or other metadata survives.
enum PhotoProcessing {
    static let side: CGFloat = 512
    static let maxBytes = 1_000_000

    /// The part of `image` inside a square viewport of `viewport` points, where the picture is drawn to cover the viewport at
    /// `scale` (1 = just covering) and shifted by `offset` points from centred.
    static func crop(_ image: UIImage, viewport: CGFloat, scale: CGFloat, offset: CGSize) -> UIImage {
        let size = image.size
        let cover = max(viewport / size.width, viewport / size.height) * max(scale, 1)
        let drawn = CGSize(width: size.width * cover, height: size.height * cover)
        let factor = side / viewport
        let origin = CGPoint(x: (viewport - drawn.width) / 2 + offset.width, y: (viewport - drawn.height) / 2 + offset.height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: side, height: side)))
            // `draw(in:)` honours the picture's orientation, so a sideways phone photo is drawn upright.
            image.draw(in: CGRect(x: origin.x * factor, y: origin.y * factor, width: drawn.width * factor, height: drawn.height * factor))
        }
    }

    /// JPEG bytes, small enough to upload (quality is lowered until it fits).
    static func jpeg(_ image: UIImage) -> Data? {
        for quality in [0.85, 0.7, 0.5, 0.3] as [CGFloat] {
            if let data = image.jpegData(compressionQuality: quality), data.count <= maxBytes { return data }
        }
        return nil
    }

    /// The most that can be shifted before the picture would leave the viewport's edge.
    static func limit(imageSize: CGSize, viewport: CGFloat, scale: CGFloat) -> CGSize {
        let cover = max(viewport / imageSize.width, viewport / imageSize.height) * max(scale, 1)
        return CGSize(width: max(0, (imageSize.width * cover - viewport) / 2), height: max(0, (imageSize.height * cover - viewport) / 2))
    }

    /// Metadata dictionaries found in encoded image data (for tests: a processed photo has none of the personal kinds).
    static func personalMetadata(in data: Data) -> [String] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return [] }
        var found: [String] = []
        if properties[kCGImagePropertyGPSDictionary] != nil { found.append("GPS") }
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            for key in [kCGImagePropertyExifDateTimeOriginal, kCGImagePropertyExifUserComment, kCGImagePropertyExifLensModel, kCGImagePropertyExifBodySerialNumber] where exif[key] != nil {
                found.append("Exif \(key)")
            }
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            for key in [kCGImagePropertyTIFFMake, kCGImagePropertyTIFFModel, kCGImagePropertyTIFFDateTime, kCGImagePropertyTIFFSoftware] where tiff[key] != nil {
                found.append("TIFF \(key)")
            }
        }
        return found
    }
}
