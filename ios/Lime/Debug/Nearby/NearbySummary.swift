#if DEBUG
import Foundation

/// The morning summary: worked out from a run's own log events (so it survives the app being killed and
/// restarted), as pure functions so the arithmetic can be tested. LIME-103b.
enum NearbySummary {
    /// One blob per tick, 5 minutes apart; a 32 KB blob joins every 6th tick (every 30 minutes).
    static let tickSeconds: Double = 300
    static let bigEvery: UInt32 = 6
    /// A blob is a miss when it was not delivered within this long of its scheduled time.
    static let missSeconds: Double = 600

    typealias Event = [String: Any]

    static func epoch(_ e: Event) -> Double { (e["ms"] as? Double ?? Double(e["ms"] as? Int ?? 0)) / 1000 }
    private static func number(_ e: Event, _ key: String) -> Double? { (e[key] as? Double) ?? (e[key] as? Int).map(Double.init) }

    // MARK: Ticks

    /// How many ticks are due by `now` (tick 0 is due at the run's start).
    static func ticksDue(runStart: Double, now: Double, limitHours: Double = 12) -> Int {
        guard now >= runStart else { return 0 }
        let elapsed = min(now - runStart, limitHours * 3600)
        return Int(elapsed / tickSeconds) + 1
    }

    static func scheduledAt(runStart: Double, tick: UInt32) -> Double { runStart + Double(tick) * tickSeconds }

    /// The blobs a tick makes: 4 KB always, plus 32 KB on every 6th tick.
    static func sizes(tick: UInt32) -> [Int] { tick % bigEvery == 0 ? [4_096, 32_768] : [4_096] }

    // MARK: Time since

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) s" }
        if total < 3_600 { return "\(total / 60) min" }
        return "\(total / 3_600) h \((total % 3_600) / 60) m"
    }

    // MARK: Battery

    static func battery(_ events: [Event]) -> (start: Int?, end: Int?) {
        var levels: [Int] = []
        if let header = events.first, let b = header["battery"] as? [String: Any], let p = b["percent"] as? Int, p >= 0 { levels.append(p) }
        for e in events where e["kind"] as? String == "battery" { if let p = e["percent"] as? Int, p >= 0 { levels.append(p) } }
        if let last = events.last(where: { $0["kind"] as? String == "summary" }), let b = last["battery"] as? [String: Any], let p = b["percent"] as? Int, p >= 0 { levels.append(p) }
        return (levels.first, levels.last)
    }

    // MARK: Pickups and idle stretches (on the receiver)

    struct Stretch: Equatable {
        let start: Double
        let end: Double
        var seconds: Double { end - start }
    }

    /// Stretches in which the app was in the background or locked with nobody picking the phone up. A pickup is the app
    /// coming to the front or the phone unlocking. The run's last event closes a stretch that is still going.
    static func idleStretches(_ events: [Event]) -> [Stretch] {
        var stretches: [Stretch] = []
        var began: Double?
        for e in events where e["kind"] as? String == "app" {
            let at = epoch(e)
            switch e["phase"] as? String ?? "" {
            case "background", "locking": if began == nil { began = at }
            case "foreground", "active", "unlocked":
                if let start = began { stretches.append(Stretch(start: start, end: at)); began = nil }
            default: break
            }
        }
        if let start = began, let last = events.last.map(epoch), last > start { stretches.append(Stretch(start: start, end: last)) }
        return stretches
    }

    // MARK: The receiver's card

    struct Receiver: Equatable {
        var delivered = 0
        var expected = 0
        var longestGap: Double = 0
        var firstMissAfter: Double?
        var batteryStart: Int?
        var batteryEnd: Int?
        var pickups = 0
        var idleHours: Double = 0
        var idleDelivered = 0
        var idleExpected = 0
        var longestIdle: Double = 0
        var longestIdleDelivered = 0
        var longestIdleExpected = 0
        var runSeconds: Double = 0
        /// How each first arrival found the phone: locked, unlocked with Lime in the background (a pickup), or Lime in front.
        var deliveredLocked = 0
        var deliveredUnlockedBackground = 0
        var deliveredInFront = 0
        /// The longest run of back-to-back arrivals that all found the phone locked.
        var longestLockedRun = 0
        var longestLockedRunSeconds: Double = 0
    }

    static func receiver(_ events: [Event]) -> Receiver {
        var card = Receiver()
        let arrivals = events.filter { $0["kind"] as? String == "auto_recv" }
        guard let started = events.first(where: { $0["kind"] as? String == "started" }).map(epoch) else { return card }
        var seenKeys = Set<String>()
        var runStart: Double?
        var maxTick: UInt32 = 0
        var delivered: [(tick: UInt32, size: Int, at: Double)] = []
        for e in arrivals {
            guard let tick = number(e, "tick"), let size = number(e, "size"), let start = number(e, "runStartMs") else { continue }
            runStart = start / 1000
            maxTick = max(maxTick, UInt32(tick))
            if seenKeys.insert("\(Int(tick))-\(Int(size))").inserted { delivered.append((UInt32(tick), Int(size), epoch(e))) }
        }
        let battery = battery(events)
        card.batteryStart = battery.start; card.batteryEnd = battery.end
        card.delivered = delivered.count
        // How the phone was when each blob arrived, and the longest run of arrivals that were all while locked.
        var run: [Double] = []
        for e in arrivals {
            let locked = e["locked"] as? Bool ?? false
            if locked { card.deliveredLocked += 1; run.append(epoch(e)) }
            else {
                if e["appState"] as? String == "active" { card.deliveredInFront += 1 } else { card.deliveredUnlockedBackground += 1 }
                run = []
            }
            if run.count > card.longestLockedRun { card.longestLockedRun = run.count; card.longestLockedRunSeconds = (run.last ?? 0) - (run.first ?? 0) }
        }
        let last = events.last.map(epoch) ?? started
        card.runSeconds = last - started
        guard let runStart else { return card }
        // What should have arrived: every blob of every tick up to the newest tick seen.
        var expected: [(tick: UInt32, size: Int, due: Double)] = []
        for tick in 0...maxTick { for size in sizes(tick: tick) { expected.append((tick, size, scheduledAt(runStart: runStart, tick: tick))) } }
        card.expected = expected.count
        let arrivalTimes = delivered.map(\.at).sorted()
        for (a, b) in zip(arrivalTimes, arrivalTimes.dropFirst()) { card.longestGap = max(card.longestGap, b - a) }
        var firstMiss: Double?
        for item in expected {
            let got = delivered.first { $0.tick == item.tick && $0.size == item.size }
            if got == nil || got!.at - item.due > missSeconds { firstMiss = min(firstMiss ?? .infinity, item.due) }
        }
        card.firstMissAfter = firstMiss.map { $0 - runStart }
        // Pickups and the idle stretches.
        card.pickups = events.filter { ($0["kind"] as? String) == "app" && ["unlocked", "foreground"].contains($0["phase"] as? String ?? "") }.count
        for stretch in idleStretches(events) {
            card.idleHours += stretch.seconds / 3600
            let due = expected.filter { $0.due >= stretch.start && $0.due < stretch.end - 60 }
            let got = due.filter { item in delivered.contains { $0.tick == item.tick && $0.size == item.size && $0.at <= stretch.end } }
            card.idleExpected += due.count; card.idleDelivered += got.count
            if stretch.seconds > card.longestIdle { card.longestIdle = stretch.seconds; card.longestIdleExpected = due.count; card.longestIdleDelivered = got.count }
        }
        return card
    }

    static func receiverLines(_ card: Receiver) -> [String] {
        var lines = ["Received \(card.delivered) of \(card.expected) expected" + (card.expected == 0 ? "" : " · longest gap \(duration(card.longestGap))")]
        lines.append(card.firstMissAfter.map { "First miss after \(duration($0))" } ?? (card.expected == 0 ? "Nothing received yet" : "No misses"))
        lines.append("Longest idle stretch with no pickups: \(duration(card.longestIdle)), delivered \(card.longestIdleDelivered) of \(card.longestIdleExpected) in it")
        lines.append("All idle time: \(String(format: "%.1f", card.idleHours)) h, delivered \(card.idleDelivered) of \(card.idleExpected) · pickups \(card.pickups)")
        lines.append("Arrivals while locked: \(card.deliveredLocked) · unlocked, Lime behind another app: \(card.deliveredUnlockedBackground) · Lime in front: \(card.deliveredInFront)")
        lines.append("Longest run of arrivals all while locked: \(card.longestLockedRun) over \(duration(card.longestLockedRunSeconds))")
        if let a = card.batteryStart, let b = card.batteryEnd { lines.append("Battery \(a)% → \(b)%") }
        return lines
    }

    // MARK: The sender's card

    struct Sender: Equatable {
        var created = 0
        var sent = 0
        var delivered = 0
        var longestGap: Double = 0
        var firstMissAfter: Double?
        var wakeups = 0
        var longestQuiet: Double = 0
        var batteryStart: Int?
        var batteryEnd: Int?
        var runSeconds: Double = 0
    }

    static func sender(_ events: [Event]) -> Sender {
        var card = Sender()
        guard let started = events.first(where: { $0["kind"] as? String == "started" }).map(epoch) else { return card }
        var createdAt: [String: Double] = [:], scheduled: [String: Double] = [:]
        var sentIDs = Set<String>(), ackedAt: [String: Double] = [:]
        var wakes: [Double] = []
        for e in events {
            switch e["kind"] as? String ?? "" {
            case "auto_created":
                if let key = e["key"] as? String { createdAt[key] = epoch(e); scheduled[key] = (number(e, "scheduledMs") ?? 0) / 1000 }
            case "auto_sent": if let key = e["key"] as? String { sentIDs.insert(key) }
            case "auto_ack": if let key = e["key"] as? String, ackedAt[key] == nil { ackedAt[key] = epoch(e) }
            case "wake": wakes.append(epoch(e)); card.wakeups += Int(number(e, "count") ?? 1)
            default: break
            }
        }
        let battery = battery(events)
        card.batteryStart = battery.start; card.batteryEnd = battery.end
        card.created = createdAt.count; card.sent = sentIDs.count; card.delivered = ackedAt.count
        let times = ackedAt.values.sorted()
        for (a, b) in zip(times, times.dropFirst()) { card.longestGap = max(card.longestGap, b - a) }
        var firstMiss: Double?
        let now = events.last.map(epoch) ?? started
        for (key, due) in scheduled {
            let late = (ackedAt[key] ?? now) - due
            if (ackedAt[key] == nil && now - due > missSeconds) || (ackedAt[key] != nil && late > missSeconds) { firstMiss = min(firstMiss ?? .infinity, due) }
        }
        card.firstMissAfter = firstMiss.map { $0 - started }
        let marks = ([started] + wakes + [now]).sorted()
        for (a, b) in zip(marks, marks.dropFirst()) { card.longestQuiet = max(card.longestQuiet, b - a) }
        card.runSeconds = now - started
        return card
    }

    static func senderLines(_ card: Sender) -> [String] {
        var lines = ["Created \(card.created) · sent \(card.sent) · delivered \(card.delivered)" + (card.delivered > 1 ? " · longest gap \(duration(card.longestGap))" : "")]
        lines.append(card.firstMissAfter.map { "First miss after \(duration($0))" } ?? (card.created == 0 ? "Nothing sent yet" : "No misses"))
        lines.append("Bluetooth woke this phone \(card.wakeups) times · longest stretch without a wake \(duration(card.longestQuiet))")
        if let a = card.batteryStart, let b = card.batteryEnd { lines.append("Battery \(a)% → \(b)%") }
        return lines
    }

    // MARK: The force-quit check

    /// The sender's side: blobs sent every 15 seconds; the last ack marks when the receiver went away.
    static func forceQuitSender(_ events: [Event]) -> [String] {
        var created: [(key: String, at: Double)] = [], acks: [Double] = []
        var missing: [Double] = []
        for e in events {
            switch e["kind"] as? String ?? "" {
            case "auto_created": if let key = e["key"] as? String { created.append((key, epoch(e))) }
            case "auto_ack": acks.append(epoch(e))
            case "service_missing": missing.append(epoch(e))
            default: break
            }
        }
        guard let started = events.first(where: { $0["kind"] as? String == "started" }).map(epoch) else { return [] }
        guard let lastAck = acks.max() else { return ["Sent \(created.count), nothing acknowledged yet"] }
        let after = created.filter { $0.at > lastAck }
        let ackedAfter = acks.filter { $0 > lastAck }.count
        return ["Sent \(created.count) · acknowledged \(acks.count) · last ack \(duration(lastAck - started)) in",
                "Made after the last ack: \(after.count) · acknowledged after it: \(ackedAfter) (expected 0 once the receiver was quit)",
                "The Lime service was missing on the other phone \(missing.filter { $0 > lastAck }.count) times after that (expected: yes)"]
    }

    /// The receiver's side, after it was opened again: what arrived, and how late.
    static func forceQuitReceiver(_ events: [Event]) -> [String] {
        let arrivals = events.filter { $0["kind"] as? String == "auto_recv" }
        let late = arrivals.filter { (number($0, "lateMs") ?? 0) > 20_000 }
        let maxLate = arrivals.compactMap { number($0, "lateMs") }.max() ?? 0
        return ["Received \(arrivals.count) in this run · \(late.count) were scheduled while Lime was closed (the sender kept them queued)",
                arrivals.isEmpty ? "Nothing arrived." : "The latest was \(duration(maxLate / 1000)) after its scheduled time"]
    }

    // MARK: Reading a log back

    static func events(in url: URL) -> [Event] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? Event }
    }
}
#endif
