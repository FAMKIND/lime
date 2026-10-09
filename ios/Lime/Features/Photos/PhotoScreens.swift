import PhotosUI
import SwiftUI
import UIKit

// MARK: Pickers (no photo-library permission: the system picker runs out of process)

/// The system photo picker: Lime receives only the one picture chosen.
struct LibraryPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private nonisolated(unsafe) let onPick: (UIImage) -> Void
        private nonisolated(unsafe) let onCancel: () -> Void
        init(onPick: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
                DispatchQueue.main.async { self.onCancel() }
                return
            }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                let image = object as? UIImage
                DispatchQueue.main.async { if let image { self.onPick(image) } else { self.onCancel() } }
            }
        }
    }
}

/// The camera, for a new profile photo.
struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    let onCancel: () -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private nonisolated(unsafe) let onPick: (UIImage) -> Void
        private nonisolated(unsafe) let onCancel: () -> Void
        init(onPick: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        nonisolated func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            DispatchQueue.main.async { if let image { self.onPick(image) } else { self.onCancel() } }
        }

        nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { DispatchQueue.main.async { self.onCancel() } }
    }
}

// MARK: Crop

/// A circular crop: drag to move, pinch to zoom, then Save. The result is a 512 px square (shown round everywhere).
struct PhotoCropScreen: View {
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
            let viewport = min(geometry.size.width - 32, 360)
            VStack(spacing: 0) {
                SheetHeader(title: "Move and Scale", leading: .close { onCancel() }) {
                    Button { onSave(rendered(viewport: viewport)) } label: {
                        Text("Save").font(Theme.title).foregroundStyle(Theme.accentInk)
                            .padding(.horizontal, 18).frame(minHeight: 44).background(Theme.accent, in: Capsule())
                    }
                    .accessibilityIdentifier("photo-crop-save")
                }
                Spacer(minLength: 0)
                ZStack {
                    cropped(viewport: viewport)
                        .frame(width: viewport, height: viewport)
                        .clipped()
                    // The circle that will remain: everything outside it is dimmed.
                    Rectangle().fill(Color.black.opacity(0.55)).frame(width: viewport, height: viewport)
                        .mask(CircleHole().fill(style: FillStyle(eoFill: true)))
                        .allowsHitTesting(false)
                    Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5).frame(width: viewport, height: viewport).allowsHitTesting(false)
                }
                .frame(width: viewport, height: viewport)
                .contentShape(Rectangle())
                .gesture(SimultaneousGesture(
                    DragGesture().onChanged { drag = $0.translation }.onEnded { value in
                        offset = clamped(CGSize(width: offset.width + value.translation.width, height: offset.height + value.translation.height), viewport: viewport)
                        drag = .zero
                    },
                    MagnifyGesture().onChanged { gestureScale = $0.magnification }.onEnded { value in
                        scale = min(max(scale * value.magnification, 1), 6)
                        gestureScale = 1
                        offset = clamped(offset, viewport: viewport)
                    }
                ))
                .accessibilityIdentifier("photo-crop-area")
                Text("Drag and pinch to choose how your photo is cropped.").font(Theme.secondary).foregroundStyle(Theme.textSecondary).padding(.top, 20)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas.ignoresSafeArea())
    }

    private func clamped(_ value: CGSize, viewport: CGFloat) -> CGSize {
        let limit = PhotoProcessing.limit(imageSize: image.size, viewport: viewport, scale: liveScale)
        return CGSize(width: min(max(value.width, -limit.width), limit.width), height: min(max(value.height, -limit.height), limit.height))
    }

    private func liveOffset(viewport: CGFloat) -> CGSize {
        clamped(CGSize(width: offset.width + drag.width, height: offset.height + drag.height), viewport: viewport)
    }

    private func cropped(viewport: CGFloat) -> some View {
        let cover = max(viewport / image.size.width, viewport / image.size.height) * liveScale
        let shift = liveOffset(viewport: viewport)
        return Image(uiImage: image).resizable()
            .frame(width: image.size.width * cover, height: image.size.height * cover)
            .offset(shift)
    }

    private func rendered(viewport: CGFloat) -> UIImage {
        PhotoProcessing.crop(image, viewport: viewport, scale: liveScale, offset: liveOffset(viewport: viewport))
    }
}

/// A square with a circular hole (even-odd), to dim the area outside the crop circle.
private struct CircleHole: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addEllipse(in: rect)
        return path
    }
}

// MARK: Profile → Photo

/// Profile → Photo: take or choose a picture, remove it, and choose who can see it.
struct ProfilePhotoScreen: View {
    @Environment(AccountSession.self) private var session
    @Environment(ConversationStore.self) private var store
    @State private var visibility: ConversationStore.PhotoVisibility = .everyone
    @State private var hasPhoto = false
    @State private var step: Step?
    @State private var cropping: UIImage?
    @State private var busy = false
    @State private var problem: String?

    private enum Step: String, Identifiable { case library, camera; var id: String { rawValue } }

    var body: some View {
        SettingsPage(title: "Photo") {
            AvatarView(person: session.mePerson, size: 140).padding(.top, 8)
                .accessibilityHidden(true)
            SettingsCard {
                row("photo.on.rectangle", "Choose from Library", id: "photo-library") { step = .library }
                if CameraPicker.isAvailable {
                    Divider().overlay(Theme.hairline).padding(.leading, 60)
                    row("camera", "Take Photo", id: "photo-camera") { step = .camera }
                }
                if hasPhoto {
                    Divider().overlay(Theme.hairline).padding(.leading, 60)
                    row("trash", "Remove Photo", id: "photo-remove", destructive: true) { remove() }
                }
            }
            if busy { ProgressView().padding(.top, 4).accessibilityIdentifier("photo-busy") }
            SettingsFootnote(text: problem ?? "Your photo is cropped to a circle and shrunk on this iPhone. Location and camera details are never uploaded.")
            SettingsCard {
                choice(.everyone, "Everyone on Lime", detail: "Any signed-in teacher who sees your profile can see your photo. Lime's servers keep a copy of the picture.", id: "photo-vis-everyone")
                Divider().overlay(Theme.hairline).padding(.leading, 18)
                choice(.contacts, "Only my contacts (encrypted)", detail: "Teachers you message see it. It's encrypted, the public copy is deleted, and everyone else sees your initials.", id: "photo-vis-contacts")
            }
            SettingsFootnote(text: "Who can see my photo")
        }
        .task {
            let mine = await store.myPhoto()
            visibility = mine.visibility
            hasPhoto = mine.jpeg != nil
        }
        .fullScreenCover(item: $step) { step in
            switch step {
            case .library: LibraryPicker(onPick: { picked in self.step = nil; cropping = picked }, onCancel: { self.step = nil }).ignoresSafeArea()
            case .camera: CameraPicker(onPick: { picked in self.step = nil; cropping = picked }, onCancel: { self.step = nil }).ignoresSafeArea()
            }
        }
        .fullScreenCover(item: Binding(get: { cropping.map(CropItem.init) }, set: { if $0 == nil { cropping = nil } })) { item in
            PhotoCropScreen(image: item.image, onSave: { cropped in cropping = nil; save(cropped) }, onCancel: { cropping = nil })
        }
        #if DEBUG
        .task { if store.demoSettingsRoute.contains("crop"), cropping == nil { cropping = Self.demoPicture } }
        #endif
    }

    private struct CropItem: Identifiable {
        let image: UIImage
        var id: ObjectIdentifier { ObjectIdentifier(image) }
    }

    #if DEBUG
    /// A made-up picture for screenshots and UI tests (the simulator has no camera and its library is empty).
    static var demoPicture: UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 800, height: 1000)).image { context in
            UIColor(red: 0.55, green: 0.8, blue: 0.4, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 1000))
            UIColor(red: 0.95, green: 0.8, blue: 0.3, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 200, y: 250, width: 400, height: 400))
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 300, y: 380, width: 60, height: 60))
            context.cgContext.fillEllipse(in: CGRect(x: 440, y: 380, width: 60, height: 60))
        }
    }
    #endif

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
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityIdentifier(id)
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
            .padding(.horizontal, 18).padding(.vertical, 14).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(visibility == value ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(id)
    }

    private func save(_ cropped: UIImage) {
        guard let data = PhotoProcessing.jpeg(cropped) else { problem = "That photo could not be prepared."; return }
        busy = true
        problem = nil
        Task {
            let ok = await store.setMyPhoto(data)
            busy = false
            if ok { hasPhoto = true } else { problem = "The photo could not be saved. Check your connection and try again." }
        }
    }

    private func remove() {
        busy = true
        problem = nil
        Task {
            let ok = await store.removeMyPhoto()
            busy = false
            if ok { hasPhoto = false } else { problem = "The photo could not be removed. Check your connection and try again." }
        }
    }

    private func choose(_ value: ConversationStore.PhotoVisibility) {
        guard value != visibility else { return }
        let previous = visibility
        visibility = value
        busy = true
        problem = nil
        Task {
            let ok = await store.setPhotoVisibility(value)
            busy = false
            if !ok { visibility = previous; problem = "That couldn't be changed. Check your connection and try again." }
        }
    }
}
