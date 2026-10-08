#if DEBUG
import CryptoKit
import Foundation
import Observation
import UIKit

/// LIME-103b: the unattended "leave it on the table" test. One phone is the **sender**: every 5 minutes it makes
/// a signed 4 KB blob (and a 32 KB one every 30 minutes) and delivers it as soon as a link exists, holding a queue
/// of the ones not yet acknowledged. The other is the **receiver**: it just sits, logging each arrival, its phase
/// (locked, in the background, picked up) and its battery. Both keep a log and show a morning summary.
@MainActor
@Observable
final class NearbyAutoTest {
    static let shared = NearbyAutoTest()

    enum Role: String, CaseIterable, Identifiable {
        case sender, receiver
        var id: String { rawValue }
        var title: String { self == .sender ? "Sender" : "Receiver" }
    }

    /// The 2-minute force-quit check: the sender sends every 15 seconds for 4 minutes instead of every 5 minutes.
    var forceQuitCheck = false
    var role: Role = .receiver
    /// Sender: keep the screen on (the sender stays awake and open, so something is always sending; the receiver is the idle one).
    var keepAwake = true
    private(set) var running = false
    private(set) var summary: [String] = []

    private struct Item {
        let key: String
        let tick: UInt32
        let size: Int
        let scheduled: Date
        var data: Data
        var created = Date()
        var lastSentAt: Date?
        var attempts = 0
        var acked = false
    }

    @ObservationIgnored private var items: [Item] = []
    @ObservationIgnored private var runStart = Date()
    @ObservationIgnored private var nextTick: UInt32 = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var wakeCount = 0
    @ObservationIgnored private var lastWakeLog = Date.distantPast
    @ObservationIgnored private var lastBattery = Date.distantPast
    @ObservationIgnored private var lastStep = Date.distantPast
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var test: NearbyTest { NearbyTest.shared }
    private var transport: NearbyTransport { NearbyTest.shared.transport }
    private var log: NearbyLog { NearbyTest.shared.log }

    private let limitHours = 12.0
    private let resendAfter: TimeInterval = 90

    private enum Keys {
        static let role = "lime.nearby.auto.role"
        static let running = "lime.nearby.auto.running"
        static let runStart = "lime.nearby.auto.runStart"
        static let nextTick = "lime.nearby.auto.nextTick"
        static let forceQuit = "lime.nearby.auto.forceQuit"
        static let keepAwake = "lime.nearby.auto.keepAwake"
    }

    private init() {
        role = UserDefaults.standard.string(forKey: Keys.role).flatMap(Role.init) ?? .receiver
    }

    // MARK: Start and stop

    /// `resuming`: iOS ended the app and started it again for Bluetooth (or it was opened again after a force-quit):
    /// carry on with the same schedule, in a new log.
    func start(resuming: Bool = false) {
        guard !running else { return }
        let defaults = UserDefaults.standard
        defaults.set(role.rawValue, forKey: Keys.role)
        running = true
        if resuming, defaults.double(forKey: Keys.runStart) > 0 {
            runStart = Date(timeIntervalSince1970: defaults.double(forKey: Keys.runStart))
            nextTick = UInt32(defaults.integer(forKey: Keys.nextTick))
        } else {
            runStart = Date(); nextTick = 0
            defaults.set(runStart.timeIntervalSince1970, forKey: Keys.runStart)
            defaults.set(0, forKey: Keys.nextTick)
        }
        defaults.set(true, forKey: Keys.running)
        defaults.set(forceQuitCheck, forKey: Keys.forceQuit)
        defaults.set(keepAwake, forKey: Keys.keepAwake)
        items = []; wakeCount = 0; lastBattery = .distantPast
        let transport = transport
        transport.mode = .both
        transport.sendOnConnect = false
        transport.acknowledgesBlobs = role == .receiver
        let label = "auto-\(role.rawValue)\(forceQuitCheck ? "-forcequit" : "")"
        test.label = label
        test.start(relabel: resuming ? label + "-relaunched" : nil)
        transport.onWake = { [weak self] source in self?.woke(source) }
        transport.onLinksChanged = { [weak self] in self?.drain() }
        transport.onAck = { [weak self] id in self?.acked(id) }
        transport.onBlob = { [weak self] id, parsed, link, first, ms in self?.arrived(id, parsed, link, first, ms) }
        if role == .sender {
            UIApplication.shared.isIdleTimerDisabled = keepAwake
            log.record("auto_start", ["role": role.rawValue, "forceQuitCheck": forceQuitCheck, "keepAwake": keepAwake,
                                       "tickSeconds": interval, "limitHours": limitHours])
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.step() } }
            step()
        } else {
            log.record("auto_start", ["role": role.rawValue, "forceQuitCheck": forceQuitCheck])
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.step() } }
            sampleBattery()
        }
        refreshSummary()
    }

    /// At launch: if an auto test was running when the app ended, carry on.
    static func resumeIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Keys.running) else { return }
        let test = NearbyAutoTest.shared
        test.role = defaults.string(forKey: Keys.role).flatMap(Role.init) ?? .receiver
        test.forceQuitCheck = defaults.bool(forKey: Keys.forceQuit)
        test.keepAwake = defaults.object(forKey: Keys.keepAwake) as? Bool ?? true
        test.start(resuming: true)
    }

    func stop() {
        guard running else { return }
        UserDefaults.standard.set(false, forKey: Keys.running)
        running = false
        timer?.invalidate(); timer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        endBackgroundTask()
        test.stop()
        transport.onWake = nil; transport.onLinksChanged = nil; transport.onAck = nil; transport.onBlob = nil
        transport.acknowledgesBlobs = false
        refreshSummary()
    }

    /// The tick length: 5 minutes, or 15 seconds in the force-quit check.
    private var interval: Double { forceQuitCheck ? 15 : NearbySummary.tickSeconds }
    private var runLimit: Double { forceQuitCheck ? 240 : limitHours * 3600 }

    // MARK: The sender

    /// Makes every blob that is due (catching up if iOS gave the app no time for a while), then delivers.
    private func step() {
        guard running else { return }
        let now = Date()
        lastStep = now
        if role == .sender {
            let elapsed = now.timeIntervalSince(runStart)
            if elapsed > runLimit + interval { log.record("auto_done", ["reason": "time limit"]); stop(); return }
            let due = forceQuitCheck ? min(Int(elapsed / interval) + 1, Int(runLimit / interval)) : NearbySummary.ticksDue(runStart: runStart.timeIntervalSince1970, now: now.timeIntervalSince1970, limitHours: limitHours)
            while Int(nextTick) < due {
                let tick = nextTick
                nextTick += 1
                UserDefaults.standard.set(Int(nextTick), forKey: Keys.nextTick)
                let scheduled = runStart.addingTimeInterval(Double(tick) * interval)
                for size in (forceQuitCheck ? [200] : NearbySummary.sizes(tick: tick)) {
                    let blob = NearbyBlob.make(bodySize: size, key: transport.signingKey, now: now, runStart: runStart, tick: tick)
                    let key = "\(tick)-\(size)"
                    items.append(Item(key: key, tick: tick, size: size, scheduled: scheduled, data: blob, created: now))
                    log.record("auto_created", ["key": key, "tick": Int(tick), "size": size, "scheduledMs": Int(scheduled.timeIntervalSince1970 * 1000),
                                                 "lateMs": Int(now.timeIntervalSince(scheduled) * 1000)])
                }
            }
            drain()
        } else {
            if now.timeIntervalSince(lastBattery) >= 900 { sampleBattery() }
        }
    }

    /// Sends every unacknowledged blob when a link exists (and again if no ack came back in a while).
    private func drain() {
        guard running, role == .sender, transport.hasSendableLink else { return }
        let now = Date()
        for index in items.indices where !items[index].acked {
            if let last = items[index].lastSentAt, now.timeIntervalSince(last) < resendAfter { continue }
            let used = transport.sendPrepared(items[index].data, bodySize: items[index].size)
            guard used > 0 else { return }
            items[index].attempts += 1
            items[index].lastSentAt = now
            log.record("auto_sent", ["key": items[index].key, "attempt": items[index].attempts, "links": used,
                                      "lateMs": Int(now.timeIntervalSince(items[index].scheduled) * 1000)])
        }
    }

    private func acked(_ id: String) {
        guard role == .sender, let index = items.firstIndex(where: { NearbyBlob.id(of: $0.data) == id }) else { return }
        guard !items[index].acked else { return }
        items[index].acked = true
        let now = Date()
        log.record("auto_ack", ["key": items[index].key, "attempts": items[index].attempts,
                                "roundTripMs": Int(now.timeIntervalSince(items[index].lastSentAt ?? now) * 1000),
                                "lateMs": Int(now.timeIntervalSince(items[index].scheduled) * 1000)])
    }

    // MARK: The receiver

    private func arrived(_ id: String, _ parsed: NearbyBlob.Parsed, _ link: NearbyLink, _ first: Bool, _ durationMs: Int) {
        guard role == .receiver, first, parsed.valid else { return }
        let scheduled = forceQuitCheck
            ? Double(parsed.runStartMs) / 1000 + Double(parsed.tick) * 15
            : NearbySummary.scheduledAt(runStart: Double(parsed.runStartMs) / 1000, tick: parsed.tick)
        log.record("auto_recv", ["blob": id, "tick": Int(parsed.tick), "size": parsed.bodySize, "runStartMs": Int(parsed.runStartMs),
                                 "transport": link.transport, "lateMs": Int(Date().timeIntervalSince1970 * 1000 - scheduled * 1000),
                                 // What the phone was doing when this arrived (an unlock while Lime sleeps is invisible to the app, this is not).
                                 "locked": !UIApplication.shared.isProtectedDataAvailable, "appState": Self.stateName(UIApplication.shared.applicationState)])
        if Date().timeIntervalSince(lastBattery) >= 900 { sampleBattery() }
    }

    private func sampleBattery() {
        lastBattery = Date()
        let b = NearbyLog.battery()
        log.record("battery", ["percent": b["percent"] ?? -1, "state": b["state"] ?? "unknown",
                               "locked": !UIApplication.shared.isProtectedDataAvailable, "appState": Self.stateName(UIApplication.shared.applicationState)])
    }

    private static func stateName(_ state: UIApplication.State) -> String {
        switch state {
        case .active: "active"
        case .inactive: "inactive"
        default: "background"
        }
    }

    // MARK: Wake-ups (iOS ran our code because of Bluetooth)

    private func woke(_ source: String) {
        guard running else { return }
        wakeCount += 1
        let now = Date()
        // One line a minute at most: the count says how many wakes it covers.
        if now.timeIntervalSince(lastWakeLog) >= 60 {
            lastWakeLog = now
            log.record("wake", ["source": source, "count": wakeCount])
            wakeCount = 0
        }
        // A wake in the background is a chance to catch up and deliver: keep the app alive for the few seconds it takes.
        if UIApplication.shared.applicationState != .active {
            beginBackgroundTask()
            if now.timeIntervalSince(lastStep) >= 5 { step() } else { drain() }
        } else {
            drain()
        }
    }

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "lime.nearby.auto") { [weak self] in
            MainActor.assumeIsolated { self?.endBackgroundTask() }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: The card

    /// Recomputes the card from the night's logs.
    func refreshSummary() {
        let events = Self.nightEvents(role: role, forceQuit: forceQuitCheck)
        summary = events.isEmpty ? [] : Self.lines(events, sender: role == .sender, forceQuit: forceQuitCheck)
    }

    /// Every log of this role from the same night, oldest first (a run that iOS restarted has a second file), as one list.
    static func nightEvents(role: Role, forceQuit: Bool, maxAge: TimeInterval = 16 * 3600) -> [NearbySummary.Event] {
        let prefix = "nearby-auto-\(role.rawValue)"
        let files = NearbyLog.savedRuns().filter { $0.lastPathComponent.hasPrefix(prefix) && $0.lastPathComponent.contains("forcequit") == forceQuit }
        guard let newest = files.first else { return [] }
        let newestTime = NearbySummary.events(in: newest).last.map(NearbySummary.epoch) ?? 0
        var merged: [NearbySummary.Event] = []
        for url in files.reversed() {
            let events = NearbySummary.events(in: url)
            guard let last = events.last.map(NearbySummary.epoch), newestTime - last <= maxAge else { continue }
            merged += merged.isEmpty ? events : events.filter { $0["kind"] as? String != "header" }
        }
        return merged
    }

    static func lines(_ events: [NearbySummary.Event], sender: Bool, forceQuit: Bool) -> [String] {
        if forceQuit { return sender ? NearbySummary.forceQuitSender(events) : NearbySummary.forceQuitReceiver(events) }
        return sender ? NearbySummary.senderLines(NearbySummary.sender(events)) : NearbySummary.receiverLines(NearbySummary.receiver(events))
    }

    /// The card of the newest night (after the app was closed and opened again), for either role.
    func summaryOfLatestRun() -> [String] {
        guard let url = NearbyLog.savedRuns().first(where: { $0.lastPathComponent.hasPrefix("nearby-auto-") }) else { return [] }
        let name = url.lastPathComponent
        let role: Role = name.hasPrefix("nearby-auto-sender") ? .sender : .receiver
        let forceQuit = name.contains("forcequit")
        let events = Self.nightEvents(role: role, forceQuit: forceQuit)
        return events.isEmpty ? [] : ["(\(role.title)\(forceQuit ? ", force-quit check" : ""))"] + Self.lines(events, sender: role == .sender, forceQuit: forceQuit)
    }
}
#endif
