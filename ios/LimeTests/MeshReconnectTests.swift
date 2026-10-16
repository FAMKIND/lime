import XCTest
@testable import Lime

/// LIME-141-fix2: the reconnect backoff, the storm guard, the L2CAP channel that arrives before its hello, and the launch key check's triggers.
final class MeshReconnectTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)

    func testTheWaitDoublesWithEveryFailureAndIsCappedAtAMinute() {
        var backoff = ReconnectBackoff()
        XCTAssertEqual(backoff.delay(jitter: 1), 0.5, "after a first, normal drop: half a second")
        let expected: [Double] = [1, 2, 4, 8, 16, 32, 60, 60]
        for want in expected {
            backoff.linkEnded(livedFor: 0.3)
            XCTAssertEqual(backoff.delay(jitter: 1), want, accuracy: 0.001)
        }
    }

    func testALinkThatNeverCameUpOrEndedWithinTwoSecondsIsAFailureAndOneThatLastedThirtySecondsStartsOver() {
        var backoff = ReconnectBackoff()
        backoff.linkEnded(livedFor: nil)
        backoff.linkEnded(livedFor: 1.9)
        XCTAssertEqual(backoff.failures, 2)
        backoff.linkEnded(livedFor: 10)
        XCTAssertEqual(backoff.failures, 2, "a middling link is neither")
        backoff.linkEnded(livedFor: 30)
        XCTAssertEqual(backoff.failures, 0, "a stable link resets it")
        XCTAssertEqual(backoff.delay(jitter: 1), 0.5)
    }

    func testJitterSpreadsTheWaitByTwentyPercent() {
        var backoff = ReconnectBackoff()
        backoff.linkEnded(livedFor: 0)
        XCTAssertEqual(backoff.delay(jitter: 0.8), 0.8, accuracy: 0.001)
        XCTAssertEqual(backoff.delay(jitter: 1.2), 1.2, accuracy: 0.001)
        for _ in 0..<50 { XCTAssertTrue((0.8...1.2).contains(backoff.delay())) }
    }

    func testTheStormGuardWarnsOnceAMinuteAboveTenAttempts() {
        var guardRail = ReconnectStormGuard()
        var warnings = 0
        for i in 0..<30 { if guardRail.record(at: t0.addingTimeInterval(Double(i) * 0.5)) { warnings += 1 } }
        XCTAssertEqual(warnings, 1, "30 attempts in 15 s: one warning, not thirty")
        XCTAssertFalse(guardRail.record(at: t0.addingTimeInterval(40)), "still the same minute")
        XCTAssertTrue(guardRail.record(at: t0.addingTimeInterval(66)), "a minute later it is still a storm: one more warning")
        var calm = ReconnectStormGuard()
        for i in 0..<10 { XCTAssertFalse(calm.record(at: t0.addingTimeInterval(Double(i) * 5))) }
    }

    /// Two phones that reject each other's link for ever (the logs' 4,500 reconnects in half an hour) must settle.
    func testAMutualRejectLoopSettlesToUnderTenReconnectsAMinute() {
        var backoff = ReconnectBackoff()
        var guardRail = ReconnectStormGuard()
        var now = t0
        var attempts: [Date] = []
        var warnings: [Date] = []
        while now.timeIntervalSince(t0) < 1200 {
            attempts.append(now)
            if guardRail.record(at: now) { warnings.append(now) }
            now = now.addingTimeInterval(0.35)            // connect, hello, channel opened and refused
            backoff.linkEnded(livedFor: 0.3)              // the link ended within 2 s: a failure
            now = now.addingTimeInterval(backoff.delay(jitter: 1))
        }
        let last = t0.addingTimeInterval(1200)
        let lastMinute = attempts.filter { last.timeIntervalSince($0) <= 60 }.count
        XCTAssertLessThanOrEqual(lastMinute, 3, "settled at one try a minute or so (got \(lastMinute))")
        XCTAssertLessThan(attempts.count, 60, "a few dozen tries in 20 minutes, not thousands (got \(attempts.count))")
        XCTAssertTrue(warnings.allSatisfy { $0.timeIntervalSince(t0) < 30 }, "the guard speaks only in the first seconds")
    }

    func testAChannelBeforeTheHelloIsKeptThenBoundAndAnOldOneIsReleased() {
        var pending = PendingChannels<Int>()
        let phone = UUID()
        pending.hold(7, from: phone, at: t0)
        XCTAssertEqual(pending.take(for: phone, at: t0.addingTimeInterval(1.5)), 7, "the hello came within the grace: the channel is bound")
        XCTAssertNil(pending.take(for: phone, at: t0.addingTimeInterval(1.6)), "taken once")
        pending.hold(8, from: phone, at: t0)
        XCTAssertNil(pending.take(for: phone, at: t0.addingTimeInterval(3)), "too late")
        pending.hold(9, from: UUID(), at: t0)
        XCTAssertEqual(pending.expire(at: t0.addingTimeInterval(1)), [], "still within the grace")
        XCTAssertEqual(pending.expire(at: t0.addingTimeInterval(5)), [9], "released for closing")
        XCTAssertEqual(pending.count, 0)
    }

    func testTheKeyCheckRunsWhenASessionAndTheInternetBothExistAndAlwaysSaysWhyItDidNot() {
        typealias G = MeshKeyCheckGate
        XCTAssertEqual(G.decide(alreadyChecked: false, engineReady: true, online: true, hasSession: true), .run)
        XCTAssertEqual(G.decide(alreadyChecked: false, engineReady: true, online: true, hasSession: false), .skip(why: "no-session"), "the session appears later: it runs then")
        XCTAssertEqual(G.decide(alreadyChecked: false, engineReady: true, online: false, hasSession: true), .skip(why: "offline"), "the internet appears later: it runs then")
        XCTAssertEqual(G.decide(alreadyChecked: false, engineReady: false, online: true, hasSession: true), .skip(why: "no-engine"))
        XCTAssertEqual(G.decide(alreadyChecked: true, engineReady: true, online: true, hasSession: true), .skip(why: "done"), "once per launch")
    }

    func testTheKeyCheckLineIsOkMismatchOrUnavailable() {
        XCTAssertEqual(MeshKeyCheckGate.line(matches: true, pinned: "03129b4296f76a31", server: "03129b4296f76a31", why: "").detail, ["result": "ok", "key": "03129b4296f76a31"])
        XCTAssertEqual(MeshKeyCheckGate.line(matches: false, pinned: "aa", server: "bb", why: "").detail, ["result": "mismatch", "pinned": "aa", "server": "bb"])
        XCTAssertEqual(MeshKeyCheckGate.line(matches: nil, pinned: "", server: "", why: "offline").detail, ["result": "unavailable", "why": "offline"])
    }
}
