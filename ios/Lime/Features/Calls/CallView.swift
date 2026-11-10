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

/// When a video call's controls may hide (LIME-130-1): never while VoiceOver or Switch Control is running (a person using them cannot tap the picture to bring them back);
/// for everyone else after five seconds, as before.
enum CallControlsPolicy {
    static func mayAutoHide(voiceOver: Bool, switchControl: Bool) -> Bool { !voiceOver && !switchControl }

    @MainActor static var voiceOverRunning: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lime-force-voiceover") { return true }   // UI tests: the simulator has no VoiceOver switch
        #endif
        return UIAccessibility.isVoiceOverRunning
    }
    @MainActor static var switchControlRunning: Bool { UIAccessibility.isSwitchControlRunning }

    /// Whether the controls are hidden now: a video call, nobody using an assistive tool, and the five seconds have passed.
    static func hidden(video: Bool, visible: Bool, voiceOver: Bool, switchControl: Bool) -> Bool {
        video && !visible && mayAutoHide(voiceOver: voiceOver, switchControl: switchControl)
    }
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
    @State private var showEmoji = false
    /// VoiceOver or Switch Control is running: the controls stay (LIME-130-1).
    @State private var voiceOver = CallControlsPolicy.voiceOverRunning
    @State private var switchControl = CallControlsPolicy.switchControlRunning
    @AccessibilityFocusState private var focus: CallFocus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let tile = CGSize(width: 108, height: 148)

    var body: some View {
        let call = store.calls
        GeometryReader { geo in
            ZStack {
                background(call, in: geo.size)
                if call.video {
                    // The picture fills the whole screen. It is an overlay on a safe-area-sized clear view, moved back by the insets, so
                    // it can be bigger than the screen's safe area without making the header and the controls (which stay inside it) move.
                    let full = screen(of: geo)
                    Color.clear.frame(width: geo.size.width, height: geo.size.height)
                        .overlay(alignment: .topLeading) {
                            videoLayers(call, in: full, safe: geo.safeAreaInsets)
                                .frame(width: full.width, height: full.height, alignment: .topLeading)
                                .offset(x: -geo.safeAreaInsets.leading, y: -geo.safeAreaInsets.top)
                        }
                }
                VStack(alignment: .leading, spacing: 6) {
                    header(call)
                    if call.phase == .outgoing && call.showUnreachableHint {
                        Text(CallAnnouncements.unreachable(name: call.peerName))
                            .font(Theme.font(.footnote)).foregroundStyle(.white.opacity(0.9)).callTextScrim()
                            .accessibilityIdentifier("call-unreachable-hint")
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.top, 8)
                if let toast = call.route.toast {
                    Text(toast).font(Theme.font(.footnote, weight: .medium)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.black.opacity(0.6), in: Capsule())
                        .frame(maxHeight: .infinity, alignment: .top).padding(.top, 70)
                        .accessibilityIdentifier("call-route-toast")
                }
                if !call.video && call.phase != .incoming {
                    // Voice: the Minimise button is a glass circle on the name pill's row (the controls row is full on a small phone).
                    Button { call.minimize() } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).callRoundBackground()
                    }
                    .accessibilityLabel("Minimise").accessibilityIdentifier("call-minimize")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(.top, 8).padding(.trailing, 16)
                }
                let hidden = controlsHidden(call)
                controls(call, landscape: geo.size.width > geo.size.height)
                    .opacity(hidden ? 0 : 1)
                    .allowsHitTesting(!hidden)
                    .accessibilityHidden(hidden)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: controlsVisible)
                if hidden {
                    // The controls are away (a touch user): the picture is one button, so Voice Control ("Tap Show call controls") and Switch Control can bring
                    // them back. It takes no touches itself; a tap on the picture is the gesture below, as before.
                    Color.clear.allowsHitTesting(false)
                        .accessibilityElement().accessibilityLabel("Show call controls").accessibilityAddTraits(.isButton)
                        .accessibilityAction { showControls(); focusMuteSoon() }
                        .accessibilityIdentifier("call-show-controls")
                }
            }
            // Pinned to the screen, so no layer can widen the layout (a 400 pt background once pushed the controls off a 375 pt screen).
            .frame(width: geo.size.width, height: geo.size.height)
            .background {
                ZStack {
                    Color.black.ignoresSafeArea().accessibilityIdentifier("call-screen")
                    blurredBackdrop(call)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if call.video { showControls() } }
            .onAppear { showControls(); preparePictureInPicture(call); focusFirstControlSoon(call) }
            .onChange(of: call.phase) { _, _ in showControls(); preparePictureInPicture(call) }
            .onChange(of: call.video) { _, _ in preparePictureInPicture(call) }
            .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
                voiceOver = CallControlsPolicy.voiceOverRunning
                showControls()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.switchControlStatusDidChangeNotification)) { _ in
                switchControl = CallControlsPolicy.switchControlRunning
                showControls()
            }
        }
        .sheet(isPresented: $showPerson) { personSheet(call) }
        .sheet(isPresented: $showEmoji) { emojiSheet(call) }
        .preferredColorScheme(.dark)
    }

    // MARK: Layers

    private var person: (ConversationStore) -> Person = { store in Person(id: store.calls.peerID, name: store.calls.peerName) }

    /// The blurred avatar behind everything: it takes the whole screen (the safe areas too) and is clipped to it, so it can never be
    /// wider than the screen.
    @ViewBuilder
    private func blurredBackdrop(_ call: CallManager) -> some View {
        if !(call.video && (swapped ? call.cameraOn : call.remoteVideoShowing)) {
            AvatarView(person: person(store), size: 480).blur(radius: 60).opacity(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func background(_ call: CallManager, in size: CGSize) -> some View {
        // The avatar fills the screen until there is a picture to show big: the other person's video, or mine after a swap.
        let pictureBig = call.video && (swapped ? call.cameraOn : call.remoteVideoShowing)
        if !pictureBig {
            AvatarView(person: person(store), size: 160)
                .accessibilityIdentifier("call-avatar")
                .frame(width: size.width, height: size.height)
        }
    }

    @ViewBuilder
    private func videoLayers(_ call: CallManager, in size: CGSize, safe: EdgeInsets) -> some View {
        let tileOrigin = origin(of: corner, in: size, safe: safe)
        // Two fixed views, laid out as the big picture or as the tile (a UIView cannot move between parents).
        let remoteBig = !swapped
        ZStack(alignment: .topLeading) {
            layer(call.media?.remoteView, placeholder: remoteBig ? Color.clear : Color(white: 0.2), id: "call-remote-view")
                .frame(width: remoteBig ? size.width : tile.width, height: remoteBig ? size.height : tile.height)
                .clipShape(RoundedRectangle(cornerRadius: remoteBig ? 0 : 14))
                .offset(x: remoteBig ? 0 : tileOrigin.x + drag.width, y: remoteBig ? 0 : tileOrigin.y + drag.height)
                .zIndex(remoteBig ? 0 : 2)
                .opacity(remoteBig && !call.remoteVideoShowing && call.media != nil ? 0 : 1)
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
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { corner = nearest(to: end, in: size, safe: safe); drag = .zero }
                })
                .onTapGesture { swapPictures() }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "Move to the other corner") { moveToNextCorner() }
                .accessibilityIdentifier("call-tile-handle")
                .accessibilityLabel("Swap the pictures")
        }
    }

    @ViewBuilder
    private func layer(_ view: UIView?, placeholder: Color, id: String) -> some View {
        if let view { VideoSurface { view }.accessibilityIdentifier(id) } else { placeholder.accessibilityIdentifier(id) }
    }

    /// The whole screen, edge to edge: the picture and the background fill it under the status bar and the home indicator (the
    /// controls stay inside the safe area). `geo` is the safe area's size, so the insets are added back.
    private func screen(of geo: GeometryProxy) -> CGSize {
        CGSize(width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
               height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
    }

    /// The tile's corners, in screen coordinates (the video layers start at the top-left of the whole screen); the margins are from
    /// the safe area's edges so the tile never sits under the status bar or the controls.
    private func origin(of corner: Corner, in size: CGSize, safe: EdgeInsets) -> CGPoint {
        let margin: CGFloat = 16, top: CGFloat = 70, bottom: CGFloat = 110
        let left = safe.leading + margin, right = safe.trailing + margin
        switch corner {
        case .topLeading: return CGPoint(x: left, y: top + 50)
        case .topTrailing: return CGPoint(x: size.width - tile.width - right, y: top)
        case .bottomLeading: return CGPoint(x: left, y: size.height - tile.height - bottom - safe.bottom)
        case .bottomTrailing: return CGPoint(x: size.width - tile.width - right - 70, y: size.height - tile.height - bottom - safe.bottom)
        }
    }

    private func nearest(to point: CGPoint, in size: CGSize, safe: EdgeInsets) -> Corner {
        Corner.allCases.min { lhs, rhs in
            let a = origin(of: lhs, in: size, safe: safe), b = origin(of: rhs, in: size, safe: safe)
            let da = hypot(a.x + tile.width / 2 - point.x, a.y + tile.height / 2 - point.y)
            let db = hypot(b.x + tile.width / 2 - point.x, b.y + tile.height / 2 - point.y)
            return da < db
        } ?? .topTrailing
    }

    private func swapPictures() {
        withAnimation(reduceMotion ? nil : .default) { swapped.toggle() }
        showControls()
    }

    /// The non-drag way to move my picture (WCAG 2.5.7): the next corner, round the screen.
    private func moveToNextCorner() {
        let all = Corner.allCases, next = all[((all.firstIndex(of: corner) ?? 0) + 1) % all.count]
        withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { corner = next }
        showControls()
    }

    // MARK: Header


    private func header(_ call: CallManager) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CallNamePill(name: call.peerName, accessibilityLabel: "\(call.peerName), details", action: { showPerson = true }) {
                AvatarView(person: person(store), size: 28)
            }
            HStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(call.statusText(at: context.date)).monospacedDigit()
                        .font(Theme.font(.subheadline)).foregroundStyle(.white.opacity(0.9)).callTextScrim()
                        .accessibilityIdentifier("call-status")
                }
                if call.phase == .active {
                    CallEmojiChip(emoji: call.verificationEmoji, spokenPrefix: "Encrypted call.", hint: "Opens how to check it") { showEmoji = true }
                }
                if call.remoteMuted && call.phase == .active {
                    Label("Muted", systemImage: "mic.slash.fill").labelStyle(.titleAndIcon)
                        .font(Theme.font(.caption, weight: .semibold)).foregroundStyle(.white)
                        .callTextScrim()
                        .accessibilityLabel("\(call.peerName) is muted")
                        .accessibilityIdentifier("call-remote-muted")
                }
            }
            .padding(.leading, 8)
            .onChange(of: call.remoteMuted) { _, muted in
                UIAccessibility.post(notification: .announcement, argument: "\(call.peerName) \(muted ? "muted" : "unmuted")")
            }
            if call.cameraPaused {
                Text(CallAnnouncements.cameraPaused)
                    .font(Theme.font(.footnote)).foregroundStyle(.white.opacity(0.9)).callTextScrim().padding(.leading, 8)
                    .accessibilityIdentifier("call-camera-paused")
            }
        }
    }

    private func emojiSheet(_ call: CallManager) -> some View {
        CallEmojiSheet(emoji: call.verificationEmoji,
                       explanation: "If you both see these same 4 emoji, in this order, your call is end-to-end encrypted and no one is in between. Read them to each other.",
                       footnote: "They belong to this call only. They are different from Verify in person, which checks a person\u{2019}s account.")
    }

    private func personSheet(_ call: CallManager) -> some View {
        ScrollView {
        VStack(spacing: 16) {
            AvatarView(person: person(store), size: 88).padding(.top, 24)
            Text(call.peerName).font(Theme.font(.title2, weight: .semibold))
            Button {
                showPerson = false
                call.minimize()
                store.openFromNotification("dm:\(call.peerID)", thread: nil)
            } label: {
                Label("Message", systemImage: "message").font(Theme.font(.headline, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(Theme.accentInk)
            .accessibilityIdentifier("call-person-message")
        }
        .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .presentationDetents([.height(300), .large])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("call-person-sheet")
    }

    // MARK: Controls

    @ViewBuilder
    private func controls(_ call: CallManager, landscape: Bool) -> some View {
        if call.phase == .incoming && !call.showsAnswerButtons {
            // iOS's own call screen has Answer and Decline (LIME-177): this screen only says who is calling.
            Color.clear.frame(height: 0).accessibilityHidden(true)
        } else if call.phase == .incoming {
            HStack(spacing: 80) {
                round("phone.down.fill", "Decline", Theme.dangerFill, id: "call-decline") { Task { await call.decline() } }
                round("phone.fill", "Accept", Color(uiColor: UIColor(hex: LimeColours.accentHex[LimeColours.lime])), ink: Color(uiColor: UIColor(hex: 0x131B17)), id: "call-accept") { Task { await call.accept() } }
            }
            .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 48)
        } else if call.video && landscape {
            // Landscape is short: the column would not fit, so the same buttons run along the bottom.
            HStack(spacing: 14) {
                toggle("arrow.triangle.2.circlepath.camera", "Flip camera", on: false, id: "call-flip", focus: .first) { call.flipCamera(); showControls() }
                CallEffectsButton(size: 56, id: "call-effects", support: { call.effectsSupport }) { call.perform($0); showControls() }
                toggle(CallToggleIcon.camera(on: call.cameraOn), "Camera", on: !call.cameraOn, value: CallAnnouncements.value(call.cameraOn), selected: call.cameraOn, id: "call-video", focus: nil) { call.toggleCamera(); showControls() }
                toggle(CallToggleIcon.mute(muted: call.muted), "Mute", on: call.muted, value: CallAnnouncements.value(call.muted), selected: call.muted, id: "call-mute", focus: .mute) { call.setMuted(!call.muted); showControls() }
                toggle("arrow.down.right.and.arrow.up.left", "Minimise", on: false, id: "call-minimize") { call.minimize() }
                routeButton(call)
                round("xmark", "End call", Theme.dangerFill, id: "call-end") { Task { await call.end() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 20)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("call-controls-video")
        } else if call.video {
            ZStack {
                VStack(spacing: 14) {
                    Spacer()
                    CallEffectsButton(size: 56, id: "call-effects", support: { call.effectsSupport }) { call.perform($0); showControls() }
                    toggle(CallToggleIcon.camera(on: call.cameraOn), "Camera", on: !call.cameraOn, value: CallAnnouncements.value(call.cameraOn), selected: call.cameraOn, id: "call-video", focus: .first) { call.toggleCamera(); showControls() }
                    toggle(CallToggleIcon.mute(muted: call.muted), "Mute", on: call.muted, value: CallAnnouncements.value(call.muted), selected: call.muted, id: "call-mute", focus: .mute) { call.setMuted(!call.muted); showControls() }
                    toggle("arrow.down.right.and.arrow.up.left", "Minimise", on: false, id: "call-minimize") { call.minimize() }
                    routeButton(call)
                    round("xmark", "End call", Theme.dangerFill, id: "call-end") { Task { await call.end() } }
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
            // Four 56 pt buttons and a 64 pt End: on a 375 pt phone the gaps are 12, not 22, so the margins stay above 16.
            HStack(spacing: 12) {
                toggle("video.fill", "Video", on: false, id: "call-start-video", focus: .first) { Task { await call.startVideo() } }
                toggle(CallToggleIcon.mute(muted: call.muted), "Mute", on: call.muted, value: CallAnnouncements.value(call.muted), selected: call.muted, id: "call-mute") { call.setMuted(!call.muted) }
                toggle(CallToggleIcon.speaker(on: call.speaker), "Speaker", on: call.speaker, value: CallAnnouncements.value(call.speaker), selected: call.speaker, id: "call-speaker") { call.toggleSpeaker() }
                routeButton(call)
                round("phone.down.fill", "End call", Theme.dangerFill, id: "call-end") { Task { await call.end() } }
            }
            .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 48)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("call-controls-voice")
        }
    }

    /// The system output picker, labelled with where the sound is now.
    private func routeButton(_ call: CallManager) -> some View {
        ZStack {
            Circle().fill(Color.clear).frame(width: 56, height: 56).callRoundBackground()
            RoutePicker().frame(width: 40, height: 40)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Audio output, now \(call.route.name)")
        .accessibilityIdentifier("call-route")
    }

    /// System Picture in Picture needs the call's picture on screen to start from.
    private func preparePictureInPicture(_ call: CallManager) {
        guard call.video, call.phase == .active, let view = call.media?.remoteView else { return }
        call.preparePictureInPicture(sourceView: view)
    }

    /// When the call screen opens with VoiceOver or Switch Control on, focus starts on the first control, not the picture behind it (LIME-130-4a).
    private func focusFirstControlSoon(_ call: CallManager) {
        guard CallControlsPolicy.voiceOverRunning || CallControlsPolicy.switchControlRunning, call.phase != .incoming else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            focus = .first
        }
    }

    private func controlsHidden(_ call: CallManager) -> Bool {
        CallControlsPolicy.hidden(video: call.video, visible: controlsVisible, voiceOver: voiceOver, switchControl: switchControl)
    }

    /// After "Show call controls": VoiceOver's focus goes to Mute (once the controls are back).
    private func focusMuteSoon() {
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            focus = .mute
        }
    }

    private func showControls() {
        controlsVisible = true
        fadeTask?.cancel()
        guard CallControlsPolicy.mayAutoHide(voiceOver: CallControlsPolicy.voiceOverRunning, switchControl: CallControlsPolicy.switchControlRunning) else { return }
        fadeTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled, store.calls.video, store.calls.phase == .active { controlsVisible = false }
        }
    }

    /// A round call button: a white glyph on `color`, or (Accept) lime's ink on lime green (LIME-130-2: 4.5:1 either way).
    private func round(_ symbol: String, _ label: String, _ color: Color, ink: Color = .white, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 24, weight: .semibold)).foregroundStyle(ink)
                .frame(width: 64, height: 64).background(color, in: Circle())
        }
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }

    /// A round toggle. `on` is the lit look; `value` ("On"/"Off") and `selected` are what VoiceOver gets, and the glyph changes shape with the state.
    private func toggle(_ symbol: String, _ label: String, on: Bool, value: String? = nil, selected: Bool = false, id: String, focus: CallFocus? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(on ? .black : .white)
                .frame(width: 56, height: 56).callRoundBackground(lit: on)
        }
        .accessibilityLabel(label).accessibilityIdentifier(id)
        .modifier(ToggleState(value: value, selected: selected))
        .modifier(OptionalAccessibilityFocus(state: $focus, target: focus))
    }
}

/// The value ("On"/"Off") and the selected trait of a toggling call button.
private struct ToggleState: ViewModifier {
    let value: String?
    let selected: Bool
    func body(content: Content) -> some View {
        if let value { content.accessibilityValue(value).accessibilityAddTraits(selected ? .isSelected : []) } else { content }
    }
}

/// `accessibilityFocused` when the button is a focus target.
private struct OptionalAccessibilityFocus: ViewModifier {
    var state: AccessibilityFocusState<CallFocus?>.Binding
    let target: CallFocus?
    func body(content: Content) -> some View {
        if let target { content.accessibilityFocused(state, equals: target) } else { content }
    }
}
