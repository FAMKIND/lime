import LiveKit
import SwiftUI

/// The group call screen (LIME-112b): a grid of up to 9 tiles (a big speaker and a strip above 12 people), the controls in one row, the
/// people list in a sheet. Always dark. A tile says who it is and what state it is in with words and an icon, never colour alone: a
/// muted person has a "Muted" label and a crossed microphone, a person speaking has the waveform and "Speaking", a person whose key has
/// not arrived says "Connecting securely…" and shows no picture. No animation is added, so Reduce Motion needs nothing.
struct GroupCallView: View {
    @Environment(ConversationStore.self) private var store
    @State private var showPeople = false

    private var call: GroupCallManager { store.groupCalls }

    var body: some View {
        let tiles = call.tiles
        VStack(spacing: 0) {
            header
            Group {
                if call.speakerViewByDefault {
                    speakerLayout(tiles)
                } else {
                    gridLayout(tiles)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            controls
        }
        .background(Color(red: 0.07, green: 0.08, blue: 0.07).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPeople) { GroupPeopleSheet() }
        .accessibilityIdentifier("group-call-screen")
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Button { call.minimized = true } label: {
                Image(systemName: "chevron.down").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Minimise call").accessibilityIdentifier("group-call-minimise")
            VStack(alignment: .leading, spacing: 1) {
                Text(call.title).font(.headline).lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(status(at: context.date)).font(.footnote).foregroundStyle(.white.opacity(0.75))
                }
            }
            Spacer(minLength: 0)
            Button { showPeople = true } label: {
                Label("\(call.tiles.count)", systemImage: "person.2.fill").font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12).frame(minHeight: 44)
            }
            .accessibilityLabel("People in the call, \(call.tiles.count)").accessibilityIdentifier("group-call-people")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
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

    private func gridLayout(_ tiles: [GroupCallManager.Tile]) -> some View {
        let shown = visible(tiles, limit: 9)
        let columns = shown.count <= 1 ? 1 : (shown.count <= 4 ? 2 : 3)
        let items = Array(repeating: GridItem(.flexible(), spacing: 6), count: columns)
        return ScrollView {
            LazyVGrid(columns: items, spacing: 6) {
                ForEach(shown) { tile in GroupTileView(tile: tile, video: call.video, large: false) }
            }
            if tiles.count > shown.count {
                Text("+\(tiles.count - shown.count) more").font(.footnote).foregroundStyle(.white.opacity(0.7)).padding(8)
                    .accessibilityLabel("\(tiles.count - shown.count) more people, see the people list")
            }
        }
    }

    private func speakerLayout(_ tiles: [GroupCallManager.Tile]) -> some View {
        let speaker = tiles.first { $0.speaking && !$0.isMe } ?? tiles.first { !$0.isMe } ?? tiles.first
        let strip = visible(tiles.filter { $0.id != speaker?.id }, limit: 9)
        return VStack(spacing: 6) {
            if let speaker { GroupTileView(tile: speaker, video: call.video, large: true) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(strip) { tile in GroupTileView(tile: tile, video: call.video, large: false).frame(width: 96, height: 128) }
                }
            }
            .frame(height: 132)
        }
    }

    // MARK: Controls

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { buttons }
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 14) { buttons }.padding(.horizontal, 16) }
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder private var buttons: some View {
        control(call.muted ? "mic.slash.fill" : "mic.fill", label: call.muted ? "Unmute" : "Mute", on: call.muted, id: "group-call-mute") { Task { await call.setMuted(!call.muted) } }
        if call.video {
            control(call.cameraOn ? "video.fill" : "video.slash.fill", label: call.cameraOn ? "Turn camera off" : "Turn camera on", on: !call.cameraOn, id: "group-call-camera") { Task { await call.toggleCamera() } }
            control("arrow.triangle.2.circlepath.camera", label: "Flip camera", on: false, id: "group-call-flip") { Task { await call.flipCamera() } }
        }
        control(call.speakerOn ? "speaker.wave.3.fill" : "speaker.fill", label: call.speakerOn ? "Speaker on" : "Speaker off", on: call.speakerOn, id: "group-call-speaker") { call.toggleSpeaker() }
        Button { Task { await call.leave() } } label: {
            Image(systemName: "phone.down.fill").font(.system(size: 22)).foregroundStyle(.white)
                .frame(width: 56, height: 56).background(Color.red, in: Circle())
        }
        .accessibilityLabel("Leave call").accessibilityIdentifier("group-call-leave")
    }

    private func control(_ symbol: String, label: String, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(on ? Color.black : Color.white)
                .frame(width: 56, height: 56).background(on ? Color.white : Color.white.opacity(0.18), in: Circle())
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
            Text(tile.isMe ? "You" : tile.name).font(.footnote.weight(.semibold)).lineLimit(1)
            if tile.muted { Text("Muted").font(.caption2) }
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
        .aspectRatio(large ? nil : 3.0 / 4.0, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: large ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Speaking is also shown by a ring (and by the waveform and the words), not by colour alone.
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white, lineWidth: tile.speaking ? 3 : 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.isMe ? "You" : tile.name)
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
        let person = Person(id: tile.userID.isEmpty ? tile.id : tile.userID, name: tile.isMe ? "You" : tile.name, tone: abs(tile.id.hashValue) % 8)
        return AvatarView(person: person, size: large ? 120 : 64)
            // Its photo is shown (or initials on its colour) with no status badge here.
    }
}

/// Who is in the call: names with their state in words, readable at the largest text sizes.
struct GroupPeopleSheet: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(store.groupCalls.tiles) { tile in
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.isMe ? "You" : tile.name).font(.body)
                    Text(detail(tile)).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            .navigationTitle("In this call")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
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
                Button("Join") { Task { await store.groupCalls.acceptIncoming() } }
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
