import SwiftUI

/// Edit profile → Background (LIME-217): a wide picture behind your name on your profile. Choose from Photos, move and scale it into a wide frame, remove
/// it, and choose who can see it (contacts only until you choose).
struct BackgroundScreen: View {
    @Environment(ConversationStore.self) private var store
    @State private var current: UIImage?
    @State private var visibility: ConversationStore.PhotoVisibility = .contacts
    @State private var picking = false
    @State private var cropping: UIImage?
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        SettingsPage(title: "Background") {
            Group {
                if let current {
                    Image(uiImage: current).resizable().scaledToFill()
                } else {
                    Theme.surface.overlay { Image(systemName: "photo").font(.system(size: 28)).foregroundStyle(Theme.textSecondary) }
                }
            }
            // The preview is this phone's hero shape: what the photo will fill (LIME-217c).
            .aspectRatio(HeroShape.aspect(screenWidth: UIScreen.main.bounds.width, screenHeight: UIScreen.main.bounds.height), contentMode: .fit)
            .frame(maxHeight: 300)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.top, 8)
            .accessibilityLabel(current == nil ? "No background" : "Your background").accessibilityIdentifier("background-preview")
            SettingsCard {
                row("photo.on.rectangle", current == nil ? "Choose from Library" : "Change Background", id: "background-choose") { choose() }
                if current != nil {
                    Divider().overlay(Theme.hairline).padding(.leading, 60)
                    row("trash", "Remove Background", id: "background-remove", destructive: true) { remove() }
                }
            }
            if busy { ProgressView().padding(.top, 4).accessibilityIdentifier("background-busy") }
            SettingsFootnote(text: problem ?? "It fills the top of your profile and fades out behind the tabs. It's shrunk on this iPhone, and location and camera details are never uploaded.")
            SettingsCard {
                visibilityChoice(.everyone, "Everyone on lime", detail: "Any signed-in teacher who sees your profile can see it. lime's servers keep a copy of the picture.", id: "background-vis-everyone")
                Divider().overlay(Theme.hairline).padding(.leading, 18)
                visibilityChoice(.contacts, "Only my contacts (encrypted)", detail: "Teachers you message see it. It's encrypted; everyone else sees none.", id: "background-vis-contacts")
            }
            SettingsFootnote(text: "Who can see my background")
        }
        .task {
            let mine = await store.myExtra(.background)
            current = mine.data.flatMap(UIImage.init(data:))
            visibility = mine.visibility
        }
        .fullScreenCover(isPresented: $picking) {
            LibraryPicker(onPick: { picked in picking = false; cropping = picked }, onCancel: { picking = false }).ignoresSafeArea()
        }
        .fullScreenCover(item: Binding(get: { cropping.map(CropItem.init) }, set: { if $0 == nil { cropping = nil } })) { item in
            BackgroundCropScreen(image: item.image, onSave: { cropped in cropping = nil; save(cropped) }, onCancel: { cropping = nil })
        }
    }

    private struct CropItem: Identifiable {
        let image: UIImage
        var id: ObjectIdentifier { ObjectIdentifier(image) }
    }

    private func choose() {
        #if DEBUG
        if store.isDemo { cropping = ProfilePhotoScreen.demoPicture; return }
        #endif
        picking = true
    }

    private func save(_ cropped: UIImage) {
        guard let data = BackgroundProcessing.jpeg(cropped) else { problem = "That picture could not be prepared."; return }
        busy = true; problem = nil
        Task {
            let ok = await store.setMyExtra(.background, data)
            busy = false
            if ok { current = UIImage(data: data) } else { problem = "The background could not be saved. Check your connection and try again." }
        }
    }

    private func remove() {
        busy = true; problem = nil
        Task {
            let ok = await store.setMyExtra(.background, nil)
            busy = false
            if ok { current = nil } else { problem = "The background could not be removed. Check your connection and try again." }
        }
    }

    private func row(_ symbol: String, _ title: String, id: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 20)).frame(width: 28)
                Text(title).font(Theme.body)
                Spacer()
            }
            .foregroundStyle(destructive ? Color.red : Theme.text)
            .padding(.horizontal, 18).frame(minHeight: 58).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(busy).accessibilityIdentifier(id)
    }

    private func visibilityChoice(_ value: ConversationStore.PhotoVisibility, _ title: String, detail: String, id: String) -> some View {
        Button {
            guard value != visibility else { return }
            let previous = visibility
            visibility = value
            busy = true; problem = nil
            Task {
                let ok = await store.setExtraVisibility(.background, value)
                busy = false
                if !ok { visibility = previous; problem = "That couldn't be changed. Check your connection and try again." }
            }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Theme.body).foregroundStyle(Theme.text)
                    Text(detail).font(Theme.secondary).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: visibility == value ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(visibility == value ? Theme.text : Theme.textSecondary)
            }
            .padding(.horizontal, 18).padding(.vertical, 14).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(busy)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(visibility == value ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(id)
    }
}

/// Move and scale a picture into the wide frame the background will have.
struct BackgroundCropScreen: View {
    let image: UIImage
    let onSave: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var scale: CGFloat = 1
    @State private var gestureScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var drag: CGSize = .zero

    private var liveScale: CGFloat { min(max(scale * gestureScale, 1), 6) }

    var body: some View {
        GeometryReader { geometry in
            let viewport = CGSize(width: geometry.size.width - 32, height: (geometry.size.width - 32) / BackgroundProcessing.ratio)
            VStack(spacing: 0) {
                SheetHeader(title: "Move and Scale", leading: .close { onCancel() }) {
                    Button { onSave(BackgroundProcessing.crop(image, viewport: viewport, scale: liveScale, offset: liveOffset(viewport))) } label: {
                        Text("Save").font(Theme.title).foregroundStyle(Theme.accentInk)
                            .padding(.horizontal, 18).frame(minHeight: 44).background(Theme.accent, in: Capsule())
                    }
                    .accessibilityIdentifier("background-crop-save")
                }
                Spacer(minLength: 0)
                preview(viewport)
                    .frame(width: viewport.width, height: viewport.height).clipped()
                    // This phone's hero shape sits over the 4:5 frame: what is outside it may be trimmed on this phone (other phones' heroes differ a little).
                    .overlay {
                        let hole = heroWindow(in: viewport)
                        ZStack {
                            Rectangle().fill(Color.black.opacity(0.45)).mask(HoleShape(hole: hole).fill(style: FillStyle(eoFill: true))).allowsHitTesting(false)
                            Rectangle().stroke(Color.white.opacity(0.9), lineWidth: 1.5).frame(width: hole.width, height: hole.height).position(x: hole.midX, y: hole.midY).allowsHitTesting(false)
                        }
                    }
                    .overlay(Rectangle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                    .contentShape(Rectangle())
                    .gesture(SimultaneousGesture(
                        DragGesture().onChanged { drag = $0.translation }.onEnded { value in
                            offset = clamped(CGSize(width: offset.width + value.translation.width, height: offset.height + value.translation.height), viewport)
                            drag = .zero
                        },
                        MagnifyGesture().onChanged { gestureScale = $0.magnification }.onEnded { value in
                            scale = min(max(scale * value.magnification, 1), 6)
                            gestureScale = 1
                            offset = clamped(offset, viewport)
                        }
                    ))
                    .accessibilityLabel("Background frame").accessibilityHint("Drag and pinch to choose how it is cropped")
                    .accessibilityIdentifier("background-crop-area")
                Text("Drag and pinch. The bright frame is the top of your profile on this phone.").font(Theme.secondary).foregroundStyle(Theme.textSecondary).padding(.top, 20)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas.ignoresSafeArea())
    }

    /// The part of the frame this phone's hero shows: the full width, centred, as tall as the hero's shape says (never more than the frame).
    private func heroWindow(in viewport: CGSize) -> CGRect {
        let aspect = HeroShape.aspect(screenWidth: UIScreen.main.bounds.width, screenHeight: UIScreen.main.bounds.height)
        let height = min(viewport.height, viewport.width / aspect)
        return CGRect(x: 0, y: (viewport.height - height) / 2, width: viewport.width, height: height)
    }

    private func clamped(_ value: CGSize, _ viewport: CGSize) -> CGSize {
        let limit = BackgroundProcessing.limit(imageSize: image.size, viewport: viewport, scale: liveScale)
        return CGSize(width: min(max(value.width, -limit.width), limit.width), height: min(max(value.height, -limit.height), limit.height))
    }

    private func liveOffset(_ viewport: CGSize) -> CGSize { clamped(CGSize(width: offset.width + drag.width, height: offset.height + drag.height), viewport) }

    private func preview(_ viewport: CGSize) -> some View {
        let cover = max(viewport.width / image.size.width, viewport.height / image.size.height) * liveScale
        return Image(uiImage: image).resizable()
            .frame(width: image.size.width * cover, height: image.size.height * cover)
            .offset(liveOffset(viewport))
    }
}

/// A rectangle with a rectangular hole (even-odd), to dim the part of the frame outside the hero window.
private struct HoleShape: Shape {
    let hole: CGRect
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRect(hole)
        return path
    }
}
