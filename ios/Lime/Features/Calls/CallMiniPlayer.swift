import SwiftUI

/// Which minimised call the mini player shows for (LIME-148c). One call at a time; shown whenever it is minimised, in the group's own chat
/// and while the floating video window is up too, and never on the full call screen (a call that is not minimised has that screen up).
enum CallMiniPlayerRule {
    enum Subject: Equatable { case group, oneToOne }

    static func subject(groupInCall: Bool, groupMinimized: Bool, callInCall: Bool, callMinimized: Bool) -> Subject? {
        if groupInCall && groupMinimized { return .group }
        if callInCall && callMinimized { return .oneToOne }
        return nil
    }

    /// "Video call · 3 in call · 1:01"; the count drops first when there is no room (`short`).
    static func subtitle(video: Bool, count: Int?, clock: String, short: Bool = false) -> String {
        var parts = [video ? "Video call" : "Voice call"]
        if let count, !short { parts.append("\(count) in call") }
        parts.append(clock)
        return parts.joined(separator: " \u{00B7} ")
    }

    /// "1:01" → "1 minute 1 second" for VoiceOver.
    static func spokenDuration(_ clock: String) -> String {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        let seconds = parts.reversed().enumerated().reduce(0) { $0 + $1.element * [1, 60, 3600][min($1.offset, 2)] }
        let m = seconds / 60, s = seconds % 60
        if m == 0 { return "\(s) second\(s == 1 ? "" : "s")" }
        return "\(m) minute\(m == 1 ? "" : "s")" + (s == 0 ? "" : " \(s) second\(s == 1 ? "" : "s")")
    }
}

/// Whether the mini player is tucked into an edge tab, and which edge (LIME-150, item 8). Pure rules, so they are tested.
struct CallMiniPlayerTuck: Equatable {
    enum Edge: Equatable { case leading, trailing }
    private(set) var edge: Edge?
    var isTucked: Bool { edge != nil }

    /// A drag of this horizontal distance (points) tucks it to that edge; a short one does not.
    static let threshold: CGFloat = 60

    /// The edge a drag ends at, or nil when it was too short.
    static func edge(forTranslation width: CGFloat) -> Edge? {
        if width <= -threshold { return .leading }
        if width >= threshold { return .trailing }
        return nil
    }

    mutating func tuck(to edge: Edge) { self.edge = edge }
    mutating func show() { edge = nil }
}

/// A call mini player like a podcast bar: the call's picture, its name, a LIVE badge and the timer, Mute and Leave; a tap on the rest returns to
/// the call screen. It is as tall as the header's glass circles (44 pt; taller only at accessibility text sizes), sits in the bottom safe area
/// (above the tab bar, or above the home indicator where the tab bar is hidden) and never over a button. Swipe it sideways off an edge and it
/// folds into a small edge tab that stays until it is brought back or the call ends (LIME-150, item 8).
struct CallMiniPlayer: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var drag: CGFloat = 0

    /// The header's glass circles and capsule are 44 pt (`ToolIconLabel`): the player matches.
    static let height: CGFloat = 44
    static let avatar: CGFloat = 32
    static let button: CGFloat = 36

    var body: some View {
        Group {
            if let subject = CallMiniPlayerRule.subject(groupInCall: store.groupCalls.inCall, groupMinimized: store.groupCalls.minimized,
                                                        callInCall: store.calls.inCall, callMinimized: store.calls.minimized) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let edge = store.miniPlayerTuck.edge { tab(edge) } else { content(for: subject, at: context.date) }
                }
                .padding(.horizontal, store.miniPlayerTuck.isTucked ? 0 : 16).padding(.vertical, 6)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("call-mini-player")
            }
        }
        .onChange(of: store.groupCalls.inCall || store.calls.inCall) { _, inCall in
            if !inCall { store.miniPlayerTuck.show() }
        }
    }

    private func animate(_ change: @escaping () -> Void) {
        if reduceMotion { withAnimation(.linear(duration: 0.15), change) } else { withAnimation(.easeOut(duration: 0.22), change) }
    }

    private func tuck(_ edge: CallMiniPlayerTuck.Edge) { animate { store.miniPlayerTuck.tuck(to: edge) } }
    private func untuck() { animate { store.miniPlayerTuck.show() } }

    /// The edge tab: a small warm handle with the call icon, in the same vertical place. Tap or swipe it back out to bring the player back.
    private func tab(_ edge: CallMiniPlayerTuck.Edge) -> some View {
        HStack(spacing: 0) {
            if edge == .trailing { Spacer(minLength: 0) }
            Button(action: untuck) {
                Image(systemName: "phone.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                    .frame(width: 44, height: 64)
                    .background(UnevenRoundedRectangle(topLeadingRadius: edge == .trailing ? 18 : 0, bottomLeadingRadius: edge == .trailing ? 18 : 0,
                                                       bottomTrailingRadius: edge == .leading ? 18 : 0, topTrailingRadius: edge == .leading ? 18 : 0)
                        .fill(Theme.pressed))
            }
            .buttonStyle(.plain)
            .gesture(DragGesture(minimumDistance: 12).onEnded { value in
                if let swiped = CallMiniPlayerTuck.edge(forTranslation: value.translation.width), swiped != edge { untuck() }
            })
            .accessibilityLabel("Call controls, hidden")
            .accessibilityHint("Double-tap to show")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Show call controls") { untuck() }
            .accessibilityIdentifier("call-mini-tab")
            if edge == .leading { Spacer(minLength: 0) }
        }
        .transition(.opacity)
    }

    private func content(for subject: CallMiniPlayerRule.Subject, at date: Date) -> some View {
        let group = subject == .group
        let name = group ? store.groupCalls.callTitle : store.calls.peerName
        let video = group ? store.groupCalls.video : store.calls.video
        let muted = group ? store.groupCalls.muted : store.calls.muted
        let clock = CallRecord.clock(date.timeIntervalSince(group ? (store.groupCalls.startedAt ?? date) : (store.calls.startedAt ?? date)))
        let count = group ? store.groupCalls.tiles.count : nil
        let line = group ? CallMiniPlayerRule.subtitle(video: video, count: count, clock: clock) : store.calls.statusText(at: date)
        let spoken = group ? "Call with \(name), \(count ?? 0) in call, \(CallMiniPlayerRule.spokenDuration(clock)). Double-tap to return"
                           : "Call with \(name), \(line). Double-tap to return"
        let large = typeSize.isAccessibilitySize
        return HStack(spacing: 6) {
            // A tap gesture, not a Button: a Button would also fire when a sideways swipe (tuck away) ends on it.
            HStack(spacing: 8) {
                avatar(group: group, name: name)
                // One line: "Shem & FAM · LIVE · 0:45". At accessibility sizes it may use two.
                ViewThatFits(in: .horizontal) {
                    oneLine(name: name, clock: group ? clock : line)
                    oneLine(name: name, clock: nil)
                }
                .lineLimit(large ? 2 : 1)
                Spacer(minLength: 0)
            }
            .frame(minHeight: Self.height)
            .contentShape(Rectangle())
            .onTapGesture { give(subject) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { give(subject) }
            .accessibilityIdentifier("call-mini-return")

            Button {
                if group { Task { await store.groupCalls.setMuted(!muted) } } else { store.calls.setMuted(!muted) }
            } label: {
                Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: Self.button, height: Self.button)
                    .background(Circle().fill(Theme.pressed))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(muted ? "Unmute" : "Mute")
            .accessibilityValue(muted ? "Muted" : "Microphone on")
            .accessibilityIdentifier("call-mini-mute")

            Button {
                if group { Task { await store.groupCalls.leave() } } else { Task { await store.calls.end() } }
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Self.button, height: Self.button)
                    .background(Circle().fill(Color.red))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Leave call")
            .accessibilityIdentifier("call-mini-leave")
        }
        .padding(.leading, 10).padding(.trailing, 4)
        .frame(minHeight: Self.height)
        .background {
            if reduceTransparency { Capsule().fill(Theme.canvas).overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5)) }
            else { Color.clear.limeGlass(in: Capsule()) }
        }
        .offset(x: drag)
        .simultaneousGesture(DragGesture(minimumDistance: 16)
            .onChanged { drag = $0.translation.width }
            .onEnded { value in
                drag = 0
                if let edge = CallMiniPlayerTuck.edge(forTranslation: value.translation.width) { tuck(edge) }
            })
        .accessibilityAction(named: "Tuck away call controls") { tuck(.trailing) }
        .transition(.opacity)
    }

    /// "Shem & FAM  LIVE  0:45": the name, the LIVE badge (the word, lime with dark ink: one of the three places green appears in a call) and
    /// the timer when it fits.
    private func oneLine(name: String, clock: String?) -> some View {
        HStack(spacing: 6) {
            Text(name).font(Theme.body.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
            Text("LIVE").font(.system(.caption2, design: .default, weight: .bold)).foregroundStyle(Theme.accentInk)
                .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.accent, in: Capsule())
                .accessibilityIdentifier("call-mini-live")
            if let clock { Text(clock).font(.footnote.monospacedDigit()).foregroundStyle(Theme.textSecondary).lineLimit(1) }
        }
        .fixedSize(horizontal: false, vertical: false)
    }

    @ViewBuilder
    private func avatar(group: Bool, name: String) -> some View {
        if group, let conversation = store.conversation(store.groupCalls.conversationID) {
            ConversationAvatar(conversation: conversation, size: Self.avatar)
        } else {
            let peer = store.conversations.first { !$0.isGroup && $0.members.first?.id == store.calls.peerID }?.members.first
            AvatarView(person: peer ?? Person(id: store.calls.peerID, name: name), size: Self.avatar)
        }
    }

    private func give(_ subject: CallMiniPlayerRule.Subject) {
        if subject == .group { store.groupCalls.minimized = false } else { store.calls.minimized = false }
    }
}

extension View {
    /// Reserves the bottom of a screen for the call mini player (and shows it there), so the last row is never covered.
    func callMiniPlayerInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { CallMiniPlayer() }
    }
}
