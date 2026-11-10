import PhotosUI
import SwiftUI

/// LIME-277d: a chat's Appearance (from a person's or a group's ⋯): a live preview, the wallpaper, the colour of my bubbles and a text size for this chat; "Use for
/// all chats" and "Reset". Only I see it: it stays on this phone.
struct ChatAppearanceSheet: View {
    let chatID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ChatAppearanceScreen(chatID: chatID)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold).accessibilityIdentifier("chat-look-done") } }
        }
        .presentationDetents([.large])
    }
}

struct ChatAppearanceScreen: View {
    let chatID: String
    @Environment(\.colorScheme) private var scheme
    @State private var picked: PhotosPickerItem?
    @State private var problem: String?
    @State private var photoImage: UIImage?
    private var looks: ChatLooks { ChatLooks.shared }
    private var look: ChatLook { looks.look(for: chatID) }

    private func update(_ change: (inout ChatLook) -> Void) {
        var next = look
        change(&next)
        looks.set(next, for: chatID)
    }

    var body: some View {
        SettingsPage(title: "Chat appearance") {
            ChatLookPreview(look: look, photo: photoImage)
            wallpaperSection
            bubbleSection
            textSection
            Button("Use for all chats") { looks.useForAll(chatID) }
                .font(Theme.body).foregroundStyle(Theme.text).frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.surface, in: Capsule()).accessibilityIdentifier("chat-use-all")
            Button("Reset this chat") { looks.reset(chatID) }
                .font(Theme.body).foregroundStyle(Theme.text).frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.surface, in: Capsule()).accessibilityIdentifier("chat-reset")
            SettingsFootnote(text: "Only you see these. They stay on this iPhone and are never sent to the people in the chat.")
        }
        .task(id: "\(look.wallpaper.key)|\(looks.photoRevision)") { photoImage = look.wallpaper == .photo ? await looks.photo(chatID) : nil }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    looks.setPhoto(image, for: chatID); problem = nil
                } else { problem = "That picture could not be used." }
                picked = nil
            }
        }
    }

    // MARK: Wallpaper

    private var wallpaperSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Wallpaper")
            SettingsCard {
                let hasPhoto = look.wallpaper == .photo
                PhotosPicker(selection: $picked, matching: .images) {
                    SettingsRowLabel(symbol: "photo.on.rectangle", title: "Choose from Photos", showsDivider: hasPhoto)
                }
                .buttonStyle(.plain).accessibilityIdentifier("chat-photo-pick")
                if look.wallpaper == .photo {
                    Button { looks.removePhoto(chatID); update { $0.wallpaper = .none } } label: { SettingsRowLabel(symbol: "trash", title: "Remove the photo", showsDivider: false, destructive: true) }
                        .buttonStyle(.plain).accessibilityIdentifier("chat-photo-remove")
                }
            }
            if let problem { Text(problem).font(Theme.caption).foregroundStyle(Theme.textSecondary) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 80), spacing: 12), count: 3), spacing: 14) {
                thumb("Default", id: "default", wallpaper: .none)
                ForEach(AppThemeBackground.allCases) { kind in thumb(kind.title, id: kind.rawValue, wallpaper: .background(kind.rawValue)) }
                ForEach(ChatLook.presets, id: \.id) { preset in thumb(preset.name, id: preset.id, wallpaper: .preset(preset.id)) }
            }
        }
    }

    private func thumb(_ name: String, id: String, wallpaper: ChatLook.Wallpaper) -> some View {
        let on = look.wallpaper == wallpaper
        return Button { update { $0.wallpaper = wallpaper } } label: {
            VStack(spacing: 6) {
                WallpaperLayer(wallpaper: wallpaper)
                    .aspectRatio(0.62, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Theme.text : Theme.hairline, lineWidth: on ? 3 : 1))
                    .overlay(alignment: .bottomTrailing) {
                        if on { Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).symbolRenderingMode(.palette).foregroundStyle(Theme.canvas, Theme.text).padding(8) }
                    }
                Text(name).font(Theme.font(.caption, weight: on ? .semibold : .regular)).foregroundStyle(Theme.text).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name).accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityIdentifier("chat-wallpaper-\(id)")
    }

    // MARK: My bubbles

    private var bubbleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Your bubble colour")
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    Button { update { $0.bubbleTone = nil; $0.bubbleDeep = false } } label: {
                        HStack(spacing: 12) {
                            Circle().fill(Theme.ownBubble).frame(width: 36, height: 36).overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                            Text("Follow my accent").font(Theme.body).foregroundStyle(Theme.text)
                            Spacer()
                            if look.bubbleTone == nil { Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text) }
                        }
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Follow my accent").accessibilityAddTraits(look.bubbleTone == nil ? [.isSelected] : [])
                    .accessibilityIdentifier("chat-bubble-default")
                    // Each of the eight in two shades, as a pair: the deep one with light ink, the pastel one with dark ink.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 60), spacing: 10), count: 4), spacing: 12) {
                        ForEach(0..<8, id: \.self) { tone in
                            HStack(spacing: 6) {
                                swatch(tone, deep: true)
                                swatch(tone, deep: false)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private func swatch(_ tone: Int, deep: Bool) -> some View {
        let on = look.bubbleTone == tone && look.bubbleDeep == deep
        let colours = ChatLook.bubbleColours(tone: tone, deep: deep)
        return Button { update { $0.bubbleTone = tone; $0.bubbleDeep = deep } } label: {
            ZStack {
                Circle().fill(Color(colours.fill))
                if on { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Color(colours.ink)) }
            }
            .frame(width: 28, height: 28)
            .overlay(Circle().strokeBorder(on ? Theme.text : Theme.hairline, lineWidth: on ? 2.5 : 1).padding(on ? -3 : 0))
            .frame(minWidth: 30, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(LimeColours.name(tone)), \(deep ? "deep" : "light")").accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityIdentifier("chat-bubble-\(tone)-\(deep ? "deep" : "pastel")")
    }

    // MARK: Text size

    private var textSection: some View {
        let step = look.textStep
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Text size")
            SettingsCard {
                VStack(spacing: 10) {
                    Toggle(isOn: Binding(get: { step == nil }, set: { same in update { $0.textStep = same ? nil : TextPreferences.shared.step } })) {
                        Text("Same as everywhere").font(Theme.body).foregroundStyle(Theme.text)
                    }
                    .accessibilityIdentifier("chat-textsize-same")
                    HStack(spacing: 12) {
                        Text("A").font(Theme.font(.caption)).accessibilityHidden(true)
                        Slider(value: Binding(get: { Double(step ?? TextPreferences.shared.step) }, set: { v in update { $0.textStep = Int(v.rounded()) } }),
                               in: 0...Double(TextStep.all.count - 1), step: 1)
                            .tint(Theme.text).disabled(step == nil)
                            .accessibilityLabel("Text size in this chat").accessibilityValue(TextStep.all[step ?? TextPreferences.shared.step].name)
                            .accessibilityIdentifier("chat-textsize-slider")
                        Text("A").font(.system(size: 28)).accessibilityHidden(true)
                    }
                    .foregroundStyle(Theme.text).opacity(step == nil ? 0.45 : 1)
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary).accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The live preview: a mini chat with this look. Decorative.
struct ChatLookPreview: View {
    let look: ChatLook
    var photo: UIImage?
    @Environment(\.dynamicTypeSize) private var globalSize

    var body: some View {
        let own = look.ownBubble
        let size = look.textStep.map { TextStep.all[$0].size } ?? globalSize
        ZStack {
            WallpaperLayer(wallpaper: look.wallpaper, photo: photo)
            VStack(alignment: .leading, spacing: 10) {
                Text("Are you coming to the staff meeting?")
                    .font(Theme.font(.subheadline)).foregroundStyle(Theme.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.bubbleOther, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                HStack {
                    Spacer(minLength: 40)
                    Text("Yes! I'll bring the reading lists.")
                        .font(Theme.font(.subheadline)).foregroundStyle(own?.ink ?? Theme.ownBubbleInk)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(own?.fill ?? Theme.ownBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(16)
            .environment(\.dynamicTypeSize, size)
        }
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .accessibilityHidden(true)
        .accessibilityIdentifier("chat-look-preview")
    }
}
