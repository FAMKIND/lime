import XCTest
@testable import Lime

/// LIME-144: the battery soak's arithmetic.
final class BatteryLogTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func sample(_ minutes: Double, _ level: Int, plugged: Bool = false) -> BatterySample {
        BatterySample(time: t0.addingTimeInterval(minutes * 60), level: level, plugged: plugged)
    }

    func testDrainIsPercentLostPerUnpluggedHour() {
        let samples = [sample(0, 100), sample(30, 98), sample(60, 96)]
        XCTAssertEqual(BatteryLog.drainPerHour(samples)!, 4.0, accuracy: 0.001)
        XCTAssertEqual(BatteryLog.summary(samples), "Battery: 4.0% per hour over 1.0 h unplugged")
    }

    func testPluggedPeriodsAreLeftOut() {
        // 1 h unplugged losing 3 %, then 1 h charging (+30 %), then 1 h unplugged losing 3 %.
        let samples = [sample(0, 90), sample(60, 87), sample(65, 87, plugged: true), sample(120, 100, plugged: true), sample(125, 100), sample(185, 97)]
        XCTAssertEqual(BatteryLog.drainPerHour(samples)!, 3.0, accuracy: 0.001, "charging neither hides nor adds drain")
    }

    func testNeedsTenMinutesUnplugged() {
        XCTAssertNil(BatteryLog.drainPerHour([sample(0, 90), sample(5, 90)]))
        XCTAssertEqual(BatteryLog.summary([sample(0, 90)]), "Battery: needs 10 minutes unplugged")
        XCTAssertNil(BatteryLog.drainPerHour([sample(0, 90, plugged: true), sample(60, 100, plugged: true)]))
    }
}
