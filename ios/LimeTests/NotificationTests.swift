import XCTest
@testable import Lime

@MainActor
final class FakeCenter: LocalNotificationCenter, ArrivalFeedback {
    var status: NotificationAuthorization = .authorized
    var grants = true
    private(set) var scheduled: [NotificationContent] = []
    private(set) var badge: Int?
    private(set) var cleared: [String] = []
    private(set) var sounds = 0
    private(set) var ticks = 0

    func authorization() async -> NotificationAuthorization { status }
    func requestAuthorization() async -> Bool { status = grants ? .authorized : .denied; return grants }
    func schedule(_ content: NotificationContent) async { scheduled.append(content) }
    func setBadge(_ count: Int) async { badge = count }
    func clearDelivered(conversationID: String) async { cleared.append(conversationID) }
    func playSound() { sounds += 1 }
    func tick() { ticks += 1 }
}

@MainActor
final class NotificationTests: XCTestCase {
    private func suite() -> UserDefaults {
        let name = "lime.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func message(_ id: String = "m1", chat: String = "dm:lee", text: String = "Can we plan the lesson?", root: String? = nil,
                         group: Bool = false, request: Bool = false) -> IncomingMessage {
        IncomingMessage(id: id, conversationID: chat, conversationTitle: group ? "Staff" : "Lee Wong", senderID: "lee", senderName: "Lee Wong",
                        text: text, threadRoot: root, isGroup: group, isRequest: request, date: Date(timeIntervalSince1970: 1_000))
    }

    // MARK: Settings

    func testDefaultsAreOnNameAndMessageAndTheSystemSound() {
        let settings = NotificationSettings(defaults: suite())
        XCTAssertTrue(settings.enabled)
        XCTAssertEqual(settings.preview, .nameAndMessage, "N2 = A")
        XCTAssertEqual(settings.sound, .systemDefault)
        XCTAssertEqual(NotificationSound.allCases, [.systemDefault, .none], "no Lime chime until the file exists")
        XCTAssertFalse(settings.explainerDismissed)
    }

    func testChoicesSurviveARelaunchAndSigningOutForgetsThem() {
        let defaults = suite()
        let first = NotificationSettings(defaults: defaults)
        first.enabled = false; first.preview = .nameOnly; first.sound = .none; first.explainerDismissed = true
        first.mute("dm:lee", for: .always)
        let second = NotificationSettings(defaults: defaults)
        XCTAssertFalse(second.enabled)
        XCTAssertEqual(second.preview, .nameOnly)
        XCTAssertEqual(second.sound, NotificationSound.none)
        XCTAssertTrue(second.explainerDismissed)
        XCTAssertTrue(second.isMuted("dm:lee"))
        second.reset()
        XCTAssertTrue(NotificationSettings(defaults: defaults).enabled)
        XCTAssertFalse(NotificationSettings(defaults: defaults).isMuted("dm:lee"))
    }

    func testMuteDurationsEndAndAlwaysNeverDoes() {
        let settings = NotificationSettings(defaults: suite())
        let now = Date(timeIntervalSince1970: 10_000)
        settings.mute("a", for: .hour, now: now)
        settings.mute("b", for: .eightHours, now: now)
        settings.mute("c", for: .week, now: now)
        settings.mute("d", for: .always, now: now)
        XCTAssertTrue(settings.isMuted("a", now: now.addingTimeInterval(3_599)))
        XCTAssertFalse(settings.isMuted("a", now: now.addingTimeInterval(3_601)), "1 hour is over")
        XCTAssertTrue(settings.isMuted("b", now: now.addingTimeInterval(7 * 3_600)))
        XCTAssertFalse(settings.isMuted("b", now: now.addingTimeInterval(8 * 3_600 + 1)))
        XCTAssertTrue(settings.isMuted("c", now: now.addingTimeInterval(6 * 86_400)))
        XCTAssertFalse(settings.isMuted("c", now: now.addingTimeInterval(7 * 86_400 + 1)))
        XCTAssertTrue(settings.isMuted("d", now: now.addingTimeInterval(10 * 365 * 86_400)))
        XCTAssertEqual(settings.activeMutes(now: now.addingTimeInterval(3_601)).map(\.conversationID), ["b", "c", "d"], "soonest end first, always last")
        settings.pruneEndedMutes(now: now.addingTimeInterval(9 * 86_400))
        XCTAssertEqual(settings.activeMutes(now: now.addingTimeInterval(9 * 86_400)).map(\.conversationID), ["d"])
        settings.unmute("d")
        XCTAssertFalse(settings.isMuted("d", now: now))
        XCTAssertEqual(MuteDuration.allCases.map(\.title), ["For 1 hour", "For 8 hours", "For 1 week", "Always"])
    }

    // MARK: How an arrival is announced

    private func how(_ m: IncomingMessage, enabled: Bool = true, muted: Bool = false, sound: NotificationSound = .systemDefault,
                     active: Bool = true, viewing: ViewingTarget? = nil) -> Presentation {
        NotificationPolicy.presentation(for: m, enabled: enabled, muted: muted, sound: sound, appActive: active, viewing: viewing)
    }

    func testOffOrMutedMeansNothing() {
        XCTAssertEqual(how(message(), enabled: false), .none)
        XCTAssertEqual(how(message(), muted: true), .none)
        XCTAssertEqual(how(message(), muted: true, active: false), .none, "muted in the background too")
    }

    func testAnotherChatWhileOpenIsABannerAndTheOneYouAreInOnlyTicks() {
        XCTAssertEqual(how(message(chat: "dm:lee"), viewing: ViewingTarget(conversationID: "dm:sam")), .banner(sound: true))
        XCTAssertEqual(how(message(chat: "dm:lee"), viewing: nil), .banner(sound: true), "on Messages")
        XCTAssertEqual(how(message(chat: "dm:lee"), viewing: ViewingTarget(conversationID: "dm:lee")), .tick, "nothing plays in the chat you are viewing")
    }

    func testARepliesTickOnlyHappensInItsOwnThread() {
        let reply = message(root: "r1")
        XCTAssertEqual(how(reply, viewing: ViewingTarget(conversationID: "dm:lee", threadRoot: "r1")), .tick)
        XCTAssertEqual(how(reply, viewing: ViewingTarget(conversationID: "dm:lee")), .banner(sound: true), "the chat is open but the thread is not")
        XCTAssertEqual(how(reply, viewing: ViewingTarget(conversationID: "dm:lee", threadRoot: "other")), .banner(sound: true))
        XCTAssertEqual(how(message(), viewing: ViewingTarget(conversationID: "dm:lee", threadRoot: "r1")), .banner(sound: true), "a timeline message while a thread is open")
    }

    func testTheBackgroundMakesALocalNotificationAndTheSoundSettingIsHonoured() {
        XCTAssertEqual(how(message(), active: false), .local(sound: true))
        XCTAssertEqual(how(message(), sound: .none, active: false), .local(sound: false))
        XCTAssertEqual(how(message(), sound: .none), .banner(sound: false))
    }

    // MARK: What it says

    func testPreviewChoicesAndGroupingByChat() {
        let m = message(text: "Can we plan the lesson?")
        let full = NotificationPolicy.content(for: m, preview: .nameAndMessage, sound: true)
        XCTAssertEqual(full.title, "Lee Wong")
        XCTAssertEqual(full.body, "Can we plan the lesson?")
        XCTAssertEqual(full.threadIdentifier, "dm:lee", "grouped by conversation")
        XCTAssertTrue(full.sound)
        let nameOnly = NotificationPolicy.content(for: m, preview: .nameOnly, sound: false)
        XCTAssertEqual(nameOnly.title, "Lee Wong"); XCTAssertEqual(nameOnly.body, "New message"); XCTAssertFalse(nameOnly.sound)
        let hidden = NotificationPolicy.content(for: m, preview: .hidden, sound: true)
        XCTAssertEqual(hidden.title, "Lime"); XCTAssertEqual(hidden.body, "New message")
        XCTAssertFalse((hidden.title + hidden.body).contains("Lee"), "no name, no words")
    }

    func testGroupsNameTheSenderRepliesSayTheyAreAndTheTapKnowsTheThread() {
        let group = NotificationPolicy.content(for: message(group: true), preview: .nameAndMessage, sound: true)
        XCTAssertEqual(group.title, "Staff"); XCTAssertEqual(group.body, "Lee Wong: Can we plan the lesson?")
        let reply = NotificationPolicy.content(for: message(root: "r1"), preview: .nameAndMessage, sound: true)
        XCTAssertEqual(reply.body, "Replied in a thread: Can we plan the lesson?")
        XCTAssertEqual(reply.threadRoot, "r1", "tapping it opens the thread")
        XCTAssertEqual(NotificationPolicy.content(for: message(root: "r1"), preview: .nameOnly, sound: true).body, "New reply")
    }

    func testARequestNeverShowsItsWordsWhateverThePreview() {
        for preview in NotificationPreview.allCases {
            let content = NotificationPolicy.content(for: message(text: "secret words", request: true), preview: preview, sound: true)
            XCTAssertFalse(content.body.contains("secret"), "\(preview)")
            XCTAssertEqual(content.body, "Wants to message you")
        }
    }

    func testLongMessagesAreCutToOneLine() {
        let long = String(repeating: "word ", count: 80)
        let body = NotificationPolicy.content(for: message(text: long), preview: .nameAndMessage, sound: true).body
        XCTAssertLessThanOrEqual(body.count, 141)
        XCTAssertTrue(body.hasSuffix("…"))
        XCTAssertEqual(NotificationPolicy.shortened("a\n\nb   c"), "a b c")
    }

    // MARK: Spotting arrivals

    func testTheFirstLookOnlyLearnsAndLaterLooksFindWhatIsNew() {
        var detector = ArrivalDetector()
        let old = [message("a"), message("b")]
        XCTAssertTrue(detector.arrivals(among: old).isEmpty, "opening the app does not announce history")
        XCTAssertEqual(detector.arrivals(among: old).count, 0)
        let fresh = old + [message("c")]
        XCTAssertEqual(detector.arrivals(among: fresh).map(\.id), ["c"])
        XCTAssertTrue(detector.arrivals(among: fresh).isEmpty, "announced once")
        detector.reset()
        XCTAssertTrue(detector.arrivals(among: fresh).isEmpty, "after signing out it learns again")
    }

    // MARK: The coordinator

    private func coordinator(_ center: FakeCenter = FakeCenter(), enabled: Bool = true) -> (NotificationCoordinator, FakeCenter) {
        let settings = NotificationSettings(defaults: suite())
        settings.enabled = enabled
        return (NotificationCoordinator(settings: settings, center: center, feedback: center), center)
    }

    func testABannerShowsTheNewestAndPlaysOneSound() async {
        let (notifications, center) = coordinator()
        await notifications.refreshAuthorization()
        await notifications.announce([message("a"), message("b", text: "Newest one")])
        XCTAssertEqual(notifications.banner?.content.body, "Newest one")
        XCTAssertEqual(center.sounds, 1, "one sound for a batch")
        XCTAssertTrue(center.scheduled.isEmpty, "no system notification while Lime is open")
        notifications.dismissBanner()
        XCTAssertNil(notifications.banner)
    }

    func testTheChatOnScreenOnlyTicks() async {
        let (notifications, center) = coordinator()
        notifications.viewing = ViewingTarget(conversationID: "dm:lee")
        await notifications.announce([message()])
        XCTAssertNil(notifications.banner)
        XCTAssertEqual(center.ticks, 1)
        XCTAssertEqual(center.sounds, 0)
    }

    func testTheSilentSettingMakesABannerWithNoSound() async {
        let (notifications, center) = coordinator()
        notifications.settings.sound = .none
        await notifications.announce([message()])
        XCTAssertNotNil(notifications.banner)
        XCTAssertEqual(center.sounds, 0)
    }

    func testTheBackgroundSchedulesLocalNotificationsOnlyWhenIosAllowsThem() async {
        let (notifications, center) = coordinator()
        notifications.isActive = false
        await notifications.refreshAuthorization()
        await notifications.announce([message("a"), message("b", chat: "dm:sam")])
        XCTAssertEqual(center.scheduled.map(\.threadIdentifier), ["dm:lee", "dm:sam"], "one per message, grouped by chat")
        XCTAssertNil(notifications.banner)

        let (denied, deniedCenter) = coordinator({ let c = FakeCenter(); c.status = .denied; return c }())
        denied.isActive = false
        await denied.refreshAuthorization()
        await denied.announce([message()])
        XCTAssertTrue(deniedCenter.scheduled.isEmpty, "refused in iOS Settings: nothing is posted")
    }

    func testMutedAndOffAnnounceNothingAndAMuteEndsOnItsOwn() async {
        let (notifications, center) = coordinator()
        notifications.settings.mute("dm:lee", for: .hour)
        await notifications.announce([message()])
        XCTAssertNil(notifications.banner)
        XCTAssertEqual(notifications.log, [.none])
        await notifications.announce([message("later")], now: Date().addingTimeInterval(7_200))
        XCTAssertNotNil(notifications.banner, "the hour is over")
        let (off, _) = coordinator(enabled: false)
        await off.announce([message()])
        XCTAssertNil(off.banner)
        XCTAssertEqual(center.ticks, 0)
    }

    func testTappingABannerOrANotificationOpensTheChatAndThread() async {
        let (notifications, _) = coordinator()
        var opened: [(String, String?)] = []
        notifications.onOpen = { opened.append(($0, $1)) }
        await notifications.announce([message(root: "r1")])
        notifications.openBanner()
        XCTAssertNil(notifications.banner)
        XCTAssertEqual(opened.first?.0, "dm:lee"); XCTAssertEqual(opened.first?.1, "r1")
        notifications.open(conversationID: "dm:sam", threadRoot: nil)
        XCTAssertEqual(opened.last?.0, "dm:sam")
    }

    func testTheBadgeIsTheUnreadChatsAndOffWhenNotificationsAreOffOrRefused() async {
        let (notifications, center) = coordinator()
        await notifications.refreshAuthorization()
        await notifications.updateBadge(unreadChats: 3)
        XCTAssertEqual(center.badge, 3)
        notifications.settings.enabled = false
        await notifications.updateBadge(unreadChats: 3)
        XCTAssertEqual(center.badge, 0)
        await notifications.chatOpened("dm:lee")
        XCTAssertEqual(center.cleared, ["dm:lee"])
    }

    func testTheExplainerComesOnceAndNotNowIsRespected() async {
        let center = FakeCenter(); center.status = .notDetermined
        let (notifications, _) = coordinator(center)
        await notifications.refreshAuthorization()
        XCTAssertTrue(notifications.shouldExplain)
        notifications.settings.explainerDismissed = true
        XCTAssertFalse(notifications.shouldExplain, "Not now: not asked again by itself")
        let granted = await notifications.requestAuthorization()
        XCTAssertTrue(granted)
        XCTAssertEqual(notifications.authorization, .authorized)

        let refused = FakeCenter(); refused.status = .notDetermined; refused.grants = false
        let (other, _) = coordinator(refused)
        let ok = await other.requestAuthorization()
        XCTAssertFalse(ok)
        XCTAssertEqual(other.authorization, .denied)
    }

    func testMuteTextSaysWhenItEnds() {
        XCTAssertEqual(MuteText.until(.distantFuture), "Muted always")
        let now = Date()
        XCTAssertTrue(MuteText.until(now.addingTimeInterval(60), now: now).hasPrefix("Muted until"))
    }
}
