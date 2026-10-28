import SwiftUI

/// Who can read a post (LIME-210c, `docs/jam.md` 13.1): **Subscribers** (the default: end-to-end encrypted) or **Everyone on lime** (open, signed by the
/// writer, readable by lime's server). It sits beside "Post as" in the composer and in Edit. Choosing Everyone says once, before Post, what that means;
/// taking a post back from Everyone says plainly that people may already have read, saved or copied it. Shown only when the server takes open posts.
struct AudienceChip: View {
    @Binding var audience: String
    /// The audience the post being edited has now (nil for a new post): taking it back from Everyone asks first.
    var saved: String? = nil
    @State private var confirmingEveryone = false
    @State private var confirmingTakeBack = false

    private var everyone: Bool { audience == "everyone" }

    var body: some View {
        Menu {
            Button { choose("subscribers") } label: { Label("Subscribers", systemImage: !everyone ? "checkmark" : "lock") }
                .accessibilityIdentifier("audience-subscribers")
            Button { choose("everyone") } label: { Label("Everyone on lime", systemImage: everyone ? "checkmark" : "globe") }
                .accessibilityIdentifier("audience-everyone")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: everyone ? "globe" : "lock").font(.system(size: 13, weight: .medium)).accessibilityHidden(true)
                Text(everyone ? "Everyone" : "Subscribers").font(Theme.font(.subheadline, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).accessibilityHidden(true)
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12).frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .accessibilityLabel(everyone ? "Audience: everyone on lime" : "Audience: subscribers").accessibilityHint("Choose who can read this post")
        .accessibilityIdentifier("jam-audience")
        .confirmSheet("Everyone on lime can read this, and so can lime's server.", isPresented: $confirmingEveryone) {
            Button("Post to everyone") { audience = "everyone" }.accessibilityIdentifier("audience-confirm-everyone")
            Button("Keep it for subscribers", role: .cancel) {}.accessibilityIdentifier("audience-keep")
        }
        .confirmSheet("Make this post for subscribers only?", isPresented: $confirmingTakeBack) {
            Button("Make it subscribers only", role: .destructive) { audience = "subscribers" }.accessibilityIdentifier("audience-confirm-takeback")
            Button("Keep it open", role: .cancel) {}
        } message: { Text("People may already have read, saved or copied it.").accessibilityIdentifier("audience-takeback-copy") }
    }

    private func choose(_ new: String) {
        guard new != audience else { return }
        if new == "everyone" { confirmingEveryone = true }
        else if saved == "everyone" { confirmingTakeBack = true }
        else { audience = "subscribers" }
    }
}
