import Foundation

/// Nearby mode (LIME-143): keeps lime awake so phones that meet pass messages in seconds, not on the next wake. The rules and the words; the
/// radios and the screen lock are in `MeshService` (Debug builds only for now).
enum NearbyMode {
    /// It turns itself off after this long unless the person renews it.
    static let limit: TimeInterval = 2 * 60 * 60

    static let statusLine = "Nearby mode on \u{00B7} keeps lime awake \u{00B7} uses more battery"
    static let plugInHint = "Keep it plugged in and lime open."
    static let settingTitle = "Nearby mode"
    static let settingFootnote = "Keeps lime awake to reach people nearby. Off after 2 hours."
    static let offerTitle = "No signal. Keep lime awake to reach people nearby?"
    static let offerButton = "Turn on Nearby mode"
    static let offerNotNow = "Not now"
    static let expiredTitle = "Nearby mode turned off after 2 hours"
    static let expiredMessage = "Turn it on again for 2 hours?"

    /// When it is on and until when; `nil` is off.
    static func isOn(until: Date?, now: Date) -> Bool { until.map { $0 > now } ?? false }

    /// The one-time offer in a chat: a message is "Waiting for signal", the mesh is on, no phone is in range, Nearby mode is off, and the
    /// person has not been offered it before.
    static func shouldOffer(waitingInChat: Bool, meshOn: Bool, phonesInRange: Int, nearbyOn: Bool, offeredBefore: Bool) -> Bool {
        waitingInChat && meshOn && phonesInRange == 0 && !nearbyOn && !offeredBefore
    }

    /// The screen stays awake only while nearby mode is on **and** lime is the app in front (iOS allows nothing more).
    static func keepsScreenAwake(nearbyOn: Bool, appActive: Bool) -> Bool { nearbyOn && appActive }
}
