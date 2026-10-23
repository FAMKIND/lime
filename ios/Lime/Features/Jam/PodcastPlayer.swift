import AVFoundation
import MediaPlayer
import SwiftUI

/// Plays one recording of a jam post (LIME-188g): audio or video, with a position you can drag, −15 s and +30 s, 1× / 1.5× / 2×, and the lock-screen /
/// Control Center controls while lime is in the background. Only one plays at a time.
@MainActor
@Observable
final class PodcastController {
    static let speeds: [Float] = [1, 1.5, 2]
    private static weak var current: PodcastController?

    private(set) var isPlaying = false
    private(set) var position: Double = 0
    private(set) var duration: Double
    private(set) var rate: Float = 1
    private(set) var loading = false
    private(set) var failed = false
    /// The video's own current time is at its end.
    var atEnd: Bool { duration > 0 && position >= duration - 0.3 && !isPlaying }
    private(set) var player: AVPlayer?
    /// Debug demo and UI tests: no sound, a clock.
    var simulated = false
    /// A video card starts silent and goes on playing when it is opened full screen (LIME-188j).
    var muted = false {
        didSet {
            player?.isMuted = muted
            if player != nil, isPlaying { configureSession() }
        }
    }

    private let title: String
    private let artist: String
    private let isVideo: Bool
    private var ticker: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var fileURL: URL?

    init(duration: Double, title: String, artist: String, isVideo: Bool = false) {
        self.duration = duration
        self.title = title
        self.artist = artist
        self.isVideo = isVideo
    }

    var hasStarted: Bool { player != nil || (simulated && (isPlaying || position > 0)) }
    var remaining: Double { max(duration - position, 0) }
    var fraction: Double { duration > 0 ? min(max(position / duration, 0), 1) : 0 }

    /// Starts playing if it is not already (the autoplay of a video card).
    func play(data: () async -> Data?) async {
        if isPlaying { return }
        await toggle(data: data)
    }

    private func configureSession() {
        // A muted card must not stop the music someone else is playing; sound on takes the session.
        let session = AVAudioSession.sharedInstance()
        if muted { try? session.setCategory(.ambient, mode: .default) } else { try? session.setCategory(.playback, mode: isVideo ? .moviePlayback : .spokenAudio) }
        try? session.setActive(true)
    }

    /// Plays, pausing whatever else was playing. `data` is fetched on the first play only.
    func toggle(data: () async -> Data?) async {
        if isPlaying { pause(); return }
        if player == nil, !simulated {
            loading = true
            defer { loading = false }
            guard let bytes = await data() else { failed = true; return }
            guard prepare(bytes) else { failed = true; return }
            // A position chosen on the card before anything was loaded: start from there.
            if position > 0.5 { player?.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: { _ in }) }
        }
        failed = false
        if let other = Self.current, other !== self { other.pause() }
        Self.current = self
        if position >= duration - 0.2 { position = 0; player?.seek(to: .zero, completionHandler: { _ in }) }
        if simulated { isPlaying = true; startTicker() } else {
            configureSession()
            player?.isMuted = muted
            player?.playImmediately(atRate: rate)
            isPlaying = true
            startTicker()
        }
        connectRemote()
        publishNowPlaying()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        ticker?.cancel()
        publishNowPlaying()
    }

    func seek(to seconds: Double) {
        let clamped = min(max(seconds, 0), duration)
        position = clamped
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: { _ in })
        publishNowPlaying()
    }

    func skip(by seconds: Double) { seek(to: position + seconds) }

    /// 1× to 1.5× to 2× and round again; takes effect at once.
    func cycleRate() {
        rate = Self.speeds[((Self.speeds.firstIndex(of: rate) ?? 0) + 1) % Self.speeds.count]
        if isPlaying { player?.rate = rate }
        publishNowPlaying()
    }

    private func prepare(_ bytes: Data) -> Bool {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("jam-\(UUID().uuidString).\(isVideo ? "mp4" : "m4a")")
        guard (try? bytes.write(to: url)) != nil else { return false }
        fileURL = url
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        player.isMuted = muted
        self.player = player
        Task { [weak self] in
            if let seconds = try? await item.asset.load(.duration).seconds, seconds.isFinite, seconds > 0 { self?.duration = seconds }
        }
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finished() }
        }
        return true
    }

    private func finished() {
        isPlaying = false
        ticker?.cancel()
        position = duration
        publishNowPlaying()
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.tick()
            }
        }
    }

    private func tick() {
        if simulated {
            guard isPlaying else { return }
            position = min(position + 0.1 * Double(rate), duration)
            if position >= duration { finished() }
        } else if let player, isPlaying {
            let now = player.currentTime().seconds
            if now.isFinite { position = min(now, duration) }
        }
    }

    // MARK: Lock screen and Control Center

    private func publishNowPlaying() {
        guard !simulated else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title.isEmpty ? "jam recording" : title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
    }

    private func connectRemote() {
        guard !simulated else { return }
        let center = MPRemoteCommandCenter.shared()
        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand, center.skipForwardCommand, center.skipBackwardCommand, center.changePlaybackPositionCommand] {
            command.removeTarget(nil)
        }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        center.playCommand.isEnabled = true; center.pauseCommand.isEnabled = true; center.togglePlayPauseCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = true; center.skipBackwardCommand.isEnabled = true; center.changePlaybackPositionCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in Task { @MainActor in await self?.toggle(data: { nil }) }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in
            guard let self else { return }
            if self.isPlaying { self.pause() } else { await self.toggle(data: { nil }) }
        }; return .success }
        center.skipForwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(by: 10) }; return .success }
        center.skipBackwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(by: -10) }; return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    deinit {
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }
}

enum PodcastFormat {
    /// "2 minutes 10 seconds", for VoiceOver.
    static func spoken(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        var parts: [String] = []
        if h > 0 { parts.append(h == 1 ? "1 hour" : "\(h) hours") }
        if m > 0 { parts.append(m == 1 ? "1 minute" : "\(m) minutes") }
        if s > 0 || parts.isEmpty { parts.append(s == 1 ? "1 second" : "\(s) seconds") }
        return parts.joined(separator: " ")
    }
}

/// The player under a recording: the waveform of the whole thing with the played part coloured (drag it to scrub), the times, play / pause, −15 s,
/// +30 s and the speed. A video has no waveform; it gets a plain track.
struct PodcastBar: View {
    let controller: PodcastController
    let waveform: Data
    let load: () async -> Data?
    var id = ""

    var body: some View {
        VStack(spacing: 8) {
            scrubber
            HStack {
                Text(VoiceFormat.clock(controller.position)).accessibilityIdentifier("podcast-elapsed-\(id)")
                Spacer()
                Text("\u{2212}" + VoiceFormat.clock(controller.remaining)).accessibilityIdentifier("podcast-remaining-\(id)")
            }
            .font(Theme.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
            .accessibilityHidden(true)
            HStack(spacing: 0) {
                Button { controller.cycleRate() } label: {
                    Text(controller.rate == 1.5 ? "1.5\u{00D7}" : "\(Int(controller.rate))\u{00D7}").font(Theme.font(.subheadline, weight: .bold)).foregroundStyle(Theme.text)
                        .frame(minWidth: 48, minHeight: 44).background(Theme.surface, in: Capsule())
                }
                .accessibilityLabel("Playback speed \(controller.rate == 1.5 ? "1.5" : "\(Int(controller.rate))")").accessibilityIdentifier("podcast-speed-\(id)")
                Spacer()
                skipButton("gobackward.10", "Back 10 seconds", -10)
                Button { Task { await controller.toggle(data: load) } } label: {
                    ZStack {
                        Circle().fill(Theme.accent).frame(width: 56, height: 56)
                        if controller.loading { ProgressView().tint(Theme.accentInk) }
                        else { Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 22)).foregroundStyle(Theme.accentInk) }
                    }
                    .frame(width: 60, height: 60)
                }
                .accessibilityLabel(controller.isPlaying ? "Pause" : "Play").accessibilityIdentifier("podcast-play-\(id)")
                skipButton("goforward.10", "Forward 10 seconds", 10)
                Spacer()
                Color.clear.frame(width: 48, height: 44).accessibilityHidden(true)
            }
            if controller.failed {
                Text("Couldn\u{2019}t play this recording.").font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("podcast-\(id)")
    }

    private func skipButton(_ symbol: String, _ label: String, _ seconds: Double) -> some View {
        Button { controller.skip(by: seconds) } label: {
            Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(Theme.text).frame(width: 46, height: 46)
        }
        .accessibilityLabel(label).accessibilityIdentifier("podcast-skip-\(Int(seconds))-\(id)")
    }

    private var scrubber: some View {
        WaveformScrubber(controller: controller, waveform: waveform, id: id, height: 48)
    }
}

/// The bars of a waveform (LIME-188y): each bar is the same width and gap in every orientation; only how many are drawn follows the width, by
/// resampling the stored values (the loudest in each stretch).
enum WaveformBars {
    static let barWidth: CGFloat = 2.5
    static let gap: CGFloat = 2

    static func count(forWidth width: CGFloat) -> Int { max(1, Int((width + gap) / (barWidth + gap))) }

    static func resample(_ values: [UInt8], to count: Int) -> [UInt8] {
        guard !values.isEmpty, count > 0 else { return [] }
        if values.count == count { return values }
        return (0..<count).map { index in
            let from = index * values.count / count
            let to = max(from + 1, (index + 1) * values.count / count)
            return values[from..<min(to, values.count)].max() ?? 0
        }
    }
}

/// The waveform of a whole recording with the played part solid: tap or drag to scrub. One adjustable element for VoiceOver.
struct WaveformScrubber: View {
    let controller: PodcastController
    let waveform: Data
    var id = ""
    var height: CGFloat = 48

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let stored: [UInt8] = waveform.isEmpty ? [UInt8](repeating: 120, count: 64) : [UInt8](waveform)
                let values = WaveformBars.resample(stored, to: WaveformBars.count(forWidth: size.width))
                let width = WaveformBars.barWidth, gap = WaveformBars.gap
                let used = CGFloat(values.count) * (width + gap) - gap
                let left = max(0, (size.width - used) / 2)
                for (index, value) in values.enumerated() {
                    let bar = waveform.isEmpty ? 4 : max(4, size.height * CGFloat(value) / 255)
                    let rect = CGRect(x: left + CGFloat(index) * (width + gap), y: (size.height - bar) / 2, width: width, height: bar)
                    let played = (Double(index) + 0.5) / Double(values.count) <= controller.fraction
                    context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(played ? Theme.text : Theme.text.opacity(0.28)))
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                controller.seek(to: Double(min(max(value.location.x / max(geo.size.width, 1), 0), 1)) * controller.duration)
            })
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue("\(PodcastFormat.spoken(controller.position)) of \(PodcastFormat.spoken(controller.duration))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: controller.skip(by: 10)
            case .decrement: controller.skip(by: -10)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("podcast-scrubber-\(id)")
    }
}

/// A video from an AVPlayer, edge to edge in its frame.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer?
    var fill = false

    final class Host: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var layer_: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> Host {
        let view = Host()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: Host, context: Context) {
        view.layer_.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        view.layer_.player = player
    }
}
