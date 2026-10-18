import CoreGraphics
import Foundation

/// What the minimised group call's window shows (LIME-150): pure rules, so every size of call and the heat guard can be tested without a window.
///
/// Counting the other people (not me): 1 fills the window; 2 sit side by side (or stacked, by the window's shape); 3 make a 2 × 2 whose fourth
/// cell is my own picture; 4 make a 2 × 2; 5 or more show the 3 people who spoke most recently and a "+N" cell.
enum PiPGridPlan {
    struct Person: Equatable {
        let id: String
        let name: String
        let isMe: Bool
        var speaking: Bool
        /// Their camera is on, their key has arrived and this is a video call: there is a picture to draw.
        var hasPicture: Bool
    }

    struct Cell: Equatable {
        enum Kind: Equatable { case person, more(Int) }
        let id: String
        let kind: Kind
        let name: String
        let isMe: Bool
        /// Draw their live picture (false: their photo, never black).
        var live: Bool
        var speaking: Bool
    }

    /// Which view of a minimised call: everyone in a grid, or the speaker alone (112c's window).
    enum View: String { case grid, speaker }

    /// The person's choice, else the grid up to 4 other people and the speaker above.
    static func view(choice: View?, others: Int) -> View {
        choice ?? (others <= 4 ? .grid : .speaker)
    }

    /// Who owns the window while minimised (LIME-150-fix5): the grid or the speaker's single picture, one at a time, decided from the kind of
    /// call, the person's choice and the number of people, and **not** from whether someone happens to be in the room this second (a person
    /// leaving and rejoining used to flip the window between the two). `why` is what the log says.
    static func mode(video: Bool, choice: View?, others: Int) -> (mode: View, why: String) {
        if !video { return (.speaker, "voice call") }
        if let choice { return (choice, "chosen: \(choice.rawValue)") }
        return others <= 4 ? (.grid, "default for \(others) other people") : (.speaker, "default for \(others) other people")
    }

    /// The cells in order. `recent` lists the other people by how lately they spoke (newest first); `speakerID` is the one person kept live
    /// when the heat guard has made the grid lighter; `allLive` is false then.
    static func cells(people: [Person], recent: [String], speakerID: String?, allLive: Bool) -> [Cell] {
        let others = people.filter { !$0.isMe }
        guard !others.isEmpty else { return [] }
        var shown: [Person]
        var extra = 0
        switch others.count {
        case 1, 2, 4: shown = others
        case 3: shown = others + people.filter(\.isMe)
        default:
            let order = recent.compactMap { id in others.first { $0.id == id } } + others.filter { !recent.contains($0.id) }
            shown = Array(order.prefix(3))
            extra = others.count - 3
        }
        var cells = shown.map { person in
            Cell(id: person.id, kind: .person, name: person.name, isMe: person.isMe,
                 live: person.hasPicture && (allLive || person.id == speakerID), speaking: person.speaking)
        }
        if extra > 0 { cells.append(Cell(id: "more", kind: .more(extra), name: "+\(extra)", isMe: false, live: false, speaking: false)) }
        return cells
    }

    /// How many cells draw a live picture.
    static func liveCount(_ cells: [Cell]) -> Int { cells.filter(\.live).count }
}

/// The heat guard (LIME-150 6b): when the phone reaches the serious thermal state the grid keeps only the speaker live, and goes back to all
/// live after two minutes at fair or nominal, so it never flaps.
struct PiPHeatGuard {
    static let calmSeconds: TimeInterval = 120
    private(set) var reduced = false
    private var calmSince: Date?

    /// Feeds the thermal state; returns whether `reduced` changed.
    @discardableResult
    mutating func update(thermal: ProcessInfo.ThermalState, now: Date) -> Bool {
        let hot = thermal == .serious || thermal == .critical
        let before = reduced
        if hot {
            reduced = true
            calmSince = nil
        } else if reduced {
            if calmSince == nil { calmSince = now }
            if let since = calmSince, now.timeIntervalSince(since) >= Self.calmSeconds { reduced = false; calmSince = nil }
        } else {
            calmSince = nil
        }
        return reduced != before
    }

    mutating func reset() { reduced = false; calmSince = nil }

    static func name(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}
