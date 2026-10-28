import SwiftUI

extension ConversationStore {
    /// The writer turns the community chat of their jam on or off.
    func setCommunity(_ jamID: String, on: Bool) async -> Bool {
        #if DEBUG
        if isDemo { demoSetCommunity(jamID, on: on); return true }
        #endif
        guard let core else { return false }
        do { try await Task.detached(priority: .userInitiated) { try core.setJamCommunity(jamId: jamID, on: on) }.value }
        catch { CallDiagnostics.shared.log("jam community failed: \(error)"); return false }
        refreshJams()
        await deliverNow()
        return true
    }

    /// A subscriber asks to join: the writer's phone adds them when it next runs.
    func joinCommunity(_ jamID: String) async {
        #if DEBUG
        if isDemo { demoJoinCommunity(jamID); return }
        #endif
        guard let core else { return }
        _ = try? await Task.detached(priority: .userInitiated) { try core.joinJamCommunity(jamId: jamID) }.value
        refreshJams()
        await deliverNow()
    }
}

/// "Join Sam's community" on a followed jam (LIME-210g, `docs/jam.md` 13.8): shown to subscribers when the writer has a community chat. There is nothing to
/// approve: the writer's phone adds you by itself, so while it is offline this says when you will be added.
struct CommunityJoinRow: View {
    let jamID: String
    @Environment(ConversationStore.self) private var store

    var body: some View {
        if let jam = store.jamSubscriptions.first(where: { $0.jamId == jamID && $0.status == "active" }), jam.community {
            let first = store.teacherName(jam.writer).split(separator: " ").first.map(String.init) ?? "the writer"
            switch jam.communityState {
            case nil:
                Button { Task { await store.joinCommunity(jamID) } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 15, weight: .medium)).accessibilityHidden(true)
                        Text("Join \(first)\u{2019}s community").font(Theme.font(.subheadline, weight: .semibold))
                    }
                    .foregroundStyle(Theme.text).padding(.horizontal, 18).frame(minHeight: 44).background(Theme.surface, in: Capsule())
                }
                .buttonStyle(.plain).accessibilityIdentifier("community-join")
            case "asked":
                Text("You will be added when \(first)\u{2019}s phone is next online.").font(Theme.secondary).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                    .accessibilityIdentifier("community-asked")
            case "joined":
                Text("You are in the community. Find it in Messages.").font(Theme.secondary).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("community-joined")
            default:
                Text("The community is full.").font(Theme.secondary).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("community-full")
            }
        }
    }
}
