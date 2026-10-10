import Foundation

/// A chat's day separators and messages, in order. `showAvatar` is true for the first of a run of
/// incoming messages from one sender (in DMs and groups alike).
struct ChatRow: Identifiable {
    enum Kind {
        case day(String)
        case message(Message, showAvatar: Bool)
        /// "Jean added Lee": a line about the group, centred.
        case system(Message)
        /// Two or more deleted messages in a row, as one line: "3 messages deleted".
        case deletedRun(count: Int)
        /// "Voice call · 4:12", "Missed call": a call with this person, from this phone's call history.
        case call(CallRecord)
    }

    let id: String
    let kind: Kind

    static func rows(for conversation: Conversation, calls: [CallRecord] = [], calendar: Calendar = .current) -> [ChatRow] {
        var result: [ChatRow] = []
        var lastDay: Date?
        var lastSender: String??
        var waiting = calls.sorted { $0.date < $1.date }
        func flushCalls(before date: Date?) {
            while let call = waiting.first, date == nil || call.date <= date! {
                waiting.removeFirst()
                if lastDay == nil || !calendar.isDate(lastDay!, inSameDayAs: call.date) {
                    result.append(ChatRow(id: "day-call-\(call.id)", kind: .day(MessageFormat.day(call.date))))
                }
                lastDay = call.date
                result.append(ChatRow(id: "call-\(call.id)", kind: .call(call)))
                lastSender = nil
            }
        }
        for message in conversation.messages {
            flushCalls(before: message.date)
            if lastDay == nil || !calendar.isDate(lastDay!, inSameDayAs: message.date) {
                result.append(ChatRow(id: "day-\(message.id)", kind: .day(MessageFormat.day(message.date))))
                lastSender = nil
            }
            lastDay = message.date
            if message.isSystem {
                result.append(ChatRow(id: message.id, kind: .system(message)))
                lastSender = nil
                continue
            }
            let showAvatar = !message.isOwn && lastSender != .some(message.senderID)
            result.append(ChatRow(id: message.id, kind: .message(message, showAvatar: showAvatar)))
            lastSender = .some(message.senderID)
        }
        flushCalls(before: nil)
        return collapsingDeletedRuns(result)
    }

    /// Runs of two or more consecutive "This message was deleted" placeholders become one line.
    static func collapsingDeletedRuns(_ rows: [ChatRow]) -> [ChatRow] {
        var out: [ChatRow] = []
        var run: [ChatRow] = []
        func flush() {
            if run.count >= 2, let first = run.first {
                out.append(ChatRow(id: "deleted-run-\(first.id)", kind: .deletedRun(count: run.count)))
            } else {
                out.append(contentsOf: run)
            }
            run = []
        }
        for row in rows {
            if case .message(let message, _) = row.kind, message.deleted {
                run.append(row)
            } else {
                flush()
                out.append(row)
            }
        }
        flush()
        return out
    }
}
