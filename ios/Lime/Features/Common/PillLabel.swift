import SwiftUI

/// The label of an icon-and-words pill button (LIME-277g). It never breaks a word: on one line at the pill's width; if the words do not fit (a wide font, a big
/// text size, three pills sharing a row) the icon goes above a smaller one-line label, and if even that does not fit it is the icon alone (VoiceOver still says
/// the words).
struct PillLabel: View {
    let symbol: String
    let title: String
    var weight: Font.Weight = .semibold

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Label(title, systemImage: symbol)
                .font(Theme.font(.subheadline, weight: weight)).lineLimit(1).minimumScaleFactor(0.85)
                .fixedSize(horizontal: true, vertical: false)
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                Text(title).font(Theme.font(.caption2, weight: weight)).lineLimit(1).minimumScaleFactor(0.8).fixedSize(horizontal: true, vertical: false)
            }
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
        }
        .foregroundStyle(Theme.text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}
