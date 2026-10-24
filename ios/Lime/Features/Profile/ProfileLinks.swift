import SwiftUI
import SafariServices

/// One link on a profile (LIME-214): a short title and an https address.
struct ProfileLink: Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var url: String

    enum CodingKeys: String, CodingKey { case title, url }
}

/// The list of links: parsing, checking and the JSON that travels (inside the profile, Everyone's or contacts-only).
enum ProfileLinks {
    static let maxCount = 5
    static let maxTitle = 40

    /// The address as it will be stored: https only (http is upgraded; anything else is refused).
    static func normalized(_ text: String) -> String? {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !raw.contains(" ") else { return nil }
        if raw.lowercased().hasPrefix("http://") { raw = "https://" + raw.dropFirst("http://".count) }
        else if !raw.contains("://") { raw = "https://" + raw }
        guard raw.lowercased().hasPrefix("https://"), let url = URL(string: raw), let host = url.host, host.contains(".") else { return nil }
        return raw
    }

    /// `nil` when everything is fine, else what to tell the person. Blank rows are ignored.
    static func problem(in links: [ProfileLink]) -> String? {
        let filled = links.filter { !($0.title.trimmingCharacters(in: .whitespaces).isEmpty && $0.url.trimmingCharacters(in: .whitespaces).isEmpty) }
        if filled.count > maxCount { return "Up to \(maxCount) links." }
        for link in filled {
            if link.title.trimmingCharacters(in: .whitespaces).isEmpty { return "Give each link a title." }
            if link.title.count > maxTitle { return "Titles are \(maxTitle) letters at most." }
            if normalized(link.url) == nil { return "Links start with https:// and need a real address." }
        }
        return nil
    }

    /// What is saved: trimmed, upgraded, in order, without blank rows.
    static func cleaned(_ links: [ProfileLink]) -> [ProfileLink] {
        links.compactMap { link in
            let title = link.title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty, let url = normalized(link.url) else { return nil }
            return ProfileLink(id: link.id, title: String(title.prefix(maxTitle)), url: url)
        }.prefix(maxCount).map { $0 }
    }

    static func encode(_ links: [ProfileLink]) -> Data? { try? JSONEncoder().encode(cleaned(links)) }

    /// What a person sent: only links that still pass the checks (a hand-made list cannot smuggle in another scheme).
    static func decode(_ data: Data?) -> [ProfileLink] {
        guard let data, let links = try? JSONDecoder().decode([ProfileLink].self, from: data) else { return [] }
        return cleaned(links)
    }

    /// The address as shown under the title: no scheme.
    static func shown(_ url: String) -> String {
        url.replacingOccurrences(of: "https://", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

/// A link opened in Safari inside the app (Safari View Controller).
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// The Links card on an Info tab: each link is "Title" over its address; a tap opens it in Safari.
struct ProfileLinksCard: View {
    let links: [ProfileLink]
    @State private var opened: ProfileLink?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Links").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(Theme.textSecondary).padding(.leading, 6)
            VStack(spacing: 0) {
                ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                    Button { opened = link } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(link.title).font(Theme.body).foregroundStyle(Theme.text).lineLimit(1)
                                Text(ProfileLinks.shown(link.url)).font(Theme.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                        }
                        .padding(.horizontal, 18).frame(minHeight: 56).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(link.title), \(ProfileLinks.shown(link.url))")
                    .accessibilityAddTraits(.isLink)
                    .accessibilityIdentifier("profile-link-\(index)")
                    if index < links.count - 1 { Divider().overlay(Theme.hairline).padding(.leading, 18) }
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .sheet(item: $opened) { link in
            if let url = URL(string: link.url) { SafariSheet(url: url).ignoresSafeArea() }
        }
    }
}
