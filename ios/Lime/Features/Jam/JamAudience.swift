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
            // A new account waits 7 days: one clear line with the date, never a cut-off sentence (LIME-242).
            Button { choose("everyone") } label: { Label(opensOn.map { "Everyone \u{00B7} from \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "Everyone on lime", systemImage: everyone ? "checkmark" : "globe") }
                .disabled(opensOn != nil && !everyone)
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

/// The subject, grade and topic chips of a post (LIME-210h, choice (d)): the jam's topics are preselected; Discover's filters (on the phone) use them for
/// the open copy. Shown while the server takes open posts.
struct TopicsChip: View {
    @Binding var topics: [String]
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "tag").font(.system(size: 14, weight: .medium)).accessibilityHidden(true)
                Text(topics.isEmpty ? "Add subject and grade" : topics.joined(separator: " \u{00B7} ")).font(Theme.font(.subheadline)).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).accessibilityHidden(true)
            }
            .foregroundStyle(topics.isEmpty ? Theme.textSecondary : Theme.text).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(topics.isEmpty ? "Add subject and grade" : "Subject and grade: \(topics.joined(separator: ", "))").accessibilityHint("Choose what this post is about")
        .accessibilityIdentifier("jam-topics")
        .sheet(isPresented: $picking) { TopicsPickerSheet(topics: $topics) }
    }
}

struct TopicsPickerSheet: View {
    @Binding var topics: [String]
    @Environment(ConversationStore.self) private var store
    @State private var custom = ""
    static let subjects = ["Maths", "Reading", "Writing", "Science", "Social studies", "Art", "Music", "Special needs"]
    static let grades = ["Kindergarten", "Grade 1", "Grade 2", "Grade 3", "Grade 4", "Grade 5", "Grade 6"]
    private static let limit = 8

    /// Your tags: the jam's own and the ones you add, apart from the subjects and grades above.
    private var yours: [String] {
        let known = Set(Self.subjects + Self.grades)
        var out: [String] = []
        for t in store.jamsMine.first?.topics ?? [] + topics where !known.contains(t) && !out.contains(t) { out.append(t) }
        return out
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("\(topics.count) of \(Self.limit)").font(Theme.secondary).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity).accessibilityIdentifier("topics-count")
                    section("Subjects", Self.subjects)
                    section("Grades", Self.grades)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your tags").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary).accessibilityAddTraits(.isHeader)
                        if !yours.isEmpty { chips(yours) }
                        HStack {
                            TextField("Add your own", text: $custom).font(Theme.body).onSubmit(addCustom).accessibilityIdentifier("topics-custom")
                            Button("Add", action: addCustom).disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty || topics.count >= Self.limit).accessibilityIdentifier("topics-add")
                        }
                        .padding(.horizontal, 14).frame(minHeight: 48).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
            .background(Theme.canvas)
            .sheetHeader("Subject and grade")
        }
        .presentationDetents([.medium, .large])
    }

    private func section(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary).accessibilityAddTraits(.isHeader)
            chips(items)
        }
    }

    private func chips(_ items: [String]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                let on = topics.contains(item)
                Button { toggle(item) } label: {
                    HStack(spacing: 6) {
                        if on { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).accessibilityHidden(true) }
                        Text(item).font(Theme.secondary)
                    }
                    .foregroundStyle(Theme.text).padding(.horizontal, 14).frame(minHeight: 40)
                    .background(on ? Theme.accent.opacity(0.28) : Theme.surface, in: Capsule())
                    .overlay { if on { Capsule().strokeBorder(Theme.accent, lineWidth: 1.5) } }
                }
                .buttonStyle(.plain).accessibilityAddTraits(on ? [.isSelected] : []).accessibilityIdentifier("jam-topic-\(item)")
            }
        }
    }

    private func toggle(_ topic: String) {
        if let i = topics.firstIndex(of: topic) { topics.remove(at: i) } else if topics.count < Self.limit { topics.append(topic) }
    }

    private func addCustom() {
        let clean = custom.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        defer { custom = "" }
        guard !clean.isEmpty, clean.count <= 30, topics.count < Self.limit, !topics.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) else { return }
        topics.append(clean)
    }
}

/// The one sheet header (LIME-242), About's: a round ✕ on the left and the title centred. No Done: whatever you change applies as you make it, and ✕ just closes.
private struct LimeSheetHeader: ViewModifier {
    let title: String
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).frame(width: 36, height: 36).background(Theme.surface, in: Circle()).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close").accessibilityIdentifier("sheet-close")
                }
            }
    }
}

extension View {
    func sheetHeader(_ title: String) -> some View { modifier(LimeSheetHeader(title: title)) }
}
