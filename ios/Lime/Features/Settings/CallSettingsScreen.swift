import SwiftUI

/// Settings → Calls (LIME-169): lime's calls in the iPhone's Recents, Low Data Mode for video, and how loud the other people sound. Each has one
/// line saying what it does; all are kept on this iPhone and reach a call that is already running.
struct CallSettingsScreen: View {
    private let settings = CallSettings.shared

    var body: some View {
        @Bindable var settings = settings
        SettingsPage(title: "Calls") {
            SettingsCard {
                Toggle(isOn: $settings.includeInRecents) {
                    Text("Include in Recents").font(Theme.body).foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 18).frame(minHeight: 58)
                .accessibilityIdentifier("calls-recents")
            }
            SettingsFootnote(text: "Shows lime calls in the Phone app's Recents. Your iPhone may sync that list to iCloud.")

            SettingsCard {
                Toggle(isOn: $settings.lowDataMode) {
                    Text("Low Data Mode").font(Theme.body).foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 18).frame(minHeight: 58)
                .accessibilityIdentifier("calls-low-data")
            }
            SettingsFootnote(text: "Uses less data. Video looks softer but holds up better on a weak connection.")

            SettingsCard {
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill").font(.system(size: 16)).foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                    Slider(value: $settings.volume, in: CallSettings.volumeRange, step: 0.1)
                        .tint(Theme.text)
                        .accessibilityLabel("Call volume")
                        .accessibilityValue(CallSettings.percent(settings.volume))
                        .accessibilityIdentifier("calls-volume")
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 16)).foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                }
                .padding(.horizontal, 18).padding(.vertical, 16)
                Text(CallSettings.percent(settings.volume))
                    .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity).padding(.bottom, 14)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("calls-volume-value")
            }
            SettingsFootnote(text: "Changes how loud others sound in lime calls, on top of your phone's volume.")
        }
    }
}
