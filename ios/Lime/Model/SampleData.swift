import Foundation

/// Made-up teachers and groups only. No real names, emails or phone numbers.
enum SampleData {
    static let me = Person(id: "me", name: "Shem Rajoon", tone: 4)

    static let jean = Person(id: "jean", name: "Jean Chung", tone: 3)
    static let grace = Person(id: "grace", name: "Grace Ortiz", tone: 0)
    static let rise = Person(id: "rise", name: "Rise Okafor", tone: 2)
    static let journey = Person(id: "journey", name: "Journey Park", tone: 6)
    static let autumn = Person(id: "autumn", name: "Autumn Reyes", tone: 7)
    static let marcus = Person(id: "marcus", name: "Marcus Bell", tone: 5)

    static func conversations(now: Date = Date()) -> [Conversation] {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        func msg(_ id: String, _ from: Person?, _ text: String, _ minutes: Double) -> Message {
            Message(id: id, senderID: from?.id, text: text, date: ago(minutes))
        }

        return [
            Conversation(
                id: "c1", title: journey.name, members: [journey],
                messages: [
                    msg("c1-1", journey, "Best breakfast in town? I'm trying the new place by the school.", 60 * 26),
                    msg("c1-2", nil, "Yes! Their pancakes are worth the wait.", 60 * 26 - 3),
                    msg("c1-3", journey, "Best breakfast in town breakfast in town. Save me a seat on Friday?", 55),
                ],
                isPinned: true, unread: 1),
            Conversation(
                id: "c2", title: autumn.name, members: [autumn],
                messages: [
                    msg("c2-1", autumn, "Can you share the unit plan for fractions?", 120),
                    msg("c2-2", nil, "Sending it over after lunch.", 118),
                    msg("c2-3", autumn, "Thank you, that helps a lot. Also, do you have the exit tickets?", 40),
                ],
                isPinned: false, unread: 2),
            Conversation(
                id: "c3", title: "Jean, Rise & Me", members: [jean, rise],
                messages: [
                    msg("c3-1", jean, "Best breakfast in town", 60 * 30),
                    msg("c3-2", rise, "Agreed. Pickup at 7:30?", 60 * 29),
                    msg("c3-3", nil, "I'll bring the coffee.", 60 * 28),
                    msg("c3-4", jean, "Best breakfast in town breakfast in town Best breakfast in town", 60 * 27),
                    msg("c3-5", nil, "Best breakfast in town breakfast in town Best breakfast in town", 60 * 26),
                ]),
            Conversation(
                id: "c4", title: "Grade 4 Team", members: [grace, marcus, jean, rise],
                messages: [
                    msg("c4-1", grace, "Reminder: report card comments are due Thursday.", 60 * 52),
                    msg("c4-2", marcus, "Thanks. Is the template still the one from last term?", 60 * 51),
                    msg("c4-3", nil, "Same template, same folder.", 60 * 50),
                ]),
            Conversation(
                id: "c5", title: "Science Fair Committee", members: [journey, autumn, grace, marcus, jean, rise],
                messages: [
                    msg("c5-1", marcus, "Judges are confirmed for the 14th.", 60 * 80),
                    msg("c5-2", autumn, "I'll print the rubrics.", 60 * 79),
                ]),
        ]
    }
}
