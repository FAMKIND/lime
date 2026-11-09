import AVFoundation
@preconcurrency import Speech
import SwiftUI
import UniformTypeIdentifiers

/// A transcript of a voice or video message, made **on this iPhone, on request** (LIME-130-3b) and never sent anywhere: iOS 26 and later use
/// `SpeechAnalyzer` (only with a language model the phone already has: lime never asks Apple to download one, which would be a network call),
/// earlier systems use `SFSpeechRecognizer` with `requiresOnDeviceRecognition`. If the phone cannot do this language on its own there is no transcript.
enum Transcriber {
    enum Outcome: Equatable {
        case text(String)
        /// The phone cannot recognise this language on its own, or heard nothing it could write down.
        case unavailable
        /// Speech Recognition was refused in Settings.
        case denied
        /// Longer than the phone's older recogniser handles (300 s).
        case tooLong
    }

    /// The limit of the recogniser on iOS 17 to 25.
    static let maxSecondsBelow26 = 300

    /// What the phone can do here, decided before any audio is read: the one place the on-device rule lives, so a test can pin it.
    struct Capability: Equatable {
        var hasAnalyzer = false          // iOS 26 SpeechAnalyzer with its model already on the phone
        var supportsOnDevice = false     // SFSpeechRecognizer.supportsOnDeviceRecognition
    }

    enum Plan: Equatable { case analyzer, recogniser, unavailable, tooLong }

    static func plan(_ capability: Capability, seconds: Double?) -> Plan {
        if capability.hasAnalyzer { return .analyzer }
        guard capability.supportsOnDevice else { return .unavailable }
        if let seconds, seconds > Double(maxSecondsBelow26) { return .tooLong }
        return .recogniser
    }

    /// The request for the older recogniser: on-device only, whatever else is set.
    static func request(url: URL) -> SFSpeechURLRecognitionRequest {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        return request
    }

    static func transcribe(bytes: Data, fileExtension: String, seconds: Double?) async -> Outcome {
        guard await authorised() else { return .denied }
        let locale = Locale.current
        let recogniser = SFSpeechRecognizer(locale: locale)
        var capability = Capability(supportsOnDevice: (recogniser?.isAvailable ?? false) && (recogniser?.supportsOnDeviceRecognition ?? false))
        var analyzerLocale: Locale?
        if #available(iOS 26.0, *), let found = await installedAnalyzerLocale(for: locale) {
            analyzerLocale = found
            capability.hasAnalyzer = true
        }
        let plan = plan(capability, seconds: seconds)
        guard plan != .unavailable else { return .unavailable }
        if plan == .tooLong { return .tooLong }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("transcript-\(UUID().uuidString).\(fileExtension)")
        guard (try? bytes.write(to: url)) != nil else { return .unavailable }
        defer { try? FileManager.default.removeItem(at: url) }
        if plan == .analyzer, #available(iOS 26.0, *), let analyzerLocale {
            if let text = await analyze(url: url, locale: analyzerLocale) { return text.isEmpty ? .unavailable : .text(text) }
            // The file could not be read as audio (some videos): the older recogniser reads those, if it can.
            guard capability.supportsOnDevice else { return .unavailable }
        }
        guard let recogniser else { return .unavailable }
        return await recognise(url: url, with: recogniser)
    }

    private static func authorised() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined: return await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        default: return false
        }
    }

    private static func recognise(url: URL, with recogniser: SFSpeechRecognizer) async -> Outcome {
        await withCheckedContinuation { continuation in
            let box = Once(continuation)
            let task = recogniser.recognitionTask(with: request(url: url)) { result, error in
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    box.resume(text.isEmpty ? .unavailable : .text(text))
                } else if error != nil { box.resume(.unavailable) }
            }
            // A recogniser that never answers must not hold the screen: stop after two minutes.
            DispatchQueue.global().asyncAfter(deadline: .now() + 120) { task.cancel(); box.resume(.unavailable) }
        }
    }

    @available(iOS 26.0, *)
    private static func installedAnalyzerLocale(for locale: Locale) async -> Locale? {
        guard SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { return nil }
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains(where: { $0.identifier(.bcp47) == supported.identifier(.bcp47) }) ? supported : nil
    }

    /// nil when the file could not be read as audio.
    @available(iOS 26.0, *)
    private static func analyze(url: URL, locale: Locale) async -> String? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collecting = Task { () -> String in
            var text = ""
            do { for try await result in transcriber.results { text += String(result.text.characters) } } catch {}
            return text
        }
        do {
            if let last = try await analyzer.analyzeSequence(from: file) { try await analyzer.finalizeAndFinish(through: last) }
            else { await analyzer.cancelAndFinishNow() }
        } catch {
            collecting.cancel()
            return nil
        }
        return await collecting.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The file extension a recogniser needs to open these bytes.
    static func fileExtension(forMime mime: String) -> String {
        if mime.hasPrefix("video/") { return UTType(mimeType: mime)?.preferredFilenameExtension ?? "mp4" }
        return mime == "audio/mpeg" ? "mp3" : "m4a"   // lime's voice messages are AAC in an MPEG-4 file
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Outcome, Never>?
        init(_ continuation: CheckedContinuation<Outcome, Never>) { self.continuation = continuation }
        func resume(_ value: Outcome) {
            lock.lock(); defer { lock.unlock() }
            continuation?.resume(returning: value)
            continuation = nil
        }
    }
}

/// The transcripts this phone has made (or loaded with the messages), by attachment: what the bubble shows, and the one place that runs a request.
@MainActor @Observable
final class Transcripts {
    static let shared = Transcripts()

    enum State: Equatable {
        case idle
        case working
        case text(String)
        case failed(String)
    }

    private(set) var states: [String: State] = [:]
    /// Whether a transcript is open under its bubble (made earlier or just now): it opens on request and closes on request.
    private(set) var shown: Set<String> = []

    static let notAvailable = "Transcript not available on this iPhone."
    static let denied = "Transcripts need Speech Recognition. You can turn it on in Settings."
    static let tooLong = "This message is too long for this iPhone to transcribe."

    func state(for item: AttachmentItem) -> State {
        if let state = states[item.id] { return state }
        return item.transcript.isEmpty ? .idle : .text(item.transcript)
    }

    func isShown(_ item: AttachmentItem) -> Bool { shown.contains(item.id) }

    func hide(_ item: AttachmentItem) { shown.remove(item.id) }

    /// "Show transcript": shows the one this phone already has, or makes it now.
    func show(_ item: AttachmentItem, messageID: String, store: ConversationStore) {
        if case .text = state(for: item) { shown.insert(item.id); Announce.say("Transcript shown"); return }
        guard state(for: item) != .working else { return }
        shown.insert(item.id)
        states[item.id] = .working
        Announce.say("Making the transcript")
        Task {
            let outcome = await make(item, store: store)
            switch outcome {
            case .text(let text):
                states[item.id] = .text(text)
                store.keepTranscript(text, for: item, messageID: messageID)
                Announce.say("Transcript ready")
            case .unavailable: states[item.id] = .failed(Self.notAvailable); Announce.say(Self.notAvailable)
            case .denied: states[item.id] = .failed(Self.denied); Announce.say(Self.denied)
            case .tooLong: states[item.id] = .failed(Self.tooLong); Announce.say(Self.tooLong)
            }
        }
    }

    private func make(_ item: AttachmentItem, store: ConversationStore) async -> Transcriber.Outcome {
        #if DEBUG
        // The demo (screenshots and UI tests) shows a fixed text, so no recogniser runs there.
        if store.isDemo { try? await Task.sleep(for: .milliseconds(300)); return .text("Hello everyone. Please bring your reading folders on Thursday, and thank you for the lovely cards.") }
        #endif
        guard let bytes = await store.attachmentData(item) else { return .unavailable }
        return await Transcriber.transcribe(bytes: bytes, fileExtension: Transcriber.fileExtension(forMime: item.mime), seconds: item.durationMs.map { Double($0) / 1000 })
    }
}

/// "Show transcript" under a voice or video message, then the text (selectable) or why there is none.
struct TranscriptSection: View {
    let item: AttachmentItem
    let messageID: String
    let isOwn: Bool
    @Environment(ConversationStore.self) private var store
    private var transcripts: Transcripts { .shared }

    var body: some View {
        let state = transcripts.state(for: item)
        VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
            if transcripts.isShown(item) {
                switch state {
                case .working:
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Making the transcript…").font(Theme.caption).foregroundStyle(Theme.textSecondary) }
                        .accessibilityElement(children: .combine).accessibilityIdentifier("transcript-working-\(item.id)")
                case .text(let text):
                    Text(text).font(Theme.secondary).foregroundStyle(Theme.text).textSelection(.enabled)
                        .multilineTextAlignment(.leading).frame(maxWidth: 248, alignment: .leading)
                        .padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityLabel("Transcript: \(text)").accessibilityIdentifier("transcript-text-\(item.id)")
                    button("Hide transcript") { transcripts.hide(item) }
                case .failed(let why):
                    Text(why).font(Theme.caption).foregroundStyle(Theme.textSecondary).frame(maxWidth: 248, alignment: isOwn ? .trailing : .leading)
                        .accessibilityIdentifier("transcript-failed-\(item.id)")
                    button("Try again") { transcripts.show(item, messageID: messageID, store: store) }
                case .idle: EmptyView()
                }
            } else {
                button("Show transcript") { transcripts.show(item, messageID: messageID, store: store) }
            }
        }
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.font(.footnote, weight: .semibold)).foregroundStyle(Theme.text)
                .padding(.horizontal, 10).frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(title == "Show transcript" ? "transcript-show-\(item.id)" : "transcript-other-\(item.id)")
    }
}
