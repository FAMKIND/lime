import SwiftUI

/// My private label beside a name, as a small capsule. The name always has priority: it keeps its one line, and the label is
/// what truncates (down to an ellipsis) when there is no room. Use with `.lineLimit(1)` and a higher `layoutPriority` on the name.
struct LabelCapsule: View {
    let text: String
    var id: String?

    var body: some View {
        Text(text)
            .accessibilityIdentifier(id ?? "label-capsule")
            .font(Theme.caption)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 7).padding(.vertical, 1)
            .background(Theme.surface, in: Capsule())
            .layoutPriority(0)
    }
}
