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
/// outbox) on nearby phones, updates each message's status ("Waiting for a phone nearby", then "Passed to a nearby phone"), and, when there is internet,
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
    @ObservationIgnored private var lastCarried: UInt32 = 0
    /// The pinned mesh key is not the pair of the server's secret (LIME-144): every upload would be refused. Set by the launch check.
    private(set) var keyWarning: String?
    @ObservationIgnored private var keyChecked = false
    @ObservationIgnored private var keySkipsLogged: Set<String> = []
    /// The battery soak (LIME-144): a Debug toggle; samples every 5 minutes into the mesh log.
    private(set) var batterySamples: [BatterySample] = []
    @ObservationIgnored private var batteryTask: Task<Void, Never>?
    @ObservationIgnored private var attachTask: Task<Void, Never>?
    var batteryLogOn: Bool { batteryTask != nil }

    private init() {
        bluetooth.onLog = { [weak self] kind, detail in self?.log.record(kind, detail) }
        bluetooth.onPeersChanged = { [weak self] in self?.refreshStats() }
        if !ProcessInfo.processInfo.arguments.contains("-lime-demo-chat"), let until = UserDefaults.standard.object(forKey: Self.nearbyUntilKey) as? Date, NearbyMode.isOn(until: until, now: Date()) { nearbyUntil = until }
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appActive = true; self?.applyNearby(); Task { await self?.uploadIfOnline(trigger: "active") } }
        }
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appActive = false; self?.applyNearby() }
        }
    }

    // MARK: The mesh key check

    /// Once per launch, when a session and the internet both exist (retried when either appears later: the 15 s tick, the connectivity flip, a
    /// sync): asks the server which mesh key it holds and compares it with the one pinned in the app. It always leaves a line: `ok key=…`,
    /// `mismatch pinned=… server=…` or `unavailable why=…` (a skip is logged once per reason, so the log never just goes quiet).
    func checkServerKeyOnce() async {
        let link = store?.currentLink
        switch MeshKeyCheckGate.decide(alreadyChecked: keyChecked, engineReady: engine != nil, online: online, hasSession: link != nil) {
        case .skip(let why):
            if why != "done", keySkipsLogged.insert(why).inserted { log.record("mesh_key_check", ["result": "unavailable", "why": why]) }
            return
        case .run: break
        }
        guard let engine, let link else { return }
        let token: String
        do { token = try await link.token() } catch {
            if keySkipsLogged.insert("no-token").inserted { log.record("mesh_key_check", ["result": "unavailable", "why": "no-token"]) }
            return
        }
        let transport = link.transport
        let result = await Task.detached(priority: .utility) { engine.checkServerKey(transport: transport, authToken: token) }.value
        guard let result else {
            if keySkipsLogged.insert("server").inserted { log.record("mesh_key_check", ["result": "unavailable", "why": "server"]) }
            return
        }
        keyChecked = true
        let line = MeshKeyCheckGate.line(matches: result.matches, pinned: result.pinned, server: result.server, why: "")
        log.record(line.kind, line.detail)
        if !result.matches {
            keyWarning = "Mesh key mismatch: this build pins \(result.pinned) but the server holds \(result.server). Uploads will be refused."
            log.record("WARNING mesh key mismatch", ["pinned": result.pinned, "server": result.server, "key_id": String(result.keyId)])
        }
    }

    // MARK: Relay download (LIME-155)

    @ObservationIgnored private var lastFetchAt: Date?
    @ObservationIgnored private var lastAsked: [UInt64: Date] = [:]
    @ObservationIgnored private var relayWasOnline = false

    /// This phone can fetch for its neighbours when it is online and signed in: tell the engine, and the neighbours when it changes.
    func updateRelayState() {
        guard let engine else { return }
        let on = MeshFetchRules.relayOnline(online: online, signedIn: store?.accountSignedIn ?? false)
        engine.setRelayOnline(online: on)
        if on != relayWasOnline {
            relayWasOnline = on
            log.record("relay_online", ["on": String(on)])
            driver?.broadcastOnline()
        }
        if online { engine.fetchReset() }
    }

    /// Every 30 s the bit is said again on each live link (two bytes), so a neighbour that missed it still hears it.
    func refreshOnlineBit() {
        refreshTicks += 1
        if refreshTicks % 2 == 0 { driver?.broadcastOnline(why: "refresh") }
    }
    @ObservationIgnored private var refreshTicks = 0

    /// Neighbours' requests waiting to be posted: each is posted to `mesh-fetch` with no session, and the answer goes back over the same link.
    func handleFetchJobs() {
        guard let engine, let runner else { return }
        let jobs = engine.takeFetchJobs()
        guard !jobs.isEmpty else { return }
        guard let link = store?.currentLink, online else { return }
        for job in jobs {
            Task { @MainActor [weak self] in
                let answer = await Task.detached(priority: .utility) { engine.relayFetch(transport: link.transport, request: job.request) }.value
                self?.bluetooth.transmit(job.link, answer)
                runner.drainNotes()
            }
        }
    }

    /// An offline, signed-in phone with a linked neighbour that can fetch for it asks for its mail (at once for a new neighbour, then once a minute).
    func maybeFetch(trigger: MeshFetchRules.Trigger) {
        guard let engine, attached else { return skip("not_attached") }
        let neighbours = engine.fetchNeighbours()
        let since = lastFetchAt.map { Date().timeIntervalSince($0) }
        let signedIn = store?.accountSignedIn ?? false
        if let why = MeshFetchRules.skipReason(offline: !online, signedIn: signedIn, neighbours: neighbours, lastAsked: lastAsked, secondsSinceLast: since, trigger: trigger) { return skip(why) }
        guard !online else { return }
        guard let link = MeshFetchRules.nextNeighbour(candidates: neighbours, lastAsked: lastAsked) else { return skip("no_candidate") }
        guard let frame = try? engine.fetchFrameFor(link: link) else { return skip("request_not_built") }
        lastAsked[link] = Date()
        lastFetchAt = Date()
        bluetooth.transmit(link, frame)
        runner?.drainNotes()
    }

    /// A neighbour's online bit arrived or changed: a changed bit is a new reason to ask, so the link is asked again.
    func neighbourOnline(link: UInt64, on: Bool) {
        lastAsked[link] = nil
        if on { maybeFetch(trigger: .neighbour) }
    }

    @ObservationIgnored private var skipLogged: [String: Date] = [:]

    /// Why this phone did not ask for mail: one line per reason per minute, so a silent "no" shows in the log.
    private func skip(_ why: String) {
        let now = Date()
        if let last = skipLogged[why], now.timeIntervalSince(last) < 60 { return }
        skipLogged[why] = now
        log.record("fetch_skip", ["why": why])
    }

    // MARK: Battery log

    func setBatteryLog(_ on: Bool) {
        batteryTask?.cancel()
        batteryTask = nil
        guard on else { log.record("battery_log", ["on": "false"]); return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        batterySamples = []
        log.record("battery_log", ["on": "true"])
        batteryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let device = UIDevice.current
                let sample = BatterySample(time: Date(), level: max(0, Int((device.batteryLevel * 100).rounded())), plugged: device.batteryState == .charging || device.batteryState == .full)
                self.batterySamples.append(sample)
                self.log.record("battery_sample", ["level": String(sample.level), "plugged": String(sample.plugged), "summary": BatteryLog.summary(self.batterySamples)])
                try? await Task.sleep(for: .seconds(BatteryLog.interval))
            }
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

    /// The one-time offer in a chat with a message "Waiting for a phone nearby" and no phone in range.
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
        if let core = store.core { core.setMeshEnabled(enabled: helpEnabled) }
        ensureAttached()
    }

    /// Attaches the engine as soon as the account's store exists and the mesh is on, however long that takes: a phone iOS relaunched for
    /// Bluetooth while locked has no store yet, and used to give up after a minute and never attach (LIME-141-fix3). Retried every 2 s.
    func ensureAttached() {
        attachTask?.cancel()
        attachTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let core = self.store?.core
                if MeshAttachGate.shouldAttach(attached: self.attached, helpEnabled: self.helpEnabled, explained: self.explained, coreReady: core != nil), let core {
                    core.setMeshEnabled(enabled: true)
                    self.attach(core: core)
                    return
                }
                if self.attached || !self.helpEnabled || !self.explained { return }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// The person is offline for the first time: explain the mesh once (not at first launch).
    func offlineSeen() {
        guard helpEnabled, !explained, !UserDefaults.standard.bool(forKey: Self.askedOfflineKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.askedOfflineKey)
        explainerPending = true
    }

    private func startIfPossible() {
        guard helpEnabled, explained else { return }
        bluetooth.start()
        if let core = store?.core { core.setMeshEnabled(enabled: true); attach(core: core) } else { ensureAttached() }
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
            if let core = self?.store?.core, let counts = Optional(core.takeDupDropped()), !counts.isEmpty { self?.log.record("dup_dropped", ["counts": counts]) }
            Task { @MainActor in await self?.store?.reload() }
        }
        self.driver = driver
        let runner = MeshOutboxRunner(engine: engine, driver: driver, log: { [weak self] kind, detail in self?.log.record(kind, detail) })
        self.runner = runner
        runner.onFetchedMessages = { [weak self] in Task { @MainActor in await self?.store?.reload() } }
        driver.onOnlineSeen = { [weak self] link, on in self?.neighbourOnline(link: link, on: on) }
        driver.onFrameHandled = { [weak self, weak runner] in
            runner?.drainNotes()
            // Relay download (LIME-155): requests a neighbour asked this phone to post, and a new neighbour that can fetch for this phone.
            self?.handleFetchJobs()
            self?.maybeFetch(trigger: .neighbour)
            // A phone that is online and was just handed something to carry uploads it at once, not on the next tick.
            Task { @MainActor in
                guard let self, let engine = self.engine, self.online else { return }
                let carried = engine.stats().carried
                if carried > self.lastCarried { await self.uploadIfOnline(trigger: "frame") }
                self.lastCarried = carried
            }
        }
        bluetooth.driver = driver
        attached = true
        try? engine.refreshTags()
        log.record("engine_attached")
        updateRelayState()
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
                await self?.afterDelivery(trigger: "tick")
                self?.updateRelayState()
                self?.refreshOnlineBit()
                self?.maybeFetch(trigger: .tick)
            }
        }
        Task { @MainActor in await self.afterDelivery() }
    }

    // MARK: Real messages

    /// After a send attempt and after each sync (and every 15 s while running): on the mesh, statuses, uploads.
    func afterDelivery(trigger: String = "sync") async {
        await checkServerKeyOnce()
        await pump()
        await uploadIfOnline(trigger: trigger)
    }

    private func pump() async {
        guard let runner, attached else { return }
        let queued = runner.pump()
        if let store, store.conversations.contains(where: { $0.messages.contains { $0.state == .waiting || $0.state == .passed } }) || queued > 0 { await store.reload() }
    }

    /// With internet, hands everything this phone carries to the server (`mesh-drop`). `trigger`: what asked (connectivity, active, tick, sync, frame).
    func uploadIfOnline(trigger: String = "sync") async {
        guard let engine, attached, let runner else { return }
        guard let link = store?.currentLink else { if trigger != "tick" { log.record("upload_skip", ["why": "no-session", "trigger": trigger]) }; return }
        guard online else { await runner.uploadIfOnline(online: false, trigger: trigger) { 0 }; return }
        guard engine.stats().carried > 0 else { return }
        await runner.uploadIfOnline(online: online, trigger: trigger) {
            try await Task.detached(priority: .utility) { try engine.uploadAll(transport: link.transport) }.value
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
                self.updateRelayState()
                // The internet is back: send what waited (it resumes by itself) and upload what is carried.
                if came { self.keySkipsLogged.remove("offline"); await self.store?.syncNow(); await self.checkServerKeyOnce(); await self.uploadIfOnline(trigger: "connectivity") }
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
