import SwiftUI
import UIKit

/// Editing an org in place (LIME-245): the org page turns into its own editor, as a profile does. Each row opens one small sheet for that one thing.
enum OrgField: String, Identifiable {
    case name, about, tags
    var id: String { rawValue }
    var title: String { switch self { case .name: "Name"; case .about: "About"; case .tags: "Tags" } }
}

/// One field of an org in a small sheet: ✕ at the left, the title centred, a round ✓ (dimmed until there is a valid change), as the profile's field sheets.
struct OrgFieldSheet: View {
    let page: JamPageInfo
    let field: OrgField
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var topics: [String] = []
    @State private var custom = ""
    @State private var saving = false
    @State private var loaded = false
    @FocusState private var focused: Bool

    private static let suggestions = ["Maths", "Reading", "Writing", "Science", "Social studies", "Art", "Music", "Special needs", "Kindergarten", "Grade 1", "Grade 2", "Grade 3", "Grade 4", "Grade 5", "Grade 6"]

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var changed: Bool {
        switch field {
        case .name: trimmed != page.title
        case .about: trimmed != page.about
        case .tags: topics != page.topics
        }
    }
    private var valid: Bool {
        switch field {
        case .name: !trimmed.isEmpty && trimmed.count <= 60
        case .about: trimmed.count <= 500
        case .tags: topics.count <= 8
        }
    }
    private var canSave: Bool { changed && valid && !saving }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: field.title, leading: .close { dismiss() }) {
                Button(action: save) {
                    Image(systemName: "checkmark").font(.system(size: 17, weight: .bold))
                        .foregroundStyle(canSave ? Theme.accentInk : Theme.textSecondary.opacity(0.6))
                        .frame(width: 44, height: 44)
                        .background { if canSave { Circle().fill(Theme.accent) } else { Color.clear.limeGlass() } }
                }
                .disabled(!canSave).accessibilityLabel("Save").accessibilityIdentifier("org-field-save")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch field {
                    case .name:
                        pill { TextField("What is your publication called?", text: $text).font(Theme.body).textInputAutocapitalization(.sentences).focused($focused)
                            .submitLabel(.done).onSubmit { if canSave { save() } }.accessibilityIdentifier("jam-title-field") }
                        count("\(text.count)/60", over: text.count > 60)
                    case .about:
                        pill { TextField("What will you share?", text: $text, axis: .vertical).font(Theme.body).lineLimit(3...8).focused($focused).accessibilityIdentifier("jam-about-field") }
                        count("\(text.count)/500", over: text.count > 500)
                    case .tags:
                        FlowChips(items: Array((topics + Self.suggestions.filter { !topics.contains($0) }).prefix(24)), selected: Set(topics)) { toggle($0) }
                        HStack {
                            TextField("Add your own", text: $custom).font(Theme.body).onSubmit(addCustom).accessibilityIdentifier("jam-topic-field")
                            Button("Add", action: addCustom).disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty || topics.count >= 8).accessibilityIdentifier("jam-topic-add")
                        }
                        .padding(.horizontal, 14).frame(minHeight: 48)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text("Up to 8. Teachers find your publication by these.").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.canvas.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .onAppear {
            guard !loaded else { return }
            loaded = true
            switch field { case .name: text = page.title; case .about: text = page.about; case .tags: topics = page.topics }
            if field != .tags { focused = true }
        }
    }

    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func count(_ text: String, over: Bool) -> some View {
        Text(text).font(Theme.caption).foregroundStyle(over ? Color.red : Theme.textSecondary).frame(maxWidth: .infinity, alignment: .trailing)
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
        guard canSave else { return }
        saving = true
        Task {
            await store.editJam(page.jamId, title: field == .name ? trimmed : page.title, about: field == .about ? trimmed : page.about, topics: field == .tags ? topics : page.topics)
            dismiss()
        }
    }
}

/// The org's picture (LIME-194), from the camera circle on its page: Add or Change from Photos, Take Photo, Remove. Saved at once; the picture is public.
struct OrgPictureSheet: View {
    let jamId: String
    let title: String
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var pictureStep: PictureStep?
    @State private var cropping: UIImage?
    @State private var busy = false

    private enum PictureStep: String, Identifiable { case library, camera; var id: String { rawValue } }
    private struct CropItem: Identifiable {
        let image: UIImage
        var id: ObjectIdentifier { ObjectIdentifier(image) }
    }

    private var hasPicture: Bool { AvatarCache.shared.image(for: ConversationStore.jamPictureKey(jamId)) != nil }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Publication picture", leading: .close { dismiss() })
            VStack(spacing: 14) {
                JamInitialTile(title: title, jamId: jamId, size: 96).accessibilityHidden(true)
                HStack(spacing: 10) {
                    button("photo.on.rectangle", hasPicture ? "Change picture" : "Add picture", id: "jam-picture-add") { pictureStep = .library }
                    if CameraPicker.isAvailable { button("camera", "Take Photo", id: "jam-picture-camera") { pictureStep = .camera } }
                }
                if hasPicture { button("trash", "Remove", id: "jam-picture-remove") { remove() } }
                Text("Your publication's picture is public, like its name.").font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity).padding(.top, 8)
            .disabled(busy)
            Spacer(minLength: 0)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .presentationDetents([.medium])
        .fullScreenCover(item: $pictureStep) { step in
            switch step {
            case .library: LibraryPicker(onPick: { picked in pictureStep = nil; cropping = picked }, onCancel: { pictureStep = nil }).ignoresSafeArea()
            case .camera: CameraPicker(onPick: { picked in pictureStep = nil; cropping = picked }, onCancel: { pictureStep = nil }).ignoresSafeArea()
            }
        }
        .fullScreenCover(item: Binding(get: { cropping.map(CropItem.init) }, set: { if $0 == nil { cropping = nil } })) { item in
            PhotoCropScreen(image: item.image, onSave: { cropped in cropping = nil; save(cropped) }, onCancel: { cropping = nil })
        }
    }

    private func button(_ symbol: String, _ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text)
                .padding(.horizontal, 14).frame(minHeight: 44).background(Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func save(_ image: UIImage) {
        guard let jpeg = PhotoProcessing.jpeg(image) else { return }
        busy = true
        Task { _ = await store.setJamPicture(jamId, jpeg: jpeg); busy = false }
    }

    private func remove() {
        busy = true
        Task { _ = await store.removeJamPicture(jamId); busy = false }
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
