import AVKit
import SwiftUI

/// Hosts the media engine's UIKit video surface.
private struct VideoSurface: UIViewRepresentable {
    let make: () -> UIView
    func makeUIView(context: Context) -> UIView { make() }
    func updateUIView(_ view: UIView, context: Context) {}
}

/// The system's output picker (AirPods, speaker, iPhone), as a button.
private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = .white
        view.prioritizesVideoDevices = false
        return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

private enum Corner: CaseIterable { case topLeading, topTrailing, bottomLeading, bottomTrailing }

/// The 1:1 call screen (LIME-118), FaceTime's layout in lime's style: the other person full-bleed (or a large avatar until there is
/// video), my own picture in a tile you can drag to a corner and tap to swap, a name pill top-left, the controls bottom-right on a
/// video call and in one row on a voice call. Always dark.
struct CallView: View {
    @Environment(ConversationStore.self) private var store
    @State private var corner: Corner = .topTrailing
    @State private var drag: CGSize = .zero
    @State private var swapped = false
    @State private var controlsVisible = true
    @State private var fadeTask: Task<Void, Never>?
    @State private var showPerson = false

    private let tile = CGSize(width: 108, height: 148)

    var body: some View {
        let call = store.calls
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea().accessibilityIdentifier("call-screen")
                background(call)
                if call.video { videoLayers(call, in: geo.size) }
                VStack(alignment: .leading, spacing: 6) {
                    header(call)
                    if call.phase == .outgoing && call.showUnreachableHint {
                        Text("\(call.peerName)\u{2019}s phone may be off or lime closed")
                            .font(.footnote).foregroundStyle(.white.opacity(0.7))
                            .accessibilityIdentifier("call-unreachable-hint")
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.top, 8)
                if let toast = call.route.toast {
                    Text(toast).font(.footnote.weight(.medium)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.black.opacity(0.6), in: Capsule())
                        .frame(maxHeight: .infinity, alignment: .top).padding(.top, 70)
                        .accessibilityIdentifier("call-route-toast")
                }
                controls(call)
                    .opacity(call.video && !controlsVisible ? 0 : 1)
                    .allowsHitTesting(!(call.video && !controlsVisible))
                    .accessibilityHidden(call.video && !controlsVisible)
                    .animation(.easeInOut(duration: 0.25), value: controlsVisible)
            }
            .contentShape(Rectangle())
            .onTapGesture { if call.video { showControls() } }
            .onAppear { showControls() }
            .onChange(of: call.phase) { _, _ in showControls() }
        }
        .sheet(isPresented: $showPerson) { personSheet(call) }
        .preferredColorScheme(.dark)
    }

    // MARK: Layers

    private var person: (ConversationStore) -> Person = { store in Person(id: store.calls.peerID, name: store.calls.peerName) }

    @ViewBuilder
    private func background(_ call: CallManager) -> some View {
        // The avatar fills the screen until there is a picture to show big: the other person's video, or mine after a swap.
        let pictureBig = call.video && (swapped ? call.cameraOn : call.remoteVideoLive)
        if !pictureBig {
            ZStack {
                AvatarView(person: person(store), size: 400).blur(radius: 60).opacity(0.5).ignoresSafeArea()
                AvatarView(person: person(store), size: 160)
                    .accessibilityIdentifier("call-avatar")
            }
        }
    }

    @ViewBuilder
    private func videoLayers(_ call: CallManager, in size: CGSize) -> some View {
        let tileOrigin = origin(of: corner, in: size)
        // Two fixed views, laid out as the big picture or as the tile (a UIView cannot move between parents).
        let remoteBig = !swapped
        ZStack(alignment: .topLeading) {
            layer(call.media?.remoteView, placeholder: remoteBig ? Color.clear : Color(white: 0.2), id: "call-remote-view")
                .frame(width: remoteBig ? size.width : tile.width, height: remoteBig ? size.height : tile.height)
                .clipShape(RoundedRectangle(cornerRadius: remoteBig ? 0 : 14))
                .offset(x: remoteBig ? 0 : tileOrigin.x + drag.width, y: remoteBig ? 0 : tileOrigin.y + drag.height)
                .zIndex(remoteBig ? 0 : 2)
                .opacity(remoteBig && !call.remoteVideoLive && call.media != nil ? 0 : 1)
            if call.cameraOn {
                layer(call.media?.localView, placeholder: Color(white: 0.35), id: "call-self-view")
                    .frame(width: remoteBig ? tile.width : size.width, height: remoteBig ? tile.height : size.height)
                    .clipShape(RoundedRectangle(cornerRadius: remoteBig ? 14 : 0))
                    .offset(x: remoteBig ? tileOrigin.x + drag.width : 0, y: remoteBig ? tileOrigin.y + drag.height : 0)
                    .zIndex(remoteBig ? 2 : 0)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            // A transparent handle over the tile: drag to a corner, tap to swap.
            Color.clear
                .frame(width: tile.width, height: tile.height)
                .contentShape(Rectangle())
                .offset(x: tileOrigin.x + drag.width, y: tileOrigin.y + drag.height)
                .gesture(DragGesture().onChanged { drag = $0.translation }.onEnded { value in
                    let end = CGPoint(x: tileOrigin.x + value.translation.width + tile.width / 2, y: tileOrigin.y + value.translation.height + tile.height / 2)
                    withAnimation(.spring(duration: 0.3)) { corner = nearest(to: end, in: size); drag = .zero }
                })
                .onTapGesture { withAnimation { swapped.toggle() }; showControls() }
                .accessibilityIdentifier("call-tile-handle")
                .accessibilityLabel("Swap the pictures")
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func layer(_ view: UIView?, placeholder: Color, id: String) -> some View {
        if let view { VideoSurface { view }.accessibilityIdentifier(id) } else { placeholder.accessibilityIdentifier(id) }
    }

    private func origin(of corner: Corner, in size: CGSize) -> CGPoint {
        let margin: CGFloat = 16, top: CGFloat = 70, bottom: CGFloat = 110
        switch corner {
        case .topLeading: return CGPoint(x: margin, y: top + 50)
        case .topTrailing: return CGPoint(x: size.width - tile.width - margin, y: top)
        case .bottomLeading: return CGPoint(x: margin, y: size.height - tile.height - bottom)
        case .bottomTrailing: return CGPoint(x: size.width - tile.width - margin - 70, y: size.height - tile.height - bottom)
        }
    }

    private func nearest(to point: CGPoint, in size: CGSize) -> Corner {
        Corner.allCases.min { lhs, rhs in
            let a = origin(of: lhs, in: size), b = origin(of: rhs, in: size)
            let da = hypot(a.x + tile.width / 2 - point.x, a.y + tile.height / 2 - point.y)
            let db = hypot(b.x + tile.width / 2 - point.x, b.y + tile.height / 2 - point.y)
            return da < db
        } ?? .topTrailing
    }

    // MARK: Header

    private func header(_ call: CallManager) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { showPerson = true } label: {
                HStack(spacing: 8) {
                    AvatarView(person: person(store), size: 28)
                    Text(call.peerName).font(.headline).foregroundStyle(.white).lineLimit(1)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                }
                .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 6)
                .background(.black.opacity(0.35), in: Capsule())
            }
            .accessibilityLabel("\(call.peerName), details")
            .accessibilityIdentifier("call-name-pill")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(call.statusText(at: context.date)).monospacedDigit()
                    .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    .padding(.leading, 8)
                    .accessibilityIdentifier("call-status")
            }
        }
    }

    private func personSheet(_ call: CallManager) -> some View {
        VStack(spacing: 16) {
            AvatarView(person: person(store), size: 88).padding(.top, 24)
            Text(call.peerName).font(.title2.weight(.semibold))
            Button {
                showPerson = false
                call.minimized = true
                store.openFromNotification("dm:\(call.peerID)", thread: nil)
            } label: {
                Label("Message", systemImage: "message").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent)
            .accessibilityIdentifier("call-person-message")
            Spacer()
        }
        .padding(.horizontal, 24)
        .presentationDetents([.height(300)])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("call-person-sheet")
    }

    // MARK: Controls

    @ViewBuilder
    private func controls(_ call: CallManager) -> some View {
        if call.phase == .incoming {
            HStack(spacing: 80) {
                round("phone.down.fill", "Decline", .red, id: "call-decline") { Task { await call.decline() } }
                round("phone.fill", "Accept", .green, id: "call-accept") { Task { await call.accept() } }
            }
            .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 48)
        } else if call.video {
            ZStack {
                VStack(spacing: 14) {
                    Spacer()
                    toggle(call.cameraOn ? "video.fill" : "video.slash.fill", "Camera", on: !call.cameraOn, id: "call-video") { call.toggleCamera(); showControls() }
                    toggle(call.muted ? "mic.slash.fill" : "mic.fill", "Mute", on: call.muted, id: "call-mute") { call.setMuted(!call.muted); showControls() }
                    routeButton(call)
                    round("xmark", "End call", .red, id: "call-end") { Task { await call.end() } }
                }
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 16)
                VStack {
                    Spacer()
                    HStack {
                        toggle("arrow.triangle.2.circlepath.camera", "Flip camera", on: false, id: "call-flip") { call.flipCamera(); showControls() }
                        Spacer()
                    }
                }
                .padding(.leading, 16)
            }
            .padding(.bottom, 36)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("call-controls-video")
        } else {
            HStack(spacing: 22) {
                toggle(call.muted ? "mic.slash.fill" : "mic.fill", "Mute", on: call.muted, id: "call-mute") { call.setMuted(!call.muted) }
                toggle("speaker.wave.2.fill", "Speaker", on: call.speaker, id: "call-speaker") { call.toggleSpeaker() }
                routeButton(call)
                round("phone.down.fill", "End call", .red, id: "call-end") { Task { await call.end() } }
            }
            .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 48)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("call-controls-voice")
        }
    }

    /// The system output picker, labelled with where the sound is now.
    private func routeButton(_ call: CallManager) -> some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.2)).frame(width: 56, height: 56)
            RoutePicker().frame(width: 40, height: 40)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Audio output, now \(call.route.name)")
        .accessibilityIdentifier("call-route")
    }

    private func showControls() {
        controlsVisible = true
        fadeTask?.cancel()
        fadeTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled, store.calls.video, store.calls.phase == .active { controlsVisible = false }
        }
    }

    private func round(_ symbol: String, _ label: String, _ color: Color, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 64, height: 64).background(color, in: Circle())
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                #if DEBUG
                ToolbarItem(placement: .cancellationAction) {
                    ShareLink(item: CallDiagnostics.shared.fileURL) { Label("Call diagnostics", systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("call-diagnostics-share")
                }
                #endif
            }
        }
        .accessibilityIdentifier("calls-screen")
    }
}
