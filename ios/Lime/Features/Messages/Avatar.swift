import SwiftUI

struct AvatarView: View {
    let person: Person
    var size: CGFloat = 52
    /// Shows the person's status badge at the bottom-right (for a contact who shared one, or me).
    var showsStatus = false
    /// For a toolbar button (iOS 26 paints its label one colour): the badge keeps its own colours.
    var badgeKeepsColours = false

    var body: some View {
        content.statusBadge(showsStatus ? person.id : nil, size: size, keepsColours: badgeKeepsColours)
    }

    @ViewBuilder
    private var content: some View {
        if let photo = AvatarCache.shared.image(for: person.id) {
            Image(uiImage: photo)
                .resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .accessibilityHidden(true)
        } else {
            initials
        }
    }

    private var initials: some View {
        Circle()
            .fill(Theme.avatar(person.tone))
            .frame(width: size, height: size)
            .overlay(
                Text(person.initials)
                    .font(.system(size: size * 0.36, weight: .medium))
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Color(red: 0.075, green: 0.106, blue: 0.09))
            )
            .accessibilityHidden(true)
    }
}

/// One avatar for a DM; a 2x2 cluster for a group (the last slot is "+N" when there are more).
struct ConversationAvatar: View {
    let conversation: Conversation
    var size: CGFloat = 52

    var body: some View {
        if let only = conversation.members.first, !conversation.isGroup {
            AvatarView(person: only, size: size, showsStatus: true)
        } else if let photo = AvatarCache.shared.image(for: conversation.id) {
            Image(uiImage: photo).resizable().scaledToFill()
                .frame(width: size, height: size).clipShape(Circle())
                .accessibilityHidden(true)
        } else if let emoji = conversation.emoji {
            Circle().fill(Theme.surface)
                .frame(width: size, height: size)
                .overlay(Text(emoji).font(.system(size: size * 0.5)))
                .accessibilityHidden(true)
        } else {
            plan
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    @Environment(ConversationStore.self) private var store: ConversationStore?

    /// The members' composite, including me (LIME-150, LIME-152b): overlapping circles with thin rings (two, a triangle, a circle of four).
    @ViewBuilder
    private var plan: some View {
        let me = store?.meProvider() ?? SampleData.me
        switch GroupAvatarPlan.make(others: conversation.members, me: me) {
        case .single(let person):
            AvatarView(person: person, size: size)
        case .pair(let front, let back):
            circles([.person(back), .person(front)])
        case .triangle(let people):
            circles(people.map { .person($0) })
        case .ring(let shown, let extra):
            circles(shown.map { .person($0) } + (extra > 0 ? [.more(extra)] : []))
        }
    }

    private enum Item { case person(Person), more(Int) }

    private func circles(_ items: [Item]) -> some View {
        let spots = GroupAvatarPlan.spots(circles: items.count)
        let d = size * spots.diameter
        return ZStack {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let at = spots.centres[min(index, spots.centres.count - 1)]
                Group {
                    switch item {
                    case .person(let person): AvatarView(person: person, size: d)
                    case .more(let extra):
                        Circle().fill(Theme.surface).frame(width: d, height: d)
                            .overlay(Text("+\(extra)").font(.system(size: d * 0.38, weight: .medium)).foregroundStyle(Theme.text))
                    }
                }
                .overlay(Circle().strokeBorder(Theme.canvas, lineWidth: GroupAvatarPlan.ringWidth(side: size)))
                .offset(x: size * at.x, y: size * at.y)
            }
        }
    }
}
