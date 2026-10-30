import Foundation

/// A band's members and groups (LIME-246): the private members group, the roles, the invite link, the band's own groups. The core does the work; the server sees an
/// ordinary group. A demo run keeps it all in memory.
extension ConversationStore {
    /// The link that joins a band: it carries the jam, its writer and the invite token (the code), and opens lime.
    static func bandLink(code: String) -> String { "https://\(InviteLink.host)/b/#\(code)" }

    /// A code read from a link (`https://limemessenger.com/b/#<code>`, which keeps the token out of what a browser sends; the older `/b/<code>` and `lime://b/<code>` still work).
    static func bandCode(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        if url.scheme == "https", [InviteLink.host, "www.\(InviteLink.host)"].contains(url.host?.lowercased() ?? ""), parts.first == "b" {
            if parts.count == 2 { return parts[1] }
            if parts.count == 1, let fragment = url.fragment, !fragment.isEmpty { return fragment }
        }
        if url.scheme == "lime", url.host == "b", let code = parts.first { return code }
        return nil
    }

    /// The band a group belongs to (a group I am in that its owners made inside a band), if any.
    func orgParent(ofGroup conversationID: String) -> String? {
        for (jam, groups) in orgGroupsByJam where groups.contains(where: { $0.conversationId == conversationID && $0.joined }) { return jam }
        return nil
    }

    /// A band's name, for its badge's initial.
    func bandName(_ jamID: String) -> String {
        orgs.first { $0.jamId == jamID }?.name ?? jamsMine.first { $0.jamId == jamID }?.title ?? "B"
    }

    /// A band's invite read from what a camera saw: its link or the bare code; nil for anything else (a teacher's QR code, say).
    func bandInvite(fromScan text: String) -> OrgInvite? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let code = Self.bandCode(from: url) { return parseBandInvite(code) }
        return nil
    }

    /// My role in a band: `owner` for one I own (or run as an owner), `writer`, `member`; nil when I am not in it.
    func bandRole(_ jamID: String) -> String? {
        if jamsMine.contains(where: { $0.jamId == jamID }) { return "owner" }
        return orgs.first { $0.jamId == jamID }?.myRole
    }

    /// Whether I belong to the band, so its Members and Groups show.
    func isBandMember(_ jamID: String) -> Bool { bandRole(jamID) != nil }

    /// Reads what this phone holds: the bands I am in, and for each the people and groups.
    func refreshOrgs() async {
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core else { return }
        let list = await Task.detached(priority: .utility) { (try? core.myOrgs()) ?? [] }.value
        if list != orgs { orgs = list }
        for org in list { await loadOrgDetails(org.jamId) }
    }

    /// The band's people and groups. The band's owner opens its members group the first time.
    func loadOrg(_ jamID: String) async {
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core else { return }
        if jamsMine.contains(where: { $0.jamId == jamID }) { _ = try? await Task.detached { try core.orgStart(jamId: jamID) }.value }
        let list = await Task.detached(priority: .utility) { (try? core.myOrgs()) ?? [] }.value
        if list != orgs { orgs = list }
        await loadOrgDetails(jamID)
    }

    private func loadOrgDetails(_ jamID: String) async {
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core else { return }
        let (members, groups) = await Task.detached(priority: .utility) { ((try? core.orgMembers(jamId: jamID)) ?? [], (try? core.orgGroups(jamId: jamID)) ?? []) }.value
        if orgMembersByJam[jamID] != members { orgMembersByJam[jamID] = members }
        if orgGroupsByJam[jamID] != groups { orgGroupsByJam[jamID] = groups }
    }

    @discardableResult
    func addOrgMembers(_ jamID: String, users: [String]) async -> Bool {
        #if DEBUG
        if isDemo { demoAddOrgMember(jamID, users); return true }
        #endif
        guard let core else { return false }
        let ok = (try? await Task.detached { try core.addOrgMembers(jamId: jamID, userIds: users) }.value) != nil
        await loadOrgDetails(jamID)
        if ok { await deliverNow() }
        return ok
    }

    @discardableResult
    func setOrgRole(_ jamID: String, user: String, role: String) async -> Bool {
        #if DEBUG
        if isDemo { demoSetOrgRole(jamID, user, role); return true }
        #endif
        guard let core else { return false }
        let ok = (try? await Task.detached { try core.setOrgRole(jamId: jamID, userId: user, role: role) }.value) != nil
        await loadOrgDetails(jamID)
        if ok { await deliverNow() }
        return ok
    }

    @discardableResult
    func removeOrgMember(_ jamID: String, user: String) async -> Bool {
        #if DEBUG
        if isDemo { orgMembersByJam[jamID]?.removeAll { $0.userId == user }; return true }
        #endif
        guard let core else { return false }
        let ok = (try? await Task.detached { try core.removeOrgMember(jamId: jamID, userId: user) }.value) != nil
        await loadOrgDetails(jamID)
        if ok { await deliverNow() }
        return ok
    }

    func leaveOrg(_ jamID: String) async {
        #if DEBUG
        if isDemo { orgs.removeAll { $0.jamId == jamID }; orgMembersByJam[jamID] = nil; orgGroupsByJam[jamID] = nil; return }
        #endif
        guard let core else { return }
        _ = try? await Task.detached { try core.leaveOrg(jamId: jamID) }.value
        await refreshOrgs()
        refreshJams()
        await deliverNow()
    }

    /// The invite link (made the first time; owners).
    func orgInviteLink(_ jamID: String) async -> String? {
        #if DEBUG
        if isDemo { return demoOrgInviteOn ? Self.bandLink(code: "\(jamID).\(meProvider().id).demotoken") : nil }
        #endif
        guard let core else { return nil }
        guard let code = try? await Task.detached(operation: { try core.orgInviteCode(jamId: jamID) }).value else { return nil }
        return Self.bandLink(code: code)
    }

    /// Turns the link off (`on == false`) or makes a new one that replaces the old.
    func resetOrgInvite(_ jamID: String, on: Bool) async -> String? {
        #if DEBUG
        if isDemo { demoOrgInviteOn = on; return on ? Self.bandLink(code: "\(jamID).\(meProvider().id).demotoken2") : nil }
        #endif
        guard let core else { return nil }
        let code = (try? await Task.detached { try core.resetOrgInvite(jamId: jamID, on: on) }.value) ?? nil
        await deliverNow()
        return code.map { Self.bandLink(code: $0) }
    }

    /// Reads an invite from its code, if it is one.
    func parseBandInvite(_ code: String) -> OrgInvite? {
        let parts = code.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 || parts.count == 4, parts.prefix(3).allSatisfy({ !$0.isEmpty && $0.count <= 64 }) else { return nil }
        // The fourth part names the other owners (LIME-246d), so a join reaches every one of them.
        let owners = parts.count == 4 ? parts[3].split(separator: ",").map(String.init).filter { !$0.isEmpty && $0.count <= 64 }.prefix(4).map { $0 } : []
        return OrgInvite(jamId: parts[0], writerId: parts[1], token: parts[2], owners: owners)
    }

    /// Asks to join with an invite: the owner's phone adds me when it next runs.
    func joinOrg(_ invite: OrgInvite) async {
        let code = "\(invite.jamId).\(invite.writerId).\(invite.token)" + (invite.owners.isEmpty ? "" : "." + invite.owners.joined(separator: ","))
        #if DEBUG
        if isDemo { orgJoinStates[invite.jamId] = "asked"; return }
        #endif
        guard let core else { return }
        _ = try? await Task.detached { try core.joinOrg(code: code) }.value
        orgJoinStates[invite.jamId] = "asked"
        await deliverNow()
    }

    func refreshOrgJoinState(_ jamID: String) async {
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core else { return }
        let state = (try? await Task.detached { try core.orgJoinState(jamId: jamID) }.value) ?? nil
        if let state { orgJoinStates[jamID] = state }
        if state == "joined" { await refreshOrgs() }
    }

    /// A group inside the band: owners make it; members join the open ones.
    func createOrgGroup(_ jamID: String, name: String, emoji: String?, open: Bool, members: [String]) async -> String? {
        #if DEBUG
        if isDemo { return demoCreateOrgGroup(jamID, name: name, open: open) }
        #endif
        guard let core else { return nil }
        let made = (try? await Task.detached { try core.createOrgGroup(jamId: jamID, name: name, emoji: emoji, open: open, members: members) }.value) ?? nil
        await loadOrgDetails(jamID)
        if made != nil { await deliverNow() }
        return made
    }

    func joinOrgGroup(_ jamID: String, group: String) async {
        #if DEBUG
        if isDemo { orgJoinStates[group] = "asked"; return }
        #endif
        guard let core else { return }
        _ = try? await Task.detached { try core.joinOrgGroup(jamId: jamID, conversationId: group) }.value
        orgJoinStates[group] = "asked"
        await deliverNow()
    }

    func refreshOrgGroupJoin(_ jamID: String, group: String) async {
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core else { return }
        let state = (try? await Task.detached { try core.orgGroupJoinState(jamId: jamID, conversationId: group) }.value) ?? nil
        if let state { orgJoinStates[group] = state }
        await loadOrgDetails(jamID)
    }
}

#if DEBUG
extension ConversationStore {
    /// A demo band with people and groups, made for the Members and Groups screens (UI tests).
    func demoSeedOrg(_ jamID: String, mine: Bool) {
        let me = meProvider().id
        orgMembersByJam[jamID] = [
            OrgMemberInfo(userId: me, name: "You", tone: 4, role: mine ? "owner" : "member", isMe: true, canManage: false),
            OrgMemberInfo(userId: "sam", name: "Sam Park", tone: UInt32(AvatarTone.tone(for: "sam")), role: mine ? "writer" : "owner", isMe: false, canManage: mine),
            OrgMemberInfo(userId: "lee", name: "Lee Wong", tone: UInt32(AvatarTone.tone(for: "lee")), role: "member", isMe: false, canManage: mine),
        ]
        orgGroupsByJam[jamID] = [
            OrgGroupInfo(conversationId: "grp:demo-science", name: "Science", open: true, joined: mine, mine: mine),
            OrgGroupInfo(conversationId: "grp:demo-leads", name: "Leads", open: false, joined: mine, mine: mine),
        ]
        if !mine { orgs = [OrgInfo(jamId: jamID, conversationId: "grp:demo-members", writerId: "sam", name: "Fractions that stick", myRole: "member", memberCount: 3)] }
    }

    func demoAddOrgMember(_ jamID: String, _ users: [String]) {
        for user in users where !(orgMembersByJam[jamID] ?? []).contains(where: { $0.userId == user }) {
            let name = conversations.first { $0.id == "dm:\(user)" }?.title ?? user.capitalized
            orgMembersByJam[jamID, default: []].append(OrgMemberInfo(userId: user, name: name, tone: UInt32(AvatarTone.tone(for: user)), role: "member", isMe: false, canManage: true))
        }
    }

    func demoSetOrgRole(_ jamID: String, _ user: String, _ role: String) {
        guard let i = orgMembersByJam[jamID]?.firstIndex(where: { $0.userId == user }), let old = orgMembersByJam[jamID]?[i] else { return }
        orgMembersByJam[jamID]?[i] = OrgMemberInfo(userId: old.userId, name: old.name, tone: old.tone, role: role, isMe: old.isMe, canManage: old.canManage)
    }

    func demoCreateOrgGroup(_ jamID: String, name: String, open: Bool) -> String {
        let id = "grp:demo-\(name.lowercased().filter(\.isLetter))"
        orgGroupsByJam[jamID, default: []].append(OrgGroupInfo(conversationId: id, name: name, open: open, joined: true, mine: true))
        return id
    }
}
#endif
