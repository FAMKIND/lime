import SwiftUI

/// The pieces both call screens' headers share (LIME-147): the 1:1 call's header (118b/119) is the model, and the group call takes the same
/// look from the same views: a glass pill (picture, name, ›) with, under it, the timer and the encryption chip. Always on a dark picture.

/// The pill at the top left: the picture, the name and a ›. Tapping it opens the details.
struct CallNamePill<Picture: View>: View {
    let name: String
    /// A group call: how many people are in it, at the end of the pill (the names truncate, this never does).
    var count: Int?
    let accessibilityLabel: String
    let picture: Picture
    let action: () -> Void

    init(name: String, count: Int? = nil, accessibilityLabel: String, action: @escaping () -> Void, @ViewBuilder picture: () -> Picture) {
        self.name = name
        self.count = count
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.picture = picture()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                picture
                Text(name).font(Theme.font(.headline, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                if let count {
                    Text("\(count)").font(Theme.font(.headline, weight: .semibold)).foregroundStyle(.white.opacity(0.85)).fixedSize().layoutPriority(1)
                        .accessibilityIdentifier("call-name-pill-count")
                }
                Image(systemName: "chevron.right").font(Theme.font(.caption, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
            }
            .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 6)
            .background(.black.opacity(0.35), in: Capsule())
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("call-name-pill")
    }
}

/// The lock and the four emoji (tap: how to check them). In a group call, while someone's key has not arrived there are no emoji: the chip says so.
struct CallEmojiChip: View {
    let emoji: [CallEmoji]
    /// A group call that does not yet hold everyone's key.
    var waiting = false
    let spokenPrefix: String
    let hint: String
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if waiting {
            HStack(spacing: 5) {
                Image(systemName: "lock.fill").font(Theme.font(.caption2))
                Text("Waiting for everyone\u{2019}s keys\u{2026}").font(Theme.font(.footnote)).lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 10).frame(minHeight: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Waiting for everyone\u{2019}s keys")
            .accessibilityIdentifier("call-emoji-waiting")
        } else if !emoji.isEmpty {
            Button(action: action) {
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill").font(Theme.font(.caption2))
                    // The same order, left to right, for everyone (so they compare the same way), whatever the language.
                    HStack(spacing: 2) { ForEach(Array(emoji.enumerated()), id: \.offset) { Text($1.emoji).font(Theme.font(.callout)) } }
                        .environment(\.layoutDirection, .leftToRight)
                        .id(emoji.map(\.emoji).joined())
                        .transition(.opacity)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10).frame(minHeight: 44)
                .contentShape(Rectangle())
                // A brief fade when the four change (none with Reduce Motion).
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: emoji.map(\.emoji))
            }
            .accessibilityLabel("\(spokenPrefix) Emoji: \(emoji.map(\.name).joined(separator: ", "))")
            .accessibilityHint(hint)
            .accessibilityIdentifier("call-emoji")
        }
    }
}

/// The sheet that explains the four emoji: the emoji large, what they prove, and what they do not.
struct CallEmojiSheet: View {
    let emoji: [CallEmoji]
    let explanation: String
    var changeNote: String?
    let footnote: String
    var height: CGFloat = 380

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill").font(Theme.font(.title2)).foregroundStyle(.white.opacity(0.8)).padding(.top, 28).accessibilityHidden(true)
            HStack(spacing: 14) {
                ForEach(Array(emoji.enumerated()), id: \.offset) { Text($1.emoji).font(.system(size: 52)) }
            }
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Emoji: \(emoji.map(\.name).joined(separator: ", "))")
            .accessibilityIdentifier("call-emoji-large")
            Text(explanation)
                .font(Theme.font(.body)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.9))
                .accessibilityIdentifier("call-emoji-explanation")
            if let changeNote {
                Text(changeNote).font(Theme.font(.callout)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.9))
                    .accessibilityIdentifier("call-emoji-change-note")
            }
            Text(footnote)
                .font(Theme.font(.footnote)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.6))
            Spacer()
        }
        .padding(.horizontal, 24)
        .presentationDetents([.height(height)])
        // (An identifier on the container would replace the children's own.)
        .background(Color.clear.accessibilityIdentifier("call-emoji-sheet"))
    }
}
