import SwiftUI
import UIKit

/// LIME-261: the default hero, made vibrant and alive (as Apple Music's and Podcasts' Now Playing): a palette of 4 to 6 colours from the person's photo, or from their
/// avatar's colour when they have none, a slowly drifting `MeshGradient`, and a canvas tinted with a hint of the palette for the page below. A chosen cover still wins.
///
/// **One switch:** `Hero.style`. `.ambient` is this; `.classic` is the earlier look (the blurred photo or a tone gradient, fading into the plain canvas). Launch with
/// `-lime-hero-classic` to see the old one. To go back for good, change the default below to `.classic`.
enum Hero {
    enum Style { case ambient, classic }
    nonisolated(unsafe) static var style: Style = ProcessInfo.processInfo.arguments.contains("-lime-hero-classic") ? .classic : .ambient
    /// The drift runs on a real phone only: a UI test run (the demo) keeps the background still, because an animation that never ends keeps the app from ever being idle.
    static let drifts = !ProcessInfo.processInfo.arguments.contains("-lime-demo-chat")

    /// What a default hero needs: the palette and the paper under it. `nil` in the classic style.
    static func ambient(photo: UIImage?, tone: Int, key: String) -> AmbientSpec? {
        guard style == .ambient else { return nil }
        // One spec per picture and tone, so the page's background is the same value every time it is worked out (a fresh dynamic colour each time made a presented
        // dialog on the group page vanish).
        let id = "\(key)|\(tone)"
        if let hit = specs[id] { return hit }
        let colours = photo.map { HeroPalette.vibrant(from: $0, key: key) } ?? []
        let palette = colours.count >= 3 ? colours : HeroPalette.tonePalette(tone)
        let made = AmbientSpec(palette: palette)
        specs[id] = made
        return made
    }
    nonisolated(unsafe) private static var specs: [String: AmbientSpec] = [:]
}

/// A hero palette and the tinted paper that goes with it.
struct AmbientSpec: Equatable {
    let palette: [UIColor]
    init(palette: [UIColor]) { self.palette = palette }

    /// The page's background below the hero: the canvas with a hint (about 7 %, in the dark about 14 % of a deep shade) of the palette's lightest colour, so the
    /// hero fades into a light tint of its own colours and not into white. A plain colour for the given appearance (a dynamic colour that read the canvas inside
    /// its provider made the group page's dialogs vanish).
    func paper(dark: Bool) -> Color {
        let lightest = palette.max { Self.brightness($0) < Self.brightness($1) } ?? .white
        let deepest = palette.min { Self.brightness($0) < Self.brightness($1) } ?? .black
        let canvas = UIColor(Theme.canvas).resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        return Color(uiColor: Self.blend(canvas, dark ? deepest : lightest, dark ? 0.14 : 0.07))
    }

    static func brightness(_ colour: UIColor) -> CGFloat { var b: CGFloat = 0; colour.getHue(nil, saturation: nil, brightness: &b, alpha: nil); return b }

    static func blend(_ a: UIColor, _ b: UIColor, _ amount: CGFloat) -> UIColor {
        var (ar, ag, ab, aa): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (br, bg, bb, ba): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa); b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: ar + (br - ar) * amount, green: ag + (bg - ag) * amount, blue: ab + (bb - ab) * amount, alpha: 1)
    }
}

extension HeroPalette {
    nonisolated(unsafe) private static let vibrantCache = NSCache<NSString, NSArray>()

    /// 4 to 6 vibrant colours from a picture: a small histogram on a tiny copy, the heaviest hues that are not near each other, each lifted in saturation and
    /// brightness so the result is lively. A near-grey picture gives none (the caller falls back to the avatar's tone family).
    static func vibrant(from image: UIImage, key: String) -> [UIColor] {
        if let hit = vibrantCache.object(forKey: key as NSString) as? [UIColor] { return hit }
        let side = 24
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in image.draw(in: CGRect(x: 0, y: 0, width: side, height: side)) }
        guard let cg = small.cgImage, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return [] }
        let stride = cg.bytesPerRow, bpp = cg.bitsPerPixel / 8
        // 12 hues x 2 brightness halves; weight = how many pixels, more for saturated ones.
        var weight = [Double](repeating: 0, count: 24)
        var sums = [(h: Double, s: Double, b: Double)](repeating: (0, 0, 0), count: 24)
        var totalSaturation = 0.0
        for y in 0..<side { for x in 0..<side {
            let o = y * stride + x * bpp
            let colour = UIColor(red: CGFloat(bytes[o]) / 255, green: CGFloat(bytes[o + 1]) / 255, blue: CGFloat(bytes[o + 2]) / 255, alpha: 1)
            var (h, s, b): (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
            colour.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
            totalSaturation += Double(s)
            guard b > 0.12, s > 0.10 else { continue }
            let bin = min(11, Int(h * 12)) * 2 + (b > 0.55 ? 1 : 0)
            let w = 0.3 + Double(s)
            weight[bin] += w
            // Hue sums on a circle would be better; within a 30-degree bin the plain mean is close enough.
            sums[bin].h += Double(h) * w; sums[bin].s += Double(s) * w; sums[bin].b += Double(b) * w
        } }
        guard totalSaturation / Double(side * side) > 0.12 else { return [] }
        var picked: [UIColor] = []
        var hues: [Double] = []
        for bin in weight.indices.sorted(by: { weight[$0] > weight[$1] }) where weight[bin] > 0 && picked.count < 5 {
            let h = sums[bin].h / weight[bin], s = sums[bin].s / weight[bin], b = sums[bin].b / weight[bin]
            // Skip a hue too near one already taken (a circle: 0 and 1 are the same).
            if hues.contains(where: { min(abs($0 - h), 1 - abs($0 - h)) < 0.06 }) && picked.count >= 2 { continue }
            hues.append(h)
            picked.append(UIColor(hue: CGFloat(h), saturation: CGFloat(min(1, s * 1.2 + 0.18)), brightness: CGFloat(min(0.96, max(0.62, b + 0.12))), alpha: 1))
        }
        let result = picked.count >= 3 ? picked : picked + variations(of: picked.first ?? .systemTeal, count: 4 - picked.count)
        vibrantCache.setObject(result as NSArray, forKey: key as NSString)
        return result
    }

    /// A palette from an avatar tone: its colour made vivid, with neighbouring hues and shades, so a person with no photo has a lively default that matches their circle.
    static func tonePalette(_ tone: Int) -> [UIColor] {
        let base = Theme.avatarUIColor(tone, dark: false)
        var (h, s, b): (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        base.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        let vivid = UIColor(hue: h, saturation: min(1, s * 1.7 + 0.2), brightness: 0.92, alpha: 1)
        return [vivid] + variations(of: vivid, count: 4)
    }

    /// Neighbouring hues and a deeper and a lighter shade of a colour.
    private static func variations(of colour: UIColor, count: Int) -> [UIColor] {
        var (h, s, b): (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        colour.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        func wrap(_ x: CGFloat) -> CGFloat { x - floor(x) }
        let all = [
            UIColor(hue: wrap(h + 0.07), saturation: min(1, s + 0.05), brightness: min(1, b), alpha: 1),
            UIColor(hue: wrap(h - 0.07), saturation: s, brightness: max(0.55, b - 0.12), alpha: 1),
            UIColor(hue: wrap(h + 0.14), saturation: max(0.35, s - 0.1), brightness: min(1, b), alpha: 1),
            UIColor(hue: wrap(h - 0.03), saturation: min(1, s + 0.1), brightness: max(0.5, b - 0.28), alpha: 1),
        ]
        return Array(all.prefix(count))
    }
}

/// A soft, organic, slowly moving background of the palette: a 3 x 3 `MeshGradient` whose inner points drift on a 20 to 30 second loop. Still with Reduce Motion or Low
/// Power Mode; on iOS 17 (no `MeshGradient`) a still arrangement of blurred blobs. Decorative.
struct AmbientBackground: View {
    let palette: [UIColor]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var colours: [Color] {
        let list = palette.isEmpty ? [UIColor.systemTeal] : palette
        // In the dark the palette is deepened so the white text on it keeps its contrast.
        let adjust: (UIColor) -> Color = { c in
            guard colorScheme == .dark else { return Color(uiColor: c) }
            var (h, s, b): (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
            c.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
            return Color(uiColor: UIColor(hue: h, saturation: min(1, s + 0.05), brightness: b * 0.55, alpha: 1))
        }
        return list.map(adjust)
    }

    var body: some View {
        let still = reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled || !Hero.drifts
        if #available(iOS 18, *), Hero.drifts {
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: still)) { context in
                mesh(at: still ? 0 : context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            blobs
        }
    }

    @available(iOS 18, *)
    private func mesh(at t: Double) -> some View {
        let c = colours
        func pick(_ i: Int) -> Color { c[i % c.count] }
        // Corners and edge points stay on the frame (they only slide along it); the middle moves in a slow loop.
        let w = t / 24
        let drift: (Double, Double) -> Float = { phase, amount in Float(sin((w + phase) * 2 * .pi) * amount) }
        let points: [SIMD2<Float>] = [
            [0, 0], [0.5 + drift(0.00, 0.12), 0], [1, 0],
            [0, 0.5 + drift(0.25, 0.12)], [0.5 + drift(0.50, 0.16), 0.5 + drift(0.75, 0.16)], [1, 0.5 + drift(0.40, 0.12)],
            [0, 1], [0.5 + drift(0.65, 0.12), 1], [1, 1],
        ]
        return MeshGradient(width: 3, height: 3, points: points, colors: [pick(0), pick(1), pick(2), pick(3), pick(4), pick(1), pick(2), pick(0), pick(3)], smoothsColors: true)
    }

    private var blobs: some View {
        let c = colours
        return ZStack {
            c[0]
            Circle().fill(c[1 % c.count]).frame(width: 340).offset(x: -90, y: -140).blur(radius: 70)
            Circle().fill(c[2 % c.count]).frame(width: 320).offset(x: 110, y: -20).blur(radius: 70)
            Circle().fill(c[3 % c.count]).frame(width: 340).offset(x: -60, y: 190).blur(radius: 70)
        }
        .clipped()
    }
}
