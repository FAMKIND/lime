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

    var body: some View {
        Group {
            if let jam {
                ZStack(alignment: .bottomTrailing) {
                    JamInitialTile(title: jam, size: size)
                    if let first = people.first {
                        AvatarView(person: first, size: size * 0.5)
                            .overlay(Circle().stroke(Theme.canvas, lineWidth: 2))
                            .offset(x: size * 0.12, y: size * 0.12)
                    }
                }
                .frame(width: size, height: size)
            } else if people.count > 1 {
                let shown = Array(people.prefix(3))
                let each = size * 0.7
                HStack(spacing: -each * 0.4) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { index, person in
                        AvatarView(person: person, size: each)
                            .overlay(Circle().stroke(Theme.canvas, lineWidth: 2))
                            .zIndex(Double(shown.count - index))
                    }
                    if people.count > shown.count {
                        Text("+\(people.count - shown.count)").font(.system(size: each * 0.36, weight: .semibold)).foregroundStyle(Theme.text)
                            .frame(width: each, height: each).background(Theme.surface, in: Circle()).overlay(Circle().stroke(Theme.canvas, lineWidth: 2))
                    }
                }
                .frame(height: size)
            } else if let person = people.first {
                AvatarView(person: person, size: size)
            } else {
                Color.clear.frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}
