import AVFoundation
import SwiftUI
import UIKit

// MARK: Reading preferences (LIME-188p)

/// The article fonts on offer: lime's own bundled faces (all open licences), written in their own face in the picker.
enum ReaderFont: String, CaseIterable, Identifiable {
    case newYork, newsreader, lora, sfPro, figtree, lexend, atkinson, comicNeue
    var id: String { rawValue }

    var title: String {
        switch self {
        case .newYork: "New York"
        case .newsreader: "Newsreader"
        case .lora: "Lora"
        case .sfPro: "SF Pro"
        case .figtree: "Figtree"
        case .lexend: "Lexend"
        case .atkinson: "Atkinson Hyperlegible"
        case .comicNeue: "Comic Neue"
        }
    }

    /// For VoiceOver: why one might choose it.
    var hint: String {
        switch self {
        case .lexend: "Designed to be easier to read for people with dyslexia"
        case .atkinson: "Designed for readers with low vision"
        case .comicNeue: "A friendly, rounded face that some readers with dyslexia find easier"
        case .newYork: "The default serif"
        default: ""
        }
    }

    private var typeface: LimeTypeface? {
        switch self {
        case .newsreader: .newsreader
        case .lora: .lora
        case .figtree: .figtree
        case .lexend: .lexend
        case .atkinson: .atkinson
        case .comicNeue: .comicNeue
        case .newYork, .sfPro: nil
        }
    }

    /// The face at a size that already follows the person's Dynamic Type (`size` is the size at the default setting).
    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let scaled = UIFontMetrics(forTextStyle: .body).scaledValue(for: size)
        if let typeface, let name = typeface.postScriptName(for: weight) { return Font.custom(name, fixedSize: scaled) }
        return Font.system(size: scaled, weight: weight, design: self == .newYork ? .serif : .default)
    }
}

/// Font, text size and line spacing for reading, remembered on this phone (Options → Display settings). The size is a step on top of Dynamic Type.
enum ReaderPrefs {
    static let fontKey = "lime.reader.font", sizeKey = "lime.reader.sizeStep", lineKey = "lime.reader.lineStep"
    static let basePoints: CGFloat = 18
    static let pointsPerStep: CGFloat = 2

    /// The size at the default Dynamic Type setting: one step is two points either way (never below 90% of the system's own body size).
    static func points(forStep step: Int) -> CGFloat {
        let clamped = min(max(step, -1), 1)
        return max(basePoints + CGFloat(clamped) * pointsPerStep, 17 * 0.9)
    }

    /// The line height as a multiple of the size: Compact, Default, Relaxed.
    static func lineMultiple(forStep step: Int) -> CGFloat { [1.3, 1.5, 1.7][min(max(step, -1), 1) + 1] }

    /// The extra space between lines SwiftUI wants (the line already has about 1.2 of the size).
    static func lineSpacing(size: CGFloat, step: Int) -> CGFloat { max(size * (lineMultiple(forStep: step) - 1.2), 0) }

    static func label(forSizeStep step: Int) -> String {
        switch min(max(step, -1), 1) {
        case -1: "\(Int(pointsPerStep)) pt smaller"
        case 1: "\(Int(pointsPerStep)) pt bigger"
        default: "Default"
        }
    }
}

extension EnvironmentValues {
    /// A jam post's text face and line spacing when it is read as an article (nil: the app's body font).
    @Entry var postBodyFont: Font? = nil
    @Entry var postLineSpacing: CGFloat = 0
}

// MARK: Saved on this phone

/// Posts saved to read later: only on this phone, never sent anywhere.
enum JamSaved {
    static let key = "lime.jam.savedPosts"
    static var ids: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
    static func contains(_ id: String) -> Bool { ids.contains(id) }
    static func toggle(_ id: String) {
        var now = ids
        if let at = now.firstIndex(of: id) { now.remove(at: at) } else { now.insert(id, at: 0) }
        UserDefaults.standard.set(now, forKey: key)
    }
}

// MARK: The card

/// An article in a feed or on a profile (LIME-188p): a cover card (the first photo, or your picture on a soft tint) with the title over a dark
/// gradient and a Save bookmark; the action row under it. Tapping opens the reading page.
struct JamArticleCover: View {
    let post: JamPostInfo
    @Environment(ConversationStore.self) private var store
    @State private var image: UIImage?
    @State private var saved = false
    @AppStorage(JamSaved.key) private var savedList: String = ""
    /// Opening a post marks it read: the dot goes.
    @AppStorage(JamRead.key) private var readList: String = ""

    var body: some View {
        let writer = store.teacher(post.author)
        ZStack(alignment: .bottomLeading) {
            CoverArt(image: image, person: writer, org: store.orgName(post))
            if JamRead.isUnread(post, me: store.meProvider().id) {
                VStack { HStack { Circle().fill(.white).frame(width: 12, height: 12).overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 1)).padding(14).accessibilityElement().accessibilityLabel("Unread").accessibilityIdentifier("jam-unread-\(post.postId)"); Spacer() }; Spacer() }
            }
            // A stronger scrim from the bottom (LIME-215) so the title and subtitle keep their contrast on a white sky.
            LinearGradient(stops: [.init(color: .clear, location: 0.15), .init(color: .black.opacity(0.62), location: 0.5), .init(color: .black.opacity(0.9), location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(post.title).font(Theme.font(.title3, weight: .bold)).foregroundStyle(.white).lineLimit(3).multilineTextAlignment(.leading)
                    .accessibilityIdentifier("jam-article-card-title")
                if !post.subtitle.isEmpty {
                    Text(post.subtitle).font(Theme.font(.subheadline)).foregroundStyle(.white.opacity(0.95)).lineLimit(2).multilineTextAlignment(.leading)
                        .accessibilityIdentifier("jam-article-card-subtitle")
                }
            }
            .padding(.leading, 16).padding(.trailing, 64).padding(.bottom, 16)
            HStack {
                Spacer()
                VStack {
                    Spacer()
                    Button { JamSaved.toggle(post.postId); saved = JamSaved.contains(post.postId) } label: {
                        Image(systemName: saved ? "bookmark.fill" : "bookmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).frame(width: 40, height: 40).background(.black.opacity(0.45), in: Circle()).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(saved ? "Saved" : "Save").accessibilityHint("Saves it on this phone to read later").accessibilityIdentifier("jam-article-save-\(post.postId)")
                    .padding(.trailing, 6).padding(.bottom, 6)
                }
            }
        }
        // Taller since the subtitle joined the title (LIME-215b): two thirds of a portrait (4:5) photo's height at the same width, about width x 0.83.
        .frame(width: JamMedia.size(ratio: JamMedia.coverRatio, column: JamMedia.column, screenHeight: UIScreen.main.bounds.height).width,
               height: JamMedia.size(ratio: JamMedia.coverRatio, column: JamMedia.column, screenHeight: UIScreen.main.bounds.height).height)
        .jamMediaClip()
        .accessibilityElement(children: .contain)
        .task {
            saved = JamSaved.contains(post.postId)
            let files = store.jamAttachments(post.postId)
            if let first = files.first(where: { $0.kind == "image" && !JamCover.isCover($0) }), let data = await store.jamAttachmentData(post.postId, first.attachmentId) { image = UIImage(data: data) }
        }
    }
}

// MARK: Reading

/// Splits a post's text into its blocks (blank-line separated, but never inside a code fence), so each can be found and scrolled to.
enum ArticleSegments {
    static func split(_ markdown: String) -> [String] {
        var parts: [String] = []
        var current: [String] = []
        var fenced = false
        for line in markdown.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { fenced.toggle() }
            if line.trimmingCharacters(in: .whitespaces).isEmpty, !fenced {
                if !current.isEmpty { parts.append(current.joined(separator: "\n")); current = [] }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { parts.append(current.joined(separator: "\n")) }
        return parts
    }

    /// How many times `query` occurs (any case, any accents) in `text`.
    static func occurrences(of query: String, in text: String) -> Int {
        guard !query.isEmpty else { return 0 }
        var count = 0
        var range = text.startIndex..<text.endIndex
        while let found = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: range) {
            count += 1
            range = found.upperBound..<text.endIndex
        }
        return count
    }
}

/// The reading page of an article (LIME-188p).
struct JamArticlePage: View {
    let postID: String
    /// Open scrolled to the comments (LIME-189d).
    var toComments = false
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(ReaderPrefs.fontKey) private var fontRaw = ReaderFont.newYork.rawValue
    @AppStorage(ReaderPrefs.sizeKey) private var sizeStep = 0
    @AppStorage(ReaderPrefs.lineKey) private var lineStep = 0
    @AppStorage(JamSaved.key) private var savedList = ""
    @State private var offset: CGFloat = 0
    @State private var lastOffset: CGFloat = 0
    @State private var barHidden = false
    /// Where the head (title, byline) ends in the scroll view: the title pill comes in once it is above the bar.
    @State private var headEnd: CGFloat = 1000
    @State private var options = false
    @State private var display = false
    @State private var sharing = false
    @State private var finding = false
    @State private var query = ""
    @State private var matchIndex = 0
    @State private var scrollTarget: String?
    /// The comment field has the keyboard: the action pill steps aside.
    @State private var typing = false
    @State private var editingPost: JamPostInfo?

    private var font: ReaderFont { ReaderFont(rawValue: fontRaw) ?? .newYork }

    var body: some View {
        let post = store.jamPost(postID)
        ZStack(alignment: .top) {
            Theme.canvas.ignoresSafeArea().accessibilityIdentifier("jam-article-page")
            if let post {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            GeometryReader { geo in Color.clear.preference(key: ArticleOffsetKey.self, value: -geo.frame(in: .named("jam-article-scroll")).minY) }.frame(height: 0)
                            content(post)
                        }
                        .frame(maxWidth: 680).frame(maxWidth: .infinity)
                    }
                    .coordinateSpace(name: "jam-article-scroll")
                    .onPreferenceChange(ArticleOffsetKey.self) { track($0, false) }
                    .onPreferenceChange(ArticleHeadEndKey.self) { headEnd = $0 }
                    .modifier(ArticleScrollTracking(track: track))
                    .onChange(of: scrollTarget) { _, id in if let id { withAnimation { proxy.scrollTo(id, anchor: id == "comments" ? .top : .center) } } }
                    .task { if toComments { try? await Task.sleep(for: .milliseconds(500)); scrollTarget = "comments" } }
                }
                .padding(.top, 0)
                topBar(post)
                if finding { findBar(post).padding(.top, 62) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // The actions slide down with the bar as you read, and come back as you scroll up (LIME-188z); they stay in the accessibility tree.
            if let post {
                JamActionPill(share: { sharing = true }, postID: post.postId, comment: { scrollTarget = "comments" }).padding(.horizontal, 48).padding(.bottom, 6).accessibilityIdentifier("jam-article-pill-\(post.postId)")
                    .offset(y: (barHidden || typing) && !reduceMotion ? 120 : 0)
                    .opacity(barHidden || typing ? 0 : 1)
                    .allowsHitTesting(!(barHidden || typing))
                    .animation(reduceMotion ? .linear(duration: 0.15) : .easeOut(duration: 0.2), value: barHidden)
            }
        }
        // ...and the dock goes with them.
        .toolbar(barHidden ? .hidden : .automatic, for: .tabBar)
        .animation(.easeOut(duration: 0.2), value: barHidden)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { store.refreshJams() }
        .sheet(isPresented: $options) { if let post { ReaderOptionsSheet(post: post, openDisplay: { options = false; display = true }, find: { options = false; finding = true }, hide: { store.hideJamPost(post.postId); dismiss() }, edit: { editingPost = post }, deleted: { dismiss() }) } }
        .fullScreenCover(item: $editingPost) { JamComposeSheet(editing: $0) }
        .sheet(isPresented: $display) { ReaderDisplaySheet() }
        .sheet(isPresented: $sharing) { if let post { JamShareSheet(post: post) } }
        .linkOpening()
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ post: JamPostInfo) -> some View {
        let writer = store.teacher(post.author)
        let size = ReaderPrefs.points(forStep: sizeStep)
        let segments = ArticleSegments.split(post.markdown)
        let minutes = max(1, Int((Double(post.plain.split { $0.isWhitespace }.count) / 220).rounded(.up)))
        VStack(alignment: .leading, spacing: 14) {
            Color.clear.frame(height: 64)
            Text(store.jamTitle(post.jamId).uppercased()).font(Theme.font(.caption, weight: .semibold)).tracking(1).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("jam-article-jam")
            Text(post.title).font(font.font(size: size + 12, weight: .bold)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader).accessibilityIdentifier("jam-reader-title")
            if !post.subtitle.isEmpty { Text(post.subtitle).font(font.font(size: size + 2)).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("jam-reader-subtitle") }
            Button { store.openProfile(ProfileRoute(userID: writer.id, name: writer.name, isMe: writer.id == store.meProvider().id)) } label: {
                HStack(spacing: 10) {
                    BylineAvatar(people: store.bylinePeople(post), jam: post.displayAs == "jam" ? store.jamTitle(post.jamId) : nil, size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(post.displayAs == "jam" ? store.jamTitle(post.jamId) : writer.name).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text)
                        Text([post.displayAs == "jam" ? "by \(writer.name)" : nil, store.byline(post), JamDates.text(post.created), "\(minutes) min read", post.editedAt > 0 ? "Edited \(JamDates.text(post.editedAt))" : nil].compactMap { $0 }.joined(separator: " \u{00B7} ")).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                            .accessibilityIdentifier("jam-reader-byline")
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(post.title), by \(post.displayAs == "jam" ? store.authorName(post) + ", by " + writer.name : writer.name), \(JamDates.text(post.created)), \(minutes) minute read").accessibilityHint("Opens their profile")
            GeometryReader { geo in Color.clear.preference(key: ArticleHeadEndKey.self, value: geo.frame(in: .named("jam-article-scroll")).minY) }.frame(height: 0)
                .modifier(HeadEndReporter(report: { headEnd = $0 }))
            Rectangle().fill(Theme.hairline).frame(height: 1).accessibilityHidden(true)
            switch post.state {
            case "fetching": Text("Downloading\u{2026}").font(Theme.body).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("jam-reader-fetching")
            case "gone": Text("This post is no longer available.").font(Theme.body).foregroundStyle(Theme.textSecondary)
            default:
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        FormattedMessageText(markdown: segment, ink: Theme.text, link: Theme.linkOther,
                                             find: findStyle(),
                                             postImage: { caption, i in AnyView(JamInlineAttachment(postID: post.postId, index: i, caption: caption)) })
                            .id("segment-\(index)")
                    }
                }
                .environment(\.postContext, PostContext(post: post))
                .environment(\.postBodyFont, font.font(size: size))
                .environment(\.postLineSpacing, ReaderPrefs.lineSpacing(size: size, step: lineStep))
                .accessibilityIdentifier("jam-reader-body-\(font.rawValue)")
                JamAttachmentsView(postID: post.postId, skipping: JamInline.placed(in: post.markdown))
                endOfArticle(post)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 24)
    }

    private func findStyle() -> FindStyle? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return finding && !trimmed.isEmpty ? FindStyle(words: [trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)], current: true) : nil
    }

    /// Share, then the jam's card with a Subscribe button.
    private func endOfArticle(_ post: JamPostInfo) -> some View {
        let jam = (store.jamsMine + store.jamSubscriptions).first { $0.jamId == post.jamId }
        let writer = store.teacher(post.author)
        let following = store.isFollowing(post.jamId)
        return VStack(alignment: .leading, spacing: 16) {
            Button { sharing = true } label: {
                Label("Share", systemImage: "square.and.arrow.up").font(Theme.title).foregroundStyle(Theme.text).frame(maxWidth: .infinity, minHeight: 50).background(Theme.surface, in: Capsule())
            }
            .accessibilityIdentifier("jam-article-share")
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    AvatarView(person: writer, size: 48).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(store.jamTitle(post.jamId)).font(Theme.font(.headline, weight: .semibold)).foregroundStyle(Theme.text)
                        Text("by \(writer.name)").font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                    }
                }
                if let about = jam?.about, !about.isEmpty { Text(about).font(Theme.body).foregroundStyle(Theme.text) }
                if post.author != store.meProvider().id {
                    Button { Task { if following { await store.unsubscribe(post.jamId) } else if let page = await store.jamPage(of: post.author) { await store.subscribe(to: page) } } } label: {
                        Text(following ? "Subscribed \u{2713}" : "Subscribe").font(Theme.title).foregroundStyle(following ? Theme.text : Theme.accentInk)
                            .frame(maxWidth: .infinity, minHeight: 50).background(following ? Theme.surface : Theme.accent, in: Capsule())
                    }
                    .accessibilityIdentifier("jam-article-end-subscribe")
                }
                // (The likes row, "12 likes · 6 remixes" with faces, is LIME-189's: nothing is drawn here yet.)
            }
            .padding(16).background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityElement(children: .contain).accessibilityIdentifier("jam-article-jam-card")
            // Likes, comments and the place to write one (LIME-189c).
            JamEngagementSection(post: post, typing: $typing).id("comments")
        }
        .padding(.top, 24)
    }

    // MARK: The top bar

    /// ‹ · the title pill (once the head has scrolled away) · Subscribe · ⋯. Glass; it slides away as you read down and returns as you scroll up.
    private func topBar(_ post: JamPostInfo) -> some View {
        let showsPill = headEnd < 56
        return HStack(spacing: 10) {
            circle("chevron.left", label: "Back", id: "jam-article-back") { dismiss() }
            if showsPill { titlePill(post).transition(.opacity) } else { Spacer() }
            if !store.isFollowing(post.jamId), post.author != store.meProvider().id {
                Button { Task { if let page = await store.jamPage(of: post.author) { await store.subscribe(to: page) } } } label: {
                    Text("Subscribe").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.accentInk).padding(.horizontal, 16).frame(minHeight: 44).background(Theme.accent, in: Capsule())
                }
                .accessibilityIdentifier("jam-article-subscribe")
            }
            circle("ellipsis", label: "More", id: "jam-article-more") { options = true }
        }
        .padding(.horizontal, 16).padding(.top, 6)
        .offset(y: barHidden && !reduceMotion ? -90 : 0)
        .opacity(barHidden ? 0 : 1)
        .animation(reduceMotion ? .linear(duration: 0.15) : .easeOut(duration: 0.2), value: barHidden)
        .animation(.easeOut(duration: 0.2), value: showsPill)
    }

    /// The glass pill like the chat header's: the byline's picture, the title, and who it is by. One button to the profile; with several people
    /// (a jam and co-authors) a small menu of them.
    private func titlePill(_ post: JamPostInfo) -> some View {
        let people = store.bylinePeople(post)
        let asJam = post.displayAs == "jam"
        let words = store.bylineText(post)
        // Where each name goes: the jam is its writer's page.
        var entries: [(label: String, person: Person)] = asJam ? [(store.jamTitle(post.jamId), people[0])] : [(people[0].name, people[0])]
        entries += people.dropFirst().map { ($0.name, $0) }
        let label = HStack(spacing: 8) {
            BylineAvatar(people: people, jam: asJam ? store.jamTitle(post.jamId) : nil, size: 32)
            VStack(alignment: .leading, spacing: 0) {
                if asJam {
                    // Posted as an org: its name first, like a group's header, then the article's title (LIME-188z).
                    Text(store.jamTitle(post.jamId)).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(post.title).font(Theme.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                } else {
                    Text(post.title).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(words).font(Theme.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 6).padding(.trailing, 14).frame(minHeight: 44).frame(maxWidth: .infinity, alignment: .leading)
        .limeGlass(in: Capsule())
        .contentShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(post.title), by \(words)")
        return Group {
            if entries.count > 1 {
                Menu {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        Button(entry.label) { open(entry.person) }
                    }
                } label: { label }
                .accessibilityHint("Choose a profile")
            } else {
                Button { open(entries[0].person) } label: { label }.buttonStyle(.plain)
                    .accessibilityHint("Opens profile")
            }
        }
        .accessibilityIdentifier("jam-article-pill")
    }

    private func open(_ person: Person) { store.openProfile(ProfileRoute(userID: person.id, name: person.name, isMe: person.id == store.meProvider().id)) }

    private func circle(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).frame(width: 44, height: 44).limeGlass(in: Circle())
        }
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }

    /// Down hides the bar, up brings it back (only visually: it stays in the accessibility tree).
    private func track(_ now: CGFloat, _ atEnd: Bool) {
        offset = now
        let delta = now - lastOffset
        if atEnd { barHidden = false; lastOffset = now }   // at the end of the article everything shows
        else if now > 80, delta > 8 { barHidden = true; lastOffset = now }
        else if delta < -8 || now <= 80 { barHidden = false; lastOffset = now }
        else if abs(delta) > 30 { lastOffset = now }
    }

    // MARK: Find in the post

    private func findBar(_ post: JamPostInfo) -> some View {
        let segments = ArticleSegments.split(post.markdown)
        let counts = segments.map { ArticleSegments.occurrences(of: query.trimmingCharacters(in: .whitespaces), in: postPlainText(text: $0)) }
        let total = counts.reduce(0, +)
        return HStack(spacing: 8) {
            TextField("Search in post", text: $query).textFieldStyle(.plain).padding(.horizontal, 12).frame(minHeight: 44).background(Theme.surface, in: Capsule())
                .onChange(of: query) { _, _ in matchIndex = 0; jump(counts) }
                .accessibilityIdentifier("jam-article-find-field")
            Text(total == 0 ? (query.isEmpty ? "" : "0 of 0") : "\(matchIndex + 1) of \(total)").font(Theme.secondary.monospacedDigit()).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("jam-article-find-count")
                .accessibilityLabel(total == 0 ? "No matches" : "\(matchIndex + 1) of \(total)")
            Button { if total > 0 { matchIndex = (matchIndex - 1 + total) % total; jump(counts) } } label: { Image(systemName: "chevron.up").frame(width: 44, height: 44) }
                .accessibilityLabel("Previous match").accessibilityIdentifier("jam-article-find-prev")
            Button { if total > 0 { matchIndex = (matchIndex + 1) % total; jump(counts) } } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }
                .accessibilityLabel("Next match").accessibilityIdentifier("jam-article-find-next")
            Button { finding = false; query = "" } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .accessibilityLabel("Close search").accessibilityIdentifier("jam-article-find-close")
        }
        .foregroundStyle(Theme.text).padding(.horizontal, 12).padding(.vertical, 4).limeGlass(in: Capsule()).padding(.horizontal, 12)
        .announcesCount(total == 0 ? "No matches" : "\(matchIndex + 1) of \(total)")
    }

    /// Scrolls to the block that holds the current match.
    private func jump(_ counts: [Int]) {
        var remaining = matchIndex
        for (index, count) in counts.enumerated() {
            if remaining < count { scrollTarget = "segment-\(index)"; DispatchQueue.main.async { scrollTarget = nil }; return }
            remaining -= count
        }
    }
}

/// Scroll position from the scroll view itself (iOS 18 and later; the preference below is what older systems use): the bar hides as you read down.
private struct ArticleScrollTracking: ViewModifier {
    let track: (CGFloat, Bool) -> Void
    private struct Snap: Equatable { var y: CGFloat; var atEnd: Bool }
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollGeometryChange(for: Snap.self) { g in
                Snap(y: g.contentOffset.y + g.contentInsets.top, atEnd: g.contentOffset.y + g.containerSize.height >= g.contentSize.height - 40)
            } action: { _, snap in track(snap.y, snap.atEnd) }
        } else { content }
    }
}

/// Where the article's head ends in the scroll view, for the title pill.
private struct HeadEndReporter: ViewModifier {
    let report: (CGFloat) -> Void
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("jam-article-scroll")).minY } action: { report($0) }
        } else { content }
    }
}

private struct ArticleHeadEndKey: PreferenceKey {
    static let defaultValue: CGFloat = 1000
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ArticleOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private extension View {
    /// Says a short status aloud when it changes ("3 of 12").
    func announcesCount(_ text: String) -> some View {
        onChange(of: text) { _, now in UIAccessibility.post(notification: .announcement, argument: now) }
    }
}

// MARK: Display settings

/// Article font, text size and line spacing (Options → Display settings). Applies live behind the sheet.
struct ReaderDisplaySheet: View {
    @AppStorage(ReaderPrefs.fontKey) private var fontRaw = ReaderFont.newYork.rawValue
    @AppStorage(ReaderPrefs.sizeKey) private var sizeStep = 0
    @AppStorage(ReaderPrefs.lineKey) private var lineStep = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Article font").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(ReaderFont.allCases) { face in
                                    Button { fontRaw = face.rawValue } label: {
                                        Text(face.title).font(face.font(size: 17)).foregroundStyle(Theme.text).padding(.horizontal, 16).frame(minHeight: 48)
                                            .background(Theme.surface, in: Capsule())
                                            .overlay(Capsule().strokeBorder(fontRaw == face.rawValue ? Theme.accent : Color.clear, lineWidth: 2))
                                    }
                                    .accessibilityLabel(face.title).accessibilityHint(face.hint).accessibilityAddTraits(fontRaw == face.rawValue ? .isSelected : [])
                                    .accessibilityIdentifier("reader-font-\(face.rawValue)")
                                }
                            }
                        }
                    }
                    stepper("Text size", value: ReaderPrefs.label(forSizeStep: sizeStep), step: $sizeStep, names: ["Smaller", "Default", "Bigger"], id: "reader-size")
                    stepper("Line spacing", value: ["Compact", "Default", "Relaxed"][min(max(lineStep, -1), 1) + 1], step: $lineStep, names: ["Compact", "Default", "Relaxed"], id: "reader-line")
                }
                .padding(20)
            }
            .background(Theme.canvas)
            .navigationTitle("Display settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close") } }
        }
        .presentationDetents([.medium])
    }

    private func stepper(_ title: String, value: String, step: Binding<Int>, names: [String], id: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(value).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 8) {
                ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                    Button { step.wrappedValue = index - 1 } label: {
                        Text(name).font(Theme.secondary).foregroundStyle(Theme.text).frame(maxWidth: .infinity, minHeight: 48).background(Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(step.wrappedValue == index - 1 ? Theme.accent : Color.clear, lineWidth: 2))
                    }
                    .accessibilityAddTraits(step.wrappedValue == index - 1 ? .isSelected : []).accessibilityIdentifier("\(id)-\(index)")
                }
            }
        }
    }
}

// MARK: Options

/// ⋯ on the reading page: what is useful for reading and teaching, all on this phone.
struct ReaderOptionsSheet: View {
    let post: JamPostInfo
    let openDisplay: () -> Void
    let find: () -> Void
    let hide: () -> Void
    /// Edit and Delete are for the writer's own post (LIME-195).
    var edit: () -> Void = {}
    var deleted: () -> Void = {}
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var sharing = false
    @State private var saved = false
    @State private var confirmingDelete = false

    @State private var reportSoon = false

    var body: some View {
        let mine = post.author == store.meProvider().id
        VStack(spacing: 0) {
            // Like Substack's: "Options" in bold with the post's title under it and a round close at the right (LIME-218).
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Options").font(Theme.font(.title3, weight: .bold)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
                    Text(post.title).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(2)
                        .accessibilityIdentifier("options-title")
                }
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                        .frame(width: 44, height: 44).background(Theme.surface, in: Circle())
                }
                .accessibilityLabel("Close").accessibilityIdentifier("options-close")
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    row("magnifyingglass", "Search in post", id: "options-search") { find() }
                    row("textformat.size", "Display settings", chevron: true, id: "options-display") { openDisplay() }
                    row(ArticleSpeaker.shared.active ? "speaker.slash" : "headphones", ArticleSpeaker.shared.active ? "Stop listening" : "Listen", id: "options-listen") { listen() }
                    row("person.crop.circle", post.displayAs == "jam" ? "View org" : "View jam", chevron: true, id: "options-viewjam") {
                        let writer = store.teacher(post.author)
                        dismiss()
                        store.openProfile(ProfileRoute(userID: writer.id, name: writer.name, isMe: writer.id == store.meProvider().id))
                    }
                    row(saved ? "bookmark.fill" : "bookmark", saved ? "Saved \u{2713}" : "Save", id: "options-save") { JamSaved.toggle(post.postId); saved = JamSaved.contains(post.postId) }
                    row("printer", "Print or save as PDF", id: "options-print") { Task { await ArticlePrint.present(post, store: store) } }
                    row("square.and.arrow.up", "Share in lime\u{2026}", id: "options-share") { sharing = true }
                    if !mine {
                        row("paperplane", "Reply privately", id: "options-private") { dismiss(); Task { await store.messageWriter(post.author) } }
                    }
                    Divider().padding(.vertical, 6)
                    if mine {
                        row("pencil", "Edit", id: "options-edit") { dismiss(); Task { try? await Task.sleep(for: .milliseconds(500)); edit() } }   // after the sheet has gone
                    } else {
                        row("eye.slash", "Hide post", id: "options-hide") { dismiss(); hide() }
                    }
                    if mine {
                        row("trash", "Delete post", id: "options-delete", destructive: true) { confirmingDelete = true }
                    } else {
                        row("flag", reportSoon ? "Report \u{00B7} coming soon" : "Report", id: "options-report", destructive: true) { reportSoon = true }
                    }
                    // No "Download" (posts are already on the phone, encrypted), no "Scan for AI text" (it would send the text to a model),
                    // no "Copy link" (there is no public link until LIME-190).
                }
                .padding(.bottom, 12)
            }
        }
        .background(Theme.canvas)
        .sheet(isPresented: $sharing) { JamShareSheet(post: post) }
        .confirmationDialog("Delete this post?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete post", role: .destructive) { Task { _ = await store.deleteJamPost(post.postId); dismiss(); deleted() } }.accessibilityIdentifier("options-delete-confirm")
            Button("Cancel", role: .cancel) {}
        } message: { Text("It goes from your subscribers' phones too.") }
        .onAppear { saved = JamSaved.contains(post.postId) }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ symbol: String, _ title: String, chevron: Bool = false, id: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol).font(.system(size: 20)).frame(width: 28).foregroundStyle(destructive ? Color.red : Theme.text)
                Text(title).font(Theme.body).foregroundStyle(destructive ? Color.red : Theme.text).multilineTextAlignment(.leading)
                Spacer()
                if chevron { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary) }
            }
            .padding(.horizontal, 20).frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(chevron ? "Opens" : "")
        .accessibilityIdentifier(id)
    }

    private func listen() {
        if ArticleSpeaker.shared.active { ArticleSpeaker.shared.stop() } else { ArticleSpeaker.shared.start(title: post.title, text: post.plain) }
        dismiss()
    }
}

// MARK: Listen

/// Reads an article aloud on this phone (`AVSpeechSynthesizer`; nothing leaves it). Play, pause and speed are in the mini player.
@MainActor
@Observable
final class ArticleSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = ArticleSpeaker()
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var active = false
    private(set) var paused = false
    private(set) var title = ""
    private(set) var rate: Float = 1

    static let speeds: [Float] = [1, 1.25, 1.5]

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    func start(title: String, text: String) {
        stop()
        self.title = title
        let utterance = AVSpeechUtterance(string: [title, text].filter { !$0.isEmpty }.joined(separator: ".\n"))
        utterance.rate = min(AVSpeechUtteranceDefaultSpeechRate * rate, AVSpeechUtteranceMaximumSpeechRate)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        active = true
        paused = false
        synthesizer.speak(utterance)
    }

    func toggle() {
        if paused { synthesizer.continueSpeaking(); paused = false } else { synthesizer.pauseSpeaking(at: .word); paused = true }
    }

    func cycleSpeed() {
        rate = Self.speeds[((Self.speeds.firstIndex(of: rate) ?? 0) + 1) % Self.speeds.count]
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        active = false
        paused = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.active = false; self.paused = false }
    }
}

// MARK: Print

/// Print, or save as PDF from the print sheet: the article laid out in the reader's face, with its pictures (classroom handouts).
enum ArticlePrint {
    @MainActor
    static func present(_ post: JamPostInfo, store: ConversationStore) async {
        let face = ReaderFont(rawValue: UserDefaults.standard.string(forKey: ReaderPrefs.fontKey) ?? "") ?? .newYork
        var images: [Int: String] = [:]
        let files = store.jamAttachments(post.postId)
        for (index, file) in files.enumerated() where file.kind == "image" {
            if let data = await store.jamAttachmentData(post.postId, file.attachmentId) { images[index] = data.base64EncodedString() }
        }
        let html = Self.html(post: post, writer: store.authorName(post), face: face, images: images)
        let formatter = UIMarkupTextPrintFormatter(markupText: html)
        formatter.perPageContentInsets = UIEdgeInsets(top: 54, left: 54, bottom: 54, right: 54)
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = post.title.isEmpty ? "jam post" : post.title
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printFormatter = formatter
        controller.present(animated: true)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func spans(_ spans: [Span]) -> String {
        spans.map { span in
            var out = escape(span.text).replacingOccurrences(of: "\n", with: "<br>")
            if span.code { out = "<code>\(out)</code>" }
            if span.bold { out = "<b>\(out)</b>" }
            if span.italic { out = "<i>\(out)</i>" }
            if span.underline { out = "<u>\(out)</u>" }
            if span.strike { out = "<s>\(out)</s>" }
            if let link = span.link { out = "<a href=\"\(escape(link))\">\(out)</a>" }
            return out
        }.joined()
    }

    static func html(post: JamPostInfo, writer: String, face: ReaderFont, images: [Int: String]) -> String {
        let family: String
        switch face {
        case .newYork: family = "'New York', Georgia, serif"
        case .sfPro: family = "-apple-system, Helvetica, sans-serif"
        default: family = "'\(face.title)', Georgia, serif"
        }
        var body = ""
        for block in MessageRender.blocks(post.markdown, post: true) {
            switch block {
            case .paragraph(let s): body += "<p>\(spans(s))</p>"
            case .heading(let level, let s): body += "<h\(min(max(level, 1), 5) + 1)>\(spans(s))</h\(min(max(level, 1), 5) + 1)>"
            case .quote(let s): body += "<blockquote>\(spans(s))</blockquote>"
            case .indent(let s): body += "<p style=\"margin-left:2em\">\(spans(s))</p>"
            case .list(let items): body += "<ul>" + items.map { "<li>\(spans($0.spans))</li>" }.joined() + "</ul>"
            case .code(let text): body += "<pre>\(escape(text))</pre>"
            case .button(let text, let url, _, _): body += "<p><a href=\"\(escape(url))\">\(escape(text))</a> (\(escape(url)))</p>"
            case .divider: body += "<hr>"
            case .freewall: break
            case .image(let caption, let index):
                if let data = images[index] { body += "<figure><img src=\"data:image/jpeg;base64,\(data)\" style=\"max-width:100%\"><figcaption>\(escape(caption))</figcaption></figure>" }
            }
        }
        return "<html><body style=\"font-family:\(family);font-size:13pt;line-height:1.5\"><h1>\(escape(post.title))</h1><p style=\"color:#555\">\(escape(post.subtitle))</p><p style=\"color:#555\">\(escape(writer)) \u{00B7} \(escape(JamDates.text(post.created)))</p><hr>\(body)</body></html>"
    }
}

extension JamPostInfo: Identifiable { public var id: String { postId } }
