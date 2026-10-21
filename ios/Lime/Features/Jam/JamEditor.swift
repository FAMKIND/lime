import SwiftUI

/// Start your jam, or edit it (LIME-188): a title, a few lines about it, and up to eight topics.
struct JamDetailsSheet: View {
    let editing: JamInfo?
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
            .navigationTitle(editing == nil ? "Start your jam" : "Edit your jam")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("jam-details-cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Start" : "Save") { save() }
                        .disabled(!canSave).fontWeight(.semibold).accessibilityIdentifier("jam-details-save")
                }
            }
            .onAppear {
                if let editing, title.isEmpty { title = editing.title; about = editing.about; topics = editing.topics }
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
            if let editing { await store.editJam(editing.jamId, title: title, about: about, topics: topics) } else { await store.startJam(title: title, about: about, topics: topics) }
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

/// Write a post (LIME-188): a title, then the same rich text editor as chats with its formatting strip and the + for photos and files. Every post is
/// free (payments are off, so a subscribers-only post would reach nobody).
struct JamPostEditor: View {
    let jam: JamInfo
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var composer = RichComposerModel()
    @State private var sink = ComposerDraftSink()
    @State private var problem: String?
    @State private var publishing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Title", text: $title, axis: .vertical)
                    .font(Theme.font(.title3, weight: .bold)).lineLimit(1...3)
                    .padding(.horizontal, 20).padding(.top, 12)
                    .accessibilityLabel("Post title").accessibilityIdentifier("jam-post-title-field")
                if let problem {
                    Text(problem).font(Theme.secondary).foregroundStyle(.red).padding(.horizontal, 20).padding(.top, 4)
                        .accessibilityIdentifier("jam-post-problem")
                }
                Divider().overlay(Theme.hairline).padding(.top, 10)
                Spacer(minLength: 0)
                ChatComposer(model: composer, onSend: { _ in }, onSendAttachments: { _, _ in }, draftSink: sink)
                    .accessibilityLabel("Post text")
            }
            .background(Theme.canvas)
            .navigationTitle("New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("jam-post-cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Publish") { publish() }.fontWeight(.semibold).disabled(publishing).accessibilityIdentifier("jam-publish")
                }
            }
        }
    }

    private func publish() {
        let cleanTitle = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let markdown = composer.markdown()
        let items = sink.items
        guard !cleanTitle.isEmpty else { problem = "Add a title."; return }
        guard cleanTitle.count <= 120 else { problem = "Make the title shorter."; return }
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !items.isEmpty else { problem = "Write something, or add a photo or file."; return }
        guard items.allSatisfy({ $0.bytes.count <= 24 * 1024 * 1024 }) else { problem = "A file is too large for a post (24 MB)."; return }
        problem = nil
        publishing = true
        Task {
            let ok = await store.publishJamPost(jam.jamId, title: cleanTitle, markdown: markdown, items: items)
            publishing = false
            if ok { dismiss() } else { problem = "Could not publish. Try again." }
        }
    }
}
