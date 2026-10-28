import Foundation
import SwiftUI

/// Open posts and Discover (LIME-210c, `docs/jam.md` section 13): posts a writer chose to make readable by everyone on lime, signed by the writer's
/// device. The core fetches and **verifies** them; this is the glue the screens use. Filters are done here, on the phone: the server never learns what
/// a person looks for.
extension ConversationStore {
    /// Asks the server what is new in Discover, and whether it takes open posts at all. Quiet, and at most once a minute unless `force`.
    func refreshDiscover(force: Bool = false) async {
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core, let link, !discoverLoading else { return }
        if !force, Date().timeIntervalSince(discoverAsked) < 60 { return }
        discoverLoading = true
        discoverAsked = Date()
        defer { discoverLoading = false }
        guard let token = try? await link.token() else { return }
        for _ in 0..<4 {
            let since = discoverCursor
            guard let page = try? await Task.detached(priority: .utility, operation: { try core.fetchOpenFeed(transport: link.transport, authToken: token, since: since) }).value else { return }
            if page.enabled != openPostsEnabled { openPostsEnabled = page.enabled }
            if !page.gone.isEmpty { discoverItems.removeAll { page.gone.contains($0.postId) } }
            for item in page.items {
                if let i = discoverItems.firstIndex(where: { $0.postId == item.postId }) { discoverItems[i] = item } else { discoverItems.append(item) }
            }
            discoverCursor = page.cursor
            if page.items.count + page.gone.count < 50 { break }
        }
    }

    /// One open post, whole and verified on this phone (nil when it is gone or does not check out).
    func openPost(_ postID: String) async -> OpenPostInfo? {
        if let cached = openPostCache[postID] { return cached }
        #if DEBUG
        if isDemo { return demoOpenPosts[postID] }
        #endif
        guard let core, let link else { return nil }
        guard let post = try? await Task.detached(operation: { try core.fetchOpenPost(transport: link.transport, postId: postID) }).value else { return nil }
        openPostCache[postID] = post
        return post
    }

    /// The jam page of an open post's writer: the jam's name for the byline, and what Subscribe needs.
    func openWriterPage(_ userID: String) async -> JamPageInfo? {
        if let page = openWriterPages[userID] { return page }
        guard let page = await jamPage(of: userID) else { return nil }
        openWriterPages[userID] = page
        return page
    }

    /// The plain address of an open file (a path on the server).
    func openFileURL(_ path: String) -> URL? {
        #if DEBUG
        if isDemo { return nil }
        #endif
        guard let base = (link?.transport as? URLSessionTransport)?.baseURL else { return nil }
        return URL(string: base.absoluteString + path)
    }

    /// Discover's items, newest first, that pass the topic filter (kept here on the phone). A post I can read as a subscriber, or my own, is not repeated.
    func discoverList(topic: String?) -> [OpenFeedItem] {
        discoverItems.reversed().filter { item in
            guard let topic else { return true }
            return item.topics.contains { $0.caseInsensitiveCompare(topic) == .orderedSame }
        }
    }

    /// The topics and grades Discover's items carry, most used first (for the filter chips).
    var discoverTopics: [String] {
        var counts: [String: Int] = [:]
        for item in discoverItems { for topic in item.topics { counts[topic, default: 0] += 1 } }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }

    /// The name shown for an open post's writer: their name when this phone knows it, else their jam's title, else a plain word.
    func openWriterName(_ userID: String) -> String {
        let name = teacherName(userID)
        if name != "A teacher" { return name }
        if let title = openWriterPages[userID]?.title, !title.isEmpty { return title }
        return name
    }

    /// Changes who can read one of my posts (Edit). Subscribers to Everyone publishes an open copy; Everyone to Subscribers deletes it.
    func setPostAudience(_ post: JamPostInfo, to audience: String) async -> Bool {
        #if DEBUG
        if isDemo { demoSetAudience(post, audience); return true }
        #endif
        guard let core else { return false }
        do { try await Task.detached(priority: .userInitiated) { try core.setJamPostAudience(postId: post.postId, audience: audience) }.value }
        catch { CallDiagnostics.shared.log("jam audience failed: \(error)"); return false }
        refreshJams()
        await deliverNow()
        return true
    }
}
