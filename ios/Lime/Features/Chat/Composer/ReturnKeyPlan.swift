import GameController
import UIKit

/// What the Return key does in a chat composer (LIME-339), like Apple Messages: on the Mac and on an iPad with a hardware keyboard Return **sends**, and
/// Shift-Return or Option-Return makes a new line; everywhere else (an iPhone, an iPad with only the on-screen keyboard) Return is a new line, as before.
/// The jam editor does not use this. Pure, so every row is tested without a keyboard.
enum ReturnKeyPlan {
    /// Does Return (with these modifiers) send the message?
    static func sends(idiom: UIUserInterfaceIdiom, hasHardwareKeyboard: Bool, modifiers: UIKeyModifierFlags, hasMarkedText: Bool, draftIsEmpty: Bool) -> Bool {
        guard idiom == .mac || (idiom == .pad && hasHardwareKeyboard) else { return false }
        // Shift, Option (and Control, Command) make a new line or are some other shortcut; Caps Lock is not a modifier here.
        guard modifiers.subtracting(.alphaShift).isEmpty else { return false }
        // An input method mid-composition uses Return to accept its text; an empty draft has nothing to send.
        return !hasMarkedText && !draftIsEmpty
    }

    /// This device's idiom as the rule means it: lime is iPhone-only today, so on an iPad it may run in a compatibility window whose idiom says phone (the device
    /// model says iPad, as `GroupCallView` reads it); on Mac Catalyst it is the Mac.
    @MainActor static var currentIdiom: UIUserInterfaceIdiom {
        #if targetEnvironment(macCatalyst)
        return .mac
        #else
        let idiom = UIDevice.current.userInterfaceIdiom
        if idiom == .pad || UIDevice.current.model.hasPrefix("iPad") { return .pad }
        return idiom
        #endif
    }

    /// A hardware keyboard is attached now (it can change while the app runs: this is read on each key press).
    static var hasHardwareKeyboard: Bool {
        #if DEBUG
        // The simulator's keyboard is not a GCKeyboard: a UI test on an iPad simulator says there is one.
        if ProcessInfo.processInfo.arguments.contains("-lime-fake-hardware-keyboard") { return true }
        #endif
        return GCKeyboard.coalesced != nil
    }

    /// The words VoiceOver adds to the composer where Return sends.
    static let hint = "Return sends; Shift-Return for a new line"
}
