import SwiftUI

/// The green "+" at the bottom right of a tab's root (New message on link, New call on call): 64 pt, glass you can faintly see the list
/// through. On a screen wide enough to leave 64 pt beside the glass tab bar it sits beside it, centred on it; otherwise it floats just
/// above the bar at the right. It never overlaps the bar.
struct FloatingPlus: View {
    let label: String
    let id: String
    let action: () -> Void
    /// A long-press (LIME-143: emergency mode starts here). Nil: none.
    var onLongPress: (() -> Void)? = nil
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    static let size: CGFloat = 64

    /// Whether 64 pt fits beside the iOS 26 tab bar platter (about 282 pt wide, centred) with an 8 pt margin each side.
    static func fitsBesideBar(width: CGFloat) -> Bool { width / 2 - 141 >= size + 16 }

    var body: some View {
        GeometryReader { geo in
            if #available(iOS 26, *), Self.fitsBesideBar(width: geo.size.width), verticalSizeClass != .compact {
                // Beside the platter: its centre line is 52 pt above the screen's bottom edge (measured on the 13 mini and 18 Pro).
                button.position(x: geo.size.width - 8 - Self.size / 2, y: geo.size.height + geo.safeAreaInsets.bottom - 52)
            } else {
                button.position(x: geo.size.width - 16 - Self.size / 2, y: geo.size.height - 14 - Self.size / 2)
            }
        }
    }

    private var button: some View {
        let glyph = Image(systemName: "plus").font(.system(size: 26, weight: .regular)).foregroundStyle(Theme.accentInk)
        return Button(action: action) {
            if #available(iOS 26, *) {
                // A tint at about 55 % so the list shows faintly through it while the green still reads.
                glyph.frame(width: Self.size, height: Self.size)
                    .glassEffect(.regular.tint(Theme.accent.opacity(0.55)).interactive(), in: Circle())
            } else {
                glyph.frame(width: Self.size, height: Self.size)
                    .background(Circle().fill(.ultraThinMaterial))
                    .background(Theme.accent.opacity(0.75), in: Circle())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            }
        }
        .buttonStyle(.plain)
        // A long-press opens the native menu (with its haptic); a plain tap still starts a message. (A long-press gesture on a Button loses to the tap.)
        .contextMenu {
            if let onLongPress {
                Button(role: .destructive, action: onLongPress) { Label("Emergency", systemImage: "exclamationmark.triangle") }
                    .accessibilityIdentifier("plus-emergency")
            }
        }
        .accessibilityLabel(label)
        .accessibilityAction(named: "Emergency") { onLongPress?() }
        .accessibilityIdentifier(id)
    }
}
