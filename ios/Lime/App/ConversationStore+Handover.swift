import Foundation

/// Handing a band's publishing to another owner (LIME-275c). The core does the work (the offer, the bundle, the take-over, the subscribers following); this is the
/// phone's side: what to show, and the four answers. A demo run keeps it in memory.
extension ConversationStore {
    /// The hand-over of this band that I am part of, if any.
    func handover(of jamID: String) -> HandoverInfo? { handovers.first { $0.jamId == jamID } }

    /// Offers made to me that wait for my answer.
    var incomingHandovers: [HandoverInfo] { handovers.filter { !$0.outgoing && $0.state == "offered" } }

    /// The band's owners other than me: the only people its publishing can go to.
    func handoverOwners(_ jamID: String) -> [OrgMemberInfo] { (orgMembersByJam[jamID] ?? []).filter { $0.role == "owner" && !$0.isMe } }

    /// Who publishes the band now: me when it is mine, else the writer I follow.
    func publisherID(_ page: JamPageInfo) -> String {
        if jamsMine.contains(where: { $0.jamId == page.jamId }) { return meProvider().id }
        return jamSubscriptions.first { $0.jamId == page.jamId }?.writer ?? page.writerId
    }

    /// "Published by Jean" (or "You").
    func publisherName(_ page: JamPageInfo) -> String {
        let id = publisherID(page)
        return id == meProvider().id ? "You" : teacherName(id)
    }

    /// Offers the band to an owner. `nil` on success, else the words for what went wrong.
    func offerHandover(_ jamID: String, to user: String) async -> String? {
        #if DEBUG
        if isDemo { handovers = [HandoverInfo(jamId: jamID, title: bandName(jamID), peer: user, outgoing: true, state: "offered")]; return nil }
        #endif
        guard let core, let link else { return "Couldn\u{2019}t hand it over: no connection." }
        do {
            let token = try await link.token()
            try await Task.detached(priority: .userInitiated) { try core.offerHandover(transport: link.transport, authToken: token, jamId: jamID, toUser: user) }.value
            refreshJams()
            await deliverNow()
            return nil
        } catch StoreError.Rejected {
            return "\(teacherName(user)) can\u{2019}t take it yet. They need a page of their own on lime first."
        } catch {
            return "Couldn\u{2019}t hand it over: \(ConnectionProblem.from(error).message)"
        }
    }

    func cancelHandover(_ jamID: String) async {
        #if DEBUG
        if isDemo { handovers.removeAll { $0.jamId == jamID }; return }
        #endif
        guard let core, let link else { return }
        do {
            let token = try await link.token()
            try await Task.detached { try core.cancelHandover(transport: link.transport, authToken: token, jamId: jamID) }.value
        } catch { report(ConnectionProblem.from(error)) }
        refreshJams()
        await deliverNow()
    }

    /// Yes: the bundle comes, and this phone publishes the band when it is all here.
    func acceptHandover(_ jamID: String) async {
        #if DEBUG
        if isDemo { demoTakeOver(jamID); return }
        #endif
        guard let core else { return }
        _ = try? await Task.detached { try core.acceptHandover(jamId: jamID) }.value
        refreshJams()
        await deliverNow()
    }

    func declineHandover(_ jamID: String) async {
        #if DEBUG
        if isDemo { handovers.removeAll { $0.jamId == jamID }; return }
        #endif
        guard let core, let link else { return }
        do {
            let token = try await link.token()
            try await Task.detached { try core.declineHandover(transport: link.transport, authToken: token, jamId: jamID) }.value
        } catch { report(ConnectionProblem.from(error)) }
        refreshJams()
        await deliverNow()
    }
}

#if DEBUG
extension ConversationStore {
    /// A demo offer made to me by Sam, for a band he publishes (a test asks with `-lime-demo-handover-offer`).
    func demoSeedHandoverOffer() {
        orgs = [OrgInfo(jamId: "demo-sam-band", conversationId: "grp:demo-writer", writerId: "sam", name: "Fractions that stick", myRole: "owner", memberCount: 3)]
        handovers = [HandoverInfo(jamId: "demo-sam-band", title: "Fractions that stick", peer: "sam", outgoing: false, state: "offered")]
    }

    /// In a demo the bundle and the take-over are instant: the band becomes mine.
    func demoTakeOver(_ jamID: String) {
        handovers.removeAll { $0.jamId == jamID }
        jamSubscriptions.removeAll { $0.jamId == jamID }
        let title = orgs.first { $0.jamId == jamID }?.name ?? "Band"
        jamsMine.append(JamInfo(jamId: jamID, conversationId: "jam:\(jamID)", writer: meProvider().id, title: title, about: "", topics: [], tiers: ["free"], mine: true,
                                status: "active", ended: false, community: false, communityState: nil, communityGroup: nil, subscriberCount: 2, postCount: 0, created: Int64(Date().timeIntervalSince1970 * 1000)))
    }
}
#endif
