import SwiftUI

/// A blocked person's message, or a run of them, as one quiet row (LIME-330): no avatar or name, "Message from someone you blocked" and Show. Show reveals them in this
/// chat until you leave it. One VoiceOver element (label, action "Show") while VoiceOver or Switch Control runs; touch and the UI tests keep the button.
struct BlockedMessagesRow: View {
    let count: Int
    let show: () -> Void
    let idSuffix: String

    var body: some View {
        HStack(spacing: 12) {
            Text(BlockedPeople.collapsedWords(count: count))
                .font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("blocked-row-\(idSuffix)")
            Spacer(minLength: 0)
            Button("Show") { show() }
                .font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.linkOther)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("blocked-show-\(idSuffix)")
        }
        .padding(.horizontal, 16).padding(.vertical, 2)
        .modifier(BlockedRowStopModifier(label: BlockedPeople.collapsedWords(count: count), show: show))
    }
}

/// One element for VoiceOver and Switch Control: the label, and "Show" as its action (the name of the person is never spoken until Show).
struct BlockedRowStopModifier: ViewModifier {
    let label: String
    let show: () -> Void
    func body(content: Content) -> some View {
        if CallControlsPolicy.voiceOverRunning || CallControlsPolicy.switchControlRunning {
            content.accessibilityElement(children: .ignore).accessibilityLabel(label)
                .accessibilityAction(named: "Show") { show() }
                .accessibilityAddTraits(.isButton)
        } else { content }
    }
}

/// "Block NAME? You won't see their messages or comments anywhere on this phone. They won't be told." with Block (danger) and Cancel (LIME-330): one sheet for every place
/// Block is offered. After it, "NAME blocked" is announced.
struct BlockTarget: Identifiable, Equatable {
    let userID: String
    let name: String
    var id: String { userID }
}

extension View {
    func blockPersonConfirm(_ target: Binding<BlockTarget?>, store: ConversationStore, then: @escaping () -> Void = {}) -> some View {
        confirmSheet("Block \(target.wrappedValue?.name ?? "this person")?", isPresented: Binding(get: { target.wrappedValue != nil }, set: { if !$0 { target.wrappedValue = nil } })) {
            Button("Block", role: .destructive) {
                if let who = target.wrappedValue {
                    Task { await store.blockPerson(who.userID, name: who.name); then() }
                }
            }
            .accessibilityIdentifier("block-person-confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won\u{2019}t see their messages or comments anywhere on this phone. They won\u{2019}t be told.")
        }
    }
}
