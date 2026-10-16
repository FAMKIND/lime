import SwiftUI
import UIKit

// MARK: The card in the chat

/// An emergency status in the timeline: the label word and an icon (never colour alone), the sender, the status line, the time.
struct EmergencyCardView: View {
    let card: EmergencyCard
    let senderName: String
    let date: Date
    let id: String

    private var icon: String { card.isEnd ? "checkmark.shield" : (card.needsHelp ? "exclamationmark.triangle.fill" : "checkmark.circle") }

    private var spoken: String {
        let label = card.drill ? "Drill" : "Emergency"
        if card.isEnd { return "\(label). \(EmergencyCopy.endedWords(by: senderName, drill: card.drill))" }
        var words = "\(label). \(senderName). \(EmergencyCopy.summary(card))"
        if !card.note.isEmpty { words += ". \(card.note)" }
        return words
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold)).accessibilityHidden(true)
                Text(EmergencyCopy.label(drill: card.drill)).font(Theme.secondary.weight(.bold)).tracking(1.2)
                Spacer(minLength: 8)
                Text(date.formatted(date: .omitted, time: .shortened)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            if card.isEnd {
                Text(EmergencyCopy.endedWords(by: senderName, drill: card.drill)).font(Theme.title)
            } else {
                Text(senderName).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                Text(EmergencyCopy.summary(card)).font(Theme.title).fixedSize(horizontal: false, vertical: true)
                if !card.note.isEmpty { Text(card.note).font(Theme.body).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .foregroundStyle(Theme.text)
        .padding(14)
        .frame(maxWidth: 320, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.text.opacity(card.drill ? 0.25 : 0.7), style: StrokeStyle(lineWidth: card.drill ? 1 : 2, dash: card.drill ? [6, 4] : [])))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("emergency-card-\(id)")
    }
}

// MARK: Starting it

/// The status sheet (one screen, big targets): call first, then the status, the students, where, a note, and who it goes to.
struct EmergencySheet: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let drill: Bool
    var conversationID: String?

    @State private var status = "safe"
    @State private var situation = ""
    @State private var students = 0
    @State private var place = ""
    @State private var note = ""
    @State private var target = ""
    @State private var settings: EmergencySettings?
    @State private var changing = false
    @State private var sending = false
    @AccessibilityFocusState private var focusStatus: Bool

    private let number = EmergencyCopy.number()
    private var targetTitle: String { store.conversation(target)?.title ?? "No group chosen" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(drill ? "DRILL" : "EMERGENCY").font(Theme.title.weight(.bold)).tracking(1.4)
                    Spacer()
                    Button("Close") { dismiss() }.font(Theme.body).frame(minWidth: 60, minHeight: 60)
                        .accessibilityIdentifier("emergency-close")
                }
                if drill {
                    Text("This is a drill. Everyone sees DRILL, and it never breaks through Do Not Disturb.")
                        .font(Theme.secondary).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("emergency-drill-note")
                } else {
                    Button { if let url = URL(string: "tel:\(number)") { openURL(url) } } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "phone.fill").font(.system(size: 22)).accessibilityHidden(true)
                            Text(EmergencyCopy.callFirst(number: number)).font(Theme.title)
                            Spacer()
                        }
                        .foregroundStyle(Theme.text).padding(.horizontal, 18).frame(maxWidth: .infinity, minHeight: 64)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.text.opacity(0.7), lineWidth: 2))
                    }
                    .accessibilityHint("Starts a phone call")
                    .accessibilityIdentifier("emergency-call-first")
                    Text(EmergencyCopy.neverAlerts).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }

                HStack(spacing: 12) {
                    choice("Safe", symbol: "checkmark.circle", selected: status == "safe", id: "emergency-safe") { status = "safe" }
                    choice("Need help", symbol: "exclamationmark.triangle", selected: status == "need_help", id: "emergency-need-help") { status = "need_help" }
                }
                .accessibilityFocused($focusStatus)

                if settings?.schoolActions == true {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Situation").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                        FlowRow(spacing: 8) {
                            ForEach(["hold", "secure", "lockdown", "evacuate", "shelter"], id: \.self) { key in
                                Button { situation = situation == key ? "" : key } label: {
                                    Text(EmergencyCopy.situationWords(key)).font(Theme.body)
                                        .padding(.horizontal, 16).frame(minHeight: 60)
                                        .background(situation == key ? Theme.accent : Theme.surface, in: Capsule())
                                        .foregroundStyle(situation == key ? Theme.accentInk : Theme.text)
                                }
                                .accessibilityAddTraits(situation == key ? .isSelected : [])
                                .accessibilityIdentifier("emergency-situation-\(key)")
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    Text("Students with me").font(Theme.title)
                    Spacer()
                    stepButton("minus", label: "Fewer students", id: "emergency-students-minus") { students = max(0, students - 1) }
                    Text("\(students)").font(Theme.title).frame(minWidth: 48).accessibilityIdentifier("emergency-students")
                        .accessibilityLabel("\(students) students")
                    stepButton("plus", label: "More students", id: "emergency-students-plus") { students = min(9999, students + 1) }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Where").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    TextField("Room 204", text: $place)
                        .font(Theme.body).padding(.horizontal, 14).frame(minHeight: 60)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .submitLabel(.done)
                        .accessibilityIdentifier("emergency-where")
                    Text("lime does not use your location.").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Note (optional)").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    TextField("A short note", text: $note)
                        .font(Theme.body).padding(.horizontal, 14).frame(minHeight: 60)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .submitLabel(.done)
                        .accessibilityIdentifier("emergency-note")
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Send to").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        Text(targetTitle).font(Theme.title).accessibilityIdentifier("emergency-target")
                    }
                    Spacer()
                    Button("Change") { changing = true }.font(Theme.body).frame(minWidth: 80, minHeight: 60)
                        .accessibilityIdentifier("emergency-change")
                }

                Button { Task { await send() } } label: {
                    Text(drill ? "Send drill status" : "Send").font(Theme.title).foregroundStyle(Theme.accentInk)
                        .frame(maxWidth: .infinity, minHeight: 64).background(Theme.accent, in: Capsule())
                }
                .disabled(target.isEmpty || sending)
                .opacity(target.isEmpty ? 0.45 : 1)
                .accessibilityIdentifier("emergency-send")
                if target.isEmpty { Text(EmergencyCopy.noGroup).font(Theme.caption).foregroundStyle(Theme.textSecondary) }
                Text(EmergencyCopy.keepAwake).font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.canvas.ignoresSafeArea())
        .accessibilityIdentifier("emergency-sheet")
        .sheet(isPresented: $changing) {
            EmergencyGroupPicker(selected: target) { picked in target = picked; changing = false }
        }
        .task {
            let loaded = await store.emergencySettings()
            settings = loaded
            students = Int(loaded.lastStudents)
            place = loaded.lastPlace
            target = conversationID ?? (store.conversation(loaded.groupId) != nil ? loaded.groupId : "")
            focusStatus = true
        }
    }

    private func choice(_ title: String, symbol: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 26)).accessibilityHidden(true)
                Text(title).font(Theme.title)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .foregroundStyle(selected ? Theme.accentInk : Theme.text)
            .background(selected ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.text.opacity(selected ? 0.9 : 0.2), lineWidth: selected ? 2 : 1))
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private func stepButton(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).frame(width: 60, height: 60)
                .background(Theme.surface, in: Circle()).foregroundStyle(Theme.text)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func send() async {
        sending = true
        defer { sending = false }
        let draft = EmergencyDraft(status: status, situation: settings?.schoolActions == true ? situation : "", students: UInt32(students),
                                   place: place, note: note, drill: drill)
        if await store.sendEmergency(draft, to: target) {
            #if DEBUG
            if !drill, !store.isDemo { MeshService.shared.setNearby(true) }   // turning an emergency on turns Nearby mode on (M3)
            #endif
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } else {
            store.showBanner("Couldn\u{2019}t send. Try again.")
        }
    }
}

/// A simple wrapping row for the situation chips.
struct FlowRow<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: Content
    var body: some View {
        // Chips are few; a wrapping layout keeps them readable at large text sizes.
        FlowLayout(spacing: spacing) { content }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? 320, subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(bounds.width, subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        var origins: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

/// Choose the group an emergency goes to (the sheet's "Change" and Settings).
struct EmergencyGroupPicker: View {
    @Environment(ConversationStore.self) private var store
    let selected: String
    let onPick: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.emergencyGroups) { group in
                    Button { onPick(group.id) } label: {
                        HStack {
                            Text(group.title).font(Theme.body).foregroundStyle(Theme.text)
                            Spacer()
                            if group.id == selected { Image(systemName: "checkmark").accessibilityHidden(true) }
                        }
                        .frame(minHeight: 60)
                    }
                    .accessibilityAddTraits(group.id == selected ? .isSelected : [])
                    .accessibilityIdentifier("emergency-group-\(group.id)")
                }
                if store.emergencyGroups.isEmpty { Text("You are not in a group yet.").foregroundStyle(Theme.textSecondary) }
            }
            .navigationTitle("Send to")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: The roll-up in the group

/// While an emergency is active in a group: everyone's latest status (need help first, then no response, then safe), the totals, and End.
struct EmergencyPanel: View {
    @Environment(ConversationStore.self) private var store
    let conversation: Conversation
    @State private var rollup: EmergencyRollup?
    @State private var showSheet = false
    @State private var confirmEnd = false

    private func name(_ entry: RollupEntry) -> String {
        guard let id = entry.userId else { return "You" }
        return conversation.members.first { $0.id == id }?.name ?? "Someone"
    }

    var body: some View {
        // A container that is always there (a `Group` with nothing in it would not run the task that loads the roll-up).
        VStack(spacing: 0) {
            if let rollup {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                        Text(EmergencyCopy.label(drill: rollup.drill)).font(Theme.secondary.weight(.bold)).tracking(1.2)
                        Spacer()
                    }
                    Text("\(rollup.safe) safe \u{00B7} \(rollup.needHelp) need help \u{00B7} \(rollup.noResponse) no response \u{00B7} \(EmergencyCopy.studentsWords(Int(rollup.studentsTotal)))")
                        .font(Theme.title).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("emergency-totals")
                    ForEach(Array(rollup.entries.enumerated()), id: \.offset) { index, entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(name(entry)).font(Theme.body.weight(.semibold))
                                Spacer()
                                Text(EmergencyCopy.statusWords(entry.status)).font(Theme.body)
                            }
                            if entry.status != "no_response" {
                                let detail = [EmergencyCopy.situationWords(entry.situation), EmergencyCopy.studentsWords(Int(entry.students)), entry.place].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
                                Text(detail).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Tap a person: their thread.
                            if let id = entry.userId, store.conversation("dm:\(id)") != nil { store.path.append("dm:\(id)") }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(entry.userId == nil ? [] : .isButton)
                        .accessibilityIdentifier("emergency-entry-\(index)")
                    }
                    HStack(spacing: 10) {
                        Button { showSheet = true } label: {
                            Text("Send my status").font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.accentInk)
                                .padding(.horizontal, 16).frame(minHeight: 48).background(Theme.accent, in: Capsule())
                        }
                        .accessibilityIdentifier("emergency-update")
                        Button { confirmEnd = true } label: {
                            Text(rollup.drill ? "End drill" : "End emergency").font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.text)
                                .padding(.horizontal, 16).frame(minHeight: 48).overlay(Capsule().strokeBorder(Theme.text.opacity(0.5), lineWidth: 1))
                        }
                        .accessibilityIdentifier("emergency-end")
                    }
                }
                .foregroundStyle(Theme.text)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.text.opacity(rollup.drill ? 0.25 : 0.7), style: StrokeStyle(lineWidth: rollup.drill ? 1 : 2, dash: rollup.drill ? [6, 4] : [])))
                .padding(.horizontal, 8)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("emergency-panel")
                .sheet(isPresented: $showSheet) { EmergencySheet(drill: rollup.drill, conversationID: conversation.id) }
                .confirmSheet(rollup.drill ? "End the drill?" : "End the emergency?", isPresented: $confirmEnd) {
                    Button(rollup.drill ? "End drill" : "End emergency", role: .destructive) { Task { await store.endEmergency(in: conversation.id) } }
                        .accessibilityIdentifier("emergency-end-confirm")
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Everyone in \(conversation.title) will see that you ended it.")
                }
            }
        }
        .task(id: conversation.messages.count) { rollup = await store.emergencyRollup(for: conversation.id) }
    }
}

// MARK: Settings → Emergency

struct EmergencySettingsScreen: View {
    @Environment(ConversationStore.self) private var store
    @State private var settings: EmergencySettings?
    @State private var picking = false
    @State private var drill = false

    private func binding<T>(_ keyPath: WritableKeyPath<EmergencySettings, T>, fallback: T) -> Binding<T> {
        Binding(get: { settings?[keyPath: keyPath] ?? fallback },
                set: { value in
                    guard var next = settings else { return }
                    next[keyPath: keyPath] = value
                    settings = next
                    Task { await store.saveEmergencySettings(next) }
                })
    }

    private var groupTitle: String { store.conversation(settings?.groupId ?? "")?.title ?? "None" }

    var body: some View {
        SettingsPage(title: "Emergency") {
            SettingsCard {
                Button { picking = true } label: {
                    SettingsRowLabel(symbol: "person.2", title: "Emergency group", value: groupTitle, showsDivider: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("emergency-settings-group")
            }
            SettingsFootnote(text: "Where statuses go. You can also choose it from a group\u{2019}s \u{22EF} menu. Start an emergency by long-pressing + in Messages, or from the group\u{2019}s \u{22EF} menu.")
            SettingsCard {
                Toggle(isOn: binding(\.schoolActions, fallback: true)) { Text(EmergencyCopy.schoolActionsTitle).font(Theme.body).foregroundStyle(Theme.text) }
                    .tint(Theme.accent).padding(.horizontal, 18).frame(minHeight: 58)
                    .accessibilityIdentifier("emergency-settings-school")
            }
            SettingsFootnote(text: EmergencyCopy.schoolActionsWhy)
            SettingsCard {
                Toggle(isOn: binding(\.sound, fallback: false)) { Text(EmergencyCopy.soundTitle).font(Theme.body).foregroundStyle(Theme.text) }
                    .tint(Theme.accent).padding(.horizontal, 18).frame(minHeight: 58)
                    .accessibilityIdentifier("emergency-settings-sound")
            }
            SettingsFootnote(text: EmergencyCopy.soundWhy)
            SettingsCard {
                Button { drill = true } label: {
                    SettingsRowLabel(symbol: "figure.walk", title: "Start a drill", showsDivider: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("emergency-settings-drill")
            }
            SettingsFootnote(text: "A drill says DRILL on every card, notification and panel, and never breaks through Do Not Disturb.")
            SettingsFootnote(text: "\(EmergencyCopy.callFirst(number: EmergencyCopy.number())). \(EmergencyCopy.neverAlerts)")
            SettingsFootnote(text: EmergencyCopy.pushNote).accessibilityIdentifier("emergency-settings-honest")
        }
        .task { settings = await store.emergencySettings() }
        .sheet(isPresented: $picking) {
            EmergencyGroupPicker(selected: settings?.groupId ?? "") { picked in
                picking = false
                if var next = settings { next.groupId = picked; settings = next; Task { await store.saveEmergencySettings(next) } }
            }
        }
        .sheet(isPresented: $drill) { EmergencySheet(drill: true, conversationID: nil) }
    }
}
