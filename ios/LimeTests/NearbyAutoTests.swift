#if DEBUG
import CryptoKit
import XCTest
@testable import Lime

/// LIME-103b: the schedule, the blob header, the log keys and the morning summary's arithmetic.
@MainActor
final class NearbyAutoTests: XCTestCase {
    private typealias Event = NearbySummary.Event

    // MARK: Schedule

    func testOneBlobPerFiveMinutesAndABigOneEveryThirtyAndAMissedStretchIsCaughtUp() {
        XCTAssertEqual(NearbySummary.ticksDue(runStart: 1_000, now: 999), 0)
        XCTAssertEqual(NearbySummary.ticksDue(runStart: 1_000, now: 1_000), 1, "tick 0 is due at the start")
        XCTAssertEqual(NearbySummary.ticksDue(runStart: 1_000, now: 1_299), 1)
        XCTAssertEqual(NearbySummary.ticksDue(runStart: 1_000, now: 1_300), 2)
        // iOS gave the app no time for 2 hours: all 25 ticks are due at once, to be made late.
        XCTAssertEqual(NearbySummary.ticksDue(runStart: 0, now: 2 * 3_600), 25)
        XCTAssertEqual(NearbySummary.ticksDue(runStart: 0, now: 20 * 3_600), 145, "stops at 12 hours: ticks 0 to 144")
        XCTAssertEqual(NearbySummary.sizes(tick: 0), [4_096, 32_768])
        XCTAssertEqual(NearbySummary.sizes(tick: 1), [4_096])
        XCTAssertEqual(NearbySummary.sizes(tick: 6), [4_096, 32_768], "every 30 minutes")
        XCTAssertEqual(NearbySummary.scheduledAt(runStart: 100, tick: 3), 1_000)
    }

    // MARK: The blob header and the ack

    func testTheBlobHeaderCarriesTheTickAndTheRunStartAndIsSigned() throws {
        let key = Curve25519.Signing.PrivateKey()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let blob = NearbyBlob.make(bodySize: 4_096, key: key, now: start.addingTimeInterval(900), runStart: start, tick: 3)
        XCTAssertEqual(blob.count, 4_096 + NearbyBlob.overhead)
        let parsed = try XCTUnwrap(NearbyBlob.parse(blob))
        XCTAssertTrue(parsed.valid)
        XCTAssertEqual(parsed.tick, 3)
        XCTAssertEqual(parsed.runStartMs, 1_700_000_000_000)
        XCTAssertEqual(parsed.sentAtMs, 1_700_000_900_000)
        var tampered = blob
        tampered[32 + 64 + 19] ^= 1 // the last byte of the tick
        XCTAssertEqual(NearbyBlob.parse(tampered)?.valid, false, "the tick is covered by the signature")
    }

    func testAnAckFrameCarriesABlobIdAndSurvivesChunking() {
        var reader = NearbyFrameReader()
        let stream = NearbyFrame.encode(.ack, Data("0123456789abcdef".utf8)) + NearbyFrame.encode(.hello, Data("t".utf8))
        var frames: [(NearbyFrame.Kind, Data)] = []
        for byte in stream { frames += reader.append(Data([byte])).map { ($0.0, $0.1) } }
        XCTAssertEqual(frames.map(\.0), [.ack, .hello])
        XCTAssertEqual(String(decoding: frames[0].1, as: UTF8.self), "0123456789abcdef")
    }

    // MARK: The log keys (LIME-103 lost durations by overwriting `ms`)

    func testALogFieldNeverOverwritesTheLogsOwnKeys() throws {
        let log = NearbyLog()
        log.begin(label: "keys", extra: [:])
        log.record("send_done", ["duration_ms": 1_234, "ms": 5, "kind": "x", "t": "y"])
        log.end(summary: [:])
        let url = try XCTUnwrap(log.fileURL)
        defer { try? FileManager.default.removeItem(at: url) }
        let line = try XCTUnwrap(NearbySummary.events(in: url).first { $0["kind"] as? String == "send_done" })
        XCTAssertEqual(line["duration_ms"] as? Int, 1_234, "the duration survives")
        XCTAssertGreaterThan(line["ms"] as? Int ?? 0, 1_700_000_000_000, "ms stays the epoch")
        XCTAssertEqual(line["x_ms"] as? Int, 5, "a colliding field is kept under another name")
        XCTAssertEqual(line["x_kind"] as? String, "x")
    }

    // MARK: The summary

    private func event(_ kind: String, at seconds: Double, _ fields: [String: Any] = [:]) -> Event {
        var e = fields
        e["kind"] = kind
        e["ms"] = Int((1_000_000 + seconds) * 1000)
        return e
    }

    private func receiverRun(arrivalsAt: [(tick: Int, seconds: Double)], phases: [(String, Double)], battery: (Int, Int) = (100, 90)) -> [Event] {
        var events: [Event] = [["kind": "header", "battery": ["percent": battery.0, "state": "unplugged"]], event("started", at: 0)]
        for (tick, at) in arrivalsAt {
            events.append(event("auto_recv", at: at, ["tick": tick, "size": 4_096, "runStartMs": 1_000_000_000, "blob": "b\(tick)"]))
            if tick % 6 == 0 { events.append(event("auto_recv", at: at, ["tick": tick, "size": 32_768, "runStartMs": 1_000_000_000, "blob": "c\(tick)"])) }
        }
        for (phase, at) in phases { events.append(event("app", at: at, ["phase": phase])) }
        events.append(event("summary", at: 4_000, ["battery": ["percent": battery.1, "state": "unplugged"]]))
        return events.sorted { NearbySummary.epoch($0) < NearbySummary.epoch($1) }
    }

    func testTheReceiverCardCountsDeliveredAgainstExpectedAndFindsTheFirstMiss() {
        // Ticks 0 to 5 arrive on time, except tick 3 (scheduled at 900 s), which never arrives.
        let events = receiverRun(arrivalsAt: [(0, 1), (1, 301), (2, 601), (4, 1_201), (5, 1_501)], phases: [])
        let card = NearbySummary.receiver(events)
        XCTAssertEqual(card.delivered, 6, "5 four-KB blobs and the tick-0 32 KB blob")
        XCTAssertEqual(card.expected, 7, "ticks 0 to 5: six 4 KB and one 32 KB")
        XCTAssertEqual(card.firstMissAfter, 900, "tick 3 was due at 900 s and never came")
        XCTAssertEqual(card.longestGap, 600, accuracy: 0.01, "between tick 2 and tick 4")
        XCTAssertEqual(card.batteryStart, 100); XCTAssertEqual(card.batteryEnd, 90)
        XCTAssertTrue(NearbySummary.receiverLines(card).joined().contains("Received 6 of 7"))
    }

    func testALateBlobIsAMissToo() {
        let events = receiverRun(arrivalsAt: [(0, 1), (1, 301), (2, 1_300)], phases: [])
        XCTAssertEqual(NearbySummary.receiver(events).firstMissAfter, 600, "tick 2 (due 600 s) came 700 s late")
        let onTime = receiverRun(arrivalsAt: [(0, 1), (1, 301), (2, 1_100)], phases: [])
        XCTAssertNil(NearbySummary.receiver(onTime).firstMissAfter, "500 s late is inside the 10 minutes")
    }

    func testIdleStretchesRunBetweenPickupsAndPickupsAreNotFailures() {
        // Locked at 100 s; picked up at 700 s (unlock), locked again at 800 s; never picked up again.
        let phases: [(String, Double)] = [("locking", 100), ("unlocked", 700), ("foreground", 700.1), ("active", 701), ("locking", 800)]
        let events = receiverRun(arrivalsAt: (0...12).map { ($0, Double($0) * 300 + 1) }, phases: phases)
        let stretches = NearbySummary.idleStretches(events)
        XCTAssertEqual(stretches.count, 2)
        XCTAssertEqual(stretches[0], NearbySummary.Stretch(start: 1_000_100, end: 1_000_700))
        XCTAssertEqual(stretches[1].start, 1_000_800)
        let card = NearbySummary.receiver(events)
        XCTAssertEqual(card.pickups, 2, "an unlock and a foreground")
        XCTAssertEqual(card.longestIdle, 3_200, accuracy: 1, "from 800 s to the run's last event at 4000 s")
        XCTAssertEqual(card.longestIdleDelivered, card.longestIdleExpected, "everything scheduled in the long idle stretch arrived")
        XCTAssertGreaterThan(card.longestIdleExpected, 5)
        XCTAssertNil(card.firstMissAfter, "a pickup is not a failure")
    }

    func testTheReceiverCardSeparatesArrivalsWhileLockedFromPickups() {
        var events: [Event] = [["kind": "header", "battery": ["percent": 100, "state": "unplugged"]], event("started", at: 0)]
        let states: [(Bool, String)] = [(true, "background"), (true, "background"), (true, "background"), (false, "background"), (false, "active"), (true, "background"), (true, "background")]
        for (tick, state) in states.enumerated() {
            events.append(event("auto_recv", at: Double(tick) * 300 + 1, ["tick": tick, "size": 4_096, "runStartMs": 1_000_000_000, "locked": state.0, "appState": state.1]))
        }
        let card = NearbySummary.receiver(events)
        XCTAssertEqual(card.deliveredLocked, 5)
        XCTAssertEqual(card.deliveredUnlockedBackground, 1, "unlocked with Lime behind another app: a pickup")
        XCTAssertEqual(card.deliveredInFront, 1)
        XCTAssertEqual(card.longestLockedRun, 3, "ticks 0 to 2 were all while locked")
        XCTAssertEqual(card.longestLockedRunSeconds, 600, accuracy: 0.01)
        XCTAssertTrue(NearbySummary.receiverLines(card).joined().contains("Arrivals while locked: 5"))
    }

    func testTheSenderCardCountsAcksWakeupsAndQuietStretches() {
        var events: [Event] = [["kind": "header", "battery": ["percent": 100, "state": "unplugged"]], event("started", at: 0)]
        for tick in 0..<4 {
            let key = "\(tick)-4096"
            events.append(event("auto_created", at: Double(tick) * 300, ["key": key, "tick": tick, "size": 4_096, "scheduledMs": Int((1_000_000 + Double(tick) * 300) * 1000)]))
            events.append(event("auto_sent", at: Double(tick) * 300 + 1, ["key": key]))
            if tick != 2 { events.append(event("auto_ack", at: Double(tick) * 300 + 2, ["key": key])) }
        }
        events.append(event("wake", at: 100, ["count": 7]))
        events.append(event("wake", at: 500, ["count": 3]))
        events.append(event("summary", at: 1_300, ["battery": ["percent": 99, "state": "unplugged"]]))
        let card = NearbySummary.sender(events)
        XCTAssertEqual(card.created, 4); XCTAssertEqual(card.sent, 4); XCTAssertEqual(card.delivered, 3)
        XCTAssertEqual(card.wakeups, 10)
        XCTAssertEqual(card.firstMissAfter, 600, "tick 2 was never acknowledged")
        XCTAssertEqual(card.longestGap, 600, accuracy: 0.01, "between the acks of ticks 1 and 3")
        XCTAssertEqual(card.longestQuiet, 800, accuracy: 0.01, "from the wake at 500 s to the end at 1300 s")
        XCTAssertEqual(card.batteryEnd, 99)
        XCTAssertTrue(NearbySummary.senderLines(card).joined().contains("delivered 3"))
    }

    func testDurationsReadAsPlainWords() {
        XCTAssertEqual(NearbySummary.duration(45), "45 s")
        XCTAssertEqual(NearbySummary.duration(660), "11 min")
        XCTAssertEqual(NearbySummary.duration(2 * 3_600 + 10 * 60), "2 h 10 m")
    }

    func testTheForceQuitCardsSayWhatArrivedAfterTheQuit() {
        var sender: [Event] = [event("started", at: 0)]
        for i in 0..<8 { sender.append(event("auto_created", at: Double(i) * 15, ["key": "\(i)-200"])) }
        for i in 0..<3 { sender.append(event("auto_ack", at: Double(i) * 15 + 1, ["key": "\(i)-200"])) }
        sender.append(event("service_missing", at: 70)); sender.append(event("service_missing", at: 90))
        let lines = NearbySummary.forceQuitSender(sender).joined(separator: "\n")
        XCTAssertTrue(lines.contains("Sent 8 · acknowledged 3"), lines)
        XCTAssertTrue(lines.contains("acknowledged after it: 0"), lines)
        XCTAssertTrue(lines.contains("missing on the other phone 2 times"), lines)
        let receiver: [Event] = [event("started", at: 0), event("auto_recv", at: 1, ["lateMs": 400_000]), event("auto_recv", at: 2, ["lateMs": 1_000])]
        let text = NearbySummary.forceQuitReceiver(receiver).joined(separator: "\n")
        XCTAssertTrue(text.contains("Received 2 in this run · 1 were scheduled while Lime was closed"), text)
    }
}
#endif
