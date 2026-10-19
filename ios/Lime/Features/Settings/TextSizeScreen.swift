import SwiftUI

/// Settings, Customize, Text size & font (LIME-168): lime's own text size and typeface with a live preview, kept on this iPhone. By default lime
/// follows the iPhone's text size and uses the system font.
struct TextSizeScreen: View {
    enum Tab: String, CaseIterable, Identifiable {
        case size = "Text size", font = "Font"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .size
    @Environment(\.dynamicTypeSize) private var typeSize
    private let preferences = TextPreferences.shared

    var body: some View {
        SettingsPage(title: "Text size") {
            // At the accessibility sizes the preview alone would fill the screen and push the controls out of reach: it scrolls in a box instead.
            if typeSize.isAccessibilitySize {
                ScrollView(.vertical) { TextPreview() }
                    .frame(height: 340)
                    .scrollIndicators(.visible)
                    .accessibilityIdentifier("text-size-preview-box")
            } else {
                TextPreview()
            }
            Picker("Settings", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("text-size-tabs")
            switch tab {
            case .size: sizeTab
            case .font: fontTab
            }
        }
    }

    private var sizeTab: some View {
        @Bindable var preferences = preferences
        return VStack(spacing: 16) {
            SettingsCard {
                Toggle(isOn: $preferences.followsSystem) {
                    Text("Use iPhone's text size").font(Theme.body).foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 18).frame(minHeight: 58)
                .accessibilityIdentifier("text-size-follow")
            }
            SettingsFootnote(text: preferences.followsSystem
                ? "lime follows Settings → Display & Brightness → Text Size on your iPhone."
                : "This size is for lime only. Your iPhone's setting is not changed.")
            SettingsCard {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Text("A").font(Theme.font(.caption)).foregroundStyle(Theme.text).accessibilityHidden(true)
                        Slider(value: Binding(get: { Double(preferences.step) }, set: { preferences.step = Int($0.rounded()) }),
                               in: 0...Double(TextStep.all.count - 1), step: 1)
                            .tint(Theme.text)
                            .disabled(preferences.followsSystem)
                            .accessibilityLabel("Text size")
                            .accessibilityValue(preferences.currentStep.name)
                            .accessibilityIdentifier("text-size-slider")
                        Text("A").font(.system(size: 28, weight: .regular)).foregroundStyle(Theme.text).accessibilityHidden(true)
                    }
                    Text(preferences.followsSystem ? "Following your iPhone" : preferences.currentStep.name)
                        .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("text-size-name")
                }
                .padding(.horizontal, 18).padding(.vertical, 16)
                .opacity(preferences.followsSystem ? 0.45 : 1)
            }
        }
    }

    private var fontTab: some View {
        @Bindable var preferences = preferences
        return VStack(spacing: 16) {
            SettingsCard {
                ForEach(LimeTypeface.allCases) { face in
                    Button { preferences.typeface = face } label: {
                        VStack(spacing: 0) {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(face.title).font(face.font(.body, weight: .medium)).foregroundStyle(Theme.text)
                                    Text(face.detail).font(face.font(.footnote)).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                if preferences.typeface == face {
                                    Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text)
                                }
                            }
                            .padding(.horizontal, 18).padding(.vertical, 12).frame(minHeight: 58)
                            if face != LimeTypeface.allCases.last { Divider().overlay(Theme.hairline).padding(.leading, 18) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(face.title), \(face.detail)")
                    .accessibilityIdentifier("font-\(face.rawValue)")
                    .accessibilityAddTraits(preferences.typeface == face ? [.isSelected, .isButton] : [.isButton])
                }
            }
            SettingsFootnote(text: "The font applies to all of lime. Icons and the numbers on calls stay as they are. Fonts are open source (SIL Open Font License).")
        }
    }
}

/// Two bubbles, one of each side, with a name and a time, drawn the way a chat draws them: the size and the font change here as you change them.
private struct TextPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sam Park").font(Theme.font(.caption, weight: .medium)).foregroundStyle(Theme.text)
                Text("Are you coming to the staff meeting?")
                    .font(Theme.body).foregroundStyle(Theme.text)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.bubbleOther, in: RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous).strokeBorder(Theme.bubbleEdge, lineWidth: 0.5))
                Text("9:41 AM").font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 40)
            VStack(alignment: .trailing, spacing: 4) {
                Text("Yes! I'll bring the new reading lists.")
                    .font(Theme.body).foregroundStyle(Theme.ownBubbleInk)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.ownBubble, in: RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
                Text("9:42 AM").font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 40)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview. Sam Park: Are you coming to the staff meeting? You: Yes! I'll bring the new reading lists.")
        .accessibilityIdentifier("text-size-preview")
    }
}
