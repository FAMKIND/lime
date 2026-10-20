import SwiftUI
import UIKit

/// When the keyboard opens (or changes height: the emoji keyboard, the formatting strip) while the list is at its newest message, the list stays at the
/// newest message, scrolled with the keyboard, so the last message is above the composer, as in iMessage (LIME-174). A reader who has scrolled up in history
/// is not moved. iOS 18 and later (it needs the scroll geometry); on iOS 17 the system's own anchoring stays as it was.
extension View {
    func keepsNewestAboveKeyboard(proxy: ScrollViewProxy, newestID: AnyHashable?) -> some View {
        modifier(KeepsNewestAboveKeyboard(proxy: proxy, newestID: newestID))
    }
}

struct KeepsNewestAboveKeyboard: ViewModifier {
    let proxy: ScrollViewProxy
    let newestID: AnyHashable?

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            Tracked(content: content, proxy: proxy, newestID: newestID)
        } else {
            content
        }
    }

    @available(iOS 18, *)
    private struct Tracked<Content: View>: View {
        let content: Content
        let proxy: ScrollViewProxy
        let newestID: AnyHashable?
        /// Whether the list showed its newest message at the last geometry change (read when the keyboard starts to move, before the layout changes).
        @State private var atNewest = true
        @State private var stickUntil = Date.distantPast

        var body: some View {
            content
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    // The end of the content is within a screenful's margin of the bottom of what is visible.
                    geometry.contentSize.height - geometry.visibleRect.maxY <= 120
                } action: { _, new in
                    atNewest = new
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { _ in
                    let now = Date()
                    if atNewest { stickUntil = now.addingTimeInterval(1.0) }
                    guard now < stickUntil, let newestID else { return }
                    // With the keyboard's animation, and once more when it has settled.
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(newestID, anchor: .bottom) }
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        proxy.scrollTo(newestID, anchor: .bottom)
                    }
                }
        }
    }
}
