import SwiftUI

/// Hand over publishing (LIME-275c): pick one of the band's other owners, then the plain confirmation. Nothing moves until they accept.
struct HandoverSheet: View {
    let page: JamPageInfo
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: OrgMemberInfo?
    @State private var working = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let chosen { confirm(chosen) } else { picker }
                }
                .padding(16)
            }
            .background(Theme.canvas)
            .sheetHeader("Hand over publishing")
        }
        .presentationDetents([.medium, .large])
        .alert("Not handed over", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}.accessibilityIdentifier("handover-failed-ok")
        } message: { Text(failure ?? "") }
    }

    private var picker: some View {
        let owners = store.handoverOwners(page.jamId)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Who will publish for \(page.title)?").font(Theme.body).foregroundStyle(Theme.text)
            if owners.isEmpty {
                Text("Only another owner can. Make someone an owner in Members first.").font(Theme.secondary).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("handover-no-owners")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(owners.enumerated()), id: \.element.userId) { index, owner in
                        Button { chosen = owner } label: {
                            HStack(spacing: 12) {
                                AvatarView(person: store.teacher(owner.userId), size: 36).accessibilityHidden(true)
                                Text(owner.name).font(Theme.body).foregroundStyle(Theme.text)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                            }
                            .padding(.horizontal, 18).frame(minHeight: 56).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("handover-owner-\(owner.userId)")
                        if index < owners.count - 1 { Divider().overlay(Theme.hairline).padding(.leading, 66) }
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private func confirm(_ owner: OrgMemberInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(owner.name)\u{2019}s phone will receive \(page.title)\u{2019}s subscriber list and publish for the band. You\u{2019}ll keep editing and reviewing.")
                .font(Theme.body).foregroundStyle(Theme.text).accessibilityIdentifier("handover-confirm-text")
            Button {
                working = true
                Task {
                    let why = await store.offerHandover(page.jamId, to: owner.userId)
                    working = false
                    if let why { failure = why } else { dismiss() }
                }
            } label: {
                Text(working ? "Asking\u{2026}" : "Hand over").font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.accentInk)
                    .frame(maxWidth: .infinity, minHeight: 50).background(Theme.accent, in: Capsule())
            }
            .disabled(working).accessibilityIdentifier("handover-confirm")
            Button { chosen = nil } label: {
                Text("Choose someone else").font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.text).frame(maxWidth: .infinity, minHeight: 50).background(Theme.surface, in: Capsule())
            }
            .accessibilityIdentifier("handover-back")
        }
    }
}

/// An offer made to me: "Shem wants to hand lime juice's publishing to you", with both answers as buttons (an alert-style card at the top of the feed).
struct HandoverOfferCard: View {
    let offer: HandoverInfo
    @Environment(ConversationStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(store.teacherName(offer.peer)) wants to hand \(offer.title)\u{2019}s publishing to you").font(Theme.body).foregroundStyle(Theme.text)
                .accessibilityIdentifier("handover-offer-\(offer.jamId)")
            Text("You\u{2019}d receive its subscriber list and publish for the band.").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 10) {
                Button { Task { await store.acceptHandover(offer.jamId) } } label: {
                    Text("Accept").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.accentInk).padding(.horizontal, 18).frame(minHeight: 44).background(Theme.accent, in: Capsule())
                }
                .accessibilityIdentifier("handover-accept-\(offer.jamId)")
                Button { Task { await store.declineHandover(offer.jamId) } } label: {
                    Text("Decline").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text).padding(.horizontal, 18).frame(minHeight: 44).background(Theme.canvas, in: Capsule())
                }
                .accessibilityIdentifier("handover-decline-\(offer.jamId)")
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
