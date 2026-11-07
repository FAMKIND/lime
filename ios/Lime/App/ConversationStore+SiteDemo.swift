#if DEBUG
import Foundation
import UIKit

/// Demo mode (the website's screenshots, LIME-286r): a believable cast and six chats, with profile photos for about half of them.
/// The photos are read from a folder named by `-lime-demo-avatars <dir>` (`<dir>/<user id>.jpg`); the rest keep their initials.
extension ConversationStore {
    func demoSiteLink(screen: String) {
        let now = Date()
        let maya = Person(id: meProvider().id, name: "Maya Ortiz", tone: 6)
        meProvider = { maya }   // "MO", not "TT", on the profile button
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-lime-demo-avatars"), i + 1 < args.count {
            for id in ["mei", "lee", "priya.nair"] {
                AvatarCache.shared.set(FileManager.default.contents(atPath: args[i + 1] + "/" + id + ".jpg"), for: id)
            }
        }
        let mei = Person(id: "mei", name: "Mei Lin"), sam = Person(id: "sam", name: "Sam Park"), priya = Person(id: "priya.nair", name: "Priya Nair"), lee = Person(id: "lee", name: "Lee Wong")
        func mine(_ id: String, _ text: String, _ ago: Double, _ state: DeliveryState = .sent) -> Message { Message(id: id, senderID: nil, text: text, date: now.addingTimeInterval(-ago), state: state) }
        func theirs(_ id: String, _ who: String, _ text: String, _ ago: Double) -> Message { Message(id: id, senderID: who, text: text, date: now.addingTimeInterval(-ago)) }
        var meiMessages = [
            theirs("m1", "mei", "Are you coming to the staff meeting?", 3_000),
            mine("m2", "Yes, see you there", 2_900),
            theirs("m3", "mei", "Great. I'm bringing the new reading schedule.", 2_800),
        ]
        if screen.hasPrefix("site-offline") {
            let state: DeliveryState = screen.hasSuffix("waiting") ? .waiting : screen.hasSuffix("passed") ? .passed : .sent
            meiMessages.append(mine("m4", "Running late: start without me. Notes are in the shared folder.", 20, state))
        }
        conversations = [
            Conversation(id: "dm:mei", title: mei.name, members: [mei], messages: meiMessages),
            Conversation(id: "dm:sam", title: sam.name, members: [sam], messages: [theirs("s1", "sam", "The week 4 plan is in the folder", 93_000)], unread: 1),
            Conversation(id: "dm:priya.nair", title: priya.name, members: [priya], messages: [theirs("p1", "priya.nair", "Thank you! The reading circles worked.", 170_000)]),
            Conversation(id: "dm:lee", title: lee.name, members: [lee], messages: [theirs("l1", "lee", "I'll send the lesson plan in the morning.", 350_000)]),
        ]
        let team = demoMakeGroup(name: "Grade 4 Team", emoji: "🍎", memberIDs: ["mei", "lee", "sam"], owner: true)
        demoAddMessages(to: team, [("lee", "Can we plan the field trip on Friday?"), ("sam", "I can bring the permission forms"), ("mei", "I'll book the bus. Who wants to take the first aid kit?"), ("lee", "Me! I also have the map.")])
        if let t = conversations.firstIndex(where: { $0.id == team }) {
            conversations[t].messages[conversations[t].messages.count - 2].reactions = [ReactionChip(emoji: "👍", count: 3, mine: false, people: ["Lee Wong", "Sam Park", "Mei Lin"])]
            conversations[t].unread = 2
        }
        let staff = demoMakeGroup(name: "Staff room", emoji: "🏫", memberIDs: ["priya.nair", "sam"], owner: false)
        demoAddMessages(to: staff, [("priya.nair", "The photocopier is fixed.")])
        // Newest chat first, as the list orders them: the team, Mei, then the rest by age.
        let order = [team, "dm:mei", "dm:sam", "dm:priya.nair", "dm:lee", staff]
        conversations.sort { (order.firstIndex(of: $0.id) ?? 99) < (order.firstIndex(of: $1.id) ?? 99) }
        // The screens are captured at any hour; the times they show are pinned to 8:04 AM today (the message times then read 7:14 AM … Yesterday, Nov 5, Nov 3).
        if let pinned = Calendar.current.date(bySettingHour: 8, minute: 4, second: 0, of: now) {
            let shift = pinned.timeIntervalSince(now)
            for c in conversations.indices { for m in conversations[c].messages.indices { conversations[c].messages[m].date.addTimeInterval(shift) } }
        }
        switch screen {
        case "site-chat", "site-offline-waiting", "site-offline-passed", "site-offline-sent": path.append("dm:mei")
        case "site-group": path.append(team)
        default: break
        }
    }
}
#endif
