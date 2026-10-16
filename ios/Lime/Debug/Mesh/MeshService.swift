#if DEBUG
import Foundation
import Network
import Observation
import UIKit

/// The one mesh on this phone (LIME-141, 142; Debug builds only for now): the engine from LimeCore, the driver that runs it, the Bluetooth link,
/// and the log. **It runs by itself:** at launch, once the person is signed in, when "Help pass on nearby messages" is on and the one-time
/// explanation has been accepted; the test screen is only a window on it.
///
/// What it does for real messages: after every send attempt and sync it puts what could not reach the server (kept sealed in LimeCore's mesh
/// outbox) on nearby phones, updates each message's status ("Waiting for signal", then "Passed to a nearby phone"), and, when there is internet,
/// uploads everything it carries through `mesh-drop`. Mail for this phone that arrives over the mesh goes into the chat at once.
@MainActor
@Observable
final class MeshService {
    static let shared = MeshService()
    static let helpKey = "lime.mesh.help"
    private static let explainedKey = "lime.mesh.debug.explained"
    private static let askedOfflineKey = "lime.mesh.askedWhenOffline"
    private static let nearbyUntilKey = "lime.mesh.nearbyUntil"
    private static let offeredKey = "lime.mesh.nearbyOffered"

    let log = MeshLog()
    let bluetooth = MeshBluetooth()
    private(set) var engine: MeshEngine?
    private(set) var stats: MeshStats?
    private(set) var attached = false
    /// The explainer should be shown (the person has not yet seen why lime wants Bluetooth).
    var explainerPending = false
    /// Nearby mode (LIME-143): lime stays awake while in front and scans all the time, for up to 2 hours.
    private(set) var nearbyUntil: Date?
    /// Nearby mode ended by itself after 2 hours: ask whether to renew it.
    var nearbyExpired = false
    @ObservationIgnored private var appActive = true
    @ObservationIgnored private var nearbyTask: Task<Void, Never>?
    @ObservationIgnored private var driver: MeshDriver?
    @ObservationIgnored private var runner: MeshOutboxRunner?
    @ObservationIgnored private var statsTask: Task<Void, Never>?
    @ObservationIgnored private var pumpTask: Task<Void, Never>?
    @ObservationIgnored private weak var store: ConversationStore?
    @ObservationIgnored private let path = NWPathMonitor()
    @ObservationIgnored private var online = true

    private init() {
        bluetooth.onLog = { [weak self] kind, detail in self?.log.record(kind, detail) }
        bluetooth.onPeersChanged = { [weak self] in self?.refreshStats() }
        if let until = UserDefaults.standard.object(forKey: Self.nearbyUntilKey) as? Date, NearbyMode.isOn(until: until, now: Date()) { nearbyUntil = until }
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appActive = true; self?.applyNearby() }
        }
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appActive = false; self?.applyNearby() }
        }
    }

    // MARK: Nearby mode

    var nearbyOn: Bool { NearbyMode.isOn(until: nearbyUntil, now: Date()) }

    /// Turns Nearby mode on (for 2 hours) or off. Turning it on also turns the mesh on (and asks the one-time question if needed).
    func setNearby(_ on: Bool) {
        nearbyExpired = false
        if on {
            if !helpEnabled { helpEnabled = true }
            nearbyUntil = Date().addingTimeInterval(NearbyMode.limit)
            UserDefaults.standard.set(nearbyUntil, forKey: Self.nearbyUntilKey)
            if explained { startIfPossible() } else { explainerPending = true }
        } else {
            nearbyUntil = nil
            UserDefaults.standard.removeObject(forKey: Self.nearbyUntilKey)
        }
        log.record("nearby_mode", ["on": String(on)])
        applyNearby()
    }

    /// The scan and the screen follow Nearby mode; a timer ends it after 2 hours.
    private func applyNearby() {
        let on = nearbyOn
        UIApplication.shared.isIdleTimerDisabled = NearbyMode.keepsScreenAwake(nearbyOn: on, appActive: appActive)
        bluetooth.setContinuousScan(on)
        nearbyTask?.cancel()
        guard on, let until = nearbyUntil else { return }
        nearbyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(1, until.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            self.setNearby(false)
            self.nearbyExpired = true
        }
    }

    /// The one-time offer in a chat with a message "Waiting for signal" and no phone in range.
    func shouldOfferNearby(waitingInChat: Bool) -> Bool {
        NearbyMode.shouldOffer(waitingInChat: waitingInChat, meshOn: helpEnabled && explained && bluetooth.running, phonesInRange: bluetooth.peerCount,
                               nearbyOn: nearbyOn, offeredBefore: UserDefaults.standard.bool(forKey: Self.offeredKey))
    }

    func offerHandled() { UserDefaults.standard.set(true, forKey: Self.offeredKey) }

    // MARK: The switch and the explanation

    /// "Help pass on nearby messages": on by default. Off: no relaying for others and no sending through the mesh (offline sends wait for the internet).
    var helpEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.helpKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.helpKey)
            store?.core?.setMeshEnabled(enabled: newValue)
            if newValue {
                if explained { startIfPossible() } else { explainerPending = true }
            } else {
                setNearby(false)
                stop()
            }
        }
    }

    /// Whether the one-time explanation before the system's Bluetooth prompt has been accepted.
    var explained: Bool {
        get { UserDefaults.standard.bool(forKey: Self.explainedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.explainedKey) }
    }

    /// The person accepted the explanation: now the system prompt may come.
    func acceptExplainer() {
        explained = true
        explainerPending = false
        startIfPossible()
    }

    var isOn: Bool { bluetooth.running }

    /// The tiny status: "off", "looking", or "N phones".
    var status: String {
        guard bluetooth.running else { return "Nearby: off" }
        if nearbyOn { return NearbyMode.statusLine }
        if bluetooth.bluetoothState != "poweredOn" && bluetooth.bluetoothState != "off" { return "Nearby: Bluetooth \(bluetooth.bluetoothState)" }
        return bluetooth.peerCount == 0 ? "Nearby: looking" : "Nearby: \(bluetooth.peerCount) phone\(bluetooth.peerCount == 1 ? "" : "s")"
    }

    // MARK: Lifecycle

    /// At launch and after sign-in: the mesh follows the switch. (The Bluetooth managers start at once if the mesh was running, so iOS can hand back
    /// what it held after relaunching the app for Bluetooth.)
    func bootstrap(store: ConversationStore) {
        self.store = store
        store.afterDelivery = { [weak self] in await self?.afterDelivery() }
        startPathMonitor()
        if explained, helpEnabled { bluetooth.start() }
        if nearbyOn { applyNearby() }
        Task { @MainActor in
            var waited = 0
            while store.core == nil && waited < 600 { try? await Task.sleep(for: .milliseconds(100)); waited += 1 }
            guard let core = store.core else { return }
            core.setMeshEnabled(enabled: helpEnabled)
            if helpEnabled, explained { attach(core: core) }
        }
    }

    /// The person is offline for the first time: explain the mesh once (not at first launch).
    func offlineSeen() {
        guard helpEnabled, !explained, !UserDefaults.standard.bool(forKey: Self.askedOfflineKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.askedOfflineKey)
        explainerPending = true
    }

    private func startIfPossible() {
        guard helpEnabled, explained, let core = store?.core else { return }
        core.setMeshEnabled(enabled: true)
        attach(core: core)
        bluetooth.start()
    }

    /// The test screen's switch.
    func start(core: LimeStore) {
        explained = true
        core.setMeshEnabled(enabled: helpEnabled)
        attach(core: core)
        bluetooth.start()
    }

    func stop() {
        bluetooth.stop()
        statsTask?.cancel()
        pumpTask?.cancel()
        attached = false
        log.record("mesh_stopped")
    }

    private func attach(core: LimeStore) {
        guard !attached else { return }
        let engine = MeshEngine(store: core)
        self.engine = engine
        let bluetooth = self.bluetooth
        let driver = MeshDriver(engine: engine, transmit: { link, bytes in bluetooth.transmit(link, bytes) }, log: { [weak self] kind, detail in self?.log.record(kind, detail) })
        driver.onMessages = { [weak self] count in
            self?.log.record("mesh_messages", ["count": String(count)])
            Task { @MainActor in await self?.store?.reload() }
        }
        self.driver = driver
        let runner = MeshOutboxRunner(engine: engine, driver: driver, log: { [weak self] kind, detail in self?.log.record(kind, detail) })
        self.runner = runner
        driver.onFrameHandled = { [weak runner] in runner?.drainNotes() }
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
        // While it runs: every 15 seconds, put what is waiting on the mesh, update the statuses and drain the notes.
        pumpTask?.cancel()
        pumpTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await self?.pump()
            }
        }
        Task { @MainActor in await self.afterDelivery() }
    }

    // MARK: Real messages

    /// After a send attempt and after each sync (and every 15 s while running): on the mesh, statuses, uploads.
    func afterDelivery() async {
        await pump()
        await uploadIfOnline()
    }

    private func pump() async {
        guard let runner, attached else { return }
        let queued = runner.pump()
        if let store, store.conversations.contains(where: { $0.messages.contains { $0.state == .waiting || $0.state == .passed } }) || queued > 0 { await store.reload() }
    }

    /// With internet, hands everything this phone carries to the server (`mesh-drop`).
    func uploadIfOnline() async {
        guard let engine, attached, let runner, let link = store?.currentLink else { return }
        guard let token = try? await link.token() else { return }
        await runner.uploadIfOnline(online: online) {
            try await Task.detached(priority: .utility) { try engine.uploadAll(transport: link.transport, authToken: token) }.value
        }
    }

    private func startPathMonitor() {
        path.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let nowOnline = path.status == .satisfied
                let came = nowOnline && !self.online
                self.online = nowOnline
                self.log.record("connectivity", ["online": String(nowOnline)])
                // The internet is back: send what waited (it resumes by itself) and upload what is carried.
                if came { await self.store?.syncNow() }
            }
        }
        path.start(queue: .main)
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

    /// Puts a test packet (random bytes, not a message) on the mesh for an accepted contact. Returns its four-character id, or nil if it was not queued.
    func queueProbe(to user: String) -> String? {
        guard let engine else { return nil }
        let id = (try? engine.queueProbe(toUser: user)) ?? nil
        log.record("probe_queued", ["ok": String(id != nil), "id": id ?? "-"])
        if id != nil { driver?.packetQueued() }
        runner?.drainNotes()
        refreshStats()
        return id
    }
}
#endif
