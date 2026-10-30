import SwiftUI

/// Where a series page is pushed on the jam tab (LIME-210f).
struct SeriesRoute: Hashable { let seriesID: String }

/// "Part 2 of 6" (or "Part 2" when the writer did not say how many).
extension SeriesInfo {
    var partLabel: String { of.map { "Part \(part) of \($0)" } ?? "Part \(part)" }
}

/// One part of a series as the series page shows it.
struct SeriesPart: Identifiable {
    let id: String
    let part: UInt32
    let title: String
    let kind: String
    /// I have the whole post (mine, or a jam I follow); otherwise it is an open post (the whole thing, or a Preview).
    let local: Bool
    let preview: Bool
    let read: Bool
    /// What the series page's rows show (LIME-260b): when, a line under the title, who, which jam, how long a recording is.
    var created: Int64 = 0
    var subtitle = ""
    var author = ""
    var jamID = ""
    var durationMs: UInt32 = 0
    var words = 0
}

extension ConversationStore {
    /// The series of my own posts: id, title, how many parts there are, and the next part number.
    func mySeries() -> [(id: String, title: String, parts: Int, next: UInt32)] {
        var found: [String: (title: String, parts: Int, last: UInt32)] = [:]
        for jam in jamsMine {
            for post in jamPosts[jam.jamId] ?? [] {
                guard let series = post.series else { continue }
                var entry = found[series.id] ?? (series.title, 0, 0)
                entry.parts += 1
                entry.last = max(entry.last, series.part)
                found[series.id] = entry
            }
        }
        return found.map { (id: $0.key, title: $0.value.title, parts: $0.value.parts, next: $0.value.last + 1) }.sorted { $0.title < $1.title }
    }

    /// The parts of a series this phone knows, in order: the posts I can read, and the open ones from Discover that I do not have.
    func seriesParts(_ seriesID: String) -> [SeriesPart] {
        let read = JamRead.ids
        var parts: [SeriesPart] = []
        var seen: Set<String> = []
        for posts in jamPosts.values {
            for post in posts where post.series?.id == seriesID {
                guard seen.insert(post.postId).inserted, let series = post.series else { continue }
                let length = jamAttachments(post.postId).first { $0.kind == "audio" || $0.kind == "video" }?.durationMs ?? 0
                parts.append(SeriesPart(id: post.postId, part: series.part, title: post.title.isEmpty ? String(post.plain.prefix(40)) : post.title, kind: post.kind, local: true, preview: false,
                                        read: read.contains(post.postId) || JamPlayed.contains(post.postId) || post.author == meProvider().id,
                                        created: post.created, subtitle: post.subtitle.isEmpty ? String(post.plain.prefix(140)) : post.subtitle, author: post.author, jamID: post.jamId,
                                        durationMs: length, words: post.plain.split(separator: " ").count))
            }
        }
        for item in discoverItems where item.series?.id == seriesID && seen.insert(item.postId).inserted {
            if let series = item.series { parts.append(SeriesPart(id: item.postId, part: series.part, title: item.title, kind: item.kind, local: false, preview: item.previewOf != nil, read: read.contains(item.postId),
                                                      created: item.created, subtitle: item.subtitle.isEmpty ? String(item.excerpt.prefix(140)) : item.subtitle, author: item.authorId, jamID: item.jamId)) }
        }
        return parts.sorted { $0.part < $1.part }
    }

    /// The series' title and total, from any part.
    func seriesInfo(_ seriesID: String) -> SeriesInfo? {
        for posts in jamPosts.values { if let s = posts.compactMap(\.series).first(where: { $0.id == seriesID }) { return s } }
        return discoverItems.compactMap(\.series).first { $0.id == seriesID }
    }

    /// Puts one of my posts in a series, or takes it out.
    func setPostSeries(_ post: JamPostInfo, to series: SeriesInfo?) async -> Bool {
        #if DEBUG
        if isDemo { demoSetSeries(post, series); return true }
        #endif
        guard let core else { return false }
        do { try await Task.detached(priority: .userInitiated) { try core.setJamPostSeries(postId: post.postId, series: series) }.value }
        catch { CallDiagnostics.shared.log("jam series failed: \(error)"); return false }
        refreshJams()
        await deliverNow()
        return true
    }
}

/// The composer's and Edit's series row: "Add to a series" or "Fractions · Part 2" (LIME-210f).
struct SeriesChip: View {
    @Binding var series: SeriesInfo?
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.stack").font(.system(size: 14, weight: .medium)).accessibilityHidden(true)
                Text(series.map { "\($0.title) \u{00B7} \($0.partLabel)" } ?? "Add to a series").font(Theme.font(.subheadline)).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).accessibilityHidden(true)
            }
            .foregroundStyle(series == nil ? Theme.textSecondary : Theme.text)
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(series.map { "Series: \($0.title), \($0.partLabel)" } ?? "Add to a series").accessibilityHint("Choose or make a series")
        .accessibilityIdentifier("jam-series")
        .sheet(isPresented: $picking) { SeriesPickerSheet(series: $series) }
    }
}

/// Choose a series of mine or make a new one, and say which part this is (and, if known, how many there will be). Reordering is changing the part
/// number of a post in Edit: there is no bulk screen. Changes apply as you make them (LIME-242): ✕ just closes.
struct SeriesPickerSheet: View {
    @Binding var series: SeriesInfo?
    @Environment(ConversationStore.self) private var store
    @State private var chosen: String?          // an existing series id, or nil
    @State private var making = false
    @State private var newTitle = ""
    @State private var newID = UUID().uuidString.lowercased()
    @State private var part: Int = 1
    @State private var total: Int = 0           // 0: not said
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { chosen = nil; making = false; series = nil } label: { row("No series", check: chosen == nil && !making) }
                        .accessibilityIdentifier("series-none")
                    ForEach(store.mySeries(), id: \.id) { entry in
                        Button { chosen = entry.id; making = false; part = Int(entry.next); total = Int(store.seriesInfo(entry.id)?.of ?? 0); apply() } label: { row("\(entry.title) \u{00B7} \(entry.parts) \(entry.parts == 1 ? "part" : "parts")", check: chosen == entry.id) }
                            .accessibilityIdentifier("series-existing-\(entry.id)")
                    }
                    Button { making = true; chosen = nil; part = 1; apply() } label: { row("New series\u{2026}", check: making) }
                        .accessibilityIdentifier("series-new")
                }
                .listRowBackground(Theme.canvas)
                if making {
                    Section("Name") {
                        TextField("Series name", text: $newTitle).textInputAutocapitalization(.sentences).accessibilityIdentifier("series-title")
                            .onChange(of: newTitle) { apply() }
                    }
                    .listRowBackground(Theme.canvas)
                }
                if making || chosen != nil {
                    Section("This post") {
                        Stepper("Part \(part)", value: $part, in: 1...99).accessibilityIdentifier("series-part").onChange(of: part) { apply() }
                        Stepper(total == 0 ? "How many parts: not said" : "How many parts: \(total)", value: $total, in: 0...99).accessibilityIdentifier("series-total").onChange(of: total) { apply() }
                    }
                    .listRowBackground(Theme.canvas)
                }
            }
            .scrollContentBackground(.hidden).background(Theme.canvas)
            .sheetHeader("Series")
            .onAppear { if !loaded { loaded = true; if let series { chosen = series.id; part = Int(series.part); total = Int(series.of ?? 0) } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ text: String, check: Bool) -> some View {
        HStack { Text(text).foregroundStyle(Theme.text); Spacer(minLength: 0); if check { Image(systemName: "checkmark").foregroundStyle(Theme.text).accessibilityHidden(true) } }.frame(minHeight: 44)
            .accessibilityAddTraits(check ? [.isSelected] : [])
    }

    /// Puts what the sheet shows into the post's series now.
    private func apply() {
        let title: String, id: String
        if making {
            title = newTitle.trimmingCharacters(in: .whitespaces)
            id = newID
            if title.isEmpty { series = nil; return }
        } else if let chosen, let known = store.seriesInfo(chosen) ?? series.flatMap({ $0.id == chosen ? $0 : nil }) {
            title = known.title; id = chosen
        } else { return }
        series = SeriesInfo(id: id, title: title, part: UInt32(part), of: total >= part ? UInt32(total) : nil)
    }
}

