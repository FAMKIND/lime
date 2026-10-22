import AVFoundation
@preconcurrency import Speech
import SwiftUI

/// Makes captions for a video or a recording on the writer's phone (LIME-188o), with Apple's speech recognition **on this iPhone only**
/// (`requiresOnDeviceRecognition`): if the phone cannot recognise this language on its own there are no captions, and nothing is ever sent to a
/// server. Used `SFSpeechRecognizer` (the iOS 26 `SpeechAnalyzer` would be a later swap behind the same function).
enum CaptionMaker {
    /// Longer recordings get no captions in this version (recognising an hour takes the phone a long while); the writer is told.
    static let maxSeconds = 300

    /// Cues from the speech in these bytes, or nil when there is none, the phone cannot do it on its own, or the person said no.
    static func make(bytes: Data, fileExtension: String, demo: Bool = false) async -> [CaptionCue]? {
        if demo { return demoCues }
        guard await authorised(), let recognizer = SFSpeechRecognizer(locale: Locale.current), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("caption-\(UUID().uuidString).\(fileExtension)")
        guard (try? bytes.write(to: url)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        return await withCheckedContinuation { continuation in
            let box = Once(continuation)
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal { box.resume(cues(from: result.bestTranscription.segments)) }
                else if error != nil { box.resume(nil) }
            }
            // A recogniser that never answers must not hold the post: stop after two minutes.
            DispatchQueue.global().asyncAfter(deadline: .now() + 120) { task.cancel(); box.resume(nil) }
        }
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
        var cues: [CaptionCue] = []
        var words: [String] = []
        var start = 0.0, end = 0.0
        func flush() {
            guard !words.isEmpty else { return }
            cues.append(CaptionCue(startMs: UInt64(max(start, 0) * 1000), endMs: UInt64(max(end, start + 0.5) * 1000), text: words.joined(separator: " ")))
            words = []
        }
        for segment in segments {
            let pause = words.isEmpty ? 0 : segment.timestamp - end
            if words.count >= 7 || pause > 0.8 || (!words.isEmpty && segment.timestamp + segment.duration - start > 4) { flush() }
            if words.isEmpty { start = segment.timestamp }
            words.append(segment.substring)
            end = segment.timestamp + segment.duration
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
        private var continuation: CheckedContinuation<[CaptionCue]?, Never>?
        init(_ continuation: CheckedContinuation<[CaptionCue]?, Never>) { self.continuation = continuation }
        func resume(_ value: [CaptionCue]?) {
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
                            Text(VoiceFormat.clock(Double(draft.cues[index].startMs) / 1000)).font(Theme.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary).frame(width: 44, alignment: .leading).padding(.top, 4)
                            TextField("Line", text: Binding(get: { draft.cues[index].text }, set: { draft.cues[index] = CaptionCue(startMs: draft.cues[index].startMs, endMs: draft.cues[index].endMs, text: $0) }), axis: .vertical)
                                .font(Theme.body).accessibilityIdentifier("caption-line-\(index)")
                        }
                    }
                    .onDelete { draft.cues.remove(atOffsets: $0) }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Captions").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("captions-done") } }
        }
        .presentationDetents([.large])
    }
}
