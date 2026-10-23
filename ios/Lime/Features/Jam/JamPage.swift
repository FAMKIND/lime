import SwiftUI

/// Where a jam post or the subscribers list is pushed on the jam tab.
struct JamPostRoute: Hashable { let postID: String }
struct JamSubscribersRoute: Hashable { let jamID: String }

/// The jam tab (LIME-188b): one feed of the posts of the teachers you follow and your own, newest first, as cards; a **+** (the same floating button
/// as link and call) writes a new one. There is nothing to set up: your jam is made on your first post, and your profile is its page. Quiet by
/// design: no rankings, no streaks, no nudges (`docs/jam.md` section 0).
struct JamPage: View {
    @Environment(ConversationStore.self) private var store
    @State private var composing = false
    /// Saving or un-saving a post redraws the Saved segment.
    @AppStorage(JamSaved.key) private var savedList: String = ""

    var body: some View {
        @Bindable var store = store
        return NavigationStack(path: $store.jamPath) {
            feed
                .background(Theme.canvas.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                // The same header as link and call: the feed scrolls under it (LIME-188v).
                .rootHeader(searchID: "jam-search-button", overlays: true) { store.jamSearching = true }
                .overlay { FloatingPlus(label: "New post", id: "new-jam-post") { composing = true } }
                .navigationDestination(for: ProfileRoute.self) { ProfileView(route: $0) }
                .navigationDestination(for: SharedListRoute.self) { SharedListView(route: $0) }
                .navigationDestination(for: JamPostRoute.self) { JamPostView(postID: $0.postID) }
                .navigationDestination(for: JamSubscribersRoute.self) { JamSubscribersView(jamID: $0.jamID) }
                .navigationDestination(isPresented: Binding(get: { store.jamSearching }, set: { store.jamSearching = $0 })) {
                    Text("Nothing to search in jam yet.")
                        .font(Theme.body).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.canvas)
                        .accessibilityIdentifier("jam-search-empty")
                }
                .fullScreenCover(isPresented: $composing) { JamComposeSheet() }
                .onAppear { store.refreshJams() }
        }
    }

    /// Someone asks to credit me on their post: a calm prompt at the top of the feed.
    private var requests: some View {
        VStack(spacing: 8) {
            ForEach(store.jamRequests, id: \.postId) { request in
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(store.teacherName(request.writer)) added you as co-author of \u{201C}\(request.title)\u{201D}").font(Theme.body).foregroundStyle(Theme.text)
                        .accessibilityIdentifier("jam-request-\(request.postId)")
                    HStack(spacing: 10) {
                        Button { Task { await store.answerCoauthorRequest(request, accept: true) } } label: {
                            Text("Accept").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.accentInk).padding(.horizontal, 18).frame(minHeight: 44).background(Theme.accent, in: Capsule())
                        }
                        .accessibilityIdentifier("jam-request-accept-\(request.postId)")
                        Button { Task { await store.answerCoauthorRequest(request, accept: false) } } label: {
                            Text("Decline").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text).padding(.horizontal, 18).frame(minHeight: 44).background(Theme.surface, in: Capsule())
                        }
                        .accessibilityIdentifier("jam-request-decline-\(request.postId)")
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.horizontal, 16).padding(.top, store.jamRequests.isEmpty ? 0 : 8)
    }

    private var feed: some View {
        _ = store.jamHiddenChanged   // hiding a post redraws the feed
        _ = savedList
        let posts = store.jamFeed
        if #available(iOS 26, *) {
            return feedBody(posts, topMargin: 8)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            // As Messages and Calls: room for the controls drawn over the list.
            return feedBody(posts, topMargin: 76)
        }
    }

    /// The posts of the chosen segment that pass the filters (Saved is one of them).
    private func shown(_ posts: [JamPostInfo]) -> [JamPostInfo] {
        posts.filter { store.jamPostMatches($0, segment: store.jamSegment, filter: store.jamFilter) }
    }

    /// Everything is one scroll view, so the requests and the filter row scroll away with the posts and go under the header.
    private func feedBody(_ posts: [JamPostInfo], topMargin: CGFloat) -> some View {
        @Bindable var store = store
        let list = shown(posts)
        let nothingYet = posts.isEmpty
        return ScrollView {
            LazyVStack(spacing: 0) {
                requests
                if nothingYet {
                    Text("Subscribe to teachers from their profiles. Your posts show here too.")
                        .font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                        .padding(.horizontal, 40).padding(.top, 120)
                        .accessibilityIdentifier("jam-feed-empty")
                } else {
                    JamFilterRow(segment: $store.jamSegment, filter: $store.jamFilter).padding(.top, 4)
                    if list.isEmpty {
                        if store.jamSegment == .all && store.jamFilter == JamFilter(saved: true) {
                            Text("Nothing saved yet.").font(Theme.body).foregroundStyle(Theme.textSecondary).padding(.top, 60)
                                .accessibilityIdentifier("jam-saved-empty")
                        } else {
                            FilteredEmpty(text: store.jamSegment == .articles ? "No articles match" : store.jamSegment == .podcasts ? "No podcasts match" : "No posts match") { store.jamFilter = JamFilter(); store.jamSegment = .all }
                        }
                    }
                    ForEach(list, id: \.postId) { post in
                        JamPostCard(post: post)
                        Divider().overlay(Theme.hairline)
                    }
                }
            }
            .padding(.top, topMargin)
            .padding(.bottom, FloatingPlus.size + 32)
        }
        .accessibilityIdentifier("jam-feed")
    }
}

/// One post in a feed or on a profile: who and when, then the post by its kind, then the actions (♥, comment, remix, share: they come with
/// LIME-189, so they are shown dimmed and do nothing yet).
struct JamPostCard: View {
    let post: JamPostInfo
    /// On a profile the writer is already known: no avatar row.
    var showsWriter = true
    /// Where tapping the post goes; the jam tab pushes the reader, a profile presents it.
    var open: ((String) -> Void)? = nil
    @Environment(ConversationStore.self) private var store
    /// A long quick post is cut at 8 lines; "more" opens it here.
    @State private var expanded = false
    @State private var cut = false

    var body: some View {
        let writer = store.teacher(post.author)
        VStack(alignment: .leading, spacing: 10) {
            if showsWriter {
                let asJam = post.displayAs == "jam"
                Button { store.openProfile(ProfileRoute(userID: writer.id, name: writer.name, isMe: writer.id == store.meProvider().id)) } label: {
                    HStack(spacing: 10) {
                        BylineAvatar(people: store.bylinePeople(post), jam: asJam ? store.jamTitle(post.jamId) : nil, size: 40)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(asJam ? store.jamTitle(post.jamId) : writer.name).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text)
                            Text([asJam ? "by \(writer.name)" : nil, store.byline(post), JamDates.text(post.created)].compactMap { $0 }.joined(separator: " \u{00B7} ")).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                                .accessibilityIdentifier("jam-card-byline-\(post.postId)")
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(asJam ? store.jamTitle(post.jamId) + ", by " + writer.name : writer.name), \(JamDates.text(post.created))").accessibilityHint("Opens their profile")
                .accessibilityIdentifier("jam-card-writer-\(post.postId)")
            } else {
                Text([store.byline(post), JamDates.text(post.created)].compactMap { $0 }.joined(separator: " \u{00B7} ")).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("jam-card-byline-\(post.postId)")
            }
            if post.kind == "article", post.state == "ready" {
                Button { openPost() } label: { JamArticleCover(post: post).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityLabel([post.title, post.subtitle, String(post.plain.prefix(80))].filter { !$0.isEmpty }.joined(separator: ", ")).accessibilityHint("Opens the article")
                    .accessibilityIdentifier("jam-post-\(post.postId)")
            } else if !isAudioRecord {
            Button { openPost() } label: { content.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens the post")
                .accessibilityIdentifier("jam-post-\(post.postId)")
            }
            if post.kind == "quick", cut, !expanded {
                Button { withAnimation { expanded = true } } label: { Text("more").font(Theme.secondary).foregroundStyle(Theme.textSecondary).frame(minHeight: 44, alignment: .leading) }
                    .buttonStyle(.plain).accessibilityLabel("more").accessibilityHint("Shows the whole post").accessibilityIdentifier("jam-more-\(post.postId)")
            }
            if post.state == "ready", post.kind != "article" { JamAttachmentsView(postID: post.postId, compact: true) }
            actions
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    /// An audio recording's card carries its own title and subtitle (LIME-188u).
    private var isAudioRecord: Bool { post.kind == "record" && post.state == "ready" && store.jamAttachments(post.postId).contains { $0.kind == "audio" } }

    private func openPost() { if let open { open(post.postId) } else { store.jamPath.append(JamPostRoute(postID: post.postId)) } }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch post.state {
            case "fetching":
                Text(post.title.isEmpty ? "Downloading\u{2026}" : post.title).font(Theme.body).foregroundStyle(Theme.textSecondary)
            case "gone":
                Text("No longer available").font(Theme.body).foregroundStyle(Theme.textSecondary)
            default:
                if post.kind == "article" {
                    Text(post.title).font(Theme.font(.title3, weight: .bold)).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                    if !post.subtitle.isEmpty { Text(post.subtitle).font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.leading) }
                    if !post.plain.isEmpty { Text(post.plain).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(3).multilineTextAlignment(.leading) }
                } else {
                    if !post.title.isEmpty { Text(post.title).font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.text).multilineTextAlignment(.leading) }
                    if post.kind == "record", !post.subtitle.isEmpty { Text(post.subtitle).font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.leading) }
                    if !post.plain.isEmpty {
                        Text(post.plain).font(Theme.body).foregroundStyle(Theme.text).lineLimit(post.kind == "quick" && expanded ? nil : 8).multilineTextAlignment(.leading)
                            .background {
                                // Is there more than 8 lines? The same text, uncut and unseen, is measured against the shown one.
                                GeometryReader { shown in
                                    Text(post.plain).font(Theme.body).fixedSize(horizontal: false, vertical: true).frame(width: shown.size.width).hidden()
                                        .background(GeometryReader { full in Color.clear.onAppear { cut = full.size.height > shown.size.height + 1 }.onChange(of: shown.size.height) { _, h in cut = full.size.height > h + 1 } })
                                }
                            }
                    }
                }
            }
        }
    }

    private var actions: some View {
        // Four equal columns across the card (LIME-188y).
        HStack(spacing: 0) {
            ForEach([("heart", "like"), ("bubble.left", "comment"), ("arrow.2.squarepath", "remix"), ("square.and.arrow.up", "share")], id: \.1) { icon, label in
                Image(systemName: icon).font(.system(size: 18)).frame(maxWidth: .infinity, minHeight: 28)
                    .accessibilityLabel(label).accessibilityAddTraits(.isButton).accessibilityHint("Coming soon")
                    .accessibilityIdentifier("jam-action-\(label)-\(post.postId)")
            }
        }
        .foregroundStyle(Theme.textSecondary.opacity(0.5))
        .allowsHitTesting(false)
    }
}

enum JamDates {
    static func text(_ millis: Int64) -> String {
        Date(timeIntervalSince1970: Double(millis) / 1000).formatted(date: .abbreviated, time: .shortened)
    }
}

extension JamInfo: Identifiable { public var id: String { jamId } }
