import Foundation

/// A band's writers send posts for review; an owner publishes (LIME-273). The draft is the ordinary shared article draft; the core carries the review.
extension ConversationStore {
    /// Bands I write for without owning them: I can draft as the band, and an owner publishes.
    var bandsIWriteFor: [OrgInfo] { orgs.filter { $0.myRole == "writer" } }

    /// This draft's place in a band's review (empty for an ordinary draft).
    func draftReview(_ id: String) -> DraftReview? {
        guard let review = try? draftCore?.draftReview(draftId: id), !review.jamId.isEmpty else { return nil }
        return review
    }

    /// Sends the draft to the band's owners. The band's owners are invited to it, told, and it waits in their band page.
    func sendDraftForReview(_ id: String, band: String) async -> Bool {
        #if DEBUG
        if isDemo { return true }
        #endif
        guard let core = draftCore else { return false }
        do { try core.sendDraftForReview(draftId: id, jamId: band) } catch { CallDiagnostics.shared.log("send for review failed: \(error)"); return false }
        refreshDraftChannels()
        draftRevision += 1
        await flushDrafts()
        await deliverNow()
        return true
    }

    /// The drafts waiting for this band's owners.
    func waitingForReview(_ jamID: String) -> [ReviewItem] {
        _ = draftRevision
        #if DEBUG
        if isDemo { return demoReviewItems }
        #endif
        return (try? draftCore?.draftsWaitingForReview(jamId: jamID)) ?? []
    }

    /// An owner returns it to the writer with a note.
    func sendDraftBack(_ id: String, note: String) async -> Bool {
        #if DEBUG
        if isDemo { demoReviewItems.removeAll { $0.draftId == id }; draftRevision += 1; return true }
        #endif
        guard let core = draftCore else { return false }
        do { try core.sendDraftBack(draftId: id, note: note) } catch { return false }
        draftRevision += 1
        await flushDrafts()
        await deliverNow()
        return true
    }

    /// The banner words for an invitation: a review draft says who sent what to which band.
    func reviewBannerLine(_ invite: DraftInvite) -> (title: String, band: String)? {
        guard let review = draftReview(invite.draftID), review.state == "waiting" else { return nil }
        return (invite.title, orgs.first { $0.jamId == review.jamId }?.name ?? jamsMine.first { $0.jamId == review.jamId }?.title ?? "the band")
    }
}

#if DEBUG
extension ConversationStore {
    /// Tests: `-lime-demo-review-writer` makes me a writer of a band (Send for review is offered); `-lime-demo-review-owner` leaves one draft waiting in my band.
    func demoReviewIfAsked() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-lime-demo-review-writer") {
            orgs = [OrgInfo(jamId: "demo-band-writer", conversationId: "grp:demo-writer-members", writerId: "sam", name: "lime juice", myRole: "writer", memberCount: 3)]
        }
        if args.contains("-lime-demo-review-owner") {
            demoReviewItems = [ReviewItem(draftId: "demo-review-1", title: "Seed swap", writer: "sam", updatedAt: Int64(Date().timeIntervalSince1970 * 1000))]
        }
    }
}
#endif
