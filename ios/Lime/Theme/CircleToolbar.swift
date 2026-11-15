import SwiftUI

extension View {
    /// A single-icon toolbar button as its own 44 pt glass circle (LIME-247c). `fixedSize` first, or the toolbar shrinks the label to 36 pt.
    func limeCircleIcon() -> some View {
        fixedSize().frame(width: 44, height: 44).contentShape(Circle()).limeGlass(in: Circle())
    }
}

/// One single-icon toolbar button: on iOS 26 the system's shared capsule background is hidden and the icon sits in a circle of our own glass;
/// before that it is the plain system item. Words ("Edit", "Done", "Cancel") stay system capsules; every icon uses this so the circles can't drift.
struct CircleToolbarItem<Content: View>: ToolbarContent {
    var placement: ToolbarItemPlacement = .topBarTrailing
    @ViewBuilder var content: Content

    var body: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarItem(placement: placement) { content.limeCircleIcon() }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: placement) { content }
        }
    }
}

/// Our own ‹ (LIME-247c): the system's is heavier than the icons beside it. It hides the system back button, puts a 44 pt glass circle with a
/// regular-weight `chevron.left` at the left, and turns the edge-swipe back on again (hiding the system button turns it off).
/// `showsBack` is false while a screen puts its own ‹ there (a profile being edited).
@available(iOS 26, *)
private struct LimeBackModifier: ViewModifier {
    let showsBack: Bool
    /// A chat's Back shows how many unread messages wait in the other chats beside the chevron (LIME-325, 331, 334); 0: the plain circle.
    let unread: Int
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .limeTopFade()
            .navigationBarBackButtonHidden(true)
            .swipeBackEnabled()
            .toolbar {
                if showsBack {
                    if unread > 0 {
                        // The chevron and the number in one glass capsule, 44 pt high (the circle widens only when there is a number).
                        ToolbarItem(placement: .topBarLeading) {
                            Button { dismiss() } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left").font(.system(size: 18)).foregroundStyle(Theme.text)
                                    CountBadge(count: unread)
                                }
                                .padding(.horizontal, 12).frame(minWidth: 44, minHeight: 44)
                                .fixedSize().contentShape(Capsule()).limeGlass(in: Capsule())
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Back")
                            .accessibilityValue(unread == 1 ? "1 unread message" : "\(unread) unread messages")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("back-button")
                        }
                        .sharedBackgroundVisibility(.hidden)
                    } else {
                        CircleToolbarItem(placement: .topBarLeading) {
                            Button { dismiss() } label: { ToolIconLabel(symbol: "chevron.left") }
                                .accessibilityLabel("Back").accessibilityIdentifier("back-button")
                        }
                    }
                }
            }
    }
}

private struct ChatIsPaneRootKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True when the chat is the root of its own pane (the Mac shows the list and the chat side by side): there is nothing to go back to, so no Back (LIME-338).
    /// Nothing in `ios/` sets it, so on the phones Back always shows; the Mac host sets it.
    var chatIsPaneRoot: Bool {
        get { self[ChatIsPaneRootKey.self] }
        set { self[ChatIsPaneRootKey.self] = newValue }
    }
}

extension View {
    /// Our ‹ on iOS 26; the system's before that.
    @ViewBuilder
    func limeBack(showsBack: Bool = true, unread: Int = 0) -> some View {
        if #available(iOS 26, *) { modifier(LimeBackModifier(showsBack: showsBack, unread: unread)) } else { navigationBarBackButtonHidden(!showsBack) }
    }
}

extension View {
    /// No frosted band behind the bar (LIME-255): the system's bar background is hidden and the scroll edge effect is the soft one link, call and jam use, so a
    /// page scrolling under the buttons fades out instead of showing a grey rectangle. iOS 26 only; before that the system bar and `TopFade` stay as they were.
    @ViewBuilder
    func limeTopFade() -> some View {
        if #available(iOS 26, *) { toolbarBackground(.hidden, for: .navigationBar).scrollEdgeEffectStyle(.soft, for: .top) } else { self }
    }
}
