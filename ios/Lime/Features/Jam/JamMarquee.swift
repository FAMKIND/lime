import SwiftUI
import UIKit
import AVKit

/// How a marquee moves (LIME-235c): a pause at the start, a slow scroll to the end, a pause, back.
enum MarqueeMotion {
    static let startPause = 2.0
    static let endPause = 1.5
    static let speed = 30.0   // points a second

    /// How far the text overflows its box (0 when it fits).
    static func overflow(text: CGFloat, box: CGFloat) -> CGFloat { max(0, text - box) }

    /// Seconds one way for an overflow.
    static func duration(overflow: CGFloat) -> Double { max(0.5, Double(overflow) / speed) }
}

private struct MarqueeWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A line of text that scrolls sideways when it does not fit, like Apple Podcasts: a pause at the start, a slow scroll to the end, a pause, back, with
/// both edges fading out. With Reduce Motion it is truncated with … and never moves. VoiceOver reads all of it.
struct MarqueeText: View {
    let text: String
    var font: Font = Theme.body
    var color: Color = .white
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflow: CGFloat { MarqueeMotion.overflow(text: textWidth, box: boxWidth) }

    var body: some View {
        // The one-line, truncated text sizes the box and is what shows when nothing needs to move; the text's own width is measured by a copy that is
        // never clipped or resized, so a long title is known to be long.
        Text(text).font(font).foregroundStyle(color).lineLimit(1).opacity(overflow > 0 && !reduceMotion ? 0 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boxWidth = $0 }
            .background {
                Text(text).font(font).fixedSize().hidden().background(GeometryReader { Color.clear.preference(key: MarqueeWidthKey.self, value: $0.size.width) })
                    .frame(width: 0, height: 0, alignment: .leading)
            }
            .onPreferenceChange(MarqueeWidthKey.self) { textWidth = $0 }
            .overlay(alignment: .leading) {
                Text(text).font(font).foregroundStyle(color).fixedSize()
                    .offset(x: offset)
                    .frame(width: boxWidth, alignment: .leading).clipped()
                    .mask { edgeFade }
                    .opacity(overflow > 0 && !reduceMotion ? 1 : 0)
            }
            .task(id: "\(text)|\(Int(textWidth))|\(Int(boxWidth))|\(reduceMotion)") { await run() }
            .accessibilityElement(children: .ignore).accessibilityLabel(text)
    }

    private var edgeFade: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 10)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 10)
        }
    }

    private func run() async {
        offset = 0
        guard overflow > 0, !reduceMotion else { return }
        let seconds = MarqueeMotion.duration(overflow: overflow)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(MarqueeMotion.startPause))
            if Task.isCancelled { return }
            withAnimation(.linear(duration: seconds)) { offset = -overflow - 10 }
            try? await Task.sleep(for: .seconds(seconds + MarqueeMotion.endPause))
            if Task.isCancelled { return }
            withAnimation(.linear(duration: seconds)) { offset = 0 }
            try? await Task.sleep(for: .seconds(seconds))
        }
    }
}

/// The player's background: a soft vertical gradient from the cover's colour, a little lighter at the top and deeper at the bottom, darkened until white
/// text keeps 4.5:1 everywhere it sits (LIME-235c item 8).
enum PlayerTint {
    /// The most luminous the top and the bottom of the gradient may be. White over luminance L has contrast 1.05 / (L + 0.05): 0.12 keeps it above 6:1,
    /// 0.03 above 13:1; Increase Contrast and Reduce Transparency go deeper.
    static func limits(deeper: Bool) -> (top: Double, bottom: Double) { deeper ? (0.06, 0.015) : (0.12, 0.03) }

    static func colors(sampled: UIColor?, fallbackTone: Int, deeper: Bool) -> (top: UIColor, bottom: UIColor) {
        let base = sampled ?? Theme.avatarUIColor(fallbackTone, dark: true)
        let l = limits(deeper: deeper)
        return (limit(base, to: l.top), limit(base, to: l.bottom))
    }

    /// `colour` scaled darker until its luminance is at most `max`.
    static func limit(_ colour: UIColor, to max: Double) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        var rgb = (Double(r), Double(g), Double(b))
        for _ in 0..<60 where HeroScrim.luminance(rgb) > max { rgb = (rgb.0 * 0.92, rgb.1 * 0.92, rgb.2 * 0.92) }
        return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }

    /// White text over a colour.
    static func contrastWithWhite(_ colour: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 1.05 / (HeroScrim.luminance((Double(r), Double(g), Double(b))) + 0.05)
    }
}

/// The gradient itself.
struct PlayerBackground: View {
    let top: UIColor
    let bottom: UIColor

    var body: some View {
        LinearGradient(colors: [Color(uiColor: top), Color(uiColor: bottom)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
    }
}

extension ConversationStore {
    /// The picture a post's player takes its colour from: its cover, else its video's poster; nil for the default cover.
    func coverImage(for postID: String) async -> UIImage? {
        let files = jamAttachments(postID).filter { $0.mime != "text/vtt" }
        if let cover = files.first(where: JamCover.isCover) { return await jamAttachmentData(postID, cover.attachmentId).flatMap(UIImage.init(data:)) }
        if let video = files.first(where: { $0.kind == "video" && !$0.poster.isEmpty }) { return UIImage(data: video.poster) }
        return nil
    }
}

/// Picture in Picture for the video on screen (the layer of the visible player view).
@MainActor
enum PictureInPicture {
    static weak var layer: AVPlayerLayer?
    private static var controller: AVPictureInPictureController?

    static var isAvailable: Bool { AVPictureInPictureController.isPictureInPictureSupported() && layer != nil }

    static func start() {
        guard let layer, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        if controller?.playerLayer !== layer { controller = AVPictureInPictureController(playerLayer: layer) }
        controller?.startPictureInPicture()
    }
}
