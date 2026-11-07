#if DEBUG
import Foundation
import UIKit

/// Demo mode (the website's jam phone, LIME-286r2): Maya follows three teachers and a band, with covers, a series, two podcasts and a members-only post.
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

        // Sam: a three-part series and a podcast.
        let sam = jam("site-sam-jam", writer: "sam", "Fractions that stick", "Short lessons for grades 3 to 5", ["Maths", "Grade 4"])
        demoJamPages["sam"] = sam
        add("site-sam-1", "site-sam-jam", "sam", "article", "Fold, cut, compare", "Part 1: halves and quarters", "We started with a strip of paper. **Fold it in half**, then in half again, and ask: what do you notice?\n\nBy the end of the lesson every pair could say why two quarters make a half.", ago: 3_000, cover: "fold", series: fractions(1))
        add("site-sam-2", "site-sam-jam", "sam", "article", "Fraction walls", "Part 2: bricks that match", "Build a wall of bricks, one row for each fraction, and slide them side by side.\n\nThe question that does the teaching: *which rows line up?*", ago: 200, cover: "walls", series: fractions(2))
        add("site-sam-3", "site-sam-jam", "sam", "article", "Comparing with benchmarks", "Part 3: more or less than a half?", "Is it more or less than a half? Start there, then ask how you know.", ago: 5_000, series: fractions(3))
        add("site-sam-pod", "site-sam-jam", "sam", "record", "Sunday planning, with Sam", "Week 4, in 18 minutes", "How we plan a week of reading circles.", ago: 400, cover: "planning", audioMs: 1_080_000)
        let seriesCover = photo("walls")
        seriesMetas["site-series-fractions"] = SeriesMeta(seriesId: "site-series-fractions", title: "Fractions that stick", description: "Short lessons on fractions, one idea each. Fold paper, build a wall of bricks, and see why one half is bigger than one third. Written for grades 3 to 5, and good to read aloud.", cover: seriesCover)
        seriesCovers["site-series-fractions"] = seriesCover

        // Priya and Lee.
        _ = jam("site-priya-jam", writer: "priya.nair", "Practice, not homework", "Ten minutes a child chooses", ["Practice"])
        add("site-priya-1", "site-priya-jam", "priya.nair", "quick", "", "", "An exit ticket that takes a minute: ask one question at the door, *which pieces are equal?*", ago: 60)
        add("site-priya-2", "site-priya-jam", "priya.nair", "article", "Why we stopped giving homework", "What we do instead", "We swapped it for ten minutes of practice a child chooses.\n\nThe rule that helped most: **everyone picks their own**.", ago: 700, cover: "circles")
        _ = jam("site-lee-jam", writer: "lee", "Reading circles", "What worked in my room", ["Reading", "Grade 3"])
        add("site-lee-pod", "site-lee-jam", "lee", "record", "Songs for the circle", "Korean children's songs", "Three songs we sing before a book.", ago: 900, cover: "songs", audioMs: 43_000)

        // The band: Science Corner, written by Mei, with a cover photo, a picture and members.
        let science = jam("site-sci-band", writer: "mei", "Science Corner", "Experiments and ideas from teachers who love science", ["Science"], band: true)
        add("site-sci-1", "site-sci-band", "mei", "article", "Moon phases with a lamp", "A twenty-minute model", "A lamp, a ball and a dark room: ten minutes to **see why the moon changes**.\n\nLet every pair hold the ball once.", ago: 20, cover: "science", figure: "fold", displayAs: "jam")
        add("site-sci-2", "site-sci-band", "mei", "article", "Our term plan", "Lab sheets, for members", "The full term plan, with the lab sheets.", ago: 240, cover: "members", members: true, displayAs: "jam")
        add("site-sci-3", "site-sci-band", "mei", "quick", "", "", "Thursday lab: bring the magnets.", ago: 500, displayAs: "jam")
        AvatarCache.shared.set(photo("band"), for: Self.jamCoverKey("site-sci-band"))
        AvatarCache.shared.set(photo("bandpic"), for: Self.jamPictureKey("site-sci-band"))
        orgs = [OrgInfo(jamId: "site-sci-band", conversationId: "grp:site-sci", writerId: "mei", name: "Science Corner", myRole: "member", memberCount: 5)]
        let tone = { (id: String) in UInt32(AvatarTone.tone(for: id)) }
        orgMembersByJam["site-sci-band"] = [
            OrgMemberInfo(userId: "mei", name: "Mei Lin", tone: tone("mei"), role: "owner", isMe: false, canManage: false),
            OrgMemberInfo(userId: "lee", name: "Lee Wong", tone: tone("lee"), role: "writer", isMe: false, canManage: false),
            OrgMemberInfo(userId: meProvider().id, name: "Maya Ortiz", tone: 6, role: "member", isMe: true, canManage: false),
            OrgMemberInfo(userId: "priya.nair", name: "Priya Nair", tone: tone("priya.nair"), role: "member", isMe: false, canManage: false),
            OrgMemberInfo(userId: "sam", name: "Sam Park", tone: tone("sam"), role: "member", isMe: false, canManage: false),
        ]
        orgGroupsByJam["site-sci-band"] = [OrgGroupInfo(conversationId: "grp:site-science", name: "Lab ideas", open: true, joined: false, mine: false)]
        publicProfiles["mei"] = PublicProfile(userId: "mei", displayName: "Mei Lin", username: "mei.lin", school: nil, aboutEmoji: nil, aboutText: nil, since: nil, hasJam: false)
        publicProfiles["priya.nair"] = PublicProfile(userId: "priya.nair", displayName: "Priya Nair", username: "priya.nair", school: nil, aboutEmoji: nil, aboutText: nil, since: nil, hasJam: false)
        discoverItems = []
        switch screen {
        case "site-jam-band": jamPath.append(OrgRoute(page: science, isMe: false))
        default: break
        }
    }
}
#endif
