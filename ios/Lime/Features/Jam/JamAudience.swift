import SwiftUI

/// Who can read a post (LIME-210c, `docs/jam.md` 13.1): **Subscribers** (the default: end-to-end encrypted) or **Everyone on lime** (open, signed by the
/// writer, readable by lime's server). It sits beside "Post as" in the composer and in Edit. Choosing Everyone says once, before Post, what that means;
/// taking a post back from Everyone says plainly that people may already have read, saved or copied it. Shown only when the server takes open posts.
struct AudienceChip: View {
    @Binding var audience: String
    /// The audience the post being edited has now (nil for a new post): taking it back from Everyone asks first.
    var saved: String? = nil
    /// A new account waits before it can post to Everyone (LIME-210d): the day it opens, or nil.
    var opensOn: Date? = AccountAge.everyoneOpensOn()
    @State private var confirmingEveryone = false
    @State private var confirmingTakeBack = false

    private var everyone: Bool { audience == "everyone" }

    var body: some View {
        Menu {
            Button { choose("subscribers") } label: { Label("Subscribers", systemImage: !everyone ? "checkmark" : "lock") }
                .accessibilityIdentifier("audience-subscribers")
            Button { choose("everyone") } label: { Label(opensOn.map { "Everyone opens \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "Everyone on lime", systemImage: everyone ? "checkmark" : "globe") }
                .disabled(opensOn != nil && !everyone)
                .accessibilityIdentifier("audience-everyone")
            if let opensOn {
                Text("New accounts can post to everyone after 7 days (\(opensOn.formatted(.dateTime.month(.abbreviated).day()))).").accessibilityIdentifier("audience-opens")
            }
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
