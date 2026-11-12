import AVFoundation
@preconcurrency import Speech
import SwiftUI

/// Makes captions for a video or a recording on the writer's phone (LIME-188o), **on this iPhone only**: nothing is ever sent to a server and no language
/// model is ever downloaded. iOS 26 and later use `SpeechAnalyzer` when the language model is already installed, with no length cap (LIME-130-6b);
/// earlier systems use `SFSpeechRecognizer` (`requiresOnDeviceRecognition`), which is kept to five minutes. The core's limits on a caption file still
/// apply: a long one stops at the limit and the writer is told.
enum CaptionMaker {
    /// The older recogniser's limit; the iOS 26 analyzer has none.
    static let maxSeconds = Transcriber.maxSecondsBelow26
    /// The core's limits on a caption file (`MAX_CUES`, `MAX_CAPTION_BYTES` in `core/src/captions.rs`).
    static let maxCues = 6000
    static let maxBytes = 256 * 1024

    /// Captions, and where they stopped when the file hit the limit.
    struct Result: Equatable {
        var cues: [CaptionCue]
        /// Milliseconds into the recording where the captions end because of the limit, or nil when they cover all of it.
        var stoppedAtMs: UInt64?
    }

    /// What the phone will use, by iOS version and whether the analyzer's model is installed: the one place the rule lives, so a test can pin it.
    static func plan(analyzerInstalled: Bool, supportsOnDevice: Bool, seconds: Double?) -> Transcriber.Plan {
        Transcriber.plan(Transcriber.Capability(hasAnalyzer: analyzerInstalled, supportsOnDevice: supportsOnDevice), seconds: seconds)
    }

    /// Whether captions can be made for a recording this long on this phone, now.
    static func canMake(seconds: Double?) async -> Bool {
        let recogniser = SFSpeechRecognizer(locale: Locale.current)
        let onDevice = (recogniser?.isAvailable ?? false) && (recogniser?.supportsOnDeviceRecognition ?? false)
        var analyzer = false
        if #available(iOS 26.0, *) { analyzer = await Transcriber.installedAnalyzerLocale(for: Locale.current) != nil }
        let plan = plan(analyzerInstalled: analyzer, supportsOnDevice: onDevice, seconds: seconds)
        return plan == .analyzer || plan == .recogniser
    }

    /// Cues cut to the core's limits: at most `maxCues` lines and `maxBytes` of file, and the time they stop at when they were cut.
    static func limited(_ cues: [CaptionCue]) -> Result {
        var kept: [CaptionCue] = []
        var bytes = 20   // the header and a margin
        for cue in cues {
            let size = cue.text.utf8.count + 32
            if kept.count >= maxCues || bytes + size > maxBytes { return Result(cues: kept, stoppedAtMs: kept.last?.endMs ?? 0) }
            kept.append(cue); bytes += size
        }
        return Result(cues: kept, stoppedAtMs: nil)
    }

    /// Cues from the speech in these bytes, or nil when there is none, the phone cannot do it on its own, or the person said no.
    static func make(bytes: Data, fileExtension: String, seconds: Double? = nil, demo: Bool = false) async -> Result? {
        if demo { return Result(cues: demoCues, stoppedAtMs: nil) }
        guard await authorised() else { return nil }
        let recogniser = SFSpeechRecognizer(locale: Locale.current)
        let onDevice = (recogniser?.isAvailable ?? false) && (recogniser?.supportsOnDeviceRecognition ?? false)
        var analyzerLocale: Locale?
        if #available(iOS 26.0, *) { analyzerLocale = await Transcriber.installedAnalyzerLocale(for: Locale.current) }
        let chosen = plan(analyzerInstalled: analyzerLocale != nil, supportsOnDevice: onDevice, seconds: seconds)
        guard chosen == .analyzer || chosen == .recogniser else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("caption-\(UUID().uuidString).\(fileExtension)")
        guard (try? bytes.write(to: url)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }
        if chosen == .analyzer, #available(iOS 26.0, *), let analyzerLocale {
            if let cues = await analyzeCues(url: url, locale: analyzerLocale), !cues.isEmpty { return limited(cues) }
            // The file could not be read as audio (some videos): the older recogniser reads those, if it can and the clip is short enough.
            guard onDevice, (seconds ?? 0) <= Double(maxSeconds) else { return nil }
        }
        guard let recogniser else { return nil }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        return await withCheckedContinuation { continuation in
            let box = Once(continuation)
            let task = recogniser.recognitionTask(with: request) { result, error in
                if let result, result.isFinal { box.resume(cues(from: result.bestTranscription.segments).map(limited)) }
                else if error != nil { box.resume(nil) }
            }
            // A recogniser that never answers must not hold the post: stop after two minutes.
            DispatchQueue.global().asyncAfter(deadline: .now() + 120) { task.cancel(); box.resume(nil) }
        }
    }

    /// iOS 26: the analyzer's results with each phrase's time range, grouped into lines. nil when the file cannot be read as audio.
    @available(iOS 26.0, *)
    private static func analyzeCues(url: URL, locale: Locale) async -> [CaptionCue]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collecting = Task { () -> [(text: String, start: Double, duration: Double)] in
            var words: [(text: String, start: Double, duration: Double)] = []
            do {
                for try await result in transcriber.results {
                    for run in result.text.runs {
                        guard let range = run.audioTimeRange else { continue }
                        let text = String(result.text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty { words.append((text, range.start.seconds, range.duration.seconds)) }
                    }
                }
            } catch {}
            return words
        }
        do {
            if let last = try await analyzer.analyzeSequence(from: file) { try await analyzer.finalizeAndFinish(through: last) }
            else { await analyzer.cancelAndFinishNow() }
        } catch {
            collecting.cancel()
            return nil
        }
        return cues(fromWords: await collecting.value)
    }

    private static func authorised() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined: return await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        default: return false
        }
    }

    /// Words into lines: a new line after about seven words, four seconds or a pause.
    static func cues(from segments: [SFTranscriptionSegment]) -> [CaptionCue]? {
        cues(fromWords: segments.map { ($0.substring, $0.timestamp, $0.duration) })
    }

    static func cues(fromWords segments: [(text: String, start: Double, duration: Double)]) -> [CaptionCue]? {
        var cues: [CaptionCue] = []
        var words: [String] = []
        var start = 0.0, end = 0.0
        func flush() {
            guard !words.isEmpty else { return }
            cues.append(CaptionCue(startMs: UInt64(max(start, 0) * 1000), endMs: UInt64(max(end, start + 0.5) * 1000), text: words.joined(separator: " ")))
            words = []
        }
        for segment in segments {
            let pause = words.isEmpty ? 0 : segment.start - end
            if words.count >= 7 || pause > 0.8 || (!words.isEmpty && segment.start + segment.duration - start > 4) { flush() }
            if words.isEmpty { start = segment.start }
            words.append(segment.text)
            end = segment.start + segment.duration
        }
        flush()
        return cues.isEmpty ? nil : cues
    }

    static let demoCues = [
        CaptionCue(startMs: 0, endMs: 4000, text: "A fraction wall in ten seconds."),
        CaptionCue(startMs: 4000, endMs: 10_000, text: "Fold it, cut it, compare the pieces."),
    ]

    /// Resumes a continuation once, from whichever callback comes first.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Result?, Never>?
        init(_ continuation: CheckedContinuation<Result?, Never>) { self.continuation = continuation }
        func resume(_ value: Result?) {
            lock.lock(); defer { lock.unlock() }
            continuation?.resume(returning: value)
            continuation = nil
        }
    }
}

/// The captions the writer is looking at before posting: the lines, and whether this post gets them.
struct CaptionDraft: Equatable {
    var cues: [CaptionCue] = []
    var on = true
    /// Recognition is still running.
    var making = true
    /// The phone made none (no speech, no on-device model, or permission refused), or the clip is too long.
    var none = false
    /// Where the captions stop because the file hit the core's limit (a long recording on iOS 26), or nil (LIME-130-6b).
    var stoppedAtMs: UInt64?
}

/// Read and correct the lines; "Captions" off leaves them out of this post.
struct CaptionsEditor: View {
    @Binding var draft: CaptionDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Captions", isOn: $draft.on).accessibilityIdentifier("captions-on")
                }
                Section("Lines") {
                    ForEach(draft.cues.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 10) {
                            Text(VoiceFormat.clock(Double(draft.cues[index].startMs) / 1000)).font(Theme.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary).frame(minWidth: 44, alignment: .leading).fixedSize(horizontal: true, vertical: false).padding(.top, 4)
                                .accessibilityLabel("at \(PodcastFormat.spoken(Double(draft.cues[index].startMs) / 1000))")
                            TextField("Line", text: Binding(get: { draft.cues[index].text }, set: { draft.cues[index] = CaptionCue(startMs: draft.cues[index].startMs, endMs: draft.cues[index].endMs, text: $0) }), axis: .vertical)
                                .font(Theme.body).accessibilityLabel("Caption line \(index + 1)").accessibilityIdentifier("caption-line-\(index)")
                        }
                    }
                    .onDelete { draft.cues.remove(atOffsets: $0) }
                }
            }
            .listStyle(.insetGrouped)
            .sheetHeader("Captions")
        }
        .presentationDetents([.large])
    }
}
