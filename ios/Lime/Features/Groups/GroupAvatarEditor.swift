import SwiftUI
import UIKit

/// How a group's picture is chosen: an emoji or a photo.
enum GroupAvatarMode: String, CaseIterable, Identifiable {
    case emoji = "Emoji", photo = "Photo"
    var id: String { rawValue }
}

/// The group's picture picker, used when a group is made and when its details are edited: the picture so far, a switch between
/// Emoji and Photo, the emoji field, or Choose / Take / Remove for a photo (a circular crop, as for the profile photo).
struct GroupAvatarEditor: View {
    @Binding var mode: GroupAvatarMode
    @Binding var emoji: String
    /// The chosen, already cropped picture (nil: none).
    @Binding var photo: UIImage?
    /// Shown in the circle when there is neither an emoji nor a photo.
    let fallback: String
    @State private var step: Step?
    @State private var cropping: UIImage?

    private enum Step: String, Identifiable { case library, camera; var id: String { rawValue } }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.surface).frame(width: 96, height: 96)
                if mode == .photo, let photo {
                    Image(uiImage: photo).resizable().scaledToFill().frame(width: 96, height: 96).clipShape(Circle())
                } else if mode == .emoji, !emoji.isEmpty {
                    Text(emoji).font(.system(size: 48))
                } else {
                    Text(fallback).font(.system(size: 34, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                }
            }
            .accessibilityHidden(true)
            Picker("Picture", selection: $mode) {
                ForEach(GroupAvatarMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
            .accessibilityIdentifier("group-avatar-mode")
            switch mode {
            case .emoji:
                TextField("Emoji (optional)", text: $emoji)
                    .multilineTextAlignment(.center).font(Theme.body).selectionTint()
                    .frame(maxWidth: 200).padding(.vertical, 10)
                    .background(Theme.surface, in: Capsule())
                    .onChange(of: emoji) { _, value in if let first = value.first(where: { $0.isEmojiCharacter }) { emoji = String(first) } else if !value.isEmpty { emoji = "" } }
                    .accessibilityIdentifier("group-emoji-field")
            case .photo:
                HStack(spacing: 10) {
                    pill("photo.on.rectangle", "Choose", id: "group-photo-library") { step = .library }
                    if CameraPicker.isAvailable { pill("camera", "Take Photo", id: "group-photo-camera") { step = .camera } }
                    if photo != nil { pill("trash", "Remove", id: "group-photo-remove") { photo = nil } }
                }
            }
        }
        .fullScreenCover(item: $step) { step in
            switch step {
            case .library: LibraryPicker(onPick: { picked in self.step = nil; cropping = picked }, onCancel: { self.step = nil }).ignoresSafeArea()
            case .camera: CameraPicker(onPick: { picked in self.step = nil; cropping = picked }, onCancel: { self.step = nil }).ignoresSafeArea()
            }
        }
        .fullScreenCover(item: Binding(get: { cropping.map(CropItem.init) }, set: { if $0 == nil { cropping = nil } })) { item in
            PhotoCropScreen(image: item.image, onSave: { cropped in cropping = nil; photo = cropped }, onCancel: { cropping = nil })
        }
    }

    private struct CropItem: Identifiable {
        let image: UIImage
        var id: ObjectIdentifier { ObjectIdentifier(image) }
    }

    private func pill(_ symbol: String, _ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.text)
                .padding(.horizontal, 14).frame(minHeight: 40).background(Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

extension Character {
    /// A character drawn as an emoji (not a plain digit or letter).
    var isEmojiCharacter: Bool { unicodeScalars.first.map { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x238C) } ?? false }
}

/// Group details → the picture: change it to another emoji or photo, or take it off. Saved with Save.
struct GroupAvatarSheet: View {
    let conversationID: Conversation.ID
    let currentEmoji: String?
    let hasPhoto: Bool
    var finish: (_ changed: Bool) -> Void
    @Environment(ConversationStore.self) private var store
    @State private var mode: GroupAvatarMode = .emoji
    @State private var emoji = ""
    @State private var photo: UIImage?
    @State private var saving = false

    private var canSave: Bool {
        if saving { return false }
        switch mode {
        case .emoji: return emoji != (currentEmoji ?? "") || hasPhoto
        case .photo: return photo != nil
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button("Cancel") { finish(false) }.foregroundStyle(Theme.text).accessibilityIdentifier("group-avatar-cancel")
                Spacer()
                Text("Group picture").font(Theme.title).foregroundStyle(Theme.text)
                Spacer()
                Button("Save") { save() }.font(Theme.title).foregroundStyle(Theme.text).disabled(!canSave)
                    .accessibilityIdentifier("group-avatar-save")
            }
            GroupAvatarEditor(mode: $mode, emoji: $emoji, photo: $photo, fallback: "👥")
            if hasPhoto || currentEmoji != nil {
                Button(role: .destructive) { remove() } label: { Text("Remove picture").font(Theme.body) }
                    .disabled(saving).accessibilityIdentifier("group-avatar-remove")
            }
            Text("A group photo is encrypted: the server never sees it. Only the group's members can.").font(Theme.caption)
                .foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).padding(.horizontal, 12)
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Theme.canvas.ignoresSafeArea())
        .presentationDetents([.large])
        .onAppear {
            emoji = currentEmoji ?? ""
            mode = hasPhoto ? .photo : .emoji
            photo = AvatarCache.shared.image(for: conversationID)
        }
    }

    private func save() {
        saving = true
        Task {
            var ok = true
            switch mode {
            case .emoji: ok = await store.setGroupEmoji(emoji.isEmpty ? nil : emoji, in: conversationID)
            case .photo:
                if let photo, let jpeg = PhotoProcessing.jpeg(photo) { ok = await store.setGroupPhoto(jpeg, in: conversationID) }
            }
            saving = false
            if ok { finish(true) }
        }
    }

    private func remove() {
        saving = true
        Task {
            let ok = await store.removeGroupPhoto(in: conversationID)
            saving = false
            if ok { finish(true) }
        }
    }
}
