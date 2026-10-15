import LiveKit
import SwiftUI

/// The group call screen (LIME-112b): a grid of up to 9 tiles (a big speaker and a strip above 12 people), the controls in one row, the
/// people list in a sheet. Always dark. A tile says who it is and what state it is in with words and an icon, never colour alone: a
/// muted person has a "Muted" label and a crossed microphone, a person speaking has the waveform and "Speaking", a person whose key has
/// not arrived says "Connecting securely…" and shows no picture. No animation is added, so Reduce Motion needs nothing.
struct GroupCallView: View {
    @Environment(ConversationStore.self) private var store
    @State private var showPeople = false
    @State private var showEmoji = false
    @State private var selfCorner: GroupCallLayout.Corner = .bottomTrailing
    @State private var selfDrag: CGSize = .zero
    @State private var viewSize: CGSize = .zero
    /// The tiles' own area (what the layout is chosen from).
    @State private var areaSize: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// A clear view over the whole screen that system Picture in Picture grows its window from.
    @State private var pipAnchor: UIView?

    private var call: GroupCallManager { store.groupCalls }

    var body: some View {
        let tiles = call.tiles
        VStack(spacing: 0) {
            header.padding(.top, windowControlsMargin).accessibilitySortPriority(3)
            tileArea(tiles)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { areaSize = $0 }
            controls.accessibilitySortPriority(0)
        }
        .background(Color(red: 0.07, green: 0.08, blue: 0.07).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { viewSize = $0 }
        .background(PiPAnchor { pipAnchor = $0 })
        .sheet(isPresented: $showPeople) { GroupPeopleSheet(layout: layoutIsSpeaker ? .speaker : .grid) }
        .sheet(isPresented: $showEmoji) { emojiSheet }
        .onAppear { preparePiP() }
        .onChange(of: call.phase) { _, _ in preparePiP() }
        .onChange(of: call.video) { _, _ in preparePiP() }
        .onChange(of: pipAnchor) { _, _ in preparePiP() }
        .accessibilityIdentifier("group-call-screen")
    }

    /// A windowed iPad scene has iPadOS's own window controls (the "•••") over its top: the header starts below them. Windowed means this
    /// view is smaller than the screen (read from the view itself, which holds in Stage Manager, Split View and Slide Over).
    private var windowControlsMargin: CGFloat {
        let screen = UIScreen.main.bounds.size
        // The screen's size in the view's own orientation.
        let matched = (viewSize.width > viewSize.height) == (screen.width > screen.height) ? screen : CGSize(width: screen.height, height: screen.width)
        // lime is iPhone-only today, so on an iPad it runs in a compatibility window whose idiom says phone: the device model says iPad.
        let isPad = UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.model.hasPrefix("iPad")
        // A compact-width window on an iPad is a Stage Manager, Split View or Slide Over window by definition.
        if isPad && horizontalSizeClass == .compact { return GroupCallLayout.windowControlsMargin(idiomIsPad: true, window: .zero, screen: matched) }
        return GroupCallLayout.windowControlsMargin(idiomIsPad: isPad, window: viewSize, screen: matched)
    }

    /// Whether the speaker layout is the one showing now (the person's choice, else the default for the area's size).
    private var layoutIsSpeaker: Bool { call.effectiveLayout(in: areaSize) == .speaker }

    private func preparePiP() {
        guard call.video, let pipAnchor else { return }
        call.preparePictureInPicture(sourceView: pipAnchor)
    }

    // MARK: Header

    /// The 1:1 call header's look (LIME-147): one pill with the people's pictures, their names (they truncate) and how many are in the call (it
    /// never does), then ›; tapping it opens the people sheet, which also has the layout (Grid / Speaker). Under it: the timer and the
    /// encryption chip. Nothing on the right; Minimise is in the controls row.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            CallNamePill(name: names, count: call.tiles.count, accessibilityLabel: "People in the call, \(call.tiles.count): \(names)", action: { showPeople = true }) { people }
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(status(at: context.date)).monospacedDigit()
                        .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                        .accessibilityIdentifier("call-status")
                }
                if call.phase == .active {
                    CallEmojiChip(emoji: call.verificationEmoji, waiting: call.emojiWaiting, spokenPrefix: "Encrypted call.",
                                  hint: "Opens how to check it. They change when people join or leave") { showEmoji = true }
                }
            }
            .padding(.leading, 8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
    }

    /// "Jean, Shem, Lee": the first names of the people in the call, in tile order.
    private var names: String {
        call.tiles.map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name }.joined(separator: ", ")
    }

    /// Up to three of the people's pictures, overlapping.
    private var people: some View {
        HStack(spacing: -10) {
            ForEach(Array(call.tiles.prefix(3).enumerated()), id: \.element.id) { index, tile in
                AvatarView(person: Person(id: tile.userID.isEmpty ? tile.id : tile.userID, name: tile.name), size: 26)
                    .overlay(Circle().stroke(Color(red: 0.07, green: 0.08, blue: 0.07), lineWidth: 1.5))
                    .zIndex(Double(3 - index))
            }
        }
        .accessibilityHidden(true)
    }

    private var emojiSheet: some View {
        CallEmojiSheet(emoji: call.verificationEmoji,
                       explanation: "Compare these 4 with everyone in the call. If you all see the same 4, nobody else can see or hear the call.",
                       changeNote: "They change when someone joins or leaves, so compare again.",
                       footnote: "They check the call\u{2019}s keys, not who each person is. Use Verify in person to check a person\u{2019}s account.",
                       height: 440)
    }

    private func status(at date: Date) -> String {
        switch call.phase {
        case .idle: return ""
        case .connecting: return "Connecting\u{2026}"
        case .active: return CallRecord.clock(date.timeIntervalSince(call.startedAt ?? date))
        }
    }

    // MARK: Layouts

    private func visible(_ tiles: [GroupCallManager.Tile], limit: Int) -> [GroupCallManager.Tile] {
        guard tiles.count > limit else { return tiles }
        // Who is speaking comes first, then everyone in the order they joined; I am always shown.
        let speaking = tiles.filter { $0.speaking && !$0.isMe }
        let rest = tiles.filter { !$0.speaking || $0.isMe }
        var chosen = Array((speaking + rest).prefix(limit))
        if let me = tiles.first(where: \.isMe), !chosen.contains(where: { $0.id == me.id }) { chosen[chosen.count - 1] = me }
        return tiles.filter { tile in chosen.contains { $0.id == tile.id } }
    }

    /// The tiles in the layout that fits: the grid, or the speaker large with the others in a strip (one-on-one: the other person fills the
    /// area). Chosen from this area's size, so a short landscape strip or a small window gets the speaker layout by itself.
    private func tileArea(_ tiles: [GroupCallManager.Tile]) -> some View {
        GeometryReader { geo in
            let mode = call.effectiveLayout(in: geo.size)
            if mode == .speaker && tiles.count >= 2 {
                spotlightLayout(tiles, in: geo.size)
            } else {
                gridLayout(tiles)
            }
        }
    }

    private func spotlightLayout(_ tiles: [GroupCallManager.Tile], in size: CGSize) -> some View {
        let others = tiles.filter { !$0.isMe }
        let speaker = others.first { $0.id == call.spotlightID } ?? others.first
        let strip = others.filter { $0.id != speaker?.id }
        let me = tiles.first(where: \.isMe)
        let layout = GroupCallLayout.spotlight(others: strip.count, in: size) ?? GroupCallLayout.Spotlight(speaker: CGRect(origin: .zero, size: size), strip: [])
        return ZStack(alignment: .topLeading) {
            if let speaker {
                GroupTileView(tile: speaker, video: call.video, large: true, fixedShape: true)
                    .frame(width: layout.speaker.width, height: layout.speaker.height)
                    .position(x: layout.speaker.midX, y: layout.speaker.midY)
                    .accessibilitySortPriority(3)
            }
            ForEach(Array(zip(strip, layout.strip)), id: \.0.id) { tile, frame in
                GroupTileView(tile: tile, video: call.video, large: false, fixedShape: true, compact: frame.width < 170)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .accessibilitySortPriority(1)
            }
            if let me {
                // My picture floats over the speaker's own tile, so it never covers the strip.
                let base = GroupCallLayout.selfView(in: layout.speaker.size, corner: selfCorner)
                let frame = base.offsetBy(dx: layout.speaker.minX, dy: layout.speaker.minY)
                GroupTileView(tile: me, video: call.video, large: false, fixedShape: true, compact: true)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX + selfDrag.width, y: frame.midY + selfDrag.height)
                    .gesture(DragGesture()
                        .onChanged { selfDrag = $0.translation }
                        .onEnded { value in
                            let centre = CGPoint(x: frame.midX + value.translation.width - layout.speaker.minX, y: frame.midY + value.translation.height - layout.speaker.minY)
                            selfCorner = GroupCallLayout.nearestCorner(to: centre, in: layout.speaker.size)
                            selfDrag = .zero
                        })
                    .accessibilitySortPriority(0.5)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: layout)
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .contain)
    }

    /// The grid fills the visible area: no scrolling at any size, tiles shrink to fit and keep a video shape (`GroupCallLayout`). With three or
    /// more people my own picture is a small floating tile in a corner (drag it to another corner) instead of one of the grid's tiles.
    private func gridLayout(_ tiles: [GroupCallManager.Tile]) -> some View {
        let shown = visible(tiles, limit: 9)
        let floating = shown.count >= 3 ? shown.first(where: \.isMe) : nil
        let others = shown.filter { $0.id != floating?.id }
        return GeometryReader { geo in
            let frames = GroupCallLayout.grid(count: others.count, in: geo.size)
            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(others, frames)), id: \.0.id) { tile, frame in
                    GroupTileView(tile: tile, video: call.video, large: false, fixedShape: true)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .accessibilitySortPriority(tile.speaking ? 2 : 1)
                }
                if let floating {
                    let frame = GroupCallLayout.selfView(in: geo.size, corner: selfCorner)
                    GroupTileView(tile: floating, video: call.video, large: false, fixedShape: true)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX + selfDrag.width, y: frame.midY + selfDrag.height)
                        .gesture(DragGesture()
                            .onChanged { selfDrag = $0.translation }
                            .onEnded { value in
                                let end = CGPoint(x: frame.midX + value.translation.width, y: frame.midY + value.translation.height)
                                selfCorner = GroupCallLayout.nearestCorner(to: end, in: geo.size)
                                selfDrag = .zero
                            })
                        .accessibilitySortPriority(0.5)
                }
                if tiles.count > shown.count {
                    Text("+\(tiles.count - shown.count) more").font(.footnote).foregroundStyle(.white.opacity(0.7)).padding(8)
                        .background(.black.opacity(0.4), in: Capsule()).position(x: geo.size.width / 2, y: geo.size.height - 14)
                        .accessibilityLabel("\(tiles.count - shown.count) more people, see the people list")
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: frames)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selfCorner)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Controls

    /// The controls in one row that always shows Leave: the buttons shrink (56, 50, then 44 pt) before anything would need to scroll.
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { buttons(size: 56) }
            HStack(spacing: 10) { buttons(size: 50) }
            HStack(spacing: 6) { buttons(size: 44) }
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) { buttons(size: 44) }.padding(.horizontal, 16) }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
    }

    @ViewBuilder private func buttons(size: CGFloat) -> some View {
        control(call.muted ? "mic.slash.fill" : "mic.fill", label: call.muted ? "Unmute" : "Mute", on: call.muted, id: "group-call-mute", size: size) { Task { await call.setMuted(!call.muted) } }
        if call.video {
            control(call.cameraOn ? "video.fill" : "video.slash.fill", label: call.cameraOn ? "Turn camera off" : "Turn camera on", on: !call.cameraOn, id: "group-call-camera", size: size) { Task { await call.toggleCamera() } }
            control("arrow.triangle.2.circlepath.camera", label: "Flip camera", on: false, id: "group-call-flip", size: size) { Task { await call.flipCamera() } }
        }
        control("arrow.down.right.and.arrow.up.left", label: "Minimise", on: false, id: "group-call-minimise-control", size: size) { call.minimize() }
        control(call.speakerOn ? "speaker.wave.3.fill" : "speaker.fill", label: call.speakerOn ? "Speaker on" : "Speaker off", on: call.speakerOn, id: "group-call-speaker", size: size) { call.toggleSpeaker() }
        Button { Task { await call.leave() } } label: {
            Image(systemName: "phone.down.fill").font(.system(size: size * 0.4)).foregroundStyle(.white)
                .frame(width: size, height: size).background(Color.red, in: Circle())
        }
        .accessibilityLabel("Leave call").accessibilityIdentifier("group-call-leave")
    }

    private func control(_ symbol: String, label: String, on: Bool, id: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size * 0.36)).foregroundStyle(on ? Color.black : Color.white)
                .frame(width: size, height: size).background(on ? Color.white : Color.white.opacity(0.18), in: Circle())
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// One person's tile.
struct GroupTileView: View {
    @Environment(ConversationStore.self) private var store
    let tile: GroupCallManager.Tile
    let video: Bool
    let large: Bool
    /// The grid sets this tile's exact frame (`GroupCallLayout`): no shape of its own.
    var fixedShape = false
    /// A small tile (the strip, my floating picture): the pill shows the name and its icon, not the word "Muted" (VoiceOver still says it).
    var compact = false

    private var stateWords: String {
        if !tile.secured { return "Connecting securely" }
        var parts: [String] = []
        if tile.muted { parts.append("Muted") }
        if video && !tile.cameraOn { parts.append("Camera off") }
        if tile.speaking { parts.append("Speaking") }
        return parts.joined(separator: ", ")
    }

    private var track: LiveKit.VideoTrack? {
        guard tile.secured, video, tile.cameraOn else { return nil }
        return store.groupCalls.videoTrack(for: tile.id) as? LiveKit.VideoTrack
    }

    /// Their name and state, as a pill (a crossed microphone and "Muted", or a waveform when speaking).
    private var namePill: some View {
        HStack(spacing: 6) {
            if tile.muted { Image(systemName: "mic.slash.fill").font(.caption) }
            else if tile.speaking { Image(systemName: "waveform").font(.caption) }
            Text(tile.name).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            if tile.muted && !compact { Text("Muted").font(.caption2).lineLimit(1) }
        }
        .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 4)
        .background(.black.opacity(0.55), in: Capsule()).padding(6)
    }

    var body: some View {
        // A read of the pictures version makes a tile look its track up again when one changes.
        let _ = store.groupCalls.picturesVersion
        Group {
            if let track {
                // A picture fills the tile and the name sits on it.
                ZStack(alignment: .bottomLeading) {
                    Color.white.opacity(0.10)
                    SwiftUIVideoView(track, layoutMode: .fill, mirrorMode: tile.isMe ? .mirror : .auto)
                    namePill
                }
            } else {
                // No picture: the status (or the photo) takes the room above and the name pill sits below it, so they never overlap,
                // however large the text.
                VStack(spacing: 0) {
                    picture.frame(maxWidth: .infinity, maxHeight: .infinity)
                    namePill.frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.white.opacity(0.10))
            }
        }
        .modifier(TileShape(fixed: fixedShape, large: large))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Speaking is also shown by a ring (and by the waveform and the words), not by colour alone.
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white, lineWidth: tile.speaking ? 3 : 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.name)
        .accessibilityValue(stateWords)
        .accessibilityIdentifier("group-tile-\(tile.id)")
    }

    @ViewBuilder private var picture: some View {
        if !tile.secured {
            VStack(spacing: 6) {
                ProgressView().tint(.white)
                Text("Connecting securely\u{2026}").font(.footnote).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
        } else {
            initials
        }
    }

    private var initials: some View {
        // Their photo (mine on my own tile), or their initials on their colour: the same as everywhere else in lime.
        let person = Person(id: tile.userID.isEmpty ? tile.id : tile.userID, name: tile.name)
        return AvatarView(person: person, size: large ? 120 : 64)
            // Its photo is shown (or initials on its colour) with no status badge here.
    }
}

/// Who is in the call: names with their state in words, readable at the largest text sizes.
struct GroupPeopleSheet: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The layout showing now (the person's choice, else the default for the screen).
    let layout: GroupCallLayout.Mode

    var body: some View {
        NavigationStack {
            List {
                Section("Layout") {
                    layoutRow("Grid", symbol: "square.grid.2x2", mode: .grid)
                    layoutRow("Speaker", symbol: "person.crop.rectangle", mode: .speaker)
                }
                Section("People") {
                    ForEach(store.groupCalls.tiles) { tile in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tile.name).font(.body)
                            Text(detail(tile)).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .navigationTitle("In this call")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    /// One row of the layout choice: the current one is checked (a check and the word "selected" for VoiceOver, never colour alone).
    private func layoutRow(_ title: String, symbol: String, mode: GroupCallLayout.Mode) -> some View {
        Button { store.groupCalls.chooseLayout(mode) } label: {
            HStack {
                Label(title, systemImage: symbol).foregroundStyle(.primary)
                Spacer()
                if layout == mode { Image(systemName: "checkmark").foregroundStyle(.primary) }
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Layout: \(title)")
        .accessibilityValue(layout == mode ? "Selected" : "")
        .accessibilityAddTraits(layout == mode ? .isSelected : [])
        .accessibilityIdentifier("group-call-layout-\(title.lowercased())")
    }

    private func detail(_ tile: GroupCallManager.Tile) -> String {
        var parts: [String] = []
        parts.append(tile.muted ? "Muted" : "Microphone on")
        if store.groupCalls.video { parts.append(tile.cameraOn ? "Camera on" : "Camera off") }
        if !tile.secured { parts.append("Connecting securely") }
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// A group call that is ringing: who, which group, and Join or Decline. (The system call screen rings too, while lime is open or recent.)
struct GroupIncomingBanner: View {
    @Environment(ConversationStore.self) private var store

    var body: some View {
        if let ring = store.groupCalls.incoming, !store.groupCalls.inCall {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ring.callerName) started a \(ring.video ? "video" : "voice") call").font(.subheadline.weight(.semibold))
                    Text(ring.title).font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Decline") { store.groupCalls.declineIncoming() }
                    .frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("group-call-decline")
                if ring.video {
                    // A video call: join with the camera or with sound only.
                    Button("Voice") { Task { await store.groupCalls.acceptIncoming(withVideo: false) } }
                        .frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("group-call-join-voice")
                }
                Button(ring.video ? "Video" : "Join") { Task { await store.groupCalls.acceptIncoming(withVideo: ring.video) } }
                    .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(Theme.accentInk)
                    .frame(minHeight: 44).accessibilityIdentifier("group-call-join")
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 12).padding(.top, 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("group-call-incoming")
        }
    }
}

/// A clear, full-size view whose UIKit view is handed to the manager: system Picture in Picture opens its window from it.
private struct PiPAnchor: UIViewRepresentable {
    let ready: (UIView) -> Void
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async { ready(view) }
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {}
}

/// "3 people are in a call", offered when a call starts in one of my groups and lime is open but elsewhere (LIME-146): the group, who is
/// there, and Dismiss or Join. (A group that rings shows the incoming banner instead; this is for the ones that do not ring.)
struct GroupInviteSheet: View {
    @Environment(ConversationStore.self) private var store

    var body: some View {
        let _ = store.groupCalls.changes
        if let invite = store.groupCalls.invite {
            let summary = store.groupCalls.liveSummary(conversationID: invite.conversationID)
            let people = summary?.people ?? []
            let count = Int(summary?.info.participantCount ?? 0)
            VStack(spacing: 14) {
                Capsule().fill(.secondary.opacity(0.4)).frame(width: 36, height: 5).padding(.top, 8)
                if let chat = store.conversation(invite.conversationID) { ConversationAvatar(conversation: chat, size: 56) }
                Text(count == 1 ? "1 person is in a call" : (count == 0 ? "A call has started" : "\(count) people are in a call"))
                    .font(Theme.title).foregroundStyle(Theme.text).multilineTextAlignment(.center)
                Text(invite.title).font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                if !people.isEmpty {
                    HStack(spacing: -10) {
                        ForEach(people.prefix(6)) { person in AvatarView(person: person, size: 44).overlay(Circle().stroke(Theme.canvas, lineWidth: 2)) }
                    }
                }
                Text(LiveCardWords.who(people.map(\.name), count: count)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button { store.groupCalls.dismissInvite() } label: {
                        Text("Dismiss").font(Theme.body.weight(.semibold)).foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity, minHeight: 48).background(Theme.surface, in: Capsule())
                    }
                    .accessibilityIdentifier("group-invite-dismiss")
                    Button { Task { await store.groupCalls.acceptInvite() } } label: {
                        Text("Join").font(Theme.body.weight(.semibold)).foregroundStyle(Theme.accentInk)
                            .frame(maxWidth: .infinity, minHeight: 48).background(Theme.accent, in: Capsule())
                    }
                    .accessibilityIdentifier("group-invite-join")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                if invite.video {
                    Button("Join with voice only") { Task { await store.groupCalls.acceptInvite(withVideo: false) } }
                        .font(Theme.secondary).frame(minHeight: 44).accessibilityIdentifier("group-invite-join-voice")
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
            .presentationDetents([.height(invite.video ? 340 : 300), .medium])
            .presentationBackground(Theme.canvas)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("group-invite-sheet")
        }
    }
}

/// A tile's own shape (the speaker view's strip and big tile), or none when the grid has already fixed its frame.
private struct TileShape: ViewModifier {
    let fixed: Bool
    let large: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if fixed {
            content
        } else {
            content.aspectRatio(large ? nil : 3.0 / 4.0, contentMode: .fit).frame(maxWidth: .infinity, maxHeight: large ? .infinity : nil)
        }
    }
}
