import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// Plays a sound once so the person hears what they picked (the system-sound path, so the silent switch is respected).
@MainActor
final class SoundPreview {
    static let shared = SoundPreview()
    private var ids: [URL: SystemSoundID] = [:]
    private var player: AVAudioPlayer?

    func play(messageSound sound: NotificationSound) {
        switch sound {
        case .none: return
        case .systemDefault: AudioServicesPlaySystemSound(1007)
        case .limeChime: if let url = Bundle.main.url(forResource: "lime-chime", withExtension: "caf") { play(url) }
        case .custom(let id): play(CustomSounds.shared.fileURL(id))
        }
    }

    func play(_ url: URL) {
        if ids[url] == nil {
            var id: SystemSoundID = 0
            guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError else { return }
            ids[url] = id
        }
        if let id = ids[url] { AudioServicesPlaySystemSound(id) }
    }

    /// A section of a longer file (the trimmer's preview).
    func play(_ url: URL, from start: Double, for seconds: Double) {
        player?.stop()
        guard let next = try? AVAudioPlayer(contentsOf: url) else { return }
        player = next
        next.currentTime = start
        next.play()
        Task { try? await Task.sleep(for: .seconds(seconds)); if next.isPlaying { next.stop() } }
    }

    func stop() { player?.stop() }
}

/// Add your own message or call sound: pick an audio file, choose which part to keep (at most 2 s for a message, under 30 s for a call),
/// listen, name it, save. Lime converts it and keeps it on this phone.
struct AddSoundSheet: View {
    let kind: CustomSounds.Kind
    @Environment(\.dismiss) private var dismiss
    @Environment(NotificationCoordinator.self) private var notifications
    @State private var picking = false
    @State private var source: URL?
    @State private var total = 0.0
    @State private var start = 0.0
    @State private var length = 1.0
    @State private var name = ""
    @State private var problem: String?

    private var maxLength: Double { min(kind.maxSeconds, max(total - start, 0.1)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text(kind == .message ? "Your message sound" : "Your call sound").font(.system(.title3, design: .default, weight: .bold)).foregroundStyle(Theme.text).padding(.top, 16)
                    Text(kind == .message ? "Pick a short sound. Lime keeps up to 2 seconds of it." : "Pick a sound. Lime keeps up to 29 seconds of it.")
                        .font(Theme.secondary).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                    Button { picking = true } label: {
                        Text(source == nil ? "Choose a file…" : "Choose another file…").font(Theme.body.weight(.semibold)).foregroundStyle(Theme.accentInk)
                            .frame(maxWidth: .infinity, minHeight: 50).background(Theme.accent, in: Capsule())
                    }
                    .accessibilityIdentifier("sound-choose-file")
                    if source != nil {
                        SettingsCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack { Text("Start").font(Theme.body); Spacer(); Text(format(start)).font(Theme.body.monospacedDigit()).foregroundStyle(Theme.textSecondary) }
                                Slider(value: $start, in: 0...max(total - 0.1, 0.1)) { _ in clamp() }.accessibilityIdentifier("sound-start")
                                HStack { Text("Length").font(Theme.body); Spacer(); Text(format(length)).font(Theme.body.monospacedDigit()).foregroundStyle(Theme.textSecondary) }
                                Slider(value: $length, in: 0.1...max(maxLength, 0.2)).accessibilityIdentifier("sound-length")
                                Button { if let source { SoundPreview.shared.play(source, from: start, for: length) } } label: {
                                    Label("Preview", systemImage: "play.fill").font(Theme.body.weight(.semibold)).foregroundStyle(Theme.text)
                                }
                                .accessibilityIdentifier("sound-preview")
                            }
                            .padding(18)
                        }
                        SettingsCard {
                            TextField("Name", text: $name).font(Theme.body).padding(.horizontal, 18).frame(minHeight: 54).accessibilityIdentifier("sound-name")
                        }
                        Button { save() } label: {
                            Text("Save").font(Theme.body.weight(.semibold)).foregroundStyle(Theme.accentInk)
                                .frame(maxWidth: .infinity, minHeight: 50).background(Theme.accent, in: Capsule())
                        }
                        .accessibilityIdentifier("sound-save")
                    }
                    if let problem { Text(problem).font(Theme.secondary).foregroundStyle(Color.red).accessibilityIdentifier("sound-problem") }
                    Button("Cancel") { SoundPreview.shared.stop(); dismiss() }.foregroundStyle(Theme.text).accessibilityIdentifier("sound-cancel")
                }
                .padding(.horizontal, 20).padding(.bottom, 32)
            }
            .background(Theme.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationBackground(Theme.canvas)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio]) { result in
            guard case .success(let url) = result else { return }
            load(url)
        }
    }

    private func load(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // A copy in the temporary folder, so it can be read after the picker lets go.
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("pick-\(UUID().uuidString)-\(url.lastPathComponent)")
        do { try FileManager.default.copyItem(at: url, to: copy) } catch { problem = "That file could not be opened."; return }
        guard let seconds = CustomSounds.duration(of: copy), seconds > 0.05 else { problem = "That is not a sound Lime can use."; return }
        problem = nil
        source = copy
        total = seconds
        start = 0
        length = min(kind.maxSeconds, seconds)
        if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
    }

    private func clamp() { length = min(length, maxLength) }
    private func format(_ seconds: Double) -> String { String(format: "%.1f s", seconds) }

    private func save() {
        guard let source else { return }
        do {
            let item = try CustomSounds.shared.add(from: source, start: start, length: length, name: name, kind: kind)
            if kind == .message { notifications.settings.sound = .custom(item.id); SoundPreview.shared.play(messageSound: .custom(item.id)) }
            else { notifications.settings.callSound = .custom(item.id) }
            SoundPreview.shared.stop()
            dismiss()
        } catch CustomSounds.Failure.tooMany {
            problem = "You can keep up to \(CustomSounds.limit) of your own sounds. Delete one first."
        } catch {
            problem = "That sound could not be saved."
        }
    }
}
