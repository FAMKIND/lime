import SwiftUI
import UIKit

extension View {
    /// Tapping the messages puts the keyboard away (LIME-175). A simultaneous gesture, so links, attachments, reactions, long-press, swipe-to-reply and selection keep their own taps;
    /// the bounce is always on, so a swipe down also works when the messages fit the screen.
    func hidesKeyboardOnTap() -> some View {
        scrollBounceBehavior(.always)
            .simultaneousGesture(TapGesture().onEnded {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            })
    }
}
