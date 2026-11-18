#if DEBUG
import Foundation
import UIKit

/// Demo mode (the website's jam phone, LIME-286r2, 347, 349): Maya follows invented teachers of every age, two real board members (as the authors of their own real work only) and a band, with covers, series, two podcasts and a members-only post.
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

        // Ms Tran: three articles of a series.
        let tran = jam("site-tran-jam", writer: "tran", "Fractions that stick", "Short lessons for grades 3 to 5", ["Maths", "Grade 4"])
        demoJamPages["tran"] = tran
        publicProfiles["tran"] = PublicProfile(userId: "tran", displayName: "Ms Tran", username: "ms.tran", school: nil, aboutEmoji: nil, aboutText: nil, since: nil, hasJam: false)
        add("site-tran-1", "site-tran-jam", "tran", "article", "Fold, cut, compare", "Part 1: halves and quarters", "We started with a strip of paper. **Fold it in half**, then in half again, and ask: what do you notice?\n\nBy the end of the lesson every pair could say why two quarters make a half.", ago: 3_000, cover: "fold", series: fractions(1))
        add("site-tran-2", "site-tran-jam", "tran", "article", "Fraction walls", "Part 2: bricks that match", "Build a wall of bricks, one row for each fraction, and slide them side by side.\n\nThe question that does the teaching: *which rows line up?*", ago: 320, cover: "walls", series: fractions(2))
        add("site-tran-3", "site-tran-jam", "tran", "article", "Comparing with benchmarks", "Part 3: more or less than a half?", "Is it more or less than a half? Start there, then ask how you know.", ago: 5_000, series: fractions(3))
        let seriesCover = photo("walls")
        seriesMetas["site-series-fractions"] = SeriesMeta(seriesId: "site-series-fractions", title: "Fractions that stick", description: "Paper strips, brick walls and one question: which rows line up? Written for grades 3 to 5, and good to read aloud.", cover: seriesCover)
        seriesCovers["site-series-fractions"] = seriesCover

        // Luis Ortega: a three-part series, "Local Government Lab".
        func lab(_ part: UInt32) -> SeriesInfo { SeriesInfo(id: "site-series-lab", title: "Local Government Lab", part: part, of: 3) }
        _ = jam("site-luis-jam", writer: "luis", "Local Government Lab", "Civics you can try in town", ["Civics", "Grade 11"])
        publicProfiles["luis"] = PublicProfile(userId: "luis", displayName: "Luis Ortega", username: "luis.ortega", school: nil, aboutEmoji: nil, aboutText: nil, since: nil, hasJam: false)
        add("site-luis-1", "site-luis-jam", "luis", "article", "Who runs your town?", "Part 1: find the offices", "Start with a map and a phone. Ask each pair to find **three offices** in their town and what each one decides.\n\nThe question that does the teaching: *who could fix this pothole?*", ago: 1_400, cover: "civics", series: lab(1))
        add("site-luis-2", "site-luis-jam", "luis", "article", "Reading a city budget", "Part 2: where the money goes", "Give every group one page of the budget and one colour pen. **Circle what surprises you.**\n\nThen compare: which line would you cut, and who would feel it?", ago: 200, cover: "civics", series: lab(2))
        add("site-luis-3", "site-luis-jam", "luis", "article", "Going to a council meeting", "Part 3: speak for two minutes", "Two minutes at the microphone is a skill. Practise it in class first.", ago: 6_000, series: lab(3))
        let labCover = photo("civics")
        seriesMetas["site-series-lab"] = SeriesMeta(seriesId: "site-series-lab", title: "Local Government Lab", description: "Three lessons that send students out of the classroom and into their town hall. Written for high-school civics.", cover: labCover)
        seriesCovers["site-series-lab"] = labCover

        // Mrs Lindgren, Walt Brennan, Kofi Mensah.
        _ = jam("site-lindgren-jam", writer: "lindgren", "Practice, not homework", "Ten minutes a child chooses", ["Practice"])
        publicProfiles["lindgren"] = PublicProfile(userId: "lindgren", displayName: "Mrs Lindgren", username: "mrs.lindgren", school: nil, aboutEmoji: nil, aboutText: nil, since: nil, hasJam: false)
        add("site-lindgren-1", "site-lindgren-jam", "lindgren", "quick", "", "", "Last year. I’m keeping a list of what I’d tell my first-year self. Number one: the pencils can wait, the child can’t.", ago: 110)
        add("site-lindgren-2", "site-lindgren-jam", "lindgren", "article", "Why we stopped giving homework", "What we do instead", "We swapped it for ten minutes of practice a child chooses.\n\nThe rule that helped most: **everyone picks their own**.", ago: 700, cover: "circles")
        _ = jam("site-kofi-jam", writer: "kofi", "Read-aloud night", "What families asked for", ["Literacy"])
        add("site-kofi-pod", "site-kofi-jam", "kofi", "record", "The ten books that never stay on the shelf", "What families asked for at read-aloud night", "Four minutes on the books that went home with the most families.", ago: 900, cover: "readaloud", audioMs: 240_000)
        // Walt Brennan: a retired shop teacher who coaches the library's robotics team: a series and a podcast.
        func build(_ part: UInt32) -> SeriesInfo { SeriesInfo(id: "site-series-build", title: "Build it twice", part: part, of: 3) }
        _ = jam("site-walt-jam", writer: "walt", "Build it twice", "Cardboard first, then metal", ["Robotics", "Making"])
        publicProfiles["walt"] = PublicProfile(userId: "walt", displayName: "Walt Brennan", username: "walt.brennan", school: nil, aboutEmoji: nil, aboutText: nil, since: nil, hasJam: false)
        add("site-walt-1", "site-walt-jam", "walt", "article", "Cardboard first", "Part 1: before any metal", "Before any metal, a robot made of cardboard and tape. It’s ugly. It’s also where every good idea shows up.\n\nThe rule: **nothing gets built twice until it has been built once in cardboard.**", ago: 150, cover: "cardboard", series: build(1))
        add("site-walt-2", "site-walt-jam", "walt", "article", "The robot that walked into a wall", "Part 2: what the first test showed", "It drove straight into the wall, three times. Then someone asked what the sensor could actually see.", ago: 4_000, series: build(2))
        add("site-walt-3", "site-walt-jam", "walt", "article", "Judging day", "Part 3: explain it in two minutes", "Judges ask one question: why did you choose that? Practise the answer out loud.", ago: 7_000, series: build(3))
        let buildCover = photo("cardboard")
        seriesMetas["site-series-build"] = SeriesMeta(seriesId: "site-series-build", title: "Build it twice", description: "Three short lessons from a robotics team that builds everything in cardboard first. Written for coaches and makers of any age.", cover: buildCover)
        seriesCovers["site-series-build"] = buildCover
        add("site-walt-pod", "site-walt-jam", "walt", "record", "The robot that lost to a pool noodle", "What our worst regional taught the team", "Twenty-one minutes on the robot that lost to a pool noodle, and what we changed on Monday.", ago: 300, cover: "workshop", audioMs: 1_260_000)

        // The band: Science Corner, written by Dr Nwosu, with a cover photo, a picture and members.
        let science = jam("site-sci-band", writer: "adaeze", "Science Corner", "Experiments and ideas from teachers who love science", ["Science"], band: true)
        add("site-sci-1", "site-sci-band", "adaeze", "article", "Moon phases with a lamp", "A twenty-minute model", "A lamp, a ball and a dark room: ten minutes to **see why the moon changes**.\n\nLet every pair hold the ball once. The groan when the lamp goes off is the whole lesson.", ago: 20, cover: "science", figure: "fold", displayAs: "jam")
        add("site-sci-2", "site-sci-band", "adaeze", "article", "The lab we almost didn’t do", "Lab sheet and what went wrong, for members", "Members only: the full term plan, the lab sheets, and the one experiment that flooded the bench. Here is how we fixed it before Thursday.", ago: 240, cover: "members", members: true, displayAs: "jam")
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
            OrgMemberInfo(userId: "tran", name: "Ms Tran", tone: tone("tran"), role: "member", isMe: false, canManage: false),
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
