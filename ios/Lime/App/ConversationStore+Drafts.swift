import Foundation

/// Drafts written with others (LIME-233b): the instant path (Realtime broadcast) and the durable flush, from the app's side.
extension ConversationStore {
    /// Opens the socket for the drafts I write in. Called once the account is live.
    func startDraftRealtime(_ config: BackendConfig) {
        #if DEBUG
        if isDemo { return }
        #endif
        guard core != nil else { return }
        draftRealtime = DraftRealtime(baseURL: config.url, apiKey: config.apiKey) { [weak self] channel, wire in
            Task { @MainActor in self?.receiveInstant(channel: channel, wire: wire) }
        }
        refreshDraftChannels()
    }

    /// Joins the channels of the drafts I am an author of (after an invitation, a removal, a new draft).
    func refreshDraftChannels() {
        guard let core, let realtime = draftRealtime else { return }
        let channels = Set(((try? core.draftChannels()) ?? []).map(\.channelId))
        Task { await realtime.setChannels(channels) }
    }

    private func receiveInstant(channel: String, wire: Data) {
        guard let core, let event = (try? core.draftInstantReceive(channelId: channel, wire: wire)) ?? nil else { return }
        draftRevision += 1
        draftEventSink?(event)
    }

    /// The editor changed the draft: the change goes out at once on the instant path (the durable path follows within seconds).
    func sendDraftChangeInstantly(_ draftID: String) {
        guard let core, let realtime = draftRealtime else { return }
        guard let wire = (try? core.draftInstantChange(draftId: draftID)) ?? nil,
              let channel = ((try? core.draftChannels()) ?? []).first(where: { $0.draftId == draftID })?.channelId else { return }
        Task { await realtime.broadcast(channel: channel, wire: wire) }
    }

    /// My caret and selection, instantly.
    func sendDraftPresence(_ draftID: String, _ presence: DraftPresence) {
        guard let core, let realtime = draftRealtime else { return }
        guard let wire = (try? core.draftInstantPresence(draftId: draftID, presence: presence)) ?? nil,
              let channel = ((try? core.draftChannels()) ?? []).first(where: { $0.draftId == draftID })?.channelId else { return }
        Task { await realtime.broadcast(channel: channel, wire: wire) }
    }

    /// Sends what is due on the durable path now.
    func flushDrafts() async {
        guard let core, let link, let token = try? await link.token() else { return }
        _ = try? await Task.detached { try core.flushDrafts(transport: link.transport, authToken: token) }.value
    }
}
