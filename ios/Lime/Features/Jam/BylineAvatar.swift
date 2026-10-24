import SwiftUI

/// Who a post is by, as words (LIME-188w): "Shem Rajoon", "Shem Rajoon & Jean Chung", "Shem Rajoon, Jean Chung & Lee Wong", and when it is posted as a
/// jam "Conscious collective · Shem Rajoon". `authors` has the writer first, then the co-authors who accepted.
enum Byline {
    static func text(jam: String?, authors: [String]) -> String {
        let names: String
        switch authors.count {
        case 0: names = ""
        case 1: names = authors[0]
        default: names = authors.dropLast().joined(separator: ", ") + " & " + (authors.last ?? "")
        }
        guard let jam, !jam.isEmpty else { return names }
        return names.isEmpty ? jam : "\(jam) \u{00B7} \(names)"
    }
}

extension ConversationStore {
    /// The writer, then the co-authors who accepted.
    func bylinePeople(_ post: JamPostInfo) -> [Person] { ([post.author] + post.coauthors).map { teacher($0) } }

    /// The post's byline in words (see `Byline`).
    func bylineText(_ post: JamPostInfo) -> String {
        Byline.text(jam: post.displayAs == "jam" ? jamTitle(post.jamId) : nil, authors: bylinePeople(post).map(\.name))
    }
}

/// The one picture for a byline: a person is a circle; people together are up to three overlapping circles and "+N"; a jam (or, later, an
/// organisation) is a rounded square, with the writer's circle over its lower-right corner. Decorative: the words carry the meaning.
struct BylineAvatar: View {
    let people: [Person]
    /// The jam's name when the post is shown as the jam.
    var jam: String?
    var size: CGFloat = 40
    /// For the writer only: people asked to be co-authors who have not answered, drawn dimmed (LIME-215).
    var pending: [Person] = []

    var body: some View {
        Group {
            if let jam {
                // The org's rounded-square tile with the writer and each co-author as small overlapping circles at its bottom right (up to 3, then "+n").
                ZStack(alignment: .bottomTrailing) {
                    JamInitialTile(title: jam, size: size)
                    let crew = people.map { ($0, false) } + pending.map { ($0, true) }
                    let shown = Array(crew.prefix(3))
                    let small = size * (crew.count > 1 ? 0.42 : 0.5)
                    HStack(spacing: -small * 0.4) {
                        ForEach(Array(shown.enumerated()), id: \.offset) { index, entry in
                            AvatarView(person: entry.0, size: small).opacity(entry.1 ? 0.45 : 1)
                                .overlay(Circle().stroke(Theme.canvas, lineWidth: 1.5))
                                .zIndex(Double(shown.count - index))
                        }
                        if crew.count > shown.count {
                            Text("+\(crew.count - shown.count)").font(.system(size: small * 0.36, weight: .semibold)).foregroundStyle(Theme.text)
                                .frame(width: small, height: small).background(Theme.surface, in: Circle()).overlay(Circle().stroke(Theme.canvas, lineWidth: 1.5))
                        }
                    }
                    .offset(x: size * 0.14, y: size * 0.12)
                }
                .frame(width: size, height: size)
            } else if people.count > 1, let writer = people.first {
                // Co-authors, drawn the way link draws a group's picture (LIME-215).
                GroupCircles(plan: GroupAvatarPlan.make(others: Array(people.dropFirst()), me: writer), size: size)
            } else if let person = people.first {
                AvatarView(person: person, size: size)
            } else {
                Color.clear.frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}
