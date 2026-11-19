import Foundation
import UIKit

/// The devices of this account (LIME-343a): the list for Settings → Linked Devices, this device's own name, unlinking a computer.
extension ConversationStore {
    /// My devices from the core, this one first. The demo shows a phone, a Mac and an iPad.
    func loadMyDevices() async -> [MyDevice] {
        #if DEBUG
        if isDemo { return Self.demoDevices(extra: demoUnlinked) }
        #endif
        guard let core else { return [] }
        let kind = LinkFactory.thisDeviceKind
        let name = UIDevice.current.name
        return await Task.detached(priority: .userInitiated) {
            // This device says what it is called the first time (the name stays inside encryption; the server never sees it).
            let mine = (try? core.myDevices()) ?? []
            if let me = mine.first(where: { $0.isThisDevice }), me.name.isEmpty {
                try? core.setDeviceName(name: name, kind: kind)
                return (try? core.myDevices()) ?? mine
            }
            return mine
        }.value
    }

    func reloadMyDevices() async { _ = await loadMyDevices() }

    /// Unlinks a computer. `true` when it worked.
    func unlinkDevice(_ deviceID: String) async -> Bool {
        #if DEBUG
        if isDemo { demoUnlinked.insert(deviceID); return true }
        #endif
        guard let core, let link else { return false }
        do {
            let token = try await link.token()
            try await Task.detached(priority: .userInitiated) { try core.unlinkDevice(transport: link.transport, authToken: token, deviceId: deviceID) }.value
            await deliverNow()
            return true
        } catch {
            return false
        }
    }

    #if DEBUG
    static func demoDevices(extra: Set<String>) -> [MyDevice] {
        let day: Int64 = 86_400_000
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var all = [
            MyDevice(deviceId: "demo-phone", name: "Test Teacher's iPhone", kind: "phone", addedAt: now - 200 * day, isThisDevice: true),
            MyDevice(deviceId: "demo-ipad", name: "Classroom iPad", kind: "tablet", addedAt: now - 60 * day, isThisDevice: false),
            MyDevice(deviceId: "demo-mac", name: "Test Teacher's MacBook Air", kind: "computer", addedAt: now - 30 * day, isThisDevice: false),
        ]
        if ProcessInfo.processInfo.arguments.contains("-lime-demo-devices-full") {
            all.append(MyDevice(deviceId: "demo-mac2", name: "Library iMac", kind: "computer", addedAt: now - 20 * day, isThisDevice: false))
            all.append(MyDevice(deviceId: "demo-mac3", name: "Home Mac mini", kind: "computer", addedAt: now - 10 * day, isThisDevice: false))
        }
        all.removeAll { extra.contains($0.deviceId) }
        return all
    }
    #endif
}
