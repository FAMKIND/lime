import SwiftUI

/// "Part 1 of 2 · Sunrise" (LIME-243): where a card says it is part of a series. A tap opens the series page. `onScrim` is white for the article cover; `inPlayer`
/// closes the player first.
struct SeriesTag: View {
    let post: JamPostInfo
    var onScrim = false
    var action: (() -> Void)? = nil
    @Environment(ConversationStore.self) private var store

    var body: some View {
        if let series = post.series {
            Button { if let action { action() } else { store.jamPath.append(SeriesRoute(seriesID: series.id)) } } label: {
                Text("\(series.partLabel) \u{00B7} \(series.title)").font(Theme.caption).foregroundStyle(onScrim ? Color.white.opacity(0.9) : Theme.textSecondary).lineLimit(1).frame(minHeight: 28, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(series.partLabel) of the series \(series.title)").accessibilityHint("Opens the series").accessibilityIdentifier("jam-card-series-\(post.postId)")
        }
    }
}

/// A soft shimmer over placeholder blocks while content is on its way; still with Reduce Motion (LIME-243).
private struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, Color.white.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.6).offset(x: phase * geo.size.width * 1.4)
                    }
                    .clipped().allowsHitTesting(false)
                }
            }
            .onAppear { if !reduceMotion { withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 } } }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

/// A grey block, rounded.
struct SkeletonBlock: View {
    var height: CGFloat
    var width: CGFloat? = nil
    var radius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.surface).frame(width: width, height: height).frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// A post card that is coming: the avatar, the name and date, a cover and two lines (the shape of an article card).
struct PostCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle().fill(Theme.surface).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 6) { SkeletonBlock(height: 12, width: 130); SkeletonBlock(height: 10, width: 90) }
            }
            SkeletonBlock(height: 200, radius: 18)
            SkeletonBlock(height: 12)
            SkeletonBlock(height: 12, width: 220)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .shimmering()
        .accessibilityHidden(true)
    }
}

/// A few skeleton cards, spoken as one "Loading".
struct SkeletonFeed: View {
    var count = 3
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in PostCardSkeleton(); Divider().overlay(Theme.hairline) }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("Loading").accessibilityIdentifier("skeleton-feed")
        .overlay { Color.clear.accessibilityHidden(true) }
    }
}

/// The lines of a post page that is coming.
struct PostPageSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SkeletonBlock(height: 12, width: 110)
            SkeletonBlock(height: 28)
            SkeletonBlock(height: 28, width: 240)
            HStack(spacing: 10) { Circle().fill(Theme.surface).frame(width: 36, height: 36); SkeletonBlock(height: 12, width: 140) }
            SkeletonBlock(height: 200, radius: 18)
            ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 12) }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .shimmering()
        .accessibilityElement(children: .ignore).accessibilityLabel("Loading").accessibilityIdentifier("skeleton-page")
    }
}
