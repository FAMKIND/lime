import Foundation

/// Emergency mode (LIME-143): sending a status, ending an emergency, the roll-up and this phone's choices. Everything that decides anything is in LimeCore.
extension ConversationStore {
    /// This phone's emergency choices (the group, the SRP actions, the sound, the last values).
    func emergencySettings() async -> EmergencySettings {
        #if DEBUG
        if isDemo { return demoEmergencySettings }
        #endif
        guard let core else { return EmergencySettings(groupId: "", schoolActions: true, sound: false, lastStudents: 0, lastPlace: "") }
        return (try? await Task.detached { try core.emergencySettings() }.value) ?? EmergencySettings(groupId: "", schoolActions: true, sound: false, lastStudents: 0, lastPlace: "")
    }

    func saveEmergencySettings(_ settings: EmergencySettings) async {
        #if DEBUG
        if isDemo { demoEmergencySettings = settings; return }
        #endif
        guard let core else { return }
        _ = try? await Task.detached { try core.setEmergencySettings(settings: settings) }.value
    }

    /// Sends a status. True when it was queued.
    @discardableResult
    func sendEmergency(_ draft: EmergencyDraft, to conversationID: Conversation.ID) async -> Bool {
        #if DEBUG
        if isDemo { return demoSendEmergency(draft, to: conversationID) }
        #endif
        guard let core else { return false }
        let item = try? await Task.detached(priority: .userInitiated) { try core.sendEmergency(conversationId: conversationID, draft: draft) }.value
        guard item != nil else { return false }
        await reload()
        await deliverNow()
        return true
    }

    func endEmergency(in conversationID: Conversation.ID) async {
        #if DEBUG
        if isDemo { demoEndEmergency(conversationID); return }
        #endif
        guard let core else { return }
        _ = try? await Task.detached(priority: .userInitiated) { try core.endEmergency(conversationId: conversationID) }.value
        await reload()
        await deliverNow()
    }

    /// The live overview of the conversation's active emergency, or nil.
    func emergencyRollup(for conversationID: Conversation.ID) async -> EmergencyRollup? {
        #if DEBUG
        if isDemo { return demoEmergencyRollup(conversationID) }
        #endif
        guard let core else { return nil }
        return (try? await Task.detached { try core.emergencyRollup(conversationId: conversationID) }.value) ?? nil
    }

    /// Groups an emergency can go to (not requests, not ended).
    var emergencyGroups: [Conversation] { conversations.filter { $0.isGroup && !$0.isRequest && $0.groupEnded == nil } }
}

#if DEBUG
/// The demo has no core: a status is shown as the card and the panel from what was sent here (only the people who answered).
extension ConversationStore {
    func demoSendEmergency(_ draft: EmergencyDraft, to id: Conversation.ID) -> Bool {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return false }
        let session = demoEmergencySessions[id] ?? UUID().uuidString
        demoEmergencySessions[id] = session
        let info = EmergencyInfo(sessionId: session, kind: "status", status: draft.status, situation: draft.situation, students: draft.students, place: draft.place, note: draft.note, drill: draft.drill)
        var message = Message(id: UUID().uuidString, senderID: nil, text: "Emergency", date: Date(), state: .sent)
        message.emergency = EmergencyCard(info)
        conversations[index].messages.append(message)
        demoEmergencyStatuses[id] = (draft, Date())
        return true
    }

    func demoEndEmergency(_ id: Conversation.ID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }), let session = demoEmergencySessions[id] else { return }
        let drill = demoEmergencyStatuses[id]?.0.drill ?? false
        let info = EmergencyInfo(sessionId: session, kind: "end", status: "", situation: "", students: 0, place: "", note: "", drill: drill)
        var message = Message(id: UUID().uuidString, senderID: nil, text: "Emergency ended", date: Date(), state: .sent)
        message.emergency = EmergencyCard(info)
        conversations[index].messages.append(message)
        demoEmergencySessions[id] = nil
        demoEmergencyStatuses[id] = nil
    }

    func demoEmergencyRollup(_ id: Conversation.ID) -> EmergencyRollup? {
        guard let session = demoEmergencySessions[id], let (draft, date) = demoEmergencyStatuses[id], let conversation = conversation(id) else { return nil }
        var entries = [RollupEntry(userId: nil, status: draft.status, situation: draft.situation, students: draft.students, place: draft.place, note: draft.note,
                                   at: Int64(date.timeIntervalSince1970 * 1000), messageId: nil)]
        for member in conversation.members {
            entries.append(RollupEntry(userId: member.id, status: "no_response", situation: "", students: 0, place: "", note: "", at: 0, messageId: nil))
        }
        entries.sort { ($0.status == "need_help" ? 0 : $0.status == "no_response" ? 1 : 2) < ($1.status == "need_help" ? 0 : $1.status == "no_response" ? 1 : 2) }
        return EmergencyRollup(sessionId: session, conversationId: id, drill: draft.drill, entries: entries, studentsTotal: draft.students,
                               safe: draft.status == "safe" ? 1 : 0, needHelp: draft.status == "need_help" ? 1 : 0, noResponse: UInt32(conversation.members.count))
    }
}
#endif
