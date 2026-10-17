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

    func testALinkIsAFailureUnlessItCarriedAFrameOrLastedThirtySecondsNotByTimeAlone() {
        var backoff = ReconnectBackoff()
        backoff.linkEnded(livedFor: nil)
        backoff.linkEnded(livedFor: 1.9)
        XCTAssertEqual(backoff.failures, 2)
        backoff.linkEnded(livedFor: 2.1)
        XCTAssertEqual(backoff.failures, 3, "2.1 s with no frame is still a failure (the grace period used to make it look fine)")
        backoff.linkEnded(livedFor: 10)
        XCTAssertEqual(backoff.failures, 4, "ten seconds that carried nothing is a failure too")
        backoff.linkEnded(livedFor: 5, carriedFrame: true)
        XCTAssertEqual(backoff.failures, 4, "a short link that carried a frame is neither")
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

    /// The 141-fix3 loop: each link lives 2.1 s (the grace runs out), carries nothing, and the other side tries again: it must settle too.
    func testALoopWhoseLinksLiveJustOverTwoSecondsWithNoFrameSettlesToAboutOneAMinute() {
        var backoff = ReconnectBackoff()
        var now = t0
        var attempts: [Date] = []
        while now.timeIntervalSince(t0) < 1200 {
            attempts.append(now)
            now = now.addingTimeInterval(2.1)
            backoff.linkEnded(livedFor: 2.1, carriedFrame: false)
            now = now.addingTimeInterval(backoff.delay(jitter: 1))
        }
        let last = t0.addingTimeInterval(1200)
        XCTAssertLessThanOrEqual(attempts.filter { last.timeIntervalSince($0) <= 60 }.count, 1, "at most one try in the last minute")
        XCTAssertLessThan(attempts.count, 40)
        // The old rule (time alone) never grew the wait at 0.5 s: about 400 tries in 20 minutes.
        var old = ReconnectBackoff()
        var oldNow = t0, oldCount = 0
        while oldNow.timeIntervalSince(t0) < 1200 { oldCount += 1; oldNow = oldNow.addingTimeInterval(2.1); if 2.1 < ReconnectBackoff.quick { old.linkEnded(livedFor: 2.1) }; oldNow = oldNow.addingTimeInterval(old.delay(jitter: 1)) }
        XCTAssertGreaterThan(oldCount, 300, "the loop the logs showed")
    }

    func testTheLowerIdKeepsItsOutboundLinkAndTheHigherIdTakesTheInbound() {
        XCTAssertTrue(MeshTieBreak.keepsOutbound(local: 5, remote: 9))
        XCTAssertFalse(MeshTieBreak.keepsOutbound(local: 9, remote: 5))
        // Both phones ask the same question about the same pair and get opposite, consistent answers: exactly one keeps its outbound.
        for (a, b) in [(1, 2), (100, 7), (UInt64.max - 1, 3)] as [(UInt64, UInt64)] {
            XCTAssertNotEqual(MeshTieBreak.keepsOutbound(local: a, remote: b), MeshTieBreak.keepsOutbound(local: b, remote: a))
        }
    }

    func testTheEngineAttachesAsSoonAsTheStoreExistsHoweverLateAndNeverWithoutTheSwitchOrTheExplanation() {
        typealias G = MeshAttachGate
        XCTAssertFalse(G.shouldAttach(attached: false, helpEnabled: true, explained: true, coreReady: false), "a locked relaunch: no store yet, keep waiting")
        XCTAssertTrue(G.shouldAttach(attached: false, helpEnabled: true, explained: true, coreReady: true), "the store appears (unlock, sign-in): attach")
        XCTAssertFalse(G.shouldAttach(attached: true, helpEnabled: true, explained: true, coreReady: true), "once")
        XCTAssertFalse(G.shouldAttach(attached: false, helpEnabled: false, explained: true, coreReady: true))
        XCTAssertFalse(G.shouldAttach(attached: false, helpEnabled: true, explained: false, coreReady: true))
    }

    // MARK: LIME-141-fix4

    func testAFallbackLinkIsAcceptedUnlessThereIsALiveLinkOrAFreshOutbound() {
        typealias F = MeshInboundFallback
        XCTAssertTrue(F.shouldAccept(hasLiveLink: false, freshOutboundHandshake: false), "no link and no outbound of my own: take the fallback")
        XCTAssertFalse(F.shouldAccept(hasLiveLink: true, freshOutboundHandshake: false), "a live link already: the fallback is a duplicate")
        XCTAssertFalse(F.shouldAccept(hasLiveLink: false, freshOutboundHandshake: true), "my own outbound may be about to finish")
    }

    func testTheHandshakeWatchdogPausesDiallingAfterTwoFailures() {
        XCTAssertEqual(MeshHandshakeWatchdog.pause(afterFailures: 1), 0)
        XCTAssertEqual(MeshHandshakeWatchdog.pause(afterFailures: 2), 60)
        XCTAssertEqual(MeshHandshakeWatchdog.pause(afterFailures: 7), 60)
        XCTAssertEqual(MeshHandshakeWatchdog.pause(afterFailures: 1, linkLive: true), 0)
        XCTAssertEqual(MeshHandshakeWatchdog.pause(afterFailures: 2, linkLive: true), 600, "with a live link the same peripheral is left alone for 10 minutes")
        XCTAssertEqual(MeshHandshakeWatchdog.timeout, 10)
    }

    /// Two phones near each other: the lower id's outbound never completes (it stalls, as the iPad's did); the higher id falls back after its 15 s
    /// grace. The lower phone must take that fallback, and nothing may keep trying after it.
    func testWhenTheLowerPhonesOutboundAlwaysStallsTheFallbackFormsAndHolds() {
        var backoff = ReconnectBackoff()
        var now = 0.0                       // seconds
        var lowerHandshakeStartedAt: Double? = 0
        var lowerTries = 1
        var pausedUntil = 0.0
        var linkFormedAt: Double?
        let grace = 15.0, fallbackAt = grace + 0.5
        while now < 120, linkFormedAt == nil {
            now += 0.25
            // The lower phone's watchdog: a handshake that has not finished in 10 s is dropped; two in a row pause it for a minute.
            if let started = lowerHandshakeStartedAt, now - started >= MeshHandshakeWatchdog.timeout {
                backoff.linkEnded(livedFor: nil)
                lowerHandshakeStartedAt = nil
                pausedUntil = now + max(MeshHandshakeWatchdog.pause(afterFailures: backoff.failures), backoff.delay(jitter: 1))
            }
            if lowerHandshakeStartedAt == nil, now >= pausedUntil { lowerHandshakeStartedAt = now; lowerTries += 1 }
            // The higher phone's fallback reaches the lower phone at 15.5 s.
            if now >= fallbackAt {
                let fresh = lowerHandshakeStartedAt.map { now - $0 < MeshInboundFallback.freshSeconds } ?? false
                if MeshInboundFallback.shouldAccept(hasLiveLink: false, freshOutboundHandshake: fresh) { linkFormedAt = now }
            }
        }
        XCTAssertNotNil(linkFormedAt, "the fallback link formed")
        XCTAssertLessThanOrEqual(linkFormedAt ?? 999, 21, "within about 20 s of the phones meeting")
        XCTAssertLessThanOrEqual(lowerTries, 3, "the lower phone made at most a couple of tries before the fallback was taken")
    }

    func testAnyFailureToRegisterAtLaunchButAnEndedSessionLeavesAPendingLink() {
        typealias R = OfflineLinkRule
        for problem in [ConnectionProblem.offline, .server, .busy, .other] { XCTAssertTrue(R.shouldConnect(problem), "\(problem): still a pending link, so sends queue") }
        XCTAssertFalse(R.shouldConnect(.sessionEnded), "signed out elsewhere: no link")
    }

    func testTheWordsOfTheStatusesAreShortAndInOrder() {
        XCTAssertEqual(DeliveryState.waiting.statusWords, "Waiting for a phone nearby")
        XCTAssertEqual(DeliveryState.passed.statusWords, "Passed to a nearby phone")
        XCTAssertNil(DeliveryState.sent.statusWords, "Sent has its own footer word and only means the server has it")
        XCTAssertTrue(DeliveryState.waiting.isInFlight && DeliveryState.passed.isInFlight)
        XCTAssertFalse(DeliveryState.sent.isInFlight)
    }

    // MARK: LIME-155

    func testAnOfflineSignedInPhoneAsksANeighbourThatCanFetchAtOnceThenOnceAMinute() {
        typealias R = MeshFetchRules
        XCTAssertTrue(R.shouldRequest(offline: true, signedIn: true, hasOnlineNeighbour: true, secondsSinceLast: nil, trigger: .neighbour), "a new neighbour: at once")
        XCTAssertTrue(R.shouldRequest(offline: true, signedIn: true, hasOnlineNeighbour: true, secondsSinceLast: 5, trigger: .neighbour), "even if it asked 5 s ago (another neighbour)")
        XCTAssertFalse(R.shouldRequest(offline: true, signedIn: true, hasOnlineNeighbour: true, secondsSinceLast: 30, trigger: .tick), "not before a minute")
        XCTAssertTrue(R.shouldRequest(offline: true, signedIn: true, hasOnlineNeighbour: true, secondsSinceLast: 60, trigger: .tick), "after a minute")
        XCTAssertTrue(R.shouldRequest(offline: true, signedIn: true, hasOnlineNeighbour: true, secondsSinceLast: nil, trigger: .tick))
        XCTAssertFalse(R.shouldRequest(offline: false, signedIn: true, hasOnlineNeighbour: true, secondsSinceLast: nil, trigger: .neighbour), "online: it fetches for itself")
        XCTAssertFalse(R.shouldRequest(offline: true, signedIn: false, hasOnlineNeighbour: true, secondsSinceLast: nil, trigger: .neighbour), "no account, nothing to fetch")
        XCTAssertFalse(R.shouldRequest(offline: true, signedIn: true, hasOnlineNeighbour: false, secondsSinceLast: nil, trigger: .neighbour), "nobody can fetch for it")
    }

    func testARequestThatTimedOutGoesToTheNextNeighbour() {
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        XCTAssertEqual(MeshFetchRules.nextNeighbour(candidates: [3, 4, 9], lastAsked: [:]), 3, "none asked yet: the first")
        XCTAssertEqual(MeshFetchRules.nextNeighbour(candidates: [3, 4, 9], lastAsked: [3: t0, 4: t0.addingTimeInterval(20)]), 9, "never asked first")
        XCTAssertEqual(MeshFetchRules.nextNeighbour(candidates: [3, 4], lastAsked: [3: t0.addingTimeInterval(20), 4: t0]), 4, "the one asked least recently")
        XCTAssertNil(MeshFetchRules.nextNeighbour(candidates: [], lastAsked: [:]))
    }

    /// LIME-155-fix: a "no" says why.
    func testAnOfflinePhoneThatDoesNotAskSaysWhy() {
        typealias R = MeshFetchRules
        let asked: [UInt64: Date] = [4: Date()]
        XCTAssertNil(R.skipReason(offline: false, signedIn: true, neighbours: [], lastAsked: [:], secondsSinceLast: nil, trigger: .tick), "online: nothing to say")
        XCTAssertEqual(R.skipReason(offline: true, signedIn: false, neighbours: [4], lastAsked: [:], secondsSinceLast: nil, trigger: .neighbour), "not_signed_in")
        XCTAssertEqual(R.skipReason(offline: true, signedIn: true, neighbours: [], lastAsked: [:], secondsSinceLast: nil, trigger: .neighbour), "no_online_neighbour")
        XCTAssertEqual(R.skipReason(offline: true, signedIn: true, neighbours: [4], lastAsked: asked, secondsSinceLast: 10, trigger: .tick), "asked_within_minute")
        XCTAssertEqual(R.skipReason(offline: true, signedIn: true, neighbours: [4], lastAsked: asked, secondsSinceLast: 10, trigger: .neighbour), "already_asked")
        XCTAssertNil(R.skipReason(offline: true, signedIn: true, neighbours: [4], lastAsked: [:], secondsSinceLast: nil, trigger: .neighbour), "asks at once")
    }

    func testAPhoneTellsNeighboursItCanFetchOnlyWhenOnlineAndSignedIn() {
        XCTAssertTrue(MeshFetchRules.relayOnline(online: true, signedIn: true))
        XCTAssertFalse(MeshFetchRules.relayOnline(online: false, signedIn: true))
        XCTAssertFalse(MeshFetchRules.relayOnline(online: true, signedIn: false))
    }
}
