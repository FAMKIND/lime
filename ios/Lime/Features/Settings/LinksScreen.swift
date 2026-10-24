import SwiftUI

/// Edit profile → Links (LIME-214): up to 5, each a title and an https address; drag to reorder; and who can see them. Contacts only until you choose.
struct LinksScreen: View {
    @Environment(ConversationStore.self) private var store
    @State private var links: [ProfileLink] = []
    @State private var visibility: ConversationStore.PhotoVisibility = .contacts
    @State private var loaded = false
    @State private var busy = false
    @State private var problem: String?
    @State private var saved = false

    var body: some View {
        List {
            Section {
                ForEach($links) { $link in
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Title", text: $link.title).font(Theme.body)
                            .onChange(of: link.title) { _, now in if now.count > ProfileLinks.maxTitle { link.title = String(now.prefix(ProfileLinks.maxTitle)) } }
                            .accessibilityLabel("Link title")
                        TextField("https://", text: $link.url).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            .accessibilityLabel("Link address")
                    }
                    .frame(minHeight: 56)
                    .accessibilityElement(children: .contain)
                }
                .onMove { links.move(fromOffsets: $0, toOffset: $1); saved = false }
                .onDelete { links.remove(atOffsets: $0); saved = false }
                if links.count < ProfileLinks.maxCount {
                    Button { links.append(ProfileLink(title: "", url: "")); saved = false } label: {
                        Label("Add a link", systemImage: "plus.circle").font(Theme.body).foregroundStyle(Theme.text).frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("links-add")
                }
            } footer: {
                Text(problem ?? "Up to \(ProfileLinks.maxCount) links. Drag to change the order.").foregroundStyle(problem == nil ? Theme.textSecondary : Color.red)
                    .accessibilityIdentifier("links-footer")
            }
            Section {
                choice(.everyone, "Everyone on lime", detail: "Any signed-in teacher who sees your profile can open your links. lime's servers keep a copy.", id: "links-vis-everyone")
                choice(.contacts, "Only my contacts (encrypted)", detail: "Teachers you message see them. They're encrypted; everyone else sees none.", id: "links-vis-contacts")
            } header: {
                Text("Who can see my links")
            }
            Section {
                Button { save() } label: {
                    HStack {
                        Spacer()
                        if busy { ProgressView() } else { Text(saved ? "Saved \u{2713}" : "Save").font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.accentInk) }
                        Spacer()
                    }
                    .frame(minHeight: 50).background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain).disabled(busy).accessibilityIdentifier("links-save")
                .listRowBackground(Color.clear)
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Links").navigationBarTitleDisplayMode(.inline)
        .task {
            guard !loaded else { return }
            let mine = await store.myExtra(.links)
            links = ProfileLinks.decode(mine.data)
            visibility = mine.visibility
            loaded = true
        }
    }

    private func choice(_ value: ConversationStore.PhotoVisibility, _ title: String, detail: String, id: String) -> some View {
        Button { choose(value) } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Theme.body).foregroundStyle(Theme.text)
                    Text(detail).font(Theme.secondary).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: visibility == value ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(visibility == value ? Theme.text : Theme.textSecondary)
            }
            .padding(.vertical, 6).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(busy)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(visibility == value ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(id)
    }

    private func choose(_ value: ConversationStore.PhotoVisibility) {
        guard value != visibility else { return }
        let previous = visibility
        visibility = value
        busy = true; problem = nil
        Task {
            let ok = await store.setExtraVisibility(.links, value)
            busy = false
            if !ok { visibility = previous; problem = "That couldn't be changed. Check your connection and try again." }
        }
    }

    private func save() {
        if let found = ProfileLinks.problem(in: links) { problem = found; return }
        let cleaned = ProfileLinks.cleaned(links)
        busy = true; problem = nil
        Task {
            let ok = await store.setMyExtra(.links, cleaned.isEmpty ? nil : ProfileLinks.encode(cleaned))
            busy = false
            if ok { links = cleaned; saved = true } else { problem = "The links could not be saved. Check your connection and try again." }
        }
    }
}
