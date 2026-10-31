// lime's sticker generator (LIME-209a). Draws animated GIF stickers frame by frame with Core Graphics and writes them with ImageIO:
// no outside artwork, no system emoji, no SF Symbols. Words are set in one of lime's bundled open-licence fonts.
//
//   swift tools/stickers/make-stickers.swift            (from the repo root)
//
// Writes ios/Lime/Resources/Stickers/<name>.gif and docs/qa-shots/209a/contact-sheet.png.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let outDir = root.appendingPathComponent("ios/Lime/Resources/Stickers")
let sheetURL = root.appendingPathComponent("docs/qa-shots/209a/contact-sheet.png")
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

// MARK: The stickers

struct Sticker {
    let file: String
    let card: UInt32
    let ink: UInt32
    let draw: (CGContext, CGFloat) -> Void   // t in 0..<1, a seamless loop
}

let confettiColours: [UInt32] = [0xE5486B, 0x2E8BD8, 0x57B03A, 0x8A5BD6, 0xF08A24, 0xF2B705]

let stickers: [Sticker] = [
    Sticker(file: "thank-you", card: 0xFEB2BF, ink: 0x3A1F27) { c, t in
        let beat = sin(t * tau)
        c.setFillColor(color(0xE5486B)); heart(c, 160, 112, 138 * (1 + 0.08 * beat))
        c.setFillColor(color(0xFFFFFF, 0.55)); circle(c, 118, 86, 9 + 1.5 * beat)
        c.setFillColor(color(0xFFFFFF))
        for (i, p) in [(CGPoint(x: 50, y: 70)), CGPoint(x: 268, y: 58), CGPoint(x: 262, y: 150), CGPoint(x: 62, y: 156)].enumerated() {
            sparkle(c, p.x, p.y, max(0, sin((t + CGFloat(i) / 4) * tau)) * 0.9 + 0.1)
        }
        words(c, "Thank you!", x: 160, baseline: 276, maxWidth: 272, cap: 60, ink: 0x3A1F27, lift: abs(sin(t * tau / 2)) * 7)
    },
    Sticker(file: "happy-birthday", card: 0xEFDF91, ink: 0x3B3410) { c, t in
        for i in 0..<22 {
            let f = CGFloat(i)
            let loops = i % 3 == 0 ? 2.0 : 1.0
            let y = fract(f * 0.137 + t * loops) * 380 - 30
            let x = CGFloat((i * 47) % 100) / 100 * 300 + 10 + sin((t * loops + f / 7) * tau) * 9
            c.setFillColor(color(confettiColours[i % confettiColours.count]))
            rotated(c, x, y, (t * loops + f / 5) * tau) {
                if i % 4 == 0 { circle(c, 0, 0, 6) } else { c.fill(CGRect(x: -7, y: -4, width: 14, height: 8)) }
            }
        }
        // a small cake with three candles
        c.translateBy(x: 0, y: -14)
        c.setFillColor(color(0xD9577F)); c.addPath(CGPath(roundedRect: CGRect(x: 80, y: 128, width: 160, height: 44), cornerWidth: 12, cornerHeight: 12, transform: nil)); c.fillPath()
        c.setFillColor(color(0xFFF3E0)); c.addPath(CGPath(roundedRect: CGRect(x: 104, y: 92, width: 112, height: 40), cornerWidth: 12, cornerHeight: 12, transform: nil)); c.fillPath()
        c.setFillColor(color(0x2E8BD8))
        for (i, cx) in [136.0, 160.0, 184.0].enumerated() {
            c.fill(CGRect(x: cx - 4, y: 66, width: 8, height: 28))
            let flicker = 1 + 0.18 * sin((t * 2 + CGFloat(i) / 3) * tau)
            c.setFillColor(color(0xF2B705)); c.fillEllipse(in: CGRect(x: cx - 5, y: 48 - 4 * flicker, width: 10, height: 16 * flicker)); c.setFillColor(color(0x2E8BD8))
        }
        c.translateBy(x: 0, y: 14)
        words(c, "Happy", x: 160, baseline: 228, maxWidth: 240, cap: 46, ink: 0x3B3410, angle: sin(t * tau) * 0.05)
        words(c, "birthday!", x: 160, baseline: 282, maxWidth: 280, cap: 54, ink: 0x3B3410, angle: -sin(t * tau) * 0.05)
    },
    Sticker(file: "snow-day", card: 0x92D4FF, ink: 0x0F3350) { c, t in
        c.setStrokeColor(color(0xFFFFFF)); c.setFillColor(color(0xFFFFFF))
        for i in 0..<20 {
            let f = CGFloat(i)
            let loops = i % 2 == 0 ? 1.0 : 2.0
            let r = 5 + CGFloat((i * 7) % 9)
            let y = fract(f * 0.211 + t * loops) * 360 - 20
            let x = CGFloat((i * 61) % 100) / 100 * 300 + 10 + sin((t + f / 9) * tau) * 10
            if r > 9 { snowflake(c, x, y, r, spin: (t * (i % 2 == 0 ? 1 : -1) + f / 6) * tau / 6) } else { circle(c, x, y, r * 0.6) }
        }
        c.setFillColor(color(0xFFFFFF)); c.fill(CGRect(x: 0, y: 296, width: 320, height: 24))
        words(c, "Snow day!", x: 160, baseline: 272, maxWidth: 272, cap: 60, ink: 0x0F3350, angle: sin(t * tau) * 0.04)
    },
    Sticker(file: "friday", card: 0x99EEFF, ink: 0x123B4A) { c, t in
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
        // a lime slice rolling along the bottom edge of the sun
        limeSlice(c, 236, 160 + sin(t * tau) * 6, 36, turn: t * tau / 8)
        words(c, "Friday!", x: 160, baseline: 276, maxWidth: 272, cap: 64, ink: 0x123B4A, lift: abs(sin(t * tau / 2)) * 7)
    },
]

// MARK: Rendering

func render(_ s: Sticker, _ t: CGFloat) -> CGImage {
    let c = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.translateBy(x: 0, y: CGFloat(side)); c.scaleBy(x: 1, y: -1)   // y grows downward, like a screen
    c.setAllowsAntialiasing(true); c.setShouldAntialias(true)
    c.saveGState()
    c.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side), cornerWidth: 44, cornerHeight: 44, transform: nil)); c.clip()
    c.setFillColor(color(s.card)); c.fill(CGRect(x: 0, y: 0, width: side, height: side))
    s.draw(c, t)
    c.restoreGState()
    return c.makeImage()!
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: sheetURL.deletingLastPathComponent(), withIntermediateDirectories: true)

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
}

// The contact sheet: each sticker at four moments of its loop, on a warm neutral.
let cell = 220, gap = 18
let sheetW = gap + 4 * (cell + gap), sheetH = gap + stickers.count * (cell + gap)
let sheet = CGContext(data: nil, width: sheetW, height: sheetH, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
sheet.setFillColor(color(0xEDE9E3)); sheet.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))
sheet.interpolationQuality = .high
for (row, s) in stickers.enumerated() {
    for col in 0..<4 {
        let rect = CGRect(x: gap + col * (cell + gap), y: sheetH - gap - (row + 1) * (cell + gap) + gap, width: cell, height: cell)
        sheet.draw(render(s, CGFloat(col) / 4), in: rect)
    }
}
let png = CGImageDestinationCreateWithURL(sheetURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(png, sheet.makeImage()!, nil)
CGImageDestinationFinalize(png)
print("contact sheet: \(sheetURL.path)")
