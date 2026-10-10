import Foundation
import SwiftUI

/// What a contact told this phone about themselves, as true now.
struct PeerStatus: Equatable, Sendable {
    let state: UserStatus
    let until: Date?
}

/// Status (LIME-108): mine, set by hand or by work hours, and my contacts' (shared only between accepted contacts).
extension ConversationStore {
    /// The status that holds for this person now: mine (from my choices and work hours), or a contact's (what they sent).
    func status(of userID: String) -> PeerStatus? {
        if userID == meProvider().id {
            let plan = StatusSettings.shared.plan()
            return plan.state == .available && plan.until == nil && StatusSettings.shared.manual == nil && !StatusSettings.shared.hours.enabled ? nil
                : PeerStatus(state: plan.state, until: plan.until)
        }
        return statuses[userID]
    }

    /// Reads what contacts last told this phone, with the ends of their periods applied.
    func refreshStatuses() {
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        guard let list = try? core.contactStatuses(nowMs: now) else { return }
        var next: [String: PeerStatus] = [:]
        for item in list {
            guard let state = UserStatus(rawValue: item.state) else { continue }
            next[item.userId] = PeerStatus(state: state, until: item.until.map { Date(timeIntervalSince1970: Double($0) / 1000) })
        }
        if next != statuses { statuses = next }
    }

    /// Tells the core what my status is now (it tells my accepted contacts, once per change). Called before each delivery.
    func publishStatus() {
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core else { return }
        let plan = StatusSettings.shared.plan()
        func ms(_ date: Date?) -> Int64? { date.map { Int64($0.timeIntervalSince1970 * 1000) } }
        // A plain "available, no end" is the default: nothing to tell until it changes from it.
        if plan.state == .available, plan.until == nil, plan.thenState == nil, (try? core.myStatus()) == nil { return }
        try? core.setMyStatus(status: StatusInfo(state: plan.state.rawValue, until: ms(plan.until), thenState: plan.thenState?.rawValue, thenUntil: ms(plan.thenUntil)))
    }

    /// My choices changed: tell my contacts now.
    func statusSettingsChanged() async {
        publishStatus()
        await deliverNow()
        await notifications?.releaseHeld()   // quiet may just have ended (Available again): the summary of what arrived
    }
}
