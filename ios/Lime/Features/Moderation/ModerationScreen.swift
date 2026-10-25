import SwiftUI

/// Settings → Moderation (LIME-191): only for accounts on the server's allow-list. Open reports first, urgent on top; each opens to what the reporter's
/// phone sent, with the actions the server can take. Nothing here reaches into anyone's phone: end-to-end encrypted messages stay theirs.
struct ModerationScreen: View {
    @Environment(ConversationStore.self) private var store
    @State private var status = "open"
    @State private var items: [ModerationItem] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Status", selection: $status) {
                    Text("Open").tag("open"); Text("Actioned").tag("actioned"); Text("Dismissed").tag("dismissed")
                }
                .pickerStyle(.segmented).accessibilityIdentifier("moderation-status")
                if loaded && items.isEmpty {
                    Text(status == "open" ? "Nothing waiting." : "Nothing here.").font(Theme.body).foregroundStyle(Theme.textSecondary).padding(.top, 20)
                        .accessibilityIdentifier("moderation-empty")
                }
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink { ModerationReportScreen(item: item) { Task { await load() } } } label: { row(item) }
                            .buttonStyle(.plain).accessibilityIdentifier("moderation-row-\(item.id)")
                        if index < items.count - 1 { Divider().overlay(Theme.hairline).padding(.leading, 16) }
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text("lime can hide a post, take a page down, remove a public picture or suspend an account. It can\u{2019}t read or remove anything on a phone: messages are end-to-end encrypted.")
                    .font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            .padding(16)
        }
        .background(Theme.canvas).navigationTitle("Moderation").navigationBarTitleDisplayMode(.inline)
        .task(id: status) { await load() }
        .accessibilityIdentifier("moderation-screen")
    }

    private func load() async {
        items = await store.moderationQueue(status: status)
        loaded = true
    }

    private func row(_ item: ModerationItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if item.urgent { Text("URGENT").font(Theme.font(.caption2, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2).background(Color.red, in: Capsule()) }
                    Text((ReportReason(rawValue: item.reason)?.title ?? item.reason)).font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.text)
                }
                Text("\(Self.kindName(item.kind)) \u{00B7} \(item.created.formatted(.relative(presentation: .named)))").font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 16).frame(minHeight: 56).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    static func kindName(_ kind: String) -> String {
        ["message": "Message", "person": "Person", "group": "Group", "jam_post": "Post", "comment": "Comment", "jam": "Jam page", "org": "Org", "profile_item": "Profile picture"][kind] ?? kind
    }
}

/// One report, opened: what was sent, and what the server can do about it. Each action asks first.
struct ModerationReportScreen: View {
    let item: ModerationItem
    var done: () -> Void
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var detail: ModerationDetail?
    @State private var failed = false
    @State private var note = ""
    @State private var pending: Pending?

    private struct Pending: Identifiable {
        let id: String   // dismiss, hide_post, take_down_page, remove_public, suspend
        var title: String
        var button: String
        var message: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let detail {
                    card("Reason") {
                        Text(ReportReason(rawValue: detail.item.reason)?.title ?? detail.item.reason).font(Theme.body).foregroundStyle(Theme.text)
                        Text("\(ModerationScreen.kindName(detail.item.kind)) \u{00B7} \(detail.item.created.formatted(date: .abbreviated, time: .shortened))").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    }
                    if !detail.note.isEmpty { card("Note") { Text(detail.note).font(Theme.body).foregroundStyle(Theme.text) } }
                    card("Reported by") { Text(store.teacherName(detail.reporter)).font(Theme.body).foregroundStyle(Theme.text); Text(detail.reporter).font(Theme.caption).foregroundStyle(Theme.textSecondary).textSelection(.enabled) }
                    card("Sent with the report") {
                        if !detail.readable { Text("This report can\u{2019}t be opened (sealed to another key).").font(Theme.body).foregroundStyle(.red) }
                        else if detail.included.isEmpty { Text("Nothing was included.").font(Theme.body).foregroundStyle(Theme.textSecondary) }
                        else { Text(detail.included).font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.text).textSelection(.enabled).accessibilityIdentifier("moderation-included") }
                        Text("Ids: " + detail.subjectIDs.joined(separator: " \u{00B7} ")).font(Theme.caption).foregroundStyle(Theme.textSecondary).textSelection(.enabled)
                    }
                    if !detail.history.isEmpty {
                        card("History") { ForEach(Array(detail.history.enumerated()), id: \.offset) { _, h in
                            Text("\(h.action.replacingOccurrences(of: "_", with: " ")) \u{00B7} \(h.date.formatted(date: .abbreviated, time: .shortened))\(h.note.isEmpty ? "" : " \u{00B7} \(h.note)")").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        } }
                    }
                    if detail.item.status == "open" { actions(detail) }
                } else if failed {
                    Text("Couldn\u{2019}t open this report.").font(Theme.body).foregroundStyle(.red)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(16)
        }
        .background(Theme.canvas).navigationTitle("Report").navigationBarTitleDisplayMode(.inline)
        .task { detail = await store.moderationOpen(item.id); failed = detail == nil }
        .confirmSheet(pending?.title ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button(pending?.button ?? "", role: pending?.id == "dismiss" ? nil : .destructive) { if let pending { Task { await run(pending) } } }.accessibilityIdentifier("moderation-confirm")
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { Text(pending?.message ?? "") }
        .accessibilityIdentifier("moderation-report-screen")
    }

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.font(.footnote, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func actions(_ detail: ModerationDetail) -> some View {
        let ids = detail.subjectIDs
        return VStack(spacing: 10) {
            TextField("Note (kept in the log)", text: $note).font(Theme.body).padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous)).accessibilityIdentifier("moderation-note")
            actionButton("Dismiss", id: "dismiss", symbol: "xmark", pending: Pending(id: "dismiss", title: "Dismiss this report?", button: "Dismiss", message: "Nothing else changes."))
            if detail.item.kind == "jam_post", ids.count >= 4 {
                actionButton("Hide post", id: "hide_post", symbol: "eye.slash", pending: Pending(id: "hide_post", title: "Hide this post?", button: "Hide post", message: "It can\u{2019}t be fetched again. Phones that already have it keep it."))
            }
            if ["jam_post", "jam", "org"].contains(detail.item.kind), ids.count >= 2 {
                actionButton("Take page down", id: "take_down_page", symbol: "rectangle.slash", pending: Pending(id: "take_down_page", title: "Take this page down?", button: "Take page down", message: "Its public page stops loading."))
            }
            if detail.item.kind == "person" || detail.item.kind == "profile_item" {
                actionButton("Remove public picture", id: "remove_public", symbol: "photo.badge.minus", pending: Pending(id: "remove_public", title: "Remove their public background?", button: "Remove", message: "Their public background is deleted from the server."))
            }
            if let suspect = suspectID(detail) {
                actionButton("Suspend account", id: "suspend", symbol: "person.crop.circle.badge.xmark", pending: Pending(id: "suspend", title: "Suspend this account?", button: "Suspend", message: "They can\u{2019}t sign in or use lime until you lift it. \(suspect.prefix(8))\u{2026}"))
            }
        }
    }

    private func actionButton(_ title: String, id: String, symbol: String, pending next: Pending) -> some View {
        Button { pending = next } label: {
            Label(title, systemImage: symbol).font(Theme.body).foregroundStyle(id == "dismiss" ? Theme.text : Color.red)
                .frame(maxWidth: .infinity, minHeight: 50).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain).accessibilityIdentifier("moderation-\(id)")
    }

    /// The account a report is about (the post's author, the person, the message's sender, the comment's author).
    private func suspectID(_ detail: ModerationDetail) -> String? {
        let ids = detail.subjectIDs
        switch detail.item.kind {
        case "jam_post", "comment": return ids.count > 2 ? ids[2] : nil
        case "message": return ids.count > 2 && !ids[2].isEmpty ? ids[2] : nil
        case "person", "profile_item": return ids.first
        case "jam", "org": return ids.count > 1 ? ids[1] : nil
        default: return nil
        }
    }

    private func run(_ action: Pending) async {
        guard let detail else { return }
        let ids = detail.subjectIDs
        let target: String? = switch action.id {
        case "hide_post": ids.count >= 4 ? ids[3] : nil
        case "take_down_page": detail.item.kind == "jam_post" ? (ids.count > 1 ? ids[1] : nil) : ids.first
        case "remove_public": ids.first
        case "suspend": suspectID(detail)
        default: nil
        }
        pending = nil
        let ok = await store.moderationAct(reportID: item.id, action: action.id, target: target, slot: action.id == "remove_public" ? "background" : nil,
                                           reason: action.id == "suspend" ? detail.item.reason : nil, note: note)
        if ok { done(); dismiss() } else { store.showBanner("Couldn\u{2019}t do that.") }
    }
}
