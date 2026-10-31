import SwiftUI
import UIKit

enum SeriesFilter: String, CaseIterable, Identifiable {
    case all = "All", unplayed = "Unplayed", played = "Played", saved = "Saved"
    var id: String { rawValue }
}

enum SeriesSort: String, CaseIterable, Identifiable {
    case part = "Part order", newest = "Newest"
    var id: String { rawValue }
}

/// A series (LIME-210f, `docs/jam.md` 13.7; the show page of LIME-260b): the cover washing its colour down behind a play pill, the description and a meta line, then
/// **Parts** (lime's word for episodes) with dates, kinds, a line of description, a thumbnail and a play or read pill; swipe right for Played/Read and Play next, left
/// for Save. Then Hosts, Information and more from the same writer. Built from what this phone has: the posts of jams you follow or write, and open posts from Discover.
struct SeriesPage: View {
    let seriesID: String
    @Environment(ConversationStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @State private var filter: SeriesFilter = .all
    @State private var sort: SeriesSort = .part
    @State private var showAll = false
    @State private var more = false
    @State private var editing = false
    @State private var refresh = 0

    private let firstParts = 10

    var body: some View {
        let _ = refresh
        let info = store.seriesInfo(seriesID)
        let meta = store.seriesMetas[seriesID]
        let all = store.seriesParts(seriesID)
        let shown = visible(all)
        let listed = showAll ? shown : Array(shown.prefix(firstParts))
        let readCount = all.filter(\.read).count
        let title = meta?.title ?? info?.title ?? "Series"
        let jam = store.seriesJam(seriesID)
        let cover = store.seriesCovers[seriesID].flatMap(UIImage.init(data:))
        List {
            hero(title: title, cover: cover, meta: meta, parts: all, info: info, readCount: readCount, jam: jam)
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
            Text("Parts \u{203A}").font(Theme.font(.title3, weight: .bold)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 4, trailing: 20)).listRowBackground(Color.clear).listRowSeparator(.hidden)
            ForEach(listed) { part in
                row(part).listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button { toggleRead(part) } label: { Label(part.kind == "record" ? "Played" : "Read", systemImage: "checkmark.circle") }.tint(.purple).accessibilityIdentifier("series-swipe-played-\(part.id)")
                        if part.kind == "record", part.local { Button { playNext(part) } label: { Label("Play next", systemImage: "text.insert") }.tint(.orange).accessibilityIdentifier("series-swipe-next-\(part.id)") }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if part.local { Button { JamSaved.toggle(part.id); refresh += 1 } label: { Label(JamSaved.contains(part.id) ? "Unsave" : "Save", systemImage: "bookmark") }.tint(.orange).accessibilityIdentifier("series-swipe-save-\(part.id)") }
                    }
            }
            if all.isEmpty { Text("No parts here yet.").font(Theme.body).foregroundStyle(Theme.textSecondary).padding(20).listRowBackground(Color.clear).listRowSeparator(.hidden) }
            else if shown.isEmpty { Text("Nothing here.").font(Theme.body).foregroundStyle(Theme.textSecondary).padding(20).listRowBackground(Color.clear).listRowSeparator(.hidden).accessibilityIdentifier("series-empty") }
            if !showAll && shown.count > firstParts {
                Button { showAll = true } label: { Text("See all (\(shown.count))").font(Theme.font(.body, weight: .semibold)).foregroundStyle(Theme.accentInk).frame(maxWidth: .infinity, minHeight: 48) }
                    .buttonStyle(.plain).background(Theme.accent, in: Capsule()).padding(.horizontal, 20).accessibilityIdentifier("series-see-all")
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            hosts(all).listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
            information(all, jam: jam).listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
            moreFrom(jam: jam).listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
            Color.clear.frame(height: 40).listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
        .listStyle(.plain).scrollContentBackground(.hidden).environment(\.defaultMinListRowHeight, 1)
        .limeBackground()
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar).toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { toolbarItems(jam: jam, title: title) }
        .sheet(isPresented: $editing) { EditSeriesSheet(seriesID: seriesID, title: title, description: meta?.description ?? "") }
        .task { await store.loadSeries(seriesID) }
        .accessibilityIdentifier("series-page")
    }

    // MARK: The top

    @ToolbarContentBuilder
    private func toolbarItems(jam: String?, title: String) -> some ToolbarContent {
        // One bubble: filter · sort · ⋯ (the reference's), here and not on the root tabs.
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Picker("Show", selection: $filter) { ForEach(SeriesFilter.allCases) { Text($0.rawValue).tag($0) } }
            } label: { ToolIconLabel(symbol: filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill") }
                .accessibilityLabel("Filter parts, \(filter.rawValue)").accessibilityIdentifier("series-filter")
            Menu {
                Picker("Sort", selection: $sort) { ForEach(SeriesSort.allCases) { Text($0.rawValue).tag($0) } }
            } label: { ToolIconLabel(symbol: "arrow.up.arrow.down") }
                .accessibilityLabel("Sort parts, \(sort.rawValue)").accessibilityIdentifier("series-sort")
            Menu {
                if let jam, store.jamsMine.contains(where: { $0.jamId == jam }) { Button { editing = true } label: { Label("Edit series", systemImage: "pencil") }.accessibilityIdentifier("series-edit") }
                Button { filter = .all; sort = .part; showAll = false } label: { Label("Reset the list", systemImage: "arrow.counterclockwise") }
            } label: { ToolIconLabel(symbol: "ellipsis") }
                .accessibilityLabel("More").accessibilityIdentifier("series-more")
        }
    }

    // MARK: The hero

    private func hero(title: String, cover: UIImage?, meta: SeriesMeta?, parts: [SeriesPart], info: SeriesInfo?, readCount: Int, jam: String?) -> some View {
        let wash = washColour(cover)
        let next = parts.first { !$0.read } ?? parts.first
        let allRead = !parts.isEmpty && parts.allSatisfy(\.read)
        let writer = parts.first.map { store.teacherName($0.author) } ?? ""
        let creator = jam.flatMap { id in (store.jamsMine + store.jamSubscriptions).first { $0.jamId == id }?.title } ?? writer
        return VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                coverView(cover)
                    .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fill).clipped()
                    .overlay(LinearGradient(colors: [.clear, wash.opacity(0.95)], startPoint: .center, endPoint: .bottom))
                Text(title).font(Theme.font(.title, weight: .bold)).foregroundStyle(.white).shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                    .padding(.horizontal, 20).padding(.bottom, 14).accessibilityAddTraits(.isHeader).accessibilityIdentifier("series-page-title")
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    if let next {
                        Button { open(next) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: next.kind == "record" ? "play.fill" : "book.fill").font(.system(size: 14, weight: .bold)).accessibilityHidden(true)
                                Text(allRead ? "Start again" : "\(next.kind == "record" ? "Play" : "Read") Part \(next.part)").font(Theme.font(.body, weight: .semibold))
                                if !allRead { Text(timeText(next)).font(Theme.font(.footnote, weight: .medium).monospacedDigit()).opacity(0.7) }
                            }
                            .foregroundStyle(Color.black).padding(.horizontal, 18).frame(minHeight: 48).background(Color.white, in: Capsule())
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("series-play")
                    }
                    followButton(jam: jam, parts: parts)
                    Spacer(minLength: 0)
                }
                if let description = meta?.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(description).font(Theme.body).foregroundStyle(.white.opacity(0.92)).lineLimit(more ? nil : 2).accessibilityIdentifier("series-description")
                        if !more { Button("MORE") { more = true }.font(Theme.font(.footnote, weight: .bold)).foregroundStyle(.white).frame(minHeight: 44, alignment: .leading).accessibilityIdentifier("series-more-text") }
                    }
                }
                Text(metaLine(creator: creator, parts: parts)).font(Theme.secondary).foregroundStyle(.white.opacity(0.8)).accessibilityIdentifier("series-meta")
                Text(info?.of.map { "\(readCount) of \($0) read" } ?? "\(readCount) of \(parts.count) read").font(Theme.secondary).foregroundStyle(.white.opacity(0.8)).accessibilityIdentifier("series-progress")
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(stops: [.init(color: wash, location: 0), .init(color: wash, location: 0.72), .init(color: Color(Theme.canvas), location: 1)], startPoint: .top, endPoint: .bottom))
        }
    }

    /// The cover, or the series' colour as a gradient when there is none.
    @ViewBuilder
    private func coverView(_ cover: UIImage?) -> some View {
        if let cover { Image(uiImage: cover).resizable().scaledToFill() }
        else { Rectangle().fill(LinearGradient(colors: [Theme.avatar(AvatarTone.tone(for: seriesID)), Theme.avatar(AvatarTone.tone(for: seriesID)).opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)).overlay(Image(systemName: "square.stack").font(.system(size: 54)).foregroundStyle(.white.opacity(0.7))) }
    }

    /// The wash: the cover's own dark colour (so white text on it keeps its contrast), or the series' colour darkened.
    private func washColour(_ cover: UIImage?) -> Color {
        if let cover { return Color(uiColor: HeroPalette.darkColor(of: cover, key: "series-\(seriesID)")) }
        return Color(uiColor: Theme.avatarUIColor(AvatarTone.tone(for: seriesID), dark: true)).opacity(1).mix(with: .black, by: 0.45)
    }

    @ViewBuilder
    private func followButton(jam: String?, parts: [SeriesPart]) -> some View {
        if let jam, !store.jamsMine.contains(where: { $0.jamId == jam }), let first = parts.first {
            let following = store.isFollowing(jam)
            Button {
                if !following { Task { await store.subscribe(to: JamPageInfo(jamId: jam, writerId: first.author, title: "", about: "", topics: [], postCount: 0, subscriberCount: 0, hasCommunity: false, pictureVersion: nil)) } }
            } label: {
                Image(systemName: following ? "checkmark" : "plus").font(.system(size: 18, weight: .bold)).foregroundStyle(.white).frame(width: 48, height: 48).background(.white.opacity(0.22), in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel(following ? "Subscribed" : "Subscribe").accessibilityIdentifier("series-follow")
        }
    }

    private func metaLine(creator: String, parts: [SeriesPart]) -> String {
        let kinds = Set(parts.map(\.kind))
        let type = kinds == ["record"] ? "Podcast" : kinds == ["article"] ? "Articles" : kinds.isEmpty ? "Series" : "Mixed"
        return [creator.isEmpty ? nil : creator, type, parts.count == 1 ? "1 part" : "\(parts.count) parts"].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    private func timeText(_ part: SeriesPart) -> String {
        if part.kind == "record" { return part.durationMs > 0 ? JamPodcastCard.short(Double(part.durationMs) / 1000) : "" }
        return "\(max(1, part.words / 200)) min read"
    }

    // MARK: Parts

    private func visible(_ parts: [SeriesPart]) -> [SeriesPart] {
        let filtered = parts.filter { part in
            switch filter {
            case .all: true
            case .unplayed: !part.read
            case .played: part.read
            case .saved: JamSaved.contains(part.id)
            }
        }
        return sort == .part ? filtered.sorted { $0.part < $1.part } : filtered.sorted { $0.created > $1.created }
    }

    private func row(_ part: SeriesPart) -> some View {
        let post = store.jamPosts.values.joined().first { $0.postId == part.id }
        let kind = part.kind == "record" ? "Podcast" : part.kind == "article" ? "Article" : "Post"
        let video = part.kind == "record" && store.jamAttachments(part.id).contains { $0.kind == "video" }
        return Button { open(part) } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(JamDates.short(part.created)) \u{00B7} \(video ? "Video" : kind) \u{00B7} Part \(part.part)").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    Text(part.title).font(Theme.font(.body, weight: part.read ? .regular : .semibold)).foregroundStyle(Theme.text).multilineTextAlignment(.leading).lineLimit(2)
                    if !part.subtitle.isEmpty { Text(part.subtitle).font(Theme.secondary).foregroundStyle(Theme.textSecondary).lineLimit(3).multilineTextAlignment(.leading) }
                    HStack(spacing: 8) {
                        pill(part)
                        if part.preview { HStack(spacing: 4) { Image(systemName: "lock").font(.system(size: 12)); Text("Preview").font(Theme.caption) }.foregroundStyle(Theme.textSecondary).accessibilityIdentifier("series-lock-\(part.id)") }
                        else if part.read { Image(systemName: "checkmark.circle").font(.system(size: 16)).foregroundStyle(Theme.textSecondary).accessibilityLabel("Read").accessibilityIdentifier("series-read-\(part.id)") }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
                thumbnail(part)
            }
            .padding(.horizontal, 20).padding(.vertical, 12).frame(minHeight: 64).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Part \(part.part), \(part.title), \(video ? "video" : kind.lowercased())\(part.read ? ", played" : "")")
        .accessibilityAction(named: part.read ? (part.kind == "record" ? "Mark as unplayed" : "Mark as unread") : (part.kind == "record" ? "Mark as played" : "Mark as read")) { toggleRead(part) }
        .accessibilityAction(named: JamSaved.contains(part.id) ? "Unsave" : "Save") { if part.local { JamSaved.toggle(part.id); refresh += 1 } }
        .accessibilityIdentifier("series-part-\(part.id)")
        .overlay(alignment: .topTrailing) { if let post { JamPostMenu(post: post).padding(.trailing, 6).padding(.top, 2) } }
    }

    private func pill(_ part: SeriesPart) -> some View {
        HStack(spacing: 6) {
            Image(systemName: part.kind == "record" ? "play.fill" : "doc.text").font(.system(size: 11, weight: .bold)).accessibilityHidden(true)
            Text(part.kind == "record" ? (timeText(part).isEmpty ? "Play" : timeText(part)) : timeText(part)).font(Theme.font(.footnote, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(Theme.text).padding(.horizontal, 12).frame(minHeight: 32).background(Theme.surface, in: Capsule())
    }

    @ViewBuilder
    private func thumbnail(_ part: SeriesPart) -> some View {
        Group {
            if part.local { PostCover(postID: part.id) } else { Rectangle().fill(Theme.surface).overlay(Image(systemName: part.kind == "record" ? "waveform" : "doc.text").foregroundStyle(Theme.textSecondary)) }
        }
        .frame(width: 88, height: 88).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)).accessibilityHidden(true)
    }

    // MARK: Hosts, information, more

    private func hosts(_ parts: [SeriesPart]) -> some View {
        var people: [(id: String, role: String)] = []
        for part in parts where !people.contains(where: { $0.id == part.author }) { people.append((part.author, "Writer")) }
        for post in store.jamPosts.values.joined() where post.series?.id == seriesID { for coauthor in post.coauthors where !people.contains(where: { $0.id == coauthor }) { people.append((coauthor, "Co-author")) } }
        return VStack(alignment: .leading, spacing: 10) {
            if !people.isEmpty {
                Text("Hosts").font(Theme.font(.title3, weight: .bold)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader).padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(people, id: \.id) { person in
                            let who = person.id == store.meProvider().id ? store.meProvider() : store.teacher(person.id)
                            Button { store.openProfile(ProfileRoute(userID: who.id, name: who.name, isMe: who.id == store.meProvider().id)) } label: {
                                VStack(spacing: 4) {
                                    AvatarView(person: who, size: 76).accessibilityHidden(true)
                                    Text(who.name).font(Theme.secondary).foregroundStyle(Theme.text).lineLimit(1)
                                    Text(person.role).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                                }
                                .frame(width: 96)
                            }
                            .buttonStyle(.plain).accessibilityLabel("\(who.name), \(person.role)").accessibilityIdentifier("series-host-\(who.id)")
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .padding(.top, 16)
    }

    private func information(_ parts: [SeriesPart], jam: String?) -> some View {
        let first = parts.map(\.created).filter { $0 > 0 }.min()
        let last = parts.map(\.created).max()
        let creator = jam.flatMap { id in (store.jamsMine + store.jamSubscriptions).first { $0.jamId == id }?.title } ?? (parts.first.map { store.teacherName($0.author) } ?? "")
        func line(_ label: String, _ value: String, id: String) -> some View {
            HStack { Text(label).font(Theme.body).foregroundStyle(Theme.textSecondary); Spacer(); Text(value).font(Theme.body).foregroundStyle(Theme.text).accessibilityIdentifier(id) }.frame(minHeight: 44)
                .accessibilityElement(children: .combine)
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text("Information").font(Theme.font(.title3, weight: .bold)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
            line("Creator", creator, id: "series-info-creator")
            Divider().overlay(Theme.hairline)
            line("Started", first.map { Date(timeIntervalSince1970: Double($0) / 1000).formatted(.dateTime.month(.wide).year()) } ?? "", id: "series-info-started")
            Divider().overlay(Theme.hairline)
            line("Parts", "\(parts.count)", id: "series-info-parts")
            Divider().overlay(Theme.hairline)
            line("Updated", last.map { JamDates.short($0) } ?? "", id: "series-info-updated")
        }
        .padding(.horizontal, 20).padding(.top, 20)
    }

    @ViewBuilder
    private func moreFrom(jam: String?) -> some View {
        if let jam {
            let others = store.otherSeries(inJam: jam, except: seriesID)
            if !others.isEmpty {
                let creator = (store.jamsMine + store.jamSubscriptions).first { $0.jamId == jam }?.title ?? "this writer"
                VStack(alignment: .leading, spacing: 10) {
                    Text("More from \(creator)").font(Theme.font(.title3, weight: .bold)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader).padding(.horizontal, 20)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(others, id: \.id) { other in
                                Button { store.jamPath.append(SeriesRoute(seriesID: other.id)) } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.avatar(AvatarTone.tone(for: other.id))).frame(width: 160, height: 160)
                                            .overlay(Image(systemName: "square.stack").font(.system(size: 36)).foregroundStyle(Theme.text.opacity(0.5)))
                                        Text(other.title).font(Theme.secondary).foregroundStyle(Theme.text).lineLimit(2).frame(width: 160, alignment: .leading)
                                    }
                                }
                                .buttonStyle(.plain).accessibilityLabel(other.title).accessibilityIdentifier("series-more-\(other.id)")
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.top, 24)
            }
        }
    }

    // MARK: Actions

    private func open(_ part: SeriesPart) {
        if part.local { store.jamPath.append(JamPostRoute(postID: part.id)) } else { store.jamPath.append(OpenPostRoute(postID: part.id)) }
    }

    private func toggleRead(_ part: SeriesPart) {
        if part.kind == "record" { JamPlayed.toggle(part.id) }
        else if part.read { JamRead.unmark(part.id); if JamPlayed.contains(part.id) { JamPlayed.toggle(part.id) } }
        else { JamRead.mark(part.id) }
        refresh += 1
    }

    private func playNext(_ part: SeriesPart) {
        guard let post = store.jamPosts.values.joined().first(where: { $0.postId == part.id }), let item = NowPlaying.shared.makeItem(for: post, store: store) else { return }
        NowPlaying.shared.playNext(item)
    }
}

extension Color {
    /// This colour blended towards `other` by `amount` (0 to 1).
    func mix(with other: Color, by amount: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var (ar, ag, ab, aa): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (br, bg, bb, ba): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa); b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return Color(red: ar + (br - ar) * amount, green: ag + (bg - ag) * amount, blue: ab + (bb - ab) * amount)
    }
}

/// The writer describes the series: its title, a description and a cover (a picture framed square and shrunk to 24 KB, public to subscribers with the jam's state).
struct EditSeriesSheet: View {
    let seriesID: String
    @State var title: String
    @State var description: String
    @Environment(ConversationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var picked: UIImage?
    @State private var picking = false
    @State private var cropping: UIImage?
    @State private var saving = false
    @State private var failed = false

    init(seriesID: String, title: String, description: String) {
        self.seriesID = seriesID
        _title = State(initialValue: title)
        _description = State(initialValue: description)
    }

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && description.count <= 1000 && !saving }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Edit series", leading: .close { dismiss() }) {
                Button { save() } label: {
                    Text(saving ? "Saving\u{2026}" : "Save").font(Theme.title).foregroundStyle(Theme.accentInk).padding(.horizontal, 18).frame(minHeight: 44)
                        .background(Theme.accent.opacity(canSave ? 1 : 0.4), in: Capsule()).opacity(canSave ? 1 : 0.6)
                }
                .disabled(!canSave).accessibilityIdentifier("series-edit-save")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Title", text: $title).font(Theme.body).padding(.horizontal, 16).frame(minHeight: 52).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous)).accessibilityIdentifier("series-edit-title")
                    TextField("Description", text: $description, axis: .vertical).font(Theme.body).lineLimit(3...8).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous)).accessibilityIdentifier("series-edit-description")
                    Text("\(description.count)/1000").font(Theme.caption).foregroundStyle(description.count > 1000 ? Color.red : Theme.textSecondary).frame(maxWidth: .infinity, alignment: .trailing)
                    HStack(spacing: 12) {
                        if let picked { Image(uiImage: picked).resizable().scaledToFill().frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)).accessibilityHidden(true) }
                        Button { picking = true } label: {
                            Label(picked == nil ? "Choose cover" : "Change cover", systemImage: "photo.on.rectangle").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.text)
                                .padding(.horizontal, 14).frame(minHeight: 44).background(Theme.surface, in: Capsule())
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("series-edit-cover")
                    }
                    Text("The description and cover show to people who follow you.").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    if failed { Text("Could not save. Try again.").font(Theme.secondary).foregroundStyle(Color.red) }
                }
                .padding(20)
            }
        }
        .limeBackground()
        .presentationDetents([.large])
        .fullScreenCover(isPresented: $picking) { LibraryPicker(onPick: { image in picking = false; cropping = image }, onCancel: { picking = false }).ignoresSafeArea() }
        .fullScreenCover(item: Binding(get: { cropping.map(CropPick.init) }, set: { if $0 == nil { cropping = nil } })) { item in
            PhotoCropScreen(image: item.image, onSave: { cropped in cropping = nil; picked = cropped }, onCancel: { cropping = nil })
        }
    }

    private struct CropPick: Identifiable { let image: UIImage; var id: ObjectIdentifier { ObjectIdentifier(image) } }

    private func save() {
        saving = true; failed = false
        let cover = picked.flatMap { SeriesCover.jpeg($0) }
        Task {
            let ok = await store.setSeriesMeta(seriesID, title: title.trimmingCharacters(in: .whitespaces), description: description.trimmingCharacters(in: .whitespacesAndNewlines), cover: cover ?? store.seriesMetas[seriesID]?.cover)
            saving = false
            if ok { dismiss() } else { failed = true }
        }
    }
}
