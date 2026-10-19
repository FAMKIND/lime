import SwiftUI

/// Every confirmation in Lime is this bottom sheet (like Signal's), never a popover that can point at the wrong place: a bold title,
/// an optional line of explanation, then full-width capsule buttons: the actions (a destructive one in the danger red) and Cancel.
/// It is used like `confirmationDialog`: the buttons are the usual `Button`s (a `.destructive` or `.cancel` role styles them); a
/// button dismisses the sheet after it has run.
private struct ConfirmSheetModifier<Actions: View, Message: View>: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let message: () -> Message
    @State private var height: CGFloat = 320

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            VStack(spacing: 10) {
                Text(title)
                    .font(Theme.font(.title3, weight: .bold)).foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("confirm-title")
                message()
                    .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 6)
                VStack(spacing: 10) {
                    actions()
                }
                .buttonStyle(ConfirmButtonStyle())
                // A tap on any button closes the sheet once its action has run.
                .simultaneousGesture(TapGesture().onEnded {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(120))
                        isPresented = false
                    }
                })
            }
            .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            // (An identifier on the container would replace the buttons' own, so it sits on this background.)
            .background(GeometryReader { geo in Color.clear.preference(key: SheetHeightKey.self, value: geo.size.height) }.accessibilityIdentifier("confirm-sheet"))
            .onPreferenceChange(SheetHeightKey.self) { height = $0 }
            .presentationDetents([.height(min(height + 8, 640))])
            .presentationDragIndicator(.visible)
            .presentationBackground(Theme.canvas)
        }
    }
}

private struct SheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A full-width capsule; red text for a destructive action.
struct ConfirmButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(.body, weight: configuration.role == .cancel ? .regular : .semibold))
            .foregroundStyle(configuration.role == .destructive ? Color.red : Theme.text)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.surface.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .contentShape(Capsule())
    }
}

extension View {
    /// A confirmation as a bottom sheet (see `ConfirmSheetModifier`).
    func confirmSheet<Actions: View, Message: View>(
        _ title: String, isPresented: Binding<Bool>,
        @ViewBuilder actions: @escaping () -> Actions, @ViewBuilder message: @escaping () -> Message
    ) -> some View {
        modifier(ConfirmSheetModifier(title: title, isPresented: isPresented, actions: actions, message: message))
    }

    func confirmSheet<Actions: View>(_ title: String, isPresented: Binding<Bool>, @ViewBuilder actions: @escaping () -> Actions) -> some View {
        modifier(ConfirmSheetModifier(title: title, isPresented: isPresented, actions: actions, message: { EmptyView() }))
    }
}
