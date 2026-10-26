import SwiftUI

/// jam's Drafts (LIME-233g): your unfinished articles and the drafts you are invited to write, newest first. Each opens the editor.
struct JamDraftsList: View {
    @Environment(ConversationStore.self) private var store
    @State private var opening: DraftRoute?

    var body: some View {
        let rows = store.draftRows()
        VStack(spacing: 0) {
            if rows.isEmpty {
                Text("Articles you start, and articles others invite you to write, wait here.").font(Theme.body).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 40).padding(.top, 60).accessibilityIdentifier("jam-drafts-empty")
            }
            ForEach(rows) { row in
                Button { opening = DraftRoute(id: row.draftID) } label: {
                    HStack(spacing: 12) {
                        HStack(spacing: -10) {
                            ForEach(row.authors.prefix(4)) { person in
                                AvatarView(person: person, size: 32).overlay(Circle().strokeBorder(Theme.canvas, lineWidth: 2)).accessibilityHidden(true)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title.isEmpty ? "Untitled" : row.title).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(2)
                            Text("Edited \(Self.ago(row.updatedAt))").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                        if row.live { Circle().fill(Theme.accent).frame(width: 9, height: 9).accessibilityHidden(true) }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.title.isEmpty ? "Untitled" : row.title), with \(row.authors.map(\.name).joined(separator: ", ")), edited \(Self.ago(row.updatedAt))\(row.live ? ", someone is writing now" : "")")
                .accessibilityHint("Opens the draft")
                .accessibilityIdentifier("jam-draft-\(row.draftID)")
                Divider().overlay(Theme.hairline)
            }
        }
        .fullScreenCover(item: $opening) { JamComposeSheet(openDraft: $0.id) }
    }

    /// "2 min ago".
    static func ago(_ millis: Int64) -> String {
        let seconds = max(0, Date.now.timeIntervalSince1970 - Double(millis) / 1000)
        if seconds < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: Date(timeIntervalSince1970: Double(millis) / 1000), relativeTo: .now)
    }
}

/// The glass banner for an invitation to write (the app's notification pattern, like a message arriving): the writer's photo, "Shem invited you to write
/// <title>"; a tap opens the draft; it goes by itself after a few seconds or when swiped up.
struct DraftInviteBanner: View {
    @Environment(ConversationStore.self) private var store

    var body: some View {
        ZStack(alignment: .top) {
            if let banner = store.draftInviteBanner {
                let who = store.teacher(banner.writer)
                let first = who.name.split(separator: " ").first.map(String.init) ?? who.name
                let title = banner.title.isEmpty ? "an article" : "\u{201C}\(banner.title)\u{201D}"
                Button { store.openDraftFromBanner() } label: {
                    HStack(spacing: 12) {
                        AvatarView(person: who, size: 40).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(first) invited you to write").font(Theme.title).foregroundStyle(Theme.text).lineLimit(1)
                            Text(title).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .limeGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 12).padding(.top, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(first) invited you to write \(title)")
                .accessibilityHint("Opens the draft")
                .accessibilityIdentifier("draft-invite-banner")
                .gesture(DragGesture(minimumDistance: 12).onEnded { drag in if drag.translation.height < -10 { store.draftInviteBanner = nil } })
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: banner.id) {
                    try? await Task.sleep(for: .seconds(6))
                    if store.draftInviteBanner?.id == banner.id { store.draftInviteBanner = nil }
                }
            }
        }
        .animation(.spring(duration: 0.3), value: store.draftInviteBanner?.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(store.draftInviteBanner != nil)
    }
}
