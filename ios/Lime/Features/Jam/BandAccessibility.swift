import SwiftUI

/// What is spoken when a band or community join changes state (LIME-130-6c). The state replaces the button in place, so it is announced; focus stays.
enum JoinSpeech {
    static func words(state: String?, name: String) -> String? {
        switch state {
        case "asked": "Asked to join \(name)"
        case "joined": "Joined \(name)"
        case "full": "\(name) is full"
        case "refused": "This link no longer works"
        default: nil
        }
    }
}

/// What the recorder says as the take changes: Recording, Paused, Stopped with the length. The running time is the record button's value, not spoken
/// every second.
enum RecorderSpeech {
    static func change(wasRecording: Bool, isRecording: Bool, wasPaused: Bool, isPaused: Bool, elapsed: TimeInterval) -> String? {
        if isRecording && !wasRecording { return "Recording" }
        if !isRecording && wasRecording { return "Stopped, \(PodcastFormat.spoken(elapsed))" }
        if isRecording && isPaused && !wasPaused { return "Paused" }
        if isRecording && !isPaused && wasPaused { return "Recording" }
        return nil
    }
}

/// Says someone else is editing a paragraph other than the one you are in, at most once every `gap` seconds for each person, and only while VoiceOver
/// runs (a sighted writer sees the cursor).
struct EditingAnnouncer {
    static let gap: TimeInterval = 5
    private var last: [String: Date] = [:]

    mutating func shouldSay(person: String, now: Date = Date()) -> Bool {
        if let before = last[person], now.timeIntervalSince(before) < Self.gap { return false }
        last[person] = now
        return true
    }
}
