#if DEBUG
import Foundation
import UIKit

/// Demo mode (the website's screenshots, LIME-286r, 347): an invented cast (Talia Brooks, Luis Ortega, Adaeze Nwosu, Kofi Mensah) and six chats, with profile photos for some of them.
/// The photos are read from a folder named by `-lime-demo-avatars <dir>` (`<dir>/<user id>.jpg`); the rest keep their initials.
extension ConversationStore {
    func demoSiteLink(screen: String) {
        let now = Date()
        let maya = Person(id: meProvider().id, name: "Maya Ortiz", tone: 6)
        meProvider = { maya }   // "MO", not "TT", on the profile button
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-lime-demo-avatars"), i + 1 < args.count {
            for id in ["talia", "luis", "kofi", "okome", "calton"] {
                AvatarCache.shared.set(FileManager.default.contents(atPath: args[i + 1] + "/" + id + ".jpg"), for: id)
            }
        }
        let talia = Person(id: "talia", name: "Talia Brooks"), luis = Person(id: "luis", name: "Luis Ortega"), adaeze = Person(id: "adaeze", name: "Adaeze Nwosu"), kofi = Person(id: "kofi", name: "Kofi Mensah")
        func mine(_ id: String, _ text: String, _ ago: Double, _ state: DeliveryState = .sent) -> Message { Message(id: id, senderID: nil, text: text, date: now.addingTimeInterval(-ago), state: state) }
        func theirs(_ id: String, _ who: String, _ text: String, _ ago: Double) -> Message { Message(id: id, senderID: who, text: text, date: now.addingTimeInterval(-ago)) }
        var taliaMessages = [
            theirs("m1", "talia", "Are you coming to Thursday's planning meeting?", 3_000),
            mine("m2", "Yes, see you there", 2_900),
            theirs("m3", "talia", "I'll bring the poetry unit", 2_800),
        ]
        if screen.hasPrefix("site-offline") {
            let state: DeliveryState = screen.hasSuffix("waiting") ? .waiting : screen.hasSuffix("passed") ? .passed : screen.hasSuffix("internet") ? .offline : .sent
            taliaMessages.append(mine("m4", "Running late: start without me. Notes are in the shared folder.", 20, state))
        }
        conversations = [
            Conversation(id: "dm:talia", title: talia.name, members: [talia], messages: taliaMessages),
            Conversation(id: "dm:luis", title: luis.name, members: [luis], messages: [theirs("s1", "luis", "The Local Government Lab handout is in the folder", 93_000)], unread: 1),
            Conversation(id: "dm:adaeze", title: adaeze.name, members: [adaeze], messages: [theirs("p1", "adaeze", "Thank you! The lab went well.", 170_000)]),
            Conversation(id: "dm:kofi", title: kofi.name, members: [kofi], messages: [theirs("l1", "kofi", "I'll send the flyer for literacy night in the morning.", 350_000)]),
        ]
        let team = demoMakeGroup(name: "8th Grade Team", emoji: "📚", memberIDs: ["talia", "luis", "adaeze"], owner: true)
        demoAddMessages(to: team, [("luis", "Can we plan the field trip on Friday?"), ("adaeze", "I can bring the permission forms"), ("talia", "I'll book the bus. Who wants to take the first aid kit?"), ("luis", "Me! I also have the map.")])
        if let t = conversations.firstIndex(where: { $0.id == team }) {
            conversations[t].messages[conversations[t].messages.count - 2].reactions = [ReactionChip(emoji: "👍", count: 3, mine: false, people: ["Luis Ortega", "Adaeze Nwosu", "Talia Brooks"])]
            conversations[t].unread = 2
        }
        let staff = demoMakeGroup(name: "Staff room", emoji: "🏫", memberIDs: ["kofi", "adaeze"], owner: false)
        demoAddMessages(to: staff, [("kofi", "The photocopier is fixed.")])
        // Newest chat first, as the list orders them: the team, Talia, then the rest by age.
        let order = [team, "dm:talia", "dm:luis", "dm:adaeze", "dm:kofi", staff]
        conversations.sort { (order.firstIndex(of: $0.id) ?? 99) < (order.firstIndex(of: $1.id) ?? 99) }
        // The screens are captured at any hour; the times they show are pinned to 8:04 AM today (the message times then read 7:14 AM … Yesterday, Nov 5, Nov 3).
        if let pinned = Calendar.current.date(bySettingHour: 8, minute: 4, second: 0, of: now) {
            let shift = pinned.timeIntervalSince(now)
            for c in conversations.indices { for m in conversations[c].messages.indices { conversations[c].messages[m].date.addTimeInterval(shift) } }
        }
        switch screen {
        case "site-chat", "site-offline-waiting", "site-offline-passed", "site-offline-sent": path.append("dm:talia")
        case "site-group": path.append(team)
        default: break
        }
    }
}
#endif
