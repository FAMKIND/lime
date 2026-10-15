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

/// A call mini player like a podcast bar: the call's picture, its name and timer, Mute and Leave; a tap on the rest returns to the call screen.
/// It sits in the bottom safe area (above the tab bar, or above the home indicator where the tab bar is hidden) and never over a button.
struct CallMiniPlayer: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if let subject = CallMiniPlayerRule.subject(groupInCall: store.groupCalls.inCall, groupMinimized: store.groupCalls.minimized,
                                                    callInCall: store.calls.inCall, callMinimized: store.calls.minimized) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(for: subject, at: context.date)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("call-mini-player")
        }
    }

    private func content(for subject: CallMiniPlayerRule.Subject, at date: Date) -> some View {
        let group = subject == .group
        let name = group ? store.groupCalls.callTitle : store.calls.peerName
        let video = group ? store.groupCalls.video : store.calls.video
        let muted = group ? store.groupCalls.muted : store.calls.muted
        let clock = CallRecord.clock(date.timeIntervalSince(group ? (store.groupCalls.startedAt ?? date) : (store.calls.startedAt ?? date)))
        let count = group ? store.groupCalls.tiles.count : nil
        let line = group ? CallMiniPlayerRule.subtitle(video: video, count: count, clock: clock) : store.calls.statusText(at: date)
        let shortLine = group ? CallMiniPlayerRule.subtitle(video: video, count: count, clock: clock, short: true) : line
        let spoken = group ? "Call with \(name), \(count ?? 0) in call, \(CallMiniPlayerRule.spokenDuration(clock)). Double-tap to return"
                           : "Call with \(name), \(line). Double-tap to return"
        return HStack(spacing: 8) {
            Button { give(subject) } label: {
                HStack(spacing: 8) {
                    avatar(group: group, name: name)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).font(Theme.body.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        ViewThatFits(in: .horizontal) {
                            Text(line).lineLimit(1)
                            Text(shortLine).lineLimit(1)
                        }
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("call-mini-return")

            Button {
                if group { Task { await store.groupCalls.setMuted(!muted) } } else { store.calls.setMuted(!muted) }
            } label: {
                Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(muted ? Theme.accentInk : Theme.text)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(muted ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surface)))
            }
            .accessibilityLabel(muted ? "Unmute" : "Mute")
            .accessibilityValue(muted ? "Muted" : "Microphone on")
            .accessibilityIdentifier("call-mini-mute")

            Button {
                if group { Task { await store.groupCalls.leave() } } else { Task { await store.calls.end() } }
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.red))
            }
            .accessibilityLabel("Leave call")
            .accessibilityIdentifier("call-mini-leave")
        }
        .padding(.leading, 10).padding(.trailing, 8).padding(.vertical, 8)
        .frame(minHeight: 60)
        .background {
            if reduceTransparency { Capsule().fill(Theme.canvas).overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5)) }
            else { Color.clear.limeGlass(in: Capsule()) }
        }
    }

    @ViewBuilder
    private func avatar(group: Bool, name: String) -> some View {
        if group, let conversation = store.conversation(store.groupCalls.conversationID) {
            ConversationAvatar(conversation: conversation, size: 38)
        } else {
            let peer = store.conversations.first { !$0.isGroup && $0.members.first?.id == store.calls.peerID }?.members.first
            AvatarView(person: peer ?? Person(id: store.calls.peerID, name: name), size: 38)
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
