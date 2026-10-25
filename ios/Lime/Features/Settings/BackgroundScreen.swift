import SwiftUI

/// Edit profile → Background (LIME-217): a wide picture behind your name on your profile. Choose from Photos, move and scale it into a wide frame, remove
/// it, and choose who can see it (contacts only until you choose).
struct BackgroundScreen: View {
    @Environment(ConversationStore.self) private var store
    @State private var current: UIImage?
    @State private var visibility: ConversationStore.PhotoVisibility = .contacts
    @State private var hasVideo = false
    @State private var picking = false
    @State private var trimming: PickedVideo?
    @State private var framing: Framing?
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        SettingsPage(title: "Background") {
            // The preview is this phone's hero shape: what the photo will fill (LIME-217c). A clear box sets the size and the picture is only drawn over it:
            // a `scaledToFill` image as the sized view would take its own (pixel) size and make the whole page wider than the screen (LIME-225b).
            Color.clear
                .aspectRatio(HeroShape.aspect(screenWidth: UIScreen.main.bounds.width, screenHeight: UIScreen.main.bounds.height), contentMode: .fit)
                .frame(maxHeight: 300)
                .overlay {
                    if let current {
                        Image(uiImage: current).resizable().scaledToFill()
                    } else {
                        Theme.surface.overlay { Image(systemName: "photo").font(.system(size: 28)).foregroundStyle(Theme.textSecondary) }
                    }
                }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.top, 8)
            .accessibilityLabel(current == nil ? "No background" : "Your background").accessibilityIdentifier("background-preview")
            SettingsCard {
                row("photo.on.rectangle", current == nil ? "Choose a Photo or Video" : "Change Background", id: "background-choose") { choose() }
                if hasVideo {
                    Divider().overlay(Theme.hairline).padding(.leading, 60)
                    row("video.slash", "Remove Video (keep the photo)", id: "background-remove-video", destructive: true) { removeVideo() }
                }
                if current != nil {
                    Divider().overlay(Theme.hairline).padding(.leading, 60)
                    row("trash", "Remove Background", id: "background-remove", destructive: true) { remove() }
                }
            }
            if busy { ProgressView().padding(.top, 4).accessibilityIdentifier("background-busy") }
            SettingsFootnote(text: problem ?? "It fills the top of your profile and fades out behind the tabs. A video plays silently on a loop (up to 10 seconds, no sound). It's shrunk on this iPhone, and location and camera details are never uploaded.")
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
            hasVideo = await store.myExtra(.backgroundVideo).data != nil
        }
        .fullScreenCover(isPresented: $picking) {
            MediaLibraryPicker(limit: 1, onPick: { images, videos in
                picking = false
                if let image = images.first { framing = Framing(image: image, video: nil) }
                else if let url = videos.first { Task { await received(video: url) } }
            }, onCancel: { picking = false }).ignoresSafeArea()
        }
        .sheet(item: $trimming) { picked in
            VideoTrimSheet(video: picked) { start in
                trimming = nil
                Task { await frame(picked.url, start: start) }
            } onCancel: { trimming = nil }
        }
        .fullScreenCover(item: $framing) { item in
            BackgroundCropScreen(image: item.image, onSave: { crop in framing = nil; save(crop, item) }, onCancel: { framing = nil })
        }
    }

    /// A photo (or a video's frame) being framed into the 4:5 crop; for a video, which file and where the clip starts.
    private struct Framing: Identifiable {
        let id = UUID()
        let image: UIImage
        let video: (url: URL, start: Double)?
    }

    private func choose() {
        #if DEBUG
        if store.isDemo {
            // UI tests: no system picker. A made-up clip goes through the whole video path; otherwise a made-up photo.
            if ProcessInfo.processInfo.arguments.contains("-lime-demo-pick-video") { Task { if let url = await DemoClip.url() { await received(video: url) } } }
            else { framing = Framing(image: ProfilePhotoScreen.demoPicture, video: nil) }
            return
        }
        #endif
        picking = true
    }

    /// A picked video: its length decides whether to ask where the 10 seconds start, then it is framed on its first frame.
    private func received(video url: URL) async {
        let duration = await BackgroundVideoProcessing.duration(of: url)
        guard duration > 0 else { problem = "That video could not be used."; return }
        if duration > BackgroundVideoProcessing.maxSeconds { trimming = PickedVideo(url: url, duration: duration) }
        else { await frame(url, start: 0) }
    }

    private func frame(_ url: URL, start: Double) async {
        guard let poster = await BackgroundVideoProcessing.frame(of: url, at: start) else { problem = "That video could not be used."; return }
        framing = Framing(image: poster, video: (url, start))
    }

    /// The framed photo is the background (and a video's still); for a video the clip is cut, framed and re-encoded the same way, then saved after the still.
    private func save(_ crop: BackgroundCrop, _ item: Framing) {
        guard let still = BackgroundProcessing.jpeg(crop.image) else { problem = "That picture could not be prepared."; return }
        busy = true; problem = nil
        Task {
            var clip: Data?
            if let video = item.video {
                do { clip = try await BackgroundVideoProcessing.export(video.url, start: video.start, crop: crop) }
                catch { busy = false; problem = "That video could not be prepared. Try a shorter one."; return }
            }
            let ok = await store.setMyExtra(.background, still)
            var okVideo = true
            if ok, let clip { okVideo = await store.setMyExtra(.backgroundVideo, clip) }
            else if ok, hasVideo { okVideo = await store.setMyExtra(.backgroundVideo, nil) }   // a new photo replaces an old video
            busy = false
            if ok { current = UIImage(data: still); hasVideo = clip != nil && okVideo }
            if !ok || !okVideo { problem = "The background could not be saved. Check your connection and try again." }
        }
    }

    private func removeVideo() {
        busy = true; problem = nil
        Task {
            let ok = await store.setMyExtra(.backgroundVideo, nil)
            busy = false
            if ok { hasVideo = false } else { problem = "The video could not be removed. Check your connection and try again." }
        }
    }

    private func remove() {
        busy = true; problem = nil
        Task {
            let ok = await store.setMyExtra(.background, nil)
            busy = false
            if ok { current = nil; hasVideo = false } else { problem = "The background could not be removed. Check your connection and try again." }
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
/// What the framing screen made: the 4:5 picture, and the geometry behind it (so a video can be framed the same way).
struct BackgroundCrop {
    let image: UIImage
    let scale: CGFloat
    let offset: CGSize
    let viewport: CGSize
}

/// A video picked for a background, longer than 10 seconds: the person chooses where the 10 seconds start.
struct PickedVideo: Identifiable {
    let url: URL
    let duration: Double
    var id: URL { url }
}

struct BackgroundCropScreen: View {
    let image: UIImage
    let onSave: (BackgroundCrop) -> Void
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
                    Button { onSave(BackgroundCrop(image: BackgroundProcessing.crop(image, viewport: viewport, scale: liveScale, offset: liveOffset(viewport)), scale: liveScale, offset: liveOffset(viewport), viewport: viewport)) } label: {
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

/// Where do the 10 seconds start? A slider over the video's length, with the frame it starts on.
struct VideoTrimSheet: View {
    let video: PickedVideo
    let onNext: (Double) -> Void
    let onCancel: () -> Void
    @State private var start = 0.0
    @State private var poster: UIImage?

    var body: some View {
        VStack(spacing: 18) {
            Text("Choose 10 seconds").font(Theme.title).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader).padding(.top, 20)
            Group {
                if let poster { Image(uiImage: poster).resizable().scaledToFit() } else { Theme.surface }
            }
            .frame(maxHeight: 260).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)).accessibilityHidden(true)
            let span = max(0.1, video.duration - BackgroundVideoProcessing.maxSeconds)
            Slider(value: $start, in: 0...span).accessibilityLabel("Start of the 10 seconds").accessibilityValue("\(Int(start)) seconds in")
                .accessibilityIdentifier("trim-slider").padding(.horizontal, 24)
            Text("From \(clock(start)) to \(clock(start + BackgroundVideoProcessing.maxSeconds)) of \(clock(video.duration))").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 12) {
                Button { onCancel() } label: { Text("Cancel").font(Theme.title).foregroundStyle(Theme.text).frame(maxWidth: .infinity, minHeight: 50).background(Theme.surface, in: Capsule()) }
                Button { onNext(start) } label: { Text("Next").font(Theme.title).foregroundStyle(Theme.accentInk).frame(maxWidth: .infinity, minHeight: 50).background(Theme.accent, in: Capsule()) }
                    .accessibilityIdentifier("trim-next")
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.canvas.ignoresSafeArea())
        .presentationDetents([.medium])
        .task(id: Int(start)) { poster = await BackgroundVideoProcessing.frame(of: video.url, at: start) }
    }

    private func clock(_ seconds: Double) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
}
