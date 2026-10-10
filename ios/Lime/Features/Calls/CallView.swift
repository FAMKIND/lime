import SwiftUI

/// Hosts the media engine's UIKit video surface.
private struct VideoSurface: UIViewRepresentable {
    let make: () -> UIView
    func makeUIView(context: Context) -> UIView { make() }
    func updateUIView(_ view: UIView, context: Context) {}
}

/// The call screen: who, how long, and mute / speaker / video / flip / end. Incoming calls show Decline and Accept.
struct CallView: View {
    @Environment(ConversationStore.self) private var store

    var body: some View {
        let call = store.calls
        ZStack {
            Color.black.ignoresSafeArea()
            if call.video, call.phase == .active || call.phase == .connecting, let media = call.media {
                VideoSurface { media.remoteView }.ignoresSafeArea()
                VStack {
                    HStack {
                        Spacer()
                        if call.cameraOn {
                            VideoSurface { media.localView }
                                .frame(width: 110, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding()
                                .accessibilityIdentifier("call-self-view")
                        }
                    }
                    Spacer()
                }
            }
            VStack(spacing: 8) {
                Spacer().frame(height: 60)
                Text(call.peerName).font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                    .accessibilityIdentifier("call-name")
                statusText(call).font(.system(size: 17)).foregroundStyle(.white.opacity(0.8))
                    .accessibilityIdentifier("call-status")
                Spacer()
                controls(call)
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
        }
        .accessibilityIdentifier("call-screen")
    }

    @ViewBuilder
    private func statusText(_ call: CallManager) -> some View {
        switch call.phase {
        case .outgoing: Text("Calling…")
        case .incoming: Text(call.video ? "Lime video call" : "Lime voice call")
        case .connecting: Text("Connecting…")
        case .active:
            if let start = call.startedAt {
                TimelineView(.periodic(from: start, by: 1)) { context in
                    Text(CallRecord.clock(context.date.timeIntervalSince(start))).monospacedDigit()
                }
            }
        case .idle: Text("")
        }
    }

    @ViewBuilder
    private func controls(_ call: CallManager) -> some View {
        if call.phase == .incoming {
            HStack(spacing: 80) {
                round("phone.down.fill", "Decline", .red, id: "call-decline") { Task { await call.decline() } }
                round("phone.fill", "Accept", .green, id: "call-accept") { Task { await call.accept() } }
            }
        } else {
            VStack(spacing: 28) {
                HStack(spacing: 28) {
                    toggle(call.muted ? "mic.slash.fill" : "mic.fill", "Mute", on: call.muted, id: "call-mute") { call.setMuted(!call.muted) }
                    toggle("speaker.wave.2.fill", "Speaker", on: call.speaker, id: "call-speaker") { call.toggleSpeaker() }
                    if call.video {
                        toggle(call.cameraOn ? "video.fill" : "video.slash.fill", "Video", on: !call.cameraOn, id: "call-video") { call.toggleCamera() }
                        toggle("arrow.triangle.2.circlepath.camera", "Flip", on: false, id: "call-flip") { call.flipCamera() }
                    }
                }
                round("phone.down.fill", "End call", .red, id: "call-end") { Task { await call.end() } }
            }
        }
    }

    private func round(_ symbol: String, _ label: String, _ color: Color, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.white)
                .frame(width: 68, height: 68).background(color, in: Circle())
        }
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }

    private func toggle(_ symbol: String, _ label: String, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(on ? .black : .white)
                .frame(width: 56, height: 56).background(on ? Color.white : Color.white.opacity(0.2), in: Circle())
        }
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }
}

/// The dock's call tab: calls on this phone, newest first; tap to call back.
struct CallHistoryView: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let log = CallLog.shared

    var body: some View {
        NavigationStack {
            List {
                if log.records.isEmpty {
                    Text("No calls yet. Start one from a chat's phone button.")
                        .foregroundStyle(Theme.textSecondary).accessibilityIdentifier("calls-empty")
                }
                ForEach(log.records) { record in
                    Button {
                        dismiss()
                        Task { _ = await store.calls.start(peerID: record.peerID, name: record.peerName, video: record.video) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.peerName).foregroundStyle(record.outcome == .missed ? Color.red : Theme.text)
                            Text("\(record.line) · \(record.date.formatted(date: .abbreviated, time: .shortened))")
                                .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .accessibilityIdentifier("call-history-row")
                }
            }
            .listStyle(.plain)
            .navigationTitle("Calls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .accessibilityIdentifier("calls-screen")
    }
}
