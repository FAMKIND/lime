import Foundation
import Observation

/// Settings → Calls (LIME-169), kept on this phone: show lime's calls in the iPhone's Recents, use less data for video, and how loud the other
/// people sound. A change reaches a call that is already running (the media listens for `CallSettings.changed`).
@Observable
final class CallSettings: @unchecked Sendable {
    static let shared = CallSettings(defaults: launchDefaults())

    static let recentsKey = "lime.calls.recents"
    static let lowDataKey = "lime.calls.lowdata"
    static let volumeKey = "lime.calls.volume"
    /// Posted (on the main thread) after any of the three changes.
    static let changed = Notification.Name("lime.callSettingsChanged")

    /// The other people's voices relative to the phone's volume: half to double. 1 is the phone's own.
    static let volumeRange: ClosedRange<Double> = 0.5...2.0

    private let defaults: UserDefaults

    /// Lime's calls appear in the Phone app's Recents (off by default: the Phone app, and iCloud, would learn when you called whom).
    var includeInRecents: Bool { didSet { defaults.set(includeInRecents, forKey: Self.recentsKey); Self.announce() } }
    /// Less video data: a smaller, slower picture is sent and the lowest layer of the others' video is asked for.
    var lowDataMode: Bool { didSet { defaults.set(lowDataMode, forKey: Self.lowDataKey); Self.announce() } }

    /// Written by hand, not by the observation macro: a `didSet` that clamps the property itself would loop under it.
    @ObservationIgnored private var storedVolume: Double
    var volume: Double {
        get { access(keyPath: \.volume); return storedVolume }
        set {
            withMutation(keyPath: \.volume) {
                storedVolume = min(max(newValue, Self.volumeRange.lowerBound), Self.volumeRange.upperBound)
                defaults.set(storedVolume, forKey: Self.volumeKey)
            }
            Self.announce()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // A Debug build can start with `-lime.calls.recents YES -lime.calls.lowdata YES -lime.calls.volume 1.5`: launch arguments arrive as text.
        includeInRecents = Self.bool(defaults.object(forKey: Self.recentsKey)) ?? false
        lowDataMode = Self.bool(defaults.object(forKey: Self.lowDataKey)) ?? false
        let stored = Self.double(defaults.object(forKey: Self.volumeKey)) ?? 1.0
        storedVolume = min(max(stored, Self.volumeRange.lowerBound), Self.volumeRange.upperBound)
    }

    /// The phone's defaults, except in a UI-test launch (`-lime-skip-sign-in`, Debug): a fresh throwaway set each time (plus the `-lime.calls.*`
    /// arguments), so one test cannot leak a setting into the next.
    private static func launchDefaults() -> UserDefaults {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-lime-skip-sign-in"), let fresh = UserDefaults(suiteName: "lime.uitest.calls") {
            fresh.removePersistentDomain(forName: "lime.uitest.calls")
            for key in [recentsKey, lowDataKey, volumeKey] {
                if let at = arguments.firstIndex(of: "-" + key), at + 1 < arguments.count { fresh.set(arguments[at + 1], forKey: key) }
            }
            return fresh
        }
        #endif
        return .standard
    }

    private static func announce() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: changed, object: nil)
        } else {
            DispatchQueue.main.async { NotificationCenter.default.post(name: changed, object: nil) }
        }
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        switch (value as? String)?.lowercased() {
        case "yes", "true", "1": return true
        case "no", "false", "0": return false
        default: return nil
        }
    }

    private static func double(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        return (value as? String).flatMap { Double($0) }
    }

    /// "100%" (the slider's value, spoken the same way).
    static func percent(_ volume: Double) -> String { "\(Int((volume * 100).rounded()))%" }
}

/// What video a phone sends, chosen from the settings (LIME-169): the choice is a plain function so it can be tested without a camera.
enum CallVideoPlan {
    struct Capture: Equatable {
        var width: Int
        var height: Int
        var fps: Int
    }

    /// The most video data Low Data Mode lets one call send (bits per second).
    static let lowDataMaxBitrate = 350_000

    /// The camera size and rate. Normal: 720p (30 fps in a group, up to 24 in a one-to-one call: WebRTC adapts down). On mobile data in a group:
    /// 480p at 24. Low Data Mode: 360p at 15, whatever else.
    static func capture(lowData: Bool, cellular: Bool = false, group: Bool) -> Capture {
        if lowData { return Capture(width: 640, height: 360, fps: 15) }
        if group { return cellular ? Capture(width: 848, height: 480, fps: 24) : Capture(width: 1280, height: 720, fps: 30) }
        return Capture(width: 1280, height: 720, fps: 24)
    }

    /// The bitrate cap (bits per second), or nil for no cap beyond what WebRTC chooses itself.
    static func maxBitrate(lowData: Bool) -> Int? { lowData ? lowDataMaxBitrate : nil }
    static func maxFps(lowData: Bool) -> Int? { lowData ? 15 : nil }
}
