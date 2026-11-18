#if DEBUG
import Foundation
import UIKit

/// Demo mode (the website's screenshots, LIME-286r, 347, 349): an invented cast of every age (Talia Brooks, Mrs Lindgren, Walt Brennan, Danny Cruz, Adaeze Nwosu, Kofi Mensah ...) and six chats, with profile photos.
/// The photos are read from a folder named by `-lime-demo-avatars <dir>` (`<dir>/<user id>.jpg`); a person without one keeps their initials.
extension ConversationStore {
    func demoSiteLink(screen: String) {
        let now = Date()
        let maya = Person(id: meProvider().id, name: "Maya Ortiz", tone: 6)
        meProvider = { maya }   // "MO", not "TT", on the profile button
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-lime-demo-avatars"), i + 1 < args.count {
            for id in ["talia", "luis", "kofi", "adaeze", "danny", "tran", "lindgren", "walt", "okome", "calton"] {
                AvatarCache.shared.set(FileManager.default.contents(atPath: args[i + 1] + "/" + id + ".jpg"), for: id)
            }
        }
        let talia = Person(id: "talia", name: "Talia Brooks"), lindgren = Person(id: "lindgren", name: "Mrs Lindgren"), adaeze = Person(id: "adaeze", name: "Adaeze Nwosu"), kofi = Person(id: "kofi", name: "Kofi Mensah")
        func mine(_ id: String, _ text: String, _ ago: Double, _ state: DeliveryState = .sent) -> Message { Message(id: id, senderID: nil, text: text, date: now.addingTimeInterval(-ago), state: state) }
        func theirs(_ id: String, _ who: String, _ text: String, _ ago: Double) -> Message { Message(id: id, senderID: who, text: text, date: now.addingTimeInterval(-ago)) }
        var taliaMessages = [
            theirs("m1", "talia", "Okay, THE EXIT TICKET WORKED on third period 🙌", 3_000),
            mine("m2", "Told you! What was the question?", 2_900),
            theirs("m3", "talia", "“What’s one thing that confused you?” Half of them wrote the same thing, so I know exactly what to reteach tomorrow.", 2_800),
        ]
        // The website's "sent" and "reply" screens (LIME-349b): the two lines the person would have just sent and got back, seeded at ~7:18 and ~7:19 AM (after the pin below) instead of
        // being sent for real, which stamps the shoot's own clock (11:33 PM) and catches "Sending…". `-lime-demo-thread sent|reply`.
        if let at = args.firstIndex(of: "-lime-demo-thread"), at + 1 < args.count, ["sent", "reply"].contains(args[at + 1]) {
            taliaMessages.append(mine("m5", "That’s the whole trick. Want my lab sheet for tomorrow?", 2_720))
            if args[at + 1] == "reply" { taliaMessages.append(theirs("m6", "talia", "YES. I’ll trade you my poem-of-the-week list 😄", 2_660)) }
        }
        if screen.hasPrefix("site-offline") {
            let state: DeliveryState = screen.hasSuffix("waiting") ? .waiting : screen.hasSuffix("passed") ? .passed : screen.hasSuffix("internet") ? .offline : .sent
            taliaMessages.append(mine("m4", "Running late, start the warm-up without me. Plan’s in the folder.", 20, state))
        }
        conversations = [
            Conversation(id: "dm:talia", title: talia.name, members: [talia], messages: taliaMessages),
            Conversation(id: "dm:lindgren", title: lindgren.name, members: [lindgren], messages: [theirs("s1", "lindgren", "My last first day is Monday. 41 of them and I still lay out the pencils the night before ✏️", 93_000)], unread: 1),
            Conversation(id: "dm:adaeze", title: adaeze.name, members: [adaeze], messages: [theirs("p1", "adaeze", "Nobody turned the titration pink this time 🧪", 170_000)]),
            Conversation(id: "dm:kofi", title: kofi.name, members: [kofi], messages: [theirs("l1", "kofi", "Families asked for more Spanish picture books. Twelve are in the cart.", 350_000)]),
        ]
        // Walt and Danny are only in the groups: their names are set here (a group looks a name up among the one-to-one chats).
        let names = ["walt": "Walt Brennan", "danny": "Danny Cruz", "talia": "Talia Brooks", "kofi": "Kofi Mensah", "adaeze": "Adaeze Nwosu"]
        func named(_ id: Conversation.ID) {
            if var group = demoGroups[id] {
                group.people = group.people.map { ($0.id, names[$0.id] ?? $0.name, $0.role) }
                demoGroups[id] = group
            }
            if let c = conversations.firstIndex(where: { $0.id == id }) { conversations[c].members = conversations[c].members.map { Person(id: $0.id, name: names[$0.id] ?? $0.name, username: $0.username) } }
        }
        let team = demoMakeGroup(name: "Robotics regional", emoji: "🤖", memberIDs: ["walt", "danny", "talia"], owner: true)
        named(team)
        // The group's cover: a photo for the header (the chat and the group's details), from `-lime-demo-covers <dir>/robotics.jpg` (LIME-349c).
        if let i = args.firstIndex(of: "-lime-demo-covers"), i + 1 < args.count, let cover = FileManager.default.contents(atPath: args[i + 1] + "/robotics.jpg") {
            AvatarCache.shared.set(cover, for: Self.groupCoverKey(team))
        }
        demoAddMessages(to: team, [("walt", "Regional is Saturday the 14th. Bus leaves the library at 6:45."), ("danny", "I’ve got the permission slips and a cooler of orange slices 🍊"), ("talia", "I can drive the second van. Who has the extra batteries?"), ("walt", "Me. And the spare gears. Don’t tell the kids I packed a spare robot.")])
        if let t = conversations.firstIndex(where: { $0.id == team }) {
            conversations[t].messages[conversations[t].messages.count - 2].reactions = [ReactionChip(emoji: "👍", count: 3, mine: false, people: ["Walt Brennan", "Danny Cruz", "Maya Ortiz"])]
            conversations[t].unread = 2
        }
        let staff = demoMakeGroup(name: "Staff room", emoji: "🏫", memberIDs: ["kofi", "adaeze"], owner: false)
        named(staff)
        demoAddMessages(to: staff, [("kofi", "Whoever fixed the copier: I love you.")])
        // Newest chat first, as the list orders them: the team, Talia, then the rest by age.
        let order = [team, "dm:talia", "dm:lindgren", "dm:adaeze", "dm:kofi", staff]
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
