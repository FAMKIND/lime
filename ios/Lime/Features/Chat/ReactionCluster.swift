import SwiftUI

/// Where the reaction circles go (LIME-278d): one round chip per emoji, attached to the bubble's bottom edge. **One rule for every count:** the first circle is at the
/// bubble's inner bottom corner (the one facing the middle of the screen) and the others are added **toward the sender's side**, so they never reach into the middle of the
/// screen; at the bubble's outer edge they wrap onto a second line, in the same direction. Pure numbers, so it is tested.
enum ReactionPlan {
    static let chip: CGFloat = 30
    /// How far neighbours overlap.
    static let overlap: CGFloat = 7
    static let rowGap: CGFloat = 4
    /// A row may hang this far past the bubble's outer edge (a small bubble would otherwise hold one circle), which stays on the screen.
    static let outerOverhang: CGFloat = 15
    /// Where the first circle starts, in from the inner edge.
    static let inset: CGFloat = 2
    static let maxShown = 6

    /// How many chips fit in `room` points.
    static func perRow(room: CGFloat) -> Int { max(1, Int((room - chip) / (chip - overlap)) + 1) }

    /// How many circles show for `kinds` emoji: up to six, then one "+N" circle for the rest.
    static func circles(kinds: Int) -> Int { kinds > maxShown ? maxShown + 1 : kinds }

    struct Layout: Equatable { var perRow: Int; var rows: Int }

    static func layout(circles: Int, bubbleWidth: CGFloat) -> Layout {
        // Never fewer than two to a row (a tiny bubble such as "hi" would otherwise stack them), which hangs a little past its outer edge.
        let per = max(2, perRow(room: bubbleWidth - inset + outerOverhang))
        return Layout(perRow: per, rows: (circles + per - 1) / per)
    }

    /// The left edge of circle `index` on a bubble `bubbleWidth` wide (0 at the bubble's left edge): mine start at the left corner and go right, theirs start at the
    /// right corner and go left.
    static func x(index: Int, bubbleWidth: CGFloat, own: Bool, perRow: Int) -> CGFloat {
        let column = CGFloat(index % perRow)
        return own ? inset + column * (chip - overlap) : bubbleWidth - inset - chip - column * (chip - overlap)
    }

    /// The room under the bubble the circles take: half a circle overlaps the bubble, the rest hangs below, and each more row adds its height.
    static func hang(rows: Int) -> CGFloat { chip / 2 + 2 + CGFloat(max(0, rows - 1)) * (chip + rowGap) }
}

/// Puts the chips by [`ReactionPlan`]: its proposal is the bubble's size, and it places the circles from the bubble's bottom corner (an overlay does not clip).
struct ReactionFlow: Layout {
    var own: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let plan = ReactionPlan.layout(circles: subviews.count, bubbleWidth: bounds.width)
        for (index, view) in subviews.enumerated() {
            let row = index / plan.perRow
            let y = bounds.maxY - ReactionPlan.chip / 2 + CGFloat(row) * (ReactionPlan.chip + ReactionPlan.rowGap)
            let x = bounds.minX + ReactionPlan.x(index: index, bubbleWidth: bounds.width, own: own, perRow: plan.perRow)
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: ReactionPlan.chip, height: ReactionPlan.chip))
        }
    }
}

/// One round reaction: the emoji in a circle, mine filled with the accent, the count as a tiny badge on the lower edge when more than one person used it.
struct ReactionCircle: View {
    let chip: ReactionChip
    let messageID: String
    let onTap: () -> Void
    /// The emoji and the count grow with the text size (the circle keeps its size, so the layout of the row does not change).
    @ScaledMetric(relativeTo: .body) private var emojiSize: CGFloat = 16
    /// Mine is the accent fill alone; with Differentiate Without Color it also gets a ring, so it does not rest on colour (LIME-130-3a, 331).
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        Button(action: onTap) {
            Text(chip.emoji).font(.system(size: min(emojiSize, 22)))
                .frame(width: ReactionPlan.chip, height: ReactionPlan.chip)
                .background(chip.mine ? Theme.accent : Theme.chipFill, in: Circle())
                .overlay { if !chip.mine { Circle().strokeBorder(Theme.hairline, lineWidth: 0.5) } else if differentiateWithoutColor { Circle().strokeBorder(Theme.text, lineWidth: 1.5) } }
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                .overlay(alignment: .bottomTrailing) {
                    if chip.count > 1 {
                        Text("\(chip.count)").font(.caption2.weight(.bold)).foregroundStyle(Theme.text)
                            .frame(minWidth: 16, minHeight: 16).padding(.horizontal, 2)
                            .background(Theme.canvas, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
                            .offset(x: 5, y: 5)
                    }
                }
                // A 44 pt target around the 30 pt circle (the next circle's own area wins where they meet).
                .frame(width: 44, height: 44).contentShape(Rectangle())
                .frame(width: ReactionPlan.chip, height: ReactionPlan.chip)
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
                    Text("+\(more)").font(.caption.weight(.bold)).minimumScaleFactor(0.6).foregroundStyle(Theme.text)
                        .frame(width: ReactionPlan.chip, height: ReactionPlan.chip)
                        .background(Theme.chipFill, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.5))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                        .frame(width: ReactionPlan.chip, height: ReactionPlan.chip)
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
