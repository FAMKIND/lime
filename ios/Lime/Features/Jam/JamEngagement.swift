import SwiftUI

/// The ♥ with its count (LIME-189c): a tap toggles it (a filled lime heart when it is on, a light haptic); a count of 0 shows no number. One button
/// "Like, 12" for VoiceOver, selected when on.
struct JamHeartButton: View {
    let postID: String
    var size: CGFloat = 18
    var dark = false
    @Environment(ConversationStore.self) private var store

    var body: some View {
        let counts = store.jamCounts(postID)
        let on = counts.likedByMe
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            store.jamToggleLike(postID)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: on ? "heart.fill" : "heart").font(.system(size: size))
                    .foregroundStyle(on ? (dark ? Theme.heartOnBlack : Theme.heart) : (dark ? Color.white : Theme.text).opacity(0.7))
                if counts.likes > 0 { Text("\(counts.likes)").font(Theme.caption.monospacedDigit()).foregroundStyle(dark ? Color.white.opacity(0.85) : Theme.textSecondary) }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(counts.likes > 0 ? "Like, \(counts.likes)" : "Like").accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityIdentifier("jam-like-\(postID)")
    }
}

/// The comment count button beside it (opens the post page where the comments are).
struct JamCommentCount: View {
    let postID: String
    var size: CGFloat = 18
    var dark = false
    let action: () -> Void
    @Environment(ConversationStore.self) private var store

    var body: some View {
        let counts = store.jamCounts(postID)
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left").font(.system(size: size)).foregroundStyle((dark ? Color.white : Theme.text).opacity(0.7))
                if counts.comments > 0 { Text("\(counts.comments)").font(Theme.caption.monospacedDigit()).foregroundStyle(dark ? Color.white.opacity(0.85) : Theme.textSecondary) }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(counts.comments > 0 ? "Comments, \(counts.comments)" : "Comment")
        .accessibilityIdentifier("jam-comment-\(postID)")
    }
}

/// The post page's response part (LIME-189c): "20 likes · 3 comments · 0 remixes", the faces of up to five of your contacts who liked, a place to leave
/// a comment, and the comments (one level of replies under their parent). A pending comment waits greyed for the writer's phone.
struct JamEngagementSection: View {
    let post: JamPostInfo
    /// On the black player (LIME-189d): white text.
    var dark = false
    /// True while the comment field has the keyboard: the page hides its action pill then.
    var typing: Binding<Bool>? = nil
    @Environment(ConversationStore.self) private var store
    private var ink: Color { dark ? .white : Theme.text }
    private var soft: Color { dark ? .white.opacity(0.7) : Theme.textSecondary }
    private var fieldFill: Color { dark ? .white.opacity(0.14) : Theme.surface }
    private var line: Color { dark ? .white.opacity(0.2) : Theme.hairline }
    @State private var text = ""
    @State private var replyingTo: JamCommentInfo?
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        let counts = store.jamCounts(post.postId)
        let comments = store.jamComments(post.postId)
        let top = comments.filter { $0.parentId == nil }
        let mineJam = store.isMyJamPost(post)
        let writer = store.teacherName(post.author)
        VStack(alignment: .leading, spacing: 14) {
            Text("\(counts.likes) \(counts.likes == 1 ? "like" : "likes") \u{00B7} \(counts.comments) \(counts.comments == 1 ? "comment" : "comments") \u{00B7} \(counts.remixes) remixes")
                .font(Theme.secondary).foregroundStyle(soft).accessibilityIdentifier("jam-counts-line")
            faces(counts)
            composer(writer)
            ForEach(top, id: \.commentId) { comment in
                row(comment, mineJam: mineJam, writer: writer)
                ForEach(comments.filter { $0.parentId == comment.commentId }, id: \.commentId) { reply in
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle().fill(line).frame(width: 1).padding(.leading, 15)
                        row(reply, mineJam: mineJam, writer: writer)
                    }
                    .padding(.leading, 12)
                }
            }
        }
        .onAppear { if mineJam { store.jamMarkSeen(post.postId) } }
        .onChange(of: focused) { _, now in typing?.wrappedValue = now }
        // Room under the last comment: the action pill and the dock must not cover the field or the words (LIME-189d).
        .padding(.bottom, dark ? 24 : 96)
    }

    @ViewBuilder
    private func faces(_ counts: JamCountsInfo) -> some View {
        let known = store.contactLikers(counts)
        if !known.isEmpty {
            let others = Int(counts.likes) - 1
            let words = others > 0 ? "\(known[0].name) and \(others) other\(others == 1 ? "" : "s")" : known[0].name
            HStack(spacing: 10) {
                HStack(spacing: -8) {
                    ForEach(Array(known.prefix(5).enumerated()), id: \.offset) { _, person in AvatarView(person: person, size: 28).overlay(Circle().stroke(Theme.canvas, lineWidth: 2)) }
                }
                .accessibilityHidden(true)
                Text(words).font(Theme.secondary).foregroundStyle(ink)
            }
            .accessibilityElement(children: .ignore).accessibilityLabel("Liked by \(words)").accessibilityIdentifier("jam-likers")
        }
    }

    private func composer(_ writer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let replyingTo {
                HStack {
                    Text("Replying to \(store.teacherName(replyingTo.author))").font(Theme.caption).foregroundStyle(soft)
                    Button { self.replyingTo = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(soft) }.accessibilityLabel("Cancel reply").accessibilityIdentifier("jam-reply-cancel")
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Leave a comment\u{2026}", text: $text, axis: .vertical).lineLimit(1...5).focused($focused)
                    .font(Theme.body).foregroundStyle(ink).padding(.horizontal, 14).padding(.vertical, 10)
                    .background(fieldFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityIdentifier("jam-comment-field")
                let ready = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending
                Button { send() } label: {
                    Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.accentInk).frame(width: 40, height: 40)
                        .background(Theme.accent.opacity(ready ? 1 : 0.35), in: Circle()).frame(width: 44, height: 44)
                }
                .disabled(!ready).accessibilityLabel("Send comment").accessibilityIdentifier("jam-comment-send")
            }
        }
    }

    private func send() {
        let words = text
        let parent = replyingTo?.commentId
        sending = true
        Task {
            if await store.jamComment(post.postId, text: words, parent: parent) { text = ""; replyingTo = nil; focused = false }
            sending = false
        }
    }

    private func row(_ comment: JamCommentInfo, mineJam: Bool, writer: String) -> some View {
        let person = store.teacher(comment.author)
        let pending = comment.state == "pending"
        let stale = pending && Date().timeIntervalSince1970 * 1000 - Double(comment.created) > 86_400_000
        return HStack(alignment: .top, spacing: 10) {
            AvatarView(person: person, size: 32).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(person.name).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(ink)
                    Text(JamDates.text(comment.created)).font(Theme.caption).foregroundStyle(soft)
                }
                Text(comment.text).font(Theme.body).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
                if pending {
                    Text(stale ? "Not delivered yet" : "Waiting for \(writer)\u{2019}s phone").font(Theme.caption).foregroundStyle(soft).accessibilityIdentifier("jam-comment-pending")
                } else {
                    Button { replyingTo = comment; focused = true } label: { Text("Reply").font(Theme.caption.weight(.semibold)).foregroundStyle(soft).frame(minHeight: 32) }
                        .buttonStyle(.plain).accessibilityIdentifier("jam-reply-\(comment.commentId)")
                }
            }
            Spacer(minLength: 0)
            Menu {
                if !comment.mine && !mineJam { Button { Task { await store.messageWriter(post.author) } } label: { Label("Reply privately", systemImage: "paperplane") }.accessibilityIdentifier("jam-comment-private") }
                if comment.mine { Button(role: .destructive) { Task { await store.jamDeleteComment(comment.commentId, postID: post.postId) } } label: { Label("Delete", systemImage: "trash") }.accessibilityIdentifier("jam-comment-delete") }
                else if mineJam { Button(role: .destructive) { Task { await store.jamDeleteComment(comment.commentId, postID: post.postId) } } label: { Label("Remove", systemImage: "trash") }.accessibilityIdentifier("jam-comment-remove") }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(soft).frame(width: 36, height: 36).contentShape(Rectangle())
            }
            .accessibilityLabel("Comment options").accessibilityIdentifier("jam-comment-more-\(comment.commentId)")
        }
        .opacity(pending ? 0.6 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("jam-comment-row-\(comment.commentId)")
    }
}

/// Activity on a profile (LIME-189d). Your own: comments on your posts and your own likes, comments and replies. Someone else's: only what you can already see
/// of theirs (posts on this phone). Each line opens its post. Local; no push.
struct JamActivityList: View {
    let userID: String
    let isMe: Bool
    @Environment(ConversationStore.self) private var store
    @State private var reading: JamPostRoute?

    var body: some View {
        let items = store.jamActivity(of: userID)
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                Text(isMe ? "Your likes and comments will show here." : "Nothing you can see yet.").font(Theme.body).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6).accessibilityIdentifier("profile-empty-activity")
            }
            ForEach(items) { item in
                let who = store.teacher(item.who)
                let title = item.post.title.isEmpty ? "a post" : "\u{201C}\(item.post.title)\u{201D}"
                let line: String = {
                    switch item.kind {
                    case .commentedOnMine: return "\(who.name) commented on \(item.post.title.isEmpty ? "your post" : title)"
                    case .commented: return isMe ? "You commented on \(title)" : "\(who.name) commented on \(title)"
                    case .replied: return isMe ? "You replied on \(title)" : "\(who.name) replied on \(title)"
                    case .liked: return isMe ? "You liked \(title)" : "\(who.name) liked \(title)"
                    }
                }()
                Button { reading = JamPostRoute(postID: item.post.postId) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        if item.kind == .liked { Image(systemName: "heart.fill").foregroundStyle(Theme.heart).frame(width: 36, height: 36).accessibilityHidden(true) }
                        else { AvatarView(person: who, size: 36).accessibilityHidden(true) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                            if !item.text.isEmpty { Text(item.text).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(2).multilineTextAlignment(.leading) }
                            Text(JamDates.text(item.date)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("jam-activity-\(item.id)")
                Divider().overlay(Theme.hairline)
            }
        }
        .sheet(item: $reading) { route in NavigationStack { JamPostView(postID: route.postID).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { reading = nil } } } } }
    }
}


/// The row at the foot of every card (LIME-212b): ♥ · 💬 · remix · share in four equal columns, the same on posts, articles and podcasts. Remix and
/// share are **disabled** buttons (dimmed; "Coming soon" for VoiceOver) until they exist.
struct JamActionRow: View {
    let postID: String
    let comment: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            JamHeartButton(postID: postID)
            JamCommentCount(postID: postID, action: comment)
            ForEach([("arrow.2.squarepath", "remix"), ("square.and.arrow.up", "share")], id: \.1) { icon, label in
                Button {} label: {
                    Image(systemName: icon).font(.system(size: 18)).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(true).foregroundStyle(Theme.textSecondary.opacity(0.5))
                .accessibilityLabel(label).accessibilityHint("Coming soon").accessibilityIdentifier("jam-action-\(label)-\(postID)")
            }
        }
    }
}
