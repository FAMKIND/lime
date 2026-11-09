import SwiftUI

/// What the 1:1 call screen says aloud and how its buttons read (LIME-130-4a). The words are the visible words, so what VoiceOver says
/// and what a sighted person reads never differ. Pure, so a unit test pins each one.
enum CallAnnouncements {
    static let ringing = "Ringing\u{2026}"
    static let cameraPaused = "Your camera is paused while lime is in a window"

    /// What the visible line says when the phone may be off (the same text as the footnote on the call screen).
    static func unreachable(name: String) -> String { "\(name)\u{2019}s phone may be off or lime closed" }

    /// What to say when the phase changes; `nil` for no speech (an incoming call is announced by iOS's own call screen).
    static func phase(from old: CallPhase, to new: CallPhase) -> String? {
        guard old != new else { return nil }
        switch new {
        case .idle: return old == .idle ? nil : "Call ended"
        case .outgoing: return "Calling\u{2026}"
        case .incoming: return nil
        case .connecting: return "Connecting\u{2026}"
        case .active: return "Connected"
        }
    }

    /// "On" or "Off", the value of a toggle button (the label stays the action's name).
    static func value(_ on: Bool) -> String { on ? "On" : "Off" }
}

/// A toggle's icon: the two states differ in shape as well as in fill (WCAG 1.4.1).
enum CallToggleIcon {
    static func mute(muted: Bool) -> String { muted ? "mic.slash.fill" : "mic.fill" }
    static func camera(on: Bool) -> String { on ? "video.fill" : "video.slash.fill" }
    static func speaker(on: Bool) -> String { on ? "speaker.wave.2.fill" : "speaker.fill" }
}

/// Text over live video (WCAG 1.4.3): a black scrim at 0.6 under the white text, which stays at 4.5:1 or better on a white picture
/// (white text on 60% black over white is #666: 5.7:1).
extension View {
    func callTextScrim() -> some View {
        padding(.horizontal, 10).padding(.vertical, 4)
            .background(.black.opacity(CallScrim.text), in: Capsule())
    }
}

/// The darkest the picture can show through under call text and round buttons (measured, see TEND.md).
enum CallScrim {
    static let text = 0.6
    /// A round button's fill over video (white glyph on black at 0.45 over a white picture is #8C8C8C: 3.4:1).
    static let button = 0.45
    /// The ring around a lit (white) button: black at 0.6 on a white picture is 5.7:1.
    static let ring = 0.6
}

extension View {
    /// A round call button's background over live video (WCAG 1.4.11): dark glass when off; white with a thin dark ring when lit, so its edge
    /// shows against a bright picture too.
    func callRoundBackground(lit: Bool = false) -> some View {
        background {
            Circle().fill(lit ? Color.white : Color.black.opacity(CallScrim.button))
                .overlay { if lit { Circle().strokeBorder(Color.black.opacity(CallScrim.ring), lineWidth: 1.5) } }
        }
    }
}

/// Which control VoiceOver's focus goes to.
enum CallFocus: Hashable { case first, mute }
