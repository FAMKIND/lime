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
                    .foregroundStyle(on ? Theme.accent : (dark ? Color.white : Theme.text).opacity(0.7))
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
    @Environment(ConversationStore.self) private var store
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
                .font(Theme.secondary).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("jam-counts-line")
            faces(counts)
            composer(writer)
            ForEach(top, id: \.commentId) { comment in
                row(comment, mineJam: mineJam, writer: writer)
                ForEach(comments.filter { $0.parentId == comment.commentId }, id: \.commentId) { reply in
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle().fill(Theme.hairline).frame(width: 1).padding(.leading, 15)
                        row(reply, mineJam: mineJam, writer: writer)
                    }
                    .padding(.leading, 12)
                }
            }
        }
        .onAppear { if mineJam { store.jamMarkSeen(post.postId) } }
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
                Text(words).font(Theme.secondary).foregroundStyle(Theme.text)
            }
            .accessibilityElement(children: .ignore).accessibilityLabel("Liked by \(words)").accessibilityIdentifier("jam-likers")
        }
    }

    private func composer(_ writer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let replyingTo {
                HStack {
                    Text("Replying to \(store.teacherName(replyingTo.author))").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    Button { self.replyingTo = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary) }.accessibilityLabel("Cancel reply").accessibilityIdentifier("jam-reply-cancel")
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Leave a comment\u{2026}", text: $text, axis: .vertical).lineLimit(1...5).focused($focused)
                    .font(Theme.body).padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                    Text(person.name).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(JamDates.text(comment.created)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                Text(comment.text).font(Theme.body).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                if pending {
                    Text(stale ? "Not delivered yet" : "Waiting for \(writer)\u{2019}s phone").font(Theme.caption).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("jam-comment-pending")
                } else {
                    Button { replyingTo = comment; focused = true } label: { Text("Reply").font(Theme.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary).frame(minHeight: 32) }
                        .buttonStyle(.plain).accessibilityIdentifier("jam-reply-\(comment.commentId)")
                }
            }
            Spacer(minLength: 0)
            Menu {
                if !comment.mine && !mineJam { Button { Task { await store.messageWriter(post.author) } } label: { Label("Reply privately", systemImage: "paperplane") }.accessibilityIdentifier("jam-comment-private") }
                if comment.mine { Button(role: .destructive) { Task { await store.jamDeleteComment(comment.commentId, postID: post.postId) } } label: { Label("Delete", systemImage: "trash") }.accessibilityIdentifier("jam-comment-delete") }
                else if mineJam { Button(role: .destructive) { Task { await store.jamDeleteComment(comment.commentId, postID: post.postId) } } label: { Label("Remove", systemImage: "trash") }.accessibilityIdentifier("jam-comment-remove") }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(Theme.textSecondary).frame(width: 36, height: 36).contentShape(Rectangle())
            }
            .accessibilityLabel("Comment options").accessibilityIdentifier("jam-comment-more-\(comment.commentId)")
        }
        .opacity(pending ? 0.6 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("jam-comment-row-\(comment.commentId)")
    }
}

/// Activity on your own profile (LIME-189c): the newest comments on your posts, each opening its post. Local; no push.
struct JamActivityList: View {
    @Environment(ConversationStore.self) private var store
    @State private var reading: JamPostRoute?

    var body: some View {
        let items = store.jamActivity()
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items, id: \.comment.commentId) { item in
                let who = store.teacher(item.comment.author)
                Button { reading = JamPostRoute(postID: item.post.postId) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        AvatarView(person: who, size: 36).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(who.name) commented on \(item.post.title.isEmpty ? "your post" : "\u{201C}\(item.post.title)\u{201D}")").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                            Text(item.comment.text).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(2).multilineTextAlignment(.leading)
                            Text(JamDates.text(item.comment.created)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("jam-activity-\(item.comment.commentId)")
                Divider().overlay(Theme.hairline)
            }
        }
        .accessibilityIdentifier("profile-activity-list")
        .sheet(item: $reading) { route in NavigationStack { JamPostView(postID: route.postID).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { reading = nil } } } } }
    }
}
