import Foundation

/// Runs delayed work: `DispatchQueue.main.asyncAfter` in the app, a fake in the tests. Never a timer that needs a suspended app.
@MainActor
protocol MeshScheduler {
    func after(milliseconds: Int, _ work: @escaping @MainActor () -> Void)
}

struct MainQueueScheduler: MeshScheduler {
    func after(milliseconds: Int, _ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(milliseconds))
            work()
        }
    }
}

/// Between the Bluetooth link and LimeCore's `MeshEngine` (LIME-141): reports links going up and down and frames arriving, and carries out the
/// actions the engine returns (honouring `delay_ms` through the scheduler; a delayed frame for a link that has gone is dropped). **Every wake
/// event** (a discovery, a connection, the app opening, a state restoration) calls `wake()`, which makes the tags current and announces every
/// live link again so the engine flushes what it holds (the MESH v1 rule). Pure of CoreBluetooth: tested with a fake engine.
@MainActor
final class MeshDriver {
    private let engine: MeshEngineProtocol
    private let scheduler: MeshScheduler
    private let transmit: (_ link: UInt64, _ bytes: Data) -> Void
    private let log: (_ kind: String, _ detail: [String: String]) -> Void
    private(set) var liveLinks: Set<UInt64> = []
    /// Called after mail for this phone was taken from the engine (messages that became part of a conversation).
    var onMessages: ((Int) -> Void)?

    init(engine: MeshEngineProtocol, scheduler: MeshScheduler = MainQueueScheduler(), transmit: @escaping (UInt64, Data) -> Void,
         log: @escaping (String, [String: String]) -> Void = { _, _ in }) {
        self.engine = engine
        self.scheduler = scheduler
        self.transmit = transmit
        self.log = log
    }

    func linkUp(_ link: UInt64) {
        liveLinks.insert(link)
        log("link_up", ["link": Self.short(link)])
        run(engine.linkUp(link: link), on: link)
    }

    func linkDown(_ link: UInt64) {
        liveLinks.remove(link)
        engine.linkDown(link: link)
        log("link_down", ["link": Self.short(link)])
    }

    func receive(_ bytes: Data, on link: UInt64) {
        log("frame_in", ["link": Self.short(link), "bytes": String(bytes.count)])
        run(engine.frame(link: link, bytes: bytes), on: link)
        if let count = try? engine.takeMine(), count > 0 { onMessages?(Int(count)) }
    }

    /// A wake event: the tags may have changed (a new day, new contacts), and every live link is announced again.
    func wake(reason: String) {
        log("wake", ["reason": reason, "links": String(liveLinks.count)])
        try? engine.refreshTags()
        for link in liveLinks.sorted() { run(engine.linkUp(link: link), on: link) }
    }

    private func run(_ actions: [MeshAction], on link: UInt64) {
        for action in actions {
            if action.delayMs == 0 {
                send(action)
            } else {
                scheduler.after(milliseconds: Int(action.delayMs)) { [weak self] in
                    guard let self, self.liveLinks.contains(action.link) else { return }
                    self.send(action)
                }
            }
        }
    }

    private func send(_ action: MeshAction) {
        log("frame_out", ["link": Self.short(action.link), "bytes": String(action.bytes.count)])
        transmit(action.link, action.bytes)
    }

    /// Four characters of a link id: enough to tell links apart in a log, not enough to identify anyone.
    static func short(_ id: UInt64) -> String { String(String(id, radix: 16).suffix(4)) }
}
