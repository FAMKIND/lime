#if DEBUG
import Foundation
import Observation

/// The spike's one instance, so a Bluetooth relaunch by iOS (state restoration) can pick the test up again.
@MainActor
@Observable
final class NearbyTest {
    static let shared = NearbyTest()

    let log = NearbyLog()
    let transport: NearbyTransport
    var label: String { didSet { UserDefaults.standard.set(label, forKey: Keys.label) } }

    private enum Keys {
        static let running = "lime.nearby.running"
        static let label = "lime.nearby.label"
    }

    private init() {
        transport = NearbyTransport(log: log)
        label = UserDefaults.standard.string(forKey: Keys.label) ?? "1-both-open-1m"
    }

    /// `relabel`: the log's label for this run when it differs from the typed label (a relaunch).
    func start(relabel: String? = nil) {
        UserDefaults.standard.set(true, forKey: Keys.running)
        transport.start(label: relabel ?? label)
    }

    func stop() {
        UserDefaults.standard.set(false, forKey: Keys.running)
        transport.stop()
    }

    /// At launch: if a test was running when the app ended (iOS relaunches it for Bluetooth), carry on in a new log.
    static func resumeIfNeeded() {
        // An auto test has its own schedule to pick up.
        if UserDefaults.standard.bool(forKey: "lime.nearby.auto.running") { NearbyAutoTest.resumeIfNeeded(); return }
        guard UserDefaults.standard.bool(forKey: Keys.running) else { return }
        let test = NearbyTest.shared
        test.transport.start(label: test.label + "-relaunched")
    }
}
#endif
