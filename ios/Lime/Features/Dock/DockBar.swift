import SwiftUI

/// The floating bottom dock: link, jam, call. Only "link" (Messages) does anything yet.
struct DockBar: View {
    @Environment(ConversationStore.self) private var store

    private struct Item: Identifiable {
        let id: String
        let symbol: String
        let badge: Int?
    }

    private let items = [
        Item(id: "link", symbol: "bubble.left", badge: 5),
        Item(id: "jam", symbol: "book", badge: nil),
        Item(id: "call", symbol: "phone", badge: nil),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                Button {
                    if item.id != "link" { store.comingSoon(item.id.capitalized) }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 22))
                            .overlay(alignment: .topTrailing) {
                                if let badge = item.badge {
                                    Text("\(badge)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Theme.accentInk)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Theme.accent, in: Capsule())
                                        .offset(x: 12, y: -8)
                                }
                            }
                        Text(item.id)
                            .font(.caption)
                    }
                    .foregroundStyle(Theme.text)
                    .frame(minWidth: 72, minHeight: 56)
                    .background {
                        if item.id == "link" { Capsule().fill(Theme.text.opacity(0.07)) }
                    }
                }
                .accessibilityLabel(item.id == "link" ? "link, selected, \(item.badge ?? 0) unread" : item.id)
                .accessibilityAddTraits(item.id == "link" ? .isSelected : [])
            }
        }
        .padding(6)
        .limeGlass()
    }
}
