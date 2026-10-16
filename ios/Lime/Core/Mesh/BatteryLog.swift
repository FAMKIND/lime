import Foundation

/// The battery soak (LIME-144): samples of the battery taken every 5 minutes while the mesh runs, and the drain per hour from them. A period is
/// counted only when the phone was unplugged at both ends of it (so charging never hides the drain). Pure, so it is tested.
struct BatterySample: Equatable, Sendable {
    let time: Date
    /// 0...100.
    let level: Int
    let plugged: Bool
}

enum BatteryLog {
    static let interval: TimeInterval = 5 * 60

    /// Percent lost per hour over the unplugged stretches, or nil when there is less than 10 minutes of unplugged time to judge by.
    static func drainPerHour(_ samples: [BatterySample]) -> Double? {
        var lost = 0.0
        var hours = 0.0
        for (a, b) in zip(samples, samples.dropFirst()) where !a.plugged && !b.plugged && b.time > a.time {
            lost += Double(a.level - b.level)
            hours += b.time.timeIntervalSince(a.time) / 3600
        }
        return hours >= 10.0 / 60 ? lost / hours : nil
    }

    /// "Battery: 3.2% per hour over 4.5 h unplugged", or why there is no number yet.
    static func summary(_ samples: [BatterySample]) -> String {
        var unplugged = 0.0
        for (a, b) in zip(samples, samples.dropFirst()) where !a.plugged && !b.plugged && b.time > a.time { unplugged += b.time.timeIntervalSince(a.time) / 3600 }
        guard let rate = drainPerHour(samples) else { return "Battery: needs 10 minutes unplugged" }
        return String(format: "Battery: %.1f%% per hour over %.1f h unplugged", rate, unplugged)
    }
}
