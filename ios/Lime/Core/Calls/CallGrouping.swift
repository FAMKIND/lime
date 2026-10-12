import Foundation

extension CallRecord {
    /// An incoming call that was missed (or silenced by Do Not Disturb or work hours).
    var isMissedIncoming: Bool { !outgoing && outcome.isMissed }
}

/// Consecutive calls with the same person, of the same kind, on the same day, that were all missed or all not missed: one row with a
/// count (Apple's rule).
struct CallGroup: Identifiable, Equatable {
    /// The newest call's id.
    let id: String
    /// Newest first.
    let records: [CallRecord]

    var first: CallRecord { records[0] }
    var count: Int { records.count }
    var isMissedIncoming: Bool { first.isMissedIncoming }
}

enum CallGrouping {
    static func groups(_ records: [CallRecord], calendar: Calendar = .current) -> [CallGroup] {
        var result: [[CallRecord]] = []
        for record in records.sorted(by: { $0.date > $1.date }) {
            if let last = result.last?.first,
               last.peerID == record.peerID, last.video == record.video,
               calendar.isDate(last.date, inSameDayAs: record.date),
               last.isMissedIncoming == record.isMissedIncoming {
                result[result.count - 1].append(record)
            } else {
                result.append([record])
            }
        }
        return result.map { CallGroup(id: $0[0].id, records: $0) }
    }

    /// The time at the right of a row: today "4:12 PM", "Yesterday", a weekday within 7 days, else a short date.
    static func timeLabel(_ date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        if let week = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)), date >= week {
            return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.wide))
        }
        return date.formatted(Date.FormatStyle(date: .numeric, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
    }

    /// A call's date on one short line (the profile's call rows): today "11:01 AM"; "Yesterday 11:01 AM"; else "Oct 11, 11:01 AM", with the
    /// year only when it is not this year.
    static func shortDate(_ date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday \(time)" }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day()
        if !sameYear { style = style.year() }
        return "\(date.formatted(style)), \(time)"
    }
}
