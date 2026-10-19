import Darwin
import Foundation

/// This app's CPU use since the last call, in percent of one core (can pass 100 on several cores): for the call diagnostics (LIME-171).
enum ProcessLoad {
    nonisolated(unsafe) private static var last: (wall: TimeInterval, cpu: TimeInterval)?

    static func cpuPercent(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Int {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> TimeInterval { TimeInterval(t.tv_sec) + TimeInterval(t.tv_usec) / 1_000_000 }
        let cpu = seconds(usage.ru_utime) + seconds(usage.ru_stime)
        defer { last = (now, cpu) }
        guard let last, now > last.wall else { return 0 }
        return Int(((cpu - last.cpu) / (now - last.wall) * 100).rounded())
    }
}
