import SwiftUI
import UIKit

/// The profile hero when there is a background (LIME-217b): the photo full bleed from the very top, vivid, with a dark gradient behind the white name and
/// lines and a soft blend (photo, a dark colour from the photo, the canvas) so the tab pills sit on the canvas with no visible edge.
enum HeroScrim {
    /// How dark the gradient behind the text is: enough that white text keeps 4.5:1 over a pure white photo. Reduce Transparency and Increase Contrast use more.
    static func opacity(reduceTransparency: Bool, increaseContrast: Bool) -> Double {
        if increaseContrast { return 0.85 }
        return reduceTransparency ? 0.8 : 0.7
    }

    /// The darkest luminance the tint may have: the photo's own dark colour is used when it is at least this dark, else it is darkened to it.
    static let maxTintLuminance = 0.02

    /// The colour of the gradients: `sampled` (a dark colour from the photo), darkened until it is dark enough to keep white text readable.
    static func tint(from sampled: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        sampled.getRed(&r, green: &g, blue: &b, alpha: &a)
        var rgb = (Double(r), Double(g), Double(b))
        for _ in 0..<40 where luminance(rgb) > maxTintLuminance { rgb = (rgb.0 * 0.85, rgb.1 * 0.85, rgb.2 * 0.85) }
        return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }

    static func luminance(_ c: (Double, Double, Double)) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2)
    }

    /// The contrast ratio of `text` over `image` covered by `scrim` of `tint` (all as sRGB).
    static func contrast(text: UIColor, tint: UIColor, image: UIColor, scrim: Double) -> Double {
        func parts(_ color: UIColor) -> (Double, Double, Double) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return (Double(r), Double(g), Double(b))
        }
        let c = parts(tint), i = parts(image)
        let behind = (c.0 * scrim + i.0 * (1 - scrim), c.1 * scrim + i.1 * (1 - scrim), c.2 * scrim + i.2 * (1 - scrim))
        let a = luminance(parts(text)), b = luminance(behind)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// A dark colour from a photo (LIME-217b): its few dominant colours by a small k-means on a tiny copy, then the darkest that holds a fair share of the picture.
/// Worked out once per picture and kept.
enum HeroPalette {
    nonisolated(unsafe) private static let cache = NSCache<NSData, UIColor>()

    static func darkColor(of image: UIImage, key: Data? = nil) -> UIColor {
        let id = (key ?? image.pngData() ?? Data()) as NSData
        if let hit = cache.object(forKey: id) { return hit }
        let result = compute(image)
        cache.setObject(result, forKey: id)
        return result
    }

    static func compute(_ image: UIImage) -> UIColor {
        let side = 16
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in image.draw(in: CGRect(x: 0, y: 0, width: side, height: side)) }
        guard let cg = small.cgImage, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return .black }
        let stride = cg.bytesPerRow, bpp = cg.bitsPerPixel / 8
        var pixels: [(Double, Double, Double)] = []
        for y in 0..<side { for x in 0..<side {
            let o = y * stride + x * bpp
            pixels.append((Double(bytes[o]) / 255, Double(bytes[o + 1]) / 255, Double(bytes[o + 2]) / 255))
        } }
        // k-means, k = 4, seeded from the pixels spread by brightness.
        let sorted = pixels.sorted { HeroScrim.luminance($0) < HeroScrim.luminance($1) }
        var centres = (0..<4).map { sorted[min(sorted.count - 1, ($0 * 2 + 1) * sorted.count / 8)] }
        var members = [Int](repeating: 0, count: pixels.count)
        for _ in 0..<6 {
            for (i, p) in pixels.enumerated() {
                members[i] = centres.indices.min { dist(p, centres[$0]) < dist(p, centres[$1]) } ?? 0
            }
            for k in centres.indices {
                let mine = pixels.enumerated().filter { members[$0.offset] == k }.map(\.element)
                guard !mine.isEmpty else { continue }
                centres[k] = (mine.map(\.0).reduce(0, +) / Double(mine.count), mine.map(\.1).reduce(0, +) / Double(mine.count), mine.map(\.2).reduce(0, +) / Double(mine.count))
            }
        }
        let share = (0..<4).map { k in members.filter { $0 == k }.count }
        // The darkest centre that covers at least 8 % of the copy (a speck of black is not the picture's dark).
        let candidates = centres.indices.filter { share[$0] * 100 >= pixels.count * 8 }
        let pick = candidates.min { HeroScrim.luminance(centres[$0]) < HeroScrim.luminance(centres[$1]) } ?? 0
        return UIColor(red: centres[pick].0, green: centres[pick].1, blue: centres[pick].2, alpha: 1)
    }

    private static func dist(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        (a.0 - b.0) * (a.0 - b.0) + (a.1 - b.1) * (a.1 - b.1) + (a.2 - b.2) * (a.2 - b.2)
    }
}

/// The picture behind a profile's top (decorative: hidden from VoiceOver). It fills its frame from the top edge, not blurred. `fadeFromBottom` is where the tab
/// pills start: the gradients bring the picture to the canvas by then.
struct ProfileHeroBackground: View {
    let image: UIImage
    /// The dark gradient holds until this far above the bottom (just above the pills, so the status line is still on it); the photo is on the canvas by `canvasFromBottom`.
    var darkUntil: CGFloat = 135
    var canvasFromBottom: CGFloat = 85
    /// The height of the text block (name, handle, school, pill, status) the dark gradient sits behind.
    var textZone: CGFloat = 170
    /// Demo runs (UI tests) expose it so a test can find it; for a person it is decorative and hidden from VoiceOver.
    var exposedForTests = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let strength = HeroScrim.opacity(reduceTransparency: reduceTransparency, increaseContrast: contrast == .increased)
        let tint = Color(uiColor: HeroScrim.tint(from: HeroPalette.darkColor(of: image)))
        GeometryReader { geo in layers(size: geo.size, strength: strength, tint: tint) }
        .clipped()
        .accessibilityHidden(!exposedForTests)
        .accessibilityIdentifier("profile-hero-background")
    }
}

extension ProfileHeroBackground {
    @ViewBuilder
    func layers(size: CGSize, strength: Double, tint: Color) -> some View {
        let h = max(size.height, 1)
        let at = { (fromBottom: CGFloat) -> CGFloat in min(max((h - fromBottom) / h, 0), 1) }
        ZStack {
            Image(uiImage: image).resizable().scaledToFill().frame(width: size.width, height: h).clipped()
            // Under the status bar and the header buttons.
            LinearGradient(stops: [.init(color: tint.opacity(0.6), location: 0), .init(color: tint.opacity(0), location: min(0.3, 150 / h))], startPoint: .top, endPoint: .bottom)
            // Behind the white text, then the blend: the photo, its dark colour, the canvas, done where the pills start.
            LinearGradient(stops: [
                .init(color: tint.opacity(0), location: at(darkUntil + textZone + 70)),
                .init(color: tint.opacity(strength), location: at(darkUntil + textZone)),
                .init(color: tint.opacity(strength), location: at(darkUntil)),
                .init(color: tint.opacity(min(strength + 0.1, 0.95)), location: at((darkUntil + canvasFromBottom) / 2 + 10)),
                .init(color: Theme.canvas, location: at(canvasFromBottom)),
                .init(color: Theme.canvas, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// The lime logomark's outline as the avatar's shape on a profile hero (the user's artwork, in the asset catalog as a vector).
struct LimeShapedAvatar: View {
    let person: Person
    var size: CGFloat = 96

    var body: some View {
        // The picture is drawn a good deal larger than the shape so it fills it right into the tail, then cut to the outline.
        AvatarView(person: person, size: size * 1.5)
            .frame(width: size, height: size)
            .mask { Image("LimeMask").resizable().scaledToFit().frame(width: size, height: size) }
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }
}

/// Make a background from a picture: a wide frame (about 3 to 1) the person moves and scales to fit, at most 1 MiB, no metadata.
enum BackgroundProcessing {
    static let ratio: CGFloat = 3
    static let width: CGFloat = 1200
    static let maxBytes = 1_000_000

    /// The part of `image` inside a viewport of `viewport` points wide (and a third as tall), drawn to cover it at `scale` and shifted by `offset`.
    static func crop(_ image: UIImage, viewport: CGSize, scale: CGFloat, offset: CGSize) -> UIImage {
        let size = image.size
        let cover = max(viewport.width / size.width, viewport.height / size.height) * max(scale, 1)
        let drawn = CGSize(width: size.width * cover, height: size.height * cover)
        let factor = width / viewport.width
        let out = CGSize(width: width, height: (width / ratio).rounded())
        let origin = CGPoint(x: (viewport.width - drawn.width) / 2 + offset.width, y: (viewport.height - drawn.height) / 2 + offset.height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: out, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: out))
            image.draw(in: CGRect(x: origin.x * factor, y: origin.y * factor, width: drawn.width * factor, height: drawn.height * factor))
        }
    }

    /// JPEG bytes small enough to upload (a re-encoded picture carries none of its original metadata).
    static func jpeg(_ image: UIImage) -> Data? {
        for quality in [0.8, 0.65, 0.5, 0.35] as [CGFloat] {
            if let data = image.jpegData(compressionQuality: quality), data.count <= maxBytes { return data }
        }
        return nil
    }

    /// The most the picture can shift before it would leave the viewport's edge.
    static func limit(imageSize: CGSize, viewport: CGSize, scale: CGFloat) -> CGSize {
        let cover = max(viewport.width / imageSize.width, viewport.height / imageSize.height) * max(scale, 1)
        return CGSize(width: max(0, (imageSize.width * cover - viewport.width) / 2), height: max(0, (imageSize.height * cover - viewport.height) / 2))
    }
}
