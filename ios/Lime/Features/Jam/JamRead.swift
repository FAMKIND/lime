import SwiftUI

/// Which jam posts were opened on this phone (never sent anywhere): an unread article from someone else has a dot.
enum JamRead {
    static let key = "lime.jam.readPosts"
    static var ids: Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    static func mark(_ id: String) {
        var now = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !now.contains(id) else { return }
        now.append(id)
        UserDefaults.standard.set(Array(now.suffix(2000)), forKey: key)
    }
    static func isUnread(_ post: JamPostInfo, me: String) -> Bool { post.kind == "article" && post.state == "ready" && post.author != me && !ids.contains(post.postId) }
}
