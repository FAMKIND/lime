import SwiftUI

/// Says a problem aloud when it appears or changes, without moving focus (LIME-322).
struct AnnouncesProblem: ViewModifier {
    let problem: String?
    func body(content: Content) -> some View {
        content.onChange(of: problem) { _, new in if let new, !new.isEmpty { Announce.say(new) } }
    }
}

/// One VoiceOver stop for a row with a label and a value, only while VoiceOver or Switch Control runs (touch and the UI tests keep the separate texts) (LIME-322).
struct OneStopRow: ViewModifier {
    func body(content: Content) -> some View {
        if CallControlsPolicy.voiceOverRunning || CallControlsPolicy.switchControlRunning { content.accessibilityElement(children: .combine) } else { content }
    }
}

/// A run of characters spoken one by one ("A 1 B 2"), only while VoiceOver runs: a safety number is not a word (LIME-322).
struct SpokenCharacters: ViewModifier {
    let text: String
    func body(content: Content) -> some View {
        if CallControlsPolicy.voiceOverRunning { content.accessibilityLabel(text.filter { !$0.isWhitespace }.map(String.init).joined(separator: " ")) } else { content }
    }
}

/// A "label, value, plus and minus" row as one adjustable element, only while VoiceOver or Switch Control runs; touch and the UI tests keep the buttons (LIME-322).
struct AdjustableRow: ViewModifier {
    let label: String
    let value: String
    let adjust: (AccessibilityAdjustmentDirection) -> Void
    func body(content: Content) -> some View {
        if CallControlsPolicy.voiceOverRunning || CallControlsPolicy.switchControlRunning {
            content.accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityValue(value).accessibilityAdjustableAction(adjust)
        } else { content }
    }
}
