import CallKit
import WebRTC
import XCTest
@testable import Lime

/// LIME-169: Settings → Calls.
@MainActor
final class CallSettingsTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "lime.test.calls.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testTheDefaultsAreRecentsOffLowDataOffAndThePhonesOwnVolume() {
        let settings = CallSettings(defaults: defaults())
        XCTAssertFalse(settings.includeInRecents, "off by default")
        XCTAssertFalse(settings.lowDataMode)
        XCTAssertEqual(settings.volume, 1.0)
    }

    func testTheChoicesPersistAcrossARestart() {
        let d = defaults()
        let first = CallSettings(defaults: d)
        first.includeInRecents = true
        first.lowDataMode = true
        first.volume = 1.5
        let second = CallSettings(defaults: d)
        XCTAssertTrue(second.includeInRecents)
        XCTAssertTrue(second.lowDataMode)
        XCTAssertEqual(second.volume, 1.5)
    }

    func testTheVolumeStaysBetweenHalfAndDouble() {
        let settings = CallSettings(defaults: defaults())
        settings.volume = 9
        XCTAssertEqual(settings.volume, 2.0)
        settings.volume = 0
        XCTAssertEqual(settings.volume, 0.5)
        XCTAssertEqual(CallSettings.percent(1.0), "100%")
        XCTAssertEqual(CallSettings.percent(0.5), "50%")
        XCTAssertEqual(CallSettings.percent(2.0), "200%")
    }

    func testLaunchArgumentsArriveAsTextAndLoadingWritesNothing() {
        let d = defaults()
        d.set("YES", forKey: CallSettings.recentsKey)
        d.set("1.5", forKey: CallSettings.volumeKey)
        let settings = CallSettings(defaults: d)
        XCTAssertTrue(settings.includeInRecents)
        XCTAssertEqual(settings.volume, 1.5)
        XCTAssertEqual(d.string(forKey: CallSettings.recentsKey), "YES", "a launch argument is for that launch only")
        let clean = defaults()
        _ = CallSettings(defaults: clean)
        XCTAssertNil(clean.object(forKey: CallSettings.recentsKey))
        XCTAssertNil(clean.object(forKey: CallSettings.lowDataKey))
        XCTAssertNil(clean.object(forKey: CallSettings.volumeKey))
    }

    func testAChangeIsAnnouncedToTheRunningCall() {
        let settings = CallSettings(defaults: defaults())
        let heard = expectation(forNotification: CallSettings.changed, object: nil)
        heard.expectedFulfillmentCount = 3
        settings.includeInRecents = true
        settings.lowDataMode = true
        settings.volume = 1.2
        wait(for: [heard], timeout: 2)
    }

    // MARK: Low Data Mode

    func testLowDataModeSendsALowerPictureInEveryKindOfCall() {
        let low = CallVideoPlan.Capture(width: 640, height: 360, fps: 15)
        XCTAssertEqual(CallVideoPlan.capture(lowData: true, group: false), low)
        XCTAssertEqual(CallVideoPlan.capture(lowData: true, group: true), low)
        XCTAssertEqual(CallVideoPlan.capture(lowData: true, cellular: true, group: true), low, "mobile data and Low Data Mode: the lower one")
        XCTAssertEqual(CallVideoPlan.maxBitrate(lowData: true), 350_000)
        XCTAssertEqual(CallVideoPlan.maxFps(lowData: true), 15)
    }

    func testWithLowDataModeOffTheOldChoicesStandAndNothingIsCapped() {
        XCTAssertEqual(CallVideoPlan.capture(lowData: false, group: true), CallVideoPlan.Capture(width: 1280, height: 720, fps: 30))
        XCTAssertEqual(CallVideoPlan.capture(lowData: false, cellular: true, group: true), CallVideoPlan.Capture(width: 848, height: 480, fps: 24))
        XCTAssertEqual(CallVideoPlan.capture(lowData: false, group: false), CallVideoPlan.Capture(width: 1280, height: 720, fps: 24))
        XCTAssertNil(CallVideoPlan.maxBitrate(lowData: false))
        XCTAssertNil(CallVideoPlan.maxFps(lowData: false))
    }

    // MARK: Recents

    func testTheProviderConfigurationFollowsTheRecentsChoiceAndKeepsTheRest() {
        let off = CallKitSystem.makeConfiguration(includeInRecents: false)
        let on = CallKitSystem.makeConfiguration(includeInRecents: true)
        XCTAssertFalse(off.includesCallsInRecents)
        XCTAssertTrue(on.includesCallsInRecents)
        for configuration in [off, on] {
            XCTAssertTrue(configuration.supportsVideo)
            XCTAssertEqual(configuration.maximumCallsPerCallGroup, 1)
            XCTAssertEqual(configuration.ringtoneSound, "lime-ring.caf", "lime's own ringtone stays")
        }
    }

    func testChangingTheSettingUpdatesTheLiveProviderWithoutARestart() {
        let settings = CallSettings.shared
        let saved = settings.includeInRecents
        defer { settings.includeInRecents = saved }
        settings.includeInRecents = false
        XCTAssertFalse(CallKitSystem.providerIncludesRecents)
        settings.includeInRecents = true
        let updated = expectation(description: "the provider takes the new configuration")
        Task { @MainActor in
            for _ in 0..<40 where !CallKitSystem.providerIncludesRecents { try? await Task.sleep(for: .milliseconds(50)) }
            updated.fulfill()
        }
        wait(for: [updated], timeout: 4)
        XCTAssertTrue(CallKitSystem.providerIncludesRecents)
        settings.includeInRecents = false
        let reverted = expectation(description: "and back")
        Task { @MainActor in
            for _ in 0..<40 where CallKitSystem.providerIncludesRecents { try? await Task.sleep(for: .milliseconds(50)) }
            reverted.fulfill()
        }
        wait(for: [reverted], timeout: 4)
        XCTAssertFalse(CallKitSystem.providerIncludesRecents)
    }

    // MARK: Volume

    /// The 1:1 call sets `RTCAudioTrack.source.volume` on the other person's voice: WebRTC accepts up to double (it takes up to 10).
    func testWebRTCTakesTheTopAndTheBottomOfTheVolumeRange() {
        let factory = RTCPeerConnectionFactory()
        let track = factory.audioTrack(with: factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)), trackId: "t")
        for volume in [CallSettings.volumeRange.lowerBound, 1.0, CallSettings.volumeRange.upperBound] {
            track.source.volume = volume
            XCTAssertEqual(track.source.volume, volume, accuracy: 0.001, "\(volume)")
        }
    }

    // MARK: Layers and the grid (LIME-171)

    func testANormalGroupCallPublishesThreeLayersAtThirtyTwentyFourAndTwentyFrames() {
        let layers = CallVideoPlan.normalLayers
        XCTAssertEqual(layers.map(\.name), ["high", "mid", "low"])
        XCTAssertEqual(layers.map(\.maxFps), [30, 24, 20], "LiveKit's own presets were 30 / 20 / 15: a grid cell never moved faster than 20 or 15")
        XCTAssertEqual(layers.map(\.width), [1280, 640, 320])
        XCTAssertEqual(layers.map(\.height), [720, 360, 180])
        XCTAssertEqual(layers.map(\.maxBitrate), [1_700_000, 450_000, 150_000], "the same bitrates as before: only the rate went up")
    }

    func testAGridCellAsksForTheMiddleLayerAndTheSpeakerOrAWholeWindowForTheHighOne() {
        // Layers are chosen by the size asked for: up to 360×640 is the middle layer, more is the high one, never the 180p floor for a visible cell.
        let others = GridLayerRequest.size(speaking: false, cellCount: 4)
        XCTAssertEqual(others, CGSize(width: 360, height: 480))
        XCTAssertGreaterThan(others.width, 320, "past the low layer's 320 pixels")
        XCTAssertGreaterThan(others.height, 320)
        XCTAssertLessThanOrEqual(others.width, 360, "and no more than the middle layer's 360")
        XCTAssertEqual(GridLayerRequest.size(speaking: true, cellCount: 4), CGSize(width: 720, height: 960))
        XCTAssertEqual(GridLayerRequest.size(speaking: false, cellCount: 1), CGSize(width: 720, height: 960), "a single cell fills the window")
    }
}
