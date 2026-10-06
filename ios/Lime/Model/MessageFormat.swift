import Foundation

enum MessageFormat {
    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// Messages list: the time today, "Yesterday", else the date.
    static func listTime(_ date: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date else { return "" }
        if calendar.isDate(date, inSameDayAs: now) { return clock(date) }
        if calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now)!) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// Chat date separators.
    static func day(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now)!) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
