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
/// actions the engine returns (honouring `delay_ms` through the scheduler; a delayed frame for a link that has gone is dropped).
///
/// **When a Hello goes out (LIME-141-fix).** A Hello is the engine's summary of what this phone holds; sending it again only helps when
/// something changed or a while has passed. The first version re-announced every link on every incoming frame, so two phones answered each
/// other's Hellos for ever (about 20,000 frames a minute, idle). Now:
/// - **an incoming data frame is not a wake**: it goes to the engine and nothing else (though if it changed what this phone holds, the *other*
///   links are told once);
/// - a **new link** gets a Hello at once;
/// - a **wake** (the app becoming active or foreground, a state restoration, a newly discovered phone) re-announces the live links, but at most
///   **one Hello per link every 30 seconds unless the engine's `summary_version` moved** since the last one;
/// - a packet queued by this phone (`packetQueued`) announces on every live link (the version moved).
/// A guard logs `WARNING frame storm` once a minute if a link carries more than 50 frames a minute while nothing changed.
@MainActor
final class MeshDriver {
    /// One Hello per link per this many seconds, unless the summary moved.
    static let helloInterval: TimeInterval = 30
    static let stormFramesPerMinute = 50

    private let engine: MeshEngineProtocol
    private let scheduler: MeshScheduler
    private let transmit: (_ link: UInt64, _ bytes: Data) -> Void
    private let log: (_ kind: String, _ detail: [String: String]) -> Void
    private let now: () -> Date
    private(set) var liveLinks: Set<UInt64> = []
    private var lastHello: [UInt64: (at: Date, version: UInt64)] = [:]
    private var lastVersion: UInt64
    private var storm: [UInt64: (windowStart: Date, frames: Int, version: UInt64, warned: Bool)] = [:]
    /// Called after mail for this phone was taken from the engine (messages that became part of a conversation).
    var onMessages: ((Int) -> Void)?
    /// Called after each frame has been handled (the notes the engine made, such as a delivery, can be logged at once).
    var onFrameHandled: (() -> Void)?

    init(engine: MeshEngineProtocol, scheduler: MeshScheduler = MainQueueScheduler(), now: @escaping () -> Date = Date.init,
         transmit: @escaping (UInt64, Data) -> Void, log: @escaping (String, [String: String]) -> Void = { _, _ in }) {
        self.engine = engine
        self.scheduler = scheduler
        self.now = now
        self.transmit = transmit
        self.log = log
        lastVersion = engine.summaryVersion()
    }

    func linkUp(_ link: UInt64) {
        liveLinks.insert(link)
        log("link_up", ["link": Self.short(link)])
        announce(link, force: true)
        // Tell the neighbour whether this phone can fetch for it (relay download, LIME-155).
        transmit(link, engine.onlineFrame())
    }

    /// This phone's "I can fetch for you" bit changed: every live link hears it.
    func broadcastOnline() {
        let frame = engine.onlineFrame()
        for link in liveLinks.sorted() { transmit(link, frame) }
    }

    func linkDown(_ link: UInt64) {
        liveLinks.remove(link)
        lastHello[link] = nil
        storm[link] = nil
        engine.linkDown(link: link)
        engine.fetchLinkDown(link: link)
        log("link_down", ["link": Self.short(link)])
    }

    /// A frame arrived. It is handed to the engine and nothing else: **a data frame is not a wake**.
    func receive(_ bytes: Data, on link: UInt64) {
        log("frame_in", ["link": Self.short(link), "bytes": String(bytes.count)])
        watchForStorm(link)
        run(engine.frame(link: link, bytes: bytes))
        if let count = try? engine.takeMine(), count > 0 { onMessages?(Int(count)) }
        onFrameHandled?()
        // If this changed what the phone holds, the other links should hear it (once: the debounce and the version see to that).
        let version = engine.summaryVersion()
        if version != lastVersion {
            lastVersion = version
            for other in liveLinks.sorted() where other != link { announce(other, force: false) }
        }
    }

    /// A wake event that may call for a re-announcement: the tags may have changed (a new day, new contacts) and every live link is announced
    /// again, subject to the Hello debounce.
    func wake(reason: String) {
        log("wake", ["reason": reason, "links": String(liveLinks.count)])
        try? engine.refreshTags()
        for link in liveLinks.sorted() { announce(link, force: false) }
    }

    /// This phone queued a packet (a message or a test packet): tell every live link.
    func packetQueued() {
        lastVersion = engine.summaryVersion()
        for link in liveLinks.sorted() { announce(link, force: false) }
    }

    private func announce(_ link: UInt64, force: Bool) {
        let version = engine.summaryVersion()
        let current = now()
        if !force, let last = lastHello[link], current.timeIntervalSince(last.at) < Self.helloInterval, last.version == version { return }
        lastHello[link] = (current, version)
        run(engine.linkUp(link: link))
    }

    private func watchForStorm(_ link: UInt64) {
        let current = now()
        let version = engine.summaryVersion()
        var state = storm[link] ?? (windowStart: current, frames: 0, version: version, warned: false)
        if current.timeIntervalSince(state.windowStart) >= 60 { state = (current, 0, version, false) }
        state.frames += 1
        if state.version != version { state.version = version; state.frames = 1; state.windowStart = current }
        if state.frames > Self.stormFramesPerMinute, !state.warned {
            state.warned = true
            log("WARNING frame storm", ["link": Self.short(link), "frames": String(state.frames)])
        }
        storm[link] = state
    }

    private func run(_ actions: [MeshAction]) {
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
