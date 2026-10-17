#if DEBUG
@preconcurrency import CoreBluetooth
import Foundation
import Observation
import UIKit

/// The Bluetooth link for the mesh (LIME-141): every phone is a central and a peripheral at once, advertising one service and scanning for it.
/// Debug builds only for now (the Release check forbids CoreBluetooth until the mesh is offered to people).
///
/// - **Meeting** is GATT: connect, read the other phone's **link id** (a hello characteristic), write mine. The **lower id initiates**: both phones
///   decide the same way (`MeshLinkPolicy`), so of the two links two phones make, one is kept and the other closed.
/// - **Moving frames** is L2CAP (unencrypted and unpaired: everything of value is already sealed), opened from the PSM the peripheral publishes;
///   **GATT write and notify** carry the frames meanwhile and whenever the channel fails (about 470 byte fragments, reassembled with caps and a
///   30 second timeout).
/// - **Privacy:** the advertisement carries the service UUID and nothing else (no name, no account, no device id); the only identifier is the
///   random link id, new every launch and every 15 minutes, which is read only by a phone that connected.
/// - **Restoration:** both managers have restore identifiers; every restore is logged and counts as a wake.
@MainActor
@Observable
final class MeshBluetooth: NSObject {
    static let serviceUUID = CBUUID(string: "6C696D65-6D65-7368-0000-000000000001")
    static let helloUUID = CBUUID(string: "6C696D65-6D65-7368-0000-000000000002")
    static let dataWriteUUID = CBUUID(string: "6C696D65-6D65-7368-0000-000000000003")
    static let dataNotifyUUID = CBUUID(string: "6C696D65-6D65-7368-0000-000000000004")
    static let psmUUID = CBUUID(string: "6C696D65-6D65-7368-0000-000000000005")
    static let centralRestoreID = "org.famkind.lime.mesh.central"
    static let peripheralRestoreID = "org.famkind.lime.mesh.peripheral"
    static let protocolVersion: UInt8 = 1

    private(set) var running = false
    /// Nearby mode (LIME-143): scan all the time, no duty cycle.
    private(set) var continuousScan = false
    private(set) var bluetoothState = "off"
    private(set) var peerCount = 0
    private(set) var scanMode = "off"

    @ObservationIgnored var identity = MeshLinkIdentity()
    @ObservationIgnored var registry = MeshLinkRegistry()
    /// The engine's driver, once the store is open (frames that arrive before are held, up to a few).
    @ObservationIgnored var driver: MeshDriver? { didSet { if driver != nil { flushHeld() } } }
    @ObservationIgnored var onLog: (String, [String: String]) -> Void = { _, _ in }
    @ObservationIgnored var onPeersChanged: (() -> Void)?

    // The central side.
    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var handshakes: [UUID: Handshake] = [:]
    @ObservationIgnored private var rejectedUntil: [UUID: Date] = [:]
    /// Links I started that dropped: connect again once iOS has let go of them (a pending connect never times out and is completed in range, in the background too).
    @ObservationIgnored private var reconnect: Set<UUID> = []
    /// The wait before connecting again to each phone, and when the next attempt may start (LIME-141-fix2).
    @ObservationIgnored private var backoffs: [UUID: ReconnectBackoff] = [:]
    @ObservationIgnored private var notBefore: [UUID: Date] = [:]
    @ObservationIgnored private var storm = ReconnectStormGuard()
    /// L2CAP channels that arrived before their phone's hello was handled.
    @ObservationIgnored private var pendingChannels = PendingChannels<CBL2CAPChannel>()
    /// How long a phone with the higher id waits for the lower-id phone to connect before keeping its own link (a locked phone cannot connect).
    static let fallbackGraceSeconds = 15
    // The peripheral side.
    @ObservationIgnored private var peripheralManager: CBPeripheralManager?
    @ObservationIgnored private var notifyCharacteristic: CBMutableCharacteristic?
    @ObservationIgnored private var psm: CBL2CAPPSM?
    /// Centrals that have written their hello: their link id, and whether they have subscribed to notifications.
    @ObservationIgnored private var inboundCentrals: [UUID: (remote: UInt64, subscribed: Bool, central: CBCentral?)] = [:]
    // Links, by the remote phone's link id.
    @ObservationIgnored private var peers: [UInt64: Peer] = [:]
    @ObservationIgnored private var held: [(UInt64, Data)] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var dutyTask: Task<Void, Never>?
    @ObservationIgnored private var lastPeerSeen = Date()
    @ObservationIgnored private var inBackground = false

    /// What is known about a phone while meeting it.
    fileprivate final class Handshake {
        let peripheral: CBPeripheral
        var hello: CBCharacteristic?
        var write: CBCharacteristic?
        var notify: CBCharacteristic?
        var psm: CBCharacteristic?
        var remote: UInt64?
        var wroteHello = false
        var subscribed = false
        /// When this handshake began, and how far it got (`connected`, `services`, `characteristics`, `hello`): so a stall says where it stalled.
        let since = Date()
        var stage = "connected"
        init(peripheral: CBPeripheral) { self.peripheral = peripheral }
    }

    /// One kept link to one phone.
    fileprivate final class Peer {
        let remote: UInt64
        let iAmCentral: Bool
        var peripheral: CBPeripheral?
        var write: CBCharacteristic?
        var central: CBCentral?
        var streams: MeshStreams?
        var reader = MeshStreamReader()
        var reassembler = MeshReassembler()
        var gatt: [Data] = []
        var writing = false
        var stream = Data()
        var nextFragment: UInt16 = 0
        var up = false
        var upAt: Date?
        /// A frame came over this link (it works: not a failure however short).
        var carriedFrame = false
        /// The PSM read while the link was not up yet: the channel opens once it is (the hello written and the subscription done).
        var pendingPSM: CBL2CAPPSM?
        init(remote: UInt64, iAmCentral: Bool) { self.remote = remote; self.iAmCentral = iAmCentral }
    }

    // MARK: Start and stop

    func start() {
        guard !running else { return }
        running = true
        lastPeerSeen = Date()
        watchApp()
        onLog("start", ["central": Self.centralRestoreID, "id": MeshDriver.short(identity.id)])
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionRestoreIdentifierKey: Self.centralRestoreID])
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main, options: [CBPeripheralManagerOptionRestoreIdentifierKey: Self.peripheralRestoreID])
    }

    func stop() {
        guard running else { return }
        running = false
        dutyTask?.cancel()
        central?.stopScan()
        peripheralManager?.stopAdvertising()
        for peripheral in peripherals.values { central?.cancelPeripheralConnection(peripheral) }
        reconnect = []
        for peer in peers.values { peer.streams?.close(); driver?.linkDown(peer.remote) }
        if let psm { peripheralManager?.unpublishL2CAPChannel(psm) }
        peers = [:]; peripherals = [:]; handshakes = [:]; inboundCentrals = [:]; registry = MeshLinkRegistry()
        central = nil; peripheralManager = nil; notifyCharacteristic = nil; psm = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        scanMode = "off"
        updateCount()
        onLog("stop", [:])
    }

    private func watchApp() {
        let center = NotificationCenter.default
        let names: [(Notification.Name, String)] = [
            (UIApplication.didEnterBackgroundNotification, "background"), (UIApplication.willEnterForegroundNotification, "foreground"),
            (UIApplication.didBecomeActiveNotification, "active"), (UIApplication.protectedDataWillBecomeUnavailableNotification, "locking"),
            (UIApplication.protectedDataDidBecomeAvailableNotification, "unlocked"),
        ]
        for (name, phase) in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.onLog("app", ["phase": phase])
                    if phase == "background" { self.inBackground = true }
                    if phase == "foreground" || phase == "active" { self.inBackground = false; self.startScan(continuous: true); self.wake("app-\(phase)") }
                }
            })
        }
    }

    /// A wake that may call for re-announcing the live links (the driver debounces). **Not** for data arriving: that is never a wake.
    private func wake(_ reason: String) {
        rotateIdentityIfIdle()
        driver?.wake(reason: reason)
    }

    /// The link id changes every 15 minutes, but **not while a link is live**: a phone that changed its id under an open link would be
    /// registered under two ids, and the policy that keeps one link per pair would tear it down.
    private func rotateIdentityIfIdle() {
        guard peers.isEmpty, registry.live.isEmpty else { return }
        identity.rotateIfDue(now: Date())
    }

    private func updateCount() {
        peerCount = peers.values.filter(\.up).count
        onPeersChanged?()
    }

    // MARK: Scanning (the duty cycle)

    /// Nearby mode on: scan continuously (no 10-on/20-off duty cycle). Off: the duty cycle may resume.
    func setContinuousScan(_ on: Bool) {
        continuousScan = on
        if running { startScan(continuous: true) }
    }

    /// Foreground and busy: scan all the time. Idle for two minutes in the foreground: 10 seconds on, 20 off, until a phone shows up or the app
    /// leaves the foreground. In the background iOS runs its own service-filtered scan and the app does not control it, so it is left running.
    private func startScan(continuous: Bool) {
        guard running, let central, central.state == .poweredOn else { return }
        // The service filter is required for scanning in the background; duplicates are not reported there.
        central.scanForPeripherals(withServices: [Self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanMode = continuous ? "scanning" : "duty-on"
        dutyTask?.cancel()
        dutyTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(continuous ? 30 : 10))
                guard let self, self.running, !Task.isCancelled else { return }
                let idle = Date().timeIntervalSince(self.lastPeerSeen) > 120 && self.peers.isEmpty && !self.inBackground && !self.continuousScan
                if idle {
                    self.central?.stopScan(); self.scanMode = "duty-off"; self.onLog("scan_cycle", ["mode": "off", "seconds": "20"])
                    try? await Task.sleep(for: .seconds(20))
                    guard !Task.isCancelled, self.running else { return }
                    self.central?.scanForPeripherals(withServices: [Self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
                    self.scanMode = "duty-on"; self.onLog("scan_cycle", ["mode": "on", "seconds": "10"])
                } else if self.scanMode != "scanning" {
                    self.scanMode = "scanning"
                }
            }
        }
    }

    // MARK: Hello

    private var helloValue: Data {
        var id = identity.id.bigEndian
        return withUnsafeBytes(of: &id) { Data($0) } + Data([Self.protocolVersion])
    }

    private static func remoteID(from data: Data) -> UInt64? {
        guard data.count >= 8 else { return nil }
        return data.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    // MARK: Sending and receiving

    /// The driver's way out: one frame to the phone with this link id.
    func transmit(_ link: UInt64, _ bytes: Data) {
        guard let peer = peers[link] else { return }
        if let streams = peer.streams, streams.isOpen {
            peer.stream.append(MeshStreamFramer.encode(bytes))
            pumpStream(peer)
        } else {
            let id = peer.nextFragment
            peer.nextFragment &+= 1
            peer.gatt.append(contentsOf: MeshFragmenter.split(bytes, id: id, fragmentBytes: fragmentBytes(for: peer)))
            pumpGATT(peer)
        }
    }

    private func fragmentBytes(for peer: Peer) -> Int {
        if let peripheral = peer.peripheral { return min(MeshFraming.fragmentBytes, peripheral.maximumWriteValueLength(for: .withResponse)) }
        if let central = peer.central { return min(MeshFraming.fragmentBytes, central.maximumUpdateValueLength) }
        return MeshFraming.fragmentBytes
    }

    private func pumpGATT(_ peer: Peer) {
        if let peripheral = peer.peripheral, let write = peer.write {
            guard !peer.writing, !peer.gatt.isEmpty else { return }
            peer.writing = true
            peripheral.writeValue(peer.gatt.removeFirst(), for: write, type: .withResponse)
        } else if let central = peer.central, let characteristic = notifyCharacteristic, let manager = peripheralManager {
            while let next = peer.gatt.first {
                if !manager.updateValue(next, for: characteristic, onSubscribedCentrals: [central]) { return }
                peer.gatt.removeFirst()
            }
        }
    }

    fileprivate func pumpStream(_ peer: Peer) {
        guard let streams = peer.streams, streams.isOpen else { return }
        while !peer.stream.isEmpty, streams.hasSpace {
            let written = streams.write(peer.stream)
            if written <= 0 { break }
            peer.stream = peer.stream.subdata(in: written..<peer.stream.count)
        }
    }

    fileprivate func streamBytes(_ data: Data, from peer: Peer) {
        for frame in peer.reader.append(data) { deliver(frame, from: peer) }
        if peer.reader.overflowed { onLog("stream_overflow", ["link": MeshDriver.short(peer.remote)]); close(peer, why: "overflow") }
    }

    fileprivate func gattBytes(_ data: Data, from peer: Peer) {
        if let frame = peer.reassembler.accept(data, now: Date()) { deliver(frame, from: peer) }
    }

    private func deliver(_ frame: Data, from peer: Peer) {
        peer.carriedFrame = true
        if let driver { driver.receive(frame, on: peer.remote) } else if held.count < 16 { held.append((peer.remote, frame)) }
    }

    private func flushHeld() {
        let pending = held
        held = []
        for (link, frame) in pending where peers[link] != nil { driver?.receive(frame, on: link) }
        for peer in peers.values where peer.up { driver?.linkUp(peer.remote) }
    }

    // MARK: Links

    /// The link to this phone is kept and usable: tell the engine.
    private func up(_ peer: Peer) {
        guard !peer.up else { return }
        peer.up = true
        peer.upAt = Date()
        lastPeerSeen = Date()
        updateCount()
        onLog("peer_up", ["link": MeshDriver.short(peer.remote), "role": peer.iAmCentral ? "central" : "peripheral"])
        driver?.linkUp(peer.remote)
    }

    private func close(_ peer: Peer, why: String) {
        peer.streams?.close()
        peers[peer.remote] = nil
        registry.release(remote: peer.remote)
        if peer.up { driver?.linkDown(peer.remote) }
        onLog("peer_down", ["link": MeshDriver.short(peer.remote), "why": why])
        updateCount()
        if let peripheral = peer.peripheral {
            // A link I started and lost: connect again once iOS has let go of this one (the disconnect callback does it), after a wait that
            // grows with every link that fails (one that ended within 2 s of opening counts as a failure; one that lasted 30 s starts over).
            if running, why != "stop", why != "tie-break" {
                reconnect.insert(peripheral.identifier)
                var backoff = backoffs[peripheral.identifier] ?? ReconnectBackoff()
                backoff.linkEnded(livedFor: peer.upAt.map { Date().timeIntervalSince($0) }, carriedFrame: peer.carriedFrame)
                backoffs[peripheral.identifier] = backoff
            }
            central?.cancelPeripheralConnection(peripheral)
        }
    }

    fileprivate func streamClosed(_ peer: Peer, why: String) { close(peer, why: "l2cap-\(why)") }

    private func name(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn: "poweredOn"
        case .poweredOff: "poweredOff"
        case .unauthorized: "unauthorized"
        case .unsupported: "unsupported"
        case .resetting: "resetting"
        default: "unknown"
        }
    }

    private func peerFor(peripheral: CBPeripheral) -> Peer? { peers.values.first { $0.peripheral === peripheral } }
    private func peerFor(central: CBCentral) -> Peer? { peers.values.first { $0.central?.identifier == central.identifier } }

    private func openChannel(_ channel: CBL2CAPChannel, for peer: Peer) {
        let streams = MeshStreams(channel: channel, owner: self, peer: peer)
        peer.streams = streams
        streams.open()
        onLog("l2cap_open", ["link": MeshDriver.short(peer.remote), "psm": String(channel.psm)])
        // What was waiting on GATT can go over the channel from now on; frames already in GATT fragments finish there.
    }
}

/// An L2CAP channel's two streams.
@MainActor
final class MeshStreams: NSObject, @preconcurrency StreamDelegate {
    let channel: CBL2CAPChannel
    private weak var owner: MeshBluetooth?
    fileprivate let peer: AnyObject
    private(set) var isOpen = false

    fileprivate init(channel: CBL2CAPChannel, owner: MeshBluetooth, peer: AnyObject) {
        self.channel = channel; self.owner = owner; self.peer = peer
        super.init()
    }

    func open() {
        for stream in [channel.inputStream, channel.outputStream] as [Stream?] {
            stream?.delegate = self
            stream?.schedule(in: .main, forMode: .default)
            stream?.open()
        }
        isOpen = true
    }

    func close() {
        isOpen = false
        for stream in [channel.inputStream, channel.outputStream] as [Stream?] {
            stream?.delegate = nil
            stream?.close()
            stream?.remove(from: .main, forMode: .default)
        }
    }

    var hasSpace: Bool { channel.outputStream.hasSpaceAvailable }

    func write(_ data: Data) -> Int {
        data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return max(channel.outputStream.write(base, maxLength: data.count), 0)
        }
    }

    func stream(_ stream: Stream, handle event: Stream.Event) {
        guard let owner, let peer = peer as? MeshBluetooth.PeerHandle else { return }
        switch event {
        case .hasBytesAvailable:
            guard let input = stream as? InputStream else { return }
            var buffer = [UInt8](repeating: 0, count: 8_192)
            while input.hasBytesAvailable {
                let count = input.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                owner.received(Data(buffer.prefix(count)), from: peer)
            }
        case .hasSpaceAvailable:
            owner.canWrite(peer)
        case .endEncountered, .errorOccurred:
            owner.closed(peer, why: event == .endEncountered ? "end" : "error")
        default:
            break
        }
    }
}

extension MeshBluetooth {
    /// A narrow handle for the streams (the `Peer` type is private to this file).
    fileprivate typealias PeerHandle = Peer
    fileprivate func received(_ data: Data, from peer: Peer) { streamBytes(data, from: peer) }
    fileprivate func canWrite(_ peer: Peer) { pumpStream(peer) }
    fileprivate func closed(_ peer: Peer, why: String) { streamClosed(peer, why: why) }
}

// MARK: The central side (we scan and connect)

extension MeshBluetooth: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ manager: CBCentralManager) {
        bluetoothState = name(manager.state)
        onLog("central_state", ["state": bluetoothState])
        guard manager.state == .poweredOn else { return }
        startScan(continuous: true)
        onLog("scan_start", [:])
    }

    func centralManager(_ manager: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral]) ?? []
        onLog("restore_central", ["peripherals": String(restored.count), "id": Self.centralRestoreID])
        for peripheral in restored {
            peripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
        }
        wake("restore-central")
    }

    func centralManager(_ manager: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        lastPeerSeen = Date()
        let rssi = RSSI.intValue
        guard MeshLinkPolicy.rssiAllowsConnecting(rssi) else { onLog("skip_weak", ["rssi": String(rssi)]); return }
        if let until = rejectedUntil[peripheral.identifier], until > Date() { return }
        guard handshakes[peripheral.identifier] == nil, peerFor(peripheral: peripheral) == nil, peripheral.state == .disconnected else { return }
        if let until = notBefore[peripheral.identifier], until > Date() { return }
        peripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        wake("discover-new")
        onLog("connecting", ["rssi": String(rssi)])
        connectNow(peripheral)
    }

    /// Starts a connection (the one place that does), and counts it for the storm guard.
    private func connectNow(_ peripheral: CBPeripheral) {
        handshakes[peripheral.identifier] = Handshake(peripheral: peripheral)
        if storm.record(at: Date()) { onLog("WARNING reconnect storm", ["per_minute": String(storm.perMinute)]) }
        central?.connect(peripheral)
    }

    func centralManager(_ manager: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onLog("connected", ["writeMTU": String(peripheral.maximumWriteValueLength(for: .withResponse))])
        if handshakes[peripheral.identifier] == nil, peerFor(peripheral: peripheral) == nil { handshakes[peripheral.identifier] = Handshake(peripheral: peripheral) }
        peripheral.discoverServices([Self.serviceUUID])
        watchHandshake(peripheral)
    }

    /// An outbound handshake that has not read the other phone's hello in 10 s is dropped, with where it stalled in the log (it used to wait for
    /// ever, the other side hanging up a minute or two later). It counts as a failure for the backoff, and after two in a row the phone is not
    /// dialled for a minute, so the other phone's fallback link can form instead of both half-trying for ever (LIME-141-fix4).
    private func watchHandshake(_ peripheral: CBPeripheral) {
        let id = peripheral.identifier
        guard let started = handshakes[id]?.since else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(MeshHandshakeWatchdog.timeout))
            guard let self, self.running, let handshake = self.handshakes[id], handshake.since == started, handshake.remote == nil else { return }
            self.onLog("handshake_timeout", ["stage": handshake.stage, "seconds": String(Int(MeshHandshakeWatchdog.timeout))])
            var backoff = self.backoffs[id] ?? ReconnectBackoff()
            backoff.linkEnded(livedFor: nil)
            self.backoffs[id] = backoff
            let pause = MeshHandshakeWatchdog.pause(afterFailures: backoff.failures)
            let wait = max(pause, backoff.delay())
            self.notBefore[id] = Date().addingTimeInterval(wait)
            if pause > 0 { self.onLog("outbound_paused", ["seconds": String(Int(pause)), "failures": String(backoff.failures)]) }
            self.handshakes[id] = nil
            self.central?.cancelPeripheralConnection(peripheral)
        }
    }

    func centralManager(_ manager: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        onLog("connect_failed", ["error": error?.localizedDescription ?? "?"])
        handshakes[peripheral.identifier] = nil
    }

    func centralManager(_ manager: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        onLog("disconnected", ["error": error?.localizedDescription ?? "none"])
        handshakes[peripheral.identifier] = nil
        if let peer = peerFor(peripheral: peripheral) { close(peer, why: "disconnected") }
        // Connecting again never times out: iOS completes it when the phone is next in range, in the background too. (Only for links I started.)
        if running, reconnect.remove(peripheral.identifier) != nil {
            let id = peripheral.identifier
            let wait = (backoffs[id] ?? ReconnectBackoff()).delay()
            notBefore[id] = Date().addingTimeInterval(wait)
            onLog("reconnecting", ["in_ms": String(Int(wait * 1000)), "failures": String(backoffs[id]?.failures ?? 0)])
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(Int(wait * 1000)))
                guard let self, self.running, self.handshakes[id] == nil, self.peerFor(peripheral: peripheral) == nil, peripheral.state == .disconnected else { return }
                self.connectNow(peripheral)
            }
        }
    }
}

extension MeshBluetooth: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        handshakes[peripheral.identifier]?.stage = "services"
        if let started = handshakes[peripheral.identifier]?.since { onLog("handshake_stage", ["stage": "services", "ms": String(Int(Date().timeIntervalSince(started) * 1000))]) }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            onLog("service_missing", ["error": error?.localizedDescription ?? "none"])
            return
        }
        peripheral.discoverCharacteristics([Self.helloUUID, Self.dataWriteUUID, Self.dataNotifyUUID, Self.psmUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let handshake = handshakes[peripheral.identifier], let characteristics = service.characteristics else { return }
        handshake.stage = "characteristics"
        onLog("handshake_stage", ["stage": "characteristics", "ms": String(Int(Date().timeIntervalSince(handshake.since) * 1000))])
        handshake.hello = characteristics.first { $0.uuid == Self.helloUUID }
        handshake.write = characteristics.first { $0.uuid == Self.dataWriteUUID }
        handshake.notify = characteristics.first { $0.uuid == Self.dataNotifyUUID }
        handshake.psm = characteristics.first { $0.uuid == Self.psmUUID }
        guard let hello = handshake.hello else { return }
        peripheral.readValue(for: hello)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value else { return }
        if characteristic.uuid == Self.helloUUID, let handshake = handshakes[peripheral.identifier] {
            guard let remote = Self.remoteID(from: value) else { return }
            handshake.remote = remote
            handshake.stage = "hello"
            backoffs[peripheral.identifier]?.linkEnded(livedFor: ReconnectBackoff.stable) // the hello came: the handshake works (resets the dial-out count)
            switch registry.claim(remote: remote, local: identity.id, iAmCentral: true) {
            case .keep:
                establish(peripheral, handshake, remote: remote, how: "hello_keep")
            case .wrongDirection:
                // The other phone should connect to me. If it has not within the grace period (it may be locked), keep this link after all.
                onLog("hello_wait", ["link": MeshDriver.short(remote), "grace": String(Self.fallbackGraceSeconds)])
                let id = peripheral.identifier
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(Self.fallbackGraceSeconds))
                    // Both phones connecting to each other: the one with the lower id keeps its outbound link; this one (the higher id) takes
                    // the other phone's inbound instead of making a second link of its own.
                    if let self, self.inboundCentrals.values.contains(where: { $0.remote == remote }), !MeshTieBreak.keepsOutbound(local: self.identity.id, remote: remote) {
                        self.onLog("tie_break", ["kept": "inbound", "link": MeshDriver.short(remote)])
                        self.handshakes[id] = nil
                        self.central?.cancelPeripheralConnection(peripheral)
                        return
                    }
                    guard let self, self.running, let waiting = self.handshakes[id], waiting.remote == remote, peripheral.state == .connected,
                          self.peers[remote] == nil, self.registry.claimFallback(remote: remote, local: self.identity.id) else {
                        if let self, self.handshakes[id]?.remote == remote, self.peers[remote] == nil {
                            self.onLog("hello_drop", ["why": "wrongDirection-after-grace"])
                            self.rejectedUntil[id] = Date().addingTimeInterval(60)
                            self.handshakes[id] = nil
                            self.central?.cancelPeripheralConnection(peripheral)
                        }
                        return
                    }
                    self.establish(peripheral, waiting, remote: remote, how: "hello_fallback")
                }
            case let verdict:
                // A link to that phone exists already (or it is me): close this one and do not come back at once.
                onLog("hello_drop", ["why": "\(verdict)"])
                rejectedUntil[peripheral.identifier] = Date().addingTimeInterval(60)
                handshakes[peripheral.identifier] = nil
                central?.cancelPeripheralConnection(peripheral)
            }
        } else if characteristic.uuid == Self.psmUUID, value.count >= 2, let peer = peerFor(peripheral: peripheral) {
            // The channel opens only once the hello is written and the subscription is on (the link is up): a channel that races ahead of
            // them reaches a phone that cannot bind it yet (LIME-141-fix3). If the link is not up, `checkReady` opens it.
            let channel = CBL2CAPPSM(value.prefix(2).reduce(UInt16(0)) { ($0 << 8) | UInt16($1) })
            if peer.up { peripheral.openL2CAPChannel(channel) } else { peer.pendingPSM = channel }
        } else if characteristic.uuid == Self.dataNotifyUUID, let peer = peerFor(peripheral: peripheral) {
            gattBytes(value, from: peer)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let peer = peerFor(peripheral: peripheral) else { return }
        if characteristic.uuid == Self.helloUUID {
            handshakes[peripheral.identifier]?.wroteHello = true
            checkReady(peripheral)
        } else {
            peer.writing = false
            if let error { onLog("write_failed", ["error": error.localizedDescription]) }
            pumpGATT(peer)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        onLog("notify_state", ["on": String(characteristic.isNotifying), "error": error?.localizedDescription ?? "none"])
        handshakes[peripheral.identifier]?.subscribed = characteristic.isNotifying
        checkReady(peripheral)
    }

    /// This central link is kept: register it, give the other phone my id, subscribe, read the PSM.
    private func establish(_ peripheral: CBPeripheral, _ handshake: Handshake, remote: UInt64, how: String) {
        onLog(how, ["link": MeshDriver.short(remote)])
        let peer = Peer(remote: remote, iAmCentral: true)
        peer.peripheral = peripheral
        peer.write = handshake.write
        peers[remote] = peer
        if let hello = handshake.hello { peripheral.writeValue(helloValue, for: hello, type: .withResponse) }
        if let notify = handshake.notify { peripheral.setNotifyValue(true, for: notify) }
        if let psmCharacteristic = handshake.psm { peripheral.readValue(for: psmCharacteristic) }
    }

    private func checkReady(_ peripheral: CBPeripheral) {
        guard let handshake = handshakes[peripheral.identifier], handshake.wroteHello, handshake.subscribed, let remote = handshake.remote, let peer = peers[remote] else { return }
        handshakes[peripheral.identifier] = nil
        up(peer)
        if let psm = peer.pendingPSM { peer.pendingPSM = nil; peripheral.openL2CAPChannel(psm) }
    }

    func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {
        if let channel, let peer = peerFor(peripheral: peripheral) { openChannel(channel, for: peer) }
        else { onLog("l2cap_failed", ["error": error?.localizedDescription ?? "?"]) }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        onLog("services_modified", [:])
        if handshakes[peripheral.identifier] == nil, peerFor(peripheral: peripheral) == nil { handshakes[peripheral.identifier] = Handshake(peripheral: peripheral) }
        peripheral.discoverServices([Self.serviceUUID])
    }
}

// MARK: The peripheral side (we advertise and accept)

extension MeshBluetooth: @preconcurrency CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ manager: CBPeripheralManager) {
        onLog("peripheral_state", ["state": name(manager.state)])
        guard manager.state == .poweredOn else { return }
        let hello = CBMutableCharacteristic(type: Self.helloUUID, properties: [.read, .write], value: nil, permissions: [.readable, .writeable])
        let write = CBMutableCharacteristic(type: Self.dataWriteUUID, properties: [.write], value: nil, permissions: [.writeable])
        let notify = CBMutableCharacteristic(type: Self.dataNotifyUUID, properties: [.notify], value: nil, permissions: [.readable])
        let psm = CBMutableCharacteristic(type: Self.psmUUID, properties: [.read], value: nil, permissions: [.readable])
        notifyCharacteristic = notify
        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [hello, write, notify, psm]
        manager.add(service)
        manager.publishL2CAPChannel(withEncryption: false)
    }

    func peripheralManager(_ manager: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        let services = (dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService]) ?? []
        onLog("restore_peripheral", ["services": String(services.count), "id": Self.peripheralRestoreID, "advertising": String(dict[CBPeripheralManagerRestoredStateAdvertisementDataKey] != nil)])
        wake("restore-peripheral")
    }

    func peripheralManager(_ manager: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        onLog("service_added", ["error": error?.localizedDescription ?? "none"])
        // The advertisement is the service UUID and nothing else: no name, no id (in the background it goes in the "overflow" area).
        manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]])
    }

    func peripheralManagerDidStartAdvertising(_ manager: CBPeripheralManager, error: Error?) {
        onLog("advertising", ["error": error?.localizedDescription ?? "none"])
    }

    func peripheralManager(_ manager: CBPeripheralManager, didPublishL2CAPChannel PSM: CBL2CAPPSM, error: Error?) {
        psm = PSM
        onLog("l2cap_published", ["psm": String(PSM), "error": error?.localizedDescription ?? "none"])
    }

    func peripheralManager(_ manager: CBPeripheralManager, didOpen channel: CBL2CAPChannel?, error: Error?) {
        guard let channel else { onLog("l2cap_failed", ["error": error?.localizedDescription ?? "?"]); return }
        if let peer = peers.values.first(where: { $0.central?.identifier == channel.peer.identifier }) { openChannel(channel, for: peer) }
        else {
            // The channel got here before the phone's hello was handled: keep it for a short grace and bind it when the peer appears.
            pendingChannels.hold(channel, from: channel.peer.identifier, at: Date())
            onLog("l2cap_pending", ["central_known": String(inboundCentrals[channel.peer.identifier] != nil)])
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(PendingChannels<CBL2CAPChannel>.grace + 0.1))
                guard let self else { return }
                for late in self.pendingChannels.expire(at: Date()) {
                    let entry = self.inboundCentrals[late.peer.identifier]
                    self.onLog("l2cap_unknown_peer", ["remote_known": String((entry?.remote ?? 0) != 0), "subscribed": String(entry?.subscribed ?? false),
                                                       "stale_peer": String(entry.map { self.peers[$0.remote] != nil } ?? false)])
                    late.inputStream?.close(); late.outputStream?.close()
                }
            }
        }
    }

    func peripheralManager(_ manager: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        var entry = inboundCentrals[central.identifier] ?? (remote: 0, subscribed: false, central: nil)
        entry.subscribed = true
        entry.central = central
        inboundCentrals[central.identifier] = entry
        attachInbound(central.identifier)
    }

    func peripheralManager(_ manager: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        inboundCentrals[central.identifier] = nil
        if let peer = peerFor(central: central) { close(peer, why: "unsubscribed") }
    }

    func peripheralManager(_ manager: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        if request.characteristic.uuid == Self.helloUUID {
            rotateIdentityIfIdle()
            request.value = helloValue.dropFirst(request.offset)
            manager.respond(to: request, withResult: .success)
        } else if request.characteristic.uuid == Self.psmUUID, let psm {
            request.value = Data([UInt8(psm >> 8), UInt8(psm & 0xFF)])
            manager.respond(to: request, withResult: .success)
        } else {
            manager.respond(to: request, withResult: .attributeNotFound)
        }
    }

    func peripheralManager(_ manager: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard let value = request.value else { continue }
            if request.characteristic.uuid == Self.helloUUID {
                guard let remote = Self.remoteID(from: value) else { continue }
                var entry = inboundCentrals[request.central.identifier] ?? (remote: 0, subscribed: false, central: nil)
                entry.remote = remote
                entry.central = request.central
                inboundCentrals[request.central.identifier] = entry
                attachInbound(request.central.identifier)
            } else if request.characteristic.uuid == Self.dataWriteUUID, let peer = peerFor(central: request.central) {
                gattBytes(value, from: peer)
            }
        }
        if let first = requests.first { manager.respond(to: first, withResult: .success) }
    }

    /// A central has written its hello and subscribed: it is a link, if the policy keeps it.
    private func attachInbound(_ id: UUID) {
        guard let entry = inboundCentrals[id], entry.remote != 0, entry.subscribed, let central = entry.central else { return }
        if let existing = peers[entry.remote] {
            // A link to this phone that is not live any more (my own connection to it dropped without telling me) blocks the new one for
            // good; drop it and carry on. A live one stays, and the new inbound is refused (logged: it used to vanish without a trace).
            let live = existing.up && (existing.central != nil || existing.peripheral?.state == .connected)
            if live, existing.iAmCentral {
                // Each phone connected to the other: the lower id keeps its outbound link and refuses this inbound; the higher id drops its
                // outbound and takes this one. Both compute the same answer, so one link is left.
                if MeshTieBreak.keepsOutbound(local: identity.id, remote: entry.remote) {
                    onLog("tie_break", ["kept": "outbound", "link": MeshDriver.short(entry.remote)])
                    return
                }
                onLog("tie_break", ["kept": "inbound", "link": MeshDriver.short(entry.remote)])
                close(existing, why: "tie-break")
            } else {
                guard !live else { onLog("inbound_drop", ["why": "live-peer"]); return }
                close(existing, why: "stale")
            }
        }
        var verdict = registry.claim(remote: entry.remote, local: identity.id, iAmCentral: false)
        if verdict == .wrongDirection {
            // The other phone has the higher id and has waited its grace: this is its fallback. Take it unless I have a live link to it or an
            // outbound of my own that is still fresh; drop my stalled outbound handshakes first (they never finished and would race it).
            let fresh = handshakes.values.contains { Date().timeIntervalSince($0.since) < MeshInboundFallback.freshSeconds }
            if MeshInboundFallback.shouldAccept(hasLiveLink: registry.live.contains(entry.remote), freshOutboundHandshake: fresh), registry.claimFallback(remote: entry.remote, local: identity.id) {
                for (id, stale) in handshakes where stale.remote == nil || stale.remote == entry.remote {
                    handshakes[id] = nil
                    self.central?.cancelPeripheralConnection(stale.peripheral)
                }
                onLog("inbound_accept", ["why": "fallback", "link": MeshDriver.short(entry.remote)])
                verdict = .keep
            }
        }
        switch verdict {
        case .keep:
            let peer = Peer(remote: entry.remote, iAmCentral: false)
            peer.central = central
            peers[entry.remote] = peer
            up(peer)
            if let channel = pendingChannels.take(for: id, at: Date()) { openChannel(channel, for: peer) }
        case let verdict:
            onLog("inbound_drop", ["why": "\(verdict)"])
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers manager: CBPeripheralManager) {
        for peer in peers.values where peer.central != nil { pumpGATT(peer) }
    }
}
#endif
