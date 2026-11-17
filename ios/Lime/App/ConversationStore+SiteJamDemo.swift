#if DEBUG
import Foundation
import UIKit

/// Demo mode (the website's jam phone, LIME-286r2, 347): Maya follows invented teachers, two real board members (as the authors of their own real work only) and a band, with covers, a series, two podcasts and a members-only post.
/// Cover photos are read from a folder named by `-lime-demo-covers <dir>` (`<dir>/<name>.jpg`); without it the posts have no cover.
extension ConversationStore {
    func demoSiteJam(screen: String) {
        demoSiteLink(screen: "site-link")   // Maya, the cast and their photos
        section = .jam
        openPostsEnabled = true
        UserDefaults.standard.removeObject(forKey: JamRead.key)
        let args = ProcessInfo.processInfo.arguments
        let dir = args.firstIndex(of: "-lime-demo-covers").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        func photo(_ name: String) -> Data? { dir.flatMap { FileManager.default.contents(atPath: $0 + "/" + name + ".jpg") } }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        func jam(_ id: String, writer: String, _ title: String, _ about: String, _ topics: [String], band: Bool = false) -> JamPageInfo {
            jamSubscriptions.append(JamInfo(jamId: id, conversationId: "jam:\(id)", writer: writer, title: title, about: about, topics: topics, tiers: ["free"], mine: false, status: "active", ended: false,
                                            community: false, communityState: nil, communityGroup: nil, subscriberCount: 0, postCount: 0, created: now))
            return JamPageInfo(jamId: id, writerId: writer, title: title, about: about, topics: topics, postCount: 4, subscriberCount: 128, hasCommunity: false, pictureVersion: nil)
        }
        func add(_ id: String, _ jamID: String, _ author: String, _ kind: String, _ title: String, _ subtitle: String, _ markdown: String, ago: Int64, cover: String? = nil, audioMs: UInt32? = nil,
                 series: SeriesInfo? = nil, figure: String? = nil, members: Bool = false, displayAs: String = "person") {
            var files: [JamAttachmentInfo] = []
            if let audioMs {
                files.append(JamAttachmentInfo(attachmentId: "\(id)-audio", name: "Recording.m4a", mime: "audio/mp4", kind: "audio", size: 90_000, width: nil, height: nil, durationMs: audioMs,
                                               thumb: Data((0..<64).map { UInt8(40 + (($0 * 37) % 200)) }), poster: Data(), available: true))
            }
            if let cover, let bytes = photo(cover) {
                Self.demoJamBlobs["\(id)-cover"] = bytes
                files.append(JamAttachmentInfo(attachmentId: "\(id)-cover", name: JamCover.name, mime: "image/jpeg", kind: "image", size: UInt64(bytes.count), width: 1200, height: 800, durationMs: nil, thumb: Data(), poster: Data(), available: true))
            }
            if let figure, let bytes = photo(figure) {
                Self.demoJamBlobs["\(id)-figure"] = bytes
                files.append(JamAttachmentInfo(attachmentId: "\(id)-figure", name: "figure.jpg", mime: "image/jpeg", kind: "image", size: UInt64(bytes.count), width: 1200, height: 800, durationMs: nil, thumb: Data(), poster: Data(), available: true))
            }
            if !files.isEmpty { demoJamAttachments[id] = files }
            jamPosts[jamID, default: []].append(JamPostInfo(postId: id, jamId: jamID, author: author, tier: members ? "members" : "free", kind: kind, title: title, subtitle: subtitle, markdown: markdown,
                                                            plain: messagePlainText(text: markdown), attachmentsJson: "[]", created: now - ago * 60_000, coauthors: [], displayAs: displayAs, editedAt: 0,
                                                            audience: "subscribers", series: series, topics: [], state: "ready"))
        }
        func fractions(_ part: UInt32) -> SeriesInfo { SeriesInfo(id: "site-series-fractions", title: "Fractions that stick", part: part, of: 3) }

        // The two board members appear only as the authors of their own real work: real titles, real addresses, nothing written for them (LIME-347).
        func link(_ postID: String, _ n: Int, title: String, url: String, site: String, poster: String?) -> JamAttachmentInfo {
            let id = "\(postID)-link\(n)"
            Self.demoJamBlobs[id] = (try? JSONEncoder().encode(JamLink.Payload(url: url, title: title, site: site))) ?? Data()
            return JamAttachmentInfo(attachmentId: id, name: title, mime: JamLink.mime, kind: "file", size: 200, width: nil, height: nil, durationMs: nil, thumb: Data(), poster: poster.flatMap(photo) ?? Data(), available: true)
        }
        publicProfiles["okome"] = PublicProfile(userId: "okome", displayName: "Dr. Mojúbàolú Olúfúnké Okome", username: "okome", school: nil, aboutEmoji: nil, aboutText: nil, since: nil, hasJam: false)
        publicProfiles["calton"] = PublicProfile(userId: "calton", displayName: "Rich Calton", username: "rich.calton", school: nil, aboutEmoji: nil, aboutText: nil, since: nil, hasJam: false)
        _ = jam("site-irin-band", writer: "okome", "Ìrìnkèrindò: a Journal of African Migration", "", ["Migration"], band: true)
        add("site-okome-1", "site-irin-band", "okome", "quick", "", "", "Ìrìnkèrindò: a Journal of African Migration — https://africamigration.com/", ago: 45, displayAs: "jam")
        demoJamAttachments["site-okome-1"] = [
            link("site-okome-1", 1, title: "Women, Water, and Migration In Africa", url: "https://africamigration.com/", site: "africamigration.com", poster: "water"),
            link("site-okome-1", 2, title: "African Immigrant Innovation in 21st Century Giving", url: "https://africamigration.com/", site: "africamigration.com", poster: "giving"),
            link("site-okome-1", 3, title: "African Diaspora Families & Changing Gender Relations: A Focus on GBV & IPV", url: "https://africamigration.com/", site: "africamigration.com", poster: "families"),
        ]
        _ = jam("site-calton-jam", writer: "calton", "Rich Calton", "", [])
        add("site-calton-1", "site-calton-jam", "calton", "quick", "", "", "The Legacy of HarlemLIVE: Empowering Youth Through Journalism and Experiential Learning, third edition (2026)\n\nFrom 1996 to 2011, teenagers in Harlem ran a real newsroom.", ago: 70)
        demoJamAttachments["site-calton-1"] = [link("site-calton-1", 1, title: "The Legacy of HarlemLIVE: Empowering Youth Through Journalism and Experiential Learning", url: "https://www.harlemlive.net/publications/", site: "harlemlive.net", poster: nil)]

        // Ms Park: three articles of a series.
        let park = jam("site-park-jam", writer: "park", "Fractions that stick", "Short lessons for grades 3 to 5", ["Maths", "Grade 4"])
        demoJamPages["park"] = park
        publicProfiles["park"] = PublicProfile(userId: "park", displayName: "Ms Park", username: "ms.park", school: nil, aboutEmoji: nil, aboutText: nil, since: nil, hasJam: false)
        add("site-park-1", "site-park-jam", "park", "article", "Fold, cut, compare", "Part 1: halves and quarters", "We started with a strip of paper. **Fold it in half**, then in half again, and ask: what do you notice?\n\nBy the end of the lesson every pair could say why two quarters make a half.", ago: 3_000, cover: "fold", series: fractions(1))
        add("site-park-2", "site-park-jam", "park", "article", "Fraction walls", "Part 2: bricks that match", "Build a wall of bricks, one row for each fraction, and slide them side by side.\n\nThe question that does the teaching: *which rows line up?*", ago: 320, cover: "walls", series: fractions(2))
        add("site-park-3", "site-park-jam", "park", "article", "Comparing with benchmarks", "Part 3: more or less than a half?", "Is it more or less than a half? Start there, then ask how you know.", ago: 5_000, series: fractions(3))
        let seriesCover = photo("walls")
        seriesMetas["site-series-fractions"] = SeriesMeta(seriesId: "site-series-fractions", title: "Fractions that stick", description: "Short lessons on fractions, one idea each. Fold paper, build a wall of bricks, and see why one half is bigger than one third. Written for grades 3 to 5, and good to read aloud.", cover: seriesCover)
        seriesCovers["site-series-fractions"] = seriesCover

        // Luis Ortega: a three-part series, "Local Government Lab".
        func lab(_ part: UInt32) -> SeriesInfo { SeriesInfo(id: "site-series-lab", title: "Local Government Lab", part: part, of: 3) }
        _ = jam("site-luis-jam", writer: "luis", "Local Government Lab", "Civics you can try in town", ["Civics", "Grade 11"])
        add("site-luis-1", "site-luis-jam", "luis", "article", "Who runs your town?", "Part 1: find the offices", "Start with a map and a phone. Ask each pair to find **three offices** in their town and what each one decides.\n\nThe question that does the teaching: *who could fix this pothole?*", ago: 1_400, cover: "civics", series: lab(1))
        add("site-luis-2", "site-luis-jam", "luis", "article", "Reading a city budget", "Part 2: where the money goes", "Give every group one page of the budget and one colour pen. **Circle what surprises you.**\n\nThen compare: which line would you cut, and who would feel it?", ago: 200, cover: "civics", series: lab(2))
        add("site-luis-3", "site-luis-jam", "luis", "article", "Going to a council meeting", "Part 3: speak for two minutes", "Two minutes at the microphone is a skill. Practise it in class first.", ago: 6_000, series: lab(3))
        let labCover = photo("civics")
        seriesMetas["site-series-lab"] = SeriesMeta(seriesId: "site-series-lab", title: "Local Government Lab", description: "Three lessons that send students out of the classroom and into their town hall. Written for high-school civics.", cover: labCover)
        seriesCovers["site-series-lab"] = labCover

        // Mrs Flowers, Dr Nwosu's podcast and Kofi Mensah.
        _ = jam("site-flowers-jam", writer: "flowers", "Practice, not homework", "Ten minutes a child chooses", ["Practice"])
        publicProfiles["flowers"] = PublicProfile(userId: "flowers", displayName: "Mrs Flowers", username: "mrs.flowers", school: nil, aboutEmoji: nil, aboutText: nil, since: nil, hasJam: false)
        add("site-flowers-1", "site-flowers-jam", "flowers", "quick", "", "", "An exit ticket that takes a minute: ask one question at the door, *which pieces are equal?*", ago: 110)
        add("site-flowers-2", "site-flowers-jam", "flowers", "article", "Why we stopped giving homework", "What we do instead", "We swapped it for ten minutes of practice a child chooses.\n\nThe rule that helped most: **everyone picks their own**.", ago: 700, cover: "circles")
        _ = jam("site-adaeze-jam", writer: "adaeze", "Lab Notes", "Chemistry for first-year students", ["Chemistry"])
        add("site-adaeze-pod", "site-adaeze-jam", "adaeze", "record", "Why the balloon shrinks", "Gas laws in 14 minutes", "How I teach the gas laws in a community-college lab.", ago: 400, cover: "labnotes", audioMs: 840_000)
        _ = jam("site-kofi-jam", writer: "kofi", "Read-aloud night", "What families asked for", ["Literacy"])
        add("site-kofi-pod", "site-kofi-jam", "kofi", "record", "Ten books families asked for", "Family literacy night", "Three minutes on the books that went home with the most families.", ago: 900, cover: "readaloud", audioMs: 190_000)

        // The band: Science Corner, written by Dr Nwosu, with a cover photo, a picture and members.
        let science = jam("site-sci-band", writer: "adaeze", "Science Corner", "Experiments and ideas from teachers who love science", ["Science"], band: true)
        add("site-sci-1", "site-sci-band", "adaeze", "article", "Moon phases with a lamp", "A twenty-minute model", "A lamp, a ball and a dark room: ten minutes to **see why the moon changes**.\n\nLet every pair hold the ball once.", ago: 20, cover: "science", figure: "fold", displayAs: "jam")
        add("site-sci-2", "site-sci-band", "adaeze", "article", "Our term plan", "Lab sheets, for members", "The full term plan, with the lab sheets.", ago: 240, cover: "members", members: true, displayAs: "jam")
        add("site-sci-3", "site-sci-band", "adaeze", "quick", "", "", "Thursday lab: bring the magnets.", ago: 500, displayAs: "jam")
        AvatarCache.shared.set(photo("band"), for: Self.jamCoverKey("site-sci-band"))
        AvatarCache.shared.set(photo("bandpic"), for: Self.jamPictureKey("site-sci-band"))
        orgs = [OrgInfo(jamId: "site-sci-band", conversationId: "grp:site-sci", writerId: "adaeze", name: "Science Corner", myRole: "member", memberCount: 5)]
        let tone = { (id: String) in UInt32(AvatarTone.tone(for: id)) }
        orgMembersByJam["site-sci-band"] = [
            OrgMemberInfo(userId: "adaeze", name: "Adaeze Nwosu", tone: tone("adaeze"), role: "owner", isMe: false, canManage: false),
            OrgMemberInfo(userId: "talia", name: "Talia Brooks", tone: tone("talia"), role: "writer", isMe: false, canManage: false),
            OrgMemberInfo(userId: meProvider().id, name: "Maya Ortiz", tone: 6, role: "member", isMe: true, canManage: false),
            OrgMemberInfo(userId: "kofi", name: "Kofi Mensah", tone: tone("kofi"), role: "member", isMe: false, canManage: false),
            OrgMemberInfo(userId: "park", name: "Ms Park", tone: tone("park"), role: "member", isMe: false, canManage: false),
        ]
        orgGroupsByJam["site-sci-band"] = [OrgGroupInfo(conversationId: "grp:site-science", name: "Lab ideas", open: true, joined: false, mine: false)]
        publicProfiles["adaeze"] = PublicProfile(userId: "adaeze", displayName: "Adaeze Nwosu", username: "adaeze.nwosu", school: nil, aboutEmoji: nil, aboutText: nil, since: nil, hasJam: false)
        discoverItems = []
        switch screen {
        case "site-jam-band": jamPath.append(OrgRoute(page: science, isMe: false))
        default: break
        }
    }
}
#endif
