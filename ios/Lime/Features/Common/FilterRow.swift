import SwiftUI

/// The first row of a list tab (LIME-124): a segmented control and, beside it, a round glass filter button with the outline filter
/// symbol and a lime badge with the number of filters on. It scrolls away with the list.
struct FilterRow<MenuContent: View>: View {
    /// The segments' names, and the chosen one's index. Two for calls and messages; jam has three (LIME-188v).
    let titles: [String]
    @Binding var selection: Int
    let activeCount: Int
    var idPrefix = "filter"
    @ViewBuilder let menu: () -> MenuContent

    /// The usual two segments, the second one a Bool.
    init(first: String, second: String, secondSelected: Binding<Bool>, activeCount: Int, idPrefix: String = "filter", @ViewBuilder menu: @escaping () -> MenuContent) {
        titles = [first, second]
        _selection = Binding(get: { secondSelected.wrappedValue ? 1 : 0 }, set: { secondSelected.wrappedValue = $0 == 1 })
        self.activeCount = activeCount
        self.idPrefix = idPrefix
        self.menu = menu
    }

    init(titles: [String], selection: Binding<Int>, activeCount: Int, idPrefix: String = "filter", @ViewBuilder menu: @escaping () -> MenuContent) {
        self.titles = titles
        _selection = selection
        self.activeCount = activeCount
        self.idPrefix = idPrefix
        self.menu = menu
    }

    var body: some View {
        HStack(spacing: 10) {
            Picker("Show", selection: $selection) {
                ForEach(Array(titles.enumerated()), id: \.offset) { index, title in Text(title).tag(index) }
            }
            .pickerStyle(.segmented)
            // More segments take what the row has left beside the filter button (a 320 pt phone has about 232 pt).
            .frame(maxWidth: titles.count > 2 ? 300 : 220)
            .accessibilityIdentifier("\(idPrefix)-segments")
            Menu { menu() } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 17, weight: .regular)).foregroundStyle(Theme.text)
                    .frame(width: 40, height: 40)
                    .limeGlass(in: Circle())
                    .overlay(alignment: .topTrailing) {
                        if activeCount > 0 {
                            CountBadge(count: activeCount, size: 16, font: .caption2.weight(.semibold))
                                .offset(x: 4, y: -4)
                                .accessibilityHidden(true)
                                .accessibilityIdentifier("\(idPrefix)-badge")
                        }
                    }
                    // Room around the button so the badge, which hangs off its corner, is inside the menu's and the row's bounds on the first frame.
                    .padding(.top, 6).padding(.trailing, 6)
            }
            .accessibilityLabel(activeCount == 0 ? "Filter" : "Filter, \(activeCount) active")
            .accessibilityValue(activeCount == 0 ? "" : "\(activeCount)")
            .accessibilityIdentifier("\(idPrefix)-button")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 0).padding(.bottom, 2)
    }
}

/// "No chats match" / "No calls match" with a Clear filters button.
struct FilteredEmpty: View {
    let text: String
    let clear: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(text).font(Theme.body).foregroundStyle(Theme.textSecondary)
            Button(action: clear) {
                Text("Clear filters").font(Theme.title).foregroundStyle(Theme.text)
                    .padding(.horizontal, 22).frame(minHeight: 44).background(Theme.surface, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("filter-clear-empty")
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }
}
