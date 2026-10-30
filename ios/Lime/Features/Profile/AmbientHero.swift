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

    /// What a default hero needs: the palette and the paper under it. `nil` in the classic style. The order (LIME-261b): a chosen colour always wins; else the
    /// picture's own colours; else the avatar's tone.
    static func ambient(photo: UIImage?, chosen: Int?, tone: Int, key: String, id: String) -> AmbientSpec? {
        guard style == .ambient else { return nil }
        // One spec per picture and colour, so the page's background is the same value every time it is worked out (a fresh dynamic colour each time made a presented
        // dialog on the group page vanish).
        let specID = "\(key)|\(chosen.map(String.init) ?? "-")|\(tone)"
        if let hit = specs[specID] { return hit }
        let palette: [UIColor]
        if let chosen { palette = HeroPalette.tonePalette(chosen) }
        else {
            let colours = photo.map { HeroPalette.vibrant(from: $0, key: key) } ?? []
            palette = colours.count >= 3 ? colours : HeroPalette.tonePalette(tone)
        }
        let made = AmbientSpec(palette: palette)
        specs[specID] = made
        HeroPaletteCache.write(id: id, version: chosen.map(String.init) ?? "-", palette: palette)
        return made
    }

    /// What this page showed last time (LIME-261b), at once and before its picture is loaded: `cover` if its hero is somebody's own picture or video (no mesh),
    /// else the kept palette (nil the first time, when the paper alone shows until the mesh is ready).
    static func remembered(id: String, chosen: Int?) -> (cover: Bool, spec: AmbientSpec?) {
        guard style == .ambient else { return (false, nil) }
        if let hit = HeroPaletteCache.read(id: id + "#cover", version: "cover"), hit.isEmpty { return (true, nil) }
        guard let palette = HeroPaletteCache.read(id: id, version: chosen.map(String.init) ?? "-"), palette.count >= 3 else { return (false, nil) }
        return (false, AmbientSpec(palette: palette))
    }
    /// Told when a page's cover is known: kept so the mesh is not drawn first next time.
    static func noteCover(id: String, has: Bool) {
        if has { HeroPaletteCache.write(id: id + "#cover", version: "cover", palette: []) }
        else if HeroPaletteCache.read(id: id + "#cover", version: "cover") != nil { HeroPaletteCache.clear(id: id + "#cover") }
    }
    nonisolated(unsafe) private static var specs: [String: AmbientSpec] = [:]
}

/// A hero palette and the tinted paper that goes with it. `palette[0]` is the dominant colour.
struct AmbientSpec: Equatable {
    let palette: [UIColor]
    init(palette: [UIColor]) { self.palette = palette }

    /// The page's background below the hero: the canvas with a hint (about 6 %, in the dark about 12 % of a deepened shade) of the palette's dominant colour, so the
    /// hero fades into a light tint of its own colours and not into white. A plain colour for the given appearance (a dynamic colour that read the canvas inside
    /// its provider made the group page's dialogs vanish).
    func paper(dark: Bool) -> Color {
        var tint = palette.first ?? .white
        if dark { var (h, s, b): (CGFloat, CGFloat, CGFloat) = (0, 0, 0); tint.getHue(&h, saturation: &s, brightness: &b, alpha: nil); tint = UIColor(hue: h, saturation: s, brightness: b * 0.6, alpha: 1) }
        let canvas = UIColor(Theme.canvas).resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        return Color(uiColor: Self.blend(canvas, tint, dark ? 0.12 : 0.06))
    }

    static func brightness(_ colour: UIColor) -> CGFloat { var b: CGFloat = 0; colour.getHue(nil, saturation: nil, brightness: &b, alpha: nil); return b }

    static func blend(_ a: UIColor, _ b: UIColor, _ amount: CGFloat) -> UIColor {
        var (ar, ag, ab, aa): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (br, bg, bb, ba): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa); b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: ar + (br - ar) * amount, green: ag + (bg - ag) * amount, blue: ab + (bb - ab) * amount, alpha: 1)
    }
}

/// Palettes worked out once, kept on disk by id and source version, so a page shows its colours at once next time (LIME-261b). `cover` marks a page whose hero is
/// somebody's own picture or video, which never shows the mesh.
enum HeroPaletteCache {
    private static let key = "lime.hero.palettes.v1"
    nonisolated(unsafe) private static var memory: [String: [String]]? = nil

    private static func all() -> [String: [String]] {
        if let memory { return memory }
        let loaded = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
        memory = loaded
        return loaded
    }
    /// What was kept for this id and version: nil if nothing; an empty palette for a page that has a cover.
    static func read(id: String, version: String) -> [UIColor]? {
        guard let hit = all()[id], hit.first == version else { return nil }
        return hit.dropFirst().compactMap(colour(fromHex:))
    }
    static func clear(id: String) { var map = all(); map[id] = nil; memory = map; UserDefaults.standard.set(map, forKey: key) }
    static func write(id: String, version: String, palette: [UIColor]) {
        var map = all()
        map[id] = [version] + palette.map(hex(of:))
        if map.count > 300 { for old in map.keys.sorted().prefix(map.count - 300) { map[old] = nil } }
        memory = map
        UserDefaults.standard.set(map, forKey: key)
    }
    private static func hex(of c: UIColor) -> String {
        var (r, g, b): (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        c.getRed(&r, green: &g, blue: &b, alpha: nil)
        return String(format: "%02x%02x%02x", Int(r * 255 + 0.5), Int(g * 255 + 0.5), Int(b * 255 + 0.5))
    }
    private static func colour(fromHex h: String) -> UIColor? {
        guard h.count == 6, let v = Int(h, radix: 16) else { return nil }
        return UIColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }
}

extension HeroPalette {
    nonisolated(unsafe) private static let vibrantCache = NSCache<NSString, NSArray>()

    /// A colour made calm: a gentle lift only (saturation x 1.1, at most 0.65; brightness kept between 0.30 and 0.70), so white text reads on it and nothing is neon.
    static func calm(_ colour: UIColor) -> UIColor {
        var (h, s, b): (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        colour.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        return UIColor(hue: h, saturation: min(0.65, s * 1.1), brightness: min(0.70, max(0.30, b)), alpha: 1)
    }

    /// The picture's own colours (LIME-261b): k-means (k = 5) in Lab on a 32 px copy, weighted by area; clusters under 6 % of the picture are dropped; only hues the
    /// picture has are kept, dominant first. With fewer than 3 left, lighter and darker shades of the dominant fill in (never other hues). A near-grey picture gives
    /// none (the caller falls back to the tone's palette).
    static func vibrant(from image: UIImage, key: String) -> [UIColor] {
        if let hit = vibrantCache.object(forKey: key as NSString) as? [UIColor] { return hit }
        let side = 32
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in image.draw(in: CGRect(x: 0, y: 0, width: side, height: side)) }
        guard let cg = small.cgImage, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return [] }
        let stride = cg.bytesPerRow, bpp = cg.bitsPerPixel / 8
        var rgb: [(Double, Double, Double)] = [], lab: [(Double, Double, Double)] = []
        var totalSaturation = 0.0
        for y in 0..<side { for x in 0..<side {
            let o = y * stride + x * bpp
            let (r, g, b) = (Double(bytes[o]) / 255, Double(bytes[o + 1]) / 255, Double(bytes[o + 2]) / 255)
            rgb.append((r, g, b)); lab.append(Self.lab(r, g, b))
            totalSaturation += Double(UIColor(red: r, green: g, blue: b, alpha: 1).saturationValue)
        } }
        guard totalSaturation / Double(side * side) > 0.06 else { return [] }
        // Farthest-point start (deterministic), then a few rounds.
        let k = 5
        let mean = lab.reduce((0.0, 0.0, 0.0)) { ($0.0 + $1.0, $0.1 + $1.1, $0.2 + $1.2) }
        let centre = (mean.0 / Double(lab.count), mean.1 / Double(lab.count), mean.2 / Double(lab.count))
        func dist(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double { let d = (a.0 - b.0, a.1 - b.1, a.2 - b.2); return d.0 * d.0 + d.1 * d.1 + d.2 * d.2 }
        var centres: [(Double, Double, Double)] = [lab.min { dist($0, centre) < dist($1, centre) } ?? centre]
        while centres.count < k {
            func gap(_ p: (Double, Double, Double)) -> Double { centres.map { dist($0, p) }.min() ?? 0 }
            guard let far = lab.max(by: { gap($0) < gap($1) }), gap(far) > 1 else { break }
            centres.append(far)
        }
        var member = [Int](repeating: 0, count: lab.count)
        for _ in 0..<8 {
            for i in lab.indices { member[i] = centres.indices.min { dist(lab[i], centres[$0]) < dist(lab[i], centres[$1]) } ?? 0 }
            for c in centres.indices {
                let ins = lab.indices.filter { member[$0] == c }
                guard !ins.isEmpty else { continue }
                let n = Double(ins.count)
                centres[c] = (ins.reduce(0) { $0 + lab[$1].0 } / n, ins.reduce(0) { $0 + lab[$1].1 } / n, ins.reduce(0) { $0 + lab[$1].2 } / n)
            }
        }
        var clusters: [(share: Double, colour: UIColor)] = []
        for c in centres.indices {
            let ins = rgb.indices.filter { member[$0] == c }
            let share = Double(ins.count) / Double(rgb.count)
            guard share >= 0.06 else { continue }
            let n = Double(ins.count)
            clusters.append((share, UIColor(red: ins.reduce(0) { $0 + rgb[$1].0 } / n, green: ins.reduce(0) { $0 + rgb[$1].1 } / n, blue: ins.reduce(0) { $0 + rgb[$1].2 } / n, alpha: 1)))
        }
        var picked = clusters.sorted { $0.share > $1.share }.map { calm($0.colour) }
        if picked.isEmpty { return [] }
        if picked.count < 3 { picked += shades(of: picked[0], count: 3 - picked.count) }
        vibrantCache.setObject(picked as NSArray, forKey: key as NSString)
        return picked
    }

    private static func lab(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (lr, lg, lb) = (lin(r), lin(g), lin(b))
        let x = (0.4124 * lr + 0.3576 * lg + 0.1805 * lb) / 0.95047, y = 0.2126 * lr + 0.7152 * lg + 0.0722 * lb, z = (0.0193 * lr + 0.1192 * lg + 0.9505 * lb) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116 }
        return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }

    /// A palette from a chosen colour: the colour, a lighter and a deeper shade, and two close neighbours (15 degrees either side).
    static func tonePalette(_ tone: Int) -> [UIColor] {
        // The swatches are pastels; the hue is kept and the saturation brought up to a body the mesh can carry.
        var (h, s, b): (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        Theme.avatarUIColor(tone, dark: false).getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        let base = calm(UIColor(hue: h, saturation: max(s, 0.6), brightness: b, alpha: 1))
        return [base] + shades(of: base, count: 2) + neighbours(of: base)
    }

    /// A lighter and a deeper shade of a colour, the same hue.
    private static func shades(of colour: UIColor, count: Int) -> [UIColor] {
        var (h, s, b): (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        colour.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        let all = [UIColor(hue: h, saturation: max(0, s - 0.08), brightness: min(0.70, b + 0.12), alpha: 1), UIColor(hue: h, saturation: s, brightness: max(0.30, b - 0.14), alpha: 1)]
        return Array(all.prefix(count))
    }

    private static func neighbours(of colour: UIColor) -> [UIColor] {
        var (h, s, b): (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        colour.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        func wrap(_ x: CGFloat) -> CGFloat { x - floor(x) }
        return [UIColor(hue: wrap(h + 15.0 / 360), saturation: s, brightness: b, alpha: 1), UIColor(hue: wrap(h - 15.0 / 360), saturation: s, brightness: b, alpha: 1)]
    }
}

private extension UIColor {
    var saturationValue: CGFloat { var s: CGFloat = 0; getHue(nil, saturation: &s, brightness: nil, alpha: nil); return s }
}

/// A soft, organic, slowly moving background of the palette: a 3 x 3 `MeshGradient` whose inner points drift on a 20 to 30 second loop. Still with Reduce Motion or Low
/// Power Mode; on iOS 17 (no `MeshGradient`) a still arrangement of blurred blobs. Decorative.
struct AmbientBackground: View {
    let palette: [UIColor]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// Fades in over the paper (about 0.4 s) the first time it shows; a test run shows it at once.
    @State private var shown = !Hero.drifts

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
        Group {
            if #available(iOS 18, *), Hero.drifts {
                TimelineView(.animation(minimumInterval: 1.0 / 20, paused: still)) { context in
                    mesh(at: still ? 0 : context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                blobs
            }
        }
        .opacity(shown ? 1 : 0)
        .onAppear { if !shown { withAnimation(reduceMotion ? nil : .easeIn(duration: 0.4)) { shown = true } } }
    }

    @available(iOS 18, *)
    private func mesh(at t: Double) -> some View {
        let c = colours
        func pick(_ i: Int) -> Color { c[i % c.count] }
        // Corners and edge points stay on the frame (they only slide along it); the middle moves in a slow loop.
        let w = t / 28
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
