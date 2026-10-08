#if DEBUG
import SwiftUI
import UIKit

/// The Bluetooth field test (LIME-103, Debug builds only): start or stop, a live log, test blobs, and
/// sharing the log files. See docs/spike-ble-test-plan.md.
struct NearbyTestScreen: View {
    @State private var test = NearbyTest.shared
    @State private var showAuto = false
    @State private var runs: [URL] = NearbyLog.savedRuns()
    @Environment(\.dismiss) private var dismiss

    private var transport: NearbyTransport { test.transport }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Throwaway Bluetooth test. It sends random signed bytes only: no messages and no personal data.")
                        .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    TextField("Scenario label, e.g. 2-A-open-B-background", text: $test.label)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .disabled(transport.running)
                        .accessibilityIdentifier("nearby-label")
                    HStack {
                        Button(transport.running ? "Stop" : "Start") { transport.running ? test.stop() : test.start(); runs = NearbyLog.savedRuns() }
                            .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(Theme.accentInk)
                            .accessibilityIdentifier("nearby-start")
                        Text("Bluetooth: \(transport.bluetoothState) · both central and peripheral").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Picker("Transport", selection: Bindable(transport).mode) {
                        ForEach(NearbyTransport.Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Send a greeting (200 B + 4 KB) when a phone connects", isOn: Bindable(transport).sendOnConnect)
                        .font(Theme.secondary)
                    Text("Links: \(transport.links.count)  ·  sent \(transport.sent)  ·  received \(transport.received)  ·  duplicates \(transport.duplicates)  ·  invalid \(transport.invalid)")
                        .font(Theme.caption.monospacedDigit())
                    ForEach(transport.linkLines, id: \.self) { Text($0).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textSecondary) }
                    HStack {
                        ForEach(NearbyBlob.sizes, id: \.self) { size in
                            Button(size < 1_000 ? "\(size) B" : "\(size / 1024) KB") { transport.sendTestBlob(bodySize: size) }
                                .buttonStyle(.bordered).tint(Theme.text)
                                .disabled(!transport.running)
                        }
                        Button("All 3") { for size in NearbyBlob.sizes { transport.sendTestBlob(bodySize: size) } }
                            .buttonStyle(.bordered).tint(Theme.text).disabled(!transport.running)
                            .accessibilityIdentifier("nearby-send-all")
                    }
                    Button("Auto test (overnight)…") { showAuto = true }
                        .buttonStyle(.bordered).tint(Theme.text)
                        .accessibilityIdentifier("nearby-auto-button")
                    Divider()
                    Text("Log").font(Theme.title)
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(test.log.events.reversed().prefix(120)) { event in
                            Text("\(event.time.formatted(.dateTime.hour().minute().second())) \(event.kind) \(event.detail)")
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Divider()
                    HStack {
                        Text("Saved runs (\(runs.count))").font(Theme.title)
                        Spacer()
                        Button("Share all") { NearbyShare.present(runs) }.disabled(runs.isEmpty)
                            .accessibilityIdentifier("nearby-share-all")
                    }
                    ForEach(runs, id: \.self) { url in
                        Button { NearbyShare.present([url]) } label: {
                            Text(url.lastPathComponent).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Nearby test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showAuto) { NearbyAutoScreen() }
        }
    }
}

#endif
