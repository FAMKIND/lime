import SwiftUI

/// A way to move and zoom a crop without a drag or a pinch (WCAG 2.5.7, LIME-130-5a): swipe up or down on the frame to zoom, and "Move up/down/left/right" in the
/// actions menu moves the picture by a tenth of the frame. The gestures stay as they were.
enum CropMove: CaseIterable {
    case up, down, left, right
    var title: String {
        switch self { case .up: "Move up"; case .down: "Move down"; case .left: "Move left"; case .right: "Move right" }
    }
}

enum CropAccessibility {
    /// How far one "Move" goes: a tenth of the frame.
    static let step: CGFloat = 0.10
    /// How far one swipe zooms.
    static let zoomStep: CGFloat = 0.5
    static let minScale: CGFloat = 1
    static let maxScale: CGFloat = 6

    /// The picture moves the way the action says ("Move up": the picture goes up). The caller clamps the result to what the frame allows.
    static func moved(_ offset: CGSize, _ move: CropMove, frame: CGSize) -> CGSize {
        switch move {
        case .up: CGSize(width: offset.width, height: offset.height - frame.height * step)
        case .down: CGSize(width: offset.width, height: offset.height + frame.height * step)
        case .left: CGSize(width: offset.width - frame.width * step, height: offset.height)
        case .right: CGSize(width: offset.width + frame.width * step, height: offset.height)
        }
    }

    static func zoomed(_ scale: CGFloat, in zoomIn: Bool) -> CGFloat {
        min(max(scale + (zoomIn ? zoomStep : -zoomStep), minScale), maxScale)
    }

    /// "Zoom 150 percent".
    static func value(scale: CGFloat) -> String { "Zoom \(Int((scale * 100).rounded())) percent" }
}

extension View {
    /// The crop frame's accessible face: a label, the zoom as the value, swipe up/down to zoom, and the four moves as actions.
    func cropAccessibility(label: String, scale: Binding<CGFloat>, offset: Binding<CGSize>, frame: CGSize, clamp: @escaping (CGSize) -> CGSize) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(CropAccessibility.value(scale: scale.wrappedValue))
            .accessibilityHint("Swipe up or down to zoom. Use the actions to move the picture")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: scale.wrappedValue = CropAccessibility.zoomed(scale.wrappedValue, in: true)
                case .decrement: scale.wrappedValue = CropAccessibility.zoomed(scale.wrappedValue, in: false)
                @unknown default: break
                }
                offset.wrappedValue = clamp(offset.wrappedValue)
            }
            .accessibilityAction(named: "Move up") { offset.wrappedValue = clamp(CropAccessibility.moved(offset.wrappedValue, .up, frame: frame)) }
            .accessibilityAction(named: "Move down") { offset.wrappedValue = clamp(CropAccessibility.moved(offset.wrappedValue, .down, frame: frame)) }
            .accessibilityAction(named: "Move left") { offset.wrappedValue = clamp(CropAccessibility.moved(offset.wrappedValue, .left, frame: frame)) }
            .accessibilityAction(named: "Move right") { offset.wrappedValue = clamp(CropAccessibility.moved(offset.wrappedValue, .right, frame: frame)) }
    }
}
