import SwiftUI
import UIKit

/// A band's cover and colour (LIME-258), from Edit Cover on its page, and a group's (LIME-257): a cover (Photos or the camera, framed into the hero's 4:5 as a
/// profile's is; Remove brings the ambient default back) and one of the eight avatar colours (the default comes from the id). Saved at once.
struct OrgCoverSheet: View {
    let jamId: String
    @Environment(ConversationStore.self) private var store

    var body: some View {
        CoverColourSheet(
            cover: AvatarCache.shared.image(for: ConversationStore.jamCoverKey(jamId)), chosen: store.jamTones[jamId], current: store.jamTone(jamId),
            note: "The cover and colour are public, like the band's name.",
            setTone: { await store.setJamTone(jamId, tone: $0) }, setCover: { await store.setJamCover(jamId, jpeg: $0) }, removeCover: { await store.removeJamCover(jamId) })
    }
}

/// The sheet itself, for a band or a group: what is held now, and what each choice does.
struct CoverColourSheet: View {
    let cover: UIImage?
    let chosen: Int?
    let current: Int
    let note: String
    let setTone: (Int?) async -> Bool
    let setCover: (Data) async -> Bool
    let removeCover: () async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step?
    @State private var framing: UIImage?
    @State private var busy = false
    @State private var problem: String?

    private enum Step: String, Identifiable { case library, camera; var id: String { rawValue } }
    private struct FrameItem: Identifiable {
        let image: UIImage
        var id: ObjectIdentifier { ObjectIdentifier(image) }
    }

    /// The names of the eight avatar colours, in tone order (what VoiceOver says).
    static let names = LimeColours.names

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Cover and colour", leading: .close { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    coverSection
                    colourSection
                    if let problem { Text(problem).font(Theme.secondary).foregroundStyle(Color.red) }
                    Text(note).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .limeBackground()
        .presentationDetents([.medium, .large])
        .disabled(busy)
        .fullScreenCover(item: $step) { s in
            switch s {
            case .library: LibraryPicker(onPick: { picked in step = nil; framing = picked }, onCancel: { step = nil }).ignoresSafeArea()
            case .camera: CameraPicker(onPick: { picked in step = nil; framing = picked }, onCancel: { step = nil }).ignoresSafeArea()
            }
        }
        .fullScreenCover(item: Binding(get: { framing.map(FrameItem.init) }, set: { if $0 == nil { framing = nil } })) { item in
            BackgroundCropScreen(image: item.image, onSave: { crop in framing = nil; save(crop) }, onCancel: { framing = nil })
        }
    }

    // MARK: Cover

    private var coverSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cover").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary).accessibilityAddTraits(.isHeader)
            HStack(spacing: 10) {
                button("photo.on.rectangle", cover == nil ? "Choose photo" : "Change photo", id: "org-cover-choose") { step = .library }
                if CameraPicker.isAvailable { button("camera", "Take Photo", id: "org-cover-camera") { step = .camera } }
            }
            if cover != nil { button("trash", "Remove", id: "org-cover-remove") { remove() } }
        }
    }

    private func button(_ symbol: String, _ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text)
                .padding(.horizontal, 14).frame(minHeight: 44).background(Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }

    // MARK: Colour

    private var colourSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Colour").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary).accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 44), spacing: 10), count: 4), spacing: 10) {
                ForEach(0..<8, id: \.self) { tone in
                    let on = current == tone
                    Button { pick(tone) } label: {
                        ZStack {
                            Circle().fill(Theme.avatar(tone))
                            if on { Image(systemName: "checkmark").font(.system(size: 17, weight: .bold)).foregroundStyle(Color(red: 0.075, green: 0.106, blue: 0.09)) }
                        }
                        .frame(width: 48, height: 48).frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Self.names[tone]).accessibilityAddTraits(on ? [.isSelected] : []).accessibilityIdentifier("org-colour-\(tone)")
                }
            }
            if chosen != nil {
                Button("Use the default colour") { reset() }.font(Theme.secondary).frame(minHeight: 44).accessibilityIdentifier("org-colour-default")
            }
        }
    }

    // MARK: Actions

    private func pick(_ tone: Int) {
        guard tone != current || chosen == nil else { return }
        Task { busy = true; if await !setTone(tone) { problem = "The colour could not be saved." }; busy = false }
    }

    private func reset() {
        Task { busy = true; if await !setTone(nil) { problem = "The colour could not be saved." }; busy = false }
    }

    private func save(_ crop: BackgroundCrop) {
        guard let still = BackgroundProcessing.jpeg(crop.image) else { problem = "That picture could not be prepared."; return }
        problem = nil
        Task { busy = true; if await !setCover(still) { problem = "The cover could not be saved. Check your connection and try again." }; busy = false }
    }

    private func remove() {
        problem = nil
        Task { busy = true; if await !removeCover() { problem = "The cover could not be removed." }; busy = false }
    }
}
