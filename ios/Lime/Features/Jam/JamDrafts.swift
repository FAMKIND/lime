import SwiftUI

/// jam's Drafts (LIME-233g, 237): your unfinished articles and the drafts you are invited to, pinned first then newest first, with link's patterns:
/// swipe left for Delete (Leave for a co-author) and Copy, swipe right for Edit and Pin; long press for a menu with Select, which turns the rows into
/// a selection with a bar of actions at the bottom. Who is writing now shows on the avatar and under the title.
struct JamDraftsList: View {
    @Environment(ConversationStore.self) private var store
    @State private var opening: DraftRoute?
    @State private var deleting: [DraftRow] = []
    /// Podcasts and quick posts kept on this phone (LIME-276).
    @State private var openingLocal: LocalDraft?
    @State private var deletingLocal: LocalDraft?

    /// The rows grow with the text size; at accessibility sizes their lines wrap and the list scrolls (LIME-130-6a).
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 84
    @Environment(\.dynamicTypeSize) private var typeSize
    private var big: Bool { typeSize.isAccessibilitySize }
    private var lines: Int? { big ? nil : 1 }
    private func listHeight(_ count: Int) -> CGFloat { let all = CGFloat(count) * rowHeight + 8; return big ? min(all, 560) : all }

    var body: some View {
        // Not a timeline: the system rebuilds a list's rows when its view redraws, which would cancel a swipe or a long press; the list changes when the
        // drafts or who is writing change (and a few seconds after someone stops).
        Group {
            let rows = store.draftRows()
            let local = LocalDrafts.shared.drafts
            VStack(spacing: 0) {
                if store.draftSelecting { selectionBar(rows) }
                if rows.isEmpty && local.isEmpty {
                    Text("Drafts you write, and drafts you\u{2019}re invited to, show here.").font(Theme.body).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 40).padding(.top, 60).accessibilityIdentifier("jam-drafts-empty")
                } else {
                    // A list that does not scroll on its own (the feed scrolls), tall enough for its rows: it is what gives rows their swipe actions.
                    List {
                        ForEach(rows) { row in
                            rowView(row)
                                .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) { if !store.draftSelecting { trailing(row) } }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) { if !store.draftSelecting { leading(row) } }
                                .contextMenu { if !store.draftSelecting { menu(row) } }
                        }
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden).scrollDisabled(!big)
                    .frame(height: listHeight(rows.count))
                }
                if !local.isEmpty { localSection(local) }
            }
        }
        .task {
            // "Jean is writing" ends 25 s after the last sign of Jean: look again every 5 s while anyone is marked live.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if store.draftLive.values.contains(where: { !$0.isEmpty }) { store.draftRevision += 1 }
            }
        }
        .fullScreenCover(item: $opening) { JamComposeSheet(openDraft: $0.id) }
        .fullScreenCover(item: $openingLocal) { JamComposeSheet(localDraft: $0) }
        .confirmationDialog("Delete this draft?", isPresented: Binding(get: { deletingLocal != nil }, set: { if !$0 { deletingLocal = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let draft = deletingLocal { LocalDrafts.shared.delete(draft.id) }; deletingLocal = nil }.accessibilityIdentifier("jam-local-draft-delete-confirm")
            Button("Cancel", role: .cancel) { deletingLocal = nil }
        } message: { Text("It is only on this iPhone. This can\u{2019}t be undone.") }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { !deleting.isEmpty }, set: { if !$0 { deleting = [] } }), titleVisibility: .visible) {
            Button(deleting.allSatisfy(\.isWriter) ? "Delete" : "Delete or leave", role: .destructive) {
                for row in deleting { store.removeDraft(row) }
                deleting = []
                store.exitDraftSelection()
            }
            .accessibilityIdentifier("jam-drafts-delete-confirm")
            Button("Cancel", role: .cancel) { deleting = [] }
        } message: { Text(deleteMessage) }
    }

    // MARK: Drafts kept on this phone (LIME-276)

    private func localSection(_ drafts: [LocalDraft]) -> some View {
        List {
            ForEach(drafts) { draft in
                localRow(draft)
                    .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { deletingLocal = draft } label: { Label("Delete", systemImage: "trash") }.tint(Theme.dangerFill).accessibilityIdentifier("swipe-local-draft-delete-\(draft.id)")
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button { openingLocal = draft } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
                    }
                    .contextMenu {
                        Button { openingLocal = draft } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { deletingLocal = draft } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).scrollDisabled(!big)
        .frame(height: listHeight(drafts.count))
        .accessibilityIdentifier("jam-local-drafts")
    }

    private func localRow(_ draft: LocalDraft) -> some View {
        let picture = (draft.cover ?? draft.photos.first ?? draft.clip).flatMap { item -> UIImage? in
            let poster = LocalDrafts.shared.data(draft, item.file + ".poster"), thumb = LocalDrafts.shared.data(draft, item.file + ".thumb")
            return (poster?.isEmpty == false ? poster : thumb).flatMap(UIImage.init(data:)) ?? (item.mime.hasPrefix("image/") ? LocalDrafts.shared.data(draft, item.file).flatMap(UIImage.init(data:)) : nil)
        }
        let ago = Self.ago(Int64(draft.updated.timeIntervalSince1970 * 1000))
        return Button { openingLocal = draft } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface)
                    if let picture { Image(uiImage: picture).resizable().scaledToFill() }
                    else { Image(systemName: draft.kind == "podcast" ? "waveform" : "text.alignleft").font(.system(size: 20)).foregroundStyle(Theme.textSecondary) }
                }
                .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.headline).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(lines)
                    Text("\(draft.label) \u{00B7} Edited \(ago)").font(Theme.caption).foregroundStyle(Theme.textSecondary).lineLimit(lines)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(draft.headline), \(draft.label), edited \(ago)")
        .accessibilityHint("Opens the draft")
        .accessibilityAction(named: "Delete") { deletingLocal = draft }
        .accessibilityIdentifier("jam-local-draft-\(draft.id)")
    }

    // MARK: One row

    private func rowView(_ row: DraftRow) -> some View {
        let selected = store.draftSelection.contains(row.draftID)
        let others = Array(row.authors.dropFirst())
        let names = others.map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name }
        let writing = row.live.map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name }
        let writingLine = writing.isEmpty ? nil : (writing.count == 1 ? "\(writing[0]) is writing" : writing.dropLast().joined(separator: ", ") + " and \(writing.last!) are writing")
        return Button {
            if store.draftSelecting { toggle(row) } else { opening = DraftRoute(id: row.draftID) }
        } label: {
            HStack(spacing: 12) {
                if store.draftSelecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 22)).foregroundStyle(selected ? Theme.text : Theme.textSecondary).accessibilityHidden(true)
                }
                GroupCircles(plan: GroupAvatarPlan.make(others: others, me: row.authors[0]), size: 52, ringed: Set(row.live.map(\.id)))
                    .frame(width: 56, height: 56).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.title.isEmpty ? "Untitled" : row.title).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(lines)
                        if row.pinned { Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(Theme.textSecondary).accessibilityHidden(true) }
                    }
                    if let writingLine {
                        Text(writingLine).font(Theme.secondary).foregroundStyle(Theme.text).lineLimit(lines).accessibilityIdentifier("jam-draft-live-\(row.draftID)")
                    }
                    if let state = row.reviewState {
                        Text(state).font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(lines).accessibilityIdentifier("jam-draft-review-\(row.draftID)")
                    }
                    Text(["Edited \(Self.ago(row.updatedAt))"] .appending(names.isEmpty ? [] : [names.joined(separator: ", ")]).joined(separator: " \u{00B7} "))
                        .font(Theme.caption).foregroundStyle(Theme.textSecondary).lineLimit(lines)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.title.isEmpty ? "Untitled" : row.title), with \(row.authors.map(\.name).joined(separator: ", ")), edited \(Self.ago(row.updatedAt))\(writingLine.map { ", " + $0 } ?? "")\(row.pinned ? ", pinned" : "")\(row.reviewState.map { ", " + $0.lowercased() } ?? "")\(store.draftSelecting ? (selected ? ", selected" : ", not selected") : "")")
        .accessibilityHint(store.draftSelecting ? "Selects it" : "Opens the draft")
        .accessibilityAction(named: "Edit") { opening = DraftRoute(id: row.draftID) }
        .accessibilityAction(named: "Copy") { store.copyDraft(row.draftID) }
        .accessibilityAction(named: row.pinned ? "Unpin" : "Pin") { store.togglePin([row.draftID]) }
        .accessibilityAction(named: row.isWriter ? "Delete" : "Leave") { deleting = [row] }
        .accessibilityAction(named: "Select") { select(row) }
        .accessibilityIdentifier("jam-draft-\(row.draftID)")
    }

    @ViewBuilder private func trailing(_ row: DraftRow) -> some View {
        Button { deleting = [row] } label: { Label(row.isWriter ? "Delete" : "Leave", systemImage: row.isWriter ? "trash" : "rectangle.portrait.and.arrow.right") }
            .tint(Theme.dangerFill).accessibilityIdentifier("swipe-draft-delete-\(row.draftID)")
        Button { store.copyDraft(row.draftID) } label: { Label("Copy", systemImage: "doc.on.doc") }
            .tint(.gray).accessibilityIdentifier("swipe-draft-copy-\(row.draftID)")
    }

    @ViewBuilder private func leading(_ row: DraftRow) -> some View {
        Button { opening = DraftRoute(id: row.draftID) } label: { Label("Edit", systemImage: "pencil") }
            .tint(.blue).accessibilityIdentifier("swipe-draft-edit-\(row.draftID)")
        Button { store.togglePin([row.draftID]) } label: { Label(row.pinned ? "Unpin" : "Pin", systemImage: row.pinned ? "pin.slash" : "pin") }
            .tint(.gray).accessibilityIdentifier("swipe-draft-pin-\(row.draftID)")
    }

    @ViewBuilder private func menu(_ row: DraftRow) -> some View {
        Button { opening = DraftRoute(id: row.draftID) } label: { Label("Edit", systemImage: "pencil") }
        Button { store.copyDraft(row.draftID) } label: { Label("Copy", systemImage: "doc.on.doc") }
        Button { store.togglePin([row.draftID]) } label: { Label(row.pinned ? "Unpin" : "Pin", systemImage: row.pinned ? "pin.slash" : "pin") }
        Button { select(row) } label: { Label("Select", systemImage: "checkmark.circle") }
        Button(role: .destructive) { deleting = [row] } label: { Label(row.isWriter ? "Delete" : "Leave", systemImage: row.isWriter ? "trash" : "rectangle.portrait.and.arrow.right") }
    }

    // MARK: Selection

    private func select(_ row: DraftRow) { store.draftSelecting = true; store.draftSelection = [row.draftID] }

    private func toggle(_ row: DraftRow) {
        if store.draftSelection.contains(row.draftID) { store.draftSelection.remove(row.draftID) } else { store.draftSelection.insert(row.draftID) }
        UIAccessibility.post(notification: .announcement, argument: "\(store.draftSelection.count) selected")
    }

    /// Cancel · "n selected" · Select All.
    private func selectionBar(_ rows: [DraftRow]) -> some View {
        HStack {
            Button("Cancel") { store.exitDraftSelection() }.accessibilityIdentifier("jam-drafts-cancel")
            Spacer()
            Text("\(store.draftSelection.count) selected").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text).accessibilityIdentifier("jam-drafts-count")
            Spacer()
            Button(store.draftSelection.count == rows.count ? "Select none" : "Select All") {
                store.draftSelection = store.draftSelection.count == rows.count ? [] : Set(rows.map(\.draftID))
                UIAccessibility.post(notification: .announcement, argument: "\(store.draftSelection.count) selected")
            }
            .accessibilityIdentifier("jam-drafts-select-all")
        }
        .font(Theme.body).foregroundStyle(Theme.text).padding(.horizontal, 20).frame(minHeight: 44)
    }

    private var deleteTitle: String {
        guard let first = deleting.first else { return "" }
        if deleting.count > 1 { return "Delete \(deleting.count) drafts?" }
        guard first.isWriter else { return "Leave this draft?" }
        let others = first.authors.dropFirst().map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name }
        return others.isEmpty ? "Delete this draft?" : "Delete this draft for you, " + (others.count == 1 ? others[0] : others.dropLast().joined(separator: ", ") + " and " + others.last!) + "?"
    }

    private var deleteMessage: String {
        deleting.contains { !$0.isWriter } ? "Drafts you were invited to are removed from this phone and you leave them; the others keep writing. A published post is never touched." : "A published post is never touched."
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

/// Selection mode's bottom bar: Copy · Pin · Delete, in glass (one confirm for Delete).
struct DraftSelectionBar: View {
    @Environment(ConversationStore.self) private var store
    @State private var confirming = false

    var body: some View {
        let rows = store.draftRows().filter { store.draftSelection.contains($0.draftID) }
        let none = rows.isEmpty
        HStack(spacing: 0) {
            item("doc.on.doc", "Copy", id: "jam-drafts-copy") { for r in rows { store.copyDraft(r.draftID) }; store.exitDraftSelection() }
            item("pin", rows.allSatisfy(\.pinned) && !none ? "Unpin" : "Pin", id: "jam-drafts-pin") { store.togglePin(rows.map(\.draftID)); store.exitDraftSelection() }
            item("trash", rows.allSatisfy(\.isWriter) ? "Delete" : "Leave", id: "jam-drafts-bar-delete", tint: Theme.danger) { confirming = true }
        }
        .padding(.horizontal, 8).limeGlass(in: Capsule()).padding(.horizontal, 24).padding(.bottom, 8)
        .disabled(none).opacity(none ? 0.5 : 1)
        .confirmationDialog(rows.count == 1 ? "Delete this draft?" : "Delete \(rows.count) drafts?", isPresented: $confirming, titleVisibility: .visible) {
            Button(rows.allSatisfy(\.isWriter) ? "Delete" : "Delete or leave", role: .destructive) { for r in rows { store.removeDraft(r) }; store.exitDraftSelection() }
                .accessibilityIdentifier("jam-drafts-delete-confirm")
            Button("Cancel", role: .cancel) {}
        } message: { Text("Drafts you were invited to are removed from this phone and you leave them. A published post is never touched.") }
    }

    private func item(_ symbol: String, _ label: String, id: String, tint: Color = Theme.text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 18)).accessibilityHidden(true)
                Text(label).font(Theme.caption)
            }
            .foregroundStyle(tint).frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle())
        }
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }
}

private extension Array {
    func appending(_ more: [Element]) -> [Element] { self + more }
}

/// The glass banner for an invitation to write (the app's notification pattern, like a message arriving): the writer's photo, "Shem invited you to write
/// <title>"; a tap opens the draft; it goes by itself after a few seconds or when swiped up.
struct DraftInviteBanner: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long it stays for a touch user; with VoiceOver or Switch Control it stays until dismissed (LIME-130-6a).
    static let touchSeconds = 20.0

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
                            if let band = store.reviewBannerLine(banner) {
                                Text("\(first) sent \u{201C}\(band.title)\u{201D} for review in \(band.band)").font(Theme.title).foregroundStyle(Theme.text).lineLimit(nil)
                            } else {
                                Text("\(first) invited you to write").font(Theme.title).foregroundStyle(Theme.text).lineLimit(nil)
                                Text(title).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(nil)
                            }
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
                .accessibilityAction(named: "Dismiss") { store.draftInviteBanner = nil }
                .gesture(DragGesture(minimumDistance: 12).onEnded { drag in if drag.translation.height < -10 { store.draftInviteBanner = nil } })
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .task(id: banner.id) {
                    Announce.say("\(first) invited you to write \(title)")
                    if BannerTiming.staysUntilDismissed { return }
                    try? await Task.sleep(for: .seconds(Self.touchSeconds))
                    if !BannerTiming.staysUntilDismissed, store.draftInviteBanner?.id == banner.id { store.draftInviteBanner = nil }
                }
            }
        }
        .animation(reduceMotion ? .linear(duration: 0.15) : .spring(duration: 0.3), value: store.draftInviteBanner?.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(store.draftInviteBanner != nil)
    }
}
