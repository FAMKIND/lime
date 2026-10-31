// lime's sticker generator (LIME-209a, LIME-209b). Draws animated GIF stickers frame by frame with Core Graphics and writes them with ImageIO:
// no outside artwork, no system emoji, no SF Symbols. Words are set in one of lime's bundled open-licence fonts.
//
//   swift tools/stickers/make-stickers.swift            (from the repo root)
//
// Writes ios/Lime/Resources/Stickers/<name>.gif and docs/qa-shots/209b/contact-sheet.png.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let outDir = root.appendingPathComponent("ios/Lime/Resources/Stickers")
let sheetURL = root.appendingPathComponent("docs/qa-shots/209b/contact-sheet.png")
let fontURL = root.appendingPathComponent("ios/Lime/Resources/Fonts/Lexend-Bold.ttf")

let side = 320, frameCount = 16, frameDelay = 0.1   // a 1.6 s loop
let tau = CGFloat.pi * 2

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

guard let provider = CGDataProvider(url: fontURL as CFURL), let cgFont = CGFont(provider) else { fatalError("no font at \(fontURL.path)") }

// MARK: Shapes

func circle(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) { c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)) }

func heart(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat) {
    let path = CGMutablePath()
    for i in 0...72 {
        let a = CGFloat(i) / 72 * tau
        let px = 16 * pow(sin(a), 3)
        let py = 13 * cos(a) - 5 * cos(2 * a) - 2 * cos(3 * a) - cos(4 * a)
        let p = CGPoint(x: x + px * size / 34, y: y - py * size / 34)
        i == 0 ? path.move(to: p) : path.addLine(to: p)
    }
    path.closeSubpath()
    c.addPath(path); c.fillPath()
}

func star(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, outer: CGFloat, inner: CGFloat, points: Int, rotation: CGFloat = -.pi / 2) {
    let path = CGMutablePath()
    for i in 0..<(points * 2) {
        let r = i % 2 == 0 ? outer : inner
        let a = rotation + CGFloat(i) / CGFloat(points * 2) * tau
        let p = CGPoint(x: x + cos(a) * r, y: y + sin(a) * r)
        i == 0 ? path.move(to: p) : path.addLine(to: p)
    }
    path.closeSubpath()
    c.addPath(path); c.fillPath()
}

func snowflake(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, spin: CGFloat) {
    c.setLineWidth(max(2, r * 0.22)); c.setLineCap(.round)
    for i in 0..<6 {
        let a = spin + CGFloat(i) / 6 * tau
        let tip = CGPoint(x: x + cos(a) * r, y: y + sin(a) * r)
        c.move(to: CGPoint(x: x, y: y)); c.addLine(to: tip)
        let m = CGPoint(x: x + cos(a) * r * 0.62, y: y + sin(a) * r * 0.62)
        for s in [-1.0, 1.0] {
            let b = a + CGFloat(s) * 0.7
            c.move(to: m); c.addLine(to: CGPoint(x: m.x + cos(b) * r * 0.32, y: m.y + sin(b) * r * 0.32))
        }
    }
    c.strokePath()
}

func limeSlice(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, turn: CGFloat) {
    c.setFillColor(color(0x5FA82A)); circle(c, x, y, r)
    c.setFillColor(color(0xE6F5B8)); circle(c, x, y, r * 0.88)
    c.setFillColor(color(0xA6D84F))
    for i in 0..<8 {
        let a0 = turn + CGFloat(i) / 8 * tau + 0.07, a1 = turn + CGFloat(i + 1) / 8 * tau - 0.07
        c.move(to: CGPoint(x: x, y: y))
        c.addArc(center: CGPoint(x: x, y: y), radius: r * 0.78, startAngle: a0, endAngle: a1, clockwise: false)
        c.closePath(); c.fillPath()
    }
    c.setFillColor(color(0xE6F5B8)); circle(c, x, y, r * 0.09)
}

func sparkle(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat) {
    guard s > 0.02 else { return }
    star(c, x, y, outer: 15 * s, inner: 4 * s, points: 4)
}

func rotated(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ angle: CGFloat, _ body: () -> Void) {
    c.saveGState(); c.translateBy(x: x, y: y); c.rotate(by: angle); body(); c.restoreGState()
}

func fract(_ v: CGFloat) -> CGFloat { v - floor(v) }

// MARK: Words

func line(_ text: String, size: CGFloat) -> (CTLine, CGFloat) {
    let font = CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
    let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
    let l = CTLineCreateWithAttributedString(attributed)
    return (l, CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil)))
}

/// Draws centred words that fit `maxWidth` (the size is capped at `cap`), turned by `angle` around their middle.
func words(_ c: CGContext, _ text: String, x: CGFloat, baseline: CGFloat, maxWidth: CGFloat, cap: CGFloat, ink: UInt32, angle: CGFloat = 0, lift: CGFloat = 0) {
    let probe = line(text, size: 100)
    let size = min(cap, 100 * maxWidth / probe.1)
    let font = CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
    let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(ink)])
    let l = CTLineCreateWithAttributedString(attributed)
    let width = CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil))
    c.saveGState()
    c.translateBy(x: x, y: baseline - size * 0.34 - lift); c.rotate(by: angle); c.translateBy(x: 0, y: size * 0.34)
    c.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    c.textPosition = CGPoint(x: -width / 2, y: 0)
    CTLineDraw(l, c)
    c.restoreGState()
}

// MARK: lime's logo mark (the app icon's lime, cut out of its background)

/// The app icon's lime without its off-white background: the background is whatever connects the picture's edge to itself in nearly the
/// background colour; those pixels become transparent (the dark outline's soft edge becomes partly transparent, in the outline's colour).
func loadMark() -> CGImage {
    let url = root.appendingPathComponent("ios/Lime/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("no icon at \(url.path)") }
    let w = image.width, h = image.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    px.withUnsafeMutableBytes { raw in
        let c = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    let bg = (Int(px[0]), Int(px[1]), Int(px[2]))
    func diff(_ i: Int) -> Int { max(abs(Int(px[i * 4]) - bg.0), abs(Int(px[i * 4 + 1]) - bg.1), abs(Int(px[i * 4 + 2]) - bg.2)) }
    var outside = [Bool](repeating: false, count: w * h)
    var stack: [Int] = []
    func push(_ i: Int) { if !outside[i] && diff(i) < 110 { outside[i] = true; stack.append(i) } }
    for x in 0..<w { push(x); push((h - 1) * w + x) }
    for y in 0..<h { push(y * w); push(y * w + w - 1) }
    while let i = stack.popLast() {
        let x = i % w, y = i / w
        if x > 0 { push(i - 1) }; if x < w - 1 { push(i + 1) }; if y > 0 { push(i - w) }; if y < h - 1 { push(i + w) }
    }
    let ink = (UInt8(16), UInt8(46), UInt8(32))   // the outline's colour
    var minX = w, minY = h, maxX = 0, maxY = 0
    for i in 0..<(w * h) {
        if outside[i] {
            let a = min(1, Double(diff(i)) / 110)
            px[i * 4] = UInt8(Double(ink.0) * a); px[i * 4 + 1] = UInt8(Double(ink.1) * a); px[i * 4 + 2] = UInt8(Double(ink.2) * a); px[i * 4 + 3] = UInt8(a * 255)
        }
        if px[i * 4 + 3] > 8 { let x = i % w, y = i / w; minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
    }
    let full = px.withUnsafeMutableBytes { raw in
        CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }
    return full.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!
}

let mark = loadMark()

/// Draws an image upright in the flipped drawing space, centred, `width` wide, turned by `angle`.
func drawMark(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, width: CGFloat, angle: CGFloat = 0) {
    let h = width * CGFloat(mark.height) / CGFloat(mark.width)
    c.saveGState(); c.translateBy(x: x, y: y); c.rotate(by: angle); c.scaleBy(x: 1, y: -1)
    c.interpolationQuality = .high
    c.draw(mark, in: CGRect(x: -width / 2, y: -h / 2, width: width, height: h))
    c.restoreGState()
}

// MARK: More shapes

func rrect(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) {
    c.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: min(r, w / 2, h / 2), cornerHeight: min(r, w / 2, h / 2), transform: nil)); c.fillPath()
}
func oval(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) { c.fillEllipse(in: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2)) }
func poly(_ c: CGContext, _ points: [(CGFloat, CGFloat)]) {
    c.move(to: CGPoint(x: points[0].0, y: points[0].1)); for p in points.dropFirst() { c.addLine(to: CGPoint(x: p.0, y: p.1)) }
    c.closePath(); c.fillPath()
}
func face(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
    c.setFillColor(color(0xFFD23F)); circle(c, x, y, r)
    c.setFillColor(color(0xFFE88A)); circle(c, x - r * 0.3, y - r * 0.36, r * 0.26)
}

// MARK: The stickers

/// How the words move: they hop, or wiggle.
enum Motion { case hop, wiggle }

struct Sticker {
    let file: String
    let words: [String]       // one or two lines
    let find: [String]        // other words that find it
    let card: UInt32
    let ink: UInt32
    var motion: Motion = .wiggle
    let draw: (CGContext, CGFloat) -> Void   // the picture, t in 0..<1, a seamless loop

    var text: String { words.joined(separator: " ") }
}

let confettiColours: [UInt32] = [0xE5486B, 0x2E8BD8, 0x57B03A, 0x8A5BD6, 0xF08A24, 0xF2B705]
let gold: UInt32 = 0xF2B705

let stickers: [Sticker] = [
    Sticker(file: "hi", words: ["Hi!"], find: ["hello", "hey"], card: 0xFED2CA, ink: 0x4A2A1A, motion: .hop) { c, t in
        c.saveGState(); c.translateBy(x: 160, y: 118); c.rotate(by: sin(t * tau) * 0.14)
        face(c, 0, 0, 74)
        c.setFillColor(color(0x4A2A1A)); oval(c, -26, -12, 9, 14); oval(c, 26, -12, 9, 14)
        c.setFillColor(color(0xFF8FA3, 0.6)); oval(c, -46, 14, 12, 8); oval(c, 46, 14, 12, 8)
        c.setStrokeColor(color(0x4A2A1A)); c.setLineWidth(9); c.setLineCap(.round)
        c.addArc(center: CGPoint(x: 0, y: 8), radius: 34, startAngle: 0.35, endAngle: .pi - 0.35, clockwise: false); c.strokePath()
        c.restoreGState()
        c.setFillColor(color(0xFFFFFF))
        for i in 0..<3 { sparkle(c, [48, 270, 262][i], [58, 40, 172][i], max(0, sin((t + CGFloat(i) / 3) * tau)) * 0.8 + 0.1) }
    },
    Sticker(file: "good-morning", words: ["Good", "morning!"], find: ["morning", "gm"], card: 0x92D4FF, ink: 0x0F3350) { c, t in
        let x: CGFloat = 160, y = 124 - 6 * sin(t * tau)
        c.setStrokeColor(color(0xF2A900)); c.setLineWidth(9); c.setLineCap(.round)
        for i in 0..<12 {
            let a = (CGFloat(i) + t) / 12 * tau
            c.move(to: CGPoint(x: x + cos(a) * 66, y: y + sin(a) * 66)); c.addLine(to: CGPoint(x: x + cos(a) * 82, y: y + sin(a) * 82))
        }
        c.strokePath()
        c.setFillColor(color(0xFFD23F)); circle(c, x, y, 52)
        c.setFillColor(color(0x7BC96F)); oval(c, 160, 204, 150, 30)
        c.setFillColor(color(0x5FB155)); oval(c, 96, 200, 70, 16)
    },
    Sticker(file: "thank-you", words: ["Thank you!"], find: ["thanks", "ty"], card: 0xFEB2BF, ink: 0x3A1F27, motion: .hop) { c, t in
        let beat = sin(t * tau)
        c.setFillColor(color(0xE5486B)); heart(c, 160, 112, 138 * (1 + 0.08 * beat))
        c.setFillColor(color(0xFFFFFF, 0.55)); circle(c, 118, 86, 9 + 1.5 * beat)
        c.setFillColor(color(0xFFFFFF))
        for (i, p) in [CGPoint(x: 50, y: 70), CGPoint(x: 268, y: 58), CGPoint(x: 262, y: 150), CGPoint(x: 62, y: 156)].enumerated() {
            sparkle(c, p.x, p.y, max(0, sin((t + CGFloat(i) / 4) * tau)) * 0.9 + 0.1)
        }
    },
    Sticker(file: "welcome", words: ["Welcome!"], find: ["welcome", "new"], card: 0xC4EFA6, ink: 0x1F3A14, motion: .hop) { c, t in
        c.setFillColor(color(0xFFF3E0)); rrect(c, 108, 100, 104, 78, 6)
        c.setFillColor(color(0xE5486B)); poly(c, [(92, 104), (160, 48), (228, 104)])
        c.setFillColor(color(0x8A5B3A)); rrect(c, 146, 128, 28, 50, 14)
        c.setFillColor(color(0xFFD23F)); circle(c, 168, 154, 3)
        c.setFillColor(color(0x92D4FF)); rrect(c, 118, 114, 22, 22, 4); rrect(c, 180, 114, 22, 22, 4)
        let rise = fract(t)
        c.setFillColor(color(0xE5486B, 1 - rise)); heart(c, 160 + sin(t * tau * 2) * 6, 44 - rise * 26, 26)
    },
    Sticker(file: "happy-birthday", words: ["Happy", "birthday!"], find: ["birthday", "bday"], card: 0xEFDF91, ink: 0x3B3410) { c, t in
        // Confetti falls through the top of the card and fades out before it reaches the words.
        for i in 0..<22 {
            let f = CGFloat(i)
            let loops = i % 3 == 0 ? 2.0 : 1.0
            let y = fract(f * 0.137 + t * loops) * 230 - 30
            let x = CGFloat((i * 47) % 100) / 100 * 300 + 10 + sin((t * loops + f / 7) * tau) * 9
            let fade = max(0, min(1, y / 24, (190 - y) / 40))
            guard fade > 0 else { continue }
            c.setFillColor(color(confettiColours[i % confettiColours.count], fade))
            rotated(c, x, y, (t * loops + f / 5) * tau) {
                if i % 4 == 0 { circle(c, 0, 0, 6) } else { c.fill(CGRect(x: -7, y: -4, width: 14, height: 8)) }
            }
        }
        c.saveGState(); c.translateBy(x: 0, y: -14)
        c.setFillColor(color(0xD9577F)); rrect(c, 80, 128, 160, 44, 12)
        c.setFillColor(color(0xFFF3E0)); rrect(c, 104, 92, 112, 40, 12)
        for (i, cx) in [136.0, 160.0, 184.0].enumerated() {
            c.setFillColor(color(0x2E8BD8)); c.fill(CGRect(x: cx - 4, y: 66, width: 8, height: 28))
            let flicker = 1 + 0.18 * sin((t * 2 + CGFloat(i) / 3) * tau)
            c.setFillColor(color(0xF2B705)); c.fillEllipse(in: CGRect(x: cx - 5, y: 48 - 4 * flicker, width: 10, height: 16 * flicker))
        }
        c.restoreGState()
    },
    Sticker(file: "congrats", words: ["Congrats!"], find: ["congratulations", "yay"], card: 0xD9BAFF, ink: 0x2A1A4A, motion: .hop) { c, t in
        c.setStrokeColor(color(0xFFFFFF)); c.setLineWidth(6); c.setLineCap(.round)
        let burst = fract(t)
        for i in 0..<12 {
            let a = CGFloat(i) / 12 * tau + 0.2
            c.setStrokeColor(color(confettiColours[i % 6], 1 - burst * 0.8))
            c.move(to: CGPoint(x: 160 + cos(a) * (70 + burst * 20), y: 108 + sin(a) * (70 + burst * 20)))
            c.addLine(to: CGPoint(x: 160 + cos(a) * (84 + burst * 30), y: 108 + sin(a) * (84 + burst * 30)))
        }
        c.strokePath()
        c.setFillColor(color(gold)); star(c, 160, 110, outer: 62 * (1 + 0.07 * sin(t * tau)), inner: 28, points: 5, rotation: -.pi / 2 + sin(t * tau) * 0.12)
        c.setFillColor(color(0xFFE88A)); star(c, 160, 110, outer: 36, inner: 16, points: 5, rotation: -.pi / 2 + sin(t * tau) * 0.12)
        c.setFillColor(color(0xFFFFFF))
        for i in 0..<3 { sparkle(c, [46, 276, 270][i], [52, 70, 172][i], max(0, sin((t + CGFloat(i) / 3) * tau)) * 0.8 + 0.1) }
    },
    Sticker(file: "great-job", words: ["Great job!"], find: ["good job", "nice", "well done"], card: 0xF3BF91, ink: 0x4A2A0A, motion: .hop) { c, t in
        c.saveGState(); c.translateBy(x: 160, y: 34); c.rotate(by: sin(t * tau) * 0.1); c.translateBy(x: -160, y: -34)
        c.setFillColor(color(0xE5486B)); rotated(c, 138, 100, 0.25) { c.fill(CGRect(x: -14, y: -4, width: 28, height: 80)) }
        c.setFillColor(color(0x2E8BD8)); rotated(c, 182, 100, -0.25) { c.fill(CGRect(x: -14, y: -4, width: 28, height: 80)) }
        c.setFillColor(color(gold)); circle(c, 160, 100, 56)
        c.setFillColor(color(0xFFE88A)); circle(c, 160, 100, 42)
        c.setFillColor(color(gold)); star(c, 160, 101, outer: 30, inner: 13, points: 5)
        c.restoreGState()
    },
    Sticker(file: "proud-of-you", words: ["Proud of", "you!"], find: ["proud"], card: 0xC4EFA6, ink: 0x1F3A14, motion: .hop) { c, t in
        let bob = sin(t * tau) * 5
        c.saveGState(); c.translateBy(x: 0, y: bob)
        c.setFillColor(color(0xE5483B)); oval(c, 134, 112, 40, 46); oval(c, 186, 112, 40, 46); oval(c, 160, 128, 52, 38)
        c.setFillColor(color(0xFFFFFF, 0.5)); oval(c, 132, 100, 8, 14)
        c.setStrokeColor(color(0x6B4423)); c.setLineWidth(7); c.setLineCap(.round); c.move(to: CGPoint(x: 160, y: 76)); c.addLine(to: CGPoint(x: 166, y: 50)); c.strokePath()
        c.setFillColor(color(0x57B03A)); rotated(c, 182, 56, -0.5) { oval(c, 0, 0, 22, 10) }
        c.restoreGState()
        c.setFillColor(color(0xFFFFFF))
        for i in 0..<2 { sparkle(c, [60, 262][i], [66, 90][i], max(0, sin((t + CGFloat(i) / 2) * tau)) * 0.8 + 0.1) }
    },
    Sticker(file: "yes", words: ["Yes!"], find: ["yes", "yay"], card: 0xC4EFA6, ink: 0x1F3A14, motion: .hop) { c, t in
        let pop = 1 + 0.07 * sin(t * tau)
        c.setFillColor(color(0x57B03A)); circle(c, 160, 106, 66 * pop)
        c.setStrokeColor(color(0xFFFFFF)); c.setLineWidth(17); c.setLineCap(.round); c.setLineJoin(.round)
        c.move(to: CGPoint(x: 160 - 30 * pop, y: 108)); c.addLine(to: CGPoint(x: 160 - 7 * pop, y: 106 + 22 * pop)); c.addLine(to: CGPoint(x: 160 + 34 * pop, y: 106 - 24 * pop)); c.strokePath()
    },
    Sticker(file: "you-got-this", words: ["You've got", "this!"], find: ["you got this", "encourage"], card: 0xF3BF91, ink: 0x4A2A0A, motion: .hop) { c, t in
        c.saveGState(); c.translateBy(x: 160, y: 108 - sin(t * tau) * 6); c.rotate(by: 0.5)
        let flame = 1 + 0.25 * sin(t * tau * 3)
        c.setFillColor(color(0xF08A24)); poly(c, [(-14, 56), (14, 56), (0, 56 + 36 * flame)])
        c.setFillColor(color(0xF2B705)); poly(c, [(-8, 56), (8, 56), (0, 56 + 22 * flame)])
        c.setFillColor(color(0xE5486B)); poly(c, [(-18, 20), (-44, 62), (-18, 56)]); poly(c, [(18, 20), (44, 62), (18, 56)])
        c.setFillColor(color(0xFFFFFF)); c.addPath(CGPath(ellipseIn: CGRect(x: -22, y: -64, width: 44, height: 124), transform: nil)); c.fillPath()
        c.setFillColor(color(0xE5486B)); poly(c, [(-20, -40), (0, -70), (20, -40)])
        c.setFillColor(color(0x2E8BD8)); circle(c, 0, -14, 12)
        c.restoreGState()
        c.setFillColor(color(0xFFFFFF))
        for i in 0..<3 { sparkle(c, [50, 268, 60][i], [60, 52, 160][i], max(0, sin((t + CGFloat(i) / 3) * tau)) * 0.8 + 0.1) }
    },
    Sticker(file: "hang-in-there", words: ["Hang in", "there"], find: ["hang in", "support"], card: 0x92D4FF, ink: 0x0F3350) { c, t in
        c.setLineCap(.butt)
        for (i, hex) in [0xE5486B, 0xF08A24, 0xF2B705, 0x57B03A, 0x2E8BD8, 0x8A5BD6].enumerated() {
            c.setStrokeColor(color(UInt32(hex))); c.setLineWidth(13)
            c.addArc(center: CGPoint(x: 160, y: 146), radius: CGFloat(98 - i * 13), startAngle: .pi, endAngle: 0, clockwise: false); c.strokePath()
        }
        c.setFillColor(color(0xFFFFFF))
        for (x, dir) in [(66.0, 1.0), (254.0, -1.0)] {
            let bob = sin((t + (dir > 0 ? 0 : 0.5)) * tau) * 4
            circle(c, x, 148 + bob, 22); circle(c, x + 24 * dir, 156 + bob, 18); circle(c, x - 20 * dir, 158 + bob, 16)
        }
    },
    Sticker(file: "lol", words: ["LOL"], find: ["lol", "funny", "haha"], card: 0xEFDF91, ink: 0x3B3410, motion: .hop) { c, t in
        c.saveGState(); c.translateBy(x: sin(t * tau * 3) * 3, y: sin(t * tau * 2) * 3)
        face(c, 160, 112, 72)
        c.setStrokeColor(color(0x4A2A1A)); c.setLineWidth(8); c.setLineCap(.round); c.setLineJoin(.round)
        c.move(to: CGPoint(x: 106, y: 100)); c.addLine(to: CGPoint(x: 126, y: 88)); c.addLine(to: CGPoint(x: 146, y: 100))
        c.move(to: CGPoint(x: 174, y: 100)); c.addLine(to: CGPoint(x: 194, y: 88)); c.addLine(to: CGPoint(x: 214, y: 100)); c.strokePath()
        c.setFillColor(color(0x4A2A1A)); c.move(to: CGPoint(x: 120, y: 120)); c.addArc(center: CGPoint(x: 160, y: 120), radius: 40, startAngle: .pi, endAngle: 0, clockwise: true)
        c.addLine(to: CGPoint(x: 120, y: 120)); c.fillPath()
        c.setFillColor(color(0xFF8FA3)); oval(c, 160, 148, 20, 9)
        c.restoreGState()
        c.setFillColor(color(0x2E8BD8))
        for (i, x) in [92.0, 228.0].enumerated() { let y = 116 + fract(t + CGFloat(i) / 2) * 40; oval(c, x, y, 7, 10) }
    },
    Sticker(file: "oops", words: ["Oops!"], find: ["oops", "sorry", "mistake"], card: 0xFED2CA, ink: 0x4A2A1A, motion: .wiggle) { c, t in
        c.saveGState(); c.translateBy(x: 160, y: 108); c.rotate(by: -0.5 + sin(t * tau) * 0.09)
        c.setFillColor(color(0xF2B705)); c.fill(CGRect(x: -70, y: -18, width: 110, height: 36))
        c.setFillColor(color(0xE0A400)); c.fill(CGRect(x: -70, y: 4, width: 110, height: 14))
        c.setFillColor(color(0xF0D5A8)); poly(c, [(40, -18), (84, 0), (40, 18)])
        c.setFillColor(color(0x4A2A1A)); poly(c, [(72, -5), (84, 0), (72, 5)])
        c.setFillColor(color(0xC8CDD2)); c.fill(CGRect(x: -86, y: -18, width: 16, height: 36))
        c.setFillColor(color(0xFF8FA3)); rrect(c, -108, -18, 24, 36, 8)
        c.restoreGState()
        c.setFillColor(color(0xFF8FA3))
        for i in 0..<5 { let f = fract(t + CGFloat(i) / 5); circle(c, 62 + CGFloat(i) * 9 + sin(f * tau) * 4, 120 + f * 56, 4) }
    },
    Sticker(file: "friday", words: ["Friday!"], find: ["tgif", "weekend"], card: 0x99EEFF, ink: 0x123B4A, motion: .hop) { c, t in
        let x = CGFloat(160), y = CGFloat(112)
        c.setStrokeColor(color(0xF2A900)); c.setLineWidth(10); c.setLineCap(.round)
        for i in 0..<12 {
            let a = (CGFloat(i) + t) / 12 * tau
            let r0: CGFloat = 70, r1: CGFloat = 86 + (i % 2 == 0 ? 8 : 0) * (1 + sin(t * tau))
            c.move(to: CGPoint(x: x + cos(a) * r0, y: y + sin(a) * r0)); c.addLine(to: CGPoint(x: x + cos(a) * r1, y: y + sin(a) * r1))
        }
        c.strokePath()
        c.setFillColor(color(0xFFD23F)); circle(c, x, y, 58)
        c.setFillColor(color(0xFFE88A)); circle(c, x - 16, y - 18, 20)
        drawMark(c, 236, 160 + sin(t * tau) * 6, width: 76, angle: sin(t * tau) * 0.12)   // lime's own logo
    },
    Sticker(file: "snow-day", words: ["Snow day!"], find: ["snow"], card: 0x92D4FF, ink: 0x0F3350) { c, t in
        c.setStrokeColor(color(0xFFFFFF)); c.setFillColor(color(0xFFFFFF))
        for i in 0..<20 {
            let f = CGFloat(i)
            let loops = i % 2 == 0 ? 1.0 : 2.0
            let r = 5 + CGFloat((i * 7) % 9)
            let y = fract(f * 0.211 + t * loops) * 360 - 20
            let x = CGFloat((i * 61) % 100) / 100 * 300 + 10 + sin((t + f / 9) * tau) * 10
            if r > 9 { snowflake(c, x, y, r, spin: (t * (i % 2 == 0 ? 1 : -1) + f / 6) * tau / 6) } else { circle(c, x, y, r * 0.6) }
        }
        // a soft drift along the bottom, the words stay above it
        c.setFillColor(color(0xFFFFFF))
        c.move(to: CGPoint(x: -10, y: 330)); c.addLine(to: CGPoint(x: -10, y: 304))
        c.addCurve(to: CGPoint(x: 170, y: 300), control1: CGPoint(x: 50, y: 288), control2: CGPoint(x: 110, y: 312))
        c.addCurve(to: CGPoint(x: 330, y: 298), control1: CGPoint(x: 230, y: 290), control2: CGPoint(x: 290, y: 308))
        c.addLine(to: CGPoint(x: 330, y: 330)); c.closePath(); c.fillPath()
    },
    Sticker(file: "coffee-time", words: ["Coffee time"], find: ["coffee", "tired"], card: 0xF3BF91, ink: 0x3A1F0A) { c, t in
        c.setStrokeColor(color(0xFFFFFF, 0.9)); c.setLineWidth(7); c.setLineCap(.round)
        for i in 0..<3 {
            let x = 134 + CGFloat(i) * 26, f = fract(t + CGFloat(i) / 3)
            c.setStrokeColor(color(0xFFFFFF, sin(f * .pi)))
            c.move(to: CGPoint(x: x, y: 82 - f * 26))
            c.addCurve(to: CGPoint(x: x, y: 52 - f * 26), control1: CGPoint(x: x + 12, y: 72 - f * 26), control2: CGPoint(x: x - 12, y: 62 - f * 26)); c.strokePath()
        }
        c.setStrokeColor(color(0xFFF3E0)); c.setLineWidth(12); c.addEllipse(in: CGRect(x: 182, y: 104, width: 40, height: 34)); c.strokePath()
        c.setFillColor(color(0xFFF3E0)); rrect(c, 112, 90, 86, 76, 22)
        c.setFillColor(color(0x6B4423)); oval(c, 155, 96, 38, 8)
        c.setFillColor(color(0xE5486B)); heart(c, 155, 134, 22)
        c.setFillColor(color(0xD9C9B0)); oval(c, 155, 170, 76, 10)
    },
    Sticker(file: "brain-break", words: ["Brain break"], find: ["break", "recess"], card: 0xD9BAFF, ink: 0x2A1A4A) { c, t in
        let h = abs(sin(t * .pi))   // 0 at the floor, 1 at the top
        let y = 150 - h * 74
        c.setFillColor(color(0x2A1A4A, 0.18)); oval(c, 160, 172, 44 - h * 14, 8 - h * 3)
        c.saveGState(); c.translateBy(x: 160, y: y + (1 - h) * 6); c.scaleBy(x: 1 + (1 - h) * 0.08, y: 1 - (1 - h) * 0.08); c.rotate(by: t * tau)
        c.setFillColor(color(0xF08A24)); circle(c, 0, 0, 44)
        // The seams are cut off at the ball's edge and turn with it: one up and down, one across, and a curve on each side bulging toward the middle.
        c.saveGState()
        c.addEllipse(in: CGRect(x: -44, y: -44, width: 88, height: 88)); c.clip()
        c.setStrokeColor(color(0x7A3A0A)); c.setLineWidth(4); c.setLineCap(.butt)
        c.move(to: CGPoint(x: -44, y: 0)); c.addLine(to: CGPoint(x: 44, y: 0))
        c.move(to: CGPoint(x: 0, y: -44)); c.addLine(to: CGPoint(x: 0, y: 44)); c.strokePath()
        c.strokeEllipse(in: CGRect(x: -62 - 36, y: -36, width: 72, height: 72))
        c.strokeEllipse(in: CGRect(x: 62 - 36, y: -36, width: 72, height: 72))
        c.restoreGState()
        c.restoreGState()
    },
    Sticker(file: "field-trip", words: ["Field trip!"], find: ["field trip", "trip"], card: 0xC4EFA6, ink: 0x1F3A14, motion: .hop) { c, t in
        let bob = sin(t * tau * 2) * 2
        c.setFillColor(color(0x2D5A27, 0.25))
        for i in 0..<4 { rrect(c, CGFloat(i) * 90 - fract(t) * 90, 178, 44, 6, 3) }
        c.saveGState(); c.translateBy(x: 0, y: bob)
        c.setFillColor(color(0xF2B705)); rrect(c, 62, 84, 196, 76, 18)
        c.setFillColor(color(0xFFFFFF)); for i in 0..<5 { rrect(c, 76 + CGFloat(i) * 34, 96, 26, 26, 5) }
        c.setFillColor(color(0x4A3A00)); c.fill(CGRect(x: 62, y: 132, width: 196, height: 5))
        c.setFillColor(color(0xFFFFFF)); circle(c, 248, 148, 5)
        for x in [104.0, 214.0] {
            c.setFillColor(color(0x2A2A2A)); circle(c, x, 162, 19)
            c.setFillColor(color(0xC8CDD2)); circle(c, x, 162, 9)
            c.setStrokeColor(color(0x2A2A2A)); c.setLineWidth(3); c.move(to: CGPoint(x: x, y: 162)); c.addLine(to: CGPoint(x: x + cos(t * tau * 2) * 9, y: 162 + sin(t * tau * 2) * 9)); c.strokePath()
        }
        c.restoreGState()
    },
    Sticker(file: "report-cards", words: ["Report cards"], find: ["grades", "grading"], card: 0xEFDF91, ink: 0x3B3410) { c, t in
        c.saveGState(); c.translateBy(x: 160, y: 108); c.rotate(by: sin(t * tau) * 0.06)
        c.setFillColor(color(0x000000, 0.08)); rrect(c, -50, -62, 108, 136, 10)
        c.setFillColor(color(0xFFFFFF)); rrect(c, -54, -66, 108, 136, 10)
        c.setFillColor(color(0xD9DEE3)); for i in 0..<3 { rrect(c, -36, 22 + CGFloat(i) * 14, 72 - CGFloat(i) * 14, 6, 3) }
        c.setFillColor(color(0x92D4FF)); rrect(c, -36, -50, 40, 8, 4)
        c.restoreGState()
        words(c, "A+", x: 160, baseline: 118 + sin(t * tau) * 3, maxWidth: 96, cap: 58, ink: 0xE5486B, angle: -0.18 + sin(t * tau) * 0.04)
    },
    Sticker(file: "testing-week", words: ["Testing week"], find: ["testing", "exams"], card: 0x99EEFF, ink: 0x123B4A) { c, t in
        c.setFillColor(color(0xFFFFFF)); rrect(c, 100, 36, 120, 142, 12)
        c.setFillColor(color(0xD9DEE3)); for i in 0..<4 { rrect(c, 114, 56 + CGFloat(i) * 29, 14, 6, 3) }
        let pick = [1, 3, 0, 2]
        for row in 0..<4 {
            let fill = max(0, min(1, t * 5.2 - CGFloat(row) * 1.0))
            for col in 0..<4 {
                let x = 146 + CGFloat(col) * 17, y = 60 + CGFloat(row) * 29
                c.setStrokeColor(color(0x8A96A3)); c.setLineWidth(2.5); c.strokeEllipse(in: CGRect(x: x - 6, y: y - 6, width: 12, height: 12))
                if pick[row] == col { c.setFillColor(color(0x123B4A, fill)); circle(c, x, y, 6 * min(1, fill * 1.2)) }
            }
        }
    },
    Sticker(file: "quiet-please", words: ["Quiet please"], find: ["quiet", "shh"], card: 0xFEB2BF, ink: 0x3A1F27) { c, t in
        let s = 1 + 0.05 * sin(t * tau)
        c.saveGState(); c.translateBy(x: 160, y: 100); c.scaleBy(x: s, y: s)
        c.setFillColor(color(0xFFFFFF)); rrect(c, -84, -50, 168, 100, 36); poly(c, [(-30, 44), (-46, 78), (0, 48)])
        c.restoreGState()
        words(c, "shh...", x: 160, baseline: 118, maxWidth: 130, cap: 50, ink: 0x3A1F27)
        c.setStrokeColor(color(0xE5486B, 0.6)); c.setLineWidth(5); c.setLineCap(.round)
        for i in 0..<2 {
            let f = fract(t + CGFloat(i) / 2)
            c.setStrokeColor(color(0xE5486B, (1 - f) * 0.6))
            c.addArc(center: CGPoint(x: 160, y: 100), radius: 100 + f * 26, startAngle: -0.5, endAngle: 0.5, clockwise: false); c.strokePath()
            c.addArc(center: CGPoint(x: 160, y: 100), radius: 100 + f * 26, startAngle: .pi - 0.5, endAngle: .pi + 0.5, clockwise: false); c.strokePath()
        }
    },
    Sticker(file: "see-you-tomorrow", words: ["See you", "tomorrow"], find: ["bye"], card: 0xD9BAFF, ink: 0x2A1A4A) { c, t in
        c.saveGState(); c.translateBy(x: 150, y: 104); c.rotate(by: sin(t * tau) * 0.07)
        c.setFillColor(color(0xFFE88A)); circle(c, 0, 0, 60)
        c.setFillColor(color(0xD9BAFF)); circle(c, 30, -16, 52)
        c.restoreGState()
        c.setFillColor(color(0xFFFFFF))
        for i in 0..<4 { sparkle(c, [236, 270, 214, 58][i], [60, 118, 150, 62][i], max(0, sin((t + CGFloat(i) / 4) * tau)) * 0.9 + 0.1) }
    },
    Sticker(file: "bell-rang", words: ["Bell rang!"], find: ["bell", "dismissal"], card: 0xFED2CA, ink: 0x4A2A1A, motion: .hop) { c, t in
        let swing = sin(t * tau) * 0.3
        c.saveGState(); c.translateBy(x: 160, y: 40); c.rotate(by: swing)
        c.setFillColor(color(gold))
        c.move(to: CGPoint(x: -60, y: 100)); c.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: -52, y: 48), control2: CGPoint(x: -44, y: 0))
        c.addCurve(to: CGPoint(x: 60, y: 100), control1: CGPoint(x: 44, y: 0), control2: CGPoint(x: 52, y: 48)); c.closePath(); c.fillPath()
        c.setFillColor(color(0xE0A400)); rrect(c, -68, 96, 136, 16, 8)
        c.setFillColor(color(0xFFE88A)); oval(c, -22, 42, 7, 24)
        c.setFillColor(color(0x6B4423)); circle(c, -swing * 14, 122, 12)
        c.setFillColor(color(gold)); circle(c, 0, -4, 9)
        c.restoreGState()
        c.setStrokeColor(color(0xE5486B)); c.setLineWidth(6); c.setLineCap(.round)
        for (i, d) in [(-1.0), 1.0].enumerated() {
            c.setStrokeColor(color(0xE5486B, 0.35 + 0.5 * abs(sin(t * tau + CGFloat(i) * 0.4))))
            c.move(to: CGPoint(x: 160 + d * 86, y: 70)); c.addLine(to: CGPoint(x: 160 + d * 104, y: 62))
            c.move(to: CGPoint(x: 160 + d * 90, y: 92)); c.addLine(to: CGPoint(x: 160 + d * 112, y: 92)); c.strokePath()
        }
    },
    Sticker(file: "summer", words: ["Summer!"], find: ["vacation", "holiday"], card: 0xEFDF91, ink: 0x4A3A00, motion: .hop) { c, t in
        c.saveGState(); c.translateBy(x: 160, y: 104); c.rotate(by: -0.18 + sin(t * tau) * 0.03)
        c.setStrokeColor(color(0x6B4423)); c.setLineWidth(8); c.setLineCap(.round); c.move(to: CGPoint(x: 0, y: -40)); c.addLine(to: CGPoint(x: 0, y: 84)); c.strokePath()
        for i in 0..<6 {
            c.setFillColor(color(i % 2 == 0 ? 0xE5486B : 0xFFFFFF))
            c.move(to: CGPoint(x: 0, y: -4))
            c.addArc(center: CGPoint(x: 0, y: -4), radius: 78, startAngle: .pi + CGFloat(i) / 6 * .pi, endAngle: .pi + CGFloat(i + 1) / 6 * .pi, clockwise: false)
            c.closePath(); c.fillPath()
        }
        c.restoreGState()
        c.setFillColor(color(0x2E8BD8))
        c.move(to: CGPoint(x: -10, y: 200))
        for x in stride(from: CGFloat(-10), through: 330, by: 10) { c.addLine(to: CGPoint(x: x, y: 170 + sin((x / 80 + t) * tau) * 7)) }
        c.addLine(to: CGPoint(x: 330, y: 200)); c.closePath(); c.fillPath()
    },
]

// MARK: Rendering

/// Words under the picture: one line low on the card, or two.
func setWords(_ c: CGContext, _ s: Sticker, _ t: CGFloat) {
    let beat = abs(sin(t * tau / 2)), sway = sin(t * tau)
    func motion(_ i: Int) -> (CGFloat, CGFloat) { s.motion == .hop ? (0, beat * 7) : (sway * 0.05 * (i == 0 ? 1 : -1), 0) }
    if s.words.count == 1 {
        let m = motion(0)
        words(c, s.words[0], x: 160, baseline: 276, maxWidth: 272, cap: 62, ink: s.ink, angle: m.0, lift: m.1)
    } else {
        let m0 = motion(0), m1 = motion(1)
        words(c, s.words[0], x: 160, baseline: 228, maxWidth: 240, cap: 46, ink: s.ink, angle: m0.0, lift: m0.1)
        words(c, s.words[1], x: 160, baseline: 284, maxWidth: 280, cap: 54, ink: s.ink, angle: m1.0, lift: m1.1)
    }
}

func render(_ s: Sticker, _ t: CGFloat) -> CGImage {
    let c = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.translateBy(x: 0, y: CGFloat(side)); c.scaleBy(x: 1, y: -1)   // y grows downward, like a screen
    c.setAllowsAntialiasing(true); c.setShouldAntialias(true)
    c.saveGState()
    c.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side), cornerWidth: 44, cornerHeight: 44, transform: nil)); c.clip()
    c.setFillColor(color(s.card)); c.fill(CGRect(x: 0, y: 0, width: side, height: side))
    s.draw(c, t)
    setWords(c, s, t)
    c.restoreGState()
    return c.makeImage()!
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: sheetURL.deletingLastPathComponent(), withIntermediateDirectories: true)

var pack: [[String: Any]] = []
for s in stickers {
    let url = outDir.appendingPathComponent("\(s.file).gif")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else { fatalError("cannot write \(url.path)") }
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary)
    for f in 0..<frameCount {
        CGImageDestinationAddImage(dest, render(s, CGFloat(f) / CGFloat(frameCount)),
                                   [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: frameDelay]] as CFDictionary)
    }
    guard CGImageDestinationFinalize(dest) else { fatalError("cannot finish \(url.path)") }
    let kb = ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) / 1024
    print("\(s.file).gif  \(kb) KB")
    pack.append(["file": "\(s.file).gif", "words": s.text, "find": s.find, "card": String(format: "%06X", s.card)])
}
let json = try JSONSerialization.data(withJSONObject: ["name": "lime", "stickers": pack], options: [.prettyPrinted, .sortedKeys])
try json.write(to: outDir.appendingPathComponent("pack.json"))

// The contact sheet: all of them at one moment of their loop, on a warm neutral.
let columns = 6, cell = 200, gap = 14
let rows = (stickers.count + columns - 1) / columns
let sheetW = gap + columns * (cell + gap), sheetH = gap + rows * (cell + gap)
let sheet = CGContext(data: nil, width: sheetW, height: sheetH, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
sheet.setFillColor(color(0xEDE9E3)); sheet.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))
sheet.interpolationQuality = .high
for (i, s) in stickers.enumerated() {
    let row = i / columns, col = i % columns
    sheet.draw(render(s, 0.25), in: CGRect(x: gap + col * (cell + gap), y: sheetH - (row + 1) * (cell + gap), width: cell, height: cell))
}
let png = CGImageDestinationCreateWithURL(sheetURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(png, sheet.makeImage()!, nil)
CGImageDestinationFinalize(png)
print("contact sheet: \(sheetURL.path)")
