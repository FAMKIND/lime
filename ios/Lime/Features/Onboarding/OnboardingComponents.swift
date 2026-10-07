import SwiftUI

/// The frame every onboarding question shares: a glass back button top left, a glass "Next" top
/// right (disabled until the answer is valid), a title, the content, and an error line.
struct OnboardingScaffold<Content: View>: View {
    let title: String
    var subtitle: String?
    var showsBack = true
    var showsNext = true
    var canNext: Bool
    var isBusy = false
    var errorMessage: String?
    var onBack: () -> Void = {}
    var onNext: () -> Void = {}
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if showsBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .frame(width: 48, height: 48)
                            .limeGlass()
                    }
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("onboarding-back")
                }
                Spacer()
                if showsNext {
                    NextButton(isEnabled: canNext, isBusy: isBusy, action: onNext)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(height: 60)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title)
                        .font(.system(.largeTitle, design: .default, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("onboarding-title")
                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("onboarding-subtitle")
                    }
                    content
                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.secondary)
                            .foregroundStyle(Color(red: 0.72, green: 0.17, blue: 0.2))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("error-message")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.canvas.ignoresSafeArea())
    }
}

/// A one-line text field in Lime's look.
struct OnboardingField: View {
    let label: String
    @Binding var text: String
    var prompt = ""
    var isSecure = false
    var identifier: String
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var submit: SubmitLabel = .next
    var onSubmit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
            Group {
                if isSecure {
                    SecureField(prompt, text: $text)
                } else {
                    TextField(prompt, text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .textContentType(contentType)
            .selectionTint()
            .submitLabel(submit)
            .onSubmit(onSubmit)
            .font(Theme.body)
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
            .accessibilityIdentifier(identifier)
        }
    }
}

/// A full-width pill in the accent colour.
struct PrimaryButton: View {
    let title: String
    var identifier: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isBusy { ProgressView() } else { Text(title).font(Theme.body.weight(.semibold)) }
            }
            .foregroundStyle(Theme.accentInk)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.accent, in: Capsule())
        }
        .accessibilityIdentifier(identifier)
    }
}

/// The glass "Next" at the top right. Enabled it is the brand primary (the accent fill and its dark
/// ink, like the welcome screen's Continue); disabled it is neutral glass with a dimmed label.
struct NextButton: View {
    let isEnabled: Bool
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isBusy { ProgressView() } else { Text("Next").font(Theme.body.weight(.semibold)) }
            }
            .foregroundStyle(isEnabled || isBusy ? Theme.accentInk : Theme.textSecondary.opacity(0.7))
            .frame(minWidth: 72, minHeight: 48)
            .padding(.horizontal, 12)
            .background {
                if isEnabled || isBusy {
                    Capsule().fill(Theme.accent)
                } else {
                    Color.clear.limeGlass()
                }
            }
        }
        .disabled(!isEnabled)
        .accessibilityLabel("Next")
        .accessibilityIdentifier("next-button")
    }
}
