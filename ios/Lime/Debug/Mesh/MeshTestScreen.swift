#if DEBUG
import SwiftUI

/// The mesh test screen (LIME-141, Debug builds only): turn the mesh on, see the status and the engine's counts, queue a test packet for a chosen
/// contact, read the log, share it. Real messages are wired to the mesh later (LIME-142); this proves the Bluetooth link first.
struct MeshTestScreen: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var service = MeshService.shared
    @State private var explaining = false
    @State private var contact: String?
    @State private var note = ""
    @State private var runs: [URL] = MeshLog.savedRuns()

    private var contacts: [Conversation] { store.conversations.filter { !$0.isGroupChat && !$0.isRequest && $0.members.first != nil } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Debug only. The mesh passes sealed packets phone to phone over Bluetooth. A test packet is random bytes: it is counted by the other phone and is never a message.")
                        .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    Text(service.status).font(Theme.title).accessibilityIdentifier("mesh-status")
                    Text("Bluetooth: \(service.bluetooth.bluetoothState) · scan: \(service.bluetooth.scanMode)").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    Button(service.bluetooth.running ? "Turn off" : "Turn on") { toggle() }
                        .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(Theme.accentInk)
                        .accessibilityIdentifier("mesh-toggle")
                    if let s = service.stats {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("carried \(s.carried) (\(s.carriedBytes) B) · received \(s.received) · duplicates \(s.duplicates)")
                            Text("mine \(s.mine) · test packets received \(s.probesReceived) · rejected \(s.rejected) · rate-limited \(s.rateLimited)")
                            Text("evicted \(s.evicted) · expired \(s.expired)")
                        }
                        .font(Theme.caption.monospacedDigit()).accessibilityIdentifier("mesh-stats")
                    }
                    Divider()
                    Text("Send a test packet to").font(Theme.title)
                    ForEach(contacts) { chat in
                        Button { contact = chat.members.first?.id } label: {
                            HStack {
                                Text(chat.title).foregroundStyle(Theme.text)
                                Spacer()
                                if contact == chat.members.first?.id { Image(systemName: "checkmark").foregroundStyle(Theme.text) }
                            }
                            .frame(minHeight: 44)
                        }
                    }
                    Button("Queue a test packet") {
                        guard let contact else { return }
                        note = service.queueProbe(to: contact) ? "Queued. It goes out the next time a phone is near." : "Not queued: no delivery key or no known device for that contact (exchange a message with them first)."
                    }
                    .buttonStyle(.bordered).tint(Theme.text).disabled(contact == nil || service.engine == nil)
                    .accessibilityIdentifier("mesh-probe")
                    if !note.isEmpty { Text(note).font(Theme.caption).foregroundStyle(Theme.textSecondary) }
                    Divider()
                    Text("Log").font(Theme.title)
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(service.log.events.reversed().prefix(150)) { event in
                            Text("\(event.time.formatted(.dateTime.hour().minute().second())) \(event.kind) \(event.detail)")
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Divider()
                    HStack {
                        Text("Saved logs (\(runs.count))").font(Theme.title)
                        Spacer()
                        Button("Share all") { NearbyShare.present(runs) }.disabled(runs.isEmpty)
                    }
                    ForEach(runs, id: \.self) { url in
                        Button { NearbyShare.present([url]) } label: {
                            Text(url.lastPathComponent).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Mesh test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .alert("Pass messages phone to phone?", isPresented: $explaining) {
                Button("Not now", role: .cancel) {}
                Button("Continue") { service.explained = true; begin() }
            } message: {
                Text("lime can pass messages phone-to-phone when there\u{2019}s no internet. It uses Bluetooth, and iOS will ask you to allow it.")
            }
        }
    }

    private func toggle() {
        if service.bluetooth.running { service.stop(); runs = MeshLog.savedRuns(); return }
        if service.explained { begin() } else { explaining = true }
    }

    private func begin() {
        guard let core = store.core else { note = "The store is not open yet."; return }
        service.start(core: core)
        runs = MeshLog.savedRuns()
    }
}
#endif
