import SwiftUI

/// Report (LIME-191): a reason, an optional note, what will be sent, "Also block", Send. The reported person is never told who reported.
struct ReportSheet: View {
    let target: ReportTarget
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason?
    @State private var note = ""
    @State private var include = true
    @State private var alsoBlock = false
    @State private var sending = false
    @State private var sent = false
    @State private var failed = false
    /// A group report (LIME-256): the messages left in, the name and photo, who is in it, and leaving afterwards.
    @State private var ticked: Set<String> = []
    @State private var nameAndPhoto = true
    @State private var withMembers = false
    @State private var leaveAfter = false
    @State private var leftGroup = false
    @FocusState private var noteFocused: Bool

    var body: some View {
        NavigationStack {
            Group { if sent { thanks } else { form } }
                .background(Theme.canvas)
                .navigationTitle(sent ? "" : "Report").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { if !sent { Button("Cancel") { dismiss() }.accessibilityIdentifier("report-cancel") } }
                    ToolbarItem(placement: .topBarTrailing) {
                        if sent { Button("Done") { dismiss(); if leftGroup { store.path = NavigationPath() } }.fontWeight(.semibold).accessibilityIdentifier("report-done") }
                        else { Button(sending ? "Sending\u{2026}" : "Send") { Task { await send() } }.fontWeight(.semibold).disabled(reason == nil || sending).accessibilityIdentifier("report-send") }
                    }
                }
        }
        .presentationDetents([.large]).presentationDragIndicator(.visible)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("What\u{2019}s wrong?").font(Theme.font(.headline, weight: .semibold)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(Array(ReportReason.allCases.enumerated()), id: \.element) { index, item in
                        Button { reason = item } label: {
                            HStack {
                                Text(item.title).font(Theme.body).foregroundStyle(Theme.text)
                                Spacer()
                                if reason == item { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text) }
                            }
                            .padding(.horizontal, 16).frame(minHeight: 48).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(reason == item ? [.isSelected] : [])
                        .accessibilityIdentifier("report-reason-\(item.rawValue)")
                        if index < ReportReason.allCases.count - 1 { Divider().overlay(Theme.hairline).padding(.leading, 16) }
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                TextField("Add a note (optional)", text: $note, axis: .vertical).lineLimit(2...5).focused($noteFocused)
                    .font(Theme.body).foregroundStyle(Theme.text).padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .onChange(of: note) { _, now in if now.count > 500 { note = String(now.prefix(500)) } }
                    .accessibilityIdentifier("report-note")

                // LIME-282b: what happens to a report, in lime's own words.
                Link("How we moderate", destination: URL(string: TermsAcceptance.guidelinesURL)!)
                    .font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text).underline()
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("report-how-we-moderate")

                if let group = target.group { groupInclude(group) } else {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Include this \(target.noun)", isOn: $include).tint(Theme.accent).font(Theme.body).accessibilityIdentifier("report-include")
                    if include, !target.preview.isEmpty {
                        Text(target.preview).font(Theme.caption).foregroundStyle(Theme.textSecondary).lineLimit(4)
                            .accessibilityIdentifier("report-preview")
                    }
                    Text(include ? "lime\u{2019}s team sees this \(target.noun) and your report. \(target.personName ?? "They") won\u{2019}t know it was you." : "lime\u{2019}s team sees your report only. \(target.personName ?? "They") won\u{2019}t know it was you.")
                        .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                if target.blockConversationID != nil, let name = target.personName {
                    Toggle("Also block \(name)", isOn: $alsoBlock).tint(Theme.accent).font(Theme.body).padding(14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityIdentifier("report-also-block")
                }
                if failed { Text("Couldn\u{2019}t send. Try again.").font(Theme.caption).foregroundStyle(Theme.danger).announcesWhenShown("Couldn\u{2019}t send. Try again.").accessibilityIdentifier("report-failed") }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// The group's Include section: Recent messages (each a toggle), Group name and photo, Who's in the group, Leave the group after reporting.
    @ViewBuilder
    private func groupInclude(_ group: GroupReportDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Include").font(Theme.font(.headline, weight: .semibold)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
            Text("Recent messages").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary).accessibilityAddTraits(.isHeader)
            if group.messages.isEmpty {
                Text("No messages yet.").font(Theme.caption).foregroundStyle(Theme.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(group.messages.enumerated()), id: \.element.id) { index, message in
                        let on = ticked.contains(message.id)
                        Button { if on { ticked.remove(message.id) } else { ticked.insert(message.id) } } label: {
                            HStack(spacing: 12) {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Theme.accent : Theme.textSecondary).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(message.senderName).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                                    Text(String(message.text.split(separator: "\n").first ?? "")).font(Theme.body).foregroundStyle(Theme.text).lineLimit(1)
                                    if message.attachments > 0 { Text("\(message.attachments) attachment\(message.attachments == 1 ? "" : "s") (not sent)").font(Theme.caption).foregroundStyle(Theme.textSecondary) }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14).frame(minHeight: 52).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Include message from \(message.senderName): \(message.text.prefix(80)), \(on ? "on" : "off")")
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                        .accessibilityIdentifier("report-message-\(message.id)")
                        if index < group.messages.count - 1 { Divider().overlay(Theme.hairline).padding(.leading, 14) }
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            VStack(spacing: 0) {
                Toggle("Group name and photo", isOn: $nameAndPhoto).tint(Theme.accent).font(Theme.body).padding(14).accessibilityIdentifier("report-group-name")
                Divider().overlay(Theme.hairline).padding(.leading, 14)
                Toggle("Who\u{2019}s in the group", isOn: $withMembers).tint(Theme.accent).font(Theme.body).padding(14).accessibilityIdentifier("report-group-members")
                Divider().overlay(Theme.hairline).padding(.leading, 14)
                Toggle("Leave the group after reporting", isOn: $leaveAfter).tint(Theme.accent).font(Theme.body).padding(14).accessibilityIdentifier("report-group-leave")
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("lime\u{2019}s team sees only what is ticked, and your report. The group won\u{2019}t know it was you.").font(Theme.caption).foregroundStyle(Theme.textSecondary)
        }
        .onAppear { if ticked.isEmpty { ticked = Set(group.messages.map(\.id)) } }
    }

    private var thanks: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle").font(.system(size: 44)).foregroundStyle(Theme.text).accessibilityHidden(true)
            Text("Thanks. lime\u{2019}s team will look at this.").font(Theme.font(.title3, weight: .semibold)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
                .accessibilityIdentifier("report-thanks")
            #if DEBUG
            // Tests: what the last demo report carried (kind and ids).
            if store.isDemo, let last = ConversationStore.demoReports.last {
                Text("").accessibilityLabel("\(last.kind) \(last.ids.joined(separator: ","))").accessibilityIdentifier("report-probe")
                Text("").accessibilityLabel(ConversationStore.demoLastIncluded).accessibilityIdentifier("report-included-probe")
            }
            #endif
            Spacer()
        }
        .padding(24).frame(maxWidth: .infinity)
    }

    private func send() async {
        guard let reason else { return }
        sending = true; failed = false
        var outgoing = target
        var includeIt = include
        if let group = target.group {
            let payload = group.payload(sending: ticked, nameAndPhoto: nameAndPhoto, withMembers: withMembers)
            outgoing.ids = payload.ids
            outgoing.included = payload.included
            includeIt = true
        }
        let ok = await store.sendReport(outgoing, reason: reason, note: note, include: includeIt, alsoBlock: alsoBlock)
        self.sending = false
        if ok, leaveAfter, let group = target.group { await store.leaveGroup(group.conversationID); leftGroup = true }
        if ok { sent = true } else { failed = true }
    }
}

extension View {
    /// Presents the Report sheet for a target (LIME-191).
    func reportSheet(_ target: Binding<ReportTarget?>) -> some View {
        sheet(item: target) { ReportSheet(target: $0) }
    }
}
