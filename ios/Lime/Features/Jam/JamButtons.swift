import SwiftUI

/// A button's colours (LIME-188q): a few named palette colours, each with a light and a dark variant chosen so the label reads at 4.5:1 or better on
/// its fill in both (a unit test computes every pair). Lime green is the default; there is no free colour picker, which could not promise contrast.
enum ButtonPalette: String, CaseIterable, Identifiable {
    case lime, ink, blue, purple, orange, red
    var id: String { rawValue }

    var title: String {
        switch self {
        case .lime: "Lime"
        case .ink: "Ink"
        case .blue: "Blue"
        case .purple: "Purple"
        case .orange: "Orange"
        case .red: "Red"
        }
    }

    /// (fill, label) as sRGB hex, light then dark.
    var light: (fill: UInt32, label: UInt32) {
        switch self {
        case .lime: (0xA5E27B, 0x10200F)
        case .ink: (0x1F2420, 0xFFFFFF)
        case .blue: (0x1F5FBF, 0xFFFFFF)
        case .purple: (0x6B3FB0, 0xFFFFFF)
        case .orange: (0xFFB347, 0x2B1700)
        case .red: (0xB3261E, 0xFFFFFF)
        }
    }

    var dark: (fill: UInt32, label: UInt32) {
        switch self {
        case .lime: (0xA5E27B, 0x10200F)
        case .ink: (0xF1EFE8, 0x161B18)
        case .blue: (0x9CC2FF, 0x0B1F3F)
        case .purple: (0xCDB4F5, 0x251046)
        case .orange: (0xFFC46B, 0x2B1700)
        case .red: (0xFFB4AB, 0x410002)
        }
    }

    /// The palette colour for a name in a post (nil or unknown: lime).
    static func named(_ name: String) -> ButtonPalette { ButtonPalette(rawValue: name) ?? .lime }

    private func dynamic(label: Bool) -> Color {
        Color(UIColor { trait in
            let pair = trait.userInterfaceStyle == .dark ? self.dark : self.light
            let hex = label ? pair.label : pair.fill
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }

    var fill: Color { dynamic(label: false) }
    var labelColor: Color { dynamic(label: true) }
}

/// What a button does. An address that starts with `lime:` is an action inside lime; anything else is a web address.
enum ButtonAction: Equatable {
    case subscribe, share, message, comment
    case link(String)

    init(url: String) {
        switch url {
        case "lime:subscribe": self = .subscribe
        case "lime:share": self = .share
        case "lime:message": self = .message
        case "lime:comment": self = .comment
        default: self = .link(url)
        }
    }

    var address: String {
        switch self {
        case .subscribe: "lime:subscribe"
        case .share: "lime:share"
        case .message: "lime:message"
        case .comment: "lime:comment"
        case .link(let url): url
        }
    }
}
