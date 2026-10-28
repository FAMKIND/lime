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

    /// How strong the one overlay is at `y` points from the top of the photo: 40 % of `strength` at the very top (under the time), all of it from 18 % of the
    /// screen's height down.
    static func overlay(at y: CGFloat, screen: CGFloat, strength: Double) -> Double { strength * (0.4 + 0.6 * HeroShape.smooth(Double(y / max(screen * 0.18, 1)))) }

    /// The colour of the gradients: `sampled` (a dark colour from the photo), darkened until it is dark enough to keep white text readable.
    static func tint(from sampled: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        sampled.getRed(&r, green: &g, blue: &b, alpha: &a)
        var rgb = (Double(r), Double(g), Double(b))
        for _ in 0..<40 where luminance(rgb) > maxTintLuminance { rgb = (rgb.0 * 0.85, rgb.1 * 0.85, rgb.2 * 0.85) }
        return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }

    /// The overlay for a **default** hero (LIME-238): only as strong as white text needs for 4.5:1 over the picture's brightest part (where the name sits is
    /// the lower part), never more than `cap`, so a soft blurred photo or tone gradient keeps its colours instead of reading flat grey.
    static func defaultStrength(image: UIImage, key: String, cap: Double, tint: UIColor) -> Double {
        let brightest = HeroPalette.brightColor(of: image, key: key)
        var s = 0.2
        while s < cap {
            if contrast(text: .white, tint: tint, image: brightest, scrim: s) >= 4.6 { return s }
            s += 0.02
        }
        return cap
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
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIColor>()

    /// `key` names the picture (a person and a version), so it is not re-encoded to find it again.
    static func darkColor(of image: UIImage, key: String) -> UIColor {
        let id = key as NSString
        if let hit = cache.object(forKey: id) { return hit }
        let result = compute(image)
        cache.setObject(result, forKey: id)
        return result
    }

    nonisolated(unsafe) private static let brightCache = NSCache<NSString, UIColor>()

    /// The bright end of a picture's lower 70 % (where the name and the tabs sit): the mean of its brightest 15 % of pixels on a tiny copy.
    static func brightColor(of image: UIImage, key: String) -> UIColor {
        let id = key as NSString
        if let hit = brightCache.object(forKey: id) { return hit }
        let side = 16
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in image.draw(in: CGRect(x: 0, y: 0, width: side, height: side)) }
        var result = UIColor.white
        if let cg = small.cgImage, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) {
            let stride = cg.bytesPerRow, bpp = cg.bitsPerPixel / 8
            var pixels: [(Double, Double, Double)] = []
            for y in Int(Double(side) * 0.3)..<side { for x in 0..<side {
                let o = y * stride + x * bpp
                pixels.append((Double(bytes[o]) / 255, Double(bytes[o + 1]) / 255, Double(bytes[o + 2]) / 255))
            } }
            let top = pixels.sorted { HeroScrim.luminance($0) > HeroScrim.luminance($1) }.prefix(max(1, pixels.count * 15 / 100))
            let n = Double(top.count)
            result = UIColor(red: top.map(\.0).reduce(0, +) / n, green: top.map(\.1).reduce(0, +) / n, blue: top.map(\.2).reduce(0, +) / n, alpha: 1)
        }
        brightCache.setObject(result, forKey: id)
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

/// The hero's proportions, as a share of the screen's height (LIME-217c, from the user's mockups): the photo reaches the pills' centre at 58 %, the avatar is
/// centred at 29 %, and the bottom blend runs from 44 % to 64 % (about 20 %, 160 pt on a 812 pt screen).
enum HeroShape {
    static let pillsCentre = 0.58
    /// The pills sit this far higher, on the photo's lower fade, with the photo faintly showing through their glass (LIME-229).
    static let pillsLift: CGFloat = 28
    static let avatarCentre = 0.29
    static let blendStart = 0.44
    static let blendEnd = 0.64
    static let topEnd = 0.25
    /// The height of the tab pills row; the pills' centre is half of it above the row's bottom.
    static let pillsRow: CGFloat = 52
    /// How long the blend into the canvas is: about a fifth of the screen, never less than 140 pt.
    static func blendLength(screen: CGFloat) -> CGFloat { max(0.20 * screen, 140) }

    /// The photo's height from the top of the screen: the pills' row bottom plus a little under it, at least to where the blend ends.
    static func heroHeight(screen: CGFloat) -> CGFloat { max(screen * pillsCentre + pillsRow / 2 + 8, screen * blendEnd) }

    /// How tall the profile's top block (under the header) must be so the pills' centre sits at 58 %.
    static func blockHeight(screen: CGFloat, inset: CGFloat) -> CGFloat { max(0, screen * pillsCentre - pillsLift + pillsRow / 2 - inset) }

    /// Space above the avatar so its centre sits at 29 % (never less than the usual 12 pt).
    static func avatarTopPadding(screen: CGFloat, inset: CGFloat, avatar: CGFloat) -> CGFloat { max(12, screen * avatarCentre - avatar / 2 - inset) }

    /// The least space between the bottom of the name block and the pills' row, so the blend (about a fifth of the screen, ending just under the pills) has
    /// barely begun where the text ends: 80 % of its length less the row and the little under it.
    static func textToPills(screen: CGFloat) -> CGFloat { max(18, 0.8 * blendLength(screen: screen) - pillsRow - 4) }

    /// Smoothstep: 0 to 1 with no kink at either end, so a gradient built on it has no visible start or end.
    static func smooth(_ t: Double) -> Double { let x = min(max(t, 0), 1); return x * x * (3 - 2 * x) }

    /// The shape of this phone's hero, width : height of the area the photo fills (for the editor's preview).
    static func aspect(screenWidth: CGFloat, screenHeight: CGFloat) -> CGFloat { screenWidth / heroHeight(screen: screenHeight) }
}

/// The picture behind a profile's top (decorative: hidden from VoiceOver). It fills its frame from the top edge, aspect-filled around the picture's centre and
/// not blurred, under soft eased gradients: a faint long one at the top, a local one behind the name block, and the blend (photo, a little of its dark colour,
/// the canvas) that the pills sit on.
struct ProfileHeroBackground: View {
    let image: UIImage
    /// Names this picture (for the colour sampled from it, worked out once).
    let cacheKey: String
    /// The default (no background chosen or visible) is a blurred photo or a tone: decorative everywhere, also in tests.
    var isDefault = false
    /// The screen's height, which every proportion is a share of.
    var screenHeight: CGFloat = UIScreen.main.bounds.height
    /// A background video (LIME-226b): the still is its poster, shown first and whenever the video is not playing.
    var videoURL: URL? = nil
    var playVideo = false
    /// Told when the clip is actually showing (ready) or not.
    var onVideoReady: (Bool) -> Void = { _ in }
    /// Demo runs (UI tests) expose it so a test can find it; for a person it is decorative and hidden from VoiceOver.
    var exposedForTests = false
    @State private var videoReady = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let cap = HeroScrim.opacity(reduceTransparency: reduceTransparency, increaseContrast: contrast == .increased)
        let tintColour = HeroScrim.tint(from: HeroPalette.darkColor(of: image, key: cacheKey))
        // A default (blurred photo, tone gradient) gets only the overlay its text needs, so its colours show; a chosen background keeps the full one.
        let strength = isDefault ? HeroScrim.defaultStrength(image: image, key: cacheKey, cap: cap, tint: tintColour) : cap
        let tint = Color(uiColor: tintColour)
        GeometryReader { geo in layers(size: geo.size, strength: strength, tint: tint) }
        .onChange(of: playVideo) { _, playing in if !playing { videoReady = false } }
        .onChange(of: videoReady) { _, now in onVideoReady(now) }
        .clipped()
        .accessibilityHidden(true)
        // Demo runs (UI tests) get a marker of exactly the photo's box (a picture that fills would report its own, larger, frame); a person gets nothing.
        .overlay { if exposedForTests { Color.clear.accessibilityIdentifier(isDefault ? "profile-hero-default" : "profile-hero-background") } }
    }
}

extension ProfileHeroBackground {
    /// Gradient stops sampled along an eased curve between two heights (in points from the top), as `opacity(y)` of `colour`.
    private func eased(_ colour: Color, size h: CGFloat, from y0: CGFloat, to y1: CGFloat, steps: Int = 7, opacity: (Double) -> Double) -> [Gradient.Stop] {
        (0...steps).map { i in
            let t = Double(i) / Double(steps)
            let y = y0 + (y1 - y0) * CGFloat(t)
            return .init(color: colour.opacity(opacity(t)), location: min(max(y / h, 0), 1))
        }
    }

    /// One overlay over the whole photo (LIME-217e): the photo's dark colour at `strength`, a little lighter only at the very top (under the time and the
    /// circles), so light photos come out evenly dimmed and dark ones barely change, with no band and no edge; then, in the last stretch above the pills, the
    /// blend into the canvas. The blend is measured from the bottom of the photo, which is always below the text and the pills.
    @ViewBuilder
    func layers(size: CGSize, strength: Double, tint: Color) -> some View {
        let h = max(size.height, 1), s = screenHeight
        let canvas = Theme.canvas
        let blend = HeroShape.blendLength(screen: s)
        let end = h - 4, start = max(0, end - blend)
        ZStack {
            Image(uiImage: image).resizable().scaledToFill().frame(width: size.width, height: h).clipped()
            // The clip, silent, looping, over its still once it is ready to show (only while allowed to play: otherwise the still stays).
            if let videoURL, playVideo {
                HeroVideoView(url: videoURL, playing: true, onReady: { withAnimation(.easeIn(duration: 0.3)) { videoReady = true } })
                    .frame(width: size.width, height: h).clipped()
                    .opacity(videoReady ? 1 : 0)
            }
            // The one overlay: 40 % of its strength at the very top, eased to all of it by 18 % of the screen, then the same all the way down.
            LinearGradient(stops: eased(tint, size: h, from: 0, to: s * 0.18) { strength * (0.4 + 0.6 * HeroShape.smooth($0)) } + [.init(color: tint.opacity(strength), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            // The blend: a little more of the dark colour that comes and goes, under the canvas coming in; the pills sit on its lower half.
            LinearGradient(stops: eased(tint, size: h, from: start, to: end, steps: 9) { 0.35 * sin(Double.pi * $0) }, startPoint: .top, endPoint: .bottom)
            LinearGradient(stops: eased(canvas, size: h, from: start, to: end, steps: 9) { HeroShape.smooth($0) } + [.init(color: canvas, location: 1)], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// What the hero shows when a person has no background, or one you cannot see (LIME-217d): their profile photo scaled to fill and heavily blurred and a
/// little dimmed; with no photo, a soft gradient of their avatar's tone colour to a darker shade. Both are decorative and made small (they are blurred).
enum HeroDefault {
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()
    private static let size = CGSize(width: 270, height: 338)   // 4:5

    /// The picture and the string that names it (for caching the colour sampled from it).
    static func image(for person: Person, photo: UIImage?, dark: Bool) -> (image: UIImage, key: String) {
        let key = photo.map { "photo-\(person.id)-\(ObjectIdentifier($0).hashValue)" } ?? "tone-\(((person.tone % 8) + 8) % 8)-\(dark)"
        if let hit = cache.object(forKey: key as NSString) { return (hit, key) }
        let made = photo.map(blurred) ?? tone(person.tone, dark: dark)
        cache.setObject(made, forKey: key as NSString)
        return (made, key)
    }

    /// An org with no picture of its own: its tile's colour (the accent) as a soft gradient to a darker shade, like a person's tone (LIME-216).
    static func org(dark: Bool) -> (image: UIImage, key: String) {
        let key = "org-tile-\(dark)"
        if let hit = cache.object(forKey: key as NSString) { return (hit, key) }
        let base = UIColor(Theme.accent).resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        let made = gradient(from: base)
        cache.setObject(made, forKey: key as NSString)
        return (made, key)
    }

    /// The photo, aspect-filled into the frame, blurred (radius about 40 at the real size: here a fifth of it, as this copy is a fifth the size) and dimmed.
    static func blurred(_ photo: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let filled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let cover = max(size.width / photo.size.width, size.height / photo.size.height)
            let drawn = CGSize(width: photo.size.width * cover, height: photo.size.height * cover)
            photo.draw(in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2, width: drawn.width, height: drawn.height))
        }
        guard let input = CIImage(image: filled), let blur = CIFilter(name: "CIGaussianBlur") else { return filled }
        blur.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        blur.setValue(16, forKey: kCIInputRadiusKey)
        guard let output = blur.outputImage?.cropped(to: input.extent), let cg = CIContext().createCGImage(output, from: input.extent) else { return filled }
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIImage(cgImage: cg).draw(in: CGRect(origin: .zero, size: size))
            // A soft tint from the photo's own colours (its dominant dark colour) instead of a grey dimming.
            HeroPalette.compute(filled).withAlphaComponent(0.22).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// A soft vertical gradient of the avatar's tone colour (the one behind their initials) to a darker shade of it.
    static func tone(_ tone: Int, dark: Bool) -> UIImage {
        gradient(from: UIColor(Theme.avatar(tone)).resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light)))
    }

    private static func gradient(from base: UIColor) -> UIImage {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getRed(&r, green: &g, blue: &b, alpha: &a)
        let deeper = UIColor(red: r * 0.55, green: g * 0.55, blue: b * 0.55, alpha: 1)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colours = [base.cgColor, deeper.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width * 0.3, y: size.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }
}

/// The lime logomark's outline as the avatar's shape on a profile hero (the user's artwork, in the asset catalog as a vector). The picture is the same square
/// picture every other avatar uses, at its normal size and centre, filling the shape's bounding box; the outline only trims its edges (and gives it its tail).
struct LimeShapedAvatar: View {
    let person: Person
    var size: CGFloat = 96

    var body: some View {
        Group {
            if let photo = AvatarCache.shared.image(for: person.id) {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                Theme.avatar(person.tone).overlay(
                    Text(person.initials).font(.system(size: size * 0.36, weight: .medium)).minimumScaleFactor(0.6)
                        .foregroundStyle(Color(red: 0.075, green: 0.106, blue: 0.09)))
            }
        }
        .frame(width: size, height: size).clipped()
        .mask { Image("LimeMask").resizable().scaledToFit().frame(width: size, height: size) }
        .accessibilityHidden(true)
    }
}

/// Make a background from a picture (LIME-217c): a **4:5 portrait** frame the person moves and scales to fit, saved about 1080 × 1350, at most 1 MiB, no
/// metadata. Every phone fills its hero from this around the centre, so a shorter hero trims only a little of the top and bottom.
enum BackgroundProcessing {
    /// Width over height.
    static let ratio: CGFloat = 0.8
    static let width: CGFloat = 1080
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
