import Foundation

/// The three statuses a teacher can have (LIME-108).
enum UserStatus: String, CaseIterable, Identifiable, Codable, Sendable {
    case available, away, dnd
    var id: String { rawValue }
    var title: String {
        switch self {
        case .available: "Available"
        case .away: "Away"
        case .dnd: "Do not disturb"
        }
    }
}

/// Work hours: a weekly schedule. Outside it the teacher is automatically in Do not disturb.
struct WorkHours: Equatable, Codable, Sendable {
    var enabled = false
    /// Calendar weekdays (1 = Sunday ... 7 = Saturday); default Monday to Friday.
    var days: Set<Int> = [2, 3, 4, 5, 6]
    /// Minutes after midnight: 7:00 and 15:30.
    var start = 7 * 60
    var end = 15 * 60 + 30

    /// Whether `date` is inside a work period.
    func isWorking(at date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled, let (from, to) = period(containing: date, calendar: calendar) else { return false }
        return date >= from && date < to
    }

    /// The work period of `date`'s own day, if that day is a work day.
    private func period(containing date: Date, calendar: Calendar) -> (Date, Date)? {
        guard days.contains(calendar.component(.weekday, from: date)), end > start else { return nil }
        let day = calendar.startOfDay(for: date)
        guard let from = calendar.date(byAdding: .minute, value: start, to: day), let to = calendar.date(byAdding: .minute, value: end, to: day) else { return nil }
        return (from, to)
    }

    /// The next moment a work period starts after `date`.
    func nextStart(after date: Date, calendar: Calendar = .current) -> Date? {
        guard enabled, !days.isEmpty, end > start else { return nil }
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)), let (from, _) = period(containing: day, calendar: calendar) else { continue }
            if from > date { return from }
        }
        return nil
    }

    /// The end of the work period `date` is in.
    func end(of date: Date, calendar: Calendar = .current) -> Date? {
        period(containing: date, calendar: calendar).flatMap { $0.1 > date ? $0.1 : nil }
    }
}

/// A status set by hand, until a time (or until changed).
struct ManualStatus: Equatable, Codable, Sendable {
    var state: UserStatus
    var until: Date?
}

/// What my status is, and what it will be next: worked out from what I set by hand and my work hours. Pure, so the clock can be injected.
struct StatusPlan: Equatable, Sendable {
    var state: UserStatus
    var until: Date?
    var thenState: UserStatus?
    var thenUntil: Date?

    /// Outside work hours (or in a quiet period) notifications are held.
    var isQuiet: Bool { state == .dnd }

    static func make(manual: ManualStatus?, hours: WorkHours, now: Date, calendar: Calendar = .current) -> StatusPlan {
        if let manual, manual.until.map({ now < $0 }) ?? true {
            // By hand wins until it ends; what the work hours say takes over after.
            guard let until = manual.until else { return StatusPlan(state: manual.state) }
            let after = base(hours: hours, now: until, calendar: calendar)
            return StatusPlan(state: manual.state, until: until, thenState: after.state, thenUntil: after.until)
        }
        let current = base(hours: hours, now: now, calendar: calendar)
        guard let until = current.until else { return current }
        let after = base(hours: hours, now: until, calendar: calendar)
        return StatusPlan(state: current.state, until: until, thenState: after.state, thenUntil: after.until)
    }

    /// The schedule alone: available inside work hours, Do not disturb outside them (and Available when there is no schedule).
    private static func base(hours: WorkHours, now: Date, calendar: Calendar) -> StatusPlan {
        guard hours.enabled else { return StatusPlan(state: .available) }
        if hours.isWorking(at: now, calendar: calendar) { return StatusPlan(state: .available, until: hours.end(of: now, calendar: calendar)) }
        return StatusPlan(state: .dnd, until: hours.nextStart(after: now, calendar: calendar))
    }

    /// "Quiet hours until 7:00 AM" or "Do not disturb", for a status that holds now.
    static func caption(state: UserStatus, until: Date?, now: Date = Date(), calendar: Calendar = .current) -> String? {
        switch state {
        case .available: return nil
        case .away: return "Away"
        case .dnd:
            guard let until, until > now else { return "Do not disturb" }
            let time = until.formatted(date: .omitted, time: .shortened)
            return calendar.isDate(until, inSameDayAs: now) ? "Quiet hours until \(time)" : "Quiet hours until \(until.formatted(.dateTime.weekday(.abbreviated))) \(time)"
        }
    }
}

/// Status and work hours, kept on this phone.
@MainActor
@Observable
final class StatusSettings {
    static let shared = StatusSettings()
    private static let manualKey = "lime.status.manual"
    private static let hoursKey = "lime.status.hours"

    var manual: ManualStatus? { didSet { save(manual, Self.manualKey) } }
    var hours: WorkHours { didSet { save(hours, Self.hoursKey) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        // UI tests start from nothing set.
        if ProcessInfo.processInfo.arguments.contains("-lime-skip-sign-in") { defaults.removeObject(forKey: Self.manualKey); defaults.removeObject(forKey: Self.hoursKey) }
        #endif
        manual = defaults.data(forKey: Self.manualKey).flatMap { try? JSONDecoder().decode(ManualStatus.self, from: $0) }
        hours = defaults.data(forKey: Self.hoursKey).flatMap { try? JSONDecoder().decode(WorkHours.self, from: $0) } ?? WorkHours()
    }

    @ObservationIgnored private let defaults: UserDefaults
    private func save<T: Encodable>(_ value: T?, _ key: String) {
        if let value, let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    func plan(now: Date = Date()) -> StatusPlan { StatusPlan.make(manual: manual, hours: hours, now: now) }
}
