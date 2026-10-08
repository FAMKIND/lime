#if DEBUG
@preconcurrency import CoreBluetooth
import CryptoKit
import Foundation
import Observation
import UIKit

/// One open way to reach a nearby phone: a GATT write (we are the central), a GATT notify (they are the
/// central, we are the peripheral), or an L2CAP channel.
@MainActor
final class NearbyLink: Identifiable {
    enum Kind: String { case gattWrite, gattNotify, l2cap }

    let id = UUID()
    let kind: Kind
    let label: String
    var remoteTag: String?
    var reader = NearbyFrameReader()
    var queue: [NearbyOutgoing] = []
    var current: NearbyOutgoing?
    var writing = false
    // GATT, as the central.
    var peripheral: CBPeripheral?
    var writeCharacteristic: CBCharacteristic?
    // GATT, as the peripheral.
    var central: CBCentral?
    // L2CAP.
    var streams: NearbyStreams?
    var remoteID: UUID?

    init(kind: Kind, label: String) {
        self.kind = kind
        self.label = label
    }

    var transport: String { kind == .l2cap ? "l2cap" : "gatt" }
}

/// A frame being sent over one link, and how far it has got.
@MainActor
final class NearbyOutgoing {
    let kind: NearbyFrame.Kind
    let blobID: String
    let data: Data
    let size: Int
    var offset = 0
    let queuedAt = Date()
    var startedAt: Date?

    init(kind: NearbyFrame.Kind, blobID: String, data: Data, size: Int) {
        self.kind = kind
        self.blobID = blobID
        self.data = data
        self.size = size
    }
}

/// An L2CAP channel's two byte streams.
@MainActor
final class NearbyStreams: NSObject, @preconcurrency StreamDelegate {
    let channel: CBL2CAPChannel
    unowned let link: NearbyLink
    weak var owner: NearbyTransport?

    init(channel: CBL2CAPChannel, link: NearbyLink, owner: NearbyTransport) {
        self.channel = channel
        self.link = link
        self.owner = owner
        super.init()
    }

    func open() {
        for stream in [channel.inputStream, channel.outputStream] as [Stream?] {
            stream?.delegate = self
            stream?.schedule(in: .main, forMode: .default)
            stream?.open()
        }
    }

    func close() {
        for stream in [channel.inputStream, channel.outputStream] as [Stream?] {
            stream?.delegate = nil
            stream?.close()
            stream?.remove(from: .main, forMode: .default)
        }
    }

    var hasSpace: Bool { channel.outputStream.hasSpaceAvailable }

    func write(_ data: Data, from offset: Int) -> Int {
        data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return max(channel.outputStream.write(base + offset, maxLength: data.count - offset), 0)
        }
    }

    func stream(_ stream: Stream, handle event: Stream.Event) {
        switch event {
        case .hasBytesAvailable:
            guard let input = stream as? InputStream else { return }
            var buffer = [UInt8](repeating: 0, count: 8_192)
            while input.hasBytesAvailable {
                let count = input.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                owner?.received(Data(buffer.prefix(count)), on: link)
            }
        case .hasSpaceAvailable:
            owner?.pump(link)
        case .endEncountered, .errorOccurred:
            owner?.closed(link, why: event == .endEncountered ? "end" : "error")
        default:
            break
        }
    }
}

/// The spike's Bluetooth: every phone is both a peripheral (advertising one service) and a central
/// (scanning for it), and talks over GATT (write with response, notify) and an L2CAP channel, so the
/// field test can compare them. Everything is logged with timestamps; nothing is a real message.
@MainActor
@Observable
final class NearbyTransport: NSObject {
    enum Mode: String, CaseIterable, Identifiable {
        case gatt, l2cap, both
        var id: String { rawValue }
        var title: String { self == .gatt ? "GATT" : self == .l2cap ? "L2CAP" : "Both" }
    }

    static let serviceUUID = CBUUID(string: "6C696D65-6E65-6172-6279-000000000001")
    static let writeUUID = CBUUID(string: "6C696D65-6E65-6172-6279-000000000002")
    static let notifyUUID = CBUUID(string: "6C696D65-6E65-6172-6279-000000000003")
    static let psmUUID = CBUUID(string: "6C696D65-6E65-6172-6279-000000000004")
    static let tagUUID = CBUUID(string: "6C696D65-6E65-6172-6279-000000000005")
    static let centralRestoreID = "org.famkind.lime.nearby.central"
    static let peripheralRestoreID = "org.famkind.lime.nearby.peripheral"

    let log: NearbyLog
    private(set) var running = false
    private(set) var bluetoothState = "off"
    private(set) var links: [NearbyLink] = []
    private(set) var sent = 0
    private(set) var received = 0
    private(set) var duplicates = 0
    private(set) var invalid = 0
    var mode: Mode = .both
    /// When a phone says hello, send it a 200 B and a 4 KB blob once (so a backgrounded or locked phone is tested by what Bluetooth itself wakes).
    var sendOnConnect = true
    /// This run's random tag: lets two links to the same phone be told apart (it identifies nothing).
    let tag: String

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripheralManager: CBPeripheralManager?
    @ObservationIgnored private var notifyCharacteristic: CBMutableCharacteristic?
    @ObservationIgnored private var psm: CBL2CAPPSM?
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var reconnects: [UUID: Int] = [:]
    @ObservationIgnored private var inbound: [UUID: NearbyFrameReader] = [:]
    @ObservationIgnored private var seen: Set<String> = []
    @ObservationIgnored private var greeted: Set<String> = []
    @ObservationIgnored private let key = NearbyBlob.signingKey()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var runStarted = Date()

    init(log: NearbyLog) {
        self.log = log
        tag = (0..<4).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        super.init()
    }

    var linkLines: [String] {
        links.map { "\($0.label) · \($0.remoteTag ?? "?") · \($0.kind.rawValue)" }
    }

    // MARK: Start and stop

    func start(label: String) {
        guard !running else { return }
        running = true
        runStarted = Date()
        sent = 0; received = 0; duplicates = 0; invalid = 0
        seen = []; greeted = []; reconnects = [:]
        log.begin(label: label, extra: [
            "centralRestoreID": Self.centralRestoreID, "peripheralRestoreID": Self.peripheralRestoreID,
            "service": Self.serviceUUID.uuidString, "tag": tag, "signer": NearbyBlob.fingerprint(key.publicKey.rawRepresentation),
            "mode": mode.rawValue, "sendOnConnect": sendOnConnect,
        ])
        watchApp()
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionRestoreIdentifierKey: Self.centralRestoreID])
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main, options: [CBPeripheralManagerOptionRestoreIdentifierKey: Self.peripheralRestoreID])
        log.record("started", ["label": label])
    }

    func stop() {
        guard running else { return }
        running = false
        central?.stopScan()
        peripheralManager?.stopAdvertising()
        for peripheral in peripherals.values { central?.cancelPeripheralConnection(peripheral) }
        for link in links { link.streams?.close() }
        if let psm { peripheralManager?.unpublishL2CAPChannel(psm) }
        links = []
        peripherals = [:]
        central = nil
        peripheralManager = nil
        notifyCharacteristic = nil
        psm = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        log.end(summary: ["seconds": Int(Date().timeIntervalSince(runStarted)), "sent": sent, "received": received,
                          "duplicates": duplicates, "invalid": invalid, "reconnects": reconnects.values.reduce(0, +)])
    }

    private func watchApp() {
        let center = NotificationCenter.default
        let names: [(Notification.Name, String)] = [
            (UIApplication.didEnterBackgroundNotification, "background"), (UIApplication.willEnterForegroundNotification, "foreground"),
            (UIApplication.didBecomeActiveNotification, "active"), (UIApplication.willResignActiveNotification, "inactive"),
            (UIApplication.protectedDataWillBecomeUnavailableNotification, "locking"), (UIApplication.protectedDataDidBecomeAvailableNotification, "unlocked"),
        ]
        for (name, phase) in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.log.record("app", ["phase": phase]) }
            })
        }
    }

    // MARK: Sending test blobs

    /// Makes a signed random blob and queues it on one link per nearby phone and transport.
    func sendTestBlob(bodySize: Int) {
        let blob = NearbyBlob.make(bodySize: bodySize, key: key)
        let id = NearbyBlob.id(of: blob)
        seen.insert(id)
        let chosen = linksForSending()
        guard !chosen.isEmpty else { log.record("send_skipped", ["blob": id, "size": bodySize, "why": "no link"]); return }
        let frame = NearbyFrame.encode(.blob, blob)
        for link in chosen {
            link.queue.append(NearbyOutgoing(kind: .blob, blobID: id, data: frame, size: bodySize))
            pump(link)
        }
    }

    /// One link per remote phone and transport class: the central's write link first, then notify.
    private func linksForSending() -> [NearbyLink] {
        var chosen: [String: NearbyLink] = [:]
        for link in links where link.remoteTag != nil || link.kind == .l2cap {
            if mode == .gatt && link.kind == .l2cap { continue }
            if mode == .l2cap && link.kind != .l2cap { continue }
            let group = "\(link.remoteTag ?? link.id.uuidString)|\(link.transport)"
            if let existing = chosen[group], existing.kind == .gattWrite || link.kind != .gattWrite { continue }
            chosen[group] = link
        }
        return Array(chosen.values)
    }

    // MARK: Pumping a link

    func pump(_ link: NearbyLink) {
        if link.current == nil, !link.queue.isEmpty {
            let next = link.queue.removeFirst()
            next.startedAt = Date()
            link.current = next
            if next.kind == .blob { log.record("send_start", ["blob": next.blobID, "size": next.size, "transport": link.transport, "link": link.kind.rawValue]) }
        }
        guard let current = link.current else { return }
        switch link.kind {
        case .gattWrite:
            guard !link.writing, let peripheral = link.peripheral, let characteristic = link.writeCharacteristic else { return }
            let chunk = min(peripheral.maximumWriteValueLength(for: .withResponse), current.data.count - current.offset)
            guard chunk > 0 else { return }
            link.writing = true
            peripheral.writeValue(current.data.subdata(in: current.offset..<current.offset + chunk), for: characteristic, type: .withResponse)
            current.offset += chunk
        case .gattNotify:
            guard let central = link.central, let characteristic = notifyCharacteristic, let manager = peripheralManager else { return }
            while current.offset < current.data.count {
                let chunk = min(central.maximumUpdateValueLength, current.data.count - current.offset)
                let part = current.data.subdata(in: current.offset..<current.offset + chunk)
                if !manager.updateValue(part, for: characteristic, onSubscribedCentrals: [central]) { return }
                current.offset += chunk
            }
            finish(link)
        case .l2cap:
            guard let streams = link.streams else { return }
            while current.offset < current.data.count, streams.hasSpace {
                let count = streams.write(current.data, from: current.offset)
                if count <= 0 { break }
                current.offset += count
            }
            if current.offset >= current.data.count { finish(link) }
        }
    }

    /// The current frame is fully handed to Bluetooth.
    private func finish(_ link: NearbyLink) {
        guard let done = link.current else { return }
        link.current = nil
        if done.kind == .blob {
            sent += 1
            let seconds = max(Date().timeIntervalSince(done.startedAt ?? done.queuedAt), 0.001)
            log.record("send_done", ["blob": done.blobID, "size": done.size, "bytes": done.data.count, "transport": link.transport, "link": link.kind.rawValue,
                                     "ms": Int(seconds * 1000), "kbps": Int(Double(done.data.count) * 8 / 1000 / seconds)])
        }
        pump(link)
    }

    private func hello(on link: NearbyLink) {
        link.queue.insert(NearbyOutgoing(kind: .hello, blobID: "hello", data: NearbyFrame.encode(.hello, Data(tag.utf8)), size: 0), at: 0)
        pump(link)
    }

    // MARK: Receiving

    func received(_ data: Data, on link: NearbyLink) {
        for (kind, payload, began) in link.reader.append(data) { handle(kind, payload, began: began, link: link) }
    }

    private func handle(_ kind: NearbyFrame.Kind, _ payload: Data, began: Date, link: NearbyLink) {
        switch kind {
        case .hello:
            let remote = String(decoding: payload, as: UTF8.self)
            link.remoteTag = remote
            log.record("hello", ["remote": remote, "link": link.kind.rawValue])
            if sendOnConnect, !greeted.contains(remote) {
                greeted.insert(remote)
                sendTestBlob(bodySize: 200)
                sendTestBlob(bodySize: 4_096)
            }
        case .blob:
            let id = NearbyBlob.id(of: payload)
            let now = Date()
            let ms = Int(now.timeIntervalSince(began) * 1000)
            guard let parsed = NearbyBlob.parse(payload) else {
                invalid += 1
                log.record("recv_bad", ["bytes": payload.count, "transport": link.transport, "why": "too short"])
                return
            }
            if seen.contains(id) {
                duplicates += 1
                log.record("recv_dup", ["blob": id, "bytes": payload.count, "transport": link.transport, "ms": ms])
                return
            }
            seen.insert(id)
            if parsed.valid { received += 1 } else { invalid += 1 }
            log.record("recv_done", ["blob": id, "size": parsed.bodySize, "bytes": payload.count, "transport": link.transport, "link": link.kind.rawValue,
                                     "ms": ms, "kbps": Int(Double(payload.count) * 8 / 1000 / max(Double(ms) / 1000, 0.001)),
                                     "signatureOK": parsed.valid, "signer": parsed.signer,
                                     // The phones' clocks are not synchronised: a rough latency only.
                                     "sentToReceivedMs": Int(Int64(now.timeIntervalSince1970 * 1000) - parsed.sentAtMs)])
        }
    }

    func closed(_ link: NearbyLink, why: String) {
        link.streams?.close()
        links.removeAll { $0 === link }
        log.record("link_closed", ["link": link.kind.rawValue, "why": why, "remote": link.remoteTag ?? "?"])
    }

    // MARK: Adding links

    private func add(_ link: NearbyLink) {
        links.append(link)
    }

    private func openL2CAP(_ channel: CBL2CAPChannel, label: String, remoteID: UUID?) {
        let link = NearbyLink(kind: .l2cap, label: label)
        link.remoteID = remoteID
        let streams = NearbyStreams(channel: channel, link: link, owner: self)
        link.streams = streams
        add(link)
        streams.open()
        log.record("l2cap_open", ["psm": channel.psm, "label": label])
        hello(on: link)
    }

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
}

// MARK: The central side (we scan and connect)

extension NearbyTransport: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ manager: CBCentralManager) {
        bluetoothState = name(manager.state)
        log.record("central_state", ["state": bluetoothState])
        guard manager.state == .poweredOn else { return }
        // The service filter is required for scanning in the background; duplicates are not reported there.
        manager.scanForPeripherals(withServices: [Self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        log.record("scan_start", [:])
    }

    func centralManager(_ manager: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral]) ?? []
        log.record("restore_central", ["peripherals": restored.count, "id": Self.centralRestoreID])
        for peripheral in restored {
            peripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
        }
    }

    func centralManager(_ manager: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let overflow = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] != nil
        log.record("discovered", ["peer": peripheral.identifier.uuidString.prefix(8).description, "rssi": RSSI.intValue, "overflowAdvert": overflow,
                                  "seconds": Int(Date().timeIntervalSince(runStarted))])
        guard peripherals[peripheral.identifier] == nil || peripheral.state == .disconnected else { return }
        peripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        manager.connect(peripheral)
        log.record("connecting", ["peer": peripheral.identifier.uuidString.prefix(8).description])
    }

    func centralManager(_ manager: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log.record("connected", ["peer": peripheral.identifier.uuidString.prefix(8).description,
                                 "writeMTU": peripheral.maximumWriteValueLength(for: .withResponse), "reconnects": reconnects[peripheral.identifier] ?? 0])
        peripheral.readRSSI()
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ manager: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log.record("connect_failed", ["peer": peripheral.identifier.uuidString.prefix(8).description, "error": error?.localizedDescription ?? "?"])
        if running { manager.connect(peripheral) }
    }

    func centralManager(_ manager: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        reconnects[peripheral.identifier, default: 0] += 1
        log.record("disconnected", ["peer": peripheral.identifier.uuidString.prefix(8).description, "error": error?.localizedDescription ?? "none",
                                    "reconnects": reconnects[peripheral.identifier] ?? 0])
        for link in links where link.peripheral === peripheral || link.remoteID == peripheral.identifier { closed(link, why: "disconnected") }
        // A connection request does not time out: iOS completes it when the phone is next in range.
        if running { manager.connect(peripheral) }
    }
}

extension NearbyTransport: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        log.record("rssi", ["peer": peripheral.identifier.uuidString.prefix(8).description, "rssi": RSSI.intValue])
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            log.record("service_missing", ["error": error?.localizedDescription ?? "none"])
            return
        }
        peripheral.discoverCharacteristics([Self.writeUUID, Self.notifyUUID, Self.psmUUID, Self.tagUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        let link = NearbyLink(kind: .gattWrite, label: peripheral.identifier.uuidString.prefix(8).description)
        link.peripheral = peripheral
        link.remoteID = peripheral.identifier
        link.writeCharacteristic = characteristics.first { $0.uuid == Self.writeUUID }
        add(link)
        log.record("gatt_ready", ["peer": link.label, "characteristics": characteristics.count])
        for characteristic in characteristics {
            if characteristic.uuid == Self.notifyUUID { peripheral.setNotifyValue(true, for: characteristic) }
            if characteristic.uuid == Self.psmUUID { peripheral.readValue(for: characteristic) }
        }
        hello(on: link)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        log.record("notify_subscribed", ["peer": peripheral.identifier.uuidString.prefix(8).description, "on": characteristic.isNotifying, "error": error?.localizedDescription ?? "none"])
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value else { return }
        if characteristic.uuid == Self.psmUUID, value.count >= 2 {
            let psm = CBL2CAPPSM(value.prefix(2).reduce(UInt16(0)) { ($0 << 8) | UInt16($1) })
            log.record("psm_read", ["psm": psm])
            peripheral.openL2CAPChannel(psm)
        } else if characteristic.uuid == Self.notifyUUID, let link = links.first(where: { $0.peripheral === peripheral && $0.kind == .gattWrite }) {
            // The peripheral's notifications arrive on the central's write link (same remote phone).
            received(value, on: link)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let link = links.first(where: { $0.peripheral === peripheral && $0.kind == .gattWrite }) else { return }
        link.writing = false
        if let error {
            log.record("write_failed", ["error": error.localizedDescription])
            link.current = nil
            return
        }
        if let current = link.current, current.offset >= current.data.count { finish(link) } else { pump(link) }
    }

    func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {
        if let channel { openL2CAP(channel, label: peripheral.identifier.uuidString.prefix(8).description, remoteID: peripheral.identifier) }
        else { log.record("l2cap_failed", ["error": error?.localizedDescription ?? "?"]) }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        log.record("services_modified", ["peer": peripheral.identifier.uuidString.prefix(8).description])
        peripheral.discoverServices([Self.serviceUUID])
    }
}

// MARK: The peripheral side (we advertise and accept)

extension NearbyTransport: @preconcurrency CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ manager: CBPeripheralManager) {
        log.record("peripheral_state", ["state": name(manager.state)])
        guard manager.state == .poweredOn else { return }
        let write = CBMutableCharacteristic(type: Self.writeUUID, properties: [.write], value: nil, permissions: [.writeable])
        let notify = CBMutableCharacteristic(type: Self.notifyUUID, properties: [.notify], value: nil, permissions: [.readable])
        let psm = CBMutableCharacteristic(type: Self.psmUUID, properties: [.read], value: nil, permissions: [.readable])
        let tag = CBMutableCharacteristic(type: Self.tagUUID, properties: [.read], value: Data(self.tag.utf8), permissions: [.readable])
        notifyCharacteristic = notify
        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [write, notify, psm, tag]
        manager.add(service)
        manager.publishL2CAPChannel(withEncryption: false)
    }

    func peripheralManager(_ manager: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        let services = (dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService]) ?? []
        log.record("restore_peripheral", ["services": services.count, "id": Self.peripheralRestoreID,
                                           "advertising": dict[CBPeripheralManagerRestoredStateAdvertisementDataKey] != nil])
    }

    func peripheralManager(_ manager: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        log.record("service_added", ["error": error?.localizedDescription ?? "none"])
        // In the background an advertisement carries the service UUID only (in the "overflow" area).
        manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]])
    }

    func peripheralManagerDidStartAdvertising(_ manager: CBPeripheralManager, error: Error?) {
        log.record("advertising", ["error": error?.localizedDescription ?? "none"])
    }

    func peripheralManager(_ manager: CBPeripheralManager, didPublishL2CAPChannel PSM: CBL2CAPPSM, error: Error?) {
        psm = PSM
        log.record("l2cap_published", ["psm": PSM, "error": error?.localizedDescription ?? "none"])
    }

    func peripheralManager(_ manager: CBPeripheralManager, didOpen channel: CBL2CAPChannel?, error: Error?) {
        if let channel { openL2CAP(channel, label: channel.peer.identifier.uuidString.prefix(8).description, remoteID: channel.peer.identifier) }
        else { log.record("l2cap_failed", ["error": error?.localizedDescription ?? "?"]) }
    }

    func peripheralManager(_ manager: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        let link = NearbyLink(kind: .gattNotify, label: central.identifier.uuidString.prefix(8).description)
        link.central = central
        link.remoteID = central.identifier
        add(link)
        log.record("subscribed", ["peer": link.label, "notifyMTU": central.maximumUpdateValueLength])
        hello(on: link)
    }

    func peripheralManager(_ manager: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        for link in links where link.central?.identifier == central.identifier { closed(link, why: "unsubscribed") }
    }

    func peripheralManager(_ manager: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        if request.characteristic.uuid == Self.psmUUID, let psm {
            request.value = Data([UInt8(psm >> 8), UInt8(psm & 0xFF)])
            manager.respond(to: request, withResult: .success)
        } else if request.characteristic.uuid == Self.tagUUID {
            request.value = Data(tag.utf8).dropFirst(request.offset)
            manager.respond(to: request, withResult: .success)
        } else {
            manager.respond(to: request, withResult: .attributeNotFound)
        }
    }

    func peripheralManager(_ manager: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if let value = request.value {
                // Writes from a central belong to its notify link on our side (the same remote phone).
                if let link = links.first(where: { $0.central?.identifier == request.central.identifier && $0.kind == .gattNotify }) {
                    received(value, on: link)
                } else {
                    // Written before its subscription arrived: keep the bytes with a holding reader.
                    var reader = inbound[request.central.identifier] ?? NearbyFrameReader()
                    for (kind, payload, began) in reader.append(value) {
                        let holder = NearbyLink(kind: .gattNotify, label: request.central.identifier.uuidString.prefix(8).description)
                        handle(kind, payload, began: began, link: holder)
                    }
                    inbound[request.central.identifier] = reader
                }
            }
        }
        if let first = requests.first { manager.respond(to: first, withResult: .success) }
    }

    func peripheralManagerIsReady(toUpdateSubscribers manager: CBPeripheralManager) {
        for link in links where link.kind == .gattNotify { pump(link) }
    }
}
#endif
