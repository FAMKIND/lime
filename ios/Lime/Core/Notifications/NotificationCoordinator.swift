import Foundation
import Observation
import UIKit
import UserNotifications
import AudioToolbox

/// Whether iOS lets Lime post notifications.
enum NotificationAuthorization: Equatable, Sendable { case notDetermined, denied, authorized }

/// What the coordinator needs from iOS, so tests can stand in for it.
@MainActor
protocol LocalNotificationCenter: AnyObject {
    func authorization() async -> NotificationAuthorization
    func requestAuthorization() async -> Bool
    func schedule(_ content: NotificationContent) async
    func setBadge(_ count: Int) async
    func clearDelivered(conversationID: String) async
}

/// The in-app arrival feedback (sound and the subtle tick).
@MainActor
protocol ArrivalFeedback: AnyObject {
    func playSound()
    func tick()
}

/// A banner shown at the top while Lime is open.
struct IncomingBanner: Identifiable, Equatable, Sendable {
    let id: String
    let content: NotificationContent
    let sender: Person
}

/// Decides how each arriving message is announced, and holds the in-app banner. Everything the words
/// say is decrypted on this phone and stays on it: nothing here talks to a server.
@MainActor
@Observable
final class NotificationCoordinator {
    let settings: NotificationSettings
    private(set) var authorization: NotificationAuthorization = .notDetermined
    private(set) var banner: IncomingBanner?
    /// True while Lime is the app on screen.
    var isActive = true
    /// The chat or thread on screen, so it only ticks.
    var viewing: ViewingTarget?
    /// Opens a chat (or a thread in it): a tapped banner or notification.
    var onOpen: (String, String?) -> Void = { _, _ in }
    /// What each arrival turned into, newest last (tests and the debug screens read it).
    private(set) var log: [Presentation] = []

    /// Whether I am quiet at a moment (Do not disturb, quiet hours, or outside work hours).
    @ObservationIgnored var isQuiet: (Date) -> Bool = { _ in false }
    /// Messages that arrived while I was quiet, waiting for a summary.
    private(set) var held: [IncomingMessage] = []

    @ObservationIgnored private let center: LocalNotificationCenter
    @ObservationIgnored private let feedback: ArrivalFeedback

    init(settings: NotificationSettings = NotificationSettings(), center: LocalNotificationCenter, feedback: ArrivalFeedback) {
        self.settings = settings
        self.center = center
        self.feedback = feedback
    }

    func refreshAuthorization() async { authorization = await center.authorization() }

    /// The explainer's "Turn on notifications": the system's own prompt. True when allowed.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = await center.requestAuthorization()
        await refreshAuthorization()
        if granted { settings.enabled = true }
        return granted
    }

    /// Show the explainer by itself once: never asked, not dismissed, notifications on.
    var shouldExplain: Bool { authorization == .notDetermined && !settings.explainerDismissed }

    /// Announce what just arrived: a banner (newest one) and one sound, a tick, or local notifications.
    func announce(_ arrivals: [IncomingMessage], now: Date = Date()) async {
        settings.pruneEndedMutes(now: now)
        var bannerFor: IncomingMessage?
        var bannerSound = false
        var ticked = false
        for message in arrivals {
            let how = NotificationPolicy.presentation(
                for: message, enabled: settings.enabled, muted: settings.isMuted(message.conversationID, now: now),
                sound: settings.sound, appActive: isActive, viewing: viewing, quiet: isQuiet(now))
            log.append(how)
            switch how {
            case .none: break
            case .held: if !message.isRequest { held.append(message) }
            case .tick: ticked = true
            case .banner(let sound): bannerFor = message; bannerSound = bannerSound || sound
            case .local(let sound):
                guard authorization == .authorized else { continue }
                await center.schedule(NotificationPolicy.content(for: message, preview: settings.preview, sound: sound))
            }
        }
        if let message = bannerFor {
            banner = IncomingBanner(id: message.id, content: NotificationPolicy.content(for: message, preview: settings.preview, sound: bannerSound),
                                    sender: Person(id: message.senderID, name: message.senderName))
            if bannerSound { feedback.playSound() }
        } else if ticked {
            feedback.tick()
        }
    }

    /// When the quiet ends, one summary of what arrived in the meantime ("3 new messages while you were away").
    func releaseHeld(now: Date = Date()) async {
        guard !held.isEmpty, !isQuiet(now) else { return }
        let messages = held
        held = []
        let chats = Set(messages.map(\.conversationID)).count
        let words = messages.count == 1 ? "1 new message" : "\(messages.count) new messages"
        let body = chats == 1 ? "\(words) from \(messages[0].conversationTitle)" : "\(words) in \(chats) chats"
        let last = messages[messages.count - 1]
        let content = NotificationContent(title: "While you were away", body: body, threadIdentifier: "summary", conversationID: last.conversationID,
                                          threadRoot: nil, messageID: "summary-\(last.id)", sound: false)
        if isActive {
            banner = IncomingBanner(id: content.messageID, content: content, sender: Person(id: "lime", name: "Lime"))
        } else if authorization == .authorized, settings.enabled {
            await center.schedule(content)
        }
    }

    func dismissBanner() { banner = nil }

    /// The banner was tapped.
    func openBanner() {
        guard let banner else { return }
        self.banner = nil
        onOpen(banner.content.conversationID, banner.content.threadRoot)
    }

    /// A notification was tapped.
    func open(conversationID: String, threadRoot: String?) { onOpen(conversationID, threadRoot) }

    /// The app icon's number: chats with something unread (cleared when there is nothing).
    func updateBadge(unreadChats: Int) async {
        await center.setBadge(authorization == .authorized && settings.enabled ? unreadChats : 0)
    }

    /// A chat was opened: its delivered notifications are no longer needed.
    func chatOpened(_ conversationID: String) async { await center.clearDelivered(conversationID: conversationID) }
}

// MARK: The real iOS pieces

/// `UNUserNotificationCenter`: permission, local notifications grouped by chat, the badge.
@MainActor
final class SystemNotifications: NSObject, LocalNotificationCenter, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    /// Set by the app: a tapped notification opens its chat (and thread).
    var onTap: (String, String?) -> Void = { _, _ in }

    override init() {
        super.init()
        center.delegate = self
    }

    func authorization() async -> NotificationAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .authorized
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func schedule(_ content: NotificationContent) async {
        let item = UNMutableNotificationContent()
        item.title = content.title
        item.body = content.body
        item.threadIdentifier = content.threadIdentifier
        item.sound = content.sound ? .default : nil
        item.userInfo = ["conversation": content.conversationID, "thread": content.threadRoot ?? ""]
        let request = UNNotificationRequest(identifier: content.messageID, content: item, trigger: nil)
        try? await center.add(request)
    }

    func setBadge(_ count: Int) async { try? await center.setBadgeCount(count) }

    func clearDelivered(conversationID: String) async {
        let delivered = await center.deliveredNotifications()
        let ids = delivered.filter { $0.request.content.threadIdentifier == conversationID }.map(\.request.identifier)
        if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
    }

    // A notification is never shown by iOS while Lime is open: Lime shows its own banner.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [] }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let conversation = info["conversation"] as? String else { return }
        let thread = (info["thread"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        await MainActor.run { self.onTap(conversation, thread) }
    }
}

/// The in-app sound (the system's, which follows the silent switch) and a soft haptic tick.
@MainActor
final class SystemArrivalFeedback: ArrivalFeedback {
    /// The system's "received message" tone.
    private static let systemMessageSound: SystemSoundID = 1007

    func playSound() { AudioServicesPlaySystemSound(Self.systemMessageSound) }

    func tick() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
}

#if DEBUG
/// Debug builds only (UI tests and screenshots): no system prompts, a chosen permission state.
@MainActor
final class DemoNotifications: LocalNotificationCenter, ArrivalFeedback {
    private(set) var status: NotificationAuthorization
    private(set) var scheduled: [NotificationContent] = []
    private(set) var badge = 0
    private(set) var sounds = 0
    private(set) var ticks = 0

    init(status: NotificationAuthorization) { self.status = status }

    func authorization() async -> NotificationAuthorization { status }
    func requestAuthorization() async -> Bool { status = .authorized; return true }
    func schedule(_ content: NotificationContent) async { scheduled.append(content) }
    func setBadge(_ count: Int) async { badge = count }
    func clearDelivered(conversationID: String) async { scheduled.removeAll { $0.conversationID == conversationID } }
    func playSound() { sounds += 1 }
    func tick() { ticks += 1 }
}
#endif
