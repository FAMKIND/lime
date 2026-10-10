import SwiftUI

struct AvatarView: View {
    let person: Person
    var size: CGFloat = 52
    /// Shows the person's status badge at the bottom-right (for a contact who shared one, or me).
    var showsStatus = false

    var body: some View {
        content.statusBadge(showsStatus ? person.id : nil, size: size)
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
            let members = conversation.members
            let shown = members.count > 4 ? Array(members.prefix(3)) : Array(members.prefix(4))
            let extra = members.count - shown.count
            let d = size * 0.52
            let o = size * 0.24
            ZStack {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, person in
                    AvatarView(person: person, size: d)
                        .offset(x: index % 2 == 0 ? -o : o, y: index < 2 ? -o : o)
                }
                if extra > 0 {
                    Circle().fill(Theme.surface).frame(width: d, height: d)
                        .overlay(Text("+\(extra)").font(.system(size: d * 0.38, weight: .medium)).foregroundStyle(Theme.text))
                        .offset(x: o, y: o)
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }
}
