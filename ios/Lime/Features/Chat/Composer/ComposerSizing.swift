import CoreGraphics

/// How tall the composer's text field may be (LIME-176), worked out from the window and the keyboard's real frame, never fixed numbers.
enum ComposerSizing {
    /// Lines the field always has room for, as before.
    static let minimumLines: CGFloat = 5
    /// What the tool row, the paddings and the card around the field take.
    static let chrome: CGFloat = 54
    /// The formatting strip under the card, while it shows.
    static let stripHeight: CGFloat = 44
    /// The header's height under the status bar, kept clear when the composer is expanded.
    static let headerHeight: CGFloat = 56
    /// The share of the window the composer and the keyboard may take together.
    static let share: CGFloat = 0.75

    static func minimumHeight(line: CGFloat) -> CGFloat { line * minimumLines + 16 }
    /// One line always shows (the field scrolls inside), whatever the window.
    static func oneLineHeight(line: CGFloat) -> CGFloat { line + 16 }

    /// The room really there for the field: between the header and the keyboard (or the bottom), under the rest of the composer.
    static func availableFieldHeight(window: CGFloat, keyboard: CGFloat, topInset: CGFloat, bottomInset: CGFloat, strip: Bool) -> CGFloat {
        let below = keyboard > 0 ? keyboard : bottomInset
        return window - topInset - headerHeight - below - chrome - (strip ? stripHeight : 0)
    }

    /// The most the field grows to while writing: composer + keyboard about 75% of the window (keyboard hidden: the composer alone, above the home indicator),
    /// but never past the room really there (a short, landscape window), and never under one line. Five lines are kept when the room allows them.
    static func maxFieldHeight(window: CGFloat, keyboard: CGFloat, topInset: CGFloat = 0, bottomInset: CGFloat, strip: Bool, line: CGFloat) -> CGFloat {
        let below = keyboard > 0 ? keyboard : bottomInset
        let share = window * Self.share - below - chrome - (strip ? stripHeight : 0)
        let available = availableFieldHeight(window: window, keyboard: keyboard, topInset: topInset, bottomInset: bottomInset, strip: strip)
        let floor = min(minimumHeight(line: line), available)
        return max(oneLineHeight(line: line), max(floor, min(share.rounded(.down), available.rounded(.down))))
    }

    /// The field's height when expanded: from just below the header to the keyboard (or the bottom).
    static func expandedFieldHeight(window: CGFloat, keyboard: CGFloat, topInset: CGFloat, bottomInset: CGFloat, strip: Bool, line: CGFloat) -> CGFloat {
        let available = availableFieldHeight(window: window, keyboard: keyboard, topInset: topInset, bottomInset: bottomInset, strip: strip)
        return max(oneLineHeight(line: line), available.rounded(.down))
    }
}
