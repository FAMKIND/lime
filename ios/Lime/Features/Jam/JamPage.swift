import SwiftUI

/// Where a jam post or the subscribers list is pushed on the jam tab.
struct JamPostRoute: Hashable { let postID: String }
struct JamSubscribersRoute: Hashable { let jamID: String }

/// The jam tab (LIME-188): the posts of the teachers you follow, and your own jam. Quiet by design: no counts shown to anyone but the writer, no
/// streaks, no nudges (`docs/jam.md` section 0).
struct JamPage: View {
    @Environment(ConversationStore.self) private var store
    @State private var part: Part = .following
    @State private var starting = false
    @State private var editing: JamInfo?
    @State private var writing: JamInfo?
    @State private var confirmingEnd = false

    enum Part: String, CaseIterable, Identifiable {
        case following = "Following", mine = "Your jam"
        var id: String { rawValue }
    }

    var body: some View {
        @Bindable var store = store
        return NavigationStack(path: $store.jamPath) {
            VStack(spacing: 0) {
                Picker("jam", selection: $part) {
                    ForEach(Part.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 10)
                .accessibilityIdentifier("jam-parts")
                switch part {
                case .following: following
                case .mine: mine
                }
            }
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .rootHeader(searchID: "jam-search-button") { store.jamSearching = true }
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
            .sheet(isPresented: $starting) { JamDetailsSheet(editing: nil) }
            .sheet(item: $editing) { JamDetailsSheet(editing: $0) }
            .fullScreenCover(item: $writing) { JamPostEditor(jam: $0) }
            .onAppear { store.refreshJams() }
        }
    }

    // MARK: Following

    private var following: some View {
        let posts = store.followingPosts
        return Group {
            if posts.isEmpty {
                VStack {
                    Spacer()
                    Text("Subscribe to a teacher\u{2019}s jam from their profile.")
                        .font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .accessibilityIdentifier("jam-following-empty")
                    Spacer()
                }
                .padding(.bottom, 60)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(posts, id: \.postId) { post in
                            Button { store.jamPath.append(JamPostRoute(postID: post.postId)) } label: { postRow(post, showWriter: true) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("jam-post-\(post.postId)")
                            Divider().overlay(Theme.hairline).padding(.leading, 72)
                        }
                    }
                    .padding(.bottom, 20)
                }
                .accessibilityIdentifier("jam-following-list")
            }
        }
    }

    private func postRow(_ post: JamPostInfo, showWriter: Bool) -> some View {
        let writer = store.teacher(post.author)
        let excerpt = post.state == "fetching" ? "Downloading\u{2026}" : post.state == "gone" ? "No longer available" : post.plain
        return HStack(alignment: .top, spacing: 12) {
            AvatarView(person: writer, size: 44).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if showWriter { Text(writer.name).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(1) }
                Text(post.title).font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(2).multilineTextAlignment(.leading)
                Text(excerpt).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(2).multilineTextAlignment(.leading)
                Text(JamDates.text(post.created)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the post")
    }

    // MARK: Your jam

    @ViewBuilder
    private var mine: some View {
        if let jam = store.jamsMine.first {
            let posts = (store.jamPosts[jam.jamId] ?? []).sorted { $0.created > $1.created }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            Text(jam.title).font(Theme.font(.title3, weight: .bold)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader).accessibilityIdentifier("jam-mine-title")
                            Spacer()
                            Menu {
                                Button("Edit") { editing = jam }.accessibilityIdentifier("jam-edit")
                                Button("End jam", role: .destructive) { confirmingEnd = true }.accessibilityIdentifier("jam-end")
                            } label: {
                                Image(systemName: "ellipsis.circle").font(.system(size: 22)).foregroundStyle(Theme.text).frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("More").accessibilityIdentifier("jam-menu")
                        }
                        if !jam.about.isEmpty { Text(jam.about).font(Theme.body).foregroundStyle(Theme.textSecondary) }
                        if !jam.topics.isEmpty {
                            Text(jam.topics.joined(separator: " \u{00B7} ")).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Button { writing = jam } label: {
                        Text("New post").font(Theme.title).foregroundStyle(Theme.accentInk)
                            .frame(maxWidth: .infinity, minHeight: 52).background(Theme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("jam-new-post")
                    // Only the writer sees this.
                    Button { store.jamPath.append(JamSubscribersRoute(jamID: jam.jamId)) } label: {
                        HStack {
                            Text("Subscribers: \(jam.subscriberCount)").font(Theme.body).foregroundStyle(Theme.text)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 16).frame(minHeight: 50)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("jam-subscribers")
                    if let progress = store.jamProgress[jam.jamId] {
                        Text("Sending to \(progress.total - progress.pending) of \(progress.total)").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                            .accessibilityIdentifier("jam-progress")
                    }
                    ForEach(posts, id: \.postId) { post in
                        Button { store.jamPath.append(JamPostRoute(postID: post.postId)) } label: { postRow(post, showWriter: false).padding(.horizontal, -20) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("jam-post-\(post.postId)")
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 30)
            }
            .confirmSheet("End this jam?", isPresented: $confirmingEnd) {
                Button("End jam", role: .destructive) { Task { await store.endJam(jam.jamId) } }.accessibilityIdentifier("jam-end-confirm")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Subscribers keep what they have.")
            }
        } else {
            VStack(spacing: 14) {
                Spacer()
                Text("Share lessons and ideas with the teachers who subscribe. Only they can read your posts.")
                    .font(Theme.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                    .accessibilityIdentifier("jam-mine-empty")
                Button { starting = true } label: {
                    Text("Start your jam").font(Theme.title).foregroundStyle(Theme.accentInk)
                        .frame(maxWidth: .infinity, minHeight: 52).background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain).accessibilityIdentifier("jam-start")
                Spacer()
            }
            .padding(.horizontal, 32).padding(.bottom, 60)
        }
    }
}

enum JamDates {
    static func text(_ millis: Int64) -> String {
        Date(timeIntervalSince1970: Double(millis) / 1000).formatted(date: .abbreviated, time: .omitted)
    }
}

extension JamInfo: Identifiable { public var id: String { jamId } }
