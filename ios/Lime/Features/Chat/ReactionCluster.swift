import SwiftUI

/// Where the reaction circles go (LIME-278c): one round chip per emoji, attached to the bubble's bottom edge and flowing from its inner corner toward the middle of
/// the screen, onto a second line if they would run off it, and along the bubble itself when the bubble is too wide to leave room. Pure numbers, so it is tested.
enum ReactionPlan {
    static let chip: CGFloat = 30
    /// How far neighbours overlap.
    static let overlap: CGFloat = 7
    static let rowGap: CGFloat = 4
    static let margin: CGFloat = 16
    /// The left edge of an incoming bubble (the avatar column sits before it).
    static let incomingLeading: CGFloat = 64
    static let maxShown = 6

    enum Flow: Equatable { case middle, along }

    /// How many chips fit in `room` points.
    static func perRow(room: CGFloat) -> Int { max(1, Int((room - chip) / (chip - overlap)) + 1) }

    /// How many circles show for `kinds` emoji: up to six, then one "+N" circle for the rest.
    static func circles(kinds: Int) -> Int { kinds > maxShown ? maxShown + 1 : kinds }

    struct Layout: Equatable { var flow: Flow; var perRow: Int; var rows: Int }

    static func layout(circles: Int, bubbleWidth: CGFloat, own: Bool, screenWidth: CGFloat) -> Layout {
        // Toward the middle: from 16 pt inside the bubble's inner corner to the screen's margin.
        let middleRoom = own ? screenWidth - margin - bubbleWidth : screenWidth - incomingLeading - bubbleWidth
        let alongRoom = bubbleWidth - 16
        let mid = perRow(room: middleRoom + 0), along = perRow(room: alongRoom)
        let flow: Flow = mid >= circles || mid >= along ? .middle : .along
        let per = max(1, flow == .middle ? mid : along)
        return Layout(flow: flow, perRow: per, rows: (circles + per - 1) / max(1, per))
    }

    /// The room under the bubble the circles take: half a circle overlaps the bubble, the rest hangs below, and each more row adds its height.
    static func hang(rows: Int) -> CGFloat { chip / 2 + 2 + CGFloat(max(0, rows - 1)) * (chip + rowGap) }
}

/// Puts the chips by [`ReactionPlan`]: its proposal is the bubble's size, and it places the circles from the bubble's bottom corner, outside its bounds when it
/// has to (an overlay does not clip).
struct ReactionFlow: Layout {
    var own: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let plan = ReactionPlan.layout(circles: subviews.count, bubbleWidth: bounds.width, own: own, screenWidth: UIScreen.main.bounds.width)
        let step = ReactionPlan.chip - ReactionPlan.overlap
        for (index, view) in subviews.enumerated() {
            let row = index / plan.perRow, column = index % plan.perRow
            let y = bounds.maxY - ReactionPlan.chip / 2 + CGFloat(row) * (ReactionPlan.chip + ReactionPlan.rowGap)
            let x: CGFloat
            switch (plan.flow, own) {
            case (.middle, true): x = bounds.minX + 16 - ReactionPlan.chip - CGFloat(column) * step
            case (.middle, false): x = bounds.maxX - 16 + CGFloat(column) * step
            case (.along, true): x = bounds.minX + 8 + CGFloat(column) * step
            case (.along, false): x = bounds.maxX - 8 - ReactionPlan.chip - CGFloat(column) * step
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: ReactionPlan.chip, height: ReactionPlan.chip))
            _ = row
        }
    }
}

/// One round reaction: the emoji in a circle, mine filled with the accent, the count as a tiny badge on the lower edge when more than one person used it.
struct ReactionCircle: View {
    let chip: ReactionChip
    let messageID: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(chip.emoji).font(.system(size: 16))
                .frame(width: ReactionPlan.chip, height: ReactionPlan.chip)
                .background(chip.mine ? Theme.accent : Theme.chipFill, in: Circle())
                .overlay(Circle().strokeBorder(chip.mine ? Color.clear : Theme.hairline, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                .overlay(alignment: .bottomTrailing) {
                    if chip.count > 1 {
                        Text("\(chip.count)").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.text)
                            .frame(minWidth: 16, minHeight: 16).padding(.horizontal, 2)
                            .background(Theme.canvas, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
                            .offset(x: 5, y: 5)
                    }
                }
                .contentShape(Circle().inset(by: -4))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(chip.emoji), \(chip.count) \(chip.count == 1 ? "person" : "people")\(chip.mine ? ", including you" : "")")
        .accessibilityHint("Double-tap to see who")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("reaction-chip-\(messageID)-\(chip.emoji)")
    }
}

/// The circles on one message: up to six, then "+N".
struct ReactionCluster: View {
    let reactions: [ReactionChip]
    let messageID: String
    let own: Bool
    let onTap: () -> Void

    var body: some View {
        let shown = Array(reactions.prefix(ReactionPlan.maxShown))
        let more = reactions.count - shown.count
        ReactionFlow(own: own) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, chip in
                ReactionCircle(chip: chip, messageID: messageID, onTap: onTap).zIndex(Double(shown.count - index))
            }
            if more > 0 {
                Button(action: onTap) {
                    Text("+\(more)").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.text)
                        .frame(width: ReactionPlan.chip, height: ReactionPlan.chip)
                        .background(Theme.chipFill, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(more) more reactions").accessibilityHint("Double-tap to see who")
                .accessibilityIdentifier("reaction-more-\(messageID)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reaction-cluster-\(messageID)")
    }
}
