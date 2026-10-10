import AVFoundation
import Foundation

/// The person's own message and call sounds (LIME-102b). A picked file is trimmed (at most 2 s for a message, under 30 s for a call),
/// converted to CAF and kept in `Library/Sounds`, where iOS looks for custom notification sounds. They stay on this phone: not uploaded,
/// not synced, and excluded from backup.
@MainActor
@Observable
final class CustomSounds {
    static let shared = CustomSounds()

    enum Kind: String, Codable, Sendable, Identifiable {
        var id: String { rawValue }
        case message, call
        /// The longest a sound of this kind may be (iOS plays a notification sound for at most 30 s).
        var maxSeconds: Double { self == .message ? 2 : 29.5 }
    }

    struct Item: Identifiable, Codable, Equatable, Sendable {
        let id: String
        var name: String
        let kind: Kind
        let seconds: Double
    }

    enum Failure: Error, Equatable { case tooMany, unreadable, empty }

    static let limit = 10
    private(set) var items: [Item] = []

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "lime.customSounds"

    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.directory = directory ?? (FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent("Sounds", isDirectory: true)
        items = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Item].self, from: $0) } ?? []
        // Forget entries whose file is gone.
        items.removeAll { !FileManager.default.fileExists(atPath: fileURL($0.id).path) }
    }

    func fileURL(_ id: String) -> URL { directory.appendingPathComponent("\(id).caf") }
    func items(of kind: Kind) -> [Item] { items.filter { $0.kind == kind } }
    func item(_ id: String) -> Item? { items.first { $0.id == id } }

    /// The length of an audio file in seconds.
    nonisolated static func duration(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    /// Cuts `start ..< start + length` seconds of `source`, converts it to CAF and keeps it under `name`.
    @discardableResult
    func add(from source: URL, start: Double, length: Double, name: String, kind: Kind) throws -> Item {
        guard items.count < Self.limit else { throw Failure.tooMany }
        guard let input = try? AVAudioFile(forReading: source) else { throw Failure.unreadable }
        let rate = input.processingFormat.sampleRate
        let first = AVAudioFramePosition(max(start, 0) * rate)
        let wanted = AVAudioFrameCount(min(length, kind.maxSeconds) * rate)
        guard first < input.length, wanted > 0 else { throw Failure.empty }
        input.framePosition = first
        let count = min(wanted, AVAudioFrameCount(input.length - first))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: count) else { throw Failure.unreadable }
        try input.read(into: buffer, frameCount: count)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        let id = "custom-\(UUID().uuidString.lowercased())"
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: Int(input.processingFormat.channelCount),
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            let output = try AVAudioFile(forWriting: fileURL(id), settings: settings, commonFormat: input.processingFormat.commonFormat, interleaved: input.processingFormat.isInterleaved)
            try output.write(from: buffer)
        } catch {
            try? FileManager.default.removeItem(at: fileURL(id))
            throw Failure.unreadable
        }
        let item = Item(id: id, name: Self.clean(name), kind: kind, seconds: Double(count) / rate)
        items.append(item)
        save()
        return item
    }

    func rename(_ id: String, to name: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].name = Self.clean(name)
        save()
    }

    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: fileURL(id))
        items.removeAll { $0.id == id }
        save()
    }

    private static func clean(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? "My sound" : trimmed).prefix(30))
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: Self.key) }
    }
}
