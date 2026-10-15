import Foundation

/// How mesh frames cross a Bluetooth link (LIME-141). Pure logic, no CoreBluetooth: tested without a radio.
///
/// - **L2CAP is a byte stream**, so a frame goes with a 4-byte big-endian length in front (`MeshStreamFramer`, `MeshStreamReader`).
/// - **GATT moves small messages**, so a frame is cut into fragments of about 470 bytes (`MeshFragmenter`) and put back together by a
///   `MeshReassembler` that caps what it holds (one frame, the number of unfinished frames, the total) and forgets a frame that has not
///   finished in 30 seconds (DESIGN-06), so a stranger cannot make a phone hold memory for ever.
enum MeshFraming {
    /// The most a fragment may carry on the wire, header included (a GATT write or notification fits in the negotiated 512 bytes).
    static let fragmentBytes = 470
    /// The largest frame accepted (a mesh packet is at most 70 KB; a frame wraps one).
    static let maxFrameBytes = 80 * 1024
}

enum MeshStreamFramer {
    static func encode(_ frame: Data) -> Data {
        var length = UInt32(frame.count).bigEndian
        return withUnsafeBytes(of: &length) { Data($0) } + frame
    }
}

/// Cuts a byte stream back into frames. An announced length above the cap poisons the stream: the reader says so and the link is closed.
struct MeshStreamReader {
    private var buffer = Data()
    private(set) var overflowed = false

    mutating func append(_ data: Data) -> [Data] {
        guard !overflowed else { return [] }
        buffer.append(data)
        var frames: [Data] = []
        while buffer.count >= 4 {
            let length = Int(buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            if length > MeshFraming.maxFrameBytes {
                overflowed = true
                buffer = Data()
                return frames
            }
            guard buffer.count >= 4 + length else { break }
            frames.append(buffer.subdata(in: 4..<4 + length))
            buffer = buffer.subdata(in: (4 + length)..<buffer.count)
        }
        return frames
    }
}

/// `id` (2 bytes) names the frame, `index` and `total` (2 bytes each) place the fragment: a 6-byte header, then the body.
enum MeshFragmenter {
    static let headerBytes = 6

    static func split(_ frame: Data, id: UInt16, fragmentBytes: Int = MeshFraming.fragmentBytes) -> [Data] {
        let body = max(fragmentBytes - headerBytes, 1)
        let total = max((frame.count + body - 1) / body, 1)
        precondition(total <= Int(UInt16.max))
        return (0..<total).map { index in
            let part = frame.subdata(in: (index * body)..<min((index + 1) * body, frame.count))
            var header = Data()
            for value in [id, UInt16(index), UInt16(total)] { header.append(UInt8(value >> 8)); header.append(UInt8(value & 0xFF)) }
            return header + part
        }
    }
}

struct MeshReassembler {
    struct Limits {
        var maxFrameBytes = MeshFraming.maxFrameBytes
        var maxPartials = 8
        var maxTotalBytes = 256 * 1024
        var timeout: TimeInterval = 30
    }

    private struct Partial {
        var total: Int
        var parts: [Int: Data] = [:]
        var bytes = 0
        var started: Date
    }

    private var partials: [UInt16: Partial] = [:]
    let limits: Limits
    /// Fragments refused for breaking a cap (for the diagnostics).
    private(set) var refused = 0

    init(limits: Limits = Limits()) { self.limits = limits }

    var unfinished: Int { partials.count }
    var heldBytes: Int { partials.values.reduce(0) { $0 + $1.bytes } }

    /// Takes one fragment; returns the whole frame when it is the last one that was missing.
    mutating func accept(_ fragment: Data, now: Date) -> Data? {
        forgetStale(now: now)
        guard fragment.count > MeshFragmenter.headerBytes else { refused += 1; return nil }
        let bytes = [UInt8](fragment.prefix(MeshFragmenter.headerBytes))
        let id = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        let index = Int(UInt16(bytes[2]) << 8 | UInt16(bytes[3]))
        let total = Int(UInt16(bytes[4]) << 8 | UInt16(bytes[5]))
        let body = fragment.subdata(in: MeshFragmenter.headerBytes..<fragment.count)
        guard total >= 1, index < total else { refused += 1; return nil }
        // A frame is at most `maxFrameBytes`: with fragments of up to `fragmentBytes`, there cannot be more than this many.
        let mostFragments = limits.maxFrameBytes / max(MeshFraming.fragmentBytes - MeshFragmenter.headerBytes, 1) + 2
        guard total <= mostFragments, body.count <= limits.maxFrameBytes else { refused += 1; return nil }
        if total == 1 { return body }
        var partial = partials[id] ?? Partial(total: total, started: now)
        guard partial.total == total else { partials[id] = nil; refused += 1; return nil }
        if partial.parts[index] == nil {
            guard partials[id] != nil || partials.count < limits.maxPartials else { refused += 1; return nil }
            guard partial.bytes + body.count <= limits.maxFrameBytes, heldBytes - (partials[id]?.bytes ?? 0) + partial.bytes + body.count <= limits.maxTotalBytes else {
                partials[id] = nil
                refused += 1
                return nil
            }
            partial.parts[index] = body
            partial.bytes += body.count
        }
        if partial.parts.count == total {
            partials[id] = nil
            return (0..<total).reduce(into: Data()) { $0.append(partial.parts[$1] ?? Data()) }
        }
        partials[id] = partial
        return nil
    }

    private mutating func forgetStale(now: Date) {
        for (id, partial) in partials where now.timeIntervalSince(partial.started) > limits.timeout { partials[id] = nil }
    }
}
