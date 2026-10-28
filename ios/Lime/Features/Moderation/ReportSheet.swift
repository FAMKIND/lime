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
    @FocusState private var noteFocused: Bool

    var body: some View {
        NavigationStack {
            Group { if sent { thanks } else { form } }
                .background(Theme.canvas)
                .navigationTitle(sent ? "" : "Report").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { if !sent { Button("Cancel") { dismiss() }.accessibilityIdentifier("report-cancel") } }
                    ToolbarItem(placement: .topBarTrailing) {
                        if sent { Button("Done") { dismiss() }.fontWeight(.semibold).accessibilityIdentifier("report-done") }
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

                if target.blockConversationID != nil, let name = target.personName {
                    Toggle("Also block \(name)", isOn: $alsoBlock).tint(Theme.accent).font(Theme.body).padding(14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityIdentifier("report-also-block")
                }
                if failed { Text("Couldn\u{2019}t send. Try again.").font(Theme.caption).foregroundStyle(.red).accessibilityIdentifier("report-failed") }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var thanks: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle").font(.system(size: 44)).foregroundStyle(Theme.text).accessibilityHidden(true)
            Text("Thanks. lime\u{2019}s team will look at this.").font(Theme.font(.title3, weight: .semibold)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
                .accessibilityIdentifier("report-thanks")
            #if DEBUG
            // Tests: what the last demo report carried (kind and ids).
            if store.isDemo, let last = ConversationStore.demoReports.last { Text("").accessibilityLabel("\(last.kind) \(last.ids.joined(separator: ","))").accessibilityIdentifier("report-probe") }
            #endif
            Spacer()
        }
        .padding(24).frame(maxWidth: .infinity)
    }

    private func send() async {
        guard let reason else { return }
        sending = true; failed = false
        let ok = await store.sendReport(target, reason: reason, note: note, include: include, alsoBlock: alsoBlock)
        sending = false
        if ok { sent = true } else { failed = true }
    }
}

extension View {
    /// Presents the Report sheet for a target (LIME-191).
    func reportSheet(_ target: Binding<ReportTarget?>) -> some View {
        sheet(item: target) { ReportSheet(target: $0) }
    }
}
