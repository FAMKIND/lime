import SwiftUI
import UIKit

/// Making a band (a publication) from jam's + (LIME-254), in a sheet as New group is: step 1 the picture, the name (required, 60) and an optional about; step 2 the tags, then Create.
/// It ends on the new publication's page, which says where to post as it. The picture, name, about and tags are public, the owner's choice, as for any jam page.
struct CreatePublicationSheet: View {
    /// Called with the new jam's id once it exists; the sheet has closed itself.
    var onCreated: (String) -> Void
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var step = 1
    @State private var name = ""
    @State private var about = ""
    @State private var topics: [String] = []
    @State private var custom = ""
    @State private var picture: UIImage?
    @State private var pictureStep: PictureStep?
    @State private var cropping: UIImage?
    @State private var making = false
    @State private var failed = false
    @FocusState private var focused: Bool

    private enum PictureStep: String, Identifiable { case library, camera; var id: String { rawValue } }
    private struct CropItem: Identifiable {
        let image: UIImage
        var id: ObjectIdentifier { ObjectIdentifier(image) }
    }

    private static let nameLimit = 60
    private static let aboutLimit = 500
    private static let suggestions = ["Maths", "Reading", "Writing", "Science", "Social studies", "Art", "Music", "Special needs", "Kindergarten", "Grade 1", "Grade 2", "Grade 3", "Grade 4", "Grade 5", "Grade 6"]
    private var cleaned: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canNext: Bool { !cleaned.isEmpty && cleaned.count <= Self.nameLimit }
    private var canCreate: Bool { canNext && !making }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Step \(step) of 2", leading: step == 1 ? .close { dismiss() } : .back { step = 1 }) {
                if step == 1 { pill("Next", enabled: canNext, id: "publication-next") { step = 2; focused = false } }
                else { pill(making ? "Creating…" : "Create", enabled: canCreate, id: "publication-create") { create() } }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if step == 1 { first } else { second }
                    if failed { Text("Could not make it. Try again.").font(Theme.secondary).foregroundStyle(Color.red).accessibilityIdentifier("publication-failed") }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.canvas.ignoresSafeArea())
        .presentationDetents([.large])
        .interactiveDismissDisabled(making)
        .onAppear { focused = true }
        .fullScreenCover(item: $pictureStep) { s in
            switch s {
            case .library: LibraryPicker(onPick: { picked in pictureStep = nil; cropping = picked }, onCancel: { pictureStep = nil }).ignoresSafeArea()
            case .camera: CameraPicker(onPick: { picked in pictureStep = nil; cropping = picked }, onCancel: { pictureStep = nil }).ignoresSafeArea()
            }
        }
        .fullScreenCover(item: Binding(get: { cropping.map(CropItem.init) }, set: { if $0 == nil { cropping = nil } })) { item in
            PhotoCropScreen(image: item.image, onSave: { cropped in cropping = nil; picture = cropped }, onCancel: { cropping = nil })
        }
    }

    // MARK: Steps

    private var first: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Spacer(); pictureTile; Spacer() }
            VStack(alignment: .leading, spacing: 6) {
                TextField("What is your band called?", text: Binding(get: { name }, set: { name = String($0.prefix(Self.nameLimit)) }))
                    .font(Theme.body).selectionTint().focused($focused).submitLabel(.next).onSubmit { if canNext { step = 2 } }
                    .padding(.horizontal, 16).frame(minHeight: 52)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel("Name").accessibilityIdentifier("publication-name-field")
                Text("\(min(cleaned.count, Self.nameLimit))/\(Self.nameLimit)").font(Theme.caption).foregroundStyle(Theme.textSecondary).padding(.horizontal, 6)
            }
            VStack(alignment: .leading, spacing: 6) {
                TextField("What will you share? (optional)", text: Binding(get: { about }, set: { about = String($0.prefix(Self.aboutLimit)) }), axis: .vertical)
                    .font(Theme.body).selectionTint().lineLimit(3...8)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel("About").accessibilityIdentifier("publication-about-field")
                Text("The picture, name and about are public.").font(Theme.caption).foregroundStyle(Theme.textSecondary).padding(.horizontal, 6)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Band together.").font(Theme.font(.footnote, weight: .semibold)).foregroundStyle(Theme.text)
                Text("A band is teachers playing together: a school team, a co-op, a union, a publication.").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("band-explainer")
            }
        }
    }

    private var second: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tags").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary).accessibilityAddTraits(.isHeader)
            FlowChips(items: Array((topics + Self.suggestions.filter { !topics.contains($0) }).prefix(24)), selected: Set(topics)) { toggle($0) }
            HStack {
                TextField("Add your own", text: $custom).font(Theme.body).onSubmit(addCustom).accessibilityIdentifier("jam-topic-field")
                Button("Add", action: addCustom).disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty || topics.count >= 8).accessibilityIdentifier("jam-topic-add")
            }
            .padding(.horizontal, 14).frame(minHeight: 48)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("Up to 8. Teachers find your band by these.").font(Theme.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    /// The picture: its first letter on a tint until one is chosen; the camera circle opens Add, Take Photo, Remove.
    private var pictureTile: some View {
        ZStack {
            if let picture {
                Image(uiImage: picture).resizable().scaledToFill().frame(width: 104, height: 104).clipShape(RoundedRectangle(cornerRadius: 104 * 0.28, style: .continuous))
            } else {
                JamInitialTile(title: cleaned.isEmpty ? "P" : cleaned, size: 104)
            }
        }
        .frame(width: 104, height: 104).accessibilityHidden(true)
        .overlay(alignment: .topTrailing) {
            Menu {
                Button { pictureStep = .library } label: { Label(picture == nil ? "Add picture" : "Change picture", systemImage: "photo.on.rectangle") }
                if CameraPicker.isAvailable { Button { pictureStep = .camera } label: { Label("Take Photo", systemImage: "camera") } }
                if picture != nil { Button(role: .destructive) { picture = nil } label: { Label("Remove", systemImage: "trash") } }
            } label: {
                Image(systemName: "camera.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                    .frame(width: 34, height: 34).background(Theme.surface.opacity(0.92), in: Circle()).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .offset(x: 12, y: -12).accessibilityLabel("Band picture").accessibilityIdentifier("publication-picture")
        }
        .padding(.top, 8)
    }

    private func pill(_ title: String, enabled: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.title).foregroundStyle(Theme.accentInk)
                .padding(.horizontal, 18).frame(minHeight: 44)
                .background(Theme.accent.opacity(enabled ? 1 : 0.4), in: Capsule())
                .opacity(enabled ? 1 : 0.6)
        }
        .disabled(!enabled).accessibilityIdentifier(id)
    }

    // MARK: Actions

    private func toggle(_ topic: String) {
        if let index = topics.firstIndex(of: topic) { topics.remove(at: index) } else if topics.count < 8 { topics.append(topic) }
    }

    private func addCustom() {
        let clean = custom.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !clean.isEmpty, clean.count <= 30, topics.count < 8, !topics.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) else { custom = ""; return }
        topics.append(clean)
        custom = ""
    }

    private func create() {
        guard canCreate else { return }
        making = true
        failed = false
        UIAccessibility.post(notification: .announcement, argument: "Creating")
        let jpeg = picture.flatMap { PhotoProcessing.jpeg($0) }
        Task {
            let id = await store.createPublication(title: cleaned, about: about.trimmingCharacters(in: .whitespacesAndNewlines), topics: topics, picture: jpeg)
            making = false
            if let id { dismiss(); onCreated(id) } else { failed = true }
        }
    }
}
