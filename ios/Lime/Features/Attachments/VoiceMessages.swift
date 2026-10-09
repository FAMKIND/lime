import AVFoundation
import SwiftUI

/// What a finished recording is: the AAC file, how long it ran, and its loudness over time (64 bars, one byte each).
struct VoiceNote: Equatable {
    let bytes: Data
    let durationMs: Int
    let waveform: [UInt8]
}

/// Records a voice message: mono AAC at about 24 kbps (a minute is roughly 180 KB). Hold to record; the caller decides
/// whether it is sent, cancelled or locked hands-free.
@MainActor
@Observable
final class VoiceRecorder {
    enum Phase: Equatable { case idle, recording, locked }

    private(set) var phase: Phase = .idle
    private(set) var elapsed: TimeInterval = 0
    /// Loudness samples while recording, 0 to 1, newest last.
    private(set) var levels: [Float] = []
    /// Debug demo and UI tests: no microphone, a made-up note.
    var simulated = false
    /// The longest a voice message can be (it keeps the file small).
    static let maxSeconds: TimeInterval = 15 * 60
    static let minSeconds: TimeInterval = 0.6

    private var recorder: AVAudioRecorder?
    private var url: URL?
    private var ticker: Task<Void, Never>?
    private var raw: [Float] = []

    var isRecording: Bool { phase != .idle }

    /// Starts recording. `false` when the microphone is not allowed.
    func start() async -> Bool {
        guard phase == .idle else { return true }
        if !simulated {
            let allowed = await AVAudioApplication.requestRecordPermission()
            guard allowed else { return false }
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try session.setActive(true)
            } catch { return false }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("lime-voice-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 22_050, AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 24_000, AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            guard let recorder = try? AVAudioRecorder(url: file, settings: settings) else { return false }
            recorder.isMeteringEnabled = true
            guard recorder.record() else { return false }
            self.recorder = recorder
            url = file
        }
        phase = .recording
        elapsed = 0
        levels = []
        raw = []
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                self?.tick()
            }
        }
        return true
    }

    private func tick() {
        guard phase != .idle else { return }
        if simulated {
            elapsed += 0.05
            let level = Float(0.35 + 0.35 * abs(sin(elapsed * 6)))
            raw.append(level)
            levels.append(level)
        } else if let recorder {
            recorder.updateMeters()
            elapsed = recorder.currentTime
            let level = max(0, min(1, (recorder.averagePower(forChannel: 0) + 50) / 50))
            raw.append(level)
            levels.append(level)
        }
        if levels.count > 60 { levels.removeFirst(levels.count - 60) }
        if elapsed >= Self.maxSeconds { /* the caller finishes on its next look */ }
    }

    /// Hands-free: recording goes on after the finger is lifted.
    func lock() { if phase == .recording { phase = .locked } }

    /// Stops and returns the note (`nil` if it was too short to mean anything).
    func finish() -> VoiceNote? {
        guard phase != .idle else { return nil }
        let duration = elapsed
        let waveform = Self.bars(raw)
        let file = url
        end()
        guard duration >= Self.minSeconds else { discard(file); return nil }
        if simulated { return VoiceNote(bytes: Data(count: 4_000), durationMs: Int(duration * 1000), waveform: waveform) }
        guard let file, let data = try? Data(contentsOf: file), !data.isEmpty else { return nil }
        discard(file)
        return VoiceNote(bytes: data, durationMs: Int(duration * 1000), waveform: waveform)
    }

    func cancel() {
        let file = url
        end()
        discard(file)
    }

    private func end() {
        ticker?.cancel()
        ticker = nil
        recorder?.stop()
        recorder = nil
        url = nil
        phase = .idle
        if !simulated { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    private func discard(_ file: URL?) {
        if let file { try? FileManager.default.removeItem(at: file) }
    }

    /// 64 bars from the loudness samples (the loudest in each stretch), scaled to 0...255.
    static func bars(_ samples: [Float], count: Int = 64) -> [UInt8] {
        guard !samples.isEmpty else { return [UInt8](repeating: 8, count: count) }
        return (0..<count).map { index in
            let start = index * samples.count / count
            let end = max(start + 1, (index + 1) * samples.count / count)
            let loudest = samples[start..<min(end, samples.count)].max() ?? 0
            return UInt8(max(8, min(255, loudest * 255)))
        }
    }
}

/// Plays voice messages one at a time, with a speed of 1×, 1.5× or 2×, and goes on to the next voice message of the chat.
@MainActor
@Observable
final class VoicePlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = VoicePlayer()
    private(set) var currentID: String?
    private(set) var isPlaying = false
    private(set) var progress: Double = 0
    private(set) var failed = false
    private(set) var rate: Float = 1
    /// Debug demo: no sound, only the progress.
    var simulated = false

    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?
    private var simulatedDuration: TimeInterval = 0
    private var simulatedClock: TimeInterval = 0
    /// Where the next voice message comes from, and its bytes.
    private var next: ((String) -> AttachmentItem?)?
    private var load: ((AttachmentItem) async -> Data?)?

    static let speeds: [Float] = [1, 1.5, 2]

    func isCurrent(_ id: String) -> Bool { currentID == id }

    /// Plays or pauses a message; on the end, `after` names the next one to play.
    func toggle(_ item: AttachmentItem, after: @escaping (String) -> AttachmentItem?, data: @escaping (AttachmentItem) async -> Data?) async {
        next = after
        load = data
        if currentID == item.id {
            if isPlaying { pause() } else { resume() }
            return
        }
        await play(item)
    }

    private func play(_ item: AttachmentItem) async {
        stop()
        failed = false
        currentID = item.id
        progress = 0
        guard let data = await load?(item) else { failed = true; currentID = nil; return }
        guard currentID == item.id else { return }
        if simulated {
            simulatedDuration = Double(item.durationMs ?? 3000) / 1000
            simulatedClock = 0
            isPlaying = true
            startTicker()
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            let player = try AVAudioPlayer(data: data)
            player.enableRate = true
            player.rate = rate
            player.delegate = self
            guard player.play() else { throw CocoaError(.fileReadUnknown) }
            self.player = player
            isPlaying = true
            startTicker()
        } catch {
            failed = true
            currentID = nil
        }
    }

    private func pause() {
        player?.pause()
        isPlaying = false
    }

    private func resume() {
        if simulated { isPlaying = true; return }
        isPlaying = player?.play() ?? false
    }

    /// 1× to 1.5× to 2× and round again; takes effect at once.
    func cycleRate() {
        let index = Self.speeds.firstIndex(of: rate) ?? 0
        rate = Self.speeds[(index + 1) % Self.speeds.count]
        player?.rate = rate
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        player?.stop()
        player = nil
        isPlaying = false
        progress = 0
        currentID = nil
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.update()
            }
        }
    }

    private func update() {
        if simulated {
            guard isPlaying else { return }
            simulatedClock += 0.1 * Double(rate)
            progress = min(simulatedClock / max(simulatedDuration, 0.1), 1)
            if progress >= 1 { finished() }
        } else if let player, player.duration > 0 {
            progress = player.currentTime / player.duration
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finished() }
    }

    private func finished() {
        guard let id = currentID else { return }
        let following = next?(id)
        ticker?.cancel()
        player = nil
        isPlaying = false
        progress = 0
        currentID = nil
        if let following { Task { await play(following) } }
    }
}

// MARK: Bubble

/// A voice message: play or pause, the waveform with the position, the time, and (while it is the one playing) the speed.
struct VoiceBubble: View {
    let item: AttachmentItem
    let isOwn: Bool
    var uploading = false
    @Environment(ConversationStore.self) private var store
    @State private var player = VoicePlayer.shared
    @State private var loading = false

    private var isCurrent: Bool { player.isCurrent(item.id) }
    private var ink: Color { isOwn ? Theme.ownBubbleInk : Theme.text }

    var body: some View {
        HStack(spacing: 10) {
            Button { Task { await play() } } label: {
                ZStack {
                    Circle().fill(isOwn ? Theme.ownBubbleInk.opacity(0.16) : Theme.surface).frame(width: 40, height: 40)
                    if loading || uploading {
                        TransferRing(attachmentID: item.id, active: true, tint: ink).frame(width: 28, height: 28)
                    } else {
                        Image(systemName: isCurrent && player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 16)).foregroundStyle(ink)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCurrent && player.isPlaying ? "Pause voice message" : "Play voice message")
            .accessibilityIdentifier("voice-play-\(item.id)")
            Waveform(bars: item.thumb, progress: isCurrent ? player.progress : 0, ink: ink)
                .frame(width: 112, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .trailing, spacing: 2) {
                Text(timeText).font(Theme.caption.monospacedDigit()).foregroundStyle(ink.opacity(0.8))
                    .accessibilityIdentifier("voice-time-\(item.id)")
                if isCurrent {
                    Button { player.cycleRate() } label: {
                        Text(rateText).font(Theme.caption.weight(.bold)).foregroundStyle(ink)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(ink.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Playback speed \(rateText)")
                    .accessibilityIdentifier("voice-speed")
                }
            }
            .frame(minWidth: 40, alignment: .trailing)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(isOwn ? Theme.ownBubble : Theme.bubbleOther, in: RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous).strokeBorder(isOwn ? Color.clear : Theme.bubbleEdge, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice-bubble-\(item.id)")
    }

    private var rateText: String { player.rate == 1.5 ? "1.5×" : "\(Int(player.rate))×" }

    private var timeText: String {
        let total = Double(item.durationMs ?? 0) / 1000
        let shown = isCurrent ? max(total * (1 - player.progress), 0) : total
        return VoiceFormat.clock(shown)
    }

    private func play() async {
        loading = !item.downloaded
        defer { loading = false }
        await player.toggle(item, after: { store.nextVoiceMessage(after: $0) }, data: { await store.attachmentData($0) })
    }
}

/// The loudness bars of a voice message; the part already played is solid.
struct Waveform: View {
    let bars: Data
    let progress: Double
    let ink: Color

    var body: some View {
        Canvas { context, size in
            let values = bars.isEmpty ? [UInt8](repeating: 40, count: 40) : [UInt8](bars)
            let gap: CGFloat = 2
            let width = max(1.5, (size.width - gap * CGFloat(values.count - 1)) / CGFloat(values.count))
            for (index, value) in values.enumerated() {
                let height = max(3, size.height * CGFloat(value) / 255)
                let x = CGFloat(index) * (width + gap)
                let rect = CGRect(x: x, y: (size.height - height) / 2, width: width, height: height)
                let played = Double(index) / Double(values.count) < progress
                context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(ink.opacity(played ? 1 : 0.35)))
            }
        }
    }
}

enum VoiceFormat {
    /// "0:07", "1:23" (and "1:02:03" for the very long).
    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: Recording (in the composer)

/// What the composer shows in place of the text while a voice message is being recorded.
struct RecordingBar: View {
    let recorder: VoiceRecorder
    let dragX: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Color.red).frame(width: 10, height: 10).opacity(Int(recorder.elapsed * 2) % 2 == 0 ? 1 : 0.35)
            Text(VoiceFormat.clock(recorder.elapsed)).font(Theme.body.monospacedDigit()).foregroundStyle(Theme.text)
                .accessibilityIdentifier("recording-time")
            HStack(spacing: 2) {
                ForEach(Array(recorder.levels.suffix(28).enumerated()), id: \.offset) { _, level in
                    Capsule().fill(Theme.text.opacity(0.7)).frame(width: 2.5, height: max(3, CGFloat(level) * 22))
                }
            }
            .frame(height: 24)
            Spacer(minLength: 0)
            if recorder.phase == .recording {
                Label("Slide to cancel", systemImage: "chevron.left").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    .opacity(1 - min(1, abs(dragX) / 90)).labelStyle(.titleAndIcon)
                    .accessibilityIdentifier("recording-hint")
            }
        }
        .padding(.horizontal, 6).frame(minHeight: 44)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recording-bar")
    }
}
