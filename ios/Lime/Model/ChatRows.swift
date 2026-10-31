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
    }

    let id: String
    let kind: Kind
    /// The last message of a run (LIME-278): the next row is not a message from the same sender within a few minutes, so this is where its time shows. Every
    /// other time is one swipe away.
    var endsRun = true

    /// Messages from one sender this close together are one run.
    static let runGap: TimeInterval = 5 * 60

    static func rows(for conversation: Conversation, calendar: Calendar = .current) -> [ChatRow] {
        var result: [ChatRow] = []
        var lastDay: Date?
        var lastSender: String??
        for message in conversation.messages {
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
        return markingRunEnds(collapsingDeletedRuns(result))
    }

    /// Sets `endsRun` on every message row (a message ends its run unless the next row is a message by the same sender less than five minutes later).
    static func markingRunEnds(_ rows: [ChatRow]) -> [ChatRow] {
        var out = rows
        for index in out.indices {
            guard case .message(let message, _) = out[index].kind else { continue }
            if index + 1 < out.count, case .message(let next, _) = out[index + 1].kind, next.senderID == message.senderID,
               next.date.timeIntervalSince(message.date) < runGap {
                out[index].endsRun = false
            }
        }
        return out
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
