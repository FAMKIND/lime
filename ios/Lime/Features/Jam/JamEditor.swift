import SwiftUI

/// Edit your jam page (LIME-188b: reached from your profile): a title, a few lines about it, and up to eight topics. The jam itself is made on your first post.
struct JamDetailsSheet: View {
    let editing: JamInfo
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var about = ""
    @State private var topics: [String] = []
    @State private var custom = ""
    @State private var saving = false

    private static let suggestions = ["Maths", "Reading", "Writing", "Science", "Social studies", "Art", "Music", "Special needs", "Kindergarten", "Grade 1", "Grade 2", "Grade 3", "Grade 4", "Grade 5", "Grade 6"]
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 60 && about.count <= 500 && !saving }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("Title", footnote: "\(title.count)/60") {
                        TextField("What is your jam called?", text: $title)
                            .font(Theme.body).textInputAutocapitalization(.sentences)
                            .accessibilityIdentifier("jam-title-field")
                    }
                    field("About", footnote: "\(about.count)/500") {
                        TextField("What will you share?", text: $about, axis: .vertical)
                            .font(Theme.body).lineLimit(3...6)
                            .accessibilityIdentifier("jam-about-field")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Topics").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                        FlowChips(items: Array((topics + Self.suggestions.filter { !topics.contains($0) }).prefix(24)), selected: Set(topics)) { toggle($0) }
                        HStack {
                            TextField("Add your own", text: $custom).font(Theme.body).onSubmit(addCustom)
                                .accessibilityIdentifier("jam-topic-field")
                            Button("Add", action: addCustom).disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty || topics.count >= 8)
                                .accessibilityIdentifier("jam-topic-add")
                        }
                        .padding(.horizontal, 14).frame(minHeight: 48)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text("Up to 8. Teachers find your jam by these.").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(20)
            }
            .background(Theme.canvas)
            .navigationTitle("Edit jam page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("jam-details-cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave).fontWeight(.semibold).accessibilityIdentifier("jam-details-save")
                }
            }
            .onAppear {
                if title.isEmpty { title = editing.title; about = editing.about; topics = editing.topics }
            }
        }
        .presentationDetents([.large])
    }

    private func field<Content: View>(_ label: String, footnote: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(footnote).font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            content().padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func toggle(_ topic: String) {
        if let index = topics.firstIndex(of: topic) { topics.remove(at: index) } else if topics.count < 8 { topics.append(topic) }
    }

    private func addCustom() {
        let clean = custom.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !clean.isEmpty, clean.count <= 30, topics.count < 8, !topics.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) else { custom = ""; return }
        topics.append(clean)
        custom = ""
    }

    private func save() {
        saving = true
        Task {
            await store.editJam(editing.jamId, title: title, about: about, topics: topics)
            dismiss()
        }
    }
}

/// Topic chips that wrap onto lines.
struct FlowChips: View {
    let items: [String]
    let selected: Set<String>
    let tap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                let on = selected.contains(item)
                Button { tap(item) } label: {
                    Text(item).font(Theme.secondary).foregroundStyle(on ? Theme.accentInk : Theme.text)
                        .padding(.horizontal, 12).frame(minHeight: 36)
                        .background(on ? Theme.accent : Theme.surface, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
                .accessibilityIdentifier("jam-topic-\(item)")
            }
        }
    }
}

