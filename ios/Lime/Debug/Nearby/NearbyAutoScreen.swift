#if DEBUG
import SwiftUI

/// The unattended overnight test (LIME-103b): pick a role, Start, lock the phone, go to bed.
struct NearbyAutoScreen: View {
    @State private var auto = NearbyAutoTest.shared
    @State private var earlier: [String] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Leave-it-on-the-table test. One phone sends a signed blob every 5 minutes, the other just sits locked and receives. Nothing personal is sent or logged.")
                        .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    Picker("Role", selection: $auto.role) {
                        ForEach(NearbyAutoTest.Role.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).disabled(auto.running)
                    .accessibilityIdentifier("auto-role")
                    if auto.role == .sender {
                        Toggle("Keep the screen on (sender stays awake)", isOn: $auto.keepAwake).font(Theme.secondary).disabled(auto.running)
                    }
                    Toggle("2-minute force-quit check instead", isOn: $auto.forceQuitCheck).font(Theme.secondary).disabled(auto.running)
                        .accessibilityIdentifier("auto-forcequit")
                    Button {
                        auto.running ? auto.stop() : auto.start()
                    } label: {
                        Text(auto.running ? "Stop" : "Start as \(auto.role.title)").font(Theme.title)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(auto.running ? Theme.surface : Theme.accent, in: Capsule())
                            .foregroundStyle(auto.running ? Theme.text : Theme.accentInk)
                    }
                    .accessibilityIdentifier("auto-start")
                    Text(auto.running
                         ? (auto.role == .sender ? "Sending. Leave this phone on the table" + (auto.keepAwake ? ", screen on." : " (you can lock it).")
                                                  : "Receiving. Lock this phone now and leave it.")
                         : "Not running.")
                        .font(Theme.secondary).accessibilityIdentifier("auto-status")
                    Divider()
                    Text(auto.running ? "Summary so far" : "Summary of the last run").font(Theme.title)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array((auto.running ? auto.summary : earlier).enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 14, design: .rounded)).foregroundStyle(Theme.text)
                        }
                        if (auto.running ? auto.summary : earlier).isEmpty { Text("Nothing yet.").foregroundStyle(Theme.textSecondary) }
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityElement(children: .combine).accessibilityIdentifier("auto-summary")
                    Button("Share logs") { NearbyShare.present(NearbyLog.savedRuns()) }
                        .disabled(NearbyLog.savedRuns().isEmpty)
                    Text("Take a screenshot of the summary in the morning. If Share logs shows an empty sheet, the logs can be copied over USB (see ios/README.md).")
                        .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                .padding(16)
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Auto test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task {
                earlier = auto.summaryOfLatestRun()
                while !Task.isCancelled {
                    auto.refreshSummary()
                    try? await Task.sleep(for: .seconds(30))
                }
            }
        }
    }
}
#endif
