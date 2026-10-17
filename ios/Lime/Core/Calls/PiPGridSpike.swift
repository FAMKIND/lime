#if DEBUG
import AVFoundation
import LiveKit
import UIKit

/// LIME-150's device spike (Debug only, switched on by the launch argument `-lime.pipSpike.tiles N`, N = 1 to 4). It draws N live tiles in the
/// system window (the people's pictures, repeated when fewer people have a camera on than there are tiles) and logs, every 5 seconds, the frames per
/// second of each tile, this app's CPU, the thermal state, the battery and whether lime is in front or not, so a person can read what a mini grid
/// costs with lime in the background. Nothing here ships: it is the measurement, not the feature.
final class PiPGridSpike: UIView {
    static var tileCount: Int { min(4, max(0, UserDefaults.standard.integer(forKey: "lime.pipSpike.tiles"))) }

    private struct Tile {
        let view: PiPDisplayView
        let renderer: GroupPiPFrameRenderer
        var track: (any VideoTrack)?
    }

    private var tiles: [Tile] = []
    private var sampler: Task<Void, Never>?

    @MainActor init(tiles count: Int) {
        super.init(frame: .zero)
        backgroundColor = .black
        for _ in 0..<count {
            let view = PiPDisplayView()
            view.layer.borderWidth = 1
            view.layer.borderColor = UIColor(white: 0.2, alpha: 1).cgColor
            addSubview(view)
            let renderer = GroupPiPFrameRenderer(layer: view.displayLayer) { size, rotation, done in
                Task { @MainActor in view.rotation = rotation; view.setNeedsLayout(); done() }
            }
            renderer.adaptiveSize = count == 1 ? CGSize(width: 360, height: 480) : CGSize(width: 240, height: 240)
            tiles.append(Tile(view: view, renderer: renderer, track: nil))
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let columns = tiles.count <= 1 ? 1 : 2
        let rows = (tiles.count + columns - 1) / columns
        let w = bounds.width / CGFloat(columns), h = bounds.height / CGFloat(max(rows, 1))
        for (index, tile) in tiles.enumerated() {
            tile.view.frame = CGRect(x: CGFloat(index % columns) * w, y: CGFloat(index / columns) * h, width: w, height: h)
        }
    }

    /// Points each tile at a track (the available ones, repeated to fill every tile).
    @MainActor func attach(tracks: [any VideoTrack]) {
        guard !tracks.isEmpty else { return }
        for index in tiles.indices {
            let wanted = tracks[index % tracks.count]
            guard tiles[index].track?.sid != wanted.sid else { continue }
            let renderer = tiles[index].renderer
            if let old = tiles[index].track { DispatchQueue.global(qos: .userInitiated).async { old.remove(videoRenderer: renderer) } }
            tiles[index].track = wanted
            DispatchQueue.global(qos: .userInitiated).async { wanted.add(videoRenderer: renderer) }
        }
    }

    @MainActor func startSampling() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        sampler = Task { @MainActor [weak self] in
            var last = self?.tiles.map { $0.renderer.frameCount } ?? []
            var lastCPU = Self.cpuSeconds(), lastAt = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                let now = Date(), span = now.timeIntervalSince(lastAt)
                let counts = self.tiles.map { $0.renderer.frameCount }
                let fps = zip(counts, last).map { String(format: "%.1f", Double($0 - $1) / span) }
                let cpu = Self.cpuSeconds()
                let percent = (cpu - lastCPU) / span * 100
                (last, lastCPU, lastAt) = (counts, cpu, now)
                let state = UIApplication.shared.applicationState == .active ? "front" : "background"
                let thermal = ["nominal", "fair", "serious", "critical"][ProcessInfo.processInfo.thermalState.rawValue]
                CallDiagnostics.shared.log("pip_spike tiles=\(self.tiles.count) lime=\(state) fps=[\(fps.joined(separator: ","))] cpu=\(String(format: "%.0f", percent))% thermal=\(thermal) battery=\(Int(UIDevice.current.batteryLevel * 100))%")
            }
        }
    }

    @MainActor func stop() {
        sampler?.cancel()
        for tile in tiles {
            if let track = tile.track { let renderer = tile.renderer; DispatchQueue.global(qos: .userInitiated).async { track.remove(videoRenderer: renderer) } }
        }
    }

    /// The CPU seconds this app has used, over all its threads.
    private static func cpuSeconds() -> Double {
        var threads: thread_act_array_t?
        var count = mach_msg_type_number_t(0)
        guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS, let threads else { return 0 }
        defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)), vm_size_t(Int(count) * MemoryLayout<thread_t>.stride)) }
        var total = 0.0
        for index in 0..<Int(count) {
            var info = thread_basic_info()
            var size = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { thread_info(threads[index], thread_flavor_t(THREAD_BASIC_INFO), $0, &size) }
            }
            if result == KERN_SUCCESS, info.flags & TH_FLAGS_IDLE == 0 {
                total += Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1e6 + Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1e6
            }
        }
        return total
    }
}
#endif
