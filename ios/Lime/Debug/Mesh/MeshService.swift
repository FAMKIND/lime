#if DEBUG
import Foundation
import Observation

/// The one mesh on this phone while testing (LIME-141, Debug builds only): the engine from LimeCore, the driver that runs it, the Bluetooth
/// link, and the log. It survives the screen (and iOS relaunching the app for Bluetooth: `resumeIfNeeded`).
@MainActor
@Observable
final class MeshService {
    static let shared = MeshService()
    private static let onKey = "lime.mesh.debug.on"
    private static let explainedKey = "lime.mesh.debug.explained"

    let log = MeshLog()
    let bluetooth = MeshBluetooth()
    private(set) var engine: MeshEngine?
    private(set) var stats: MeshStats?
    private(set) var attached = false
    @ObservationIgnored private var driver: MeshDriver?
    @ObservationIgnored private var statsTask: Task<Void, Never>?

    private init() {
        bluetooth.onLog = { [weak self] kind, detail in self?.log.record(kind, detail) }
        bluetooth.onPeersChanged = { [weak self] in self?.refreshStats() }
    }

    var isOn: Bool { UserDefaults.standard.bool(forKey: Self.onKey) }

    /// Whether the one-time explanation before the system's Bluetooth prompt has been shown.
    var explained: Bool {
        get { UserDefaults.standard.bool(forKey: Self.explainedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.explainedKey) }
    }

    /// The tiny status: "off", "looking", or "N phones".
    var status: String {
        guard bluetooth.running else { return "Nearby: off" }
        if bluetooth.bluetoothState != "poweredOn" && bluetooth.bluetoothState != "off" { return "Nearby: Bluetooth \(bluetooth.bluetoothState)" }
        return bluetooth.peerCount == 0 ? "Nearby: looking" : "Nearby: \(bluetooth.peerCount) phone\(bluetooth.peerCount == 1 ? "" : "s")"
    }

    func start(core: LimeStore) {
        UserDefaults.standard.set(true, forKey: Self.onKey)
        attach(core: core)
        bluetooth.start()
    }

    func stop() {
        UserDefaults.standard.set(false, forKey: Self.onKey)
        bluetooth.stop()
        statsTask?.cancel()
        attached = false
        log.record("mesh_stopped")
    }

    private func attach(core: LimeStore) {
        guard !attached else { return }
        let engine = MeshEngine(store: core)
        self.engine = engine
        let bluetooth = self.bluetooth
        let driver = MeshDriver(engine: engine, transmit: { link, bytes in bluetooth.transmit(link, bytes) }, log: { [weak self] kind, detail in self?.log.record(kind, detail) })
        driver.onMessages = { [weak self] count in self?.log.record("mesh_messages", ["count": String(count)]) }
        self.driver = driver
        bluetooth.driver = driver
        attached = true
        try? engine.refreshTags()
        log.record("engine_attached")
        statsTask?.cancel()
        statsTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refreshStats(log: true)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func refreshStats(log shouldLog: Bool = false) {
        guard let engine else { return }
        let s = engine.stats()
        stats = s
        if shouldLog {
            log.record("stats", ["carried": String(s.carried), "bytes": String(s.carriedBytes), "received": String(s.received), "dup": String(s.duplicates),
                                 "rejected": String(s.rejected), "limited": String(s.rateLimited), "evicted": String(s.evicted), "expired": String(s.expired),
                                 "mine": String(s.mine), "probes": String(s.probesReceived), "scan": bluetooth.scanMode])
        }
    }

    /// Puts a test packet (random bytes, not a message) on the mesh for an accepted contact. Returns whether it was queued.
    func queueProbe(to user: String) -> Bool {
        guard let engine else { return false }
        let queued = (try? engine.queueProbe(toUser: user)) ?? false
        log.record("probe_queued", ["ok": String(queued)])
        if queued { driver?.packetQueued() }
        refreshStats()
        return queued
    }

    /// At launch: if the mesh was on when the app ended (iOS relaunches it for Bluetooth), the Bluetooth managers start again at once (with their
    /// restore identifiers, so iOS can hand back what it held) and the engine attaches as soon as the store is open.
    static func resumeIfNeeded(store: ConversationStore) {
        guard shared.isOn else { return }
        shared.bluetooth.start()
        Task { @MainActor in
            var waited = 0
            while store.core == nil && waited < 600 { try? await Task.sleep(for: .milliseconds(100)); waited += 1 }
            if let core = store.core { shared.attach(core: core) }
        }
    }
}
#endif
