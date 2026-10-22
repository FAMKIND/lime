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

    /// "Video call · 3 in call · 1:01". When there is no room: `compact` ("Video · 3 · 1:01", the words shortened), then `short` (the count
    /// dropped: "Video call · 1:01"). The timer is always there.
    static func subtitle(video: Bool, count: Int?, clock: String, short: Bool = false, compact: Bool = false) -> String {
        var parts = [compact ? (video ? "Video" : "Voice") : (video ? "Video call" : "Voice call")]
        if let count, !short { parts.append(compact ? "\(count)" : "\(count) in call") }
        parts.append(clock)
        return parts.joined(separator: " \u{00B7} ")
    }

    /// The width of the iOS 26 tab bar's capsule (measured on the 13 mini and the 18 Pro: about 282 pt, centred). The player is as wide as the
    /// dock on every screen, tab bar or not, so it never jumps. The bar's real width cannot be read without a private class name, so this is
    /// a measured constant, like the floating "+" uses. Before iOS 26 the bar spans the screen, and so does the player (inside its margins).
    static let dockWidth: CGFloat = 282
    static func width(isIOS26: Bool) -> CGFloat? { isIOS26 ? dockWidth : nil }

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
    /// How far the player floats above what is under it: the tab bar on a screen, the composer in a chat.
    var gapBelow: CGFloat = CallMiniPlayer.floatGapAboveTabBar
    private var isIOS26: Bool { if #available(iOS 26, *) { true } else { false } }

    /// The header's glass circles and capsule are 44 pt (`ToolIconLabel`): the player matches.
    static let height: CGFloat = 44
    static let avatar: CGFloat = 32
    static let button: CGFloat = 36
    /// The player floats this far from what is above it (the call's own content) and below it. Two constants, one per side (LIME-150-fix3): the
    /// composer's top edge and the tab bar's glass capsule are different things, so the same number can look different. Measured on the 13 mini
    /// simulator the visible gaps are the same (about 3.3 pt between the two outlines, 10 px at 3x) on both sides, so both are 4 for now.
    static let floatGapAboveComposer: CGFloat = 4
    static let floatGapAboveTabBar: CGFloat = 4
    /// The player's own distance from what is above it.
    static let floatGap: CGFloat = 4

    var body: some View {
        Group {
            if let subject = CallMiniPlayerRule.subject(groupInCall: store.groupCalls.inCall, groupMinimized: store.groupCalls.minimized,
                                                        callInCall: store.calls.inCall, callMinimized: store.calls.minimized) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let edge = store.miniPlayerTuck.edge { tab(edge, video: subject == .group ? store.groupCalls.video : store.calls.video) } else { content(for: subject, at: context.date) }
                }
                .padding(.horizontal, store.miniPlayerTuck.isTucked ? 0 : 16).padding(.top, Self.floatGap).padding(.bottom, gapBelow)
                .frame(maxWidth: .infinity)
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

    /// The edge tab (iOS's stashed-PiP pattern, LIME-150-fix4): a small warm handle as tall as the player with a bold chevron that points the way it
    /// will open (tucked at the right edge: `chevron.left`; at the left: `chevron.right`). Tap or swipe it back out to bring the player back.
    static let tabHeight: CGFloat = 48
    /// As wide as iOS's own stashed-video tab: about 24 pt of it shows at the screen's edge (46 px of a 724 px wide screenshot, 3x), so the chevron
    /// sits close to the edge and looks a little skewed, as iOS's does.
    static let tabWidth: CGFloat = 24
    private func tab(_ edge: CallMiniPlayerTuck.Edge, video: Bool) -> some View {
        HStack(spacing: 0) {
            if edge == .trailing { Spacer(minLength: 0) }
            Button(action: untuck) {
                Image(systemName: edge == .trailing ? "chevron.left" : "chevron.right").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: Self.tabWidth, height: Self.tabHeight)
                    .modifier(TabGlass(edge: edge, reduceTransparency: reduceTransparency))
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
        let forms: [String] = group
            ? [line, CallMiniPlayerRule.subtitle(video: video, count: count, clock: clock, compact: true), CallMiniPlayerRule.subtitle(video: video, count: count, clock: clock, short: true)]
            : [line]
        return HStack(spacing: 6) {
            // A tap gesture, not a Button: a Button would also fire when a sideways swipe (tuck away) ends on it.
            HStack(spacing: 8) {
                avatar(group: group, name: name)
                twoLines(name: name, forms: forms)
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

            // Mute and Leave sit 2 pt closer than the rest of the row (their 44 pt tap areas still do not overlap).
            HStack(spacing: 4) {
                Button {
                    if group { Task { await store.groupCalls.setMuted(!muted) } } else { store.calls.setMuted(!muted) }
                } label: {
                    Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 17, weight: .semibold))
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
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: Self.button, height: Self.button)
                        .background(Circle().fill(Color.red))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Leave call")
                .accessibilityIdentifier("call-mini-leave")
            }
        }
        // 2 pt more room all round than 150-fix, so the contents sit evenly inside the capsule.
        .padding(.leading, 12).padding(.trailing, 6)
        .padding(.vertical, typeSize.isAccessibilitySize ? 8 : 2)
        .frame(minHeight: Self.height)
        // As wide as the tab bar (iOS 26); at accessibility sizes the text needs the room, so it uses the full width.
        .frame(maxWidth: typeSize.isAccessibilitySize ? nil : CallMiniPlayerRule.width(isIOS26: isIOS26))
        .background {
            // A capsule at normal sizes; at accessibility sizes the player grows tall, so it becomes a rounded rectangle (a tall capsule is a blob).
            if typeSize.isAccessibilitySize {
                if reduceTransparency { RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.canvas).overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5)) }
                else { Color.clear.limeGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous)) }
            } else if reduceTransparency { Capsule().fill(Theme.canvas).overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5)) }
            else { Color.clear.modifier(PlayerGlass(shape: Capsule())) }
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

    /// 148c's text: the name, then the subtitle in the smaller grey line with the timer always present (the words shorten when narrow).
    private func twoLines(name: String, forms: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if typeSize.isAccessibilitySize {
                // Accessibility sizes: everything wraps and the player grows, never clips.
                Text(name).font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.text)
                Text(forms[0]).font(Theme.font(.footnote)).foregroundStyle(Theme.textSecondary)
            } else {
                Text(name).font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                ViewThatFits(in: .horizontal) {
                    ForEach(forms, id: \.self) { Text($0).lineLimit(1) }
                }
                .font(Theme.font(.footnote)).foregroundStyle(Theme.textSecondary)
            }
        }
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
        safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                AudioMiniPlayer()   // a playing recording (LIME-188k), above a minimised call
                CallMiniPlayer()
            }
        }
    }
}


/// The player's capsule glass. (It once shared a glass id with the tab so the capsule flowed into it; the morph left the player's text and buttons
/// blurred and doubled after a tuck, LIME-150-fix6, so each is its own plain piece of glass.)
struct PlayerGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    func body(content: Content) -> some View { content.limeGlass(in: shape) }
}

/// The tucked tab, like iOS's own stashed-video tab: dark Liquid Glass (dark in light and dark mode) with a white chevron, flush to the screen
/// edge and rounded on the inner side, only as tall as the player.
struct TabGlass: ViewModifier {
    let edge: CallMiniPlayerTuck.Edge
    let reduceTransparency: Bool

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: edge == .trailing ? 20 : 0, bottomLeadingRadius: edge == .trailing ? 20 : 0,
                               bottomTrailingRadius: edge == .leading ? 20 : 0, topTrailingRadius: edge == .leading ? 20 : 0, style: .continuous)
    }

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(shape.fill(Color(white: 0.12)))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(Color.black.opacity(0.72)), in: shape)
        } else {
            content.background(shape.fill(Color.black.opacity(0.6)))
        }
    }
}
