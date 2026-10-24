import SwiftUI
import UIKit

/// The profile's background image (LIME-217): behind the avatar, name and lines, softly blurred, under a scrim that fades into the canvas at the bottom so the
/// lines keep their contrast and the glass pills sit on today's clean background.
enum HeroScrim {
    /// How much of the canvas colour covers the picture where the text is. High enough that the secondary text keeps 4.5:1 on a pure white or black image.
    static func opacity(reduceTransparency: Bool, increaseContrast: Bool) -> Double {
        if increaseContrast { return 0.96 }
        return reduceTransparency ? 0.95 : 0.9
    }

    /// The scrim as a gradient from the top to the canvas at the bottom (the text sits in the first 60 %).
    static func stops(opacity: Double) -> [Gradient.Stop] {
        [.init(color: Theme.canvas.opacity(opacity), location: 0), .init(color: Theme.canvas.opacity(opacity), location: 0.6), .init(color: Theme.canvas.opacity(0), location: 1)]
    }

    /// The contrast ratio of `text` over `image` covered by `scrim` of `canvas` (all as sRGB).
    static func contrast(text: UIColor, canvas: UIColor, image: UIColor, scrim: Double) -> Double {
        func parts(_ color: UIColor) -> (Double, Double, Double) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return (Double(r), Double(g), Double(b))
        }
        func luminance(_ c: (Double, Double, Double)) -> Double {
            func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2)
        }
        let c = parts(canvas), i = parts(image)
        let behind = (c.0 * scrim + i.0 * (1 - scrim), c.1 * scrim + i.1 * (1 - scrim), c.2 * scrim + i.2 * (1 - scrim))
        let a = luminance(parts(text)), b = luminance(behind)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// The picture behind a profile's top (decorative: hidden from VoiceOver). Reduce Transparency: no blur and a more solid scrim. Increase Contrast: a stronger scrim.
struct ProfileHeroBackground: View {
    let image: UIImage
    /// Demo runs (UI tests) expose it so a test can find it; for a person it is decorative and hidden from VoiceOver.
    var exposedForTests = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let scrim = HeroScrim.opacity(reduceTransparency: reduceTransparency, increaseContrast: contrast == .increased)
        Color.clear
            .overlay {
                Image(uiImage: image).resizable().scaledToFill()
                    .blur(radius: reduceTransparency ? 0 : 10)
            }
            .overlay { LinearGradient(stops: HeroScrim.stops(opacity: scrim), startPoint: .top, endPoint: .bottom) }
            .clipped()
            .accessibilityHidden(!exposedForTests)
            .accessibilityIdentifier("profile-hero-background")
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
